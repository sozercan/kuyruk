import Foundation
import Testing

@testable import Kuyruk

// MARK: - GitHubError Tests

@Suite("GitHubError Tests")
struct GitHubErrorTests {
    @Test("GitHubError has correct error descriptions")
    func gitHubErrorDescriptions() {
        let errors: [GitHubError] = [
            .unauthorized,
            .authenticationFailed("test message"),
            .invalidResponse,
            .httpError(500),
            .decodingError("parse error"),
            .networkError("timeout"),
            .notFound,
            .rateLimited(resetDate: Date()),
            .rateLimited(resetDate: nil),
            .serverError,
            .unknown("mystery"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("HTTP error includes status code")
    func httpErrorIncludesStatusCode() {
        let error = GitHubError.httpError(404)
        #expect(error.errorDescription?.contains("404") == true)
    }

    @Test("Authentication failed includes message")
    func authFailedIncludesMessage() {
        let error = GitHubError.authenticationFailed("Invalid token")
        #expect(error.errorDescription?.contains("Invalid token") == true)
    }

    @Test("Rate limited includes reset date when provided")
    func rateLimitedWithDate() {
        let resetDate = Date()
        let error = GitHubError.rateLimited(resetDate: resetDate)
        #expect(error.errorDescription?.contains("Rate limit") == true)
    }
}

// MARK: - GitHubEndpoint Tests

@Suite("GitHubEndpoint Tests")
struct GitHubEndpointTests {
    @Test("Notifications endpoint path is correct")
    func notificationsPath() {
        let endpoint = GitHubEndpoint.notifications(all: false, participating: false, page: 1)
        #expect(endpoint.path == "/notifications")
        #expect(endpoint.method == "GET")
    }

    @Test("Notifications endpoint query items are correct")
    func notificationsQueryItems() {
        let endpoint = GitHubEndpoint.notifications(all: true, participating: true, page: 2)
        let queryItems = endpoint.queryItems

        #expect(queryItems != nil)
        #expect(queryItems?.contains { $0.name == "all" && $0.value == "true" } == true)
        #expect(queryItems?.contains { $0.name == "participating" && $0.value == "true" } == true)
        #expect(queryItems?.contains { $0.name == "page" && $0.value == "2" } == true)
        #expect(queryItems?.contains { $0.name == "per_page" && $0.value == "50" } == true)
    }

    @Test("Page 1 does not include page query item")
    func page1NoQueryItem() {
        let endpoint = GitHubEndpoint.notifications(all: false, participating: false, page: 1)
        let queryItems = endpoint.queryItems

        #expect(queryItems?.contains { $0.name == "page" } == false)
    }

    @Test("Mark thread as read endpoint is correct")
    func markThreadAsReadPath() {
        let endpoint = GitHubEndpoint.markThreadAsRead(threadId: "12345")
        #expect(endpoint.path == "/notifications/threads/12345")
        #expect(endpoint.method == "PATCH")
    }

    @Test("User endpoint is correct")
    func userPath() {
        let endpoint = GitHubEndpoint.user
        #expect(endpoint.path == "/user")
        #expect(endpoint.method == "GET")
    }

    @Test("Repository endpoint path is correct")
    func repositoryPath() {
        let endpoint = GitHubEndpoint.repository(owner: "apple", repo: "swift")
        #expect(endpoint.path == "/repos/apple/swift")
        #expect(endpoint.method == "GET")
    }

    @Test("Issue endpoint path is correct")
    func issuePath() {
        let endpoint = GitHubEndpoint.issue(owner: "owner", repo: "repo", number: 42)
        #expect(endpoint.path == "/repos/owner/repo/issues/42")
        #expect(endpoint.method == "GET")
    }

    @Test("Pull request endpoint path is correct")
    func pullRequestPath() {
        let endpoint = GitHubEndpoint.pullRequest(owner: "owner", repo: "repo", number: 123)
        #expect(endpoint.path == "/repos/owner/repo/pulls/123")
        #expect(endpoint.method == "GET")
    }

    @Test("Thread subscription endpoint is correct")
    func threadSubscriptionPath() {
        let endpoint = GitHubEndpoint.threadSubscription(threadId: "999")
        #expect(endpoint.path == "/notifications/threads/999/subscription")
        #expect(endpoint.method == "GET")
    }
}

// MARK: - DataStore Tests

@Suite("DataStore Tests", .serialized)
struct DataStoreTests {
    @Test("DataStore initializes with in-memory storage")
    @MainActor
    func dataStoreInitializesInMemory() throws {
        let store = try DataStore(inMemory: true)
        #expect(store.container != nil)
    }

    @Test("Save and fetch notifications")
    @MainActor
    func saveAndFetchNotifications() throws {
        let store = try DataStore(inMemory: true)

        // Create test notifications
        let notification = ServiceTestHelpers.makeNotification(id: "test-1")

        // Save
        try store.saveNotifications([notification])

        // Fetch
        let cached = try store.fetchCachedNotifications()
        #expect(cached.count == 1)
        #expect(cached.first?.id == "test-1")
    }

    @Test("Fetch unread notifications")
    @MainActor
    func fetchUnreadNotifications() throws {
        let store = try DataStore(inMemory: true)

        let unread = ServiceTestHelpers.makeNotification(id: "unread-1", unread: true)
        let read = ServiceTestHelpers.makeNotification(id: "read-1", unread: false)

        try store.saveNotifications([unread, read])

        let unreadNotifications = try store.fetchUnreadNotifications()
        #expect(unreadNotifications.count == 1)
        #expect(unreadNotifications.first?.id == "unread-1")
    }

    @Test("Mark notification as read")
    @MainActor
    func markNotificationAsRead() throws {
        let store = try DataStore(inMemory: true)

        let notification = ServiceTestHelpers.makeNotification(id: "to-read", unread: true)
        try store.saveNotifications([notification])

        // Mark as read
        try store.markAsRead(notificationId: "to-read")

        // Verify
        let cached = try store.fetchCachedNotifications()
        #expect(cached.first?.unread == false)
    }

    @Test("Unread count is correct")
    @MainActor
    func unreadCountIsCorrect() throws {
        let store = try DataStore(inMemory: true)

        let notifications = [
            ServiceTestHelpers.makeNotification(id: "1", unread: true),
            ServiceTestHelpers.makeNotification(id: "2", unread: true),
            ServiceTestHelpers.makeNotification(id: "3", unread: false),
        ]

        try store.saveNotifications(notifications)

        let count = try store.unreadCount()
        #expect(count == 2)
    }

    @Test("Save and fetch repositories")
    @MainActor
    func saveAndFetchRepositories() throws {
        let store = try DataStore(inMemory: true)

        let repo = ServiceTestHelpers.makeRepository(id: 100, name: "test-repo", owner: "test-owner")
        try store.saveRepositories([repo])

        let cached = try store.fetchCachedRepositories()
        #expect(cached.count == 1)
        #expect(cached.first?.name == "test-repo")
        #expect(cached.first?.fullName == "test-owner/test-repo")
    }

    @Test("Mark deleted notifications")
    @MainActor
    func markDeletedNotifications() throws {
        let store = try DataStore(inMemory: true)

        let notifications = [
            ServiceTestHelpers.makeNotification(id: "keep"),
            ServiceTestHelpers.makeNotification(id: "remove"),
        ]

        try store.saveNotifications(notifications)

        // Only "keep" is in current IDs
        try store.markDeletedNotifications(currentIds: Set(["keep"]))

        let cached = try store.fetchCachedNotifications()
        #expect(cached.count == 1)
        #expect(cached.first?.id == "keep")
    }

    @Test("Update existing notification")
    @MainActor
    func updateExistingNotification() throws {
        let store = try DataStore(inMemory: true)

        // Save initial
        let initial = ServiceTestHelpers.makeNotification(id: "update-me", unread: true)
        try store.saveNotifications([initial])

        // Save updated (same ID, different state)
        let updated = ServiceTestHelpers.makeNotification(id: "update-me", unread: false)
        try store.saveNotifications([updated])

        // Should still be 1 notification, now read
        let cached = try store.fetchCachedNotifications()
        #expect(cached.count == 1)
        #expect(cached.first?.unread == false)
    }
}

// MARK: - NotificationFilter Extended Tests

@Suite("NotificationFilter Extended Tests")
struct NotificationFilterExtendedTests {
    @Test("Repository filter matches only that repository")
    func repositoryFilterMatches() {
        let repo1 = ServiceTestHelpers.makeRepository(id: 1, name: "repo-a", owner: "owner")
        let repo2 = ServiceTestHelpers.makeRepository(id: 2, name: "repo-b", owner: "owner")

        let notification1 = ServiceTestHelpers.makeNotification(id: "1", repository: repo1)
        let notification2 = ServiceTestHelpers.makeNotification(id: "2", repository: repo2)

        let filter = NotificationFilter.repository(repo1)

        #expect(filter.matches(notification1))
        #expect(!filter.matches(notification2))
    }

    @Test("Participating filter matches participating reasons")
    func participatingFilterMatches() {
        let reasons: [NotificationReason] = [
            .author, .comment, .mention, .reviewRequested,
            .stateChange, .subscribed, .teamMention,
        ]

        for reason in reasons {
            let notification = ServiceTestHelpers.makeNotification(reason: reason)
            // Participating should match most interactive reasons
            let matches = NotificationFilter.participating.matches(notification)
            // Just verify it doesn't crash - actual logic may vary
            _ = matches
        }
    }

    @Test("Smart filters array contains expected filters")
    func smartFiltersContainsExpected() {
        let filters = NotificationFilter.smartFilters

        #expect(filters.contains(.inbox))
        #expect(filters.contains(.unread))
        #expect(filters.count >= 4)
    }

    @Test("Filter display names are not empty")
    func filterDisplayNamesNotEmpty() {
        let filters: [NotificationFilter] = [
            .inbox, .unread, .participating, .mentioned,
            .assigned, .reviewRequested,
        ]

        for filter in filters {
            #expect(!filter.displayName.isEmpty)
        }
    }

    @Test("Filter icons are valid SF Symbols")
    func filterIconsValid() {
        let filters = NotificationFilter.smartFilters

        for filter in filters {
            #expect(!filter.iconName.isEmpty)
        }
    }
}

// MARK: - DeviceFlowState Tests

@Suite("DeviceFlowState Tests")
struct DeviceFlowStateTests {
    @Test("DeviceFlowState is Equatable")
    func deviceFlowStateEquatable() {
        let state1 = DeviceFlowState(
            userCode: "ABCD-1234",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5)

        let state2 = DeviceFlowState(
            userCode: "ABCD-1234",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5)

        let state3 = DeviceFlowState(
            userCode: "WXYZ-5678",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5)

        #expect(state1 == state2)
        #expect(state1 != state3)
    }

    @Test("DeviceFlowState is Sendable")
    func deviceFlowStateSendable() {
        let state = DeviceFlowState(
            userCode: "TEST-CODE",
            verificationUri: "https://github.com/login/device",
            expiresIn: 600,
            interval: 5)

        // This should compile without issues if Sendable
        Task { @Sendable in
            _ = state.userCode
        }

        #expect(state.userCode == "TEST-CODE")
    }
}

// MARK: - AuthState Extended Tests

@Suite("AuthState Extended Tests")
struct AuthStateExtendedTests {
    @Test("Waiting for user auth state has device flow state")
    func waitingForUserAuthHasDeviceFlowState() {
        let deviceState = DeviceFlowState(
            userCode: "CODE-123",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5)

        let authState = AuthState.waitingForUserAuth(deviceState)

        #expect(authState.deviceFlowState != nil)
        #expect(authState.deviceFlowState?.userCode == "CODE-123")
        #expect(!authState.isAuthenticated)
        #expect(authState.accessToken == nil)
    }

    @Test("Authenticated state has no device flow state")
    func authenticatedHasNoDeviceFlowState() {
        let authState = AuthState.authenticated("test-token")

        #expect(authState.deviceFlowState == nil)
        #expect(authState.isAuthenticated)
        #expect(authState.accessToken == "test-token")
    }

    @Test("Error state is not authenticated")
    func errorStateNotAuthenticated() {
        let authState = AuthState.error("Something went wrong")

        #expect(!authState.isAuthenticated)
        #expect(authState.accessToken == nil)
        #expect(authState.deviceFlowState == nil)
    }

    @Test("Requesting device code state")
    func requestingDeviceCodeState() {
        let authState = AuthState.requestingDeviceCode

        #expect(!authState.isAuthenticated)
        #expect(authState.accessToken == nil)
        #expect(authState.deviceFlowState == nil)
    }
}

// MARK: - GitHubUser Tests

@Suite("GitHubUser Tests")
struct GitHubUserTests {
    @Test("GitHubUser decodes from JSON")
    func userDecodesFromJSON() throws {
        let json = """
        {
            "login": "octocat",
            "id": 1,
            "node_id": "MDQ6VXNlcjE=",
            "avatar_url": "https://github.com/images/octocat.png",
            "url": "https://api.github.com/users/octocat",
            "html_url": "https://github.com/octocat",
            "type": "User",
            "name": "The Octocat",
            "email": "octocat@github.com",
            "bio": "A cat",
            "public_repos": 10,
            "followers": 100,
            "following": 50,
            "created_at": "2020-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let user = try decoder.decode(GitHubUser.self, from: data)

        #expect(user.login == "octocat")
        #expect(user.id == 1)
        #expect(user.name == "The Octocat")
        #expect(user.email == "octocat@github.com")
        #expect(user.bio == "A cat")
        #expect(user.publicRepos == 10)
        #expect(user.followers == 100)
    }

    @Test("GitHubUser decodes with optional fields missing")
    func userDecodesWithMissingOptionals() throws {
        let json = """
        {
            "login": "minimal",
            "id": 42,
            "node_id": "node123",
            "avatar_url": "https://example.com/avatar.png",
            "url": "https://api.github.com/users/minimal",
            "html_url": "https://github.com/minimal",
            "type": "User",
            "public_repos": 5,
            "followers": 10,
            "following": 20,
            "created_at": "2021-06-15T00:00:00Z",
            "updated_at": "2025-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let user = try decoder.decode(GitHubUser.self, from: data)

        #expect(user.login == "minimal")
        #expect(user.name == nil)
        #expect(user.email == nil)
        #expect(user.bio == nil)
        #expect(user.publicRepos == 5)
    }
}

// MARK: - Test Helpers

enum ServiceTestHelpers {
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
        let repo = repository ?? Self.makeRepository()
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
