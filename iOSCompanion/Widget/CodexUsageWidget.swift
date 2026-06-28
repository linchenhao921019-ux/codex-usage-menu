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
    @Environment(\.widgetFamily) private var widgetFamily

    var entry: CodexUsageEntry

    var body: some View {
        Group {
            if widgetFamily == .accessoryRectangular {
                compactBody
            } else {
                standardBody
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = entry.snapshot {
                HStack {
                    Text("Codex")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    if snapshot.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    UsageLine(label: "5h", window: snapshot.primary, scale: .standard)
                    UsageLine(label: "7d", window: snapshot.secondary, scale: .standard)
                }
            } else {
                Spacer()
                Text("等待 Mac")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let snapshot = entry.snapshot {
                UsageLine(label: "5h", window: snapshot.primary, scale: .compact)
                UsageLine(label: "7d", window: snapshot.secondary, scale: .compact)
            } else {
                Spacer()
                Text("等待 Mac")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

struct UsageLine: View {
    enum Scale {
        case standard
        case compact

        var labelFont: Font {
            switch self {
            case .standard:
                return .title3.weight(.semibold)
            case .compact:
                return .headline.weight(.semibold)
            }
        }

        var percentFont: Font {
            switch self {
            case .standard:
                return .title2.monospacedDigit().weight(.semibold)
            case .compact:
                return .headline.monospacedDigit().weight(.semibold)
            }
        }

        var labelWidth: CGFloat {
            switch self {
            case .standard:
                return 34
            case .compact:
                return 28
            }
        }

        var percentWidth: CGFloat {
            switch self {
            case .standard:
                return 54
            case .compact:
                return 46
            }
        }

        var barHeight: CGFloat {
            switch self {
            case .standard:
                return 10
            case .compact:
                return 8
            }
        }

        var barWidth: CGFloat {
            switch self {
            case .standard:
                return 42
            case .compact:
                return 34
            }
        }
    }

    let label: String
    let window: CodexUsageWindow?
    let scale: Scale

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(scale.labelFont)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .frame(width: scale.labelWidth, alignment: .leading)

            SegmentedUsageBar(value: window?.remainingPercent ?? 0, width: scale.barWidth, height: scale.barHeight)

            Text(window.map { "\($0.remainingPercent)%" } ?? "--")
                .font(scale.percentFont)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .frame(width: scale.percentWidth, alignment: .trailing)
        }
    }
}

struct SegmentedUsageBar: View {
    private let segmentCount = 5

    let value: Int
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < activeCount ? color(for: value) : .secondary.opacity(0.22))
            }
        }
        .frame(width: width, height: height)
    }

    private var activeCount: Int {
        max(0, min(segmentCount, Int((Double(value) / 20.0).rounded())))
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
