import Foundation

/// Represents a GitHub repository from the notifications API.
struct Repository: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let nodeId: String
    let name: String
    let fullName: String
    let owner: RepositoryOwner
    let isPrivate: Bool
    let htmlUrl: String
    let description: String?
    let fork: Bool
    let url: String

    enum CodingKeys: String, CodingKey {
        case id
        case nodeId = "node_id"
        case name
        case fullName = "full_name"
        case owner
        case isPrivate = "private"
        case htmlUrl = "html_url"
        case description
        case fork
        case url
    }

    // MARK: - Hashable (use only stable identifier)

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }

    // MARK: - Equatable (use only stable identifier)

    static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.id == rhs.id
    }
}

/// Owner of a GitHub repository.
struct RepositoryOwner: Codable, Sendable, Hashable {
    let login: String
    let id: Int
    let nodeId: String
    let avatarUrl: String
    let url: String
    let htmlUrl: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case login
        case id
        case nodeId = "node_id"
        case avatarUrl = "avatar_url"
        case url
        case htmlUrl = "html_url"
        case type
    }

    // MARK: - Hashable (use only stable identifier)

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }

    // MARK: - Equatable (use only stable identifier)

    static func == (lhs: RepositoryOwner, rhs: RepositoryOwner) -> Bool {
        lhs.id == rhs.id
    }
}
