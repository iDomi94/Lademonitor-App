import Foundation

/// Gemeinsame Logik der Kurzbefehle (App Intents). Liest und schreibt nur die
/// lokale Kopie - kein Netz, damit alles auch bei gesperrtem Geraet und im
/// Hintergrund funktioniert. Im Server-Modus bleibt ein neuer Vorgang dirty
/// und geht beim naechsten Sync aus der App mit hoch.
enum ChargingShortcuts {

    // MARK: - Voraussetzungen

    static func ensureDataAccess() throws {
        let settings = AppSettings.shared
        guard settings.appMode != .undecided, settings.isReadyForDataAccess else {
            throw ShortcutError.notSetUp
        }
        if settings.appMode == .server, !SessionManager.shared.isAuthenticated {
            throw ShortcutError.notSignedIn
        }
    }

    // MARK: - Ladevorgang erfassen

    /// Legt den Vorgang so an, wie ihn das Formular vorbelegt (Fahrzeug,
    /// jetzt, AC), mit gemessener Energie und `needsReview`, damit er in der
    /// Liste als zu pruefen auffaellt.
    static func logSession(energyKwh: Double, priceTotal: Double, now: Date = Date()) async throws -> ChargingSession {
        try ensureDataAccess()
        guard energyKwh.isFinite, energyKwh > 0 else { throw ShortcutError.invalidEnergy }
        guard priceTotal.isFinite, priceTotal >= 0 else { throw ShortcutError.invalidPrice }
        let vehicles = try LocalDataStore.shared.fetchVehicles()
        guard let vehicleId = NewSessionDefaults.vehicleId(in: vehicles) else {
            throw ShortcutError.noVehicle
        }
        let payload = ChargingSessionPayload(
            vehicleId: vehicleId,
            startTime: now,
            chargingType: NewSessionDefaults.chargingType,
            energyKwh: energyKwh,
            priceTotal: priceTotal,
            needsReview: true,
            energyMeter: NewSessionDefaults.energyMeter.rawValue
        )
        // Aktualisiert auch das Widget und die Erinnerungs-Mitteilungen.
        return try await AppRepository.shared.createSession(payload, syncs: false)
    }

    // MARK: - Abfragen

    /// Dieselben Monatszahlen wie das Widget.
    static func monthSnapshot(now: Date = Date()) throws -> WidgetSnapshot {
        try ensureDataAccess()
        return try WidgetSnapshotWriter.makeSnapshot(now: now)
    }

    struct LastSessionInfo {
        let startTime: Date
        let place: String?
        let energyKwh: Double?
        /// Saeulenpreis plus Grundgebuehrenanteil, wie im Widget.
        let cost: Double?
        let socStart: Int?
        let socEnd: Int?
    }

    static func lastSession(now: Date = Date()) throws -> LastSessionInfo? {
        try ensureDataAccess()
        let store = LocalDataStore.shared
        let sessions = try store.fetchSessions(vehicleId: nil, needsReview: nil)
        guard let last = sessions.filter({ $0.startTime <= now }).max(by: { $0.startTime < $1.startTime }) else {
            return nil
        }
        let locationName = last.locationId.flatMap { id in
            (try? store.fetchLocations())?.first { $0.id == id }?.name
        }
        let canonical = try store.canonicalProviderIds()
        let providerName = last.providerId.flatMap { id in
            (try? store.fetchProviders())?.first { $0.id == (canonical[id] ?? id) }?.name
        }
        let place = [locationName, last.geocodedPlace, providerName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let hasCost = last.priceTotal != nil || last.feeShare != nil
        return LastSessionInfo(
            startTime: last.startTime,
            place: place,
            energyKwh: last.energyKwh,
            cost: hasCost ? (last.priceTotal ?? 0) + (last.feeShare ?? 0) : nil,
            socStart: last.socStart,
            socEnd: last.socEnd
        )
    }

    /// Bald faellige und ueberfaellige Erinnerungen, dringendste zuerst.
    static func dueReminders() throws -> [ReminderItem] {
        try ensureDataAccess()
        return try AppRepository.shared.reminderItemsNow()
            .filter { $0.state.status == .overdue || $0.state.status == .dueSoon }
    }

    // MARK: - Formatierung

    static func kwhText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func euroText(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR"))
    }

    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }

    static func lastSessionDetails(_ info: LastSessionInfo) -> (head: String, details: String) {
        let date = info.startTime.formatted(.dateTime.day().month(.wide).hour().minute())
        let head = [date, info.place].compactMap { $0 }.joined(separator: ", ")
        var parts: [String] = []
        if let kwh = info.energyKwh { parts.append("\(kwhText(kwh)) kWh") }
        if let cost = info.cost { parts.append(euroText(cost)) }
        switch (info.socStart, info.socEnd) {
        case let (start?, end?):
            parts.append(String(localized: "SoC \(start) → \(end) %"))
        case let (start?, nil):
            parts.append(String(localized: "SoC ab \(start) %"))
        case let (nil, end?):
            parts.append(String(localized: "SoC bis \(end) %"))
        default:
            break
        }
        return (head, parts.joined(separator: ", "))
    }

    static func remindersText(_ items: [ReminderItem]) -> String {
        let showVehicle = Set(items.map(\.reminder.vehicleId)).count > 1
        return items.map { item in
            var title = item.reminder.displayTitle
            if showVehicle, let vehicle = item.vehicleName { title += " (\(vehicle))" }
            let status: String
            if item.state.status == .dueSoon, let date = item.state.nextDueDate {
                status = String(localized: "fällig am \(date.formatted(.dateTime.day().month(.wide)))")
            } else {
                status = item.state.status.displayName
            }
            return "\(title) – \(status)"
        }
        .joined(separator: "; ")
    }
}

/// Fehler der Kurzbefehle - Siri liest `localizedStringResource` vor.
/// `nonisolated`, weil die App standardmaessig auf dem MainActor isoliert ist
/// und App Intents die Meldung ausserhalb davon abfragt.
nonisolated enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case notSetUp
    case notSignedIn
    case noVehicle
    case invalidEnergy
    case invalidPrice

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSetUp: return "Öffne zuerst die App und richte sie ein."
        case .notSignedIn: return "Melde dich zuerst in der App an."
        case .noVehicle: return "Lege zuerst in der App ein Fahrzeug an."
        case .invalidEnergy: return "Die kWh müssen größer als 0 sein."
        case .invalidPrice: return "Der Preis darf nicht negativ sein."
        }
    }
}
