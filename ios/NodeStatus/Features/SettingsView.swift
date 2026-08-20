import SwiftUI

/// Tabblad Settings: globale defaults die je per server kunt overschrijven.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var devices: [DevicesResult.Device] = []
    @State private var deviceError: String?

    var body: some View {
        NavigationStack {
            Form {
                // Nederlands alleen aanbieden als het toestel zelf Nederlands
                // is; anders is het een keuze die niemand die hem ziet wil.
                if Localizer.systemIsDutch {
                    Section {
                        Picker(T("Language", "Taal"), selection: Binding(
                            get: { Localizer.shared.language },
                            set: { Localizer.shared.language = $0 })) {
                            ForEach(AppLanguage.allCases, id: \.self) { l in
                                Text(l.label).tag(l)
                            }
                        }
                    } header: {
                        Text(T("Language", "Taal"))
                    } footer: {
                        Text(T("English is the default. Dutch is offered because your device language is Dutch.",
                               "Engels is de standaard. Nederlands wordt aangeboden omdat je toestel op Nederlands staat."))
                    }
                }

                Section(T("Units", "Eenheden")) {
                    Toggle(T("Temperature in °F", "Temperatuur in °F"), isOn: bind(\.fahrenheit))
                    Toggle(T("Binary units (GiB)", "Binaire eenheden (GiB)"), isOn: bind(\.binaryUnits))
                    Toggle(T("Network speed in bits", "Netwerksnelheid in bits"), isOn: bind(\.bitsPerSecond))
                }

                Section {
                    Picker(T("History window", "Historievenster"), selection: bind(\.historyWindow)) {
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                        Text("120 s").tag(120)
                        Text("300 s").tag(300)
                    }
                } header: {
                    Text("Real-time")
                } footer: {
                    Text(T("How much history the charts show. The agent keeps at most 5 minutes in memory and writes nothing to disk.", "Bepaalt hoeveel geschiedenis de grafieken tonen. De agent bewaart maximaal 5 minuten in geheugen en schrijft niets naar schijf."))
                }

                Section {
                    Toggle(T("Mask sensitive data", "Gevoelige gegevens maskeren"), isOn: bind(\.maskSensitive))
                    Toggle(T("Warn before speedtest", "Waarschuwen vóór speedtest"), isOn: bind(\.warnBeforeSpeedtest))
                } header: {
                    Text(T("Privacy & data", "Privacy & data"))
                } footer: {
                    Text(T("A speedtest uses 1–3 GB on the server. On a VPS with a data cap that matters.", "Een speedtest verbruikt 1–3 GB op de server. Op een VPS met datalimiet is dat relevant."))
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
                                            Text(T("this device", "dit toestel"))
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Capsule().fill(Theme.C.accent.opacity(0.2)))
                                                .foregroundStyle(Theme.C.accent)
                                        }
                                    }
                                    Text(T("paired \(Fmt.shortDate(d.enrolledAt)) · expires \(Fmt.shortDate(d.expiresAt))", "gekoppeld \(Fmt.shortDate(d.enrolledAt)) · verloopt \(Fmt.shortDate(d.expiresAt))"))
                                        .font(.caption2).foregroundStyle(Theme.C.textTertiary)
                                }
                                Spacer()
                            }
                            .listRowBackground(Theme.C.card)
                            .swipeActions {
                                if !d.isCurrent {
                                    Button(T("Revoke", "Intrekken"), role: .destructive) {
                                        Task { await revoke(d) }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(T("Paired devices · \(server.name)", "Gekoppelde apparaten · \(server.name)"))
                    } footer: {
                        Text(T("Only these devices get through the TLS handshake. Revoking takes effect immediately, even on open connections.", "Alleen deze apparaten komen door de TLS-handshake. Intrekken werkt direct, ook op openstaande verbindingen."))
                    }
                }

                Section {
                    if let sys = app.system {
                        LabeledContent(T("Agent", "Agent"), value: sys.agentVersion)
                        LabeledContent(T("Server", "Server"), value: sys.hostname)
                        LabeledContent("Capabilities", value: "\(sys.capabilities.count)")
                    }
                    LabeledContent("App", value: appVersion)
                } header: {
                    Text(T("About", "Over"))
                } footer: {
                    Text(T("No analytics, no third-party crash reporting. The app talks only to your own servers.\n\nRemove the agent: sudo /usr/local/bin/uninstall.sh --purge", "Geen analytics, geen crash-reporting naar derden. De app praat uitsluitend met je eigen servers.\n\nAgent verwijderen: sudo /usr/local/bin/uninstall.sh --purge"))
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
