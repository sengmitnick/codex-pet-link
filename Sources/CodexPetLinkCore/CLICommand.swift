import Foundation

public enum SourceMode: String, Equatable, Sendable {
    case fake
    case codex
}

public enum CLICommand: Equatable, Sendable {
    case run(source: SourceMode, sessions: String?)
    case ensure
    case start
    case stop
    case restart
    case status(json: Bool)
    case doctor(json: Bool)
    case hook(HookKind)
    case privacy(titlesEnabled: Bool)

    public static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else { return .run(source: .codex, sessions: nil) }
        if first.hasPrefix("--") {
            return try parseRun(arguments)
        }
        switch first {
        case "run": return try parseRun(Array(arguments.dropFirst()))
        case "ensure": return .ensure
        case "start": return .start
        case "stop": return .stop
        case "restart": return .restart
        case "status": return .status(json: arguments.contains("--json"))
        case "doctor": return .doctor(json: arguments.contains("--json"))
        case "hook":
            guard arguments.count == 2, let kind = HookKind(rawValue: arguments[1]) else {
                throw CLICommandError.invalidHook
            }
            return .hook(kind)
        case "privacy":
            guard arguments.count == 2 else { throw CLICommandError.invalidPrivacy }
            if arguments[1] == "titles-on" { return .privacy(titlesEnabled: true) }
            if arguments[1] == "titles-off" { return .privacy(titlesEnabled: false) }
            throw CLICommandError.invalidPrivacy
        default:
            throw CLICommandError.unknownCommand(first)
        }
    }

    private static func parseRun(_ arguments: [String]) throws -> CLICommand {
        let sourceName = value(after: "--source", in: arguments) ?? SourceMode.codex.rawValue
        guard let source = SourceMode(rawValue: sourceName) else { throw CLICommandError.invalidSource }
        return .run(source: source, sessions: value(after: "--sessions", in: arguments))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

public enum CLICommandError: Error, Equatable {
    case unknownCommand(String)
    case invalidSource
    case invalidHook
    case invalidPrivacy
}
