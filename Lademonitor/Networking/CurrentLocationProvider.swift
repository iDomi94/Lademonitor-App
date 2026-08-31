import CoreLocation
import Combine

/// Einmalige Abfrage des aktuellen Standorts via CoreLocation, als async/await
/// verpackt. Fragt bei Bedarf die "When in Use"-Berechtigung an.
@MainActor
final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var awaitingAuthorization = false

    enum LocationError: LocalizedError {
        case denied
        case busy
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                return String(localized: "Standortzugriff nicht erlaubt. Bitte in den iOS-Einstellungen unter „Datenschutz → Ortungsdienste“ aktivieren.")
            case .busy:
                return String(localized: "Es läuft bereits eine Standortabfrage.")
            case .failed(let message):
                return String(localized: "Standort konnte nicht ermittelt werden: \(message)")
            }
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Liefert die aktuellen Koordinaten oder wirft einen `LocationError`.
    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        guard continuation == nil else { throw LocationError.busy }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .notDetermined:
                awaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            @unknown default:
                finish(.failure(LocationError.denied))
            }
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        awaitingAuthorization = false
        cont.resume(with: result)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard awaitingAuthorization else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                awaitingAuthorization = false
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            case .notDetermined:
                break // Weiter warten, bis der Nutzer entscheidet.
            @unknown default:
                finish(.failure(LocationError.denied))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.first?.coordinate
        Task { @MainActor in
            if let coordinate {
                finish(.success(coordinate))
            } else {
                finish(.failure(LocationError.failed(String(localized: "Keine Position empfangen."))))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            // Frühe Fehler ignorieren, solange nur die Autorisierung aussteht.
            guard !awaitingAuthorization else { return }
            finish(.failure(LocationError.failed(message)))
        }
    }
}
