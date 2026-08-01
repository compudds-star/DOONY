import Foundation
import SwiftData

/// Presence classification for a single raw GPS sample.
enum PresenceResult: String, Codable, CaseIterable {
    case insideNY      // point-in-polygon returned true
    case outsideNY     // point-in-polygon returned false
    case nearBorder    // outside/inside but within the border buffer — flagged for scrutiny
}

/// A single raw location fix. We persist every sample so a day's classification
/// can always be traced back to the underlying points (audit requirement).
@Model
final class LocationSample {
    /// UTC instant the fix was captured.
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy in meters (as reported by CoreLocation).
    var horizontalAccuracy: Double
    /// Result of the on-device point-in-polygon test.
    var resultRaw: String
    /// Approximate distance to the NY border in meters (nil if not computed).
    var distanceToBorderMeters: Double?
    /// How this sample was obtained (significant-change, region-boundary, precise-escalation, manual).
    var source: String
    /// The America/New_York calendar day key (yyyy-MM-dd) this sample belongs to.
    var dayKey: String

    var result: PresenceResult {
        get { PresenceResult(rawValue: resultRaw) ?? .outsideNY }
        set { resultRaw = newValue.rawValue }
    }

    init(timestamp: Date,
         latitude: Double,
         longitude: Double,
         horizontalAccuracy: Double,
         result: PresenceResult,
         distanceToBorderMeters: Double?,
         source: String,
         dayKey: String) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.resultRaw = result.rawValue
        self.distanceToBorderMeters = distanceToBorderMeters
        self.source = source
        self.dayKey = dayKey
    }
}

/// The audit conclusion for one calendar day.
///
/// NY's statutory-resident test counts ANY part of a day physically present in
/// NY as a NY day. So a day is:
///   - `ny`         if at least one sample that day is inside NY,
///   - `nonNY`      only if the day has samples and ALL of them are outside NY,
///   - `unverified` if the day has no samples at all (phone off / no fixes).
enum DayStatus: String, Codable, CaseIterable {
    case ny
    case nonNY
    case unverified

    var displayName: String {
        switch self {
        case .ny: return "NY Day"
        case .nonNY: return "Out of NY"
        case .unverified: return "Unverified"
        }
    }
}

/// One row per America/New_York calendar day. Recomputed from samples.
@Model
final class DayClassification {
    /// yyyy-MM-dd in America/New_York.
    @Attribute(.unique) var dayKey: String
    var statusRaw: String
    /// Count of samples backing this day (0 == unverified).
    var sampleCount: Int
    /// True if any backing sample landed within the border buffer — user should review.
    var hasBorderAmbiguity: Bool
    /// True if the user manually overrode the automatic classification.
    var manualOverride: Bool
    /// Optional user note explaining an override or context (e.g. "flew to FL 6am").
    var note: String?
    var lastComputed: Date

    var status: DayStatus {
        get { DayStatus(rawValue: statusRaw) ?? .unverified }
        set { statusRaw = newValue.rawValue }
    }

    init(dayKey: String,
         status: DayStatus,
         sampleCount: Int,
         hasBorderAmbiguity: Bool = false,
         manualOverride: Bool = false,
         note: String? = nil,
         lastComputed: Date = .now) {
        self.dayKey = dayKey
        self.statusRaw = status.rawValue
        self.sampleCount = sampleCount
        self.hasBorderAmbiguity = hasBorderAmbiguity
        self.manualOverride = manualOverride
        self.note = note
        self.lastComputed = lastComputed
    }
}
