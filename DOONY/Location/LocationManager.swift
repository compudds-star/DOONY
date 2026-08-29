import Foundation
import CoreLocation
import SwiftData
import Combine
import BackgroundTasks

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
    // "Near border" threshold: within this distance of the NY line a sample is
    // flagged for review and precise GPS is engaged. 2 km keeps a safe margin
    // over typical coarse-location error while not escalating (battery) at spots
    // like a golf course ~3 km inside NY, which coarse location already places
    // firmly in-state.
    //
    // 2 km IS A FLOOR, NOT JUST A BATTERY KNOB. Measured 2026-08-29, the bundled
    // ny_state_boundary.geojson deviates from the Census cartographic boundary
    // (cb_2023_us_state_500k) by a median of 29 m, p99 1183 m, and a worst case
    // of 1951 m in the Thousand Islands. Because that maximum sits just inside
    // this buffer, every location where the polygon is wrong enough to flip a
    // day's classification is also flagged `nearBorder` and escalated — boundary
    // error can never silently produce a confident wrong answer. Lowering this
    // below ~2 km forfeits that guarantee; raising it only costs battery.
    // Re-measure before changing it, or before replacing the boundary file.
    private let borderBufferMeters: Double = 2_000
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

    /// Write through the container's MAIN context — the same one `@Query` observes
    /// in the UI. Using a separate ModelContext here meant day reclassifications
    /// weren't reliably reflected in the summary counts (a fixed day could stay
    /// counted as Unverified). Safe because this class is @MainActor.
    private var context: ModelContext { container.mainContext }

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

    /// Request a single fresh fix, e.g. each time the app becomes active. This
    /// ensures a stationary day (where significant-location-change never fires)
    /// still records at least one sample and is classified rather than left
    /// Unverified. Silently no-ops until location is authorized.
    func requestFreshFix() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    private var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - Daily background refresh
    //
    // A once-a-day background wake so a day spent entirely stationary (no
    // significant-location-change, app never opened) still records a sample and
    // is classified instead of left Unverified. Registered via SwiftUI's
    // `.backgroundTask(.appRefresh:)`; the identifier is in Info.plist.

    static let dailyFixTaskID = "com.doony.app.dailyfix"

    /// Ask iOS to run our daily-fix task no sooner than ~12h from now. iOS
    /// ultimately decides the timing based on usage and power.
    static func scheduleDailyFix() {
        let request = BGAppRefreshTaskRequest(identifier: dailyFixTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private var oneShotContinuation: CheckedContinuation<Void, Never>?

    /// Awaitably acquire one location fix, with a timeout so a background task
    /// never hangs waiting for a fix that won't arrive (e.g. no signal).
    func acquireOneFix(timeout: TimeInterval = 20) async {
        guard isAuthorized else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { continuation in
                    self.oneShotContinuation = continuation
                    self.manager.requestLocation()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            _ = await group.next()   // whichever finishes first (fix or timeout)
            // Resume the continuation now (if the timeout won) so the waiting
            // child task can complete and the group can return without hanging.
            self.resolveOneShot()
            group.cancelAll()
        }
    }

    /// Idempotently resume the pending one-shot continuation (guarded against
    /// double-resume from both the delegate and the timeout).
    private func resolveOneShot() {
        guard let continuation = oneShotContinuation else { return }
        oneShotContinuation = nil
        continuation.resume()
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
                // NearestTenMeters — not Best/BestForNavigation. ~10 m resolves
                // which side of the state line you're on (and already beats the
                // bundled boundary's own precision), while drawing far less power
                // than Best, which streamed continuously for hours near the border.
                manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                // Only report movement of 25 m+, so a stationary phone near the
                // line isn't firing constant updates.
                manager.distanceFilter = 25
                manager.startUpdatingLocation()
            }
        } else {
            if isPreciseEscalated {
                isPreciseEscalated = false
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.distanceFilter = kCLDistanceFilterNone
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
            self.resolveOneShot()
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
        Task { @MainActor in self.resolveOneShot() }
    }
}
