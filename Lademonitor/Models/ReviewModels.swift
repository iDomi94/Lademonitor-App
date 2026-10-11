import Foundation

// MARK: - Vergleichsfahrzeug (Server ab 0.36.0)

/// Das Vergleichsfahrzeug fuer "Gespart gegenueber dem Verbrenner" im
/// Rueckblick und als Startwert des Verbrenner-Tools. Global je Nutzer:
/// `GET`/`PUT /api/combustion-vehicle`. Lokal liegt es in
/// `ComparisonVehicleStore` (UserDefaults), im Server-Modus gleicht der
/// SyncService es ab.
struct ComparisonVehicle: Codable, Equatable {
    var fuelType: String
    var consumptionLPer100km: Double
    var fuelPricePerL: Double
    var gridCo2KgPerKwh: Double
    /// Nur in der Antwort: `false` = Standardwerte, nie gespeichert.
    var configured: Bool? = nil

    var fuel: CombustionComparison.Fuel { CombustionComparison.Fuel(rawValue: fuelType) ?? .petrol }

    /// Standardwerte wie im Server (petrol, 7,0 l, 1,75 EUR/l, 0,36 kg/kWh).
    static func defaults(for fuel: CombustionComparison.Fuel = .petrol) -> ComparisonVehicle {
        ComparisonVehicle(
            fuelType: fuel.rawValue,
            consumptionLPer100km: fuel.defaultConsumption,
            fuelPricePerL: fuel.defaultPrice,
            gridCo2KgPerKwh: CombustionComparison.defaultGridCo2KgPerKwh,
            configured: false
        )
    }

    enum CodingKeys: String, CodingKey {
        case configured
        case fuelType = "fuel_type"
        case consumptionLPer100km = "consumption_l_per_100km"
        case fuelPricePerL = "fuel_price_per_l"
        case gridCo2KgPerKwh = "grid_co2_kg_per_kwh"
    }
}

/// Body fuer PUT /api/combustion-vehicle - der Server erwartet alle vier Felder.
struct ComparisonVehiclePayload: Codable {
    let fuelType: String
    let consumptionLPer100km: Double
    let fuelPricePerL: Double
    let gridCo2KgPerKwh: Double

    init(_ vehicle: ComparisonVehicle) {
        fuelType = vehicle.fuelType
        consumptionLPer100km = vehicle.consumptionLPer100km
        fuelPricePerL = vehicle.fuelPricePerL
        gridCo2KgPerKwh = vehicle.gridCo2KgPerKwh
    }

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case consumptionLPer100km = "consumption_l_per_100km"
        case fuelPricePerL = "fuel_price_per_l"
        case gridCo2KgPerKwh = "grid_co2_kg_per_kwh"
    }
}

// MARK: - Rueckblick (lokal gerechnet, siehe LocalReviewCalculator)

/// Spiegel von `ReviewOut` aus GET /api/stats/review - die App rechnet ihn
/// bewusst lokal (auch im Local-Only-Modus), nach denselben Regeln. Betraege
/// in EUR, ungerundet - gerundet wird erst in der Anzeige.
struct Review {
    enum Period: String, CaseIterable, Identifiable {
        case year, month
        var id: Self { self }
    }

    struct Totals {
        var sessions: Int
        var kwh: Double
        var cost: Double
        var km: Double
        var avgPricePerKwh: Double?
        var pricePer100km: Double?
        var avgConsumptionKwhPer100km: Double?
    }

    struct Savings {
        var fuel: CombustionComparison.Fuel
        var consumptionLPer100km: Double
        var fuelPricePerL: Double
        var gridCo2KgPerKwh: Double
        var configured: Bool
        var fuelLiters: Double
        var fuelCost: Double
        var chargingCost: Double
        var savedEur: Double
        var co2CombustionKg: Double
        var co2EvKg: Double
        var savedCo2Kg: Double
    }

    struct SessionRecord {
        var sessionId: String
        var startTime: Date
        var value: Double
        var place: String?
        var vehicleName: String?
        /// Nur bei `longestDistance`: Start des vorherigen Vorgangs.
        var previousStartTime: Date? = nil
    }

    struct NamedRecord {
        var name: String
        var sessions: Int
        var kwh: Double
    }

    struct MonthRecord {
        var month: Int
        var value: Double
    }

    struct Records {
        var cheapestPerKwh: SessionRecord?
        var mostExpensivePerKwh: SessionRecord?
        var biggestCharge: SessionRecord?
        var coldest: SessionRecord?
        var warmest: SessionRecord?
        var longestDistance: SessionRecord?
        var topLocation: NamedRecord?
        var topProvider: NamedRecord?
        var lowestConsumptionMonth: MonthRecord?
        var highestConsumptionMonth: MonthRecord?
    }

    struct Split {
        var acKwh: Double
        var dcKwh: Double
        var acSharePct: Double?
        var dcSharePct: Double?
        var byPlace: [PlaceStat]
    }

    struct MonthRow: Identifiable {
        var id: Int { month }
        var month: Int
        var sessions: Int
        var kwh: Double
        var cost: Double
        var avgConsumptionKwhPer100km: Double?
    }

    var period: Period
    var year: Int
    var month: Int?
    /// Erster und letzter Tag (lokale Mitternacht), beide inklusive.
    var startDate: Date
    var endDate: Date
    var vehicleId: String?
    var totals: Totals
    /// nil, wenn die Vorperiode keinen Ladevorgang hat.
    var previous: Totals?
    /// nil, wenn im Zeitraum keine km gefahren wurden.
    var savings: Savings?
    var records: Records
    var split: Split
    /// Nur beim Jahr, dann immer 12 Zeilen.
    var monthly: [MonthRow]
}

/// Alles, was LocalReviewCalculator braucht, mit EINER ID-Form fuer
/// Fahrzeuge, Anbieter und Ladeorte. Die Ladevorgaenge tragen ihren
/// Grundgebuehr-Anteil (Umlage ueber ALLE Vorgaenge wie im Server).
struct ReviewBasis {
    let sessions: [ChargingSession]
    let vehicles: [Vehicle]
    let providers: [Provider]
    let locations: [ChargingLocation]
    /// Perioden ohne Ladevorgang, ungefiltert - der Rechner filtert selbst.
    let unallocatedFees: [LocalFeeAllocator.Period]
}
