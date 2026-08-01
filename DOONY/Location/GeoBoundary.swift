import Foundation
import CoreLocation

/// Loads the bundled NY State boundary GeoJSON and answers point-in-polygon
/// queries entirely on-device. No remote geocoding, ever.
///
/// Supports GeoJSON `Polygon` and `MultiPolygon`. Each polygon's first linear
/// ring is the outer boundary; any subsequent rings are holes.
final class GeoBoundary {

    /// A ring is an array of (lon, lat) coordinates.
    private struct Ring {
        let points: [CLLocationCoordinate2D]
    }

    /// A polygon: one outer ring plus zero or more holes.
    private struct Poly {
        let outer: Ring
        let holes: [Ring]
    }

    private let polygons: [Poly]
    /// Bounding box of the whole state, for a cheap early-reject.
    let boundingBox: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)

    static let shared: GeoBoundary = {
        do {
            return try GeoBoundary(resourceName: "ny_state_boundary")
        } catch {
            fatalError("Failed to load NY boundary GeoJSON: \(error)")
        }
    }()

    enum LoadError: Error { case missingResource, badJSON, noGeometry }

    init(resourceName: String) throws {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "geojson") else {
            throw LoadError.missingResource
        }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.badJSON
        }

        // Accept either a Feature, a FeatureCollection, or a raw geometry.
        let geometry = try GeoBoundary.extractGeometry(from: root)
        guard let type = geometry["type"] as? String,
              let coords = geometry["coordinates"] as? [Any] else {
            throw LoadError.noGeometry
        }

        var polys: [Poly] = []
        switch type {
        case "Polygon":
            polys.append(GeoBoundary.parsePolygon(coords))
        case "MultiPolygon":
            for polyCoords in coords {
                if let pc = polyCoords as? [Any] {
                    polys.append(GeoBoundary.parsePolygon(pc))
                }
            }
        default:
            throw LoadError.noGeometry
        }
        self.polygons = polys

        // Compute overall bounding box.
        var minLon = Double.greatestFiniteMagnitude, minLat = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude, maxLat = -Double.greatestFiniteMagnitude
        for p in polys {
            for c in p.outer.points {
                minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
                minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            }
        }
        self.boundingBox = (minLon, minLat, maxLon, maxLat)
    }

    private static func extractGeometry(from root: [String: Any]) throws -> [String: Any] {
        if let geom = root["geometry"] as? [String: Any] { return geom }             // Feature
        if let features = root["features"] as? [[String: Any]],
           let first = features.first,
           let geom = first["geometry"] as? [String: Any] { return geom }            // FeatureCollection
        if root["coordinates"] != nil { return root }                                // raw geometry
        throw LoadError.noGeometry
    }

    private static func parsePolygon(_ coords: [Any]) -> Poly {
        var rings: [Ring] = []
        for ringAny in coords {
            guard let ring = ringAny as? [Any] else { continue }
            var pts: [CLLocationCoordinate2D] = []
            pts.reserveCapacity(ring.count)
            for pointAny in ring {
                guard let pair = pointAny as? [Any], pair.count >= 2 else { continue }
                // JSONSerialization yields NSNumber; bridge explicitly to Double.
                let lon = (pair[0] as? NSNumber)?.doubleValue ?? (pair[0] as? Double)
                let lat = (pair[1] as? NSNumber)?.doubleValue ?? (pair[1] as? Double)
                if let lon, let lat {
                    pts.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            }
            rings.append(Ring(points: pts))
        }
        let outer = rings.first ?? Ring(points: [])
        let holes = Array(rings.dropFirst())
        return Poly(outer: outer, holes: holes)
    }

    // MARK: - Queries

    /// True if the coordinate is inside NY State (inside any outer ring and not
    /// inside a hole of that ring).
    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        // Cheap bounding-box reject first.
        if coord.longitude < boundingBox.minLon || coord.longitude > boundingBox.maxLon ||
           coord.latitude < boundingBox.minLat || coord.latitude > boundingBox.maxLat {
            return false
        }
        for poly in polygons {
            if rayCast(coord, ring: poly.outer) {
                let inHole = poly.holes.contains { rayCast(coord, ring: $0) }
                if !inHole { return true }
            }
        }
        return false
    }

    /// Standard even-odd ray-casting point-in-polygon for a single ring.
    private func rayCast(_ p: CLLocationCoordinate2D, ring: Ring) -> Bool {
        let pts = ring.points
        guard pts.count > 2 else { return false }
        var inside = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let xi = pts[i].longitude, yi = pts[i].latitude
            let xj = pts[j].longitude, yj = pts[j].latitude
            if ((yi > p.latitude) != (yj > p.latitude)),
               p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Approximate shortest distance (meters) from `coord` to the nearest boundary
    /// segment. Used to decide whether a fix is "near the border" and to escalate
    /// sampling precision. This is an approximation using an equirectangular
    /// projection local to the point — accurate enough at NY latitudes for the
    /// kilometer-scale buffers we care about.
    func distanceToBorderMeters(_ coord: CLLocationCoordinate2D) -> Double {
        let lat0 = coord.latitude * .pi / 180
        let metersPerDegLat = 111_132.0
        let metersPerDegLon = 111_320.0 * cos(lat0)

        func project(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (x: c.longitude * metersPerDegLon, y: c.latitude * metersPerDegLat)
        }
        let p = project(coord)
        var best = Double.greatestFiniteMagnitude

        for poly in polygons {
            for ring in [poly.outer] + poly.holes {
                let pts = ring.points
                guard pts.count > 1 else { continue }
                var j = pts.count - 1
                for i in 0..<pts.count {
                    let a = project(pts[j])
                    let b = project(pts[i])
                    best = min(best, GeoBoundary.pointToSegment(p, a, b))
                    j = i
                }
            }
        }
        return best
    }

    private static func pointToSegment(_ p: (x: Double, y: Double),
                                       _ a: (x: Double, y: Double),
                                       _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let projX = a.x + t * dx, projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }
}
