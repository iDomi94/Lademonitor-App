import SwiftUI
import Charts

/// "Akku und Ladeverluste": Akku-Index je Quartal und der Mehrbedarf beim
/// Laden gegenueber der Akkukapazitaet, nach Lade-Art und Anbieter.
///
/// Nur im Server-Modus - die Auswertung kommt fertig aus
/// `/api/stats/battery` (siehe `BatteryStats`).
struct BatteryHealthView: View {
    @State private var stats: BatteryStats?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var vehicleId: String?

    private var isServerMode: Bool { AppSettings.shared.appMode == .server }

    private var vehicles: [BatteryVehicleStats] {
        (stats?.vehicles ?? []).filter { !$0.points.isEmpty }
    }

    private var selected: BatteryVehicleStats? {
        vehicles.first { $0.vehicleId == vehicleId } ?? vehicles.first
    }

    var body: some View {
        List {
            if !isServerMode {
                ContentUnavailableView(
                    "Nur mit Server",
                    systemImage: "server.rack",
                    description: Text("Die Auswertung rechnet der Lademonitor-Server. Im Modus „Nur lokal auf diesem Gerät“ steht sie nicht zur Verfügung.")
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Nicht verfügbar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Erneut versuchen") { Task { await load() } }
                }
            } else if let v = selected {
                if vehicles.count > 1 {
                    Picker("Fahrzeug", selection: $vehicleId) {
                        ForEach(vehicles) { Text($0.vehicleName).tag(Optional($0.vehicleId)) }
                    }
                }
                healthSection(v)
                lossSection(title: "Nach Lade-Art", groups: v.lossesByType, nominal: v.nominalCapacityKwh)
                lossSection(title: "Nach Anbieter", groups: v.lossesByProvider, nominal: v.nominalCapacityKwh)
                Section {
                    Text("Grundlage sind nur Ladevorgänge mit echter kWh-Angabe (Rechnung, Wallbox, Import) und mindestens \(v.minSocDelta) Prozentpunkten SoC-Hub. Die scheinbare Kapazität ist, was eine Ladung von 0 auf 100 % am Zähler kosten würde. Der Verlust ist der Mehrbedarf gegenüber der Akkukapazität des Fahrzeugs – bei einem gealterten Akku fällt er etwas zu klein aus; belastbar ist vor allem der Unterschied zwischen AC und DC.")
                    if v.excluded.total > 0 {
                        Text("\(v.excluded.total) Ladevorgänge nicht berücksichtigt, davon \(v.excluded.estimatedEnergy) mit geschätzter Energie")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "Noch keine Daten",
                    systemImage: "battery.25percent",
                    description: Text("Es gibt noch keine Ladevorgänge mit gemessener kWh-Angabe und ausreichend SoC-Hub. Automatisch erkannte Vorgänge zählen nicht mit, ihre Energie ist selbst geschätzt.")
                )
            }
        }
        .navigationTitle("Akku und Ladeverluste")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func healthSection(_ v: BatteryVehicleStats) -> some View {
        Section {
            if let index = v.healthLatestIndexPct {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.percent(index, digits: 0))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Akku-Index gegenüber Beginn der Aufzeichnung, letztes Quartal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let trend = v.healthTrendPctPerYear {
                        Text(String(format: String(localized: "Trend %@ pro Jahr"),
                                    (trend > 0 ? "+" : "") + Self.percent(trend, digits: 1)))
                            .font(.footnote.weight(.semibold))
                    }
                }
                .accessibilityElement(children: .combine)
                Chart(v.healthPeriods) { p in
                    BarMark(x: .value("Quartal", p.label), y: .value("Index", p.indexPct))
                        .foregroundStyle(.green)
                        .annotation(position: .top) {
                            Text(TariffCalculatorView.number(p.indexPct, digits: 1))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            } else {
                Text("Für einen Verlauf reichen die Daten noch nicht (mindestens drei Ladevorgänge je Lade-Art und zwei je Quartal).")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Akku-Gesundheit")
        } footer: {
            Text("100 % = wie zu Beginn der Aufzeichnung. AC und DC werden getrennt auf ihren eigenen Anfang bezogen. Kein absoluter Gesundheitswert (SoH), zeigt aber, ob der Akku mit der Zeit weniger aufnimmt.")
        }
    }

    @ViewBuilder
    private func lossSection(title: LocalizedStringKey, groups: [BatteryLossGroup], nominal: Double?) -> some View {
        if !groups.isEmpty {
            Section {
                ForEach(groups) { g in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.groupLabel(g.key))
                            Text(String(format: String(localized: "%1$lld Vorgänge · scheinbar %2$@ kWh"),
                                        g.sessionCount, TariffCalculatorView.number(g.apparentCapacityKwh, digits: 1)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(g.lossPct.map { ($0 > 0 ? "+" : "") + Self.percent($0, digits: 1) } ?? "–")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                }
            } header: {
                Text(title)
            } footer: {
                if nominal == nil {
                    Text("Ohne hinterlegte Akkukapazität am Fahrzeug lassen sich keine Verluste in Prozent angeben.")
                }
            }
        }
    }

    private static func groupLabel(_ key: String) -> String {
        switch key {
        case "": return String(localized: "Ohne Anbieter")
        case "unknown": return String(localized: "Lade-Art unbekannt")
        default: return key
        }
    }

    private static func percent(_ v: Double, digits: Int) -> String {
        TariffCalculatorView.number(v, digits: digits) + " %"
    }

    private func load() async {
        guard isServerMode else { return }
        isLoading = true
        do {
            stats = try await APIClient.shared.fetchBatteryStats()
            errorMessage = nil
        } catch {
            // Aelterer Server ohne den Endpunkt oder keine Verbindung.
            if stats == nil {
                errorMessage = String(localized: "Die Auswertung braucht Lademonitor-Server 0.28.0 oder neuer und eine Verbindung dorthin.")
            }
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack { BatteryHealthView() }
}
