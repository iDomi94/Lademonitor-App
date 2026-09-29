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

    private enum Field: Identifiable {
        case consumption, price, grid
        var id: Self { self }
    }

    private static let consumptionRange = 3.0...15.0
    private static let priceRange = 1.00...2.50
    private static let gridRange = 0.0...0.60

    @State private var sessions: [ChargingSession] = []
    @State private var loadError: String?
    @AppStorage("combustion.period") private var periodRaw = Period.lastYear.rawValue
    @AppStorage("combustion.fuel") private var fuelRaw = CombustionComparison.Fuel.petrol.rawValue
    @AppStorage("combustion.consumption") private var consumption = CombustionComparison.Fuel.petrol.defaultConsumption
    @AppStorage("combustion.price") private var price = CombustionComparison.Fuel.petrol.defaultPrice
    @AppStorage("combustion.gridCo2") private var gridCo2 = CombustionComparison.defaultGridCo2KgPerKwh

    @State private var editingField: Field?
    @State private var editText = ""

    private var period: Period { Period(rawValue: periodRaw) ?? .lastYear }
    private var fuel: CombustionComparison.Fuel { CombustionComparison.Fuel(rawValue: fuelRaw) ?? .petrol }

    private var basis: CombustionComparison.Basis {
        let since = period == .lastYear ? Calendar.current.date(byAdding: .year, value: -1, to: Date()) : nil
        return CombustionComparison.basis(sessions: sessions, since: since)
    }

    private var result: CombustionComparison.Result {
        CombustionComparison.compute(basis: basis, input: .init(
            litersPer100km: consumption,
            pricePerLiter: price,
            co2KgPerLiter: fuel.co2KgPerLiter,
            gridCo2KgPerKwh: gridCo2
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
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if basis.km > 0 { resultCard }
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
            Text("Vorgabe ist der deutsche Strommix. Mit Ökostrom oder eigener PV-Anlage den Wert entsprechend senken. Beim Kraftstoff zählt nur die Verbrennung (\(TariffCalculatorView.number(fuel.co2KgPerLiter, digits: 2)) kg je Liter), nicht die Herstellung.")
        }
    }

    // MARK: - Ergebnis

    private var resultCard: some View {
        let r = result
        let tint: Color = r.savings > 0.005 ? .green : (r.savings < -0.005 ? .red : .secondary)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    (r.savings >= 0 ? Text("Gespart gegenüber Verbrenner") : Text("Mehrkosten gegenüber Verbrenner"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(TariffCalculatorView.euro(abs(r.savings)))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: r.savings >= 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(tint)
                    .font(.title2)
            }
            Text(String(format: String(localized: "Verbrenner %1$@ (%2$@ l), elektrisch %3$@"),
                        TariffCalculatorView.euro(r.combustionCost),
                        TariffCalculatorView.number(r.liters, digits: 0),
                        TariffCalculatorView.euro(r.electricCost)))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let c = r.combustionCostPer100km, let e = r.electricCostPer100km {
                Text(String(format: String(localized: "Pro 100 km: %1$@ statt %2$@"),
                            TariffCalculatorView.euro(e), TariffCalculatorView.euro(c)))
                    .font(.footnote)
            }
            Text(String(format: String(localized: "CO₂: %1$@ kg statt %2$@ kg"),
                        TariffCalculatorView.number(r.electricCo2Kg, digits: 0),
                        TariffCalculatorView.number(r.combustionCo2Kg, digits: 0)))
                .font(.footnote)
            if let breakEven = r.breakEvenPricePerLiter {
                Text(String(format: String(localized: "Gleich teuer bei %@ pro Liter"), TariffCalculatorView.euro(breakEven)))
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.45), lineWidth: 1))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Laden und Eingabe

    private func load() async {
        do {
            sessions = try await AppRepository.shared.fetchSessions()
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
        case nil: return ""
        }
    }

    private func startEdit(_ field: Field) {
        editingField = field
        switch field {
        case .consumption: editText = TariffCalculatorView.number(consumption, digits: 1)
        case .price: editText = TariffCalculatorView.number(price, digits: 2)
        case .grid: editText = TariffCalculatorView.number(gridCo2 * 1000, digits: 0)
        }
    }

    private func applyEdit() {
        let normalized = editText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value >= 0 else { return }
        switch editingField {
        case .consumption: consumption = value
        case .price: price = value
        case .grid: gridCo2 = value / 1000
        case nil: break
        }
        editingField = nil
    }
}

#Preview {
    NavigationStack { CombustionComparisonView() }
}
