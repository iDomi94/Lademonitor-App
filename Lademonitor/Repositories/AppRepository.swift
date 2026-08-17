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

    func fetchSessions(vehicleId: String? = nil, needsReview: Bool? = nil) async throws -> [ChargingSession] {
        await syncBeforeRead()
        return try LocalDataStore.shared.fetchSessions(vehicleId: vehicleId, needsReview: needsReview)
    }

    func createSession(_ payload: ChargingSessionPayload) async throws -> ChargingSession {
        let session = try LocalDataStore.shared.createSession(payload)
        syncAfterWrite()
        return session
    }

    func updateSession(id: String, _ payload: ChargingSessionPayload) async throws -> ChargingSession {
        let session = try LocalDataStore.shared.updateSession(id: id, payload)
        syncAfterWrite()
        return session
    }

    func deleteSession(id: String) async throws {
        try LocalDataStore.shared.deleteSession(id: id)
        syncAfterWrite()
    }

    // MARK: - Stats
    //
    // Immer lokal berechnet (auch im Server-Modus): dieselbe lokale Kopie, die auch die
    // Listen speist, damit das Dashboard offline nicht leer bleibt, nur weil syncBeforeRead()
    // gerade keine Verbindung hatte.

    func fetchStatsSummary(vehicleId: String? = nil) async throws -> StatsSummary {
        await syncBeforeRead()
        let sessions = try LocalDataStore.shared.fetchSessions(vehicleId: vehicleId, needsReview: nil)
        let vehicles = try LocalDataStore.shared.fetchVehicles()
        let providers = try LocalDataStore.shared.fetchProviders()
        return LocalStatsCalculator.compute(sessions: sessions, vehicles: vehicles, providers: providers)
    }
}
