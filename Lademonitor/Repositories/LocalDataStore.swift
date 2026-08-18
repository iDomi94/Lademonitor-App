import Foundation
import SwiftData

enum LocalStoreError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return "Eintrag wurde nicht gefunden."
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
    func resetAllData() throws {
        try context.delete(model: LocalChargingSession.self)
        try context.delete(model: LocalChargingLocation.self)
        try context.delete(model: LocalProvider.self)
        try context.delete(model: LocalVehicle.self)
        try context.save()
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
        vehicle.updatedAt = Date()
        vehicle.isDirty = true
        try context.save()
        return vehicle.asDTO
    }

    /// Loescht kaskadierend alle zugehoerigen Ladevorgaenge, analog zum Server-Verhalten.
    /// War die Zeile schon einmal synchronisiert (serverId gesetzt), wird nicht sofort
    /// hart geloescht, sondern nur als pendingDelete markiert - der SyncService loescht
    /// dann beim naechsten Push zuerst serverseitig (kaskadiert dort automatisch die
    /// Sessions) und entfernt die lokale Zeile erst danach. Nie synchronisierte Zeilen
    /// (Local-Only-Modus oder offline angelegt) werden weiterhin sofort hart geloescht,
    /// da der Server nichts von ihnen weiss.
    func deleteVehicle(id: String) throws {
        guard let vehicle = try findVehicle(id: id) else { throw LocalStoreError.notFound }
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
            notes: payload.notes
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
        provider.updatedAt = Date()
        provider.isDirty = true
        try context.save()
        return provider.asDTO
    }

    func deleteProvider(id: String) throws {
        guard let provider = try findProvider(id: id) else { throw LocalStoreError.notFound }
        if provider.serverId != nil {
            provider.pendingDelete = true
            provider.isDirty = true
        } else {
            context.delete(provider)
        }
        try context.save()
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

    // MARK: - Sessions

    func fetchSessions(vehicleId: String?, needsReview: Bool?, dateRange: ClosedRange<Date>? = nil) throws -> [ChargingSession] {
        // Verbrauch muss ueber die VOLLSTAENDIGE Fahrzeug-Historie berechnet werden
        // (Vorgaenger/Nachfolger-Vergleich), deshalb erst dekorieren, dann filtern -
        // sonst wuerde z.B. ein Datums- oder needs_review-Filter den chronologischen
        // Vorgaenger faelschlich aus der Berechnung herausnehmen.
        let all = try allUndeletedSessions()
        var sessions = decoratedWithConsumption(all).sorted { $0.startTime > $1.startTime }
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
            startTime: payload.startTime ?? Date(),
            chargingType: payload.chargingType?.rawValue,
            socStart: payload.socStart,
            socEnd: payload.socEnd,
            energyKwh: payload.energyKwh,
            odometerKm: payload.odometerKm,
            priceTotal: payload.priceTotal,
            pricePerKwh: payload.pricePerKwh,
            latitude: payload.latitude,
            longitude: payload.longitude,
            geocodedPlace: payload.geocodedPlace,
            notes: payload.notes,
            source: "manual",
            needsReview: payload.needsReview ?? false
        )
        context.insert(session)
        try updateProviderPriceMemory(providerId: payload.providerId, chargingType: payload.chargingType, pricePerKwh: payload.pricePerKwh)
        try context.save()
        return try decorateOne(session.asDTO)
    }

    func updateSession(id: String, _ payload: ChargingSessionPayload) throws -> ChargingSession {
        guard let session = try findSession(id: id) else { throw LocalStoreError.notFound }
        if let providerId = payload.providerId { session.providerId = providerId }
        if let startTime = payload.startTime { session.startTime = startTime }
        if let chargingType = payload.chargingType { session.chargingType = chargingType.rawValue }
        if let socStart = payload.socStart { session.socStart = socStart }
        if let socEnd = payload.socEnd { session.socEnd = socEnd }
        if let energyKwh = payload.energyKwh { session.energyKwh = energyKwh }
        if let pricePerKwh = payload.pricePerKwh { session.pricePerKwh = pricePerKwh }
        if let priceTotal = payload.priceTotal { session.priceTotal = priceTotal }
        if let odometerKm = payload.odometerKm { session.odometerKm = odometerKm }
        if let latitude = payload.latitude { session.latitude = latitude }
        if let longitude = payload.longitude { session.longitude = longitude }
        if let geocodedPlace = payload.geocodedPlace { session.geocodedPlace = geocodedPlace }
        if let notes = payload.notes { session.notes = notes }
        if let needsReview = payload.needsReview { session.needsReview = needsReview }
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

    private func findSession(id: String) throws -> LocalChargingSession? {
        let uuid = UUID(uuidString: id) ?? UUID()
        return try context.fetch(FetchDescriptor<LocalChargingSession>(
            predicate: #Predicate { $0.serverId == id || $0.localId == uuid }
        )).first
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
        return decoratedWithConsumption(siblings).first { $0.id == session.id } ?? session
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
