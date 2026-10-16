import Foundation

enum ReaderMode: String, CaseIterable, Identifiable {
    case vertical, horizontal, horizontalRTL
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vertical: "垂直捲動"
        case .horizontal: "左右翻頁"
        case .horizontalRTL: "右到左翻頁（日漫）"
        }
    }
}

/// 使用者可調整的來源與閱讀設定。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var nhMirror: String { didSet { defaults.set(nhMirror, forKey: "nh.mirror") } }
    @Published var nhApiKey: String { didSet { defaults.set(nhApiKey, forKey: "nh.apiKey") } }
    @Published var jmCustomDomain: String { didSet { defaults.set(jmCustomDomain, forKey: "jm.customDomain") } }
    @Published var jmUsername: String { didSet { defaults.set(jmUsername, forKey: "jm.username") } }
    @Published var jmAVS: String { didSet { defaults.set(jmAVS, forKey: "jm.avs") } }
    @Published var readerMode: ReaderMode { didSet { defaults.set(readerMode.rawValue, forKey: "reader.mode") } }
    @Published var downloadConcurrency: Int { didSet { defaults.set(downloadConcurrency, forKey: "dl.concurrency") } }
    @Published var translateTags: Bool { didSet { defaults.set(translateTags, forKey: "ui.translateTags") } }
    /// 被使用者停用（不顯示、不載入）的來源 rawValue
    @Published var disabledSources: Set<String> {
        didSet { defaults.set(Array(disabledSources), forKey: "ui.disabledSources") }
    }
    @Published var lastSource: SourceKind { didSet { defaults.set(lastSource.rawValue, forKey: "ui.lastSource") } }

    var jmLoggedIn: Bool { !jmAVS.isEmpty }

    /// 目前啟用的來源（依序：nhentai、禁漫、已安裝的 venera 漫畫源）
    var enabledSources: [SourceKind] {
        SourceKind.all.filter { !disabledSources.contains($0.rawValue) }
    }

    func isEnabled(_ kind: SourceKind) -> Bool { !disabledSources.contains(kind.rawValue) }

    func setEnabled(_ kind: SourceKind, _ enabled: Bool) {
        if enabled { disabledSources.remove(kind.rawValue) } else { disabledSources.insert(kind.rawValue) }
        if !enabled, lastSource == kind, let fallback = enabledSources.first { lastSource = fallback }
    }

    private init() {
        nhMirror = defaults.string(forKey: "nh.mirror") ?? "nhentai.net"
        nhApiKey = defaults.string(forKey: "nh.apiKey") ?? ""
        jmCustomDomain = defaults.string(forKey: "jm.customDomain") ?? ""
        jmUsername = defaults.string(forKey: "jm.username") ?? ""
        jmAVS = defaults.string(forKey: "jm.avs") ?? ""
        readerMode = ReaderMode(rawValue: defaults.string(forKey: "reader.mode") ?? "") ?? .vertical
        disabledSources = Set(defaults.stringArray(forKey: "ui.disabledSources") ?? [])
        let savedConcurrency = defaults.integer(forKey: "dl.concurrency")
        downloadConcurrency = savedConcurrency == 0 ? 4 : savedConcurrency
        translateTags = defaults.object(forKey: "ui.translateTags") as? Bool ?? true
        lastSource = SourceKind(rawValue: defaults.string(forKey: "ui.lastSource") ?? "nhentai")
    }
}
