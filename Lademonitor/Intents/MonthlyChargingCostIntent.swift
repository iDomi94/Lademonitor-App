import AppIntents
import Foundation

/// "Was hat Laden diesen Monat gekostet?" - dieselben Zahlen wie das Widget
/// (inkl. Grundgebuehr-Anteil). Gibt die Kosten zusaetzlich als Wert zurueck,
/// damit Kurzbefehle damit weiterrechnen koennen.
nonisolated struct MonthlyChargingCostIntent: AppIntent {
    static let title: LocalizedStringResource = "Was hat Laden diesen Monat gekostet?"
    static let description: IntentDescription? = IntentDescription("Nennt Kosten, kWh und Anzahl der Ladevorgänge im laufenden Monat.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let snapshot = try ChargingShortcuts.monthSnapshot()
        let month = ChargingShortcuts.monthName(snapshot.month)
        let cost = ChargingShortcuts.euroText(snapshot.monthCost)
        let kwh = ChargingShortcuts.kwhText(snapshot.monthKwh)
        let count = snapshot.monthSessions
        let text: LocalizedStringResource
        switch count {
        case 0: text = LocalizedStringResource("Im \(month) noch kein Ladevorgang.")
        case 1: text = LocalizedStringResource("Im \(month) \(cost) für \(kwh) kWh, 1 Ladevorgang.")
        default: text = LocalizedStringResource("Im \(month) \(cost) für \(kwh) kWh, \(count) Ladevorgänge.")
        }
        return .result(value: snapshot.monthCost, dialog: IntentDialog(text))
    }
}
