import Foundation
import UIKit

/// CSV und PDF des Erstattungsberichts zum Teilen. Die CSV folgt
/// `reimbursement.py::to_csv` im Server: Deutsch mit Semikolon und
/// Dezimalkomma (so oeffnet Excel sie direkt), Englisch mit Komma und Punkt,
/// UTF-8 mit BOM, Kopfzeilen oben, Monatssummen unten.
enum ReimbursementExport {
    /// Sprache der Oberflaeche - danach richten sich Texte UND Trennzeichen,
    /// damit beides zusammenpasst.
    static var isGerman: Bool {
        (Bundle.main.preferredLocalizations.first ?? "de").hasPrefix("de")
    }

    // MARK: - Formatierung

    static func number(_ value: Double?, digits: Int = 2, german: Bool? = nil) -> String {
        guard let value else { return "" }
        let text = String(format: "%.\(digits)f", value)
        return (german ?? isGerman) ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    static func isoDay(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    static func time(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }

    static func fileBaseName(_ report: ReimbursementReport) -> String {
        "lademonitor-erstattung-\(isoDay(report.dateFrom))_\(isoDay(report.dateTo))"
    }

    static func modeText(_ report: ReimbursementReport) -> String {
        report.mode.displayName + (report.includeFees ? " (" + String(localized: "inkl. Grundgebühr") + ")" : "")
    }

    static func sourceText(_ source: ReimbursementKwhSource) -> String {
        source == .estimated ? source.displayName + "*" : source.displayName
    }

    /// Hinweis zu den geschaetzten kWh, `nil` ohne solche Vorgaenge.
    static func estimatedNote(_ report: ReimbursementReport) -> String? {
        guard report.estimatedSessions > 0 else { return nil }
        let kwh = number(report.estimatedKwh, digits: 1)
        return String(localized: "* \(report.estimatedSessions) Ladungen mit geschätzten kWh (\(kwh) kWh) – aus Ladestand × Akkukapazität, kein Messwert.")
    }

    /// Hinweis zu Vorgaengen ohne Betrag, `nil` ohne solche Vorgaenge.
    static func missingNote(_ report: ReimbursementReport) -> String? {
        guard report.missingAmountSessions > 0 else { return nil }
        let count = report.missingAmountSessions
        switch report.mode {
        case .flat:
            return String(localized: "\(count) Ladungen ohne Betrag: für ihr Datum ist noch kein Erstattungssatz eingetragen.")
        case .actual:
            return String(localized: "\(count) Ladungen ohne Betrag: kein Preis am Ladevorgang oder Anbieter.")
        }
    }

    // MARK: - CSV

    static func csv(_ report: ReimbursementReport) -> String {
        let german = isGerman
        let delimiter = german ? ";" : ","
        var lines: [String] = []

        func row(_ fields: [String]) {
            lines.append(fields.map { quoted($0, delimiter: delimiter) }.joined(separator: delimiter))
        }
        func num(_ value: Double?, _ digits: Int = 2) -> String { number(value, digits: digits, german: german) }

        row([String(localized: "Erstattungsbericht Heimladungen")])
        row([String(localized: "Fahrzeug"), report.vehicleName])
        if let plate = report.licensePlate, !plate.isEmpty { row([String(localized: "Kennzeichen"), plate]) }
        if let name = report.employeeName, !name.isEmpty { row([String(localized: "Name"), name]) }
        if let number = report.employeeNumber, !number.isEmpty { row([String(localized: "Personalnummer"), number]) }
        row([String(localized: "Zeitraum"), "\(isoDay(report.dateFrom)) - \(isoDay(report.dateTo))"])
        row([String(localized: "Erstattungsart"), modeText(report)])
        row([])
        row([
            String(localized: "Datum"), String(localized: "Uhrzeit"), "kWh",
            String(localized: "Herkunft kWh"), String(localized: "km-Stand"),
            "€/kWh", String(localized: "Grundgebühr €"), String(localized: "Betrag €"),
        ])
        for r in report.rows {
            row([
                isoDay(r.startTime), time(r.startTime), num(r.energyKwh),
                r.kwhSource.displayName,
                r.odometerKm.map { String($0) } ?? "",
                num(r.ratePerKwh, 4), r.feeShare != 0 ? num(r.feeShare) : "", num(r.amount),
            ])
        }
        row([])
        row([
            String(localized: "Monat"), String(localized: "Ladungen"), "kWh",
            String(localized: "davon geschätzt kWh"), String(localized: "Betrag €"),
        ])
        for m in report.months {
            row([m.month, String(m.sessions), num(m.energyKwh), num(m.estimatedKwh), num(m.amount)])
        }
        row([
            String(localized: "Summe"), String(report.rows.count), num(report.totalKwh),
            num(report.estimatedKwh), num(report.totalAmount),
        ])
        if report.missingAmountSessions > 0 {
            row([])
            row([String(localized: "\(report.missingAmountSessions) Ladungen ohne Betrag (kein Satz bzw. kein Preis)")])
        }
        // BOM, damit Excel die Umlaute als UTF-8 liest; CRLF wie der Server.
        return "\u{FEFF}" + lines.map { $0 + "\r\n" }.joined()
    }

    /// Wie Pythons csv-Modul (QUOTE_MINIMAL): nur in Anfuehrungszeichen, wenn
    /// Trennzeichen, Anfuehrungszeichen oder Zeilenumbruch vorkommen.
    private static func quoted(_ field: String, delimiter: String) -> String {
        guard field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Dateien

    /// Schreibt CSV und PDF in das temporaere Verzeichnis und gibt beide
    /// Adressen zurueck (fuer ShareLink).
    static func writeFiles(_ report: ReimbursementReport) throws -> (csv: URL, pdf: URL) {
        let directory = FileManager.default.temporaryDirectory
        let base = fileBaseName(report)
        let csvURL = directory.appendingPathComponent(base + ".csv")
        let pdfURL = directory.appendingPathComponent(base + ".pdf")
        try csv(report).data(using: .utf8)?.write(to: csvURL, options: .atomic)
        try pdf(report).write(to: pdfURL, options: .atomic)
        return (csvURL, pdfURL)
    }

    // MARK: - PDF

    private static let pageSize = CGSize(width: 595.2, height: 841.8) // A4
    private static let margin: CGFloat = 40

    static func pdf(_ report: ReimbursementReport) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            var writer = PDFWriter(context: context, report: report)
            writer.draw()
        }
    }

    /// Zeichnet den Bericht seitenweise; laeuft eine Tabelle ueber das
    /// Seitenende, kommt ihr Kopf auf der neuen Seite noch einmal.
    private struct PDFWriter {
        let context: UIGraphicsPDFRendererContext
        let report: ReimbursementReport
        var y: CGFloat = 0

        init(context: UIGraphicsPDFRendererContext, report: ReimbursementReport) {
            self.context = context
            self.report = report
        }

        private var width: CGFloat { ReimbursementExport.pageSize.width - 2 * ReimbursementExport.margin }
        private var bottom: CGFloat { ReimbursementExport.pageSize.height - ReimbursementExport.margin }

        private let titleFont = UIFont.boldSystemFont(ofSize: 16)
        private let bodyFont = UIFont.systemFont(ofSize: 10)
        private let boldFont = UIFont.boldSystemFont(ofSize: 10)
        private let smallFont = UIFont.systemFont(ofSize: 8.5)

        mutating func draw() {
            newPage()
            text(String(localized: "Erstattungsbericht Heimladungen"), font: titleFont)
            y += 6
            var header: [(String, String)] = [(String(localized: "Fahrzeug"), report.vehicleName)]
            if let plate = report.licensePlate, !plate.isEmpty { header.append((String(localized: "Kennzeichen"), plate)) }
            if let name = report.employeeName, !name.isEmpty { header.append((String(localized: "Name"), name)) }
            if let number = report.employeeNumber, !number.isEmpty { header.append((String(localized: "Personalnummer"), number)) }
            header.append((String(localized: "Zeitraum"),
                           "\(ReimbursementExport.isoDay(report.dateFrom)) – \(ReimbursementExport.isoDay(report.dateTo))"))
            header.append((String(localized: "Erstattungsart"), ReimbursementExport.modeText(report)))
            for (label, value) in header {
                cells([label, value], widths: [120, width - 120], fonts: [boldFont, bodyFont], alignRight: [false, false])
            }
            y += 12

            // Vorgaenge
            let showFees = report.includeFees
            var titles = [
                String(localized: "Datum"), "kWh", String(localized: "Herkunft kWh"),
                String(localized: "km-Stand"), "€/kWh",
            ]
            var widths: [CGFloat] = showFees ? [95, 55, 80, 65, 60, 70] : [110, 65, 95, 75, 70]
            if showFees { titles.append(String(localized: "Grundgebühr €")) }
            titles.append(String(localized: "Betrag €"))
            let used = widths.reduce(0, +)
            widths.append(max(width - used, 60))
            let alignRight = titles.indices.map { $0 != 0 && $0 != 2 }
            tableHeader(titles, widths: widths, alignRight: alignRight)
            if report.rows.isEmpty {
                text(String(localized: "Keine Heimladungen im Zeitraum."), font: bodyFont)
            }
            for r in report.rows {
                if y + 16 > bottom {
                    newPage()
                    tableHeader(titles, widths: widths, alignRight: alignRight)
                }
                var values = [
                    ReimbursementExport.isoDay(r.startTime) + " " + ReimbursementExport.time(r.startTime),
                    ReimbursementExport.number(r.energyKwh),
                    ReimbursementExport.sourceText(r.kwhSource),
                    r.odometerKm.map { String($0) } ?? "",
                    ReimbursementExport.number(r.ratePerKwh, digits: 4),
                ]
                if showFees { values.append(r.feeShare != 0 ? ReimbursementExport.number(r.feeShare) : "") }
                values.append(r.amount.map { ReimbursementExport.number($0) } ?? "–")
                cells(values, widths: widths, fonts: Array(repeating: bodyFont, count: values.count), alignRight: alignRight)
            }
            y += 12

            // Monatssummen
            let monthTitles = [
                String(localized: "Monat"), String(localized: "Ladungen"), "kWh",
                String(localized: "davon geschätzt kWh"), String(localized: "Betrag €"),
            ]
            let monthWidths: [CGFloat] = [100, 80, 90, 130, width - 400]
            let monthAlign = [false, true, true, true, true]
            if y + 40 > bottom { newPage() }
            cells(monthTitles, widths: monthWidths, fonts: Array(repeating: boldFont, count: 5), alignRight: monthAlign)
            line()
            for m in report.months {
                if y + 16 > bottom { newPage() }
                cells([m.month, String(m.sessions), ReimbursementExport.number(m.energyKwh),
                       ReimbursementExport.number(m.estimatedKwh), ReimbursementExport.number(m.amount)],
                      widths: monthWidths, fonts: Array(repeating: bodyFont, count: 5), alignRight: monthAlign)
            }
            line()
            cells([String(localized: "Summe"), String(report.rows.count), ReimbursementExport.number(report.totalKwh),
                   ReimbursementExport.number(report.estimatedKwh), ReimbursementExport.number(report.totalAmount) + " €"],
                  widths: monthWidths, fonts: Array(repeating: boldFont, count: 5), alignRight: monthAlign)
            y += 12

            for note in [ReimbursementExport.estimatedNote(report), ReimbursementExport.missingNote(report)].compactMap({ $0 }) {
                if y + 30 > bottom { newPage() }
                text(note, font: smallFont)
                y += 4
            }
        }

        private mutating func tableHeader(_ titles: [String], widths: [CGFloat], alignRight: [Bool]) {
            cells(titles, widths: widths, fonts: Array(repeating: boldFont, count: titles.count), alignRight: alignRight)
            line()
        }

        private mutating func newPage() {
            context.beginPage()
            y = ReimbursementExport.margin
        }

        private mutating func text(_ string: String, font: UIFont) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let rect = CGRect(x: ReimbursementExport.margin, y: y, width: width, height: .greatestFiniteMagnitude)
            let size = (string as NSString).boundingRect(
                with: rect.size, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
            ).size
            (string as NSString).draw(
                with: CGRect(x: rect.minX, y: y, width: width, height: ceil(size.height)),
                options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
            )
            y += ceil(size.height) + 2
        }

        private mutating func cells(_ values: [String], widths: [CGFloat], fonts: [UIFont], alignRight: [Bool]) {
            var x = ReimbursementExport.margin
            let height: CGFloat = 14
            for (index, value) in values.enumerated() {
                let cellWidth = index < widths.count ? widths[index] : 60
                let style = NSMutableParagraphStyle()
                style.alignment = (index < alignRight.count && alignRight[index]) ? .right : .left
                style.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: index < fonts.count ? fonts[index] : bodyFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: style,
                ]
                (value as NSString).draw(in: CGRect(x: x + 2, y: y, width: cellWidth - 4, height: height), withAttributes: attributes)
                x += cellWidth
            }
            y += height + 1
        }

        private mutating func line() {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: ReimbursementExport.margin, y: y))
            path.addLine(to: CGPoint(x: ReimbursementExport.margin + width, y: y))
            path.lineWidth = 0.5
            UIColor.gray.setStroke()
            path.stroke()
            y += 3
        }
    }
}
