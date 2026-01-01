# InsForge Todo App - macOS Sample

A complete Todo List application for macOS built with SwiftUI and InsForge Swift SDK.

## Features

### 🔐 Authentication
- **Sign Up**: Create a new account with email, password, and name
- **Sign In**: Log in with existing credentials
- **Sign Out**: Securely log out
- **Session Persistence**: Automatically restore user session

### ✅ Todo Management
- **Create Todos**: Add new todos with title and optional description
- **View Todos**: See all your todos in a list with completion status
- **Update Todos**: Edit todo details, mark as complete/incomplete
- **Delete Todos**: Remove todos you no longer need
- **Real-time Sync**: All changes are synced with InsForge backend

### 📅 Due Dates
- Set optional due dates for todos
- Visual indicators for overdue items
- Date and time picker for precise scheduling

### 🔔 Reminders
- Schedule notifications for your todos
- macOS native notification system
- Visual indicator for todos with reminders
- Automatic cancellation when todos are deleted

## Architecture

```
TodoApp/
├── Sources/
│   ├── Models/
│   │   └── Todo.swift              # Todo data model
│   ├── Services/
│   │   ├── InsForgeService.swift   # InsForge SDK wrapper
│   │   └── ReminderService.swift   # Notification management
│   ├── Views/
│   │   ├── AuthView.swift          # Authentication UI
│   │   ├── TodoListView.swift      # Main list view
│   │   ├── TodoDetailView.swift    # Detail/edit view
│   │   └── AddTodoView.swift       # Create todo form
│   └── TodoApp.swift               # App entry point
└── Package.swift                   # Swift Package configuration
```

## Setup

### 1. Configure InsForge Connection

Create your configuration file:

```bash
cd Samples/TodoApp
cp Config.example.swift Sources/Config.swift
```

Edit `Sources/Config.swift` and replace the values:

```swift
enum Config {
    static let insForgeURL = "https://your-project.insforge.com"  // Your InsForge URL
    static let anonKey = "your-api-key-here"                       // Your API key
}
```

**Note:** `Config.swift` is in `.gitignore` and will not be committed to version control, keeping your API key secure.

### 2. Set Up Database Schema

Create a `todos` table in your InsForge database with the following schema:

```sql
CREATE TABLE todos (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    is_completed BOOLEAN DEFAULT FALSE,
    due_date TIMESTAMP,
    reminder_date TIMESTAMP,
    user_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add index for user queries
CREATE INDEX idx_todos_user_id ON todos(user_id);

-- Add Row Level Security policies
ALTER TABLE todos ENABLE ROW LEVEL SECURITY;

-- Users can only see their own todos
CREATE POLICY "Users can view their own todos"
ON todos FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own todos
CREATE POLICY "Users can insert their own todos"
ON todos FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own todos
CREATE POLICY "Users can update their own todos"
ON todos FOR UPDATE
USING (auth.uid() = user_id);

-- Users can delete their own todos
CREATE POLICY "Users can delete their own todos"
ON todos FOR DELETE
USING (auth.uid() = user_id);
```

### 3. Grant Notification Permission

The app will automatically request notification permission on first launch. Make sure to allow notifications in macOS System Settings if prompted.

## Building and Running

### Using Swift Package Manager

```bash
cd Samples/TodoApp
swift build
swift run
```

### Using Xcode

```bash
cd Samples/TodoApp
open Package.swift
```

Then press `⌘R` to build and run.

## Usage

### First Time Setup

1. **Launch the app**
2. **Sign up** with your email, password, and name
3. **Allow notifications** when prompted (optional, for reminders)

### Creating a Todo

1. Click the **+** button in the top-right
2. Enter a **title** (required)
3. Add a **description** (optional)
4. Set a **due date** (optional)
5. Set a **reminder** (optional)
6. Click **Add Todo**

### Managing Todos

- **Complete/Uncomplete**: Click the circle icon next to the todo
- **View Details**: Click on a todo in the list
- **Edit**: Click the pencil icon in the detail view
- **Delete**: Click the trash icon in the detail view

### Reminders

Reminders will trigger a macOS notification at the specified time. You can:
- Set reminder when creating a todo
- Add/edit reminder in the detail view
- Remove reminder by unchecking "Set reminder"

## Technologies Used

- **SwiftUI**: Modern declarative UI framework
- **InsForge Swift SDK**: Backend services
  - Authentication
  - Database (PostgREST-style queries)
- **UserNotifications**: macOS notification system
- **Swift Concurrency**: async/await for all async operations

## Key Components

### InsForgeService

Singleton service managing all InsForge SDK operations:
- User authentication
- Todo CRUD operations
- Session management

### ReminderService

Handles local notification scheduling:
- Request notification permission
- Schedule/cancel reminders
- Track pending notifications

### Todo Model

Codable struct representing a todo item with:
- Basic fields (title, description, completion status)
- Timestamps (created, updated)
- Optional fields (due date, reminder date)
- User association

## Requirements

- macOS 13.0+
- Swift 5.9+
- InsForge instance with authentication and database enabled

## Troubleshooting

### Notifications Not Working

1. Check System Settings → Notifications → TodoApp
2. Ensure notifications are enabled
3. Verify reminder date is in the future

### Authentication Errors

1. Verify InsForge URL and API key are correct
2. Check network connectivity
3. Ensure authentication is enabled in InsForge

### Database Errors

1. Verify `todos` table exists with correct schema
2. Check Row Level Security policies are set up
3. Ensure user is authenticated

## Future Enhancements

Potential features to add:
- [ ] Todo categories/tags
- [ ] Search and filter
- [ ] Sorting options
- [ ] Dark mode support
- [ ] Recurring todos
- [ ] Priority levels
- [ ] Attachments
- [ ] Collaborative todos
- [ ] Export/import functionality

## License

This sample app is provided as-is for demonstration purposes.
