import SwiftUI

/// Schieberegler des Tarifrechners.
///
/// Eigener Regler statt `Slider`, weil der Rechner zwei Dinge braucht, die
/// `Slider` nicht kann: eine Markierung fuer den Vorschlagswert (damit man nach
/// dem Verschieben sieht, wo man herkam) und eine zweigeteilte Spur (km-Regler:
/// links vom Break-even rot, rechts gruen). VoiceOver bekommt ueber
/// `accessibilityAdjustableAction` dasselbe Verhalten wie bei `Slider`.
struct TariffSlider: View {
    struct Split {
        let at: Double
        let below: Color
        let above: Color
    }

    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var marker: Double?
    var split: Split?
    let accessibilityLabel: Text
    let accessibilityValue: String

    private let thumb: CGFloat = 26
    private let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            ZStack(alignment: .leading) {
                track(usable: usable)
                    .frame(width: usable, height: trackHeight)
                    .offset(x: thumb / 2)
                if let marker {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: 3, height: 16)
                        .offset(x: thumb / 2 + position(marker, usable) - 1.5)
                }
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: position(value, usable))
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    update(fraction: (drag.location.x - thumb / 2) / usable)
                }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(snapped(value) + step, range.upperBound)
            case .decrement: value = max(snapped(value) - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func track(usable: CGFloat) -> some View {
        if let split {
            let at = position(split.at, usable)
            HStack(spacing: 0) {
                Rectangle().fill(split.below).frame(width: at)
                Rectangle().fill(split.above)
            }
            .clipShape(Capsule())
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray4))
                Capsule().fill(Color.accentColor).frame(width: position(value, usable))
            }
        }
    }

    /// Ein von Hand eingetippter Wert darf ausserhalb des Bereichs liegen, der
    /// Regler steht dann am Rand.
    private func position(_ v: Double, _ usable: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(max(v, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / span) * usable
    }

    private func snapped(_ v: Double) -> Double {
        ((v - range.lowerBound) / step).rounded() * step + range.lowerBound
    }

    private func update(fraction: CGFloat) {
        let f = min(max(Double(fraction), 0), 1)
        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        let new = min(max(snapped(raw), range.lowerBound), range.upperBound)
        if new != value { value = new }
    }
}
