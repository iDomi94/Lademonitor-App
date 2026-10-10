import SwiftUI

/// Farben der Kostenkategorien - dieselben wie im Web-Dashboard
/// (`static/ui.js::renderCostBars`), damit eine Kategorie auf beiden Seiten
/// gleich aussieht.
enum CostCategoryStyle {
    static func color(_ category: String) -> Color {
        switch category {
        case "charging": return Color(hex: 0x5b8def)
        case "depreciation", "leasing": return Color(hex: 0xa78bfa)
        case "insurance": return Color(hex: 0x4fd1a5)
        case "tax": return Color(hex: 0xf2b84b)
        case "maintenance": return Color(hex: 0xf08a5d)
        case "repair": return Color(hex: 0xe5534b)
        case "tires": return Color(hex: 0x8b98a9)
        case "wallbox": return Color(hex: 0x2ea87f)
        case "parking": return Color(hex: 0xd48ac8)
        case "toll": return Color(hex: 0xc9a227)
        case "cleaning": return Color(hex: 0x6cc4e0)
        default: return Color(hex: 0x6b7280)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

/// Ein liegender Balken je Kategorie, groesster Posten zuerst (die Liste
/// kommt schon sortiert), Laenge relativ zum groessten Posten.
struct CostCategoryBars: View {
    let categories: [CostCategoryStat]

    private var maxAmount: Double { max(categories.map(\.amount).max() ?? 0, 0.0001) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(categories) { stat in
                HStack(spacing: 8) {
                    Text(CostCategory.displayName(raw: stat.category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(CostCategoryStyle.color(stat.category))
                            .frame(width: max(geo.size.width * max(stat.amount, 0) / maxAmount, 4))
                    }
                    .frame(height: 16)
                    Text(stat.amount.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }
}
