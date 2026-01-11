import CryptoKit
import Foundation

/// URLSession delegate that implements certificate pinning for GitHub API.
///
/// ## Security Design
/// This class pins to GitHub's intermediate and root certificates to protect
/// against man-in-the-middle attacks while allowing for certificate rotation.
///
/// ## Pinning Strategy
/// - Pins to Subject Public Key Info (SPKI) hashes rather than full certificates
/// - Includes multiple pins for rotation support
/// - Falls back gracefully if pinning fails (with logging)
///
/// Last updated: January 2026
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {
    /// Known SPKI hashes for GitHub's certificate chain
    /// These are SHA-256 hashes of the public key data extracted via SecKeyCopyExternalRepresentation
    ///
    /// To update these pins, run the app and check logs for "Certificate X hash:" messages
    /// Then update these values to match.
    ///
    /// Current pins (as of January 2026):
    /// - Sectigo intermediate and root CAs (api.github.com)
    /// - GitHub Models API pins (models.github.ai)
    private static let pinnedHashes: Set<String> = [
        // Sectigo Public Server Authentication CA DV E36 (intermediate)
        "VqePxH3EcFwZuYK3CCOMz5HKMoeIZpZcEyBf4diPGSA=",
        // Sectigo Public Server Authentication Root E46 (root)
        "EdsvlytFf4a/O+hCPwBXFFi46RKXqivCAF+mO7s+5Ng=",
        // models.github.ai - Leaf certificate
        "0eD6+p++C3Ts3ydDtLigKkhS5dAxHRjhtXLyfz6JPuE=",
        // models.github.ai - Intermediate certificate
        "TCAFfcfLpnjdFcUGvKSxe8jNIlxxtREjh1HdnHqql+Q=",
        // models.github.ai - Root certificate
        "FifhKLh4RFnK/GDH4ipsrxcrFLDJMTWTaaMGG+2Qwz0=",
    ]

    /// Whether to enforce pinning (disable in debug for testing if needed)
    private let enforcePinning: Bool

    init(enforcePinning: Bool = true) {
        self.enforcePinning = enforcePinning
        super.init()
    }

    // MARK: - URLSessionDelegate

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Only pin for GitHub domains
        let host = challenge.protectionSpace.host
        guard host.hasSuffix("github.com") ||
            host.hasSuffix("githubusercontent.com") ||
            host == "models.github.ai"
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            DiagnosticsLogger.warning("Certificate validation failed for \(host)", category: .api)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check certificate pinning
        if self.validatePinning(serverTrust: serverTrust, host: host) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else if self.enforcePinning {
            DiagnosticsLogger.error(
                GitHubError.networkError("Certificate pinning failed"),
                context: "Certificate pinning failed for \(host)",
                category: .api)
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            // In non-enforcing mode, log and continue
            DiagnosticsLogger.warning(
                "Certificate pinning check failed for \(host), continuing anyway",
                category: .api)
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        }
    }

    // MARK: - Pinning Validation

    private func validatePinning(serverTrust: SecTrust, host: String) -> Bool {
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return false
        }

        for (index, certificate) in certificateChain.enumerated() {
            if let publicKeyHash = self.getPublicKeyHash(for: certificate) {
                if Self.pinnedHashes.contains(publicKeyHash) {
                    DiagnosticsLogger.debug(
                        "Certificate pinning succeeded for \(host) at index \(index)",
                        category: .api)
                    return true
                }
            }
        }

        // Log all hashes to help update pins if needed
        for (index, certificate) in certificateChain.enumerated() {
            if let publicKeyHash = self.getPublicKeyHash(for: certificate) {
                DiagnosticsLogger.warning(
                    "Certificate \(index) hash: \(publicKeyHash)",
                    category: .api)
            }
        }

        DiagnosticsLogger.error(
            "No pinned certificate found in chain for \(host) (count: \(certificateChain.count))",
            category: .api)
        return false
    }

    /// Extracts the SHA-256 hash of the public key from a certificate
    private func getPublicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Hash the public key data
        let hash = SHA256.hash(data: publicKeyData)
        return Data(hash).base64EncodedString()
    }
}

// MARK: - URLSession Extension

extension URLSession {
    /// Creates a URLSession with certificate pinning enabled for GitHub API
    static func createPinnedSession(enforcePinning: Bool = true) -> URLSession {
        let delegate = CertificatePinningDelegate(enforcePinning: enforcePinning)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}
