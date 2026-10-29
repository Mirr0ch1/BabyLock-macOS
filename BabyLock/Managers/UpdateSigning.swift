import CryptoKit
import Foundation

enum UpdateSigningError: Error {
    case invalidPublicKey
    case invalidSignature
    case archiveTooLarge
    case unreadableArtifact
}

/// Verifies the detached Ed25519 signature that ships next to the update zip.
///
/// `codesign --verify` only proves that a bundle is internally consistent.
/// Ad-hoc signatures pass that check, so a replaced release asset would also
/// pass. The Ed25519 key is kept offline and its public half is pinned here;
/// an attacker who can replace the GitHub asset still cannot produce a valid
/// signature.
enum UpdateSigning {
    static let publicKeyBase64 = "6yX33wBdVhlOYROiJ8V+uonayrn2d3BN5Dm0EZhb714="

    private static let maxArchiveSize = 200 * 1024 * 1024

    static func verify(zipURL: URL, signatureURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0

        guard size > 0, size <= maxArchiveSize else {
            throw UpdateSigningError.archiveTooLarge
        }

        let signature = try Data(contentsOf: signatureURL)

        guard signature.count == 64 else {
            throw UpdateSigningError.invalidSignature
        }

        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw UpdateSigningError.invalidPublicKey
        }

        let archive = try Data(contentsOf: zipURL)

        guard key.isValidSignature(signature, for: archive) else {
            throw UpdateSigningError.invalidSignature
        }
    }
}
