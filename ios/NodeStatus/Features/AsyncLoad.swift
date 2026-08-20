import SwiftUI

/// Eén plek waar laden, mislukken en leeg-zijn wordt afgehandeld, zodat elk
/// detailscherm die drie toestanden gratis krijgt in plaats van ze te vergeten.
struct AsyncLoad<Value: Decodable & Sendable, Content: View>: View {
    let path: String
    var refreshInterval: Double?
    @ViewBuilder var content: (Value) -> Content

    @Environment(AppState.self) private var app
    @State private var value: Value?
    @State private var error: String?

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let error {
                EmptyStateView(symbol: "exclamationmark.triangle",
                               title: T("Could not load this", "Kon dit niet ophalen"),
                               message: error,
                               actionTitle: T("Retry", "Opnieuw"), action: { Task { await load() } })
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(T("Loading…", "Ophalen…")).font(.footnote).foregroundStyle(Theme.C.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .task(id: app.selectedID) {
            await load()
            if let interval = refreshInterval {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    await load(silent: true)
                }
            }
        }
    }

    private func load(silent: Bool = false) async {
        do {
            let api = try app.clientForSelected()
            let v: Value = try await api.get(path)
            value = v
            error = nil
        } catch {
            if !silent && value == nil { self.error = error.localizedDescription }
        }
    }
}

/// Standaard scrollcontainer voor detailschermen.
struct DetailScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.M.cardGap) {
                content
            }
            .padding(.horizontal, Theme.M.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 90)
        }
        .screenBackground()
    }
}

/// Rij met label links en waarde rechts — het patroon uit het Locale-scherm.
struct InfoRow: View {
    let label: String
    let value: String
    var symbol: String?
    var mono = true
    var tint: Color = Theme.C.text

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.C.textTertiary)
                    .frame(width: 18)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.C.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }
}

/// Kaart met een titel en een reeks InfoRows.
struct InfoCard<Content: View>: View {
    let title: String
    var symbol: String?
    var tint: Color = Theme.C.blue
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    if let symbol { IconTile(symbol: symbol, color: tint, size: 28) }
                    Text(title).font(.headline).foregroundStyle(Theme.C.text)
                }
                .padding(.bottom, 8)
                content
            }
        }
    }
}
