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
/// Ladevorgangsliste. Aufbau wie eine Zeile der Ladevorgangsliste
/// (`SessionRow`): links Kopfzeile, Fahrzeug/Anbieter/Ort, SoC, Ladebalken
/// mit den roten Markierungen aus den Ladebalken-Einstellungen; rechts kWh,
/// Gesamtpreis und Preis je kWh - alles mit "~" als Schaetzung markiert.
/// Nicht antippbar - der Vorgang ist noch kein Datensatz, es gibt nichts zu
/// bearbeiten.
struct ActiveChargingCard: View {
    let item: ActiveCharging

    @ObservedObject private var capabilities = ServerCapabilities.shared

    // Ladebalken-Einstellungen (nur lokal, siehe ChargeBarSettingsView) -
    // dieselben roten Markierungen wie in der Liste.
    @AppStorage(ChargeBarSettings.lowerMarkerEnabledKey) private var lowerMarkerEnabled = true
    @AppStorage(ChargeBarSettings.lowerMarkerKey) private var lowerMarker = ChargeBarSettings.defaultLowerMarker
    @AppStorage(ChargeBarSettings.upperMarkerEnabledKey) private var upperMarkerEnabled = true
    @AppStorage(ChargeBarSettings.upperMarkerKey) private var upperMarker = ChargeBarSettings.defaultUpperMarker

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

    /// Wie `SessionRow.detailsLine`: SoC-Verlauf, Kilometerstand - dazu, was
    /// es nur beim laufenden Vorgang gibt (Leistung, Temperatur).
    private var detailsLine: String {
        var parts: [String] = []
        switch (item.socStart, item.socCurrent) {
        case let (start?, now?):
            parts.append(String(localized: "SoC \(start) → \(now) %"))
        case let (start?, nil):
            parts.append(String(localized: "SoC ab \(start) %"))
        case let (nil, now?):
            parts.append(String(localized: "SoC bis \(now) %"))
        default:
            break
        }
        if let km = item.odometerKm {
            parts.append(km.formatted(.number) + " km")
        }
        if let kw = item.maxPowerKw, kw > 0 {
            parts.append(String(format: String(localized: "max. %.1f kW"), kw))
        }
        if let temp = item.outsideTempC {
            parts.append(String(format: "%.1f °C", temp))
        }
        return parts.joined(separator: " · ")
    }

    private var subtitle: String {
        [item.vehicleName, item.providerName, item.locationName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var metaLine: String {
        var parts = [item.sourceLabel]
        if let updated = item.updatedAt {
            parts.append(String(format: String(localized: "Stand %@"), Self.when(updated)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Label("Lädt gerade", systemImage: "bolt.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse)
                    if let start = item.startTime {
                        Text(String(format: String(localized: "seit %@"), Self.when(start)))
                            .font(.subheadline)
                    }
                    if let type = item.chargingType.flatMap(ChargingType.init(rawValue:)) {
                        ChargingTypeBadge(type: type)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !detailsLine.isEmpty {
                    Text(detailsLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let start = item.socStart, let now = item.socCurrent, now >= start {
                    ChargeBar(
                        socStart: start,
                        socEnd: now,
                        lowerMarker: lowerMarkerEnabled ? lowerMarker : nil,
                        upperMarker: upperMarkerEnabled ? upperMarker : nil
                    )
                    .padding(.vertical, 2)
                }
                Text(metaLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let kwh = item.energyKwh {
                    Text((item.energyIsEstimated ? "~" : "") + String(format: "%.1f kWh", kwh))
                        .font(.subheadline)
                }
                if let hint = capabilities.unavailableHint(.activeChargingPrice) {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120, alignment: .trailing)
                } else {
                    if let total = item.priceTotal {
                        Text(String(format: "~%.2f €", total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let perKwh = item.pricePerKwh {
                        Text(String(format: "~%.3f €/kWh", perKwh))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if item.pricePerKwh != nil {
                        Text(item.priceIsAverage ? "Ø-Preis geschätzt" : "geschätzt")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
