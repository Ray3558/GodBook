import SwiftUI

struct ComicCard: View {
    let comic: ComicSummary
    var showSourceBadge = false

    var body: some View {
        RemoteImageView(spec: comic.coverURL.map { ImageSpec(url: $0, source: comic.source) },
                        fill: true, placeholderAspect: 0.72)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.72, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comic.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle = comic.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassCard(cornerRadius: 16)
                .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if showSourceBadge {
                    Text(comic.source.title)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassCapsule()
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ComicGrid: View {
    let items: [ComicSummary]
    var showSourceBadge = false
    var onAppearItem: ((ComicSummary) -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { comic in
                NavigationLink(value: comic) {
                    ComicCard(comic: comic, showSourceBadge: showSourceBadge)
                }
                .buttonStyle(.plain)
                .onAppear { onAppearItem?(comic) }
            }
        }
        .padding(.horizontal, 12)
    }
}

/// 帶分頁狀態的清單內容（載入中 / 錯誤 / 空結果）。
struct PagedComicList: View {
    @ObservedObject var model: PagedListModel

    var body: some View {
        VStack(spacing: 16) {
            ComicGrid(items: model.items) { model.loadMoreIfNeeded(current: $0) }

            if model.isLoading {
                ProgressView().padding()
            } else if let message = model.errorMessage {
                VStack(spacing: 10) {
                    Text(message).font(.footnote).multilineTextAlignment(.center)
                    GlassButton(title: "重試", systemImage: "arrow.clockwise") { model.retry() }
                        .frame(maxWidth: 200)
                }
                .padding()
                .glassCard()
                .padding(.horizontal)
            } else if model.didLoadOnce && model.items.isEmpty {
                Text("沒有結果").foregroundStyle(.secondary).padding()
            }
        }
        .padding(.vertical, 8)
    }
}

struct SearchResultsView: View {
    let route: SearchRoute
    @StateObject private var model = PagedListModel()
    @State private var sortId = ""

    var body: some View {
        let source = SourceRegistry.source(route.source)
        ScrollView {
            PagedComicList(model: model)
        }
        .themedScreen()
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(options: source.sortOptions, selection: sortId) { sortId = $0 }
            }
        }
        .task(id: sortId) {
            let sort = source.sortOptions.first { $0.id == sortId } ?? source.sortOptions[0]
            if sortId.isEmpty { sortId = sort.id; return }
            await model.start { try await source.browse(query: route.query, page: $0, sort: sort) }
        }
    }
}
