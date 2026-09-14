import SwiftUI

/// Wird nur einmalig beim allerersten Start gezeigt (AppSettings.appMode == .undecided),
/// ersetzt den frueher erzwungenen Login-Screen. Der Server-Modus fuehrt direkt weiter
/// zu AuthView; der Local-Only-Modus schaltet sofort in die Haupt-App.
struct ModeSelectionView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Bewusst die gerundete Kachel (= das App-Icon) statt des queren
                // Zeichens aus der Web-Kopfleiste: dieser Screen folgt dem
                // Hell/Dunkel-Modus des Systems, und die graue Silhouette mit
                // gruenem Kabel ist fuer dunklen Grund gezeichnet. Die Kachel
                // bringt ihren eigenen Grund mit und sitzt in beiden Modi richtig.
                // Dekorativ: der Schriftzug direkt darunter traegt den Namen schon.
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Lademonitor")
                        .font(.largeTitle.bold())
                    Text("Wie möchtest du die App nutzen?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    ModeOptionCard(
                        icon: "iphone",
                        title: String(localized: "Nur lokal auf diesem Gerät"),
                        description: String(localized: "Alle Daten bleiben ausschließlich auf diesem iPhone. Kein Server, keine automatische Erkennung über Home Assistant, keine Synchronisation zwischen Geräten. Du kannst später jederzeit zu einem Server wechseln und alle lokalen Daten hochladen.")
                    ) {
                        settings.appMode = .localOnly
                    }

                    ModeOptionCard(
                        icon: "network",
                        title: String(localized: "Mit eigenem Server verbinden"),
                        description: String(localized: "Daten liegen zentral auf einem selbst gehosteten Lademonitor-Server (Open Source, per Docker) statt nur auf dem Gerät: automatische Ladevorgangs-Erkennung über Home Assistant, Zugriff auch vom Web-UI aus, alle Geräte zeigen denselben Stand."),
                        link: (String(localized: "Quellcode auf GitHub"), URL(string: "https://github.com/iDomi94/Lademonitor-Server")!)
                    ) {
                        settings.serverHosting = .selfHosted
                        settings.appMode = .server
                    }

                    ModeOptionCard(
                        icon: "cloud",
                        title: String(localized: "Lademonitor-Cloud"),
                        description: String(localized: "Wie „Mit eigenem Server verbinden“, aber auf dem öffentlichen Server unter lademonitor.cloud – der Betreiber übernimmt Betrieb, Updates und Backups für dich. Kein eigener Server nötig.")
                    ) {
                        settings.serverHosting = .cloud
                        settings.appMode = .server
                    }
                }
                .padding(.horizontal)

                Spacer()
                Spacer()
            }
            .padding()
        }
    }
}

private struct ModeOptionCard: View {
    let icon: String
    let title: String
    let description: String
    var link: (title: String, url: URL)? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if let link {
                Link(destination: link.url) {
                    Text(link.title)
                }
                .font(.caption)
                .padding(.leading, 48)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ModeSelectionView()
}
