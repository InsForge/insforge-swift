import SwiftUI

struct TodoListView: View {
    @StateObject private var service = InsForgeService.shared
    @StateObject private var reminderService = ReminderService.shared

    @State private var todos: [Todo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddTodo = false
    @State private var selectedTodo: Todo?

    var body: some View {
        NavigationSplitView {
            // Sidebar - Todo List
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("My Todos")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: { showingAddTodo = true }) {
                        Image(systemName: "plus")
                    }
                }
                .padding()

                // Todo list
                if isLoading && todos.isEmpty {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if todos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No todos yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Click the + button to add one")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(selection: $selectedTodo) {
                        ForEach(todos) { todo in
                            TodoRowView(todo: todo) {
                                await toggleCompletion(todo)
                            }
                            .tag(todo)
                        }
                        .onDelete(perform: deleteTodos)
                    }
                }

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(8)
                }

                // Bottom toolbar
                HStack {
                    Text("\(todos.count) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { Task { await loadTodos() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                .padding()
            }
            .frame(minWidth: 250, idealWidth: 300)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: { Task { await signOut() } }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .help("Sign Out")
                }
            }
        } detail: {
            // Detail view
            if let todo = selectedTodo {
                TodoDetailView(todo: todo) { updatedTodo in
                    await updateTodo(updatedTodo)
                } onDelete: {
                    await deleteTodo(todo.id)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a todo")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddTodo) {
            AddTodoView { newTodo in
                await createTodo(newTodo)
            }
        }
        .task {
            await requestNotificationPermission()
            await loadTodos()
        }
    }

    // MARK: - Actions

    private func requestNotificationPermission() async {
        do {
            try await reminderService.requestAuthorization()
        } catch {
            print("Failed to get notification permission: \(error)")
        }
    }

    private func loadTodos() async {
        isLoading = true
        errorMessage = nil

        do {
            todos = try await service.fetchTodos()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func createTodo(_ todo: Todo) async {
        do {
            let newTodo = try await service.createTodo(todo)
            todos.insert(newTodo, at: 0)

            if newTodo.reminderDate != nil {
                try await reminderService.scheduleReminder(for: newTodo)
            }

            showingAddTodo = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateTodo(_ todo: Todo) async {
        do {
            let updatedTodo = try await service.updateTodo(todo)

            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                todos[index] = updatedTodo
            }

            // Update reminder
            if updatedTodo.reminderDate != nil {
                try await reminderService.scheduleReminder(for: updatedTodo)
            } else {
                await reminderService.cancelReminder(for: updatedTodo.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTodo(_ todoId: String) async {
        do {
            try await service.deleteTodo(todoId)
            todos.removeAll { $0.id == todoId }
            await reminderService.cancelReminder(for: todoId)
            selectedTodo = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTodos(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let todo = todos[index]
                await deleteTodo(todo.id)
            }
        }
    }

    private func toggleCompletion(_ todo: Todo) async {
        do {
            let updatedTodo = try await service.toggleTodoCompletion(todo)
            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                todos[index] = updatedTodo
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        do {
            try await service.signOut()
            todos = []
            await reminderService.cancelAllReminders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Todo Row View

struct TodoRowView: View {
    let todo: Todo
    let onToggle: () async -> Void

    @State private var isToggling = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { Task { await toggleTodo() } }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(isToggling)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? .secondary : .primary)

                if let dueDate = todo.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(dueDate, style: .date)
                    }
                    .font(.caption)
                    .foregroundColor(dueDate < Date() && !todo.isCompleted ? .red : .secondary)
                }

                if todo.reminderDate != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                        Text("Reminder set")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func toggleTodo() async {
        isToggling = true
        await onToggle()
        isToggling = false
    }
}
