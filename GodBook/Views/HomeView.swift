import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
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

    private struct LoadKey: Hashable {
        var source: SourceKind
        var query: String
        var sort: String
    }

    var body: some View {
        ScrollView {
            PagedComicList(model: model)
        }
        .themedScreen()
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("來源", selection: $settings.lastSource) {
                ForEach(SourceKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)
            .glassCard(cornerRadius: 18)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .navigationTitle("GodBook")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: settings.lastSource == .nhentai ? "搜尋標籤、關鍵字或 ID" : "搜尋關鍵字或車號")
        .onSubmit(of: .search) { submitSearch() }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty && !query.isEmpty { query = "" }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序", selection: Binding(
                        get: { currentSort.id },
                        set: { sortIds[settings.lastSource] = $0 })) {
                        ForEach(source.sortOptions) { Text($0.title).tag($0.id) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
        .navigationDestination(item: $directOpen) { DetailView(summary: $0) }
        .task(id: LoadKey(source: settings.lastSource, query: query, sort: currentSort.id)) {
            let source = self.source
            let sort = currentSort
            let query = self.query
            await model.start { try await source.browse(query: query, page: $0, sort: sort) }
        }
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
