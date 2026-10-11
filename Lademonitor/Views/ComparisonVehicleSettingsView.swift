import SwiftUI

/// Einstellungen → Vergleichsfahrzeug: der Verbrenner, mit dem der Rueckblick
/// die Ersparnis rechnet und mit dem das Verbrenner-Tool startet. Lokal
/// gespeichert (ComparisonVehicleStore), im Server-Modus abgeglichen.
struct ComparisonVehicleSettingsView: View {
    @ObservedObject private var store = ComparisonVehicleStore.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var fuel: CombustionComparison.Fuel
    @State private var consumptionText: String
    @State private var priceText: String
    @State private var gridText: String
    @State private var status: String?
    @State private var statusIsError = false

    private static let consumptionRange = 1.0...30.0
    private static let priceRange = 0.5...5.0
    /// In Gramm je kWh, gespeichert wird kg.
    private static let gridRange = 0.0...1500.0

    init() {
        let stored = ComparisonVehicleStore.shared.vehicle
        _fuel = State(initialValue: stored.fuel)
        _consumptionText = State(initialValue: TariffCalculatorView.number(stored.consumptionLPer100km, digits: 1))
        _priceText = State(initialValue: TariffCalculatorView.number(stored.fuelPricePerL, digits: 2))
        _gridText = State(initialValue: TariffCalculatorView.number(stored.gridCo2KgPerKwh * 1000, digits: 0))
    }

    var body: some View {
        Form {
            Section {
                Picker("Kraftstoff", selection: $fuel) {
                    Text("Benzin").tag(CombustionComparison.Fuel.petrol)
                    Text("Diesel").tag(CombustionComparison.Fuel.diesel)
                }
                .onChange(of: fuel) { _, newFuel in
                    consumptionText = TariffCalculatorView.number(newFuel.defaultConsumption, digits: 1)
                    priceText = TariffCalculatorView.number(newFuel.defaultPrice, digits: 2)
                }
                LabeledContent("Verbrauch") {
                    HStack(spacing: 4) {
                        TextField("7,0" as String, text: $consumptionText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(verbatim: "l/100 km").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Preis pro Liter") {
                    HStack(spacing: 4) {
                        TextField("1,75" as String, text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(verbatim: "€").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Verbrenner")
            } footer: {
                Text("Richtwerte für einen vergleichbaren Kompakt-SUV: Benzin 7,0 l und 1,75 €, Diesel 5,8 l und 1,65 €.")
            }

            Section {
                LabeledContent("CO₂ je kWh Strom") {
                    HStack(spacing: 4) {
                        TextField("360" as String, text: $gridText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(verbatim: "g").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("CO₂")
            } footer: {
                Text("Vorgabe ist der deutsche Strommix (360 g). Mit Ökostrom oder eigener PV-Anlage den Wert entsprechend senken.")
            }

            Section {
                Button("Speichern") { save() }
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Damit rechnet der Rückblick „Gespart gegenüber dem Verbrenner“, und der Vergleich mit Verbrenner startet mit diesen Werten.")
                    if !store.isConfigured {
                        Text("Noch nicht gespeichert – bis dahin gelten die Standardwerte.")
                    }
                    if settings.appMode == .server {
                        Text("Wird mit dem Server abgeglichen (ab Server 0.36.0).")
                    }
                }
            }
        }
        .navigationTitle("Vergleichsfahrzeug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    private func save() {
        guard let consumption = Self.parse(consumptionText), Self.consumptionRange.contains(consumption) else {
            fail(String(localized: "Verbrauch muss zwischen 1 und 30 l/100 km liegen."))
            return
        }
        guard let price = Self.parse(priceText), Self.priceRange.contains(price) else {
            fail(String(localized: "Der Literpreis muss zwischen 0,50 und 5,00 € liegen."))
            return
        }
        guard let grid = Self.parse(gridText), Self.gridRange.contains(grid) else {
            fail(String(localized: "CO₂ je kWh muss zwischen 0 und 1500 g liegen."))
            return
        }
        store.save(ComparisonVehicle(
            fuelType: fuel.rawValue,
            consumptionLPer100km: consumption,
            fuelPricePerL: price,
            gridCo2KgPerKwh: grid / 1000
        ))
        statusIsError = false
        status = String(localized: "Gespeichert.")
        if settings.appMode == .server {
            Task { await SyncService.shared.syncNow() }
        }
    }

    private func fail(_ message: String) {
        statusIsError = true
        status = message
    }
}

#Preview {
    NavigationStack { ComparisonVehicleSettingsView() }
}
