import Foundation

/// Formattering hoort in de app, niet in de agent: die stuurt altijd kale bytes
/// en seconden. Zo kan de gebruiker later GB vs GiB kiezen zonder serverwijziging.
enum Fmt {

    static func bytes(_ v: UInt64, binary: Bool = false) -> String {
        let unit: Double = binary ? 1024 : 1000
        let names = binary ? ["B", "KiB", "MiB", "GiB", "TiB", "PiB"] : ["B", "K", "M", "G", "T", "P"]
        var value = Double(v)
        var i = 0
        while value >= unit && i < names.count - 1 {
            value /= unit
            i += 1
        }
        if i == 0 { return "\(v) B" }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, names[i])
    }

    /// Netwerksnelheid met dezelfde schaalstappen als de referentie-app: "9.2 K/s".
    static func speed(_ bytesPerSec: UInt64) -> String {
        let names = ["B/s", "K/s", "M/s", "G/s"]
        var value = Double(bytesPerSec)
        var i = 0
        while value >= 1000 && i < names.count - 1 {
            value /= 1000
            i += 1
        }
        if i == 0 { return "\(bytesPerSec) B/s" }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, names[i])
    }

    static func bits(_ bitsPerSec: Double) -> String {
        let names = ["bps", "Kbps", "Mbps", "Gbps"]
        var value = bitsPerSec
        var i = 0
        while value >= 1000 && i < names.count - 1 {
            value /= 1000
            i += 1
        }
        return String(format: "%.1f %@", value, names[i])
    }

    static func percent(_ p: Double) -> String {
        String(format: "%.1f%%", max(0, min(100, p)))
    }

    /// Uptime als "1d 18h 54m 47s" — telt in de app door zonder serververkeer.
    static func uptime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h \(m)m \(sec)s" }
        if h > 0 { return "\(h)h \(m)m \(sec)s" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    static func shortUptime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func date(_ epoch: Int64) -> String {
        guard epoch > 0 else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    static func shortDate(_ epoch: Int64) -> String {
        guard epoch > 0 else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    /// Relatieve tijd. @MainActor omdat hij vertaalt; hij wordt uitsluitend
    /// vanuit views aangeroepen.
    @MainActor
    static func ago(_ epoch: Double) -> String {
        let d = Date().timeIntervalSince1970 - epoch
        switch d {
        case ..<60:    return T("just now", "zojuist")
        case ..<3600:  return T("\(Int(d / 60)) min ago", "\(Int(d / 60)) min geleden")
        case ..<86400: return T("\(Int(d / 3600))h ago", "\(Int(d / 3600)) uur geleden")
        default:       return T("\(Int(d / 86400))d ago", "\(Int(d / 86400)) dagen geleden")
        }
    }

    static func temp(_ c: Double, fahrenheit: Bool = false) -> String {
        fahrenheit ? String(format: "%.0f°F", c * 9 / 5 + 32) : String(format: "%.0f°C", c)
    }
}
