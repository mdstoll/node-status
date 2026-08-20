import Foundation
import SwiftUI
import Observation

/// Taalkeuze. Engels is de standaard; Nederlands wordt alleen aangeboden als
/// het toestel zelf op Nederlands staat — anders is het een optie die niemand
/// die hem ziet ook wil.
enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case dutch = "nl"

    var label: String {
        switch self {
        case .english: "English"
        case .dutch: "Nederlands"
        }
    }
}

@Observable
@MainActor
final class Localizer {
    static let shared = Localizer()

    /// True als de systeemtaal Nederlands is. Alleen dan tonen we de keuze.
    static let systemIsDutch: Bool = {
        Locale.preferredLanguages.first?.hasPrefix("nl") ?? false
    }()

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "appLanguage")
        if let stored, let l = AppLanguage(rawValue: stored), l != .dutch || Self.systemIsDutch {
            language = l
        } else {
            // Standaard Engels, ook op een Nederlands toestel: dat is de taal
            // waarin de meeste servertermen sowieso staan.
            language = .english
        }
    }
}

/// Vertaalt één string. Beide talen staan naast elkaar op de plek waar de
/// tekst gebruikt wordt; dat leest prettiger dan losse sleutelbestanden en
/// werkt zonder omwegen met string-interpolatie.
///
/// Omdat dit `Localizer.shared.language` leest, hertekent SwiftUI vanzelf
/// zodra de taal wijzigt.
@MainActor
func T(_ english: String, _ dutch: String) -> String {
    Localizer.shared.language == .dutch ? dutch : english
}
