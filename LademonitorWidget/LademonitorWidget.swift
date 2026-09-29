import SwiftUI
import WidgetKit

/// Homescreen-Widget: Kosten und kWh des laufenden Monats, in der mittleren
/// Groesse zusaetzlich der letzte Ladevorgang.
///
/// Das Widget liest nur den Stand, den die App in den gemeinsamen
/// App-Group-Speicher schreibt (`WidgetSnapshot`) - es hat keinen eigenen
/// Datenzugriff, weder auf SwiftData noch auf den Server.
@main
struct LademonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        LademonitorWidget()
    }
}

struct LademonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: SnapshotProvider()) { entry in
            LademonitorWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lademonitor")
        .description("Kosten und Energie des laufenden Monats und der letzte Ladevorgang.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Neue Daten kommen nur ueber die App (reloadTimelines). Zum
        // Monatswechsel trotzdem neu zeichnen, damit nicht der alte Monat
        // stehen bleibt, bis die App das naechste Mal offen war.
        let calendar = Calendar.current
        let now = Date()
        let nextMonth = calendar.date(
            byAdding: .month, value: 1,
            to: calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        ) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: WidgetSnapshot.load())],
                            policy: .after(nextMonth)))
    }
}

struct LademonitorWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Summen eines vergangenen Monats nicht als "diesen Monat" zeigen.
    private var monthValues: (cost: Double, kwh: Double, count: Int) {
        guard let s = entry.snapshot,
              Calendar.current.isDate(s.month, equalTo: entry.date, toGranularity: .month)
        else { return (0, 0, 0) }
        return (s.monthCost, s.monthKwh, s.monthSessions)
    }

    var body: some View {
        if entry.snapshot == nil {
            VStack(alignment: .leading, spacing: 4) {
                Label("Lademonitor", systemImage: "bolt.car")
                    .font(.caption.weight(.semibold))
                Text("Öffne die App einmal, dann erscheinen hier deine Zahlen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            switch family {
            case .systemMedium:
                HStack(alignment: .top, spacing: 16) {
                    monthBlock
                    Divider()
                    lastBlock
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.date, format: .dateTime.month(.wide))
                        .font(.caption2.weight(.semibold))
                    Text(Self.euro(monthValues.cost))
                        .font(.headline)
                    Text(Self.kwh(monthValues.kwh))
                        .font(.caption2)
                }
            default:
                monthBlock
            }
        }
    }

    private var monthBlock: some View {
        let m = monthValues
        return VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(entry.date, format: .dateTime.month(.wide))
            } icon: {
                Image(systemName: "bolt.car")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Self.euro(m.cost))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(Self.kwh(m.kwh))
                .font(.subheadline)
                .monospacedDigit()
            Text("\(m.count) Ladevorgänge")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var lastBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Zuletzt geladen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let last = entry.snapshot?.lastSession {
                Spacer(minLength: 4)
                Text(last.startTime, format: .dateTime.day().month(.abbreviated).hour().minute())
                    .font(.subheadline.weight(.semibold))
                if let name = last.providerName {
                    Text(name).font(.caption).lineLimit(1)
                }
                if let a = last.socStart, let b = last.socEnd {
                    Text(verbatim: "\(a) → \(b) %").font(.caption).monospacedDigit()
                }
                HStack(spacing: 6) {
                    if let e = last.energyKwh { Text(Self.kwh(e)) }
                    if let c = last.cost { Text(Self.euro(c)) }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            } else {
                Text("Noch kein Ladevorgang")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func euro(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2))) + " €"
    }

    static func kwh(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1))) + " kWh"
    }
}

#Preview(as: .systemMedium) {
    LademonitorWidget()
} timeline: {
    SnapshotEntry(date: Date(), snapshot: .placeholder)
}
