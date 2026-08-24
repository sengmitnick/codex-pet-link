import XCTest
@testable import CodexPetLinkCore

final class CLICommandTests: XCTestCase {
    func testParsesServiceHookAndPrivacyCommands() throws {
        XCTAssertEqual(try CLICommand.parse(["run", "--source", "fake"]), .run(source: .fake, sessions: nil))
        XCTAssertEqual(try CLICommand.parse(["hook", "UserPromptSubmit"]), .hook(.userPromptSubmit))
        XCTAssertEqual(try CLICommand.parse(["privacy", "titles-off"]), .privacy(titlesEnabled: false))
        XCTAssertEqual(try CLICommand.parse(["status", "--json"]), .status(json: true))
        XCTAssertEqual(try CLICommand.parse(["doctor"]), .doctor(json: false))
    }

    func testKeepsLegacySourceArgumentsWorking() throws {
        XCTAssertEqual(try CLICommand.parse(["--source", "codex", "--sessions", "/tmp/sessions"]), .run(source: .codex, sessions: "/tmp/sessions"))
    }

    func testRejectsUnknownCommandAndHook() {
        XCTAssertThrowsError(try CLICommand.parse(["unknown"]))
        XCTAssertThrowsError(try CLICommand.parse(["hook", "UnknownHook"]))
    }
}
