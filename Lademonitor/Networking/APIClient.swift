import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(statusCode: Int, message: String)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Keine Server-URL konfiguriert. Bitte in den Einstellungen eintragen."
        case .invalidResponse:
            return "Ungültige Antwort vom Server."
        case .server(let code, let message):
            return "Serverfehler (\(code)): \(message)"
        case .decoding(let err):
            return "Antwort konnte nicht gelesen werden: \(err.localizedDescription)"
        case .network(let err):
            return "Verbindung fehlgeschlagen: \(err.localizedDescription)"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = formatter.date(from: raw) { return date }
            if let date = fallback.date(from: raw) { return date }
            // Backend liefert teils "YYYY-MM-DDTHH:MM:SS" ohne Zeitzone (naive datetime),
            // ggf. mit Sekundenbruchteilen (z.B. Postgres/SQLAlchemy:
            // "2026-08-11T19:55:48.123456"). Diese Wanduhrzeit ist als lokale Zeit
            // gemeint, daher in der aktuellen Zeitzone interpretieren – sonst wird
            // z.B. 00:00 als UTC gelesen und in Deutschland (Sommer UTC+2)
            // faelschlich als 02:00 angezeigt.
            let plain = DateFormatter()
            plain.locale = Locale(identifier: "en_US_POSIX")
            plain.timeZone = TimeZone.current
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                           "yyyy-MM-dd'T'HH:mm:ss.SSS",
                           "yyyy-MM-dd'T'HH:mm:ss"] {
                plain.dateFormat = format
                if let date = plain.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unbekanntes Datumsformat: \(raw)")
        }
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        // Naive Zeitstempel (ohne Offset) als lokale Wanduhrzeit senden, passend
        // zur Interpretation beim Decodieren und zur Anzeige.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone.current
        e.dateEncodingStrategy = .formatted(formatter)
        return e
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true) throws -> URLRequest {
        guard let base = AppSettings.shared.serverURL else { throw APIError.notConfigured }
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Auth-Token zentral anhaengen, damit alle bestehenden Endpunkte ihn
        // automatisch mitschicken. Fuer Login/Registrierung: authenticated = false.
        if authenticated, let token = KeychainStore.shared.readToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        request.timeoutInterval = 15
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        try validate(response, data: data, request: request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func sendNoContent(_ request: URLRequest) async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        try validate(response, data: data, request: request)
    }

    /// Prueft den HTTP-Status. Bei 401 auf einem authentifizierten Request gilt die
    /// Session als ungueltig -> Token verwerfen und zurueck zum Login.
    private func validate(_ response: URLResponse, data: Data, request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401, request.value(forHTTPHeaderField: "Authorization") != nil {
                Task { @MainActor in SessionManager.shared.invalidateSession() }
            }
            throw APIError.server(statusCode: http.statusCode, message: message(from: data))
        }
    }

    /// Fehlermeldung aus einer `{ "detail": ... }`-Antwort extrahieren.
    private func message(from data: Data) -> String {
        struct Detail: Decodable { let detail: String }
        if let parsed = try? JSONDecoder().decode(Detail.self, from: data), !parsed.detail.isEmpty {
            return parsed.detail
        }
        return String(data: data, encoding: .utf8) ?? "unbekannt"
    }

    // MARK: - Auth

    func register(username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(AuthCredentials(username: username, password: password))
        return try await send(try makeRequest(path: "/api/auth/register", method: "POST", body: body, authenticated: false))
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(AuthCredentials(username: username, password: password))
        return try await send(try makeRequest(path: "/api/auth/login", method: "POST", body: body, authenticated: false))
    }

    func logout() async throws {
        try await sendNoContent(try makeRequest(path: "/api/auth/logout", method: "POST"))
    }

    func fetchMe() async throws -> AuthUser {
        try await send(try makeRequest(path: "/api/auth/me"))
    }

    // MARK: - Health

    func checkHealth() async throws -> Bool {
        let request = try makeRequest(path: "/health")
        struct Health: Decodable { let status: String }
        let result: Health = try await send(request)
        return result.status == "ok"
    }

    // MARK: - Vehicles

    func fetchVehicles() async throws -> [Vehicle] {
        try await send(try makeRequest(path: "/api/vehicles"))
    }

    func createVehicle(_ payload: VehiclePayload) async throws -> Vehicle {
        let body = try encoder.encode(payload)
        return try await send(try makeRequest(path: "/api/vehicles", method: "POST", body: body))
    }

    func updateVehicle(id: String, _ payload: VehiclePayload) async throws -> Vehicle {
        let body = try encoder.encode(payload)
        return try await send(try makeRequest(path: "/api/vehicles/\(id)", method: "PATCH", body: body))
    }

    /// Achtung: Loescht serverseitig kaskadierend alle zugehoerigen Ladevorgaenge.
    func deleteVehicle(id: String) async throws {
        try await sendNoContent(try makeRequest(path: "/api/vehicles/\(id)", method: "DELETE"))
    }

    // MARK: - Providers

    func fetchProviders() async throws -> [Provider] {
        try await send(try makeRequest(path: "/api/providers"))
    }

    func createProvider(_ payload: ProviderPayload) async throws -> Provider {
        let body = try encoder.encode(payload)
        return try await send(try makeRequest(path: "/api/providers", method: "POST", body: body))
    }

    func updateProvider(id: String, _ payload: ProviderPayload) async throws -> Provider {
        let body = try encoder.encode(payload)
        return try await send(try makeRequest(path: "/api/providers/\(id)", method: "PATCH", body: body))
    }

    func deleteProvider(id: String) async throws {
        try await sendNoContent(try makeRequest(path: "/api/providers/\(id)", method: "DELETE"))
    }

    // MARK: - Locations

    func fetchLocations() async throws -> [ChargingLocation] {
        try await send(try makeRequest(path: "/api/locations"))
    }

    func createLocation(_ payload: LocationPayload) async throws -> ChargingLocation {
        let body = try encoder.encode(payload)
        return try await send(try makeRequest(path: "/api/locations", method: "POST", body: body))
    }

    func updateLocation(id: String, _ payload: LocationPayload) async throws -> ChargingLocation {
        let body = try encoder.encode(payload)
        return try await send(try makeRequest(path: "/api/locations/\(id)", method: "PATCH", body: body))
    }

    func deleteLocation(id: String) async throws {
        try await sendNoContent(try makeRequest(path: "/api/locations/\(id)", method: "DELETE"))
    }

    // MARK: - Geocoding

    /// Freitext-Adresssuche (Forward-Geocoding). Leeres Array = keine Treffer.
    /// URL wird ueber URLComponents gebaut, damit der Query-Text korrekt
    /// prozentkodiert wird (makeRequest wuerde ein "?" im Pfad falsch encodieren).
    func forwardGeocode(query: String) async throws -> [GeocodeResult] {
        guard let base = AppSettings.shared.serverURL else { throw APIError.notConfigured }
        guard var components = URLComponents(
            url: base.appendingPathComponent("/api/geocode/forward"),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidResponse }
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        return try await send(request)
    }

    // MARK: - Sessions

    func fetchSessions(vehicleId: String? = nil, needsReview: Bool? = nil) async throws -> [ChargingSession] {
        var path = "/api/sessions"
        var query: [String] = []
        if let vehicleId { query.append("vehicle_id=\(vehicleId)") }
        if let needsReview { query.append("needs_review=\(needsReview)") }
        if !query.isEmpty { path += "?" + query.joined(separator: "&") }
        return try await send(try makeRequest(path: path))
    }

    func createSession(_ payload: ChargingSessionPayload) async throws -> ChargingSession {
        let body = try encoder.encode(payload)
        let request = try makeRequest(path: "/api/sessions", method: "POST", body: body)
        return try await send(request)
    }

    func updateSession(id: String, _ payload: ChargingSessionPayload) async throws -> ChargingSession {
        let body = try encoder.encode(payload)
        let request = try makeRequest(path: "/api/sessions/\(id)", method: "PATCH", body: body)
        return try await send(request)
    }

    func deleteSession(id: String) async throws {
        let request = try makeRequest(path: "/api/sessions/\(id)", method: "DELETE")
        try await sendNoContent(request)
    }

    // MARK: - Stats

    func fetchStatsSummary(vehicleId: String? = nil) async throws -> StatsSummary {
        var path = "/api/stats/summary"
        if let vehicleId { path += "?vehicle_id=\(vehicleId)" }
        return try await send(try makeRequest(path: path))
    }
}
