import SwiftUI

struct AddTodoView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = InsForgeService.shared

    let onAdd: (Todo) async -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400) // Tomorrow
    @State private var hasReminder = false
    @State private var reminderDate = Date().addingTimeInterval(3600) // 1 hour from now
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Todo")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTitleFocused)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $description)
                            .frame(height: 80)
                            .border(Color.secondary.opacity(0.3))
                    }
                }
                .onAppear {
                    // Auto-focus title field when view appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTitleFocused = true
                    }
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Due date",
                            selection: $dueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                Section("Reminder") {
                    Toggle("Set reminder", isOn: $hasReminder)

                    if hasReminder {
                        DatePicker(
                            "Reminder time",
                            selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        if reminderDate < Date() {
                            Text("Reminder time must be in the future")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Todo") {
                    addTodo()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private var isFormValid: Bool {
        !title.isEmpty && (!hasReminder || reminderDate > Date())
    }

    private func addTodo() {
        guard let userId = service.currentUser?.id else { return }

        let todo = Todo(
            title: title,
            description: description.isEmpty ? nil : description,
            dueDate: hasDueDate ? dueDate : nil,
            reminderDate: hasReminder ? reminderDate : nil,
            userId: userId
        )

        Task {
            await onAdd(todo)
        }
    }
}
