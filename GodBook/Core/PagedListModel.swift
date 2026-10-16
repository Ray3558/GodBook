import Foundation

/// 無限捲動清單的狀態；以 generation 避免舊請求覆蓋新結果。
@MainActor
final class PagedListModel: ObservableObject {
    @Published private(set) var items: [ComicSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true
    @Published private(set) var didLoadOnce = false

    private var loader: ((Int) async throws -> ComicPageResult)?
    private var nextPage = 1
    private var generation = 0
    private var seen = Set<String>()
    private var knownTotal: Int?

    func start(_ loader: @escaping (Int) async throws -> ComicPageResult) {
        generation += 1
        self.loader = loader
        items = []
        seen = []
        nextPage = 1
        hasMore = true
        errorMessage = nil
        didLoadOnce = false
        knownTotal = nil
        isLoading = false
        loadMore()
    }

    func loadMoreIfNeeded(current: ComicSummary) {
        guard let index = items.firstIndex(where: { $0.id == current.id }) else { return }
        if index >= items.count - 6 { loadMore() }
    }

    func retry() { loadMore() }

    func loadMore() {
        guard !isLoading, hasMore, let loader else { return }
        isLoading = true
        errorMessage = nil
        let ticket = generation
        let page = nextPage
        Task {
            do {
                let result = try await loader(page)
                guard ticket == generation else { return }
                let fresh = result.items.filter { seen.insert($0.id).inserted }
                items.append(contentsOf: fresh)
                nextPage = page + 1
                if let total = result.total { knownTotal = total }
                var more = !result.items.isEmpty
                if let pages = result.totalPages, page >= pages { more = false }
                if let total = knownTotal, items.count >= total { more = false }
                if fresh.isEmpty && !result.items.isEmpty { more = false } // 伺服器重複回傳同一頁
                hasMore = more
                didLoadOnce = true
                isLoading = false
            } catch {
                guard ticket == generation else { return }
                errorMessage = error.localizedDescription
                didLoadOnce = true
                isLoading = false
            }
        }
    }
}
