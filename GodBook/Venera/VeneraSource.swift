import Foundation

/// 把 venera 漫畫源（JS）轉接成 GodBook 的 ComicSource。
struct VeneraSource: ComicSource {
    let kind: SourceKind

    private final class TokenBox {
        var next: [Int: String] = [:]
        var folder: String??
    }
    private let tokens = TokenBox()

    private var key: String { kind.veneraKey }
    private var info: VeneraInfo? { VeneraRegistry.shared.info(key) }
    private var runtime: VeneraRuntime { .shared }

    init(kind: SourceKind) { self.kind = kind }

    // MARK: 排序 / 分區

    var sortOptions: [SortOption] {
        guard let info else { return [SortOption(id: "none", title: "—")] }
        var options: [SortOption] = []
        for (index, page) in info.explore.enumerated() {
            options.append(SortOption(id: "explore:\(index)", title: page.title, section: "探索"))
        }
        if let category = info.category {
            for (partIndex, part) in category.parts.enumerated() {
                for (itemIndex, item) in part.items.enumerated() {
                    options.append(SortOption(id: "cat:\(partIndex):\(itemIndex)", title: item.label,
                                              section: part.name.isEmpty ? category.title : part.name))
                }
            }
        }
        for pair in info.ranking?.options ?? [] where pair.count == 2 {
            options.append(SortOption(id: "rank:\(pair[0])", title: pair[1], section: "排行"))
        }
        if let first = info.search?.options.first, first.type == "select" {
            for pair in first.options where pair.count == 2 {
                options.append(SortOption(id: "search:\(pair[0])", title: pair[1], section: first.label.isEmpty ? "搜尋排序" : first.label))
            }
        }
        return options.isEmpty ? [SortOption(id: "none", title: "—")] : options
    }

    // MARK: 瀏覽

    func browse(query: String, page: Int, sort: SortOption) async throws -> ComicPageResult {
        guard let info else { throw AppError.message("漫畫源尚未載入") }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let (category, param) = VeneraQuery.decodeCategory(trimmed) {
            let result = try await runtime.call(key, "__category", [category, param, defaultCategoryOptions(info), page])
            return decodePage(result, page: page)
        }

        if !trimmed.isEmpty {
            guard let search = info.search else { throw AppError.message("這個漫畫源不支援搜尋") }
            var options = defaultOptions(search.options)
            if sort.id.hasPrefix("search:"), !options.isEmpty {
                options[0] = String(sort.id.dropFirst("search:".count))
            }
            let result = try await runtime.call(key, "__search", [trimmed, options, page, tokens.next[page]])
            return decodePage(result, page: page)
        }

        let parts = sort.id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "explore":
            let result = try await runtime.call(key, "__explore", [Int(parts[safe: 1] ?? "") ?? 0, page, tokens.next[page]])
            return decodePage(result, page: page)
        case "cat":
            let item = info.category?.parts[safe: Int(parts[safe: 1] ?? "") ?? 0]?.items[safe: Int(parts[safe: 2] ?? "") ?? 0]
            guard let item else { throw AppError.message("分類不存在") }
            if item.kind == "search" {
                return try await browse(query: item.text ?? item.label, page: page, sort: SortOption(id: "none", title: ""))
            }
            let result = try await runtime.call(key, "__category", [item.category ?? item.label, item.param, defaultCategoryOptions(info), page])
            return decodePage(result, page: page)
        case "rank":
            let result = try await runtime.call(key, "__ranking", [parts.dropFirst().joined(separator: ":"), page, tokens.next[page]])
            return decodePage(result, page: page)
        default:
            // 沒有選任何分區時的預設行為
            if !info.explore.isEmpty {
                let result = try await runtime.call(key, "__explore", [0, page, tokens.next[page]])
                return decodePage(result, page: page)
            }
            throw AppError.message("這個漫畫源沒有可瀏覽的首頁，請使用搜尋")
        }
    }

    func favorites(page: Int) async throws -> ComicPageResult {
        guard let info, let favorites = info.favorites else { throw AppError.message("這個漫畫源沒有雲端收藏") }
        var folder: String?
        if favorites.multiFolder {
            if tokens.folder == nil {
                let result = try await runtime.call(key, "__favoriteFolders", [])
                let first = (result["folders"] as? [[String: Any]])?.first?["id"] as? String
                tokens.folder = .some(first)
            }
            folder = tokens.folder ?? nil
        }
        let result = try await runtime.call(key, "__favorites", [page, folder, tokens.next[page]])
        return decodePage(result, page: page)
    }

    // MARK: 詳情

    func detail(of summary: ComicSummary) async throws -> ComicDetail {
        let r = try await runtime.call(key, "__loadInfo", [summary.sid])

        var base = summary
        if let title = r["title"] as? String, !title.isEmpty { base.title = title }
        if let cover = (r["cover"] as? String).flatMap(VeneraURL.make) { base.coverURL = cover }
        let subtitle = (r["subtitle"] as? String) ?? ""
        if !subtitle.isEmpty { base.subtitle = subtitle }

        let authorNamespaces: Set<String> = ["author", "authors", "artist", "artists", "作者", "画师", "畫師"]
        var tags: [ComicTag] = []
        var authors: [String] = []
        for item in (r["tags"] as? [[String: Any]]) ?? [] {
            guard let name = item["name"] as? String else { continue }
            let namespace = (item["ns"] as? String) ?? ""
            var query: String? = name
            if let target = item["target"] as? [String: Any] {
                if (target["kind"] as? String) == "category", let category = target["category"] as? String {
                    query = VeneraQuery.category(category, target["param"] as? String)
                } else if let text = target["text"] as? String {
                    query = text
                }
            }
            tags.append(ComicTag(name: name, group: namespace.isEmpty ? nil : namespace, query: query))
            if authorNamespaces.contains(namespace.lowercased()) { authors.append(name) }
        }
        if authors.isEmpty, !subtitle.isEmpty { authors = [subtitle] }

        var chapters: [Chapter] = ((r["chapters"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let title = (item["title"] as? String) ?? id
            if let group = item["group"] as? String, !group.isEmpty { return Chapter(id: id, title: "\(group) · \(title)") }
            return Chapter(id: id, title: title)
        }
        if chapters.isEmpty { chapters = [Chapter(id: VeneraQuery.noChapter, title: "開始閱讀")] }

        var stats: [String] = []
        if let likes = r["likesCount"] as? Int { stats.append("♥ \(likes)") }
        if let comments = r["commentCount"] as? Int { stats.append("💬 \(comments)") }
        if let stars = r["stars"] as? Double { stats.append("★ \(String(format: "%.1f", stars))") }
        if let uploader = r["uploader"] as? String, !uploader.isEmpty { stats.append(uploader) }
        if let updated = (r["updateTime"] as? String) ?? (r["uploadTime"] as? String) { stats.append(updated) }

        let related = ((r["recommend"] as? [[String: Any]]) ?? []).compactMap(makeSummary)
        let description = (r["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return ComicDetail(summary: base, description: description, authors: authors, tags: tags,
                           stats: stats, chapters: chapters, related: related, pageCount: r["maxPage"] as? Int)
    }

    func pages(of detail: ComicDetail, chapter: Chapter) async throws -> [ReaderPage] {
        let epId: String? = chapter.id == VeneraQuery.noChapter ? nil : chapter.id
        let result = try await runtime.call(key, "__loadEp", [detail.summary.sid, epId])
        let images = (result["images"] as? [String]) ?? []
        guard !images.isEmpty else { throw AppError.message("這個章節沒有圖片") }
        return images.enumerated().map { index, string in
            let spec = ImageSpec(url: VeneraURL.make(string) ?? VeneraURL.placeholder, source: kind,
                                 imageKey: string, comicId: detail.summary.sid, epId: epId ?? "")
            return ReaderPage(index: index, image: spec)
        }
    }

    // MARK: 轉換

    private func makeSummary(_ item: [String: Any]) -> ComicSummary? {
        guard let id = item["id"] as? String else { return nil }
        var subtitle = (item["subtitle"] as? String) ?? ""
        if subtitle.isEmpty, let tags = item["tags"] as? [String], !tags.isEmpty {
            subtitle = tags.prefix(3).joined(separator: " · ")
        }
        return ComicSummary(source: kind, sid: id, title: (item["title"] as? String) ?? id,
                            coverURL: (item["cover"] as? String).flatMap(VeneraURL.make),
                            subtitle: subtitle.isEmpty ? nil : subtitle)
    }

    private func decodePage(_ result: [String: Any], page: Int) -> ComicPageResult {
        let items = ((result["comics"] as? [[String: Any]]) ?? []).compactMap(makeSummary)
        if let next = result["next"] as? String { tokens.next[page + 1] = next }
        var totalPages = result["maxPage"] as? Int
        if totalPages == nil, (result["usesNext"] as? Bool) == true, result["next"] == nil || result["next"] is NSNull {
            totalPages = page
        }
        return ComicPageResult(items: items, total: nil, totalPages: totalPages)
    }

    private func defaultOptions(_ options: [VeneraInfo.Option]) -> [String?] {
        options.map { option in
            if let value = option.def { return value }
            if option.type == "multi-select" { return "[]" }
            if option.type == "dropdown" { return nil }
            return option.options.first?.first
        }
    }

    private func defaultCategoryOptions(_ info: VeneraInfo) -> [String?] {
        defaultOptions(info.categoryOptions)
    }
}

enum VeneraURL {
    static let placeholder = URL(string: "https://venera.invalid/")!

    static func make(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        let allowed = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#%"))
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }
}

/// 以特殊前綴把「分類」編碼成搜尋字串，讓標籤點擊可以沿用同一條導覽路徑。
enum VeneraQuery {
    static let noChapter = "__none__"
    private static let prefix = "\u{1}category\u{1}"

    static func category(_ name: String, _ param: String?) -> String {
        prefix + name + "\u{1}" + (param ?? "")
    }

    static func decodeCategory(_ query: String) -> (String, String?)? {
        guard query.hasPrefix(prefix) else { return nil }
        let rest = query.dropFirst(prefix.count).split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = rest.first else { return nil }
        let param = rest.count > 1 ? String(rest[1]) : ""
        return (String(name), param.isEmpty ? nil : param)
    }
}
