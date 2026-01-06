import Foundation

/// Represents the reason why a user received a GitHub notification.
/// Maps to GitHub API's `reason` field.
enum NotificationReason: String, Codable, Sendable, CaseIterable, Identifiable {
    /// You were assigned to the issue/PR
    case assign

    /// You created the thread
    case author

    /// You commented on the thread
    case comment

    /// A GitHub Actions workflow run was triggered for your repository
    case ciActivity = "ci_activity"

    /// You accepted an invitation to contribute to the repository
    case invitation

    /// You subscribed to the thread via the GitHub UI or API
    case manual

    /// You were mentioned in the content
    case mention

    /// You, or a team you're a member of, were requested to review a PR
    case reviewRequested = "review_requested"

    /// You changed the thread state (e.g., closed or merged)
    case stateChange = "state_change"

    /// You're watching the repository
    case subscribed

    /// You were on a team that was mentioned
    case teamMention = "team_mention"

    /// Unknown reason (fallback for API changes)
    case unknown

    var id: String { self.rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .assign:
            "Assigned"
        case .author:
            "Author"
        case .comment:
            "Comment"
        case .ciActivity:
            "CI Activity"
        case .invitation:
            "Invitation"
        case .manual:
            "Subscribed"
        case .mention:
            "Mentioned"
        case .reviewRequested:
            "Review Requested"
        case .stateChange:
            "State Change"
        case .subscribed:
            "Watching"
        case .teamMention:
            "Team Mention"
        case .unknown:
            "Unknown"
        }
    }

    /// SF Symbol icon name for this reason
    var iconName: String {
        switch self {
        case .assign:
            "person.badge.plus"
        case .author:
            "pencil"
        case .comment:
            "bubble.left"
        case .ciActivity:
            "gearshape.2"
        case .invitation:
            "envelope"
        case .manual:
            "bell"
        case .mention:
            "at"
        case .reviewRequested:
            "eye"
        case .stateChange:
            "arrow.triangle.2.circlepath"
        case .subscribed:
            "star"
        case .teamMention:
            "person.3"
        case .unknown:
            "questionmark.circle"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = NotificationReason(rawValue: rawValue) ?? .unknown
    }
}
