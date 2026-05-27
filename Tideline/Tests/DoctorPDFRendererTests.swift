import Testing
import Foundation
import PDFKit
@testable import Tideline

/// Tests for the pure `DoctorPDFRenderer` (task #46). Verifies hash
/// stability, content presence, mode-driven omissions, and pagination —
/// without spinning up SwiftData or SwiftUI.
@Suite("DoctorPDFRenderer — pure rendering + receipt")
struct DoctorPDFRendererTests {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(timeZone: TimeZone.current, year: y, month: m, day: d, hour: hour))!
    }

    private func sampleData(
        cycles: [DoctorPDFData.CycleRow] = [],
        events: [DoctorPDFData.EventRow] = [],
        symptoms: [DoctorPDFData.SymptomRow]? = nil,
        modeLabel: String = "aktiv",
        prediction: DoctorPDFData.PredictionRow? = nil,
        patientHeader: String = "",
        generatedAt: Date? = nil
    ) -> DoctorPDFData {
        DoctorPDFData(
            generatedAt: generatedAt ?? date(2026, 5, 22, hour: 14),
            appVersion: "0.1.0",
            patientHeader: patientHeader,
            observedCycleCount: cycles.count,
            averageCycleLengthDays: 28.7,
            predictorModeLabel: modeLabel,
            irregularityDeclared: false,
            upcomingPrediction: prediction,
            cycles: cycles,
            events: events,
            symptomEntries: symptoms
        )
    }

    private func cycle(_ y: Int, _ m: Int, _ d: Int, length: Int, bleed: Int = 5) -> DoctorPDFData.CycleRow {
        let start = date(y, m, d)
        let end = cal.date(byAdding: .day, value: length, to: start)
        return DoctorPDFData.CycleRow(startDate: start, endDate: end, lengthDays: length, bleedingDayCount: bleed)
    }

    // MARK: - Output sanity

    @Test("Empty data renders a valid non-empty PDF")
    func emptyDataRenders() {
        let data = sampleData()
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        #expect(!pdf.isEmpty)
        #expect(PDFDocument(data: pdf) != nil)
    }

    @Test("3-cycle data lands all 3 rows in the PDF text")
    func threeCyclesPresent() throws {
        let data = sampleData(cycles: [
            cycle(2026, 3, 1, length: 28),
            cycle(2026, 3, 29, length: 30),
            cycle(2026, 4, 28, length: 27)
        ])
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined()
        #expect(text.contains("28 T"))
        #expect(text.contains("30 T"))
        #expect(text.contains("27 T"))
    }

    @Test("Header text appears at the top of the PDF")
    func patientHeaderRendered() throws {
        let data = sampleData(patientHeader: "Maria Mustermann, geb. 01.01.1990")
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = doc.page(at: 0)?.string ?? ""
        #expect(text.contains("Maria Mustermann"))
    }

    // MARK: - Hash stability

    @Test("Same data → identical SHA-256")
    func hashStable() {
        let data = sampleData(cycles: [cycle(2026, 3, 1, length: 28)])
        let (_, r1) = DoctorPDFRenderer.render(data: data)
        let (_, r2) = DoctorPDFRenderer.render(data: data)
        #expect(r1.sha256Hex == r2.sha256Hex)
    }

    @Test("One-byte content change → different SHA-256")
    func hashChangesOnDataChange() {
        let a = sampleData(cycles: [cycle(2026, 3, 1, length: 28)])
        let b = sampleData(cycles: [cycle(2026, 3, 1, length: 29)])  // 28 → 29
        let (_, ra) = DoctorPDFRenderer.render(data: a)
        let (_, rb) = DoctorPDFRenderer.render(data: b)
        #expect(ra.sha256Hex != rb.sha256Hex)
    }

    // MARK: - Receipt footer format

    @Test("Receipt footer line matches expected shape")
    func footerFormat() {
        let data = sampleData()
        let (_, receipt) = DoctorPDFRenderer.render(data: data)
        let line = receipt.footerLine
        #expect(line.hasPrefix("Beleg: SHA-256:"))
        #expect(line.contains("· Tideline 0.1.0"))
        // 16-char hex short form embedded:
        #expect(receipt.shortHex.count == 16)
        #expect(receipt.shortHex.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Mode-driven omissions

    @Test("Paused mode hides the upcoming-prediction row")
    func pausedModeHidesPrediction() throws {
        let data = sampleData(modeLabel: "pausiert (Stillzeit)", prediction: nil)
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = doc.page(at: 0)?.string ?? ""
        #expect(text.contains("pausiert"))
        #expect(!text.contains("Erwartete nächste Periode"))
    }

    @Test("Retired mode hides the upcoming-prediction row")
    func retiredModeHidesPrediction() throws {
        let data = sampleData(modeLabel: "beendet (Hysterektomie)", prediction: nil)
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = doc.page(at: 0)?.string ?? ""
        #expect(text.contains("beendet"))
        #expect(!text.contains("Erwartete nächste Periode"))
    }

    @Test("Full SHA-256 hash is embedded in PDF Keywords metadata")
    func receiptMetadataEmbedded() throws {
        let data = sampleData(cycles: [cycle(2026, 3, 1, length: 28)])
        let (pdf, receipt) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let attrs = doc.documentAttributes ?? [:]
        let keywords = attrs[PDFDocumentAttribute.keywordsAttribute] as? String
            ?? (attrs[PDFDocumentAttribute.keywordsAttribute] as? [String])?.first
        let expected = "TidelineExportReceiptSHA256:\(receipt.sha256Hex)"
        #expect(keywords == expected)
    }

    @Test("Active mode with prediction renders the prediction row")
    func activeModeShowsPrediction() throws {
        let pred = DoctorPDFData.PredictionRow(
            estimatedDate: date(2026, 6, 20),
            intervalLower: date(2026, 6, 18),
            intervalUpper: date(2026, 6, 23)
        )
        let data = sampleData(prediction: pred)
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = doc.page(at: 0)?.string ?? ""
        #expect(text.contains("Erwartete nächste Periode"))
    }

    // MARK: - Optional sections

    @Test("Symptom journal omitted when symptomEntries is nil")
    func symptomsOmittedWhenNil() throws {
        let data = sampleData(symptoms: nil)
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined()
        #expect(!text.contains("Symptom-Journal"))
    }

    @Test("Symptom journal rendered when entries provided")
    func symptomsRendered() throws {
        let sym = DoctorPDFData.SymptomRow(
            date: date(2026, 5, 18), flowLabel: "leicht", symptoms: ["Kopfschmerzen"], mood: 3
        )
        let data = sampleData(symptoms: [sym])
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined()
        #expect(text.contains("Symptom-Journal"))
        #expect(text.contains("Kopfschmerzen"))
    }

    // MARK: - Event notes

    @Test("Long event note truncates to 80 chars + ellipsis")
    func longEventNoteTruncated() {
        let longNote = String(repeating: "a", count: 200)
        let event = DoctorPDFData.EventRow(
            date: date(2026, 3, 1),
            germanLabel: "Test",
            note: longNote
        )
        // Truncation happens in the EventRow init.
        #expect(event.note.count <= 81)
        #expect(event.note.hasSuffix("…"))
    }

    // MARK: - Multi-page pagination

    @Test("Many cycles produce a multi-page PDF")
    func multiPagePagination() throws {
        // 60 cycles is well beyond what fits on a single A4 page.
        var rows: [DoctorPDFData.CycleRow] = []
        for i in 0..<60 {
            let m = (i % 12) + 1
            rows.append(cycle(2024, m, 1, length: 28))
        }
        let data = sampleData(cycles: rows)
        let (pdf, _) = DoctorPDFRenderer.render(data: data)
        let doc = try #require(PDFDocument(data: pdf))
        #expect(doc.pageCount > 1)
    }
}
