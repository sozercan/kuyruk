````markdown
# ADR 0005: SwiftData for Local Persistence

## Status

Accepted

## Context

The app needs local data persistence to:
1. Enable fast startup by loading cached notifications
2. Allow offline viewing of previously fetched notifications
3. Detect sync deltas (what's new, what's changed)
4. Reduce API calls by caching data locally

### Options Considered

1. **In-memory only** — No persistence, fresh fetch on every launch
2. **JSON files** — Simple file-based persistence
3. **SQLite (raw)** — Direct SQLite database access
4. **Core Data** — Apple's legacy object graph framework
5. **SwiftData** — Apple's modern persistence framework (Swift-native)

## Decision

We will use **SwiftData** for local persistence.

### Rationale

1. **Swift-native**: SwiftData uses Swift macros (`@Model`) and integrates naturally with Swift 6.0 and SwiftUI
2. **Minimal boilerplate**: No need for NSManagedObject subclasses or .xcdatamodeld files
3. **SwiftUI integration**: Works seamlessly with `@Query` and `@Environment(\.modelContext)`
4. **First-party**: Aligns with our "no third-party dependencies" policy
5. **Modern API**: Built on CloudKit patterns, supports async/await

### Data Models

```swift
@Model
final class CachedNotification {
    @Attribute(.unique) var id: String
    var title: String
    var repositoryName: String
    var reason: String
    var unread: Bool
    var updatedAt: Date
    var url: String
    var lastSyncedAt: Date
}
```

### Usage Pattern

```swift
@MainActor
final class DataStore {
    private let modelContainer: ModelContainer
    
    init() throws {
        let schema = Schema([CachedNotification.self])
        self.modelContainer = try ModelContainer(for: schema)
    }
    
    func saveNotifications(_ notifications: [GitHubNotification]) throws {
        let context = modelContainer.mainContext
        for notification in notifications {
            // Upsert logic
        }
        try context.save()
    }
}
```

## Consequences

### Positive

1. **Fast startup**: App loads cached data instantly, syncs in background
2. **Offline support**: Users can view notifications without network
3. **Reduced API load**: Only fetch deltas after initial load
4. **Modern code**: SwiftData feels natural in Swift 6.0 codebase
5. **Type safety**: Compile-time checking of model relationships

### Negative

1. **macOS 14+ requirement**: SwiftData requires macOS Sonoma or later
   - **Mitigation**: We already require macOS 26, so this is not an issue
2. **Migration complexity**: Schema changes require migration code
   - **Mitigation**: Start with a simple schema, plan migrations carefully
3. **Learning curve**: SwiftData is newer, less community knowledge
   - **Mitigation**: Apple documentation is comprehensive

### Trade-offs

- **vs. Core Data**: SwiftData is simpler but less mature. Core Data has more features but verbose boilerplate.
- **vs. JSON files**: JSON is simpler but lacks query capabilities and relationship management.
- **vs. SQLite**: Raw SQLite is more flexible but requires manual ORM layer.

## Implementation Notes

### Schema

Start with minimal schema:
- `CachedNotification` — Mirrors GitHub API notification structure
- `CachedRepository` — Repository metadata with unread counts

### Sync Metadata

Each cached entity includes:
- `lastSyncedAt: Date` — When this record was last updated from API
- `isDeleted: Bool` — Soft delete flag for sync

### Cache Invalidation

- Prune notifications older than 30 days
- Full refresh if last sync was > 24 hours ago
- Clear cache on logout

## References

- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [Migrating from Core Data to SwiftData](https://developer.apple.com/documentation/swiftdata/migrating-from-core-data-to-swiftdata)
- [ADR 0004: Swift Package Manager](0004-swift-package-manager.md)

````