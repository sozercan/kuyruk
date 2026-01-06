import AppKit

/// App delegate for handling application lifecycle and menu bar support
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    private var statusItem: NSStatusItem?

    /// Reference to the main view model for triggering refreshes
    var viewModel: NotificationsViewModel?

    /// Reference to sync service for background operations
    var syncService: SyncService?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        // Set up menu bar icon
        self.setupMenuBarItem()

        // Configure app behavior
        NSApp.setActivationPolicy(.regular)
    }

    func applicationWillTerminate(_: Notification) {
        // Cleanup if needed
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // Keep running in menu bar when window is closed
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            // Reopen main window when dock icon is clicked
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(self)
                break
            }
        }
        return true
    }

    // MARK: - Badge Management

    /// Update the dock badge with the unread count
    func updateBadge(count: Int) {
        if count > 0 {
            NSApp.dockTile.badgeLabel = "\(count)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBarItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")
            button.action = #selector(self.menuBarItemClicked)
            button.target = self
        }

        // Build menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Kuyruk", action: #selector(self.openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Refresh Notifications",
            action: #selector(self.refreshNotifications),
            keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kuyruk", action: #selector(self.quitApp), keyEquivalent: "q"))

        self.statusItem?.menu = menu
    }

    @objc private func menuBarItemClicked() {
        self.openMainWindow()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(self)
            break
        }
    }

    @objc private func refreshNotifications() {
        // Post notification to trigger refresh
        NotificationCenter.default.post(name: .refreshNotifications, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshNotifications = Notification.Name("refreshNotifications")
}
