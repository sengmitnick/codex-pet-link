import Foundation

public protocol LaunchCommandRunning: Sendable {
    func run(_ arguments: [String]) -> Int32
}

public struct ProcessLaunchCommandRunner: LaunchCommandRunning {
    public init() {}

    public func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}

public enum EnsureResult: String, Equatable, Sendable {
    case alreadyRunning
    case started
}

public enum LaunchAgentError: Error, Equatable {
    case bootstrapFailed(Int32)
    case bootoutFailed(Int32)
    case restartTimedOut
}

public struct LaunchAgentController: Sendable {
    public static let label = "com.rokid.codex-pet-link"

    public let paths: ServicePaths
    public let uid: uid_t
    private let runner: any LaunchCommandRunning

    public init(
        paths: ServicePaths = ServicePaths(),
        uid: uid_t = getuid(),
        runner: any LaunchCommandRunning = ProcessLaunchCommandRunner()
    ) {
        self.paths = paths
        self.uid = uid
        self.runner = runner
    }

    public static func plistData(paths: ServicePaths) throws -> Data {
        let executablePath = [
            "/Applications/ChatGPT.app/Contents/Resources",
            paths.homeDirectory.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
        let value: [String: Any] = [
            "Label": label,
            "ProgramArguments": [paths.executable.path, "run"],
            "EnvironmentVariables": ["PATH": executablePath],
            "RunAtLoad": false,
            "KeepAlive": true,
            "StandardOutPath": paths.stdoutLog.path,
            "StandardErrorPath": paths.stderrLog.path,
            "ProcessType": "Interactive",
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
    }

    public func isLoaded() -> Bool {
        runner.run(["print", serviceTarget]) == 0
    }

    public func ensure() throws -> EnsureResult {
        if isLoaded() { return .alreadyRunning }
        try FileManager.default.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)
        try Self.plistData(paths: paths).write(to: paths.plist, options: .atomic)
        let status = runner.run(["bootstrap", domainTarget, paths.plist.path])
        guard status == 0 else { throw LaunchAgentError.bootstrapFailed(status) }
        return .started
    }

    @discardableResult
    public func stop() throws -> Bool {
        guard isLoaded() else { return false }
        let status = runner.run(["bootout", serviceTarget])
        guard status == 0 else { throw LaunchAgentError.bootoutFailed(status) }
        return true
    }

    public func restart(
        maxWaitAttempts: Int = 40,
        waitInterval: TimeInterval = 0.05
    ) throws -> EnsureResult {
        _ = try stop()
        for _ in 0..<max(0, maxWaitAttempts) {
            if !isLoaded() { return try ensure() }
            if waitInterval > 0 {
                Thread.sleep(forTimeInterval: waitInterval)
            }
        }
        guard !isLoaded() else { throw LaunchAgentError.restartTimedOut }
        return try ensure()
    }

    private var domainTarget: String { "gui/\(uid)" }
    private var serviceTarget: String { "\(domainTarget)/\(Self.label)" }
}
