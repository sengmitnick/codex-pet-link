import Foundation

public struct ServicePaths: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var dataDirectory: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/CodexPetLink", isDirectory: true)
    }
    public var binDirectory: URL { dataDirectory.appendingPathComponent("bin", isDirectory: true) }
    public var executable: URL { binDirectory.appendingPathComponent("codex-pet-link") }
    public var commandLink: URL { homeDirectory.appendingPathComponent(".local/bin/codex-pet-link") }
    public var plist: URL { dataDirectory.appendingPathComponent("com.rokid.codex-pet-link.plist") }
    public var inbox: URL { dataDirectory.appendingPathComponent("inbox", isDirectory: true) }
    public var config: URL { dataDirectory.appendingPathComponent("config.json") }
    public var stdoutLog: URL { dataDirectory.appendingPathComponent("codex-pet-link.log") }
    public var stderrLog: URL { dataDirectory.appendingPathComponent("codex-pet-link.error.log") }
    public var sessions: URL {
        if let value = ProcessInfo.processInfo.environment["CODEX_HOME"], !value.isEmpty {
            return URL(fileURLWithPath: value).appendingPathComponent("sessions", isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    }
}
