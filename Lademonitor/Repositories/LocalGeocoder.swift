import Foundation
import MapKit

/// Ersatz fuer APIClient.forwardGeocode() im Local-Only-Modus: die Server-Route
/// proxied zu OSM-Nominatim (bewusste Ausnahme von "kein Cloud-Dienst" im Server-
/// Projekt, siehe dortige CLAUDE.md) - ohne Server nutzen wir stattdessen Apples
/// eigene On-Device/Apple-Maps-Suche (MKLocalSearch), keine eigene Cloud-Abhaengigkeit.
enum LocalGeocoder {
    static func search(query: String) async throws -> [GeocodeResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems.map { item in
            let name = item.name
            let address = item.placemark.title
            let display = [name, address]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let joined = display.isEmpty ? String(localized: "Unbekannter Ort") : display.joined(separator: " – ")
            return GeocodeResult(
                displayName: joined,
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
        }
    }
}
