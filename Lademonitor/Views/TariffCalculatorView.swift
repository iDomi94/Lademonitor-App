import SwiftUI

/// "Lohnt sich der Tarif?" - rechnet voraus, was eine kWh mit Grundgebuehr
/// effektiv kostet und ob das guenstiger ist als ohne Tarif.
///
/// In erster Linie eine Spielwiese: der Rechner braucht keinen bekannten
/// Anbieter. "Werte uebernehmen von" fuellt Preis, Grundgebuehr und Anteil nur
/// vor. km, Verbrauch und der automatische Vergleichspreis kommen aus den
/// eigenen Ladevorgaengen (TariffCalculator). Gerechnet wird bei jeder
/// Reglerbewegung neu, das Ergebnis steht oben und bleibt beim Scrollen
/// sichtbar.
struct TariffCalculatorView: View {
    /// Vorausgewaehlter Anbieter (Sprung aus "Anbieter bearbeiten"), sonst
    /// startet der Rechner als "Neuer Tarif".
    var initialProviderId: String?

    private enum ComparisonMode: String {
        case automatic, manual
    }

    private enum Field: Identifiable {
        case price, fee, share, km
        var id: Self { self }
    }

    /// Einmal je Anbieter-/Lade-Art-Wechsel berechnet, nicht bei jeder
    /// Reglerbewegung - die laufen ueber alle Ladevorgaenge.
    private struct Suggestions {
        var km: Double?
        var consumption: Double?
        var sharePct: Double?
        /// Der Anteil stammt vom gewaehlten Anbieter selbst (sonst: Anteil
        /// aller oeffentlichen Anbieter).
        var shareFromProvider = false
        var price: Double?
        var fee: Double?
        var comparison: TariffCalculator.PaidPrice?
    }

    private static let fallbackConsumption = 18.0
    private static let priceRange = 0.20...1.00
    private static let feeRange = 0.0...30.0
    private static let shareRange = 0.0...100.0
    private static let kmRange = 0.0...5000.0

    @State private var basis: TariffBasis?
    @State private var loadError: String?
    @State private var didLoad = false
    @State private var suggestions = Suggestions()

    @State private var providerId: String?
    @State private var chargingType: ChargingType = .dc
    // Beispielwerte fuer einen neuen Tarif, bis Vorschlaege oder ein Anbieter
    // sie ersetzen.
    @State private var price = 0.49
    @State private var fee = 10.0
    @State private var sharePct = 30.0
    @State private var km = 1000.0
    @State private var consumptionText = ""

    @AppStorage("tariffCalculator.comparisonMode") private var comparisonModeRaw = ComparisonMode.automatic.rawValue
    @AppStorage("tariffCalculator.manualComparisonPrice") private var manualComparisonText = ""

    @State private var editingField: Field?
    @State private var editText = ""

    var body: some View {
        Form {
            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            tariffSection
            profileSection
            comparisonSection
        }
        .safeAreaInset(edge: .top, spacing: 0) { resultCard }
        .navigationTitle("Lohnt sich der Tarif?")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Beim ersten Mal alle Regler aus den Vorschlaegen setzen, danach
            // (Rueckkehr aus "Oeffentliche Anbieter") nur neu laden.
            let first = !didLoad
            didLoad = true
            await load(resetInputs: first)
        }
        .onChange(of: providerId) { applyProviderValues() }
        .onChange(of: chargingType) {
            suggestions = makeSuggestions()
            if providerId != nil, let suggested = suggestions.price { price = suggested }
        }
        .alert(Text(editTitle), isPresented: editingBinding) {
            TextField("Wert", text: $editText)
                .keyboardType(editingField == .km || editingField == .share ? .numberPad : .decimalPad)
            Button("Übernehmen") { applyEdit() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: - Abschnitte

    private var selectedProvider: Provider? {
        basis?.providers.first { $0.id == providerId }
    }

    private var tariffSection: some View {
        Section {
            Picker("Werte übernehmen von", selection: $providerId) {
                Text("Neuer Tarif").tag(String?.none)
                ForEach(basis?.providers ?? []) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }
            Picker("Lade-Art", selection: $chargingType) {
                ForEach(ChargingType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            SliderRow(
                title: "Tarifpreis",
                valueText: Self.perKwh(price),
                value: $price,
                range: Self.priceRange,
                step: 0.01,
                marker: suggestions.price,
                caption: priceCaption,
                onReset: resetAction(value: price, suggestion: suggestions.price) { price = $0 },
                onEdit: { startEdit(.price) }
            )
            SliderRow(
                title: "Grundgebühr pro Monat",
                valueText: Self.euro(fee),
                value: $fee,
                range: Self.feeRange,
                step: 0.5,
                marker: suggestions.fee,
                caption: feeCaption,
                onReset: resetAction(value: fee, suggestion: suggestions.fee) { fee = $0 },
                onEdit: { startEdit(.fee) }
            )
        } header: {
            Text("Tarif")
        } footer: {
            Text("Spielwiese für jeden Tarif, auch einen, den du noch nicht hast. „Werte übernehmen von“ füllt Preis, Grundgebühr und Anteil aus einem vorhandenen Anbieter vor. Ein Tipp auf einen Wert erlaubt die genaue Eingabe.")
        }
    }

    private var profileSection: some View {
        Section {
            SliderRow(
                title: "km im Monat",
                valueText: Self.kmText(km),
                value: $km,
                range: Self.kmRange,
                step: 50,
                marker: suggestions.km,
                split: kmSplit,
                caption: kmCaption,
                onReset: resetAction(value: km, suggestion: suggestions.km) { km = $0 },
                onEdit: { startEdit(.km) }
            )
            SliderRow(
                title: "Anteil beim Tarif",
                valueText: Self.percent(sharePct),
                value: $sharePct,
                range: Self.shareRange,
                step: 5,
                marker: suggestions.sharePct,
                caption: shareCaption,
                onReset: resetAction(value: sharePct, suggestion: suggestions.sharePct) { sharePct = $0 },
                onEdit: { startEdit(.share) }
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Verbrauch (kWh/100 km)")
                    Spacer()
                    TextField(Self.number(suggestions.consumption ?? Self.fallbackConsumption, digits: 1), text: $consumptionText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                Text(suggestions.consumption != nil
                     ? String(localized: "Ø der letzten 12 Monate aus deinen Ladevorgängen, inklusive Ladeverlusten")
                     : String(localized: "Kein eigener Wert vorhanden, Richtwert"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Fahrprofil")
        } footer: {
            Text("Der Anteil ist der Teil deiner geladenen Energie, der beim Tarif geladen würde. Was du zu Hause lädst, zählt nicht dazu.")
        }
    }

    private var comparisonMode: ComparisonMode {
        ComparisonMode(rawValue: comparisonModeRaw) ?? .automatic
    }

    private var comparisonSection: some View {
        Section {
            Picker("Preis ohne Tarif", selection: $comparisonModeRaw) {
                Text("Automatik").tag(ComparisonMode.automatic.rawValue)
                Text("Selbst eintragen").tag(ComparisonMode.manual.rawValue)
            }
            .pickerStyle(.segmented)

            if comparisonMode == .automatic {
                if let comparison = suggestions.comparison {
                    LabeledContent("Ø bezahlt (\(chargingType.rawValue))", value: Self.perKwh(comparison.pricePerKwh))
                    Text("aus \(comparison.sessionCount) Ladevorgängen im letzten Jahr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Keine passenden Ladevorgänge im letzten Jahr. Trag den Preis selbst ein oder prüfe die Auswahl der öffentlichen Anbieter.")
                        .foregroundStyle(.secondary)
                }
                NavigationLink("Öffentliche Anbieter auswählen") {
                    PublicProvidersView()
                }
            } else {
                HStack {
                    Text("Preis je kWh (€)")
                    Spacer()
                    TextField("z. B. 0,69", text: $manualComparisonText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
            }
        } header: {
            Text("Preis ohne Tarif")
        } footer: {
            if comparisonMode == .automatic {
                Text("Automatik: Durchschnitt dessen, was du in den letzten 12 Monaten an öffentlichen Ladesäulen pro kWh bezahlt hast, inklusive Grundgebührenanteilen, gewichtet nach kWh und nur für die gewählte Lade-Art. Der Anbieter, dessen Werte übernommen wurden, zählt nicht mit. Welche Anbieter als öffentlich zählen, stellst du unter „Öffentliche Anbieter“ ein.")
            } else {
                Text("Der Preis, den du ohne diesen Tarif pro kWh zahlen würdest, z. B. der Ad-hoc-Preis an der Säule.")
            }
        }
    }

    // MARK: - Ergebnis

    private var consumption: Double {
        Self.parse(consumptionText) ?? suggestions.consumption ?? Self.fallbackConsumption
    }

    private var comparisonPrice: Double? {
        switch comparisonMode {
        case .automatic: return suggestions.comparison?.pricePerKwh
        case .manual: return Self.parse(manualComparisonText)
        }
    }

    private var result: TariffCalculator.Result {
        TariffCalculator.compute(TariffCalculator.Input(
            tariffPricePerKwh: price,
            monthlyFee: fee,
            sharePct: sharePct,
            kmPerMonth: km,
            consumptionKwhPer100km: consumption,
            comparisonPricePerKwh: comparisonPrice
        ))
    }

    /// km-Regler: links vom Break-even rot, rechts gruen. Wird der Tarif bei
    /// keiner Fahrleistung guenstiger, ist die ganze Spur rot.
    private var kmSplit: TariffSlider.Split? {
        let r = result
        let red = Color.red.opacity(0.75)
        let green = Color.green.opacity(0.75)
        if r.neverPaysOff { return TariffSlider.Split(at: Self.kmRange.upperBound, below: red, above: green) }
        guard let breakEven = r.breakEvenKm else { return nil }
        return TariffSlider.Split(at: breakEven, below: red, above: green)
    }

    private func tint(_ verdict: TariffCalculator.Verdict) -> Color {
        switch verdict {
        case .cheaper: return .green
        case .moreExpensive: return .red
        case .equal, .unknown: return .secondary
        }
    }

    private var resultCard: some View {
        let r = result
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Effektiver Preis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(r.effectivePricePerKwh.map { Self.perKwh($0) } ?? "–")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                verdictLabel(r.verdict)
            }
            Text(detailLine(r))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let savings = savingsLine(r) {
                Text(savings).font(.footnote)
            }
            if let breakEven = breakEvenLine(r) {
                Text(breakEven).font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint(r.verdict).opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint(r.verdict).opacity(0.45), lineWidth: 1))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: r.verdict)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func verdictLabel(_ verdict: TariffCalculator.Verdict) -> some View {
        // Symbol UND Wort, damit das Ergebnis auch ohne Farbsehen eindeutig ist.
        switch verdict {
        case .cheaper:
            Label("Günstiger", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
        case .moreExpensive:
            Label("Teurer", systemImage: "xmark.circle.fill")
                .font(.headline).foregroundStyle(.red)
        case .equal:
            Label("Gleich teuer", systemImage: "equal.circle.fill")
                .font(.headline).foregroundStyle(.secondary)
        case .unknown:
            EmptyView()
        }
    }

    private func detailLine(_ r: TariffCalculator.Result) -> String {
        guard r.kwhPerMonth > 0, let feePerKwh = r.feePerKwh else {
            return String(localized: "Ohne Ladungen beim Tarif bleibt nur die Grundgebühr von \(Self.euro(fee)) im Monat.")
        }
        return String(localized: "\(Self.number(r.kwhPerMonth, digits: 0)) kWh im Monat beim Tarif: \(Self.perKwh(price)) plus \(Self.perKwh(feePerKwh)) Grundgebühr")
    }

    private func savingsLine(_ r: TariffCalculator.Result) -> String? {
        guard let savings = r.savingsPerMonth, let without = r.costWithoutTariff else {
            return String(localized: "Ohne Vergleichspreis lässt sich nicht sagen, ob sich der Tarif lohnt.")
        }
        let with = Self.euro(r.costWithTariff)
        switch r.verdict {
        case .cheaper:
            return String(localized: "Spart \(Self.euro(savings)) im Monat (\(with) statt \(Self.euro(without)))")
        case .moreExpensive:
            return String(localized: "Kostet \(Self.euro(-savings)) mehr im Monat (\(with) statt \(Self.euro(without)))")
        case .equal:
            return String(localized: "Mit und ohne Tarif gleich teuer (\(with) im Monat)")
        case .unknown:
            return nil
        }
    }

    private func breakEvenLine(_ r: TariffCalculator.Result) -> String? {
        if r.neverPaysOff {
            return String(localized: "Lohnt sich bei keiner Fahrleistung: der Tarifpreis liegt nicht unter dem Preis ohne Tarif.")
        }
        guard let kwh = r.breakEvenKwh else { return nil }
        if kwh <= 0 {
            return String(localized: "Ohne Grundgebühr lohnt sich der Tarif ab der ersten kWh.")
        }
        if let breakEvenKm = r.breakEvenKm {
            return String(localized: "Lohnt sich ab ca. \(Self.kmText((breakEvenKm / 10).rounded() * 10)) im Monat (\(Self.number(kwh, digits: 0)) kWh beim Tarif)")
        }
        return String(localized: "Lohnt sich ab ca. \(Self.number(kwh, digits: 0)) kWh im Monat beim Tarif")
    }

    // MARK: - Beschriftungen

    private var kmCaption: String {
        guard let suggested = suggestions.km else {
            return String(localized: "Noch kein Verlauf des Kilometerstands vorhanden")
        }
        return String(localized: "Vorschlag \(Self.kmText(suggested)): Ø der letzten 3 Monate aus dem Kilometerstand")
    }

    private var shareCaption: String {
        guard let suggested = suggestions.sharePct else {
            return String(localized: "Noch keine Ladevorgänge, Anteil bitte schätzen")
        }
        if suggestions.shareFromProvider, let name = selectedProvider?.name {
            return String(localized: "Vorschlag \(Self.percent(suggested)): bisheriger Anteil von \(name), letzte 3 Monate")
        }
        return String(localized: "Vorschlag \(Self.percent(suggested)): bisheriger Anteil öffentlicher Anbieter, letzte 3 Monate")
    }

    private var priceCaption: String? {
        guard let provider = selectedProvider else { return nil }
        guard let suggested = suggestions.price else {
            return String(localized: "Für \(provider.name) ist kein \(chargingType.rawValue)-Preis hinterlegt")
        }
        return String(localized: "Vorschlag \(Self.perKwh(suggested)): zuletzt bezahlter \(chargingType.rawValue)-Preis bei \(provider.name)")
    }

    private var feeCaption: String? {
        guard let provider = selectedProvider else { return nil }
        guard let suggested = suggestions.fee else {
            return String(localized: "Für \(provider.name) ist keine aktive Grundgebühr hinterlegt")
        }
        return String(localized: "Vorschlag \(Self.euro(suggested)): aktive Grundgebühr von \(provider.name), auf einen Monat gerechnet")
    }

    // MARK: - Laden und Vorschlaege

    private func load(resetInputs: Bool) async {
        guard AppSettings.shared.isReadyForDataAccess else {
            loadError = String(localized: "Bitte zuerst die Server-Adresse in den Einstellungen eintragen.")
            return
        }
        do {
            let loaded = try await AppRepository.shared.tariffBasis()
            basis = loaded
            loadError = nil
            if resetInputs, let initialProviderId, loaded.providers.contains(where: { $0.id == initialProviderId }) {
                providerId = initialProviderId
            }
            suggestions = makeSuggestions()
            if resetInputs {
                if let suggested = suggestions.km { km = suggested }
                applyProviderValues()
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func makeSuggestions() -> Suggestions {
        guard let basis else { return Suggestions() }
        let sessions = basis.sessions
        var s = Suggestions()
        s.km = TariffCalculator.suggestedKmPerMonth(sessions: sessions)
        s.consumption = TariffCalculator.suggestedConsumption(sessions: sessions)

        let publicShare = TariffCalculator.suggestedSharePct(sessions: sessions) { session in
            guard let id = session.providerId else { return false }
            return !basis.excludedProviderIds.contains(id)
        }
        if let providerId {
            // Ein Anbieter ohne eigene Ladungen (z. B. gerade erst angelegt, um
            // ein Abo durchzurechnen) bekaeme sonst 0 % - dann ist der Anteil
            // des oeffentlichen Ladens die bessere Schaetzung.
            let own = TariffCalculator.suggestedSharePct(sessions: sessions) { $0.providerId == providerId }
            if let own, own > 0 {
                s.sharePct = own
                s.shareFromProvider = true
            } else {
                s.sharePct = publicShare
            }
            let provider = basis.providers.first { $0.id == providerId }
            s.price = chargingType == .dc ? provider?.lastPriceDcPerKwh : provider?.lastPriceAcPerKwh
            s.fee = TariffCalculator.suggestedMonthlyFee(providerId: providerId, fees: basis.fees)
        } else {
            s.sharePct = publicShare
        }
        s.sharePct = s.sharePct.map { $0.rounded() }
        s.comparison = TariffCalculator.automaticComparisonPrice(
            sessions: sessions,
            excludedProviderIds: basis.excludedProviderIds,
            selectedProviderId: providerId,
            chargingType: chargingType
        )
        return s
    }

    /// Anbieterwechsel: Anteil, Preis und Grundgebuehr neu vorbelegen. Beim
    /// Wechsel auf "Neuer Tarif" bleiben Preis und Grundgebuehr stehen - man
    /// spielt dann meist genau mit diesen beiden weiter.
    private func applyProviderValues() {
        suggestions = makeSuggestions()
        if let suggested = suggestions.sharePct { sharePct = suggested }
        guard providerId != nil else { return }
        if let suggested = suggestions.price { price = suggested }
        fee = suggestions.fee ?? 0
    }

    private func resetAction(value: Double, suggestion: Double?, apply: @escaping (Double) -> Void) -> (() -> Void)? {
        guard let suggestion, abs(value - suggestion) > 0.0001 else { return nil }
        return { apply(suggestion) }
    }

    // MARK: - Genaue Eingabe

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingField != nil }, set: { if !$0 { editingField = nil } })
    }

    private var editTitle: String {
        switch editingField {
        case .price: return String(localized: "Tarifpreis (€/kWh)")
        case .fee: return String(localized: "Grundgebühr pro Monat (€)")
        case .share: return String(localized: "Anteil beim Tarif (%)")
        case .km: return String(localized: "km im Monat")
        case nil: return ""
        }
    }

    private func startEdit(_ field: Field) {
        switch field {
        case .price: editText = Self.number(price, digits: 2)
        case .fee: editText = Self.number(fee, digits: 2)
        case .share: editText = Self.number(sharePct, digits: 0)
        case .km: editText = String(Int(km.rounded()))
        }
        editingField = field
    }

    private func applyEdit() {
        guard let field = editingField else { return }
        editingField = nil
        switch field {
        case .km:
            if let v = Double(editText.filter(\.isNumber)) { km = v }
        case .share:
            if let v = Self.parse(editText) { sharePct = min(max(v, 0), 100) }
        case .price:
            if let v = Self.parse(editText), v >= 0 { price = v }
        case .fee:
            if let v = Self.parse(editText), v >= 0 { fee = v }
        }
    }

    // MARK: - Formatierung

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }

    static func number(_ v: Double, digits: Int) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    static func euro(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2))) + " €"
    }

    static func perKwh(_ v: Double) -> String {
        euro(v) + "/kWh"
    }

    static func kmText(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0))) + " km"
    }

    static func percent(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0))) + " %"
    }
}

/// Eine Zeile mit Titel, antippbarem Wert, Regler und grauer Herkunftszeile.
private struct SliderRow: View {
    let title: LocalizedStringKey
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var marker: Double?
    var split: TariffSlider.Split?
    var caption: String?
    var onReset: (() -> Void)?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if let onReset {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Auf Vorschlag zurücksetzen")
                }
                Button(action: onEdit) {
                    Text(valueText)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Genauen Wert eingeben")
            }
            TariffSlider(
                value: $value,
                range: range,
                step: step,
                marker: marker,
                split: split,
                accessibilityLabel: Text(title),
                accessibilityValue: valueText
            )
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { TariffCalculatorView() }
}
