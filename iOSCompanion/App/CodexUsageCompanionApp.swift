import SwiftUI
import Network
import WidgetKit

@MainActor
final class LocalNetworkPermissionPrompter {
    static let shared = LocalNetworkPermissionPrompter()
    private var browser: NWBrowser?

    func request() {
        guard browser == nil else {
            return
        }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { _ in }
        browser.browseResultsChangedHandler = { _, _ in }
        browser.start(queue: .main)
        self.browser = browser
    }
}

final class LocalSnapshotServer: @unchecked Sendable {
    static let shared = LocalSnapshotServer()

    private let queue = DispatchQueue(label: "codex-usage-ios-snapshot-server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var snapshotData: Data?

    func start() {
        queue.async { [weak self] in
            guard let self, listener == nil else {
                return
            }
            guard let port = NWEndpoint.Port(rawValue: 8766),
                  let listener = try? NWListener(using: .tcp, on: port) else {
                return
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        }
    }

    func update(snapshot: CodexUsageSnapshot?) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = snapshot.flatMap { try? encoder.encode($0) }

        lock.lock()
        snapshotData = data
        lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] _, _, _, _ in
            self?.respond(on: connection)
        }
    }

    private func respond(on connection: NWConnection) {
        lock.lock()
        let body = snapshotData
        lock.unlock()

        let status = body == nil ? "404 Not Found" : "200 OK"
        let payload = body ?? Data("{\"ok\":false,\"error\":\"No snapshot\"}".utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json; charset=utf-8",
            "Cache-Control: no-store",
            "Content-Length: \(payload.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(payload)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

@main
struct CodexUsageCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: CodexUsageSnapshot?
    @State private var syncMessage = "正在连接 Mac mini..."
    @State private var sourceMessage = "来源：正在检测"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let snapshot {
                    UsageCard(title: "5 小时", window: snapshot.primary)
                    UsageCard(title: "1 周", window: snapshot.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("更新于 \(snapshot.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(snapshot.isStale ? .orange : .secondary)
                        Text(sourceMessage)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                } else {
                    ContentUnavailableView(
                        "等待同步",
                        systemImage: "wifi",
                        description: Text("确认 iPhone 和 Mac 在同一个 Wi-Fi，并保持 Mac 菜单栏小组件运行。")
                    )
                    Text(syncMessage)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(sourceMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Codex 用量")
            .task {
                LocalSnapshotServer.shared.start()
                LocalNetworkPermissionPrompter.shared.request()
                refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    LocalSnapshotServer.shared.start()
                    LocalNetworkPermissionPrompter.shared.request()
                    refresh()
                }
            }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                refresh()
            }
            .toolbar {
                Button {
                    refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func refresh() {
        syncMessage = "正在连接 Mac mini / MacBook Air..."
        sourceMessage = "来源：正在检测"
        CodexUsageSnapshotStore.loadWithDiagnostics { result in
            DispatchQueue.main.async {
                syncMessage = result.message.isEmpty ? "没有可用连接" : result.message
                sourceMessage = sourceText(for: result)
                if snapshot != result.snapshot {
                    snapshot = result.snapshot
                }
                LocalSnapshotServer.shared.update(snapshot: result.snapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
            }
        }
    }

    private func sourceText(for result: CodexUsageLoadResult) -> String {
        guard let sourceName = result.sourceName else {
            return "来源：暂无"
        }
        return "来源：\(sourceName)"
    }
}

struct UsageCard: View {
    let title: String
    let window: CodexUsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if let window {
                HStack(alignment: .lastTextBaseline) {
                    Text("\(window.remainingPercent)%")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                    Text("剩余")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .tint(color(for: window.remainingPercent))

                if let resetsAt = window.resetsAt {
                    Text("重置：\(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func color(for remainingPercent: Int) -> Color {
        if remainingPercent < 20 {
            return .red
        }
        if remainingPercent <= 60 {
            return .orange
        }
        return .green
    }
}
