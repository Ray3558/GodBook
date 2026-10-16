import SwiftUI

struct ReaderView: View {
    let route: ReaderRoute
    /// 由呈現端提供的關閉動作（比 `@Environment(\.dismiss)` 在 fullScreenCover 中更可靠）
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefsStore: ReaderPrefsStore
    @EnvironmentObject private var imageFavorites: ImageFavoritesStore

    @State private var chapterIndex: Int
    @State private var pages: [ReaderPage] = []
    @State private var current: Int
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showChrome = true
    @State private var notice: String?
    @State private var showSettings = false
    @State private var showChapters = false
    @State private var shareImage: ShareImageItem?
    @State private var volume = VolumeKeyObserver()
    @State private var autoTurnTick = 0
    @State private var showChapterComments = false

    private let autoTurnTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(route: ReaderRoute, onClose: @escaping () -> Void = {}) {
        self.route = route
        self.onClose = onClose
        _chapterIndex = State(initialValue: route.chapterIndex)
        _current = State(initialValue: route.startPage)
    }

    private var detail: ComicDetail { route.detail }
    private var chapter: Chapter { detail.chapters[chapterIndex] }
    private var comicKey: String { detail.summary.id }
    private var prefs: ReaderPrefs { prefsStore.prefs(for: comicKey) }

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
                    .id("\(chapterIndex)-\(prefs.mode.rawValue)")
                    .ignoresSafeArea(edges: .vertical)
            }
        }
        .overlay(alignment: .top) { if showChrome { topBar } }
        .overlay(alignment: .bottom) { if showChrome && !pages.isEmpty { bottomBar } else if !pages.isEmpty { infoBar } }
        .overlay(alignment: .center) { noticeView }
        .statusBarHidden(!showChrome)
        .preferredColorScheme(.dark)
        .task(id: chapterIndex) { await load() }
        .onChange(of: current) { _, newValue in
            library.record(detail.summary, chapter: chapter, pageIndex: newValue)
            prefetch()
            autoTurnTick = 0
        }
        .onChange(of: prefs.volumeKeys) { _, _ in configureVolume() }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
            configureVolume()
        }
        .onChange(of: prefs.keepScreenOn) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
        .onDisappear {
            volume.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(autoTurnTimer) { _ in
            guard prefs.autoTurnSeconds > 0, !isLoading, !pages.isEmpty else { return }
            autoTurnTick += 1
            if autoTurnTick >= prefs.autoTurnSeconds {
                autoTurnTick = 0
                turn(1)
            }
        }
        .sheet(isPresented: $showSettings) { ReaderSettingsSheet(comicKey: comicKey).environmentObject(prefsStore) }
        .sheet(isPresented: $showChapters) {
            ReaderChapterSheet(chapters: detail.chapters, currentIndex: chapterIndex) { selectChapter($0) }
        }
        .sheet(item: $shareImage) { item in ShareItemsSheet(items: [item.image]) }
        .sheet(isPresented: $showChapterComments) {
            CommentsSheet(kind: detail.summary.source,
                          context: CommentContext(summary: detail.summary, subId: detail.subId, chapterId: chapter.id))
        }
    }

    // MARK: 內容

    @ViewBuilder
    private var content: some View {
        let mode = prefs.mode
        if mode.isPaged {
            PagedReader(pages: pages, current: $current, vertical: mode == .pagedVertical, rtl: mode.isRTL,
                        prefs: prefs, onTap: handleTap, onQuickCollect: { collect($0) })
        } else {
            ContinuousReader(pages: pages, current: $current, horizontal: mode != .vertical, rtl: mode.isRTL,
                             prefs: prefs, onTap: handleTap, onQuickCollect: { collect($0) })
        }
    }

    // MARK: 翻頁

    private func handleTap(_ point: CGPoint) {
        let mode = prefs.mode
        guard prefs.tapToTurn, mode != .vertical else { toggleChrome(); return }
        let coordinate = mode == .pagedVertical ? point.y : point.x
        let zone = coordinate < 1.0 / 3 ? -1 : (coordinate > 2.0 / 3 ? 1 : 0)
        if zone == 0 { toggleChrome(); return }
        var delta = zone                      // 左 / 上 = 上一頁，右 / 下 = 下一頁
        if mode.isRTL { delta = -delta }      // 右到左：左邊才是下一頁
        if prefs.reverseTap { delta = -delta }
        turn(delta)
    }

    private func toggleChrome() { withAnimation(.snappy) { showChrome.toggle() } }

    private func turn(_ delta: Int) {
        let target = current + delta
        if target < 0 {
            if chapterIndex > 0 { step(-1) } else { show("已經是第一頁") }
        } else if target >= pages.count {
            if chapterIndex < detail.chapters.count - 1 { step(1) } else { show("已經是最後一頁") }
        } else {
            current = target
        }
    }

    private func configureVolume() {
        if prefs.volumeKeys {
            volume.onPress = { up in turn(up ? -1 : 1) }
            volume.start()
        } else {
            volume.stop()
        }
    }

    private func prefetch() {
        guard prefs.preloadCount > 0, current + 1 < pages.count else { return }
        let upper = min(pages.count, current + 1 + prefs.preloadCount)
        for index in (current + 1)..<upper {
            let spec = pages[index].image
            Task.detached(priority: .utility) { _ = try? await ImageLoader.shared.image(for: spec) }
        }
    }

    // MARK: 工具列

    private var topBar: some View {
        HStack(spacing: 12) {
            circleButton("xmark") { close() }

            Button {
                if detail.chapters.count > 1 { showChapters = true }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.summary.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    if detail.chapters.count > 1 {
                        Text(chapter.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassCapsule(interactive: detail.chapters.count > 1)
            }
            .buttonStyle(.plain)

            Spacer()

            circleButton("slider.horizontal.3") { showSettings = true }

            Menu {
                Button { collect(current) } label: {
                    Label(isCollected(current) ? "取消收藏這張圖" : "收藏這張圖", systemImage: isCollected(current) ? "heart.slash" : "heart")
                }
                if SourceRegistry.source(detail.summary.source).capabilities.chapterComments {
                    Button { showChapterComments = true } label: { Label("章節評論", systemImage: "text.bubble") }
                }
                Button { Task { await saveToPhotos() } } label: { Label("儲存到相簿", systemImage: "square.and.arrow.down") }
                Button { Task { await share() } } label: { Label("分享這張圖", systemImage: "square.and.arrow.up") }
            } label: {
                circleLabel("ellipsis")
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
                if pages.count > 1 {
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

    /// 工具列隱藏時，角落的頁碼與時間 / 電量
    private var infoBar: some View {
        HStack {
            if prefs.showClockBattery { ReaderInfoBadge() }
            Spacer()
            if prefs.showPageNumber {
                Text("\(min(current + 1, pages.count)) / \(pages.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassCapsule()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCapsule()
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if notice == text { withAnimation { notice = nil } }
        }
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
        volume.stop()
        onClose()
        dismiss()
    }

    // MARK: 單張圖片動作

    private func isCollected(_ index: Int) -> Bool {
        imageFavorites.find(detail.summary, chapterId: chapter.id, pageIndex: index) != nil
    }

    private func image(at index: Int) async -> UIImage? {
        guard pages.indices.contains(index) else { return nil }
        return try? await ImageLoader.shared.image(for: pages[index].image)
    }

    private func collect(_ index: Int) {
        Task {
            guard let image = await image(at: index) else { show("圖片尚未載入完成"); return }
            let added = imageFavorites.toggle(summary: detail.summary, chapter: chapter, pageIndex: index, image: image)
            show(added ? "已收藏這張圖" : "已取消收藏")
        }
    }

    private func saveToPhotos() async {
        guard let image = await image(at: current) else { show("圖片尚未載入完成"); return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        show("已儲存到相簿")
    }

    private func share() async {
        guard let image = await image(at: current) else { show("圖片尚未載入完成"); return }
        shareImage = ShareImageItem(image: image)
    }

    // MARK: 章節與載入

    private func selectChapter(_ index: Int) {
        guard detail.chapters.indices.contains(index), index != chapterIndex else { return }
        current = 0
        chapterIndex = index
    }

    private func step(_ delta: Int) { selectChapter(chapterIndex + delta) }

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
            isLoading = false
            library.record(detail.summary, chapter: chapter, pageIndex: current)
            prefetch()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
