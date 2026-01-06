import Foundation
import SwiftData

/// SwiftData persistence layer for caching notifications and repositories.
@MainActor
@Observable
final class DataStore {
    // MARK: - Properties

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

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
        self.modelContext.autosaveEnabled = true

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
        self.modelContext.autosaveEnabled = true
    }

    // MARK: - Notifications

    /// Saves or updates notifications from the API.
    func saveNotifications(_ notifications: [GitHubNotification]) throws {
        DiagnosticsLogger.debug("Saving \(notifications.count) notifications", category: .data)

        for notification in notifications {
            let descriptor = FetchDescriptor<CachedNotification>(
                predicate: #Predicate { $0.id == notification.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: notification)
            } else {
                let cached = CachedNotification(from: notification)
                self.modelContext.insert(cached)
            }
        }

        try self.modelContext.save()
        DiagnosticsLogger.info("Saved \(notifications.count) notifications", category: .data)
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
        }
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

    /// Saves or updates repositories.
    func saveRepositories(_ repositories: [Repository]) throws {
        for repository in repositories {
            let descriptor = FetchDescriptor<CachedRepository>(
                predicate: #Predicate { $0.id == repository.id })

            if let existing = try modelContext.fetch(descriptor).first {
                existing.update(from: repository)
            } else {
                let cached = CachedRepository(from: repository)
                self.modelContext.insert(cached)
            }
        }

        try self.modelContext.save()
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

        for repo in repos {
            let notifications = try self.fetchNotifications(forRepositoryId: repo.id)
            repo.unreadCount = notifications.filter(\.unread).count
        }

        try self.modelContext.save()
    }

    // MARK: - Container Access

    /// Returns the model container for use with SwiftUI's modelContainer modifier.
    var container: ModelContainer {
        self.modelContainer
    }
}
