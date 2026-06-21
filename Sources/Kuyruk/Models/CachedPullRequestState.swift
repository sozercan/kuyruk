import Foundation
import SwiftData

/// SwiftData model caching a pull request's resolution state, so the Digest can
/// hide already merged/closed PRs from "Recommended Actions" without refetching.
@Model
final class CachedPullRequestState {
    /// Unique identifier matching the notification ID.
    @Attribute(.unique) var notificationId: String

    /// The notification's `updatedAt` when this state was fetched (cache invalidation key).
    var notificationUpdatedAt: Date

    /// Raw `PullRequestStatus` value (open / closed / merged).
    var statusRaw: String

    /// Whether the pull request is a draft.
    var isDraft: Bool

    /// When this state was fetched.
    var fetchedAt: Date

    init(
        notificationId: String,
        notificationUpdatedAt: Date,
        status: PullRequestStatus,
        isDraft: Bool) {
        self.notificationId = notificationId
        self.notificationUpdatedAt = notificationUpdatedAt
        self.statusRaw = status.rawValue
        self.isDraft = isDraft
        self.fetchedAt = Date()
    }

    /// The decoded resolution status (defaults to `.open` for unknown raw values).
    var status: PullRequestStatus {
        PullRequestStatus(rawValue: self.statusRaw) ?? .open
    }

    /// Whether the cached pull request is resolved (merged or closed).
    var isResolved: Bool {
        self.status.isResolved
    }

    /// Whether the cached state is still valid for the given notification.
    ///
    /// State is valid while the notification has not been updated since it was fetched.
    func isValid(for notification: GitHubNotification) -> Bool {
        self.notificationUpdatedAt >= notification.updatedAt
    }
}
