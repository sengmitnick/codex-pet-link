import Foundation

public final class CodexSessionWatcher: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private var offsets: [URL: UInt64] = [:]
    private var partialLines: [URL: String] = [:]
    private var reducers: [URL: SessionEventReducer] = [:]

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

    private func readAppendedLines(from file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        var offset = offsets[file] ?? 0
        if UInt64(fileSize) < offset {
            offset = 0
            partialLines[file] = ""
            reducers[file] = SessionEventReducer()
        }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        offsets[file] = offset + UInt64(data.count)
        guard !data.isEmpty else { return }

        let input = partialLines[file, default: ""] + String(decoding: data, as: UTF8.self)
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        partialLines[file] = lines.removeLast()

        var reducer = reducers[file] ?? SessionEventReducer()
        for line in lines where !line.isEmpty {
            reducer.consume(line: line)
        }
        reducers[file] = reducer
    }
}
