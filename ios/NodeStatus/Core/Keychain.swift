import Foundation
import Security

/// Keychain-toegang. Alles staat op `whenUnlockedThisDeviceOnly`: geen
/// iCloud-sync van servertokens en niet leesbaar met een vergrendeld toestel.
enum Keychain {

    private static let service = "nl.merlinstoll.nodestatus"

    // MARK: - Generieke geheimen (token, certificaten in PEM)

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    // MARK: - Sleutelpaar

    private static func keyTag(_ id: UUID) -> Data {
        Data("\(service).key.\(id.uuidString)".utf8)
    }

    /// Genereert een P-256 sleutelpaar dat permanent in de Keychain blijft.
    /// De private sleutel verlaat het toestel nooit; alleen het publieke punt
    /// gaat naar de server om er een certificaat voor te laten tekenen.
    static func createKeyPair(for id: UUID) throws -> SecKey {
        deleteKeyPair(for: id)
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag(id),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? IdentityError.keyGeneration
        }
        return key
    }

    static func privateKey(for id: UUID) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: keyTag(id),
            kSecReturnRef as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return (out as! SecKey?)
    }

    static func deleteKeyPair(for id: UUID) {
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag(id),
        ] as CFDictionary)
    }

    /// X9.63 uncompressed point (0x04 ‖ X ‖ Y) — precies wat de agent verwacht.
    static func publicKeyData(from privateKey: SecKey) throws -> Data {
        guard let pub = SecKeyCopyPublicKey(privateKey) else { throw IdentityError.publicKey }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
            throw error?.takeRetainedValue() ?? IdentityError.publicKey
        }
        return data
    }

    // MARK: - Certificaten

    static func storeCertificate(_ cert: SecCertificate, label: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: label,
        ]
        SecItemDelete([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
        ] as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteCertificate(label: String) {
        SecItemDelete([
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
        ] as CFDictionary)
    }
}

enum IdentityError: LocalizedError {
    case keyGeneration
    case publicKey
    case badPEM
    case identityCreation
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .keyGeneration:    "Kon geen sleutelpaar aanmaken op dit toestel."
        case .publicKey:        "Kon de publieke sleutel niet uitlezen."
        case .badPEM:           "Het certificaat van de server is onleesbaar."
        case .identityCreation: "Kon de client-identiteit niet samenstellen."
        case .missingCredentials: "Deze server is nog niet gekoppeld."
        }
    }
}

/// PEM ⇄ DER. De agent stuurt PEM; Security.framework wil DER.
enum PEM {
    static func certificate(from pem: String) throws -> SecCertificate {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let der = Data(base64Encoded: body),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            throw IdentityError.badPEM
        }
        return cert
    }
}
