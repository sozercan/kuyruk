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

@Suite("Notification Filter Tests")
struct KuyrukTests {
    @Test("Notification filter matches correctly")
    func notificationFilterMatches() {
        let notification = KuyrukTests.makeNotification(reason: .assign, unread: true)

        // Test filter matching
        #expect(NotificationFilter.inbox.matches(notification))
        #expect(NotificationFilter.unread.matches(notification))
        #expect(NotificationFilter.assigned.matches(notification))
        #expect(!NotificationFilter.mentioned.matches(notification))
        #expect(!NotificationFilter.reviewRequested.matches(notification))
    }

    @Test("Unread filter excludes read notifications")
    func unreadFilterExcludesRead() {
        let readNotification = KuyrukTests.makeNotification(unread: false)
        let unreadNotification = KuyrukTests.makeNotification(unread: true)

        #expect(!NotificationFilter.unread.matches(readNotification))
        #expect(NotificationFilter.unread.matches(unreadNotification))
    }

    @Test("Inbox filter matches only unread notifications (like GitHub default)")
    func inboxFilterMatchesUnread() {
        let readNotification = KuyrukTests.makeNotification(unread: false)
        let unreadNotification = KuyrukTests.makeNotification(unread: true)

        // Inbox shows only unread notifications, matching GitHub's default view
        #expect(!NotificationFilter.inbox.matches(readNotification))
        #expect(NotificationFilter.inbox.matches(unreadNotification))
    }

    @Test("Mention filter matches mention reason")
    func mentionFilterMatchesMentions() {
        let mentionNotification = KuyrukTests.makeNotification(reason: .mention)
        let assignNotification = KuyrukTests.makeNotification(reason: .assign)
        let teamMentionNotification = KuyrukTests.makeNotification(reason: .teamMention)

        #expect(NotificationFilter.mentioned.matches(mentionNotification))
        #expect(NotificationFilter.mentioned.matches(teamMentionNotification))
        #expect(!NotificationFilter.mentioned.matches(assignNotification))
    }

    @Test("Review requested filter matches review_requested reason")
    func reviewRequestedFilterMatches() {
        let reviewNotification = KuyrukTests.makeNotification(reason: .reviewRequested)
        let assignNotification = KuyrukTests.makeNotification(reason: .assign)

        #expect(NotificationFilter.reviewRequested.matches(reviewNotification))
        #expect(!NotificationFilter.reviewRequested.matches(assignNotification))
    }
}

// MARK: - Notification Reason Tests

@Suite("Notification Reason Tests")
struct NotificationReasonTests {
    @Test("Notification reason has correct display name")
    func notificationReasonDisplayName() {
        #expect(NotificationReason.assign.displayName == "Assigned")
        #expect(NotificationReason.reviewRequested.displayName == "Review Requested")
        #expect(NotificationReason.mention.displayName == "Mentioned")
        #expect(NotificationReason.author.displayName == "Author")
        #expect(NotificationReason.ciActivity.displayName == "CI Activity")
        #expect(NotificationReason.teamMention.displayName == "Team Mention")
    }

    @Test("Notification reason has correct icon")
    func notificationReasonIcon() {
        #expect(NotificationReason.assign.iconName == "person.badge.plus")
        #expect(NotificationReason.mention.iconName == "at")
        #expect(NotificationReason.reviewRequested.iconName == "eye")
    }

    @Test("Known notification reasons are decodable")
    func knownReasonsDecodable() throws {
        let reasons = [
            ("assign", NotificationReason.assign),
            ("author", NotificationReason.author),
            ("comment", NotificationReason.comment),
            ("ci_activity", NotificationReason.ciActivity),
            ("mention", NotificationReason.mention),
            ("review_requested", NotificationReason.reviewRequested),
            ("team_mention", NotificationReason.teamMention),
        ]

        for (jsonValue, expected) in reasons {
            let json = "\"\(jsonValue)\""
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(NotificationReason.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test("Unknown reasons decode to unknown case")
    func unknownReasonsDecodesToUnknown() throws {
        let json = "\"some_new_reason\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NotificationReason.self, from: data)
        #expect(decoded == .unknown)
    }
}

// MARK: - Subject Type Tests

@Suite("Subject Type Tests")
struct SubjectTypeTests {
    @Test("Subject type has correct icon")
    func subjectTypeIcon() {
        #expect(SubjectType.issue.iconName == "circle.dotted")
        #expect(SubjectType.pullRequest.iconName == "arrow.triangle.merge")
        #expect(SubjectType.release.iconName == "tag")
        #expect(SubjectType.discussion.iconName == "bubble.left.and.bubble.right")
    }

    @Test("Subject type decodes from API values")
    func subjectTypeDecoding() throws {
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
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(SubjectType.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test("Subject type display name is correct")
    func subjectTypeDisplayName() {
        #expect(SubjectType.issue.displayName == "Issue")
        #expect(SubjectType.pullRequest.displayName == "Pull Request")
        #expect(SubjectType.release.displayName == "Release")
    }
}

// MARK: - Repository Tests

@Suite("Repository Tests")
struct RepositoryTests {
    @Test("Repository fullName is correct")
    func repositoryFullName() {
        let repo = KuyrukTests.makeRepository(name: "my-app", owner: "acme")
        #expect(repo.fullName == "acme/my-app")
    }

    @Test("Repository is Hashable")
    func repositoryHashable() {
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

@Suite("GitHubNotification Tests")
struct GitHubNotificationTests {
    @Test("Notification webUrl is constructed correctly for issues")
    func notificationWebUrlIssue() {
        let notification = KuyrukTests.makeNotification(type: .issue)
        let expectedUrl = "https://github.com/owner/test-repo/issues/1"
        #expect(notification.webUrl?.absoluteString == expectedUrl)
    }

    @Test("Notification webUrl is constructed correctly for PRs")
    func notificationWebUrlPR() {
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

    @Test("Notification is Identifiable")
    func notificationIdentifiable() {
        let notification = KuyrukTests.makeNotification(id: "unique-123")
        #expect(notification.id == "unique-123")
    }

    @Test("Notifications with same ID are identifiable")
    func notificationIdentifiableByID() {
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

@Suite("Auth State Tests")
struct AuthStateTests {
    @Test("Auth state isAuthenticated is correct")
    func authStateIsAuthenticated() {
        #expect(!AuthState.unknown.isAuthenticated)
        #expect(!AuthState.unauthenticated.isAuthenticated)
        #expect(!AuthState.requestingDeviceCode.isAuthenticated)
        #expect(AuthState.authenticated("test-token").isAuthenticated)
        #expect(!AuthState.error("Some error").isAuthenticated)
    }

    @Test("Auth state accessToken returns token when authenticated")
    func authStateAccessToken() {
        let authenticatedState = AuthState.authenticated("my-token")
        #expect(authenticatedState.accessToken == "my-token")

        let unauthenticatedState = AuthState.unauthenticated
        #expect(unauthenticatedState.accessToken == nil)

        let errorState = AuthState.error("Some error")
        #expect(errorState.accessToken == nil)
    }

    @Test("Auth state is Equatable")
    func authStateEquatable() {
        #expect(AuthState.unknown == AuthState.unknown)
        #expect(AuthState.authenticated("a") == AuthState.authenticated("a"))
        #expect(AuthState.authenticated("a") != AuthState.authenticated("b"))
        #expect(AuthState.error("err") == AuthState.error("err"))
    }
}

// MARK: - Keychain Error Tests

@Suite("Keychain Error Tests")
struct KeychainErrorTests {
    @Test("Keychain error has correct error descriptions")
    func keychainErrorDescriptions() {
        let errors: [KeychainError] = [
            .encodingFailed,
            .decodingFailed,
            .saveFailed(0),
            .retrieveFailed(0),
            .deleteFailed(0),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Keychain save error includes status code")
    func keychainSaveErrorIncludesStatus() {
        let error = KeychainError.saveFailed(-25300)
        #expect(error.errorDescription?.contains("-25300") == true)
    }
}
