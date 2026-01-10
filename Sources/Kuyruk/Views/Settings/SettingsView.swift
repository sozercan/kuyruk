import SwiftUI

/// Settings view for app preferences.
struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(NotificationService.self) private var notificationService

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(self.notificationService)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AccountSettingsView()
                .environment(self.authService)
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsView: View {
    @Environment(NotificationService.self) private var notificationService

    @AppStorage("syncInterval") private var syncInterval: Int = 900
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("showInDock") private var showInDock: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("playSoundForNotifications") private var playSoundForNotifications: Bool = true

    var body: some View {
        Form {
            Section("Sync") {
                Picker("Sync Interval", selection: self.$syncInterval) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                }
                .pickerStyle(.menu)

                Text("Kuyruk will check for new notifications at this interval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Show Notifications", isOn: self.$notificationsEnabled)

                if self.notificationsEnabled {
                    if self.notificationService.isAuthorized {
                        Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("Notifications not authorized", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            Spacer()

                            Button("Open Settings") {
                                self.openNotificationSettings()
                            }
                            .buttonStyle(.link)
                        }
                    }

                    Toggle("Play Sound", isOn: self.$playSoundForNotifications)
                }
            }

            Section("Appearance") {
                Toggle("Show in Menu Bar", isOn: self.$showInMenuBar)
                Toggle("Show in Dock", isOn: self.$showInDock)

                Text("At least one option must be enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: self.showInMenuBar) { _, newValue in
            // Ensure at least one is enabled
            if !newValue, !self.showInDock {
                self.showInDock = true
            }
        }
        .onChange(of: self.showInDock) { _, newValue in
            // Ensure at least one is enabled
            if !newValue, !self.showInMenuBar {
                self.showInMenuBar = true
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.notifications?id=com.sertacozercan.Kuyruk") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AccountSettingsView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        Form {
            Section("GitHub Account") {
                if let user = authService.currentUser {
                    HStack(spacing: 16) {
                        AsyncImage(url: URL(string: user.avatarUrl)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name ?? user.login)
                                .font(.headline)

                            Text("@\(user.login)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    Button("Sign Out", role: .destructive) {
                        Task {
                            await self.authService.logout()
                        }
                    }
                } else if self.authService.state.isAuthenticated {
                    Text("Loading user info...")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)

                    Button("Sign in with GitHub") {
                        Task {
                            await self.authService.login()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
