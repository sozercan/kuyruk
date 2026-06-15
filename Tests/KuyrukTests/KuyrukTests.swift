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
            updatedAt: Date(),
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
