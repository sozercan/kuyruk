import Foundation
import SwiftData

/// SwiftData model for caching AI-generated notification analyses.
@Model
final class CachedSummary {
    /// Unique identifier matching the notification ID.
    @Attribute(.unique) var notificationId: String

    /// The timestamp when the notification was last updated (used for cache invalidation).
    var notificationUpdatedAt: Date

    /// The generated TL;DR summary text.
    var summary: String

    /// The generated thread summary (discussion status).
    var threadSummary: String?

    /// Priority score: "High", "Medium", or "Low".
    var priorityScore: String?

    /// Explanation for the priority score.
    var priorityExplanation: String?

    /// Recommended action for the user.
    var actionRecommendation: String?

    /// The model ID used to generate analyses.
    var modelUsed: String

    /// When analyses were last generated.
    var generatedAt: Date

    init(
        notificationId: String,
        notificationUpdatedAt: Date,
        summary: String,
        threadSummary: String? = nil,
        priorityScore: String? = nil,
        priorityExplanation: String? = nil,
        actionRecommendation: String? = nil,
        modelUsed: String) {
        self.notificationId = notificationId
        self.notificationUpdatedAt = notificationUpdatedAt
        self.summary = summary
        self.threadSummary = threadSummary
        self.priorityScore = priorityScore
        self.priorityExplanation = priorityExplanation
        self.actionRecommendation = actionRecommendation
        self.modelUsed = modelUsed
        self.generatedAt = Date()
    }

    /// Check if cached analyses are still valid for the given notification.
    ///
    /// Analyses are valid if the notification hasn't been updated since they were generated.
    /// - Parameter notification: The notification to check against.
    /// - Returns: `true` if the cached analyses are still valid.
    func isValid(for notification: GitHubNotification) -> Bool {
        self.notificationUpdatedAt >= notification.updatedAt
    }

    /// Check if a specific analysis type has been generated.
    /// - Parameter type: The analysis type to check.
    /// - Returns: `true` if that analysis has been generated.
    func hasAnalysis(for type: AnalysisType) -> Bool {
        switch type {
        case .summary:
            !self.summary.isEmpty
        case .threadSummary:
            self.threadSummary != nil
        case .priority:
            self.priorityScore != nil
        case .action:
            self.actionRecommendation != nil
        }
    }
}
