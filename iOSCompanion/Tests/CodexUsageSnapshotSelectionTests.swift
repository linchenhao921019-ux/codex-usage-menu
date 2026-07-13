import Foundation

@main
enum CodexUsageSnapshotSelectionTests {
    static func main() {
        let base = Date(timeIntervalSince1970: 1_000)
        let air = endpoint(name: "MacBook Air", port: 1001)
        let mini = endpoint(name: "Mac mini", port: 1002)

        let weekly = CodexUsageWindow(
            label: "1 周", compactLabel: "7d", usedPercent: 24,
            remainingPercent: 76, windowMinutes: 10_080, resetsAt: nil
        )
        let weeklySnapshot = CodexUsageSnapshot(
            schemaVersion: 2, exportedAt: base, snapshotTimestamp: base,
            planType: nil, primary: weekly, secondary: nil
        )
        precondition(weeklySnapshot.weekly?.remainingPercent == 76)

        assertSelected(
            "Mac mini",
            from: [
                candidate(endpoint: air, snapshotTime: base, exportedTime: base),
                candidate(endpoint: mini, snapshotTime: base.addingTimeInterval(60), exportedTime: base)
            ]
        )
        assertSelected(
            "MacBook Air",
            from: [
                candidate(endpoint: air, snapshotTime: base.addingTimeInterval(120), exportedTime: base),
                candidate(endpoint: mini, snapshotTime: base.addingTimeInterval(60), exportedTime: base)
            ]
        )
        assertSelected(
            "Mac mini",
            from: [
                candidate(endpoint: air, snapshotTime: base, exportedTime: base),
                candidate(endpoint: mini, snapshotTime: base, exportedTime: base.addingTimeInterval(60))
            ]
        )

        print("iOS source selection tests passed")
    }

    private static func endpoint(name: String, port: Int) -> CodexUsageEndpoint {
        CodexUsageEndpoint(url: URL(string: "http://127.0.0.1:\(port)/snapshot")!, sourceName: name)
    }

    private static func candidate(
        endpoint: CodexUsageEndpoint,
        snapshotTime: Date,
        exportedTime: Date
    ) -> CodexUsageEndpointSnapshot {
        CodexUsageEndpointSnapshot(
            snapshot: CodexUsageSnapshot(
                schemaVersion: 1,
                exportedAt: exportedTime,
                snapshotTimestamp: snapshotTime,
                planType: nil,
                primary: nil,
                secondary: nil
            ),
            endpoint: endpoint
        )
    }

    private static func assertSelected(
        _ expectedSource: String,
        from candidates: [CodexUsageEndpointSnapshot]
    ) {
        let actualSource = CodexUsageSnapshotStore.freshestCandidate(in: candidates)?.endpoint.sourceName
        precondition(actualSource == expectedSource, "Expected \(expectedSource), got \(actualSource ?? "nil")")
    }
}
