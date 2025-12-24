import Foundation

struct Todo: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var description: String?
    var isCompleted: Bool
    var dueDate: Date?
    var reminderDate: Date?
    let userId: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case isCompleted = "is_completed"
        case dueDate = "due_date"
        case reminderDate = "reminder_date"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        userId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
