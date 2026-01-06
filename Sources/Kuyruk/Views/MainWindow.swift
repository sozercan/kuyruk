import SwiftUI

/// Main window of the Kuyruk app.
struct MainWindow: View {
    @Environment(AuthService.self) private var authService
    @Environment(NotificationsViewModel.self) private var viewModel

    // Keyboard navigation state
    @FocusState private var isListFocused: Bool

    var body: some View {
        Group {
            if self.authService.state.isAuthenticated {
                self.authenticatedContent
            } else {
                self.unauthenticatedContent
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            self.isListFocused = true
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            NotificationListView()
                .navigationSplitViewColumnWidth(min: 350, ideal: 450)
                .focused(self.$isListFocused)
        } detail: {
            NotificationDetailView()
        }
        .onKeyPress(.downArrow) {
            self.selectNextNotification()
            return .handled
        }
        .onKeyPress(.upArrow) {
            self.selectPreviousNotification()
            return .handled
        }
        .onKeyPress("j") {
            self.selectNextNotification()
            return .handled
        }
        .onKeyPress("k") {
            self.selectPreviousNotification()
            return .handled
        }
        .onKeyPress("o") {
            self.openSelectedInBrowser()
            return .handled
        }
        .onKeyPress(.return) {
            self.openSelectedInBrowser()
            return .handled
        }
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        VStack(spacing: 24) {
            switch authService.state {
            case .waitingForUserAuth(let deviceState):
                self.deviceFlowContent(deviceState)

            case .requestingDeviceCode:
                self.loadingContent

            default:
                self.welcomeContent
            }
        }
        .padding(48)
    }

    @ViewBuilder
    private var welcomeContent: some View {
        if #available(macOS 26, *) {
            Image(systemName: "bell.badge")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .padding(24)
                .glassEffect(in: .circle)
        } else {
            Image(systemName: "bell.badge")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
        }

        Text("Welcome to Kuyruk")
            .font(.largeTitle)
            .fontWeight(.bold)

        Text("Sign in with GitHub to view your notifications")
            .font(.title3)
            .foregroundStyle(.secondary)

        if #available(macOS 26, *) {
            Button("Sign in with GitHub") {
                Task {
                    await self.authService.login()
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button("Sign in with GitHub") {
                Task {
                    await self.authService.login()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        if case let .error(message) = authService.state {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 8)

            Button("Try Again") {
                Task {
                    await self.authService.login()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var loadingContent: some View {
        ProgressView()
            .scaleEffect(1.5)

        Text("Connecting to GitHub...")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func deviceFlowContent(_ deviceState: DeviceFlowState) -> some View {
        if #available(macOS 26, *) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(20)
                .glassEffect(in: .circle)
        } else {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
        }

        Text("Enter this code on GitHub")
            .font(.title2)
            .fontWeight(.semibold)

        // User code display
        if #available(macOS 26, *) {
            Text(deviceState.userCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .tracking(4)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            Text(deviceState.userCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .tracking(4)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }

        HStack(spacing: 16) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deviceState.userCode, forType: .string)
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if #available(macOS 26, *) {
                Button {
                    if let url = URL(string: deviceState.verificationUri) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    if let url = URL(string: deviceState.verificationUri) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }
        }

        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Waiting for authorization...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)

        Button("Cancel") {
            self.authService.cancelLogin()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Keyboard Navigation

    private func selectNextNotification() {
        let notifications = self.viewModel.filteredNotifications
        guard !notifications.isEmpty else { return }

        if let current = viewModel.selectedNotification,
           let index = notifications.firstIndex(where: { $0.id == current.id }),
           index < notifications.count - 1 {
            self.viewModel.selectedNotification = notifications[index + 1]
        } else if self.viewModel.selectedNotification == nil {
            self.viewModel.selectedNotification = notifications.first
        }
    }

    private func selectPreviousNotification() {
        let notifications = self.viewModel.filteredNotifications
        guard !notifications.isEmpty else { return }

        if let current = viewModel.selectedNotification,
           let index = notifications.firstIndex(where: { $0.id == current.id }),
           index > 0 {
            self.viewModel.selectedNotification = notifications[index - 1]
        }
    }

    private func selectFirstNotification() {
        if let first = viewModel.filteredNotifications.first {
            self.viewModel.selectedNotification = first
        }
    }

    private func selectLastNotification() {
        if let last = viewModel.filteredNotifications.last {
            self.viewModel.selectedNotification = last
        }
    }

    private func openSelectedInBrowser() {
        if let notification = viewModel.selectedNotification,
           let url = notification.webUrl {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    MainWindow()
}
