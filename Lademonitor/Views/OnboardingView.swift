import SwiftUI

/// Einfuehrung in die wichtigsten Funktionen. Erscheint beim allerersten Start
/// VOR der Moduswahl (AppSettings.hasCompletedOnboarding) und laesst sich in
/// den Einstellungen unter "Hilfe" jederzeit erneut oeffnen.
///
/// Gleicher Inhalt wie `OnboardingScreen.kt` in der Android-App - Aenderungen
/// an Seiten oder Texten immer in beiden Apps.
struct OnboardingView: View {
    enum Context {
        /// Erster Start: die letzte Seite fuehrt weiter zur Moduswahl.
        case firstLaunch
        /// Aus den Einstellungen: die letzte Seite schliesst nur und nennt
        /// den aktuell genutzten Modus.
        case replay
    }

    let context: Context
    let onFinish: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var page = 0

    private var pageCount: Int { OnboardingPage.all.count + 1 }
    private var isLastPage: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !isLastPage {
                    Button(skipTitle) {
                        onFinish()
                    }
                    .padding()
                }
            }
            .frame(minHeight: 52)

            TabView(selection: $page) {
                ForEach(Array(OnboardingPage.all.enumerated()), id: \.offset) { index, item in
                    FeaturePageView(page: item)
                        .tag(index)
                }
                ModesPageView(context: context, currentMode: settings.appMode, hosting: settings.serverHosting)
                    .tag(pageCount - 1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var skipTitle: LocalizedStringKey {
        context == .firstLaunch ? "Überspringen" : "Schließen"
    }

    private var buttonTitle: LocalizedStringKey {
        if !isLastPage { return "Weiter" }
        return context == .firstLaunch ? "Modus auswählen" : "Fertig"
    }
}

/// Eine Seite der Einfuehrung: Symbol, Ueberschrift, ein Satz und ein paar
/// Punkte. Die Moduswahl ist die eigene letzte Seite (ModesPageView).
struct OnboardingPage {
    let icon: String
    let title: LocalizedStringKey
    let intro: LocalizedStringKey
    let points: [OnboardingPoint]

    static let all: [OnboardingPage] = [
        OnboardingPage(
            icon: "bolt.car.fill",
            title: "Willkommen bei Lademonitor",
            intro: "Dein Fahrtenbuch fürs Laden: jeder Ladevorgang mit Energie, Preis, Ladestand und Kilometerstand – und daraus Kosten, Verbrauch und Statistik für dein E-Auto.",
            points: [
                OnboardingPoint(icon: "eurosign.circle", text: "Sieh auf einen Blick, was dich das Laden wirklich kostet."),
                OnboardingPoint(icon: "gauge.with.dots.needle.33percent", text: "Verbrauch je 100 km, auch wenn du fast nie vollständig lädst."),
                OnboardingPoint(icon: "lock.shield", text: "Ohne Werbung und ohne Tracking – du entscheidest, wo deine Daten liegen."),
            ]
        ),
        OnboardingPage(
            icon: "bolt.fill",
            title: "Ladevorgänge erfassen",
            intro: "Ein neuer Ladevorgang ist in wenigen Sekunden eingetragen – oder kommt ganz von allein.",
            points: [
                OnboardingPoint(icon: "plus.circle", text: "Von Hand im Reiter „Ladevorgänge“: der zuletzt bezahlte Preis des Anbieters wird vorgeschlagen."),
                OnboardingPoint(icon: "mappin.and.ellipse", text: "Gespeicherte Ladeorte werden per GPS erkannt und bringen ihren Anbieter gleich mit."),
                OnboardingPoint(icon: "mic", text: "Per Siri oder Kurzbefehl: „Ladevorgang erfassen“ fragt nur kWh und Preis ab."),
                OnboardingPoint(icon: "antenna.radiowaves.left.and.right", text: "Mit Server automatisch aus Home Assistant, MyŠkoda, VW-Datenportal, BMW CarData oder Renault – du prüfst den Eintrag nur noch."),
            ]
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Kosten und Verbrauch im Blick",
            intro: "Das Dashboard rechnet aus deinen Ladevorgängen alles Wichtige zusammen, für jeden Zeitraum und jedes Fahrzeug.",
            points: [
                OnboardingPoint(icon: "chart.pie", text: "Kosten, Ø Preis je kWh, AC/DC-Anteil und Aufteilung nach Anbieter."),
                OnboardingPoint(icon: "creditcard", text: "Grundgebühren und Abos werden auf die Ladevorgänge umgelegt – so siehst du den echten Preis."),
                OnboardingPoint(icon: "sun.max", text: "Laden zuhause mit PV: der Sonnenanteil wird mitgezählt."),
                OnboardingPoint(icon: "map", text: "Die Karte zeigt alle Ladeorte und wo du geladen hast, das Widget die Kosten des Monats."),
            ]
        ),
        OnboardingPage(
            icon: "car.fill",
            title: "Rund ums Auto",
            intro: "Laden ist nur ein Teil der Kosten. In den Einstellungen pflegst du alles Weitere zu deinen Fahrzeugen.",
            points: [
                OnboardingPoint(icon: "eurosign.circle", text: "Kosten wie Versicherung, Wartung, Wertverlust oder Leasing – ergibt die Gesamtkosten je km."),
                OnboardingPoint(icon: "bell", text: "Erinnerungen an HU, Reifenwechsel oder Versicherung, nach Datum oder Kilometerstand, mit Mitteilung."),
                OnboardingPoint(icon: "fuelpump", text: "Ein Vergleichsfahrzeug zeigt, was dieselben Kilometer mit Benzin oder Diesel gekostet hätten."),
            ]
        ),
        OnboardingPage(
            icon: "wrench.and.screwdriver.fill",
            title: "Tools",
            intro: "Im Reiter „Tools“ liegen kleine Rechner und Berichte rund ums Laden.",
            points: [
                OnboardingPoint(icon: "eurosign.circle", text: "Lohnt sich der Tarif? Effektiver Preis mit Grundgebühr gegen das Laden ohne Tarif."),
                OnboardingPoint(icon: "road.lanes", text: "Reichweitenrechner: wie weit du bei einer bestimmten Außentemperatur kommst."),
                OnboardingPoint(icon: "calendar", text: "Rückblick auf dein Jahr oder deinen Monat in Zahlen, mit Rekorden."),
                OnboardingPoint(icon: "briefcase", text: "Erstattungsbericht für den Dienstwagen: Heimladungen als PDF oder CSV."),
            ]
        ),
    ]
}

struct OnboardingPoint {
    let icon: String
    let text: LocalizedStringKey
}

private struct FeaturePageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: page.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(page.title)
                        .font(.title.bold())
                    Text(page.intro)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(page.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(point.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            // Platz fuer die Seitenpunkte unten
            .padding(.bottom, 48)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Letzte Seite: die drei Wege, die App zu nutzen, nebeneinander erklaert.
private struct ModesPageView: View {
    let context: OnboardingView.Context
    let currentMode: AppMode
    let hosting: AppSettings.ServerHosting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drei Wege, die App zu nutzen")
                        .font(.title.bold())
                    Text("Die App funktioniert ganz ohne Server. Mit einem Server kommen automatische Erfassung, Web-Oberfläche und Abgleich zwischen Geräten dazu.")
                        .foregroundStyle(.secondary)
                }

                ModeExplanationCard(
                    icon: "iphone",
                    title: "Nur lokal",
                    isCurrent: context == .replay && currentMode == .localOnly,
                    points: [
                        "Alle Daten liegen nur auf diesem iPhone – kein Konto, kein Server, sofort startklar.",
                        "Ladevorgänge trägst du von Hand ein, alle Auswertungen und Tools rechnet die App selbst.",
                        "Es gibt keine zweite Kopie außer dem Backup deines Geräts und keinen Abgleich mit anderen Geräten.",
                    ]
                )

                ModeExplanationCard(
                    icon: "network",
                    title: "Eigener Server",
                    isCurrent: context == .replay && currentMode == .server && hosting == .selfHosted,
                    points: [
                        "Du betreibst den Open-Source-Lademonitor-Server selbst, z. B. per Docker, auf Unraid oder als Home-Assistant-Add-on.",
                        "Ladevorgänge kommen automatisch (Home Assistant, MyŠkoda, VW, BMW, Renault), dazu Web-Oberfläche und mehrere Geräte mit demselben Stand.",
                        "Zusätzliche Auswertungen: Verbrauch nach Außentemperatur, Reifen, Akku und Ladeverluste, laufender Ladevorgang.",
                        "Die Daten bleiben bei dir – Updates und Backups liegen aber auch bei dir.",
                    ]
                )

                ModeExplanationCard(
                    icon: "cloud",
                    title: "Lademonitor-Cloud",
                    isCurrent: context == .replay && currentMode == .server && hosting == .cloud,
                    points: [
                        "Derselbe Server mit allen Funktionen, fertig betrieben unter lademonitor.cloud.",
                        "Konto anlegen und loslegen – Betrieb, Updates und Backups übernimmt der Betreiber.",
                        "Deine Daten liegen dafür auf dem Server des Betreibers statt bei dir.",
                    ]
                )

                Text("Wechseln geht jederzeit unter Einstellungen → Server & Verbindung. Beim Wechsel von „Nur lokal“ zu einem Server kannst du alle Daten mitnehmen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ModeExplanationCard: View {
    let icon: String
    let title: LocalizedStringKey
    let isCurrent: Bool
    let points: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Spacer()
                if isCurrent {
                    Text("Aktuell")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(point)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 1.5)
            }
        }
    }
}

#Preview("Erster Start") {
    OnboardingView(context: .firstLaunch) {}
}

#Preview("Aus den Einstellungen") {
    OnboardingView(context: .replay) {}
}
