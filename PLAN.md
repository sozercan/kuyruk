# Kuyruk - GitHub Notifications App for macOS 26

A native macOS 26 GitHub Notifications client built with Swift and SwiftUI, featuring Liquid Glass design inspired by Apple Reminders.

---

## Overview

**Kuyruk** (Turkish for "queue") is a native macOS application that provides a beautiful, focused interface for managing GitHub notifications. The app follows Apple's Human Interface Guidelines and leverages the new macOS 26 Liquid Glass design language to create a familiar yet powerful experience similar to Apple Reminders.

### Target Platform
- macOS 26.0 or later
- Swift 6.0+
- Xcode 16.0+
- Swift Package Manager (swift-tools-version: 6.0)

### Design Philosophy
- **Apple Reminders-inspired UI**: Clean sidebar navigation with notification categories (similar to smart lists)
- **Liquid Glass design**: Modern translucent surfaces with `.glassEffect()` and `GlassEffectContainer`
- **Native experience**: Full system integration with notifications, menu bar, and keyboard shortcuts

### Architectural Decisions (MVP)

| Decision | Choice | Rationale |
|----------|--------|----------|
| **Authentication** | OAuth App | Standard for desktop clients, best UX |
| **Data Persistence** | SwiftData | Offline viewing, faster startup, sync delta |
| **Sync Interval** | 60 seconds | Matches GitHub's backend refresh cycle |
| **Distribution** | Direct download (notarized) | Avoids sandbox, enables Keychain access |
| **MVP Scope** | Core only | View, mark read, open in browser |
| **Menu Bar** | Both (user preference) | Flexibility for notification apps |
| **Grouping** | By repository | Matches mental model of project work |
| **Testing** | Unit tests only | Fast coverage for MVP, add snapshots in v1.1 |
| **GitHub Enterprise** | github.com only | Simpler for MVP, designed for extensibility |
| **Multiple Accounts** | Single account | Simpler state management for MVP |
| **Inline Actions** | View only | "Open in browser" for actions, add inline in v1.1 |
| **Badge Location** | Dock icon | Standard macOS pattern |
| **Keyboard Navigation** | Essential (vim-like) | Power users expect j/k navigation |

---

## Features

### MVP Features (v1.0)
- 🔔 **Real-time Notifications** — Sync every 60 seconds, display with local alerts
- 📋 **Smart Filters** — Filter by repository, reason (review requested, mentioned, assigned, etc.)
- 🏷️ **Category Groups** — Inbox, Participating, Mentioned, Review Requested, Assigned
- ✅ **Mark as Read** — Mark notifications as read with swipe gestures or keyboard
- 🔗 **Open in Browser** — Open issues/PRs directly in default browser
- 🔍 **Search** — Full-text search across all notifications
- 🎨 **Liquid Glass UI** — macOS 26 native design with translucent surfaces
- ⌨️ **Keyboard Shortcuts** — Full keyboard control including vim-like j/k navigation
- 📦 **Repository Grouping** — Notifications grouped by repository (expandable)
- 💾 **Offline Cache** — SwiftData persistence for fast startup and offline viewing
- 🔐 **OAuth Authentication** — Secure GitHub OAuth 2.0 with PKCE
- 🔴 **Dock Badge** — Unread count on Dock icon
- 📍 **Menu Bar + Dock** — User preference for app presence

### Future Features (v1.1+)
- 📊 **Notification Statistics** — Track notification trends and patterns
- 🏷️ **Custom Tags** — Add personal tags to organize notifications
- 📌 **Pin Important** — Pin critical notifications for quick access
- 🎯 **Inline Actions** — Comment, close issues, merge PRs without leaving app
- 🔕 **Focus Modes** — Integration with macOS Focus modes
- 🏢 **GitHub Enterprise** — Support for self-hosted GitHub instances
- 👥 **Multiple Accounts** — Account switcher for multiple GitHub accounts

---

## Architecture

### Swift Package Manager Structure

This project uses **Swift Package Manager** as the primary build system. The package can be built with `swift build` or opened in Xcode.

```
Kuyruk/
├── Package.swift               → Swift Package Manager manifest
├── Sources/
│   ├── Kuyruk/                 → Main app executable target
│   │   ├── KuyrukApp.swift     → @main App struct
│   │   ├── AppDelegate.swift   → Window lifecycle, menu bar
│   │   ├── Models/             → Data models
│   │   │   ├── Notification.swift
│   │   │   ├── Repository.swift
│   │   │   ├── NotificationReason.swift
│   │   │   └── NotificationFilter.swift
│   │   ├── Services/
│   │   │   ├── API/            → GitHub API client
│   │   │   │   ├── GitHubClient.swift
│   │   │   │   ├── GitHubEndpoints.swift
│   │   │   │   └── Parsers/
│   │   │   ├── Auth/           → OAuth authentication
│   │   │   │   ├── AuthService.swift
│   │   │   │   └── KeychainManager.swift
│   │   │   ├── Persistence/    → SwiftData storage
│   │   │   │   └── DataStore.swift
│   │   │   ├── Notifications/  → Local notification handling
│   │   │   │   └── NotificationService.swift
│   │   │   └── Sync/           → Background sync service
│   │   │       └── SyncService.swift
│   │   ├── ViewModels/         → Observable view models
│   │   │   ├── NotificationsViewModel.swift
│   │   │   ├── SidebarViewModel.swift
│   │   │   └── SettingsViewModel.swift
│   │   ├── Views/              → SwiftUI views
│   │   │   ├── MainWindow.swift
│   │   │   ├── Sidebar/
│   │   │   │   ├── SidebarView.swift
│   │   │   │   ├── FilterRow.swift
│   │   │   │   └── RepositorySection.swift
│   │   │   ├── Content/
│   │   │   │   ├── NotificationListView.swift
│   │   │   │   ├── NotificationRow.swift
│   │   │   │   └── EmptyStateView.swift
│   │   │   ├── Detail/
│   │   │   │   ├── NotificationDetailView.swift
│   │   │   │   └── IssuePreviewView.swift
│   │   │   ├── Components/
│   │   │   │   ├── GlassCard.swift
│   │   │   │   ├── FilterChip.swift
│   │   │   │   ├── AvatarView.swift
│   │   │   │   └── StatusBadge.swift
│   │   │   └── Settings/
│   │   │       └── SettingsView.swift
│   │   ├── Utilities/
│   │   │   ├── DiagnosticsLogger.swift
│   │   │   ├── ImageCache.swift
│   │   │   └── Extensions/
│   │   └── Resources/          → App resources (assets, etc.)
│   └── APIExplorer/            → CLI tool executable target
│       └── main.swift
├── Tests/
│   └── KuyrukTests/            → Unit test target
│       └── ...swift
├── docs/
│   ├── architecture.md
│   ├── api-integration.md
│   └── adr/
└── .swiftformat                → SwiftFormat configuration
```

### Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kuyruk",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "Kuyruk",
            targets: ["Kuyruk"]
        ),
        .executable(
            name: "api-explorer",
            targets: ["APIExplorer"]
        )
    ],
    dependencies: [
        // No third-party dependencies (first-party only policy)
    ],
    targets: [
        // Main app executable
        .executableTarget(
            name: "Kuyruk",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        // API Explorer CLI tool
        .executableTarget(
            name: "APIExplorer",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Unit tests
        .testTarget(
            name: "KuyrukTests",
            dependencies: ["Kuyruk"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
```

### Build Commands

```bash
# Build the app
swift build

# Build for release
swift build -c release

# Run the app (CLI mode - for debugging)
swift run Kuyruk

# Run the API Explorer tool
swift run api-explorer notifications

# Run tests
swift test

# Generate Xcode project (optional, for Xcode development)
swift package generate-xcodeproj

# Or open directly in Xcode (recommended)
open Package.swift
```

> **Note**: For full macOS app bundle with proper entitlements, code signing, and notarization, use Xcode with the generated scheme or create an Xcode project that references the Swift package.

### State Management
Following the MV (Model-View) pattern as recommended in Skills:

```swift
// Services injected via @Environment
@MainActor
@Observable
final class NotificationsViewModel {
    var notifications: [GitHubNotification] = []
    var selectedFilter: NotificationFilter = .inbox
    var isLoading: Bool = false
    var error: Error?
    
    private let gitHubClient: GitHubClient
    private let syncService: SyncService
    
    func fetchNotifications() async { ... }
    func markAsRead(_ notification: GitHubNotification) async { ... }
}
```

### Data Flow
```
GitHub API ──► GitHubClient ──► NotificationsViewModel ──► Views
                    │                    ▲
                    ▼                    │
              SwiftData ─────────────────┘
              (DataStore)
```

### Persistence Layer

Using SwiftData for local caching:

```swift
import SwiftData

@Model
final class CachedNotification {
    @Attribute(.unique) var id: String
    var title: String
    var repositoryName: String
    var reason: String
    var unread: Bool
    var updatedAt: Date
    var url: String
    
    // Sync metadata
    var lastSyncedAt: Date
}
```

**Benefits:**
- Fast app startup (load from cache, then sync)
- Offline viewing of previously fetched notifications
- Sync delta detection (only fetch new/changed)

---

## UI Design

### Layout (Reminders-Inspired)
```
┌─────────────────────────────────────────────────────────────────┐
│  ● ● ●                    Kuyruk                                │
├─────────────┬───────────────────────────────────────────────────┤
│             │                                                   │
│  SMART      │  ┌─────────────────────────────────────────────┐  │
│  FILTERS    │  │ ● Issue Title #123                         │  │
│             │  │   repo/name • 2h ago • @username            │  │
│  📥 Inbox   │  │   Review requested by @reviewer             │  │
│  👤 Assigned│  └─────────────────────────────────────────────┘  │
│  💬 Mention │  ┌─────────────────────────────────────────────┐  │
│  👀 Review  │  │ ● PR Title #456                             │  │
│             │  │   repo/name • 5h ago • @author              │  │
│  ───────────│  │   You were mentioned                        │  │
│             │  └─────────────────────────────────────────────┘  │
│  REPOS      │                                                   │
│             │                                                   │
│  📦 repo1   │                                                   │
│  📦 repo2   │                                                   │
│  📦 repo3   │                                                   │
│             │                                                   │
└─────────────┴───────────────────────────────────────────────────┘
```

### Liquid Glass Implementation

Following the SwiftUI Liquid Glass skill guidelines:

```swift
// Sidebar filter items with glass effect
GlassEffectContainer(spacing: 8) {
    VStack(spacing: 8) {
        ForEach(filters) { filter in
            FilterRow(filter: filter, isSelected: selectedFilter == filter)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
        }
    }
}

// Notification cards with subtle glass
NotificationRow(notification: notification)
    .padding()
    .glassEffect(.regular, in: .rect(cornerRadius: 12))

// Toolbar buttons
Button(action: { }) {
    Image(systemName: "arrow.clockwise")
}
.buttonStyle(.glass)
```

### Color Scheme
- Use semantic colors that adapt to light/dark mode
- Notification reason badges with tinted glass:
  - Review Requested: `.tint(.orange)`
  - Mentioned: `.tint(.blue)`
  - Assigned: `.tint(.green)`
  - CI Activity: `.tint(.purple)`

---

## Technical Implementation

### GitHub API Integration

#### Authentication
- OAuth 2.0 with PKCE flow
- Token storage in Keychain
- Automatic token refresh

#### Endpoints Used
```
GET /notifications                    → List notifications
PATCH /notifications/threads/:id     → Mark as read
GET /repos/:owner/:repo/issues/:num  → Issue details
GET /repos/:owner/:repo/pulls/:num   → PR details
GET /user                             → Current user info
```

#### API Client Pattern
```swift
@MainActor
@Observable
final class GitHubClient {
    private let session: URLSession
    private let authService: AuthService
    
    func fetchNotifications(all: Bool = false) async throws -> [GitHubNotification] {
        let request = try await buildRequest(for: .notifications(all: all))
        let (data, response) = try await session.data(for: request)
        return try JSONDecoder().decode([GitHubNotification].self, from: data)
    }
}
```

### Local Notifications
```swift
@MainActor
final class NotificationService {
    func scheduleNotification(for ghNotification: GitHubNotification) async {
        let content = UNMutableNotificationContent()
        content.title = ghNotification.repository.fullName
        content.body = ghNotification.subject.title
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: ghNotification.id,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| ⌘1-5 | Switch to filter 1-5 |
| ⌘R | Refresh notifications |
| ⌘O | Open in browser |
| ⌘⇧M | Mark as read |
| ⌘K | Open command bar |
| ↑↓ or j/k | Navigate notifications (vim-like) |
| ⏎ or o | Open selected notification |
| ⌘F or / | Focus search |
| g g | Go to top of list |
| G | Go to bottom of list |
| Esc | Clear selection / Close detail |

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
**Deliverables:**
- [ ] Project setup with Swift Package Manager
- [ ] Create `Package.swift` with correct platforms and targets
- [ ] Basic project structure following SPM conventions
- [ ] GitHub OAuth authentication (OAuth App with PKCE)
- [ ] API client with basic endpoints
- [ ] Core data models (API + SwiftData)
- [ ] SwiftData persistence layer (DataStore)

**Exit Criteria:**
- `swift build` passes without errors
- `swift test` runs (even with placeholder tests)
- Can authenticate with GitHub (github.com only)
- Can fetch notifications from API
- Notifications persist to SwiftData

### Phase 2: Core UI (Week 2)
**Deliverables:**
- [ ] Main window with NavigationSplitView
- [ ] Sidebar with smart filters
- [ ] Notification list view with repository grouping
- [ ] Expandable repository sections
- [ ] Basic notification row component
- [ ] Empty states
- [ ] Loading states

**Exit Criteria:**
- App displays notifications grouped by repository
- Sidebar navigation works
- Filter selection updates the list
- Offline: shows cached notifications on startup

### Phase 3: Liquid Glass Integration (Week 3)
**Deliverables:**
- [ ] GlassEffectContainer for sidebar
- [ ] Glass-styled notification cards
- [ ] Interactive glass buttons
- [ ] Glass-styled toolbar
- [ ] Proper fallbacks for older OS (if needed)

**Exit Criteria:**
- All interactive elements use `.glassEffect(.interactive())`
- Glass effects render correctly
- UI matches macOS 26 design language

### Phase 4: Notification Actions (Week 4)
**Deliverables:**
- [ ] Mark as read functionality
- [ ] Swipe actions on rows
- [ ] Context menus
- [ ] Open in browser
- [ ] Notification detail view

**Exit Criteria:**
- Can mark notifications as read
- Swipe gestures work
- Can open issues/PRs in browser

### Phase 5: System Integration (Week 5)
**Deliverables:**
- [ ] Local notifications for new GitHub notifications
- [ ] Background sync service (60-second interval)
- [ ] Menu bar icon with dropdown
- [ ] User preference: Dock only / Menu bar only / Both
- [ ] Keyboard shortcuts including vim-like navigation (j/k)
- [ ] Dock badge with unread count
- [ ] Settings view with preferences

**Exit Criteria:**
- Receives local alerts for new notifications
- Background sync works (60-second polling)
- All keyboard shortcuts functional (including j/k)
- User can toggle menu bar / dock visibility

### Phase 6: Polish & Testing (Week 6)
**Deliverables:**
- [ ] Unit tests for services
- [ ] UI polish and animations
- [ ] Error handling improvements
- [ ] Performance optimization
- [ ] Documentation

**Exit Criteria:**
- Test coverage > 70%
- No SwiftLint errors
- App feels polished and responsive

---

## Dependencies

### First-Party Only
Following the kaset pattern, no third-party frameworks:
- SwiftUI (UI)
- SwiftData (Persistence)
- Foundation (Networking, JSON)
- Security (Keychain)
- UserNotifications (Local alerts)
- OSLog (Logging)

### Swift Package Manager Benefits
- **Command-line builds**: `swift build` works without Xcode
- **Cross-platform potential**: SPM packages can target Linux (though this app is macOS-only)
- **Declarative manifest**: `Package.swift` is readable, versionable Swift code
- **Modern tooling**: Native integration with Xcode 16+ and Swift 6.0
- **Test isolation**: Clear separation of test targets

### Skills Required
From [Dimillian/Skills](https://github.com/Dimillian/Skills):
- 💎 **SwiftUI Liquid Glass** — Core UI implementation
- 🔧 **SwiftUI View Refactor** — Code structure and patterns
- ⚡ **Swift Concurrency Expert** — Async/await, actor isolation
- 🚀 **SwiftUI Performance Audit** — Performance optimization
- 📝 **SwiftUI UI Patterns** — TabView, NavigationStack, Lists

---

## AGENTS.md Reference

The following patterns should be followed (adapted from kaset):

### Critical Rules
- Never leak tokens or secrets
- Never run `git commit` or `git push`
- No third-party frameworks without approval
- Use DiagnosticsLogger, not `print()`
- Prefer API calls over WebView

### Modern SwiftUI APIs
| Avoid | Use Instead |
|-------|-------------|
| `.foregroundColor()` | `.foregroundStyle()` |
| `.cornerRadius()` | `.clipShape(.rect(cornerRadius:))` |
| `NavigationView` | `NavigationSplitView` |
| `print()` | `DiagnosticsLogger` |
| `.background(.ultraThinMaterial)` | `.glassEffect()` for macOS 26+ |

### Liquid Glass UI (macOS 26+)
- Use `.glassEffect(.regular.interactive(), in: .capsule)` for interactive elements
- Wrap multiple glass elements in `GlassEffectContainer`
- Avoid glass-on-glass (no `.buttonStyle(.glass)` inside glass containers)

### Swift Concurrency
- Mark `@Observable` classes with `@MainActor`
- Never use `DispatchQueue` — use `async`/`await`
- Use `.task` for async loading in views

### Testing
- Use Swift Testing (`@Suite`, `@Test`, `#expect`)
- Keep UI tests separate from unit tests
- Run `swiftlint --strict && swiftformat .` before completing work

---

## UI Components Reference

### NotificationRow
```swift
struct NotificationRow: View {
    let notification: GitHubNotification
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(notification.unread ? .blue : .clear)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.subject.title)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(notification.repository.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(notification.updatedAt.relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                ReasonBadge(reason: notification.reason)
            }
            
            Spacer()
            
            Image(systemName: notification.subject.type.icon)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
```

### SidebarView
```swift
struct SidebarView: View {
    @Environment(NotificationsViewModel.self) private var viewModel
    
    var body: some View {
        List(selection: $viewModel.selectedFilter) {
            Section("Smart Filters") {
                GlassEffectContainer(spacing: 4) {
                    ForEach(NotificationFilter.smartFilters) { filter in
                        FilterRow(filter: filter)
                            .tag(filter)
                    }
                }
            }
            
            Section("Repositories") {
                ForEach(viewModel.repositories) { repo in
                    Label(repo.name, systemImage: "folder")
                        .tag(NotificationFilter.repository(repo))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Kuyruk")
    }
}
```

---

## Resources

### Reference Projects
- [sozercan/kaset](https://github.com/sozercan/kaset) — Architecture, AGENTS.md, patterns
- [Dimillian/Skills](https://github.com/Dimillian/Skills) — SwiftUI skills and Liquid Glass

### Apple Documentation
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [GlassEffectContainer](https://developer.apple.com/documentation/SwiftUI/GlassEffectContainer)
- [GitHub REST API - Notifications](https://docs.github.com/en/rest/activity/notifications)

### Design References
- Apple Reminders app (layout inspiration)
- macOS 26 Human Interface Guidelines
- GitHub notification screenshot (attached)

---

## Next Steps

1. **Review this plan** and confirm scope
2. **Set up project structure** following the layout above
3. **Implement authentication** with GitHub OAuth
4. **Build basic UI** with Liquid Glass
5. **Iterate** based on feedback

---

*Plan created: January 5, 2026*
*Version: 1.1 — Updated with architectural decisions*
