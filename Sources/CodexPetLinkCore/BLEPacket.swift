import Foundation

public enum BLEContract {
    public static let serviceUUID = "7d6b0001-9d7e-4e8a-a7b7-5c2e8f4a1100"
    public static let statusUUID = "7d6b0002-9d7e-4e8a-a7b7-5c2e8f4a1100"
    public static let heartbeat: TimeInterval = 10
}

public enum BLEPacketError: Error, Equatable {
    case invalidLength
    case invalidMagic
    case unsupportedVersion
    case invalidState
}

public enum BLEPacket {
    public static func encode(_ snapshot: CodexStatusSnapshot) -> Data {
        let seconds = UInt32(clamping: Int64(snapshot.updatedAt.timeIntervalSince1970))
        return Data(
            [0xC7, 1, snapshot.state.rawValue, snapshot.progress ?? 255]
                + littleEndian(snapshot.sequence)
                + littleEndian(seconds)
        )
    }

    public static func decode(_ data: Data) throws -> CodexStatusSnapshot {
        let bytes = [UInt8](data)
        guard bytes.count == 12 else { throw BLEPacketError.invalidLength }
        guard bytes[0] == 0xC7 else { throw BLEPacketError.invalidMagic }
        guard bytes[1] == 1 else { throw BLEPacketError.unsupportedVersion }
        guard let state = CodexTaskState(rawValue: bytes[2]) else {
            throw BLEPacketError.invalidState
        }

        return CodexStatusSnapshot(
            state: state,
            progress: bytes[3] == 255 ? nil : min(bytes[3], 100),
            sequence: uint32(bytes, at: 4),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(uint32(bytes, at: 8)))
        )
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ]
    }

    private static func uint32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16
            | UInt32(bytes[index + 3]) << 24
    }
}
