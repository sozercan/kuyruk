import SwiftUI

/// Sidebar view with smart filters and repository list.
struct SidebarView: View {
    @Environment(NotificationsViewModel.self) private var viewModel
    @Environment(SyncService.self) private var syncService

    private let filterGridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            self.destinationPicker
            self.filterCardsGrid
            self.repositoriesList(selection: self.notificationSelection)

            // Sync status at bottom
            SyncStatusBar()
        }
        .navigationTitle("Kuyruk")
        .frame(minWidth: 220)
    }

    // MARK: - Filter Cards Grid

    private var filterCardsGrid: some View {
        self.filterGridContent(selection: self.notificationSelection)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private var destinationPicker: some View {
        Picker("Destination", selection: self.appDestinationSelection) {
            ForEach(AppDestination.allCases) { destination in
                Label(destination.displayName, systemImage: destination.iconName)
                    .tag(destination)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func filterGridContent(selection: Binding<NotificationFilter?>) -> some View {
        LazyVGrid(columns: self.filterGridColumns, spacing: 8) {
            ForEach(NotificationFilter.smartFilters) { filter in
                FilterCardView(
                    filter: filter,
                    count: self.count(for: filter),
                    isSelected: selection.wrappedValue == filter)
                    .onTapGesture {
                        selection.wrappedValue = filter
                    }
            }
        }
    }

    // MARK: - Repositories List

    private func repositoriesList(selection: Binding<NotificationFilter?>) -> some View {
        List(selection: selection) {
            if !self.viewModel.repositories.isEmpty {
                Section("Repositories") {
                    ForEach(self.viewModel.repositories, id: \.id) { repo in
                        self.repositoryRow(for: repo)
                            .tag(NotificationFilter.repository(repo))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func repositoryRow(for repo: Repository) -> some View {
        HStack(spacing: 8) {
            AvatarView(url: repo.owner.avatarUrl, size: 20)

            Text(repo.name)
                .lineLimit(1)

            Spacer()

            let count = self.repositoryUnreadCount(repo)
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    // MARK: - Helpers

    private var appDestinationSelection: Binding<AppDestination> {
        Binding(
            get: { self.viewModel.appDestination },
            set: { destination in
                switch destination {
                case .notifications:
                    self.viewModel.showNotifications()
                case .digest:
                    self.viewModel.showDigest()
                }
            })
    }

    private var notificationSelection: Binding<NotificationFilter?> {
        Binding(
            get: {
                guard self.viewModel.appDestination == .notifications else { return nil }
                return self.viewModel.selectedFilter
            },
            set: { filter in
                guard let filter else { return }
                self.viewModel.selectFilter(filter)
            })
    }

    private func count(for filter: NotificationFilter) -> Int {
        self.viewModel.notifications.count(where: { filter.matches($0) })
    }

    private func repositoryUnreadCount(_ repo: Repository) -> Int {
        self.viewModel.notifications.count(where: { $0.repository.id == repo.id && $0.unread })
    }
}

#Preview {
    // Preview requires mock services - shown as placeholder
    Text("SidebarView Preview - requires NotificationsViewModel and SyncService environments")
        .frame(width: 250, height: 400)
}
