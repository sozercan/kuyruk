import Foundation

/// Represents a filter for displaying notifications.
enum NotificationFilter: Hashable, Identifiable, Sendable {
    // Smart filters
    case inbox
    case unread
    case participating
    case mentioned
    case assigned
    case reviewRequested

    // Repository filter
    case repository(Repository)

    var id: String {
        switch self {
        case .inbox:
            "inbox"
        case .unread:
            "unread"
        case .participating:
            "participating"
        case .mentioned:
            "mentioned"
        case .assigned:
            "assigned"
        case .reviewRequested:
            "review_requested"
        case let .repository(repo):
            "repo_\(repo.id)"
        }
    }

    /// Display name for the filter
    var displayName: String {
        switch self {
        case .inbox:
            "Inbox"
        case .unread:
            "Unread"
        case .participating:
            "Participating"
        case .mentioned:
            "Mentioned"
        case .assigned:
            "Assigned"
        case .reviewRequested:
            "Review Requested"
        case let .repository(repo):
            repo.name
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .inbox:
            "tray"
        case .unread:
            "circle.fill"
        case .participating:
            "person.2"
        case .mentioned:
            "at"
        case .assigned:
            "person.badge.plus"
        case .reviewRequested:
            "eye"
        case .repository:
            "folder"
        }
    }

    /// Returns the smart filters for the sidebar
    static var smartFilters: [NotificationFilter] {
        [.inbox, .unread, .participating, .mentioned, .assigned, .reviewRequested]
    }

    /// Checks if a notification matches this filter
    func matches(_ notification: GitHubNotification) -> Bool {
        switch self {
        case .inbox:
            // Inbox shows only unread notifications (like GitHub's default view)
            notification.unread
        case .unread:
            notification.unread
        case .participating:
            [.author, .comment, .mention, .teamMention, .reviewRequested, .assign]
                .contains(notification.reason)
        case .mentioned:
            notification.reason == .mention || notification.reason == .teamMention
        case .assigned:
            notification.reason == .assign
        case .reviewRequested:
            notification.reason == .reviewRequested
        case let .repository(repo):
            notification.repository.id == repo.id
        }
    }
}
