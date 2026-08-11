import SwiftUI

struct DashboardView: View {
    @State private var stats: StatsSummary?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private static let kmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.maximumFractionDigits = 0
        return f
    }()

    private func kmString(_ km: Int) -> String {
        let number = Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(km)"
        return "\(number) km"
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
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(label: "Ladevorgänge", value: "\(stats.totalSessions)")
                        StatCard(label: "Gesamt kWh", value: String(format: "%.1f kWh", stats.totalKwh))
                        StatCard(label: "Gesamtkosten", value: String(format: "%.2f €", stats.totalCost))
                        StatCard(label: "Ø Preis/kWh", value: stats.avgPricePerKwh.map { String(format: "%.3f €", $0) } ?? "–")
                        StatCard(label: "Ø Verbrauch/100km", value: stats.avgConsumptionKwhPer100km.map { String(format: "%.1f kWh", $0) } ?? "–")
                        StatCard(label: "Preis/100km", value: stats.pricePer100km.map { String(format: "%.2f €", $0) } ?? "–")
                        StatCard(label: "Gefahrene Kilometer", value: stats.totalKmDriven.map { kmString($0) } ?? "–")
                    }
                    .padding()

                    if !stats.monthly.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kosten pro Monat")
                                .font(.headline)
                                .padding(.horizontal)
                            MonthlyBarChart(data: stats.monthly.map { ($0.displayMonth, $0.totalCost) }, color: .blue, unit: "€")
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 24)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("kWh pro Monat")
                                .font(.headline)
                                .padding(.horizontal)
                            MonthlyBarChart(data: stats.monthly.map { ($0.displayMonth, $0.totalKwh) }, color: .green, unit: " kWh")
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
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard AppSettings.shared.isConfigured else {
            errorMessage = "Bitte zuerst die Server-Adresse in den Einstellungen eintragen."
            return
        }
        isLoading = true
        do {
            stats = try await APIClient.shared.fetchStatsSummary()
            errorMessage = nil
        } catch {
            // Ein fehlgeschlagener Refresh (z.B. abgebrochene Anfrage beim
            // Pull-to-Refresh) soll die bereits angezeigten Daten nicht
            // verwerfen. Den Fehler-Screen nur zeigen, wenn noch keine Daten
            // geladen wurden.
            if stats == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

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
