import Foundation
import SwiftData

/// SwiftData-Pendants zu den Codable-DTOs in Models.swift, fuer den Local-Only-Modus
/// (und spaeter als lokaler Puffer im Server-Modus). Jede Zeile traegt zusaetzlich zu
/// den Fachfeldern Sync-Metadaten:
/// - `localId`: stabile, rein lokale Identitaet (existiert schon vor jedem Server-Kontakt)
/// - `serverId`: erst gesetzt, nachdem die Zeile einmal erfolgreich hochgeladen wurde
///   (der Server vergibt IDs selbst, siehe Lademonitor-Server/backend/app/models.py)
/// - `updatedAt`/`isDirty`/`pendingDelete`: fuer den spaeteren SyncService (Schritt 2),
///   im Local-Only-Modus aktuell ungenutzt, aber schon jetzt im Schema, um eine
///   SwiftData-Migration beim Einfuehren des Sync-Layers zu vermeiden.
@Model
final class LocalVehicle {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    var externalId: String
    var name: String
    var brand: String?
    var model: String?
    var batteryCapacityKwh: Double?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        externalId: String,
        name: String,
        brand: String? = nil,
        model: String? = nil,
        batteryCapacityKwh: Double? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.externalId = externalId
        self.name = name
        self.brand = brand
        self.model = model
        self.batteryCapacityKwh = batteryCapacityKwh
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }
}

@Model
final class LocalProvider {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    var name: String
    var lastPriceAcPerKwh: Double?
    var lastPriceDcPerKwh: Double?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        name: String,
        lastPriceAcPerKwh: Double? = nil,
        lastPriceDcPerKwh: Double? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.name = name
        self.lastPriceAcPerKwh = lastPriceAcPerKwh
        self.lastPriceDcPerKwh = lastPriceDcPerKwh
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }
}

@Model
final class LocalChargingLocation {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusM: Int
    /// Zeigt auf `LocalProvider.serverId ?? localId.uuidString` - lose Referenz per
    /// ID-String statt SwiftData-Relationship, analog zu den Server-DTOs (siehe
    /// ChargingLocation.defaultProviderId in Models.swift).
    var defaultProviderId: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusM: Int = 100,
        defaultProviderId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusM = radiusM
        self.defaultProviderId = defaultProviderId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }
}

@Model
final class LocalChargingSession {
    @Attribute(.unique) var localId: UUID
    var serverId: String?
    /// ID-Referenzen auf LocalVehicle/LocalProvider/LocalChargingLocation, siehe
    /// Kommentar bei LocalChargingLocation.defaultProviderId.
    var vehicleId: String
    var providerId: String?
    var locationId: String?
    var startTime: Date
    var endTime: Date?
    var chargingType: String?
    var socStart: Int?
    var socEnd: Int?
    var energyKwh: Double?
    var energyIsEstimated: Bool
    var odometerKm: Int?
    var priceTotal: Double?
    var pricePerKwh: Double?
    var latitude: Double?
    var longitude: Double?
    var geocodedPlace: String?
    var notes: String?
    var source: String
    var needsReview: Bool
    var externalSessionId: String?
    var createdAt: Date
    var updatedAt: Date
    var isDirty: Bool
    var pendingDelete: Bool

    init(
        localId: UUID = UUID(),
        serverId: String? = nil,
        vehicleId: String,
        providerId: String? = nil,
        locationId: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        chargingType: String? = nil,
        socStart: Int? = nil,
        socEnd: Int? = nil,
        energyKwh: Double? = nil,
        energyIsEstimated: Bool = false,
        odometerKm: Int? = nil,
        priceTotal: Double? = nil,
        pricePerKwh: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        geocodedPlace: String? = nil,
        notes: String? = nil,
        source: String = "manual",
        needsReview: Bool = false,
        externalSessionId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDirty: Bool = true,
        pendingDelete: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.vehicleId = vehicleId
        self.providerId = providerId
        self.locationId = locationId
        self.startTime = startTime
        self.endTime = endTime
        self.chargingType = chargingType
        self.socStart = socStart
        self.socEnd = socEnd
        self.energyKwh = energyKwh
        self.energyIsEstimated = energyIsEstimated
        self.odometerKm = odometerKm
        self.priceTotal = priceTotal
        self.pricePerKwh = pricePerKwh
        self.latitude = latitude
        self.longitude = longitude
        self.geocodedPlace = geocodedPlace
        self.notes = notes
        self.source = source
        self.needsReview = needsReview
        self.externalSessionId = externalSessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDirty = isDirty
        self.pendingDelete = pendingDelete
    }
}

// MARK: - Mapping zu den bestehenden DTOs (Models.swift)
//
// `id` der DTOs wird bewusst `serverId ?? localId.uuidString`: solange eine Zeile nie
// synchronisiert wurde, ist die lokale UUID die einzige Identitaet; nach dem Sync
// (Schritt 2) uebernimmt die Server-ID. Views arbeiten ausschliesslich mit den DTOs
// und muessen diesen Unterschied nicht kennen.

extension LocalVehicle {
    var asDTO: Vehicle {
        Vehicle(
            id: serverId ?? localId.uuidString,
            externalId: externalId,
            name: name,
            brand: brand,
            model: model,
            batteryCapacityKwh: batteryCapacityKwh,
            isActive: isActive
        )
    }
}

extension LocalProvider {
    var asDTO: Provider {
        Provider(
            id: serverId ?? localId.uuidString,
            name: name,
            lastPriceAcPerKwh: lastPriceAcPerKwh,
            lastPriceDcPerKwh: lastPriceDcPerKwh,
            notes: notes
        )
    }
}

extension LocalChargingLocation {
    var asDTO: ChargingLocation {
        ChargingLocation(
            id: serverId ?? localId.uuidString,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusM: radiusM,
            defaultProviderId: defaultProviderId
        )
    }
}

extension LocalChargingSession {
    var asDTO: ChargingSession {
        ChargingSession(
            id: serverId ?? localId.uuidString,
            vehicleId: vehicleId,
            providerId: providerId,
            locationId: locationId,
            startTime: startTime,
            endTime: endTime,
            chargingType: chargingType.flatMap(ChargingType.init(rawValue:)),
            socStart: socStart,
            socEnd: socEnd,
            energyKwh: energyKwh,
            energyIsEstimated: energyIsEstimated,
            odometerKm: odometerKm,
            priceTotal: priceTotal,
            pricePerKwh: pricePerKwh,
            latitude: latitude,
            longitude: longitude,
            geocodedPlace: geocodedPlace,
            consumptionKwhPer100km: nil,
            consumptionMethod: nil,
            notes: notes,
            source: SessionSource(rawValue: source) ?? .manual,
            needsReview: needsReview,
            externalSessionId: externalSessionId
        )
    }
}
