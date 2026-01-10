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

    /// Whether to show the menu bar icon (from settings)
    private var showInMenuBar: Bool {
        UserDefaults.standard.bool(forKey: "showInMenuBar")
    }

    /// Whether to show in dock (from settings)
    private var showInDock: Bool {
        let value = UserDefaults.standard.object(forKey: "showInDock")
        // Default to true if not set
        return value == nil ? true : UserDefaults.standard.bool(forKey: "showInDock")
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        // Set up menu bar icon based on settings
        self.updateMenuBarVisibility()

        // Configure app behavior
        self.updateActivationPolicy()
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

        // Also update menu bar badge
        self.updateMenuBarBadge(count: count)
    }

    // MARK: - Menu Bar

    /// Updates menu bar visibility based on settings
    func updateMenuBarVisibility() {
        if self.showInMenuBar {
            self.setupMenuBarItem()
        } else {
            self.statusItem = nil
        }
    }

    /// Updates the activation policy (dock vs accessory)
    func updateActivationPolicy() {
        if self.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func setupMenuBarItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")
            button.imagePosition = .imageLeft
        }

        self.rebuildMenu()
    }

    /// Updates the menu bar icon badge
    private func updateMenuBarBadge(count: Int) {
        guard let button = statusItem?.button else { return }

        if count > 0 {
            // Create attributed title with badge
            let attachment = NSTextAttachment()
            attachment.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Notifications")
            button.image = attachment.image

            // Add count as title
            button.title = count > 99 ? "99+" : "\(count)"
        } else {
            button.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")
            button.title = ""
        }
    }

    /// Rebuilds the menu bar dropdown menu
    private func rebuildMenu() {
        let menu = NSMenu()

        // Quick stats header
        if let vm = viewModel {
            let headerItem = NSMenuItem(title: "\(vm.unreadCount) unread notifications", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            menu.addItem(NSMenuItem.separator())

            // Recent notifications (up to 5)
            let recentNotifications = vm.filteredNotifications.prefix(5)
            if !recentNotifications.isEmpty {
                for notification in recentNotifications {
                    let item = NSMenuItem(
                        title: notification.subject.title,
                        action: #selector(self.openNotification(_:)),
                        keyEquivalent: "")
                    item.target = self
                    item.representedObject = notification.webUrl
                    item.toolTip = notification.repository.fullName

                    // Add unread indicator
                    if notification.unread {
                        item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Unread")
                        item.image?.isTemplate = true
                    }

                    menu.addItem(item)
                }
                menu.addItem(NSMenuItem.separator())
            }
        }

        // Actions
        menu.addItem(NSMenuItem(title: "Open Kuyruk", action: #selector(self.openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(
            title: "Refresh Notifications",
            action: #selector(self.refreshNotifications),
            keyEquivalent: "r"))

        // Sync status
        if let sync = syncService {
            menu.addItem(NSMenuItem.separator())
            let statusItem: NSMenuItem
            if sync.isSyncing {
                statusItem = NSMenuItem(title: "Syncing...", action: nil, keyEquivalent: "")
            } else if let lastSync = sync.lastSyncedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relativeTime = formatter.localizedString(for: lastSync, relativeTo: Date())
                statusItem = NSMenuItem(title: "Last synced \(relativeTime)", action: nil, keyEquivalent: "")
            } else {
                statusItem = NSMenuItem(title: "Not synced", action: nil, keyEquivalent: "")
            }
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

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
        Task {
            await self.viewModel?.refresh()
        }
        // Rebuild menu to update stats
        self.rebuildMenu()
    }

    @objc private func openNotification(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Call this when notifications update to refresh the menu
    func notificationsDidUpdate() {
        self.rebuildMenu()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshNotifications = Notification.Name("refreshNotifications")
}
