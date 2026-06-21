import Foundation
import Testing
@testable import Kuyruk

// MARK: - Test Helpers

extension KuyrukTests {
    static func makeRepository(
        id: Int = 1,
        name: String = "test-repo",
        owner: String = "owner") -> Repository {
        Repository(
            id: id,
            nodeId: "test-\(id)",
            name: name,
            fullName: "\(owner)/\(name)",
            owner: RepositoryOwner(
                login: owner,
                id: 1,
                nodeId: "owner-node",
                avatarUrl: "https://example.com/avatar.png",
                url: "https://api.github.com/users/\(owner)",
                htmlUrl: "https://github.com/\(owner)",
                type: "User"),
            isPrivate: false,
            htmlUrl: "https://github.com/\(owner)/\(name)",
            description: "Test repository",
            fork: false,
            url: "https://api.github.com/repos/\(owner)/\(name)")
    }

    static func makeNotification(
        id: String = "123",
        reason: NotificationReason = .assign,
        unread: Bool = true,
        type: SubjectType = .issue,
        updatedAt: Date = Date(),
        repository: Repository? = nil) -> GitHubNotification {
        let repo = repository ?? self.makeRepository()
        let subject = NotificationSubject(
            title: "Test Subject",
            url: "https://api.github.com/repos/owner/test-repo/issues/1",
            latestCommentUrl: nil,
            type: type)

        return GitHubNotification(
            id: id,
            repository: repo,
            subject: subject,
            reason: reason,
            unread: unread,
            updatedAt: updatedAt,
            lastReadAt: nil,
            url: "https://api.github.com/notifications/threads/\(id)",
            subscriptionUrl: "https://api.github.com/notifications/threads/\(id)/subscription")
    }
}

// MARK: - Notification Filter Tests

struct KuyrukTests {
    @Test
    func `Notification filter matches correctly`() {
        let notification = KuyrukTests.makeNotification(reason: .assign, unread: true)

        // Test filter matching
        #expect(NotificationFilter.inbox.matches(notification))
        #expect(NotificationFilter.unread.matches(notification))
        #expect(NotificationFilter.assigned.matches(notification))
        #expect(!NotificationFilter.mentioned.matches(notification))
        #expect(!NotificationFilter.reviewRequested.matches(notification))
    }

    @Test
    func `Unread filter excludes read notifications`() {
        let readNotification = KuyrukTests.makeNotification(unread: false)
        let unreadNotification = KuyrukTests.makeNotification(unread: true)

        #expect(!NotificationFilter.unread.matches(readNotification))
        #expect(NotificationFilter.unread.matches(unreadNotification))
    }

    @Test
    func `Inbox filter matches only unread notifications (like GitHub default)`() {
        let readNotification = KuyrukTests.makeNotification(unread: false)
        let unreadNotification = KuyrukTests.makeNotification(unread: true)

        // Inbox shows only unread notifications, matching GitHub's default view
        #expect(!NotificationFilter.inbox.matches(readNotification))
        #expect(NotificationFilter.inbox.matches(unreadNotification))
    }

    @Test
    func `Mention filter matches mention reason`() {
        let mentionNotification = KuyrukTests.makeNotification(reason: .mention)
        let assignNotification = KuyrukTests.makeNotification(reason: .assign)
        let teamMentionNotification = KuyrukTests.makeNotification(reason: .teamMention)

        #expect(NotificationFilter.mentioned.matches(mentionNotification))
        #expect(NotificationFilter.mentioned.matches(teamMentionNotification))
        #expect(!NotificationFilter.mentioned.matches(assignNotification))
    }

    @Test
    func `Review requested filter matches review_requested reason`() {
        let reviewNotification = KuyrukTests.makeNotification(reason: .reviewRequested)
        let assignNotification = KuyrukTests.makeNotification(reason: .assign)

        #expect(NotificationFilter.reviewRequested.matches(reviewNotification))
        #expect(!NotificationFilter.reviewRequested.matches(assignNotification))
    }
}

// MARK: - Notification Reason Tests

struct NotificationReasonTests {
    @Test
    func `Notification reason has correct display name`() {
        #expect(NotificationReason.assign.displayName == "Assigned")
        #expect(NotificationReason.reviewRequested.displayName == "Review Requested")
        #expect(NotificationReason.mention.displayName == "Mentioned")
        #expect(NotificationReason.author.displayName == "Author")
        #expect(NotificationReason.ciActivity.displayName == "CI Activity")
        #expect(NotificationReason.securityAlert.displayName == "Security Alert")
        #expect(NotificationReason.teamMention.displayName == "Team Mention")
    }

    @Test
    func `Notification reason has correct icon`() {
        #expect(NotificationReason.assign.iconName == "person.badge.plus")
        #expect(NotificationReason.mention.iconName == "at")
        #expect(NotificationReason.reviewRequested.iconName == "eye")
        #expect(NotificationReason.securityAlert.iconName == "shield.lefthalf.filled")
    }

    @Test
    func `Known notification reasons are decodable`() throws {
        let reasons = [
            ("assign", NotificationReason.assign),
            ("author", NotificationReason.author),
            ("comment", NotificationReason.comment),
            ("ci_activity", NotificationReason.ciActivity),
            ("mention", NotificationReason.mention),
            ("review_requested", NotificationReason.reviewRequested),
            ("security_alert", NotificationReason.securityAlert),
            ("team_mention", NotificationReason.teamMention),
        ]

        for (jsonValue, expected) in reasons {
            let json = "\"\(jsonValue)\""
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(NotificationReason.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test
    func `Unknown reasons decode to unknown case`() throws {
        let json = "\"some_new_reason\""
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(NotificationReason.self, from: data)
        #expect(decoded == .unknown)
    }
}

// MARK: - App Destination Tests

struct AppDestinationTests {
    @Test
    func `App destination has correct metadata`() {
        #expect(AppDestination.allCases == [.notifications, .digest])
        #expect(AppDestination.notifications.displayName == "Notifications")
        #expect(AppDestination.notifications.iconName == "tray")
        #expect(AppDestination.digest.displayName == "Digest")
        #expect(AppDestination.digest.iconName == "newspaper")
    }
}

// MARK: - Notifications ViewModel Navigation Tests

@Suite(.serialized)
@MainActor
struct NotificationsViewModelNavigationTests {
    @Test
    func `Selecting a filter returns to notifications destination`() throws {
        let viewModel = try self.makeViewModel()

        viewModel.showDigest()
        viewModel.selectFilter(.mentioned)

        #expect(viewModel.appDestination == .notifications)
        #expect(viewModel.selectedFilter == .mentioned)
    }

    @Test
    func `Showing notifications preserves the current filter`() throws {
        let viewModel = try self.makeViewModel()

        viewModel.selectFilter(.reviewRequested)
        viewModel.showDigest()
        viewModel.showNotifications()

        #expect(viewModel.appDestination == .notifications)
        #expect(viewModel.selectedFilter == .reviewRequested)
    }

    @Test
    func `Showing a notification returns to notifications destination`() throws {
        let viewModel = try self.makeViewModel()
        let notification = KuyrukTests.makeNotification(reason: .assign)

        viewModel.selectFilter(.assigned)
        viewModel.showDigest()
        viewModel.showNotification(notification)

        #expect(viewModel.appDestination == .notifications)
        #expect(viewModel.selectedFilter == .assigned)
        #expect(viewModel.selectedNotification?.id == notification.id)
    }

    @Test
    func `Showing a notification switches to its repository when the current filter does not match`() throws {
        let viewModel = try self.makeViewModel()
        let repository = KuyrukTests.makeRepository(id: 42, name: "digest", owner: "sozer")
        let notification = KuyrukTests.makeNotification(
            id: "digest-thread",
            reason: .assign,
            repository: repository)

        viewModel.selectFilter(.mentioned)
        viewModel.showDigest()
        viewModel.showNotification(notification)

        #expect(viewModel.appDestination == .notifications)
        #expect(viewModel.selectedFilter == .repository(repository))
        #expect(viewModel.selectedNotification?.id == notification.id)
    }

    @Test
    func `Selecting a repository returns to notifications destination`() throws {
        let viewModel = try self.makeViewModel()
        let repository = KuyrukTests.makeRepository(id: 88, name: "activity", owner: "sozer")

        viewModel.showDigest()
        viewModel.selectRepository(repository)

        #expect(viewModel.appDestination == .notifications)
        #expect(viewModel.selectedFilter == .repository(repository))
    }

    private func makeViewModel() throws -> NotificationsViewModel {
        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()
        let gitHubClient = GitHubClient(authService: authService)
        let syncService = SyncService(gitHubClient: gitHubClient, dataStore: dataStore)

        return NotificationsViewModel(
            gitHubClient: gitHubClient,
            dataStore: dataStore,
            syncService: syncService)
    }
}

// MARK: - Notifications ViewModel Merge Tests

struct NotificationsViewModelMergeTests {
    @Test
    func `Merge preserves local read state while thread is still returned by API`() {
        let localReadNotification = KuyrukTests.makeNotification(id: "thread-1", unread: false)
        let serverUnreadNotification = KuyrukTests.makeNotification(id: "thread-1", unread: true)

        let merged = NotificationsViewModel.mergedNotifications(
            existing: [localReadNotification],
            fresh: [serverUnreadNotification])

        #expect(merged.count == 1)
        #expect(merged.first?.id == localReadNotification.id)
        #expect(merged.first?.unread == false)
    }

    @Test
    func `Merge drops local read notifications that no longer exist in API results`() {
        let localReadNotification = KuyrukTests.makeNotification(id: "thread-1", unread: false)
        let currentUnreadNotification = KuyrukTests.makeNotification(id: "thread-2", unread: true)

        let merged = NotificationsViewModel.mergedNotifications(
            existing: [localReadNotification, currentUnreadNotification],
            fresh: [currentUnreadNotification])

        #expect(merged.count == 1)
        #expect(merged.first?.id == currentUnreadNotification.id)
    }
}

// MARK: - Notifications ViewModel Digest Tests

@Suite(.serialized)
@MainActor
struct NotificationsViewModelDigestTests {
    @Test
    func `Prepare digest refreshes pull request state even when analyses are cached`() async throws {
        let notification = KuyrukTests.makeNotification(
            id: "pr-cached",
            reason: .reviewRequested,
            type: .pullRequest)
        let dataStore = try DataStore(inMemory: true)
        try dataStore.updateAnalysis(
            for: notification.id,
            notificationUpdatedAt: notification.updatedAt,
            type: .priority,
            value: "High",
            priorityExplanation: "Needs review before release.",
            model: "test-model")
        try dataStore.updateAnalysis(
            for: notification.id,
            notificationUpdatedAt: notification.updatedAt,
            type: .action,
            value: "Review this pull request.",
            model: "test-model")

        let gitHubClient = MockDigestGitHubClient(notifications: [notification])
        gitHubClient.pullRequestResponse = PullRequestStateResponse(
            state: "closed",
            merged: true,
            draft: false)
        let viewModel = self.makeViewModel(gitHubClient: gitHubClient, dataStore: dataStore)
        await viewModel.forceRefresh()

        #expect(DigestSnapshot(viewModel: viewModel).recommendedActions.count == 1)

        let modelsService = MockDigestModelsService()
        await viewModel.prepareDigest(using: modelsService)

        #expect(gitHubClient.pullRequestFetches == [PullRequestFetch(owner: "owner", repo: "test-repo", number: 1)])
        #expect(modelsService.generatedTypes.isEmpty)
        #expect(try dataStore.fetchPullRequestState(for: notification.id)?.status == .merged)
        #expect(DigestSnapshot(viewModel: viewModel).recommendedActions.isEmpty)
    }

    @Test
    func `Digest snapshot hides cached AI recommendations when AI content is disabled`() async throws {
        let notification = KuyrukTests.makeNotification(
            id: "pr-cached-hidden",
            reason: .reviewRequested,
            type: .pullRequest)
        let dataStore = try DataStore(inMemory: true)
        try dataStore.updateAnalysis(
            for: notification.id,
            notificationUpdatedAt: notification.updatedAt,
            type: .priority,
            value: "High",
            priorityExplanation: "Needs review before release.",
            model: "test-model")
        try dataStore.updateAnalysis(
            for: notification.id,
            notificationUpdatedAt: notification.updatedAt,
            type: .action,
            value: "Review this pull request.",
            model: "test-model")

        let gitHubClient = MockDigestGitHubClient(notifications: [notification])
        let viewModel = self.makeViewModel(gitHubClient: gitHubClient, dataStore: dataStore)
        await viewModel.forceRefresh()

        #expect(DigestSnapshot(viewModel: viewModel).recommendationsReadyCount == 1)
        let disabledSnapshot = DigestSnapshot(
            viewModel: viewModel,
            allowsCachedAIContent: false)
        #expect(disabledSnapshot.summariesReadyCount == 0)
        #expect(disabledSnapshot.recommendationsReadyCount == 0)
        #expect(disabledSnapshot.recommendedActions.isEmpty)
    }

    @Test
    func `Prepare digest with AI disabled refreshes pull request state without generating analyses`() async throws {
        let notification = KuyrukTests.makeNotification(
            id: "pr-ai-disabled",
            reason: .reviewRequested,
            type: .pullRequest)
        let dataStore = try DataStore(inMemory: true)
        let gitHubClient = MockDigestGitHubClient(notifications: [notification])
        gitHubClient.pullRequestResponse = PullRequestStateResponse(
            state: "closed",
            merged: true,
            draft: false)
        let viewModel = self.makeViewModel(gitHubClient: gitHubClient, dataStore: dataStore)
        await viewModel.forceRefresh()

        let modelsService = MockDigestModelsService()
        await viewModel.prepareDigest(
            using: modelsService,
            allowsAnalysisGeneration: false)

        #expect(gitHubClient.pullRequestFetches == [PullRequestFetch(owner: "owner", repo: "test-repo", number: 1)])
        #expect(modelsService.generatedTypes.isEmpty)
        #expect(viewModel.digestPendingPRAnalysisCount == 0)
        #expect(try dataStore.fetchPullRequestState(for: notification.id)?.status == .merged)
    }

    private func makeViewModel(
        gitHubClient: MockDigestGitHubClient,
        dataStore: DataStore) -> NotificationsViewModel {
        let authService = AuthService()
        let realGitHubClient = GitHubClient(authService: authService, enablePinning: false)
        let syncService = SyncService(gitHubClient: realGitHubClient, dataStore: dataStore)

        return NotificationsViewModel(
            gitHubClient: gitHubClient,
            dataStore: dataStore,
            syncService: syncService)
    }
}

private struct PullRequestFetch: Equatable {
    let owner: String
    let repo: String
    let number: Int
}

@MainActor
private final class MockDigestGitHubClient: GitHubClienting {
    var isCacheValid = false
    var hasConditionalHeaders = false
    var notifications: [GitHubNotification]
    var pullRequestResponse = PullRequestStateResponse(state: "open", merged: false, draft: false)
    private(set) var pullRequestFetches: [PullRequestFetch] = []

    init(notifications: [GitHubNotification]) {
        self.notifications = notifications
    }

    func fetchAllNotificationsProgressive(
        all: Bool,
        participating: Bool,
        onBatchReceived: @escaping ([GitHubNotification]) -> Void) async throws -> [GitHubNotification]? {
        onBatchReceived(self.notifications)
        return self.notifications
    }

    func fetchAllNotificationsForced(
        all: Bool,
        participating: Bool) async throws -> [GitHubNotification] {
        self.notifications
    }

    func updateCachedNotification(_ notification: GitHubNotification) {}

    func markAsRead(threadId: String) async throws {}

    func fetchPullRequestState(
        owner: String,
        repo: String,
        number: Int) async throws -> PullRequestStateResponse {
        self.pullRequestFetches.append(PullRequestFetch(owner: owner, repo: repo, number: number))
        return self.pullRequestResponse
    }
}

@MainActor
private final class MockDigestModelsService: DigestPreparingModelsService {
    var canGenerateSummaries = true
    var selectedModelId: String? = "test-model"
    private(set) var generatedTypes: [AnalysisType] = []

    func generateAnalysis(for notification: GitHubNotification, type: AnalysisType) async throws -> String {
        self.generatedTypes.append(type)
        return "Generated \(type.rawValue)"
    }
}

// MARK: - Digest Snapshot Ranking Tests

@MainActor
struct DigestSnapshotRankingTests {
    @Test
    func `Ranking places action recommendations ahead of summary-only items`() {
        let withAction = Self.makeSummaryItem(id: "a", priorityScore: "low", actionRecommendation: "Review now")
        let summaryOnly = Self.makeSummaryItem(id: "b", priorityScore: "high", actionRecommendation: nil)

        // Action guidance wins even when the summary-only item has a higher priority score.
        #expect(DigestSnapshot.areRankedDescending(withAction, summaryOnly))
        #expect(!DigestSnapshot.areRankedDescending(summaryOnly, withAction))
    }

    @Test
    func `Ranking orders by priority when action flag is equal`() {
        let high = Self.makeSummaryItem(id: "a", priorityScore: "High", actionRecommendation: nil)
        let medium = Self.makeSummaryItem(id: "b", priorityScore: "medium", actionRecommendation: nil)
        let low = Self.makeSummaryItem(id: "c", priorityScore: "low", actionRecommendation: nil)
        let none = Self.makeSummaryItem(id: "d", priorityScore: nil, actionRecommendation: nil)

        let sorted = [none, low, high, medium].sorted(by: DigestSnapshot.areRankedDescending)

        #expect(sorted.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test
    func `Ranking falls back to recency then identifier`() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        let fresher = Self.makeSummaryItem(
            id: "z",
            priorityScore: "medium",
            actionRecommendation: nil,
            updatedAt: newer)
        let staler = Self.makeSummaryItem(
            id: "a",
            priorityScore: "medium",
            actionRecommendation: nil,
            updatedAt: older)

        // Fresher activity wins despite a higher identifier.
        #expect(DigestSnapshot.areRankedDescending(fresher, staler))

        let sameTimeA = Self.makeSummaryItem(
            id: "a",
            priorityScore: "medium",
            actionRecommendation: nil,
            updatedAt: newer)
        let sameTimeB = Self.makeSummaryItem(
            id: "b",
            priorityScore: "medium",
            actionRecommendation: nil,
            updatedAt: newer)

        // Tie on every other key falls back to the lower identifier.
        #expect(DigestSnapshot.areRankedDescending(sameTimeA, sameTimeB))
    }

    @Test
    func `Priority rank is case-insensitive and ordered`() {
        #expect(DigestSnapshot.priorityRank("High") == 3)
        #expect(DigestSnapshot.priorityRank("medium") == 2)
        #expect(DigestSnapshot.priorityRank("  low ") == 1)
        #expect(DigestSnapshot.priorityRank("not-a-score") == 0)
        #expect(DigestSnapshot.priorityRank(nil) == 0)
        #expect(DigestSnapshot.priorityRank("HIGH") > DigestSnapshot.priorityRank("LOW"))
    }

    @Test
    func `Repository activity orders by unread load first`() {
        let heavy = Self.makeActivity(
            repository: KuyrukTests.makeRepository(id: 1, name: "heavy"),
            unreadCount: 5,
            latestUpdatedAt: Date(timeIntervalSince1970: 1000))
        let light = Self.makeActivity(
            repository: KuyrukTests.makeRepository(id: 2, name: "light"),
            unreadCount: 1,
            latestUpdatedAt: Date(timeIntervalSince1970: 5000))

        let sorted = [light, heavy].sorted(by: DigestSnapshot.repositoryActivityOrder)

        // Higher unread load wins even though the lighter repo has fresher activity.
        #expect(sorted.map(\.repository.id) == [1, 2])
    }

    @Test
    func `Repository activity breaks unread ties by recency then name`() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        let fresher = Self.makeActivity(
            repository: KuyrukTests.makeRepository(id: 1, name: "zzz", owner: "octo"),
            unreadCount: 3,
            latestUpdatedAt: newer)
        let staler = Self.makeActivity(
            repository: KuyrukTests.makeRepository(id: 2, name: "aaa", owner: "octo"),
            unreadCount: 3,
            latestUpdatedAt: older)

        // Recency beats name when unread counts tie.
        #expect(DigestSnapshot.repositoryActivityOrder(fresher, staler))

        let aaa = Self.makeActivity(
            repository: KuyrukTests.makeRepository(id: 3, name: "aaa", owner: "octo"),
            unreadCount: 3,
            latestUpdatedAt: newer)
        let bbb = Self.makeActivity(
            repository: KuyrukTests.makeRepository(id: 4, name: "bbb", owner: "octo"),
            unreadCount: 3,
            latestUpdatedAt: newer)

        // Full tie on unread and recency falls back to ascending full name.
        #expect(DigestSnapshot.repositoryActivityOrder(aaa, bbb))
    }

    private static func makeSummaryItem(
        id: String,
        priorityScore: String?,
        actionRecommendation: String?,
        updatedAt: Date = Date(timeIntervalSince1970: 1000),
        isActionable: Bool? = nil) -> DigestSummaryItem {
        DigestSummaryItem(
            notification: KuyrukTests.makeNotification(id: id, type: .pullRequest, updatedAt: updatedAt),
            summaryText: "Summary for \(id)",
            priorityScore: priorityScore,
            priorityExplanation: nil,
            actionRecommendation: actionRecommendation,
            isActionable: isActionable ?? (actionRecommendation != nil))
    }

    private static func makeActivity(
        repository: Repository,
        unreadCount: Int,
        latestUpdatedAt: Date) -> DigestRepositoryActivity {
        DigestRepositoryActivity(
            repository: repository,
            unreadCount: unreadCount,
            totalCount: unreadCount,
            summaryCount: 0,
            latestNotification: KuyrukTests.makeNotification(id: "\(repository.id)", repository: repository),
            latestUpdatedAt: latestUpdatedAt)
    }
}

// MARK: - Digest Actionability Tests

@MainActor
struct DigestActionabilityTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Double) -> Date {
        self.now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    @Test
    func `Affirmative action verdict is actionable`() {
        #expect(DigestSnapshot.hasMeaningfulAction("Needs your review"))
        #expect(DigestSnapshot.hasMeaningfulAction("**Please respond** to the maintainer"))
        // Positive phrasing wins even when a negative token co-occurs.
        #expect(DigestSnapshot.hasMeaningfulAction("Needs your review; no rush"))
    }

    @Test
    func `FYI and no-action verdicts are not actionable`() {
        #expect(!DigestSnapshot.hasMeaningfulAction("**Just FYI, no action needed**"))
        #expect(!DigestSnapshot.hasMeaningfulAction("\"Just FYI, no action needed\""))
        #expect(!DigestSnapshot.hasMeaningfulAction("No immediate action needed."))
        #expect(!DigestSnapshot.hasMeaningfulAction("Nothing to do here."))
        #expect(!DigestSnapshot.hasMeaningfulAction("Waiting on others."))
        #expect(!DigestSnapshot.hasMeaningfulAction(nil))
    }

    @Test
    func `Unknown phrasing fails open as actionable`() {
        // No positive or negative signal -> kept, so a genuine ask is never hidden on phrasing alone.
        #expect(DigestSnapshot.hasMeaningfulAction("Triage the flaky integration test."))
    }

    @Test
    func `Release that is watched and FYI is not actionable`() {
        // The reported case: release + Watching + "Just FYI, no action needed", 5 months old.
        let actionable = DigestSnapshot.isActionable(
            actionRecommendation: "Just FYI, no action needed",
            subjectType: .release,
            reason: .subscribed,
            updatedAt: self.daysAgo(160),
            now: self.now)
        #expect(!actionable)
    }

    @Test
    func `Stale low-signal item is dropped even with an action verdict`() {
        let actionable = DigestSnapshot.isActionable(
            actionRecommendation: "Take a look",
            subjectType: .issue,
            reason: .comment,
            updatedAt: self.daysAgo(120),
            now: self.now)
        #expect(!actionable)
    }

    @Test
    func `Recent actionable item is kept`() {
        let actionable = DigestSnapshot.isActionable(
            actionRecommendation: "Needs your response",
            subjectType: .issue,
            reason: .comment,
            updatedAt: self.daysAgo(10),
            now: self.now)
        #expect(actionable)
    }

    @Test
    func `High-signal reasons bypass staleness`() {
        // A review request stays actionable even when old, so a real ask is never hidden by age.
        let oldReview = DigestSnapshot.isActionable(
            actionRecommendation: "Needs your review",
            subjectType: .pullRequest,
            reason: .reviewRequested,
            updatedAt: self.daysAgo(200),
            now: self.now)
        #expect(oldReview)
    }

    @Test
    func `High-signal reason still requires a meaningful action`() {
        // Bypassing staleness must not bypass an explicit no-action verdict.
        let fyiMention = DigestSnapshot.isActionable(
            actionRecommendation: "Just FYI, no action needed",
            subjectType: .issue,
            reason: .mention,
            updatedAt: self.daysAgo(5),
            now: self.now)
        #expect(!fyiMention)
    }

    @Test
    func `Recency boundary is inclusive at the window edge`() {
        #expect(DigestSnapshot.isRecentEnough(updatedAt: self.daysAgo(90), now: self.now))
        #expect(!DigestSnapshot.isRecentEnough(updatedAt: self.daysAgo(91), now: self.now))
    }
}

// MARK: - Subject Type Tests

struct SubjectTypeTests {
    @Test
    func `Subject type has correct icon`() {
        #expect(SubjectType.issue.iconName == "circle.dotted")
        #expect(SubjectType.pullRequest.iconName == "arrow.triangle.merge")
        #expect(SubjectType.release.iconName == "tag")
        #expect(SubjectType.discussion.iconName == "bubble.left.and.bubble.right")
    }

    @Test
    func `Subject type decodes from API values`() throws {
        let types = [
            ("Issue", SubjectType.issue),
            ("PullRequest", SubjectType.pullRequest),
            ("Release", SubjectType.release),
            ("Discussion", SubjectType.discussion),
            ("Commit", SubjectType.commit),
            ("CheckSuite", SubjectType.checkSuite),
        ]

        for (jsonValue, expected) in types {
            let json = "\"\(jsonValue)\""
            let data = try #require(json.data(using: .utf8))
            let decoded = try JSONDecoder().decode(SubjectType.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test
    func `Subject type display name is correct`() {
        #expect(SubjectType.issue.displayName == "Issue")
        #expect(SubjectType.pullRequest.displayName == "Pull Request")
        #expect(SubjectType.release.displayName == "Release")
    }
}

// MARK: - Repository Tests

struct RepositoryTests {
    @Test
    func `Repository fullName is correct`() {
        let repo = KuyrukTests.makeRepository(name: "my-app", owner: "acme")
        #expect(repo.fullName == "acme/my-app")
    }

    @Test
    func `Repository is Hashable`() {
        let repo1 = KuyrukTests.makeRepository(id: 1, name: "repo-a")
        let repo2 = KuyrukTests.makeRepository(id: 1, name: "repo-a")
        let repo3 = KuyrukTests.makeRepository(id: 2, name: "repo-b")

        #expect(repo1 == repo2)
        #expect(repo1 != repo3)

        var repos: Set<Repository> = []
        repos.insert(repo1)
        repos.insert(repo2)
        repos.insert(repo3)

        #expect(repos.count == 2)
    }
}

// MARK: - GitHubNotification Tests

struct GitHubNotificationTests {
    @Test
    func `Notification webUrl is constructed correctly for issues`() {
        let notification = KuyrukTests.makeNotification(type: .issue)
        let expectedUrl = "https://github.com/owner/test-repo/issues/1"
        #expect(notification.webUrl?.absoluteString == expectedUrl)
    }

    @Test
    func `Notification webUrl is constructed correctly for PRs`() {
        let repo = KuyrukTests.makeRepository()
        let subject = NotificationSubject(
            title: "Test PR",
            url: "https://api.github.com/repos/owner/test-repo/pulls/42",
            latestCommentUrl: nil,
            type: .pullRequest)

        let notification = GitHubNotification(
            id: "456",
            repository: repo,
            subject: subject,
            reason: .reviewRequested,
            unread: true,
            updatedAt: Date(),
            lastReadAt: nil,
            url: "https://api.github.com/notifications/threads/456",
            subscriptionUrl: "https://api.github.com/notifications/threads/456/subscription")

        let expectedUrl = "https://github.com/owner/test-repo/pull/42"
        #expect(notification.webUrl?.absoluteString == expectedUrl)
    }

    @Test
    func `Notification is Identifiable`() {
        let notification = KuyrukTests.makeNotification(id: "unique-123")
        #expect(notification.id == "unique-123")
    }

    @Test
    func `Notifications with same ID are identifiable`() {
        let notification1 = KuyrukTests.makeNotification(id: "same-id")
        let notification2 = KuyrukTests.makeNotification(id: "same-id")
        let notification3 = KuyrukTests.makeNotification(id: "different-id")

        // Same IDs
        #expect(notification1.id == notification2.id)

        // Different IDs
        #expect(notification1.id != notification3.id)
    }
}

// MARK: - Auth State Tests

struct AuthStateTests {
    @Test
    func `Auth state isAuthenticated is correct`() {
        #expect(!AuthState.unknown.isAuthenticated)
        #expect(!AuthState.unauthenticated.isAuthenticated)
        #expect(!AuthState.requestingDeviceCode.isAuthenticated)
        #expect(AuthState.authenticated("test-token").isAuthenticated)
        #expect(!AuthState.error("Some error").isAuthenticated)
    }

    @Test
    func `Auth state accessToken returns token when authenticated`() {
        let authenticatedState = AuthState.authenticated("my-token")
        #expect(authenticatedState.accessToken == "my-token")

        let unauthenticatedState = AuthState.unauthenticated
        #expect(unauthenticatedState.accessToken == nil)

        let errorState = AuthState.error("Some error")
        #expect(errorState.accessToken == nil)
    }

    @Test
    func `Auth state is Equatable`() {
        #expect(AuthState.unknown == AuthState.unknown)
        #expect(AuthState.authenticated("a") == AuthState.authenticated("a"))
        #expect(AuthState.authenticated("a") != AuthState.authenticated("b"))
        #expect(AuthState.error("err") == AuthState.error("err"))
    }
}

// MARK: - Keychain Error Tests

struct KeychainErrorTests {
    @Test
    func `Keychain error has correct error descriptions`() throws {
        let errors: [KeychainError] = [
            .encodingFailed,
            .decodingFailed,
            .saveFailed(0),
            .retrieveFailed(0),
            .deleteFailed(0),
        ]

        for error in errors {
            let description = try #require(error.errorDescription)
            #expect(!description.isEmpty)
        }
    }

    @Test
    func `Keychain save error includes status code`() {
        let error = KeychainError.saveFailed(-25300)
        #expect(error.errorDescription?.contains("-25300") == true)
    }
}
