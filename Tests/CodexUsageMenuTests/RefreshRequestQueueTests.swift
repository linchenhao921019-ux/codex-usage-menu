import XCTest
@testable import CodexUsageMenu

final class RefreshRequestQueueTests: XCTestCase {
    func testAutomaticRefreshIsNotQueued() {
        var queue = RefreshRequestQueue()

        queue.enqueue(updateMenu: true, reason: .automatic)

        XCTAssertNil(queue.take())
    }

    func testMenuOpenQueuesRefreshInsteadOfDroppingIt() {
        var queue = RefreshRequestQueue()

        queue.enqueue(updateMenu: true, reason: .menuOpened)

        XCTAssertEqual(
            queue.take(),
            PendingRefreshRequest(updateMenu: true, reason: .menuOpened)
        )
        XCTAssertNil(queue.take())
    }

    func testManualRefreshTakesPriorityOverMenuRefresh() {
        var queue = RefreshRequestQueue()

        queue.enqueue(updateMenu: false, reason: .menuOpened)
        queue.enqueue(updateMenu: true, reason: .manual)

        XCTAssertEqual(
            queue.take(),
            PendingRefreshRequest(updateMenu: true, reason: .manual)
        )
    }
}
