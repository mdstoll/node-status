import SwiftUI

/// Tabblad Settings: globale defaults die je per server kunt overschrijven.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var devices: [DevicesResult.Device] = []
    @State private var deviceError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Eenheden") {
                    Toggle("Temperatuur in °F", isOn: bind(\.fahrenheit))
                    Toggle("Binaire eenheden (GiB)", isOn: bind(\.binaryUnits))
                    Toggle("Netwerksnelheid in bits", isOn: bind(\.bitsPerSecond))
                }

                Section {
                    Picker("Historievenster", selection: bind(\.historyWindow)) {
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                        Text("120 s").tag(120)
                        Text("300 s").tag(300)
                    }
                } header: {
                    Text("Real-time")
                } footer: {
                    Text("Bepaalt hoeveel geschiedenis de grafieken tonen. De agent bewaart maximaal 5 minuten in geheugen en schrijft niets naar schijf.")
                }

                Section {
                    Toggle("Gevoelige gegevens maskeren", isOn: bind(\.maskSensitive))
                    Toggle("Waarschuwen vóór speedtest", isOn: bind(\.warnBeforeSpeedtest))
                } header: {
                    Text("Privacy & data")
                } footer: {
                    Text("Een speedtest verbruikt 1–3 GB op de server. Op een VPS met datalimiet is dat relevant.")
                }

                if let server = app.selected {
                    Section {
                        if let e = deviceError {
                            Text(e).font(.caption).foregroundStyle(Theme.C.warn)
                        }
                        ForEach(devices) { d in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(d.name).foregroundStyle(Theme.C.text)
                                        if d.isCurrent {
                                            Text("dit toestel")
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Capsule().fill(Theme.C.accent.opacity(0.2)))
                                                .foregroundStyle(Theme.C.accent)
                                        }
                                    }
                                    Text("gekoppeld \(Fmt.shortDate(d.enrolledAt)) · verloopt \(Fmt.shortDate(d.expiresAt))")
                                        .font(.caption2).foregroundStyle(Theme.C.textTertiary)
                                }
                                Spacer()
                            }
                            .listRowBackground(Theme.C.card)
                            .swipeActions {
                                if !d.isCurrent {
                                    Button("Intrekken", role: .destructive) {
                                        Task { await revoke(d) }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Gekoppelde apparaten · \(server.name)")
                    } footer: {
                        Text("Alleen deze apparaten komen door de TLS-handshake. Intrekken werkt direct, ook op openstaande verbindingen.")
                    }
                }

                Section {
                    if let sys = app.system {
                        LabeledContent("Agent", value: sys.agentVersion)
                        LabeledContent("Server", value: sys.hostname)
                        LabeledContent("Capabilities", value: "\(sys.capabilities.count)")
                    }
                    LabeledContent("App", value: appVersion)
                } header: {
                    Text("Over")
                } footer: {
                    Text("Geen analytics, geen crash-reporting naar derden. De app praat uitsluitend met je eigen servers.\n\nAgent verwijderen: sudo /usr/local/bin/uninstall.sh --purge")
                }
            }
            .screenBackground()
            .accessoryInset()
            .navigationTitle("Settings")
            .task(id: app.selectedID) { await loadDevices() }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func bind<T>(_ key: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { app.prefs[keyPath: key] },
                set: { app.prefs[keyPath: key] = $0; app.prefs.save() })
    }

    private func loadDevices() async {
        guard app.selected != nil else { return }
        do {
            let api = try app.clientForSelected()
            devices = try await api.get("v1/devices", as: DevicesResult.self).devices
            deviceError = nil
        } catch {
            deviceError = error.localizedDescription
        }
    }

    private func revoke(_ d: DevicesResult.Device) async {
        do {
            let api = try app.clientForSelected()
            try await api.delete("v1/devices/\(d.id)")
            await loadDevices()
        } catch {
            deviceError = error.localizedDescription
        }
    }
}
