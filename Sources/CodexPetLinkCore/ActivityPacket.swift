import Foundation

public struct BLEActivity: Equatable, Sendable {
    public var state: CodexTaskState
    public var phase: TaskPhase
    public var title: String
    public var additionalCount: UInt8

    public init(
        state: CodexTaskState,
        phase: TaskPhase,
        title: String,
        additionalCount: UInt8
    ) {
        self.state = state
        self.phase = phase
        self.title = TaskTitle.sanitize(title)
        self.additionalCount = additionalCount
    }

    public init(_ snapshot: TaskActivitySnapshot) {
        state = snapshot.primary?.state ?? .idle
        phase = snapshot.primary?.phase ?? .idle
        title = TaskTitle.sanitize(snapshot.primary?.title ?? "")
        additionalCount = snapshot.additionalCount
    }
}

public enum ActivityPacketError: Error, Equatable {
    case empty
    case invalidFrame
    case mixedSequence
    case incomplete
    case invalidPayload
}

public enum ActivityPacket {
    public static let magic: UInt8 = 0xC8
    public static let version: UInt8 = 1
    public static let maximumFrameBytes = 20
    public static let headerBytes = 7
    public static let payloadBytesPerFrame = maximumFrameBytes - headerBytes
    public static let maximumFrames = 6

    public static func encode(_ snapshot: TaskActivitySnapshot, sequence: UInt16) -> [Data] {
        encode(BLEActivity(snapshot), sequence: sequence)
    }

    public static func encode(_ activity: BLEActivity, sequence: UInt16) -> [Data] {
        let title = truncatedUTF8(activity.title, limit: TaskTitle.maximumUTF8Bytes)
        let titleBytes = [UInt8](title.utf8)
        let payload = [
            activity.state.rawValue,
            activity.phase.rawValue,
            activity.additionalCount,
            UInt8(titleBytes.count),
        ] + titleBytes
        let count = max(1, Int(ceil(Double(payload.count) / Double(payloadBytesPerFrame))))

        return (0..<count).map { index in
            let start = index * payloadBytesPerFrame
            let end = min(start + payloadBytesPerFrame, payload.count)
            let chunk = Array(payload[start..<end])
            return Data([
                magic,
                version,
                UInt8(truncatingIfNeeded: sequence),
                UInt8(truncatingIfNeeded: sequence >> 8),
                UInt8(index),
                UInt8(count),
                UInt8(chunk.count),
            ] + chunk)
        }
    }

    public static func decode<S: Sequence>(_ frames: S) throws -> BLEActivity where S.Element == Data {
        let input = Array(frames)
        guard let first = input.first else { throw ActivityPacketError.empty }
        let firstBytes = [UInt8](first)
        guard firstBytes.count >= headerBytes else { throw ActivityPacketError.invalidFrame }
        let expectedSequence = UInt16(firstBytes[2]) | UInt16(firstBytes[3]) << 8
        let expectedCount = Int(firstBytes[5])
        guard (1...maximumFrames).contains(expectedCount) else { throw ActivityPacketError.invalidFrame }

        var chunks: [Int: [UInt8]] = [:]
        for frame in input {
            let bytes = [UInt8](frame)
            guard bytes.count >= headerBytes,
                  bytes.count <= maximumFrameBytes,
                  bytes[0] == magic,
                  bytes[1] == version,
                  Int(bytes[5]) == expectedCount,
                  Int(bytes[6]) == bytes.count - headerBytes
            else {
                throw ActivityPacketError.invalidFrame
            }
            let sequence = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
            guard sequence == expectedSequence else { throw ActivityPacketError.mixedSequence }
            let index = Int(bytes[4])
            guard index < expectedCount, chunks[index] == nil else { throw ActivityPacketError.invalidFrame }
            chunks[index] = Array(bytes.dropFirst(headerBytes))
        }
        guard chunks.count == expectedCount else { throw ActivityPacketError.incomplete }
        let payload = (0..<expectedCount).flatMap { chunks[$0] ?? [] }
        guard payload.count >= 4,
              let state = CodexTaskState(rawValue: payload[0]),
              let phase = TaskPhase(rawValue: payload[1])
        else {
            throw ActivityPacketError.invalidPayload
        }
        let titleLength = Int(payload[3])
        guard payload.count == 4 + titleLength,
              let title = String(bytes: payload.dropFirst(4), encoding: .utf8)
        else {
            throw ActivityPacketError.invalidPayload
        }
        return BLEActivity(
            state: state,
            phase: phase,
            title: title,
            additionalCount: payload[2]
        )
    }

    private static func truncatedUTF8(_ value: String, limit: Int) -> String {
        var result = ""
        for character in value {
            let candidate = result + String(character)
            guard candidate.utf8.count <= limit else { break }
            result = candidate
        }
        return result
    }
}

public struct BLEActivityItem: Equatable, Sendable {
    public var state: CodexTaskState
    public var phase: TaskPhase
    public var title: String

    public init(state: CodexTaskState, phase: TaskPhase, title: String) {
        self.state = state
        self.phase = phase
        self.title = TaskTitle.sanitize(title)
    }

    public init(_ activity: TaskActivity) {
        self.init(state: activity.state, phase: activity.phase, title: activity.title)
    }
}

/// Full Codex Pet-style activity tray. Version 1 remains available on the same
/// characteristic so older glasses builds can continue showing the primary task.
public enum ActivityListPacket {
    public static let magic = ActivityPacket.magic
    public static let version: UInt8 = 2
    public static let maximumFrameBytes = ActivityPacket.maximumFrameBytes
    public static let headerBytes = ActivityPacket.headerBytes
    public static let payloadBytesPerFrame = ActivityPacket.payloadBytesPerFrame
    public static let maximumFrames = 255

    public static func encode(_ snapshot: TaskActivitySnapshot, sequence: UInt16) -> [Data] {
        encode(snapshot.activities.map(BLEActivityItem.init), sequence: sequence)
    }

    public static func encode(_ activities: [BLEActivityItem], sequence: UInt16) -> [Data] {
        // 32 full-length titles fit in the one-byte frame count while covering
        // far more concurrent work than the pet tray can reasonably present.
        let visible = Array(activities.prefix(32))
        var payload = [UInt8(visible.count)]
        for activity in visible {
            let title = truncatedUTF8(activity.title, limit: TaskTitle.maximumUTF8Bytes)
            let titleBytes = [UInt8](title.utf8)
            payload.append(activity.state.rawValue)
            payload.append(activity.phase.rawValue)
            payload.append(UInt8(titleBytes.count))
            payload.append(contentsOf: titleBytes)
        }
        let count = max(1, Int(ceil(Double(payload.count) / Double(payloadBytesPerFrame))))
        precondition(count <= maximumFrames)

        return (0..<count).map { index in
            let start = index * payloadBytesPerFrame
            let end = min(start + payloadBytesPerFrame, payload.count)
            let chunk = Array(payload[start..<end])
            return Data([
                magic,
                version,
                UInt8(truncatingIfNeeded: sequence),
                UInt8(truncatingIfNeeded: sequence >> 8),
                UInt8(index),
                UInt8(count),
                UInt8(chunk.count),
            ] + chunk)
        }
    }

    public static func decode<S: Sequence>(_ frames: S) throws -> [BLEActivityItem] where S.Element == Data {
        let input = Array(frames)
        guard let first = input.first else { throw ActivityPacketError.empty }
        let firstBytes = [UInt8](first)
        guard firstBytes.count >= headerBytes else { throw ActivityPacketError.invalidFrame }
        let expectedSequence = UInt16(firstBytes[2]) | UInt16(firstBytes[3]) << 8
        let expectedCount = Int(firstBytes[5])
        guard (1...maximumFrames).contains(expectedCount) else { throw ActivityPacketError.invalidFrame }

        var chunks: [Int: [UInt8]] = [:]
        for frame in input {
            let bytes = [UInt8](frame)
            guard bytes.count >= headerBytes,
                  bytes.count <= maximumFrameBytes,
                  bytes[0] == magic,
                  bytes[1] == version,
                  Int(bytes[5]) == expectedCount,
                  Int(bytes[6]) == bytes.count - headerBytes
            else {
                throw ActivityPacketError.invalidFrame
            }
            let sequence = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
            guard sequence == expectedSequence else { throw ActivityPacketError.mixedSequence }
            let index = Int(bytes[4])
            guard index < expectedCount, chunks[index] == nil else { throw ActivityPacketError.invalidFrame }
            chunks[index] = Array(bytes.dropFirst(headerBytes))
        }
        guard chunks.count == expectedCount else { throw ActivityPacketError.incomplete }
        let payload = (0..<expectedCount).flatMap { chunks[$0] ?? [] }
        guard let taskCount = payload.first else { throw ActivityPacketError.invalidPayload }

        var offset = 1
        var result: [BLEActivityItem] = []
        for _ in 0..<Int(taskCount) {
            guard offset + 3 <= payload.count,
                  let state = CodexTaskState(rawValue: payload[offset]),
                  let phase = TaskPhase(rawValue: payload[offset + 1])
            else {
                throw ActivityPacketError.invalidPayload
            }
            let titleLength = Int(payload[offset + 2])
            offset += 3
            guard offset + titleLength <= payload.count,
                  let title = String(bytes: payload[offset..<(offset + titleLength)], encoding: .utf8)
            else {
                throw ActivityPacketError.invalidPayload
            }
            result.append(BLEActivityItem(state: state, phase: phase, title: title))
            offset += titleLength
        }
        guard offset == payload.count else { throw ActivityPacketError.invalidPayload }
        return result
    }

    private static func truncatedUTF8(_ value: String, limit: Int) -> String {
        var result = ""
        for character in value {
            let candidate = result + String(character)
            guard candidate.utf8.count <= limit else { break }
            result = candidate
        }
        return result
    }
}
