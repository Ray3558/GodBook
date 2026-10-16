import SwiftUI

struct LibraryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "收藏", history = "歷史", downloads = "下載", images = "圖片", cloud = "雲端"
        var id: String { rawValue }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var tab = Tab.favorites

    var body: some View {
        ScrollView {
            switch tab {
            case .favorites:
                if library.favorites.isEmpty {
                    emptyState("還沒有收藏", systemImage: "heart")
                } else {
                    ComicGrid(items: library.favorites, showSourceBadge: true).padding(.vertical, 8)
                }
            case .history:
                if library.history.isEmpty {
                    emptyState("沒有閱讀紀錄", systemImage: "clock")
                } else {
                    historyList
                }
            case .downloads:
                DownloadsView()
            case .images:
                ImageFavoritesView()
            case .cloud:
                CloudFavoritesView()
            }
        }
        .themedScreen()
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("書庫", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)
            .glassCard(cornerRadius: 18)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .navigationTitle("書庫")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tab == .history && !library.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清除", role: .destructive) { library.clearHistory() }
                }
            }
        }
    }

    private var historyList: some View {
        LazyVStack(spacing: 10) {
            ForEach(library.history) { entry in
                NavigationLink(value: entry.summary) {
                    HStack(spacing: 12) {
                        RemoteImageView(spec: entry.summary.coverURL.map { ImageSpec(url: $0, source: entry.summary.source) },
                                        fill: true)
                            .frame(width: 56, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.summary.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("\(entry.summary.source.title) · \(entry.chapterTitle) · 第 \(entry.pageIndex + 1) 頁")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .glassCard(cornerRadius: 20, interactive: true)
                    .contextMenu {
                        Button("移除紀錄", role: .destructive) { library.removeHistory(entry) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle)
            Text(text)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// 已登入來源的雲端收藏（禁漫 + 支援收藏的 venera 漫畫源）
private struct CloudFavoritesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var venera: VeneraStore
    @StateObject private var model = PagedListModel()
    @State private var selected: SourceKind?
    @State private var refresh = 0

    private var kinds: [SourceKind] {
        var list: [SourceKind] = []
        if settings.jmLoggedIn { list.append(.jmcomic) }
        list += venera.sources.filter { $0.favorites != nil && VeneraStorage.shared.isLogged($0.key) }.map(\.kind)
        return list.filter { settings.isEnabled($0) }
    }

    private var current: SourceKind? {
        if let selected, kinds.contains(selected) { return selected }
        return kinds.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if kinds.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle)
                    Text("請先到「設定」登入禁漫或 venera 漫畫源的帳號")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                if kinds.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(kinds) { kind in
                                Button { selected = kind } label: {
                                    Text(kind.title)
                                        .font(.subheadline.weight(kind == current ? .bold : .regular))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .glassCapsule(interactive: true)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                    }
                }
                PagedComicList(model: model)
            }
        }
        .onAppear { refresh += 1 }
        .task(id: "\(current?.rawValue ?? "")|\(refresh)") {
            guard let kind = current else { return }
            let loader: (Int) async throws -> ComicPageResult
            if kind == .jmcomic {
                let source = JMComicSource()
                loader = { try await source.favorites(page: $0) }
            } else {
                let source = VeneraSource(kind: kind)
                loader = { try await source.favorites(page: $0) }
            }
            await model.start(loader)
        }
    }
}
