import SwiftUI
import Charts

/// Tools → "Rueckblick": ein Jahr oder ein Monat in Zahlen - die grossen
/// Kennzahlen mit Vergleich zur Vorperiode, die Ersparnis gegenueber dem
/// Verbrenner, Rekorde und die Verteilung.
///
/// Lokal gerechnet (LocalReviewCalculator), auch im Local-Only-Modus und
/// ohne Verbindung - nach denselben Regeln wie GET /api/stats/review, damit
/// App und Web dieselben Zahlen zeigen. Zeilen ohne Daten fallen weg, statt
/// "–" zu zeigen.
struct ReviewView: View {
    @ObservedObject private var comparisonStore = ComparisonVehicleStore.shared

    @State private var basis: ReviewBasis?
    @State private var loadError: String?
    @AppStorage("review.period") private var periodRaw = Review.Period.year.rawValue
    @State private var year = ReviewView.defaultYear()
    /// Schluessel `Jahr * 100 + Monat`, damit ein einziger Picker reicht.
    @State private var monthKey = ReviewView.defaultMonthKey()
    @State private var vehicleId: String?
    @State private var appliedDefaults = false

    private var period: Review.Period { Review.Period(rawValue: periodRaw) ?? .year }

    /// Ab dem 1. Dezember das laufende Jahr, sonst das Vorjahr - wie die
    /// Kachel im Web.
    private static func defaultYear(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) == 12 ? year : year - 1
    }

    /// Der Vormonat - der letzte vollstaendige.
    private static func defaultMonthKey(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        return calendar.component(.year, from: previous) * 100 + calendar.component(.month, from: previous)
    }

    /// Unverstellt gilt das Vergleichsfahrzeug mit Standardwerten - wie im
    /// Server, der dann `configured: false` meldet.
    private var comparison: ComparisonVehicle {
        comparisonStore.isConfigured ? comparisonStore.vehicle : ComparisonVehicle.defaults()
    }

    private var review: Review? {
        guard let basis else { return nil }
        switch period {
        case .year:
            return LocalReviewCalculator.compute(
                basis: basis, period: .year, year: year, month: nil,
                vehicleId: vehicleId, comparison: comparison
            )
        case .month:
            return LocalReviewCalculator.compute(
                basis: basis, period: .month, year: monthKey / 100, month: monthKey % 100,
                vehicleId: vehicleId, comparison: comparison
            )
        }
    }

    private var vehicles: [Vehicle] {
        let all = basis?.vehicles ?? []
        return all.filter(\.isActive) + all.filter { !$0.isActive }
    }

    var body: some View {
        List {
            selectionSection
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            if let review {
                if review.totals.sessions == 0 {
                    Section {
                        Text("Für diesen Zeitraum gibt es keine Ladevorgänge.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    figuresSection(review)
                    savingsSection(review)
                    recordsSection(review)
                    splitSection(review)
                    monthlySection(review)
                }
            } else if loadError == nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Rückblick")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Auswahl

    private var selectionSection: some View {
        Section {
            Picker("Zeitraum", selection: $periodRaw) {
                Text("Jahr").tag(Review.Period.year.rawValue)
                Text("Monat").tag(Review.Period.month.rawValue)
            }
            .pickerStyle(.segmented)
            if period == .year {
                Picker("Jahr", selection: $year) {
                    ForEach(yearOptions, id: \.self) { option in
                        Text(verbatim: String(option)).tag(option)
                    }
                }
            } else {
                Picker("Monat", selection: $monthKey) {
                    ForEach(monthOptions, id: \.self) { key in
                        Text(Self.monthTitle(key)).tag(key)
                    }
                }
            }
            if vehicles.count > 1 {
                Picker("Fahrzeug", selection: $vehicleId) {
                    Text("Alle Fahrzeuge").tag(String?.none)
                    ForEach(vehicles) { vehicle in
                        Text(vehicle.name).tag(Optional(vehicle.id))
                    }
                }
            }
        }
    }

    private var yearOptions: [Int] {
        var years = LocalReviewCalculator.availableYears(sessions: basis?.sessions ?? [])
        if !years.contains(year) { years.append(year) }
        return years.sorted(by: >)
    }

    /// Vom laufenden Monat zurueck bis zum ersten Ladevorgang (ohne Daten:
    /// die letzten 12 Monate), neueste zuerst.
    private var monthOptions: [Int] {
        let calendar = Calendar.current
        let now = Date()
        func key(_ date: Date) -> Int {
            calendar.component(.year, from: date) * 100 + calendar.component(.month, from: date)
        }
        var keys: [Int] = []
        var cursor = now
        let oldest: Int
        if let earliest = basis?.sessions.map(\.startTime).min() {
            oldest = key(earliest)
        } else {
            oldest = key(calendar.date(byAdding: .month, value: -11, to: now) ?? now)
        }
        // Obergrenze nur als Schutz gegen voellig verirrte Datumsangaben.
        while key(cursor) >= oldest && keys.count < 600 {
            keys.append(key(cursor))
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        if !keys.contains(monthKey) { keys.append(monthKey) }
        return keys.sorted(by: >)
    }

    // MARK: - Die grossen Zahlen

    private struct Figure: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let value: String
        let delta: String?
    }

    private func figures(_ r: Review) -> [Figure] {
        let t = r.totals
        let p = r.previous
        var list: [Figure] = [
            Figure(id: "sessions", title: "Ladevorgänge", value: String(t.sessions),
                   delta: delta(Double(t.sessions), p.map { Double($0.sessions) })),
        ]
        if t.kwh > 0 {
            list.append(Figure(id: "kwh", title: "Geladen",
                               value: TariffCalculatorView.number(t.kwh, digits: 0) + " kWh",
                               delta: delta(t.kwh, p?.kwh)))
        }
        if t.cost > 0 {
            list.append(Figure(id: "cost", title: "Kosten", value: TariffCalculatorView.euro(t.cost),
                               delta: delta(t.cost, p?.cost)))
        }
        if t.km > 0 {
            list.append(Figure(id: "km", title: "Gefahren", value: TariffCalculatorView.kmText(t.km),
                               delta: delta(t.km, p?.km)))
        }
        if let price = t.avgPricePerKwh, t.cost > 0 {
            list.append(Figure(id: "price", title: "Ø Preis je kWh", value: TariffCalculatorView.perKwh(price),
                               delta: delta(price, p?.avgPricePerKwh)))
        }
        if let per100 = t.pricePer100km, t.cost > 0 {
            list.append(Figure(id: "per100", title: "Kosten je 100 km", value: TariffCalculatorView.euro(per100),
                               delta: delta(per100, p?.pricePer100km)))
        }
        if let consumption = t.avgConsumptionKwhPer100km {
            list.append(Figure(id: "consumption", title: "Ø Verbrauch",
                               value: TariffCalculatorView.number(consumption, digits: 1) + " kWh/100 km",
                               delta: delta(consumption, p?.avgConsumptionKwhPer100km)))
        }
        return list
    }

    /// "+12 % ggü. Vorjahr" - nur, wenn die Vorperiode einen Wert hat.
    private func delta(_ current: Double, _ previous: Double?) -> String? {
        guard let previous, previous > 0 else { return nil }
        let pct = (current - previous) / previous * 100
        let rounded = pct.rounded()
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "±")
        let text = sign + abs(rounded).formatted(.number.precision(.fractionLength(0))) + " %"
        if period == .year {
            return String(format: String(localized: "%@ ggü. Vorjahr"), text)
        }
        return String(format: String(localized: "%@ ggü. Vormonat"), text)
    }

    private func figuresSection(_ r: Review) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(figures(r)) { figure in
                    FigureTile(title: figure.title, value: figure.value, delta: figure.delta)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(periodTitle(r))
        } footer: {
            if r.previous == nil {
                if r.period == .year {
                    Text("Im Vorjahr gibt es keine Ladevorgänge zum Vergleichen.")
                } else {
                    Text("Im Vormonat gibt es keine Ladevorgänge zum Vergleichen.")
                }
            } else {
                Text("Kosten inklusive Grundgebühren, Kilometer aus dem Kilometerstand deiner Ladevorgänge.")
            }
        }
    }

    private func periodTitle(_ r: Review) -> String {
        if let month = r.month { return Self.monthTitle(r.year * 100 + month) }
        return String(r.year)
    }

    // MARK: - Ersparnis

    @ViewBuilder
    private func savingsSection(_ r: Review) -> some View {
        if let s = r.savings {
            Section {
                if s.savedEur >= 0 {
                    LabeledContent("Gespart", value: TariffCalculatorView.euro(s.savedEur))
                } else {
                    LabeledContent("Mehrkosten", value: TariffCalculatorView.euro(abs(s.savedEur)))
                }
                Text(String(format: String(localized: "Verbrenner %1$@ (%2$@ l), elektrisch %3$@"),
                            TariffCalculatorView.euro(s.fuelCost),
                            TariffCalculatorView.number(s.fuelLiters, digits: 0),
                            TariffCalculatorView.euro(s.chargingCost)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if s.savedCo2Kg >= 0 {
                    LabeledContent("CO₂ gespart", value: Self.co2Text(s.savedCo2Kg))
                } else {
                    LabeledContent("CO₂ mehr", value: Self.co2Text(abs(s.savedCo2Kg)))
                }
                Text(String(format: String(localized: "CO₂: %1$@ kg statt %2$@ kg"),
                            TariffCalculatorView.number(s.co2EvKg, digits: 0),
                            TariffCalculatorView.number(s.co2CombustionKg, digits: 0)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !s.configured {
                    NavigationLink {
                        ComparisonVehicleSettingsView()
                    } label: {
                        Label("Vergleichsfahrzeug festlegen", systemImage: "fuelpump")
                    }
                }
            } header: {
                Text("Gegenüber dem Verbrenner")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !s.configured {
                        Text("Gerechnet mit Standardwerten, weil noch kein Vergleichsfahrzeug gespeichert ist.")
                    }
                    Text(String(format: String(localized: "%1$@, %2$@ l/100 km, %3$@ pro Liter, Strom %4$@ g CO₂/kWh. Nur der Betrieb (Tank-to-Wheel), ohne Herstellung."),
                                s.fuel == .petrol ? String(localized: "Benzin") : String(localized: "Diesel"),
                                TariffCalculatorView.number(s.consumptionLPer100km, digits: 1),
                                TariffCalculatorView.euro(s.fuelPricePerL),
                                TariffCalculatorView.number(s.gridCo2KgPerKwh * 1000, digits: 0)))
                }
            }
        }
    }

    private static func co2Text(_ kg: Double) -> String {
        if kg >= 1000 { return TariffCalculatorView.number(kg / 1000, digits: 1) + " t" }
        return TariffCalculatorView.number(kg, digits: 0) + " kg"
    }

    // MARK: - Rekorde

    private var showsVehicleNames: Bool { vehicleId == nil && vehicles.count > 1 }

    private func detail(_ record: Review.SessionRecord) -> String {
        var parts = [record.startTime.formatted(date: .abbreviated, time: .omitted)]
        if let place = record.place { parts.append(place) }
        if showsVehicleNames, let name = record.vehicleName { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private func namedDetail(_ record: Review.NamedRecord) -> String {
        String(format: String(localized: "%1$@ Ladevorgänge · %2$@ kWh"),
               String(record.sessions), TariffCalculatorView.number(record.kwh, digits: 0))
    }

    private func hasRecords(_ r: Review) -> Bool {
        let x = r.records
        return x.cheapestPerKwh != nil || x.mostExpensivePerKwh != nil || x.biggestCharge != nil
            || x.longestDistance != nil || x.coldest != nil || x.warmest != nil
            || x.topLocation != nil || x.topProvider != nil
            || x.lowestConsumptionMonth != nil || x.highestConsumptionMonth != nil
    }

    @ViewBuilder
    private func recordsSection(_ r: Review) -> some View {
        if hasRecords(r) {
            let x = r.records
            Section("Rekorde") {
                if let rec = x.cheapestPerKwh {
                    RecordRow(title: "Günstigster Ladevorgang", value: TariffCalculatorView.perKwh(rec.value), detail: detail(rec))
                }
                if let rec = x.mostExpensivePerKwh {
                    RecordRow(title: "Teuerster Ladevorgang", value: TariffCalculatorView.perKwh(rec.value), detail: detail(rec))
                }
                if let rec = x.biggestCharge {
                    RecordRow(title: "Größte Ladung", value: TariffCalculatorView.number(rec.value, digits: 1) + " kWh", detail: detail(rec))
                }
                if let rec = x.longestDistance {
                    RecordRow(title: "Längste Strecke zwischen zwei Ladungen",
                              value: TariffCalculatorView.kmText(rec.value),
                              detail: distanceDetail(rec))
                }
                if let rec = x.coldest {
                    RecordRow(title: "Kältester Ladetag", value: Self.temperature(rec.value), detail: detail(rec))
                }
                if let rec = x.warmest {
                    RecordRow(title: "Wärmster Ladetag", value: Self.temperature(rec.value), detail: detail(rec))
                }
                if let top = x.topLocation {
                    RecordRow(title: "Meistgenutzter Ladeort", value: top.name, detail: namedDetail(top))
                }
                if let top = x.topProvider {
                    RecordRow(title: "Meistgenutzter Anbieter", value: top.name, detail: namedDetail(top))
                }
                if let rec = x.lowestConsumptionMonth {
                    RecordRow(title: "Geringster Verbrauch",
                              value: TariffCalculatorView.number(rec.value, digits: 1) + " kWh/100 km",
                              detail: Self.monthName(rec.month))
                }
                if let rec = x.highestConsumptionMonth {
                    RecordRow(title: "Höchster Verbrauch",
                              value: TariffCalculatorView.number(rec.value, digits: 1) + " kWh/100 km",
                              detail: Self.monthName(rec.month))
                }
            }
        }
    }

    private func distanceDetail(_ record: Review.SessionRecord) -> String {
        let to = record.startTime.formatted(date: .abbreviated, time: .omitted)
        var parts: [String] = []
        if let from = record.previousStartTime?.formatted(date: .abbreviated, time: .omitted) {
            parts.append(from + " – " + to)
        } else {
            parts.append(to)
        }
        if showsVehicleNames, let name = record.vehicleName { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private static func temperature(_ value: Double) -> String {
        TariffCalculatorView.number(value, digits: 1) + " °C"
    }

    // MARK: - Verteilung

    @ViewBuilder
    private func splitSection(_ r: Review) -> some View {
        let s = r.split
        if s.acSharePct != nil || !s.byPlace.isEmpty {
            Section("Verteilung") {
                if let ac = s.acSharePct, let dc = s.dcSharePct {
                    LabeledContent("AC") {
                        Text(TariffCalculatorView.percent(ac) + " · " + TariffCalculatorView.number(s.acKwh, digits: 0) + " kWh")
                            .monospacedDigit()
                    }
                    LabeledContent("DC") {
                        Text(TariffCalculatorView.percent(dc) + " · " + TariffCalculatorView.number(s.dcKwh, digits: 0) + " kWh")
                            .monospacedDigit()
                    }
                }
                ForEach(s.byPlace) { place in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(TariffCalculatorView.number(place.totalKwh, digits: 0) + " kWh · " + TariffCalculatorView.euro(place.totalCost))
                                .monospacedDigit()
                            if let price = place.avgPricePerKwh {
                                Text(TariffCalculatorView.perKwh(price))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Text(place.place.displayName)
                    }
                }
            }
        }
    }

    // MARK: - Monate

    @ViewBuilder
    private func monthlySection(_ r: Review) -> some View {
        if r.period == .year, r.monthly.contains(where: { $0.kwh > 0 }) {
            Section("kWh je Monat") {
                Chart(r.monthly) { row in
                    BarMark(
                        x: .value("Monat", Self.shortMonthName(row.month)),
                        y: .value("kWh", row.kwh)
                    )
                    .foregroundStyle(Color.teal)
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Monatsnamen

    private static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.standaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : String(month)
    }

    private static func shortMonthName(_ month: Int) -> String {
        let symbols = Calendar.current.shortStandaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : String(month)
    }

    private static func monthTitle(_ key: Int) -> String {
        monthName(key % 100) + " " + String(key / 100)
    }

    // MARK: - Laden

    private func load() async {
        do {
            let loaded = try await AppRepository.shared.reviewBasis()
            basis = loaded
            loadError = nil
            if !appliedDefaults {
                appliedDefaults = true
                // Ohne Ladevorgang im Vorjahr (noch neu dabei) lieber das laufende.
                let calendar = Calendar.current
                let currentYear = calendar.component(.year, from: Date())
                let hasDefaultYear = loaded.sessions.contains { calendar.component(.year, from: $0.startTime) == year }
                if !hasDefaultYear, year != currentYear {
                    year = currentYear
                }
            }
            if let vehicleId, !loaded.vehicles.contains(where: { $0.id == vehicleId }) {
                self.vehicleId = nil
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct FigureTile: View {
    let title: LocalizedStringKey
    let value: String
    let delta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let delta {
                Text(delta)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }
}

private struct RecordRow: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(value)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { ReviewView() }
}
