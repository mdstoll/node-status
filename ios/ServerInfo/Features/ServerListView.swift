import SwiftUI

/// Tabblad Server: overzicht, selectie en koppelen.
struct ServerListView: View {
    @Environment(AppState.self) private var app
    @State private var showAdd = false
    @State private var editing: Server?

    var body: some View {
        NavigationStack {
            Group {
                if app.servers.isEmpty {
                    EmptyStateView(
                        symbol: "server.rack",
                        title: "Nog geen servers",
                        message: "Koppel je eerste server. Je hebt alleen het commando nodig dat de app je zo laat zien.",
                        actionTitle: "Server koppelen",
                        action: { showAdd = true }
                    )
                } else {
                    list
                }
            }
            .screenBackground()
            .navigationTitle("Server")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Server koppelen")
                }
            }
            .sheet(isPresented: $showAdd) { PairServerView() }
            .sheet(item: $editing) { s in EditServerView(server: s) }
            .sheet(item: Binding(get: { app.pendingPairing },
                                 set: { app.pendingPairing = $0 })) { info in
                PairServerView(incoming: info)
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.M.cardGap) {
                ForEach(app.servers) { server in
                    ServerCard(server: server,
                               isSelected: server.id == app.selectedID,
                               onSelect: { app.select(server) },
                               onEdit: { editing = server })
                }
            }
            .padding(.horizontal, Theme.M.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 90)
        }
    }
}

/// Eén serverkaart met live statusindicatie. Deze pollt op 5 s en niet op 1 s:
/// genoeg om te zien of een server leeft, zonder alle servers tegelijk te belasten.
struct ServerCard: View {
    @Environment(AppState.self) private var app
    let server: Server
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    @State private var sample: Sample?
    @State private var system: SystemInfo?
    @State private var online = false
    @State private var cpuHistory: [Double] = []

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect()
        }) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        StatusDot(status: online ? .ok : .warn, pulsing: online && isSelected)
                        Text(server.name)
                            .font(.headline)
                            .foregroundStyle(Theme.C.text)
                        Spacer()
                        if isSelected {
                            Label("selected", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(server.accent)
                                .font(.title3)
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.C.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 14) {
                        if !cpuHistory.isEmpty {
                            Sparkline(values: cpuHistory, color: server.accent, height: 26)
                                .frame(width: 62)
                        }
                        if let s = sample {
                            stat("CPU", Fmt.percent(s.cpu.total))
                            stat("RAM", Fmt.percent(s.memory.percent))
                            if let sys = system {
                                stat("Up", Fmt.shortUptime(Date().timeIntervalSince1970 - Double(sys.bootTime)))
                            }
                        } else {
                            Text(online ? "verbinden…" : "offline")
                                .font(.caption)
                                .foregroundStyle(Theme.C.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }

                    if server.certExpiresSoon {
                        Label("Certificaat verloopt \(Fmt.shortDate(server.certExpiresAt))",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.C.warn)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.M.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? server.accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .contextMenu {
            Button("Bewerken", systemImage: "pencil", action: onEdit)
            Button("Nu verversen", systemImage: "arrow.clockwise") { Task { await refresh() } }
            Button("Verwijderen", systemImage: "trash", role: .destructive) { app.remove(server) }
        }
        .task(id: server.id) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var subtitle: String {
        if let sys = system { return "\(server.displayHost) · \(sys.osLine)" }
        return server.displayHost
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(Theme.C.textTertiary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.C.text)
        }
    }

    private func refresh() async {
        do {
            let api = try app.client(for: server)
            if system == nil {
                system = try await api.get("v1/system", as: SystemInfo.self)
            }
            let s = try await api.get("v1/metrics", as: Sample.self)
            sample = s
            online = true
            cpuHistory.append(s.cpu.total)
            if cpuHistory.count > 20 { cpuHistory.removeFirst() }
        } catch {
            online = false
        }
    }
}
