import Foundation
import Security

/// De koppelgegevens van één server: client-identiteit voor mTLS, de CA om de
/// server mee te valideren, en het bearer token als tweede laag.
///
/// `@unchecked Sendable`: SecIdentity en SecCertificate zijn CoreFoundation-
/// types zonder Sendable-conformance, maar ze zijn immutable en thread-safe
/// zodra ze gemaakt zijn. Ze worden hier alleen gelezen.
struct ServerCredentials: @unchecked Sendable {
    var identity: SecIdentity
    var clientCertificate: SecCertificate
    var caCertificate: SecCertificate
    var token: String
}

enum IdentityStore {

    private static func account(_ id: UUID, _ what: String) -> String {
        "\(id.uuidString).\(what)"
    }

    static func save(serverID: UUID, clientCertPEM: String, caCertPEM: String, token: String) throws {
        let clientCert = try PEM.certificate(from: clientCertPEM)
        Keychain.storeCertificate(clientCert, label: "serverinfo-client-\(serverID.uuidString)")
        Keychain.set(clientCertPEM, for: account(serverID, "clientcert"))
        Keychain.set(caCertPEM, for: account(serverID, "cacert"))
        Keychain.set(token, for: account(serverID, "token"))
    }

    static func load(serverID: UUID) throws -> ServerCredentials {
        guard let clientPEM = Keychain.get(account(serverID, "clientcert")),
              let caPEM = Keychain.get(account(serverID, "cacert")),
              let token = Keychain.get(account(serverID, "token")) else {
            throw IdentityError.missingCredentials
        }
        let clientCert = try PEM.certificate(from: clientPEM)
        let caCert = try PEM.certificate(from: caPEM)

        // SecIdentityCreateWithCertificate bestaat alleen op macOS. Op iOS
        // vormt de Keychain zelf een identity zodra het certificaat én de
        // bijbehorende private sleutel erin staan; we zoeken hem op door de
        // certificaat-DER te vergelijken.
        guard let identity = findIdentity(matching: clientCert) else {
            throw IdentityError.identityCreation
        }
        return ServerCredentials(identity: identity, clientCertificate: clientCert,
                                 caCertificate: caCert, token: token)
    }

    /// Zoekt de identity die bij dit certificaat hoort. Vergelijken op DER is
    /// betrouwbaarder dan op label: labels kunnen botsen, de DER niet.
    private static func findIdentity(matching cert: SecCertificate) -> SecIdentity? {
        let wanted = SecCertificateCopyData(cert) as Data
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let identities = out as? [SecIdentity] else { return nil }
        for identity in identities {
            var candidate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &candidate) == errSecSuccess,
                  let candidate else { continue }
            if (SecCertificateCopyData(candidate) as Data) == wanted { return identity }
        }
        return nil
    }

    static func remove(serverID: UUID) {
        Keychain.delete(account(serverID, "clientcert"))
        Keychain.delete(account(serverID, "cacert"))
        Keychain.delete(account(serverID, "token"))
        Keychain.deleteCertificate(label: "serverinfo-client-\(serverID.uuidString)")
        Keychain.deleteKeyPair(for: serverID)
    }

    static func hasCredentials(serverID: UUID) -> Bool {
        Keychain.get(account(serverID, "token")) != nil
    }
}
