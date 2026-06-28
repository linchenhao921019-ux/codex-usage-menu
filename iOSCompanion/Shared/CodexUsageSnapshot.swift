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
    static let snapshotURL = URL(string: "http://linchenhaodeMacBook-Air.local:8765/snapshot")!

    static func load() -> CodexUsageSnapshot? {
        load(from: snapshotURL)
    }

    static func load(completion: @escaping (CodexUsageSnapshot?) -> Void) {
        URLSession.shared.dataTask(with: snapshotURL) { data, _, _ in
            guard let data else {
                completion(nil)
                return
            }
            completion(decode(data: data))
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
