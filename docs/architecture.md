# Architecture

This document describes the architecture of Kuyruk, a native macOS GitHub Notifications client.

## Overview

Kuyruk follows a clean Model-View (MV) architecture pattern, leveraging SwiftUI's modern state management with `@Observable` and Swift Concurrency for all async operations.

## Build System

This project uses **Swift Package Manager (SPM)** as the primary build system.

### Package.swift

The package manifest defines:
- **Platform**: macOS 26.0+ (required for Liquid Glass)
- **Language Mode**: Swift 6.0 with strict concurrency
- **Targets**:
  - `Kuyruk` — Main executable app target
  - `APIExplorer` — Standalone CLI tool for API exploration
  - `KuyrukTests` — Unit tests

### Build Commands

```bash
# Build the app
swift build

# Build for release
swift build -c release

# Run tests
swift test

# Run the API explorer
swift run api-explorer notifications
```

### Resources

Resources are bundled using SPM's resource processing:

```swift
.executableTarget(
    name: "Kuyruk",
    resources: [
        .process("Resources")
    ]
)
```

Access resources in code via `Bundle.module`:

```swift
let image = NSImage(resource: .appIcon)
// or
let url = Bundle.module.url(forResource: "config", withExtension: "json")
```

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Views (SwiftUI)                       │
│  MainWindow, Sidebar, NotificationList, NotificationDetail  │
├─────────────────────────────────────────────────────────────┤
│                      ViewModels (@Observable)                │
│       NotificationsViewModel, SidebarViewModel, etc.        │
├─────────────────────────────────────────────────────────────┤
│                         Services                             │
│    GitHubClient, AuthService, SyncService, Notifications    │
├─────────────────────────────────────────────────────────────┤
│                       Persistence                            │
│                  SwiftData (DataStore)                       │
├─────────────────────────────────────────────────────────────┤
│                          Models                              │
│    GitHubNotification, Repository, NotificationFilter       │
└─────────────────────────────────────────────────────────────┘
```

## Persistence (SwiftData)

The app uses SwiftData for local caching to enable:
- Fast startup (load from cache, then sync)
- Offline viewing of previously fetched notifications
- Sync delta detection (only process new/changed)

### Data Models

```swift
import SwiftData

@Model
final class CachedNotification {
    @Attribute(.unique) var id: String
    var title: String
    var repositoryName: String
    var repositoryOwner: String
    var reason: String
    var unread: Bool
    var updatedAt: Date
    var url: String
    var subjectType: String  // "Issue", "PullRequest", "Commit", etc.
    
    // Sync metadata
    var lastSyncedAt: Date
    var isDeleted: Bool = false  // Soft delete for sync
}

@Model
final class CachedRepository {
    @Attribute(.unique) var fullName: String
    var name: String
    var owner: String
    var avatarURL: String?
    
    var unreadCount: Int = 0
}
```

### DataStore Service

```swift
@MainActor
@Observable
final class DataStore {
    private let modelContainer: ModelContainer
    private var modelContext: ModelContext { modelContainer.mainContext }
    
    init() throws {
        let schema = Schema([CachedNotification.self, CachedRepository.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
    }
    
    func saveNotifications(_ notifications: [GitHubNotification]) throws { ... }
    func fetchCachedNotifications() throws -> [CachedNotification] { ... }
    func markAsRead(_ notificationId: String) throws { ... }
    func pruneOldNotifications(olderThan: Date) throws { ... }
}
```

### Sync Strategy

1. **On Launch**: Load cached notifications immediately, then trigger background sync
2. **Polling**: Every 60 seconds, fetch from GitHub API
3. **Merge**: Update cache with new data, preserve local state (read status)
4. **Prune**: Remove notifications older than 30 days from cache

## Services

### GitHubClient

The primary API client for GitHub REST API communication.

```swift
@MainActor
@Observable
final class GitHubClient {
    private let session: URLSession
    private let authService: AuthService
    
    func fetchNotifications(all: Bool = false) async throws -> [GitHubNotification]
    func markAsRead(_ notification: GitHubNotification) async throws
    func markAllAsRead() async throws
    func getIssue(owner: String, repo: String, number: Int) async throws -> Issue
    func getPullRequest(owner: String, repo: String, number: Int) async throws -> PullRequest
}
```

**Key Responsibilities:**
- Build authenticated requests with OAuth token
- Parse GitHub API responses
- Handle rate limiting and errors
- Provide type-safe access to GitHub endpoints

### AuthService

Manages OAuth 2.0 authentication with GitHub.

```swift
@MainActor
@Observable
final class AuthService {
    enum State {
        case loggedOut
        case authenticating
        case authenticated(token: String)
        case error(Error)
    }
    
    var state: State = .loggedOut
    
    func startOAuth() async throws
    func handleCallback(url: URL) async throws
    func logout()
}
```

**Authentication Flow:**
1. User clicks "Sign in with GitHub"
2. App opens GitHub OAuth URL in browser
3. User authorizes the app
4. GitHub redirects to `kuyruk://oauth/callback?code=...`
5. App exchanges code for access token
6. Token stored securely in Keychain

### SyncService

Handles background synchronization of notifications.

```swift
@MainActor
@Observable
final class SyncService {
    var lastSyncTime: Date?
    var isSyncing: Bool = false
    
    func startBackgroundSync()
    func stopBackgroundSync()
    func syncNow() async throws
}
```

**Sync Strategy:**
- Poll GitHub API every 60 seconds when app is active
- Reduce frequency when app is in background
- Detect new notifications and trigger local alerts

### NotificationService

Manages local macOS notifications.

```swift
@MainActor
final class NotificationService {
    func requestPermission() async -> Bool
    func scheduleNotification(for: GitHubNotification) async
    func removeDeliveredNotifications()
}
```

## ViewModels

### NotificationsViewModel

The primary view model for notification state.

```swift
@MainActor
@Observable
final class NotificationsViewModel {
    // State
    var notifications: [GitHubNotification] = []
    var selectedFilter: NotificationFilter = .inbox
    var selectedNotification: GitHubNotification?
    var isLoading: Bool = false
    var error: Error?
    
    // Computed
    var filteredNotifications: [GitHubNotification] { ... }
    var unreadCount: Int { ... }
    var repositories: [Repository] { ... }
    
    // Actions
    func fetchNotifications() async
    func markAsRead(_ notification: GitHubNotification) async
    func markAllAsRead() async
    func refresh() async
}
```

### SidebarViewModel

Manages sidebar state and filter selection.

```swift
@MainActor
@Observable
final class SidebarViewModel {
    var selectedFilter: NotificationFilter = .inbox
    var expandedSections: Set<String> = ["Smart Filters", "Repositories"]
    
    var smartFilters: [NotificationFilter] { ... }
    var repositoryFilters: [NotificationFilter] { ... }
}
```

## State Management

### Environment Injection

Services are injected via SwiftUI's `@Environment`:

```swift
@main
struct KuyrukApp: App {
    @State private var authService = AuthService()
    @State private var gitHubClient: GitHubClient
    @State private var notificationsViewModel: NotificationsViewModel
    
    init() {
        let auth = AuthService()
        let client = GitHubClient(authService: auth)
        _authService = State(initialValue: auth)
        _gitHubClient = State(initialValue: client)
        _notificationsViewModel = State(initialValue: NotificationsViewModel(client: client))
    }
    
    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(authService)
                .environment(gitHubClient)
                .environment(notificationsViewModel)
        }
    }
}
```

### View State Pattern

Views use lightweight local state with `@State` and access shared state via `@Environment`:

```swift
struct NotificationListView: View {
    @Environment(NotificationsViewModel.self) private var viewModel
    @State private var searchText: String = ""
    
    var body: some View {
        List(viewModel.filteredNotifications) { notification in
            NotificationRow(notification: notification)
        }
        .searchable(text: $searchText)
        .task {
            await viewModel.fetchNotifications()
        }
    }
}
```

## UI Design (macOS 26+)

### Liquid Glass Guidelines

The app uses macOS 26's Liquid Glass design language throughout:

#### Sidebar Filters
```swift
GlassEffectContainer(spacing: 8) {
    VStack(spacing: 8) {
        ForEach(smartFilters) { filter in
            FilterRow(filter: filter)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        }
    }
}
```

#### Notification Cards
```swift
NotificationRow(notification: notification)
    .padding()
    .glassEffect(.regular, in: .rect(cornerRadius: 12))
```

#### Buttons
```swift
Button("Mark as Read") { ... }
    .buttonStyle(.glass)

Button("Open in Browser") { ... }
    .buttonStyle(.glassProminent)
```

### Navigation Structure

The app uses `NavigationSplitView` for the three-column layout:

```swift
NavigationSplitView {
    SidebarView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
} content: {
    NotificationListView()
        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
} detail: {
    NotificationDetailView()
}
```

### Color Scheme

The app uses semantic colors that adapt to light/dark mode:

| Element | Light Mode | Dark Mode |
|---------|------------|-----------|
| Unread indicator | `.blue` | `.blue` |
| Review Requested badge | `.orange` with glass tint | `.orange` with glass tint |
| Mentioned badge | `.blue` with glass tint | `.blue` with glass tint |
| Assigned badge | `.green` with glass tint | `.green` with glass tint |
| CI Activity badge | `.purple` with glass tint | `.purple` with glass tint |

## Error Handling

### Error Types

```swift
enum GitHubError: Error, LocalizedError {
    case unauthorized
    case rateLimited(resetDate: Date)
    case notFound
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    
    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}
```

### Error Display

Errors are shown using SwiftUI's alert system with retry options:

```swift
.alert("Error", isPresented: $showError, presenting: viewModel.error) { error in
    Button("Retry") { Task { await viewModel.refresh() } }
    Button("Cancel", role: .cancel) { }
} message: { error in
    Text(error.localizedDescription)
}
```

## Performance Considerations

### Lazy Loading
- Use `LazyVStack` in `ScrollView` for large notification lists
- Defer image loading with `ImageCache`
- Paginate API calls if notification count is high

### Memory Management
- Cancel ongoing tasks when views disappear (`.task` handles this automatically)
- Use weak references where appropriate
- Clear caches when memory warnings occur

### Network Efficiency
- Cache responses with appropriate TTL
- Use conditional requests with `If-Modified-Since` header
- Debounce search input to reduce API calls
