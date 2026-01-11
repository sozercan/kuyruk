import Foundation

/// API Explorer - CLI tool for exploring GitHub API endpoints
/// Usage: swift run api-explorer <command> [options]
///
/// Commands:
///   auth                   - Check authentication status
///   notifications          - List notifications
///   notification <id>      - Get notification details
///   user                   - Get current user info
///   models                 - List available GitHub Models
///   models-chat <prompt>   - Test chat completion with GitHub Models
///
/// Options:
///   -v, --verbose          - Show verbose output

@main
struct APIExplorer {
    static func main() async {
        let arguments = CommandLine.arguments

        guard arguments.count > 1 else {
            Self.printUsage()
            return
        }

        let command = arguments[1]
        let verbose = arguments.contains("-v") || arguments.contains("--verbose")

        switch command {
        case "auth":
            await Self.checkAuth(verbose: verbose)

        case "notifications":
            await Self.listNotifications(verbose: verbose)

        case "notification":
            guard arguments.count > 2 else {
                print("❌ Error: Missing notification ID")
                print("Usage: api-explorer notification <thread_id>")
                return
            }
            await Self.getNotification(id: arguments[2], verbose: verbose)

        case "user":
            await Self.getCurrentUser(verbose: verbose)

        case "models":
            await Self.listModels(verbose: verbose)

        case "models-chat":
            guard arguments.count > 2 else {
                print("❌ Error: Missing prompt")
                print("Usage: api-explorer models-chat <prompt>")
                return
            }
            // Collect all remaining arguments as the prompt (allows multi-word prompts)
            let promptArgs = arguments.dropFirst(2).filter { !$0.hasPrefix("-") }
            let prompt = promptArgs.joined(separator: " ")
            await Self.chatCompletion(prompt: prompt, verbose: verbose)

        case "help",
             "-h",
             "--help":
            Self.printUsage()

        default:
            print("❌ Unknown command: \(command)")
            Self.printUsage()
        }
    }

    // MARK: - Commands

    private static func checkAuth(verbose _: Bool) async {
        print("🔑 Checking authentication...\n")

        guard let token = getToken() else {
            print("❌ No token found")
            print("\nTo authenticate, set the GITHUB_TOKEN environment variable:")
            print("  export GITHUB_TOKEN=ghp_your_token_here")
            return
        }

        print("✅ Token found: \(String(token.prefix(10)))...")

        // Validate token
        do {
            let (data, response) = try await request(
                path: "/user",
                token: token)

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    if let user = try? JSONDecoder().decode(UserResponse.self, from: data) {
                        print("✅ Authenticated as: @\(user.login)")
                    }
                } else {
                    print("❌ Token is invalid or expired")
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }

    private static func listNotifications(verbose: Bool) async {
        print("📬 Fetching notifications...\n")

        guard let token = getToken() else {
            print("❌ No token found. Set GITHUB_TOKEN environment variable.")
            return
        }

        do {
            let (data, response) = try await request(
                path: "/notifications",
                token: token)

            if verbose {
                self.printResponseHeaders(response)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let notifications = try decoder.decode([NotificationResponse].self, from: data)

            print("Found \(notifications.count) notifications:\n")

            for notification in notifications {
                let unreadIcon = notification.unread ? "🔵" : "⚪️"
                print("\(unreadIcon) [\(notification.id)] \(notification.subject.title)")
                print("   📦 \(notification.repository.full_name)")
                print("   📝 \(notification.reason) • \(notification.subject.type)")
                print("")
            }

            if verbose {
                print("\n📄 Raw JSON:")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }

    private static func getNotification(id: String, verbose: Bool) async {
        print("📬 Fetching notification \(id)...\n")

        guard let token = getToken() else {
            print("❌ No token found. Set GITHUB_TOKEN environment variable.")
            return
        }

        do {
            let (data, response) = try await request(
                path: "/notifications/threads/\(id)",
                token: token)

            if verbose {
                self.printResponseHeaders(response)
            }

            print("📄 Response:")
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }

    private static func getCurrentUser(verbose: Bool) async {
        print("👤 Fetching current user...\n")

        guard let token = getToken() else {
            print("❌ No token found. Set GITHUB_TOKEN environment variable.")
            return
        }

        do {
            let (data, response) = try await request(
                path: "/user",
                token: token)

            if verbose {
                self.printResponseHeaders(response)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let user = try decoder.decode(UserResponse.self, from: data)

            print("👤 User: \(user.name ?? user.login)")
            print("   📛 Login: @\(user.login)")
            print("   📧 Email: \(user.email ?? "N/A")")
            print("   📍 Bio: \(user.bio ?? "N/A")")
            print("   📦 Public Repos: \(user.public_repos)")
            print("   👥 Followers: \(user.followers)")
            print("   👣 Following: \(user.following)")

            if verbose {
                print("\n📄 Raw JSON:")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }

    // MARK: - GitHub Models Commands

    private static func listModels(verbose: Bool) async {
        print("🤖 Fetching available GitHub Models...\n")

        guard let token = getToken() else {
            print("❌ No token found. Set GITHUB_TOKEN environment variable.")
            return
        }

        do {
            let (data, response) = try await modelsRequest(
                path: "/catalog/models",
                method: "GET",
                body: nil,
                token: token,
                verbose: verbose)

            Self.printRateLimitInfo(response)

            if verbose {
                Self.printResponseHeaders(response)
            }

            let decoder = JSONDecoder()
            let models = try decoder.decode([ModelsResponse].self, from: data)

            print("Found \(models.count) models:\n")

            for model in models {
                print("📦 \(model.name)")
                print("   Publisher: \(model.publisher)")
                if let displayName = model.displayName {
                    print("   Display: \(displayName)")
                }
                if let modelType = model.modelType {
                    print("   Type: \(modelType)")
                }
                print("")
            }

            if verbose {
                print("\n📄 Raw JSON:")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }

    private static func chatCompletion(prompt: String, verbose: Bool) async {
        print("💬 Testing chat completion...\n")
        print("📝 Prompt: \(prompt)\n")

        guard let token = getToken() else {
            print("❌ No token found. Set GITHUB_TOKEN environment variable.")
            return
        }

        // Build request body
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": prompt],
            ],
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
            print("❌ Failed to serialize request body")
            return
        }

        do {
            let (data, response) = try await modelsRequest(
                path: "/inference/chat/completions",
                method: "POST",
                body: bodyData,
                token: token,
                verbose: verbose)

            Self.printRateLimitInfo(response)

            if verbose {
                Self.printResponseHeaders(response)
            }

            // Parse response
            let decoder = JSONDecoder()
            let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

            if let firstChoice = chatResponse.choices.first {
                print("🤖 Response:")
                print("─────────────────────────────────────")
                print(firstChoice.message.content)
                print("─────────────────────────────────────")

                if let usage = chatResponse.usage {
                    print("\n📊 Token Usage:")
                    print("   Prompt tokens: \(usage.promptTokens)")
                    print("   Completion tokens: \(usage.completionTokens)")
                    print("   Total tokens: \(usage.totalTokens)")
                }
            }

            if verbose {
                print("\n📄 Raw JSON:")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }

    // MARK: - Helpers

    private static func getToken() -> String? {
        ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
    }

    private static func request(path: String, token: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw APIExplorerError.invalidURL("https://api.github.com\(path)")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        return try await URLSession.shared.data(for: request)
    }

    private static func modelsRequest(
        path: String,
        method: String,
        body: Data?,
        token: String,
        verbose: Bool) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "https://models.github.ai\(path)") else {
            throw APIExplorerError.invalidURL("https://models.github.ai\(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        // Use a custom session delegate to capture certificate info in verbose mode
        let session: URLSession
        if verbose {
            let delegate = CertificateLoggingDelegate()
            session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            session = URLSession.shared
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIExplorerError.invalidResponse
        }

        // Check for error status codes
        if httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ HTTP \(httpResponse.statusCode): \(errorBody)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                print("\n⚠️  Your token may not have access to GitHub Models.")
                print("   Ensure your token has the required scopes.")
            }
        }

        return (data, httpResponse)
    }

    private static func printRateLimitInfo(_ response: HTTPURLResponse) {
        print("📊 Rate Limit Info:")
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            print("   Remaining: \(remaining)")
        }
        if let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit") {
            print("   Limit: \(limit)")
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset") {
            if let timestamp = Double(reset) {
                let date = Date(timeIntervalSince1970: timestamp)
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                print("   Reset: \(formatter.string(from: date))")
            }
        }
        print("")
    }

    private static func printResponseHeaders(_ response: URLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        print("📡 Response Headers:")
        print("   Status: \(httpResponse.statusCode)")

        if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
            print("   Rate Limit Remaining: \(remaining)")
        }
        if let reset = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset") {
            if let timestamp = Double(reset) {
                let date = Date(timeIntervalSince1970: timestamp)
                print("   Rate Limit Reset: \(date)")
            }
        }
        print("")
    }

    private static func printUsage() {
        print("""
        API Explorer - GitHub API exploration tool for Kuyruk

        Usage: api-explorer <command> [options]

        Commands:
            auth                   Check authentication status
            notifications          List notifications
            notification <id>      Get notification thread details
            user                   Get current user info
            models                 List available GitHub Models
            models-chat <prompt>   Test chat completion with GitHub Models
            help                   Show this help message

        Options:
            -v, --verbose          Show verbose output (headers, raw JSON, cert info)

        Environment:
            GITHUB_TOKEN           GitHub personal access token (required)

        Examples:
            export GITHUB_TOKEN=ghp_your_token
            swift run api-explorer auth
            swift run api-explorer notifications -v
            swift run api-explorer notification 12345678
            swift run api-explorer models -v
            swift run api-explorer models-chat "Hello, how are you?"
        """)
    }
}

// MARK: - Response Models

private struct NotificationResponse: Decodable {
    let id: String
    let repository: RepositoryResponse
    let subject: SubjectResponse
    let reason: String
    let unread: Bool
    let updated_at: String
    let url: String
}

private struct RepositoryResponse: Decodable {
    let id: Int
    let name: String
    let full_name: String
}

private struct SubjectResponse: Decodable {
    let title: String
    let url: String?
    let type: String
}

private struct UserResponse: Decodable {
    let id: Int
    let login: String
    let name: String?
    let email: String?
    let bio: String?
    let public_repos: Int
    let followers: Int
    let following: Int
}

// MARK: - GitHub Models Response Models

private struct ModelsResponse: Decodable {
    let name: String
    let displayName: String?
    let publisher: String
    let modelType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "friendly_name"
        case publisher
        case modelType = "model_type"
    }
}

private struct ChatCompletionResponse: Decodable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int?
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Errors

private enum APIExplorerError: Error, CustomStringConvertible {
    case invalidResponse
    case invalidURL(String)

    var description: String {
        switch self {
        case .invalidResponse:
            "Invalid response from server"
        case let .invalidURL(urlString):
            "Invalid URL: \(urlString)"
        }
    }
}

// MARK: - Certificate Logging Delegate

/// URLSession delegate that logs certificate information for pin discovery
private final class CertificateLoggingDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        print("\n🔐 Certificate Info for \(host):")

        // Get certificate chain
        if let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            for (index, certificate) in certificateChain.enumerated() {
                let certData = SecCertificateCopyData(certificate) as Data

                // Get subject summary
                let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
                print("   [\(index)] \(summary)")

                // Calculate SPKI hash for pinning
                if let spkiHash = Self.calculateSPKIHash(from: certData) {
                    print("       SPKI SHA-256: \(spkiHash)")
                }
            }
        }
        print("")

        // Allow the connection to proceed
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }

    /// Calculate SPKI (Subject Public Key Info) SHA-256 hash for certificate pinning
    private static func calculateSPKIHash(from certData: Data) -> String? {
        // Create a certificate from the data
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            return nil
        }

        // Extract the public key
        var publicKey: SecKey?
        if #available(macOS 10.14, *) {
            publicKey = SecCertificateCopyKey(certificate)
        }

        guard let key = publicKey,
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else {
            return nil
        }

        // Hash the public key data
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return Data(hash).base64EncodedString()
    }
}

// Import CommonCrypto for SHA256
import CommonCrypto
