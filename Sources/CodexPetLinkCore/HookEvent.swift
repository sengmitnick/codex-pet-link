import Foundation

public enum HookKind: String, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case notification = "Notification"
}

public struct NormalizedHookEvent: Codable, Equatable, Sendable {
    public var sessionID: String
    public var turnID: String?
    public var title: String?
    public var state: CodexTaskState
    public var phase: TaskPhase
    public var updatedAt: Date

    public init(
        sessionID: String,
        turnID: String? = nil,
        title: String? = nil,
        state: CodexTaskState,
        phase: TaskPhase,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.title = title.map(TaskTitle.sanitize)
        self.state = state
        self.phase = phase
        self.updatedAt = updatedAt
    }
}

public enum HookEventError: Error, Equatable {
    case malformedJSON
    case missingSessionID
}

public enum HookEvent {
    public static func parse(kind: HookKind, data: Data, now: Date = Date()) throws -> NormalizedHookEvent {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookEventError.malformedJSON
        }
        guard let sessionID = string("session_id", "sessionId", "id", in: root), !sessionID.isEmpty else {
            throw HookEventError.missingSessionID
        }

        let turnID = string("turn_id", "turnId", in: root)
        let status = string("status", in: root)?.lowercased()
        if ["failed", "error", "aborted", "cancelled"].contains(status) {
            return NormalizedHookEvent(
                sessionID: sessionID,
                turnID: turnID,
                state: .blocked,
                phase: .problem,
                updatedAt: now
            )
        }

        switch kind {
        case .sessionStart:
            return NormalizedHookEvent(sessionID: sessionID, turnID: turnID, state: .idle, phase: .idle, updatedAt: now)
        case .userPromptSubmit:
            let title = string("prompt", in: root).map(TaskTitle.sanitize)
            return NormalizedHookEvent(
                sessionID: sessionID,
                turnID: turnID,
                title: title,
                state: .running,
                phase: .thinking,
                updatedAt: now
            )
        case .preToolUse:
            let tool = string("tool_name", "toolName", "name", in: root) ?? ""
            return NormalizedHookEvent(
                sessionID: sessionID,
                turnID: turnID,
                state: .running,
                phase: phase(forTool: tool),
                updatedAt: now
            )
        case .postToolUse:
            return NormalizedHookEvent(sessionID: sessionID, turnID: turnID, state: .running, phase: .thinking, updatedAt: now)
        case .permissionRequest:
            return NormalizedHookEvent(sessionID: sessionID, turnID: turnID, state: .needsInput, phase: .waitingApproval, updatedAt: now)
        case .stop:
            return NormalizedHookEvent(sessionID: sessionID, turnID: turnID, state: .ready, phase: .completed, updatedAt: now)
        case .notification:
            return NormalizedHookEvent(sessionID: sessionID, turnID: turnID, state: .running, phase: .thinking, updatedAt: now)
        }
    }

    private static func phase(forTool value: String) -> TaskPhase {
        let tool = value.lowercased()
        if ["exec_command", "bash", "shell", "terminal"].contains(where: tool.contains) {
            return .runningCommand
        }
        if ["apply_patch", "write", "edit", "patch"].contains(where: tool.contains) {
            return .modifyingFiles
        }
        if ["web", "search", "browser", "open"].contains(where: tool.contains) {
            return .searching
        }
        return .thinking
    }

    private static func string(_ keys: String..., in root: [String: Any]) -> String? {
        for key in keys {
            if let value = root[key] as? String { return value }
        }
        return nil
    }
}
