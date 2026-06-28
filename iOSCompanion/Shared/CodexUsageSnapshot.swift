import Foundation

struct CodexUsageWindow: Codable, Hashable {
    let label: String
    let compactLabel: String
    let usedPercent: Double
    let remainingPercent: Int
    let windowMinutes: Int
    let resetsAt: Date?
}

struct CodexUsageSnapshot: Codable, Hashable {
    let schemaVersion: Int
    let exportedAt: Date
    let snapshotTimestamp: Date
    let planType: String?
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?
}

struct CodexUsageLoadResult: Hashable {
    let snapshot: CodexUsageSnapshot?
    let message: String
}

enum CodexUsageSnapshotStore {
    static let snapshotURLs = [
        URL(string: "http://Mac-mini.local:8765/snapshot")!,
        URL(string: "http://10.241.1.21:8765/snapshot")!,
        URL(string: "http://10.241.1.186:8765/snapshot")!,
        URL(string: "http://MacBook-Air.local:8765/snapshot")!,
        URL(string: "http://MacBookAir.local:8765/snapshot")!
    ]
    static let snapshotURL = snapshotURLs[0]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        return URLSession(configuration: configuration)
    }()

    static func load() -> CodexUsageSnapshot? {
        for url in snapshotURLs {
            if let snapshot = load(from: url) {
                return snapshot
            }
        }
        return nil
    }

    static func load(completion: @escaping (CodexUsageSnapshot?) -> Void) {
        loadWithDiagnostics { result in
            completion(result.snapshot)
        }
    }

    static func loadWithDiagnostics(completion: @escaping (CodexUsageLoadResult) -> Void) {
        load(from: snapshotURLs, index: 0, failures: [], completion: completion)
    }

    private static func load(
        from urls: [URL],
        index: Int,
        failures: [String],
        completion: @escaping (CodexUsageLoadResult) -> Void
    ) {
        guard index < urls.count else {
            completion(CodexUsageLoadResult(snapshot: nil, message: failures.joined(separator: "\n")))
            return
        }

        let url = urls[index]
        session.dataTask(with: url) { data, response, error in
            var failures = failures
            if let error {
                failures.append("\(url.host ?? url.absoluteString): \(error.localizedDescription)")
                load(from: urls, index: index + 1, failures: failures, completion: completion)
                return
            }
            guard let data else {
                failures.append("\(url.host ?? url.absoluteString): 没有返回数据")
                load(from: urls, index: index + 1, failures: failures, completion: completion)
                return
            }
            if let snapshot = decode(data: data) {
                completion(CodexUsageLoadResult(snapshot: snapshot, message: "已连接：\(url.host ?? url.absoluteString)"))
            } else {
                let statusCode = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "unknown"
                failures.append("\(url.host ?? url.absoluteString): JSON 解析失败，HTTP \(statusCode)")
                load(from: urls, index: index + 1, failures: failures, completion: completion)
            }
        }.resume()
    }

    static func load(from url: URL) -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode(data: data)
    }

    static func decode(data: Data) -> CodexUsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexUsageSnapshot.self, from: data)
    }
}

extension CodexUsageSnapshot {
    var isStale: Bool {
        Date().timeIntervalSince(exportedAt) > 60 * 60
    }
}
