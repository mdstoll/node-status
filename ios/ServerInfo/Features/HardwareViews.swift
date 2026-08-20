import SwiftUI

// MARK: - Hardware-overzicht

/// Geen eigen tab: bereikbaar vanuit de identiteitskaart op Metrics en vanuit
/// de Hardware-sectie in Tools.
struct HardwareView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DetailScroll {
            if let sys = app.system {
                InfoCard(title: "Systeem", symbol: "server.rack", tint: Theme.C.indigo) {
                    InfoRow(label: "Vendor", value: sys.model.vendor.isEmpty ? "—" : sys.model.vendor)
                    InfoRow(label: "Model", value: sys.modelLine)
                    if let b = sys.model.board, !b.isEmpty {
                        InfoRow(label: "Moederbord", value: b)
                    }
                    InfoRow(label: "Distributie", value: sys.osLine)
                    InfoRow(label: "Kernel", value: sys.os.kernel)
                    InfoRow(label: "Architectuur", value: sys.os.arch)
                    InfoRow(label: "Virtualisatie", value: sys.os.virtualization ?? "geen (bare metal)")
                    InfoRow(label: "Agent", value: sys.agentVersion)
                }

                InfoCard(title: "Processor", symbol: "cpu.fill", tint: Theme.C.blue) {
                    InfoRow(label: "Model", value: sys.cpu.model)
                    InfoRow(label: "Cores / threads", value: "\(sys.cpu.coresPhysical) / \(sys.cpu.threads)")
                    InfoRow(label: "Sockets", value: "\(sys.cpu.sockets)")
                    if let m = sys.cpu.maxMhz, m > 0 { InfoRow(label: "Maximum", value: "\(m) MHz") }
                    if let c = sys.cpu.cacheL3Bytes, c > 0 {
                        InfoRow(label: "L3-cache", value: Fmt.bytes(c, binary: true))
                    }
                    if let g = sys.cpu.governor, !g.isEmpty { InfoRow(label: "Governor", value: g) }
                    if let f = sys.cpu.flagsNotable, !f.isEmpty {
                        InfoRow(label: "Features", value: f.joined(separator: " "), mono: false)
                    }
                }

                if let s = app.latest {
                    InfoCard(title: "Geheugen", symbol: "memorychip.fill", tint: Theme.C.blue) {
                        InfoRow(label: "Totaal", value: Fmt.bytes(s.memory.total, binary: app.prefs.binaryUnits))
                        InfoRow(label: "In gebruik", value: Fmt.bytes(s.memory.used, binary: app.prefs.binaryUnits))
                        InfoRow(label: "Beschikbaar", value: Fmt.bytes(s.memory.available, binary: app.prefs.binaryUnits))
                        InfoRow(label: "Cache", value: Fmt.bytes(s.memory.cached, binary: app.prefs.binaryUnits))
                        InfoRow(label: "Buffers", value: Fmt.bytes(s.memory.buffers, binary: app.prefs.binaryUnits))
                        InfoRow(label: "Swap",
                                value: s.memory.swapTotal == 0 ? "geen"
                                     : "\(Fmt.bytes(s.memory.swapUsed)) / \(Fmt.bytes(s.memory.swapTotal))")
                    }
                }

                NavigationLink { SmartDetailView() } label: {
                    linkCard("Opslag & SMART", "internaldrive.fill", Theme.C.magenta,
                             "Schijven, partities en gezondheid")
                }.buttonStyle(.plain)

                NavigationLink { NetworkDetailView() } label: {
                    linkCard("Netwerkinterfaces", "cable.connector", Theme.C.green,
                             "MAC, MTU, adressen, gateway en DNS")
                }.buttonStyle(.plain)

                NavigationLink { SensorsDetailView() } label: {
                    linkCard("Sensoren", "sensor.fill", Theme.C.teal,
                             "Temperatuur, fans, spanning en vermogen")
                }.buttonStyle(.plain)

                if sys.hasGPU || !(app.latest?.gpu.isEmpty ?? true) {
                    NavigationLink { GPUDetailView() } label: {
                        linkCard("GPU", "cpu.fill", Theme.C.purple, "Belasting, geheugen en temperatuur")
                    }.buttonStyle(.plain)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .navigationTitle("Hardware")
        .navigationBarTitleDisplayMode(.large)
    }

    private func linkCard(_ title: String, _ symbol: String, _ tint: Color, _ subtitle: String) -> some View {
        Card {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.C.text)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.C.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.C.textTertiary)
            }
        }
    }
}

// MARK: - Opslag

struct StorageDetailView: View {
    @Environment(AppState.self) private var app
    let sample: Sample

    private var current: Sample { app.latest ?? sample }

    var body: some View {
        DetailScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lokale opslag").font(.headline).foregroundStyle(Theme.C.text)
                    GaugeBar(fraction: current.storagePercent / 100, gradient: Theme.G.storage, height: 10)
                    HStack {
                        Text("\(Fmt.bytes(current.storageUsed)) / \(Fmt.bytes(current.storageTotal))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.C.textSecondary)
                        Spacer()
                        Text(Fmt.percent(current.storagePercent))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(Theme.C.text)
                    }
                }
            }

            ForEach(current.localStorage) { v in volumeCard(v) }

            if !current.remoteStorage.isEmpty {
                Text("Netwerkmounts")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.C.textTertiary)
                    .padding(.top, 8)
                Text("Deze tellen niet mee in het totaal — het zijn geen lokale schijven.")
                    .font(.caption)
                    .foregroundStyle(Theme.C.textTertiary)
                ForEach(current.remoteStorage) { v in volumeCard(v) }
            }
        }
        .navigationTitle("Storage")
    }

    private func volumeCard(_ v: Sample.Storage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(v.mount)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.C.text)
                    Spacer()
                    Text(v.fstype)
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.C.cardElevated))
                        .foregroundStyle(Theme.C.textSecondary)
                }
                GaugeBar(fraction: v.percent / 100,
                         gradient: v.remote ? Theme.G.load : Theme.G.storage, height: 6)
                HStack {
                    Text("\(Fmt.bytes(v.used)) / \(Fmt.bytes(v.total))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.C.textSecondary)
                    Spacer()
                    Text(Fmt.percent(v.percent))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.C.text)
                }
                if v.readBps > 0 || v.writeBps > 0 {
                    HStack(spacing: 14) {
                        Label(Fmt.speed(v.readBps), systemImage: "arrow.down")
                        Label(Fmt.speed(v.writeBps), systemImage: "arrow.up")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.C.textTertiary)
                }
                Text(v.device)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.C.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - SMART

struct SmartDetailView: View {
    var body: some View {
        AsyncLoad(path: "v1/hardware/smart", refreshInterval: 60) { (r: SmartResult) in
            DetailScroll {
                if r.disks.isEmpty {
                    Text("Geen schijven gevonden of smartmontools ontbreekt op de server.")
                        .font(.footnote).foregroundStyle(Theme.C.textSecondary)
                }
                ForEach(r.disks) { d in
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                IconTile(symbol: d.isSSD ? "internaldrive.fill" : "opticaldiscdrive.fill",
                                         color: Theme.C.magenta)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(d.model.isEmpty ? d.device : d.model)
                                        .font(.headline).foregroundStyle(Theme.C.text)
                                    Text(d.device).font(.caption.monospaced())
                                        .foregroundStyle(Theme.C.textTertiary)
                                }
                                Spacer()
                                if d.error == nil {
                                    Label(d.health, systemImage: d.healthStatus.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(d.healthStatus.color)
                                }
                            }
                            if let e = d.error {
                                Text(e).font(.caption).foregroundStyle(Theme.C.warn)
                            } else {
                                InfoRow(label: "Capaciteit", value: Fmt.bytes(d.sizeBytes))
                                InfoRow(label: "Type", value: d.isSSD ? "SSD / NVMe" : "\(d.rotationRpm ?? 0) RPM")
                                if let p = d.protocolName { InfoRow(label: "Protocol", value: p) }
                                if let t = d.tempC, t > 0 { InfoRow(label: "Temperatuur", value: "\(t) °C") }
                                if let h = d.powerOnHours, h > 0 {
                                    let years = Double(h) / 24 / 365.25
                                    InfoRow(label: "Bedrijfsuren",
                                            value: String(format: "%d u (%.1f jaar)", h, years))
                                }
                                if let c = d.powerCycles, c > 0 { InfoRow(label: "Startcycli", value: "\(c)") }
                                if let u = d.percentageUsed {
                                    InfoRow(label: "Slijtage", value: "\(u)%",
                                            tint: u > 80 ? Theme.C.crit : Theme.C.text)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Opslag & SMART")
    }
}

// MARK: - Netwerk

struct NetworkDetailView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        AsyncLoad(path: "v1/hardware/network", refreshInterval: 30) { (r: NetworkResult) in
            DetailScroll {
                if let s = app.latest {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Live doorvoer").font(.headline).foregroundStyle(Theme.C.text)
                            ZStack(alignment: .topTrailing) {
                                NetworkChart(samples: app.history.elements,
                                             window: app.prefs.historyWindow, height: 150)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Fmt.speed(s.network.txBps)) ↑").foregroundStyle(Theme.C.green)
                                    Text("\(Fmt.speed(s.network.rxBps)) ↓").foregroundStyle(Theme.C.blue)
                                }
                                .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
                InfoCard(title: "Routering", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                         tint: Theme.C.green) {
                    InfoRow(label: "Gateway", value: r.gateway ?? "—")
                    InfoRow(label: "DNS", value: (r.dns ?? []).isEmpty ? "—" : (r.dns ?? []).joined(separator: ", "))
                }

                ForEach(r.interfaces.filter { !$0.virtual }) { nic in nicCard(nic) }

                let virt = r.interfaces.filter { $0.virtual }
                if !virt.isEmpty {
                    Text("Virtuele interfaces (\(virt.count))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.C.textTertiary)
                        .padding(.top, 8)
                    Text("Docker-bridges, veth-paren en tunnels. Hun verkeer loopt óók over de fysieke interface en telt daarom niet mee in het totaal.")
                        .font(.caption).foregroundStyle(Theme.C.textTertiary)
                    ForEach(virt) { nic in nicCard(nic) }
                }
            }
        }
        .navigationTitle("Netwerk")
    }

    private func nicCard(_ nic: NetworkResult.NIC) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusDot(status: nic.state == "up" ? .ok : .warn)
                    Text(nic.name).font(.headline.monospaced()).foregroundStyle(Theme.C.text)
                    Spacer()
                    if let s = nic.speedMbps, s > 0 {
                        Text("\(s) Mb/s").font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.C.textSecondary)
                    }
                }
                if !nic.mac.isEmpty { InfoRow(label: "MAC", value: nic.mac) }
                InfoRow(label: "MTU", value: "\(nic.mtu)")
                ForEach(nic.addresses, id: \.self) { a in
                    InfoRow(label: a.contains(":") ? "IPv6" : "IPv4", value: a)
                }
            }
        }
    }
}

// MARK: - Sensoren

struct SensorsDetailView: View {
    @Environment(AppState.self) private var app
    @State private var filter = "all"

    var body: some View {
        AsyncLoad(path: "v1/hardware/sensors", refreshInterval: 5) { (r: SensorsResult) in
            DetailScroll {
                Picker("Type", selection: $filter) {
                    Text("Alles").tag("all")
                    Text("Temp").tag("temperature")
                    Text("Fans").tag("fan")
                    Text("Spanning").tag("voltage")
                }
                .pickerStyle(.segmented)

                HStack(spacing: 14) {
                    Label("Available \(r.available)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.C.ok)
                    Label("Not Available \(r.unavailable)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Theme.C.crit)
                    Spacer()
                }
                .font(.caption)

                ForEach(r.chips) { chip in
                    let sensors = chip.sensors.filter { filter == "all" || $0.type == filter }
                    if !sensors.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chip.name)
                                    .font(.headline.monospaced())
                                    .foregroundStyle(Theme.C.text)
                                    .padding(.bottom, 6)
                                ForEach(sensors) { s in
                                    HStack(spacing: 10) {
                                        Image(systemName: s.symbol)
                                            .font(.footnote)
                                            .foregroundStyle(s.status.color)
                                            .frame(width: 20)
                                        Text(s.label)
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.C.textSecondary)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        if let h = s.high, h > 0 {
                                            Text("max \(Int(h))")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(Theme.C.textTertiary)
                                        }
                                        Text(s.formatted)
                                            .font(.subheadline.monospacedDigit().weight(.medium))
                                            .foregroundStyle(s.status == .ok ? Theme.C.text : s.status.color)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sensoren")
    }
}

// MARK: - GPU

struct GPUDetailView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DetailScroll {
            let gpus = app.latest?.gpu ?? []
            if gpus.isEmpty {
                EmptyStateView(symbol: "cpu",
                               title: "Geen GPU gevonden",
                               message: "Deze server rapporteert geen losse GPU. NVIDIA vereist nvidia-smi; AMD wordt via sysfs gelezen.")
            }
            ForEach(gpus) { g in
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            IconTile(symbol: "cpu.fill", color: Theme.C.purple)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.name).font(.headline).foregroundStyle(Theme.C.text)
                                Text(g.vendor + (g.driver.map { " · driver \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(Theme.C.textTertiary)
                            }
                        }
                        GaugeBar(fraction: g.utilPercent / 100,
                                 gradient: LinearGradient(colors: [Theme.C.purple, Theme.C.magenta],
                                                          startPoint: .leading, endPoint: .trailing))
                        HStack {
                            Text("Belasting").font(.footnote).foregroundStyle(Theme.C.textSecondary)
                            Spacer()
                            Text(Fmt.percent(g.utilPercent))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(Theme.C.text)
                        }
                        if g.memTotal > 0 {
                            InfoRow(label: "VRAM",
                                    value: "\(Fmt.bytes(g.memUsed)) / \(Fmt.bytes(g.memTotal))")
                        }
                        if let t = g.tempC, t > 0 { InfoRow(label: "Temperatuur", value: "\(Int(t)) °C") }
                        if let p = g.powerW, p > 0 { InfoRow(label: "Vermogen", value: String(format: "%.0f W", p)) }
                        if let f = g.fanPercent, f > 0 { InfoRow(label: "Ventilator", value: "\(Int(f))%") }
                        if let c = g.clockMhz, c > 0 { InfoRow(label: "Klok", value: "\(c) MHz") }
                    }
                }
            }
        }
        .navigationTitle("GPU")
    }
}
