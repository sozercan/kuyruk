import Foundation
import Security

/// Manages secure storage of OAuth tokens in the macOS Keychain.
@MainActor
final class KeychainManager {
    /// Shared instance
    static let shared = KeychainManager()

    private let serviceName = "com.kuyruk.github-oauth"
    private let accessTokenKey = "github_access_token"
    private let refreshTokenKey = "github_refresh_token"

    private init() {}

    // MARK: - Access Token

    /// Saves the access token to the Keychain.
    func saveAccessToken(_ token: String) throws {
        try self.save(token, forKey: self.accessTokenKey)
    }

    /// Retrieves the access token from the Keychain.
    func getAccessToken() throws -> String? {
        try self.retrieve(forKey: self.accessTokenKey)
    }

    /// Deletes the access token from the Keychain.
    func deleteAccessToken() throws {
        try self.delete(forKey: self.accessTokenKey)
    }

    // MARK: - Refresh Token

    /// Saves the refresh token to the Keychain.
    func saveRefreshToken(_ token: String) throws {
        try self.save(token, forKey: self.refreshTokenKey)
    }

    /// Retrieves the refresh token from the Keychain.
    func getRefreshToken() throws -> String? {
        try self.retrieve(forKey: self.refreshTokenKey)
    }

    /// Deletes the refresh token from the Keychain.
    func deleteRefreshToken() throws {
        try self.delete(forKey: self.refreshTokenKey)
    }

    // MARK: - Clear All

    /// Clears all stored tokens.
    func clearAll() throws {
        try self.deleteAccessToken()
        try? self.deleteRefreshToken()
    }

    // MARK: - Private Helpers

    private func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        try? self.delete(forKey: key)

        // Create access that allows any application to access this item.
        // This avoids repeated Keychain prompts when using ad-hoc signing during development,
        // since each build produces a different code signature.
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        #if DEBUG
        // In DEBUG builds, create an access object that allows any application.
        // An empty trusted application list (nil) means "allow all applications".
        // Note: SecAccessCreate is deprecated but still functional - it's the only way
        // to create a Keychain item that doesn't require app signature verification.
        var access: SecAccess?
        withUnsafeMutablePointer(to: &access) { accessPtr in
            // Silence deprecation warning - this API is deprecated but has no replacement
            // for creating signature-independent Keychain access in development.
            _ = SecAccessCreate(
                "Kuyruk GitHub Token" as CFString,
                nil, // nil = allow any application (no trusted app list)
                accessPtr)
        }
        if let access {
            query[kSecAttrAccess as String] = access
        }
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func retrieve(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.decodingFailed
            }
            return string

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.retrieveFailed(status)
        }
    }

    private func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.serviceName,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Errors

/// Errors that can occur during Keychain operations.
enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode token data"
        case .decodingFailed:
            "Failed to decode token data"
        case let .saveFailed(status):
            "Failed to save to Keychain (status: \(status))"
        case let .retrieveFailed(status):
            "Failed to retrieve from Keychain (status: \(status))"
        case let .deleteFailed(status):
            "Failed to delete from Keychain (status: \(status))"
        }
    }
}
