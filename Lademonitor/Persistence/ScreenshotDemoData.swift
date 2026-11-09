import Foundation
import SwiftData

/// Beispieldaten fuer die automatisierten App-Store-Screenshots (siehe
/// LademonitorUITests/ScreenshotTests.swift). Aktiv nur mit dem Launch-Argument
/// `-screenshotDemo`: dann laeuft der SwiftData-Store rein im Speicher (siehe
/// LocalStore) - echte Ladevorgaenge auf dem Geraet werden weder gelesen noch
/// ueberschrieben.
///
/// Zwei Quellen: ohne weitere Angaben Local-Only mit den Beispieldaten unten,
/// mit `SCREENSHOT_SERVER_URL`/`SCREENSHOT_USER`/`SCREENSHOT_PASSWORD` in der
/// Umgebung der Server-Modus mit einem Testkonto. Der leere In-Memory-Store
/// wird dann nur vom Server befuellt - hochgeladen wird nichts.
@MainActor
enum ScreenshotDemoData {
    nonisolated static let launchArgument = "-screenshotDemo"

    nonisolated static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    struct ServerAccount {
        let url: String
        let identifier: String
        let password: String
    }

    /// Das Testkonto fuer Screenshots im Server-Modus, sonst `nil`.
    nonisolated static var serverAccount: ServerAccount? {
        guard isActive else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["SCREENSHOT_SERVER_URL"], !url.isEmpty,
              let identifier = environment["SCREENSHOT_USER"], !identifier.isEmpty,
              let password = environment["SCREENSHOT_PASSWORD"], !password.isEmpty
        else { return nil }
        return ServerAccount(url: url, identifier: identifier, password: password)
    }

    /// Meldet das Testkonto an und stoesst den ersten Sync an - wie AuthView,
    /// nur ohne Eingabe.
    static func loginIfNeeded() async {
        guard let account = serverAccount, !SessionManager.shared.isAuthenticated else { return }
        do {
            let response = try await APIClient.shared.login(identifier: account.identifier, password: account.password)
            SessionManager.shared.completeAuthentication(response)
            SyncService.shared.startAfterLogin()
        } catch {
            print("Screenshot-Demo: Anmeldung am Testkonto fehlgeschlagen: \(error)")
        }
    }

    /// Ein Fahrzeug mit gut einem halben Jahr Ladehistorie (Zuhause, Arbeit,
    /// Schnelllader unterwegs). Deterministisch, damit jeder Lauf dieselben
    /// Zahlen zeigt.
    static func seed(into context: ModelContext, now: Date = Date()) {
        var random = SeededGenerator(seed: 42)
        let calendar = Calendar.current

        let vehicle = LocalVehicle(
            externalId: "demo-vehicle",
            name: "Mein ID.4",
            brand: "Volkswagen",
            model: "ID.4 Pro",
            batteryCapacityKwh: 77,
            isDirty: false
        )
        context.insert(vehicle)
        let vehicleId = vehicle.localId.uuidString

        let home = LocalProvider(
            name: "Stadtwerke (Wallbox)", lastPriceAcPerKwh: 0.32,
            chargingPlace: "home", isDirty: false
        )
        let work = LocalProvider(
            name: "Arbeitgeber", lastPriceAcPerKwh: 0.25,
            chargingPlace: "work", isDirty: false
        )
        let ionity = LocalProvider(
            name: "IONITY", lastPriceDcPerKwh: 0.59, isDirty: false
        )
        let enbw = LocalProvider(
            name: "EnBW mobility+", lastPriceAcPerKwh: 0.49, lastPriceDcPerKwh: 0.59, isDirty: false
        )
        [home, work, ionity, enbw].forEach(context.insert)

        struct Place {
            let location: LocalChargingLocation
            let provider: LocalProvider
            let type: ChargingType
            let name: String
        }
        func place(_ name: String, _ lat: Double, _ lon: Double, _ provider: LocalProvider, _ type: ChargingType) -> Place {
            let location = LocalChargingLocation(
                name: name, latitude: lat, longitude: lon,
                defaultProviderId: provider.localId.uuidString, isDirty: false
            )
            context.insert(location)
            return Place(location: location, provider: provider, type: type, name: name)
        }
        let homePlace = place("Zuhause", 48.1374, 11.5755, home, .ac)
        let workPlace = place("Büro", 48.1772, 11.5562, work, .ac)
        let trips = [
            place("IONITY Holledau", 48.5560, 11.5980, ionity, .dc),
            place("EnBW Augsburg", 48.3705, 10.8978, enbw, .dc),
            place("IONITY Irschenberg", 47.8330, 11.9150, ionity, .dc),
            place("EnBW Rosenheim", 47.8561, 12.1289, enbw, .ac)
        ]

        // Rueckwaerts ab heute: alle 2-5 Tage ein Vorgang, meist zuhause,
        // ab und zu im Buero oder unterwegs.
        let start = calendar.date(byAdding: .month, value: -7, to: now) ?? now
        var day = start
        var odometer = 18_400
        var soc = 70
        while day < now {
            let roll = Int.random(in: 0..<10, using: &random)
            let place = roll < 6 ? homePlace : (roll < 8 ? workPlace : trips[Int.random(in: 0..<trips.count, using: &random)])

            let driven = Int.random(in: 90...260, using: &random)
            odometer += driven
            // Verbrauch im Winter etwas hoeher - fuer die Temperaturkurven.
            let month = calendar.component(.month, from: day)
            let winter = [11, 12, 1, 2, 3].contains(month)
            let consumption = (winter ? 19.5 : 16.0) + Double.random(in: -1.5...1.5, using: &random)
            let socStart = max(8, soc - Int(Double(driven) * consumption / 100 / 77 * 100))
            let socEnd = place.type == .dc ? Int.random(in: 75...85, using: &random) : 80
            let energy = Double(socEnd - socStart) / 100 * 77 * (place.type == .dc ? 1.04 : 1.1)
            let price = place.type == .dc
                ? (place.provider.lastPriceDcPerKwh ?? 0.59)
                : (place.provider.lastPriceAcPerKwh ?? 0.32)
            let hour = place.location === homePlace.location ? 19 : (place.location === workPlace.location ? 8 : 13)
            let startTime = calendar.date(bySettingHour: hour, minute: Int.random(in: 0..<60, using: &random), second: 0, of: day) ?? day
            let minutes = place.type == .dc ? Int.random(in: 20...40, using: &random) : Int(energy / 10.5 * 60)
            let temp = (winter ? 3.0 : 17.0) + Double.random(in: -5...6, using: &random)

            context.insert(LocalChargingSession(
                vehicleId: vehicleId,
                providerId: place.provider.localId.uuidString,
                locationId: place.location.localId.uuidString,
                startTime: startTime,
                endTime: startTime.addingTimeInterval(Double(minutes) * 60),
                chargingType: place.type.rawValue,
                socStart: socStart,
                socEnd: socEnd,
                energyKwh: (energy * 10).rounded() / 10,
                odometerKm: odometer,
                outsideTempC: (temp * 10).rounded() / 10,
                outsideTempSource: "vehicle",
                priceTotal: (energy * price * 100).rounded() / 100,
                pricePerKwh: price,
                latitude: place.location.latitude,
                longitude: place.location.longitude,
                geocodedPlace: place.name,
                isDirty: false
            ))

            soc = socEnd
            day = calendar.date(byAdding: .day, value: Int.random(in: 2...5, using: &random), to: day) ?? now
        }

        try? context.save()
    }
}

/// Einfacher deterministischer Zufallsgenerator (SplitMix64), damit die
/// Demo-Daten bei jedem Lauf gleich ausfallen.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
