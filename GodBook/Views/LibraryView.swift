import SwiftUI

struct LibraryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "收藏", history = "歷史", downloads = "下載", cloud = "雲端"
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
            case .cloud:
                if settings.jmLoggedIn {
                    JMCloudFavorites()
                } else {
                    emptyState("請先到「設定」登入禁漫帳號", systemImage: "person.crop.circle.badge.questionmark")
                }
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

private struct JMCloudFavorites: View {
    @StateObject private var model = PagedListModel()

    var body: some View {
        PagedComicList(model: model)
            .task {
                await model.start { try await JMComicSource().favorites(page: $0) }
            }
    }
}
