import Foundation

/// The backend used for AI analyses.
enum AIBackend: String, CaseIterable, Identifiable {
    /// GitHub Models API (default). Uses the user's GitHub OAuth token.
    case githubModels

    /// A user-supplied OpenAI-compatible endpoint (e.g. a local vekil proxy).
    case custom

    var id: String {
        self.rawValue
    }

    /// Display name for the backend.
    var displayName: String {
        switch self {
        case .githubModels:
            "GitHub Models"
        case .custom:
            "Custom (OpenAI-compatible)"
        }
    }
}
