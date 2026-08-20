import Foundation
import XCTest
@testable import CodexPetLinkCore

final class BLEPacketTests: XCTestCase {
    func testRoundTripEveryState() throws {
        for state in CodexTaskState.allCases {
            let input = CodexStatusSnapshot(
                state: state,
                progress: nil,
                sequence: 0x1234_5678,
                updatedAt: Date(timeIntervalSince1970: 0x0102_0304)
            )

            let bytes = [UInt8](BLEPacket.encode(input))

            XCTAssertEqual(bytes, [0xC7, 1, state.rawValue, 255, 0x78, 0x56, 0x34, 0x12, 4, 3, 2, 1])
            XCTAssertEqual(try BLEPacket.decode(Data(bytes)), input)
        }
    }

    func testRoundTripsKnownProgress() throws {
        let input = CodexStatusSnapshot(
            state: .running,
            progress: 42,
            sequence: 1,
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(try BLEPacket.decode(BLEPacket.encode(input)), input)
    }

    func testRejectsMalformedPackets() {
        XCTAssertThrowsError(try BLEPacket.decode(Data(repeating: 0, count: 11)))
        XCTAssertThrowsError(try BLEPacket.decode(Data([0, 1, 0, 255] + Array(repeating: 0, count: 8))))
        XCTAssertThrowsError(try BLEPacket.decode(Data([0xC7, 2, 0, 255] + Array(repeating: 0, count: 8))))
        XCTAssertThrowsError(try BLEPacket.decode(Data([0xC7, 1, 9, 255] + Array(repeating: 0, count: 8))))
    }
}
