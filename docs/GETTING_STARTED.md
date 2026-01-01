# Getting Started with InsForge Swift SDK

This guide will help you get up and running with the InsForge Swift SDK.

## Table of Contents

- [Installation](#installation)
- [Initialization](#initialization)
- [Authentication](#authentication)
- [Database Operations](#database-operations)
- [File Storage](#file-storage)
- [Serverless Functions](#serverless-functions)
- [AI Services](#ai-services)
- [Realtime Messaging](#realtime-messaging)

## Installation

### Swift Package Manager

Add InsForge to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/insforge-swift.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies...
2. Enter: `https://github.com/your-org/insforge-swift.git`
3. Click "Add Package"

## Initialization

Initialize the InsForge client with your project URL and API key:

```swift
import InsForge

let client = InsForgeClient(
    baseURL: URL(string: "https://your-project.insforge.com")!,
    anonKey: "your-anon-or-service-key"
)
```

### Configuration Options

For advanced usage, you can customize the client:

```swift
let client = InsForgeClient(
    baseURL: URL(string: "https://your-project.insforge.com")!,
    anonKey: "your-key",
    options: InsForgeClientOptions(
        database: .init(
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        ),
        auth: .init(
            autoRefreshToken: true,
            storage: UserDefaultsAuthStorage(),
            flowType: .pkce
        ),
        global: .init(
            headers: ["X-App-Version": "1.0.0"],
            session: .shared,
            logger: ConsoleLogger()
        )
    )
)
```

## Authentication

### Email/Password Sign Up

```swift
let response = try await client.auth.signUp(
    email: "user@example.com",
    password: "SecurePassword123!",
    name: "John Doe"
)

if let token = response.accessToken {
    print("User signed up and logged in")
} else if response.requireEmailVerification == true {
    print("Please verify your email")
}
```

### Sign In

```swift
let session = try await client.auth.signIn(
    email: "user@example.com",
    password: "SecurePassword123!"
)
print("Signed in as:", session.user.email)
```

### OAuth

```swift
// Get OAuth URL
let oauthURL = try await client.auth.getOAuthURL(
    provider: .google,
    redirectTo: "yourapp://callback"
)

// Open in browser/web view
// After callback, user will be authenticated
```

### Email Verification

```swift
// Send verification code
try await client.auth.sendEmailVerification(email: "user@example.com")

// Verify with code
let response = try await client.auth.verifyEmail(
    email: "user@example.com",
    otp: "123456"
)
```

### Password Reset

```swift
// Request password reset
try await client.auth.sendPasswordReset(email: "user@example.com")

// Reset password with code
try await client.auth.resetPassword(
    otp: "reset-token",
    newPassword: "NewSecurePassword456!"
)
```

### Get Current User

```swift
let user = try await client.auth.getCurrentUser()
print("Current user:", user.email)
```

### Sign Out

```swift
try await client.auth.signOut()
```

## Database Operations

### Define Models

```swift
struct Todo: Codable {
    let id: String?
    let title: String
    let completed: Bool
    let userId: String
    let createdAt: Date?
}
```

### Query Records

```swift
// Get all todos
let todos: [Todo] = try await client.database
    .from("todos")
    .select()
    .execute()

// Filter and sort
let completed: [Todo] = try await client.database
    .from("todos")
    .select()
    .eq("completed", value: true)
    .order("createdAt", ascending: false)
    .limit(20)
    .execute()

// Multiple filters
let userTodos: [Todo] = try await client.database
    .from("todos")
    .select()
    .eq("userId", value: currentUserId)
    .eq("completed", value: false)
    .execute()
```

### Insert Records

```swift
// Insert single
let newTodo = Todo(
    id: nil,
    title: "Learn InsForge",
    completed: false,
    userId: currentUserId,
    createdAt: nil
)
let inserted = try await client.database
    .from("todos")
    .insert(newTodo)

// Insert multiple
let todos = [todo1, todo2, todo3]
let inserted = try await client.database
    .from("todos")
    .insert(todos)
```

### Update Records

```swift
struct TodoUpdate: Codable {
    let completed: Bool
}

let updated: [Todo] = try await client.database
    .from("todos")
    .eq("id", value: todoId)
    .update(TodoUpdate(completed: true))
```

### Delete Records

```swift
try await client.database
    .from("todos")
    .eq("id", value: todoId)
    .delete()
```

## File Storage

### Create Bucket

```swift
try await client.storage.createBucket(
    "avatars",
    options: BucketOptions(isPublic: true)
)
```

### Update Bucket

```swift
// Update bucket visibility
try await client.storage.updateBucket(
    "avatars",
    options: BucketOptions(isPublic: false)
)
```

### Upload Files

```swift
// Upload with specific path
let file = try await client.storage
    .from("avatars")
    .upload(
        path: "users/\(userId)/avatar.jpg",
        data: imageData,
        options: FileOptions(contentType: "image/jpeg")
    )

// Upload with auto-generated key
let autoFile = try await client.storage
    .from("avatars")
    .upload(
        data: imageData,
        fileName: "avatar.jpg",
        options: FileOptions(contentType: "image/jpeg")
    )

// Upload from file URL
let fileFromURL = try await client.storage
    .from("avatars")
    .upload(
        path: "documents/report.pdf",
        fileURL: localFileURL,
        options: FileOptions(contentType: "application/pdf")
    )
```

### Download Files

```swift
let data = try await client.storage
    .from("avatars")
    .download(path: "users/123/avatar.jpg")

let image = UIImage(data: data)
```

### Get Public URL

```swift
let url = client.storage
    .from("avatars")
    .getPublicURL(path: "users/123/avatar.jpg")
```

### List Files

```swift
// List all files
let files = try await client.storage
    .from("avatars")
    .list()

// List with prefix filter and pagination
let filteredFiles = try await client.storage
    .from("avatars")
    .list(options: ListOptions(prefix: "users/", limit: 50, offset: 0))

// Convenience method with prefix
let userFiles = try await client.storage
    .from("avatars")
    .list(prefix: "users/123/", limit: 20)

for file in files {
    print("\(file.key) - \(file.size) bytes")
}
```

### Delete Files

```swift
// Delete a single file
try await client.storage
    .from("avatars")
    .delete(path: "users/123/old-avatar.jpg")
```

### Upload Strategy (S3 Presigned URL)

For large files or direct S3 uploads, use the upload strategy API:

```swift
// Get upload strategy
let strategy = try await client.storage
    .from("avatars")
    .getUploadStrategy(
        filename: "large-video.mp4",
        contentType: "video/mp4",
        size: 104857600  // 100MB
    )

// Upload directly to S3 using the presigned URL
// ... upload to strategy.uploadUrl with strategy.fields ...

// Confirm the upload if required
if strategy.confirmRequired {
    let confirmed = try await client.storage
        .from("avatars")
        .confirmUpload(
            path: strategy.key,
            size: 104857600,
            contentType: "video/mp4"
        )
}
```

### Download Strategy (S3 Presigned URL)

For private files or time-limited access:

```swift
// Get a presigned download URL (expires in 1 hour)
let strategy = try await client.storage
    .from("private-files")
    .getDownloadStrategy(path: "document.pdf", expiresIn: 3600)

// Use strategy.url to download the file
```

## Serverless Functions

### Invoke Functions

```swift
// With type safety
struct Input: Codable {
    let name: String
    let age: Int
}

struct Output: Codable {
    let message: String
}

let result: Output = try await client.functions.invoke(
    "process-user",
    body: Input(name: "Alice", age: 25)
)

// Without response
try await client.functions.invoke(
    "send-notification",
    body: ["message": "Hello!"]
)
```

## AI Services

### Chat Completion

```swift
let messages = [
    ChatMessage(role: .system, content: "You are a helpful coding assistant."),
    ChatMessage(role: .user, content: "How do I sort an array in Swift?")
]

let response = try await client.ai.chatCompletion(
    model: "openai/gpt-4",
    messages: messages,
    temperature: 0.7,
    maxTokens: 500
)

print(response.content)
```

### Image Generation

```swift
let result = try await client.ai.generateImage(
    model: "openai/dall-e-3",
    prompt: "A futuristic city at sunset, cyberpunk style"
)

for image in result.images {
    let url = URL(string: image.imageUrl.url)!
    // Load and display image
}
```

### List Models

```swift
let models = try await client.ai.listModels()

print("Text models:")
for provider in models.text {
    print("  \(provider.provider): \(provider.models.count) models")
}

print("Image models:")
for provider in models.image {
    print("  \(provider.provider): \(provider.models.count) models")
}
```

## Realtime Messaging

### Connect

```swift
try await client.realtime.connect()
```

### Subscribe to Channels

```swift
await client.realtime.subscribe(to: "chat:lobby") { message in
    print("Event:", message.eventName ?? "")
    if let payload = message.payload {
        print("Data:", payload)
    }
}
```

### Publish Messages

```swift
try await client.realtime.publish(
    to: "chat:lobby",
    event: "message.new",
    payload: [
        "text": "Hello everyone!",
        "author": currentUser.name,
        "timestamp": Date().timeIntervalSince1970
    ]
)
```

### Unsubscribe

```swift
await client.realtime.unsubscribe(from: "chat:lobby")
```

### Disconnect

```swift
await client.realtime.disconnect()
```

## Error Handling

All async functions can throw errors. Use Swift's error handling:

```swift
do {
    let user = try await client.auth.getCurrentUser()
    print("Logged in as:", user.email)
} catch InsForgeError.authenticationRequired {
    print("Please sign in")
} catch InsForgeError.httpError(let code, let message, _, _) {
    print("HTTP \(code): \(message)")
} catch {
    print("Unexpected error:", error)
}
```

## Next Steps

- Explore the [API Reference](./API_REFERENCE.md)
- Check out [Examples](../Samples)
- Read about [Best Practices](./BEST_PRACTICES.md)
- Join our [Discord Community](https://discord.gg/insforge)
