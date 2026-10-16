import SwiftUI
import UIKit

final class ZoomPageViewController: UIViewController {
    let index: Int
    private let spec: ImageSpec
    private var prefs: ReaderPrefs
    var onTap: ((CGPoint) -> Void)?
    var onQuickCollect: ((Int) -> Void)?
    private let scroll = ZoomScrollView()

    init(index: Int, spec: ImageSpec, prefs: ReaderPrefs) {
        self.index = index
        self.spec = spec
        self.prefs = prefs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = scroll
        apply(prefs)
        scroll.onSingleTap = { [weak self] point in self?.onTap?(point) }
        scroll.onQuickCollect = { [weak self] in
            guard let self else { return }
            self.onQuickCollect?(self.index)
        }
        scroll.load(spec)
    }

    func apply(_ newPrefs: ReaderPrefs) {
        prefs = newPrefs
        scroll.doubleTapZoom = newPrefs.doubleTapZoom
        scroll.longPressZoom = newPrefs.longPressZoom
        scroll.quickCollect = newPrefs.quickCollect
    }
}

/// 分頁閱讀器（左到右 / 右到左 / 上到下），以 UIPageViewController 實作，每頁可縮放。
struct PagedReader: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    @Binding var current: Int
    let vertical: Bool
    let rtl: Bool
    let prefs: ReaderPrefs
    let onTap: (CGPoint) -> Void
    let onQuickCollect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: vertical ? .vertical : .horizontal,
            options: [.interPageSpacing: 12])
        controller.view.backgroundColor = .black
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.show(current, animated: false, in: controller)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        controller.viewControllers?.forEach { ($0 as? ZoomPageViewController)?.apply(prefs) }
        context.coordinator.syncIfNeeded(controller)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReader
        private var displayed = -1

        init(_ parent: PagedReader) { self.parent = parent }

        private func makeController(for index: Int) -> ZoomPageViewController? {
            guard parent.pages.indices.contains(index) else { return nil }
            let controller = ZoomPageViewController(index: index, spec: parent.pages[index].image, prefs: parent.prefs)
            controller.onTap = { [weak self] point in self?.parent.onTap(point) }
            controller.onQuickCollect = { [weak self] page in self?.parent.onQuickCollect(page) }
            return controller
        }

        func show(_ index: Int, animated: Bool, in controller: UIPageViewController) {
            let target = min(max(index, 0), max(parent.pages.count - 1, 0))
            guard let page = makeController(for: target) else { return }
            let forward = displayed < 0 ? true : (parent.rtl ? target < displayed : target > displayed)
            controller.setViewControllers([page], direction: forward ? .forward : .reverse, animated: animated)
            displayed = target
        }

        func syncIfNeeded(_ controller: UIPageViewController) {
            guard displayed != parent.current else { return }
            show(parent.current, animated: parent.prefs.pageAnimation, in: controller)
        }

        // MARK: DataSource（RTL 時前後對調）

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? ZoomPageViewController else { return nil }
            return makeController(for: parent.rtl ? page.index + 1 : page.index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? ZoomPageViewController else { return nil }
            return makeController(for: parent.rtl ? page.index - 1 : page.index + 1)
        }

        // MARK: Delegate

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let page = pageViewController.viewControllers?.first as? ZoomPageViewController else { return }
            displayed = page.index
            DispatchQueue.main.async { self.parent.current = page.index }
        }
    }
}
