import SwiftUI
import Charts

/// De netwerkgrafiek uit de screenshots: twee lijnen met vulling, groen omhoog
/// en blauw omlaag, gestippelde gridlijnen, schaal-labels links in de chart.
struct NetworkChart: View {
    let samples: [Sample]
    var window: Int = 60
    var height: CGFloat = 130

    /// De y-schaal wordt vastgehouden in state en niet elke tick opnieuw
    /// berekend. Anders herschaalt de hele grafiek bij elke piek en lijkt hij
    /// te knipperen — precies wat je niet wilt bij 1 Hz.
    @State private var scaleMax: Double = 64_000
    @State private var lowerSince: Date?

    private struct Point: Identifiable {
        let id: Double
        let x: Double
        let value: Double
        let series: String
    }

    private var now: Double { samples.last?.t ?? Date().timeIntervalSince1970 }

    /// Alleen de samples binnen het zichtbare venster. De ringbuffer bevat er
    /// 300 (5 minuten) terwijl er 60 in beeld zijn: alles tekenen kost onnodig
    /// werk, en een piek van vier minuten geleden zou de schaal opblazen
    /// terwijl je hem niet eens ziet.
    private var visible: [Sample] {
        let cutoff = now - Double(window)
        return samples.filter { $0.t >= cutoff }
    }

    private func points(_ window: [Sample]) -> [Point] {
        window.flatMap { s in
            [Point(id: s.t, x: s.t - now, value: Double(s.network.rxBps), series: "down"),
             Point(id: -s.t, x: s.t - now, value: Double(s.network.txBps), series: "up")]
        }
    }

    private func peak(_ window: [Sample]) -> Double {
        window.flatMap { [Double($0.network.rxBps), Double($0.network.txBps)] }.max() ?? 0
    }

    var body: some View {
        Chart(points(visible)) { p in
            AreaMark(x: .value("t", p.x), y: .value("bps", p.value))
                .foregroundStyle(by: .value("s", p.series))
                .opacity(0.18)
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", p.x), y: .value("bps", p.value))
                .foregroundStyle(by: .value("s", p.series))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(["up": Theme.C.green, "down": Theme.C.blue])
        .chartLegend(.hidden)
        .chartXScale(domain: -Double(window)...0)
        .chartYScale(domain: 0...scaleMax)
        .chartXAxis {
            AxisMarks(values: [-Double(window) * 0.75, -Double(window) * 0.5, -Double(window) * 0.25]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.C.textTertiary.opacity(0.5))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.C.textTertiary.opacity(0.5))
                AxisValueLabel(anchor: .leading) {
                    if let v = value.as(Double.self), v > 0 {
                        Text(Fmt.speed(UInt64(v)))
                            .font(.caption2)
                            .foregroundStyle(Theme.C.textTertiary)
                    }
                }
            }
        }
        // Zonder clip tekenen de lijn en de area-vulling tot buiten het kader.
        .chartPlotStyle { plot in plot.clipped() }
        .frame(height: height)
        .clipped()
        .onChange(of: samples.last?.t ?? 0) { _, _ in updateScale() }
        .onAppear { scaleMax = niceCeil(max(peak(visible) * 1.25, 64_000)) }
    }

    /// Meteen omhoog schalen bij een piek, maar pas omlaag als het tien
    /// seconden rustig is gebleven. Dat voorkomt heen-en-weer springen.
    private func updateScale() {
        let target = niceCeil(max(peak(visible) * 1.25, 64_000))
        if target > scaleMax {
            scaleMax = target
            lowerSince = nil
            return
        }
        guard target < scaleMax else {
            lowerSince = nil
            return
        }
        if let since = lowerSince {
            if Date().timeIntervalSince(since) > 10 {
                scaleMax = target
                lowerSince = nil
            }
        } else {
            lowerSince = Date()
        }
    }

    /// Rondt af op 1, 2 of 5 maal een macht van tien, zodat de aslabels nette
    /// waarden zijn en niet 1,37 M/s.
    private func niceCeil(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(v)))
        let normalized = v / magnitude
        let step: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10
        return step * magnitude
    }
}

/// Kleine lijn zonder assen — gebruikt bij temperatuur, ping-RTT's en de
/// serverlijst.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.C.green
    var filled = true
    var height: CGFloat = 40

    private struct P: Identifiable { let id: Int; let v: Double }

    var body: some View {
        let pts = values.enumerated().map { P(id: $0.offset, v: $0.element) }
        let lo = (values.min() ?? 0)
        let hi = (values.max() ?? 1)
        let pad = max((hi - lo) * 0.2, 0.5)

        Chart(pts) { p in
            if filled {
                AreaMark(x: .value("i", p.id), y: .value("v", p.v))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            LineMark(x: .value("i", p.id), y: .value("v", p.v))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .frame(height: height)
        // Zonder clip loopt de area-vulling door onder de rand van de kaart.
        .clipped()
    }
}

/// Drie lijnen (totaal/user/system) voor het CPU-detailscherm.
struct CPUHistoryChart: View {
    let samples: [Sample]
    var height: CGFloat = 150

    private struct Point: Identifiable {
        let id = UUID()
        let x: Double
        let v: Double
        let series: String
    }

    var body: some View {
        let now = samples.last?.t ?? 0
        let pts = samples.flatMap { s in
            [Point(x: s.t - now, v: s.cpu.total, series: "Totaal"),
             Point(x: s.t - now, v: s.cpu.user, series: "User"),
             Point(x: s.t - now, v: s.cpu.system, series: "System")]
        }
        Chart(pts) { p in
            LineMark(x: .value("t", p.x), y: .value("%", p.v))
                .foregroundStyle(by: .value("s", p.series))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale([
            "Totaal": Theme.C.blue, "User": Theme.C.green, "System": Theme.C.orange,
        ])
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.C.textTertiary.opacity(0.4))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text("\(Int(d))%").font(.caption2).foregroundStyle(Theme.C.textTertiary)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Donut voor de CPU-tijdverdeling in het uptime-scherm.
struct DonutChart: View {
    struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }
    let slices: [Slice]
    var size: CGFloat = 190

    var body: some View {
        Chart(slices) { s in
            SectorMark(angle: .value(s.label, s.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(s.color)
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .frame(width: size, height: size)
    }
}
