import AppKit
import SwiftUI

/// Dashboard-style digest for scanning active threads, recommendations, and repositories.
struct DigestView: View {
    @Environment(NotificationsViewModel.self) private var viewModel
    @Environment(GitHubModelsService.self) private var modelsService

    private let spotlightFilters: [NotificationFilter] = [
        .inbox,
        .reviewRequested,
        .mentioned,
        .assigned,
        .participating,
    ]

    var body: some View {
        GeometryReader { geometry in
            let snapshot = DigestSnapshot(
                viewModel: self.viewModel,
                spotlightFilters: self.spotlightFilters,
                analysisRevision: self.viewModel.digestAnalysisRevision)
            let isWideLayout = geometry.size.width >= 920

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    self.heroSection(snapshot: snapshot)
                    self.spotlightSection(snapshot: snapshot)
                    self.insightSections(snapshot: snapshot, isWideLayout: isWideLayout)
                    self.repositoryActivitySection(snapshot: snapshot)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(self.backgroundView)
        }
        .navigationTitle(AppDestination.digest.displayName)
        .task(id: self.digestPreparationTrigger) {
            await self.viewModel.prepareDigest(using: self.modelsService)
        }
    }

    private func heroSection(snapshot: DigestSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Digest", systemImage: AppDestination.digest.iconName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(self.headline(for: snapshot))
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(self.subheadline(for: snapshot))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Open Notifications") {
                    self.viewModel.showNotifications()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)],
                spacing: 16) {
                    DigestStatCard(
                        title: "Unread now",
                        value: "\(snapshot.unreadCount)",
                        subtitle: "Threads waiting in the inbox",
                        tint: .blue)

                    DigestStatCard(
                        title: "Snoozed",
                        value: "\(snapshot.snoozedCount)",
                        subtitle: "Temporarily out of the way",
                        tint: .orange)

                    DigestStatCard(
                        title: "Actions ready",
                        value: "\(snapshot.recommendationsReadyCount)",
                        subtitle: "Cached next steps ready to review",
                        tint: .green)
                }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.15),
                    Color.orange.opacity(0.12),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func spotlightSection(snapshot: DigestSnapshot) -> some View {
        DigestPanel(
            title: "Spotlight Filters",
            subtitle: "Jump directly into the busiest smart filters.") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                    spacing: 16) {
                        ForEach(snapshot.spotlightMetrics) { metric in
                            Button {
                                self.viewModel.selectFilter(metric.filter)
                            } label: {
                                FilterCardView(
                                    filter: metric.filter,
                                    count: metric.count,
                                    isSelected: self.isSelected(metric.filter))
                            }
                            .buttonStyle(.plain)
                        }
                    }
            }
    }

    @ViewBuilder
    private func insightSections(snapshot: DigestSnapshot, isWideLayout: Bool) -> some View {
        if isWideLayout {
            HStack(alignment: .top, spacing: 20) {
                self.recentUnreadSection(snapshot: snapshot)
                    .frame(maxWidth: .infinity, alignment: .top)
                self.recommendedActionsSection(snapshot: snapshot)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                self.recentUnreadSection(snapshot: snapshot)
                self.recommendedActionsSection(snapshot: snapshot)
            }
        }
    }

    private func recentUnreadSection(snapshot: DigestSnapshot) -> some View {
        DigestPanel(
            title: "Recent Unread",
            subtitle: "Latest unread threads ranked by freshest activity.") {
                if snapshot.recentUnread.isEmpty {
                    DigestEmptyState(
                        title: "No unread threads",
                        systemImage: "checkmark.circle",
                        description: "Unread activity will appear here as new notifications arrive.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snapshot.recentUnread.enumerated()), id: \.element.id) { index, notification in
                            Button {
                                self.viewModel.showNotification(notification)
                            } label: {
                                DigestNotificationRow(notification: notification)
                            }
                            .buttonStyle(.plain)

                            if index < snapshot.recentUnread.count - 1 {
                                Divider()
                                    .padding(.vertical, 14)
                            }
                        }
                    }
                }
            }
    }

    private func recommendedActionsSection(snapshot: DigestSnapshot) -> some View {
        DigestPanel(
            title: "Recommended Actions",
            subtitle: self.recommendedActionsSubtitle(for: snapshot)) {
                if snapshot.primaryInsights.isEmpty {
                    DigestEmptyState(
                        title: "No recommendations yet",
                        systemImage: "hand.point.right",
                        description: "Cached next-step guidance will appear here as summaries are generated.")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snapshot.primaryInsights.enumerated()), id: \.element.id) { index, item in
                            Button {
                                self.viewModel.showNotification(item.notification)
                            } label: {
                                DigestRecommendationRow(item: item)
                            }
                            .buttonStyle(.plain)

                            if index < snapshot.primaryInsights.count - 1 {
                                Divider()
                                    .padding(.vertical, 14)
                            }
                        }
                    }
                }
            }
    }

    private func repositoryActivitySection(snapshot: DigestSnapshot) -> some View {
        DigestPanel(
            title: "Repository Activity",
            subtitle: "Repositories with the heaviest unread load rise to the top.") {
                if snapshot.repositoryActivity.isEmpty {
                    DigestEmptyState(
                        title: "No repository activity",
                        systemImage: "folder",
                        description: "Repository hotspots appear here once notifications are available.")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)],
                        spacing: 16) {
                            ForEach(snapshot.repositoryActivity) { activity in
                                Button {
                                    self.viewModel.selectRepository(activity.repository)
                                } label: {
                                    DigestRepositoryCard(activity: activity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                }
            }
    }

    private func headline(for snapshot: DigestSnapshot) -> String {
        if snapshot.unreadCount == 0 {
            return "You're caught up across \(snapshot.repositoryCount) repositories."
        }

        return "\(snapshot.unreadCount) unread threads across \(snapshot.repositoryCount) repositories."
    }

    private func subheadline(for snapshot: DigestSnapshot) -> String {
        if snapshot.recommendationsReadyCount > 0 {
            if snapshot.snoozedCount > 0 {
                return
                    """
                    \(snapshot.recommendationsReadyCount) recommendations are ready to review, \
                    and \(snapshot.snoozedCount) threads are snoozed for later.
                    """
            }

            return
                """
                \(snapshot.recommendationsReadyCount) recommendations are ready to review \
                alongside the freshest unread threads.
                """
        }

        if snapshot.summariesReadyCount > 0 {
            if snapshot.snoozedCount > 0 {
                return
                    """
                    \(snapshot.summariesReadyCount) summaries are ready to skim while \
                    \(snapshot.snoozedCount) threads stay snoozed for later.
                    """
            }

            return
                """
                \(snapshot.summariesReadyCount) summaries are ready to skim while the digest \
                waits for clearer next steps.
                """
        }

        if snapshot.snoozedCount > 0 {
            return
                """
                \(snapshot.snoozedCount) threads are snoozed for later while the newest unread \
                items stay front and center.
                """
        }

        return
            """
            Use the sections below to jump straight into active filters, fresh unread threads, \
            and repository hotspots.
            """
    }

    private func isSelected(_ filter: NotificationFilter) -> Bool {
        self.viewModel.appDestination == .notifications &&
            self.viewModel.selectedFilter == filter
    }

    private func recommendedActionsSubtitle(for snapshot: DigestSnapshot) -> String {
        if self.viewModel.isPreparingDigest {
            let totalPullRequests =
                self.viewModel.digestEvaluatedPRCount + self.viewModel.digestPendingPRAnalysisCount

            if totalPullRequests > 0 {
                return
                    """
                    Digest is evaluating \(self.viewModel.digestEvaluatedPRCount) of \
                    \(totalPullRequests) pull requests for priority and action guidance.
                    """
            }
        }

        if snapshot.hasExplicitRecommendations {
            return
                """
                Threads with explicit next-step guidance rise above summary-only items.
                """
        }

        if snapshot.highlightedSummaries.isEmpty {
            return
                """
                Cached recommendations will appear here once summaries include clear action \
                guidance.
                """
        }

        return "No explicit next steps yet, so the strongest cached summaries are standing in."
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor),
                    Color.blue.opacity(0.04),
                ],
                startPoint: .top,
                endPoint: .bottom)

            Circle()
                .fill(Color.orange.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 24)
                .offset(x: 220, y: -220)

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 28)
                .offset(x: -260, y: -260)
        }
        .ignoresSafeArea()
    }

    private var digestPreparationTrigger: DigestPreparationTrigger {
        let pullRequests = self.viewModel.notifications
            .filter { $0.subject.type == .pullRequest }
            .map { DigestTrackedPullRequest(id: $0.id, updatedAt: $0.updatedAt) }
            .sorted { $0.id < $1.id }

        return DigestPreparationTrigger(
            canGenerateSummaries: self.modelsService.canGenerateSummaries,
            selectedModelId: self.modelsService.selectedModelId,
            pullRequests: pullRequests)
    }
}

// MARK: - Snapshot Models

@MainActor
struct DigestSnapshot {
    let unreadCount: Int
    let snoozedCount: Int
    let summariesReadyCount: Int
    let recommendationsReadyCount: Int
    let repositoryCount: Int
    let spotlightMetrics: [DigestFilterMetric]
    let recentUnread: [GitHubNotification]
    let recommendedActions: [DigestSummaryItem]
    let highlightedSummaries: [DigestSummaryItem]
    let repositoryActivity: [DigestRepositoryActivity]

    var hasExplicitRecommendations: Bool {
        self.recommendationsReadyCount > 0
    }

    var primaryInsights: [DigestSummaryItem] {
        if self.recommendedActions.isEmpty {
            return self.highlightedSummaries
        }

        return self.recommendedActions
    }

    init(
        viewModel: NotificationsViewModel,
        spotlightFilters: [NotificationFilter],
        analysisRevision: Int = 0) {
        _ = analysisRevision
        let notifications = viewModel.notifications
        let summaries = notifications.compactMap { notification -> DigestSummaryItem? in
            guard let cached = viewModel.cachedSummary(for: notification),
                  cached.isValid(for: notification)
            else {
                return nil
            }

            guard let summaryText = Self.summaryText(for: cached, notification: notification) else {
                return nil
            }

            return DigestSummaryItem(
                notification: notification,
                summaryText: summaryText,
                priorityScore: Self.normalizedText(cached.priorityScore),
                priorityExplanation: Self.normalizedText(cached.priorityExplanation),
                actionRecommendation: Self.normalizedText(cached.actionRecommendation))
        }
        let rankedSummaries = summaries.sorted(by: Self.areRankedDescending)

        let summaryIds = Set(summaries.map(\.id))
        let groupedByRepository = Dictionary(grouping: notifications, by: \.repository)

        self.unreadCount = viewModel.unreadCount
        self.snoozedCount = viewModel.snoozedCount
        self.summariesReadyCount = summaries.count
        self.recommendationsReadyCount = summaries.count(where: { $0.hasActionRecommendation })
        self.repositoryCount = max(viewModel.repositories.count, groupedByRepository.count)
        self.spotlightMetrics = spotlightFilters.map { filter in
            DigestFilterMetric(
                filter: filter,
                count: Self.count(for: filter, in: notifications, viewModel: viewModel))
        }
        self.recentUnread = Array(
            notifications
                .filter(\.unread)
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(6))
        self.recommendedActions = Array(
            rankedSummaries
                .filter(\.hasActionRecommendation)
                .prefix(6))
        self.highlightedSummaries = Array(
            rankedSummaries
                .prefix(6))
        self.repositoryActivity = Array(
            groupedByRepository
                .compactMap { repository, repoNotifications in
                    guard let latestNotification = repoNotifications.max(by: { $0.updatedAt < $1.updatedAt }) else {
                        return nil
                    }

                    return DigestRepositoryActivity(
                        repository: repository,
                        unreadCount: repoNotifications.count(where: { $0.unread }),
                        totalCount: repoNotifications.count,
                        summaryCount: repoNotifications.count(where: { summaryIds.contains($0.id) }),
                        latestNotification: latestNotification,
                        latestUpdatedAt: latestNotification.updatedAt)
                }
                .sorted { lhs, rhs in
                    if lhs.unreadCount != rhs.unreadCount {
                        return lhs.unreadCount > rhs.unreadCount
                    }

                    if lhs.latestUpdatedAt != rhs.latestUpdatedAt {
                        return lhs.latestUpdatedAt > rhs.latestUpdatedAt
                    }

                    return lhs.repository.fullName < rhs.repository.fullName
                }
                .prefix(8))
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func summaryText(
        for cached: CachedSummary,
        notification: GitHubNotification) -> String? {
        if let summary = normalizedText(cached.summary) {
            return summary
        }

        guard notification.subject.type == .pullRequest else { return nil }

        if let priorityExplanation = Self.normalizedText(cached.priorityExplanation) {
            return priorityExplanation
        }

        if let actionRecommendation = Self.normalizedText(cached.actionRecommendation) {
            return actionRecommendation
        }

        if cached.hasAnalysis(for: .priority) || cached.hasAnalysis(for: .action) {
            return "AI evaluation in progress for this pull request."
        }

        return nil
    }

    private static func areRankedDescending(_ lhs: DigestSummaryItem, _ rhs: DigestSummaryItem) -> Bool {
        if lhs.hasActionRecommendation != rhs.hasActionRecommendation {
            return lhs.hasActionRecommendation && !rhs.hasActionRecommendation
        }

        let leftPriority = Self.priorityRank(lhs.priorityScore)
        let rightPriority = Self.priorityRank(rhs.priorityScore)

        if leftPriority != rightPriority {
            return leftPriority > rightPriority
        }

        if lhs.notification.updatedAt != rhs.notification.updatedAt {
            return lhs.notification.updatedAt > rhs.notification.updatedAt
        }

        return lhs.notification.id < rhs.notification.id
    }

    private static func count(
        for filter: NotificationFilter,
        in notifications: [GitHubNotification],
        viewModel: NotificationsViewModel) -> Int {
        switch filter {
        case .snoozed:
            viewModel.snoozedCount
        default:
            notifications.count(where: { filter.matches($0) })
        }
    }

    private static func priorityRank(_ score: String?) -> Int {
        switch score?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            3
        case "medium":
            2
        case "low":
            1
        default:
            0
        }
    }
}

private struct DigestPreparationTrigger: Equatable {
    let canGenerateSummaries: Bool
    let selectedModelId: String?
    let pullRequests: [DigestTrackedPullRequest]
}

private struct DigestTrackedPullRequest: Equatable {
    let id: String
    let updatedAt: Date
}

struct DigestFilterMetric: Identifiable {
    let filter: NotificationFilter
    let count: Int

    var id: String {
        self.filter.id
    }
}

struct DigestSummaryItem: Identifiable {
    let notification: GitHubNotification
    let summaryText: String
    let priorityScore: String?
    let priorityExplanation: String?
    let actionRecommendation: String?

    var hasActionRecommendation: Bool {
        self.actionRecommendation != nil
    }

    var id: String {
        self.notification.id
    }
}

struct DigestRepositoryActivity: Identifiable {
    let repository: Repository
    let unreadCount: Int
    let totalCount: Int
    let summaryCount: Int
    let latestNotification: GitHubNotification
    let latestUpdatedAt: Date

    var id: Int {
        self.repository.id
    }
}

// MARK: - Reusable Panels

private struct DigestPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(self.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            self.content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DigestStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(self.value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(self.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    self.tint.opacity(0.18),
                    self.tint.opacity(0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DigestEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(self.title, systemImage: self.systemImage)
                .font(.headline)

            Text(self.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DigestNotificationRow: View {
    let notification: GitHubNotification

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                SubjectTypeBadge(type: self.notification.subject.type)

                VStack(alignment: .leading, spacing: 6) {
                    Text(self.notification.subject.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(self.notification.repository.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(self.notification.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ReasonBadge(reason: self.notification.reason)

                if let number = self.notification.subjectNumber {
                    Text("#\(number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DigestRecommendationRow: View {
    let item: DigestSummaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.item.notification.repository.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(self.item.notification.subject.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if let priorityScore = self.item.priorityScore {
                    DigestPriorityBadge(score: priorityScore)
                }
            }

            if let actionRecommendation = self.item.actionRecommendation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.point.right.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 2)

                    Text(actionRecommendation)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(self.item.summaryText)
                .font(self.item.hasActionRecommendation ? .caption : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(self.item.hasActionRecommendation ? 2 : 3)

            HStack(spacing: 8) {
                ReasonBadge(reason: self.item.notification.reason)
                SubjectTypeBadge(type: self.item.notification.subject.type)

                Spacer(minLength: 0)

                Text(self.item.notification.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .help(self.item.priorityExplanation ?? self.item.actionRecommendation ?? "")
    }
}

private struct DigestPriorityBadge: View {
    let score: String

    var body: some View {
        Text(self.score)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(self.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(self.tint.opacity(0.14), in: Capsule())
    }

    private var tint: Color {
        switch self.score.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            .red
        case "medium":
            .orange
        case "low":
            .green
        default:
            .secondary
        }
    }
}

private struct DigestRepositoryCard: View {
    let activity: DigestRepositoryActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(url: self.activity.repository.owner.avatarUrl, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(self.activity.repository.fullName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(self.activity.latestUpdatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(self.activity.unreadCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    Text("unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(self.activity.latestNotification.subject.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("\(self.activity.totalCount) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if self.activity.summaryCount > 0 {
                    Text("\(self.activity.summaryCount) summarized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8)))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    Text("DigestView Preview - requires NotificationsViewModel environment")
        .frame(width: 700, height: 600)
}
