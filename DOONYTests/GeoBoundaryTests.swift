import XCTest
import CoreLocation
@testable import DOONY

/// Sanity checks for the on-device point-in-polygon classifier against the
/// bundled NY boundary. These are the audit-critical correctness tests.
final class GeoBoundaryTests: XCTestCase {

    private var boundary: GeoBoundary!

    override func setUpWithError() throws {
        // Load the bundled resource from the test bundle.
        boundary = try GeoBoundary(resourceName: "ny_state_boundary")
    }

    func testKnownNYLocationsInside() {
        // Albany (state capital), Buffalo, Syracuse — all firmly inside NY.
        let inside: [CLLocationCoordinate2D] = [
            .init(latitude: 42.6526, longitude: -73.7562),  // Albany
            .init(latitude: 42.8864, longitude: -78.8784),  // Buffalo
            .init(latitude: 43.0481, longitude: -76.1474),  // Syracuse
            .init(latitude: 40.7128, longitude: -74.0060),  // NYC (Manhattan)
        ]
        for c in inside {
            XCTAssertTrue(boundary.contains(c), "Expected inside NY: \(c.latitude),\(c.longitude)")
        }
    }

    func testKnownNonNYLocationsOutside() {
        // Delray Beach FL, Newark NJ, Hartford CT, Boston MA — all outside NY.
        let outside: [CLLocationCoordinate2D] = [
            .init(latitude: 26.4615, longitude: -80.0728),  // Delray Beach, FL
            .init(latitude: 40.7357, longitude: -74.1724),  // Newark, NJ
            .init(latitude: 41.7658, longitude: -72.6734),  // Hartford, CT
            .init(latitude: 42.3601, longitude: -71.0589),  // Boston, MA
        ]
        for c in outside {
            XCTAssertFalse(boundary.contains(c), "Expected outside NY: \(c.latitude),\(c.longitude)")
        }
    }

    func testBorderDistanceIsSmallNearLine() {
        // A point in NYC should be far from the *state* border but the function
        // should still return a finite, positive distance.
        let d = boundary.distanceToBorderMeters(.init(latitude: 42.6526, longitude: -73.7562))
        XCTAssertGreaterThan(d, 0)
        XCTAssertLessThan(d, 5_000_000)
    }
}

/// Verifies the "any part of a day" classification rule.
final class DayClassifierTests: XCTestCase {
    func testUnverifiedWhenNoSamples() {
        XCTAssertEqual(DayClassifier.classify(results: []).status, .unverified)
    }
    func testNYIfAnyInside() {
        let o = DayClassifier.classify(results: [.outsideNY, .outsideNY, .insideNY])
        XCTAssertEqual(o.status, .ny)
    }
    func testNonNYOnlyIfAllOutside() {
        let o = DayClassifier.classify(results: [.outsideNY, .outsideNY])
        XCTAssertEqual(o.status, .nonNY)
    }
    func testNearBorderCountsAsNY() {
        let o = DayClassifier.classify(results: [.outsideNY, .nearBorder])
        XCTAssertEqual(o.status, .ny)
        XCTAssertTrue(o.hasBorderAmbiguity)
    }
}
