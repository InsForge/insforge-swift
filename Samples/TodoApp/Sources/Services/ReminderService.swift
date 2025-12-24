import Foundation
import UserNotifications

@MainActor
class ReminderService: ObservableObject {
    static let shared = ReminderService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    // Request notification permission
    func requestAuthorization() async throws {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        if !granted {
            throw NSError(
                domain: "ReminderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Notification permission denied"]
            )
        }
    }

    // Schedule a reminder for a todo
    func scheduleReminder(for todo: Todo) async throws {
        guard let reminderDate = todo.reminderDate else { return }

        // Remove existing notification if any
        await cancelReminder(for: todo.id)

        // Only schedule if reminder is in the future
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Todo Reminder"
        content.body = todo.title
        content.sound = .default

        if let description = todo.description {
            content.subtitle = description
        }

        // Create trigger
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Create request
        let request = UNNotificationRequest(
            identifier: todo.id,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }

    // Cancel a reminder
    func cancelReminder(for todoId: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [todoId])
    }

    // Cancel all reminders
    func cancelAllReminders() async {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    // Get pending reminders count
    func getPendingRemindersCount() async -> Int {
        let requests = await notificationCenter.pendingNotificationRequests()
        return requests.count
    }
}
