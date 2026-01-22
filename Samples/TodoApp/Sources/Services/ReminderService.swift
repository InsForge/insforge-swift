import Foundation

@MainActor
class ReminderService: ObservableObject {
    static let shared = ReminderService()

    private init() {}

    // Request notification permission (no-op for now)
    func requestAuthorization() async throws {
        // TODO: Implement when bundleIdentifier is available
    }

    // Schedule a reminder for a todo (no-op for now)
    func scheduleReminder(for todo: Todo) async throws {
        // TODO: Implement when bundleIdentifier is available
    }

    // Cancel a reminder (no-op for now)
    func cancelReminder(for todoId: String) async {
        // TODO: Implement when bundleIdentifier is available
    }

    // Cancel all reminders (no-op for now)
    func cancelAllReminders() async {
        // TODO: Implement when bundleIdentifier is available
    }

    // Get pending reminders count (no-op for now)
    func getPendingRemindersCount() async -> Int {
        return 0
    }
}
