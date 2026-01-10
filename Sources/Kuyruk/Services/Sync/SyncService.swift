import Foundation

/// Callback for progressive notification updates.
typealias NotificationUpdateHandler = @MainActor @Sendable ([GitHubNotification]) -> Void

/// Background sync service for fetching notifications from GitHub.
@MainActor
@Observable
final class SyncService {
    // MARK: - Properties

    /// Current sync status
    private(set) var isSyncing: Bool = false

    /// Last sync timestamp
    private(set) var lastSyncedAt: Date?

    /// Sync error (if any)
    private(set) var lastError: Error?

    /// Count of new notifications since last check
    private(set) var newNotificationCount: Int = 0

    /// Whether data was modified in last sync
    private(set) var lastSyncHadChanges: Bool = false

    /// Sync interval in seconds (configurable)
    var syncInterval: TimeInterval {
        TimeInterval(UserDefaults.standard.integer(forKey: "syncInterval").clamped(to: 30...900))
    }

    private let gitHubClient: GitHubClient
    private let dataStore: DataStore
    private let notificationService: NotificationService?
    private var syncTask: Task<Void, Never>?
    private var previousNotificationIds: Set<String> = []

    /// Optional callback for progressive updates
    var onNotificationsUpdated: NotificationUpdateHandler?

    // MARK: - Initialization

    init(
        gitHubClient: GitHubClient,
        dataStore: DataStore,
        notificationService: NotificationService? = nil) {
        self.gitHubClient = gitHubClient
        self.dataStore = dataStore
        self.notificationService = notificationService

        // Set default sync interval if not set
        if UserDefaults.standard.integer(forKey: "syncInterval") == 0 {
            UserDefaults.standard.set(60, forKey: "syncInterval")
        }
    }

    // MARK: - Public Methods

    /// Starts the background sync loop.
    func startBackgroundSync() {
        guard self.syncTask == nil else {
            DiagnosticsLogger.warning("Background sync already running", category: .sync)
            return
        }

        DiagnosticsLogger.info("Starting background sync (interval: \(self.syncInterval)s)", category: .sync)

        // Register notification categories
        self.notificationService?.registerCategories()

        self.syncTask = Task { [weak self] in
            guard let self else { return }

            // Initial sync
            await self.sync(isInitialSync: true)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.syncInterval))
                } catch {
                    // Task was cancelled
                    break
                }

                await self.sync(isInitialSync: false)
            }
        }
    }

    /// Stops the background sync loop.
    func stopBackgroundSync() {
        DiagnosticsLogger.info("Stopping background sync", category: .sync)
        self.syncTask?.cancel()
        self.syncTask = nil
    }

    /// Performs a single sync operation.
    func sync(isInitialSync: Bool = false) async {
        guard !self.isSyncing else {
            DiagnosticsLogger.debug("Sync already in progress, skipping", category: .sync)
            return
        }

        self.isSyncing = true
        self.lastError = nil
        self.newNotificationCount = 0
        self.lastSyncHadChanges = false

        DiagnosticsLogger.info("Starting sync (initial: \(isInitialSync))", category: .sync)

        do {
            // Use conditional fetch - returns nil if unchanged
            guard let notifications = try await gitHubClient.fetchAllNotifications() else {
                // 304 Not Modified - no changes
                DiagnosticsLogger.info("No changes since last sync (304)", category: .sync)
                self.lastSyncedAt = Date()
                self.isSyncing = false
                return
            }

            self.lastSyncHadChanges = true
            DiagnosticsLogger.info("Fetched \(notifications.count) notifications from API", category: .sync)

            // Notify listeners of new data
            self.onNotificationsUpdated?(notifications)

            // Detect new notifications
            let currentIds = Set(notifications.map(\.id))
            let newIds = currentIds.subtracting(self.previousNotificationIds)
            let newNotifications = notifications.filter { newIds.contains($0.id) && $0.unread }

            if !isInitialSync, !newNotifications.isEmpty {
                self.newNotificationCount = newNotifications.count
                DiagnosticsLogger.info("Found \(newNotifications.count) new notifications", category: .sync)

                // Send local notifications for new items
                await self.notificationService?.scheduleNotifications(for: newNotifications)
            } else if isInitialSync {
                // Mark all current notifications as "already notified" on initial sync
                self.notificationService?.markAsNotified(Array(currentIds))
            }

            // Update previous IDs for next comparison
            self.previousNotificationIds = currentIds

            // Save to cache
            try self.dataStore.saveNotifications(notifications)

            // Extract and save unique repositories
            let repositories = Array(Set(notifications.map(\.repository)))
            try self.dataStore.saveRepositories(repositories)

            // Update repository unread counts
            try self.dataStore.updateRepositoryUnreadCounts()

            // Mark notifications that are no longer in the API response
            try self.dataStore.markDeletedNotifications(currentIds: currentIds)

            self.lastSyncedAt = Date()
            DiagnosticsLogger.info("Sync completed successfully", category: .sync)
        } catch {
            self.lastError = error
            DiagnosticsLogger.error(error, context: "sync", category: .sync)
        }

        self.isSyncing = false
    }

    /// Forces an immediate sync, bypassing conditional caching.
    func forceSync() async {
        guard !self.isSyncing else { return }

        self.isSyncing = true
        self.lastError = nil

        DiagnosticsLogger.info("Starting force sync", category: .sync)

        do {
            let notifications = try await gitHubClient.fetchAllNotificationsForced()
            self.lastSyncHadChanges = true

            // Notify listeners
            self.onNotificationsUpdated?(notifications)

            // Save to cache
            try self.dataStore.saveNotifications(notifications)

            let repositories = Array(Set(notifications.map(\.repository)))
            try self.dataStore.saveRepositories(repositories)

            self.lastSyncedAt = Date()
            DiagnosticsLogger.info("Force sync completed successfully", category: .sync)
        } catch {
            self.lastError = error
            DiagnosticsLogger.error(error, context: "forceSync", category: .sync)
        }

        self.isSyncing = false
    }

    /// Clears the sync error.
    func clearError() {
        self.lastError = nil
    }
}

// MARK: - Helpers

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
