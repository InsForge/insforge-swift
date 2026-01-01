import Foundation
import InsForge

/// Quick Start Example for InsForge Swift SDK
/// This demonstrates the basic usage of all modules

@main
struct QuickStartExample {
    static func main() async {
        // Initialize the client
        let client = InsForgeClient(
            baseURL: URL(string: "https://your-project.insforge.com")!,
            anonKey: "your-anon-key"
        )

        do {
            // ============================================
            // AUTHENTICATION
            // ============================================
            print("\n=== Authentication ===")

            // Sign up a new user
            let signUpResponse = try await client.auth.signUp(
                email: "alice@example.com",
                password: "SecurePass123!",
                name: "Alice"
            )
            print("✅ User registered:", signUpResponse.user.email)

            // Sign in
            let session = try await client.auth.signIn(
                email: "alice@example.com",
                password: "SecurePass123!"
            )
            print("✅ User signed in:", session.user.email)

            // ============================================
            // DATABASE
            // ============================================
            print("\n=== Database ===")

            // Define a data model
            struct Post: Codable {
                let id: String?
                let title: String
                let content: String
                let published: Bool
            }

            // Insert a record
            let newPost = Post(
                id: nil,
                title: "Getting Started with InsForge",
                content: "InsForge is a powerful BaaS platform...",
                published: true
            )
            let insertedPost = try await client.database
                .from("posts")
                .insert(newPost)
            print("✅ Post created:", insertedPost.title)

            // Query records
            let posts: [Post] = try await client.database
                .from("posts")
                .select()
                .eq("published", value: true)
                .order("createdAt", ascending: false)
                .limit(10)
                .execute()
            print("✅ Found \(posts.count) published posts")

            // ============================================
            // STORAGE
            // ============================================
            print("\n=== Storage ===")

            // Create a bucket
            try await client.storage.createBucket("avatars", options: BucketOptions(isPublic: true))
            print("✅ Bucket 'avatars' created")

            // Upload a file
            let sampleData = "Hello, InsForge!".data(using: .utf8)!
            let uploadedFile = try await client.storage
                .from("avatars")
                .upload(
                    path: "sample.txt",
                    data: sampleData,
                    options: FileOptions(contentType: "text/plain")
                )
            print("✅ File uploaded:", uploadedFile.key)

            // Get public URL
            let publicURL = client.storage
                .from("avatars")
                .getPublicURL(path: uploadedFile.key)
            print("✅ Public URL:", publicURL.absoluteString)

            // ============================================
            // FUNCTIONS
            // ============================================
            print("\n=== Functions ===")

            struct GreetingRequest: Codable {
                let name: String
            }

            struct GreetingResponse: Codable {
                let message: String
            }

            // Invoke a function
            let greeting: GreetingResponse = try await client.functions.invoke(
                "hello-world",
                body: GreetingRequest(name: "Alice")
            )
            print("✅ Function response:", greeting.message)

            // ============================================
            // AI
            // ============================================
            print("\n=== AI ===")

            // Chat completion
            let messages = [
                ChatMessage(role: .system, content: "You are a helpful assistant."),
                ChatMessage(role: .user, content: "What is Swift in one sentence?")
            ]

            let aiResponse = try await client.ai.chatCompletion(
                model: "openai/gpt-4",
                messages: messages,
                temperature: 0.7
            )
            print("✅ AI response:", aiResponse.content)

            // ============================================
            // REALTIME
            // ============================================
            print("\n=== Realtime ===")

            // Connect to realtime server
            try await client.realtime.connect()
            print("✅ Connected to realtime server")

            // Subscribe to a channel
            await client.realtime.subscribe(to: "notifications") { message in
                print("📨 Received:", message.eventName ?? "unknown event")
            }

            // Publish a message
            try await client.realtime.publish(
                to: "notifications",
                event: "user.joined",
                payload: ["userId": session.user.id, "name": "Alice"]
            )
            print("✅ Message published")

            // Wait a bit to receive messages
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Cleanup
            await client.realtime.disconnect()
            try await client.auth.signOut()

            print("\n✨ All examples completed successfully!")

        } catch {
            print("❌ Error:", error)
        }
    }
}
