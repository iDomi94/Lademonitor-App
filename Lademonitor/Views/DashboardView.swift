import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject private var sessionFilter = SessionFilter.shared
    @State private var stats: StatsSummary?
    /// Nur im Server-Modus gefuellt - siehe TemperatureSection.
    @State private var temperature: TemperatureStats?
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

                    // Verbrauch nach Aussentemperatur. Bewusst NUR im
                    // Server-Modus: die Auswertung kommt fertig aus
                    // /api/stats/temperature, damit sie nicht ein drittes Mal
                    // nachgebaut werden muss (siehe TemperatureStats).
                    if let temperature {
                        TemperatureSection(stats: temperature)
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
            await loadTemperature()
        } catch {
            // Fehlgeschlagener Refresh soll bestehende Daten nicht verwerfen.
            if stats == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Temperaturauswertung nachladen - ausschliesslich im Server-Modus.
    /// Scheitert der Abruf (aelterer Server ohne den Endpunkt, Netzfehler),
    /// bleibt der Abschnitt einfach weg: er ist eine Ergaenzung, kein Grund,
    /// das ganze Dashboard als fehlgeschlagen zu melden.
    private func loadTemperature() async {
        guard AppSettings.shared.appMode == .server else {
            temperature = nil
            return
        }
        do {
            temperature = try await APIClient.shared.fetchTemperatureStats(dateRange: sessionFilter.dateRange)
        } catch {
            temperature = nil
        }
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
    /// Nachkommastellen der Beschriftung. Kosten/kWh pro Monat lesen sich ohne
    /// (Vorgabe), beim Verbrauch je Jahreszeit ginge der ganze Unterschied
    /// verloren (15,4 und 17,9 waeren beide "16").
    var decimals: Int = 0

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
                    Text(String(format: "%.\(decimals)f%@", entry.1, unit))
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

// MARK: - Verbrauch nach Aussentemperatur

/// Gegenstueck zum Temperatur-Abschnitt des Web-Dashboards. Zeigt dieselben
/// drei Marken in einem Bild - ein Punkt je Fahrt (die Streuung), das Mittel
/// je Temperaturklasse (das, was man ablesen soll) und die Ausgleichsgerade
/// (die Zusammenfassung) - plus die Jahreszeiten darunter.
///
/// Die Farben sind bewusst dieselben wie im Web (#3d8ee0/#2ea87f/#bd8a26):
/// eine Stufe dunkler als die sonstigen Akzentfarben, weil ein Feld aus ueber
/// hundert Punkten in den hellen Toenen blendet.
private struct TemperatureSection: View {
    let stats: TemperatureStats

    private static let pointColor  = Color(red: 0.239, green: 0.557, blue: 0.878)
    private static let bucketColor = Color(red: 0.180, green: 0.659, blue: 0.498)
    private static let trendColor  = Color(red: 0.741, green: 0.541, blue: 0.149)

    /// Eckpunkte der Ausgleichskurve, gezeichnet nur ueber den Bereich, in dem
    /// es auch Messpunkte gibt - eine bis 0 Grad verlaengerte Linie ohne
    /// Winterdaten waere eine Behauptung, keine Ablesung.
    ///
    /// Der Server liefert ab 0.25.0 `curve`: zwei Eckpunkte bei der Geraden,
    /// drei beim Knickmodell. Ein aelterer Server kennt das Feld nicht - dann
    /// wird die Gerade wie bisher aus `slope`/`intercept` gebaut.
    private func trendLine(_ trend: TempTrend) -> [(x: Double, y: Double)] {
        if let curve = trend.curve, curve.count > 1 {
            return curve.map { (x: $0.tempC, y: $0.consumption) }
        }
        let temps = stats.points.map(\.tempC)
        guard let minT = temps.min(), let maxT = temps.max(), minT < maxT else { return [] }
        return [minT, maxT].map { (x: $0, y: trend.intercept + trend.slope * $0) }
    }

    /// Woraus die Kennzahl stammt - eine Gerade oder zwei, und bei zweien auch
    /// gleich die Temperatur des geringsten Verbrauchs.
    private func modelDescription(_ trend: TempTrend) -> String {
        guard trend.model == "breakpoint", let breakpoint = trend.breakpointC else {
            return String(localized: "einer Ausgleichsgeraden")
        }
        return String(format: String(localized: "zwei Geraden mit dem geringsten Verbrauch bei %.0f °C"),
                      breakpoint)
    }

    private var seasonData: [(String, Double)] {
        stats.seasons.map { ($0.displayName, $0.avgConsumptionKwhPer100km) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verbrauch nach Außentemperatur")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                if stats.points.isEmpty {
                    Text("Noch keine Ladevorgänge mit Außentemperatur. Der Wert wird beim Einstecken erfasst – die Auswertung füllt sich über die nächsten Wochen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    if let trend = stats.trend {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%+.1f %%", trend.extraPctAt0c))
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundStyle(Self.trendColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mehrverbrauch bei 0 °C statt 20 °C")
                                    .font(.subheadline)
                                Text(String(format: String(localized: "%1$.1f statt %2$.1f kWh/100km laut %3$@ · R² %4$.2f"),
                                            trend.consumptionAt0c, trend.consumptionAt20c,
                                            modelDescription(trend), trend.r2))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                // Der Hinweis gehoert an die Kennzahl, nicht in
                                // eine Fussnote: wer erst im Fruehjahr
                                // angefangen hat zu messen, sieht hier eine
                                // Hochrechnung auf einen Winter, den es in den
                                // Daten gar nicht gibt.
                                if trend.at0cIsExtrapolated == true {
                                    Text("hochgerechnet – so kalt war es in deinen Daten noch nie")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    chart
                        .frame(height: 220)

                    HStack(spacing: 14) {
                        LegendDot(color: Self.pointColor, label: String(localized: "Fahrten"))
                        LegendDot(color: Self.bucketColor,
                                  label: String(localized: "Mittel je \(stats.bucketWidthC) °C"))
                        if stats.trend != nil {
                            LegendDot(color: Self.trendColor, label: String(localized: "Trend"))
                        }
                    }
                    .font(.caption)

                    if stats.sessionsWithoutTemp > 0 {
                        Text("\(stats.sessionsWithoutTemp) Ladevorgänge ohne Temperaturangabe sind nicht enthalten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            if !seasonData.isEmpty {
                Text("Verbrauch nach Jahreszeit")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                // Nullbasiert wie im Web: der Unterschied zwischen 15,4 und
                // 17,9 ist klein, eine abgeschnittene Achse wuerde ihn
                // kuenstlich vergroessern.
                MonthlyBarChart(data: seasonData,
                                color: Self.bucketColor,
                                unit: " kWh",
                                decimals: 1)
                    .padding(.horizontal)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(stats.points) { point in
                PointMark(
                    x: .value("Temperatur", point.tempC),
                    y: .value("kWh/100km", point.consumptionKwhPer100km)
                )
                .foregroundStyle(Self.pointColor.opacity(0.6))
                .symbolSize(24)
            }
            if let trend = stats.trend {
                ForEach(trendLine(trend), id: \.x) { end in
                    LineMark(
                        x: .value("Temperatur", end.x),
                        y: .value("kWh/100km", end.y),
                        series: .value("Serie", "trend")
                    )
                    .foregroundStyle(Self.trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            ForEach(stats.buckets) { bucket in
                LineMark(
                    x: .value("Temperatur", bucket.centerC),
                    y: .value("kWh/100km", bucket.avgConsumptionKwhPer100km),
                    series: .value("Serie", "buckets")
                )
                .foregroundStyle(Self.bucketColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(
                    x: .value("Temperatur", bucket.centerC),
                    y: .value("kWh/100km", bucket.avgConsumptionKwhPer100km)
                )
                .foregroundStyle(Self.bucketColor)
                .symbolSize(60)
            }
        }
        .chartXAxisLabel("°C")
        .chartYAxisLabel("kWh/100km")
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DashboardView()
}
