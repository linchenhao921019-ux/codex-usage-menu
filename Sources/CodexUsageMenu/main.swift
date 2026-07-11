import AppKit
import Darwin
import Foundation
import Network
import WidgetKit

struct UsageWindow: Codable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Int {
        let remaining = 100 - usedPercent
        return Int(max(0, min(100, remaining)).rounded())
    }

    var label: String {
        if abs(Double(windowMinutes) - 300) <= 15 {
            return "5 小时"
        }
        if abs(Double(windowMinutes) - 10_080) <= 504 {
            return "1 周"
        }
        if abs(Double(windowMinutes) - 1_440) <= 72 {
            return "1 天"
        }
        if windowMinutes >= 60 {
            return "\(windowMinutes / 60) 小时"
        }
        return "\(windowMinutes) 分钟"
    }

    var compactLabel: String {
        if abs(Double(windowMinutes) - 300) <= 15 {
            return "5h"
        }
        if abs(Double(windowMinutes) - 10_080) <= 504 {
            return "7d"
        }
        if abs(Double(windowMinutes) - 1_440) <= 72 {
            return "1d"
        }
        if windowMinutes >= 60 {
            return "\(windowMinutes / 60)h"
        }
        return "\(windowMinutes)m"
    }
}

struct UsageCredits: Codable, Equatable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: Double?
}

struct UsageSnapshot: Codable {
    let timestamp: Date
    let sourcePath: String
    let limitID: String?
    let limitName: String?
    let planType: String?
    let credits: UsageCredits?
    let primary: UsageWindow?
    let secondary: UsageWindow?
}

struct SyncUsageWindow: Codable {
    let label: String
    let compactLabel: String
    let usedPercent: Double
    let remainingPercent: Int
    let windowMinutes: Int
    let resetsAt: Date?
}

struct SyncUsageSnapshot: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let snapshotTimestamp: Date
    let limitID: String?
    let limitName: String?
    let planType: String?
    let credits: UsageCredits?
    let primary: SyncUsageWindow?
    let secondary: SyncUsageWindow?

    init(snapshot: UsageSnapshot, exportedAt: Date = Date()) {
        schemaVersion = 2
        self.exportedAt = exportedAt
        snapshotTimestamp = snapshot.timestamp
        limitID = snapshot.limitID
        limitName = snapshot.limitName
        planType = snapshot.planType
        credits = snapshot.credits
        primary = snapshot.primary.map(SyncUsageWindow.init)
        secondary = snapshot.secondary.map(SyncUsageWindow.init)
    }
}

extension SyncUsageWindow {
    init(window: UsageWindow) {
        label = window.label
        compactLabel = window.compactLabel
        usedPercent = window.usedPercent
        remainingPercent = window.remainingPercent
        windowMinutes = window.windowMinutes
        resetsAt = window.resetsAt
    }
}

extension UsageWindow {
    init(syncWindow: SyncUsageWindow) {
        usedPercent = syncWindow.usedPercent
        windowMinutes = syncWindow.windowMinutes
        resetsAt = syncWindow.resetsAt
    }
}

extension UsageSnapshot {
    init(syncSnapshot: SyncUsageSnapshot, sourceURL: URL) {
        timestamp = syncSnapshot.snapshotTimestamp
        sourcePath = sourceURL.absoluteString
        limitID = syncSnapshot.limitID
        limitName = syncSnapshot.limitName
        planType = syncSnapshot.planType
        credits = syncSnapshot.credits
        primary = syncSnapshot.primary.map(UsageWindow.init(syncWindow:))
        secondary = syncSnapshot.secondary.map(UsageWindow.init(syncWindow:))
    }
}

enum CodexApplication {
    static let bundleIdentifier = "com.openai.codex"

    static func installedURL(workspace: NSWorkspace = .shared) -> URL? {
        if let runningURL = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .bundleURL {
            return runningURL
        }

        if let registeredURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return registeredURL
        }

        let candidates = [
            "/Applications/ChatGPT.app",
            "/Applications/Codex.app",
            NSString(string: "~/Applications/ChatGPT.app").expandingTildeInPath,
            NSString(string: "~/Applications/Codex.app").expandingTildeInPath
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func open(workspace: NSWorkspace = .shared) {
        guard let url = installedURL(workspace: workspace) else {
            NSSound.beep()
            return
        }
        workspace.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

enum RefreshSettings {
    static var interval: TimeInterval {
        guard let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"],
              let value = TimeInterval(rawValue) else {
            return 60
        }
        return min(300, max(2, value))
    }

    static var intervalLabel: String {
        let seconds = Int(interval.rounded())
        return "\(seconds) 秒"
    }
}

enum LiveRateLimitReader {
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var response: Data?

        func append(_ data: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? Int) == 2 else {
                    continue
                }
                response = line
                return true
            }
            return false
        }

        func get() -> Data? {
            lock.lock()
            defer { lock.unlock() }
            return response
        }
    }

    static func latestSnapshot(timeout: TimeInterval = 8) -> UsageSnapshot? {
        guard let executableURL else {
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let responseBox = ResponseBox()
        let responseReady = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else {
                return
            }
            if responseBox.append(data) {
                responseReady.signal()
            }
        }

        do {
            try process.run()
            let requests = [
                #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-usage-menu","version":"1.2"},"capabilities":{"experimentalApi":true}}}"#,
                #"{"method":"initialized"}"#,
                #"{"id":2,"method":"account/rateLimits/read","params":null}"#
            ].joined(separator: "\n") + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))
            _ = responseReady.wait(timeout: .now() + timeout)
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }

        guard let data = responseBox.get() else {
            return nil
        }
        return snapshot(fromResponseData: data)
    }

    static func snapshot(fromResponseData data: Data, fetchedAt: Date = Date()) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            return nil
        }

        let rateLimits: [String: Any]?
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            rateLimits = codex
        } else {
            rateLimits = result["rateLimits"] as? [String: Any]
        }

        guard let rateLimits,
              let primary = window(rateLimits["primary"]),
              let secondary = window(rateLimits["secondary"]) else {
            return nil
        }

        return UsageSnapshot(
            timestamp: fetchedAt,
            sourcePath: "codex-app-server://account/rateLimits/read",
            limitID: rateLimits["limitId"] as? String,
            limitName: rateLimits["limitName"] as? String,
            planType: rateLimits["planType"] as? String,
            credits: credits(rateLimits["credits"]),
            primary: primary,
            secondary: secondary
        )
    }

    private static var executableURL: URL? {
        var candidates: [URL] = []
        if let appURL = CodexApplication.installedURL() {
            candidates.append(appURL.appendingPathComponent("Contents/Resources/codex"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".local/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = number(object["usedPercent"]),
              let windowMinutes = number(object["windowDurationMins"]) else {
            return nil
        }
        return UsageWindow(
            usedPercent: usedPercent,
            windowMinutes: Int(windowMinutes),
            resetsAt: number(object["resetsAt"]).map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func credits(_ value: Any?) -> UsageCredits? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        return UsageCredits(
            hasCredits: object["hasCredits"] as? Bool,
            unlimited: object["unlimited"] as? Bool,
            balance: number(object["balance"])
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

enum UsageSyncExporter {
    static let relativeSnapshotPath = "CodexUsage/codex-usage-snapshot.json"

    static var visibleICloudURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent(relativeSnapshotPath)
    }

    static var configuredContainerURL: URL? {
        guard let containerID = ProcessInfo.processInfo.environment["CODEX_USAGE_ICLOUD_CONTAINER_ID"],
              containerID.isEmpty == false else {
            return nil
        }
        let folderName = containerID.replacingOccurrences(of: ".", with: "~")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(relativeSnapshotPath)
    }

    static var customExportURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["CODEX_USAGE_EXPORT_PATH"],
              path.isEmpty == false else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static var displayURL: URL {
        customExportURL ?? configuredContainerURL ?? visibleICloudURL
    }

    static var widgetContainerURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.local.codexusage.menu.widget/Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(relativeSnapshotPath)
    }

    static func export(snapshot: UsageSnapshot) throws {
        try exportForWidget(snapshot: snapshot)

        let payload = SyncUsageSnapshot(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        var destinations = [visibleICloudURL]
        if let configuredContainerURL, configuredContainerURL != visibleICloudURL {
            destinations.append(configuredContainerURL)
        }
        if let customExportURL, destinations.contains(customExportURL) == false {
            destinations.append(customExportURL)
        }

        for url in destinations {
            try write(data: data, to: url)
        }
    }

    static func exportForWidget(snapshot: UsageSnapshot) throws {
        let payload = SyncUsageSnapshot(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try write(data: data, to: widgetContainerURL)
    }

    private static func write(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }
}

final class SnapshotHTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "codex-usage-snapshot-http")
    private var listener: NWListener?

    var localURLString: String {
        SnapshotProvider.localServerURLString
    }

    func start() {
        guard listener == nil else {
            return
        }
        do {
            let listener = try NWListener(using: .tcp, on: 8765)
            let serviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            listener.service = NWListener.Service(name: "Codex Usage \(serviceName)", type: "_http._tcp")
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            fputs("Codex usage snapshot server failed: \(error)\n", stderr)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: String) -> Data {
        if request.hasPrefix("GET /snapshot ") || request.hasPrefix("GET /snapshot?") || request.hasPrefix("GET / ") {
            return snapshotResponse()
        }
        return httpResponse(
            status: "404 Not Found",
            contentType: "application/json; charset=utf-8",
            body: Data("{\"ok\":false,\"error\":\"Not found\"}".utf8)
        )
    }

    private func snapshotResponse() -> Data {
        guard let snapshot = SnapshotProvider.latestSnapshot() else {
            return httpResponse(
                status: "404 Not Found",
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":false,\"error\":\"No Codex usage snapshot found\"}".utf8)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let body = try encoder.encode(SyncUsageSnapshot(snapshot: snapshot))
            return httpResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: body)
        } catch {
            return httpResponse(
                status: "500 Internal Server Error",
                contentType: "application/json; charset=utf-8",
                body: Data("{\"ok\":false,\"error\":\"Encode failed\"}".utf8)
            )
        }
    }

    private func httpResponse(status: String, contentType: String, body: Data) -> Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status)\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Cache-Control: no-store\r\n".utf8))
        response.append(Data("Access-Control-Allow-Origin: *\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        return response
    }
}

enum AppFont {
    static func regular(_ size: CGFloat) -> NSFont {
        named(size: size, names: [
            "GoogleSansCode-Regular",
            "Google Sans Code Regular",
            "Google Sans Code"
        ]) ?? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    static func medium(_ size: CGFloat) -> NSFont {
        named(size: size, names: [
            "GoogleSansCode-Medium",
            "Google Sans Code Medium",
            "GoogleSansCode-Regular",
            "Google Sans Code"
        ]) ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    static func semibold(_ size: CGFloat) -> NSFont {
        named(size: size, names: [
            "GoogleSansCode-Medium",
            "Google Sans Code Medium",
            "GoogleSansCode-Regular",
            "Google Sans Code Regular",
            "Google Sans Code"
        ]) ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    private static func named(size: CGFloat, names: [String]) -> NSFont? {
        for name in names {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return nil
    }
}

enum UsageReader {
    static func latestSnapshot() -> UsageSnapshot? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions"),
            home.appendingPathComponent(".codex/archived_sessions")
        ]

        let files = roots.flatMap { jsonlFiles(under: $0) }
            .compactMap { url -> (URL, Date)? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(30)

        var best: UsageSnapshot?
        for (url, _) in files {
            guard let snapshot = latestSnapshot(in: url) else {
                continue
            }
            if best == nil || snapshot.timestamp > best!.timestamp {
                best = snapshot
            }
        }
        return best
    }

    private static func jsonlFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            urls.append(url)
        }
        return urls
    }

    private static func latestSnapshot(in file: URL) -> UsageSnapshot? {
        guard let text = try? recentText(in: file) else {
            return nil
        }

        return snapshot(fromJSONL: text, sourcePath: file.path)
    }

    static func snapshot(fromJSONL text: String, sourcePath: String = "fixture.jsonl") -> UsageSnapshot? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).reversed()
        for line in lines where line.contains("\"rate_limits\"") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  isTokenCountRecord(object),
                  let rateLimits = rateLimits(in: object),
                  let timestamp = parseTimestamp(object["timestamp"]) else {
                continue
            }

            let primary = parseWindow(rateLimits["primary"])
            let secondary = parseWindow(rateLimits["secondary"])
            if primary == nil && secondary == nil {
                continue
            }

            return UsageSnapshot(
                timestamp: timestamp,
                sourcePath: sourcePath,
                limitID: rateLimits["limit_id"] as? String,
                limitName: rateLimits["limit_name"] as? String,
                planType: rateLimits["plan_type"] as? String,
                credits: parseCredits(rateLimits["credits"]),
                primary: primary,
                secondary: secondary
            )
        }
        return nil
    }

    private static func recentText(in file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let maxBytes: UInt64 = 8 * 1024 * 1024
        let offset = size > maxBytes ? size - maxBytes : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        guard var text = String(data: data, encoding: .utf8) else {
            return ""
        }
        if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
            text.removeSubrange(text.startIndex...firstNewline)
        }
        return text
    }

    private static func isTokenCountRecord(_ object: [String: Any]) -> Bool {
        if object["rate_limits"] != nil {
            return true
        }
        if let payload = object["payload"] as? [String: Any],
           payload["rate_limits"] != nil,
           payload["type"] as? String == "token_count" {
            return true
        }
        return false
    }

    private static func rateLimits(in object: [String: Any]) -> [String: Any]? {
        if let rateLimits = object["rate_limits"] as? [String: Any] {
            return rateLimits
        }
        if let payload = object["payload"] as? [String: Any],
           let rateLimits = payload["rate_limits"] as? [String: Any] {
            return rateLimits
        }
        return nil
    }

    private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = number(object["used_percent"]),
              let windowMinutes = number(object["window_minutes"]).map({ Int($0) }) else {
            return nil
        }
        let resetsAt = number(object["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }

    private static func parseCredits(_ value: Any?) -> UsageCredits? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        return UsageCredits(
            hasCredits: boolean(object["has_credits"]),
            unlimited: boolean(object["unlimited"]),
            balance: number(object["balance"])
        )
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let value = value as? String else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum RemoteSnapshotReader {
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?

        func set(_ value: Data?) {
            lock.lock()
            data = value
            lock.unlock()
        }

        func get() -> Data? {
            lock.lock()
            let value = data
            lock.unlock()
            return value
        }
    }

    private static var timeout: TimeInterval {
        guard let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REMOTE_TIMEOUT_SECONDS"],
              let value = TimeInterval(rawValue) else {
            return 1.5
        }
        return min(max(value, 0.5), 10)
    }

    static func latestSnapshot(from url: URL) -> UsageSnapshot? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false

        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        let responseBox = ResponseBox()
        let task = session.dataTask(with: request) { data, _, _ in
            responseBox.set(data)
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout + 0.2)
        if waitResult == .timedOut {
            task.cancel()
            session.invalidateAndCancel()
            return nil
        }
        session.finishTasksAndInvalidate()

        guard let data = responseBox.get() else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let syncSnapshot = try? decoder.decode(SyncUsageSnapshot.self, from: data) else {
            return nil
        }
        return UsageSnapshot(syncSnapshot: syncSnapshot, sourceURL: url)
    }
}

enum SnapshotDataSource {
    case liveCodex
    case localAuthority
    case remoteAuthority(URL)
    case localFallback

    var label: String {
        switch self {
        case .liveCodex:
            return "Codex 实时"
        case .localAuthority:
            return "本机"
        case .remoteAuthority:
            return "远程 Mac"
        case .localFallback:
            return "本机备用"
        }
    }
}

struct SnapshotProviderResult {
    let snapshot: UsageSnapshot
    let dataSource: SnapshotDataSource
    let remoteUnavailable: Bool
}

enum RefreshReason: Sendable, Equatable {
    case automatic
    case menuOpened
    case manual

    var priority: Int {
        switch self {
        case .automatic: return 0
        case .menuOpened: return 1
        case .manual: return 2
        }
    }
}

struct PendingRefreshRequest: Equatable {
    let updateMenu: Bool
    let reason: RefreshReason
}

struct RefreshRequestQueue {
    private(set) var pending: PendingRefreshRequest?

    mutating func enqueue(updateMenu: Bool, reason: RefreshReason) {
        guard reason != .automatic else {
            return
        }

        guard let current = pending else {
            pending = PendingRefreshRequest(updateMenu: updateMenu, reason: reason)
            return
        }

        let preferredReason = reason.priority > current.reason.priority ? reason : current.reason
        pending = PendingRefreshRequest(
            updateMenu: current.updateMenu || updateMenu,
            reason: preferredReason
        )
    }

    mutating func take() -> PendingRefreshRequest? {
        defer { pending = nil }
        return pending
    }
}

enum SnapshotProvider {
    static var authorityHost: String {
        nonEmptyEnvironmentValue("CODEX_USAGE_AUTHORITY_HOST") ?? defaultAuthorityHost
    }

    static var remoteSnapshotURL: URL {
        if let value = nonEmptyEnvironmentValue("CODEX_USAGE_SNAPSHOT_URL"),
           let url = URL(string: value) {
            return url
        }
        return URL(string: "http://\(authorityHost).local:8765/snapshot")!
    }

    static var isAuthorityHost: Bool {
        let authority = normalizedHostName(authorityHost)
        return localHostCandidates.contains(authority)
    }

    static var allowsLocalFallback: Bool {
        nonEmptyEnvironmentValue("CODEX_USAGE_DISABLE_LOCAL_FALLBACK") != "1"
    }

    static var sourceLabel: String {
        isAuthorityHost ? "本机" : "远程 Mac"
    }

    static var localServerURLString: String {
        let hostName = ProcessInfo.processInfo.hostName
        let host = hostName.isEmpty ? "localhost" : hostName
        let localHost = host.contains(".") ? host : "\(host).local"
        return "http://\(localHost):8765/snapshot"
    }

    static func latestSnapshot() -> UsageSnapshot? {
        latestSnapshotResult()?.snapshot
    }

    static func latestSnapshotResult() -> SnapshotProviderResult? {
        if isAuthorityHost {
            if let snapshot = LiveRateLimitReader.latestSnapshot() {
                return SnapshotProviderResult(
                    snapshot: snapshot,
                    dataSource: .liveCodex,
                    remoteUnavailable: false
                )
            }
            guard let snapshot = UsageReader.latestSnapshot() else {
                return nil
            }
            return SnapshotProviderResult(
                snapshot: snapshot,
                dataSource: .localAuthority,
                remoteUnavailable: false
            )
        }

        if let snapshot = RemoteSnapshotReader.latestSnapshot(from: remoteSnapshotURL) {
            return SnapshotProviderResult(
                snapshot: snapshot,
                dataSource: .remoteAuthority(remoteSnapshotURL),
                remoteUnavailable: false
            )
        }

        if allowsLocalFallback, let snapshot = UsageReader.latestSnapshot() {
            return SnapshotProviderResult(
                snapshot: snapshot,
                dataSource: .localFallback,
                remoteUnavailable: true
            )
        }
        return nil
    }

    private static var localHostCandidates: Set<String> {
        Set(localHostNames.map(normalizedHostName))
    }

    private static var defaultAuthorityHost: String {
        localHostNames.first ?? "localhost"
    }

    private static var localHostNames: [String] {
        let values: [String?] = [
            ProcessInfo.processInfo.hostName,
            Host.current().name,
            Host.current().localizedName
        ]

        return values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmed.isEmpty == false else {
                return nil
            }
            return hostWithoutLocalSuffix(trimmed)
        }
    }

    private static func nonEmptyEnvironmentValue(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key],
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return value
    }

    private static func normalizedHostName(_ value: String) -> String {
        let withoutLocalSuffix = hostWithoutLocalSuffix(value).lowercased()
        return withoutLocalSuffix.filter { $0.isLetter || $0.isNumber }
    }

    private static func hostWithoutLocalSuffix(_ value: String) -> String {
        let lowercased = value.lowercased()
        guard lowercased.hasSuffix(".local") else {
            return value
        }
        return String(value.dropLast(".local".count))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusView = StatusBarUsageView()
    private let snapshotServer = SnapshotHTTPServer()
    private var timer: Timer?
    private var snapshot: UsageSnapshot?
    private var dataSource: SnapshotDataSource?
    private var sourceUnavailable = false
    private var isRefreshing = false
    private var refreshRequestQueue = RefreshRequestQueue()
    private var lastRefreshAt: Date?
    private var refreshStatus: String?
    private var instanceLockFileDescriptor: Int32 = -1
    private weak var visibleMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard prepareSingleRunningInstance() else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        snapshotServer.start()
        refresh()
        scheduleStartupRefreshes()

        let timer = Timer(timeInterval: RefreshSettings.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func prepareSingleRunningInstance() -> Bool {
        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return false
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentPID = NSRunningApplication.current.processIdentifier
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let currentIsInstalled = isInstalledAppURL(currentBundleURL)
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        if currentIsInstalled {
            let duplicatePeers = peers.filter { peer in
                guard let peerURL = peer.bundleURL?.standardizedFileURL else {
                    return false
                }
                return peerURL.path != currentBundleURL.path
            }
            terminate(peers: duplicatePeers)
            return true
        }

        if peers.contains(where: { isInstalledAppURL($0.bundleURL?.standardizedFileURL) }) || isSnapshotServerRunning() {
            NSApp.terminate(nil)
            return false
        }

        return true
    }

    private func acquireInstanceLock() -> Bool {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.local.codexusage.menu.lock")
        let fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            return false
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            return false
        }

        instanceLockFileDescriptor = fileDescriptor
        return true
    }

    private func isInstalledAppURL(_ url: URL?) -> Bool {
        guard let path = url?.path else {
            return false
        }

        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path

        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications + "/")
    }

    private func isSnapshotServerRunning() -> Bool {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else {
            return false
        }
        defer { close(socketFileDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(8765).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketFileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func terminate(peers: [NSRunningApplication]) {
        guard peers.isEmpty == false else {
            return
        }

        for peer in peers {
            peer.terminate()
        }

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline && peers.contains(where: { $0.isTerminated == false }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for peer in peers where peer.isTerminated == false {
            peer.forceTerminate()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        statusItem.length = 122
        button.image = nil
        button.imagePosition = .noImage
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.alignment = .left
        button.font = AppFont.medium(11)

        statusView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusView)
        NSLayoutConstraint.activate([
            statusView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
            statusView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
            statusView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            statusView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc private func refreshNow() {
        refresh(reason: .manual)
        statusView.needsDisplay = true
        statusItem.button?.needsDisplay = true
    }

    private func scheduleStartupRefreshes() {
        for delay in [2.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh(updateMenu: Bool = true, reason: RefreshReason = .automatic) {
        guard isRefreshing == false else {
            refreshRequestQueue.enqueue(updateMenu: updateMenu, reason: reason)
            return
        }
        isRefreshing = true
        let previousSnapshotTimestamp = snapshot?.timestamp
        if reason == .manual {
            refreshStatus = "正在读取最新记录..."
        }
        if updateMenu {
            render(updateMenu: true)
        }

        Task.detached(priority: .utility) { [weak self] in
            let result = SnapshotProvider.latestSnapshotResult()
            let isAuthorityHost = SnapshotProvider.isAuthorityHost
            if let snapshot = result?.snapshot {
                try? UsageSyncExporter.exportForWidget(snapshot: snapshot)
            }
            if let snapshot = result?.snapshot, isAuthorityHost {
                try? UsageSyncExporter.export(snapshot: snapshot)
            }

            await self?.finishRefresh(
                result: result,
                isAuthorityHost: isAuthorityHost,
                updateMenu: updateMenu,
                previousSnapshotTimestamp: previousSnapshotTimestamp,
                reason: reason
            )
        }
    }

    private func finishRefresh(
        result: SnapshotProviderResult?,
        isAuthorityHost: Bool,
        updateMenu: Bool,
        previousSnapshotTimestamp: Date?,
        reason: RefreshReason
    ) {
        isRefreshing = false
        lastRefreshAt = Date()
        sourceUnavailable = result == nil || result?.remoteUnavailable == true
        if let result {
            snapshot = result.snapshot
            dataSource = result.dataSource
        } else if isAuthorityHost {
            snapshot = nil
            dataSource = nil
        }
        updateRefreshStatus(
            result: result,
            previousSnapshotTimestamp: previousSnapshotTimestamp,
            reason: reason
        )

        render(updateMenu: updateMenu)
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageMacWidget")

        if let pendingRequest = refreshRequestQueue.take() {
            refresh(updateMenu: pendingRequest.updateMenu, reason: pendingRequest.reason)
        }
    }

    private func updateRefreshStatus(
        result: SnapshotProviderResult?,
        previousSnapshotTimestamp: Date?,
        reason: RefreshReason
    ) {
        guard reason == .manual else {
            return
        }

        guard let result else {
            refreshStatus = "没有读到 Codex 用量记录"
            return
        }

        if let previousSnapshotTimestamp,
           result.snapshot.timestamp <= previousSnapshotTimestamp {
            refreshStatus = "暂无新数据，最新记录 \(elapsedTime(result.snapshot.timestamp))"
        } else {
            refreshStatus = "已更新到 \(formatRefreshTime(result.snapshot.timestamp))"
        }
    }

    private func render(updateMenu: Bool = true) {
        statusView.update(snapshot: snapshot)
        if updateMenu {
            if let visibleMenu {
                populate(visibleMenu)
            } else {
                statusItem.menu = makeMenu()
            }
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        visibleMenu = menu
        populate(menu)
        refresh(updateMenu: true, reason: .menuOpened)
    }

    func menuDidClose(_ menu: NSMenu) {
        if visibleMenu === menu {
            visibleMenu = nil
        }
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(viewItem(HeaderView()))

        if let snapshot {
            if let primary = snapshot.primary {
                menu.addItem(viewItem(UsageLimitRowView(window: primary)))
            }
            if let secondary = snapshot.secondary {
                menu.addItem(viewItem(UsageLimitRowView(window: secondary)))
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(disabledItem("数据：\(elapsedTime(snapshot.timestamp))"))
            menu.addItem(disabledItem("来源：\(compactSourceLabel(dataSource))"))
            if let planType = snapshot.planType {
                menu.addItem(disabledItem("方案：\(compactPlanLabel(planType))"))
            }
            if let creditLabel = creditStatusLabel(snapshot.credits) {
                menu.addItem(disabledItem(creditLabel))
            }
            if let refreshStatus {
                menu.addItem(disabledItem("状态：\(refreshStatus)"))
            }
        } else {
            if SnapshotProvider.isAuthorityHost {
                menu.addItem(disabledItem("暂无 Codex 用量记录"))
            } else {
                menu.addItem(disabledItem("暂无数据：远程 Mac 不可达"))
            }
            if let refreshStatus {
                menu.addItem(disabledItem("状态：\(refreshStatus)"))
            }
        }

        menu.addItem(NSMenuItem.separator())
        if isRefreshing {
            menu.addItem(disabledItem("正在刷新..."))
        } else {
            menu.addItem(actionItem("刷新", selector: #selector(refreshNow)))
        }
        menu.addItem(actionItem("打开同步文件夹", selector: #selector(openSyncFolder)))
        menu.addItem(actionItem("打开 Codex", selector: #selector(openCodex)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("退出", selector: #selector(quit)))
    }

    private func compactSourceLabel(_ source: SnapshotDataSource?) -> String {
        switch source {
        case .liveCodex:
            return "Codex 实时"
        case .localAuthority:
            return "本机"
        case .remoteAuthority:
            return "远程 Mac"
        case .localFallback:
            return "本机备用"
        case nil:
            return SnapshotProvider.isAuthorityHost ? "本机" : "远程 Mac"
        }
    }

    private func compactPlanLabel(_ plan: String) -> String {
        let trimmed = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return plan
        }
        return String(first).uppercased() + trimmed.dropFirst().lowercased()
    }

    private func creditStatusLabel(_ credits: UsageCredits?) -> String? {
        guard let credits else {
            return nil
        }
        if credits.unlimited == true {
            return "附加额度：无限"
        }
        if let balance = credits.balance {
            return "附加额度：余额 \(balance.formatted(.number.precision(.fractionLength(0...2))))"
        }
        if credits.hasCredits == true {
            return "附加额度：可用"
        }
        if credits.hasCredits == false {
            return "附加额度：未启用"
        }
        return nil
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppFont.regular(13),
                .foregroundColor: NSColor.labelColor
            ]
        )
        return item
    }

    private func actionItem(_ title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openCodex() {
        CodexApplication.open()
    }

    @objc private func openSyncFolder() {
        let folder = UsageSyncExporter.displayURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folder)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class HeaderView: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 42))
        wantsLayer = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "剩余用量")
        title.font = AppFont.medium(16)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(title)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class StatusBarUsageView: NSView {
    private let primaryRow = StatusBarUsageRowView()
    private let secondaryRow = StatusBarUsageRowView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 106, height: 22))
        wantsLayer = true

        primaryRow.translatesAutoresizingMaskIntoConstraints = false
        secondaryRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(primaryRow)
        addSubview(secondaryRow)

        NSLayoutConstraint.activate([
            primaryRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            primaryRow.topAnchor.constraint(equalTo: topAnchor),
            primaryRow.heightAnchor.constraint(equalToConstant: 11),

            secondaryRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            secondaryRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            secondaryRow.topAnchor.constraint(equalTo: primaryRow.bottomAnchor),
            secondaryRow.heightAnchor.constraint(equalToConstant: 11)
        ])

        update(snapshot: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(snapshot: UsageSnapshot?) {
        if let primary = snapshot?.primary {
            primaryRow.update(window: primary)
        } else {
            primaryRow.updatePlaceholder(label: "5h")
        }

        if let secondary = snapshot?.secondary {
            secondaryRow.update(window: secondary)
        } else {
            secondaryRow.updatePlaceholder(label: "7d")
        }
    }
}

final class StatusBarUsageRowView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let dots = DotStripView()
    private let percent = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 106, height: 11))
        wantsLayer = true

        label.font = AppFont.medium(10.5)
        label.textColor = .white
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false

        dots.translatesAutoresizingMaskIntoConstraints = false

        percent.font = AppFont.medium(10.5)
        percent.alignment = .right
        percent.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(dots)
        addSubview(percent)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 24),

            dots.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            dots.centerYAnchor.constraint(equalTo: centerYAnchor),
            dots.widthAnchor.constraint(equalToConstant: 34),
            dots.heightAnchor.constraint(equalToConstant: 8),

            percent.leadingAnchor.constraint(equalTo: dots.trailingAnchor, constant: 8),
            percent.trailingAnchor.constraint(equalTo: trailingAnchor),
            percent.centerYAnchor.constraint(equalTo: centerYAnchor),
            percent.widthAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(window: UsageWindow) {
        let remaining = window.remainingPercent
        label.stringValue = window.compactLabel
        percent.stringValue = "\(remaining)%"
        percent.textColor = .white
        dots.update(remainingPercent: remaining)
    }

    func updatePlaceholder(label placeholder: String) {
        label.stringValue = placeholder
        percent.stringValue = "--"
        percent.textColor = .white.withAlphaComponent(0.72)
        dots.update(remainingPercent: 0)
    }
}

final class DotStripView: NSView {
    private var activeCount = 0
    private var activeColor = NSColor.systemGreen

    func update(remainingPercent: Int) {
        activeCount = max(0, min(5, Int((Double(remainingPercent) / 20.0).rounded())))
        activeColor = progressColor(for: remainingPercent)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillWidth: CGFloat = 4.8
        let pillHeight: CGFloat = 8.2
        let gap = max(0, (bounds.width - pillWidth * 5) / 4)
        let y = (bounds.height - pillHeight) / 2

        for index in 0..<5 {
            let x = CGFloat(index) * (pillWidth + gap)
            let rect = NSRect(x: x, y: y, width: pillWidth, height: pillHeight)
            let radius = pillWidth / 2
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            let color = index < activeCount ? activeColor : NSColor.secondaryLabelColor.withAlphaComponent(0.35)
            color.setFill()
            path.fill()
        }
    }
}

final class UsageLimitRowView: NSView {
    private let progressView: ProgressBarView

    init(window: UsageWindow) {
        progressView = ProgressBarView(value: Double(window.remainingPercent) / 100.0)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        wantsLayer = true

        let nameLabel = NSTextField(labelWithString: window.label)
        nameLabel.font = AppFont.medium(14)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let percentLabel = NSTextField(labelWithString: "\(window.remainingPercent)%")
        percentLabel.font = AppFont.medium(15)
        percentLabel.textColor = progressColor(for: window.remainingPercent)
        percentLabel.alignment = .right
        percentLabel.translatesAutoresizingMaskIntoConstraints = false

        let resetLabel = NSTextField(labelWithString: window.resetsAt.map(formatReset) ?? "--")
        resetLabel.font = AppFont.regular(13)
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.alignment = .right
        resetLabel.translatesAutoresizingMaskIntoConstraints = false

        progressView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLabel)
        addSubview(percentLabel)
        addSubview(resetLabel)
        addSubview(progressView)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.widthAnchor.constraint(equalToConstant: 80),

            percentLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 12),
            percentLabel.topAnchor.constraint(equalTo: nameLabel.topAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 58),

            resetLabel.leadingAnchor.constraint(equalTo: percentLabel.trailingAnchor, constant: 14),
            resetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            resetLabel.firstBaselineAnchor.constraint(equalTo: percentLabel.firstBaselineAnchor),

            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            progressView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 11),
            progressView.heightAnchor.constraint(equalToConstant: 7)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ProgressBarView: NSView {
    private let value: Double

    init(value: Double) {
        self.value = max(0, min(1, value))
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0, dy: 0)
        let radius = rect.height / 2
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.separatorColor.withAlphaComponent(0.42).setFill()
        trackPath.fill()

        guard value > 0 else {
            return
        }

        let fillWidth = max(rect.height, rect.width * value)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        progressColor(for: Int((value * 100).rounded())).setFill()
        fillPath.fill()
    }
}

private func progressColor(for remainingPercent: Int) -> NSColor {
    if remainingPercent < 20 {
        return NSColor.systemRed
    }
    if remainingPercent <= 60 {
        return NSColor.systemOrange
    }
    return NSColor.systemGreen
}

private func formatReset(_ date: Date) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
    } else if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
        formatter.dateFormat = "M月d日"
    } else {
        formatter.dateFormat = "yyyy/M/d"
    }
    return formatter.string(from: date)
}

private func formatRefreshTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func elapsedTime(_ date: Date) -> String {
    let elapsed = max(0, Date().timeIntervalSince(date))
    if elapsed < 1 {
        return "刚刚"
    }
    if elapsed < 60 {
        return "\(Int(elapsed.rounded()))秒前"
    }
    if elapsed < 3_600 {
        return "\(Int((elapsed / 60).rounded()))分钟前"
    }
    if elapsed < 86_400 {
        return "\(Int((elapsed / 3_600).rounded()))小时前"
    }
    return relativeTime(date)
}

private func printSnapshotJSON() {
    guard let snapshot = SnapshotProvider.latestSnapshot() else {
        print("{\"ok\":false,\"error\":\"No Codex usage snapshot found\"}")
        return
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let value: any Encodable = CommandLine.arguments.contains("--sync-json")
        ? SyncUsageSnapshot(snapshot: snapshot)
        : snapshot
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

if CommandLine.arguments.contains("--json") || CommandLine.arguments.contains("--sync-json") {
    printSnapshotJSON()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
