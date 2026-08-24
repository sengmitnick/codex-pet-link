import Foundation
import XCTest
@testable import CodexPetLinkCore

final class HookEventTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 123)

    func testUserPromptCreatesRunningActivityWithSanitizedTitle() throws {
        let input = #"{"session_id":"s1","turn_id":"t1","prompt":"修复蓝牙重连","tool_input":{"cmd":"cat /secret"}}"#

        let event = try HookEvent.parse(kind: .userPromptSubmit, data: Data(input.utf8), now: date)

        XCTAssertEqual(event.sessionID, "s1")
        XCTAssertEqual(event.turnID, "t1")
        XCTAssertEqual(event.title, "修复蓝牙重连")
        XCTAssertEqual(event.state, .running)
        XCTAssertEqual(event.phase, .thinking)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(event), as: UTF8.self).contains("/secret"))
    }

    func testMapsToolsToSafePhasesWithoutKeepingToolInput() throws {
        let expectations: [(String, TaskPhase)] = [
            ("exec_command", .runningCommand),
            ("Bash", .runningCommand),
            ("apply_patch", .modifyingFiles),
            ("Write", .modifyingFiles),
            ("web__run", .searching),
            ("search_query", .searching),
            ("mystery", .thinking),
        ]

        for (tool, phase) in expectations {
            let input = #"{"session_id":"s1","tool_name":"\#(tool)","tool_input":{"path":"/private/file"}}"#
            let event = try HookEvent.parse(kind: .preToolUse, data: Data(input.utf8), now: date)
            XCTAssertEqual(event.phase, phase)
            XCTAssertNil(event.title)
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(event), as: UTF8.self).contains("/private/file"))
        }
    }

    func testMapsPermissionStopAndFailureLifecycle() throws {
        let input = Data(#"{"session_id":"s1"}"#.utf8)
        let permission = try HookEvent.parse(kind: .permissionRequest, data: input, now: date)
        let stopped = try HookEvent.parse(kind: .stop, data: input, now: date)
        let failed = try HookEvent.parse(kind: .notification, data: Data(#"{"session_id":"s1","status":"failed"}"#.utf8), now: date)

        XCTAssertEqual(permission.state, .needsInput)
        XCTAssertEqual(permission.phase, .waitingApproval)
        XCTAssertEqual(stopped.state, .ready)
        XCTAssertEqual(stopped.phase, .completed)
        XCTAssertEqual(failed.state, .blocked)
        XCTAssertEqual(failed.phase, .problem)
    }

    func testRequiresSessionIdentifier() {
        XCTAssertThrowsError(
            try HookEvent.parse(kind: .stop, data: Data(#"{"turn_id":"t1"}"#.utf8), now: date)
        )
    }
}
