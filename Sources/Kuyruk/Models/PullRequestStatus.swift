import Foundation

/// The resolution state of a pull request.
enum PullRequestStatus: String, Codable {
    case open
    case closed
    case merged

    /// Whether the pull request no longer needs action (merged or closed).
    var isResolved: Bool {
        switch self {
        case .open:
            false
        case .closed,
             .merged:
            true
        }
    }
}

/// Minimal decode of `GET /repos/{owner}/{repo}/pulls/{number}` for resolution state.
struct PullRequestStateResponse: Decodable {
    let state: String
    let merged: Bool?
    let draft: Bool?

    enum CodingKeys: String, CodingKey {
        case state
        case merged
        case draft
    }

    /// Maps the raw API fields to a resolution status.
    ///
    /// A merged PR reports `state == "closed"` with `merged == true`, so the
    /// merge flag is checked first.
    var status: PullRequestStatus {
        if self.merged == true {
            return .merged
        }

        return self.state.lowercased() == "closed" ? .closed : .open
    }

    /// Whether the pull request is a draft.
    var isDraft: Bool {
        self.draft ?? false
    }
}
