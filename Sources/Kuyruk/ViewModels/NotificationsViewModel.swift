import Foundation

/// View model for managing notifications display and interactions.
@MainActor
@Observable
final class NotificationsViewModel {
    // MARK: - Properties

    /// All notifications
    private(set) var notifications: [GitHubNotification] = []

    /// Unique repositories from notifications
    private(set) var repositories: [Repository] = []

    /// Currently selected filter
    var selectedFilter: NotificationFilter = .inbox

    /// Currently selected notification
    var selectedNotification: GitHubNotification?

    /// Loading state
    private(set) var isLoading: Bool = false

    /// Error state
    private(set) var error: Error?

    /// Search text
    var searchText: String = ""

    private let gitHubClient: GitHubClient
    private let dataStore: DataStore
    private let syncService: SyncService

    // MARK: - Computed Properties

    /// Notifications filtered by the current filter and search text
    var filteredNotifications: [GitHubNotification] {
        var filtered = self.notifications.filter { self.selectedFilter.matches($0) }

        if !self.searchText.isEmpty {
            let query = self.searchText.lowercased()
            filtered = filtered.filter { notification in
                notification.subject.title.lowercased().contains(query) ||
                    notification.repository.fullName.lowercased().contains(query) ||
                    notification.reason.displayName.lowercased().contains(query)
            }
        }

        return filtered
    }

    /// Count of unread notifications
    var unreadCount: Int {
        self.notifications.filter(\.unread).count
    }

    // MARK: - Initialization

    init(gitHubClient: GitHubClient, dataStore: DataStore, syncService: SyncService) {
        self.gitHubClient = gitHubClient
        self.dataStore = dataStore
        self.syncService = syncService
    }

    // MARK: - Public Methods

    /// Loads notifications from cache on startup.
    func loadFromCache() async {
        DiagnosticsLogger.info("Loading notifications from cache", category: .ui)

        do {
            let cached = try self.dataStore.fetchCachedNotifications()

            // Convert cached notifications to GitHubNotification
            // For now, we'll trigger a refresh to get fresh data
            DiagnosticsLogger.info("Found \(cached.count) cached notifications", category: .ui)
        } catch {
            DiagnosticsLogger.error(error, context: "loadFromCache", category: .ui)
        }

        // Always refresh on startup
        await self.refresh()
    }

    /// Refreshes notifications from the API.
    func refresh() async {
        guard !self.isLoading else { return }

        self.isLoading = true
        self.error = nil

        DiagnosticsLogger.info("Refreshing notifications", category: .ui)

        do {
            self.notifications = try await self.gitHubClient.fetchAllNotifications()

            // Extract unique repositories
            self.repositories = Array(Set(self.notifications.map(\.repository)))
                .sorted { $0.fullName < $1.fullName }

            // Save to cache
            try self.dataStore.saveNotifications(self.notifications)
            try self.dataStore.saveRepositories(self.repositories)

            DiagnosticsLogger.info(
                "Loaded \(self.notifications.count) notifications from \(self.repositories.count) repositories",
                category: .ui)
        } catch {
            self.error = error
            DiagnosticsLogger.error(error, context: "refresh", category: .ui)
        }

        self.isLoading = false
    }

    /// Marks a notification as read.
    func markAsRead(_ notification: GitHubNotification) async {
        DiagnosticsLogger.info("Marking notification \(notification.id) as read", category: .ui)

        do {
            try await self.gitHubClient.markAsRead(threadId: notification.id)

            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                // Create updated notification with unread = false
                let updated = GitHubNotification(
                    id: notification.id,
                    repository: notification.repository,
                    subject: notification.subject,
                    reason: notification.reason,
                    unread: false,
                    updatedAt: notification.updatedAt,
                    lastReadAt: Date(),
                    url: notification.url,
                    subscriptionUrl: notification.subscriptionUrl)
                self.notifications[index] = updated

                // Update selected notification if needed
                if self.selectedNotification?.id == notification.id {
                    self.selectedNotification = updated
                }
            }

            // Update cache
            try self.dataStore.markAsRead(notificationId: notification.id)
        } catch {
            DiagnosticsLogger.error(error, context: "markAsRead", category: .ui)
        }
    }

    /// Clears the current error.
    func clearError() {
        self.error = nil
    }
}
