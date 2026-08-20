import CodexPetLinkCore
import Foundation

private enum SourceMode: String {
    case fake
    case codex
}

@MainActor
private final class RuntimeController: NSObject {
    private let mode: SourceMode
    private let watcher: CodexSessionWatcher
    private let peripheral = CodexBLEPeripheral()
    private var sequencer = StatusSequencer()
    private var fakeIndex = -1
    private var timer: Timer?

    init(mode: SourceMode, sessionsRoot: URL) {
        self.mode = mode
        watcher = CodexSessionWatcher(rootURL: sessionsRoot)
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(
            timeInterval: mode == .fake ? 5 : 1,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func tick() {
        switch mode {
        case .fake:
            let states = CodexTaskState.allCases
            fakeIndex = (fakeIndex + 1) % states.count
            publish(state: states[fakeIndex])
        case .codex:
            do {
                let status = try watcher.pollOnce()
                let snapshot = sequencer.snapshot(state: status.state, progress: status.progress)
                peripheral.publish(snapshot)
                print("codex-pet-link: state=\(snapshot.state)")
            } catch {
                publish(state: .blocked)
                Self.writeError("session watcher failed: \(error)")
            }
        }
    }

    private func publish(state: CodexTaskState) {
        peripheral.publish(sequencer.snapshot(state: state))
        print("codex-pet-link: state=\(state)")
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("codex-pet-link: \(message)\n".utf8))
    }
}

private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1)
    else {
        return nil
    }
    return arguments[index + 1]
}

let arguments = CommandLine.arguments
let modeName = value(after: "--source", in: arguments) ?? SourceMode.codex.rawValue
guard let mode = SourceMode(rawValue: modeName) else {
    FileHandle.standardError.write(Data("Usage: codex-pet-link --source fake|codex [--sessions PATH]\n".utf8))
    exit(2)
}
let sessionsRoot = value(after: "--sessions", in: arguments).map(URL.init(fileURLWithPath:))
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
private let controller = RuntimeController(mode: mode, sessionsRoot: sessionsRoot)
print("codex-pet-link: source=\(mode.rawValue) sessions=\(sessionsRoot.path)")
controller.start()
RunLoop.main.run()
