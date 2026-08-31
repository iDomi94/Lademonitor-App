import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject private var sessionFilter = SessionFilter.shared
    @State private var stats: StatsSummary?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingFilterSheet = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private static let kmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        f.maximumFractionDigits = 0
        return f
    }()

    private func kmString(_ km: Int) -> String {
        let number = Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(km)"
        return "\(number) km"
    }

    /// Verbrauchsdaten chronologisch (aeltester Monat zuerst), Monate ohne Wert ausgelassen.
    private func consumptionPoints(_ monthly: [MonthlyStat]) -> [ConsumptionPoint] {
        monthly.reversed().compactMap { m in
            m.avgConsumptionKwhPer100km.map {
                ConsumptionPoint(id: m.month, label: m.shortMonth, value: $0)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Keine Verbindung", systemImage: "wifi.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Erneut versuchen") { Task { await load() } }
                    }
                    .padding(.top, 60)
                } else if let stats {
                    // Kennzahlen-Grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(label: String(localized: "Ladevorgänge"), value: "\(stats.totalSessions)")
                        StatCard(label: String(localized: "Gesamt kWh"), value: String(format: "%.1f kWh", stats.totalKwh))
                        StatCard(label: String(localized: "Gesamtkosten"), value: String(format: "%.2f €", stats.totalCost))
                        StatCard(label: String(localized: "Ø Preis/kWh"), value: stats.avgPricePerKwh.map { String(format: "%.3f €", $0) } ?? "–")
                        StatCard(label: String(localized: "Ø Verbrauch/100km"), value: stats.avgConsumptionKwhPer100km.map { String(format: "%.1f kWh", $0) } ?? "–")
                        StatCard(label: String(localized: "Preis/100km"), value: stats.pricePer100km.map { String(format: "%.2f €", $0) } ?? "–")
                        StatCard(label: String(localized: "Gefahrene Kilometer"), value: stats.totalKmDriven.map { kmString($0) } ?? "–")
                    }
                    .padding()

                    // AC/DC-Balken
                    if let acKwh = stats.acKwh, let dcKwh = stats.dcKwh, acKwh + dcKwh > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AC / DC-Aufteilung")
                                .font(.headline)
                                .padding(.horizontal)
                            AcDcBar(acKwh: acKwh, dcKwh: dcKwh)
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                    }

                    // Anbieter-Kuchendiagramme
                    if !stats.byProvider.isEmpty {
                        ProviderPieChartsSection(providers: stats.byProvider)
                            .padding(.bottom, 24)
                    }

                    // Ø Verbrauch/100km pro Monat (vertikal, chronologisch)
                    let points = consumptionPoints(stats.monthly)
                    if !points.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ø Verbrauch/100km")
                                .font(.headline)
                                .padding(.horizontal)
                            MonthlyConsumptionChart(points: points)
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                    }

                    // Kosten & kWh pro Monat (horizontal)
                    if !stats.monthly.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kosten pro Monat")
                                .font(.headline)
                                .padding(.horizontal)
                            MonthlyBarChart(
                                data: stats.monthly.map { ($0.displayMonth, $0.totalCost) },
                                color: .blue,
                                unit: "€"
                            )
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("kWh pro Monat")
                                .font(.headline)
                                .padding(.horizontal)
                            MonthlyBarChart(
                                data: stats.monthly.map { ($0.displayMonth, $0.totalKwh) },
                                color: .green,
                                unit: " kWh"
                            )
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                    }
                } else if isLoading {
                    ProgressView("Lade Statistiken…")
                        .padding(.top, 60)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                FilterToolbarItem(isPresented: $showingFilterSheet)
            }
            .task(id: sessionFilter.dateRange) { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showingFilterSheet) {
                FilterSheetView()
            }
        }
    }

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            errorMessage = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        isLoading = true
        do {
            stats = try await AppRepository.shared.fetchStatsSummary(dateRange: sessionFilter.dateRange)
            errorMessage = nil
        } catch {
            // Fehlgeschlagener Refresh soll bestehende Daten nicht verwerfen.
            if stats == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - AC/DC Linear Bar

private struct AcDcBar: View {
    let acKwh: Double
    let dcKwh: Double

    private var total: Double { acKwh + dcKwh }
    private var acFraction: Double { acKwh / total }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: max(geo.size.width * acFraction - 1, 0))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange)
                }
            }
            .frame(height: 24)
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 10, height: 10)
                    Text(String(format: "AC  %.0f%% · %.1f kWh", acFraction * 100, acKwh))
                        .font(.caption)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(String(format: "DC  %.0f%% · %.1f kWh", (1 - acFraction) * 100, dcKwh))
                        .font(.caption)
                    Circle().fill(Color.orange).frame(width: 10, height: 10)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Provider Pie Charts

/// Zeigt zwei Donut-Diagramme (kWh und Kosten pro Anbieter).
/// Gleicher Anbieter hat in beiden dieselbe Farbe.
/// "Ohne Anbieter"-Eintraege fliessen immer in "Andere" ein, nie als eigene Slice.
private struct ProviderPieChartsSection: View {
    let providers: [ProviderStat]

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .red, .teal, .pink, .indigo]
    /// Lokalisierte Anzeige-Bezeichnung fuer die zusammengefasste "Sonstige"-Slice
    /// (siehe entries). Als eigene Konstante gehalten, damit Erzeugung und der
    /// Grau-Farbvergleich in colorRange immer denselben (lokalisierten) Wert nutzen.
    private static let otherLabel = String(localized: "Andere")

    /// Grouping-Logik:
    /// 1. "Ohne Anbieter" herausfiltern
    /// 2. Top 5 der verbleibenden echten Anbieter als Einzelslices
    /// 3. Anbieter ab Platz 6 + "Ohne Anbieter"-Daten → gemeinsamer "Andere"-Posten
    private var entries: [(name: String, kwh: Double, cost: Double)] {
        let named    = providers.filter { $0.providerName != "Ohne Anbieter" }
        let noName   = providers.filter { $0.providerName == "Ohne Anbieter" }

        let top      = named.prefix(5).map { (name: $0.providerName, kwh: $0.totalKwh, cost: $0.totalCost) }
        let overflow = named.dropFirst(5).map { (name: $0.providerName, kwh: $0.totalKwh, cost: $0.totalCost) }
        let noNameMapped = noName.map { (name: $0.providerName, kwh: $0.totalKwh, cost: $0.totalCost) }

        let otherItems = overflow + noNameMapped
        guard !otherItems.isEmpty else { return Array(top) }

        let otherKwh  = otherItems.reduce(0.0) { $0 + $1.kwh }
        let otherCost = otherItems.reduce(0.0) { $0 + $1.cost }
        return Array(top) + [(name: Self.otherLabel, kwh: otherKwh, cost: otherCost)]
    }

    private var colorDomain: [String] { entries.map(\.name) }

    private var colorRange: [Color] {
        entries.enumerated().map { (i, e) in
            e.name == Self.otherLabel ? .gray : Self.palette[i % Self.palette.count]
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ProviderPieChart(
                title: String(localized: "kWh pro Anbieter"),
                data: entries.map { ($0.name, $0.kwh) },
                unit: "kWh",
                colorDomain: colorDomain,
                colorRange: colorRange
            )
            ProviderPieChart(
                title: String(localized: "Bezahlt pro Anbieter"),
                data: entries.map { ($0.name, $0.cost) },
                unit: "€",
                colorDomain: colorDomain,
                colorRange: colorRange
            )
        }
        .padding(.horizontal)
    }
}

/// Interaktives Donut-Diagramm: Antippen eines Segments hebt es hervor
/// und zeigt Name + Wert im Donut-Loch. Erneutes Antippen oder Tap ausserhalb
/// hebt die Auswahl wieder auf.
private struct ProviderPieChart: View {
    let title: String
    let data: [(String, Double)]
    let unit: String
    let colorDomain: [String]
    let colorRange: [Color]

    @State private var selectedValue: Double?
    @State private var selectedName: String?

    private var total: Double { data.reduce(0.0) { $0 + $1.1 } }

    /// Bestimmt per kumulativer Summe, zu welchem Segment der Tap-Winkel gehoert.
    private func findSelected(_ value: Double) -> String? {
        var cumulative = 0.0
        for (name, v) in data {
            cumulative += v
            if value < cumulative { return name }
        }
        return data.last?.0
    }

    private func formatValue(_ v: Double) -> String {
        unit == "€"
            ? String(format: "%.2f €", v)
            : String(format: "%.1f kWh", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Chart(data, id: \.0) { entry in
                SectorMark(
                    angle: .value(unit, entry.1),
                    // Kleinerer Innenradius als frueher (0.55) - der Anbieter-Name
                    // braucht mehr radialen Platz als eine Prozentzahl, dickerer Ring gleicht das aus
                    innerRadius: .ratio(0.35),
                    angularInset: 2.0
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Anbieter", entry.0))
                .opacity(selectedName == nil || selectedName == entry.0 ? 1.0 : 0.5)
                // Anbieter-Name statt Prozentzahl direkt auf dem Segment, nur wenn
                // genug Platz vorhanden; schrumpft bei Bedarf statt abgeschnitten zu werden
                .annotation(position: .overlay) {
                    if entry.1 / total >= 0.08 {
                        Text(entry.0)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: 60)
                    }
                }
            }
            .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .chartAngleSelection(value: $selectedValue)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotAnchor = proxy.plotFrame,
                       let name = selectedName,
                       let value = data.first(where: { $0.0 == name })?.1 {
                        let rect = geo[plotAnchor]
                        VStack(spacing: 4) {
                            Text(name)
                                .font(.caption2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(formatValue(value))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: rect.width * 0.45)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                    }
                }
            }
            // Auswahl bleibt nach Finger-Abheben stehen (nil ignorieren).
            // Gleiches Segment nochmal tippen = deselektieren.
            .onChange(of: selectedValue) { _, newValue in
                guard let newValue else { return }
                let tapped = findSelected(newValue)
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedName = (tapped == selectedName) ? nil : tapped
                }
            }
            .frame(height: 260)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Monthly Consumption Chart (vertikal, chronologisch)

private struct ConsumptionPoint: Identifiable {
    let id: String      // "YYYY-MM", eindeutiger Schluessel
    let label: String   // "Aug '26", Achsenbeschriftung
    let value: Double
}

private struct MonthlyConsumptionChart: View {
    let points: [ConsumptionPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Monat", point.label),
                y: .value("kWh/100km", point.value)
            )
            .foregroundStyle(Color.teal)
            .cornerRadius(4)
        }
        .chartYAxisLabel("kWh/100km")
        .frame(height: 180)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Monthly Bar Chart (horizontal)

private struct MonthlyBarChart: View {
    let data: [(String, Double)]
    let color: Color
    let unit: String

    private var maxValue: Double { max(data.map(\.1).max() ?? 0, 0.0001) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(data, id: \.0) { entry in
                HStack {
                    Text(entry.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: max(geo.size.width * (entry.1 / maxValue), 4))
                    }
                    .frame(height: 20)
                    Text(String(format: "%.0f%@", entry.1, unit))
                        .font(.caption)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    DashboardView()
}
