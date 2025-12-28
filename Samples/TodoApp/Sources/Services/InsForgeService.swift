import Foundation
import InsForge
import InsForgeAuth
import InsForgeDatabase
import InsForgeCore

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
            insForgeURL: url,
            apiKey: Config.apiKey,
            options: InsForgeClientOptions(
                global: InsForgeClientOptions.GlobalOptions(
                    logger: ConsoleLogger()
                )
            )
        )
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
}
