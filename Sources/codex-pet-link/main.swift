import CodexPetLinkCore
import Foundation

@MainActor
private final class RuntimeController: NSObject {
    private let mode: SourceMode
    private let paths: ServicePaths
    private let watcher: CodexSessionWatcher
    private let inbox: HookInbox
    private let peripheral = CodexBLEPeripheral()
    private let titleTransport = AppServerProcessTransport()
    private var store = ActivityStore()
    private var sequencer = StatusSequencer()
    private var fallbackState: CodexTaskState = .idle
    private var fakeIndex = -1
    private var timer: Timer?
    private var lastWatcherPoll = Date.distantPast
    private var lastConfigPoll = Date.distantPast
    private var titlesEnabled = true
    private var nextTitleAttempt: [String: Date] = [:]

    init(mode: SourceMode, paths: ServicePaths, sessionsRoot: URL) {
        self.mode = mode
        self.paths = paths
        watcher = CodexSessionWatcher(rootURL: sessionsRoot)
        inbox = HookInbox(root: paths.inbox)
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(
            timeInterval: mode == .fake ? 3 : 0.25,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    @objc private func tick() {
        switch mode {
        case .fake:
            publishFakeActivity()
        case .codex:
            pollCodexActivity()
        }
    }

    private func pollCodexActivity(now: Date = Date()) {
        do {
            try store.consume(inbox: inbox)
        } catch {
            Self.writeError("hook inbox failed: \(error)")
        }

        if now.timeIntervalSince(lastConfigPoll) >= 1 {
            titlesEnabled = LinkConfiguration.load(from: paths.config).titlesEnabled
            lastConfigPoll = now
        }
        if now.timeIntervalSince(lastWatcherPoll) >= 1 {
            do {
                fallbackState = try watcher.pollOnce().state
            } catch {
                fallbackState = .blocked
                Self.writeError("session fallback failed: \(error)")
            }
            lastWatcherPoll = now
        }

        var activity = store.snapshot(now: now, titlesEnabled: titlesEnabled)
        if let primary = activity.primary {
            resolveOfficialTitleIfNeeded(for: primary, now: now)
            activity = store.snapshot(now: now, titlesEnabled: titlesEnabled)
        }
        let state = activity.primary?.state ?? fallbackState
        let status = sequencer.snapshot(state: state, at: now)
        peripheral.publish(status, activity: activity)
        Self.writeLog(
            "state=\(state) phase=\(activity.primary?.phase.rawValue ?? 0) titleLength=\(activity.primary?.title.count ?? 0) additional=\(activity.additionalCount)"
        )
    }

    private func resolveOfficialTitleIfNeeded(for activity: TaskActivity, now: Date) {
        guard titlesEnabled,
              now >= nextTitleAttempt[activity.sessionID, default: .distantPast]
        else {
            return
        }
        nextTitleAttempt[activity.sessionID] = now.addingTimeInterval(30)
        do {
            let client = AppServerTitleClient(transport: titleTransport)
            if let title = try client.title(threadID: activity.sessionID) {
                store.setTitle(title, for: activity.sessionID)
                nextTitleAttempt[activity.sessionID] = .distantFuture
            }
        } catch {
            Self.writeError("thread title unavailable for session=\(activity.sessionID): \(error)")
        }
    }

    private func publishFakeActivity() {
        let samples: [(String, CodexTaskState, TaskPhase)] = [
            ("连接 Codex", .running, .thinking),
            ("连接 Codex", .running, .runningCommand),
            ("优化引导", .running, .modifyingFiles),
            ("优化引导", .needsInput, .waitingApproval),
            ("优化引导", .ready, .completed),
        ]
        fakeIndex = (fakeIndex + 1) % samples.count
        let sample = samples[fakeIndex]
        let task = TaskActivity(
            sessionID: "fake-session",
            title: sample.0,
            state: sample.1,
            phase: sample.2,
            updatedAt: Date()
        )
        let activity = TaskActivitySnapshot(primary: task)
        peripheral.publish(sequencer.snapshot(state: sample.1), activity: activity)
        Self.writeLog("fake state=\(sample.1) phase=\(sample.2) titleLength=\(sample.0.count)")
    }

    private static func writeLog(_ message: String) {
        print("codex-pet-link: \(message)")
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("codex-pet-link: \(message)\n".utf8))
    }
}

private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

private struct ServiceStatus: Codable {
    var loaded: Bool
    var executable: String
    var dataDirectory: String
}

@MainActor
private func run(_ command: CLICommand) throws {
    let paths = ServicePaths()
    let service = LaunchAgentController(paths: paths)

    switch command {
    case let .run(source, sessions):
        let sessionsRoot = sessions.map(URL.init(fileURLWithPath:)) ?? paths.sessions
        let controller = RuntimeController(mode: source, paths: paths, sessionsRoot: sessionsRoot)
        print("codex-pet-link: source=\(source.rawValue) sessions=\(sessionsRoot.path)")
        controller.start()
        RunLoop.main.run()
    case .ensure, .start:
        print("codex-pet-link: \(try service.ensure().rawValue)")
    case .stop:
        print("codex-pet-link: \(try service.stop() ? "stopped" : "notLoaded")")
    case .restart:
        _ = try service.stop()
        print("codex-pet-link: \(try service.ensure().rawValue)")
    case let .status(json):
        let status = ServiceStatus(
            loaded: service.isLoaded(),
            executable: paths.executable.path,
            dataDirectory: paths.dataDirectory.path
        )
        if json {
            try printJSON(status)
        } else {
            print("loaded: \(status.loaded)\nexecutable: \(status.executable)\ndata: \(status.dataDirectory)")
        }
    case let .doctor(json):
        let report = Doctor(paths: paths, serviceLoaded: service.isLoaded).inspect()
        if json {
            try printJSON(report)
        } else {
            print("overall: \(report.overall.rawValue)")
            print("executable: \(report.executableInstalled)")
            print("sessions: \(report.sessionsAvailable)")
            print("service: \(report.serviceLoaded)")
        }
    case let .hook(kind):
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let event = try HookEvent.parse(kind: kind, data: input)
        try HookInbox(root: paths.inbox).enqueue(event)
        print("codex-pet-link: queued session=\(event.sessionID) state=\(event.state) phase=\(event.phase)")
    case let .privacy(titlesEnabled):
        try LinkConfiguration(titlesEnabled: titlesEnabled).save(to: paths.config)
        print("codex-pet-link: titles \(titlesEnabled ? "enabled" : "disabled")")
    }
}

do {
    try run(CLICommand.parse(Array(CommandLine.arguments.dropFirst())))
} catch {
    FileHandle.standardError.write(Data("codex-pet-link: \(error)\n".utf8))
    FileHandle.standardError.write(Data("usage: codex-pet-link run|ensure|start|stop|restart|status|doctor|hook EVENT|privacy titles-on|titles-off\n".utf8))
    exit(2)
}
