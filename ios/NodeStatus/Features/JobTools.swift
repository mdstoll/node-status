import SwiftUI

/// Eén meetpunt tijdens een lopende taak. Staat bewust buiten JobRunner:
/// een genest type in een generieke klasse is elders niet aan te spreken.
struct LiveSample: Decodable, Sendable, Identifiable {
    var t: Double
    var bps: Double
    var phase: String
    var id: Double { t }
}

/// Draait een langlopende taak op de server en pollt tot hij klaar is.
/// Speedtest, ping en traceroute duren te lang voor één request/response.
@Observable
@MainActor
final class JobRunner<Result: Decodable & Sendable> {
    enum State {
        case idle, running(String), done(Result), failed(String)
    }
    var state: State = .idle

    var isRunning: Bool { if case .running = state { true } else { false } }

    // Live voortgang tijdens de taak, zodat de app de doorvoer kan tonen in
    // plaats van dertig seconden een spinner.
    var completion: Double = 0
    var liveBps: Double = 0
    var pingMs: Double = 0
    var samples: [LiveSample] = []

    func run(app: AppState, body: [String: String]) async {
        state = .running(T("starting…", "starten…"))
        completion = 0; liveBps = 0; pingMs = 0; samples = []
        do {
            let api = try app.clientForSelected()
            let job = try await api.post("v1/jobs", body: JobBody(body), as: JobStatus.self)
            while true {
                // Sneller pollen dan de agent meet (200 ms), zodat de grafiek
                // vloeiend meeloopt zonder de server te belasten.
                try await Task.sleep(for: .milliseconds(350))
                let status = try await api.get("v1/jobs/\(job.jobId)", as: JobEnvelope<Result>.self)
                completion = status.progress
                liveBps = status.liveBps ?? 0
                if let p = status.pingMs, p > 0 { pingMs = p }
                if let sm = status.samples { samples = sm }
                if status.state == "done", let r = status.result {
                    state = .done(r)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
                if status.state == "failed" {
                    state = .failed(status.error ?? T("The task failed.", "De taak is mislukt."))
                    return
                }
                state = .running(status.phase ?? T("working…", "bezig…"))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    struct JobBody: Encodable {
        let values: [String: String]
        init(_ v: [String: String]) { values = v }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Key.self)
            for (k, v) in values {
                // count/max_hops zijn getallen in het API-contract.
                if k == "count" || k == "max_hops", let n = Int(v) {
                    try c.encode(n, forKey: Key(k))
                } else {
                    try c.encode(v, forKey: Key(k))
                }
            }
        }
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ s: String) { stringValue = s }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
    }

    struct JobEnvelope<R: Decodable & Sendable>: Decodable, Sendable {
        var state: String
        var phase: String?
        var progress: Double
        var liveBps: Double?
        var pingMs: Double?
        var samples: [LiveSample]?
        var error: String?
        var result: R?
    }
}

// MARK: - Speedtest

struct SpeedtestView: View {
    @Environment(AppState.self) private var app
    @State private var runner = JobRunner<SpeedtestResult>()
    @State private var confirming = false

    var body: some View {
        DetailScroll {
            switch runner.state {
            case .idle:
                startCard
            case .running(let phase):
                runningCard(phase)
            case .failed(let msg):
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(T("Test failed", "Test mislukt"), systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(Theme.C.warn)
                        Text(msg).font(.footnote).foregroundStyle(Theme.C.textSecondary)
                        Button(T("Retry", "Opnieuw")) { runner.state = .idle }.buttonStyle(.bordered)
                    }
                }
            case .done(let r):
                resultCards(r)
                Button(T("Measure again", "Opnieuw meten")) { runner.state = .idle }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Network Speed")
        .confirmationDialog(T("A speedtest uses 1–3 GB of traffic on this server.", "Een speedtest verbruikt 1–3 GB dataverkeer op deze server."),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(T("Start test", "Test starten")) { Task { await start() } }
            Button(T("Cancel", "Annuleren"), role: .cancel) {}
        }
    }

    private var startCard: some View {
        Card {
            VStack(spacing: 16) {
                Image(systemName: "speedometer")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.C.cyan)
                Text(T("Measure this server's internet speed", "Meet de internetsnelheid van deze server"))
                    .font(.headline).foregroundStyle(Theme.C.text)
                    .multilineTextAlignment(.center)
                Text(T("The test runs on the server itself, not on your phone. It uses 1–3 GB.", "De test draait op de server zelf, niet op je telefoon. Hij verbruikt 1–3 GB en is begrensd op één run per vijf minuten."))
                    .font(.footnote).foregroundStyle(Theme.C.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    if app.prefs.warnBeforeSpeedtest { confirming = true } else { Task { await start() } }
                } label: {
                    Label(T("Start test", "Start test"), systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!(app.system?.hasSpeedtest ?? true))

                if app.system?.hasSpeedtest == false {
                    Text(T("No speedtest tool is installed on this server.", "Op deze server is geen speedtest-tool geïnstalleerd."))
                        .font(.caption).foregroundStyle(Theme.C.warn)
                }
            }
            .padding(.vertical, 10)
        }
    }

    /// Live meting: het grote getal is de doorvoer van dit moment, met een
    /// grafiek eronder die tijdens de test meeloopt. Een spinner vertelt je
    /// niets; dit laat zien wat er gebeurt.
    private func runningCard(_ phase: String) -> some View {
        let isUpload = phase == "upload"
        let tint = isUpload ? Theme.C.green : Theme.C.blue
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(phaseLabel(phase), systemImage: phaseSymbol(phase))
                        .font(.headline)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(Int(runner.completion * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.C.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.bits(runner.liveBps))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if runner.pingMs > 0 {
                        Text(String(format: "ping %.1f ms", runner.pingMs))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.C.textTertiary)
                    }
                }

                GaugeBar(fraction: runner.completion,
                         gradient: LinearGradient(colors: [tint.opacity(0.6), tint],
                                                  startPoint: .leading, endPoint: .trailing),
                         height: 6)

                if runner.samples.count > 1 {
                    ThroughputChart(samples: runner.samples)
                }
            }
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "ping":     T("Latency", "Latency")
        case "download": T("Download", "Download")
        case "upload":   T("Upload", "Upload")
        default:         T("Connecting", "Verbinden")
        }
    }

    private func phaseSymbol(_ phase: String) -> String {
        switch phase {
        case "ping": "timer"
        case "upload": "arrow.up"
        case "download": "arrow.down"
        default: "antenna.radiowaves.left.and.right"
        }
    }

    @ViewBuilder
    private func resultCards(_ r: SpeedtestResult) -> some View {
        HStack(spacing: Theme.M.cardGap) {
            bigStat("Download", Fmt.bits(r.downloadBps), Theme.C.blue, "arrow.down")
            bigStat("Upload", Fmt.bits(r.uploadBps), Theme.C.green, "arrow.up")
        }
        HStack(spacing: Theme.M.cardGap) {
            bigStat("Ping", String(format: "%.1f ms", r.pingMs), Theme.C.orange, "timer")
            bigStat("Jitter", String(format: "%.1f ms", r.jitterMs), Theme.C.purple, "waveform")
        }
        InfoCard(title: T("Details", "Details"), symbol: "info.circle.fill", tint: Theme.C.cyan) {
            InfoRow(label: T("Server", "Server"), value: r.serverName)
            if let c = r.serverCity { InfoRow(label: T("Location", "Locatie"), value: c) }
            if let i = r.isp { InfoRow(label: T("Provider", "Provider"), value: i) }
            if let ip = r.externalIpMasked, !ip.isEmpty {
                InfoRow(label: T("External IP", "Extern IP"), value: app.prefs.maskSensitive ? ip : ip)
            }
            InfoRow(label: T("Packet loss", "Pakketverlies"), value: Fmt.percent(r.packetLoss))
            InfoRow(label: T("Engine", "Engine"), value: r.engine)
        }
        if let url = r.resultUrl, !url.isEmpty, let u = URL(string: url) {
            Link(destination: u) {
                Label(T("View result on speedtest.net", "Resultaat op speedtest.net"), systemImage: "arrow.up.right.square")
                    .font(.footnote)
            }
        }
    }

    private func bigStat(_ label: String, _ value: String, _ color: Color, _ symbol: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label(label, systemImage: symbol)
                    .font(.caption).foregroundStyle(Theme.C.textSecondary)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(color)
            }
        }
    }

    private func start() async {
        await runner.run(app: app, body: ["type": "speedtest"])
    }
}

// MARK: - Ping

struct PingView: View {
    @Environment(AppState.self) private var app
    @State private var runner = JobRunner<PingResult>()
    @State private var target = "1.1.1.1"
    @State private var count = 10

    var body: some View {
        DetailScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(T("Domain or IP address", "Domein of IP-adres"), text: $target)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Stepper(T("Ping count: \(count)", "Aantal pings: \(count)"), value: $count, in: 1...20)
                        .font(.subheadline)
                    Button {
                        Task { await runner.run(app: app, body: ["type": "ping", "target": target, "count": "\(count)"]) }
                    } label: {
                        Label(T("Start ping", "Start ping"), systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(target.isEmpty || runner.isRunning)
                }
            }

            switch runner.state {
            case .running:
                ProgressView().frame(maxWidth: .infinity).padding()
            case .failed(let m):
                Card { Text(m).font(.footnote).foregroundStyle(Theme.C.warn) }
            case .done(let r):
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(r.resolvedIp ?? r.target)
                                .font(.headline.monospaced()).foregroundStyle(Theme.C.text)
                            Spacer()
                            Text("\(r.received)/\(r.sent)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(r.lossPercent > 0 ? Theme.C.warn : Theme.C.ok)
                        }
                        if !r.rttsMs.isEmpty {
                            Sparkline(values: r.rttsMs, color: Theme.C.blue, height: 60)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.M.cardGap) {
                    stat(T("Average", "Gemiddeld"), String(format: "%.1f ms", r.avgMs), Theme.C.blue)
                    stat(T("Minimum", "Minimum"), String(format: "%.1f ms", r.minMs), Theme.C.ok)
                    stat(T("Maximum", "Maximum"), String(format: "%.1f ms", r.maxMs), Theme.C.orange)
                    stat(T("Loss", "Verlies"), Fmt.percent(r.lossPercent),
                         r.lossPercent > 0 ? Theme.C.crit : Theme.C.ok)
                }
            case .idle:
                EmptyView()
            }
        }
        .navigationTitle("Ping")
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(Theme.C.textSecondary)
                Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            }
        }
    }
}

// MARK: - DNS

struct DNSView: View {
    @Environment(AppState.self) private var app
    @State private var runner = JobRunner<DNSResult>()
    @State private var domain = ""
    @State private var record = "A"
    @State private var server = ""

    private let records = ["A", "AAAA", "MX", "TXT", "NS", "CNAME", "SOA", "CAA"]

    var body: some View {
        DetailScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("example.com", text: $domain)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Picker(T("Type", "Type"), selection: $record) {
                        ForEach(records, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(T("DNS server (empty = system)", "DNS-server (leeg = systeem)"), text: $server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                    Button {
                        var body = ["type": "dns", "target": domain, "record": record]
                        if !server.isEmpty { body["server"] = server }
                        Task { await runner.run(app: app, body: body) }
                    } label: {
                        Label(T("Query DNS", "Query DNS"), systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(domain.isEmpty || runner.isRunning)
                }
            }

            switch runner.state {
            case .running: ProgressView().frame(maxWidth: .infinity).padding()
            case .failed(let m): Card { Text(m).font(.footnote).foregroundStyle(Theme.C.warn) }
            case .done(let r):
                HStack {
                    Text(T("\(r.answers.count) answers", "\(r.answers.count) antwoorden")).font(.footnote)
                        .foregroundStyle(Theme.C.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f ms · %@", r.queryMs, r.server))
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.C.textTertiary)
                }
                ForEach(r.answers) { a in
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.type)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.C.blue.opacity(0.2)))
                                    .foregroundStyle(Theme.C.blue)
                                Spacer()
                                Text("TTL \(a.ttl)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.C.textTertiary)
                            }
                            Text(a.value)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Theme.C.text)
                                .textSelection(.enabled)
                        }
                    }
                }
            case .idle: EmptyView()
            }
        }
        .navigationTitle("DNS Query")
    }
}

// MARK: - Traceroute

struct TracerouteView: View {
    @Environment(AppState.self) private var app
    @State private var runner = JobRunner<TracerouteResult>()
    @State private var target = "1.1.1.1"

    var body: some View {
        DetailScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(T("Domain or IP address", "Domein of IP-adres"), text: $target)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button {
                        Task { await runner.run(app: app, body: ["type": "traceroute", "target": target]) }
                    } label: {
                        Label(T("Start traceroute", "Start traceroute"), systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(target.isEmpty || runner.isRunning)
                }
            }
            switch runner.state {
            case .running:
                VStack(spacing: 8) {
                    ProgressView()
                    Text(T("May take up to a minute", "Kan tot een minuut duren")).font(.caption)
                        .foregroundStyle(Theme.C.textTertiary)
                }
                .frame(maxWidth: .infinity).padding()
            case .failed(let m): Card { Text(m).font(.footnote).foregroundStyle(Theme.C.warn) }
            case .done(let r):
                let maxRTT = r.hops.compactMap(\.avg).max() ?? 1
                ForEach(r.hops) { h in
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(h.number)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(Theme.C.textTertiary)
                                    .frame(width: 22, alignment: .leading)
                                Text(h.host)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(h.host == "*" ? Theme.C.textTertiary : Theme.C.text)
                                Spacer()
                                if let a = h.avg {
                                    Text(String(format: "%.1f ms", a))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.C.textSecondary)
                                }
                            }
                            if let a = h.avg, maxRTT > 0 {
                                GaugeBar(fraction: a / maxRTT, gradient: Theme.G.cpu, height: 4)
                            }
                        }
                    }
                }
            case .idle: EmptyView()
            }
        }
        .navigationTitle("Traceroute")
    }
}

// MARK: - WHOIS

struct WhoisView: View {
    @Environment(AppState.self) private var app
    @State private var runner = JobRunner<WhoisResult>()
    @State private var domain = ""
    @State private var showRaw = false

    var body: some View {
        DetailScroll {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(T("Domain or IP", "Domein of IP"), text: $domain)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button {
                        Task { await runner.run(app: app, body: ["type": "whois", "target": domain]) }
                    } label: {
                        Label(T("Query", "Query"), systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(domain.isEmpty || runner.isRunning)
                }
            }
            switch runner.state {
            case .running: ProgressView().frame(maxWidth: .infinity).padding()
            case .failed(let m): Card { Text(m).font(.footnote).foregroundStyle(Theme.C.warn) }
            case .done(let r):
                InfoCard(title: r.query, symbol: "globe", tint: Theme.C.orange) {
                    if let v = r.registrar { InfoRow(label: T("Registrar", "Registrar"), value: v, mono: false) }
                    if let v = r.created { InfoRow(label: T("Created", "Aangemaakt"), value: v) }
                    if let v = r.updated { InfoRow(label: T("Updated", "Gewijzigd"), value: v) }
                    if let v = r.expires { InfoRow(label: T("Expires", "Verloopt"), value: v, tint: Theme.C.warn) }
                }
                if !r.nameServers.isEmpty {
                    InfoCard(title: T("Name servers", "Nameservers"), symbol: "network", tint: Theme.C.blue) {
                        ForEach(r.nameServers, id: \.self) { ns in
                            InfoRow(label: "NS", value: ns)
                        }
                    }
                }
                DisclosureGroup(T("Raw WHOIS output", "Ruwe WHOIS-uitvoer"), isExpanded: $showRaw) {
                    Text(r.raw)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.C.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(Theme.C.accent)
                .padding(Theme.M.cardPadding)
                .background(RoundedRectangle(cornerRadius: Theme.M.cardRadius, style: .continuous)
                    .fill(Theme.C.card))
            case .idle: EmptyView()
            }
        }
        .navigationTitle("WHOIS")
    }
}
