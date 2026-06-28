import SwiftUI
import WidgetKit

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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let snapshot {
                    UsageCard(title: "5 小时", window: snapshot.primary)
                    UsageCard(title: "1 周", window: snapshot.secondary)
                    Text("更新于 \(snapshot.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(snapshot.isStale ? .orange : .secondary)
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
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Codex 用量")
            .task {
                refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refresh()
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
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
        syncMessage = "正在连接 Mac mini..."
        CodexUsageSnapshotStore.loadWithDiagnostics { result in
            DispatchQueue.main.async {
                syncMessage = result.message.isEmpty ? "没有可用连接" : result.message
                if snapshot != result.snapshot {
                    snapshot = result.snapshot
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
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
