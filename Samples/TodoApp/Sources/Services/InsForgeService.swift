import Foundation
import InsForge
import InsForgeAuth
import InsForgeDatabase
import InsForgeCore
import InsForgeRealtime

@MainActor
class InsForgeService: ObservableObject {
    static let shared = InsForgeService()

    @Published var currentUser: User?
    @Published var isAuthenticated = false

    private let client: InsForgeClient

    private init() {
        // Load configuration from Config.swift
        guard let url = URL(string: Config.insForgeURL) else {
            fatalError("Invalid InsForge URL in Config.swift. Please check your configuration.")
        }

        print("[TodoApp] Initializing InsForgeClient with URL: \(Config.insForgeURL)")

        self.client = InsForgeClient(
            baseURL: url,
            anonKey: Config.anonKey,
            options: InsForgeClientOptions(
                global: InsForgeClientOptions.GlobalOptions(
                    logger: ConsoleLogger()
                )
            )
        )

        // Check for existing session to auto-login user
        Task { @MainActor in
            await checkExistingSession()
        }
    }

    /// Check if user has existing valid session and auto-login
    private func checkExistingSession() async {
        do {
            if let session = try await client.auth.getSession() {
                print("[InsForgeService] Existing session found for user ID: \(session.user.id)")
                self.currentUser = session.user
                self.isAuthenticated = true
            } else {
                print("[InsForgeService] No existing session found")
            }
        } catch {
            print("[InsForgeService] Error retrieving session: \(error)")
        }
    }

    // MARK: - Authentication

    func signUp(email: String, password: String, name: String) async throws {
        print("[InsForgeService] signUp called for email: \(email)")
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            name: name
        )
        print("[InsForgeService] signUp response received, user ID: \(response.user.id)")
        // Note: Auth headers are automatically updated by SDK

        self.currentUser = response.user
        self.isAuthenticated = true
    }

    func signIn(email: String, password: String) async throws {
        print("[InsForgeService] signIn called for email: \(email)")
        let response = try await client.auth.signIn(
            email: email,
            password: password
        )
        print("[InsForgeService] signIn response received, user ID: \(response.user.id)")
        // Note: Auth headers are automatically updated by SDK

        self.currentUser = response.user
        self.isAuthenticated = true
    }

    func signOut() async throws {
        try await client.auth.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }

    func getCurrentUser() async throws {
        let user = try await client.auth.getCurrentUser()
        self.currentUser = user
        self.isAuthenticated = true
    }

    // MARK: - OAuth Authentication

    /// Sign in using OAuth via default web view
    func signInWithOAuth() async {
        await client.auth.signInWithDefaultView(redirectTo: "todoapp://auth/callback")
    }

    /// Handle OAuth callback and authenticate user
    func handleOAuthCallback(_ url: URL) async throws {
        print("[InsForgeService] handleOAuthCallback called with URL: \(url)")
        let response = try await client.auth.handleAuthCallback(url)
        print("[InsForgeService] OAuth callback handled, user ID: \(response.user.id)")

        self.currentUser = response.user
        self.isAuthenticated = true
    }

    // MARK: - Todo Operations

    func fetchTodos() async throws -> [Todo] {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "TodoApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }

        let todos: [Todo] = try await client.database
            .from("todos")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()

        return todos
    }

    func createTodo(_ todo: Todo) async throws -> Todo {
        let todos: [Todo] = try await client.database
            .from("todos")
            .insert([todo])

        guard let newTodo = todos.first else {
            throw NSError(domain: "TodoApp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create todo"])
        }

        return newTodo
    }

    func updateTodo(_ todo: Todo) async throws -> Todo {
        var updatedTodo = todo
        updatedTodo.updatedAt = Date()

        let todos: [Todo] = try await client.database
            .from("todos")
            .eq("id", value: todo.id)
            .update(updatedTodo)

        guard let result = todos.first else {
            throw NSError(domain: "TodoApp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to update todo"])
        }

        return result
    }

    func deleteTodo(_ todoId: String) async throws {
        try await client.database
            .from("todos")
            .eq("id", value: todoId)
            .delete()
    }

    func toggleTodoCompletion(_ todo: Todo) async throws -> Todo {
        var updatedTodo = todo
        updatedTodo.isCompleted.toggle()
        return try await updateTodo(updatedTodo)
    }

    // MARK: - Realtime

    /// Subscribe to todo changes for the current user
    /// - Parameter onTodoInserted: Callback when a new todo is inserted
    /// - Returns: Cleanup function to unsubscribe
    func subscribeToTodoChanges(
        onTodoInserted: @escaping (Todo) -> Void,
        onTodoUpdated: @escaping (Todo) -> Void,
        onTodoDeleted: @escaping (String) -> Void
    ) async -> (() -> Void) {
        guard let userId = currentUser?.id else {
            print("[InsForgeService] Cannot subscribe: No user logged in")
            return {}
        }

        // Create a channel for this user's todos
        let channelName = "todos"
        let channel = client.realtime.channel(channelName)

        // Subscribe to the channel
        let response = await channel.subscribe()
        if !response.ok {
            print("[InsForgeService] Failed to subscribe to \(channelName)")
            return {}
        }

        print("[InsForgeService] Subscribed to realtime channel: \(channelName)")

        // Listen for INSERT events (database trigger events)
        channel.on("INSERT") { message in
            print("[InsForgeService] Received INSERT event")
            print("[InsForgeService] Payload: \(message.payload)")
            do {
                let todo = try message.decode(Todo.self)
                print("[InsForgeService] Decoded todo: \(todo.title), userId: \(todo.userId)")
                // Only process if it belongs to current user
                if todo.userId == userId {
                    print("[InsForgeService] Todo belongs to current user, adding to list")
                    DispatchQueue.main.async {
                        onTodoInserted(todo)
                    }
                } else {
                    print("[InsForgeService] Todo belongs to different user, ignoring")
                }
            } catch {
                print("[InsForgeService] Failed to decode inserted todo: \(error)")
            }
        }

        // Listen for UPDATE events
        channel.on("UPDATE") { message in
            print("[InsForgeService] Received UPDATE event")
            do {
                let todo = try message.decode(Todo.self)
                if todo.userId == userId {
                    DispatchQueue.main.async {
                        onTodoUpdated(todo)
                    }
                }
            } catch {
                print("[InsForgeService] Failed to decode updated todo: \(error)")
            }
        }

        // Listen for DELETE events
        channel.on("DELETE") { message in
            print("[InsForgeService] Received DELETE event")
            if let todoId = message.payload["id"] as? String {
                DispatchQueue.main.async {
                    onTodoDeleted(todoId)
                }
            }
        }

        // Return cleanup function
        return {
            channel.unsubscribe()
            print("[InsForgeService] Unsubscribed from realtime channel: \(channelName)")
        }
    }

    /// Disconnect from realtime server
    func disconnectRealtime() {
        client.realtime.disconnect()
        print("[InsForgeService] Disconnected from realtime server")
    }
}
