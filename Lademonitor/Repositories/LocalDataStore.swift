import Foundation
import SwiftData

enum LocalStoreError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return String(localized: "Eintrag wurde nicht gefunden.")
        }
    }
}

/// SwiftData-CRUD fuer den Local-Only-Modus. Arbeitet ausschliesslich mit den
/// bestehenden DTOs/Payloads aus Models.swift, damit Views (und der Remote-Zweig
/// in AppRepository) keinen Unterschied zwischen lokal und Server-backed sehen.
/// IDs werden per `serverId ?? localId.uuidString` aufgeloest (siehe LocalModels.swift).
@MainActor
final class LocalDataStore {
    static let shared = LocalDataStore()
    private var context: ModelContext { LocalStore.shared.context }
    private init() {}

    // MARK: - Reset

    /// Loescht ALLE lokalen Daten unwiderruflich (Fahrzeuge, Anbieter, Ladeorte,
    /// Ladevorgaenge). Im Server-Modus gehen dabei noch nicht hochgeladene (isDirty)
    /// Aenderungen verloren - bereits synchronisierte Daten bleiben auf dem Server und
    /// koennen per Pull zurueckgeholt werden (siehe SettingsView, das nach dem Reset im
    /// Server-Modus direkt einen Sync anstoesst).
    /// Ob ueberhaupt lokale Daten vorliegen - inklusive der zum Loeschen
    /// vorgemerkten Zeilen, denn auch die haetten beim Kontowechsel eine
    /// Auswirkung (siehe SyncService.resetSyncState). Wird gebraucht, um beim
    /// Anmelden nur dann nach dem Umgang mit lokalen Daten zu fragen, wenn es
    /// wirklich etwas zu entscheiden gibt.
    func hasAnyData() throws -> Bool {
        if try context.fetchCount(FetchDescriptor<LocalChargingSession>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalVehicle>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalProvider>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalChargingLocation>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalProviderFee>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalVehicleCost>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalReminder>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<LocalReimbursementRate>()) > 0 { return true }
        return false
    }

    /// Kurzfassung fuer die Abfrage beim Anmelden ("3 Fahrzeuge, 128 Ladevorgaenge").
    func localDataSummary() throws -> String {
        let vehicles = try context.fetchCount(FetchDescriptor<LocalVehicle>())
        let providers = try context.fetchCount(FetchDescriptor<LocalProvider>())
        let locations = try context.fetchCount(FetchDescriptor<LocalChargingLocation>())
        let sessions = try context.fetchCount(FetchDescriptor<LocalChargingSession>())
        let fees = try context.fetchCount(FetchDescriptor<LocalProviderFee>())
        let costs = try context.fetchCount(FetchDescriptor<LocalVehicleCost>())
        let reminders = try context.fetchCount(FetchDescriptor<LocalReminder>())
        let rates = try context.fetchCount(FetchDescriptor<LocalReimbursementRate>())
        var parts: [String] = []
        if vehicles > 0 { parts.append(String(localized: "\(vehicles) Fahrzeuge")) }
        if providers > 0 { parts.append(String(localized: "\(providers) Anbieter")) }
        if locations > 0 { parts.append(String(localized: "\(locations) Ladeorte")) }
        if sessions > 0 { parts.append(String(localized: "\(sessions) Ladevorgänge")) }
        if fees > 0 { parts.append(String(localized: "\(fees) Grundgebühren")) }
        if costs > 0 { parts.append(String(localized: "\(costs) Fahrzeugkosten")) }
        if reminders > 0 { parts.append(String(localized: "\(reminders) Erinnerungen")) }
        if rates > 0 { parts.append(String(localized: "\(rates) Erstattungssätze")) }
        return parts.joined(separator: ", ")
    }

    func resetAllData() throws {
        try context.delete(model: LocalReimbursementRate.self)
        try context.delete(model: LocalReminder.self)
        try context.delete(model: LocalVehicleCost.self)
        try context.delete(model: LocalProviderFee.self)
        try context.delete(model: LocalChargingSession.self)
        try context.delete(model: LocalChargingLocation.self)
        try context.delete(model: LocalProvider.self)
        try context.delete(model: LocalVehicle.self)
        try context.save()
        // Geplante Mitteilungen der geloeschten Erinnerungen mit entfernen.
        ReminderNotificationScheduler.reschedule()
    }

    // MARK: - Vehicles

    func fetchVehicles() throws -> [Vehicle] {
        let descriptor = FetchDescriptor<LocalVehicle>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map(\.asDTO)
    }

    func createVehicle(_ payload: VehiclePayload) throws -> Vehicle {
        let vehicle = LocalVehicle(
            externalId: payload.externalId ?? "",
            name: payload.name ?? "",
            brand: payload.brand,
            model: payload.model,
            batteryCapacityKwh: payload.batteryCapacityKwh,
            isActive: payload.isActive ?? true
        )
        if payload.sendsOwnership { applyOwnership(payload, to: vehicle) }
        if payload.sendsReimbursement { applyReimbursement(payload, to: vehicle) }
        context.insert(vehicle)
        try context.save()
        return vehicle.asDTO
    }

    func updateVehicle(id: String, _ payload: VehiclePayload) throws -> Vehicle {
        guard let vehicle = try findVehicle(id: id) else { throw LocalStoreError.notFound }
        if let name = payload.name { vehicle.name = name }
        if let brand = payload.brand { vehicle.brand = brand }
        if let model = payload.model { vehicle.model = model }
        if let capacity = payload.batteryCapacityKwh { vehicle.batteryCapacityKwh = capacity }
        if let isActive = payload.isActive { vehicle.isActive = isActive }
        if payload.sendsOwnership { applyOwnership(payload, to: vehicle) }
        if payload.sendsReimbursement { applyReimbursement(payload, to: vehicle) }
        vehicle.updatedAt = Date()
        vehicle.isDirty = true
        try context.save()
        return vehicle.asDTO
    }

    private func applyOwnership(_ payload: VehiclePayload, to vehicle: LocalVehicle) {
        vehicle.applyOwnership(
            ownership: payload.ownership, purchasePrice: payload.purchasePrice,
            purchaseDate: payload.purchaseDate, firstRegistration: payload.firstRegistration,
            purchaseOdometerKm: payload.purchaseOdometerKm,
            depreciationMonthlyOverride: payload.depreciationMonthlyOverride,
            leasingRateMonthly: payload.leasingRateMonthly, leasingStart: payload.leasingStart,
            leasingEnd: payload.leasingEnd, leasingDownPayment: payload.leasingDownPayment
        )
    }

    private func applyReimbursement(_ payload: VehiclePayload, to vehicle: LocalVehicle) {
        vehicle.applyReimbursement(
            isCompanyCar: payload.isCompanyCar, reimbursementMode: payload.reimbursementMode,
            reimbursementIncludeFees: payload.reimbursementIncludeFees,
            employeeName: payload.employeeName, employeeNumber: payload.employeeNumber,
            licensePlate: payload.licensePlate, reimbursementMonthlyMail: payload.reimbursementMonthlyMail
        )
    }

    /// Loescht kaskadierend alle zugehoerigen Ladevorgaenge, analog zum Server-Verhalten.
    /// War die Zeile schon einmal synchronisiert (serverId gesetzt), wird nicht sofort
    /// hart geloescht, sondern nur als pendingDelete markiert - der SyncService loescht
    /// dann beim naechsten Push zuerst serverseitig (kaskadiert dort automatisch die
    /// Sessions) und entfernt die lokale Zeile erst danach. Nie synchronisierte Zeilen
    /// (Local-Only-Modus oder offline angelegt) werden weiterhin sofort hart geloescht,
    /// da der Server nichts von ihnen weiss.
    ///
    /// Die Fahrzeugkosten und Erinnerungen gehen sofort und hart mit, wie die
    /// Grundgebuehren beim Anbieter: der Server loescht sie beim Loeschen des
    /// Fahrzeugs selbst (mit Grabsteinen).
    func deleteVehicle(id: String) throws {
        guard let vehicle = try findVehicle(id: id) else { throw LocalStoreError.notFound }
        let refs = Set([vehicle.localId.uuidString] + (vehicle.serverId.map { [$0] } ?? []))
        try context.fetch(FetchDescriptor<LocalVehicleCost>())
            .filter { refs.contains($0.vehicleId) }
            .forEach { context.delete($0) }
        try deleteReminders(ofVehicleRefs: refs)
        try deleteReimbursementRates(ofVehicleRefs: refs)
        let sessions = try context.fetch(FetchDescriptor<LocalChargingSession>(
            predicate: #Predicate { $0.vehicleId == id }
        ))
        if vehicle.serverId != nil {
            vehicle.pendingDelete = true
            vehicle.isDirty = true
            sessions.forEach { $0.pendingDelete = true; $0.isDirty = true }
        } else {
            sessions.forEach { context.delete($0) }
            context.delete(vehicle)
        }
        try context.save()
    }

    private func findVehicle(id: String) throws -> LocalVehicle? {
        // UUID == UUID statt localId.uuidString == id: #Predicate uebersetzt den
        // Ausdruck in eine Store-Query und unterstuetzt dafuer nur eine eingeschraenkte
        // Menge an Ausdruecken - ein Aufruf von .uuidString (berechnete Property) darin
        // fuehrte zur Laufzeit zum Haengen/Absturz statt zu einem sauberen Fehler.
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalVehicle>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Providers

    func fetchProviders() throws -> [Provider] {
        let descriptor = FetchDescriptor<LocalProvider>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map(\.asDTO)
    }

    func createProvider(_ payload: ProviderPayload) throws -> Provider {
        let provider = LocalProvider(
            name: payload.name ?? "",
            lastPriceAcPerKwh: payload.lastPriceAcPerKwh,
            lastPriceDcPerKwh: payload.lastPriceDcPerKwh,
            notes: payload.notes,
            energyMeter: EnergyMeter(raw: payload.energyMeter).rawValue,
            chargingPlace: ChargingPlace(raw: payload.chargingPlace).rawValue
        )
        context.insert(provider)
        try context.save()
        return provider.asDTO
    }

    func updateProvider(id: String, _ payload: ProviderPayload) throws -> Provider {
        guard let provider = try findProvider(id: id) else { throw LocalStoreError.notFound }
        if let name = payload.name { provider.name = name }
        if let ac = payload.lastPriceAcPerKwh { provider.lastPriceAcPerKwh = ac }
        if let dc = payload.lastPriceDcPerKwh { provider.lastPriceDcPerKwh = dc }
        if let notes = payload.notes { provider.notes = notes }
        if let energyMeter = payload.energyMeter { provider.energyMeter = EnergyMeter(raw: energyMeter).rawValue }
        if let place = payload.chargingPlace { provider.chargingPlace = ChargingPlace(raw: place).rawValue }
        provider.updatedAt = Date()
        provider.isDirty = true
        try context.save()
        return provider.asDTO
    }

    /// Die Grundgebuehren des Anbieters gehen sofort und hart mit: der Server
    /// loescht sie beim Loeschen des Anbieters selbst (mit Grabstein), ein
    /// eigener Push waere also ueberfluessig, und ohne Anbieter sind sie
    /// ohnehin nicht mehr zuzuordnen.
    func deleteProvider(id: String) throws {
        guard let provider = try findProvider(id: id) else { throw LocalStoreError.notFound }
        let refs = Set([provider.localId.uuidString] + (provider.serverId.map { [$0] } ?? []))
        try context.fetch(FetchDescriptor<LocalProviderFee>())
            .filter { refs.contains($0.providerId) }
            .forEach { context.delete($0) }
        if provider.serverId != nil {
            provider.pendingDelete = true
            provider.isDirty = true
        } else {
            context.delete(provider)
        }
        try context.save()
    }

    /// Einmalig: Anbieter, die in der frueheren, nur lokalen Auswahl des
    /// Tarifrechners als "nicht oeffentlich" abgewaehlt waren, werden
    /// "Zuhause" - das war praktisch immer die eigene Wallbox. Dirty markiert,
    /// damit der Ladeort mit dem naechsten Sync zum Server geht. Der alte
    /// Schluessel faellt erst nach erfolgreichem Speichern weg; ein zweiter
    /// Lauf waere ohnehin folgenlos.
    func migrateLegacyTariffExclusions() throws {
        guard let ids = TariffCalculatorSettings.legacyExcludedProviderIds else { return }
        for id in ids {
            guard let provider = try findProvider(id: id), !provider.pendingDelete else { continue }
            provider.chargingPlace = ChargingPlace.home.rawValue
            provider.updatedAt = Date()
            provider.isDirty = true
        }
        try context.save()
        TariffCalculatorSettings.clearLegacyExcluded()
    }

    private func findProvider(id: String) throws -> LocalProvider? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalProvider>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Locations

    func fetchLocations() throws -> [ChargingLocation] {
        let descriptor = FetchDescriptor<LocalChargingLocation>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map(\.asDTO)
    }

    func createLocation(_ payload: LocationPayload) throws -> ChargingLocation {
        let location = LocalChargingLocation(
            name: payload.name ?? "",
            latitude: payload.latitude ?? 0,
            longitude: payload.longitude ?? 0,
            radiusM: payload.radiusM ?? 100,
            defaultProviderId: payload.defaultProviderId
        )
        context.insert(location)
        try context.save()
        return location.asDTO
    }

    func updateLocation(id: String, _ payload: LocationPayload) throws -> ChargingLocation {
        guard let location = try findLocation(id: id) else { throw LocalStoreError.notFound }
        if let name = payload.name { location.name = name }
        if let lat = payload.latitude { location.latitude = lat }
        if let lon = payload.longitude { location.longitude = lon }
        if let radius = payload.radiusM { location.radiusM = radius }
        // defaultProviderId kann bewusst auf nil gesetzt werden ("– keiner –"),
        // daher hier direkt zuweisen statt nur bei non-nil zu ueberschreiben.
        location.defaultProviderId = payload.defaultProviderId
        location.updatedAt = Date()
        location.isDirty = true
        try context.save()
        return location.asDTO
    }

    func deleteLocation(id: String) throws {
        guard let location = try findLocation(id: id) else { throw LocalStoreError.notFound }
        if location.serverId != nil {
            location.pendingDelete = true
            location.isDirty = true
        } else {
            context.delete(location)
        }
        try context.save()
    }

    private func findLocation(id: String) throws -> LocalChargingLocation? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalChargingLocation>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Grundgebuehren

    /// Alle Anbieter-Referenzen (lokale UUID ODER serverId) auf die kanonische
    /// DTO-ID abbilden. Gebuehren und Ladevorgaenge koennen ihren Anbieter
    /// noch ueber die lokale UUID kennen, obwohl der inzwischen eine serverId
    /// hat - ohne diese Vereinheitlichung fiele die Umlage fuer genau diese
    /// Vorgaenge still aus.
    func canonicalProviderIds() throws -> [String: String] {
        var map: [String: String] = [:]
        for provider in try context.fetch(FetchDescriptor<LocalProvider>()) {
            let canonical = provider.serverId ?? provider.localId.uuidString
            map[provider.localId.uuidString] = canonical
            if let serverId = provider.serverId { map[serverId] = canonical }
        }
        return map
    }

    func fetchFees(providerId: String? = nil) throws -> [ProviderFee] {
        let canonical = try canonicalProviderIds()
        let rows = try context.fetch(FetchDescriptor<LocalProviderFee>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        ))
        var fees = rows.map { row -> ProviderFee in
            var fee = row.asDTO
            fee.providerId = canonical[fee.providerId] ?? fee.providerId
            return fee
        }
        if let providerId {
            let wanted = canonical[providerId] ?? providerId
            fees = fees.filter { $0.providerId == wanted }
        }
        return fees
    }

    /// Umlage ueber ALLE Ladevorgaenge des Nutzers, wie load_allocation() im
    /// Server. Filter (Fahrzeug, Zeitraum) greifen erst danach.
    func feeAllocation() throws -> LocalFeeAllocator.Allocation {
        let fees = try fetchFees()
        guard !fees.isEmpty else { return LocalFeeAllocator.Allocation() }
        let canonical = try canonicalProviderIds()
        let sessions = try allUndeletedSessions().map { session -> ChargingSession in
            var s = session
            s.providerId = s.providerId.map { canonical[$0] ?? $0 }
            return s
        }
        return LocalFeeAllocator.allocate(fees: fees, sessions: sessions)
    }

    func createFee(_ payload: ProviderFeePayload) throws -> ProviderFee {
        let fee = LocalProviderFee(
            providerId: payload.providerId,
            amount: payload.amount,
            interval: payload.interval.rawValue,
            startDate: Calendar.current.startOfDay(for: payload.startDate),
            endDate: payload.endDate.map { Calendar.current.startOfDay(for: $0) },
            label: payload.label,
            notes: payload.notes
        )
        context.insert(fee)
        try context.save()
        return fee.asDTO
    }

    /// Ersetzt alle Felder, wie der PATCH der App (siehe ProviderFeePayload):
    /// ein leeres Enddatum hebt eine Kuendigung wieder auf.
    func updateFee(id: String, _ payload: ProviderFeePayload) throws -> ProviderFee {
        guard let fee = try findFee(id: id) else { throw LocalStoreError.notFound }
        fee.providerId = payload.providerId
        fee.amount = payload.amount
        fee.interval = payload.interval.rawValue
        fee.startDate = Calendar.current.startOfDay(for: payload.startDate)
        fee.endDate = payload.endDate.map { Calendar.current.startOfDay(for: $0) }
        fee.label = payload.label
        fee.notes = payload.notes
        fee.updatedAt = Date()
        fee.isDirty = true
        try context.save()
        return fee.asDTO
    }

    func deleteFee(id: String) throws {
        guard let fee = try findFee(id: id) else { throw LocalStoreError.notFound }
        if fee.serverId != nil {
            fee.pendingDelete = true
            fee.isDirty = true
        } else {
            context.delete(fee)
        }
        try context.save()
    }

    private func findFee(id: String) throws -> LocalProviderFee? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalProviderFee>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Fahrzeugkosten

    /// Wie canonicalProviderIds(), fuer Fahrzeuge: Kosten und Ladevorgaenge
    /// koennen ihr Fahrzeug noch ueber die lokale UUID kennen.
    func canonicalVehicleIds() throws -> [String: String] {
        var map: [String: String] = [:]
        for vehicle in try context.fetch(FetchDescriptor<LocalVehicle>()) {
            let canonical = vehicle.serverId ?? vehicle.localId.uuidString
            map[vehicle.localId.uuidString] = canonical
            if let serverId = vehicle.serverId { map[serverId] = canonical }
        }
        return map
    }

    /// Neueste (erste) Zahlung zuerst, Fahrzeug-IDs vereinheitlicht.
    func fetchVehicleCosts(vehicleId: String? = nil) throws -> [VehicleCost] {
        let canonical = try canonicalVehicleIds()
        let rows = try context.fetch(FetchDescriptor<LocalVehicleCost>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        ))
        var costs = rows.map { row -> VehicleCost in
            var cost = row.asDTO
            cost.vehicleId = canonical[cost.vehicleId] ?? cost.vehicleId
            return cost
        }
        if let vehicleId {
            let wanted = canonical[vehicleId] ?? vehicleId
            costs = costs.filter { $0.vehicleId == wanted }
        }
        return costs
    }

    /// Alle Ladevorgaenge mit vereinheitlichter Fahrzeug-ID - Grundlage fuer
    /// Restwertkurve (km-Staende) und Ladekosten je Jahr.
    func sessionsWithCanonicalVehicles() throws -> [ChargingSession] {
        let canonical = try canonicalVehicleIds()
        return try fetchSessions(vehicleId: nil, needsReview: nil).map { session -> ChargingSession in
            var s = session
            s.vehicleId = canonical[s.vehicleId] ?? s.vehicleId
            return s
        }
    }

    func createVehicleCost(_ payload: VehicleCostPayload) throws -> VehicleCost {
        let cost = LocalVehicleCost(vehicleId: payload.vehicleId, amount: payload.amount, startDate: Date())
        apply(payload, to: cost)
        context.insert(cost)
        try context.save()
        return cost.asDTO
    }

    /// Ersetzt alle Felder, wie der PATCH der App (siehe VehicleCostPayload).
    func updateVehicleCost(id: String, _ payload: VehicleCostPayload) throws -> VehicleCost {
        guard let cost = try findVehicleCost(id: id) else { throw LocalStoreError.notFound }
        apply(payload, to: cost)
        cost.updatedAt = Date()
        cost.isDirty = true
        try context.save()
        return cost.asDTO
    }

    /// Wie der Server: Datumsangaben nur als Kalendertag, und eine einzelne
    /// Zahlung hat kein Enddatum.
    private func apply(_ payload: VehicleCostPayload, to cost: LocalVehicleCost) {
        cost.vehicleId = payload.vehicleId
        cost.amount = payload.amount
        cost.category = CostCategory(raw: payload.category).rawValue
        cost.interval = payload.interval.rawValue
        cost.startDate = Calendar.current.startOfDay(for: payload.startDate)
        cost.endDate = payload.interval == .once ? nil : payload.endDate.map { Calendar.current.startOfDay(for: $0) }
        cost.odometerKm = payload.odometerKm
        cost.label = payload.label
        cost.notes = payload.notes
    }

    func deleteVehicleCost(id: String) throws {
        guard let cost = try findVehicleCost(id: id) else { throw LocalStoreError.notFound }
        if cost.serverId != nil {
            cost.pendingDelete = true
            cost.isDirty = true
        } else {
            context.delete(cost)
        }
        try context.save()
    }

    private func findVehicleCost(id: String) throws -> LocalVehicleCost? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalVehicleCost>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Erinnerungen

    /// Alle Erinnerungen (ohne die zum Loeschen vorgemerkten), Fahrzeug-IDs
    /// vereinheitlicht wie bei den Fahrzeugkosten.
    func fetchReminders(vehicleId: String? = nil) throws -> [Reminder] {
        let canonical = try canonicalVehicleIds()
        let rows = try context.fetch(FetchDescriptor<LocalReminder>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        var reminders = rows.map { row -> Reminder in
            var reminder = row.asDTO
            reminder.vehicleId = canonical[reminder.vehicleId] ?? reminder.vehicleId
            return reminder
        }
        if let vehicleId {
            let wanted = canonical[vehicleId] ?? vehicleId
            reminders = reminders.filter { $0.vehicleId == wanted }
        }
        return reminders
    }

    func createReminder(_ payload: ReminderPayload) throws -> Reminder {
        let reminder = LocalReminder(vehicleId: payload.vehicleId, kind: payload.kind)
        apply(payload, to: reminder)
        context.insert(reminder)
        try context.save()
        return reminder.asDTO
    }

    /// Ersetzt alle Felder, wie der PATCH der App (siehe ReminderPayload).
    func updateReminder(id: String, _ payload: ReminderPayload) throws -> Reminder {
        guard let reminder = try findReminder(id: id) else { throw LocalStoreError.notFound }
        apply(payload, to: reminder)
        reminder.updatedAt = Date()
        reminder.isDirty = true
        try context.save()
        return reminder.asDTO
    }

    /// Wie der Server: Datumsangaben nur als Kalendertag, unbekannte Art = "Eigene".
    private func apply(_ payload: ReminderPayload, to reminder: LocalReminder) {
        let day = { (date: Date?) in date.map { Calendar.current.startOfDay(for: $0) } }
        reminder.vehicleId = payload.vehicleId
        reminder.kind = ReminderKind(raw: payload.kind).rawValue
        reminder.title = payload.title
        reminder.dueDate = day(payload.dueDate)
        reminder.dueKm = payload.dueKm
        reminder.repeatMonths = payload.repeatMonths
        reminder.repeatKm = payload.repeatKm
        reminder.leadDays = payload.leadDays
        reminder.leadKm = payload.leadKm
        reminder.notes = payload.notes
        reminder.lastDoneDate = day(payload.lastDoneDate)
        reminder.lastDoneKm = payload.lastDoneKm
    }

    func deleteReminder(id: String) throws {
        guard let reminder = try findReminder(id: id) else { throw LocalStoreError.notFound }
        if reminder.serverId != nil {
            reminder.pendingDelete = true
            reminder.isDirty = true
        } else {
            context.delete(reminder)
        }
        try context.save()
    }

    /// Hart, ohne Speichern - fuer das Loeschen eines Fahrzeugs (lokal, per
    /// Push oder per Grabstein). Der Server raeumt seine Erinnerungen selbst
    /// mit weg und legt dafuer Grabsteine an.
    func deleteReminders(ofVehicleRefs refs: Set<String>) throws {
        try context.fetch(FetchDescriptor<LocalReminder>())
            .filter { refs.contains($0.vehicleId) }
            .forEach { context.delete($0) }
    }

    private func findReminder(id: String) throws -> LocalReminder? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalReminder>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Erstattungssaetze (Dienstwagen)

    /// Alle Saetze (ohne die zum Loeschen vorgemerkten), juengster zuerst,
    /// Fahrzeug-IDs vereinheitlicht wie bei den Fahrzeugkosten.
    func fetchReimbursementRates(vehicleId: String? = nil) throws -> [ReimbursementRate] {
        let canonical = try canonicalVehicleIds()
        let rows = try context.fetch(FetchDescriptor<LocalReimbursementRate>(
            predicate: #Predicate { !$0.pendingDelete },
            sortBy: [SortDescriptor(\.validFrom, order: .reverse)]
        ))
        var rates = rows.map { row -> ReimbursementRate in
            var rate = row.asDTO
            rate.vehicleId = canonical[rate.vehicleId] ?? rate.vehicleId
            return rate
        }
        if let vehicleId {
            let wanted = canonical[vehicleId] ?? vehicleId
            rates = rates.filter { $0.vehicleId == wanted }
        }
        return rates
    }

    /// Wie der Server: `validFrom` nur als Kalendertag.
    func createReimbursementRate(_ payload: ReimbursementRatePayload) throws -> ReimbursementRate {
        let rate = LocalReimbursementRate(
            vehicleId: payload.vehicleId,
            validFrom: Calendar.current.startOfDay(for: payload.validFrom),
            ratePerKwh: payload.ratePerKwh
        )
        context.insert(rate)
        try context.save()
        return rate.asDTO
    }

    func updateReimbursementRate(id: String, _ payload: ReimbursementRatePayload) throws -> ReimbursementRate {
        guard let rate = try findReimbursementRate(id: id) else { throw LocalStoreError.notFound }
        rate.vehicleId = payload.vehicleId
        rate.validFrom = Calendar.current.startOfDay(for: payload.validFrom)
        rate.ratePerKwh = payload.ratePerKwh
        rate.updatedAt = Date()
        rate.isDirty = true
        try context.save()
        return rate.asDTO
    }

    func deleteReimbursementRate(id: String) throws {
        guard let rate = try findReimbursementRate(id: id) else { throw LocalStoreError.notFound }
        if rate.serverId != nil {
            rate.pendingDelete = true
            rate.isDirty = true
        } else {
            context.delete(rate)
        }
        try context.save()
    }

    /// Hart, ohne Speichern - fuer das Loeschen eines Fahrzeugs (lokal, per
    /// Push oder per Grabstein). Der Server raeumt die Saetze selbst mit weg
    /// und legt dafuer Grabsteine an.
    func deleteReimbursementRates(ofVehicleRefs refs: Set<String>) throws {
        try context.fetch(FetchDescriptor<LocalReimbursementRate>())
            .filter { refs.contains($0.vehicleId) }
            .forEach { context.delete($0) }
    }

    private func findReimbursementRate(id: String) throws -> LocalReimbursementRate? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalReimbursementRate>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    // MARK: - Sessions

    func fetchSessions(vehicleId: String?, needsReview: Bool?, dateRange: ClosedRange<Date>? = nil) throws -> [ChargingSession] {
        // Verbrauch muss ueber die VOLLSTAENDIGE Fahrzeug-Historie berechnet werden
        // (Vorgaenger/Nachfolger-Vergleich), deshalb erst dekorieren, dann filtern -
        // sonst wuerde z.B. ein Datums- oder needs_review-Filter den chronologischen
        // Vorgaenger faelschlich aus der Berechnung herausnehmen.
        let all = try allUndeletedSessions()
        var sessions = try decoratedWithFees(decoratedWithConsumption(all)).sorted { $0.startTime > $1.startTime }
        if let vehicleId { sessions = sessions.filter { $0.vehicleId == vehicleId } }
        if let needsReview { sessions = sessions.filter { $0.needsReview == needsReview } }
        if let dateRange { sessions = sessions.filter { dateRange.contains($0.startTime) } }
        return sessions
    }

    private func allUndeletedSessions() throws -> [ChargingSession] {
        try context.fetch(FetchDescriptor<LocalChargingSession>(
            predicate: #Predicate { !$0.pendingDelete }
        )).map(\.asDTO)
    }

    func createSession(_ payload: ChargingSessionPayload) throws -> ChargingSession {
        guard let vehicleId = payload.vehicleId else {
            throw LocalStoreError.notFound
        }
        let session = LocalChargingSession(
            vehicleId: vehicleId,
            providerId: payload.providerId,
            locationId: payload.locationId,
            startTime: payload.startTime ?? Date(),
            chargingType: payload.chargingType?.rawValue,
            socStart: payload.socStart,
            socEnd: payload.socEnd,
            energyKwh: payload.energyKwh,
            odometerKm: payload.odometerKm,
            outsideTempC: payload.outsideTempC,
            // Im Local-Only-Modus gibt es nur eine Quelle: den Menschen, der
            // sie eintippt. Der Server macht dieselbe Ableitung.
            outsideTempSource: payload.outsideTempC != nil ? "manual" : nil,
            priceTotal: payload.priceTotal,
            pricePerKwh: payload.pricePerKwh,
            latitude: payload.latitude,
            longitude: payload.longitude,
            geocodedPlace: payload.geocodedPlace,
            notes: payload.notes,
            source: "manual",
            needsReview: payload.needsReview ?? false,
            energyMeter: try storedEnergyMeter(payload.energyMeter, providerId: payload.providerId)
        )
        context.insert(session)
        try updateProviderPriceMemory(providerId: payload.providerId, chargingType: payload.chargingType, pricePerKwh: payload.pricePerKwh)
        try context.save()
        return try decorateOne(session.asDTO)
    }

    func updateSession(id: String, _ payload: ChargingSessionPayload) throws -> ChargingSession {
        guard let session = try findSession(id: id) else { throw LocalStoreError.notFound }
        if let providerId = payload.providerId { session.providerId = providerId }
        if let locationId = payload.locationId { session.locationId = locationId }
        if let startTime = payload.startTime { session.startTime = startTime }
        if let chargingType = payload.chargingType { session.chargingType = chargingType.rawValue }
        if let socStart = payload.socStart { session.socStart = socStart }
        if let socEnd = payload.socEnd { session.socEnd = socEnd }
        if let energyKwh = payload.energyKwh {
            // Korrigierte Energiemenge (z.B. aus der App des Ladeanbieters abgelesen)
            // ist nicht mehr geschaetzt - identisch zur Regel in update_session() im
            // Backend: nur eine tatsaechliche Wertaenderung zaehlt als Korrektur,
            // reines Oeffnen + Speichern laesst das Flag stehen.
            if session.energyIsEstimated, session.energyKwh.map({ abs(energyKwh - $0) > 1e-6 }) ?? true {
                session.energyIsEstimated = false
            }
            session.energyKwh = energyKwh
        }
        if let pricePerKwh = payload.pricePerKwh { session.pricePerKwh = pricePerKwh }
        if let priceTotal = payload.priceTotal { session.priceTotal = priceTotal }
        if let odometerKm = payload.odometerKm { session.odometerKm = odometerKm }
        if let outsideTempC = payload.outsideTempC {
            // Wie beim energy_is_estimated-Flag daneben und wie in
            // update_session() im Backend: das Formular schickt die Temperatur
            // bei JEDEM Speichern mit, deshalb zaehlt nur eine tatsaechliche
            // Wertaenderung als Handeintrag. Sonst wuerde ein vom Wetterdienst
            // geholter Wert nach einmal Oeffnen-und-Speichern als "von Hand"
            // dastehen.
            if session.outsideTempC.map({ abs(outsideTempC - $0) > 1e-6 }) ?? true {
                session.outsideTempSource = "manual"
            }
            session.outsideTempC = outsideTempC
        }
        if let latitude = payload.latitude { session.latitude = latitude }
        if let longitude = payload.longitude { session.longitude = longitude }
        if let geocodedPlace = payload.geocodedPlace { session.geocodedPlace = geocodedPlace }
        if let notes = payload.notes { session.notes = notes }
        if let needsReview = payload.needsReview { session.needsReview = needsReview }
        if let energyMeter = payload.energyMeter {
            // Gegen den Anbieter NACH obiger Zuweisung normalisiert - wer im
            // Formular zugleich den Anbieter wechselt, vergleicht mit dessen
            // Voreinstellung.
            session.energyMeter = try storedEnergyMeter(energyMeter, providerId: session.providerId)
        }
        session.updatedAt = Date()
        session.isDirty = true
        try updateProviderPriceMemory(providerId: session.providerId, chargingType: payload.chargingType, pricePerKwh: payload.pricePerKwh)
        try context.save()
        return try decorateOne(session.asDTO)
    }

    func deleteSession(id: String) throws {
        guard let session = try findSession(id: id) else { throw LocalStoreError.notFound }
        if session.serverId != nil {
            session.pendingDelete = true
            session.isDirty = true
        } else {
            context.delete(session)
        }
        try context.save()
    }

    /// Ein Vorgang ueber seine Server- ODER lokale ID - die lokale bleibt
    /// gueltig, auch wenn ein Sync inzwischen eine Server-ID vergeben hat.
    func fetchSession(id: String) throws -> ChargingSession? {
        guard let session = try findSession(id: id), !session.pendingDelete else { return nil }
        return try decorateOne(session.asDTO)
    }

    private func findSession(id: String) throws -> LocalChargingSession? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalChargingSession>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
    }

    /// Messort der kWh, wie er am Vorgang gespeichert wird: `nil`, wenn die
    /// Wahl der Voreinstellung des Anbieters entspricht - dieselbe
    /// Normalisierung wie in update_session() im Backend.
    private func storedEnergyMeter(_ choice: String?, providerId: String?) throws -> String? {
        guard let choice else { return nil }
        let providerDefault = try providerId.flatMap { try findProvider(id: $0) }?.energyMeter
        return EnergyMeter.storedOverride(choice: EnergyMeter(raw: choice), providerDefault: providerDefault)
    }

    /// Anbieter-"Preis-Gedaechtnis": last_price_ac/dc_per_kwh nachziehen, analog zum
    /// Server (siehe apply_provider_price() im Backend).
    private func updateProviderPriceMemory(providerId: String?, chargingType: ChargingType?, pricePerKwh: Double?) throws {
        guard let providerId, let pricePerKwh, let provider = try findProvider(id: providerId) else { return }
        switch chargingType {
        case .ac: provider.lastPriceAcPerKwh = pricePerKwh
        case .dc: provider.lastPriceDcPerKwh = pricePerKwh
        case nil: break
        }
    }

    private func decorateOne(_ session: ChargingSession) throws -> ChargingSession {
        let siblings = try allUndeletedSessions().filter { $0.vehicleId == session.vehicleId }
        var decorated = decoratedWithConsumption(siblings).first { $0.id == session.id } ?? session
        decorated.feeShare = try feeAllocation().shares[session.id]
        return decorated
    }

    private func decoratedWithFees(_ sessions: [ChargingSession]) throws -> [ChargingSession] {
        let shares = try feeAllocation().shares
        guard !shares.isEmpty else { return sessions }
        return sessions.map { session in
            var s = session
            s.feeShare = shares[session.id]
            return s
        }
    }

    /// Reichert Sessions mit consumptionKwhPer100km/-Method an, pro Fahrzeug getrennt
    /// berechnet (siehe LocalConsumptionCalculator).
    private func decoratedWithConsumption(_ sessions: [ChargingSession]) -> [ChargingSession] {
        let vehicleIds = Set(sessions.map(\.vehicleId))
        var byId: [String: LocalConsumptionCalculator.Result] = [:]
        for vehicleId in vehicleIds {
            let capacity = (try? findVehicle(id: vehicleId))?.batteryCapacityKwh
            let vehicleSessions = sessions.filter { $0.vehicleId == vehicleId }
            byId.merge(LocalConsumptionCalculator.compute(sessions: vehicleSessions, batteryCapacityKwh: capacity)) { _, new in new }
        }
        return sessions.map { session in
            var s = session
            if let result = byId[session.id] {
                s.consumptionKwhPer100km = result.value
                s.consumptionMethod = result.method
            }
            return s
        }
    }
}
