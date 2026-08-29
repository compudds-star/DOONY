import Foundation

/// Utilities for the America/New_York calendar-day boundary that NY's
/// statutory-resident test uses.
enum NYCalendar {
    static let timeZone = TimeZone(identifier: "America/New_York")!

    static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }()

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// yyyy-MM-dd key for the America/New_York day containing `date`.
    static func dayKey(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    /// Parse a day key back to the start-of-day Date in NY time.
    static func date(fromKey key: String) -> Date? {
        keyFormatter.date(from: key)
    }
}

/// Turns a set of samples for one day into a `DayStatus`.
enum DayClassifier {

    struct Outcome {
        let status: DayStatus
        let sampleCount: Int
        let hasBorderAmbiguity: Bool
    }

    /// Classification rule (NY's "any part of a day" standard):
    ///   - no samples             -> unverified (phone off; never assumed)
    ///   - any sample inside NY   -> ny
    ///   - all samples outside NY -> nonNY
    /// `nearBorder` samples are treated as inside for safety (conservative: a
    /// near-border fix is flagged so the user can review, and does not let a day
    /// silently count as out-of-NY when the fix might actually be in NY).
    static func classify(results: [PresenceResult]) -> Outcome {
        guard !results.isEmpty else {
            return Outcome(status: .unverified, sampleCount: 0, hasBorderAmbiguity: false)
        }
        let anyInside = results.contains(.insideNY)
        let anyBorder = results.contains(.nearBorder)
        let status: DayStatus = (anyInside || anyBorder) ? .ny : .nonNY
        return Outcome(status: status, sampleCount: results.count, hasBorderAmbiguity: anyBorder)
    }
}
