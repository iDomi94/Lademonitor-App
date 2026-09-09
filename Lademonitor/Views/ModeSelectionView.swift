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

                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

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
                        description: String(localized: "Daten liegen zentral auf einem Lademonitor-Server statt nur auf dem Gerät: automatische Ladevorgangs-Erkennung über Home Assistant, Zugriff auch vom Web-UI aus, alle Geräte zeigen denselben Stand. Selbst gehostet (Open Source, per Docker) oder – in Kürze – auf dem öffentlichen Server unter lademonitor.cloud, der dir Betrieb, Updates und Backups abnimmt."),
                        link: (String(localized: "Quellcode auf GitHub"), URL(string: "https://github.com/iDomi94/Lademonitor-Server")!)
                    ) {
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
