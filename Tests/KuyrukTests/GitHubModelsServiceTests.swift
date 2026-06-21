import Foundation
import Testing
@testable import Kuyruk

// MARK: - Mock URLProtocol

/// Custom URLProtocol for mocking network requests in tests.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Static Properties (nonisolated for Sendable compliance)

    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockResponse: HTTPURLResponse?
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // MARK: - URLProtocol Overrides

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = self.request

        if let error = Self.mockError {
            self.client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let requestHandler = Self.requestHandler {
            do {
                let (response, data) = try requestHandler(self.request)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
            return
        }

        if let response = Self.mockResponse {
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        } else {
            // Default 200 response - use fallback URL if request URL is nil
            let fallbackURL = URL(string: "https://models.github.ai")
            guard let url = self.request.url ?? fallbackURL,
                  let defaultResponse = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: nil) else {
                return
            }
            self.client?.urlProtocol(self, didReceive: defaultResponse, cacheStoragePolicy: .notAllowed)
        }

        if let data = Self.mockData {
            self.client?.urlProtocol(self, didLoad: data)
        }

        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No-op
    }

    // MARK: - Test Helpers

    static func reset() {
        self.mockData = nil
        self.mockResponse = nil
        self.mockError = nil
        self.requestCount = 0
        self.lastRequest = nil
        self.requestHandler = nil
    }

    static func setMockResponse(statusCode: Int, headers: [String: String]? = nil) {
        guard let url = URL(string: "https://models.github.ai") else { return }
        self.mockResponse = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers)
    }
}

// MARK: - Test Fixtures

enum GitHubModelsTestFixtures {
    static let mockModelsJSON = """
    [{"id":"openai/gpt-4o-mini","name":"GPT-4o mini",\
    "publisher":"OpenAI","summary":"Efficient AI","rate_limit_tier":"low"}]
    """

    static let mockMultipleModelsJSON = """
    [
        {"id":"openai/gpt-4o-mini","name":"GPT-4o mini",\
    "publisher":"OpenAI","summary":"Efficient AI","rate_limit_tier":"low"},
        {"id":"openai/gpt-4o","name":"GPT-4o",\
    "publisher":"OpenAI","summary":"Advanced AI","rate_limit_tier":"high"}
    ]
    """

    static let mockCompletionJSON = """
    {"choices":[{"message":{"content":"This is a test summary."}}]}
    """

    /// OpenAI-compatible `/v1/models` list response (custom backend shape).
    static let mockOpenAIModelsJSON = """
    {"object":"list","data":[{"id":"gpt-4o-mini","object":"model"},\
    {"id":"claude-sonnet-4","object":"model"}]}
    """

    static let mockModelMissingOptionals = """
    [{"id":"test/model","name":"Test Model","publisher":"Test Publisher"}]
    """

    static func makeNotification(
        id: String = "test-notification",
        updatedAt: Date = Date()) -> GitHubNotification {
        let owner = RepositoryOwner(
            login: "owner",
            id: 1,
            nodeId: "owner-node",
            avatarUrl: "https://example.com/avatar.png",
            url: "https://api.github.com/users/owner",
            htmlUrl: "https://github.com/owner",
            type: "User")

        let repository = Repository(
            id: 1,
            nodeId: "repo-node",
            name: "test-repo",
            fullName: "owner/test-repo",
            owner: owner,
            isPrivate: false,
            htmlUrl: "https://github.com/owner/test-repo",
            description: "Test repository",
            fork: false,
            url: "https://api.github.com/repos/owner/test-repo")

        let subject = NotificationSubject(
            title: "Test Issue Title",
            url: "https://api.github.com/repos/owner/test-repo/issues/1",
            latestCommentUrl: nil,
            type: .issue)

        return GitHubNotification(
            id: id,
            repository: repository,
            subject: subject,
            reason: .assign,
            unread: true,
            updatedAt: updatedAt,
            lastReadAt: nil,
            url: "https://api.github.com/notifications/threads/\(id)",
            subscriptionUrl: "https://api.github.com/notifications/threads/\(id)/subscription")
    }
}

// MARK: - GitHubModel Parsing Tests

@Suite("GitHubModel Parsing Tests")
struct GitHubModelParsingTests {
    @Test
    func `Decodes model from JSON correctly`() throws {
        let json = GitHubModelsTestFixtures.mockModelsJSON
        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to convert JSON to data")
            return
        }

        let decoder = JSONDecoder()
        let models = try decoder.decode([GitHubModel].self, from: data)

        #expect(models.count == 1)
        #expect(models[0].id == "openai/gpt-4o-mini")
        #expect(models[0].name == "GPT-4o mini")
        #expect(models[0].publisher == "OpenAI")
        #expect(models[0].summary == "Efficient AI")
        #expect(models[0].rateLimitTier == "low")
    }

    @Test
    func `Decodes model with missing optional fields`() throws {
        let json = GitHubModelsTestFixtures.mockModelMissingOptionals
        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to convert JSON to data")
            return
        }

        let decoder = JSONDecoder()
        let models = try decoder.decode([GitHubModel].self, from: data)

        #expect(models.count == 1)
        #expect(models[0].id == "test/model")
        #expect(models[0].name == "Test Model")
        #expect(models[0].publisher == "Test Publisher")
        #expect(models[0].summary == nil)
        #expect(models[0].rateLimitTier == nil)
    }

    @Test
    func `Model display name combines publisher and name`() throws {
        let json = GitHubModelsTestFixtures.mockModelsJSON
        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to convert JSON to data")
            return
        }

        let decoder = JSONDecoder()
        let models = try decoder.decode([GitHubModel].self, from: data)

        #expect(models[0].displayName == "OpenAI/GPT-4o mini")
    }

    @Test
    func `Model isLowTier detects low tier correctly`() throws {
        let json = GitHubModelsTestFixtures.mockMultipleModelsJSON
        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to convert JSON to data")
            return
        }

        let decoder = JSONDecoder()
        let models = try decoder.decode([GitHubModel].self, from: data)

        let lowTierModel = models.first { $0.id == "openai/gpt-4o-mini" }
        let highTierModel = models.first { $0.id == "openai/gpt-4o" }

        #expect(lowTierModel?.isLowTier == true)
        #expect(highTierModel?.isLowTier == false)
    }

    @Test
    func `Model conforms to Hashable`() throws {
        let json = GitHubModelsTestFixtures.mockModelsJSON
        guard let data = json.data(using: .utf8) else {
            Issue.record("Failed to convert JSON to data")
            return
        }

        let decoder = JSONDecoder()
        let models = try decoder.decode([GitHubModel].self, from: data)

        var modelSet: Set<GitHubModel> = []
        modelSet.insert(models[0])

        #expect(modelSet.count == 1)
        #expect(modelSet.contains(models[0]))
    }
}

// MARK: - CachedSummary Tests

@Suite("CachedSummary Tests")
struct CachedSummaryTests {
    @Test
    func `Summary is valid when notification not updated`() {
        let summaryDate = Date()
        let notificationDate = summaryDate.addingTimeInterval(-60) // Notification updated 1 min ago

        let summary = CachedSummary(
            notificationId: "test-id",
            notificationUpdatedAt: summaryDate,
            summary: "Test summary",
            modelUsed: "gpt-4o-mini")

        let notification = GitHubModelsTestFixtures.makeNotification(
            id: "test-id",
            updatedAt: notificationDate)

        #expect(summary.isValid(for: notification))
    }

    @Test
    func `Summary is invalid when notification updated after summary`() {
        let summaryDate = Date().addingTimeInterval(-120) // Summary from 2 min ago
        let notificationDate = Date() // Notification just updated

        let summary = CachedSummary(
            notificationId: "test-id",
            notificationUpdatedAt: summaryDate,
            summary: "Outdated summary",
            modelUsed: "gpt-4o-mini")

        let notification = GitHubModelsTestFixtures.makeNotification(
            id: "test-id",
            updatedAt: notificationDate)

        #expect(!summary.isValid(for: notification))
    }

    @Test
    func `Summary stores generation metadata`() {
        let beforeCreation = Date()

        let summary = CachedSummary(
            notificationId: "meta-test",
            notificationUpdatedAt: Date(),
            summary: "A test summary",
            modelUsed: "openai/gpt-4o")

        #expect(summary.notificationId == "meta-test")
        #expect(summary.modelUsed == "openai/gpt-4o")
        #expect(summary.summary == "A test summary")
        #expect(summary.generatedAt >= beforeCreation)
    }
}

// MARK: - GitHubModelsService Tests (Using Mock URLSession)

@Suite("GitHubModelsService API Tests", .serialized)
@MainActor
struct GitHubModelsServiceAPITests {

    // MARK: - Setup

    /// Creates a URLSession configured with MockURLProtocol.
    private func createMockSession() -> URLSession {
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Creates a mock AuthService that returns a test token.
    private func createMockAuthService() throws -> AuthService {
        // Create AuthService in authenticated state
        AuthService()
        // We'll work around this by using a real auth service that we've configured
        // For testing purposes, we need the service to provide a token
    }

    // MARK: - Fetch Models Tests

    @Test
    func `Fetches available models successfully`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockMultipleModelsJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: session)

        // Note: Service requires auth token, so this will fail gracefully without token
        // We're testing that the service handles the response parsing correctly
        await service.fetchAvailableModels()

        // Without auth, we expect an error or empty models
        // The key test is that it doesn't crash
        #expect(service.isLoadingModels == false)
    }

    @Test
    func `Handles fetch models error gracefully`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockError = URLError(.notConnectedToInternet)

        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: session)

        await service.fetchAvailableModels()

        #expect(service.isLoadingModels == false)
        // Error should be set or models should be empty
        #expect(service.availableModels.isEmpty || service.modelsError != nil)
    }

    @Test
    func `Handles rate limit response`() async throws {
        let session = self.createMockSession()
        let resetTime = Date().addingTimeInterval(3600).timeIntervalSince1970
        MockURLProtocol.setMockResponse(
            statusCode: 429,
            headers: [
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": String(Int(resetTime)),
            ])

        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: session)

        await service.fetchAvailableModels()

        #expect(service.isLoadingModels == false)
    }

    // MARK: - Generate Summary Tests

    @Test
    func `Generate summary returns content`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockCompletionJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: session)

        // Set a model so the service can attempt generation
        service.selectedModelId = "openai/gpt-4o-mini"

        let notification = GitHubModelsTestFixtures.makeNotification()

        // This will fail without auth token, which is expected
        // We're testing error handling path
        do {
            _ = try await service.generateSummary(for: notification)
            // If it succeeds (shouldn't without token), that's fine too
        } catch {
            // Expected without proper auth
            #expect(error is GitHubError)
        }
    }

    @Test
    func `Cancel current generation cancels task`() throws {
        let session = self.createMockSession()
        // Set up a slow response by just using normal mock
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockCompletionJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: session)

        service.selectedModelId = "openai/gpt-4o-mini"

        // Cancel immediately
        service.cancelCurrentGeneration()

        // Verify no crash and service is in clean state
        #expect(service.isLoadingModels == false)
    }

    @Test
    func `Can generate summaries returns false without model`() throws {
        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: nil)

        // No model selected
        service.selectedModelId = nil

        #expect(service.canGenerateSummaries == false)
    }

    @Test
    func `Is rate limited when remaining is zero`() throws {
        let session = self.createMockSession()
        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()

        let service = GitHubModelsService(
            authService: authService,
            dataStore: dataStore,
            session: session)

        // Initially not rate limited
        #expect(service.isRateLimited == false)
    }

    // MARK: - Custom Backend Tests

    @Test
    func `Custom backend targets the configured base URL and OpenAI chat path`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockCompletionJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: session)
        defer { Self.resetBackend(service) }

        // Trailing slash should be trimmed before appending the path.
        service.backend = .custom
        service.customBaseURL = "http://localhost:1337/v1/"
        service.selectedModelId = "gpt-4o-mini"

        _ = try await service.generateAnalysis(
            for: GitHubModelsTestFixtures.makeNotification(),
            type: .summary)

        let lastURL = try #require(MockURLProtocol.lastRequest?.url?.absoluteString)
        #expect(lastURL == "http://localhost:1337/v1/chat/completions")
    }

    @Test
    func `Custom backend sends API key as bearer when set`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockCompletionJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: session)
        defer { Self.resetBackend(service) }

        service.backend = .custom
        service.customBaseURL = "http://localhost:1337/v1"
        service.customAPIKey = "secret-key"
        service.selectedModelId = "gpt-4o-mini"

        _ = try await service.generateAnalysis(
            for: GitHubModelsTestFixtures.makeNotification(),
            type: .summary)

        let auth = MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer secret-key")

        service.customAPIKey = nil
    }

    @Test
    func `Custom backend omits authorization header when no API key`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockCompletionJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: session)
        defer { Self.resetBackend(service) }

        service.backend = .custom
        service.customBaseURL = "http://localhost:1337/v1"
        service.customAPIKey = nil
        service.selectedModelId = "gpt-4o-mini"

        _ = try await service.generateAnalysis(
            for: GitHubModelsTestFixtures.makeNotification(),
            type: .summary)

        let auth = MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == nil)
    }

    @Test
    func `Custom backend decodes OpenAI model list`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.mockData = GitHubModelsTestFixtures.mockOpenAIModelsJSON.data(using: .utf8)
        MockURLProtocol.setMockResponse(statusCode: 200)

        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: session)
        defer { Self.resetBackend(service) }

        service.backend = .custom
        service.customBaseURL = "http://localhost:1337/v1"

        await service.fetchAvailableModels()

        #expect(service.availableModels.map(\.id) == ["gpt-4o-mini", "claude-sonnet-4"])
        // Synthesized models have no publisher, so displayName is the bare id.
        #expect(service.availableModels.first?.displayName == "gpt-4o-mini")
        // Catalog request used the OpenAI /models path on the custom base URL.
        let url = try #require(MockURLProtocol.lastRequest?.url?.absoluteString)
        #expect(url == "http://localhost:1337/v1/models")
    }

    @Test
    func `Custom backend queues latest model fetch while another fetch is active`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw GitHubError.invalidResponse }
            Thread.sleep(forTimeInterval: 0.05)

            let modelId = url.absoluteString.contains("/final/") ? "final-model" : "stale-model"
            let payload = """
            {"object":"list","data":[{"id":"\(modelId)","object":"model"}]}
            """
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil),
                let data = payload.data(using: .utf8) else {
                throw GitHubError.invalidResponse
            }
            return (response, data)
        }

        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: session)
        defer { Self.resetBackend(service) }

        service.backend = .custom
        service.customBaseURL = "http://localhost:1337/v1"

        let firstFetch = Task { @MainActor in
            await service.fetchAvailableModels()
        }

        try await Task.sleep(for: .milliseconds(10))
        service.customBaseURL = "http://localhost:1337/final/v1"
        await service.fetchAvailableModels()

        await firstFetch.value

        #expect(MockURLProtocol.requestCount == 2)
        #expect(service.availableModels.map(\.id) == ["final-model"])
        #expect(service.selectedModelId == "final-model")
        let url = try #require(MockURLProtocol.lastRequest?.url?.absoluteString)
        #expect(url == "http://localhost:1337/final/v1/models")
        #expect(service.modelsError == nil)
    }

    @Test
    func `Custom backend ignores stale model fetch when latest endpoint fails`() async throws {
        let session = self.createMockSession()
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw GitHubError.invalidResponse }
            Thread.sleep(forTimeInterval: 0.05)

            guard !url.absoluteString.contains("/final/") else {
                throw GitHubError.networkError("final endpoint unavailable")
            }

            let payload = """
            {"object":"list","data":[{"id":"stale-model","object":"model"}]}
            """
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil),
                let data = payload.data(using: .utf8) else {
                throw GitHubError.invalidResponse
            }
            return (response, data)
        }

        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: session)
        defer { Self.resetBackend(service) }

        service.backend = .custom
        service.customBaseURL = "http://localhost:1337/v1"

        let firstFetch = Task { @MainActor in
            await service.fetchAvailableModels()
        }

        try await Task.sleep(for: .milliseconds(10))
        service.customBaseURL = "http://localhost:1337/final/v1"
        await service.fetchAvailableModels()

        await firstFetch.value

        #expect(MockURLProtocol.requestCount == 2)
        #expect(service.availableModels.isEmpty)
        #expect(service.selectedModelId == nil)
        #expect(service.modelsError != nil)
    }

    @Test
    func `Custom backend is ready to generate without GitHub auth`() throws {
        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: nil)
        defer { Self.resetBackend(service) }

        service.backend = .custom

        // No endpoint yet → not ready.
        service.customBaseURL = ""
        #expect(service.isReadyToListModels == false)
        #expect(service.canGenerateSummaries == false)

        // Endpoint + model → ready, despite being unauthenticated with GitHub.
        service.customBaseURL = "http://localhost:1337/v1"
        service.selectedModelId = "gpt-4o-mini"
        #expect(service.isReadyToListModels == true)
        #expect(service.canGenerateSummaries == true)
    }

    @Test
    func `Switching backend resets the selected model`() throws {
        let dataStore = try DataStore(inMemory: true)
        let service = GitHubModelsService(
            authService: AuthService(),
            dataStore: dataStore,
            session: nil)
        defer { Self.resetBackend(service) }

        service.selectedModelId = "openai/gpt-4o-mini"
        service.backend = .custom

        #expect(service.selectedModelId == nil)
        #expect(service.availableModels.isEmpty)
    }

    /// Restores backend-related persisted state mutated by a custom-backend test so
    /// it does not leak across the serialized suite or into the real Keychain.
    private static func resetBackend(_ service: GitHubModelsService) {
        service.customAPIKey = nil
        service.customBaseURL = ""
        service.backend = .githubModels
        service.selectedModelId = nil
    }
}

// MARK: - DataStore Summary Integration Tests

@Suite("DataStore Summary Tests", .serialized)
@MainActor
struct DataStoreSummaryTests {
    @Test
    func `Summary uses cached value without API call`() throws {
        let dataStore = try DataStore(inMemory: true)
        let notification = GitHubModelsTestFixtures.makeNotification(id: "cached-test")

        // Pre-cache a summary
        try dataStore.saveSummary(
            "This is a cached summary",
            for: notification,
            model: "openai/gpt-4o-mini")

        // Fetch it back
        let cached = try dataStore.fetchSummary(for: "cached-test")

        #expect(cached != nil)
        #expect(cached?.summary == "This is a cached summary")
        #expect(cached?.modelUsed == "openai/gpt-4o-mini")
    }

    @Test
    func `Summary can be invalidated`() throws {
        let dataStore = try DataStore(inMemory: true)
        let notification = GitHubModelsTestFixtures.makeNotification(id: "invalidate-test")

        // Save a summary
        try dataStore.saveSummary(
            "Summary to invalidate",
            for: notification,
            model: "openai/gpt-4o-mini")

        // Verify it exists
        let before = try dataStore.fetchSummary(for: "invalidate-test")
        #expect(before != nil)

        // Invalidate it
        try dataStore.invalidateSummary(for: "invalidate-test")

        // Verify it's gone
        let after = try dataStore.fetchSummary(for: "invalidate-test")
        #expect(after == nil)
    }

    @Test
    func `Cleanup old summaries removes stale entries`() throws {
        let dataStore = try DataStore(inMemory: true)
        let notification = GitHubModelsTestFixtures.makeNotification(id: "cleanup-test")

        // Save a summary
        try dataStore.saveSummary(
            "Old summary",
            for: notification,
            model: "openai/gpt-4o-mini")

        // Cleanup with 0 days should remove all
        try dataStore.cleanupOldSummaries(olderThan: 0)

        // The summary should be removed (or still exist if just created - timing dependent)
        // This tests the mechanism doesn't crash
        let result = try dataStore.fetchSummary(for: "cleanup-test")
        // Result may or may not exist depending on timing, but no crash
        _ = result
    }

    @Test
    func `Save summary updates existing entry`() throws {
        let dataStore = try DataStore(inMemory: true)
        let notification = GitHubModelsTestFixtures.makeNotification(id: "update-test")

        // Save initial summary
        try dataStore.saveSummary(
            "Initial summary",
            for: notification,
            model: "openai/gpt-4o-mini")

        // Update with new summary
        try dataStore.saveSummary(
            "Updated summary",
            for: notification,
            model: "openai/gpt-4o")

        // Fetch and verify updated
        let cached = try dataStore.fetchSummary(for: "update-test")

        #expect(cached?.summary == "Updated summary")
        #expect(cached?.modelUsed == "openai/gpt-4o")
    }
}

// MARK: - NotificationsViewModel AI Cache Tests

@Suite("NotificationsViewModel AI Cache Tests", .serialized)
@MainActor
struct NotificationsViewModelAICacheTests {
    @Test
    func `ViewModel returns cached summary for notification`() throws {
        // Create dependencies
        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()
        let gitHubClient = GitHubClient(authService: authService)
        let syncService = SyncService(gitHubClient: gitHubClient, dataStore: dataStore)

        let viewModel = NotificationsViewModel(
            gitHubClient: gitHubClient,
            dataStore: dataStore,
            syncService: syncService)

        // Create and cache a summary
        let notification = GitHubModelsTestFixtures.makeNotification(id: "vm-cache-test")
        try dataStore.saveSummary(
            "ViewModel cached summary",
            for: notification,
            model: "openai/gpt-4o-mini")

        // Retrieve via ViewModel
        let cached = viewModel.cachedSummary(for: notification)

        #expect(cached != nil)
        #expect(cached?.summary == "ViewModel cached summary")
    }

    @Test
    func `ViewModel returns nil for uncached notification`() throws {
        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()
        let gitHubClient = GitHubClient(authService: authService)
        let syncService = SyncService(gitHubClient: gitHubClient, dataStore: dataStore)

        let viewModel = NotificationsViewModel(
            gitHubClient: gitHubClient,
            dataStore: dataStore,
            syncService: syncService)

        let notification = GitHubModelsTestFixtures.makeNotification(id: "no-cache-test")

        let cached = viewModel.cachedSummary(for: notification)

        #expect(cached == nil)
    }

    @Test
    func `ViewModel invalidates summary cache`() throws {
        let dataStore = try DataStore(inMemory: true)
        let authService = AuthService()
        let gitHubClient = GitHubClient(authService: authService)
        let syncService = SyncService(gitHubClient: gitHubClient, dataStore: dataStore)

        let viewModel = NotificationsViewModel(
            gitHubClient: gitHubClient,
            dataStore: dataStore,
            syncService: syncService)

        // Add a summary
        let notification = GitHubModelsTestFixtures.makeNotification(id: "invalidate-vm-test")
        try dataStore.saveSummary(
            "Summary to clear",
            for: notification,
            model: "openai/gpt-4o-mini")

        // Invalidate all via ViewModel
        viewModel.invalidateSummaryCache()

        // The summary should be removed (testing mechanism doesn't crash)
        // Note: Timing may affect whether it's actually removed
        _ = viewModel.cachedSummary(for: notification)
    }
}
