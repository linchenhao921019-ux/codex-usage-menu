import Foundation
import XCTest
@testable import CodexUsageMenu

final class LiveRateLimitReaderTests: XCTestCase {
    func testParsesLiveAccountRateLimitResponse() throws {
        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1783788211},"secondary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":1784375011},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus"},"rateLimitsByLimitId":null}}"#
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let snapshot = LiveRateLimitReader.snapshot(
            fromResponseData: try XCTUnwrap(response.data(using: .utf8)),
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot?.timestamp, fetchedAt)
        XCTAssertEqual(snapshot?.sourcePath, "codex-app-server://account/rateLimits/read")
        XCTAssertEqual(snapshot?.primary?.remainingPercent, 88)
        XCTAssertEqual(snapshot?.secondary?.remainingPercent, 66)
        XCTAssertEqual(snapshot?.planType, "plus")
    }

    func testTreatsExpiredServerWindowAsResetWithoutAUsageEvent() throws {
        let response = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":1699999999},"secondary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":1700003600},"planType":"plus"}}}"#
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let snapshot = LiveRateLimitReader.snapshot(
            fromResponseData: try XCTUnwrap(response.data(using: .utf8)),
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot?.primary?.remainingPercent, 100)
        XCTAssertNil(snapshot?.primary?.resetsAt)
        XCTAssertEqual(snapshot?.secondary?.remainingPercent, 66)
        XCTAssertNotNil(snapshot?.secondary?.resetsAt)
    }
}
