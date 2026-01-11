import SwiftUI

/// Detail view for a selected notification.
struct NotificationDetailView: View {
    @Environment(NotificationsViewModel.self) private var viewModel
    @Environment(GitHubModelsService.self) private var modelsService
    @Environment(DataStore.self) private var dataStore

    // MARK: - AI Analysis State

    @AppStorage("aiSummariesEnabled") private var aiSummariesEnabled: Bool = true
    @State private var loadingAnalysis: AnalysisType?
    @State private var analysisError: String?

    // Cached analysis values
    @State private var generatedSummary: String?
    @State private var threadSummary: String?
    @State private var priorityScore: String?
    @State private var priorityExplanation: String?
    @State private var actionRecommendation: String?

    var body: some View {
        Group {
            if let notification = viewModel.selectedNotification {
                self.detailContent(for: notification)
                    .id(notification.id)
            } else {
                self.emptyState
            }
        }
        .frame(minWidth: 300)
        .animation(.easeInOut(duration: 0.15), value: self.viewModel.selectedNotification?.id)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Select a Notification", systemImage: "bell")
        } description: {
            Text("Choose a notification from the list to view details")
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(for notification: GitHubNotification) -> some View {
        ScrollView {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 24) {
                    self.detailSections(for: notification)
                }
            } else {
                self.detailSections(for: notification)
            }
        }
        .navigationTitle(notification.repository.name)
        .task(id: notification.id) {
            // Reset AI analysis state when notification changes
            self.loadingAnalysis = nil
            self.analysisError = nil
            self.generatedSummary = nil
            self.threadSummary = nil
            self.priorityScore = nil
            self.priorityExplanation = nil
            self.actionRecommendation = nil
            // Load cached analyses
            self.loadCachedAnalyses(for: notification)
        }
    }

    /// Loads cached analyses for the notification if available.
    private func loadCachedAnalyses(for notification: GitHubNotification) {
        if let cached = try? self.dataStore.fetchSummary(for: notification.id),
           cached.isValid(for: notification) {
            if !cached.summary.isEmpty {
                self.generatedSummary = cached.summary
            }
            self.threadSummary = cached.threadSummary
            self.priorityScore = cached.priorityScore
            self.priorityExplanation = cached.priorityExplanation
            self.actionRecommendation = cached.actionRecommendation
        }
    }

    @ViewBuilder
    private func detailSections(for notification: GitHubNotification) -> some View {
        VStack(spacing: 24) {
            // Header
            self.headerSection(for: notification)

            Divider()

            // AI Analysis section (replaces old AI Summary section)
            self.aiAnalysisSection(for: notification)

            Divider()

            // Info section
            self.infoSection(for: notification)

            Divider()

            // Actions
            self.actionsSection(for: notification)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Header Section

    @ViewBuilder
    private func headerSection(for notification: GitHubNotification) -> some View {
        VStack(spacing: 16) {
            // Subject type icon
            SubjectTypeBadge(type: notification.subject.type)
                .font(.system(size: 48))

            // Title
            Text(notification.subject.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Repository
            HStack(spacing: 8) {
                AvatarView(url: notification.repository.owner.avatarUrl, size: 24)

                Text(notification.repository.fullName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Reason badge
            ReasonBadge(reason: notification.reason)
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private func infoSection(for notification: GitHubNotification) -> some View {
        // Note: Already inside GlassEffectContainer from detailContent,
        // so use regular background instead of glassEffect to avoid glass-on-glass
        self.infoGrid(for: notification)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func infoGrid(for notification: GitHubNotification) -> some View {
        VStack(spacing: 12) {
            self.infoRow(label: "Status", value: notification.unread ? "Unread" : "Read")
            self.infoRow(label: "Type", value: notification.subject.type.displayName)
            self.infoRow(label: "Reason", value: notification.reason.displayName)
            self.infoRow(
                label: "Updated",
                value: notification.updatedAt.formatted(date: .abbreviated, time: .shortened))

            if let number = notification.subjectNumber {
                self.infoRow(label: "Number", value: "#\(number)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private func actionsSection(for notification: GitHubNotification) -> some View {
        VStack(spacing: 12) {
            // Primary action - Open in Browser
            // Note: Use bordered styles inside GlassEffectContainer to avoid glass-on-glass
            Button {
                if let url = notification.webUrl {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            // Secondary actions
            HStack(spacing: 12) {
                Button {
                    Task {
                        await self.viewModel.markAsRead(notification)
                    }
                } label: {
                    Label("Mark as Read", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!notification.unread)
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button {
                    if let url = notification.webUrl {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                } label: {
                    Label("Copy Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - AI Analysis Section

    @ViewBuilder
    private func aiAnalysisSection(for notification: GitHubNotification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Label("AI Analysis", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Content based on state
            if !self.aiSummariesEnabled {
                self.aiDisabledView
            } else if !self.modelsService.canGenerateSummaries {
                self.aiNotConfiguredView
            } else if self.modelsService.isRateLimited {
                self.rateLimitedView
            } else {
                // Analysis rows
                VStack(spacing: 12) {
                    self.analysisRow(
                        title: "TL;DR",
                        icon: "text.quote",
                        value: self.generatedSummary,
                        isLoading: self.loadingAnalysis == .summary,
                        type: .summary,
                        notification: notification)

                    self.analysisRow(
                        title: "Thread Status",
                        icon: "bubble.left.and.bubble.right",
                        value: self.threadSummary,
                        isLoading: self.loadingAnalysis == .threadSummary,
                        type: .threadSummary,
                        notification: notification)

                    self.analysisRow(
                        title: "Priority",
                        icon: "flag",
                        value: self.formattedPriority,
                        isLoading: self.loadingAnalysis == .priority,
                        type: .priority,
                        notification: notification)

                    self.analysisRow(
                        title: "Recommended Action",
                        icon: "hand.point.right",
                        value: self.actionRecommendation,
                        isLoading: self.loadingAnalysis == .action,
                        type: .action,
                        notification: notification)

                    // Error display
                    if let error = self.analysisError {
                        self.analysisErrorView(error: error)
                    }

                    // Analyze All button
                    if self.canGenerateAny {
                        Button {
                            Task { await self.generateAllAnalyses(for: notification) }
                        } label: {
                            Label("Analyze All", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(self.loadingAnalysis != nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Formats priority score with explanation.
    private var formattedPriority: String? {
        guard let score = self.priorityScore else { return nil }
        if let explanation = self.priorityExplanation {
            return "\(score) - \(explanation)"
        }
        return score
    }

    /// Whether any analysis can still be generated.
    private var canGenerateAny: Bool {
        self.generatedSummary == nil ||
            self.threadSummary == nil ||
            self.priorityScore == nil ||
            self.actionRecommendation == nil
    }

    /// Generates all missing analyses.
    private func generateAllAnalyses(for notification: GitHubNotification) async {
        let typesToGenerate: [AnalysisType] = [
            self.generatedSummary == nil ? .summary : nil,
            self.threadSummary == nil ? .threadSummary : nil,
            self.priorityScore == nil ? .priority : nil,
            self.actionRecommendation == nil ? .action : nil,
        ].compactMap(\.self)

        for type in typesToGenerate {
            await self.generateAnalysis(for: notification, type: type)
        }
    }

    // MARK: - Analysis Row

    @ViewBuilder
    private func analysisRow(
        title: String,
        icon: String,
        value: String?,
        isLoading: Bool,
        type: AnalysisType,
        notification: GitHubNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)

                    Button("Cancel") {
                        self.modelsService.cancelCurrentGeneration()
                        self.loadingAnalysis = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                } else if value == nil {
                    Button {
                        Task { await self.generateAnalysis(for: notification, type: type) }
                    } label: {
                        Label("Generate", systemImage: "sparkle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let value {
                self.analysisValueView(value: value, type: type)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func analysisValueView(value: String, type: AnalysisType) -> some View {
        switch type {
        case .priority:
            self.priorityBadgeView(value: value)
        default:
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func priorityBadgeView(value: String) -> some View {
        HStack(spacing: 8) {
            // Priority badge
            self.priorityBadge

            // Explanation text
            if let explanation = self.priorityExplanation {
                Text(explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var priorityBadge: some View {
        if let score = self.priorityScore {
            let (color, icon) = Self.priorityStyle(for: score)
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(score)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
        }
    }

    /// Returns color and icon for a priority score.
    private static func priorityStyle(for score: String) -> (Color, String) {
        switch score.lowercased() {
        case "high":
            (.red, "exclamationmark.triangle.fill")
        case "medium":
            (.orange, "flag.fill")
        case "low":
            (.green, "checkmark.circle.fill")
        default:
            (.secondary, "questionmark.circle")
        }
    }

    @ViewBuilder
    private func analysisErrorView(error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button("Dismiss") {
                self.analysisError = nil
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Analysis Generation

    private func generateAnalysis(for notification: GitHubNotification, type: AnalysisType) async {
        self.analysisError = nil
        self.loadingAnalysis = type

        defer { self.loadingAnalysis = nil }

        do {
            let result = try await self.modelsService.generateAnalysis(for: notification, type: type)

            switch type {
            case .summary:
                self.generatedSummary = result
            case .threadSummary:
                self.threadSummary = result
            case .priority:
                // Parse the result to extract score and explanation
                let parts = result.split(separator: "-", maxSplits: 1)
                self.priorityScore = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) }
                self.priorityExplanation = parts.count > 1
                    ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                    : nil
            case .action:
                self.actionRecommendation = result
            }
        } catch is CancellationError {
            DiagnosticsLogger.debug("Analysis generation cancelled", category: .api)
        } catch {
            self.analysisError = error.localizedDescription
            DiagnosticsLogger.error(error, context: "generateAnalysis(\(type.rawValue))", category: .api)
        }
    }

    @ViewBuilder
    private var aiDisabledView: some View {
        // Note: Inside GlassEffectContainer, use regular background to avoid glass-on-glass
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Summaries Disabled")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Enable AI summaries in Settings → AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                self.openAISettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var aiNotConfiguredView: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Configure AI")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Select a model in Settings → AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                self.openAISettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var rateLimitedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Rate Limit Reached")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let reset = modelsService.rateLimitReset {
                    Text("Resets at \(reset.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Please try again later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func openAISettings() {
        // Open Settings window and navigate to AI tab
        // Note: macOS Settings window navigation is limited; we open the window
        if let url = URL(string: "kuyruk://settings/ai") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: just show the settings
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

#Preview {
    // Preview requires mock services - shown as placeholder
    Text("NotificationDetailView Preview - requires NotificationsViewModel and GitHubModelsService environments")
        .frame(width: 400, height: 500)
}
