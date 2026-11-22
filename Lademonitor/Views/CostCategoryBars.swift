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
        case "thg": return Color(hex: 0x16a34a)
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
/// kommt schon sortiert). Gutschriften (THG-Quote) kommen negativ und wachsen
/// von einer Nulllinie aus nach LINKS, Kosten nach rechts - beide im selben
/// Massstab, wie im Web (`renderCostBars`). Ohne Gutschrift liegt die
/// Nulllinie ganz links und alles sieht aus wie bisher.
struct CostCategoryBars: View {
    let categories: [CostCategoryStat]

    private var maxPositive: Double { max(categories.map(\.amount).max() ?? 0, 0) }
    private var maxNegative: Double { max(categories.map { -$0.amount }.max() ?? 0, 0) }
    private var span: Double { max(maxPositive + maxNegative, 0.0001) }
    private var hasCredit: Bool { maxNegative > 0 }

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
                        let zero = geo.size.width * maxNegative / span
                        let width = max(geo.size.width * abs(stat.amount) / span, 4)
                        let credit = stat.amount < 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(CostCategoryStyle.color(stat.category))
                                .frame(width: width)
                                .offset(x: credit ? zero - width : zero)
                            if hasCredit {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.7))
                                    .frame(width: 2)
                                    .offset(x: zero - 1)
                            }
                        }
                    }
                    .frame(height: 16)
                    Text(stat.amount.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(stat.amount < 0 ? Color.green : Color.primary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }
}
