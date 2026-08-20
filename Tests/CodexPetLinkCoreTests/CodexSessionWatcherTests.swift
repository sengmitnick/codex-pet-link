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
