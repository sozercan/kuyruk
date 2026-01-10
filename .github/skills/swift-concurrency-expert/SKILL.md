---
name: swift-concurrency-expert
description: Swift Concurrency review and remediation for Swift 6.2+. Use when asked to review Swift Concurrency usage, improve concurrency compliance, or fix Swift concurrency compiler errors in a feature or file.
---

# Swift Concurrency Expert

## Overview
Review and fix Swift Concurrency issues in Swift 6.2+ codebases by applying actor isolation, Sendable safety, and modern concurrency patterns with minimal behavior changes.

## Workflow

### 1. Triage the issue
- Capture the exact compiler diagnostics and the offending symbol(s).
- Check project concurrency settings: Swift language version (6.2+), strict concurrency level, and whether approachable concurrency (default actor isolation / main-actor-by-default) is enabled.
- Identify the current actor context (`@MainActor`, `actor`, `nonisolated`) and whether a default actor isolation mode is enabled.
- Confirm whether the code is UI-bound or intended to run off the main actor.

### 2. Apply the smallest safe fix
Prefer edits that preserve existing behavior while satisfying data-race safety.

Common fixes:
- **UI-bound types**: annotate the type or relevant members with `@MainActor`.
- **Protocol conformance on main actor types**: make the conformance isolated (e.g., `extension Foo: @MainActor SomeProtocol`).
- **Global/static state**: protect with `@MainActor` or move into an actor.
- **Background work**: move expensive work into a `@concurrent` async function on a `nonisolated` type or use an `actor` to guard mutable state.
- **Sendable errors**: prefer immutable/value types; add `Sendable` conformance only when correct; avoid `@unchecked Sendable` unless you can prove thread safety.

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

### Background Work with @concurrent
```swift
@MainActor
final class DataProcessor {
    @concurrent
    nonisolated func processData(_ data: Data) async -> ProcessedData {
        // Heavy computation runs off main actor
        return await heavyProcess(data)
    }
}
```

## Common Fixes

| Error | Fix |
|-------|-----|
| "Cannot access property from non-isolated context" | Add `@MainActor` or use `await MainActor.run { }` |
| "Type does not conform to Sendable" | Make type `Sendable` or use `@unchecked Sendable` |
| "Actor-isolated property cannot be referenced from main actor" | Use `await` or restructure to avoid crossing boundaries |
| "Call to main actor-isolated function in a synchronous nonisolated context" | Make caller async or use `Task { @MainActor in }` |
| "Passing closure as a 'sending' parameter" | Ensure closure captures only Sendable values or use `@Sendable` |

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

## Approachable Concurrency Mode
When the project opts into approachable concurrency (Swift 6.2+):
- Types default to `@MainActor` isolation in UI modules.
- Use `nonisolated` explicitly for background work.
- Use `@concurrent` for async functions that should run off the main actor.

## References
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Sendable and @Sendable](https://developer.apple.com/documentation/swift/sendable)
- [WWDC24: What's new in Swift](https://developer.apple.com/videos/play/wwdc2024/10136/)
