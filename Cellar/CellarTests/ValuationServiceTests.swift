import XCTest
@testable import Cellar

final class ValuationServiceTests: XCTestCase {

    func testDecodesEndpointContract() throws {
        let json = """
        {
          "average": 189.00,
          "min": 165.00,
          "max": 220.00,
          "currency": "USD",
          "offers": [
            { "merchant": "Wine Library", "price": 175.00, "currency": "USD",
              "url": "https://example.com/x", "address": "123 Main St",
              "latitude": 41.03, "longitude": -73.76, "inStock": true },
            { "merchant": "Total Wine", "price": 182.50 }
          ]
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(RemoteValuationDTO.self, from: json)
        XCTAssertEqual(dto.average, Decimal(string: "189.00"))
        XCTAssertEqual(dto.currency, "USD")
        XCTAssertEqual(dto.offers?.count, 2)
        XCTAssertEqual(dto.offers?.first?.merchant, "Wine Library")
        XCTAssertEqual(dto.offers?.first?.latitude, 41.03)
        // Sparse offer: missing optionals decode as nil, not a failure.
        XCTAssertNil(dto.offers?.last?.url)
        XCTAssertNil(dto.offers?.last?.inStock)
    }

    func testDecodesEmptyOffers() throws {
        let json = #"{ "average": 50.0, "currency": "USD" }"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(RemoteValuationDTO.self, from: json)
        XCTAssertEqual(dto.average, Decimal(50))
        XCTAssertNil(dto.offers)
    }

    func testUnconfiguredEndpointIsNotConfigured() {
        // No baseURL → not configured (empty UserDefaults in the test host).
        let cfg = ValuationConfig(baseURL: nil, apiKey: nil)
        XCTAssertFalse(cfg.isConfigured)
    }

    func testHTTPEndpointIsRejected() {
        let cfg = ValuationConfig(baseURL: URL(string: "http://insecure.example.com"), apiKey: nil)
        XCTAssertFalse(cfg.isConfigured)   // must be HTTPS
    }

    func testHTTPSEndpointIsConfigured() {
        let cfg = ValuationConfig(baseURL: URL(string: "https://host.example.com/api"), apiKey: "k")
        XCTAssertTrue(cfg.isConfigured)
    }
}
