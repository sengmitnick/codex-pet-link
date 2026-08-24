import Foundation
import XCTest
@testable import CodexPetLinkCore

final class ActivityPacketTests: XCTestCase {
    func testEncodesTaskActivityIntoTwentyByteFrames() throws {
        let activity = TaskActivity(
            sessionID: "s1",
            title: "优化赛博宠物的 Codex 任务引导",
            state: .running,
            phase: .modifyingFiles,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let frames = ActivityPacket.encode(
            TaskActivitySnapshot(primary: activity, additionalCount: 2),
            sequence: 0x1234
        )

        XCTAssertEqual(BLEContract.activityUUID, "7d6b0003-9d7e-4e8a-a7b7-5c2e8f4a1100")
        XCTAssertGreaterThan(frames.count, 1)
        XCTAssertTrue(frames.allSatisfy { $0.count <= 20 })
        XCTAssertEqual([UInt8](frames[0].prefix(4)), [0xC8, 1, 0x34, 0x12])
        XCTAssertEqual([UInt8](frames[0])[4], 0)
        XCTAssertEqual(Int([UInt8](frames[0])[5]), frames.count)
    }

    func testReassemblesOutOfOrderFrames() throws {
        let input = BLEActivity(
            state: .needsInput,
            phase: .waitingApproval,
            title: "连接 Codex",
            additionalCount: 1
        )
        let frames = ActivityPacket.encode(input, sequence: 7)

        let output = try ActivityPacket.decode(frames.reversed())

        XCTAssertEqual(output, input)
    }

    func testRejectsIncompleteOrMixedSequenceFrames() {
        let input = BLEActivity(state: .running, phase: .runningCommand, title: "运行测试", additionalCount: 0)
        let frames = ActivityPacket.encode(input, sequence: 7)
        XCTAssertThrowsError(try ActivityPacket.decode(frames.dropLast()))

        var mixed = frames
        mixed.append(contentsOf: ActivityPacket.encode(input, sequence: 8))
        XCTAssertThrowsError(try ActivityPacket.decode(mixed))
    }

    func testLimitsLongUTF8TitleWithoutSplittingCharacter() throws {
        let input = BLEActivity(
            state: .running,
            phase: .thinking,
            title: String(repeating: "😀", count: 40),
            additionalCount: 0
        )
        let frames = ActivityPacket.encode(input, sequence: 1)
        let output = try ActivityPacket.decode(frames)

        XCTAssertLessThanOrEqual(output.title.utf8.count, 72)
        XCTAssertTrue(output.title.allSatisfy { $0 == "😀" })
        XCTAssertLessThanOrEqual(frames.count, 6)
    }

    func testV2EncodesAndReassemblesEveryTaskOutOfOrder() throws {
        let tasks = [
            BLEActivityItem(state: .needsInput, phase: .waitingApproval, title: "赛博宠物：确认方案"),
            BLEActivityItem(state: .running, phase: .ranCommand, title: "赛博宠物：连接 Codex"),
            BLEActivityItem(state: .running, phase: .modifiedFiles, title: "赛博宠物：优化引导"),
        ]

        let frames = ActivityListPacket.encode(tasks, sequence: 0x3412)
        let decoded = try ActivityListPacket.decode(frames.reversed())

        XCTAssertEqual(decoded, tasks)
        XCTAssertTrue(frames.allSatisfy { $0.count <= 20 })
        XCTAssertEqual([UInt8](frames[0].prefix(4)), [0xC8, 2, 0x12, 0x34])
    }

    func testV2RejectsIncompleteSnapshotWithoutReplacingIt() {
        let frames = ActivityListPacket.encode([
            BLEActivityItem(state: .running, phase: .searched, title: "查找资料"),
            BLEActivityItem(state: .ready, phase: .completed, title: "完成实现"),
        ], sequence: 9)

        XCTAssertGreaterThan(frames.count, 1)
        XCTAssertThrowsError(try ActivityListPacket.decode(frames.dropLast()))
    }
}
