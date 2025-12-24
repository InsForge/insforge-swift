# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Streaming support for AI chat completion
- Batch operations for database
- Progress callbacks for file uploads
- Connection retry logic for Realtime
- Offline support with local cache
- Request queuing and retry mechanisms
- Performance monitoring
- DocC documentation

## [1.0.0] - 2025-12-22

### Added
- Initial release of InsForge Swift SDK
- **Authentication Module** (`InsForgeAuth`)
  - Email/password sign up and sign in
  - OAuth integration with 11 providers (Google, GitHub, Discord, etc.)
  - Email verification (code/link methods)
  - Password reset (code/link methods)
  - Session management with configurable storage
  - User profile management
- **Database Module** (`InsForgeDatabase`)
  - PostgREST-style query builder
  - Type-safe operations with Codable
  - Filtering: eq, neq, gt, gte, lt, lte
  - Ordering and pagination
  - Insert, update, delete operations
- **Storage Module** (`InsForgeStorage`)
  - Bucket management (create, list, delete)
  - File upload/download with multipart support
  - Public URL generation
  - File listing with prefix filtering
  - Auto-generated and custom file keys
- **Functions Module** (`InsForgeFunctions`)
  - Serverless function invocation
  - Type-safe request/response
  - Support for any JSON payload
- **AI Module** (`InsForgeAI`)
  - Chat completion via OpenRouter
  - Image generation
  - Model listing and discovery
  - Token usage tracking
- **Realtime Module** (`InsForgeRealtime`)
  - WebSocket connections
  - Channel subscriptions
  - Message publishing
  - Event-driven architecture
- **Core Infrastructure**
  - Actor-based concurrency for thread safety
  - Comprehensive error handling with typed errors
  - Pluggable logger interface
  - HTTP client with async/await support
  - Thread-safe state management with LockIsolated
  - Configurable options for all modules
- **Documentation**
  - Comprehensive README
  - Getting Started guide
  - Quick Start example
  - Project summary and architecture documentation
- **Platform Support**
  - iOS 13.0+
  - macOS 10.15+
  - tvOS 13.0+
  - watchOS 6.0+
  - visionOS 1.0+
- **Dependencies**
  - Starscream for WebSocket support

### Technical Details
- Minimum Swift version: 5.9
- Sendable conformance throughout for Swift concurrency
- Lazy initialization of sub-clients
- Facade pattern for unified API
- Builder pattern for query construction
- Dependency injection via configuration options

---

## Release Notes Format

For future releases, follow this format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security fixes
```

[Unreleased]: https://github.com/YOUR_ORG/insforge-swift/compare/1.0.0...HEAD
[1.0.0]: https://github.com/YOUR_ORG/insforge-swift/releases/tag/1.0.0
