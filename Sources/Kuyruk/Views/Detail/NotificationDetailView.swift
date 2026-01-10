import SwiftUI

/// Detail view for a selected notification.
struct NotificationDetailView: View {
    @Environment(NotificationsViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let notification = viewModel.selectedNotification {
                self.detailContent(for: notification)
                    .id(notification.id)
            } else {
                self.emptyState
            }
        }
        .frame(minWidth: 300)
        .animation(.easeInOut(duration: 0.15), value: self.viewModel.selectedNotification?.id)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Select a Notification", systemImage: "bell")
        } description: {
            Text("Choose a notification from the list to view details")
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(for notification: GitHubNotification) -> some View {
        ScrollView {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 24) {
                    self.detailSections(for: notification)
                }
            } else {
                self.detailSections(for: notification)
            }
        }
        .navigationTitle(notification.repository.name)
    }

    @ViewBuilder
    private func detailSections(for notification: GitHubNotification) -> some View {
        VStack(spacing: 24) {
            // Header
            self.headerSection(for: notification)

            Divider()

            // Info section
            self.infoSection(for: notification)

            Divider()

            // Actions
            self.actionsSection(for: notification)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Header Section

    @ViewBuilder
    private func headerSection(for notification: GitHubNotification) -> some View {
        VStack(spacing: 16) {
            // Subject type icon
            SubjectTypeBadge(type: notification.subject.type)
                .font(.system(size: 48))

            // Title
            Text(notification.subject.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Repository
            HStack(spacing: 8) {
                AvatarView(url: notification.repository.owner.avatarUrl, size: 24)

                Text(notification.repository.fullName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Reason badge
            ReasonBadge(reason: notification.reason)
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private func infoSection(for notification: GitHubNotification) -> some View {
        // Note: Already inside GlassEffectContainer from detailContent,
        // so use regular background instead of glassEffect to avoid glass-on-glass
        self.infoGrid(for: notification)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func infoGrid(for notification: GitHubNotification) -> some View {
        VStack(spacing: 12) {
            self.infoRow(label: "Status", value: notification.unread ? "Unread" : "Read")
            self.infoRow(label: "Type", value: notification.subject.type.displayName)
            self.infoRow(label: "Reason", value: notification.reason.displayName)
            self.infoRow(
                label: "Updated",
                value: notification.updatedAt.formatted(date: .abbreviated, time: .shortened))

            if let number = notification.subjectNumber {
                self.infoRow(label: "Number", value: "#\(number)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private func actionsSection(for notification: GitHubNotification) -> some View {
        VStack(spacing: 12) {
            // Primary action - Open in Browser
            // Note: Use bordered styles inside GlassEffectContainer to avoid glass-on-glass
            Button {
                if let url = notification.webUrl {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            // Secondary actions
            HStack(spacing: 12) {
                Button {
                    Task {
                        await self.viewModel.markAsRead(notification)
                    }
                } label: {
                    Label("Mark as Read", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!notification.unread)
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button {
                    if let url = notification.webUrl {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                } label: {
                    Label("Copy Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

#Preview {
    // Preview requires mock services - shown as placeholder
    Text("NotificationDetailView Preview - requires NotificationsViewModel environment")
        .frame(width: 400, height: 500)
}
