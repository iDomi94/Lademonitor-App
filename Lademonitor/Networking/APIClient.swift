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
            return String(localized: "Keine Server-URL konfiguriert. Bitte in den Einstellungen eintragen.")
        case .invalidResponse:
            return String(localized: "Ungültige Antwort vom Server.")
        case .server(let code, let message):
            return String(localized: "Serverfehler (\(code)): \(message)")
        case .decoding(let err):
            return String(localized: "Antwort konnte nicht gelesen werden: \(err.localizedDescription)")
        case .network(let err):
            return String(localized: "Verbindung fehlgeschlagen: \(err.localizedDescription)")
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

    /// Baut einen Request auf einen Pfad, der auch einen Query-String enthalten darf.
    ///
    /// `appendingPathComponent` behandelt sein Argument als EINEN Pfadbestandteil
    /// und prozentkodiert alles, was darin nicht erlaubt ist - aus
    /// "/api/sessions?vehicle_id=x" wird also ".../api/sessions%3Fvehicle_id=x",
    /// und der Server sieht einen unbekannten Pfad statt eines Filters. Deshalb
    /// wird ein "?" hier vorher abgetrennt und ueber URLComponents als echter
    /// Query gesetzt.
    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true) throws -> URLRequest {
        guard let base = AppSettings.shared.serverURL else { throw APIError.notConfigured }
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var url = base.appendingPathComponent(String(parts[0]))
        if parts.count > 1, !parts[1].isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidResponse
            }
            components.percentEncodedQuery = String(parts[1])
            guard let combined = components.url else { throw APIError.invalidResponse }
            url = combined
        }
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

    func register(username: String, password: String, email: String? = nil) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(
            RegisterCredentials(username: username, password: password, email: email)
        )
        return try await send(try makeRequest(path: "/api/auth/register", method: "POST", body: body, authenticated: false))
    }

    /// `identifier` ist Nutzername ODER E-Mail-Adresse. Das JSON-Feld heisst
    /// serverseitig weiterhin `username` (siehe schemas.LoginRequest) - der Name
    /// wurde bewusst nicht geaendert, damit bestehende Clients weiterlaufen.
    func login(identifier: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(AuthCredentials(username: identifier, password: password))
        return try await send(try makeRequest(path: "/api/auth/login", method: "POST", body: body, authenticated: false))
    }

    func logout() async throws {
        try await sendNoContent(try makeRequest(path: "/api/auth/logout", method: "POST"))
    }

    func fetchMe() async throws -> AuthUser {
        try await send(try makeRequest(path: "/api/auth/me"))
    }

    // MARK: - Konto (Server ab 0.14.0)

    /// Aendert das eigene Passwort und gibt den neuen Zugang zurueck.
    ///
    /// Der Server verwirft dabei ALLE Sitzungen des Nutzers - auch die eigene -
    /// und stellt sofort eine neue aus. Seit Server 0.14.1 liefert er den neuen
    /// Token in der Antwort mit (wie Login und Registrierung); vorher gab es nur
    /// ein Cookie fuer die Web-Oberflaeche und ein Bearer-Client musste sich mit
    /// dem neuen Passwort ein zweites Mal anmelden.
    func changePassword(currentPassword: String, newPassword: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(
            PasswordChangePayload(currentPassword: currentPassword, newPassword: newPassword)
        )
        return try await send(try makeRequest(path: "/api/auth/password", method: "PUT", body: body))
    }

    /// Setzt oder entfernt (`email == nil`) die eigene Adresse. Eine geaenderte
    /// Adresse gilt danach als unbestaetigt; der Server verschickt automatisch
    /// einen Bestaetigungslink, sofern der Mailversand eingerichtet ist.
    func updateEmail(_ email: String?, currentPassword: String) async throws -> AuthUser {
        let body = try JSONEncoder().encode(
            EmailUpdatePayload(email: email, currentPassword: currentPassword)
        )
        return try await send(try makeRequest(path: "/api/auth/email", method: "PUT", body: body))
    }

    func resendEmailVerification() async throws {
        try await sendNoContent(try makeRequest(path: "/api/auth/email/verify/resend", method: "POST"))
    }

    func updateNotifications(_ payload: NotificationSettingsPayload) async throws -> AuthUser {
        let body = try JSONEncoder().encode(payload)
        return try await send(try makeRequest(path: "/api/auth/notifications", method: "PUT", body: body))
    }

    /// Fordert einen Link zum Zuruecksetzen an. Der Server antwortet BEWUSST
    /// immer mit 204 - auch bei unbekanntem Konto, fehlender oder unbestaetigter
    /// Adresse. Jede Unterscheidung waere ein Verzeichnis aller Nutzernamen und
    /// Adressen dieses Servers. Die App darf daraus also nichts ableiten und
    /// zeigt in jedem Fall dieselbe Meldung.
    func requestPasswordReset(identifier: String) async throws {
        let body = try JSONEncoder().encode(PasswordResetRequestPayload(identifier: identifier))
        try await sendNoContent(
            try makeRequest(path: "/api/auth/password-reset/request", method: "POST", body: body, authenticated: false)
        )
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
    ///
    /// Baut den Request ueber URLComponents, damit der Suchtext korrekt
    /// prozentkodiert wird, haengt den Auth-Token aber wie ueberall sonst
    /// explizit an. Der Endpunkt liegt hinter der Anmeldepflicht (in main.py
    /// haengt an jedem Router ein `Depends(get_current_user)`).
    ///
    /// Ohne den Header funktionierte der Aufruf zwar meistens trotzdem - der
    /// Server setzt beim Login zusaetzlich ein `session_token`-Cookie, und
    /// `URLSession.shared` schickt Cookies automatisch mit. Genau das ist das
    /// Problem: die Adresssuche haengt dann als einziger Aufruf an einem
    /// impliziten Nebenweg statt am Token aus dem Keychain. Sie faellt aus,
    /// sobald der Cookie-Speicher leer ist (Neuinstallation, aus einem Backup
    /// wiederhergestellte App), und die 401-Behandlung in `validate` greift
    /// nicht, weil die nur bei gesetztem Authorization-Header anschlaegt - eine
    /// serverseitig beendete Sitzung erschiene hier also als nackter
    /// "Serverfehler (401)", statt zurueck zum Login zu fuehren.
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
        if let token = KeychainStore.shared.readToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
