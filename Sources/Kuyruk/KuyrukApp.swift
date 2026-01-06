import SwiftData
import SwiftUI

/// Main entry point for the Kuyruk app.
@main
struct KuyrukApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Services

    @State private var authService: AuthService
    @State private var gitHubClient: GitHubClient
    @State private var dataStore: DataStore
    @State private var notificationService: NotificationService
    @State private var syncService: SyncService
    @State private var viewModel: NotificationsViewModel

    // MARK: - Initialization

    init() {
        // Initialize services
        let auth = AuthService()
        let client = GitHubClient(authService: auth)

        // Initialize data store (fail gracefully)
        let store: DataStore
        do {
            store = try DataStore()
        } catch {
            DiagnosticsLogger.critical("Failed to initialize DataStore: \(error)", category: .data)
            fatalError("Failed to initialize DataStore: \(error)")
        }

        let notifications = NotificationService()
        let sync = SyncService(
            gitHubClient: client,
            dataStore: store,
            notificationService: notifications)
        let vm = NotificationsViewModel(gitHubClient: client, dataStore: store, syncService: sync)

        self._authService = State(initialValue: auth)
        self._gitHubClient = State(initialValue: client)
        self._dataStore = State(initialValue: store)
        self._notificationService = State(initialValue: notifications)
        self._syncService = State(initialValue: sync)
        self._viewModel = State(initialValue: vm)
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(self.authService)
                .environment(self.gitHubClient)
                .environment(self.notificationService)
                .environment(self.viewModel)
                .modelContainer(self.dataStore.container)
                .task {
                    await self.onAppLaunch()
                }
                .onChange(of: self.authService.state.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await self.onAuthenticated()
                        }
                    }
                }
                .onChange(of: self.viewModel.unreadCount) { _, newCount in
                    self.appDelegate.updateBadge(count: newCount)
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            self.appCommands
        }

        Settings {
            SettingsView()
                .environment(self.authService)
                .environment(self.notificationService)
        }
    }

    // MARK: - Commands

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Refresh Notifications") {
                Task {
                    await self.viewModel.refresh()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            // Remove "New Window" since we only want one window
        }
    }

    // MARK: - Lifecycle

    private func onAppLaunch() async {
        DiagnosticsLogger.info("Kuyruk app launched", category: .ui)

        // Pass references to AppDelegate for menu bar actions
        self.appDelegate.viewModel = self.viewModel
        self.appDelegate.syncService = self.syncService

        // Request notification authorization on first launch
        if !UserDefaults.standard.bool(forKey: "notificationAuthRequested") {
            let granted = await self.notificationService.requestAuthorization()
            UserDefaults.standard.set(true, forKey: "notificationAuthRequested")
            DiagnosticsLogger.info("Notification auth requested, granted: \(granted)", category: .ui)
        } else {
            await self.notificationService.checkAuthorization()
        }

        // Check for existing authentication
        await self.authService.checkExistingAuth()
    }

    private func onAuthenticated() async {
        DiagnosticsLogger.info("User authenticated, loading notifications", category: .ui)
        await self.viewModel.loadFromCache()
        self.syncService.startBackgroundSync()
    }
}
