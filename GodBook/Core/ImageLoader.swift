import SwiftUI
import UIKit

actor ImageLoader {
    static let shared = ImageLoader()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 256 << 20
        return cache
    }()
    private var inflight: [String: Task<UIImage, Error>] = [:]

    private func key(for spec: ImageSpec) -> String {
        var components = URLComponents(url: spec.url, resolvingAgainstBaseURL: false)
        components?.query = nil // 禁漫的 ?v=timestamp 每次不同，不應影響快取
        return "\(components?.string ?? spec.url.absoluteString)#\(spec.scramble)"
    }

    func image(for spec: ImageSpec) async throws -> UIImage {
        let key = key(for: spec)
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = inflight[key] { return try await task.value }

        let task = Task { try await Self.fetch(spec) }
        inflight[key] = task
        defer { inflight[key] = nil }
        let image = try await task.value
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }

    private static func fetch(_ spec: ImageSpec) async throws -> UIImage {
        var request = URLRequest(url: spec.url)
        switch spec.source {
        case .nhentai:
            request.setValue("NClient/3 (GodBook iOS)", forHTTPHeaderField: "User-Agent")
        case .jmcomic:
            request.setValue(JMClient.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("com.JMComic3.app", forHTTPHeaderField: "X-Requested-With")
            request.setValue("https://www.cdnhjk.net", forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await HTTP.data(for: request)
        guard response.statusCode == 200 else { throw AppError.http(response.statusCode) }
        guard var image = UIImage(data: data) else { throw AppError.message("無法解碼圖片") }
        if spec.scramble > 1, let restored = Descrambler.descramble(image, num: spec.scramble) {
            image = restored
        }
        return await image.byPreparingForDisplay() ?? image
    }
}

/// 非同步載入遠端圖片（支援禁漫還原與請求標頭）。
struct RemoteImageView: View {
    let spec: ImageSpec?
    var fill = false
    /// 載入前的預留高寬比 (寬/高)
    var placeholderAspect: CGFloat = 0.72

    @State private var image: UIImage?
    @State private var loadedSpec: ImageSpec?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        ZStack {
            if let image {
                if fill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Color.gray.opacity(0.14)
                    .aspectRatio(placeholderAspect, contentMode: .fit)
                    .overlay {
                        if failed {
                            Button {
                                failed = false
                                attempt += 1
                            } label: {
                                Image(systemName: "arrow.clockwise").font(.title3)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: TaskKey(spec: spec, attempt: attempt)) { await load() }
    }

    private struct TaskKey: Hashable {
        var spec: ImageSpec?
        var attempt: Int
    }

    private func load() async {
        guard let spec else { return }
        if loadedSpec == spec, image != nil { return }
        image = nil
        do {
            let loaded = try await ImageLoader.shared.image(for: spec)
            image = loaded
            loadedSpec = spec
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
