# InsForge Swift SDK

Official Swift SDK for InsForge - A modern Backend-as-a-Service platform.

## Features

- 🔐 **Authentication** - Email/password, OAuth, email verification, password reset
- 🗄️ **Database** - PostgREST-style queries with type-safe builders
- 📦 **Storage** - S3-compatible file storage with buckets
- ⚡ **Functions** - Serverless function invocation
- 🤖 **AI** - Chat completion and image generation
- 🔄 **Realtime** - WebSocket-based pub/sub messaging

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/InsForge/insforge-swift.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File > Add Package Dependencies...
2. Enter package URL: `https://github.com/InsForge/insforge-swift.git`

## Quick Start

### Initialize the Client

```swift
import InsForge

let client = InsForgeClient(
    baseURL: URL(string: "https://your-project.insforge.com")!,
    anonKey: "your-anon-key"
)
```

### Authentication

```swift
// Sign up
let response = try await client.auth.signUp(
    email: "user@example.com",
    password: "securePassword123",
    name: "John Doe"
)

// Sign in
let session = try await client.auth.signIn(
    email: "user@example.com",
    password: "securePassword123"
)

// Get current user
let user = try await client.auth.getCurrentUser()

// Sign out
try await client.auth.signOut()
```

### Database

```swift
// Define your model
struct Post: Codable {
    let id: String?
    let title: String
    let content: String
    let published: Bool
}

// Query records
let posts: [Post] = try await client.database
    .from("posts")
    .select()
    .eq("published", value: true)
    .order("createdAt", ascending: false)
    .limit(10)
    .execute()

// Insert a record
let newPost = Post(
    id: nil,
    title: "My First Post",
    content: "Hello world!",
    published: true
)
let inserted = try await client.database
    .from("posts")
    .insert(newPost)

// Update records
let updates = ["title": "Updated Title"]
let updated: [Post] = try await client.database
    .from("posts")
    .eq("id", value: "some-id")
    .update(updates)

// Delete records
try await client.database
    .from("posts")
    .eq("id", value: "some-id")
    .delete()
```

### Storage

```swift
// Create a bucket
try await client.storage.createBucket("avatars", options: BucketOptions(isPublic: true))

// Upload a file with specific path
let imageData = // ... your image data
let file = try await client.storage
    .from("avatars")
    .upload(
        path: "users/profile.jpg",
        data: imageData,
        options: FileOptions(contentType: "image/jpeg")
    )

// Upload with auto-generated key
let autoFile = try await client.storage
    .from("avatars")
    .upload(
        data: imageData,
        fileName: "profile.jpg"
    )

// Download a file
let data = try await client.storage
    .from("avatars")
    .download(path: file.key)

// Get public URL
let publicURL = client.storage
    .from("avatars")
    .getPublicURL(path: file.key)

// List files
let files = try await client.storage
    .from("avatars")
    .list(options: ListOptions(prefix: "users/", limit: 50))

// Delete a file
try await client.storage
    .from("avatars")
    .delete(path: file.key)

// Get upload strategy (for S3 presigned URL upload)
let uploadStrategy = try await client.storage
    .from("avatars")
    .getUploadStrategy(filename: "large-file.jpg", contentType: "image/jpeg", size: 10485760)

// Get download strategy (for S3 presigned URL download)
let downloadStrategy = try await client.storage
    .from("avatars")
    .getDownloadStrategy(path: "private/document.pdf", expiresIn: 3600)
```

### Functions

```swift
// Invoke a function
struct GreetingRequest: Codable {
    let name: String
}

struct GreetingResponse: Codable {
    let message: String
}

let response: GreetingResponse = try await client.functions.invoke(
    "hello-world",
    body: GreetingRequest(name: "Alice")
)
print(response.message) // "Hello, Alice!"
```

### AI

```swift
// Chat completion
let messages = [
    ChatMessage(role: .system, content: "You are a helpful assistant."),
    ChatMessage(role: .user, content: "What is Swift?")
]

let response = try await client.ai.chatCompletion(
    model: "openai/gpt-4",
    messages: messages,
    temperature: 0.7,
    maxTokens: 500
)
print(response.content)

// Generate images
let imageResponse = try await client.ai.generateImage(
    model: "openai/dall-e-3",
    prompt: "A serene landscape with mountains at sunset"
)

for image in imageResponse.images {
    print(image.imageUrl.url)
}

// List available models
let models = try await client.ai.listModels()
print("Text models:", models.text.count)
print("Image models:", models.image.count)
```

### Realtime

```swift
// Connect to realtime server
try await client.realtime.connect()

// Subscribe to a channel
await client.realtime.subscribe(to: "chat:lobby") { message in
    print("Received message:", message.eventName ?? "")
    print("Payload:", message.payload ?? [:])
}

// Publish a message
try await client.realtime.publish(
    to: "chat:lobby",
    event: "message.new",
    payload: [
        "text": "Hello everyone!",
        "author": "Alice"
    ]
)

// Unsubscribe
await client.realtime.unsubscribe(from: "chat:lobby")

// Disconnect
await client.realtime.disconnect()
```

## Advanced Configuration

```swift
let client = InsForgeClient(
    baseURL: URL(string: "https://your-project.insforge.com")!,
    anonKey: "your-anon-key",
    options: InsForgeClientOptions(
        database: .init(
            encoder: customJSONEncoder,
            decoder: customJSONDecoder
        ),
        auth: .init(
            autoRefreshToken: true,
            storage: UserDefaultsAuthStorage(),
            flowType: .pkce
        ),
        global: .init(
            headers: ["Custom-Header": "value"],
            session: .shared,
            logger: ConsoleLogger()
        )
    )
)
```

## Error Handling

The SDK uses typed errors for better error handling:

```swift
do {
    let user = try await client.auth.getCurrentUser()
} catch InsForgeError.authenticationRequired {
    print("Please sign in first")
} catch InsForgeError.httpError(let statusCode, let message, _, _) {
    print("HTTP \(statusCode): \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Documentation

For detailed documentation, visit [https://docs.insforge.com/swift](https://docs.insforge.com/swift)

## Examples

Check out the [Samples](./Samples) directory for complete example projects:
- iOS app with authentication
- SwiftUI data binding
- Realtime chat application
- File upload/download examples

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- Documentation: [https://docs.insforge.dev](https://docs.insforge.dev)
- Issues: [GitHub Issues](https://github.com/InsForge/insforge-swift/issues)
- Discord: [Join our community](https://discord.gg/DvBtaEc9Jz)
