import SwiftUI

/// Badge displaying the subject type (Issue, PR, etc.) with icon.
struct SubjectTypeBadge: View {
    let type: SubjectType

    var body: some View {
        Image(systemName: self.type.iconName)
            .font(.title3)
            .foregroundStyle(self.tintColor)
            .help(self.type.displayName)
    }

    private var tintColor: Color {
        switch self.type {
        case .issue:
            .green
        case .pullRequest:
            .purple
        case .commit:
            .blue
        case .release:
            .orange
        case .discussion:
            .cyan
        case .repositoryVulnerabilityAlert:
            .red
        case .checkSuite:
            .yellow
        case .unknown:
            .secondary
        }
    }
}

extension SubjectType {
    var displayName: String {
        switch self {
        case .issue:
            "Issue"
        case .pullRequest:
            "Pull Request"
        case .commit:
            "Commit"
        case .release:
            "Release"
        case .discussion:
            "Discussion"
        case .repositoryVulnerabilityAlert:
            "Security Alert"
        case .checkSuite:
            "Check Suite"
        case .unknown:
            "Unknown"
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        SubjectTypeBadge(type: .issue)
        SubjectTypeBadge(type: .pullRequest)
        SubjectTypeBadge(type: .commit)
        SubjectTypeBadge(type: .release)
    }
    .padding()
}
