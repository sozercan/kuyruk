---
name: swift-concurrency-expert
description: Review and fix Swift Concurrency issues for Swift 6.0+ codebases. Apply actor isolation, Sendable safety, and modern concurrency patterns to resolve compiler errors and improve concurrency compliance.
---

# Swift Concurrency Expert

## Overview
Apply actor isolation, Sendable safety, and modern concurrency patterns to resolve compiler errors and improve concurrency compliance. Focuses on minimal behavior changes while ensuring data-race safety.

## Workflow

### 1. Triage the issue
- Identify the concurrency error or warning.
- Determine if it's actor isolation, Sendable, or async/await related.
- Check the Swift version and concurrency mode (strict, complete, etc.).

### 2. Apply the smallest safe fix
- Prefer `@MainActor` for UI-bound types.
- Use `nonisolated` for properties/methods that don't need isolation.
- Mark types as `Sendable` only when they truly are thread-safe.
- Use `@unchecked Sendable` sparingly and document why.

## Key Patterns

### MainActor Isolation
```swift
@MainActor
@Observable
final class NotificationsViewModel {
    var notifications: [GitHubNotification] = []
    var isLoading = false
    
    func fetchNotifications() async { ... }
}
```

### Async Task in Views
```swift
.task {
    await viewModel.fetchNotifications()
}
```

### Sendable Closures
```swift
// Use @Sendable for closures that cross actor boundaries
func process(_ handler: @Sendable @escaping () async -> Void) async { ... }
```

### Nonisolated Access
```swift
@MainActor
final class Service {
    nonisolated let id: String  // Can be accessed from any context
    
    var state: State  // Requires MainActor
}
```

## Common Fixes

| Error | Fix |
|-------|-----|
| "Cannot access property from non-isolated context" | Add `@MainActor` or use `await MainActor.run { }` |
| "Type does not conform to Sendable" | Make type `Sendable` or use `@unchecked Sendable` |
| "Actor-isolated property cannot be referenced from main actor" | Use `await` or restructure to avoid crossing boundaries |
| "Call to main actor-isolated function in a synchronous nonisolated context" | Make caller async or use `Task { @MainActor in }` |

## Testing MainActor Code

```swift
@Suite(.serialized)
@MainActor
struct ViewModelTests {
    @Test
    func fetchUpdatesState() async throws {
        let viewModel = NotificationsViewModel()
        await viewModel.fetchNotifications()
        #expect(viewModel.isLoading == false)
    }
}
```

## References
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Sendable and @Sendable](https://developer.apple.com/documentation/swift/sendable)
