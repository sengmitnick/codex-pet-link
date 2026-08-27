import Foundation

public struct CodexSessionActivity: Equatable, Sendable {
    public var sessionID: String
    public var state: CodexTaskState
    public var updatedAt: Date

    public init(sessionID: String, state: CodexTaskState, updatedAt: Date) {
        self.sessionID = sessionID
        self.state = state
        self.updatedAt = updatedAt
    }
}

public final class CodexSessionWatcher: @unchecked Sendable {
    private static let initialReplayLimit: UInt64 = 512 * 1_024
    private let rootURL: URL
    private let fileManager: FileManager
    private var offsets: [URL: UInt64] = [:]
    private var partialLines: [URL: String] = [:]
    private var reducers: [URL: SessionEventReducer] = [:]
    private var sessionFiles: [String: URL] = [:]
    private var initialReplayBytes: [String: UInt64] = [:]

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func pollOnce() throws -> CodexStatusSnapshot {
        guard let file = try newestSessionFile() else {
            return CodexStatusSnapshot(
                state: .idle,
                progress: nil,
                sequence: 0,
                updatedAt: Date()
            )
        }

        try readAppendedLines(from: file)
        let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return CodexStatusSnapshot(
            state: reducers[file]?.state ?? .idle,
            progress: nil,
            sequence: UInt32(truncatingIfNeeded: fileSize),
            updatedAt: Date()
        )
    }

    public func pollStates(for sessionIDs: Set<String>) throws -> [String: CodexTaskState] {
        guard !sessionIDs.isEmpty else { return [:] }
        try resolveSessionFiles(for: sessionIDs)

        var states: [String: CodexTaskState] = [:]
        for sessionID in sessionIDs {
            guard let file = sessionFiles[sessionID] else { continue }
            try readAppendedLines(from: file)
            states[sessionID] = reducers[file]?.state ?? .idle
        }
        return states
    }

    func initialReplayByteCount(for file: URL) -> UInt64? {
        initialReplayBytes[file.standardizedFileURL.path]
    }

    public func pollRecentActivities(
        since date: Date,
        limit: Int
    ) throws -> [CodexSessionActivity] {
        guard limit > 0,
              fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                  at: rootURL,
                  includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var recent: [(url: URL, updatedAt: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true,
                  let updatedAt = values.contentModificationDate,
                  updatedAt >= date,
                  sessionID(from: url) != nil
            else {
                continue
            }
            recent.append((url, updatedAt))
        }
        recent.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.url.path > $1.url.path
        }

        var activities: [CodexSessionActivity] = []
        for candidate in recent.prefix(limit) {
            guard let sessionID = sessionID(from: candidate.url) else { continue }
            sessionFiles[sessionID] = candidate.url
            try readAppendedLines(from: candidate.url)
            let reducedState = reducers[candidate.url]?.state ?? .idle
            let state: CodexTaskState = reducedState == .idle ? .running : reducedState
            activities.append(CodexSessionActivity(
                sessionID: sessionID,
                state: state,
                updatedAt: candidate.updatedAt
            ))
        }
        return activities
    }

    private func newestSessionFile() throws -> URL? {
        guard fileManager.fileExists(atPath: rootURL.path) else { return nil }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var newest: (url: URL, modifiedAt: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if newest == nil
                || modifiedAt > newest!.modifiedAt
                || (modifiedAt == newest!.modifiedAt && url.path > newest!.url.path)
            {
                newest = (url, modifiedAt)
            }
        }
        return newest?.url
    }

    private func resolveSessionFiles(for sessionIDs: Set<String>) throws {
        let missing = sessionIDs.filter { sessionFiles[$0] == nil }
        guard !missing.isEmpty,
              fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                  at: rootURL,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return
        }

        var unresolved = Set(missing)
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            for sessionID in unresolved where url.lastPathComponent.contains(sessionID) {
                sessionFiles[sessionID] = url
                unresolved.remove(sessionID)
            }
            if unresolved.isEmpty { break }
        }
    }

    private func sessionID(from url: URL) -> String? {
        let name = url.lastPathComponent
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: name,
                  range: NSRange(name.startIndex..., in: name)
              ),
              let range = Range(match.range, in: name)
        else {
            return nil
        }
        return String(name[range])
    }

    private func readAppendedLines(from file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let isInitialReplay = offsets[file] == nil
        var offset = offsets[file] ?? 0
        if isInitialReplay, UInt64(fileSize) > Self.initialReplayLimit {
            offset = UInt64(fileSize) - Self.initialReplayLimit
        }
        if UInt64(fileSize) < offset {
            offset = 0
            partialLines[file] = ""
            reducers[file] = SessionEventReducer()
        }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        offsets[file] = offset + UInt64(data.count)
        if isInitialReplay {
            initialReplayBytes[file.standardizedFileURL.path] = UInt64(data.count)
        }
        guard !data.isEmpty else { return }

        var appended = String(decoding: data, as: UTF8.self)
        if isInitialReplay, offset > 0 {
            guard let newline = appended.firstIndex(of: "\n") else {
                partialLines[file] = ""
                return
            }
            appended = String(appended[appended.index(after: newline)...])
        }
        let input = partialLines[file, default: ""] + appended
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        partialLines[file] = lines.removeLast()

        var reducer = reducers[file] ?? SessionEventReducer()
        for line in lines where !line.isEmpty {
            reducer.consume(line: line)
        }
        reducers[file] = reducer
    }
}
