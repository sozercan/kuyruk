import SwiftUI

/// Command for the command palette
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let shortcut: String?
    let action: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        shortcut: String? = nil,
        action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.action = action
    }
}

/// Command palette view (⌘K) for quick actions
struct CommandPalette: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationsViewModel.self) private var viewModel

    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredCommands: [PaletteCommand] {
        let allCommands = self.buildCommands()
        if self.searchText.isEmpty {
            return allCommands
        }
        let query = self.searchText.lowercased()
        return allCommands.filter {
            $0.title.lowercased().contains(query) ||
                ($0.subtitle?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Type a command or search...", text: self.$searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused(self.$isSearchFocused)

                if !self.searchText.isEmpty {
                    Button {
                        self.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            // Commands list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(self.filteredCommands.enumerated()), id: \.element.id) { index, command in
                            CommandRow(
                                command: command,
                                isSelected: index == self.selectedIndex)
                                .id(command.id)
                                .onTapGesture {
                                    self.executeCommand(command)
                                }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                }
                .onChange(of: self.selectedIndex) { _, newIndex in
                    if let command = self.filteredCommands[safe: newIndex] {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(command.id, anchor: .center)
                        }
                    }
                }
            }

            if self.filteredCommands.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No commands match '\(self.searchText)'")
                }
                .frame(height: 150)
            }
        }
        .frame(width: 500, height: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .onAppear {
            self.isSearchFocused = true
        }
        .onKeyPress(.downArrow) {
            self.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            self.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            if let command = self.filteredCommands[safe: self.selectedIndex] {
                self.executeCommand(command)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            self.dismiss()
            return .handled
        }
        .onChange(of: self.searchText) { _, _ in
            self.selectedIndex = 0
        }
    }

    // MARK: - Commands

    private func buildCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        // Navigation commands
        commands.append(PaletteCommand(
            id: "nav-inbox",
            title: "Go to Inbox",
            icon: "tray",
            shortcut: "⌘1") {
                self.viewModel.selectedFilter = .inbox
                self.dismiss()
            })

        commands.append(PaletteCommand(
            id: "nav-unread",
            title: "Go to Unread",
            icon: "circle.fill",
            shortcut: "⌘2") {
                self.viewModel.selectedFilter = .unread
                self.dismiss()
            })

        commands.append(PaletteCommand(
            id: "nav-mentioned",
            title: "Go to Mentioned",
            icon: "at",
            shortcut: "⌘3") {
                self.viewModel.selectedFilter = .mentioned
                self.dismiss()
            })

        commands.append(PaletteCommand(
            id: "nav-review",
            title: "Go to Review Requested",
            icon: "eye",
            shortcut: "⌘4") {
                self.viewModel.selectedFilter = .reviewRequested
                self.dismiss()
            })

        commands.append(PaletteCommand(
            id: "nav-assigned",
            title: "Go to Assigned",
            icon: "person.badge.plus",
            shortcut: "⌘5") {
                self.viewModel.selectedFilter = .assigned
                self.dismiss()
            })

        // Action commands
        commands.append(PaletteCommand(
            id: "action-refresh",
            title: "Refresh Notifications",
            subtitle: "Fetch latest from GitHub",
            icon: "arrow.clockwise",
            shortcut: "⌘R") {
                Task {
                    await self.viewModel.refresh()
                }
                self.dismiss()
            })

        commands.append(PaletteCommand(
            id: "action-force-refresh",
            title: "Force Refresh",
            subtitle: "Ignore cache and fetch all",
            icon: "arrow.clockwise.circle") {
                Task {
                    await self.viewModel.forceRefresh()
                }
                self.dismiss()
            })

        // Selected notification actions
        if let selected = viewModel.selectedNotification {
            commands.append(PaletteCommand(
                id: "action-open",
                title: "Open in Browser",
                subtitle: selected.subject.title,
                icon: "safari",
                shortcut: "⌘O") {
                    if let url = selected.webUrl {
                        NSWorkspace.shared.open(url)
                    }
                    self.dismiss()
                })

            if selected.unread {
                commands.append(PaletteCommand(
                    id: "action-mark-read",
                    title: "Mark as Read",
                    subtitle: selected.subject.title,
                    icon: "checkmark.circle",
                    shortcut: "⌘⇧M") {
                        Task {
                            await self.viewModel.markAsRead(selected)
                        }
                        self.dismiss()
                    })
            }

            commands.append(PaletteCommand(
                id: "action-copy-link",
                title: "Copy Link",
                subtitle: selected.subject.title,
                icon: "link") {
                    if let url = selected.webUrl {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    self.dismiss()
                })
        }

        // Repository navigation
        for repo in self.viewModel.repositories.prefix(10) {
            commands.append(PaletteCommand(
                id: "repo-\(repo.id)",
                title: repo.name,
                subtitle: "Repository: \(repo.fullName)",
                icon: "folder") {
                    self.viewModel.selectedFilter = .repository(repo)
                    self.dismiss()
                })
        }

        return commands
    }

    // MARK: - Helpers

    private func moveSelection(by delta: Int) {
        let newIndex = self.selectedIndex + delta
        if newIndex >= 0, newIndex < self.filteredCommands.count {
            self.selectedIndex = newIndex
        }
    }

    private func executeCommand(_ command: PaletteCommand) {
        command.action()
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.command.icon)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(self.isSelected ? .white : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.command.title)
                    .font(.body)
                    .foregroundStyle(self.isSelected ? .white : .primary)

                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(self.isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(self.isSelected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        self.isSelected
                            ? Color.white.opacity(0.2)
                            : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            self.isSelected
                ? Color.accentColor
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < self.count else { return nil }
        return self[index]
    }
}

#Preview {
    CommandPalette()
}
