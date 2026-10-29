import XCTest
@testable import ShunfengCore

final class BoardingPassTests: XCTestCase {

    /// The shape Muse Spark returned for a real ANA pass (Haneda → Songshan) with a handwritten time.
    func testDecodesModelOutput() throws {
        let json = #"{"flight":"NH851","date":"04-07","from":"HND","to":"TSA","gate":"144","boarding_time":"09:35","departure_time":"10:05","seat":"21A","handwritten_changes":"9:25 handwritten next to printed boarding time 09:35"}"#
        let pass = try JSONDecoder().decode(BoardingPass.self, from: Data(json.utf8))
        XCTAssertEqual(pass.flightCode, "NH851")
        XCTAssertEqual(pass.destinationName, "台北")
        XCTAssertEqual(pass.gate, "144")
        XCTAssertFalse(pass.handwrittenChanges.isEmpty)
    }

    func testLeadingZerosAndUnknownAirports() throws {
        let json = #"{"flight":"BR0197","date":"05-31","from":"NRT","to":"XYZ","gate":"36","boarding_time":"14:45","departure_time":null,"seat":"41F","handwritten_changes":""}"#
        let pass = try JSONDecoder().decode(BoardingPass.self, from: Data(json.utf8))
        XCTAssertEqual(pass.flightCode, "BR197")
        XCTAssertEqual(pass.destinationName, "XYZ")   // unknown code stays as is
        XCTAssertNil(pass.departureTime)
    }

    func testDestinationNamesMatchAnnouncements() {
        // The name filled into the destination field must be one the destination check understands.
        for code in ["NRT", "HND", "TSA", "PVG", "ICN", "HKG"] {
            XCTAssertNotNil(Destinations.canonical(Airports.name[code]!), code)
        }
    }
}
