import Foundation
import CoreLocation
import SwiftData
import Combine

/// Owns all CoreLocation interaction and turns raw fixes into persisted samples
/// and day classifications.
///
/// ## Strategy (battery-efficient, survives termination & reboot)
///
/// 1. **Baseline:** `startMonitoringSignificantLocationChanges()` — extremely
///    low power, and iOS relaunches the app in the background to deliver these
///    even after termination or reboot.
/// 2. **Dynamic geofence:** after every fix we register ONE circular region
///    centered on the current location whose radius is the distance to the NY
///    border (clamped). Leaving that circle means the user moved materially
///    toward/away from the border, so iOS wakes us for a fresh evaluation.
///    Region monitoring, like SLC, relaunches the app after termination.
/// 3. **Escalation:** only when a fix is within `borderBufferMeters` of the
///    boundary do we switch on continuous high-accuracy updates to pin down
///    which side of the line the day falls on; we switch them off again once
///    we're comfortably inside or outside.
///
/// No timers, no foreground loop — everything is event-driven by the OS.
@MainActor
final class LocationManager: NSObject, ObservableObject {

    // Tunables
    private let borderBufferMeters: Double = 3_000      // "near border" threshold
    private let minGeofenceRadius: Double = 200
    private let maxGeofenceRadius: Double = 50_000      // 50 km cap (iOS practical limit ~ few hundred km)
    private let dynamicRegionId = "doony.dynamic.border"

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isPreciseEscalated = false
    @Published private(set) var lastFix: CLLocation?

    /// True when Info.plist's UIBackgroundModes contains "location". Guards the
    /// `allowsBackgroundLocationUpdates` setter, which throws otherwise.
    private static let backgroundLocationModeEnabled: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }()

    private let manager = CLLocationManager()
    private let boundary = GeoBoundary.shared
    private let container: ModelContainer
    private lazy var context = ModelContext(container)

    init(container: ModelContainer) {
        self.container = container
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Only legal when the "location" background mode is declared in Info.plist;
        // setting it otherwise throws NSInternalInconsistencyException at launch.
        if Self.backgroundLocationModeEnabled {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Lifecycle

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Start the always-on baseline. Safe to call on every launch.
    func startTracking() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation() // one immediate fix to seed classification & geofence
    }

    func stopTracking() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        isPreciseEscalated = false
    }

    // MARK: - Fix processing

    private func process(_ location: CLLocation, source: String) {
        lastFix = location
        let coord = location.coordinate
        let inside = boundary.contains(coord)
        let distance = boundary.distanceToBorderMeters(coord)

        let result: PresenceResult
        if distance <= borderBufferMeters {
            result = .nearBorder
        } else {
            result = inside ? .insideNY : .outsideNY
        }

        persistSample(location: location, result: result, distance: distance, source: source)
        updateDynamicGeofence(around: coord, distanceToBorder: distance)
        adjustEscalation(distanceToBorder: distance)
    }

    private func persistSample(location: CLLocation, result: PresenceResult, distance: Double, source: String) {
        let dayKey = NYCalendar.dayKey(for: location.timestamp)
        let sample = LocationSample(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            result: result,
            distanceToBorderMeters: distance,
            source: source,
            dayKey: dayKey
        )
        context.insert(sample)
        recomputeDay(dayKey)
        try? context.save()
    }

    /// Recompute a single day's classification from all its samples.
    func recomputeDay(_ dayKey: String) {
        let descriptor = FetchDescriptor<LocationSample>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        let samples = (try? context.fetch(descriptor)) ?? []
        let outcome = DayClassifier.classify(results: samples.map(\.result))

        let dayDescriptor = FetchDescriptor<DayClassification>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        if let existing = try? context.fetch(dayDescriptor).first {
            if !existing.manualOverride {
                existing.status = outcome.status
            }
            existing.sampleCount = outcome.sampleCount
            existing.hasBorderAmbiguity = outcome.hasBorderAmbiguity
            existing.lastComputed = .now
        } else {
            let day = DayClassification(
                dayKey: dayKey,
                status: outcome.status,
                sampleCount: outcome.sampleCount,
                hasBorderAmbiguity: outcome.hasBorderAmbiguity
            )
            context.insert(day)
        }
    }

    // MARK: - Adaptive monitoring

    private func updateDynamicGeofence(around coord: CLLocationCoordinate2D, distanceToBorder: Double) {
        // Remove the previous dynamic region.
        for region in manager.monitoredRegions where region.identifier == dynamicRegionId {
            manager.stopMonitoring(for: region)
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let radius = min(max(distanceToBorder * 0.75, minGeofenceRadius), maxGeofenceRadius)
        let region = CLCircularRegion(center: coord, radius: radius, identifier: dynamicRegionId)
        region.notifyOnExit = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
    }

    private func adjustEscalation(distanceToBorder: Double) {
        if distanceToBorder <= borderBufferMeters {
            if !isPreciseEscalated {
                isPreciseEscalated = true
                manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.startUpdatingLocation()
            }
        } else {
            if isPreciseEscalated {
                isPreciseEscalated = false
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.stopUpdatingLocation()
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways ||
               manager.authorizationStatus == .authorizedWhenInUse {
                self.startTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let source = self.isPreciseEscalated ? "precise-escalation" : "significant-change"
            for loc in locations where loc.horizontalAccuracy >= 0 {
                self.process(loc, source: source)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in self.manager.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .outside {
            Task { @MainActor in self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Intentionally silent in release: never log coordinates or error detail
        // that could leak location. Failures self-recover on the next OS event.
        #if DEBUG
        print("[DOONY] location error: \(error.localizedDescription)")
        #endif
    }
}
