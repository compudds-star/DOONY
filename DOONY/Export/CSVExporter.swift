import Foundation
import SwiftData

/// Builds CSV files for local, user-initiated export via the share sheet.
/// Nothing here touches the network.
enum CSVExporter {

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",") + "\n"
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = NYCalendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.timeZone = NYCalendar.timeZone; return f
    }()

    /// One row per calendar day with its status and sample backing.
    @MainActor
    static func dayClassificationsCSV(context: ModelContext) -> String {
        let days = (try? context.fetch(FetchDescriptor<DayClassification>(
            sortBy: [SortDescriptor(\.dayKey)]))) ?? []
        var out = row(["date_america_new_york", "status", "sample_count",
                       "border_ambiguity", "manual_override", "note"])
        for d in days {
            out += row([d.dayKey, d.status.rawValue, String(d.sampleCount),
                        d.hasBorderAmbiguity ? "yes" : "no",
                        d.manualOverride ? "yes" : "no",
                        d.note ?? ""])
        }
        return out
    }

    /// Every raw sample — the audit trail behind each day's classification.
    @MainActor
    static func rawSamplesCSV(context: ModelContext) -> String {
        let samples = (try? context.fetch(FetchDescriptor<LocationSample>(
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        var out = row(["timestamp_iso", "day_america_new_york", "latitude", "longitude",
                       "accuracy_m", "result", "distance_to_border_m", "source"])
        for s in samples {
            out += row([isoDateTime.string(from: s.timestamp), s.dayKey,
                        String(s.latitude), String(s.longitude),
                        String(s.horizontalAccuracy), s.result.rawValue,
                        s.distanceToBorderMeters.map { String(Int($0)) } ?? "",
                        s.source])
        }
        return out
    }

    /// Yearly summary counts.
    @MainActor
    static func yearlySummaryCSV(context: ModelContext) -> String {
        let days = (try? context.fetch(FetchDescriptor<DayClassification>())) ?? []
        var byYear: [String: (ny: Int, nonNY: Int, unverified: Int)] = [:]
        for d in days {
            let year = String(d.dayKey.prefix(4))
            var t = byYear[year] ?? (0, 0, 0)
            switch d.status {
            case .ny: t.ny += 1
            case .nonNY: t.nonNY += 1
            case .unverified: t.unverified += 1
            }
            byYear[year] = t
        }
        var out = row(["year", "ny_days", "out_of_ny_days", "unverified_days", "ny_threshold_183"])
        for year in byYear.keys.sorted() {
            let t = byYear[year]!
            out += row([year, String(t.ny), String(t.nonNY), String(t.unverified),
                        t.ny >= 183 ? "EXCEEDED" : "under"])
        }
        return out
    }
}
