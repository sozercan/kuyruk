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

    /// Fetches all pages of notifications.
    func fetchAllNotifications(all: Bool = false, participating: Bool = false) async throws -> [GitHubNotification] {
        var allNotifications: [GitHubNotification] = []
        var page = 1
        var hasMore = true

        while hasMore {
            let notifications: [GitHubNotification] = try await self.fetchNotifications(
                all: all,
                participating: participating,
                page: page)

            allNotifications.append(contentsOf: notifications)

            // GitHub returns 50 per page max
            hasMore = notifications.count == 50
            page += 1

            // Safety limit
            if page > 10 {
                DiagnosticsLogger.warning("Reached page limit, stopping pagination", category: .api)
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
