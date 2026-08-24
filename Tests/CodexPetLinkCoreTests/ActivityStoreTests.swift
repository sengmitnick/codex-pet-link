import Foundation
import XCTest
@testable import CodexPetLinkCore

final class ActivityStoreTests: XCTestCase {
    func testConsumesConcurrentEventsAndPrioritizesNeedsInput() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = HookInbox(root: root)
        try inbox.enqueue(event(session: "running", title: "优化引导", state: .running, phase: .modifyingFiles, time: 20))
        try inbox.enqueue(event(session: "needs-input", title: "连接 Codex", state: .needsInput, phase: .waitingApproval, time: 10))

        var store = ActivityStore()
        try store.consume(inbox: inbox)
        let snapshot = store.snapshot(now: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(snapshot.primary?.sessionID, "needs-input")
        XCTAssertEqual(snapshot.primary?.title, "连接 Codex")
        XCTAssertEqual(snapshot.additionalCount, 1)
        XCTAssertEqual(snapshot.activities.map(\.sessionID), ["needs-input", "running"])
        XCTAssertTrue(try inbox.pendingFiles().isEmpty)
    }

    func testSnapshotCarriesEveryVisibleActivityInPetPriorityOrder() {
        var store = ActivityStore()
        store.apply(event(session: "running", title: "实现蓝牙", state: .running, phase: .runningCommand, time: 40))
        store.apply(event(session: "ready", title: "更新文档", state: .ready, phase: .completed, time: 30))
        store.apply(event(session: "blocked", title: "修复构建", state: .blocked, phase: .problem, time: 20))
        store.apply(event(session: "input", title: "确认方案", state: .needsInput, phase: .waitingApproval, time: 10))

        let snapshot = store.snapshot(now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.activities.map(\.sessionID), ["input", "blocked", "ready", "running"])
        XCTAssertEqual(snapshot.additionalCount, 3)
    }

    func testNewEventWithoutTitleKeepsExistingTitle() {
        var store = ActivityStore()
        store.apply(event(session: "s1", title: "修复重连", state: .running, phase: .thinking, time: 1))
        store.apply(event(session: "s1", title: nil, state: .running, phase: .runningCommand, time: 2))

        let activity = store.snapshot(now: Date(timeIntervalSince1970: 3)).primary
        XCTAssertEqual(activity?.title, "修复重连")
        XCTAssertEqual(activity?.phase, .runningCommand)
    }

    func testRejectsMalformedInboxFileAndContinues() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = HookInbox(root: root)
        try inbox.prepare()
        try Data("not json".utf8).write(to: root.appendingPathComponent("000-bad.json"))
        try inbox.enqueue(event(session: "s1", title: "任务", state: .running, phase: .thinking, time: 1))

        var store = ActivityStore()
        try store.consume(inbox: inbox)

        XCTAssertEqual(store.snapshot(now: Date(timeIntervalSince1970: 2)).primary?.sessionID, "s1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("rejected").path).count, 1)
    }

    func testCompletedActivityExpiresAfterThirtyMinutes() {
        var store = ActivityStore()
        store.apply(event(session: "s1", title: "完成", state: .ready, phase: .completed, time: 1))

        XCTAssertNotNil(store.snapshot(now: Date(timeIntervalSince1970: 1_800)).primary)
        XCTAssertNil(store.snapshot(now: Date(timeIntervalSince1970: 1_802)).primary)
    }

    func testOfficialTitleDoesNotMakeOlderTaskLookMoreRecent() {
        var store = ActivityStore()
        store.apply(event(session: "older", title: "旧标题", state: .running, phase: .thinking, time: 1))
        store.apply(event(session: "newer", title: "新任务", state: .running, phase: .thinking, time: 2))

        store.setTitle("Codex 标题", for: "older", at: Date(timeIntervalSince1970: 99))

        XCTAssertEqual(store.snapshot(now: Date(timeIntervalSince1970: 100)).primary?.sessionID, "newer")
    }

    func testOfficialTitleSurvivesLaterPromptsInSameThread() {
        var store = ActivityStore()
        store.apply(event(session: "s1", title: "第一个 prompt", state: .running, phase: .thinking, time: 1))
        store.setTitle("赛博宠物：连接 Codex", for: "s1", at: Date(timeIntervalSince1970: 2))

        store.apply(event(session: "s1", title: "继续改一下", state: .running, phase: .thinking, time: 3))

        XCTAssertEqual(
            store.snapshot(now: Date(timeIntervalSince1970: 4)).primary?.title,
            "赛博宠物：连接 Codex"
        )
    }

    private func event(
        session: String,
        title: String?,
        state: CodexTaskState,
        phase: TaskPhase,
        time: TimeInterval
    ) -> NormalizedHookEvent {
        NormalizedHookEvent(
            sessionID: session,
            title: title,
            state: state,
            phase: phase,
            updatedAt: Date(timeIntervalSince1970: time)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
