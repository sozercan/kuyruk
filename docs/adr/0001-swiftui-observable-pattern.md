# ADR-0001: SwiftUI Observable Pattern

## Status

Accepted

## Context

We need to choose a state management pattern for the Kuyruk app. Options include:

1. **Traditional MVVM with ObservableObject**: Uses `@Published` properties and `ObservableObject` protocol
2. **MV (Model-View) with @Observable**: Uses Swift 5.9's new `@Observable` macro
3. **The Composable Architecture (TCA)**: Third-party framework with unidirectional data flow

Key considerations:
- macOS 26+ target allows use of newest APIs
- Team wants minimal third-party dependencies
- Performance with potentially large notification lists
- Simplicity and maintainability

## Decision

We will use the **MV pattern with `@Observable`** for state management.

### Implementation

1. **Services are `@Observable` and `@MainActor`**:
   ```swift
   @MainActor
   @Observable
   final class NotificationsViewModel {
       var notifications: [GitHubNotification] = []
       var isLoading = false
   }
   ```

2. **Environment injection for shared state**:
   ```swift
   @main
   struct KuyrukApp: App {
       @State private var viewModel = NotificationsViewModel()
       
       var body: some Scene {
           WindowGroup {
               MainWindow()
                   .environment(viewModel)
           }
       }
   }
   ```

3. **Views access via `@Environment`**:
   ```swift
   struct NotificationListView: View {
       @Environment(NotificationsViewModel.self) private var viewModel
   }
   ```

4. **Local state with `@State`**:
   ```swift
   struct FilterRow: View {
       @State private var isHovered = false
   }
   ```

### Why not MVVM with ObservableObject?

- `@Observable` provides more granular observation (only properties accessed trigger updates)
- Simpler syntax without `@Published` wrapper
- Better performance with less view invalidation
- Native Swift feature, not SwiftUI-specific

### Why not TCA?

- Adds third-party dependency
- Steeper learning curve
- Overkill for this app's complexity
- Team prefers first-party solutions

## Consequences

### Positive

- ✅ Granular view updates (better performance)
- ✅ Simpler code without `@Published` boilerplate
- ✅ Native Swift feature, well-documented
- ✅ Easy to test with dependency injection
- ✅ No third-party dependencies

### Negative

- ❌ Requires macOS 14+ (we target macOS 26, so not an issue)
- ❌ Team may need to learn new patterns
- ❌ Less prescribed architecture than TCA

### Neutral

- Views become "lightweight state expressions"
- Business logic stays in services/view models
- Testing requires mock protocols for services
