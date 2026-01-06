import Foundation

// MARK: - OAuthConfig

/// OAuth 2.0 configuration for GitHub Device Flow
enum OAuthConfig {
    static let clientId = "Ov23li3MPDZBIQpusS18"
    static let scope = "notifications read:user"

    static let deviceCodeUrl = "https://github.com/login/device/code"
    static let tokenUrl = "https://github.com/login/oauth/access_token"
}

// MARK: - Device Flow State

/// State for the device flow authentication
struct DeviceFlowState: Equatable, Sendable {
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
}

// MARK: - Auth State

/// Authentication state machine
enum AuthState: Equatable, Sendable {
    case unknown
    case unauthenticated
    case requestingDeviceCode
    case waitingForUserAuth(DeviceFlowState)
    case authenticated(String) // access token
    case error(String)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var accessToken: String? {
        if case let .authenticated(token) = self { return token }
        return nil
    }

    var deviceFlowState: DeviceFlowState? {
        if case let .waitingForUserAuth(state) = self { return state }
        return nil
    }
}

// MARK: - Auth Service

/// Manages GitHub OAuth authentication using Device Flow.
@MainActor
@Observable
final class AuthService {
    // MARK: - Properties

    private(set) var state: AuthState = .unknown
    private(set) var currentUser: GitHubUser?

    private let keychainManager: KeychainManager
    private var pollingTask: Task<Void, Never>?

    // MARK: - Initialization

    init(keychainManager: KeychainManager = .shared) {
        self.keychainManager = keychainManager
    }

    // MARK: - Public Methods

    /// Checks for existing authentication on app launch.
    func checkExistingAuth() async {
        DiagnosticsLogger.info("Checking for existing authentication", category: .auth)

        do {
            if let token = try keychainManager.getAccessToken() {
                DiagnosticsLogger.info("Found existing token, validating...", category: .auth)
                self.state = .authenticated(token)
                await self.validateToken()
            } else {
                DiagnosticsLogger.info("No existing token found", category: .auth)
                self.state = .unauthenticated
            }
        } catch {
            DiagnosticsLogger.error(error, context: "checkExistingAuth", category: .auth)
            self.state = .unauthenticated
        }
    }

    /// Initiates the OAuth Device Flow.
    func login() async {
        DiagnosticsLogger.info("Starting OAuth Device Flow", category: .auth)
        self.state = .requestingDeviceCode

        do {
            // Step 1: Request device and user verification codes
            let deviceResponse = try await requestDeviceCode()

            // Update state with the user code for display
            let deviceState = DeviceFlowState(
                userCode: deviceResponse.userCode,
                verificationUri: deviceResponse.verificationUri,
                expiresIn: deviceResponse.expiresIn,
                interval: deviceResponse.interval
            )
            self.state = .waitingForUserAuth(deviceState)

            DiagnosticsLogger.info(
                "Device code received. User code: \(deviceResponse.userCode)",
                category: .auth
            )

            // Step 2: Poll for user authorization
            await pollForAuthorization(deviceCode: deviceResponse.deviceCode, interval: deviceResponse.interval)

        } catch {
            DiagnosticsLogger.error(error, context: "login", category: .auth)
            self.state = .error(error.localizedDescription)
        }
    }

    /// Cancels the current login flow.
    func cancelLogin() {
        pollingTask?.cancel()
        pollingTask = nil
        self.state = .unauthenticated
        DiagnosticsLogger.info("Login cancelled", category: .auth)
    }

    /// Logs out the current user.
    func logout() async {
        DiagnosticsLogger.info("Logging out", category: .auth)

        pollingTask?.cancel()
        pollingTask = nil

        do {
            try self.keychainManager.clearAll()
        } catch {
            DiagnosticsLogger.error(error, context: "logout", category: .auth)
        }

        self.currentUser = nil
        self.state = .unauthenticated
    }

    // MARK: - Device Flow Implementation

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: OAuthConfig.deviceCodeUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let scopeEncoded = OAuthConfig.scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? OAuthConfig.scope
        let body = "client_id=\(OAuthConfig.clientId)&scope=\(scopeEncoded)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw GitHubError.authenticationFailed("Failed to request device code")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForAuthorization(deviceCode: String, interval: Int) async {
        var pollInterval = interval

        pollingTask = Task {
            while !Task.isCancelled {
                // Wait for the specified interval
                try? await Task.sleep(for: .seconds(pollInterval))

                if Task.isCancelled { break }

                do {
                    let result = try await checkAuthorization(deviceCode: deviceCode)

                    switch result {
                    case let .success(tokenResponse):
                        // Success! Save token and update state
                        try self.keychainManager.saveAccessToken(tokenResponse.accessToken)
                        self.state = .authenticated(tokenResponse.accessToken)
                        DiagnosticsLogger.info("Successfully authenticated via Device Flow", category: .auth)
                        await self.validateToken()
                        return

                    case let .pending(newInterval):
                        // User hasn't authorized yet, keep polling
                        if let newInterval {
                            pollInterval = newInterval
                        }

                    case .expired:
                        self.state = .error("Authorization expired. Please try again.")
                        return

                    case let .error(message):
                        self.state = .error(message)
                        return
                    }

                } catch {
                    DiagnosticsLogger.error(error, context: "pollForAuthorization", category: .auth)
                    self.state = .error(error.localizedDescription)
                    return
                }
            }
        }

        await pollingTask?.value
    }

    private func checkAuthorization(deviceCode: String) async throws -> AuthorizationResult {
        var request = URLRequest(url: URL(string: OAuthConfig.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(OAuthConfig.clientId)",
            "device_code=\(deviceCode)",
            "grant_type=urn:ietf:params:oauth:grant-type:device_code",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        // Parse response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Check for error response first
        if let errorResponse = try? decoder.decode(DeviceFlowError.self, from: data) {
            switch errorResponse.error {
            case "authorization_pending":
                return .pending(nil)

            case "slow_down":
                // Add 5 seconds to interval as per spec
                let newInterval = (errorResponse.interval ?? 5) + 5
                return .pending(newInterval)

            case "expired_token":
                return .expired

            case "access_denied":
                return .error("Access denied. User cancelled authorization.")

            default:
                return .error(errorResponse.errorDescription ?? errorResponse.error)
            }
        }

        // Try to parse success response
        if httpResponse.statusCode == 200 {
            let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
            return .success(tokenResponse)
        }

        throw GitHubError.authenticationFailed("Unexpected response: \(httpResponse.statusCode)")
    }

    // MARK: - Token Validation

    private func validateToken() async {
        guard case let .authenticated(token) = state else { return }

        DiagnosticsLogger.info("Validating token", category: .auth)

        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                self.currentUser = try decoder.decode(GitHubUser.self, from: data)
                DiagnosticsLogger.info(
                    "Token valid, user: \(self.currentUser?.login ?? "unknown")",
                    category: .auth
                )

            case 401, 403:
                DiagnosticsLogger.warning("Token invalid or expired", category: .auth)
                try? self.keychainManager.clearAll()
                self.state = .unauthenticated

            default:
                throw GitHubError.httpError(httpResponse.statusCode)
            }

        } catch {
            DiagnosticsLogger.error(error, context: "validateToken", category: .auth)
            // Don't log out on network errors, just log the issue
        }
    }
}

// MARK: - Response Types

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
}

private struct DeviceFlowError: Decodable {
    let error: String
    let errorDescription: String?
    let interval: Int?
}

private enum AuthorizationResult {
    case success(TokenResponse)
    case pending(Int?) // optional new interval
    case expired
    case error(String)
}
