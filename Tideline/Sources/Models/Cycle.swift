import Foundation
import SwiftData

@Model
final class Cycle {
    var startDate: Date
    var endDate: Date?
    var notes: String

    init(startDate: Date, endDate: Date? = nil, notes: String = "") {
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
    }

    var lengthInDays: Int? {
        guard let endDate else { return nil }
        return Calendar.current.dateComponents([.day], from: startDate, to: endDate).day
    }
}
