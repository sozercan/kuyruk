import Foundation

/// Types of AI analysis available for notifications.
enum AnalysisType: String, CaseIterable, Sendable {
    case summary = "TL;DR"
    case threadSummary = "Thread Summary"
    case priority = "Priority"
    case action = "Action"

    /// System message for the AI assistant based on analysis type.
    var systemMessage: String {
        switch self {
        case .summary:
            "You are a helpful assistant that summarizes GitHub notifications concisely."
        case .threadSummary:
            "You are a helpful assistant that summarizes discussion threads on GitHub."
        case .priority:
            "You are a helpful assistant that evaluates notification priority for developers."
        case .action:
            "You are a helpful assistant that provides actionable guidance for GitHub notifications."
        }
    }

    /// Max tokens for each analysis type.
    var maxTokens: Int {
        switch self {
        case .summary,
             .threadSummary:
            150
        case .priority:
            100
        case .action:
            75
        }
    }
}

/// Service for interacting with the GitHub Models API.
///
/// Provides functionality to:
/// - Fetch available models from the catalog
/// - Generate AI summaries for notifications
/// - Cache summaries in SwiftData
///
/// Uses the same OAuth token as the main GitHub API.
@MainActor
@Observable
final class GitHubModelsService {
    // MARK: - Types

    /// Chat completion request body.
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case maxTokens = "max_tokens"
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    /// Chat completion response.
    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }

    /// Models catalog response (array of models).
    private struct CatalogResponse: Decodable {
        let models: [GitHubModel]

        init(from decoder: Decoder) throws {
            // The API returns an array directly
            let container = try decoder.singleValueContainer()
            self.models = try container.decode([GitHubModel].self)
        }
    }

    // MARK: - Constants

    private enum Constants {
        static let modelsBaseUrl = "https://models.github.ai"
        static let catalogPath = "/catalog/models"
        static let inferencePath = "/inference/chat/completions"
        static let defaultModelId = "openai/gpt-4o-mini"
        static let maxTokens = 150
        static let selectedModelKey = "ai.selectedModelId"
    }

    // MARK: - State

    /// The currently selected model ID. Persisted via UserDefaults.
    var selectedModelId: String? {
        didSet {
            UserDefaults.standard.set(self.selectedModelId, forKey: Constants.selectedModelKey)
        }
    }

    /// Available models from the catalog.
    private(set) var availableModels: [GitHubModel] = []

    /// Whether models are currently being fetched.
    private(set) var isLoadingModels: Bool = false

    /// Error message from the last models fetch attempt.
    private(set) var modelsError: String?

    /// Rate limit remaining for the Models API.
    private(set) var rateLimitRemaining: Int?

    /// When the rate limit resets.
    private(set) var rateLimitReset: Date?

    // MARK: - Private Properties

    /// Current summary generation task (for single-flight pattern).
    private var currentGenerationTask: Task<String, Error>?

    /// Notification ID for the current generation task.
    private var currentNotificationId: String?

    /// Analysis type for the current generation task.
    private var currentAnalysisType: AnalysisType?

    /// URLSession with certificate pinning for models.github.ai.
    private let session: URLSession

    /// Dependencies.
    private let authService: AuthService
    private let dataStore: DataStore

    /// JSON decoder configured for the Models API.
    private let decoder: JSONDecoder

    /// JSON encoder for request bodies.
    private let encoder: JSONEncoder

    // MARK: - Initialization

    /// Creates a new GitHubModelsService.
    /// - Parameters:
    ///   - authService: Authentication service for token access.
    ///   - dataStore: SwiftData store for caching summaries.
    ///   - session: URLSession to use (defaults to pinned session).
    init(
        authService: AuthService,
        dataStore: DataStore,
        session: URLSession? = nil) {
        self.authService = authService
        self.dataStore = dataStore

        #if DEBUG
        // In debug builds, allow non-pinned session for testing
        self.session = session ?? URLSession.createPinnedSession(enforcePinning: false)
        #else
        // In release builds, always use pinned session
        self.session = session ?? URLSession.createPinnedSession(enforcePinning: true)
        #endif

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase

        // Load persisted model selection
        self.selectedModelId = UserDefaults.standard.string(forKey: Constants.selectedModelKey)
    }

    // MARK: - Public Methods

    /// Fetches available models from the GitHub Models catalog.
    func fetchAvailableModels() async {
        guard !self.isLoadingModels else { return }

        self.isLoadingModels = true
        self.modelsError = nil

        defer { self.isLoadingModels = false }

        do {
            let request = try self.buildRequest(path: Constants.catalogPath, method: "GET")

            DiagnosticsLogger.info("Fetching models catalog", category: .api)

            let (data, response) = try await self.session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubError.invalidResponse
            }

            self.updateRateLimitInfo(from: httpResponse)
            try Self.handleResponseStatus(httpResponse, rateLimitReset: self.rateLimitReset)

            self.availableModels = try self.decoder.decode([GitHubModel].self, from: data)

            DiagnosticsLogger.info("Fetched \(self.availableModels.count) models", category: .api)

            // Set default model if none selected
            if self.selectedModelId == nil, !self.availableModels.isEmpty {
                // Prefer the default model if available
                if self.availableModels.contains(where: { $0.id == Constants.defaultModelId }) {
                    self.selectedModelId = Constants.defaultModelId
                } else {
                    self.selectedModelId = self.availableModels.first?.id
                }
            }
        } catch {
            DiagnosticsLogger.error(error, context: "fetchAvailableModels", category: .api)
            self.modelsError = error.localizedDescription
        }
    }

    /// Generates an AI summary for a notification.
    ///
    /// Uses a single-flight pattern: if a generation is already in progress for the same
    /// notification, returns that task's result. If a different notification is requested,
    /// cancels the previous task.
    ///
    /// - Parameter notification: The notification to summarize.
    /// - Returns: The generated summary text.
    /// - Throws: `GitHubError` if the request fails.
    func generateSummary(for notification: GitHubNotification) async throws -> String {
        // Cancel previous task if different notification
        if self.currentNotificationId != notification.id {
            self.currentGenerationTask?.cancel()
            self.currentGenerationTask = nil
        }

        // Check SwiftData cache first
        if let cached = try? self.dataStore.fetchSummary(for: notification.id),
           cached.isValid(for: notification) {
            DiagnosticsLogger.debug("Using cached summary for \(notification.id)", category: .api)
            return cached.summary
        }

        // Single-flight: reuse existing task for same notification
        if self.currentNotificationId == notification.id,
           let existingTask = self.currentGenerationTask {
            return try await existingTask.value
        }

        // Create new task
        self.currentNotificationId = notification.id
        let task = Task<String, Error> {
            try await self.performGeneration(for: notification)
        }
        self.currentGenerationTask = task

        do {
            let result = try await task.value
            return result
        } catch {
            // Clear task on error
            if self.currentNotificationId == notification.id {
                self.currentGenerationTask = nil
                self.currentNotificationId = nil
            }
            throw error
        }
    }

    /// Cancels any in-progress summary generation.
    func cancelCurrentGeneration() {
        self.currentGenerationTask?.cancel()
        self.currentGenerationTask = nil
        self.currentNotificationId = nil
        self.currentAnalysisType = nil
        DiagnosticsLogger.debug("Cancelled analysis generation", category: .api)
    }

    /// Generates a specific type of AI analysis for a notification.
    ///
    /// Uses a single-flight pattern: if a generation is already in progress for the same
    /// notification and analysis type, returns that task's result.
    ///
    /// - Parameters:
    ///   - notification: The notification to analyze.
    ///   - type: The type of analysis to generate.
    /// - Returns: The generated analysis text.
    /// - Throws: `GitHubError` if the request fails.
    func generateAnalysis(
        for notification: GitHubNotification,
        type: AnalysisType) async throws -> String {
        // Cancel previous task if different notification or type
        if self.currentNotificationId != notification.id || self.currentAnalysisType != type {
            self.currentGenerationTask?.cancel()
            self.currentGenerationTask = nil
        }

        // Check SwiftData cache first
        if let cached = try? self.dataStore.fetchSummary(for: notification.id),
           cached.isValid(for: notification),
           cached.hasAnalysis(for: type) {
            DiagnosticsLogger.debug("Using cached \(type.rawValue) for \(notification.id)", category: .api)
            return self.extractAnalysisValue(from: cached, type: type)
        }

        // Single-flight: reuse existing task for same notification and type
        if self.currentNotificationId == notification.id,
           self.currentAnalysisType == type,
           let existingTask = self.currentGenerationTask {
            return try await existingTask.value
        }

        // Create new task
        self.currentNotificationId = notification.id
        self.currentAnalysisType = type
        let task = Task<String, Error> {
            try await self.performAnalysisGeneration(for: notification, type: type)
        }
        self.currentGenerationTask = task

        do {
            let result = try await task.value
            return result
        } catch {
            // Clear task on error
            if self.currentNotificationId == notification.id, self.currentAnalysisType == type {
                self.currentGenerationTask = nil
                self.currentNotificationId = nil
                self.currentAnalysisType = nil
            }
            throw error
        }
    }

    /// Extracts the analysis value from a cached summary based on type.
    private func extractAnalysisValue(from cached: CachedSummary, type: AnalysisType) -> String {
        switch type {
        case .summary:
            return cached.summary
        case .threadSummary:
            return cached.threadSummary ?? ""
        case .priority:
            if let score = cached.priorityScore, let explanation = cached.priorityExplanation {
                return "\(score) - \(explanation)"
            }
            return cached.priorityScore ?? ""
        case .action:
            return cached.actionRecommendation ?? ""
        }
    }

    /// Whether summaries can be generated (model selected and authenticated).
    var canGenerateSummaries: Bool {
        self.selectedModelId != nil && self.authService.state.isAuthenticated
    }

    /// Whether the API is currently rate limited.
    var isRateLimited: Bool {
        guard let remaining = self.rateLimitRemaining else { return false }
        return remaining <= 0
    }

    // MARK: - Private Methods

    /// Performs the actual API call to generate a summary.
    private func performGeneration(for notification: GitHubNotification) async throws -> String {
        try await self.performAnalysisGeneration(for: notification, type: .summary)
    }

    /// Performs the actual API call to generate an analysis.
    private func performAnalysisGeneration(
        for notification: GitHubNotification,
        type: AnalysisType) async throws -> String {
        guard let modelId = self.selectedModelId else {
            throw GitHubError.unknown("No model selected")
        }

        let prompt = Self.buildPrompt(for: notification, type: type)

        let chatRequest = ChatRequest(
            model: modelId,
            messages: [
                ChatRequest.Message(
                    role: "system",
                    content: type.systemMessage),
                ChatRequest.Message(
                    role: "user",
                    content: prompt),
            ],
            maxTokens: type.maxTokens)

        var request = try self.buildRequest(path: Constants.inferencePath, method: "POST")
        request.httpBody = try self.encoder.encode(chatRequest)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        DiagnosticsLogger.info(
            "Generating \(type.rawValue) for notification \(notification.id)",
            category: .api)

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        self.updateRateLimitInfo(from: httpResponse)
        try Self.handleResponseStatus(httpResponse, rateLimitReset: self.rateLimitReset)

        let chatResponse = try self.decoder.decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw GitHubError.invalidResponse
        }

        // Parse and cache the result
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        try self.cacheAnalysisResult(result, for: notification, type: type, model: modelId)

        DiagnosticsLogger.info(
            "Generated \(type.rawValue) for notification \(notification.id)",
            category: .api)

        return result
    }

    /// Caches an analysis result based on type.
    private func cacheAnalysisResult(
        _ result: String,
        for notification: GitHubNotification,
        type: AnalysisType,
        model: String) throws {
        switch type {
        case .summary:
            try self.dataStore.saveSummary(result, for: notification, model: model)

        case .threadSummary,
             .action:
            try self.dataStore.updateAnalysis(
                for: notification.id,
                notificationUpdatedAt: notification.updatedAt,
                type: type,
                value: result,
                model: model)

        case .priority:
            // Parse priority: "High - explanation" format
            let (score, explanation) = Self.parsePriorityResult(result)
            try self.dataStore.updateAnalysis(
                for: notification.id,
                notificationUpdatedAt: notification.updatedAt,
                type: type,
                value: score,
                priorityExplanation: explanation,
                model: model)
        }
    }

    /// Parses a priority result into score and explanation.
    /// - Parameter result: The raw priority result string.
    /// - Returns: A tuple of (score, explanation).
    private static func parsePriorityResult(_ result: String) -> (score: String, explanation: String?) {
        // Expected format: "High - you're blocking this PR review"
        let parts = result.split(separator: "-", maxSplits: 1)
        let score = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? result
        let explanation = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : nil

        // Normalize score to standard values
        let normalizedScore: String = switch score.lowercased() {
        case "high":
            "High"
        case "medium":
            "Medium"
        case "low":
            "Low"
        default:
            score
        }

        return (normalizedScore, explanation)
    }

    /// Builds the prompt for analyzing a notification.
    private static func buildPrompt(for notification: GitHubNotification, type: AnalysisType) -> String {
        let notificationInfo = """
        Title: \(notification.subject.title)
        Type: \(notification.subject.type.rawValue)
        Repository: \(notification.repository.fullName)
        Reason: \(notification.reason.displayName)
        """

        switch type {
        case .summary:
            return """
            Summarize this GitHub notification in 2-3 sentences:
            \(notificationInfo)
            """

        case .threadSummary:
            return """
            Summarize the discussion thread on this GitHub notification. \
            What's the current status? Keep it to 2-3 sentences.
            \(notificationInfo)
            """

        case .priority:
            return """
            Rate the priority of this notification for the user as High, Medium, or Low.
            Start with the rating, then explain briefly why.
            Example: "High - you're blocking this PR review"
            Consider: Is user blocking others? Is this urgent? Is user mentioned directly?
            \(notificationInfo)
            """

        case .action:
            return """
            What action should the user take on this notification?
            Reply with one of: "Needs your review", "Needs your response", \
            "Just FYI, no action needed", "Waiting on others", or similar brief actionable guidance.
            Keep response to one short sentence.
            \(notificationInfo)
            """
        }
    }

    /// Builds the prompt for summarizing a notification (legacy, delegates to buildPrompt).
    private static func buildPrompt(for notification: GitHubNotification) -> String {
        self.buildPrompt(for: notification, type: .summary)
    }

    /// Builds an authenticated request for the Models API.
    private func buildRequest(path: String, method: String) throws -> URLRequest {
        guard let token = self.authService.state.accessToken else {
            throw GitHubError.unauthorized
        }

        guard let url = URL(string: Constants.modelsBaseUrl + path) else {
            throw GitHubError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        return request
    }

    /// Handles HTTP response status codes.
    private static func handleResponseStatus(_ response: HTTPURLResponse, rateLimitReset: Date?) throws {
        switch response.statusCode {
        case 200...299:
            return // Success

        case 401,
             403:
            throw GitHubError.unauthorized

        case 404:
            throw GitHubError.notFound

        case 429:
            throw GitHubError.rateLimited(resetDate: rateLimitReset)

        case 500...599:
            throw GitHubError.serverError

        default:
            throw GitHubError.httpError(response.statusCode)
        }
    }

    /// Updates rate limit tracking from response headers.
    private func updateRateLimitInfo(from response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remainingInt = Int(remaining) {
            self.rateLimitRemaining = remainingInt
        }

        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = Double(reset) {
            self.rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
        }

        if let remaining = self.rateLimitRemaining, remaining < 5 {
            DiagnosticsLogger.warning("Low Models API rate limit: \(remaining)", category: .api)
        }
    }
}
