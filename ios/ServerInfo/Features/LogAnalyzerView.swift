import SwiftUI

/// Niet journalctl nabouwen, maar in één blik laten zien wáár het druk of fout is.
struct LogAnalyzerView: View {
    @Environment(AppState.self) private var app

    @State private var sources: [LogSourcesResult.Source] = []
    @State private var selected: String?
    @State private var lines: [LogsResult.Line] = []
    @State private var since = "1h"
    @State private var priority = "info"
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?

    private let windows = [("15m", "15 min"), ("1h", "1 uur"), ("24h", "24 uur"), ("7d", "7 dagen")]
    private let levels = [("err", "Error"), ("warning", "Warning"), ("info", "Info"), ("debug", "Debug")]

    var body: some View {
        VStack(spacing: 0) {
            if selected == nil {
                sourceList
            } else {
                logView
            }
        }
        .screenBackground()
        .navigationTitle(selected.map { $0.replacingOccurrences(of: "unit:", with: "") } ?? "Log Analyzer")
        .navigationBarTitleDisplayMode(selected == nil ? .large : .inline)
        .toolbar {
            if selected != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bronnen") { selected = nil; lines = [] }
                }
            }
        }
        .task { await loadSources() }
    }

    // MARK: - Bronkeuze

    private var sourceList: some View {
        List {
            Section {
                ForEach(sources.filter(\.available)) { s in
                    Button {
                        selected = s.id
                        Task { await loadLines() }
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: s.kind == "unit" ? "shippingbox.fill" : "doc.text.fill",
                                     color: s.kind == "unit" ? Theme.C.blue : Theme.C.teal)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.label).foregroundStyle(Theme.C.text)
                                Text(s.kind == "unit" ? "systemd-unit" : "logbestand")
                                    .font(.caption).foregroundStyle(Theme.C.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(Theme.C.textTertiary)
                        }
                    }
                    .listRowBackground(Theme.C.card)
                }
            } header: {
                Text("Beschikbare bronnen")
            } footer: {
                let missing = sources.filter { !$0.available }.count
                Text(missing > 0
                     ? "\(missing) bron(nen) uit de whitelist bestaan niet op deze server en zijn verborgen. De whitelist staat in config.toml."
                     : "Alleen bronnen uit de whitelist in config.toml zijn leesbaar.")
            }
        }
        .listStyle(.insetGrouped)
        .screenBackground()
        .accessoryInset()
        .overlay {
            if sources.isEmpty && !loading {
                EmptyStateView(symbol: "doc.text.magnifyingglass",
                               title: "Geen logbronnen",
                               message: error ?? "Er zijn geen bronnen beschikbaar op deze server.")
            }
        }
    }

    // MARK: - Logweergave

    private var logView: some View {
        VStack(spacing: 0) {
            filterBar
            summaryStrip
            Divider().overlay(Theme.C.hairline)
            if loading && lines.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if lines.isEmpty {
                EmptyStateView(symbol: "text.magnifyingglass",
                               title: "Geen regels",
                               message: "Geen logregels in dit tijdvenster met dit niveau.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in logRow(line) }
                    }
                    .padding(.bottom, 90)
                }
            }
        }
        .searchable(text: $query, prompt: "Zoek in regels")
        .onSubmit(of: .search) { Task { await loadLines() } }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Venster", selection: $since) {
                ForEach(windows, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: since) { Task { await loadLines() } }

            Picker("Niveau", selection: $priority) {
                ForEach(levels, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: priority) { Task { await loadLines() } }
        }
        .padding(.horizontal, Theme.M.screenMargin)
        .padding(.vertical, 8)
    }

    /// Tellingen per niveau: een piek moet meteen opvallen.
    private var summaryStrip: some View {
        HStack(spacing: 16) {
            counter("Error", lines.filter { $0.priority <= 3 }.count, Theme.C.crit)
            counter("Warning", lines.filter { $0.priority == 4 }.count, Theme.C.warn)
            counter("Info", lines.filter { $0.priority >= 5 }.count, Theme.C.textSecondary)
            Spacer()
            if loading { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, Theme.M.screenMargin)
        .padding(.bottom, 8)
    }

    private func counter(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(n)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.C.text)
            Text(label).font(.caption).foregroundStyle(Theme.C.textTertiary)
        }
    }

    private func logRow(_ line: LogsResult.Line) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(line.status.color)
                .frame(width: 3)
                .opacity(line.priority <= 4 ? 1 : 0.25)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.level)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(line.status.color)
                    Text(Fmt.ago(line.t))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.C.textTertiary)
                    if let pid = line.pid {
                        Text("[\(pid)]")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.C.textTertiary)
                    }
                }
                Text(line.message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.C.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.M.screenMargin)
        .padding(.vertical, 6)
        .background(Theme.C.base)
    }

    // MARK: - Laden

    private func loadSources() async {
        loading = true
        defer { loading = false }
        do {
            let api = try app.clientForSelected()
            sources = try await api.get("v1/tools/logs/sources", as: LogSourcesResult.self).sources
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadLines() async {
        guard let source = selected else { return }
        loading = true
        defer { loading = false }
        do {
            let api = try app.clientForSelected()
            var path = "v1/tools/logs?source=\(source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source)&lines=300&since=\(since)&priority=\(priority)"
            if !query.isEmpty,
               let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                path += "&q=\(q)"
            }
            lines = try await api.get(path, as: LogsResult.self).lines.reversed()
        } catch {
            self.error = error.localizedDescription
            lines = []
        }
    }
}
