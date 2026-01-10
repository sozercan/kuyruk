import SwiftUI

/// Snooze duration options for notifications.
enum SnoozeDuration: CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case threeHours
    case tomorrow
    case nextWeek
    case custom

    var id: String {
        switch self {
        case .thirtyMinutes:
            "30min"
        case .oneHour:
            "1hour"
        case .threeHours:
            "3hours"
        case .tomorrow:
            "tomorrow"
        case .nextWeek:
            "nextweek"
        case .custom:
            "custom"
        }
    }

    var displayName: String {
        switch self {
        case .thirtyMinutes:
            "30 minutes"
        case .oneHour:
            "1 hour"
        case .threeHours:
            "3 hours"
        case .tomorrow:
            "Tomorrow morning"
        case .nextWeek:
            "Next week"
        case .custom:
            "Custom..."
        }
    }

    var iconName: String {
        switch self {
        case .thirtyMinutes:
            "clock"
        case .oneHour:
            "clock.fill"
        case .threeHours:
            "clock.badge"
        case .tomorrow:
            "sun.horizon"
        case .nextWeek:
            "calendar"
        case .custom:
            "calendar.badge.clock"
        }
    }

    /// Returns the snooze end date for this duration.
    var snoozeUntil: Date? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .thirtyMinutes:
            return calendar.date(byAdding: .minute, value: 30, to: now)
        case .oneHour:
            return calendar.date(byAdding: .hour, value: 1, to: now)
        case .threeHours:
            return calendar.date(byAdding: .hour, value: 3, to: now)
        case .tomorrow:
            // Tomorrow at 9 AM
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
                return nil
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case .nextWeek:
            // Next Monday at 9 AM
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now),
                  let monday = calendar.nextDate(
                      after: nextWeek,
                      matching: DateComponents(weekday: 2),
                      matchingPolicy: .nextTime,
                      direction: .backward)
            else {
                return calendar.date(byAdding: .day, value: 7, to: now)
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday)
        case .custom:
            return nil
        }
    }

    /// Standard durations (excluding custom)
    static var standardDurations: [SnoozeDuration] {
        [.thirtyMinutes, .oneHour, .threeHours, .tomorrow, .nextWeek]
    }
}

/// A menu for snoozing notifications.
struct SnoozeMenu: View {
    let onSnooze: (Date) -> Void
    let onUnsnooze: (() -> Void)?

    @State private var showCustomPicker: Bool = false
    @State private var customDate: Date = .init().addingTimeInterval(3600)

    init(onSnooze: @escaping (Date) -> Void, onUnsnooze: (() -> Void)? = nil) {
        self.onSnooze = onSnooze
        self.onUnsnooze = onUnsnooze
    }

    var body: some View {
        Menu {
            ForEach(SnoozeDuration.standardDurations) { duration in
                Button {
                    if let snoozeDate = duration.snoozeUntil {
                        self.onSnooze(snoozeDate)
                    }
                } label: {
                    Label(duration.displayName, systemImage: duration.iconName)
                }
            }

            Divider()

            Button {
                self.showCustomPicker = true
            } label: {
                Label("Custom...", systemImage: "calendar.badge.clock")
            }

            if let onUnsnooze {
                Divider()

                Button(role: .destructive) {
                    onUnsnooze()
                } label: {
                    Label("Unsnooze", systemImage: "bell")
                }
            }
        } label: {
            Label("Snooze", systemImage: "moon.zzz")
        }
        .sheet(isPresented: self.$showCustomPicker) {
            self.customDatePickerSheet
        }
    }

    @ViewBuilder
    private var customDatePickerSheet: some View {
        VStack(spacing: 20) {
            Text("Snooze Until")
                .font(.headline)

            DatePicker(
                "Snooze until",
                selection: self.$customDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()

            HStack {
                Button("Cancel") {
                    self.showCustomPicker = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Snooze") {
                    self.onSnooze(self.customDate)
                    self.showCustomPicker = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

/// Badge showing when a notification is snoozed until.
struct SnoozedBadge: View {
    let snoozedUntil: Date

    private var timeRemaining: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self.snoozedUntil, relativeTo: Date())
    }

    var body: some View {
        Label {
            Text(self.timeRemaining)
                .font(.caption2)
        } icon: {
            Image(systemName: "moon.zzz.fill")
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.orange.opacity(0.15), in: Capsule())
    }
}

#Preview("Snooze Menu") {
    SnoozeMenu { date in
        print("Snoozed until: \(date)")
    }
    .padding()
}

#Preview("Snoozed Badge") {
    VStack(spacing: 10) {
        SnoozedBadge(snoozedUntil: Date().addingTimeInterval(1800))
        SnoozedBadge(snoozedUntil: Date().addingTimeInterval(3600))
        SnoozedBadge(snoozedUntil: Date().addingTimeInterval(86400))
    }
    .padding()
}
