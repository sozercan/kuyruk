import SwiftUI

/// Sidebar view with smart filters and repository list.
struct SidebarView: View {
    @Environment(NotificationsViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = self.viewModel

        List(selection: $vm.selectedFilter) {
            self.smartFiltersSection
            self.repositoriesSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Kuyruk")
        .frame(minWidth: 200)
    }

    // MARK: - Sections

    @ViewBuilder
    private var smartFiltersSection: some View {
        Section("Filters") {
            self.filtersList
        }
    }

    @ViewBuilder
    private var filtersList: some View {
        ForEach(NotificationFilter.smartFilters) { filter in
            self.filterRow(for: filter)
                .tag(filter)
        }
    }

    @ViewBuilder
    private func filterRow(for filter: NotificationFilter) -> some View {
        let count = self.count(for: filter)

        HStack {
            Label(filter.displayName, systemImage: filter.iconName)

            Spacer()

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

    @ViewBuilder
    private var repositoriesSection: some View {
        if !self.viewModel.repositories.isEmpty {
            Section("Repositories") {
                ForEach(self.viewModel.repositories, id: \.id) { repo in
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
                    .tag(NotificationFilter.repository(repo))
                }
            }
        }
    }

    // MARK: - Helpers

    private func count(for filter: NotificationFilter) -> Int {
        self.viewModel.notifications.count(where: { filter.matches($0) })
    }

    private func repositoryUnreadCount(_ repo: Repository) -> Int {
        self.viewModel.notifications.count(where: { $0.repository.id == repo.id && $0.unread })
    }
}

#Preview {
    SidebarView()
}
