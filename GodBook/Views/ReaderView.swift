import SwiftUI

struct ReaderView: View {
    let route: ReaderRoute
    /// 由呈現端提供的關閉動作（比 `@Environment(\.dismiss)` 在 fullScreenCover 中更可靠）
    let onClose: () -> Void
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
            circleButton("xmark") { close() }

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
                circleLabel("rectangle.on.rectangle.angled")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if detail.chapters.count > 1 {
                circleButton("chevron.left.2") { step(-1) }
                    .disabled(chapterIndex == 0)
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
                circleButton("chevron.right.2") { step(1) }
                    .disabled(chapterIndex >= detail.chapters.count - 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    /// 圓形玻璃按鈕：整個圓都是點擊範圍
    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(systemName) }
            .buttonStyle(.plain)
    }

    private func circleLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.headline)
            .frame(width: 48, height: 48)
            .glass(in: Circle(), interactive: true)
            .contentShape(Circle())
    }

    private func close() {
        onClose()
        dismiss()
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
            let loaded: [ReaderPage]
            if let local = DownloadStorage.localPages(summary: detail.summary, chapterId: chapter.id) {
                loaded = local // 已下載：離線閱讀
            } else {
                loaded = try await SourceRegistry.source(detail.summary.source).pages(of: detail, chapter: chapter)
            }
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
