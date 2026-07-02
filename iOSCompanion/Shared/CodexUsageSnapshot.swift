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
    let sourceName: String?
    let sourceURL: URL?
    let isCached: Bool
}

struct CodexUsageEndpoint: Hashable {
    let url: URL
    let sourceName: String
}

final class CodexUsageLoadCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedFailureCount: Int
    private let completion: (CodexUsageLoadResult) -> Void
    private let allFailed: ([String]) -> Void
    private var completed = false
    private var failures: [String] = []
    private var tasks: [URLSessionDataTask] = []

    init(
        expectedFailureCount: Int,
        completion: @escaping (CodexUsageLoadResult) -> Void,
        allFailed: @escaping ([String]) -> Void
    ) {
        self.expectedFailureCount = expectedFailureCount
        self.completion = completion
        self.allFailed = allFailed
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
        let failures = failures
        lock.unlock()

        if shouldFinish {
            allFailed(failures)
        }
    }
}

enum CodexUsageSnapshotStore {
    private static let cachedSnapshotKey = "codexUsage.lastSuccessfulSnapshot"
    private static let companionEndpoint = CodexUsageEndpoint(
        url: URL(string: "http://127.0.0.1:8766/snapshot")!,
        sourceName: "当前 App"
    )

    private static let macMiniEndpoints = [
        CodexUsageEndpoint(url: URL(string: "http://10.241.1.21:8765/snapshot")!, sourceName: "Mac mini"),
        CodexUsageEndpoint(url: URL(string: "http://10.241.1.186:8765/snapshot")!, sourceName: "Mac mini"),
        CodexUsageEndpoint(url: URL(string: "http://Mac-mini.local:8765/snapshot")!, sourceName: "Mac mini")
    ]

    private static let macBookEndpoints = [
        CodexUsageEndpoint(url: URL(string: "http://linchenhaodeMacBook-Air.local:8765/snapshot")!, sourceName: "MacBook Air"),
        CodexUsageEndpoint(url: URL(string: "http://MacBook-Air.local:8765/snapshot")!, sourceName: "MacBook Air"),
        CodexUsageEndpoint(url: URL(string: "http://MacBookAir.local:8765/snapshot")!, sourceName: "MacBook Air")
    ]

    private static let snapshotEndpoints = macMiniEndpoints + macBookEndpoints
    static let snapshotURLs = snapshotEndpoints.map(\.url)
    static let snapshotURL = snapshotURLs[0]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 1.25
        configuration.timeoutIntervalForResource = 1.25
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func load() -> CodexUsageSnapshot? {
        for endpoint in snapshotEndpoints {
            if let snapshot = load(from: endpoint.url) {
                saveToCache(snapshot)
                return snapshot
            }
        }
        return cachedSnapshot()
    }

    static func load(completion: @escaping (CodexUsageSnapshot?) -> Void) {
        load(from: [[companionEndpoint], macMiniEndpoints, macBookEndpoints], index: 0, failures: []) { result in
            completion(result.snapshot)
        }
    }

    static func loadWithDiagnostics(completion: @escaping (CodexUsageLoadResult) -> Void) {
        let tiers = [macMiniEndpoints, macBookEndpoints]
        load(from: tiers, index: 0, failures: [], completion: completion)
    }

    private static func load(
        from tiers: [[CodexUsageEndpoint]],
        index: Int,
        failures: [String],
        completion: @escaping (CodexUsageLoadResult) -> Void
    ) {
        guard index < tiers.count else {
            let failureMessage = failures.joined(separator: "\n")
            if let cachedSnapshot = cachedSnapshot() {
                completion(CodexUsageLoadResult(
                    snapshot: cachedSnapshot,
                    message: "网络不可达，显示最后一次成功数据\n\(failureMessage)",
                    sourceName: "上次成功缓存",
                    sourceURL: nil,
                    isCached: true
                ))
            } else {
                completion(CodexUsageLoadResult(
                    snapshot: nil,
                    message: failureMessage,
                    sourceName: nil,
                    sourceURL: nil,
                    isCached: false
                ))
            }
            return
        }

        let endpoints = tiers[index]
        guard endpoints.isEmpty == false else {
            load(from: tiers, index: index + 1, failures: failures, completion: completion)
            return
        }

        let coordinator = CodexUsageLoadCoordinator(
            expectedFailureCount: endpoints.count,
            completion: completion,
            allFailed: { tierFailures in
                load(
                    from: tiers,
                    index: index + 1,
                    failures: failures + tierFailures,
                    completion: completion
                )
            }
        )

        for endpoint in endpoints {
            let url = endpoint.url
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 1.25

            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    coordinator.recordFailure("\(endpoint.sourceName) \(url.host ?? url.absoluteString): \(error.localizedDescription)")
                    return
                }
                guard let data else {
                    coordinator.recordFailure("\(endpoint.sourceName) \(url.host ?? url.absoluteString): 没有返回数据")
                    return
                }
                if let snapshot = decode(data: data) {
                    saveToCache(snapshot)
                    coordinator.finish(CodexUsageLoadResult(
                        snapshot: snapshot,
                        message: "已连接：\(endpoint.sourceName)",
                        sourceName: endpoint.sourceName,
                        sourceURL: url,
                        isCached: false
                    ))
                } else {
                    let statusCode = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "unknown"
                    coordinator.recordFailure("\(endpoint.sourceName) \(url.host ?? url.absoluteString): JSON 解析失败，HTTP \(statusCode)")
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
