import SwiftUI

/// "Reichweitenrechner": wie weit komme ich von Ladestand A bis Ladestand B
/// bei einer bestimmten Aussentemperatur?
///
/// Der Verbrauch folgt im Server-Modus der Reichweitenkurve des Servers
/// (`TempRange.curve`, Verbrauch ab Akku je Grad) und damit dem
/// Temperaturregler - bis man ihn selbst verschiebt. Ohne Server (oder ohne
/// Kurve) ist der Vorschlag der eigene Durchschnitt des letzten Jahres, dann
/// ohne Temperaturabhaengigkeit. Gerechnet wird bei jeder Reglerbewegung neu
/// (`RangeCalculator`), nichts wird gespeichert oder synchronisiert.
struct RangeCalculatorView: View {
    private enum Field: Identifiable {
        case socStart, socEnd, temperature, consumption, capacity
        var id: Self { self }
    }

    /// Woher der Vorschlag fuer den Verbrauch stammt.
    private enum Source {
        case curve, average, fallback
    }

    private static let socStartRange = 1.0...100.0
    private static let socEndRange = 0.0...99.0
    private static let temperatureRange = -20.0...40.0
    private static let consumptionRange = 10.0...35.0
    private static let capacityRange = 30.0...120.0

    @ObservedObject private var settings = AppSettings.shared

    @State private var vehicles: [Vehicle] = []
    @State private var sessions: [ChargingSession] = []
    @State private var vehicleId: String?
    @State private var loadError: String?
    /// Reichweitenkurve des gewaehlten Fahrzeugs (nur Server-Modus).
    @State private var range: TempRange?

    @State private var socStart = 100.0
    @State private var socEnd = 10.0
    @State private var temperature = 15.0
    /// `nil` = der Verbrauch folgt dem Datenwert; gesetzt, sobald man den
    /// Regler selbst bewegt oder einen Wert eintippt.
    @State private var manualConsumption: Double?
    @State private var manualCapacity = RangeCalculator.fallbackCapacityKwh

    @State private var editingField: Field?
    @State private var editText = ""

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == vehicleId }
    }

    var body: some View {
        Form {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            vehicleSection
            socSection
            conditionsSection
        }
        .safeAreaInset(edge: .top, spacing: 0) { resultCard }
        .navigationTitle("Reichweitenrechner")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: vehicleId) { await loadRange() }
        .onChange(of: vehicleId) { manualConsumption = nil }
        .onChange(of: socStart) {
            // Das Ziel muss unter dem Start bleiben - der Start schiebt es mit.
            if socEnd >= socStart { socEnd = max(socStart - 1, Self.socEndRange.lowerBound) }
        }
        .onChange(of: socEnd) {
            if socEnd >= socStart { socEnd = max(socStart - 1, Self.socEndRange.lowerBound) }
        }
        .alert(Text(editTitle), isPresented: editingBinding) {
            TextField("Wert", text: $editText)
                .keyboardType(editingField == .temperature ? .numbersAndPunctuation : .decimalPad)
            Button("Übernehmen") { applyEdit() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: - Abschnitte

    private var vehicleSection: some View {
        Section {
            if vehicles.count > 1 {
                Picker("Fahrzeug", selection: $vehicleId) {
                    ForEach(vehicles) { vehicle in
                        Text(vehicle.name).tag(Optional(vehicle.id))
                    }
                }
            }
            if let vehicleCapacity {
                LabeledContent("Akkukapazität",
                               value: TariffCalculatorView.number(vehicleCapacity, digits: 1) + " kWh")
            } else {
                SliderRow(
                    title: "Akkukapazität",
                    valueText: TariffCalculatorView.number(manualCapacity, digits: 0) + " kWh",
                    value: $manualCapacity,
                    range: Self.capacityRange,
                    step: 1,
                    marker: RangeCalculator.fallbackCapacityKwh,
                    caption: String(localized: "Am Fahrzeug ist keine Akkukapazität hinterlegt – trag sie in den Einstellungen unter „Fahrzeuge“ ein oder stell sie hier ein."),
                    onEdit: { startEdit(.capacity) }
                )
            }
        } header: {
            Text("Fahrzeug")
        }
    }

    private var socSection: some View {
        Section {
            SliderRow(
                title: "Ladestand Start",
                valueText: TariffCalculatorView.percent(socStart),
                value: $socStart,
                range: Self.socStartRange,
                step: 1,
                marker: 100,
                onEdit: { startEdit(.socStart) }
            )
            SliderRow(
                title: "Ladestand Ziel",
                valueText: TariffCalculatorView.percent(socEnd),
                value: $socEnd,
                range: Self.socEndRange,
                step: 1,
                marker: 10,
                onEdit: { startEdit(.socEnd) }
            )
        } header: {
            Text("Ladestand")
        } footer: {
            Text("Das Ziel bleibt immer unter dem Start. Ein Tipp auf einen Wert erlaubt die genaue Eingabe.")
        }
    }

    private var conditionsSection: some View {
        Section {
            SliderRow(
                title: "Außentemperatur",
                valueText: Self.degrees(temperature),
                value: $temperature,
                range: Self.temperatureRange,
                step: 1,
                marker: 15,
                onEdit: { startEdit(.temperature) }
            )
            VStack(alignment: .leading, spacing: 4) {
                SliderRow(
                    title: "Verbrauch (kWh/100 km)",
                    valueText: TariffCalculatorView.number(consumption, digits: 1),
                    value: consumptionBinding,
                    range: Self.consumptionRange,
                    step: 0.1,
                    marker: suggestion.value,
                    caption: consumptionCaption,
                    onEdit: { startEdit(.consumption) }
                )
                if let lossCaption {
                    Text(lossCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if manualConsumption != nil {
                    Button {
                        manualConsumption = nil
                    } label: {
                        Label("Zurück zum Datenwert", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Bedingungen")
        } footer: {
            if suggestion.source == .curve {
                Text("Der Verbrauch folgt der Außentemperatur, bis du ihn selbst verschiebst.")
            }
        }
    }

    // MARK: - Rechnung

    private var vehicleCapacity: Double? {
        guard let capacity = selectedVehicle?.batteryCapacityKwh, capacity > 0 else { return nil }
        return capacity
    }

    private var capacity: Double { vehicleCapacity ?? manualCapacity }

    /// Vorschlag fuer den Verbrauch: Kurve des Servers bei der gewaehlten
    /// Temperatur, sonst der eigene Durchschnitt, sonst ein Richtwert.
    private var suggestion: (value: Double, source: Source) {
        if let range, let value = RangeCalculator.consumption(at: temperature, curve: range.curve) {
            return (value, .curve)
        }
        if let average = averageConsumption {
            return (average, .average)
        }
        return (RangeCalculator.fallbackConsumption, .fallback)
    }

    /// Wie das Dashboard lokal: geladene kWh / gefahrene km des letzten Jahres,
    /// nur fuer das gewaehlte Fahrzeug (inkl. Ladeverlusten, ohne Temperatur).
    private var averageConsumption: Double? {
        guard let vehicleId else { return nil }
        return TariffCalculator.suggestedConsumption(sessions: sessions.filter { $0.vehicleId == vehicleId })
    }

    private var consumption: Double { manualConsumption ?? suggestion.value }

    private var consumptionBinding: Binding<Double> {
        Binding(
            get: { consumption },
            set: { manualConsumption = $0 }
        )
    }

    private var usableKwh: Double {
        RangeCalculator.usableKwh(capacityKwh: capacity, socStart: socStart, socEnd: socEnd)
    }

    private var rangeKm: Double? {
        RangeCalculator.rangeKm(capacityKwh: capacity, socStart: socStart, socEnd: socEnd,
                                consumptionKwhPer100km: consumption)
    }

    // MARK: - Ergebnis

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reichweite")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(rangeKm.map { "≈ " + TariffCalculatorView.kmText($0) } ?? "–")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(String(format: String(localized: "%1$@ kWh aus dem Akku (%2$@ → %3$@) bei %4$@ kWh/100 km"),
                        TariffCalculatorView.number(usableKwh, digits: 1),
                        TariffCalculatorView.percent(socStart),
                        TariffCalculatorView.percent(socEnd),
                        TariffCalculatorView.number(consumption, digits: 1)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Beschriftungen

    private var consumptionCaption: String {
        if manualConsumption != nil {
            return String(format: String(localized: "Datenwert bei dieser Temperatur: %@ kWh/100 km"),
                          TariffCalculatorView.number(suggestion.value, digits: 1))
        }
        switch suggestion.source {
        case .curve:
            return String(localized: "Aus deinen Fahrten bei dieser Außentemperatur")
        case .average:
            return String(localized: "Durchschnitt des letzten Jahres, ohne Temperatur")
        case .fallback:
            return String(localized: "Kein eigener Wert vorhanden, Richtwert")
        }
    }

    /// Nur, wenn der Vorschlag aus der Kurve stammt - der eigene Durchschnitt
    /// enthaelt die Ladeverluste noch.
    private var lossCaption: String? {
        guard suggestion.source == .curve, let range else { return nil }
        guard let loss = range.lossPct else {
            return String(localized: "Ladeverlust unbekannt – Reichweite eher zu niedrig")
        }
        return String(format: String(localized: "Verbrauch ab Akku (Ladeverlust %@ herausgerechnet)"),
                      TariffCalculatorView.number(loss, digits: 1) + " %")
    }

    // MARK: - Laden

    private func load() async {
        guard AppSettings.shared.isReadyForDataAccess else {
            loadError = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        do {
            let loaded = try await AppRepository.shared.fetchVehicles()
            // Aktive Fahrzeuge zuerst, darunter die mit Akkukapazitaet.
            vehicles = loaded.sorted { a, b in
                if a.isActive != b.isActive { return a.isActive }
                return (a.batteryCapacityKwh != nil) && (b.batteryCapacityKwh == nil)
            }
            // Fahrzeug-IDs vereinheitlicht (lokale UUID vs. Server-ID), damit
            // der Filter je Fahrzeug greift.
            sessions = try LocalDataStore.shared.sessionsWithCanonicalVehicles()
            if vehicleId == nil || !vehicles.contains(where: { $0.id == vehicleId }) {
                vehicleId = vehicles.first?.id
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Reichweitenkurve des Fahrzeugs - ausschliesslich im Server-Modus.
    /// Scheitert der Abruf (aelterer Server, offline, Fahrzeug noch nicht
    /// synchronisiert), gilt einfach der Durchschnitt.
    private func loadRange() async {
        range = nil
        guard settings.appMode == .server, let vehicleId else { return }
        do {
            let stats = try await APIClient.shared.fetchTemperatureStats(vehicleId: vehicleId)
            range = stats.range
        } catch {
            range = nil
        }
    }

    // MARK: - Genaue Eingabe

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingField != nil }, set: { if !$0 { editingField = nil } })
    }

    private var editTitle: String {
        switch editingField {
        case .socStart: return String(localized: "Ladestand Start (%)")
        case .socEnd: return String(localized: "Ladestand Ziel (%)")
        case .temperature: return String(localized: "Außentemperatur (°C)")
        case .consumption: return String(localized: "Verbrauch (kWh/100 km)")
        case .capacity: return String(localized: "Akkukapazität (kWh)")
        case nil: return ""
        }
    }

    private func startEdit(_ field: Field) {
        switch field {
        case .socStart: editText = TariffCalculatorView.number(socStart, digits: 0)
        case .socEnd: editText = TariffCalculatorView.number(socEnd, digits: 0)
        case .temperature: editText = TariffCalculatorView.number(temperature, digits: 0)
        case .consumption: editText = TariffCalculatorView.number(consumption, digits: 1)
        case .capacity: editText = TariffCalculatorView.number(manualCapacity, digits: 0)
        }
        editingField = field
    }

    private func applyEdit() {
        guard let field = editingField else { return }
        editingField = nil
        let normalized = editText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-")
        guard let value = Double(normalized) else { return }
        switch field {
        case .socStart:
            socStart = min(max(value, Self.socStartRange.lowerBound), Self.socStartRange.upperBound)
        case .socEnd:
            socEnd = min(max(value, Self.socEndRange.lowerBound), socStart - 1)
        case .temperature:
            temperature = min(max(value, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        case .consumption:
            if value > 0 { manualConsumption = value }
        case .capacity:
            if value > 0 { manualCapacity = value }
        }
    }

    // MARK: - Formatierung

    private static func degrees(_ v: Double) -> String {
        TariffCalculatorView.number(v, digits: 0) + " °C"
    }
}

#Preview {
    NavigationStack { RangeCalculatorView() }
}
