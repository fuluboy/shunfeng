import XCTest
@testable import ShunfengCore

final class BoardingPassTests: XCTestCase {
    func testDepartureDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
        var pass = BoardingPass(flight: "BR57", date: "10-30", from: "TPE", to: "VIE", gate: "D6",
                                boardingTime: "22:50", departureTime: "23:40", seat: "31A", handwrittenChanges: "")
        let d = try XCTUnwrap(pass.departure(now: now, calendar: calendar))
        XCTAssertEqual(d.date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 23, minute: 40)))
        XCTAssertFalse(d.estimated)
        // Only boarding printed: 30 minutes later, marked as estimated. An April pass means next April.
        pass.date = "04-07"
        pass.departureTime = nil
        let e = try XCTUnwrap(pass.departure(now: now, calendar: calendar))
        XCTAssertEqual(e.date, calendar.date(from: DateComponents(year: 2027, month: 4, day: 7, hour: 23, minute: 20)))
        XCTAssertTrue(e.estimated)
    }


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
