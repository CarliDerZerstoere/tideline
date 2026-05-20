import Foundation
import SwiftData

@Model
final class DayEntry {
    var date: Date
    var flow: FlowLevel
    var moodRaw: Int?
    var symptoms: [String]
    var note: String

    init(
        date: Date,
        flow: FlowLevel = .none,
        moodRaw: Int? = nil,
        symptoms: [String] = [],
        note: String = ""
    ) {
        self.date = date
        self.flow = flow
        self.moodRaw = moodRaw
        self.symptoms = symptoms
        self.note = note
    }
}

public enum FlowLevel: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case spotting = 1
    case light = 2
    case medium = 3
    case heavy = 4
}
