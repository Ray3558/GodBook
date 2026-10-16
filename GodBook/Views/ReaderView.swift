import SwiftUI

struct ReaderView: View {
    let route: ReaderRoute
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var chapterIndex: Int
    @State private var pages: [ReaderPage] = []
    @State private var current: Int
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showChrome = true
    @State private var pendingScroll: Int?

    init(route: ReaderRoute) {
        self.route = route
        _chapterIndex = State(initialValue: route.chapterIndex)
        _current = State(initialValue: route.startPage)
        _pendingScroll = State(initialValue: route.startPage > 0 ? route.startPage : nil)
    }

    private var detail: ComicDetail { route.detail }
    private var chapter: Chapter { detail.chapters[chapterIndex] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(.white)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage).foregroundStyle(.white).multilineTextAlignment(.center)
                    GlassButton(title: "重試", systemImage: "arrow.clockwise") { Task { await load() } }
                        .frame(maxWidth: 200)
                }
                .padding()
            } else {
                content
                    .ignoresSafeArea(edges: .vertical)
                    .onTapGesture { withAnimation(.snappy) { showChrome.toggle() } }
            }
        }
        .overlay(alignment: .top) { if showChrome { topBar } }
        .overlay(alignment: .bottom) { if showChrome && !pages.isEmpty { bottomBar } }
        .statusBarHidden(!showChrome)
        .preferredColorScheme(.dark)
        .task(id: chapterIndex) { await load() }
        .onChange(of: current) { _, newValue in
            library.record(detail.summary, chapter: chapter, pageIndex: newValue)
        }
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        switch settings.readerMode {
        case .vertical:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pages) { page in
                            RemoteImageView(spec: page.image)
                                .id(page.index)
                                .onAppear { current = page.index }
                        }
                    }
                }
                .onAppear { restoreScroll(proxy) }
            }
        case .horizontal, .horizontalRTL:
            let ordered: [ReaderPage] = settings.readerMode == .horizontalRTL ? Array(pages.reversed()) : pages
            TabView(selection: $current) {
                ForEach(ordered) { page in
                    RemoteImageView(spec: page.image)
                        .tag(page.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func restoreScroll(_ proxy: ScrollViewProxy) {
        guard let wanted = pendingScroll else { return }
        pendingScroll = nil
        let target = min(max(wanted, 0), max(pages.count - 1, 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // MARK: 工具列

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glass(in: Circle(), interactive: true)

            VStack(alignment: .leading, spacing: 0) {
                Text(detail.summary.title).font(.footnote.weight(.semibold)).lineLimit(1)
                if detail.chapters.count > 1 {
                    Text(chapter.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCapsule()

            Spacer()

            Menu {
                Picker("閱讀方式", selection: $settings.readerMode) {
                    ForEach(ReaderMode.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "rectangle.on.rectangle.angled").font(.headline).frame(width: 44, height: 44)
            }
            .glass(in: Circle(), interactive: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if detail.chapters.count > 1 {
                Button { step(-1) } label: { Image(systemName: "chevron.left.2").frame(width: 40, height: 40) }
                    .disabled(chapterIndex == 0)
                    .buttonStyle(.plain)
                    .glass(in: Circle(), interactive: true)
            }

            VStack(spacing: 4) {
                Text("\(min(current + 1, pages.count)) / \(pages.count)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                if pages.count > 1 && settings.readerMode != .vertical {
                    Slider(value: Binding(get: { Double(current) },
                                          set: { current = Int($0.rounded()) }),
                           in: 0...Double(pages.count - 1), step: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 24)

            if detail.chapters.count > 1 {
                Button { step(1) } label: { Image(systemName: "chevron.right.2").frame(width: 40, height: 40) }
                    .disabled(chapterIndex >= detail.chapters.count - 1)
                    .buttonStyle(.plain)
                    .glass(in: Circle(), interactive: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    // MARK: 載入

    private func step(_ delta: Int) {
        let next = chapterIndex + delta
        guard detail.chapters.indices.contains(next) else { return }
        current = 0
        pendingScroll = nil
        chapterIndex = next
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await SourceRegistry.source(detail.summary.source).pages(of: detail, chapter: chapter)
            pages = loaded
            if current >= loaded.count { current = 0 }
            if pendingScroll != nil { pendingScroll = min(current, max(loaded.count - 1, 0)) }
            isLoading = false
            library.record(detail.summary, chapter: chapter, pageIndex: current)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
