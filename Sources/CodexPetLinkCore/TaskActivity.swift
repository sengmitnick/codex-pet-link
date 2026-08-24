import Foundation

public enum TaskPhase: UInt8, Codable, CaseIterable, Sendable {
    case idle = 0
    case thinking = 1
    case runningCommand = 2
    case modifyingFiles = 3
    case searching = 4
    case waitingApproval = 5
    case completed = 6
    case problem = 7
}

public struct TaskActivity: Codable, Equatable, Sendable {
    public var sessionID: String
    public var title: String
    public var state: CodexTaskState
    public var phase: TaskPhase
    public var updatedAt: Date

    public init(
        sessionID: String,
        title: String,
        state: CodexTaskState,
        phase: TaskPhase,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.title = TaskTitle.sanitize(title)
        self.state = state
        self.phase = phase
        self.updatedAt = updatedAt
    }

    public func presented(titlesEnabled: Bool) -> TaskActivity {
        var copy = self
        if !titlesEnabled { copy.title = "" }
        return copy
    }
}

public struct TaskActivitySnapshot: Equatable, Sendable {
    public var primary: TaskActivity?
    public var additionalCount: UInt8

    public init(primary: TaskActivity?, additionalCount: UInt8 = 0) {
        self.primary = primary
        self.additionalCount = additionalCount
    }
}

public enum TaskTitle {
    public static let maximumCharacters = 24
    public static let maximumUTF8Bytes = 72

    public static func sanitize(_ value: String) -> String {
        var result = replacing(#"```[\s\S]*?```"#, in: value, with: " ")
        result = replacing(#"<(?:image|attachment)\b[^>]*>"#, in: result, with: " ")
        result = replacing(#"(?:file://)?/(?:[^\s/]+/)*[^\s]+"#, in: result, with: " ")
        result = replacing(#"\s+"#, in: result, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var output = ""
        for character in result {
            guard output.count < maximumCharacters else { break }
            let candidate = output + String(character)
            guard candidate.utf8.count <= maximumUTF8Bytes else { break }
            output = candidate
        }
        return output
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}
