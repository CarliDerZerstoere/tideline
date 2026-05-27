import Foundation

/// Sendable snapshot consumed by `DoctorPDFRenderer` (task #46). Built by
/// `CycleStore.doctorPDFData(...)` from the actor's perspective, then
/// rendered on the main actor without needing any further actor hops.
///
/// **Design intent:** strict separation between "what to render" (this
/// struct) and "how to render" (the renderer). Lets the renderer be a
/// pure function fully unit-testable without SwiftData or HealthKit.
public struct DoctorPDFData: Sendable, Equatable {
    public let generatedAt: Date
    public let appVersion: String
    /// Optional patient-supplied free text. Empty by default — user can
    /// add their name + birthdate before printing. Truncated at 60 chars
    /// in the renderer to keep the header tidy.
    public let patientHeader: String

    // MARK: - Summary block

    public let observedCycleCount: Int
    public let averageCycleLengthDays: Double?
    public let predictorModeLabel: String
    public let irregularityDeclared: Bool
    public let upcomingPrediction: PredictionRow?

    // MARK: - Sections

    public let cycles: [CycleRow]
    public let events: [EventRow]
    /// Last 30 days of logged days. `nil` when user opted out.
    public let symptomEntries: [SymptomRow]?

    public init(
        generatedAt: Date,
        appVersion: String,
        patientHeader: String,
        observedCycleCount: Int,
        averageCycleLengthDays: Double?,
        predictorModeLabel: String,
        irregularityDeclared: Bool,
        upcomingPrediction: PredictionRow?,
        cycles: [CycleRow],
        events: [EventRow],
        symptomEntries: [SymptomRow]?
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.patientHeader = patientHeader
        self.observedCycleCount = observedCycleCount
        self.averageCycleLengthDays = averageCycleLengthDays
        self.predictorModeLabel = predictorModeLabel
        self.irregularityDeclared = irregularityDeclared
        self.upcomingPrediction = upcomingPrediction
        self.cycles = cycles
        self.events = events
        self.symptomEntries = symptomEntries
    }

    public struct CycleRow: Sendable, Equatable {
        public let startDate: Date
        public let endDate: Date?
        public let lengthDays: Int?
        public let bleedingDayCount: Int

        public init(startDate: Date, endDate: Date?, lengthDays: Int?, bleedingDayCount: Int) {
            self.startDate = startDate
            self.endDate = endDate
            self.lengthDays = lengthDays
            self.bleedingDayCount = bleedingDayCount
        }
    }

    public struct EventRow: Sendable, Equatable {
        public let date: Date
        public let germanLabel: String
        public let note: String

        public init(date: Date, germanLabel: String, note: String) {
            self.date = date
            self.germanLabel = germanLabel
            // Truncate long notes for layout sanity (≤80 chars + ellipsis).
            self.note = note.count > 80 ? String(note.prefix(80)) + "…" : note
        }
    }

    public struct SymptomRow: Sendable, Equatable {
        public let date: Date
        public let flowLabel: String?
        public let symptoms: [String]
        public let mood: Int?

        public init(date: Date, flowLabel: String?, symptoms: [String], mood: Int?) {
            self.date = date
            self.flowLabel = flowLabel
            self.symptoms = symptoms
            self.mood = mood
        }
    }

    public struct PredictionRow: Sendable, Equatable {
        public let estimatedDate: Date
        public let intervalLower: Date
        public let intervalUpper: Date

        public init(estimatedDate: Date, intervalLower: Date, intervalUpper: Date) {
            self.estimatedDate = estimatedDate
            self.intervalLower = intervalLower
            self.intervalUpper = intervalUpper
        }
    }
}

/// Cryptographic export receipt — SHA-256 of the document's canonical
/// content + ISO-8601 timestamp + app version. Embedded in the PDF footer
/// (differentiator #18). Lets the user or a recipient verify that two
/// exports of the same data produce the same hash (tamper-evidence on the
/// export, not on the underlying data — see the caveat string the renderer
/// adds to the footer).
public struct ExportReceipt: Sendable, Equatable {
    public let sha256Hex: String        // 64-char lowercase hex
    public let generatedAt: Date
    public let appVersion: String

    public init(sha256Hex: String, generatedAt: Date, appVersion: String) {
        self.sha256Hex = sha256Hex
        self.generatedAt = generatedAt
        self.appVersion = appVersion
    }

    /// Short hex (first 16 chars) for the footer display.
    public var shortHex: String { String(sha256Hex.prefix(16)) }

    /// ISO 8601 with timezone offset, e.g. `2026-05-22T14:32:00+02:00`.
    public var generatedAtISO8601: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: generatedAt)
    }

    /// One-line footer ready for the PDF.
    public var footerLine: String {
        "Beleg: SHA-256:\(shortHex)… · \(generatedAtISO8601) · Tideline \(appVersion)"
    }
}
