import Foundation

/// Represents a model from the GitHub Models catalog.
struct GitHubModel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let publisher: String
    let summary: String?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case publisher
        case summary
        case rateLimitTier = "rate_limit_tier"
    }
}

// MARK: - Display Helpers

extension GitHubModel {
    /// Human-readable display name combining publisher and model name.
    var displayName: String {
        "\(self.publisher)/\(self.name)"
    }

    /// Whether this is a low-tier model (suitable for frequent summaries).
    var isLowTier: Bool {
        self.rateLimitTier?.lowercased() == "low"
    }
}
