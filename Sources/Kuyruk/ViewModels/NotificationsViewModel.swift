import Combine
import Foundation

/// View model for managing notifications display and interactions.
@MainActor
@Observable
final class NotificationsViewModel {
    // MARK: - Properties

    /// All notifications
    private(set) var notifications: [GitHubNotification] = [] {
        didSet {
            self.updateGroupedNotifications()
        }
    }

    /// Unique repositories from notifications
    private(set) var repositories: [Repository] = []

    /// Pre-computed grouped notifications (updated only when data changes)
    private(set) var groupedNotifications: [(key: String, value: [GitHubNotification])] = []

    /// Currently selected filter
    var selectedFilter: NotificationFilter = .inbox {
        didSet {
            self.updateGroupedNotifications()
        }
    }

    /// Currently selected notification
    var selectedNotification: GitHubNotification?

    /// Loading state (only true when no cached data available)
    private(set) var isLoading: Bool = false

    /// Refreshing state (true when updating in background)
    private(set) var isRefreshing: Bool = false

    /// Error state
    private(set) var error: Error?

    /// Search text (debounced)
    var searchText: String = "" {
        didSet {
            self.scheduleSearchUpdate()
        }
    }

    /// Debounced search text (actually applied to filtering)
    private var debouncedSearchText: String = ""

    private let gitHubClient: GitHubClient
    private let dataStore: DataStore
    private let syncService: SyncService

    /// Debounce timer for search
    private var searchDebounceTask: Task<Void, Never>?

    /// Debounce delay for search (300ms)
    private let searchDebounceDelay: Duration = .milliseconds(300)

    // MARK: - Computed Properties

    /// Notifications filtered by the current filter and search text
    var filteredNotifications: [GitHubNotification] {
        var filtered = self.notifications.filter { self.selectedFilter.matches($0) }

        if !self.debouncedSearchText.isEmpty {
            let query = self.debouncedSearchText.lowercased()
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

    /// Loads notifications from cache on startup, then refreshes in background.
    func loadFromCache() async {
        DiagnosticsLogger.info("Loading notifications from cache", category: .ui)

        do {
            let cached = try self.dataStore.fetchCachedNotifications()

            if !cached.isEmpty {
                // Convert cached notifications to GitHubNotification
                self.notifications = cached.compactMap { self.convertCachedNotification($0) }
                self.repositories = self.extractRepositories(from: self.notifications)

                DiagnosticsLogger.info(
                    "Loaded \(self.notifications.count) notifications from cache",
                    category: .ui)

                // Prefetch avatars for visible items
                await self.prefetchAvatars()

                // Refresh in background WITHOUT blocking - stale-while-revalidate pattern
                self.refreshInBackground()
            } else {
                // No cache - must wait for network
                await self.refresh()
            }
        } catch {
            DiagnosticsLogger.error(error, context: "loadFromCache", category: .ui)
            await self.refresh()
        }
    }

    /// Refreshes in the background without blocking the caller.
    /// Uses stale-while-revalidate pattern - shows existing data while fetching.
    private func refreshInBackground() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    /// Refreshes notifications from the API.
    func refresh() async {
        // Don't show any loading indicator if:
        // 1. Cache is still valid (TTL not expired), OR
        // 2. We have conditional headers for 304 optimization AND have cached data to show
        let canSilentRefresh = self.gitHubClient.isCacheValid ||
            (self.gitHubClient.hasConditionalHeaders && !self.notifications.isEmpty)

        if self.notifications.isEmpty {
            self.isLoading = true
        } else if !canSilentRefresh {
            self.isRefreshing = true
        }
        self.error = nil

        DiagnosticsLogger.info("Refreshing notifications (silent: \(canSilentRefresh))", category: .ui)

        do {
            // Use progressive fetch to update UI as pages arrive
            let finalNotifications = try await self.gitHubClient.fetchAllNotificationsProgressive { [weak self] batch in
                guard let self else { return }
                // Update UI immediately with each batch
                self.mergeNotifications(batch)
            }

            if let notifications = finalNotifications {
                // Final merge to ensure consistency
                self.mergeNotifications(notifications)

                // Save to cache in background
                Task.detached { [dataStore, notifications = self.notifications, repositories = self.repositories] in
                    try? await MainActor.run {
                        try dataStore.saveNotifications(notifications)
                        try dataStore.saveRepositories(repositories)
                    }
                }

                DiagnosticsLogger.info(
                    "Loaded \(self.notifications.count) notifications from \(self.repositories.count) repositories",
                    category: .ui)
            } else {
                // 304 Not Modified - data unchanged
                DiagnosticsLogger.info("Notifications unchanged, using cache", category: .ui)
            }

            // Prefetch avatars for new items
            await self.prefetchAvatars()
        } catch {
            self.error = error
            DiagnosticsLogger.error(error, context: "refresh", category: .ui)
        }

        self.isLoading = false
        self.isRefreshing = false
    }

    /// Forces a full refresh, ignoring conditional caching.
    func forceRefresh() async {
        self.isRefreshing = true
        self.error = nil

        do {
            let notifications = try await self.gitHubClient.fetchAllNotificationsForced()
            self.mergeNotifications(notifications)

            try self.dataStore.saveNotifications(self.notifications)
            try self.dataStore.saveRepositories(self.repositories)
        } catch {
            self.error = error
            DiagnosticsLogger.error(error, context: "forceRefresh", category: .ui)
        }

        self.isRefreshing = false
    }

    /// Marks a notification as read.
    func markAsRead(_ notification: GitHubNotification) async {
        DiagnosticsLogger.info("Marking notification \(notification.id) as read", category: .ui)

        // Find the notification index
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else {
            DiagnosticsLogger.warning("Notification \(notification.id) not found in list", category: .ui)
            return
        }

        // Optimistic update: Update local state immediately for responsive UI
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

        // Keep API client cache in sync
        self.gitHubClient.updateCachedNotification(updated)

        // Update persistence cache (this won't fail in a way that matters for UX)
        try? self.dataStore.markAsRead(notificationId: notification.id)

        // Now sync with the API in the background
        do {
            try await self.gitHubClient.markAsRead(threadId: notification.id)
            DiagnosticsLogger.info(
                "Successfully marked notification \(notification.id) as read on server",
                category: .ui)
        } catch {
            // API call failed, but we keep the local state updated for better UX
            // The next sync will reconcile if needed
            DiagnosticsLogger.error(error, context: "markAsRead API call", category: .ui)

            // For unauthorized errors, we might want to revert, but for now keep optimistic
            // since the user intended to mark it as read
        }
    }

    /// Clears the current error.
    func clearError() {
        self.error = nil
    }

    // MARK: - Private Methods

    /// Updates the pre-computed grouped notifications.
    private func updateGroupedNotifications() {
        let filtered = self.filteredNotifications
        let grouped = Dictionary(grouping: filtered) { $0.repository.fullName }
        self.groupedNotifications = grouped.sorted { $0.key < $1.key }
    }

    /// Schedules a debounced search update.
    private func scheduleSearchUpdate() {
        self.searchDebounceTask?.cancel()

        self.searchDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.searchDebounceDelay ?? .milliseconds(300))
            } catch {
                return // Cancelled
            }

            guard let self, !Task.isCancelled else { return }
            self.debouncedSearchText = self.searchText
            self.updateGroupedNotifications()
        }
    }

    /// Merges fresh notifications with existing data efficiently.
    private func mergeNotifications(_ fresh: [GitHubNotification]) {
        // Build index of existing notifications for fast lookup
        var existingById: [String: GitHubNotification] = [:]
        for notification in self.notifications {
            existingById[notification.id] = notification
        }

        // Merge fresh data, preserving local "read" state
        var merged: [GitHubNotification] = []
        var seenIds: Set<String> = []

        for notification in fresh {
            // Check if we have a local version that was marked as read
            if let existing = existingById[notification.id],
               !existing.unread, notification.unread {
                // Local is read, API says unread - keep local "read" state
                // This handles the race condition where we marked as read locally
                // but the API hasn't caught up yet
                merged.append(existing)
            } else {
                merged.append(notification)
            }
            seenIds.insert(notification.id)
        }

        // Keep notifications that might still be relevant but weren't in this fetch
        // (e.g., read notifications when fetching unread only)
        for notification in self.notifications where !seenIds.contains(notification.id) {
            // Only keep if it's read (might have been marked read locally)
            if !notification.unread {
                merged.append(notification)
            }
        }

        self.notifications = merged
        self.repositories = self.extractRepositories(from: merged)
    }

    /// Extracts unique repositories from notifications.
    private func extractRepositories(from notifications: [GitHubNotification]) -> [Repository] {
        Array(Set(notifications.map(\.repository)))
            .sorted { $0.fullName < $1.fullName }
    }

    /// Prefetches avatar images for visible notifications.
    private func prefetchAvatars() async {
        let avatarUrls = Array(Set(notifications.prefix(50).map(\.repository.owner.avatarUrl)))
        await ImageCache.shared.prefetch(avatarUrls)
    }

    /// Converts a cached notification back to GitHubNotification.
    private func convertCachedNotification(_ cached: CachedNotification) -> GitHubNotification? {
        // Reconstruct Repository
        let owner = RepositoryOwner(
            login: cached.repositoryFullName.components(separatedBy: "/").first ?? "",
            id: 0,
            nodeId: "",
            avatarUrl: cached.ownerAvatarUrl,
            url: "",
            htmlUrl: "",
            type: "User")

        let repository = Repository(
            id: cached.repositoryId,
            nodeId: "",
            name: cached.repositoryName,
            fullName: cached.repositoryFullName,
            owner: owner,
            isPrivate: false,
            htmlUrl: "",
            description: nil,
            fork: false,
            url: "")

        // Reconstruct Subject
        let subject = NotificationSubject(
            title: cached.title,
            url: cached.subjectUrl,
            latestCommentUrl: nil,
            type: cached.notificationSubjectType)

        return GitHubNotification(
            id: cached.id,
            repository: repository,
            subject: subject,
            reason: cached.notificationReason,
            unread: cached.unread,
            updatedAt: cached.updatedAt,
            lastReadAt: cached.lastReadAt,
            url: cached.url,
            subscriptionUrl: "")
    }
}
