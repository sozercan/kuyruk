import Foundation
import SwiftData

/// SwiftData persistence layer for caching notifications and repositories.
@MainActor
@Observable
final class DataStore {
    // MARK: - Properties

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    /// Batch size for bulk operations
    private let batchSize = 100

    // MARK: - Initialization

    init() throws {
        let schema = Schema([
            CachedNotification.self,
            CachedRepository.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true)

        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration])

        self.modelContext = ModelContext(self.modelContainer)
        self.modelContext.autosaveEnabled = false // Manual saves for batching

        DiagnosticsLogger.info("DataStore initialized", category: .data)
    }

    /// Creates a DataStore with in-memory storage for testing.
    init(inMemory: Bool) throws {
        let schema = Schema([
            CachedNotification.self,
            CachedRepository.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true)

        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration])

        self.modelContext = ModelContext(self.modelContainer)
        self.modelContext.autosaveEnabled = false
    }

    // MARK: - Notifications

    /// Saves or updates notifications from the API using batch operations.
    func saveNotifications(_ notifications: [GitHubNotification]) throws {
        guard !notifications.isEmpty else { return }

        DiagnosticsLogger.debug("Saving \(notifications.count) notifications (batched)", category: .data)

        // Fetch all existing IDs in one query
        let existingIds = try self.fetchExistingNotificationIds()

        // Process in batches
        for batch in notifications.chunked(into: self.batchSize) {
            for notification in batch {
                if existingIds.contains(notification.id) {
                    // Update existing
                    let descriptor = FetchDescriptor<CachedNotification>(
                        predicate: #Predicate { $0.id == notification.id })

                    if let existing = try modelContext.fetch(descriptor).first {
                        existing.update(from: notification)
                    }
                } else {
                    // Insert new
                    let cached = CachedNotification(from: notification)
                    self.modelContext.insert(cached)
                }
            }
        }

        // Single save at the end
        try self.modelContext.save()
        DiagnosticsLogger.info("Saved \(notifications.count) notifications", category: .data)
    }

    /// Fetches all existing notification IDs for efficient lookup.
    private func fetchExistingNotificationIds() throws -> Set<String> {
        let descriptor = FetchDescriptor<CachedNotification>()
        let notifications = try self.modelContext.fetch(descriptor)
        return Set(notifications.map(\.id))
    }

    /// Fetches all cached notifications.
    func fetchCachedNotifications() throws -> [CachedNotification] {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { !$0.isDeleted },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])

        return try self.modelContext.fetch(descriptor)
    }

    /// Fetches unread notifications.
    func fetchUnreadNotifications() throws -> [CachedNotification] {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.unread && !$0.isDeleted },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])

        return try self.modelContext.fetch(descriptor)
    }

    /// Fetches notifications for a specific repository.
    func fetchNotifications(forRepositoryId repoId: Int) throws -> [CachedNotification] {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.repositoryId == repoId && !$0.isDeleted },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])

        return try self.modelContext.fetch(descriptor)
    }

    /// Marks a notification as read in the cache.
    func markAsRead(notificationId: String) throws {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.id == notificationId })

        if let notification = try modelContext.fetch(descriptor).first {
            notification.unread = false
            notification.lastSyncedAt = Date()
            try self.modelContext.save()
            DiagnosticsLogger.debug("Marked notification \(notificationId) as read in cache", category: .data)
        } else {
            DiagnosticsLogger.warning(
                "Notification \(notificationId) not found in cache for markAsRead",
                category: .data)
        }
    }

    /// Marks a notification as unread in the cache (used for rollback).
    func markAsUnread(notificationId: String) throws {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.id == notificationId })

        if let notification = try modelContext.fetch(descriptor).first {
            notification.unread = true
            notification.lastReadAt = nil
            notification.lastSyncedAt = Date()
            try self.modelContext.save()
            DiagnosticsLogger.debug("Marked notification \(notificationId) as unread in cache", category: .data)
        }
    }

    // MARK: - Snooze Operations

    /// Snoozes a notification until the specified date.
    func snoozeNotification(id: String, until date: Date) throws {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.id == id })

        if let notification = try modelContext.fetch(descriptor).first {
            notification.snoozedUntil = date
            notification.lastSyncedAt = Date()
            try self.modelContext.save()
            DiagnosticsLogger.info("Snoozed notification \(id) until \(date)", category: .data)
        }
    }

    /// Unsnoozes a notification.
    func unsnoozeNotification(id: String) throws {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.id == id })

        if let notification = try modelContext.fetch(descriptor).first {
            notification.snoozedUntil = nil
            notification.lastSyncedAt = Date()
            try self.modelContext.save()
            DiagnosticsLogger.info("Unsnoozed notification \(id)", category: .data)
        }
    }

    /// Fetches all currently snoozed notifications.
    func fetchSnoozedNotifications() throws -> [CachedNotification] {
        let now = Date()
        // swiftlint:disable:next force_unwrapping
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.snoozedUntil != nil && $0.snoozedUntil! > now && !$0.isDeleted },
            sortBy: [SortDescriptor(\.snoozedUntil)])

        return try self.modelContext.fetch(descriptor)
    }

    /// Gets the count of snoozed notifications.
    func snoozedCount() throws -> Int {
        let now = Date()
        // swiftlint:disable:next force_unwrapping
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.snoozedUntil != nil && $0.snoozedUntil! > now && !$0.isDeleted })

        return try self.modelContext.fetchCount(descriptor)
    }

    /// Unsnoozes expired notifications (snooze time has passed).
    func unsnoozeExpiredNotifications() throws -> Int {
        let now = Date()
        // swiftlint:disable:next force_unwrapping
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.snoozedUntil != nil && $0.snoozedUntil! <= now && !$0.isDeleted })

        let expired = try self.modelContext.fetch(descriptor)

        for notification in expired {
            notification.snoozedUntil = nil
        }

        if !expired.isEmpty {
            try self.modelContext.save()
            DiagnosticsLogger.info("Unsnoozed \(expired.count) expired notifications", category: .data)
        }

        return expired.count
    }

    /// Gets the count of unread notifications.
    func unreadCount() throws -> Int {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.unread && !$0.isDeleted })

        return try self.modelContext.fetchCount(descriptor)
    }

    /// Marks notifications as deleted that are no longer in the API response.
    func markDeletedNotifications(currentIds: Set<String>) throws {
        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { !$0.isDeleted })

        let cached = try self.modelContext.fetch(descriptor)

        for notification in cached where !currentIds.contains(notification.id) {
            notification.isDeleted = true
        }

        try self.modelContext.save()
    }

    /// Permanently deletes old notifications.
    func cleanupOldNotifications(olderThan days: Int = 30) throws {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return
        }

        let descriptor = FetchDescriptor<CachedNotification>(
            predicate: #Predicate { $0.lastSyncedAt < cutoffDate })

        let old = try self.modelContext.fetch(descriptor)

        for notification in old {
            self.modelContext.delete(notification)
        }

        try self.modelContext.save()
        DiagnosticsLogger.info("Cleaned up \(old.count) old notifications", category: .data)
    }

    // MARK: - Repositories

    /// Saves or updates repositories using batch operations.
    func saveRepositories(_ repositories: [Repository]) throws {
        guard !repositories.isEmpty else { return }

        // Fetch all existing IDs in one query
        let existingIds = try self.fetchExistingRepositoryIds()

        for repository in repositories {
            if existingIds.contains(repository.id) {
                let descriptor = FetchDescriptor<CachedRepository>(
                    predicate: #Predicate { $0.id == repository.id })

                if let existing = try modelContext.fetch(descriptor).first {
                    existing.update(from: repository)
                }
            } else {
                let cached = CachedRepository(from: repository)
                self.modelContext.insert(cached)
            }
        }

        try self.modelContext.save()
    }

    /// Fetches all existing repository IDs for efficient lookup.
    private func fetchExistingRepositoryIds() throws -> Set<Int> {
        let descriptor = FetchDescriptor<CachedRepository>()
        let repositories = try self.modelContext.fetch(descriptor)
        return Set(repositories.map(\.id))
    }

    /// Fetches all cached repositories.
    func fetchCachedRepositories() throws -> [CachedRepository] {
        let descriptor = FetchDescriptor<CachedRepository>(
            sortBy: [SortDescriptor(\.fullName)])

        return try self.modelContext.fetch(descriptor)
    }

    /// Updates unread counts for repositories.
    func updateRepositoryUnreadCounts() throws {
        let repos = try self.fetchCachedRepositories()

        var hasChanges = false
        for repo in repos {
            let notifications = try self.fetchNotifications(forRepositoryId: repo.id)
            let newCount = notifications.filter(\.unread).count
            if repo.unreadCount != newCount {
                repo.unreadCount = newCount
                hasChanges = true
            }
        }

        if hasChanges {
            try self.modelContext.save()
        }
    }

    // MARK: - Container Access

    /// Returns the model container for use with SwiftUI's modelContainer modifier.
    var container: ModelContainer {
        self.modelContainer
    }
}

// MARK: - Array Extension

extension Array {
    /// Splits the array into chunks of the specified size.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
