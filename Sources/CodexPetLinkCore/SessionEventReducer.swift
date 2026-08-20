import Foundation

public struct SessionEventReducer: Sendable {
    public private(set) var state: CodexTaskState = .idle
    public private(set) var invalidLineCount = 0

    private var pendingInputCallIDs = Set<String>()

    public init() {}

    public mutating func consume(line: String) {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            invalidLineCount += 1
            return
        }

        let payload = root["payload"] as? [String: Any] ?? [:]
        let payloadType = payload["type"] as? String ?? ""
        let status = (payload["status"] as? String ?? "").lowercased()

        if payloadType == "custom_tool_call",
           Self.inputRequestNames.contains(payload["name"] as? String ?? ""),
           let callID = payload["call_id"] as? String
        {
            pendingInputCallIDs.insert(callID)
            state = .needsInput
            return
        }

        if payloadType == "custom_tool_call_output",
           let callID = payload["call_id"] as? String
        {
            pendingInputCallIDs.remove(callID)
            if pendingInputCallIDs.isEmpty, state == .needsInput {
                state = .running
            }
            return
        }

        if Self.failureStatuses.contains(status) || Self.failureEventTypes.contains(payloadType) {
            pendingInputCallIDs.removeAll()
            state = .blocked
            return
        }

        switch payloadType {
        case "task_started":
            pendingInputCallIDs.removeAll()
            state = .running
        case "task_complete":
            pendingInputCallIDs.removeAll()
            state = .ready
        default:
            break
        }
    }

    private static let inputRequestNames: Set<String> = [
        "request_user_input",
        "approval_request",
        "request_approval",
    ]

    private static let failureStatuses: Set<String> = [
        "failed",
        "error",
        "aborted",
        "cancelled",
    ]

    private static let failureEventTypes: Set<String> = [
        "task_failed",
        "turn_aborted",
        "stream_error",
        "error",
    ]
}
