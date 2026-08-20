import SwiftUI

/// Designtokens. Alles wat kleur, ruimte of typografie is, staat hier — zodat
/// een wijziging op één plek doorwerkt in het hele scherm.
enum Theme {

    // MARK: - Kleuren

    enum C {
        static let base          = Color(hex: 0x000000)
        static let card          = Color(hex: 0x1C1C1E)
        static let cardElevated  = Color(hex: 0x2C2C2E)
        static let hairline      = Color.white.opacity(0.08)

        static let text          = Color.white
        static let textSecondary = Color(hex: 0xEBEBF5).opacity(0.62)
        static let textTertiary  = Color(hex: 0xEBEBF5).opacity(0.32)

        static let accent        = Color(hex: 0x0A84FF)
        static let ok            = Color(hex: 0x30D158)
        static let warn          = Color(hex: 0xFF9F0A)
        static let crit          = Color(hex: 0xFF375F)

        static let track         = Color.white.opacity(0.10)

        // Iconentegels
        static let blue    = Color(hex: 0x0A84FF)
        static let cyan    = Color(hex: 0x32D0FF)
        static let magenta = Color(hex: 0xFF2D9B)
        static let red     = Color(hex: 0xFF453A)
        static let green   = Color(hex: 0x30D158)
        static let mint    = Color(hex: 0x66E39A)
        static let purple  = Color(hex: 0xBF5AF2)
        static let indigo  = Color(hex: 0x5E5CE6)
        static let orange  = Color(hex: 0xFF9F0A)
        static let teal    = Color(hex: 0x40C8E0)
        static let gray    = Color(hex: 0x8E8E93)
    }

    // MARK: - Gradients
    //
    // De gradient loopt bewust over de vólle breedte van de balk en niet over
    // het gevulde deel: anders verandert de kleur mee met de vulling en ziet
    // 22% er anders uit dan 80%.

    enum G {
        static let cpu     = LinearGradient(colors: [C.blue, C.cyan], startPoint: .leading, endPoint: .trailing)
        static let ram     = LinearGradient(colors: [C.blue, C.cyan], startPoint: .leading, endPoint: .trailing)
        static let storage = LinearGradient(colors: [C.magenta, C.red], startPoint: .leading, endPoint: .trailing)
        static let load    = LinearGradient(colors: [C.green, C.mint], startPoint: .leading, endPoint: .trailing)

        static func status(_ s: Status) -> LinearGradient {
            switch s {
            case .ok:   LinearGradient(colors: [C.green, C.mint], startPoint: .leading, endPoint: .trailing)
            case .warn: LinearGradient(colors: [C.orange, Color(hex: 0xFFD60A)], startPoint: .leading, endPoint: .trailing)
            case .crit: LinearGradient(colors: [C.crit, Color(hex: 0xFF6482)], startPoint: .leading, endPoint: .trailing)
            }
        }
    }

    // MARK: - Maatvoering

    enum M {
        static let cardRadius: CGFloat = 20
        static let tileRadius: CGFloat = 10
        static let cardPadding: CGFloat = 16
        static let cardGap: CGFloat = 12
        static let sectionGap: CGFloat = 24
        static let screenMargin: CGFloat = 16
        static let barHeight: CGFloat = 8
        static let iconTile: CGFloat = 32
    }
}

enum Status: String, Codable, Sendable {
    case ok, warn, crit

    var color: Color {
        switch self {
        case .ok: Theme.C.ok
        case .warn: Theme.C.warn
        case .crit: Theme.C.crit
        }
    }

    /// Kleur is nooit de enige informatiedrager.
    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .crit: "xmark.octagon.fill"
        }
    }

    static func forPercent(_ p: Double) -> Status {
        switch p {
        case ..<70: .ok
        case ..<90: .warn
        default: .crit
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
