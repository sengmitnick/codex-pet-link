import Foundation

public enum HookFallbackActivity {
    public static let actionTitle = "请信任 Hooks 并新建任务"

    public static func apply(
        to snapshot: TaskActivitySnapshot,
        fallbackState: CodexTaskState,
        at date: Date = Date()
    ) -> TaskActivitySnapshot {
        guard snapshot.activities.isEmpty, fallbackState != .idle else {
            return snapshot
        }
        return TaskActivitySnapshot(activities: [
            TaskActivity(
                sessionID: "codex-pet-link-hook-fallback",
                title: actionTitle,
                state: .needsInput,
                phase: .waitingApproval,
                updatedAt: date
            ),
        ])
    }
}
