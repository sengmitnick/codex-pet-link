import Foundation
import XCTest
@testable import CodexPetLinkCore

final class CodexSessionWatcherTests: XCTestCase {
    func testReplaysExistingEventsThenConsumesOnlyAppendedLines() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let file = fixture.root.appendingPathComponent("rollout-a.jsonl")
        try fixture.write(event("task_started"), to: file)
        let watcher = CodexSessionWatcher(rootURL: fixture.root)

        XCTAssertEqual(try watcher.pollOnce().state, .running)

        try fixture.append(event("task_complete"), to: file)
        XCTAssertEqual(try watcher.pollOnce().state, .ready)
        XCTAssertEqual(try watcher.pollOnce().state, .ready)
    }

    func testKeepsIncompleteLineUntilNewlineArrives() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let file = fixture.root.appendingPathComponent("rollout-a.jsonl")
        try "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}"
            .write(to: file, atomically: true, encoding: .utf8)
        let watcher = CodexSessionWatcher(rootURL: fixture.root)

        XCTAssertEqual(try watcher.pollOnce().state, .idle)

        try fixture.append("\n", to: file, includeTrailingNewline: false)
        XCTAssertEqual(try watcher.pollOnce().state, .running)
    }

    func testSwitchesToNewerSessionFile() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let first = fixture.root.appendingPathComponent("rollout-a.jsonl")
        try fixture.write(event("task_complete"), to: first)
        let watcher = CodexSessionWatcher(rootURL: fixture.root)
        XCTAssertEqual(try watcher.pollOnce().state, .ready)

        Thread.sleep(forTimeInterval: 0.02)
        let second = fixture.root.appendingPathComponent("rollout-b.jsonl")
        try fixture.write(event("task_started"), to: second)

        XCTAssertEqual(try watcher.pollOnce().state, .running)
    }

    func testMissingRootReturnsIdle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let watcher = CodexSessionWatcher(rootURL: root)

        XCTAssertEqual(try watcher.pollOnce().state, .idle)
    }

    func testPollStatesTracksEveryRequestedSessionIndependently() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let running = fixture.root.appendingPathComponent("rollout-running-session-running.jsonl")
        let completed = fixture.root.appendingPathComponent("rollout-completed-session-completed.jsonl")
        try fixture.write(event("task_started"), to: running)
        try fixture.write(event("task_started") + "\n" + event("task_complete"), to: completed)
        let watcher = CodexSessionWatcher(rootURL: fixture.root)

        let states = try watcher.pollStates(for: ["session-running", "session-completed"])

        XCTAssertEqual(states["session-running"], .running)
        XCTAssertEqual(states["session-completed"], .ready)
    }

    func testPollRecentActivitiesRestoresRunningAndCompletedSessions() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let runningID = "11111111-1111-7111-8111-111111111111"
        let completedID = "22222222-2222-7222-8222-222222222222"
        let staleID = "33333333-3333-7333-8333-333333333333"
        let running = fixture.root.appendingPathComponent("rollout-a-\(runningID).jsonl")
        let completed = fixture.root.appendingPathComponent("rollout-b-\(completedID).jsonl")
        let stale = fixture.root.appendingPathComponent("rollout-c-\(staleID).jsonl")
        try fixture.write(event("task_started"), to: running)
        try fixture.write(event("task_started") + "\n" + event("task_complete"), to: completed)
        try fixture.write(event("task_started"), to: stale)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: running.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 990)], ofItemAtPath: completed.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: stale.path)
        let watcher = CodexSessionWatcher(rootURL: fixture.root)

        let activities = try watcher.pollRecentActivities(
            since: Date(timeIntervalSince1970: 900),
            limit: 12
        )

        XCTAssertEqual(activities.map(\.sessionID), [runningID, completedID])
        XCTAssertEqual(activities.map(\.state), [.running, .ready])
    }

    func testLargeExistingSessionReplaysOnlyABoundedTail() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let file = fixture.root.appendingPathComponent(
            "rollout-large-44444444-4444-7444-8444-444444444444.jsonl"
        )
        let padding = #"{"type":"event_msg","payload":{"type":"noop","data":""#
            + String(repeating: "x", count: 700_000)
            + #""}}"#
        try fixture.write(
            event("task_started") + "\n" + padding + "\n" + event("task_complete"),
            to: file
        )
        let watcher = CodexSessionWatcher(rootURL: fixture.root)

        XCTAssertEqual(try watcher.pollOnce().state, .ready)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(watcher.initialReplayByteCount(for: file)),
            512 * 1_024
        )
    }

    private func event(_ type: String) -> String {
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}"
    }
}

private final class SessionFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ line: String, to file: URL) throws {
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    func append(_ line: String, to file: URL, includeTrailingNewline: Bool = true) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let suffix = includeTrailingNewline ? "\n" : ""
        try handle.write(contentsOf: Data((line + suffix).utf8))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
