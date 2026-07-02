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
    @Environment(\.colorScheme) private var colorScheme

    var entry: CodexUsageEntry

    var body: some View {
        Group {
            if widgetFamily == .accessoryRectangular {
                compactBody
            } else {
                standardBody
            }
        }
        .containerBackground(for: .widget) {
            BrandWidgetBackground()
        }
        .foregroundStyle(BrandWidgetPalette.primaryText(for: colorScheme))
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
                    .foregroundStyle(BrandWidgetPalette.secondaryText(for: colorScheme))
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
                    .foregroundStyle(BrandWidgetPalette.secondaryText(for: colorScheme))
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

struct BrandWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            darkBackground
        } else {
            lightBackground
        }
    }

    private var lightBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.91, green: 0.98, blue: 1.00), location: 0.00),
                .init(color: Color(red: 0.96, green: 1.00, blue: 0.98), location: 0.44),
                .init(color: Color(red: 0.94, green: 0.92, blue: 1.00), location: 1.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.78),
                    Color.white.opacity(0.28),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.46, blue: 1.00).opacity(0.18),
                    Color(red: 0.15, green: 0.82, blue: 0.70).opacity(0.08),
                    Color.clear
                ],
                startPoint: .bottomTrailing,
                endPoint: .topLeading
            )
        }
    }

    private var darkBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.03, green: 0.09, blue: 0.14), location: 0.00),
                .init(color: Color(red: 0.04, green: 0.18, blue: 0.22), location: 0.48),
                .init(color: Color(red: 0.15, green: 0.12, blue: 0.27), location: 1.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.86, blue: 0.92).opacity(0.28),
                    Color(red: 0.16, green: 0.72, blue: 0.58).opacity(0.10),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.42, blue: 1.00).opacity(0.30),
                    Color(red: 0.15, green: 0.78, blue: 0.64).opacity(0.10),
                    Color.clear
                ],
                startPoint: .bottomTrailing,
                endPoint: .topLeading
            )
        }
    }
}

enum BrandWidgetPalette {
    static func primaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.92, green: 0.99, blue: 1.00)
            : Color(red: 0.02, green: 0.04, blue: 0.05)
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.84, blue: 0.88)
            : Color(red: 0.34, green: 0.41, blue: 0.44)
    }

    static func activeUsage(for remainingPercent: Int, colorScheme: ColorScheme) -> Color {
        if remainingPercent < 20 {
            return colorScheme == .dark
                ? Color(red: 1.00, green: 0.36, blue: 0.40)
                : .red
        }
        if remainingPercent <= 60 {
            return colorScheme == .dark
                ? Color(red: 1.00, green: 0.64, blue: 0.23)
                : .orange
        }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.92, blue: 0.60)
            : Color(red: 0.12, green: 0.78, blue: 0.38)
    }

    static func inactiveUsage(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.74, green: 0.92, blue: 0.94).opacity(0.22)
            : Color(red: 0.26, green: 0.34, blue: 0.39).opacity(0.12)
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
    @Environment(\.colorScheme) private var colorScheme

    private let segmentCount = 5

    let value: Int
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < activeCount ? BrandWidgetPalette.activeUsage(for: value, colorScheme: colorScheme) : BrandWidgetPalette.inactiveUsage(for: colorScheme))
            }
        }
        .frame(width: width, height: height)
    }

    private var activeCount: Int {
        max(0, min(segmentCount, Int((Double(value) / 20.0).rounded())))
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
