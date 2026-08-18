import Foundation
import SwiftData
import Combine

/// Gleicht den lokalen SwiftData-Puffer (LocalStore) bidirektional mit dem Server ab.
/// Nur im Server-Modus aktiv - im Local-Only-Modus wird das isDirty/serverId-Schema der
/// LocalModels schlicht nie konsultiert.
///
/// Ablauf pro Sync: erst PUSH (alle lokal geaenderten/geloeschten Zeilen hoch, in
/// FK-Reihenfolge Vehicles -> Providers -> Locations -> Sessions, damit z.B. eine neu
/// angelegte Session ihre Fahrzeug-serverId schon kennt), dann PULL (Server-Stand
/// herunterladen und mergen). Konfliktstrategie: lokal dirty gewinnt (wird beim naechsten
/// Push ueberschrieben statt beim Pull ueberschrieben zu werden) - siehe Konzept-Diskussion,
/// fuer Single-User-Nutzung ausreichend.
///
/// Da jede neu angelegte lokale Zeile (LocalModels.swift) standardmaessig isDirty=true und
/// serverId=nil hat, ist der "alle lokalen Daten hochladen"-Fall beim Wechsel von
/// Local-Only zu Server KEIN Sonderfall, sondern einfach der erste normale Sync-Durchlauf.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncError: String?

    private let minAutoSyncInterval: TimeInterval = 10
    private var inFlightTask: Task<Void, Never>?
    private var networkObservation: AnyCancellable?
    /// Fehler einzelner Zeilen waehrend eines Push (siehe pushVehicles() etc.) - eine
    /// fehlerhafte Zeile (z.B. eine verwaiste Referenz) soll nicht den kompletten
    /// Sync-Durchlauf fuer alle anderen Zeilen abbrechen, siehe performSync().
    private var itemErrors: [String] = []

    private var context: ModelContext { LocalStore.shared.context }

    private init() {
        // Sobald die Verbindung nach einer Offline-Phase wiederkommt, gepufferte
        // Aenderungen automatisch nachschieben statt auf die naechste manuelle
        // Aktion des Nutzers zu warten.
        networkObservation = NetworkMonitor.shared.$isOnline
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isOnline in
                guard isOnline else { return }
                Task { await self?.syncNow() }
            }
    }

    /// Fuer Views (.task/.refreshable): synct nur, wenn der letzte Sync laenger als
    /// minAutoSyncInterval her ist, um nicht bei jedem Tab-Wechsel einen vollen
    /// Push+Pull auszuloesen.
    func syncIfNeeded() async {
        guard AppSettings.shared.appMode == .server, SessionManager.shared.isAuthenticated else { return }
        if let last = lastSyncDate, Date().timeIntervalSince(last) < minAutoSyncInterval { return }
        await syncNow()
    }

    /// Erzwingt einen Sync. Parallele Aufrufe (z.B. mehrere Views gleichzeitig) werden
    /// auf denselben laufenden Task gebuendelt statt mehrfach zu synchronisieren.
    func syncNow() async {
        if let inFlightTask {
            await inFlightTask.value
            return
        }
        let task = Task { await performSync() }
        inFlightTask = task
        await task.value
        inFlightTask = nil
    }

    /// UserDefaults-Backing: welcher Server-Account zuletzt synchronisiert wurde. Dient
    /// nur der Erkennung eines Accountwechsels (siehe resetSyncStateIfAccountChanged),
    /// keine sensiblen Daten.
    private var lastSyncedUserId: String? {
        get { UserDefaults.standard.string(forKey: "lastSyncedUserId") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSyncedUserId") }
    }

    private func performSync() async {
        guard AppSettings.shared.appMode == .server, SessionManager.shared.isAuthenticated else { return }
        guard NetworkMonitor.shared.isOnline else {
            lastSyncError = "Offline – Änderungen werden gepuffert und beim nächsten Mal hochgeladen."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        resetSyncStateIfAccountChanged()
        itemErrors = []
        do {
            try await pushVehicles()
            try await pushProviders()
            try await pushLocations()
            try await pushSessions()
            try await pullVehicles()
            try await pullProviders()
            try await pullLocations()
            try await pullSessions()
            lastSyncDate = Date()
            // Auch bei insgesamt erfolgreichem Durchlauf koennen einzelne Zeilen
            // uebersprungen worden sein (siehe itemErrors) - das soll sichtbar bleiben,
            // statt eine falsche "alles synchronisiert"-Meldung zu zeigen.
            lastSyncError = itemErrors.isEmpty ? nil : itemErrors.joined(separator: " · ")
        } catch {
            let summary = itemErrors.isEmpty ? "" : itemErrors.joined(separator: " · ") + " · "
            lastSyncError = summary + error.localizedDescription
        }
    }

    /// Erkennt einen Wechsel des Server-Accounts (z.B. lokal mit Account A synchronisiert,
    /// spaeter mit neu registriertem Account B eingeloggt): serverId/isDirty-Markierungen
    /// von Account A sind fuer Account B bedeutungslos - ohne Reset wuerden diese Zeilen
    /// fuer immer als "schon synchronisiert" gelten und nie zu Account B gepusht werden.
    /// Bei nil (noch nie synchronisiert) passiert nichts, nur der aktuelle Account wird
    /// gemerkt. Loest bewusst NICHTS, was Daten loescht (siehe removeVanishedMirrors) -
    /// nur ein Zuruecksetzen auf "frisch lokal, muss gepusht werden".
    private func resetSyncStateIfAccountChanged() {
        guard let currentUserId = SessionManager.shared.currentUser?.id else { return }
        defer { lastSyncedUserId = currentUserId }
        guard let lastSyncedUserId, lastSyncedUserId != currentUserId else { return }
        resetSyncState(for: LocalVehicle.self)
        resetSyncState(for: LocalProvider.self)
        resetSyncState(for: LocalChargingLocation.self)
        resetSyncState(for: LocalChargingSession.self)
        try? context.save()
    }

    private func resetSyncState<T: PersistentModel>(for type: T.Type) where T: SyncMirrorable {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else { return }
        for item in all {
            // War unter dem alten Account schon zur Loeschung vorgemerkt: die Absicht
            // ("das soll weg") bleibt gueltig, aber ohne gueltige serverId fuer den neuen
            // Account kann das nicht mehr gepusht werden - hier ist Hart-Loeschen sicher,
            // da der Nutzer diese Zeile ohnehin loeschen wollte.
            if item.pendingDelete {
                context.delete(item)
            } else {
                item.serverId = nil
                item.isDirty = true
            }
        }
    }

    // MARK: - Push

    /// Eine Zeile, die nicht gepusht werden konnte (z.B. verwaiste Referenz oder ein vom
    /// Server abgelehnter Wert). Bleibt dirty, damit ein spaeterer Sync es erneut versucht,
    /// statt entweder den ganzen Durchlauf abzubrechen oder die Zeile stumm fallenzulassen.
    private struct UnresolvedReferenceError: LocalizedError {
        let what: String
        var errorDescription: String? { "Konnte \(what) nicht zuordnen." }
    }

    private func pushVehicles() async throws {
        let dirty = try context.fetch(FetchDescriptor<LocalVehicle>(predicate: #Predicate { $0.isDirty }))
        for vehicle in dirty {
            do {
                if vehicle.pendingDelete {
                    if let serverId = vehicle.serverId {
                        try? await APIClient.shared.deleteVehicle(id: serverId)
                    }
                    // Server-Delete kaskadiert dort automatisch alle Sessions dieses
                    // Fahrzeugs - lokal deshalb hart entfernen statt einzeln zu syncen.
                    let vehicleRef = vehicle.serverId ?? vehicle.localId.uuidString
                    let sessions = try context.fetch(FetchDescriptor<LocalChargingSession>(
                        predicate: #Predicate<LocalChargingSession> { $0.vehicleId == vehicleRef }
                    ))
                    sessions.forEach { context.delete($0) }
                    context.delete(vehicle)
                    continue
                }
                let payload = VehiclePayload(
                    externalId: vehicle.serverId == nil ? vehicle.externalId : nil,
                    name: vehicle.name, brand: vehicle.brand, model: vehicle.model,
                    batteryCapacityKwh: vehicle.batteryCapacityKwh, isActive: vehicle.isActive
                )
                if let serverId = vehicle.serverId {
                    _ = try await APIClient.shared.updateVehicle(id: serverId, payload)
                } else {
                    let created = try await APIClient.shared.createVehicle(payload)
                    vehicle.serverId = created.id
                }
                vehicle.isDirty = false
            } catch {
                itemErrors.append("Fahrzeug „\(vehicle.name)“: \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    private func pushProviders() async throws {
        let dirty = try context.fetch(FetchDescriptor<LocalProvider>(predicate: #Predicate { $0.isDirty }))
        for provider in dirty {
            do {
                if provider.pendingDelete {
                    if let serverId = provider.serverId {
                        try? await APIClient.shared.deleteProvider(id: serverId)
                    }
                    context.delete(provider)
                    continue
                }
                let payload = ProviderPayload(
                    name: provider.name, lastPriceAcPerKwh: provider.lastPriceAcPerKwh,
                    lastPriceDcPerKwh: provider.lastPriceDcPerKwh, notes: provider.notes
                )
                if let serverId = provider.serverId {
                    _ = try await APIClient.shared.updateProvider(id: serverId, payload)
                } else {
                    let created = try await APIClient.shared.createProvider(payload)
                    provider.serverId = created.id
                }
                provider.isDirty = false
            } catch {
                itemErrors.append("Anbieter „\(provider.name)“: \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    private func pushLocations() async throws {
        let dirty = try context.fetch(FetchDescriptor<LocalChargingLocation>(predicate: #Predicate { $0.isDirty }))
        for location in dirty {
            do {
                if location.pendingDelete {
                    if let serverId = location.serverId {
                        try? await APIClient.shared.deleteLocation(id: serverId)
                    }
                    context.delete(location)
                    continue
                }
                let resolvedProviderId = try resolvedProviderServerId(location.defaultProviderId)
                let payload = LocationPayload(
                    name: location.name, latitude: location.latitude, longitude: location.longitude,
                    radiusM: location.radiusM, defaultProviderId: resolvedProviderId
                )
                if let serverId = location.serverId {
                    _ = try await APIClient.shared.updateLocation(id: serverId, payload)
                } else {
                    let created = try await APIClient.shared.createLocation(payload)
                    location.serverId = created.id
                }
                location.defaultProviderId = resolvedProviderId
                location.isDirty = false
            } catch {
                itemErrors.append("Ladeort „\(location.name)“: \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    private func pushSessions() async throws {
        let dirty = try context.fetch(FetchDescriptor<LocalChargingSession>(predicate: #Predicate { $0.isDirty }))
        for session in dirty {
            do {
                if session.pendingDelete {
                    if let serverId = session.serverId {
                        try? await APIClient.shared.deleteSession(id: serverId)
                    }
                    context.delete(session)
                    continue
                }
                let resolvedVehicleId = try resolvedVehicleServerId(session.vehicleId)
                let resolvedProviderId = try resolvedProviderServerId(session.providerId)
                let payload = ChargingSessionPayload(
                    // vehicle_id kann serverseitig beim Bearbeiten nicht geaendert werden,
                    // daher nur beim erstmaligen Anlegen mitschicken (analog AddEditSessionView).
                    vehicleId: session.serverId == nil ? resolvedVehicleId : nil,
                    providerId: resolvedProviderId,
                    startTime: session.startTime,
                    chargingType: session.chargingType.flatMap(ChargingType.init(rawValue:)),
                    socStart: session.socStart,
                    socEnd: session.socEnd,
                    energyKwh: session.energyKwh,
                    pricePerKwh: session.pricePerKwh,
                    priceTotal: session.priceTotal,
                    odometerKm: session.odometerKm,
                    latitude: session.latitude,
                    longitude: session.longitude,
                    geocodedPlace: session.geocodedPlace,
                    notes: session.notes,
                    needsReview: session.needsReview
                )
                if let serverId = session.serverId {
                    _ = try await APIClient.shared.updateSession(id: serverId, payload)
                } else {
                    let created = try await APIClient.shared.createSession(payload)
                    session.serverId = created.id
                }
                session.vehicleId = resolvedVehicleId
                session.providerId = resolvedProviderId
                session.isDirty = false
            } catch {
                itemErrors.append("Ladevorgang vom \(session.startTime.formatted()): \(error.localizedDescription)")
            }
        }
        try context.save()
    }

    /// Loest eine lokale ID-Referenz (lokale UUID ODER bereits eine serverId) zur
    /// aktuellen serverId auf. Vehicles/Providers/Locations wurden in diesem Sync-Durchlauf
    /// bereits VOR den Sessions gepusht, ihre serverId ist an dieser Stelle also aktuell.
    /// Wirft statt still auf die (falsche) lokale Referenz zurueckzufallen, falls keine
    /// passende, bereits synchronisierte Zeile gefunden wird - ein Aufrufer, der das
    /// verschluckt haette, wuerde sonst eine garantiert ungueltige ID an den Server senden
    /// (siehe die Diskussion zum 404 "Vehicle nicht gefunden").
    private func resolvedVehicleServerId(_ ref: String) throws -> String {
        let uuid = UUID(uuidString: ref) ?? UUID()
        let vehicle = try context.fetch(FetchDescriptor<LocalVehicle>(
            predicate: #Predicate { $0.serverId == ref || $0.localId == uuid }
        )).first
        guard let resolved = vehicle?.serverId else {
            throw UnresolvedReferenceError(what: "Fahrzeug")
        }
        return resolved
    }

    /// Anders als beim Fahrzeug (Pflichtfeld) wirft dies bewusst NICHT: der Anbieter ist
    /// optional, eine nicht aufloesbare Referenz (z.B. verwaiste Altdaten) soll den Sync
    /// von Fahrzeug/Ladeort/Session nicht blockieren, sondern still auf "kein Anbieter"
    /// zurueckfallen statt eine ungueltige ID an den Server zu senden.
    private func resolvedProviderServerId(_ ref: String?) throws -> String? {
        guard let ref else { return nil }
        let uuid = UUID(uuidString: ref) ?? UUID()
        let provider = try context.fetch(FetchDescriptor<LocalProvider>(
            predicate: #Predicate { $0.serverId == ref || $0.localId == uuid }
        )).first
        return provider?.serverId
    }

    // MARK: - Pull

    private func pullVehicles() async throws {
        let serverVehicles = try await APIClient.shared.fetchVehicles()
        var serverIds = Set<String>()
        for sv in serverVehicles {
            serverIds.insert(sv.id)
            if let existing = try findLocalVehicle(serverId: sv.id) {
                if !existing.isDirty {
                    existing.externalId = sv.externalId
                    existing.name = sv.name
                    existing.brand = sv.brand
                    existing.model = sv.model
                    existing.batteryCapacityKwh = sv.batteryCapacityKwh
                    existing.isActive = sv.isActive
                }
            } else {
                context.insert(LocalVehicle(
                    serverId: sv.id, externalId: sv.externalId, name: sv.name, brand: sv.brand,
                    model: sv.model, batteryCapacityKwh: sv.batteryCapacityKwh, isActive: sv.isActive,
                    isDirty: false
                ))
            }
        }
        try removeVanishedMirrors(LocalVehicle.self, stillOnServer: serverIds)
        try context.save()
    }

    private func pullProviders() async throws {
        let serverProviders = try await APIClient.shared.fetchProviders()
        var serverIds = Set<String>()
        for sp in serverProviders {
            serverIds.insert(sp.id)
            if let existing = try findLocalProvider(serverId: sp.id) {
                if !existing.isDirty {
                    existing.name = sp.name
                    existing.lastPriceAcPerKwh = sp.lastPriceAcPerKwh
                    existing.lastPriceDcPerKwh = sp.lastPriceDcPerKwh
                    existing.notes = sp.notes
                }
            } else {
                context.insert(LocalProvider(
                    serverId: sp.id, name: sp.name, lastPriceAcPerKwh: sp.lastPriceAcPerKwh,
                    lastPriceDcPerKwh: sp.lastPriceDcPerKwh, notes: sp.notes, isDirty: false
                ))
            }
        }
        try removeVanishedMirrors(LocalProvider.self, stillOnServer: serverIds)
        try context.save()
    }

    private func pullLocations() async throws {
        let serverLocations = try await APIClient.shared.fetchLocations()
        var serverIds = Set<String>()
        for sl in serverLocations {
            serverIds.insert(sl.id)
            if let existing = try findLocalLocation(serverId: sl.id) {
                if !existing.isDirty {
                    existing.name = sl.name
                    existing.latitude = sl.latitude
                    existing.longitude = sl.longitude
                    existing.radiusM = sl.radiusM
                    existing.defaultProviderId = sl.defaultProviderId
                }
            } else {
                context.insert(LocalChargingLocation(
                    serverId: sl.id, name: sl.name, latitude: sl.latitude, longitude: sl.longitude,
                    radiusM: sl.radiusM, defaultProviderId: sl.defaultProviderId, isDirty: false
                ))
            }
        }
        try removeVanishedMirrors(LocalChargingLocation.self, stillOnServer: serverIds)
        try context.save()
    }

    private func pullSessions() async throws {
        let serverSessions = try await APIClient.shared.fetchSessions()
        var serverIds = Set<String>()
        for ss in serverSessions {
            serverIds.insert(ss.id)
            if let existing = try findLocalSession(serverId: ss.id) {
                if !existing.isDirty {
                    apply(ss, to: existing)
                }
            } else {
                context.insert(LocalChargingSession(
                    serverId: ss.id, vehicleId: ss.vehicleId, providerId: ss.providerId, locationId: ss.locationId,
                    startTime: ss.startTime, endTime: ss.endTime, chargingType: ss.chargingType?.rawValue,
                    socStart: ss.socStart, socEnd: ss.socEnd, energyKwh: ss.energyKwh,
                    energyIsEstimated: ss.energyIsEstimated, odometerKm: ss.odometerKm, priceTotal: ss.priceTotal,
                    pricePerKwh: ss.pricePerKwh, latitude: ss.latitude, longitude: ss.longitude,
                    geocodedPlace: ss.geocodedPlace, notes: ss.notes, source: ss.source.rawValue,
                    needsReview: ss.needsReview, externalSessionId: ss.externalSessionId, isDirty: false
                ))
            }
        }
        try removeVanishedMirrors(LocalChargingSession.self, stillOnServer: serverIds)
        try context.save()
    }

    private func apply(_ dto: ChargingSession, to session: LocalChargingSession) {
        session.vehicleId = dto.vehicleId
        session.providerId = dto.providerId
        session.locationId = dto.locationId
        session.startTime = dto.startTime
        session.endTime = dto.endTime
        session.chargingType = dto.chargingType?.rawValue
        session.socStart = dto.socStart
        session.socEnd = dto.socEnd
        session.energyKwh = dto.energyKwh
        session.energyIsEstimated = dto.energyIsEstimated
        session.odometerKm = dto.odometerKm
        session.priceTotal = dto.priceTotal
        session.pricePerKwh = dto.pricePerKwh
        session.latitude = dto.latitude
        session.longitude = dto.longitude
        session.geocodedPlace = dto.geocodedPlace
        session.notes = dto.notes
        session.source = dto.source.rawValue
        session.needsReview = dto.needsReview
        session.externalSessionId = dto.externalSessionId
    }

    /// ACHTUNG: entfernt lokale Spiegel-Zeilen NICHT mehr automatisch nur weil sie in
    /// einer Pull-Antwort fehlen (fruehere Version tat das, um serverseitige Loeschungen
    /// z.B. ueber das Web-UI zu spiegeln). Grund fuer die Ruecknahme: jede Luecke in der
    /// Pull-Antwort - ob durch einen echten Server-Fehler, eine unerwartete leere Antwort
    /// oder einen Fehler in der ID-Aufloesung beim vorangegangenen Push - fuehrte sonst zu
    /// STILLEM, UNWIDERRUFLICHEM Verlust lokaler Ladevorgaenge. Das Risiko ist die Funktion
    /// nicht wert. Serverseitig geloeschte Eintraege bleiben dadurch als "Geisterzeilen"
    /// lokal bestehen, bis sie auch in der App geloescht werden - bewusster Kompromiss.
    private func removeVanishedMirrors<T: PersistentModel>(_ type: T.Type, stillOnServer: Set<String>) throws where T: SyncMirrorable {
    }

    private func findLocalVehicle(serverId: String) throws -> LocalVehicle? {
        try context.fetch(FetchDescriptor<LocalVehicle>(predicate: #Predicate { $0.serverId == serverId })).first
    }
    private func findLocalProvider(serverId: String) throws -> LocalProvider? {
        try context.fetch(FetchDescriptor<LocalProvider>(predicate: #Predicate { $0.serverId == serverId })).first
    }
    private func findLocalLocation(serverId: String) throws -> LocalChargingLocation? {
        try context.fetch(FetchDescriptor<LocalChargingLocation>(predicate: #Predicate { $0.serverId == serverId })).first
    }
    private func findLocalSession(serverId: String) throws -> LocalChargingSession? {
        try context.fetch(FetchDescriptor<LocalChargingSession>(predicate: #Predicate { $0.serverId == serverId })).first
    }
}

/// Gemeinsames Protokoll der vier LocalModels-Typen, nur damit removeVanishedMirrors()/
/// resetSyncState() generisch auf serverId/isDirty/pendingDelete zugreifen koennen.
protocol SyncMirrorable: AnyObject {
    var serverId: String? { get set }
    var isDirty: Bool { get set }
    var pendingDelete: Bool { get set }
}

extension LocalVehicle: SyncMirrorable {}
extension LocalProvider: SyncMirrorable {}
extension LocalChargingLocation: SyncMirrorable {}
extension LocalChargingSession: SyncMirrorable {}
