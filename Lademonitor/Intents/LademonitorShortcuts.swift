import AppIntents
import Foundation

/// Die Kurzbefehle fuer Siri, Spotlight und die Kurzbefehle-App. Jede Phrase
/// muss den App-Namen enthalten; englische Phrasen in AppShortcuts.xcstrings.
nonisolated struct LademonitorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogChargingSessionIntent(),
            phrases: [
                "Ladevorgang in \(.applicationName) erfassen",
                "Ladung in \(.applicationName) erfassen",
                "\(.applicationName) Ladevorgang erfassen"
            ],
            shortTitle: "Ladevorgang erfassen",
            systemImageName: "bolt.car"
        )
        AppShortcut(
            intent: MonthlyChargingCostIntent(),
            phrases: [
                "Was hat Laden in \(.applicationName) diesen Monat gekostet",
                "Ladekosten diesen Monat in \(.applicationName)",
                "\(.applicationName) Ladekosten"
            ],
            shortTitle: "Ladekosten im Monat",
            systemImageName: "eurosign.circle"
        )
        AppShortcut(
            intent: LastChargingSessionIntent(),
            phrases: [
                "Letzter Ladevorgang in \(.applicationName)",
                "\(.applicationName) letzter Ladevorgang"
            ],
            shortTitle: "Letzter Ladevorgang",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: DueRemindersIntent(),
            phrases: [
                "Was ist in \(.applicationName) fällig",
                "\(.applicationName) Erinnerungen"
            ],
            shortTitle: "Fällige Erinnerungen",
            systemImageName: "bell.badge"
        )
    }
}
