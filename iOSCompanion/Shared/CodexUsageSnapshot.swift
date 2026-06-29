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

final class CodexUsageLoadCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedFailureCount: Int
    private let completion: (CodexUsageLoadResult) -> Void
    private var completed = false
    private var failures: [String] = []
    private var tasks: [URLSessionDataTask] = []

    init(expectedFailureCount: Int, completion: @escaping (CodexUsageLoadResult) -> Void) {
        self.expectedFailureCount = expectedFailureCount
        self.completion = completion
    }

    func append(task: URLSessionDataTask) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    func finish(_ result: CodexUsageLoadResult) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        let tasksToCancel = tasks
        lock.unlock()

        tasksToCancel.forEach { $0.cancel() }
        completion(result)
    }

    func recordFailure(_ message: String) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        failures.append(message)
        let shouldFinish = failures.count == expectedFailureCount
        let failureMessage = failures.joined(separator: "\n")
        lock.unlock()

        if shouldFinish {
            if let cachedSnapshot = CodexUsageSnapshotStore.cachedSnapshot() {
                finish(CodexUsageLoadResult(
                    snapshot: cachedSnapshot,
                    message: "网络不可达，显示最后一次成功数据\n\(failureMessage)"
                ))
            } else {
                finish(CodexUsageLoadResult(snapshot: nil, message: failureMessage))
            }
        }
    }
}

enum CodexUsageSnapshotStore {
    private static let cachedSnapshotKey = "codexUsage.lastSuccessfulSnapshot"

    static let snapshotURLs = [
        URL(string: "http://10.241.1.21:8765/snapshot")!,
        URL(string: "http://10.241.1.186:8765/snapshot")!,
        URL(string: "http://Mac-mini.local:8765/snapshot")!,
        URL(string: "http://linchenhaodeMacBook-Air.local:8765/snapshot")!,
        URL(string: "http://MacBook-Air.local:8765/snapshot")!,
        URL(string: "http://MacBookAir.local:8765/snapshot")!
    ]
    static let snapshotURL = snapshotURLs[0]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func load() -> CodexUsageSnapshot? {
        for url in snapshotURLs {
            if let snapshot = load(from: url) {
                saveToCache(snapshot)
                return snapshot
            }
        }
        return cachedSnapshot()
    }

    static func load(completion: @escaping (CodexUsageSnapshot?) -> Void) {
        loadWithDiagnostics { result in
            completion(result.snapshot)
        }
    }

    static func loadWithDiagnostics(completion: @escaping (CodexUsageLoadResult) -> Void) {
        let coordinator = CodexUsageLoadCoordinator(
            expectedFailureCount: snapshotURLs.count,
            completion: completion
        )

        for url in snapshotURLs {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 2

            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    coordinator.recordFailure("\(url.host ?? url.absoluteString): \(error.localizedDescription)")
                    return
                }
                guard let data else {
                    coordinator.recordFailure("\(url.host ?? url.absoluteString): 没有返回数据")
                    return
                }
                if let snapshot = decode(data: data) {
                    saveToCache(snapshot)
                    coordinator.finish(CodexUsageLoadResult(snapshot: snapshot, message: "已连接：\(url.host ?? url.absoluteString)"))
                } else {
                    let statusCode = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "unknown"
                    coordinator.recordFailure("\(url.host ?? url.absoluteString): JSON 解析失败，HTTP \(statusCode)")
                }
            }

            coordinator.append(task: task)
            task.resume()
        }
    }

    static func load(from url: URL) -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let snapshot = decode(data: data)
        if let snapshot {
            saveToCache(snapshot)
        }
        return snapshot
    }

    static func decode(data: Data) -> CodexUsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexUsageSnapshot.self, from: data)
    }

    static func cachedSnapshot() -> CodexUsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cachedSnapshotKey) else {
            return nil
        }
        return decode(data: data)
    }

    private static func saveToCache(_ snapshot: CodexUsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: cachedSnapshotKey)
        }
    }
}

extension CodexUsageSnapshot {
    var isStale: Bool {
        Date().timeIntervalSince(exportedAt) > 60 * 60
    }
}
