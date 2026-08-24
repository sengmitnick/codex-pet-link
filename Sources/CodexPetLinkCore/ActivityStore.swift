import Foundation

public struct HookInbox {
    public let root: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func prepare() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rejectedDirectory, withIntermediateDirectories: true)
    }

    public func enqueue(_ event: NormalizedHookEvent) throws {
        try prepare()
        let identifier = UUID().uuidString.lowercased()
        let timestamp = UInt64(max(0, event.updatedAt.timeIntervalSince1970 * 1_000))
        let temporary = root.appendingPathComponent(".\(identifier).tmp")
        let destination = root.appendingPathComponent(String(format: "%020llu-%@.json", timestamp, identifier))
        try JSONEncoder().encode(event).write(to: temporary, options: .atomic)
        try fileManager.moveItem(at: temporary, to: destination)
    }

    public func pendingFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    fileprivate func reject(_ file: URL) throws {
        try prepare()
        let destination = rejectedDirectory.appendingPathComponent(file.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: file, to: destination)
    }

    fileprivate func remove(_ file: URL) throws {
        try fileManager.removeItem(at: file)
    }

    private var rejectedDirectory: URL {
        root.appendingPathComponent("rejected", isDirectory: true)
    }
}

public struct ActivityStore: Sendable {
    private var activities: [String: TaskActivity] = [:]
    public static let completedRetention: TimeInterval = 30 * 60

    public init() {}

    public mutating func apply(_ event: NormalizedHookEvent) {
        if let current = activities[event.sessionID], current.updatedAt > event.updatedAt {
            return
        }
        let title = event.title?.isEmpty == false
            ? event.title!
            : activities[event.sessionID]?.title ?? ""
        activities[event.sessionID] = TaskActivity(
            sessionID: event.sessionID,
            title: title,
            state: event.state,
            phase: event.phase,
            updatedAt: event.updatedAt
        )
    }

    public mutating func setTitle(_ title: String, for sessionID: String, at _: Date = Date()) {
        guard var activity = activities[sessionID] else { return }
        let sanitized = TaskTitle.sanitize(title)
        guard !sanitized.isEmpty else { return }
        activity.title = sanitized
        activities[sessionID] = activity
    }

    public mutating func consume(inbox: HookInbox) throws {
        for file in try inbox.pendingFiles() {
            do {
                let event = try JSONDecoder().decode(NormalizedHookEvent.self, from: Data(contentsOf: file))
                apply(event)
                try inbox.remove(file)
            } catch {
                try inbox.reject(file)
            }
        }
    }

    public func snapshot(now: Date = Date(), titlesEnabled: Bool = true) -> TaskActivitySnapshot {
        let visible = activities.values.filter { activity in
            guard activity.state != .idle else { return false }
            if activity.state == .ready,
               now.timeIntervalSince(activity.updatedAt) > Self.completedRetention
            {
                return false
            }
            return true
        }
        .sorted {
            if $0.state.activityPriority != $1.state.activityPriority {
                return $0.state.activityPriority > $1.state.activityPriority
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.sessionID < $1.sessionID
        }

        let additional = max(0, visible.count - 1)
        return TaskActivitySnapshot(
            primary: visible.first?.presented(titlesEnabled: titlesEnabled),
            additionalCount: UInt8(clamping: additional)
        )
    }
}
