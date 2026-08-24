import Foundation
import XCTest
@testable import CodexPetLinkCore

final class DoctorTests: XCTestCase {
    func testReportsMissingInstallSessionsAndServiceSeparately() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let report = Doctor(paths: ServicePaths(homeDirectory: home), serviceLoaded: { false }).inspect()

        XCTAssertFalse(report.executableInstalled)
        XCTAssertFalse(report.sessionsAvailable)
        XCTAssertFalse(report.serviceLoaded)
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
