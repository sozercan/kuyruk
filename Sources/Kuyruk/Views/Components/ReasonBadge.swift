import SwiftUI

/// Badge displaying the notification reason with appropriate styling.
struct ReasonBadge: View {
    let reason: NotificationReason

    var body: some View {
        Label(self.reason.displayName, systemImage: self.reason.iconName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(self.tintColor)
            .background(self.tintColor.opacity(0.15), in: Capsule())
    }

    private var tintColor: Color {
        switch self.reason {
        case .reviewRequested:
            .orange
        case .mention,
             .teamMention:
            .blue
        case .assign:
            .green
        case .ciActivity:
            .purple
        case .author:
            .indigo
        case .comment:
            .cyan
        case .stateChange:
            .pink
        default:
            .secondary
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ReasonBadge(reason: .reviewRequested)
        ReasonBadge(reason: .mention)
        ReasonBadge(reason: .assign)
        ReasonBadge(reason: .ciActivity)
    }
    .padding()
}
