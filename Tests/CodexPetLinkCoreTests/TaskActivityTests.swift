import Foundation
import XCTest
@testable import CodexPetLinkCore

final class TaskActivityTests: XCTestCase {
    func testSanitizesPromptWithoutLeakingCodePathOrAttachmentMarkup() {
        let prompt = """
        <image path=\"/tmp/private.png\"> 修复 /Users/me/a.swift 的蓝牙重连
        ```swift
        secret()
        ```
        """

        XCTAssertEqual(TaskTitle.sanitize(prompt), "修复 的蓝牙重连")
    }

    func testLimitsTitleByCharactersAndUTF8Bytes() {
        XCTAssertEqual(TaskTitle.sanitize(String(repeating: "蓝", count: 40)), String(repeating: "蓝", count: 24))
        XCTAssertLessThanOrEqual(TaskTitle.sanitize(String(repeating: "😀", count: 40)).utf8.count, 72)
    }

    func testPrivacyCanHideTaskTitle() {
        let activity = TaskActivity(
            sessionID: "s1",
            title: "优化引导",
            state: .running,
            phase: .modifyingFiles,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(activity.presented(titlesEnabled: true).title, "优化引导")
        XCTAssertEqual(activity.presented(titlesEnabled: false).title, "")
    }

    func testPriorityMatchesCodexPetSemantics() {
        XCTAssertGreaterThan(CodexTaskState.needsInput.activityPriority, CodexTaskState.blocked.activityPriority)
        XCTAssertGreaterThan(CodexTaskState.blocked.activityPriority, CodexTaskState.running.activityPriority)
        XCTAssertGreaterThan(CodexTaskState.running.activityPriority, CodexTaskState.ready.activityPriority)
        XCTAssertGreaterThan(CodexTaskState.running.activityPriority, CodexTaskState.idle.activityPriority)
    }
}
