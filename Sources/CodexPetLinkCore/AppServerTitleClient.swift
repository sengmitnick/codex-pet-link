import Foundation

public protocol AppServerRequesting: Sendable {
    func request(
        method: String,
        params: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any]
}

public struct AppServerTitleClient: Sendable {
    private let transport: any AppServerRequesting
    private let timeout: TimeInterval

    public init(transport: any AppServerRequesting, timeout: TimeInterval = 2) {
        self.transport = transport
        self.timeout = timeout
    }

    public func title(threadID: String) throws -> String? {
        let response = try transport.request(
            method: "thread/read",
            params: ["threadId": threadID, "includeTurns": false],
            timeout: timeout
        )
        guard let result = response["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any],
              thread["id"] as? String == threadID,
              let name = thread["name"] as? String
        else {
            return nil
        }
        let sanitized = TaskTitle.sanitize(name)
        return sanitized.isEmpty ? nil : sanitized
    }
}

public enum AppServerProcessError: Error {
    case launchFailed
    case invalidRequest
    case writeFailed
    case timedOut
    case invalidResponse
    case serverError(String)
}

public final class AppServerProcessTransport: AppServerRequesting, @unchecked Sendable {
    private final class PendingResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var value: [String: Any]?
    }

    private let requestLock = NSLock()
    private let stateLock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: PendingResponse] = [:]
    private var initialized = false

    public init() {}

    deinit {
        shutdown()
    }

    public func request(
        method: String,
        params: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any] {
        requestLock.lock()
        defer { requestLock.unlock() }
        try startIfNeeded()

        if !initialized {
            _ = try send(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "codex-pet-link",
                        "title": "Codex Pet Link",
                        "version": "0.2.1",
                    ],
                ],
                timeout: timeout
            )
            try sendNotification(method: "initialized", params: [:])
            initialized = true
        }
        return try send(method: method, params: params, timeout: timeout)
    }

    public func shutdown() {
        requestLock.lock()
        defer { requestLock.unlock() }
        resetProcess()
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { self?.receive(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw AppServerProcessError.launchFailed
        }
        self.process = process
        input = inputPipe.fileHandleForWriting
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        initialized = false
    }

    private func send(
        method: String,
        params: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any] {
        stateLock.lock()
        nextID += 1
        let id = nextID
        let waiting = PendingResponse()
        pending[id] = waiting
        stateLock.unlock()

        do {
            try write(["id": id, "method": method, "params": params])
        } catch {
            stateLock.lock()
            pending.removeValue(forKey: id)
            stateLock.unlock()
            throw error
        }

        guard waiting.semaphore.wait(timeout: .now() + timeout) == .success else {
            stateLock.lock()
            pending.removeValue(forKey: id)
            stateLock.unlock()
            resetProcess()
            throw AppServerProcessError.timedOut
        }
        guard let response = waiting.value else { throw AppServerProcessError.invalidResponse }
        if let error = response["error"] as? [String: Any] {
            throw AppServerProcessError.serverError(error["message"] as? String ?? "unknown error")
        }
        return response
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try write(["method": method, "params": params])
    }

    private func write(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object), let input else {
            throw AppServerProcessError.invalidRequest
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)
        } catch {
            throw AppServerProcessError.writeFailed
        }
    }

    private func receive(_ data: Data) {
        stateLock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue ?? object["id"] as? Int,
                  let waiting = pending.removeValue(forKey: id)
            else {
                continue
            }
            waiting.value = object
            waiting.semaphore.signal()
        }
        stateLock.unlock()
    }

    private func resetProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        outputPipe = nil
        errorPipe = nil
        initialized = false
        stateLock.lock()
        buffer.removeAll(keepingCapacity: false)
        let waiters = pending.values
        pending.removeAll()
        stateLock.unlock()
        for waiter in waiters { waiter.semaphore.signal() }
    }
}
