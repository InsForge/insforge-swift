# Twitter Clone - iOS App

A Twitter-like iOS application built with SwiftUI and InsForge backend.

## Features

- **Authentication**: Sign up, sign in, and sign out
- **Feed**: View all tweets in chronological order
- **Compose**: Create new tweets with optional image attachments
- **Profile**: View and edit user profiles
- **Interactions**: Like, bookmark, and reply to tweets
- **Follow System**: Follow/unfollow other users
- **Search**: Search for users by username

## Tech Stack

- **Frontend**: SwiftUI (iOS 17+)
- **Backend**: InsForge BaaS
- **Database**: PostgreSQL via PostgREST
- **Storage**: InsForge Storage for images

## Project Structure

```
TwitterClone/
├── Package.swift
└── TwitterClone/
    ├── TwitterCloneApp.swift      # App entry point
    ├── Info.plist                 # App configuration
    ├── Models/
    │   └── Models.swift           # Data models
    ├── Services/
    │   └── InsForgeService.swift  # InsForge client
    ├── ViewModels/
    │   ├── AuthViewModel.swift    # Authentication logic
    │   ├── FeedViewModel.swift    # Feed management
    │   ├── TweetViewModel.swift   # Tweet operations
    │   └── ProfileViewModel.swift # Profile management
    ├── Views/
    │   ├── ContentView.swift      # Root view
    │   ├── AuthView.swift         # Login/Register
    │   ├── MainTabView.swift      # Main tab navigation
    │   ├── FeedView.swift         # Home feed
    │   ├── ComposeView.swift      # Tweet composer
    │   ├── TweetDetailView.swift  # Tweet detail with replies
    │   ├── ProfileView.swift      # User profile
    │   ├── SearchView.swift       # User search
    │   └── NotificationsView.swift
    └── Components/
        └── TweetRowView.swift     # Tweet card component
```

## Database Schema

### Tables

- **profiles**: User profiles (username, display name, bio, avatar, etc.)
- **tweets**: Tweet content and metadata
- **likes**: User-tweet like relationships
- **follows**: User-user follow relationships
- **bookmarks**: User-tweet bookmark relationships

### Storage Buckets

- **avatars**: User profile pictures
- **headers**: User header images
- **tweets**: Tweet image attachments

## Getting Started

### Prerequisites

- Xcode 15 or later
- iOS 17+ Simulator or device
- InsForge backend running locally at `http://localhost:7130`

### Running the App

1. Open the project in Xcode:
   ```bash
   cd TwitterClone
   open Package.swift
   ```

2. Or build with Swift Package Manager:
   ```bash
   swift build
   ```

3. Run on iOS Simulator from Xcode

### Configuration

The InsForge client is configured in `Services/InsForgeService.swift`:

```swift
let client = InsForgeClient(
    baseUrl: "http://localhost:7130",
    anonKey: "your-anon-key"
)
```

## API Endpoints Used

### Authentication
- `POST /auth/signup` - Register new user
- `POST /auth/signin` - Sign in user
- `POST /auth/signout` - Sign out user

### Database (PostgREST)
- `GET/POST/PATCH/DELETE /rest/v1/profiles`
- `GET/POST/PATCH/DELETE /rest/v1/tweets`
- `GET/POST/DELETE /rest/v1/likes`
- `GET/POST/DELETE /rest/v1/follows`
- `GET/POST/DELETE /rest/v1/bookmarks`

### Storage
- `POST /storage/buckets/{bucket}/objects` - Upload file
- `GET /storage/buckets/{bucket}/objects/{key}` - Download file

## License

MIT License
