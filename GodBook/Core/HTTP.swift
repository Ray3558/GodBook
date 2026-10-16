import Foundation

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 400 << 20)
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("無效的伺服器回應") }
        return (data, http)
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.message("無法解析伺服器資料")
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
