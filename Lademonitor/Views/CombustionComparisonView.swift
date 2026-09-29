import SwiftUI

/// "Vergleich mit Verbrenner": was dieselben Kilometer mit Benzin oder Diesel
/// gekostet haetten und wie viel CO2 dabei entstanden waere.
///
/// Grundlage sind die eigenen Ladevorgaenge (km aus dem Kilometerstand, Kosten
/// inkl. Grundgebuehren), das Vergleichsfahrzeug stellt man ueber Regler ein.
/// Rechnung in `CombustionComparison`.
struct CombustionComparisonView: View {
    private enum Period: String, CaseIterable, Identifiable {
        case lastYear, all
        var id: Self { self }
    }

    /// Umschalter ganz oben: dieselben Eingaben, drei Blickwinkel.
    private enum Mode: String, CaseIterable, Identifiable {
        /// Summen ueber den gewaehlten Zeitraum
        case total
        /// Kosten und CO2 je 100 km im Betrieb
        case per100km
        /// Ueber die ganze Laufleistung, inkl. CO2 aus der Herstellung
        case lifecycle
        var id: Self { self }
    }

    private enum Field: Identifiable {
        case consumption, price, grid, lifetime, batteryKwh, batteryCo2
        var id: Self { self }
    }

    private static let consumptionRange = 3.0...15.0
    private static let priceRange = 1.00...2.50
    private static let gridRange = 0.0...0.60
    private static let lifetimeRange = 50_000.0...400_000.0
    private static let batteryKwhRange = 30.0...120.0
    private static let batteryCo2Range = 40.0...150.0

    @State private var sessions: [ChargingSession] = []
    /// Akkukapazitaet des Fahrzeugs als Vorschlag fuer den Lebenszyklus.
    @State private var vehicleBatteryKwh: Double?
    @AppStorage("combustion.mode") private var modeRaw = Mode.per100km.rawValue
    @AppStorage("combustion.lifetimeKm") private var lifetimeKm = CombustionComparison.defaultLifetimeKm
    @AppStorage("combustion.batteryKwh") private var batteryKwh = 0.0
    @AppStorage("combustion.batteryCo2") private var batteryCo2 = CombustionComparison.defaultBatteryCo2KgPerKwh
    @State private var loadError: String?
    @AppStorage("combustion.period") private var periodRaw = Period.lastYear.rawValue
    @AppStorage("combustion.fuel") private var fuelRaw = CombustionComparison.Fuel.petrol.rawValue
    @AppStorage("combustion.consumption") private var consumption = CombustionComparison.Fuel.petrol.defaultConsumption
    @AppStorage("combustion.price") private var price = CombustionComparison.Fuel.petrol.defaultPrice
    @AppStorage("combustion.gridCo2") private var gridCo2 = CombustionComparison.defaultGridCo2KgPerKwh

    @State private var editingField: Field?
    @State private var editText = ""

    private var period: Period { Period(rawValue: periodRaw) ?? .lastYear }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .per100km }
    /// 0 = noch nie eingestellt, dann gilt das Fahrzeug bzw. der Richtwert.
    private var effectiveBatteryKwh: Double {
        batteryKwh > 0 ? batteryKwh : (vehicleBatteryKwh ?? CombustionComparison.defaultBatteryKwh)
    }
    private var fuel: CombustionComparison.Fuel { CombustionComparison.Fuel(rawValue: fuelRaw) ?? .petrol }

    private var basis: CombustionComparison.Basis {
        let since = period == .lastYear ? Calendar.current.date(byAdding: .year, value: -1, to: Date()) : nil
        return CombustionComparison.basis(sessions: sessions, since: since)
    }

    private var input: CombustionComparison.Input {
        .init(
            litersPer100km: consumption,
            pricePerLiter: price,
            co2KgPerLiter: fuel.co2KgPerLiter,
            upstreamCo2KgPerLiter: fuel.upstreamCo2KgPerLiter,
            gridCo2KgPerKwh: gridCo2
        )
    }

    private var result: CombustionComparison.Result {
        CombustionComparison.compute(basis: basis, input: input)
    }

    private var lifecycle: CombustionComparison.Lifecycle {
        CombustionComparison.lifecycle(basis: basis, input: input, lifecycle: .init(
            lifetimeKm: lifetimeKm, batteryKwh: effectiveBatteryKwh, batteryCo2KgPerKwh: batteryCo2
        ))
    }

    var body: some View {
        Form {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            basisSection
            vehicleSection
            co2Section
            if mode == .lifecycle { lifecycleSection }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $modeRaw) {
                    Text("Zeitraum").tag(Mode.total.rawValue)
                    Text("Pro 100 km").tag(Mode.per100km.rawValue)
                    Text("Lebenszyklus").tag(Mode.lifecycle.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                if basis.km > 0 { resultCard }
            }
            .background(.bar)
        }
        .navigationTitle("Vergleich mit Verbrenner")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(Text(editTitle), isPresented: editingBinding) {
            TextField("Wert", text: $editText).keyboardType(.decimalPad)
            Button("Übernehmen") { applyEdit() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: - Abschnitte

    private var basisSection: some View {
        Section {
            Picker("Zeitraum", selection: $periodRaw) {
                Text("Letzte 12 Monate").tag(Period.lastYear.rawValue)
                Text("Gesamte Aufzeichnung").tag(Period.all.rawValue)
            }
            let b = basis
            if b.km > 0 {
                LabeledContent("Gefahren", value: TariffCalculatorView.kmText(b.km))
                LabeledContent("Geladen", value: TariffCalculatorView.number(b.kwh, digits: 0) + " kWh")
                LabeledContent("Bezahlt", value: TariffCalculatorView.euro(b.cost))
            } else {
                Text("Für den Zeitraum fehlen Ladevorgänge mit Kilometerstand.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Deine Daten")
        } footer: {
            Text("Kilometer aus dem Kilometerstand deiner Ladevorgänge, Kosten inklusive Grundgebühren. Was du ohne Preis eingetragen hast (z. B. kostenlos an der Wallbox beim Arbeitgeber), zählt mit 0 €.")
        }
    }

    private var vehicleSection: some View {
        Section {
            Picker("Kraftstoff", selection: $fuelRaw) {
                Text("Benzin").tag(CombustionComparison.Fuel.petrol.rawValue)
                Text("Diesel").tag(CombustionComparison.Fuel.diesel.rawValue)
            }
            .onChange(of: fuelRaw) {
                consumption = fuel.defaultConsumption
                price = fuel.defaultPrice
            }
            SliderRow(
                title: "Verbrauch",
                valueText: TariffCalculatorView.number(consumption, digits: 1) + " l/100 km",
                value: $consumption,
                range: Self.consumptionRange,
                step: 0.1,
                marker: fuel.defaultConsumption,
                onEdit: { startEdit(.consumption) }
            )
            SliderRow(
                title: "Preis pro Liter",
                valueText: TariffCalculatorView.euro(price),
                value: $price,
                range: Self.priceRange,
                step: 0.01,
                marker: fuel.defaultPrice,
                onEdit: { startEdit(.price) }
            )
        } header: {
            Text("Vergleichsfahrzeug")
        } footer: {
            Text("Die Markierung zeigt den Richtwert für einen vergleichbaren Verbrenner. Wartung, Steuer und Wertverlust sind nicht enthalten.")
        }
    }

    private var co2Section: some View {
        Section {
            SliderRow(
                title: "CO₂ je kWh Strom",
                valueText: TariffCalculatorView.number(gridCo2 * 1000, digits: 0) + " g",
                value: $gridCo2,
                range: Self.gridRange,
                step: 0.01,
                marker: CombustionComparison.defaultGridCo2KgPerKwh,
                onEdit: { startEdit(.grid) }
            )
        } header: {
            Text("CO₂")
        } footer: {
            Text("Vorgabe ist der deutsche Strommix. Mit Ökostrom oder eigener PV-Anlage den Wert entsprechend senken. Beim Kraftstoff zählt nur die Verbrennung (\(TariffCalculatorView.number(fuel.co2KgPerLiter, digits: 2)) kg je Liter), ohne Vorkette – die kommt in der Ansicht „Lebenszyklus“ dazu.")
        }
    }

    private var lifecycleSection: some View {
        Section {
            SliderRow(
                title: "Laufleistung",
                valueText: TariffCalculatorView.kmText(lifetimeKm),
                value: $lifetimeKm,
                range: Self.lifetimeRange,
                step: 10_000,
                marker: CombustionComparison.defaultLifetimeKm,
                onEdit: { startEdit(.lifetime) }
            )
            SliderRow(
                title: "Akkugröße",
                valueText: TariffCalculatorView.number(effectiveBatteryKwh, digits: 0) + " kWh",
                value: Binding(get: { effectiveBatteryKwh }, set: { batteryKwh = $0 }),
                range: Self.batteryKwhRange,
                step: 1,
                marker: vehicleBatteryKwh,
                caption: vehicleBatteryKwh != nil
                    ? String(localized: "Markierung: Akkukapazität deines Fahrzeugs")
                    : nil,
                onEdit: { startEdit(.batteryKwh) }
            )
            SliderRow(
                title: "CO₂ je kWh Akku",
                valueText: TariffCalculatorView.number(batteryCo2, digits: 0) + " kg",
                value: $batteryCo2,
                range: Self.batteryCo2Range,
                step: 5,
                marker: CombustionComparison.defaultBatteryCo2KgPerKwh,
                onEdit: { startEdit(.batteryCo2) }
            )
        } header: {
            Text("Lebenszyklus")
        } footer: {
            Text("Die Herstellung des Fahrzeugs ohne Akku zählt für beide gleich (rund 7 t CO₂), beim E-Auto kommt der Akku dazu. Studien nennen dafür 60 bis 100 kg je kWh. Beim Kraftstoff zählt hier zusätzlich die Vorkette (Förderung, Raffinerie, Transport), beim Strom steckt sie schon im Emissionsfaktor. Verbrauch und Kosten pro km kommen aus deinem gewählten Zeitraum.")
        }
    }

    // MARK: - Ergebnis

    private var resultCard: some View {
        let savings = cardSavings
        let tint: Color = savings > 0.005 ? .green : (savings < -0.005 ? .red : .secondary)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(cardTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cardFigure)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: savings >= 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(tint)
                    .font(.title2)
            }
            ForEach(Array(cardLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == cardLines.count - 1 ? .footnote.weight(.semibold) : .footnote)
                    .foregroundStyle(index == 0 ? .secondary : .primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.45), lineWidth: 1))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// Wofuer die Farbe steht: Geld im Zeitraum und je 100 km, CO2 im Lebenszyklus.
    private var cardSavings: Double {
        switch mode {
        case .total: return result.savings
        case .per100km: return (result.combustionCostPer100km ?? 0) - (result.electricCostPer100km ?? 0)
        case .lifecycle: return lifecycle.combustionTotalCo2Kg - lifecycle.electricTotalCo2Kg
        }
    }

    private var cardTitle: String {
        switch mode {
        case .total:
            return result.savings >= 0 ? String(localized: "Gespart gegenüber Verbrenner")
                                       : String(localized: "Mehrkosten gegenüber Verbrenner")
        case .per100km:
            return cardSavings >= 0 ? String(localized: "Pro 100 km günstiger")
                                    : String(localized: "Pro 100 km teurer")
        case .lifecycle:
            let km = TariffCalculatorView.kmText(lifetimeKm)
            return cardSavings >= 0 ? String(format: String(localized: "CO₂ weniger über %@"), km)
                                    : String(format: String(localized: "CO₂ mehr über %@"), km)
        }
    }

    private var cardFigure: String {
        switch mode {
        case .total, .per100km:
            return TariffCalculatorView.euro(abs(cardSavings))
        case .lifecycle:
            return Self.tons(cardSavings)
        }
    }

    private var cardLines: [String] {
        let r = result
        switch mode {
        case .total:
            var lines = [
                String(format: String(localized: "Verbrenner %1$@ (%2$@ l), elektrisch %3$@"),
                       TariffCalculatorView.euro(r.combustionCost),
                       TariffCalculatorView.number(r.liters, digits: 0),
                       TariffCalculatorView.euro(r.electricCost)),
                String(format: String(localized: "CO₂: %1$@ kg statt %2$@ kg"),
                       TariffCalculatorView.number(r.electricCo2Kg, digits: 0),
                       TariffCalculatorView.number(r.combustionCo2Kg, digits: 0)),
            ]
            if let breakEven = r.breakEvenPricePerLiter {
                lines.append(String(format: String(localized: "Gleich teuer bei %@ pro Liter"), TariffCalculatorView.euro(breakEven)))
            }
            return lines
        case .per100km:
            let kwh = CombustionComparison.kwhPerKm(basis) * 100
            let electricCo2 = kwh * gridCo2
            let combustionCo2 = consumption * fuel.co2KgPerLiter
            var lines = [
                String(format: String(localized: "%1$@ kWh statt %2$@ l %3$@"),
                       TariffCalculatorView.number(kwh, digits: 1),
                       TariffCalculatorView.number(consumption, digits: 1),
                       fuel == .petrol ? String(localized: "Benzin") : String(localized: "Diesel")),
                String(format: String(localized: "Kosten: %1$@ statt %2$@"),
                       TariffCalculatorView.euro(r.electricCostPer100km ?? 0),
                       TariffCalculatorView.euro(r.combustionCostPer100km ?? 0)),
                String(format: String(localized: "CO₂: %1$@ kg statt %2$@ kg"),
                       TariffCalculatorView.number(electricCo2, digits: 1),
                       TariffCalculatorView.number(combustionCo2, digits: 1)),
            ]
            if let breakEven = r.breakEvenPricePerLiter {
                lines.append(String(format: String(localized: "Gleich teuer bei %@ pro Liter"), TariffCalculatorView.euro(breakEven)))
            }
            return lines
        case .lifecycle:
            let l = lifecycle
            var lines = [
                String(format: String(localized: "Gesamt %1$@ statt %2$@, davon Herstellung %3$@ statt %4$@"),
                       Self.tons(l.electricTotalCo2Kg), Self.tons(l.combustionTotalCo2Kg),
                       Self.tons(l.electricProductionCo2Kg), Self.tons(l.combustionProductionCo2Kg)),
                String(format: String(localized: "Pro 100 km inkl. Herstellung: %1$@ kg statt %2$@ kg CO₂"),
                       TariffCalculatorView.number(l.electricCo2Per100km, digits: 1),
                       TariffCalculatorView.number(l.combustionCo2Per100km, digits: 1)),
                String(format: String(localized: "Energiekosten: %1$@ statt %2$@"),
                       TariffCalculatorView.euro(l.electricEnergyCost),
                       TariffCalculatorView.euro(l.combustionEnergyCost)),
            ]
            if let km = l.co2BreakEvenKm {
                lines.append(String(format: String(localized: "Herstellungs-Rucksack eingeholt nach %@"),
                                    TariffCalculatorView.kmText((km / 1000).rounded() * 1000)))
            } else {
                lines.append(String(localized: "Im Betrieb nicht sauberer – der Rucksack wird nie eingeholt"))
            }
            return lines
        }
    }

    private static func tons(_ kg: Double) -> String {
        TariffCalculatorView.number(abs(kg) / 1000, digits: 1) + " t"
    }

    // MARK: - Laden und Eingabe

    private func load() async {
        do {
            sessions = try await AppRepository.shared.fetchSessions()
            vehicleBatteryKwh = try await AppRepository.shared.fetchVehicles()
                .compactMap(\.batteryCapacityKwh).first
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingField != nil }, set: { if !$0 { editingField = nil } })
    }

    private var editTitle: String {
        switch editingField {
        case .consumption: return String(localized: "Verbrauch (l/100 km)")
        case .price: return String(localized: "Preis pro Liter (€)")
        case .grid: return String(localized: "CO₂ je kWh (g)")
        case .lifetime: return String(localized: "Laufleistung (km)")
        case .batteryKwh: return String(localized: "Akkugröße (kWh)")
        case .batteryCo2: return String(localized: "CO₂ je kWh Akku (kg)")
        case nil: return ""
        }
    }

    private func startEdit(_ field: Field) {
        editingField = field
        switch field {
        case .consumption: editText = TariffCalculatorView.number(consumption, digits: 1)
        case .price: editText = TariffCalculatorView.number(price, digits: 2)
        case .grid: editText = TariffCalculatorView.number(gridCo2 * 1000, digits: 0)
        case .lifetime: editText = TariffCalculatorView.number(lifetimeKm, digits: 0)
        case .batteryKwh: editText = TariffCalculatorView.number(effectiveBatteryKwh, digits: 0)
        case .batteryCo2: editText = TariffCalculatorView.number(batteryCo2, digits: 0)
        }
    }

    private func applyEdit() {
        let normalized = editText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value >= 0 else { return }
        switch editingField {
        case .consumption: consumption = value
        case .price: price = value
        case .grid: gridCo2 = value / 1000
        case .lifetime: lifetimeKm = max(value, 1)
        case .batteryKwh: batteryKwh = value
        case .batteryCo2: batteryCo2 = value
        case nil: break
        }
        editingField = nil
    }
}

#Preview {
    NavigationStack { CombustionComparisonView() }
}
