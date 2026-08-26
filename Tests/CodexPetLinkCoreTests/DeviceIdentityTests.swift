import Foundation
import XCTest
@testable import CodexPetLinkCore

final class DeviceIdentityTests: XCTestCase {
    func testIdentityIsShortAndStableAcrossComputerRename() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("device-identity.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try DeviceIdentity.loadOrCreate(
            at: url,
            computerName: "seng 的 MacBook Air",
            randomSuffix: { "A1B2" }
        )
        let second = try DeviceIdentity.loadOrCreate(
            at: url,
            computerName: "renamed Mac",
            randomSuffix: { "FFFF" }
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.advertisedName, "Codex seng-MacBook-Air A1B2")
        XCTAssertLessThanOrEqual(first.advertisedName.utf8.count, 28)
    }

    func testLongOrNonLatinComputerNameStillProducesUsefulName() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("device-identity.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let identity = try DeviceIdentity.loadOrCreate(
            at: url,
            computerName: "张三的超级超级长的 MacBook Pro 工作电脑",
            randomSuffix: { "C3D4" }
        )

        XCTAssertTrue(identity.advertisedName.hasPrefix("Codex "))
        XCTAssertTrue(identity.advertisedName.hasSuffix(" C3D4"))
        XCTAssertLessThanOrEqual(identity.advertisedName.utf8.count, 28)
    }
}
