# Contributing to Kuyruk

Thank you for your interest in contributing! This document provides guidelines and information for developers.

## Getting Started

### Requirements

- macOS 26.0 or later
- Xcode 16.0 or later
- Swift 6.0
- GitHub account (for OAuth testing)

### Build & Run

```bash
# Clone the repository
git clone https://github.com/sozercan/kuyruk.git
cd kuyruk

# Build from command line
xcodebuild -scheme Kuyruk -destination 'platform=macOS' build

# Run tests
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test

# Lint & Format
swiftlint --strict && swiftformat .
```

Or open `Kuyruk.xcodeproj` in Xcode and press ⌘R.

## Project Structure

```
App/                → App entry point, AppDelegate (window lifecycle)
Core/
  ├── Models/       → Data models (Notification, Repository, Filter, etc.)
  ├── Services/
  │   ├── API/      → GitHubClient (GitHub API calls)
  │   ├── Auth/     → AuthService (OAuth authentication)
  │   ├── Notifications/ → NotificationService (local alerts)
  │   └── Sync/     → SyncService (background sync)
  ├── ViewModels/   → NotificationsViewModel, SidebarViewModel, SettingsViewModel
  └── Utilities/    → DiagnosticsLogger, extensions
Views/
  └── macOS/        → SwiftUI views (MainWindow, Sidebar, NotificationList, etc.)
Tests/              → Unit tests (KuyrukTests/)
docs/               → Detailed documentation
```

### Key Files

| File | Purpose |
|------|---------|
| `App/AppDelegate.swift` | Window lifecycle, menu bar support |
| `Core/Services/API/GitHubClient.swift` | GitHub API client |
| `Core/Services/Auth/AuthService.swift` | OAuth state machine |
| `Core/Services/Sync/SyncService.swift` | Background sync |
| `Views/macOS/MainWindow.swift` | Main app window |
| `Core/Utilities/DiagnosticsLogger.swift` | Logging |

## Architecture

For detailed architecture documentation, see the `docs/` folder:

- `docs/architecture.md` — Services, state management, data flow
- `docs/api-integration.md` — GitHub API endpoints, authentication
- `docs/testing.md` — Test commands, patterns, debugging

### High-Level Overview

The app uses a clean architecture with:

- **Observable Pattern**: `@Observable` classes for reactive state management
- **MainActor Isolation**: All UI and service classes are `@MainActor` for thread safety
- **OAuth Integration**: Secure token storage in Keychain
- **Swift Concurrency**: `async`/`await` throughout, no `DispatchQueue`

### Data Flow

```
GitHub API ──► GitHubClient ──► NotificationsViewModel ──► Views
                    │
                    ▼
              Local Cache (optional)
```

### Authentication Flow

```
App Launch → Check Keychain → Token exists?
    │                              │
    │ No                           │ Yes
    ▼                              ▼
Show OAuth Login              Validate token
    │                              │
    │ User authorizes              │ Valid
    ▼                              ▼
Store token in Keychain    NotificationsViewModel.fetch()
```

## Coding Guidelines

### Modern SwiftUI APIs

| Avoid | Use Instead |
|-------|-------------|
| `.foregroundColor()` | `.foregroundStyle()` |
| `.cornerRadius()` | `.clipShape(.rect(cornerRadius:))` |
| `onChange(of:) { newValue in }` | `onChange(of:) { _, newValue in }` |
| `Task.sleep(nanoseconds:)` | `Task.sleep(for: .seconds())` |
| `NavigationView` | `NavigationSplitView` or `NavigationStack` |
| `onTapGesture()` | `Button` (unless tap location needed) |
| `print()` | `DiagnosticsLogger` |
| `DispatchQueue` | Swift concurrency (`async`/`await`) |
| `.background(.ultraThinMaterial)` | `.glassEffect()` for macOS 26+ |

### Liquid Glass UI (macOS 26+)

- Use `.glassEffect(.regular.interactive(), in: .capsule)` for interactive elements
- Wrap multiple glass elements in `GlassEffectContainer`
- Apply `.glassEffect(...)` after layout and visual modifiers
- Use `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` for actions

### Swift Concurrency

- Mark `@Observable` classes with `@MainActor`
- Never use `DispatchQueue` — use `async`/`await`, `MainActor`
- Use `.task` for async loading in views

### Error Handling

- Throw `GitHubError.unauthorized` on HTTP 401/403
- Use `DiagnosticsLogger` for all logging (not `print()`)
- Show user-friendly error messages with retry options

## Pull Request Guidelines

1. **No Third-Party Frameworks** — Do not introduce third-party dependencies without discussion first
2. **Build Must Pass** — Run `xcodebuild -scheme Kuyruk -destination 'platform=macOS' build`
3. **Tests Must Pass** — Run `xcodebuild -scheme Kuyruk -destination 'platform=macOS' test`
4. **Linting** — Run `swiftlint --strict && swiftformat .` before submitting
5. **Small PRs** — Keep changes focused and reviewable

## Testing

```bash
# Run all tests
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test

# Run specific test class
xcodebuild -scheme Kuyruk -destination 'platform=macOS' \
  test -only-testing:KuyrukTests/GitHubClientTests
```

### Swift Testing (Preferred)

Use Swift Testing for all new unit tests:

```swift
import Testing

@Suite(.serialized)
@MainActor
struct GitHubClientTests {
    @Test
    func fetchNotifications_returnsNotifications() async throws {
        let client = GitHubClient(session: MockURLSession())
        let notifications = try await client.fetchNotifications()
        #expect(notifications.count > 0)
    }
}
```

See `docs/testing.md` for detailed testing patterns and debugging tips.

## License

MIT License - see LICENSE file for details.
