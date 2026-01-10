import SwiftUI

/// Connection status indicator showing online/offline state and last sync time
struct ConnectionStatusView: View {
    @Environment(NotificationsViewModel.self) private var viewModel
    let syncService: SyncService

    @State private var isOnline: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            // Connection indicator
            Circle()
                .fill(self.statusColor)
                .frame(width: 8, height: 8)

            // Status text
            Text(self.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .onAppear {
            self.startMonitoringNetwork()
        }
    }

    private var statusColor: Color {
        if !self.isOnline {
            .red
        } else if self.syncService.isSyncing {
            .yellow
        } else if self.syncService.lastError != nil {
            .orange
        } else {
            .green
        }
    }

    private var statusText: String {
        if !self.isOnline {
            return "Offline"
        } else if self.syncService.isSyncing {
            return "Syncing..."
        } else if let error = syncService.lastError {
            if let gitHubError = error as? GitHubError {
                switch gitHubError {
                case .rateLimited:
                    return "Rate limited"
                case .unauthorized:
                    return "Auth expired"
                default:
                    return "Sync error"
                }
            }
            return "Sync error"
        } else if let lastSync = syncService.lastSyncedAt {
            return "Synced \(self.formatRelativeTime(lastSync))"
        } else {
            return "Not synced"
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func startMonitoringNetwork() {
        // Simple network check using URLSession
        Task {
            while !Task.isCancelled {
                await self.checkConnectivity()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func checkConnectivity() async {
        guard let url = URL(string: "https://api.github.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                self.isOnline = httpResponse.statusCode < 500
            }
        } catch {
            self.isOnline = false
        }
    }
}

/// Larger status bar for the sidebar footer
struct SyncStatusBar: View {
    @Environment(SyncService.self) private var syncService

    @State private var isOnline: Bool = true

    /// Whether retry is available (has error and not currently syncing)
    private var canRetry: Bool {
        self.syncService.lastError != nil && !self.syncService.isSyncing && self.isOnline
    }

    var body: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(self.statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.primaryText)
                        .font(.caption)
                        .fontWeight(.medium)

                    if let secondaryText = self.secondaryText {
                        Text(secondaryText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if self.syncService.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else if !self.isOnline {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if self.canRetry {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                self.handleRetryTap()
            }
        }
        .onAppear {
            self.startMonitoringNetwork()
        }
    }

    private func handleRetryTap() {
        guard self.canRetry else { return }
        DiagnosticsLogger.info("User tapped retry", category: .sync)
        Task {
            await self.syncService.forceSync()
        }
    }

    private var statusColor: Color {
        if !self.isOnline {
            .red
        } else if self.syncService.lastError != nil {
            .orange
        } else {
            .green
        }
    }

    private var primaryText: String {
        if !self.isOnline {
            "Offline"
        } else if self.syncService.isSyncing {
            "Syncing..."
        } else if self.syncService.lastError != nil {
            "Sync failed"
        } else {
            "Connected"
        }
    }

    private var secondaryText: String? {
        // Prioritize showing error info when there's a sync error
        if let error = syncService.lastError {
            if let gitHubError = error as? GitHubError {
                switch gitHubError {
                case .unauthorized:
                    return "Please re-authenticate"
                case .rateLimited:
                    return "Rate limited - wait and retry"
                case .networkError:
                    return "Network error - tap to retry"
                case .serverError:
                    return "Server error - tap to retry"
                default:
                    return "Tap to retry"
                }
            }
            return "Tap to retry"
        } else if let lastSync = syncService.lastSyncedAt {
            return "Last synced \(self.formatRelativeTime(lastSync))"
        }
        return nil
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func startMonitoringNetwork() {
        Task {
            while !Task.isCancelled {
                await self.checkConnectivity()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func checkConnectivity() async {
        guard let url = URL(string: "https://api.github.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                self.isOnline = httpResponse.statusCode < 500
            }
        } catch {
            self.isOnline = false
        }
    }
}

/// Pending actions indicator showing queued offline actions
struct PendingActionsView: View {
    let count: Int

    var body: some View {
        if self.count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)

                Text("\(self.count) pending")
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.15), in: Capsule())
        }
    }
}
