import Foundation
import SwiftUI
import WidgetKit

struct CodexMacUsageWindow: Codable, Hashable {
    let label: String
    let compactLabel: String
    let usedPercent: Double
    let remainingPercent: Int
    let windowMinutes: Int
    let resetsAt: Date?
}

struct CodexMacUsageSnapshot: Codable, Hashable {
    let schemaVersion: Int
    let exportedAt: Date
    let snapshotTimestamp: Date
    let planType: String?
    let primary: CodexMacUsageWindow?
    let secondary: CodexMacUsageWindow?

    var weekly: CodexMacUsageWindow? {
        [primary, secondary]
            .compactMap { $0 }
            .filter { abs($0.windowMinutes - 10_080) <= 504 }
            .min { abs($0.windowMinutes - 10_080) < abs($1.windowMinutes - 10_080) }
    }

    var isStale: Bool {
        Date().timeIntervalSince(exportedAt) > 60 * 60
    }
}

struct CodexMacUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: CodexMacUsageSnapshot?
}

enum CodexMacUsageSnapshotStore {
    private static let cachedSnapshotKey = "codexUsage.macWidget.lastSuccessfulSnapshot"

    private static var localSnapshotURLs: [URL] {
        var urls = [
            URL(string: "http://127.0.0.1:8765/snapshot")!,
            URL(string: "http://localhost:8765/snapshot")!
        ]

        let hostName = ProcessInfo.processInfo.hostName
        if hostName.isEmpty == false {
            let localHost = hostName.contains(".") ? hostName : "\(hostName).local"
            if let url = URL(string: "http://\(localHost):8765/snapshot") {
                urls.append(url)
            }
        }
        return urls
    }

    private static var exportedSnapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("CodexUsage/codex-usage-snapshot.json")
    }

    private static var widgetContainerSnapshotURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/CodexUsage/codex-usage-snapshot.json"),
            home
                .appendingPathComponent("Library/Containers/com.local.codexusage.menu.widget/Data/Library/Application Support", isDirectory: true)
                .appendingPathComponent("CodexUsage/codex-usage-snapshot.json")
        ]
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 1.2
        configuration.timeoutIntervalForResource = 1.2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func load(completion: @escaping (CodexMacUsageSnapshot?) -> Void) {
        loadFromLocalApp(urls: localSnapshotURLs) { snapshot in
            if let snapshot {
                saveToCache(snapshot)
                completion(snapshot)
                return
            }

            if let snapshot = loadWidgetContainerSnapshot() {
                saveToCache(snapshot)
                completion(snapshot)
                return
            }

            if let snapshot = loadExportedSnapshot() {
                saveToCache(snapshot)
                completion(snapshot)
                return
            }

            completion(cachedSnapshot())
        }
    }

    private static func loadWidgetContainerSnapshot() -> CodexMacUsageSnapshot? {
        for url in widgetContainerSnapshotURLs {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(CodexMacUsageSnapshot.self, from: data) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private static func loadFromLocalApp(
        urls: [URL],
        completion: @escaping (CodexMacUsageSnapshot?) -> Void
    ) {
        guard let url = urls.first else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 1.2

        session.dataTask(with: request) { data, _, _ in
            if let data,
               let snapshot = try? decoder.decode(CodexMacUsageSnapshot.self, from: data) {
                completion(snapshot)
                return
            }
            loadFromLocalApp(urls: Array(urls.dropFirst()), completion: completion)
        }.resume()
    }

    private static func loadExportedSnapshot() -> CodexMacUsageSnapshot? {
        guard let data = try? Data(contentsOf: exportedSnapshotURL) else {
            return nil
        }
        return try? decoder.decode(CodexMacUsageSnapshot.self, from: data)
    }

    private static func cachedSnapshot() -> CodexMacUsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cachedSnapshotKey) else {
            return nil
        }
        return try? decoder.decode(CodexMacUsageSnapshot.self, from: data)
    }

    private static func saveToCache(_ snapshot: CodexMacUsageSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        UserDefaults.standard.set(data, forKey: cachedSnapshotKey)
    }
}

struct CodexMacUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexMacUsageEntry {
        CodexMacUsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexMacUsageEntry) -> Void) {
        CodexMacUsageSnapshotStore.load { snapshot in
            completion(CodexMacUsageEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexMacUsageEntry>) -> Void) {
        CodexMacUsageSnapshotStore.load { snapshot in
            let entry = CodexMacUsageEntry(date: Date(), snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct CodexMacUsageWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    let entry: CodexMacUsageEntry

    var body: some View {
        standardBody
        .containerBackground(for: .widget) {
            MacBrandWidgetBackground()
        }
        .foregroundStyle(MacBrandWidgetPalette.primaryText(for: colorScheme))
    }

    private var standardBody: some View {
        Group {
            if let snapshot = entry.snapshot {
                if widgetFamily == .systemMedium {
                    mediumBody(snapshot)
                } else {
                    smallBody(snapshot)
                }
            } else {
                Spacer()
                Text("等待 Mac")
                    .font(.headline)
                    .foregroundStyle(MacBrandWidgetPalette.secondaryText(for: colorScheme))
                Spacer()
            }
        }
        .padding(14)
    }

    private func smallBody(_ snapshot: CodexMacUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetHeader(snapshot)

            MacHeroMetric(label: "7d", window: snapshot.weekly)
                .padding(.top, 1)

            Spacer(minLength: 0)
        }
    }

    private func mediumBody(_ snapshot: CodexMacUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(snapshot)

            MacMetricCard(label: "7d", window: snapshot.weekly, isPrimary: true)
        }
    }

    private func widgetHeader(_ snapshot: CodexMacUsageSnapshot) -> some View {
        HStack(spacing: 8) {
            Text("Codex 用量")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Image(systemName: snapshot.isStale ? "clock.badge.exclamationmark" : "desktopcomputer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(snapshot.isStale ? .orange : MacBrandWidgetPalette.secondaryText(for: colorScheme))
        }
    }
}

struct MacBrandWidgetBackground: View {
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

enum MacBrandWidgetPalette {
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

struct MacHeroMetric: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let window: CodexMacUsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MacBrandWidgetPalette.secondaryText(for: colorScheme))
                    .frame(width: 34, alignment: .leading)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(percentText)
                        .font(.system(size: 50, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.72)
                    Text("%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MacBrandWidgetPalette.secondaryText(for: colorScheme))
                }
                .lineLimit(1)
            }

            MacLinearUsageBar(value: window?.remainingPercent ?? 0, height: 10, segmentCount: 12)
        }
    }

    private var percentText: String {
        window.map { "\($0.remainingPercent)" } ?? "--"
    }
}

struct MacSecondaryMetric: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let window: CodexMacUsageWindow?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.headline.weight(.bold))
                .foregroundStyle(MacBrandWidgetPalette.secondaryText(for: colorScheme))
                .frame(width: 34, alignment: .leading)

            MacLinearUsageBar(value: window?.remainingPercent ?? 0, height: 8, segmentCount: 8)

            Text(window.map { "\($0.remainingPercent)%" } ?? "--")
                .font(.title3.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 54, alignment: .trailing)
        }
    }
}

struct MacMetricCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let window: CodexMacUsageWindow?
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.headline.weight(.bold))
                .foregroundStyle(MacBrandWidgetPalette.secondaryText(for: colorScheme))

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(window.map { "\($0.remainingPercent)" } ?? "--")
                    .font(.system(size: isPrimary ? 52 : 42, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.72)
                Text("%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MacBrandWidgetPalette.secondaryText(for: colorScheme))
            }
            .lineLimit(1)

            MacLinearUsageBar(value: window?.remainingPercent ?? 0, height: 10, segmentCount: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacLinearUsageBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let value: Int
    let height: CGFloat
    let segmentCount: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < activeCount ? MacBrandWidgetPalette.activeUsage(for: value, colorScheme: colorScheme) : MacBrandWidgetPalette.inactiveUsage(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var activeCount: Int {
        max(0, min(segmentCount, Int((Double(value) / 100.0 * Double(segmentCount)).rounded())))
    }
}

struct CodexMacUsageWidget: Widget {
    let kind = "CodexUsageMacWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexMacUsageProvider()) { entry in
            CodexMacUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 用量")
        .description("显示这台 Mac 的 Codex 5 小时和 7 天剩余额度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CodexMacUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexMacUsageWidget()
    }
}
