import Foundation
import OSLog

/// Centralized logging utility using OSLog.
/// Use this instead of `print()` throughout the app.
enum DiagnosticsLogger {
    private static let subsystem = "com.kuyruk"

    // MARK: - Log Categories

    private static let generalLog = Logger(subsystem: subsystem, category: "general")
    private static let authLog = Logger(subsystem: subsystem, category: "auth")
    private static let apiLog = Logger(subsystem: subsystem, category: "api")
    private static let syncLog = Logger(subsystem: subsystem, category: "sync")
    private static let uiLog = Logger(subsystem: subsystem, category: "ui")
    private static let dataLog = Logger(subsystem: subsystem, category: "data")

    // MARK: - Log Levels

    /// General debug information
    static func debug(_ message: String, category: LogCategory = .general) {
        self.logger(for: category).debug("\(message)")
    }

    /// Informational messages
    static func info(_ message: String, category: LogCategory = .general) {
        self.logger(for: category).info("\(message)")
    }

    /// Warning messages (potential issues)
    static func warning(_ message: String, category: LogCategory = .general) {
        self.logger(for: category).warning("\(message)")
    }

    /// Error messages (something went wrong)
    static func error(_ message: String, category: LogCategory = .general) {
        self.logger(for: category).error("\(message)")
    }

    /// Critical errors (app may not function correctly)
    static func critical(_ message: String, category: LogCategory = .general) {
        self.logger(for: category).critical("\(message)")
    }

    // MARK: - Error Logging

    /// Logs an error with its description
    static func error(_ error: Error, context: String? = nil, category: LogCategory = .general) {
        let contextString = context.map { "[\($0)] " } ?? ""
        Self.logger(for: category).error("\(contextString)\(error.localizedDescription)")
    }

    // MARK: - Private Helpers

    private static func logger(for category: LogCategory) -> Logger {
        switch category {
        case .general:
            self.generalLog
        case .auth:
            self.authLog
        case .api:
            self.apiLog
        case .sync:
            self.syncLog
        case .ui:
            self.uiLog
        case .data:
            self.dataLog
        }
    }
}

// MARK: - Log Category

extension DiagnosticsLogger {
    /// Categories for organizing log messages
    enum LogCategory: String, Sendable {
        case general
        case auth
        case api
        case sync
        case ui
        case data
    }
}
