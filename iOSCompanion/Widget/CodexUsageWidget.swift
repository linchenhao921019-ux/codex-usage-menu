import SwiftUI
import WidgetKit

struct CodexUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: CodexUsageSnapshot?
}

struct CodexUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexUsageEntry {
        CodexUsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) {
        CodexUsageSnapshotStore.load { snapshot in
            completion(CodexUsageEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        CodexUsageSnapshotStore.load { snapshot in
            let entry = CodexUsageEntry(date: Date(), snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct CodexUsageWidgetView: View {
    var entry: CodexUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Codex")
                    .font(.headline)
                Spacer()
                if entry.snapshot?.isStale == true {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }

            if let snapshot = entry.snapshot {
                UsageLine(label: "5h", window: snapshot.primary)
                UsageLine(label: "7d", window: snapshot.secondary)
                Text(snapshot.exportedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                Text("等待 Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct UsageLine: View {
    let label: String
    let window: CodexUsageWindow?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 24, alignment: .leading)

            ProgressView(value: Double(window?.remainingPercent ?? 0), total: 100)
                .tint(color(for: window?.remainingPercent ?? 0))

            Text(window.map { "\($0.remainingPercent)%" } ?? "--")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
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

struct CodexUsageWidget: Widget {
    let kind = "CodexUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexUsageProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 用量")
        .description("显示 Mac 同步来的 Codex 5 小时和 7 天剩余额度。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
