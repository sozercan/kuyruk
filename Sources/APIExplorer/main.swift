import Foundation

/// API Explorer - CLI tool for exploring GitHub API endpoints
/// Usage: swift run api-explorer <command> [options]
///
/// Commands:
///   auth              - Check authentication status
///   notifications     - List notifications
///   notification <id> - Get notification details
///   user              - Get current user info
///
/// Options:
///   -v, --verbose     - Show verbose output

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

    // MARK: - Helpers

    private static func getToken() -> String? {
        ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
    }

    private static func request(path: String, token: String) async throws -> (Data, URLResponse) {
        let url = URL(string: "https://api.github.com\(path)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        return try await URLSession.shared.data(for: request)
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
            auth              Check authentication status
            notifications     List notifications
            notification <id> Get notification thread details
            user              Get current user info
            help              Show this help message

        Options:
            -v, --verbose     Show verbose output (headers, raw JSON)

        Environment:
            GITHUB_TOKEN      GitHub personal access token (required)

        Examples:
            export GITHUB_TOKEN=ghp_your_token
            swift run api-explorer auth
            swift run api-explorer notifications -v
            swift run api-explorer notification 12345678
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
