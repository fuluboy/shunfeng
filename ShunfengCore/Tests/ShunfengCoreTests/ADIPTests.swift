import XCTest
@testable import ShunfengCore

/// Rows written for these tests in the ADIP CSV format (same columns and quirks as the live file:
/// quoted fields, flight numbers with leading spaces, codeshare rows without an aircraft type).
final class ADIPTests: XCTestCase {

    static let header = "航廈,種類,航空公司代碼,航空公司中文,班次,機門,表訂日期,表訂時間,預計日期,預計時間,往來地點,往來地點英文,往來地點中文,航班狀態,機型,其他航點,行李轉盤,報到櫃台,航班動態中文,航班動態英文"
    static let rows = [
        // BR57 to Vienna, operated by EVA with one codeshare, gate D6.
        #""T2","D","BR","長榮航空"," 57","D6","2026-10-30","23:40:00","2026-10-30","23:40:00","VIE","Vienna","維也納","準時","B787-9","VIE","","10","","""#,
        #""T2","D","OS","奧地利航空","7811","D6","2026-10-30","23:40:00","2026-10-30","23:40:00","VIE","Vienna","維也納","準時","","VIE","","10","","""#,
        // CI100 to Tokyo, delayed by 50 minutes.
        #""T2","D","CI","中華航空","100","A5","2026-10-30","09:30:00","2026-10-30","10:20:00","NRT","Tokyo","東京","改時","A350-900","NRT","","08","","""#,
        // Two cancelled flights to Seoul at the same time: no gates, different terminals. Not codeshares.
        #""T1","D","KE","大韓航空","  92","","2026-10-30","12:00:00","2026-10-30","12:00:00","ICN","Incheon","仁川","取消","-","ICN","","","","""#,
        #""T2","D","BR","長榮航空"," 170","","2026-10-30","12:00:00","2026-10-30","12:00:00","ICN","Incheon","仁川","取消","-","ICN","","","","""#,
        // An arrival with the same number as nothing above.
        #""T2","A","CI","中華航空","101","D4","2026-10-30","17:45:00","2026-10-30","17:41:00","NRT","Tokyo","東京","已到","A350-900","NRT","05","","抵達機坪","To Gate""#,
    ]

    func flights(withBOM: Bool = false) -> [ADIPFlight] {
        let text = (withBOM ? "\u{FEFF}" : "") + ([Self.header] + Self.rows).joined(separator: "\r\n") + "\r\n"
        return ADIP.parse(Data(text.utf8))
    }

    func testParsesRowsWithOrWithoutBOM() {
        XCTAssertEqual(flights().count, 6)
        XCTAssertEqual(flights(withBOM: true).count, 6)
        let br57 = ADIP.find("br 057", in: flights())
        XCTAssertEqual(br57?.code, "BR57")
        XCTAssertEqual(br57?.gate, "D6")
        XCTAssertEqual(br57?.placeZh, "維也納")
        XCTAssertEqual(br57?.scheduled, "2026-10-30 23:40")
    }

    func testCodesharesAreLinked() {
        XCTAssertEqual(ADIP.find("BR57", in: flights())?.codeshares, ["OS7811"])
        XCTAssertEqual(ADIP.find("OS7811", in: flights())?.codeshares, ["BR57"])
    }

    func testCancelledFlightsWithoutGatesAreNotMerged() {
        XCTAssertEqual(ADIP.find("KE92", in: flights())?.codeshares, [])
        XCTAssertNil(ADIP.find("KE92", in: flights())?.gate)
    }

    // MARK: Heard vs data

    func testGateAgrees() {
        let heard = AnnouncementRules.read("長榮航空BR57班機登機門更改為D6。", myFlight: "BR57")
        XCTAssertEqual(Verification.check(heard, against: ADIP.find("BR57", in: flights())).gate, .agrees("D6"))
    }

    func testDataFillsAGateTheRecognizerDropped() {
        let heard = AnnouncementRules.read("长荣航空BR57班机现在开始登机，请至D登机门登机。", myFlight: "BR57")
        let v = Verification.check(heard, against: ADIP.find("BR57", in: flights()))
        XCTAssertEqual(v.gate, .fromData("D6"))
        XCTAssertEqual(v.bestGate, "D6")
    }

    func testGateDisagreementIsReportedNotResolved() {
        let heard = AnnouncementRules.read("BR57 passengers, your new gate is C3.", myFlight: "BR57")
        let v = Verification.check(heard, against: ADIP.find("BR57", in: flights()))
        XCTAssertEqual(v.gate, .disagrees(heard: "C3", data: "D6"))
        XCTAssertEqual(v.bestGate, "C3")   // the announcement is usually newer than the data
    }

    func testDelayMatchesDataByStatusOrTime() {
        let heard = AnnouncementRules.read("China Airlines flight CI100 is delayed.", myFlight: "CI100")
        XCTAssertEqual(Verification.check(heard, against: ADIP.find("CI100", in: flights())).status, .agrees)
    }

    func testCancellationNotYetInData() {
        let heard = AnnouncementRules.read("長榮航空BR57班機因天候因素取消。", myFlight: "BR57")
        XCTAssertEqual(Verification.check(heard, against: ADIP.find("BR57", in: flights())).status,
                       .notYetInData(dataStatus: "準時"))
    }

    func testNoDataMeansUnknown() {
        let heard = AnnouncementRules.read("JL8261 final call.", myFlight: "JL8261")
        XCTAssertEqual(Verification.check(heard, against: nil), Verification(gate: .unknown, status: .notApplicable))
    }

    // MARK: Changes between fetches

    func testDataChangesBetweenFetches() {
        var old = ADIP.find("BR57", in: flights())!
        var new = old
        new.gate = "C2"
        XCTAssertEqual(Verification.changes(from: old, to: new), [.gate(from: "D6", to: "C2")])
        old = new
        new.status = "取消"
        XCTAssertEqual(Verification.changes(from: old, to: new), [.status(from: "準時", to: "取消")])
        old = new
        new.status = "出發"
        XCTAssertEqual(Verification.changes(from: old, to: new), [])   // departing isn't news to act on
    }

    func testCancelledAndMovedToNextDay() {
        var f = ADIP.find("BR57", in: flights())!
        XCTAssertFalse(f.isCancelled || f.isMovedToNextDay)
        f.estimated = "2026-10-31 08:00"   // scheduled 2026-10-30 23:40
        XCTAssertTrue(f.isMovedToNextDay)
        XCTAssertTrue(ADIP.find("KE92", in: flights())!.isCancelled)
    }

    func testDeparted() {
        var f = ADIP.find("BR57", in: flights())!
        XCTAssertFalse(f.hasDeparted)
        f.status = "出發"
        XCTAssertTrue(f.hasDeparted)
        XCTAssertFalse(ADIP.find("CI101", in: flights())!.hasDeparted)   // an arrival never departs
    }
}
