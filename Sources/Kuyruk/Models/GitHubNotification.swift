import Foundation

/// The type of subject in a GitHub notification.
enum SubjectType: String, Codable, Sendable {
    case issue = "Issue"
    case pullRequest = "PullRequest"
    case commit = "Commit"
    case release = "Release"
    case discussion = "Discussion"
    case repositoryVulnerabilityAlert = "RepositoryVulnerabilityAlert"
    case checkSuite = "CheckSuite"
    case unknown

    /// SF Symbol icon name for this subject type
    var iconName: String {
        switch self {
        case .issue:
            "circle.dotted"
        case .pullRequest:
            "arrow.triangle.merge"
        case .commit:
            "point.3.filled.connected.trianglepath.dotted"
        case .release:
            "tag"
        case .discussion:
            "bubble.left.and.bubble.right"
        case .repositoryVulnerabilityAlert:
            "exclamationmark.shield"
        case .checkSuite:
            "checkmark.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = SubjectType(rawValue: rawValue) ?? .unknown
    }
}

/// The subject of a GitHub notification (issue, PR, etc.).
struct NotificationSubject: Codable, Sendable, Hashable {
    let title: String
    let url: String?
    let latestCommentUrl: String?
    let type: SubjectType

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case latestCommentUrl = "latest_comment_url"
        case type
    }
}

/// Represents a GitHub notification from the API.
struct GitHubNotification: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let repository: Repository
    let subject: NotificationSubject
    let reason: NotificationReason
    let unread: Bool
    let updatedAt: Date
    let lastReadAt: Date?
    let url: String
    let subscriptionUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case repository
        case subject
        case reason
        case unread
        case updatedAt = "updated_at"
        case lastReadAt = "last_read_at"
        case url
        case subscriptionUrl = "subscription_url"
    }
}

// MARK: - Convenience Extensions

extension GitHubNotification {
    /// Extracts the issue/PR number from the subject URL, if available.
    var subjectNumber: Int? {
        guard let url = subject.url else { return nil }
        let components = url.split(separator: "/")
        return components.last.flatMap { Int($0) }
    }

    /// Returns the web URL for opening in browser.
    var webUrl: URL? {
        // Convert API URL to web URL
        // API: https://api.github.com/repos/owner/repo/issues/123
        // Web: https://github.com/owner/repo/issues/123

        // For releases, the API URL uses the release ID but the web URL needs the tag name
        // API: https://api.github.com/repos/owner/repo/releases/270883206
        // Web: https://github.com/owner/repo/releases/tag/v0.26.3
        // The tag name is the subject title for releases
        if self.subject.type == .release {
            // URL-encode the tag name to handle special characters
            let tagName = self.subject.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? self.subject.title
            return URL(string: "https://github.com/\(self.repository.fullName)/releases/tag/\(tagName)")
        }

        guard let apiUrl = subject.url else { return nil }

        let webUrlString = apiUrl
            .replacingOccurrences(of: "api.github.com/repos", with: "github.com")
            .replacingOccurrences(of: "/pulls/", with: "/pull/")

        return URL(string: webUrlString)
    }
}
