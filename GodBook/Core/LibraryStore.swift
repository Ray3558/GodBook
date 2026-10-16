import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var summary: ComicSummary
    var chapterId: String
    var chapterTitle: String
    var pageIndex: Int
    var date: Date

    var id: String { summary.id }
}

/// 本機收藏與閱讀紀錄（JSON 存放於 Application Support）。
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [ComicSummary]
    @Published private(set) var history: [HistoryEntry]

    private static let favoritesFile = "favorites.json"
    private static let historyFile = "history.json"

    init() {
        favorites = Storage.load([ComicSummary].self, from: Self.favoritesFile) ?? []
        history = Storage.load([HistoryEntry].self, from: Self.historyFile) ?? []
    }

    func isFavorite(_ summary: ComicSummary) -> Bool {
        favorites.contains { $0.id == summary.id }
    }

    func toggleFavorite(_ summary: ComicSummary) {
        if let index = favorites.firstIndex(where: { $0.id == summary.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(summary, at: 0)
        }
        Storage.save(favorites, to: Self.favoritesFile)
    }

    func progress(for summary: ComicSummary) -> HistoryEntry? {
        history.first { $0.id == summary.id }
    }

    func record(_ summary: ComicSummary, chapter: Chapter, pageIndex: Int) {
        history.removeAll { $0.id == summary.id }
        history.insert(HistoryEntry(summary: summary, chapterId: chapter.id, chapterTitle: chapter.title,
                                    pageIndex: pageIndex, date: Date()), at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        Storage.save(history, to: Self.historyFile)
    }

    func removeHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        Storage.save(history, to: Self.historyFile)
    }

    func clearHistory() {
        history = []
        Storage.save(history, to: Self.historyFile)
    }
}
