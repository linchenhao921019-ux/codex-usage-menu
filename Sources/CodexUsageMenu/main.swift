import AppKit
import Foundation

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

struct UsageSnapshot: Codable {
    let timestamp: Date
    let sourcePath: String
    let planType: String?
    let primary: UsageWindow?
    let secondary: UsageWindow?
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
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).reversed()
        for line in lines where line.contains("\"rate_limits\"") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any],
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
                sourcePath: file.path,
                planType: rateLimits["plan_type"] as? String,
                primary: primary,
                secondary: secondary
            )
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusView = StatusBarUsageView()
    private var timer: Timer?
    private var snapshot: UsageSnapshot?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
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

    @objc private func refresh() {
        snapshot = UsageReader.latestSnapshot()
        render()
    }

    private func render() {
        statusView.update(snapshot: snapshot)
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(viewItem(HeaderView()))

        if let snapshot {
            if let primary = snapshot.primary {
                menu.addItem(viewItem(UsageLimitRowView(window: primary)))
            }
            if let secondary = snapshot.secondary {
                menu.addItem(viewItem(UsageLimitRowView(window: secondary)))
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(disabledItem("更新于 \(relativeTime(snapshot.timestamp))"))
            if let plan = snapshot.planType {
                menu.addItem(disabledItem("计划：\(plan)"))
            }
        } else {
            menu.addItem(disabledItem("还没有找到 Codex 用量记录"))
            menu.addItem(disabledItem("发起一次 Codex 对话后会自动出现"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("刷新", selector: #selector(refresh)))
        menu.addItem(actionItem("打开 Codex", selector: #selector(openCodex)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("退出", selector: #selector(quit)))
        return menu
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
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Codex.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
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

private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func printSnapshotJSON() {
    guard let snapshot = UsageReader.latestSnapshot() else {
        print("{\"ok\":false,\"error\":\"No Codex rate_limits found\"}")
        return
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(snapshot), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

if CommandLine.arguments.contains("--json") {
    printSnapshotJSON()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
