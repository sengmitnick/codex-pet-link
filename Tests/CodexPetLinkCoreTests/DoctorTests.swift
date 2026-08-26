import Foundation
import XCTest
@testable import CodexPetLinkCore

final class DoctorTests: XCTestCase {
    func testReportsMissingInstallSessionsAndServiceSeparately() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = ServicePaths(homeDirectory: home)
        _ = try? DeviceIdentity.loadOrCreate(
            at: paths.deviceIdentity,
            computerName: "测试电脑",
            randomSuffix: { "A1B2" }
        )
        let report = Doctor(paths: paths, serviceLoaded: { false }).inspect()

        XCTAssertFalse(report.executableInstalled)
        XCTAssertFalse(report.sessionsAvailable)
        XCTAssertFalse(report.serviceLoaded)
        XCTAssertEqual(report.advertisedName, "Codex Mac A1B2")
        XCTAssertEqual(report.overall, .needsAttention)
    }

    func testReportsHealthyInstall() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ServicePaths(homeDirectory: home)
        try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.sessions, withIntermediateDirectories: true)
        try Data().write(to: paths.executable)

        let report = Doctor(paths: paths, serviceLoaded: { true }).inspect()

        XCTAssertTrue(report.executableInstalled)
        XCTAssertTrue(report.sessionsAvailable)
        XCTAssertTrue(report.serviceLoaded)
        XCTAssertEqual(report.overall, .healthy)
    }
}
