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

struct CodexUsageEndpointSnapshot: Hashable {
    let snapshot: CodexUsageSnapshot
    let endpoint: CodexUsageEndpoint
}

final class BonjourEndpointDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var endpoints: Set<CodexUsageEndpoint> = []
    private var completion: (([CodexUsageEndpoint]) -> Void)?

    static func discover(timeout: TimeInterval = 2.5, completion: @escaping ([CodexUsageEndpoint]) -> Void) {
        let discovery = BonjourEndpointDiscovery()
        discovery.completion = completion
        discovery.browser.delegate = discovery
        discovery.browser.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            discovery.finish()
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        guard service.name.hasPrefix("Codex Usage ") else {
            return
        }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 2)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, sender.port > 0 else {
            return
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = sender.port
        components.path = "/snapshot"
        if let url = components.url {
            endpoints.insert(CodexUsageEndpoint(url: url, sourceName: "Mac"))
        }
    }

    private func finish() {
        browser.stop()
        services.forEach { $0.stop() }
        completion?(Array(endpoints))
        completion = nil
    }
}

final class CodexUsageSourceCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedFailureCount: Int
    private let completion: (CodexUsageEndpointSnapshot?, [String]) -> Void
    private var completed = false
    private var failures: [String] = []
    private var tasks: [URLSessionDataTask] = []

    init(
        expectedFailureCount: Int,
        completion: @escaping (CodexUsageEndpointSnapshot?, [String]) -> Void
    ) {
        self.expectedFailureCount = expectedFailureCount
        self.completion = completion
    }

    func append(task: URLSessionDataTask) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    func finish(_ result: CodexUsageEndpointSnapshot) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        let tasksToCancel = tasks
        lock.unlock()

        tasksToCancel.forEach { $0.cancel() }
        completion(result, [])
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
            completion(nil, failures)
        }
    }
}

final class CodexUsageFreshestCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedSourceCount: Int
    private let completion: ([CodexUsageEndpointSnapshot], [String]) -> Void
    private var resolvedSourceCount = 0
    private var candidates: [CodexUsageEndpointSnapshot] = []
    private var failures: [String] = []

    init(
        expectedSourceCount: Int,
        completion: @escaping ([CodexUsageEndpointSnapshot], [String]) -> Void
    ) {
        self.expectedSourceCount = expectedSourceCount
        self.completion = completion
    }

    func resolve(candidate: CodexUsageEndpointSnapshot?, failures sourceFailures: [String]) {
        lock.lock()
        resolvedSourceCount += 1
        if let candidate {
            candidates.append(candidate)
        }
        failures.append(contentsOf: sourceFailures)
        let shouldFinish = resolvedSourceCount == expectedSourceCount
        let candidates = candidates
        let failures = failures
        lock.unlock()

        if shouldFinish {
            completion(candidates, failures)
        }
    }
}

enum CodexUsageSnapshotStore {
    private static let cachedSnapshotKey = "codexUsage.lastSuccessfulSnapshot"
    private static let cachedSourceNameKey = "codexUsage.lastSuccessfulSourceName"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func load() -> CodexUsageSnapshot? {
        return cachedSnapshot()
    }

    static func load(completion: @escaping (CodexUsageSnapshot?) -> Void) {
        loadFreshest(allowsCacheFallback: true) { result in
            completion(result.snapshot)
        }
    }

    static func loadWithDiagnostics(completion: @escaping (CodexUsageLoadResult) -> Void) {
        loadFreshest(allowsCacheFallback: false, completion: completion)
    }

    private static func loadFreshest(
        allowsCacheFallback: Bool,
        completion: @escaping (CodexUsageLoadResult) -> Void
    ) {
        BonjourEndpointDiscovery.discover { endpoints in
            loadFreshest(
                from: endpoints,
                allowsCacheFallback: allowsCacheFallback,
                completion: completion
            )
        }
    }

    private static func loadFreshest(
        from endpoints: [CodexUsageEndpoint],
        allowsCacheFallback: Bool,
        completion: @escaping (CodexUsageLoadResult) -> Void
    ) {
        guard endpoints.isEmpty == false else {
            let cached = allowsCacheFallback ? cachedSnapshot() : nil
            completion(CodexUsageLoadResult(
                snapshot: cached,
                message: cached == nil ? "未发现同一网络中的 Mac" : "显示上次成功数据",
                sourceName: cached == nil ? nil : cachedSourceName(),
                sourceURL: nil,
                isCached: cached != nil
            ))
            return
        }

        let endpointGroups = endpoints.map { [$0] }
        let coordinator = CodexUsageFreshestCoordinator(expectedSourceCount: endpointGroups.count) { candidates, failures in
            if let freshest = freshestCandidate(in: candidates) {
                saveToCache(freshest.snapshot, sourceName: freshest.endpoint.sourceName)
                completion(CodexUsageLoadResult(
                    snapshot: freshest.snapshot,
                    message: "已同步最新数据",
                    sourceName: freshest.endpoint.sourceName,
                    sourceURL: freshest.endpoint.url,
                    isCached: false
                ))
            } else if allowsCacheFallback, let cachedSnapshot = cachedSnapshot() {
                let cachedSourceName = cachedSourceName() ?? "上次成功缓存"
                completion(CodexUsageLoadResult(
                    snapshot: cachedSnapshot,
                    message: "Mac 暂时不可达，显示上次成功数据",
                    sourceName: cachedSourceName,
                    sourceURL: nil,
                    isCached: true
                ))
            } else {
                completion(CodexUsageLoadResult(
                    snapshot: nil,
                    message: failures.isEmpty ? "Mac 暂时不可达" : "无法读取 Mac 数据",
                    sourceName: nil,
                    sourceURL: nil,
                    isCached: false
                ))
            }
        }

        for endpoints in endpointGroups {
            loadFirstAvailable(from: endpoints) { candidate, failures in
                coordinator.resolve(candidate: candidate, failures: failures)
            }
        }
    }

    private static func loadFirstAvailable(
        from endpoints: [CodexUsageEndpoint],
        completion: @escaping (CodexUsageEndpointSnapshot?, [String]) -> Void
    ) {
        let coordinator = CodexUsageSourceCoordinator(
            expectedFailureCount: endpoints.count,
            completion: completion
        )

        for endpoint in endpoints {
            let url = endpoint.url
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8

            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    coordinator.recordFailure("连接失败：\(error.localizedDescription)")
                    return
                }
                guard let data else {
                    coordinator.recordFailure("没有返回数据")
                    return
                }
                if let snapshot = decode(data: data) {
                    coordinator.finish(CodexUsageEndpointSnapshot(snapshot: snapshot, endpoint: endpoint))
                } else {
                    let statusCode = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "unknown"
                    coordinator.recordFailure("JSON 解析失败，HTTP \(statusCode)")
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

    static func cachedSourceName() -> String? {
        UserDefaults.standard.string(forKey: cachedSourceNameKey)
    }

    private static func saveToCache(_ snapshot: CodexUsageSnapshot, sourceName: String? = nil) {
        if let cachedSnapshot = cachedSnapshot(),
           isOlder(snapshot, than: cachedSnapshot) {
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: cachedSnapshotKey)
        }
        if let sourceName {
            UserDefaults.standard.set(sourceName, forKey: cachedSourceNameKey)
        }
    }

    private static func isOlder(_ candidate: CodexUsageSnapshot, than current: CodexUsageSnapshot) -> Bool {
        if candidate.snapshotTimestamp != current.snapshotTimestamp {
            return candidate.snapshotTimestamp < current.snapshotTimestamp
        }
        return candidate.exportedAt < current.exportedAt
    }

    static func freshestCandidate(in candidates: [CodexUsageEndpointSnapshot]) -> CodexUsageEndpointSnapshot? {
        candidates.max { lhs, rhs in
            isOlder(lhs.snapshot, than: rhs.snapshot)
        }
    }
}

extension CodexUsageSnapshot {
    var isStale: Bool {
        Date().timeIntervalSince(exportedAt) > 60 * 60
    }
}
