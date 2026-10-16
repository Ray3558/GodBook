import Foundation

/// 標籤翻譯（繁體中文）。資料來自 EhTagTranslation Database（經 venera 整理的 tags_tw.json）。
final class TagTranslator {
    static let shared = TagTranslator()

    private lazy var table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "tags_tw", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// nhentai 的 tag 類型 → 翻譯資料的命名空間
    private func namespaces(for group: String?) -> [String] {
        switch group {
        case "tag": ["female", "male", "mixed", "other"]
        case "category": ["reclass"]
        case let group?: [group]
        case nil: []
        }
    }

    func translate(_ name: String, group: String?) -> String {
        let key = name.lowercased()
        for namespace in namespaces(for: group) {
            if let value = table[namespace]?[key] { return value }
        }
        return name
    }

    func groupTitle(_ group: String) -> String {
        table["rows"]?[group] ?? group
    }
}
