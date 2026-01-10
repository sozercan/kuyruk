import SwiftUI

/// A Reminders-style filter card with colored background, icon, count, and label.
struct FilterCardView: View {
    let filter: NotificationFilter
    let count: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                self.iconView
                Spacer()
                self.countView
            }

            Spacer()

            Text(self.filter.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(12)
        .frame(minWidth: 80, idealWidth: 100, maxWidth: .infinity, minHeight: 80, idealHeight: 90, maxHeight: 100)
        .background(self.filter.color.gradient, in: RoundedRectangle(cornerRadius: 14))
        .overlay(self.selectionOverlay)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var iconView: some View {
        Image(systemName: self.filter.iconName)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var countView: some View {
        Text("\(self.count)")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if self.isSelected {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.5), lineWidth: 3)
        }
    }
}

// MARK: - Filter Color Extension

extension NotificationFilter {
    /// The color associated with this filter, inspired by Reminders app.
    var color: Color {
        switch self {
        case .inbox:
            Color(red: 0.55, green: 0.55, blue: 0.58) // Gray like "All"
        case .unread:
            Color(red: 0.25, green: 0.47, blue: 0.85) // Blue like "Today"
        case .participating:
            Color(red: 0.30, green: 0.75, blue: 0.55) // Green like "Assigned"
        case .mentioned:
            Color(red: 0.95, green: 0.60, blue: 0.35) // Orange like "Flagged"
        case .assigned:
            Color(red: 0.70, green: 0.45, blue: 0.85) // Purple
        case .reviewRequested:
            Color(red: 0.90, green: 0.45, blue: 0.50) // Coral/Red like "Scheduled"
        case .snoozed:
            Color(red: 0.95, green: 0.70, blue: 0.30) // Warm orange/amber for snoozed
        case .repository:
            Color(red: 0.35, green: 0.65, blue: 0.80) // Cyan
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        FilterCardView(filter: .inbox, count: 42, isSelected: false)
        FilterCardView(filter: .unread, count: 8, isSelected: true)
        FilterCardView(filter: .mentioned, count: 3, isSelected: false)
    }
    .padding()
    .frame(width: 320)
}
