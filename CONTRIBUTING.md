# Contributing Guide

First of all, thank you for considering contributing to InsForge Swift SDK! It's people like you that make InsForge a great tool.

## Code of Conduct

By participating in this project, you agree to abide by our code of conduct. Please be kind and respectful to others.

## How Can I Contribute?

### Reporting Bugs

If you find a bug, please report it by following these steps:

1. **Check if it already exists**: Search [GitHub Issues](https://github.com/YOUR_ORG/insforge-swift/issues) to ensure the issue hasn't been reported yet
2. **Create a detailed Issue**: Use the Bug Report template, including:
   - Clear title and description
   - Steps to reproduce
   - Expected behavior vs actual behavior
   - Environment information (iOS/macOS version, Swift version, SDK version)
   - Code sample (if possible)
   - Screenshots or logs (if applicable)

### Suggesting New Features

We welcome new feature suggestions!

1. **Check the roadmap**: See if it's already planned
2. **Create a Feature Request**: Use the template to explain:
   - Use case for the feature
   - Why this feature would be useful
   - Possible implementation approach
   - Whether you're willing to implement it

### Contributing Code

#### Setting Up Development Environment

```bash
# 1. Fork the repository
# Click the "Fork" button on GitHub

# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/insforge-swift.git
cd insforge-swift

# 3. Add upstream repository
git remote add upstream https://github.com/YOUR_ORG/insforge-swift.git

# 4. Create development branch
git checkout -b feature/my-awesome-feature

# 5. Install dependencies
swift package resolve

# 6. Build project
swift build

# 7. Run tests
swift test
```

#### Development Workflow

1. **Create a Branch**

   Use descriptive branch names:
   - `feature/add-batch-operations` - New features
   - `fix/auth-token-refresh` - Bug fixes
   - `docs/improve-readme` - Documentation updates
   - `refactor/database-client` - Code refactoring

2. **Write Code**

   Follow project conventions:
   - Use [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
   - Maintain consistent code style
   - Add appropriate comments
   - Use meaningful variable and function names

3. **Add Tests**

   ```swift
   import XCTest
   @testable import InsForge

   final class MyFeatureTests: XCTestCase {
       func testMyFeature() async throws {
           // Arrange
           let client = InsForgeClient(/* ... */)

           // Act
           let result = try await client.myFeature()

           // Assert
           XCTAssertEqual(result, expectedValue)
       }
   }
   ```

4. **Run Tests**

   ```bash
   # Run all tests
   swift test

   # Run specific tests
   swift test --filter MyFeatureTests

   # With verbose output
   swift test -v
   ```

5. **Commit Code**

   Use clear commit messages:

   ```
   type: short description (no more than 50 characters)

   Detailed explanation of why this change was made, not how.
   Include relevant issue numbers.

   Closes #123
   ```

   Commit types:
   - `feat:` New feature
   - `fix:` Bug fix
   - `docs:` Documentation update
   - `style:` Formatting (doesn't affect code meaning)
   - `refactor:` Refactoring (neither fixes bugs nor adds features)
   - `test:` Adding tests
   - `chore:` Build process or auxiliary tool changes
   - `perf:` Performance optimization

   Example:
   ```
   feat: add batch insert operation to database client

   Implements batch insert functionality to reduce network overhead
   when inserting multiple records at once.

   Closes #45
   ```

6. **Push Code**

   ```bash
   git push origin feature/my-awesome-feature
   ```

7. **Create Pull Request**

   Create a PR on GitHub:
   - Clear title
   - Detailed description of changes
   - Link related issues
   - Ensure CI passes
   - Request review

#### Pull Request Checklist

Before submitting a PR, ensure:

- [ ] Code follows project style guide
- [ ] All tests pass
- [ ] Added tests for new features
- [ ] Updated relevant documentation
- [ ] Updated CHANGELOG.md
- [ ] Commit messages are clear
- [ ] No compilation warnings
- [ ] Passed SwiftLint checks

### Documentation Contributions

Documentation is equally important! You can:

- Fix spelling or grammar errors
- Improve existing documentation
- Add code examples
- Translate documentation
- Create tutorials or guides

Documentation locations:
- `README.md` - Project homepage
- `docs/GETTING_STARTED.md` - Getting started guide
- `docs/PUBLISHING.md` - Publishing guide
- Code comments - DocC documentation

## Code Standards

### Swift Style

```swift
// ✅ Good
public actor MyClient {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func doSomething() async throws -> Result {
        // Implementation
    }
}

// ❌ Bad
public actor myClient {
    var Url: URL

    func DoSomething() throws -> Result {
        // Implementation
    }
}
```

### Naming Conventions

- **Type names**: PascalCase (`InsForgeClient`, `AuthClient`)
- **Variables/Functions**: camelCase (`signIn`, `getCurrentUser`)
- **Constants**: camelCase (`maxRetryCount`, `defaultTimeout`)
- **Protocols**: Nouns or adjectives (`AuthStorage`, `Sendable`)

### Error Handling

```swift
// ✅ Use typed errors
public enum MyError: Error {
    case invalidInput
    case networkFailure(Error)
}

throw MyError.invalidInput

// ❌ Avoid generic errors
throw NSError(domain: "MyDomain", code: -1)
```

### Concurrency

```swift
// ✅ Use async/await
public func fetchData() async throws -> Data {
    try await httpClient.execute(.get, url: url)
}

// ✅ Use actor to protect state
public actor StateManager {
    private var state: State

    public func update(_ newState: State) {
        state = newState
    }
}

// ❌ Avoid callbacks
public func fetchData(completion: @escaping (Result<Data, Error>) -> Void) {
    // Don't do this
}
```

### Testing

```swift
// ✅ Use descriptive test names
func testSignInWithValidCredentialsSucceeds() async throws {
    // Test implementation
}

// ✅ Use Arrange-Act-Assert pattern
func testExample() async throws {
    // Arrange
    let client = makeTestClient()

    // Act
    let result = try await client.doSomething()

    // Assert
    XCTAssertEqual(result, expectedValue)
}

// ✅ Test error cases
func testSignInWithInvalidCredentialsThrowsError() async throws {
    let client = makeTestClient()

    await XCTAssertThrowsError(
        try await client.signIn(email: "bad", password: "bad")
    ) { error in
        XCTAssertTrue(error is InsForgeError)
    }
}
```

## SwiftLint Configuration

The project uses SwiftLint to maintain code quality.

Installation:
```bash
brew install swiftlint
```

Run checks:
```bash
swiftlint
```

Auto-fix:
```bash
swiftlint --fix
```

## Version Release Process

Only maintainers can release new versions:

1. Update `CHANGELOG.md`
2. Update version number in `Sources/InsForge/InsForgeClient.swift`
3. Create PR and merge
4. Create tag: `git tag -a 1.0.1 -m "Release 1.0.1"`
5. Push tag: `git push origin 1.0.1`
6. Create Release on GitHub

## Getting Help

If you have questions:

- Check the [documentation](https://github.com/YOUR_ORG/insforge-swift/tree/main/docs)
- Search existing [Issues](https://github.com/YOUR_ORG/insforge-swift/issues)
- Ask in [Discussions](https://github.com/YOUR_ORG/insforge-swift/discussions)
- Join the [Discord community](https://discord.gg/insforge)

## Acknowledgments

Thanks to all contributors! Your efforts make InsForge better.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
