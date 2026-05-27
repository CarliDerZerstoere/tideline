import Foundation
import UIKit
import CryptoKit

/// Pure renderer that turns a `DoctorPDFData` snapshot into a PDF `Data`
/// blob + an `ExportReceipt` (task #46).
///
/// Pure — no SwiftData, no SwiftUI, no actor hops. Fully unit-testable.
/// Uses `UIGraphicsPDFRenderer` (iOS) and `CryptoKit.SHA256` (Apple
/// framework, no dependency).
///
/// **Layout:** A4 portrait, 595 × 842 pt. Single column, generous margins.
/// Multi-page handled by calling `ctx.beginPage()` when Y exceeds the
/// usable height.
public enum DoctorPDFRenderer {

    // MARK: - Public API

    /// Default locale is `de_DE` BY DESIGN (task #130): the Doctor PDF
    /// is a clinical document handed to a DACH practitioner and must
    /// render in German regardless of the device user's locale. Tests
    /// or future EN-locale export flows can override.
    public static func render(
        data: DoctorPDFData,
        locale: Locale = Locale(identifier: "de_DE")
    ) -> (pdf: Data, receipt: ExportReceipt) {
        let canonical = canonicalContent(data: data)
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let receipt = ExportReceipt(
            sha256Hex: hex,
            generatedAt: data.generatedAt,
            appVersion: data.appVersion
        )

        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        // `documentInfo` only round-trips through the standard PDF info
        // keys (`PDFDocument.documentAttributes`). Custom keys get
        // dropped. Stash the full hash in `Keywords` so the metadata is
        // recoverable + the standard tooling can read it.
        format.documentInfo = [
            kCGPDFContextCreator as String: "Tideline \(data.appVersion)",
            kCGPDFContextTitle as String: "Zyklus-Bericht",
            kCGPDFContextKeywords as String: "TidelineExportReceiptSHA256:\(hex)"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        let pdf = renderer.pdfData { ctx in
            var painter = Painter(ctx: ctx, locale: locale, receipt: receipt)
            painter.beginPage()
            painter.drawHeader(data)
            painter.drawSummary(data)
            painter.drawCycleTable(data)
            if !data.events.isEmpty {
                painter.drawEventList(data)
            }
            if let symptoms = data.symptomEntries, !symptoms.isEmpty {
                painter.drawSymptomJournal(symptoms)
            }
            painter.drawFooterOnCurrentPage()
        }
        return (pdf, receipt)
    }

    /// Canonical string that the receipt's SHA-256 hashes over. Stable
    /// across runs for identical input: same data → same hash. Excludes
    /// the timestamp and the receipt itself — only content rows count.
    static func canonicalContent(data: DoctorPDFData) -> String {
        var lines: [String] = []
        lines.append("HEADER|\(data.patientHeader)")
        lines.append("SUMMARY|\(data.observedCycleCount)|\(data.averageCycleLengthDays?.description ?? "nil")|\(data.predictorModeLabel)|\(data.irregularityDeclared)")
        if let p = data.upcomingPrediction {
            lines.append("PREDICTION|\(p.estimatedDate.timeIntervalSince1970)|\(p.intervalLower.timeIntervalSince1970)|\(p.intervalUpper.timeIntervalSince1970)")
        }
        for c in data.cycles {
            let endStr = c.endDate?.timeIntervalSince1970.description ?? "open"
            lines.append("CYCLE|\(c.startDate.timeIntervalSince1970)|\(endStr)|\(c.lengthDays ?? -1)|\(c.bleedingDayCount)")
        }
        for e in data.events {
            lines.append("EVENT|\(e.date.timeIntervalSince1970)|\(e.germanLabel)|\(e.note)")
        }
        if let syms = data.symptomEntries {
            for s in syms {
                let flow = s.flowLabel ?? ""
                let symsJoined = s.symptoms.sorted().joined(separator: ",")
                lines.append("SYMPTOM|\(s.date.timeIntervalSince1970)|\(flow)|\(symsJoined)|\(s.mood?.description ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Page geometry

    static let pageWidth: CGFloat = 595
    static let pageHeight: CGFloat = 842
    static let sideMargin: CGFloat = 48
    static let topMargin: CGFloat = 56
    static let bottomMargin: CGFloat = 56
    static var usableWidth: CGFloat { pageWidth - 2 * sideMargin }
    static var contentBottom: CGFloat { pageHeight - bottomMargin }
}

// MARK: - Painter

private struct Painter {
    let ctx: UIGraphicsPDFRendererContext
    let locale: Locale
    let receipt: ExportReceipt

    var y: CGFloat = DoctorPDFRenderer.topMargin
    var pageCount: Int = 0
    /// When a section is being drawn, this holds its German label so the
    /// header can be repainted at the top of every new page that the
    /// section spills onto. Cleared between sections.
    var currentSectionHeader: String?

    private let titleFont: UIFont
    private let sectionFont: UIFont
    private let bodyFont: UIFont
    private let smallFont: UIFont
    private let footerFont: UIFont
    private let tableHeaderFont: UIFont

    init(ctx: UIGraphicsPDFRendererContext, locale: Locale, receipt: ExportReceipt) {
        self.ctx = ctx
        self.locale = locale
        self.receipt = receipt
        let serifDescriptor = UIFont.systemFont(ofSize: 11).fontDescriptor
            .withDesign(.serif) ?? UIFont.systemFont(ofSize: 11).fontDescriptor
        self.bodyFont = UIFont(descriptor: serifDescriptor, size: 11)
        self.smallFont = UIFont(descriptor: serifDescriptor, size: 9.5)
        self.footerFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
        self.tableHeaderFont = UIFont(descriptor: serifDescriptor.withSymbolicTraits(.traitBold) ?? serifDescriptor, size: 10)
        self.titleFont = UIFont(descriptor: serifDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) ?? serifDescriptor, size: 22)
        self.sectionFont = UIFont(descriptor: serifDescriptor.withSymbolicTraits(.traitBold) ?? serifDescriptor, size: 14)
    }

    mutating func beginPage() {
        ctx.beginPage()
        pageCount += 1
        y = DoctorPDFRenderer.topMargin
        if let header = currentSectionHeader {
            // Repaint the section header on the new page so a multi-page
            // table doesn't leave page 2+ unlabelled. (Reviewer rec.)
            drawStringRaw(header + " (Fortsetzung)", font: sectionFont)
            drawHorizontalRule()
        }
    }

    /// Internal: draw without auto-pagination (used inside `beginPage` to
    /// avoid recursion). External callers should use `drawString`.
    private mutating func drawStringRaw(_ s: String, font: UIFont) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black
        ]
        let attributed = NSAttributedString(string: s, attributes: attrs)
        let bounds = attributed.boundingRect(
            with: CGSize(width: DoctorPDFRenderer.usableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        attributed.draw(in: CGRect(
            x: DoctorPDFRenderer.sideMargin, y: y,
            width: DoctorPDFRenderer.usableWidth, height: bounds.height
        ))
        y += bounds.height
    }

    private mutating func ensureSpace(_ needed: CGFloat) {
        if y + needed > DoctorPDFRenderer.contentBottom {
            // Footer is drawn at the end on every page via
            // `drawFooterOnEveryPage`. Just open a new page here.
            beginPage()
        }
    }

    // MARK: - Drawing primitives

    private mutating func drawString(_ s: String, font: UIFont, color: UIColor = .black, indent: CGFloat = 0) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]
        let attributed = NSAttributedString(string: s, attributes: attrs)
        let width = DoctorPDFRenderer.usableWidth - indent
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        ensureSpace(bounds.height + 2)
        attributed.draw(in: CGRect(
            x: DoctorPDFRenderer.sideMargin + indent,
            y: y,
            width: width,
            height: bounds.height
        ))
        y += bounds.height
    }

    private mutating func drawHorizontalRule(opacity: CGFloat = 0.25) {
        ensureSpace(8)
        let cg = ctx.cgContext
        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(opacity).cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: DoctorPDFRenderer.sideMargin, y: y + 4))
        cg.addLine(to: CGPoint(x: DoctorPDFRenderer.pageWidth - DoctorPDFRenderer.sideMargin, y: y + 4))
        cg.strokePath()
        cg.restoreGState()
        y += 10
    }

    private mutating func vSpace(_ amount: CGFloat) {
        ensureSpace(amount)
        y += amount
    }

    // MARK: - Sections

    mutating func drawHeader(_ data: DoctorPDFData) {
        drawString("Tideline · Zyklus-Bericht", font: titleFont)
        let df = DateFormatter()
        df.locale = locale
        df.dateStyle = .long
        df.timeStyle = .short
        drawString("Erstellt am \(df.string(from: data.generatedAt))", font: smallFont, color: .darkGray)
        // MDR-posture banner: explicit framing so a doctor receiving the
        // PDF cannot read it as a clinical claim. (Reviewer rec.)
        drawString(
            "Persönliche Aufzeichnung zur Besprechung mit medizinischem Fachpersonal. Keine Diagnose.",
            font: smallFont, color: .darkGray
        )
        if !data.patientHeader.isEmpty {
            vSpace(2)
            drawString(data.patientHeader, font: bodyFont)
        }
        vSpace(8)
    }

    mutating func drawSummary(_ data: DoctorPDFData) {
        currentSectionHeader = "Übersicht"
        drawString("Übersicht", font: sectionFont)
        drawHorizontalRule()

        drawSummaryRow(label: "Erfasste Zyklen:", value: "\(data.observedCycleCount)")
        if let mu = data.averageCycleLengthDays {
            drawSummaryRow(
                label: "Durchschnittliche Länge:",
                value: String(format: "%.1f Tage", mu).replacingOccurrences(of: ".", with: ",")
            )
        }
        drawSummaryRow(label: "Vorhersage-Modus:", value: data.predictorModeLabel)
        drawSummaryRow(
            label: "Unregelmäßigkeit erklärt:",
            value: data.irregularityDeclared ? "Ja" : "Nein"
        )
        if let p = data.upcomingPrediction {
            let df = DateFormatter()
            df.locale = locale
            df.setLocalizedDateFormatFromTemplate("dMMM")
            let estStr = df.string(from: p.estimatedDate)
            let loStr = df.string(from: p.intervalLower)
            let hiStr = df.string(from: p.intervalUpper)
            drawSummaryRow(
                label: "Erwartete nächste Periode:",
                value: "\(estStr) (90% KI: \(loStr) – \(hiStr))"
            )
        }
        vSpace(10)
    }

    private mutating func drawSummaryRow(label: String, value: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: UIColor.black
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: UIColor.darkGray
        ]
        ensureSpace(bodyFont.lineHeight + 2)
        NSAttributedString(string: label, attributes: labelAttrs)
            .draw(at: CGPoint(x: DoctorPDFRenderer.sideMargin, y: y))
        NSAttributedString(string: value, attributes: attrs)
            .draw(at: CGPoint(x: DoctorPDFRenderer.sideMargin + 180, y: y))
        y += bodyFont.lineHeight + 2
    }

    mutating func drawCycleTable(_ data: DoctorPDFData) {
        currentSectionHeader = "Zyklusverlauf"
        drawString("Zyklusverlauf", font: sectionFont)
        drawHorizontalRule()

        if data.cycles.isEmpty {
            drawString("Keine Zyklen erfasst.", font: bodyFont, color: .darkGray)
            vSpace(10)
            return
        }

        // Table header.
        drawTableRow(
            ["Start", "Ende", "Länge", "Bluttage"],
            font: tableHeaderFont,
            columnWidths: [140, 140, 70, 70]
        )
        drawHorizontalRule(opacity: 0.4)

        let df = DateFormatter()
        df.locale = locale
        df.setLocalizedDateFormatFromTemplate("dMMMyyyy")

        for cycle in data.cycles {
            let startStr = df.string(from: cycle.startDate)
            let endStr = cycle.endDate.map { df.string(from: $0) } ?? "—"
            let lenStr = cycle.lengthDays.map { "\($0) T" } ?? "—"
            let bleedStr = "\(cycle.bleedingDayCount)"
            drawTableRow(
                [startStr, endStr, lenStr, bleedStr],
                font: bodyFont,
                columnWidths: [140, 140, 70, 70]
            )
        }
        vSpace(10)
    }

    private mutating func drawTableRow(_ cells: [String], font: UIFont, columnWidths: [CGFloat]) {
        ensureSpace(font.lineHeight + 4)
        var x = DoctorPDFRenderer.sideMargin
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        for (i, cell) in cells.enumerated() where i < columnWidths.count {
            NSAttributedString(string: cell, attributes: attrs)
                .draw(at: CGPoint(x: x, y: y))
            x += columnWidths[i]
        }
        y += font.lineHeight + 4
    }

    mutating func drawEventList(_ data: DoctorPDFData) {
        currentSectionHeader = "Ereignisse"
        drawString("Ereignisse", font: sectionFont)
        drawHorizontalRule()

        let df = DateFormatter()
        df.locale = locale
        df.setLocalizedDateFormatFromTemplate("dMMMyyyy")

        for ev in data.events {
            let dateStr = df.string(from: ev.date)
            let line = ev.note.isEmpty
                ? "\(dateStr)   \(ev.germanLabel)"
                : "\(dateStr)   \(ev.germanLabel) — \(ev.note)"
            drawString(line, font: bodyFont)
        }
        vSpace(10)
    }

    mutating func drawSymptomJournal(_ entries: [DoctorPDFData.SymptomRow]) {
        currentSectionHeader = "Symptom-Journal (letzte 30 Tage)"
        drawString("Symptom-Journal (letzte 30 Tage)", font: sectionFont)
        drawHorizontalRule()

        let df = DateFormatter()
        df.locale = locale
        df.setLocalizedDateFormatFromTemplate("dMMM")

        for entry in entries {
            var parts: [String] = []
            if let f = entry.flowLabel { parts.append("Blutung: \(f)") }
            if !entry.symptoms.isEmpty { parts.append("Symptome: \(entry.symptoms.joined(separator: ", "))") }
            if let m = entry.mood { parts.append("Stimmung: \(m)/5") }
            guard !parts.isEmpty else { continue }
            drawString("\(df.string(from: entry.date))   \(parts.joined(separator: "  ·  "))", font: smallFont)
        }
        vSpace(8)
    }

    /// Draws the receipt footer + MDR caveat on the **current** page
    /// only. v1 trade-off: a multi-page export has the receipt on the
    /// last page; the full SHA-256 also lives in PDF metadata
    /// (`TidelineExportReceiptSHA256`) for power-user verification, so a
    /// recipient who archives only an interior page still has integrity
    /// proof at the document level. Per-page footers can be added later
    /// if reports start spanning many pages routinely.
    mutating func drawFooterOnCurrentPage() {
        let footerY = DoctorPDFRenderer.pageHeight - DoctorPDFRenderer.bottomMargin + 14
        let caveat = "Beleg dokumentiert die Datenkonsistenz, nicht die medizinische Genauigkeit der Einträge."
        let footer = receipt.footerLine
        let attrs: [NSAttributedString.Key: Any] = [
            .font: footerFont, .foregroundColor: UIColor.darkGray
        ]
        NSAttributedString(string: footer, attributes: attrs)
            .draw(at: CGPoint(x: DoctorPDFRenderer.sideMargin, y: footerY))
        NSAttributedString(string: caveat, attributes: attrs)
            .draw(at: CGPoint(x: DoctorPDFRenderer.sideMargin, y: footerY + 11))
    }
}
