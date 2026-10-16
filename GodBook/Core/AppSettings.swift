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
    @Published var lastSource: SourceKind { didSet { defaults.set(lastSource.rawValue, forKey: "ui.lastSource") } }

    var jmLoggedIn: Bool { !jmAVS.isEmpty }

    private init() {
        nhMirror = defaults.string(forKey: "nh.mirror") ?? "nhentai.net"
        nhApiKey = defaults.string(forKey: "nh.apiKey") ?? ""
        jmCustomDomain = defaults.string(forKey: "jm.customDomain") ?? ""
        jmUsername = defaults.string(forKey: "jm.username") ?? ""
        jmAVS = defaults.string(forKey: "jm.avs") ?? ""
        readerMode = ReaderMode(rawValue: defaults.string(forKey: "reader.mode") ?? "") ?? .vertical
        lastSource = SourceKind(rawValue: defaults.string(forKey: "ui.lastSource") ?? "") ?? .nhentai
    }
}
