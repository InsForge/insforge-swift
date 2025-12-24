import SwiftUI

struct TodoDetailView: View {
    let todo: Todo
    let onUpdate: (Todo) async -> Void
    let onDelete: () async -> Void

    @State private var editedTodo: Todo
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false

    init(todo: Todo, onUpdate: @escaping (Todo) async -> Void, onDelete: @escaping () async -> Void) {
        self.todo = todo
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self._editedTodo = State(initialValue: todo)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        if isEditing {
                            TextField("Title", text: $editedTodo.title)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                        } else {
                            Text(todo.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        HStack(spacing: 16) {
                            Label(
                                todo.isCompleted ? "Completed" : "Active",
                                systemImage: todo.isCompleted ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundColor(todo.isCompleted ? .green : .secondary)

                            Text("Created \(todo.createdAt, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if isEditing {
                            Button("Cancel") {
                                editedTodo = todo
                                isEditing = false
                            }

                            Button("Save") {
                                Task {
                                    await onUpdate(editedTodo)
                                    isEditing = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(action: { isEditing = true }) {
                                Image(systemName: "pencil")
                            }

                            Button(action: { showingDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                            }
                            .foregroundColor(.red)
                        }
                    }
                }

                Divider()

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)

                    if isEditing {
                        TextEditor(text: Binding(
                            get: { editedTodo.description ?? "" },
                            set: { editedTodo.description = $0.isEmpty ? nil : $0 }
                        ))
                        .frame(minHeight: 100)
                        .border(Color.secondary.opacity(0.3))
                    } else {
                        Text(todo.description ?? "No description")
                            .foregroundColor(todo.description == nil ? .secondary : .primary)
                    }
                }

                Divider()

                // Due Date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Due Date")
                        .font(.headline)

                    if isEditing {
                        Toggle("Set due date", isOn: Binding(
                            get: { editedTodo.dueDate != nil },
                            set: { enabled in
                                if enabled {
                                    editedTodo.dueDate = Date().addingTimeInterval(86400) // Tomorrow
                                } else {
                                    editedTodo.dueDate = nil
                                }
                            }
                        ))

                        if editedTodo.dueDate != nil {
                            DatePicker(
                                "Due date",
                                selection: Binding(
                                    get: { editedTodo.dueDate ?? Date() },
                                    set: { editedTodo.dueDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    } else {
                        if let dueDate = todo.dueDate {
                            HStack {
                                Image(systemName: "calendar")
                                Text(dueDate, style: .date)
                                Text("at")
                                Text(dueDate, style: .time)

                                if dueDate < Date() && !todo.isCompleted {
                                    Text("(Overdue)")
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            Text("No due date set")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Reminder
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Reminder")
                            .font(.headline)

                        Spacer()

                        Image(systemName: "bell.fill")
                            .foregroundColor(.blue)
                    }

                    if isEditing {
                        Toggle("Set reminder", isOn: Binding(
                            get: { editedTodo.reminderDate != nil },
                            set: { enabled in
                                if enabled {
                                    editedTodo.reminderDate = Date().addingTimeInterval(3600) // 1 hour from now
                                } else {
                                    editedTodo.reminderDate = nil
                                }
                            }
                        ))

                        if editedTodo.reminderDate != nil {
                            DatePicker(
                                "Reminder time",
                                selection: Binding(
                                    get: { editedTodo.reminderDate ?? Date() },
                                    set: { editedTodo.reminderDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    } else {
                        if let reminderDate = todo.reminderDate {
                            HStack {
                                Image(systemName: "bell.fill")
                                Text(reminderDate, style: .date)
                                Text("at")
                                Text(reminderDate, style: .time)

                                if reminderDate < Date() {
                                    Text("(Past)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("No reminder set")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text("Metadata")
                        .font(.headline)

                    Text("ID: \(todo.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Last updated: \(todo.updatedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(minWidth: 400, idealWidth: 500)
        .confirmationDialog(
            "Delete Todo",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(todo.title)'? This action cannot be undone.")
        }
        .onAppear {
            editedTodo = todo
        }
    }
}
