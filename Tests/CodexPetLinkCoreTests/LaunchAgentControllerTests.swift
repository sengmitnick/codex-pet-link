import Foundation
import XCTest
@testable import CodexPetLinkCore

final class LaunchAgentControllerTests: XCTestCase {
    func testPathsStayInsideApplicationSupportExceptCommandLink() {
        let paths = ServicePaths(homeDirectory: URL(fileURLWithPath: "/tmp/test-home"))

        XCTAssertEqual(paths.executable.path, "/tmp/test-home/Library/Application Support/CodexPetLink/bin/codex-pet-link")
        XCTAssertEqual(paths.inbox.path, "/tmp/test-home/Library/Application Support/CodexPetLink/inbox")
        XCTAssertEqual(paths.config.path, "/tmp/test-home/Library/Application Support/CodexPetLink/config.json")
        XCTAssertFalse(paths.plist.path.contains("Library/LaunchAgents"))
        XCTAssertEqual(paths.commandLink.path, "/tmp/test-home/.local/bin/codex-pet-link")
    }

    func testPlistKeepsServiceAliveButDoesNotLoadAtLogin() throws {
        let paths = ServicePaths(homeDirectory: URL(fileURLWithPath: "/tmp/test-home"))
        let data = try LaunchAgentController.plistData(paths: paths)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        XCTAssertEqual(value["Label"] as? String, "com.rokid.codex-pet-link")
        XCTAssertEqual(value["ProgramArguments"] as? [String], [paths.executable.path, "run"])
        XCTAssertEqual(value["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(value["KeepAlive"] as? Bool, true)
    }

    func testEnsureIsIdempotentAndBootstrapsOnlyWhenMissing() throws {
        let loadedRunner = RecordingLaunchRunner(results: [0])
        let loaded = LaunchAgentController(paths: temporaryPaths(), uid: 501, runner: loadedRunner)
        XCTAssertEqual(try loaded.ensure(), .alreadyRunning)
        XCTAssertEqual(loadedRunner.calls, [["print", "gui/501/com.rokid.codex-pet-link"]])

        let missingRunner = RecordingLaunchRunner(results: [113, 0])
        let missing = LaunchAgentController(paths: temporaryPaths(), uid: 501, runner: missingRunner)
        XCTAssertEqual(try missing.ensure(), .started)
        XCTAssertEqual(missingRunner.calls.count, 2)
        XCTAssertEqual(Array(missingRunner.calls[1].prefix(2)), ["bootstrap", "gui/501"])
    }

    func testStopUsesExactGUIServiceLabel() throws {
        let runner = RecordingLaunchRunner(results: [0, 0])
        let controller = LaunchAgentController(paths: temporaryPaths(), uid: 502, runner: runner)

        XCTAssertTrue(try controller.stop())
        XCTAssertEqual(runner.calls.last, ["bootout", "gui/502/com.rokid.codex-pet-link"])
    }

    private func temporaryPaths() -> ServicePaths {
        ServicePaths(homeDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
}

private final class RecordingLaunchRunner: LaunchCommandRunning, @unchecked Sendable {
    var results: [Int32]
    var calls: [[String]] = []

    init(results: [Int32]) { self.results = results }

    func run(_ arguments: [String]) -> Int32 {
        calls.append(arguments)
        return results.removeFirst()
    }
}
