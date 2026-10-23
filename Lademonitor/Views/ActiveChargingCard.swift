import SwiftUI

/// Laedt die laufenden Ladevorgaenge - nur im Server-Modus. Ein Fehler (Server
/// aelter als 0.45.0, Netz weg) liefert einfach eine leere Liste: die Anzeige
/// ist eine Ergaenzung, kein Grund, Dashboard oder Liste scheitern zu lassen.
enum ActiveChargingLoader {
    static func load() async -> [ActiveCharging] {
        guard AppSettings.shared.appMode == .server else { return [] }
        return (try? await APIClient.shared.fetchActiveSessions()) ?? []
    }
}

/// "Lädt gerade": ganz oben im Dashboard und als markierter Eintrag ueber der
/// Ladevorgangsliste. Nicht antippbar - der Vorgang ist noch kein Datensatz,
/// es gibt nichts zu bearbeiten.
struct ActiveChargingCard: View {
    let item: ActiveCharging

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("ddMMHHmm")
        return f
    }()

    private static func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? timeFormatter.string(from: date)
            : dateTimeFormatter.string(from: date)
    }

    private var socText: String? {
        switch (item.socStart, item.socCurrent) {
        case let (start?, now?) where now != start: return "\(start) % → \(now) %"
        case let (start?, _): return "\(start) %"
        case let (nil, now?): return "→ \(now) %"
        default: return nil
        }
    }

    private var detailsLine: String {
        var parts: [String] = []
        if let start = item.startTime {
            parts.append(String(format: String(localized: "seit %@"), Self.when(start)))
        }
        if let socText { parts.append(socText) }
        if let kwh = item.energyKwh {
            parts.append((item.energyIsEstimated ? "~" : "") + String(format: "%.1f kWh", kwh))
        }
        if let kw = item.maxPowerKw, kw > 0 {
            parts.append(String(format: String(localized: "max. %.1f kW"), kw))
        }
        if let km = item.odometerKm {
            parts.append(km.formatted(.number) + " km")
        }
        if let temp = item.outsideTempC {
            parts.append(String(format: "%.1f °C", temp))
        }
        return parts.joined(separator: " · ")
    }

    private var metaLine: String {
        var parts = [item.sourceLabel]
        if let updated = item.updatedAt {
            parts.append(String(format: String(localized: "Stand %@"), Self.when(updated)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("Lädt gerade", systemImage: "bolt.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse)
                if let name = item.vehicleName {
                    Text(name).font(.subheadline.bold())
                }
                if let type = item.chargingType.flatMap(ChargingType.init(rawValue:)) {
                    ChargingTypeBadge(type: type)
                }
            }
            if !detailsLine.isEmpty {
                Text(detailsLine)
                    .font(.subheadline)
            }
            if let start = item.socStart, let now = item.socCurrent, now >= start {
                ChargeBar(socStart: start, socEnd: now)
                    .padding(.vertical, 2)
            }
            Text(metaLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.green).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
