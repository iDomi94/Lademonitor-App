import Foundation
import WidgetKit

/// Schreibt den Stand fuer das Homescreen-Widget (siehe `WidgetSnapshot`).
///
/// Aufgerufen nach jedem Laden des Dashboards, nach jedem Speichern oder
/// Loeschen eines Ladevorgangs und beim Wechsel in den Hintergrund - das
/// Widget selbst hat keinen Datenzugriff. Rechnet aus der lokalen Kopie, also
/// in beiden Modi gleich und ohne Netz.
@MainActor
enum WidgetSnapshotWriter {
    static func refresh(now: Date = Date()) {
        do {
            let store = LocalDataStore.shared
            let calendar = Calendar.current
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let all = try store.fetchSessions(vehicleId: nil, needsReview: nil)
            let month = all.filter { $0.startTime >= monthStart && $0.startTime <= now }
            let canonical = try store.canonicalProviderIds()
            let names = Dictionary(
                try store.fetchProviders().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }
            )

            // Nur Grundgebuehren, die an Ladevorgaengen haengen - wie das
            // Dashboard mit Monatsfilter, ohne die Perioden ohne Vorgang.
            let cost = month.reduce(0.0) { $0 + ($1.priceTotal ?? 0) + ($1.feeShare ?? 0) }
            let kwh = month.reduce(0.0) { $0 + ($1.energyKwh ?? 0) }

            let last = all.filter { $0.startTime <= now }.max { $0.startTime < $1.startTime }
            let lastSession = last.map { s -> WidgetSnapshot.LastSession in
                let providerName = s.providerId.flatMap { names[canonical[$0] ?? $0] }
                let hasCost = s.priceTotal != nil || s.feeShare != nil
                return .init(
                    startTime: s.startTime,
                    energyKwh: s.energyKwh,
                    cost: hasCost ? (s.priceTotal ?? 0) + (s.feeShare ?? 0) : nil,
                    providerName: providerName,
                    socStart: s.socStart,
                    socEnd: s.socEnd
                )
            }

            let snapshot = WidgetSnapshot(
                month: monthStart,
                monthSessions: month.count,
                monthKwh: (kwh * 10).rounded() / 10,
                monthCost: (cost * 100).rounded() / 100,
                lastSession: lastSession,
                updatedAt: now
            )
            if WidgetSnapshot.save(snapshot) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
            }
        } catch {
            // Ein veraltetes Widget ist kein Grund, irgendetwas anderes
            // scheitern zu lassen.
        }
    }
}
