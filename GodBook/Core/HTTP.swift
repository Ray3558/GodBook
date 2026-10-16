import Foundation

enum HTTP {
    private static let lock = NSLock()
    private static var cachedSession = NetworkManager.makeSession(cached: true)
    private static var uncachedSession = NetworkManager.makeSession(cached: false)
    private static var tcpSessionStore = NetworkManager.makeSession(cached: false, tcpOnly: true)

    /// 一般 API 請求（有 URL 快取）
    static var session: URLSession {
        lock.lock(); defer { lock.unlock() }
        return cachedSession
    }

    /// 不使用快取的連線（漫畫源腳本、登入等）
    static var plainSession: URLSession {
        lock.lock(); defer { lock.unlock() }
        return uncachedSession
    }

    /// 只走 TCP（不使用 HTTP/3）的連線；某些網路環境下 QUIC 會出現 -1103 之類的怪錯誤，用來重試
    static var tcpSession: URLSession {
        lock.lock(); defer { lock.unlock() }
        return tcpSessionStore
    }

    /// 代理或憑證設定變更後重新建立連線
    static func reload() {
        lock.lock()
        let old = [cachedSession, uncachedSession, tcpSessionStore]
        cachedSession = NetworkManager.makeSession(cached: true)
        uncachedSession = NetworkManager.makeSession(cached: false)
        tcpSessionStore = NetworkManager.makeSession(cached: false, tcpOnly: true)
        lock.unlock()
        old.forEach { $0.finishTasksAndInvalidate() }
    }

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code.rawValue == -1103 {
            // 某些網路環境下 HTTP/3 會回 -1103，改走只用 TCP 的連線重試
            (data, response) = try await tcpSession.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw AppError.message(L("無效的伺服器回應")) }
        return (data, http)
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.message(L("無法解析伺服器資料"))
        }
        return object
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let s = self[key] as? String { return s }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = self[key] as? Int { return n }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func dicts(_ key: String) -> [[String: Any]] {
        (self[key] as? [[String: Any]]) ?? []
    }

    func strings(_ key: String) -> [String] {
        (self[key] as? [Any])?.compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue } ?? []
    }
}
