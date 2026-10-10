import Foundation

/// Einziger Anlaufpunkt fuer Views. Seit dem SyncService (Schritt 2) ist LocalDataStore
/// in BEIDEN Modi der alleinige Datenzugriff der Views - der Server-Modus unterscheidet
/// sich nur dadurch, dass vor jedem Lesen ein Sync-Versuch laeuft (syncIfNeeded) und nach
/// jedem Schreiben ein Push angestossen wird (fire-and-forget, blockiert die UI nicht).
/// Views bleiben davon unberuehrt: sie sehen immer die lokale SwiftData-Kopie, die im
/// Server-Modus laufend mit dem Server abgeglichen wird - das ist zugleich der
/// Offline-Puffer (Schreiben funktioniert immer, auch ohne Verbindung) und der Mechanismus
/// fuer die Migration beim Wechsel von Local-Only zu Server (alle lokalen Zeilen sind
/// beim ersten Sync-Durchlauf einfach "dirty", siehe SyncService).
@MainActor
final class AppRepository {
    static let shared = AppRepository()
    private init() {}

    private var isServerMode: Bool { AppSettings.shared.appMode == .server }

    private func syncBeforeRead() async {
        // Vor dem Sync, damit ein uebernommener Ladeort gleich mitgeht.
        try? LocalDataStore.shared.migrateLegacyTariffExclusions()
        if isServerMode { await SyncService.shared.syncIfNeeded() }
    }

    private func syncAfterWrite() {
        guard isServerMode else { return }
        Task { await SyncService.shared.syncNow() }
    }

    // MARK: - Vehicles

    func fetchVehicles() async throws -> [Vehicle] {
        await syncBeforeRead()
        return try LocalDataStore.shared.fetchVehicles()
    }

    func createVehicle(_ payload: VehiclePayload) async throws -> Vehicle {
        let vehicle = try LocalDataStore.shared.createVehicle(payload)
        syncAfterWrite()
        return vehicle
    }

    func updateVehicle(id: String, _ payload: VehiclePayload) async throws -> Vehicle {
        let vehicle = try LocalDataStore.shared.updateVehicle(id: id, payload)
        syncAfterWrite()
        return vehicle
    }

    func deleteVehicle(id: String) async throws {
        try LocalDataStore.shared.deleteVehicle(id: id)
        syncAfterWrite()
        ReminderNotificationScheduler.reschedule()
    }

    // MARK: - Providers

    func fetchProviders() async throws -> [Provider] {
        await syncBeforeRead()
        return try LocalDataStore.shared.fetchProviders()
    }

    func createProvider(_ payload: ProviderPayload) async throws -> Provider {
        let provider = try LocalDataStore.shared.createProvider(payload)
        syncAfterWrite()
        return provider
    }

    func updateProvider(id: String, _ payload: ProviderPayload) async throws -> Provider {
        let provider = try LocalDataStore.shared.updateProvider(id: id, payload)
        syncAfterWrite()
        return provider
    }

    func deleteProvider(id: String) async throws {
        try LocalDataStore.shared.deleteProvider(id: id)
        syncAfterWrite()
    }

    // MARK: - Locations

    func fetchLocations() async throws -> [ChargingLocation] {
        await syncBeforeRead()
        return try LocalDataStore.shared.fetchLocations()
    }

    func createLocation(_ payload: LocationPayload) async throws -> ChargingLocation {
        let location = try LocalDataStore.shared.createLocation(payload)
        syncAfterWrite()
        return location
    }

    func updateLocation(id: String, _ payload: LocationPayload) async throws -> ChargingLocation {
        let location = try LocalDataStore.shared.updateLocation(id: id, payload)
        syncAfterWrite()
        return location
    }

    func deleteLocation(id: String) async throws {
        try LocalDataStore.shared.deleteLocation(id: id)
        syncAfterWrite()
    }

    // MARK: - Geocoding
    //
    // Bewusst NICHT ueber den lokalen Puffer: Adresssuche ist kein persistenter Datensatz,
    // sondern ein einmaliger Lookup. Local-Only nutzt MKLocalSearch, Server-Modus weiterhin
    // den Server-Proxy zu Nominatim (siehe LocalGeocoder.swift).

    func forwardGeocode(query: String) async throws -> [GeocodeResult] {
        if AppSettings.shared.appMode == .localOnly { return try await LocalGeocoder.search(query: query) }
        return try await APIClient.shared.forwardGeocode(query: query)
    }

    // MARK: - Sessions

    func fetchSessions(vehicleId: String? = nil, needsReview: Bool? = nil, dateRange: ClosedRange<Date>? = nil) async throws -> [ChargingSession] {
        await syncBeforeRead()
        return try LocalDataStore.shared.fetchSessions(vehicleId: vehicleId, needsReview: needsReview, dateRange: dateRange)
    }

    func createSession(_ payload: ChargingSessionPayload) async throws -> ChargingSession {
        let session = try LocalDataStore.shared.createSession(payload)
        syncAfterWrite()
        WidgetSnapshotWriter.refresh()
        // Der km-Stand verschiebt die Prognose der Erinnerungen.
        ReminderNotificationScheduler.reschedule()
        return session
    }

    func updateSession(id: String, _ payload: ChargingSessionPayload) async throws -> ChargingSession {
        let session = try LocalDataStore.shared.updateSession(id: id, payload)
        syncAfterWrite()
        WidgetSnapshotWriter.refresh()
        // Der km-Stand verschiebt die Prognose der Erinnerungen.
        ReminderNotificationScheduler.reschedule()
        return session
    }

    func deleteSession(id: String) async throws {
        try LocalDataStore.shared.deleteSession(id: id)
        syncAfterWrite()
        WidgetSnapshotWriter.refresh()
        // Der km-Stand verschiebt die Prognose der Erinnerungen.
        ReminderNotificationScheduler.reschedule()
    }

    // MARK: - Stats
    //
    // Immer lokal berechnet (auch im Server-Modus): dieselbe lokale Kopie, die auch die
    // Listen speist, damit das Dashboard offline nicht leer bleibt, nur weil syncBeforeRead()
    // gerade keine Verbindung hatte.

    func fetchStatsSummary(vehicleId: String? = nil, dateRange: ClosedRange<Date>? = nil) async throws -> StatsSummary {
        await syncBeforeRead()
        let sessions = try LocalDataStore.shared.fetchSessions(vehicleId: vehicleId, needsReview: nil, dateRange: dateRange)
        let vehicles = try LocalDataStore.shared.fetchVehicles()
        let providers = try LocalDataStore.shared.fetchProviders()
        // Perioden ohne Ladevorgang gehoeren zu keinem Fahrzeug (ein Abo gilt
        // fuers Konto) und zaehlen beim Zeitraum nach ihrem Beginn - wie stats.py.
        var unallocated: [LocalFeeAllocator.Period] = []
        if vehicleId == nil {
            unallocated = try LocalDataStore.shared.feeAllocation().unallocated
            if let dateRange {
                let from = Calendar.current.startOfDay(for: dateRange.lowerBound)
                let to = Calendar.current.startOfDay(for: dateRange.upperBound)
                unallocated = unallocated.filter { from <= $0.start && $0.start <= to }
            }
        }
        var summary = LocalStatsCalculator.compute(
            sessions: sessions, vehicles: vehicles, providers: providers, unallocatedFees: unallocated
        )
        // Gesamtkosten wie stats.py::build_vehicle_costs: Ladekosten und km
        // aus der Zusammenfassung, Kosten und km-Staende fuer die
        // Restwertkurve aus der GANZEN Historie der betrachteten Fahrzeuge.
        let basis = try costBasisNow()
        summary.vehicleCosts = LocalVehicleCostCalculator.summary(
            vehicles: vehicleId.map { id in basis.vehicles.filter { $0.id == id } } ?? basis.vehicles,
            costs: basis.costs,
            sessions: basis.sessions,
            dateRange: dateRange,
            chargingCost: summary.totalCost,
            kmDriven: summary.totalKmDriven
        )
        return summary
    }

    // MARK: - Fahrzeugkosten

    /// Fahrzeuge, Kosten und Ladevorgaenge mit EINER Fahrzeug-ID-Form
    /// (= `Vehicle.id`) - alles, was LocalVehicleCostCalculator braucht.
    func vehicleCostBasis() async throws -> VehicleCostBasis {
        await syncBeforeRead()
        return try costBasisNow()
    }

    private func costBasisNow() throws -> VehicleCostBasis {
        let store = LocalDataStore.shared
        return VehicleCostBasis(
            vehicles: try store.fetchVehicles(),
            costs: try store.fetchVehicleCosts(),
            sessions: try store.sessionsWithCanonicalVehicles()
        )
    }

    func createVehicleCost(_ payload: VehicleCostPayload) async throws -> VehicleCost {
        let cost = try LocalDataStore.shared.createVehicleCost(payload)
        syncAfterWrite()
        return cost
    }

    func updateVehicleCost(id: String, _ payload: VehicleCostPayload) async throws -> VehicleCost {
        let cost = try LocalDataStore.shared.updateVehicleCost(id: id, payload)
        syncAfterWrite()
        return cost
    }

    func deleteVehicleCost(id: String) async throws {
        try LocalDataStore.shared.deleteVehicleCost(id: id)
        syncAfterWrite()
    }

    // MARK: - Erinnerungen

    /// Alle Erinnerungen (optional eines Fahrzeugs) mit lokal gerechnetem
    /// Zustand, dringendste zuerst - in beiden Modi gleich.
    func fetchReminderItems(vehicleId: String? = nil) async throws -> [ReminderItem] {
        await syncBeforeRead()
        return try reminderItemsNow(vehicleId: vehicleId)
    }

    private func reminderItemsNow(vehicleId: String?) throws -> [ReminderItem] {
        let store = LocalDataStore.shared
        return LocalReminderCalculator.items(
            reminders: try store.fetchReminders(vehicleId: vehicleId),
            sessions: try store.sessionsWithCanonicalVehicles(),
            vehicles: try store.fetchVehicles()
        )
    }

    func createReminder(_ payload: ReminderPayload) async throws -> Reminder {
        let reminder = try LocalDataStore.shared.createReminder(payload)
        syncAfterWrite()
        await remindersChanged()
        return reminder
    }

    func updateReminder(id: String, _ payload: ReminderPayload) async throws -> Reminder {
        let reminder = try LocalDataStore.shared.updateReminder(id: id, payload)
        syncAfterWrite()
        await remindersChanged()
        return reminder
    }

    func deleteReminder(id: String) async throws {
        try LocalDataStore.shared.deleteReminder(id: id)
        syncAfterWrite()
        await ReminderNotificationScheduler.rescheduleNow()
    }

    /// Nach dem Speichern: beim ersten Mal um Erlaubnis fragen, dann neu planen.
    private func remindersChanged() async {
        await ReminderNotificationScheduler.requestAuthorizationIfNeeded()
        await ReminderNotificationScheduler.rescheduleNow()
    }

    // MARK: - Tarifrechner

    /// Alles, was der Tarifrechner fuer seine Vorschlagswerte braucht, mit
    /// EINER Anbieter-ID-Form (= `Provider.id`): Ladevorgaenge koennen einen
    /// Anbieter noch ueber seine lokale UUID kennen, obwohl er inzwischen
    /// eine Server-ID hat.
    func tariffBasis() async throws -> TariffBasis {
        await syncBeforeRead()
        let store = LocalDataStore.shared
        let canonical = try store.canonicalProviderIds()
        let sessions = try store.fetchSessions(vehicleId: nil, needsReview: nil).map { session -> ChargingSession in
            var s = session
            s.providerId = s.providerId.map { canonical[$0] ?? $0 }
            return s
        }
        let providers = try store.fetchProviders()
        return TariffBasis(
            sessions: sessions,
            providers: providers,
            fees: try store.fetchFees(),
            excludedProviderIds: Set(providers.filter { $0.place != .public }.map(\.id))
        )
    }

    // MARK: - Grundgebuehren

    func fetchFees(providerId: String? = nil) async throws -> [ProviderFee] {
        await syncBeforeRead()
        return try LocalDataStore.shared.fetchFees(providerId: providerId)
    }

    func createFee(_ payload: ProviderFeePayload) async throws -> ProviderFee {
        let fee = try LocalDataStore.shared.createFee(payload)
        syncAfterWrite()
        return fee
    }

    func updateFee(id: String, _ payload: ProviderFeePayload) async throws -> ProviderFee {
        let fee = try LocalDataStore.shared.updateFee(id: id, payload)
        syncAfterWrite()
        return fee
    }

    func deleteFee(id: String) async throws {
        try LocalDataStore.shared.deleteFee(id: id)
        syncAfterWrite()
    }
}

struct VehicleCostBasis {
    let vehicles: [Vehicle]
    let costs: [VehicleCost]
    /// Mit `feeShare`, Fahrzeug-ID vereinheitlicht.
    let sessions: [ChargingSession]
}

struct TariffBasis {
    let sessions: [ChargingSession]
    let providers: [Provider]
    let fees: [ProviderFee]
    /// Anbieter "Zuhause"/"Arbeit" (zaehlen nicht zum Vergleichspreis).
    var excludedProviderIds: Set<String>
}
