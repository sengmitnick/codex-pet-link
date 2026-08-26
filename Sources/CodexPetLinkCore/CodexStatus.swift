import Foundation

public enum CodexTaskState: UInt8, CaseIterable, Codable, Sendable {
    case idle = 0
    case running = 1
    case needsInput = 2
    case ready = 3
    case blocked = 4
}

public extension CodexTaskState {
    var activityPriority: Int {
        switch self {
        case .needsInput: 4
        case .blocked: 3
        case .running: 2
        case .ready: 1
        case .idle: 0
        }
    }
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

public struct StatusSequencer: Sendable {
    private var sequence: UInt32 = 0
    private var previousState: CodexTaskState?

    public init() {}

    public mutating func snapshot(
        state: CodexTaskState,
        progress: UInt8? = nil,
        at date: Date = Date()
    ) -> CodexStatusSnapshot {
        if previousState != state {
            sequence &+= 1
            previousState = state
        }
        return CodexStatusSnapshot(
            state: state,
            progress: progress,
            sequence: sequence,
            updatedAt: date
        )
    }
}
