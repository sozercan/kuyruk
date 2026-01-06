import Foundation
import UserNotifications

/// Service for managing local notifications for new GitHub notifications.
@MainActor
@Observable
final class NotificationService {
    // MARK: - Properties

    private(set) var isAuthorized: Bool = false
    private(set) var isAvailable: Bool = false
    private var notifiedIds: Set<String> = []

    // MARK: - Initialization

    init() {
        // Check if we're running in a proper app bundle
        // UNUserNotificationCenter requires a bundle identifier
        self.isAvailable = Bundle.main.bundleIdentifier != nil
        if !self.isAvailable {
            DiagnosticsLogger.warning(
                "NotificationService unavailable - no bundle identifier (running via swift run?)",
                category: .ui)
        }
    }

    // MARK: - Authorization

    /// Requests notification authorization from the user.
    func requestAuthorization() async -> Bool {
        guard self.isAvailable else {
            DiagnosticsLogger.debug("Skipping notification auth - not available", category: .ui)
            return false
        }

        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.isAuthorized = granted

            if granted {
                DiagnosticsLogger.info("Notification authorization granted", category: .ui)
            } else {
                DiagnosticsLogger.warning("Notification authorization denied", category: .ui)
            }

            return granted
        } catch {
            DiagnosticsLogger.error(error, context: "requestAuthorization", category: .ui)
            return false
        }
    }

    /// Checks current authorization status.
    func checkAuthorization() async {
        guard self.isAvailable else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        self.isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Notifications

    /// Schedules a local notification for a new GitHub notification.
    func scheduleNotification(for notification: GitHubNotification) async {
        guard self.isAvailable, self.isAuthorized else {
            DiagnosticsLogger.debug("Skipping notification - not available or authorized", category: .ui)
            return
        }

        // Don't notify for already-notified items
        guard !self.notifiedIds.contains(notification.id) else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.repository.fullName
        content.subtitle = notification.reason.displayName
        content.body = notification.subject.title
        content.sound = .default
        content.categoryIdentifier = "GITHUB_NOTIFICATION"

        // Add user info for handling taps
        content.userInfo = [
            "notificationId": notification.id,
            "repositoryFullName": notification.repository.fullName,
            "webUrl": notification.webUrl?.absoluteString ?? "",
        ]

        // Add thread identifier for grouping
        content.threadIdentifier = notification.repository.fullName

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil, // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            self.notifiedIds.insert(notification.id)
            DiagnosticsLogger.debug("Scheduled notification for \(notification.id)", category: .ui)
        } catch {
            DiagnosticsLogger.error(error, context: "scheduleNotification", category: .ui)
        }
    }

    /// Schedules notifications for multiple new notifications.
    func scheduleNotifications(for notifications: [GitHubNotification]) async {
        // Only notify for unread notifications we haven't seen before
        let newNotifications = notifications.filter { $0.unread && !self.notifiedIds.contains($0.id) }

        guard !newNotifications.isEmpty else { return }

        DiagnosticsLogger.info("Scheduling \(newNotifications.count) new notifications", category: .ui)

        for notification in newNotifications.prefix(5) {
            // Limit to 5 to avoid notification spam
            await self.scheduleNotification(for: notification)
        }

        if newNotifications.count > 5 {
            // Show summary for remaining
            await self.scheduleSummaryNotification(count: newNotifications.count - 5)
        }
    }

    /// Schedules a summary notification when there are many new items.
    private func scheduleSummaryNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Kuyruk"
        content.body = "And \(count) more notification\(count == 1 ? "" : "s")"
        content.sound = nil // No sound for summary

        let request = UNNotificationRequest(
            identifier: "summary-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil)

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Clears all pending and delivered notifications.
    func clearAllNotifications() {
        guard self.isAvailable else { return }

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        self.notifiedIds.removeAll()
        DiagnosticsLogger.info("Cleared all notifications", category: .ui)
    }

    /// Removes a specific notification.
    func removeNotification(id: String) {
        guard self.isAvailable else { return }

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Registers notification categories and actions.
    func registerCategories() {
        guard self.isAvailable else { return }

        let openAction = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Open in Browser",
            options: [.foreground])

        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_ACTION",
            title: "Mark as Read",
            options: [])

        let category = UNNotificationCategory(
            identifier: "GITHUB_NOTIFICATION",
            actions: [openAction, markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction])

        UNUserNotificationCenter.current().setNotificationCategories([category])
        DiagnosticsLogger.debug("Registered notification categories", category: .ui)
    }

    /// Marks notification IDs as already notified (for initial load).
    func markAsNotified(_ ids: [String]) {
        self.notifiedIds.formUnion(ids)
    }
}
