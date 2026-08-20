import Foundation

public enum CodexTaskState: UInt8, CaseIterable, Sendable {
    case idle = 0
    case running = 1
    case needsInput = 2
    case ready = 3
    case blocked = 4
}

public struct CodexStatusSnapshot: Equatable, Sendable {
    public var state: CodexTaskState
    public var progress: UInt8?
    public var sequence: UInt32
    public var updatedAt: Date

    public init(
        state: CodexTaskState,
        progress: UInt8?,
        sequence: UInt32,
        updatedAt: Date
    ) {
        self.state = state
        self.progress = progress.map { min($0, 100) }
        self.sequence = sequence
        self.updatedAt = updatedAt
    }
}
