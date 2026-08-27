import Foundation

public struct TitleResolutionScheduler: Sendable {
    private let retryInterval: TimeInterval
    private var nextAttempt: [String: Date] = [:]
    private var resolvedSessionIDs = Set<String>()

    public init(retryInterval: TimeInterval = 30) {
        self.retryInterval = retryInterval
    }

    public mutating func nextActivity(
        in activities: [TaskActivity],
        at date: Date = Date()
    ) -> TaskActivity? {
        guard let activity = activities.first(where: {
            !resolvedSessionIDs.contains($0.sessionID)
                && date >= nextAttempt[$0.sessionID, default: .distantPast]
        }) else {
            return nil
        }
        nextAttempt[activity.sessionID] = date.addingTimeInterval(retryInterval)
        return activity
    }

    public mutating func markResolved(sessionID: String) {
        resolvedSessionIDs.insert(sessionID)
        nextAttempt.removeValue(forKey: sessionID)
    }
}
