import Foundation

/// Represents the app's top-level content areas.
enum AppDestination: String, CaseIterable, Hashable, Identifiable {
    case notifications
    case digest

    var id: String {
        self.rawValue
    }

    /// Display name for the destination.
    var displayName: String {
        switch self {
        case .notifications:
            "Notifications"
        case .digest:
            "Digest"
        }
    }

    /// SF Symbol icon name.
    var iconName: String {
        switch self {
        case .notifications:
            "tray"
        case .digest:
            "newspaper"
        }
    }
}
