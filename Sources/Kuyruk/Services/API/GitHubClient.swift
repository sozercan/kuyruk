import Foundation

/// Errors that can occur when interacting with the GitHub API.
enum GitHubError: Error, LocalizedError, Sendable {
    case unauthorized
    case authenticationFailed(String)
    case invalidResponse
    case httpError(Int)
    case decodingError(String)
    case networkError(String)
    case notFound
    case rateLimited(resetDate: Date?)
    case serverError
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Authentication required. Please log in."
        case let .authenticationFailed(message):
            "Authentication failed: \(message)"
        case .invalidResponse:
            "Invalid response from GitHub."
        case let .httpError(code):
            "HTTP error: \(code)"
        case let .decodingError(message):
            "Failed to parse response: \(message)"
        case let .networkError(message):
            "Network error: \(message)"
        case .notFound:
            "Resource not found."
        case let .rateLimited(resetDate):
            if let date = resetDate {
                "Rate limit exceeded. Resets at \(date.formatted())."
            } else {
                "Rate limit exceeded."
            }
        case .serverError:
            "GitHub server error. Please try again later."
        case let .unknown(message):
            "Unknown error: \(message)"
        }
    }
}

/// GitHub API endpoints
enum GitHubEndpoint {
    case notifications(all: Bool, participating: Bool, page: Int)
    case markThreadAsRead(threadId: String)
    case threadSubscription(threadId: String)
    case user
    case repository(owner: String, repo: String)
    case issue(owner: String, repo: String, number: Int)
    case pullRequest(owner: String, repo: String, number: Int)

    var path: String {
        switch self {
        case .notifications:
            "/notifications"
        case let .markThreadAsRead(threadId):
            "/notifications/threads/\(threadId)"
        case let .threadSubscription(threadId):
            "/notifications/threads/\(threadId)/subscription"
        case .user:
            "/user"
        case let .repository(owner, repo):
            "/repos/\(owner)/\(repo)"
        case let .issue(owner, repo, number):
            "/repos/\(owner)/\(repo)/issues/\(number)"
        case let .pullRequest(owner, repo, number):
            "/repos/\(owner)/\(repo)/pulls/\(number)"
        }
    }

    var method: String {
        switch self {
        case .notifications,
             .user,
             .repository,
             .issue,
             .pullRequest,
             .threadSubscription:
            "GET"
        case .markThreadAsRead:
            "PATCH"
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case let .notifications(all, participating, page):
            var items = [URLQueryItem]()
            items.append(URLQueryItem(name: "all", value: all ? "true" : "false"))
            items.append(URLQueryItem(name: "participating", value: participating ? "true" : "false"))
            items.append(URLQueryItem(name: "per_page", value: "50"))
            if page > 1 {
                items.append(URLQueryItem(name: "page", value: String(page)))
            }
            return items
        default:
            return nil
        }
    }
}

/// GitHub API client for making authenticated requests.
@MainActor
@Observable
final class GitHubClient {
    // MARK: - Properties

    private let baseUrl = "https://api.github.com"
    private let session: URLSession
    private let authService: AuthService
    private let decoder: JSONDecoder

    // MARK: - Rate Limiting

    private(set) var rateLimitRemaining: Int?
    private(set) var rateLimitReset: Date?

    // MARK: - Conditional Request Caching (Persisted)

    /// UserDefaults keys for persisting conditional headers
    private enum CacheKeys {
        static let etag = "notifications.etag"
        static let lastModified = "notifications.lastModified"
        static let cacheTimestamp = "notifications.cacheTimestamp"
    }

    /// Cached ETag for notifications endpoint (persisted to UserDefaults)
    private var notificationsETag: String? {
        get { UserDefaults.standard.string(forKey: CacheKeys.etag) }
        set { UserDefaults.standard.set(newValue, forKey: CacheKeys.etag) }
    }

    /// Cached Last-Modified for notifications endpoint (persisted to UserDefaults)
    private var notificationsLastModified: String? {
        get { UserDefaults.standard.string(forKey: CacheKeys.lastModified) }
        set { UserDefaults.standard.set(newValue, forKey: CacheKeys.lastModified) }
    }

    /// Maximum concurrent pages to fetch in parallel
    private let maxParallelPages = 5

    // MARK: - TTL Cache

    /// Cached notifications with timestamp (in-memory only for performance)
    private var cachedNotifications: [GitHubNotification]?

    /// When the cache was last updated (persisted for cross-session TTL)
    private var cacheTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: CacheKeys.cacheTimestamp) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: CacheKeys.cacheTimestamp) }
    }

    /// Cache TTL in seconds (default: 30 seconds)
    /// Can be configured via UserDefaults "notificationCacheTTL"
    var cacheTTL: TimeInterval {
        let userTTL = UserDefaults.standard.integer(forKey: "notificationCacheTTL")
        return userTTL > 0 ? TimeInterval(userTTL) : 30
    }

    /// Whether the cache is still valid (public for UI decisions)
    /// Note: On app restart, in-memory cache is empty but we still have ETag for 304
    var isCacheValid: Bool {
        guard let timestamp = cacheTimestamp, cachedNotifications != nil else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < self.cacheTTL
    }

    /// Whether we have persisted conditional headers for 304 optimization
    var hasConditionalHeaders: Bool {
        notificationsETag != nil || notificationsLastModified != nil
    }

    /// Time remaining until cache expires (for UI display)
    var cacheTimeRemaining: TimeInterval? {
        guard let timestamp = cacheTimestamp else { return nil }
        let elapsed = Date().timeIntervalSince(timestamp)
        let remaining = self.cacheTTL - elapsed
        return remaining > 0 ? remaining : nil
    }

    // MARK: - Initialization

    init(authService: AuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Fetches notifications from GitHub.
    /// - Parameters:
    ///   - all: Include read notifications
    ///   - participating: Only notifications where user is participating
    ///   - page: Page number for pagination
    /// - Returns: Array of GitHub notifications
    func fetchNotifications(
        all: Bool = false,
        participating: Bool = false,
        page: Int = 1) async throws -> [GitHubNotification] {
        let endpoint = GitHubEndpoint.notifications(all: all, participating: participating, page: page)
        return try await self.request(endpoint)
    }

    /// Fetches all pages of notifications using parallel requests.
    /// Returns nil if data hasn't changed (304 Not Modified).
    func fetchAllNotifications(
        all: Bool = false,
        participating: Bool = false) async throws -> [GitHubNotification]? {
        // First, try a conditional request to check if data changed
        let firstPageResult = try await self.fetchNotificationsConditional(
            all: all,
            participating: participating,
            page: 1)

        switch firstPageResult {
        case .notModified:
            DiagnosticsLogger.info("Notifications not modified (304)", category: .api)
            return nil

        case let .success(firstPage, hasMore):
            var allNotifications = firstPage

            if hasMore {
                // Fetch remaining pages in parallel
                let additionalPages = try await self.fetchRemainingPagesParallel(
                    all: all,
                    participating: participating,
                    startPage: 2)
                allNotifications.append(contentsOf: additionalPages)
            }

            DiagnosticsLogger.info("Fetched \(allNotifications.count) notifications total", category: .api)
            return allNotifications
        }
    }

    /// Fetches notifications progressively, calling the handler as each batch arrives.
    /// This allows the UI to update immediately with the first page while more load.
    /// Uses TTL cache to avoid unnecessary network requests.
    /// - Parameters:
    ///   - all: Include read notifications
    ///   - participating: Only notifications where user is participating
    ///   - onBatchReceived: Called with accumulated notifications after each batch
    /// - Returns: Final array of all notifications, or nil if cache is valid/304 Not Modified
    func fetchAllNotificationsProgressive(
        all: Bool = false,
        participating: Bool = false,
        onBatchReceived: @escaping ([GitHubNotification]) -> Void) async throws -> [GitHubNotification]? {
        // Check TTL cache first
        if self.isCacheValid, let cached = cachedNotifications {
            DiagnosticsLogger.info("Using cached notifications (TTL: \(Int(self.cacheTTL))s)", category: .api)
            onBatchReceived(cached)
            return nil // nil means "use existing data"
        }

        // First, try a conditional request to check if data changed
        let firstPageResult = try await self.fetchNotificationsConditional(
            all: all,
            participating: participating,
            page: 1)

        switch firstPageResult {
        case .notModified:
            DiagnosticsLogger.info("Notifications not modified (304)", category: .api)
            // Update cache timestamp even on 304
            self.cacheTimestamp = Date()
            return nil

        case let .success(firstPage, hasMore):
            // Immediately update UI with first page
            onBatchReceived(firstPage)

            var allNotifications = firstPage

            if hasMore {
                // Fetch remaining pages progressively
                allNotifications = try await self.fetchRemainingPagesProgressively(
                    all: all,
                    participating: participating,
                    startPage: 2,
                    existingNotifications: firstPage,
                    onBatchReceived: onBatchReceived)
            }

            // Update cache
            self.cachedNotifications = allNotifications
            self.cacheTimestamp = Date()

            DiagnosticsLogger.info("Fetched \(allNotifications.count) notifications total", category: .api)
            return allNotifications
        }
    }

    /// Fetches all notifications (non-optional for backward compatibility).
    func fetchAllNotificationsForced(
        all: Bool = false,
        participating: Bool = false) async throws -> [GitHubNotification] {
        // Clear all caches to force a fresh fetch
        self.invalidateCache()

        return try await self.fetchAllNotifications(all: all, participating: participating) ?? []
    }

    /// Invalidates the notifications cache, forcing the next fetch to hit the network.
    func invalidateCache() {
        self.cachedNotifications = nil
        self.cacheTimestamp = nil
        self.notificationsETag = nil
        self.notificationsLastModified = nil
        DiagnosticsLogger.debug("Notifications cache invalidated", category: .api)
    }

    /// Updates the cache after a local change (e.g., marking as read).
    func updateCachedNotification(_ notification: GitHubNotification) {
        guard var cached = cachedNotifications else { return }
        if let index = cached.firstIndex(where: { $0.id == notification.id }) {
            cached[index] = notification
            self.cachedNotifications = cached
        }
    }

    // MARK: - Private Pagination Methods

    private enum ConditionalResult {
        case notModified
        case success([GitHubNotification], hasMore: Bool)
    }

    private func fetchNotificationsConditional(
        all: Bool,
        participating: Bool,
        page: Int) async throws -> ConditionalResult {
        let endpoint = GitHubEndpoint.notifications(all: all, participating: participating, page: page)
        var request = try self.buildRequest(for: endpoint)

        // Add conditional headers
        if let etag = notificationsETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = notificationsLastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        DiagnosticsLogger.info("Request: \(endpoint.method) \(endpoint.path) (conditional)", category: .api)

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        self.updateRateLimitInfo(from: httpResponse)

        // Handle 304 Not Modified
        if httpResponse.statusCode == 304 {
            return .notModified
        }

        try self.handleResponseStatus(httpResponse)

        // Store conditional headers for next request
        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            self.notificationsETag = etag
        }
        if let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
            self.notificationsLastModified = lastModified
        }

        do {
            let notifications = try self.decoder.decode([GitHubNotification].self, from: data)
            let hasMore = notifications.count == 50
            return .success(notifications, hasMore: hasMore)
        } catch {
            DiagnosticsLogger.error(error, context: "Decoding notifications", category: .api)
            throw GitHubError.decodingError(error.localizedDescription)
        }
    }

    private func fetchRemainingPagesParallel(
        all: Bool,
        participating: Bool,
        startPage: Int) async throws -> [GitHubNotification] {
        var allNotifications: [GitHubNotification] = []
        var currentPage = startPage

        while true {
            // Fetch up to maxParallelPages concurrently
            let pagesToFetch = currentPage...(currentPage + self.maxParallelPages - 1)

            let results = try await withThrowingTaskGroup(
                of: (page: Int, notifications: [GitHubNotification]).self) { group in
                    for page in pagesToFetch {
                        group.addTask {
                            let notifications = try await self.fetchNotifications(
                                all: all,
                                participating: participating,
                                page: page)
                            return (page: page, notifications: notifications)
                        }
                    }

                    var pageResults: [(page: Int, notifications: [GitHubNotification])] = []
                    for try await result in group {
                        pageResults.append(result)
                    }
                    return pageResults.sorted { $0.page < $1.page }
                }

            // Process results in page order
            var continuesFetching = false
            for result in results {
                allNotifications.append(contentsOf: result.notifications)

                // If any page has 50 items, there might be more
                if result.notifications.count == 50 {
                    continuesFetching = true
                }
            }

            // Check if we should continue
            if !continuesFetching {
                break
            }

            currentPage += self.maxParallelPages

            // Safety limit
            if currentPage > 20 {
                DiagnosticsLogger.warning("Reached page limit (20), stopping pagination", category: .api)
                break
            }
        }

        return allNotifications
    }

    /// Fetches remaining pages progressively, calling the handler after each batch.
    private func fetchRemainingPagesProgressively(
        all: Bool,
        participating: Bool,
        startPage: Int,
        existingNotifications: [GitHubNotification],
        onBatchReceived: @escaping ([GitHubNotification]) -> Void) async throws -> [GitHubNotification] {
        var allNotifications = existingNotifications
        var currentPage = startPage

        while true {
            // Fetch up to maxParallelPages concurrently
            let pagesToFetch = currentPage...(currentPage + self.maxParallelPages - 1)

            let results = try await withThrowingTaskGroup(
                of: (page: Int, notifications: [GitHubNotification]).self) { group in
                    for page in pagesToFetch {
                        group.addTask {
                            let notifications = try await self.fetchNotifications(
                                all: all,
                                participating: participating,
                                page: page)
                            return (page: page, notifications: notifications)
                        }
                    }

                    var pageResults: [(page: Int, notifications: [GitHubNotification])] = []
                    for try await result in group {
                        pageResults.append(result)
                    }
                    return pageResults.sorted { $0.page < $1.page }
                }

            // Process results in page order
            var continuesFetching = false
            for result in results {
                allNotifications.append(contentsOf: result.notifications)

                // If any page has 50 items, there might be more
                if result.notifications.count == 50 {
                    continuesFetching = true
                }
            }

            // Update UI after each batch of parallel fetches
            onBatchReceived(allNotifications)

            // Check if we should continue
            if !continuesFetching {
                break
            }

            currentPage += self.maxParallelPages

            // Safety limit
            if currentPage > 20 {
                DiagnosticsLogger.warning("Reached page limit (20), stopping pagination", category: .api)
                break
            }
        }

        return allNotifications
    }

    /// Marks a notification thread as read.
    func markAsRead(threadId: String) async throws {
        let endpoint = GitHubEndpoint.markThreadAsRead(threadId: threadId)
        let request = try self.buildRequest(for: endpoint)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        try self.handleResponseStatus(httpResponse)
        DiagnosticsLogger.info("Marked thread \(threadId) as read", category: .api)
    }

    /// Fetches the authenticated user's information.
    func fetchCurrentUser() async throws -> GitHubUser {
        try await self.request(.user)
    }

    // MARK: - Private Methods

    private func request<T: Decodable>(_ endpoint: GitHubEndpoint) async throws -> T {
        let request = try self.buildRequest(for: endpoint)

        DiagnosticsLogger.info("Request: \(endpoint.method) \(endpoint.path)", category: .api)

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        self.updateRateLimitInfo(from: httpResponse)
        try self.handleResponseStatus(httpResponse)

        do {
            return try self.decoder.decode(T.self, from: data)
        } catch {
            DiagnosticsLogger.error(error, context: "Decoding \(T.self)", category: .api)
            throw GitHubError.decodingError(error.localizedDescription)
        }
    }

    private func buildRequest(for endpoint: GitHubEndpoint) throws -> URLRequest {
        guard let token = authService.state.accessToken else {
            throw GitHubError.unauthorized
        }

        guard var components = URLComponents(string: baseUrl + endpoint.path) else {
            throw GitHubError.invalidResponse
        }
        components.queryItems = endpoint.queryItems

        guard let url = components.url else {
            throw GitHubError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        return request
    }

    private func handleResponseStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return // Success

        case 304:
            return // Not Modified (for conditional requests)

        case 401,
             403:
            throw GitHubError.unauthorized

        case 404:
            throw GitHubError.notFound

        case 429:
            throw GitHubError.rateLimited(resetDate: self.rateLimitReset)

        case 500...599:
            throw GitHubError.serverError

        default:
            throw GitHubError.httpError(response.statusCode)
        }
    }

    private func updateRateLimitInfo(from response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remainingInt = Int(remaining) {
            self.rateLimitRemaining = remainingInt
        }

        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = Double(reset) {
            self.rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
        }

        if let remaining = rateLimitRemaining, remaining < 10 {
            DiagnosticsLogger.warning("Low rate limit remaining: \(remaining)", category: .api)
        }
    }
}
