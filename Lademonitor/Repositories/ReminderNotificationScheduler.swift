import Foundation
import UserNotifications

/// Lokale Mitteilungen fuer die Erinnerungen - in beiden Modi, ohne Server:
/// je Erinnerung eine um 09:00 am naechsten Termin (Faelligkeitsdatum oder
/// km-Prognose, das Fruehere = `nextDueDate`) und eine zu Beginn des Vorlaufs
/// (Faelligkeitsdatum minus `leadDays`), jeweils nur, wenn der Zeitpunkt noch
/// in der Zukunft liegt.
///
/// Geplant wird immer komplett neu (alle eigenen Mitteilungen entfernen, dann
/// anlegen): nach jeder Aenderung an Erinnerungen oder Ladevorgaengen (die
/// km-Prognose haengt an ihnen), nach jedem Sync und beim Start bzw. Wechsel
/// in den Vordergrund. Das ist billig und vermeidet jeden Abgleich.
///
/// Die Server-Mail (notifications.py) ist davon unabhaengig - wer beides
/// eingeschaltet hat, bekommt beides.
@MainActor
enum ReminderNotificationScheduler {
    /// @AppStorage-Schluessel des Schalters in den Einstellungen.
    nonisolated static let enabledKey = "reminderNotificationsEnabled"
    /// Ob schon einmal um Erlaubnis gefragt wurde (nur einmal, beim ersten
    /// Speichern einer Erinnerung).
    private static let askedKey = "reminderNotificationsAsked"
    private static let identifierPrefix = "reminder."
    /// iOS behaelt hoechstens 64 geplante Mitteilungen je App.
    private static let maxPending = 60
    private static let hour = 9

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Nach dem Speichern einer Erinnerung: beim ersten Mal um Erlaubnis
    /// fragen, danach (auch bei Ablehnung) nicht mehr - dann bleibt nur der
    /// Weg ueber die Systemeinstellungen.
    static func requestAuthorizationIfNeeded() async {
        guard isEnabled, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Fire-and-forget fuer Aufrufer ohne async-Kontext.
    static func reschedule() {
        Task { await rescheduleNow() }
    }

    static func rescheduleNow(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard isEnabled, AppSettings.shared.isReadyForDataAccess else { return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let requests = buildRequests(now: now)
        for request in requests {
            try? await center.add(request)
        }
    }

    // MARK: - Aufbau

    private struct Planned {
        let identifier: String
        let fireDay: Date
        let title: String
        let body: String
    }

    private static func buildRequests(now: Date) -> [UNNotificationRequest] {
        let store = LocalDataStore.shared
        guard let reminders = try? store.fetchReminders(),
              !reminders.isEmpty,
              let sessions = try? store.sessionsWithCanonicalVehicles(),
              let vehicles = try? store.fetchVehicles()
        else { return [] }
        let items = LocalReminderCalculator.items(reminders: reminders, sessions: sessions, vehicles: vehicles, today: now)
        let showVehicle = Set(reminders.map(\.vehicleId)).count > 1
        let calendar = Calendar.current

        var planned: [Planned] = []
        for item in items {
            let reminder = item.reminder
            let title = showVehicle && item.vehicleName != nil
                ? "\(reminder.displayTitle) · \(item.vehicleName!)"
                : reminder.displayTitle
            let dueDay = reminder.dueDate.map { calendar.startOfDay(for: $0) }

            if let next = item.state.nextDueDate {
                let body: String
                if let dueDay, dueDay == next {
                    body = String(localized: "Heute fällig.")
                } else if let km = reminder.dueKm {
                    body = String(localized: "Fällig bei \(km.formatted()) km – bei deiner Fahrleistung etwa heute erreicht.")
                } else {
                    body = String(localized: "Heute fällig.")
                }
                planned.append(Planned(identifier: "\(identifierPrefix)\(reminder.id).due", fireDay: next, title: title, body: body))
            }

            if let dueDay, reminder.leadDays > 0,
               let leadDay = calendar.date(byAdding: .day, value: -reminder.leadDays, to: dueDay),
               leadDay != item.state.nextDueDate {
                let dateText = dueDay.formatted(date: .abbreviated, time: .omitted)
                planned.append(Planned(
                    identifier: "\(identifierPrefix)\(reminder.id).lead",
                    fireDay: leadDay,
                    title: title,
                    body: String(localized: "Fällig am \(dateText).")
                ))
            }
        }

        return planned
            .compactMap { p -> (Date, UNNotificationRequest)? in
                guard let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: p.fireDay),
                      fire > now
                else { return nil }
                let content = UNMutableNotificationContent()
                content.title = p.title
                content.body = p.body
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                return (fire, UNNotificationRequest(identifier: p.identifier, content: content, trigger: trigger))
            }
            .sorted { $0.0 < $1.0 }
            .prefix(maxPending)
            .map { $0.1 }
    }
}
