import Foundation
import SwiftUI

/// Eén geconfigureerde server. Alleen niet-geheime gegevens staan hier;
/// certificaten en token leven in de Keychain (zie IdentityStore).
struct Server: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var remoteHost: String?
    var port: Int = 29500
    var deviceID: String = ""
    var certExpiresAt: Int64 = 0
    var accentIndex: Int = 0

    var baseURL: URL? {
        URL(string: "https://\(host):\(port)/")
    }

    var displayHost: String { "\(host):\(port)" }

    var accent: Color {
        let palette: [Color] = [Theme.C.blue, Theme.C.green, Theme.C.purple,
                                Theme.C.orange, Theme.C.teal, Theme.C.magenta]
        return palette[abs(accentIndex) % palette.count]
    }

    /// Waarschuw ruim voor het verlopen van het client-certificaat: zonder
    /// vernieuwing breekt de app precies een jaar na koppelen zonder uitleg.
    var certExpiresSoon: Bool {
        guard certExpiresAt > 0 else { return false }
        let days = (Double(certExpiresAt) - Date().timeIntervalSince1970) / 86400
        return days < 30
    }
}

/// Persistentie van de serverlijst. Bewust simpel: een JSON-bestand in
/// Application Support. SwiftData zou hier alleen overhead toevoegen.
@MainActor
final class ServerStore {
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("servers.json")
    }

    func load() -> [Server] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Server].self, from: data) else { return [] }
        return list
    }

    func save(_ servers: [Server]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
