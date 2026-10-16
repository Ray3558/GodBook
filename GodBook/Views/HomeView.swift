import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var venera: VeneraStore
    @StateObject private var model = PagedListModel()
    @State private var searchText = ""
    @State private var query = ""
    @State private var sortIds: [SourceKind: String] = [:]
    @State private var directOpen: ComicSummary?

    private var source: ComicSource { SourceRegistry.source(settings.lastSource) }

    private var currentSort: SortOption {
        let options = source.sortOptions
        return options.first { $0.id == sortIds[settings.lastSource] } ?? options[0]
    }

    /// 只有「目前這個 venera 漫畫源」載入完成時才需要重新抓取；
    /// 其他漫畫源啟動時陸續載入不應觸發重新請求（否則 nhentai 會因請求過多回 429）。
    private var catalogState: Int {
        settings.lastSource.isVenera
            ? (VeneraRegistry.shared.info(settings.lastSource.veneraKey) == nil ? 0 : 1)
            : 0
    }

    private struct LoadKey: Hashable {
        var source: SourceKind
        var query: String
        var sort: String
        var catalog: Int
    }

    var body: some View {
        ScrollView {
            PagedComicList(model: model)
        }
        .themedScreen()
        .safeAreaInset(edge: .top, spacing: 0) {
            sourceChips
        }
        .navigationTitle("GodBook")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: settings.lastSource == .nhentai ? "搜尋標籤、關鍵字或 ID" : "搜尋關鍵字")
        .onSubmit(of: .search) { submitSearch() }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty && !query.isEmpty { query = "" }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(options: source.sortOptions, selection: currentSort.id) {
                    sortIds[settings.lastSource] = $0
                }
            }
        }
        .navigationDestination(item: $directOpen) { DetailView(summary: $0) }
        .task(id: LoadKey(source: settings.lastSource, query: query, sort: currentSort.id, catalog: catalogState)) {
            let source = self.source
            let sort = currentSort
            let query = self.query
            await model.start { try await source.browse(query: query, page: $0, sort: sort) }
        }
    }

    /// 來源切換列：內建兩個來源 + 已安裝的 venera 漫畫源
    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SourceKind.all) { kind in
                    let selected = kind == settings.lastSource
                    Button {
                        withAnimation(.snappy) { settings.lastSource = kind }
                    } label: {
                        Text(kind.title)
                            .font(.subheadline.weight(selected ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassCapsule(tint: selected ? nil : Color.clear, interactive: true)
                    .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .id(venera.sources.count) // 安裝 / 移除漫畫源後重新整理
    }

    private func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // nhentai 的純數字視為 gallery ID，直接開啟
        if settings.lastSource == .nhentai, !text.isEmpty, text.allSatisfy(\.isNumber) {
            directOpen = ComicSummary(source: .nhentai, sid: text, title: "#\(text)")
            return
        }
        query = text
    }
}
