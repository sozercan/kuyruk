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

    /// Currently selected top-level destination
    var appDestination: AppDestination = .notifications

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

    /// Number of pull requests that still need digest analyses.
    private(set) var digestPendingPRAnalysisCount: Int = 0

    /// Number of pull requests evaluated during the current digest-prep pass.
    private(set) var digestEvaluatedPRCount: Int = 0

    /// Monotonic revision used to refresh digest snapshots after cache mutations.
    private(set) var digestAnalysisRevision: Int = 0

    /// Whether digest analyses are currently being prepared.
    private(set) var isPreparingDigest: Bool = false

    /// Search text (debounced)
    var searchText: String = "" {
        didSet {
            self.scheduleSearchUpdate()
        }
    }

    /// Debounced search text (actually applied to filtering)
    private var debouncedSearchText: String = ""

    private let gitHubClient: any GitHubClienting
    private let dataStore: DataStore
    private let syncService: SyncService

    /// Debounce timer for search
    private var searchDebounceTask: Task<Void, Never>?

    /// Guards against stale digest-preparation work updating observable state.
    private var digestPreparationRunID = UUID()

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

    init(gitHubClient: any GitHubClienting, dataStore: DataStore, syncService: SyncService) {
        self.gitHubClient = gitHubClient
        self.dataStore = dataStore
        self.syncService = syncService
    }

    // MARK: - Public Methods

    /// Shows the notifications shell while preserving the current filter.
    func showNotifications() {
        self.appDestination = .notifications
    }

    /// Shows the digest shell.
    func showDigest() {
        self.appDestination = .digest
    }

    /// Shows a specific notification, returning to the notifications shell as needed.
    func showNotification(_ notification: GitHubNotification) {
        self.showNotifications()
        self.resetSearchImmediately()

        if !self.selectedFilter.matches(notification) {
            self.selectedFilter = .repository(notification.repository)
        }

        self.selectedNotification = notification
    }

    /// Selects a notification filter and returns to the notifications shell.
    func selectFilter(_ filter: NotificationFilter) {
        self.showNotifications()
        self.selectedFilter = filter
    }

    /// Selects a repository filter and returns to the notifications shell.
    func selectRepository(_ repository: Repository) {
        self.selectFilter(.repository(repository))
    }

    /// Loads notifications from cache on startup, then refreshes in background.
    func loadFromCache() async {
        DiagnosticsLogger.info("Loading notifications from cache", category: .ui)

        self.pruneStaleCaches()

        do {
            let cached = try self.dataStore.fetchCachedNotifications()

            if !cached.isEmpty {
                // Convert cached notifications to GitHubNotification
                self.notifications = cached.compactMap { self.convertCachedNotification($0) }
                self.repositories = self.extractRepositories(from: self.notifications)

                // Log read/unread counts for debugging
                let readCount = self.notifications.count(where: { !$0.unread })
                let unreadCount = self.notifications.filter(\.unread).count
                DiagnosticsLogger.info(
                    """
                    Loaded \(self.notifications.count) notifications from cache \
                    (\(readCount) read, \(unreadCount) unread)
                    """,
                    category: .ui)

                // Prefetch avatars for visible items
                await self.prefetchAvatars()

                // Refresh in background WITHOUT blocking - stale-while-revalidate pattern
                self.refreshInBackground()
            } else {
                // No cache - must wait for network
                DiagnosticsLogger.info("No cached notifications, fetching from network", category: .ui)
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
            var receivedProgressiveBatch = false

            // Use progressive fetch to update UI as pages arrive
            let finalNotifications = try await self.gitHubClient.fetchAllNotificationsProgressive(
                all: false,
                participating: false) { [weak self] batch in
                    guard let self else { return }
                    receivedProgressiveBatch = true
                    // Update UI immediately with each batch
                    self.mergeNotifications(batch)
                }

            if let notifications = finalNotifications {
                // Final merge to ensure consistency
                self.mergeNotifications(notifications)
                let currentNotificationIds = Set(notifications.map(\.id))
                let notificationsToPersist = self.notifications
                let repositoriesToPersist = self.repositories

                // Save to cache in background
                Task.detached { [dataStore, currentNotificationIds, notificationsToPersist, repositoriesToPersist] in
                    try? await MainActor.run {
                        try dataStore.markDeletedNotifications(currentIds: currentNotificationIds)
                        try dataStore.saveNotifications(notificationsToPersist)
                        try dataStore.saveRepositories(repositoriesToPersist)
                    }
                }

                DiagnosticsLogger.info(
                    "Loaded \(self.notifications.count) notifications from \(self.repositories.count) repositories",
                    category: .ui)
            } else {
                // 304 Not Modified - data unchanged
                DiagnosticsLogger.info("Notifications unchanged, using cache", category: .ui)

                if self.notifications.isEmpty,
                   !receivedProgressiveBatch,
                   self.gitHubClient.hasConditionalHeaders,
                   self.gitHubClient.cachedNotificationCount != 0 {
                    DiagnosticsLogger.warning(
                        "Received 304 with an empty UI cache; forcing notification refresh",
                        category: .ui)
                    let notifications = try await self.gitHubClient.fetchAllNotificationsForced(
                        all: false,
                        participating: false)
                    self.mergeNotifications(notifications)
                    try self.dataStore.markDeletedNotifications(currentIds: Set(notifications.map(\.id)))
                    try self.dataStore.saveNotifications(self.notifications)
                    try self.dataStore.saveRepositories(self.repositories)
                }
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
            let notifications = try await self.gitHubClient.fetchAllNotificationsForced(
                all: false,
                participating: false)
            self.mergeNotifications(notifications)
            let currentNotificationIds = Set(notifications.map(\.id))

            try self.dataStore.markDeletedNotifications(currentIds: currentNotificationIds)
            try self.dataStore.saveNotifications(self.notifications)
            try self.dataStore.saveRepositories(self.repositories)
        } catch {
            self.error = error
            DiagnosticsLogger.error(error, context: "forceRefresh", category: .ui)
        }

        self.isRefreshing = false
    }

    /// Marks a notification as read.
    /// Uses optimistic update with rollback on failure for critical errors.
    func markAsRead(_ notification: GitHubNotification) async {
        DiagnosticsLogger.info("Marking notification \(notification.id) as read", category: .ui)

        // Find the notification index
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else {
            DiagnosticsLogger.warning("Notification \(notification.id) not found in list", category: .ui)
            return
        }

        // Store original state for potential rollback
        let originalNotification = notification
        let wasSelected = self.selectedNotification?.id == notification.id

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
        if wasSelected {
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
        } catch let error as GitHubError {
            // Rollback on critical errors (unauthorized, not found)
            switch error {
            case .unauthorized,
                 .notFound:
                DiagnosticsLogger.warning(
                    "Rolling back markAsRead due to critical error: \(error)",
                    category: .ui)
                self.rollbackMarkAsRead(
                    originalNotification: originalNotification,
                    atIndex: index,
                    wasSelected: wasSelected)
                self.error = error

            case .rateLimited,
                 .networkError,
                 .serverError:
                // Keep optimistic update for transient errors
                // These will be reconciled on next sync
                DiagnosticsLogger.warning(
                    "Keeping optimistic update despite transient error: \(error)",
                    category: .ui)

            default:
                DiagnosticsLogger.error(error, context: "markAsRead API call", category: .ui)
            }
        } catch {
            // For unknown errors, log but keep optimistic update
            DiagnosticsLogger.error(error, context: "markAsRead API call", category: .ui)
        }
    }

    /// Rolls back an optimistic markAsRead update.
    private func rollbackMarkAsRead(
        originalNotification: GitHubNotification,
        atIndex index: Int,
        wasSelected: Bool) {
        // Verify index is still valid
        guard index < self.notifications.count,
              self.notifications[index].id == originalNotification.id
        else {
            DiagnosticsLogger.warning(
                "Cannot rollback: notification moved or removed",
                category: .ui)
            return
        }

        // Restore original state
        self.notifications[index] = originalNotification

        if wasSelected {
            self.selectedNotification = originalNotification
        }

        // Restore in API client cache
        self.gitHubClient.updateCachedNotification(originalNotification)

        // Restore in persistence cache
        try? self.dataStore.markAsUnread(notificationId: originalNotification.id)

        DiagnosticsLogger.info(
            "Rolled back markAsRead for notification \(originalNotification.id)",
            category: .ui)
    }

    /// Clears the current error.
    func clearError() {
        self.error = nil
    }

    // MARK: - Snooze Operations

    /// Snoozes a notification until the specified date.
    func snoozeNotification(_ notification: GitHubNotification, until date: Date) {
        DiagnosticsLogger.info("Snoozing notification \(notification.id) until \(date)", category: .ui)

        do {
            try self.dataStore.snoozeNotification(id: notification.id, until: date)
            // Trigger UI update
            self.updateGroupedNotifications()
        } catch {
            DiagnosticsLogger.error(error, context: "snoozeNotification", category: .ui)
            self.error = error
        }
    }

    /// Unsnoozes a notification.
    func unsnoozeNotification(_ notification: GitHubNotification) {
        DiagnosticsLogger.info("Unsnoozing notification \(notification.id)", category: .ui)

        do {
            try self.dataStore.unsnoozeNotification(id: notification.id)
            // Trigger UI update
            self.updateGroupedNotifications()
        } catch {
            DiagnosticsLogger.error(error, context: "unsnoozeNotification", category: .ui)
            self.error = error
        }
    }

    /// Gets the count of snoozed notifications.
    var snoozedCount: Int {
        (try? self.dataStore.snoozedCount()) ?? 0
    }

    /// Checks for expired snoozes and unsnoozes them.
    /// Call this periodically (e.g., every minute) to wake up snoozed notifications.
    func checkExpiredSnoozes() {
        do {
            let count = try self.dataStore.unsnoozeExpiredNotifications()
            if count > 0 {
                self.updateGroupedNotifications()
            }
        } catch {
            DiagnosticsLogger.error(error, context: "checkExpiredSnoozes", category: .ui)
        }
    }

    // MARK: - AI Summary Cache

    /// Fetch cached summary for a notification.
    /// - Parameter notification: The notification to fetch the summary for.
    /// - Returns: The cached summary if available, nil otherwise.
    func cachedSummary(for notification: GitHubNotification) -> CachedSummary? {
        try? self.dataStore.fetchSummary(for: notification.id)
    }

    /// Fetch the cached pull request resolution state for a notification.
    /// - Parameter notification: The notification to look up.
    /// - Returns: The cached pull request state if available, nil otherwise.
    func cachedPullRequestState(for notification: GitHubNotification) -> CachedPullRequestState? {
        try? self.dataStore.fetchPullRequestState(for: notification.id)
    }

    /// Invalidate all cached summaries (e.g., when clearing cache).
    /// This removes all cached AI-generated summaries from the store.
    func invalidateSummaryCache() {
        try? self.dataStore.cleanupOldSummaries(olderThan: 0)
    }

    /// Removes aged cache entries to bound local storage growth. Runs once at startup.
    private func pruneStaleCaches() {
        try? self.dataStore.cleanupOldSummaries()
        try? self.dataStore.cleanupOldPullRequestStates()
        try? self.dataStore.cleanupOldNotifications()
    }

    /// Prepares digest state for pull request notifications.
    ///
    /// Pull request resolution state is refreshed independently from AI analysis
    /// generation so cached recommendations for merged/closed PRs can be filtered out.
    func prepareDigest(
        using modelsService: any DigestPreparingModelsService,
        allowsAnalysisGeneration: Bool = true) async {
        let runID = UUID()
        self.digestPreparationRunID = runID

        let pullRequestNotifications = self.pullRequestNotificationsForDigest()
        self.digestEvaluatedPRCount = 0

        let canGenerateSummaries = allowsAnalysisGeneration && modelsService.canGenerateSummaries
        self.digestPendingPRAnalysisCount = canGenerateSummaries
            ? pullRequestNotifications.count(where: { !self.hasCompleteDigestAnalyses(for: $0) })
            : 0
        self.isPreparingDigest = canGenerateSummaries && self.digestPendingPRAnalysisCount > 0

        guard !pullRequestNotifications.isEmpty else { return }

        if self.isPreparingDigest {
            DiagnosticsLogger.info(
                """
                Preparing digest analyses for \(pullRequestNotifications.count) pull requests \
                with model \(modelsService.selectedModelId ?? "unknown")
                """,
                category: .ui)
        }

        defer {
            if self.digestPreparationRunID == runID {
                self.isPreparingDigest = false
            }
        }

        do {
            for notification in pullRequestNotifications {
                try Task.checkCancellation()
                guard self.digestPreparationRunID == runID else { return }

                let missingTypes = canGenerateSummaries
                    ? self.missingDigestAnalysisTypes(for: notification)
                    : []

                // Resolve PR state first; skip AI evaluation for merged/closed PRs.
                let status = await self.ensurePullRequestState(for: notification)

                guard self.digestPreparationRunID == runID else { return }

                if status?.isResolved == true {
                    if !missingTypes.isEmpty {
                        self.digestPendingPRAnalysisCount = max(0, self.digestPendingPRAnalysisCount - 1)
                    }
                    self.digestEvaluatedPRCount += 1
                    continue
                }

                guard canGenerateSummaries else {
                    self.digestEvaluatedPRCount += 1
                    continue
                }

                var generatedAnalysis = false

                for type in missingTypes {
                    do {
                        _ = try await modelsService.generateAnalysis(for: notification, type: type)
                        generatedAnalysis = true
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        DiagnosticsLogger.error(
                            error,
                            context: "prepareDigest(\(type.rawValue)) \(notification.id)",
                            category: .ui)
                    }
                }

                guard self.digestPreparationRunID == runID else { return }

                if generatedAnalysis {
                    if self.hasCompleteDigestAnalyses(for: notification) {
                        self.digestPendingPRAnalysisCount = max(0, self.digestPendingPRAnalysisCount - 1)
                    }
                    self.digestAnalysisRevision += 1
                }

                self.digestEvaluatedPRCount += 1
            }
        } catch is CancellationError {
            DiagnosticsLogger.debug("Digest preparation cancelled", category: .ui)
        } catch {
            DiagnosticsLogger.error(error, context: "prepareDigest", category: .ui)
        }
    }

    // MARK: - Private Methods

    private func resetDigestPreparationState() {
        self.digestPendingPRAnalysisCount = 0
        self.digestEvaluatedPRCount = 0
        self.isPreparingDigest = false
    }

    private func pullRequestNotificationsForDigest() -> [GitHubNotification] {
        self.notifications.filter { $0.subject.type == .pullRequest }
    }

    /// Returns the pull request's resolution status, using a valid cached value when
    /// available and otherwise fetching and caching it.
    ///
    /// Fails open: any error (or a non-pull-request notification) returns `nil`, so the
    /// caller treats the PR as unresolved and current behavior is preserved.
    private func ensurePullRequestState(for notification: GitHubNotification) async -> PullRequestStatus? {
        guard notification.subject.type == .pullRequest else { return nil }

        if let cached = self.cachedPullRequestState(for: notification),
           cached.isValid(for: notification) {
            return cached.status
        }

        guard let number = notification.subjectNumber else { return nil }
        let owner = notification.repository.owner.login
        let repo = notification.repository.name

        guard !owner.isEmpty, !repo.isEmpty else { return nil }

        do {
            let response = try await self.gitHubClient.fetchPullRequestState(
                owner: owner,
                repo: repo,
                number: number)
            let status = response.status

            try self.dataStore.savePullRequestState(
                status,
                isDraft: response.isDraft,
                for: notification)
            self.digestAnalysisRevision += 1
            return status
        } catch {
            DiagnosticsLogger.error(
                error,
                context: "ensurePullRequestState \(notification.id)",
                category: .ui)
            return nil
        }
    }

    private func missingDigestAnalysisTypes(for notification: GitHubNotification) -> [AnalysisType] {
        guard notification.subject.type == .pullRequest else { return [] }

        guard let cached = self.cachedSummary(for: notification),
              cached.isValid(for: notification) else {
            return [.priority, .action]
        }

        var missingTypes: [AnalysisType] = []
        if !cached.hasAnalysis(for: .priority) {
            missingTypes.append(.priority)
        }
        if !cached.hasAnalysis(for: .action) {
            missingTypes.append(.action)
        }
        return missingTypes
    }

    private func hasCompleteDigestAnalyses(for notification: GitHubNotification) -> Bool {
        guard let cached = self.cachedSummary(for: notification),
              cached.isValid(for: notification) else {
            return false
        }

        return cached.hasAnalysis(for: .priority) && cached.hasAnalysis(for: .action)
    }

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

    /// Clears the current search state without waiting for the debounce timer.
    private func resetSearchImmediately() {
        guard !self.searchText.isEmpty || !self.debouncedSearchText.isEmpty else { return }

        self.searchDebounceTask?.cancel()
        self.searchDebounceTask = nil

        // Clear the visible field, then immediately cancel the debounce task created by didSet.
        self.searchText = ""
        self.searchDebounceTask?.cancel()
        self.searchDebounceTask = nil

        self.debouncedSearchText = ""
        self.updateGroupedNotifications()
    }

    /// Merges fresh notifications with existing data efficiently.
    private func mergeNotifications(_ fresh: [GitHubNotification]) {
        DiagnosticsLogger.debug(
            "Merging \(fresh.count) fresh notifications with \(self.notifications.count) existing",
            category: .ui)

        let merged = Self.mergedNotifications(existing: self.notifications, fresh: fresh)

        DiagnosticsLogger.debug(
            "Merge result: \(merged.count) total notifications",
            category: .ui)

        self.notifications = merged
        self.repositories = self.extractRepositories(from: merged)
        self.selectedNotification = self.selectedNotification.flatMap { selected in
            merged.first(where: { $0.id == selected.id })
        }
    }

    /// Merges notifications while preserving optimistic local read state only for
    /// threads that are still returned by the API.
    nonisolated static func mergedNotifications(
        existing: [GitHubNotification],
        fresh: [GitHubNotification]) -> [GitHubNotification] {
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        return fresh.map { notification in
            if let existing = existingById[notification.id],
               !existing.unread, notification.unread {
                return existing
            }

            return notification
        }
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
