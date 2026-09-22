import Foundation
import SwiftData
import Combine

/// Gleicht den lokalen SwiftData-Puffer (LocalStore) bidirektional mit dem Server ab.
/// Nur im Server-Modus aktiv - im Local-Only-Modus wird das isDirty/serverId-Schema der
/// LocalModels schlicht nie konsultiert.
///
/// Ablauf pro Sync: erst PUSH (alle lokal geaenderten/geloeschten Zeilen hoch, in
/// FK-Reihenfolge Vehicles -> Providers -> Gebuehren -> Locations -> Sessions, damit z.B. eine neu
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

    /// Steuert den Dialog "Was soll mit den Daten auf diesem Geraet passieren?".
    /// Liegt hier und nicht in der AuthView, weil die in dem Moment schon
    /// verschwunden ist: `completeAuthentication` setzt `isAuthenticated`, und
    /// ContentView schaltet sofort auf die Haupt-App um - ein Alert an der
    /// AuthView wuerde nie erscheinen. Praesentiert wird er deshalb von
    /// ContentView, die in beiden Zustaenden existiert.
    @Published var pendingLocalDataDecision = false
    @Published private(set) var pendingLocalDataSummary = ""

    private let minAutoSyncInterval: TimeInterval = 10
    private var inFlightTask: Task<Void, Never>?
    private var networkObservation: AnyCancellable?
    /// Fehler einzelner Zeilen waehrend eines Push (siehe pushVehicles() etc.) - eine
    /// fehlerhafte Zeile (z.B. eine verwaiste Referenz) soll nicht den kompletten
    /// Sync-Durchlauf fuer alle anderen Zeilen abbrechen, siehe performSync().
    private var itemErrors: [String] = []

    private var context: ModelContext { LocalStore.shared.context }

    /// Ob der Server Grundgebuehren kennt (ab 0.27.0). Wird in jedem Durchlauf
    /// neu ermittelt (pushFees), damit ein Server-Update ohne App-Neustart
    /// greift.
    private var serverSupportsFees = false

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

    // MARK: - Umgang mit lokalen Daten beim Anmelden

    /// Was mit den bereits auf dem Geraet liegenden Daten geschehen soll, wenn
    /// sich jemand an einem Konto anmeldet, mit dem dieses Geraet noch nie
    /// synchronisiert hat.
    enum LocalDataDecision: Equatable {
        /// In das jetzt angemeldete Konto hochladen (bisheriges Verhalten).
        case upload
        /// Vom Geraet loeschen und stattdessen den Stand des Kontos laden.
        case discard
    }

    /// Ob vor dem ersten Sync eine Entscheidung des Nutzers noetig ist.
    ///
    /// Ohne diese Abfrage wanderten die lokalen Daten immer stillschweigend in
    /// das gerade angemeldete Konto - beim Wechsel von Konto A zu Konto B also
    /// auch A's Ladeorte samt GPS-Koordinaten der Wohnadresse. Genau davor
    /// schuetzt serverseitig die Pro-Nutzer-Trennung, und die soll die App
    /// nicht aus Versehen unterlaufen.
    ///
    /// Gefragt wird nur, wenn es wirklich etwas zu entscheiden gibt: im
    /// Server-Modus, mit vorhandenen lokalen Daten, und wenn dieses Geraet mit
    /// GENAU DIESEM Konto noch nie synchronisiert hat. Eine normale
    /// Wiederanmeldung am gewohnten Konto fragt also nichts.
    func needsLocalDataDecision() -> Bool {
        guard AppSettings.shared.appMode == .server,
              let userId = SessionManager.shared.currentUser?.id,
              lastSyncedUserId != userId,
              let hasData = try? LocalDataStore.shared.hasAnyData(), hasData
        else { return false }
        return true
    }

    /// Nach erfolgreicher Anmeldung aufzurufen. Ob synchronisiert oder zuerst
    /// gefragt wird, entscheidet die Sperre in performSync() - hier steht
    /// deshalb nur der normale Anstoss.
    func startAfterLogin() {
        Task { await syncNow() }
    }

    /// Setzt die Entscheidung um und synchronisiert anschliessend.
    ///
    /// Beide Zweige vermerken das Konto als "gesehen" - erst dadurch laesst die
    /// Sperre in performSync() den folgenden Sync ueberhaupt durch.
    func applyLocalDataDecision(_ decision: LocalDataDecision) async {
        pendingLocalDataDecision = false
        switch decision {
        case .upload:
            // Genau das, was frueher automatisch beim ersten Sync passierte:
            // alle Zeilen auf "frisch lokal, muss gepusht werden" setzen. Setzt
            // nebenbei lastSyncedUserId.
            resetSyncStateIfAccountChanged()
        case .discard:
            do {
                try LocalDataStore.shared.resetAllData()
                // Das Konto als "schon gesehen" vermerken, BEVOR synchronisiert
                // wird: sonst liefe beim naechsten Durchlauf die
                // Kontowechsel-Erkennung auf den frisch heruntergeladenen
                // Server-Daten und markierte sie als lokal geaendert.
                lastSyncedUserId = SessionManager.shared.currentUser?.id
            } catch {
                lastSyncError = error.localizedDescription
                return
            }
        }
        await syncNow()
    }

    /// Abbruch im Dialog: wieder abmelden. Sonst stuende man angemeldet da,
    /// ohne dass die Frage beantwortet ist - und der naechste beliebige Sync
    /// (Tab-Wechsel, Netz wieder da) wuerde sie stillschweigend mit
    /// "hochladen" beantworten. Die lokalen Daten bleiben unangetastet.
    func cancelLocalDataDecision() async {
        pendingLocalDataDecision = false
        await SessionManager.shared.logout()
    }

    private func performSync() async {
        guard AppSettings.shared.appMode == .server, SessionManager.shared.isAuthenticated else { return }
        guard NetworkMonitor.shared.isOnline else {
            lastSyncError = String(localized: "Offline – Änderungen werden gepuffert und beim nächsten Mal hochgeladen.")
            return
        }
        // Sperre gegen den stillen Weg: auch ein Sync, der NICHT ueber
        // startAfterLogin() kommt (App-Neustart nach abgebrochener Anmeldung,
        // Netz-Wiederkehr, Tab-Wechsel), darf die Frage nicht stillschweigend
        // mit "hochladen" beantworten. Stattdessen wird sie hier gestellt.
        // applyLocalDataDecision() vermerkt das Konto in beiden Zweigen als
        // gesehen, sodass der darauf folgende Sync hier durchkommt.
        if needsLocalDataDecision() {
            pendingLocalDataSummary = (try? LocalDataStore.shared.localDataSummary()) ?? ""
            pendingLocalDataDecision = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        resetSyncStateIfAccountChanged()
        itemErrors = []
        do {
            try await pushVehicles()
            try await pushProviders()
            try await pushFees()
            try await pushLocations()
            try await pushSessions()
            try await pullVehicles()
            try await pullProviders()
            try await pullFees()
            try await pullLocations()
            try await pullSessions()
            // Zum Schluss, nach den Pulls: die legen fehlende Zeilen an, und eine
            // gerade erst angelegte Zeile darf ein Grabstein aus demselben
            // Durchlauf gleich wieder entfernen.
            try await applyServerDeletions()
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
        // Grabsteine gelten pro Konto - ein Cursor aus Konto A sagt ueber Konto B
        // nichts aus. Zurueckgesetzt holt der naechste Abruf dessen vollstaendige
        // Liste.
        lastDeletionCursor = nil
        // Gebuehren kennen ihren Anbieter nach dem ersten Sync nur noch ueber
        // dessen serverId. Die verfaellt gleich - ohne Umschreiben auf die
        // lokale UUID liesse sich die Gebuehr fuer das neue Konto nie mehr
        // zuordnen und bliebe fuer immer ungepusht.
        if let providers = try? context.fetch(FetchDescriptor<LocalProvider>()),
           let fees = try? context.fetch(FetchDescriptor<LocalProviderFee>()) {
            var localRef: [String: String] = [:]
            for provider in providers {
                if let serverId = provider.serverId { localRef[serverId] = provider.localId.uuidString }
            }
            for fee in fees {
                if let ref = localRef[fee.providerId] { fee.providerId = ref }
            }
        }
        resetSyncState(for: LocalVehicle.self)
        resetSyncState(for: LocalProvider.self)
        resetSyncState(for: LocalChargingLocation.self)
        resetSyncState(for: LocalChargingSession.self)
        resetSyncState(for: LocalProviderFee.self)
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
        var errorDescription: String? { String(localized: "Konnte \(what) nicht zuordnen.") }
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
                itemErrors.append(String(localized: "Fahrzeug „\(vehicle.name)“: \(error.localizedDescription)"))
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
                itemErrors.append(String(localized: "Anbieter „\(provider.name)“: \(error.localizedDescription)"))
            }
        }
        try context.save()
    }

    /// Grundgebuehren nach den Anbietern, damit eine neue Gebuehr die serverId
    /// ihres gerade erst hochgeladenen Anbieters schon kennt.
    ///
    /// Gegen einen Server aelter als 0.27.0 (404 auf die Liste) bleibt alles
    /// lokal und dirty - nach dem Server-Update geht es beim naechsten Sync von
    /// selbst hoch, und der uebrige Sync gilt deswegen nicht als gescheitert.
    private func pushFees() async throws {
        do {
            _ = try await APIClient.shared.fetchProviderFees()
            serverSupportsFees = true
        } catch APIError.server(let statusCode, _) where statusCode == 404 {
            serverSupportsFees = false
            return
        }
        let dirty = try context.fetch(FetchDescriptor<LocalProviderFee>(predicate: #Predicate { $0.isDirty }))
        for fee in dirty {
            do {
                if fee.pendingDelete {
                    if let serverId = fee.serverId {
                        try? await APIClient.shared.deleteProviderFee(id: serverId)
                    }
                    context.delete(fee)
                    continue
                }
                guard let providerId = try resolvedProviderServerId(fee.providerId) else {
                    throw UnresolvedReferenceError(what: String(localized: "Anbieter"))
                }
                let payload = ProviderFeePayload(
                    providerId: providerId, amount: fee.amount,
                    interval: FeeInterval(rawValue: fee.interval) ?? .monthly,
                    startDate: fee.startDate, endDate: fee.endDate, label: fee.label, notes: fee.notes
                )
                if let serverId = fee.serverId {
                    _ = try await APIClient.shared.updateProviderFee(id: serverId, payload)
                } else {
                    let created = try await APIClient.shared.createProviderFee(payload)
                    fee.serverId = created.id
                }
                fee.providerId = providerId
                fee.isDirty = false
            } catch {
                itemErrors.append(String(localized: "Grundgebühr „\(fee.label ?? fee.amount.formatted(.currency(code: "EUR")))“: \(error.localizedDescription)"))
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
                itemErrors.append(String(localized: "Ladeort „\(location.name)“: \(error.localizedDescription)"))
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
                    outsideTempC: session.outsideTempC,
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
                itemErrors.append(String(localized: "Ladevorgang vom \(session.startTime.formatted()): \(error.localizedDescription)"))
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
            throw UnresolvedReferenceError(what: String(localized: "Fahrzeug"))
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

    private func pullFees() async throws {
        guard serverSupportsFees else { return }
        let serverFees = try await APIClient.shared.fetchProviderFees()
        for sf in serverFees {
            if let existing = try findLocalFee(serverId: sf.id) {
                if !existing.isDirty {
                    existing.providerId = sf.providerId
                    existing.amount = sf.amount
                    existing.interval = sf.interval.rawValue
                    existing.startDate = sf.startDate
                    existing.endDate = sf.endDate
                    existing.label = sf.label
                    existing.notes = sf.notes
                }
            } else {
                context.insert(LocalProviderFee(
                    serverId: sf.id, providerId: sf.providerId, amount: sf.amount,
                    interval: sf.interval.rawValue, startDate: sf.startDate, endDate: sf.endDate,
                    label: sf.label, notes: sf.notes, isDirty: false
                ))
            }
        }
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
                    energyIsEstimated: ss.energyIsEstimated, odometerKm: ss.odometerKm,
                    outsideTempC: ss.outsideTempC, outsideTempSource: ss.outsideTempSource,
                    priceTotal: ss.priceTotal,
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
        session.outsideTempC = dto.outsideTempC
        session.outsideTempSource = dto.outsideTempSource
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

    /// ACHTUNG: entfernt lokale Spiegel-Zeilen bewusst NICHT, nur weil sie in einer
    /// Pull-Antwort fehlen. Jede Luecke in der Antwort - ob durch einen Server-Fehler,
    /// eine unerwartet leere Antwort oder einen Fehler in der ID-Aufloesung beim
    /// vorangegangenen Push - wuerde sonst STILL und UNWIDERRUFLICH lokale Ladevorgaenge
    /// vernichten. Absenz ist kein Beweis.
    ///
    /// Serverseitige Loeschungen kommen stattdessen ueber applyServerDeletions() an: ein
    /// ausdrueckliches "diese ID ist geloescht" vom Server, das eine unvollstaendige
    /// Antwort nicht erfinden kann. Die Geisterzeilen, mit denen diese App bis dahin
    /// leben musste, gibt es damit nicht mehr.
    ///
    /// Die Funktion bleibt als bewusst leerer Aufruf an den vier Pull-Stellen stehen,
    /// damit dort sichtbar ist, dass hier NICHT aufgeraeumt wird.
    private func removeVanishedMirrors<T: PersistentModel>(_ type: T.Type, stillOnServer: Set<String>) throws where T: SyncMirrorable {
    }

    // MARK: - Serverseitige Loeschungen

    /// Cursor fuer GET /api/sync/deletions: der `server_time`-Wert des letzten
    /// erfolgreichen Abrufs, roh als Zeichenkette (siehe DeletionsResponse).
    /// UserDefaults reicht - es ist kein sensibler Wert, und geht er verloren,
    /// holt der naechste Abruf eben alle Grabsteine statt nur der neuen.
    private var lastDeletionCursor: String? {
        get { UserDefaults.standard.string(forKey: "lastDeletionCursor") }
        set { UserDefaults.standard.set(newValue, forKey: "lastDeletionCursor") }
    }

    /// Loescht lokal, was auf dem Server geloescht wurde.
    ///
    /// Der Grabstein gewinnt - auch gegen eine lokal noch ungespeicherte Aenderung
    /// (`isDirty`). Das ist Absicht: die Zeile existiert auf dem Server nicht mehr,
    /// ein Push darauf liefe ins Leere (404), und sie stehenzulassen brachte genau
    /// die Geisterzeilen zurueck, wegen derer es diesen Mechanismus gibt. Der Fall
    /// verlangt ohnehin zwei Geraete gleichzeitig: eines loescht, das andere
    /// bearbeitet denselben Datensatz, bevor es synchronisiert.
    ///
    /// Der Cursor wird erst NACH dem erfolgreichen Anwenden gesetzt. Bricht der
    /// Durchlauf vorher ab, kommen dieselben Grabsteine beim naechsten Mal erneut -
    /// eine bereits geloeschte Zeile noch einmal zu loeschen ist folgenlos, eine
    /// verpasste Loeschung waere dauerhaft.
    private func applyServerDeletions() async throws {
        let response: DeletionsResponse
        do {
            response = try await APIClient.shared.fetchDeletions(since: lastDeletionCursor)
        } catch APIError.server(let statusCode, _) where statusCode == 404 {
            // Server aelter als 0.22.0 - den Endpunkt gibt es dort noch nicht.
            // Dann bleibt es beim bisherigen Verhalten (serverseitige Loeschungen
            // bleiben als Geisterzeilen stehen); der Rest des Syncs soll deswegen
            // aber nicht als fehlgeschlagen gelten.
            return
        }
        for record in response.deletions {
            switch record.entityType {
            case "vehicle":
                if let row = try findLocalVehicle(serverId: record.entityId) { context.delete(row) }
            case "provider":
                if let row = try findLocalProvider(serverId: record.entityId) {
                    // Seine Gebuehren mit: eine noch nie hochgeladene haette sonst
                    // keinen Anbieter mehr und scheiterte bei jedem Push erneut.
                    let refs = Set([row.localId.uuidString, record.entityId])
                    try context.fetch(FetchDescriptor<LocalProviderFee>())
                        .filter { refs.contains($0.providerId) }
                        .forEach { context.delete($0) }
                    context.delete(row)
                }
            case "location":
                if let row = try findLocalLocation(serverId: record.entityId) { context.delete(row) }
            case "session":
                if let row = try findLocalSession(serverId: record.entityId) { context.delete(row) }
            case "provider_fee":
                if let row = try findLocalFee(serverId: record.entityId) { context.delete(row) }
            default:
                // Unbekannter Typ aus einem neueren Server: ueberspringen statt
                // zu raten. Eine aeltere App soll an einem neueren Server nicht
                // scheitern.
                continue
            }
        }
        try context.save()
        lastDeletionCursor = response.serverTime
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
    private func findLocalFee(serverId: String) throws -> LocalProviderFee? {
        try context.fetch(FetchDescriptor<LocalProviderFee>(predicate: #Predicate { $0.serverId == serverId })).first
    }
}

/// Gemeinsames Protokoll der LocalModels-Typen (plus LocalProviderFee), nur damit removeVanishedMirrors()/
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
