import SwiftUI

/// Main notification list view with grouping and filtering.
struct NotificationListView: View {
    @Environment(NotificationsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = self.viewModel

        Group {
            if self.viewModel.isLoading, self.viewModel.notifications.isEmpty {
                self.loadingState
            } else if self.viewModel.error != nil, self.viewModel.notifications.isEmpty {
                self.errorState
            } else if self.viewModel.groupedNotifications.isEmpty {
                self.emptyState
            } else {
                self.notificationsList
            }
        }
        .navigationTitle(self.viewModel.selectedFilter.displayName)
        .searchable(text: $vm.searchText, prompt: "Search notifications")
        .toolbar {
            self.toolbarContent
        }
    }

    // MARK: - States

    @ViewBuilder
    private var loadingState: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
        } description: {
            Text("Loading notifications...")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(self.viewModel.selectedFilter.emptyStateTitle, systemImage: self.emptyStateIcon)
        } description: {
            if self.viewModel.searchText.isEmpty {
                Text(self.viewModel.selectedFilter.emptyStateDescription)
            } else {
                Text("No notifications match '\(self.viewModel.searchText)'")
            }
        } actions: {
            Button("Refresh") {
                Task {
                    await self.viewModel.refresh()
                }
            }
        }
    }

    /// Icon for the empty state based on current filter
    private var emptyStateIcon: String {
        switch self.viewModel.selectedFilter {
        case .inbox,
             .unread:
            "bell.slash"
        case .participating:
            "person.2.slash"
        case .mentioned:
            "at.badge.minus"
        case .assigned:
            "person.badge.minus"
        case .reviewRequested:
            "eye.slash"
        case .snoozed:
            "moon.zzz"
        case .repository:
            "folder.badge.minus"
        }
    }

    @ViewBuilder
    private var errorState: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            if let error = self.viewModel.error {
                Text(error.localizedDescription)
            } else {
                Text("An unexpected error occurred.")
            }
        } actions: {
            Button("Try Again") {
                self.viewModel.clearError()
                Task {
                    await self.viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Notifications List

    @ViewBuilder
    private var notificationsList: some View {
        List(selection: Binding(
            get: { self.viewModel.selectedNotification?.id },
            set: { id in
                self.viewModel.selectedNotification = self.viewModel.filteredNotifications.first { $0.id == id }
            })) {
                // Use pre-computed grouped notifications
                ForEach(self.viewModel.groupedNotifications, id: \.key) { repoName, notifications in
                    Section {
                        ForEach(notifications) { notification in
                            NotificationRowView(notification: notification)
                                .tag(notification.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        Task {
                                            await self.viewModel.markAsRead(notification)
                                        }
                                    } label: {
                                        Label("Mark Read", systemImage: "checkmark")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        if let url = notification.webUrl {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } label: {
                                        Label("Open", systemImage: "safari")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    self.contextMenu(for: notification)
                                }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            if let firstNotification = notifications.first {
                                AvatarView(url: firstNotification.repository.owner.avatarUrl, size: 16)
                            }
                            Text(repoName)
                                .font(.headline)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollClipDisabled()
            .scrollContentBackground(.visible)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .overlay(alignment: .top) {
                    // Show refreshing indicator at top when updating in background
                    if self.viewModel.isRefreshing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: self.viewModel.isRefreshing)
                    }
                }
    }

    @ViewBuilder
    private func contextMenu(for notification: GitHubNotification) -> some View {
        Button {
            if let url = notification.webUrl {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open in Browser", systemImage: "safari")
        }

        Button {
            Task {
                await self.viewModel.markAsRead(notification)
            }
        } label: {
            Label("Mark as Read", systemImage: "checkmark.circle")
        }
        .disabled(!notification.unread)

        Divider()

        Button {
            if let url = notification.webUrl {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        } label: {
            Label("Copy Link", systemImage: "link")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task {
                    await self.viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(self.viewModel.isLoading || self.viewModel.isRefreshing)
        }

        ToolbarItem(placement: .automatic) {
            if self.viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

#Preview {
    // Preview requires mock services - shown as placeholder
    Text("NotificationListView Preview - requires NotificationsViewModel environment")
        .frame(width: 400, height: 500)
}
