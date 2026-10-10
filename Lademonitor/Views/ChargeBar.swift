import SwiftUI

/// Schluessel und Vorgabewerte fuer den Ladebalken in der Ladevorgangsliste.
/// Liegen bewusst nur in den UserDefaults dieses Geraets (@AppStorage) und
/// werden NICHT synchronisiert - es ist reine Darstellung.
enum ChargeBarSettings {
    static let lowerMarkerEnabledKey = "chargeBar.lowerMarkerEnabled"
    static let lowerMarkerKey = "chargeBar.lowerMarker"
    static let upperMarkerEnabledKey = "chargeBar.upperMarkerEnabled"
    static let upperMarkerKey = "chargeBar.upperMarker"

    static let defaultLowerMarker = 10
    static let defaultUpperMarker = 100

    /// "Elektrisches" Gruen fuer den geladenen Bereich - einmal definiert,
    /// damit Liste und Vorschau in den Einstellungen gleich aussehen.
    static let chargedColor = Color(red: 0x00 / 255.0, green: 0xD2 / 255.0, blue: 0x6A / 255.0)
}

/// Duenner Balken 0-100 %: grauer Hintergrund, der geladene Bereich
/// socStart..socEnd in Gruen, dazu optional zwei rote Markierungen
/// (z.B. Mindest- und Zielladestand).
struct ChargeBar: View {
    let socStart: Int
    let socEnd: Int
    var lowerMarker: Int?
    var upperMarker: Int?

    private let barHeight: CGFloat = 6
    private let markerHeight: CGFloat = 10
    private let markerWidth: CGFloat = 2

    private static func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }

    var body: some View {
        let start = Self.clamp(socStart)
        let end = Self.clamp(socEnd)
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(height: barHeight)
                Capsule()
                    .fill(ChargeBarSettings.chargedColor)
                    .frame(width: width * CGFloat(max(end - start, 0)) / 100, height: barHeight)
                    .offset(x: width * CGFloat(start) / 100)
                ForEach(markers, id: \.self) { value in
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: markerWidth, height: markerHeight)
                        .offset(x: markerOffset(for: value, width: width))
                }
            }
            .frame(width: width, height: markerHeight, alignment: .leading)
        }
        .frame(height: markerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Geladen von \(start) % auf \(end) %"))
    }

    private var markers: [Int] {
        Array(Set([lowerMarker, upperMarker].compactMap { $0 }.map(Self.clamp))).sorted()
    }

    /// Linke Kante der Markierung. Auf [0, Breite - Markierungsbreite]
    /// begrenzt, damit eine Markierung bei 0 oder 100 % nicht abgeschnitten wird.
    private func markerOffset(for value: Int, width: CGFloat) -> CGFloat {
        let center = width * CGFloat(value) / 100
        return min(max(center - markerWidth / 2, 0), max(width - markerWidth, 0))
    }
}

/// Einstellungen fuer den Ladebalken (nur lokal auf diesem Geraet).
struct ChargeBarSettingsView: View {
    @AppStorage(ChargeBarSettings.lowerMarkerEnabledKey) private var lowerEnabled = true
    @AppStorage(ChargeBarSettings.lowerMarkerKey) private var lowerMarker = ChargeBarSettings.defaultLowerMarker
    @AppStorage(ChargeBarSettings.upperMarkerEnabledKey) private var upperEnabled = true
    @AppStorage(ChargeBarSettings.upperMarkerKey) private var upperMarker = ChargeBarSettings.defaultUpperMarker

    var body: some View {
        Form {
            Section {
                ChargeBar(
                    socStart: 30,
                    socEnd: 70,
                    lowerMarker: lowerEnabled ? lowerMarker : nil,
                    upperMarker: upperEnabled ? upperMarker : nil
                )
                .padding(.vertical, 8)
            } header: {
                Text("Vorschau")
            }

            Section {
                Toggle("Untere Markierung", isOn: $lowerEnabled)
                if lowerEnabled {
                    markerSlider(value: $lowerMarker)
                }
                Toggle("Obere Markierung", isOn: $upperEnabled)
                if upperEnabled {
                    markerSlider(value: $upperMarker)
                }
            } footer: {
                Text("Rote Markierungen im Ladebalken der Ladevorgangsliste, z. B. für deinen Mindest- und Zielladestand. Gilt nur auf diesem Gerät.")
            }
        }
        .navigationTitle("Ladebalken")
    }

    private func markerSlider(value: Binding<Int>) -> some View {
        HStack {
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int(($0 / 5).rounded()) * 5 }
                ),
                in: 0...100,
                step: 5
            )
            Text(verbatim: "\(value.wrappedValue) %")
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
        }
    }
}

#Preview {
    NavigationStack {
        ChargeBarSettingsView()
    }
}
