import Foundation
import XCTest
@testable import CodexPetLinkCore

final class StatusSequencerTests: XCTestCase {
    func testSequenceOnlyAdvancesWhenStateChanges() {
        var sequencer = StatusSequencer()
        let date = Date(timeIntervalSince1970: 100)

        let first = sequencer.snapshot(state: .running, at: date)
        let heartbeat = sequencer.snapshot(state: .running, at: date.addingTimeInterval(1))
        let completed = sequencer.snapshot(state: .ready, at: date.addingTimeInterval(2))

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(heartbeat.sequence, 1)
        XCTAssertEqual(completed.sequence, 2)
        XCTAssertEqual(heartbeat.updatedAt, date.addingTimeInterval(1))
    }
}
