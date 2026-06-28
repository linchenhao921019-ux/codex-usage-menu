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

enum CodexUsageSnapshotStore {
    static let snapshotURLs = [
        URL(string: "http://Mac-mini.local:8765/snapshot")!,
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
        load(from: snapshotURLs, index: 0, completion: completion)
    }

    private static func load(from urls: [URL], index: Int, completion: @escaping (CodexUsageSnapshot?) -> Void) {
        guard index < urls.count else {
            completion(nil)
            return
        }

        session.dataTask(with: urls[index]) { data, _, _ in
            guard let data else {
                load(from: urls, index: index + 1, completion: completion)
                return
            }
            if let snapshot = decode(data: data) {
                completion(snapshot)
            } else {
                load(from: urls, index: index + 1, completion: completion)
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
