import XCTest
@testable import CodexUsageMenu

final class UsageReaderTests: XCTestCase {
    func testWeeklyWindowCanBeReturnedAsPrimary() {
        let weekly = UsageWindow(usedPercent: 23, windowMinutes: 10_080, resetsAt: nil)
        let snapshot = UsageSnapshot(
            timestamp: Date(), sourcePath: "test", limitID: nil, limitName: nil,
            planType: nil, credits: nil, primary: weekly, secondary: nil
        )

        XCTAssertEqual(snapshot.weekly?.remainingPercent, 77)
        XCTAssertEqual(snapshot.weekly?.compactLabel, "7d")
    }

    func testReadsCurrentCodexRateLimitShapeWithCreditsAndNullPlan() throws {
        let text = #"{"timestamp":"2026-07-10T00:05:37.123Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":4.0,"window_minutes":300,"resets_at":1783659806},"secondary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1784246606},"credits":{"has_credits":false,"unlimited":false,"balance":null},"individual_limit":null,"plan_type":null,"rate_limit_reached_type":null}}}"#

        let snapshot = try XCTUnwrap(UsageReader.snapshot(fromJSONL: text))

        XCTAssertEqual(snapshot.limitID, "codex")
        XCTAssertNil(snapshot.planType)
        XCTAssertEqual(snapshot.primary?.remainingPercent, 96)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 99)
        XCTAssertEqual(snapshot.credits, UsageCredits(hasCredits: false, unlimited: false, balance: nil))
    }

    func testKeepsLegacyTopLevelRateLimitShapeCompatible() throws {
        let text = #"{"timestamp":"2026-06-01T12:00:00Z","rate_limits":{"plan_type":"plus","primary":{"used_percent":"25","window_minutes":"300","resets_at":"1780000000"},"secondary":{"used_percent":10,"window_minutes":10080,"resets_at":1780500000}}}"#

        let snapshot = try XCTUnwrap(UsageReader.snapshot(fromJSONL: text))

        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 75)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 90)
        XCTAssertNil(snapshot.credits)
    }

    func testUsesNewestValidRateLimitRecord() throws {
        let text = """
        {"timestamp":"2026-07-10T00:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":10,"window_minutes":300}}}}
        {"timestamp":"2026-07-10T00:01:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20,"window_minutes":300}}}}
        """

        let snapshot = try XCTUnwrap(UsageReader.snapshot(fromJSONL: text))

        XCTAssertEqual(snapshot.primary?.remainingPercent, 80)
    }
}
