import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case nhentai, jmcomic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nhentai: "nhentai"
        case .jmcomic: "禁漫"
        }
    }
}

struct SortOption: Identifiable, Hashable {
    let id: String
    let title: String
    var order: String = ""
    var time: String = ""
}

struct ComicSummary: Identifiable, Hashable, Codable {
    var source: SourceKind
    var sid: String
    var title: String
    var coverURL: URL?
    var subtitle: String?

    var id: String { "\(source.rawValue):\(sid)" }
}

struct ComicTag: Hashable, Identifiable {
    var name: String
    var group: String?
    /// 點擊後用來搜尋的字串；nil 代表不可點擊
    var query: String?

    var id: String { "\(group ?? "")|\(name)" }
}

struct Chapter: Identifiable, Hashable {
    var id: String
    var title: String
}

struct ImageSpec: Hashable {
    var url: URL
    var source: SourceKind
    /// 禁漫圖片的切割份數，0 或 1 代表不需還原
    var scramble: Int = 0
}

struct ReaderPage: Identifiable, Hashable {
    var index: Int
    var image: ImageSpec
    var id: Int { index }
}

struct ComicDetail {
    var summary: ComicSummary
    var description: String?
    var authors: [String] = []
    var tags: [ComicTag] = []
    var stats: [String] = []
    var chapters: [Chapter] = []
    var related: [ComicSummary] = []
    var pageCount: Int?
    /// nhentai 的詳情已含所有頁面；禁漫需再向章節 API 取得
    var preloadedPages: [ReaderPage]?
}

struct ComicPageResult {
    var items: [ComicSummary]
    var total: Int?
    var totalPages: Int?
}

struct SearchRoute: Hashable {
    var source: SourceKind
    var query: String
    var title: String
}

protocol ComicSource {
    var kind: SourceKind { get }
    var sortOptions: [SortOption] { get }
    func browse(query: String, page: Int, sort: SortOption) async throws -> ComicPageResult
    func detail(of summary: ComicSummary) async throws -> ComicDetail
    func pages(of detail: ComicDetail, chapter: Chapter) async throws -> [ReaderPage]
}

enum SourceRegistry {
    static func source(_ kind: SourceKind) -> ComicSource {
        switch kind {
        case .nhentai: NHentaiSource()
        case .jmcomic: JMComicSource()
        }
    }
}

enum AppError: LocalizedError {
    case http(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            switch code {
            case 403: "存取被拒絕 (403)：可能需要 API Key、換鏡像網域，或網路環境被封鎖"
            case 404: "找不到內容 (404)"
            case 429: "請求太頻繁 (429)，請稍後再試"
            default: "伺服器回應錯誤 (\(code))"
            }
        case .message(let text):
            text
        }
    }
}
