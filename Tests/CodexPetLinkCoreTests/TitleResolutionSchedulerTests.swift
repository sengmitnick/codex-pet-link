import Foundation
import XCTest
@testable import CodexPetLinkCore

final class TitleResolutionSchedulerTests: XCTestCase {
    func testReturnsAtMostOneEligibleActivityPerTickAndAppliesCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        let activities = [
            TaskActivity(sessionID: "first", title: "", state: .running, phase: .thinking, updatedAt: now),
            TaskActivity(sessionID: "second", title: "", state: .ready, phase: .completed, updatedAt: now),
        ]
        var scheduler = TitleResolutionScheduler(retryInterval: 30)

        XCTAssertEqual(scheduler.nextActivity(in: activities, at: now)?.sessionID, "first")
        XCTAssertEqual(scheduler.nextActivity(in: activities, at: now)?.sessionID, "second")
        XCTAssertNil(scheduler.nextActivity(in: activities, at: now))
        XCTAssertEqual(
            scheduler.nextActivity(in: activities, at: now.addingTimeInterval(30))?.sessionID,
            "first"
        )
    }

    func testResolvedActivityIsNotRetried() {
        let now = Date(timeIntervalSince1970: 1_000)
        let activity = TaskActivity(
            sessionID: "resolved",
            title: "",
            state: .running,
            phase: .thinking,
            updatedAt: now
        )
        var scheduler = TitleResolutionScheduler(retryInterval: 30)

        XCTAssertNotNil(scheduler.nextActivity(in: [activity], at: now))
        scheduler.markResolved(sessionID: activity.sessionID)

        XCTAssertNil(scheduler.nextActivity(in: [activity], at: .distantFuture))
    }
}
