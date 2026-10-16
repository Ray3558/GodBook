import SwiftUI

struct ReaderRoute: Identifiable {
    let id = UUID()
    let detail: ComicDetail
    let chapterIndex: Int
    let startPage: Int
}

struct DetailView: View {
    let summary: ComicSummary
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var settings: AppSettings
    @State private var detail: ComicDetail?
    @State private var errorMessage: String?
    @State private var reader: ReaderRoute?

    private var shown: ComicSummary { detail?.summary ?? summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let detail {
                    actions(detail)
                    if let text = detail.description, !text.isEmpty {
                        Text(text)
                            .font(.callout)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                    if !detail.tags.isEmpty { tagSection(detail) }
                    if detail.chapters.count > 1 { chapterSection(detail) }
                    if !detail.related.isEmpty { relatedSection(detail) }
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Text(errorMessage).multilineTextAlignment(.center)
                        GlassButton(title: "重試", systemImage: "arrow.clockwise") { Task { await load() } }
                    }
                    .padding()
                    .glassCard()
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(16)
        }
        .themedScreen()
        .navigationTitle(shown.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleFavorite(shown)
                } label: {
                    Image(systemName: library.isFavorite(shown) ? "heart.fill" : "heart")
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $reader) { route in
            ReaderView(route: route)
                .environmentObject(library)
                .environmentObject(theme)
                .environmentObject(settings)
        }
    }

    // MARK: 區塊

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RemoteImageView(spec: shown.coverURL.map { ImageSpec(url: $0, source: shown.source) }, fill: true)
                .frame(width: 118, height: 164)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(shown.title).font(.headline).textSelection(.enabled)
                if let detail {
                    if !detail.authors.isEmpty {
                        Text(detail.authors.joined(separator: "、")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !detail.stats.isEmpty {
                        Text(detail.stats.joined(separator: "  ")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let count = detail.pageCount {
                        Text("\(count) 頁").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(cornerRadius: 26)
    }

    private func actions(_ detail: ComicDetail) -> some View {
        let progress = library.progress(for: shown)
        let resumeIndex = progress.flatMap { entry in detail.chapters.firstIndex { $0.id == entry.chapterId } }
        return HStack(spacing: 12) {
            if let progress, let resumeIndex {
                GlassButton(title: "繼續 \(progress.pageIndex + 1) 頁", systemImage: "play.fill", prominent: true) {
                    reader = ReaderRoute(detail: detail, chapterIndex: resumeIndex, startPage: progress.pageIndex)
                }
                GlassButton(title: "從頭", systemImage: "backward.end.fill") {
                    reader = ReaderRoute(detail: detail, chapterIndex: 0, startPage: 0)
                }
            } else {
                GlassButton(title: "開始閱讀", systemImage: "book.fill", prominent: true) {
                    reader = ReaderRoute(detail: detail, chapterIndex: 0, startPage: 0)
                }
            }
        }
    }

    private func tagSection(_ detail: ComicDetail) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(detail.tags) { tag in
                if let query = tag.query {
                    NavigationLink(value: SearchRoute(source: shown.source, query: query, title: tag.name)) {
                        tagLabel(tag)
                    }
                    .buttonStyle(.plain)
                } else {
                    tagLabel(tag)
                }
            }
        }
    }

    private func tagLabel(_ tag: ComicTag) -> some View {
        HStack(spacing: 4) {
            if let group = tag.group, group != "tag" {
                Text(group).foregroundStyle(.secondary)
            }
            Text(tag.name)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule(interactive: true)
    }

    private func chapterSection(_ detail: ComicDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("章節（\(detail.chapters.count)）").font(.headline)
            LazyVStack(spacing: 8) {
                ForEach(Array(detail.chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        reader = ReaderRoute(detail: detail, chapterIndex: index, startPage: 0)
                    } label: {
                        HStack {
                            Text(chapter.title).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCard(cornerRadius: 16, interactive: true)
                }
            }
        }
    }

    private func relatedSection(_ detail: ComicDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("相關作品").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(detail.related) { item in
                        NavigationLink(value: item) {
                            ComicCard(comic: item).frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            detail = try await SourceRegistry.source(summary.source).detail(of: summary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
