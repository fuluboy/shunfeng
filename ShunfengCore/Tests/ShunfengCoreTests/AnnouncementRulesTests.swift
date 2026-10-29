import XCTest
@testable import ShunfengCore

/// Cases written during the hackathon. The user's flight is BR57 unless a test says otherwise,
/// so nothing here leans on the pre-hackathon evaluation set.
final class AnnouncementRulesTests: XCTestCase {

    func read(_ text: String, myFlight: String = "BR57") -> AnnouncementReading {
        AnnouncementRules.read(text, myFlight: myFlight)
    }

    // MARK: Gate changes

    func testHyphenatedCodeAfterAirlineName() {
        // The airline name must not add its code again in front of a code spelled "B-R".
        let r = read("長榮B-R五十七班機，登機門改到C三。")
        XCTAssertEqual(r.flight, "BR57")
        XCTAssertEqual(r.gate, "C3")
    }

    func testGateChangeInChinese() {
        let r = read("長榮航空BR57班機飛往維也納的旅客請注意，登機門由C3更改為D6，請前往D6登機門。")
        XCTAssertEqual(r.flight, "BR57")
        XCTAssertEqual(r.event, .gateChange)
        XCTAssertEqual(r.gate, "D6")
        XCTAssertTrue(r.gateIsCertain)
    }

    func testGateChangeInEnglishKeepsNewGateOnly() {
        let r = read("EVA Air flight BR57 to Vienna, gate C3 has changed to D6.")
        XCTAssertEqual(r.event, .gateChange)
        XCTAssertEqual(r.gate, "D6")
    }

    func testCorrectionDropsTheWrongGate() {
        let r = read("更正廣播：BR57班機登機門仍為C3，先前更改至D6的廣播有誤。")
        XCTAssertEqual(r.event, .gateChange)
        XCTAssertEqual(r.gate, "C3")
    }

    func testRemoteGateWithSpokenLetters() {
        let r = read("Flight B R five seven, gate change, now gate C five R.")
        XCTAssertEqual(r.flight, "BR57")
        XCTAssertEqual(r.gate, "C5R")
    }

    // MARK: Other events

    func testDelayWithChineseClock() {
        let r = read("BR57班機因天候因素，起飛時間延後至晚上八點十五分。")
        XCTAssertEqual(r.event, .delay)
        XCTAssertEqual(r.time, "20:15")
    }

    func testEarlierDepartureIsNotADelay() {
        let r = read("Due to the typhoon, BR57 will now depart earlier, at 9:40 AM.")
        XCTAssertEqual(r.event, .timeChange)
        XCTAssertEqual(r.time, "09:40")
    }

    func testFinalCallMentioningGateIsStillFinalCall() {
        XCTAssertEqual(read("This is the final call for BR57 at gate D6.").event, .finalCall)
    }

    func testNameCall() {
        XCTAssertEqual(read("林小姐，搭乘BR57班機的林小姐，請到D6登機門櫃台。").event, .nameCall)
    }

    func testBatchCancellationFindsTheUserFlightAtTheEnd() {
        let r = read("因颱風影響，以下班機取消：BR31飛往紐約、BR35飛往波士頓、BR57飛往維也納。")
        XCTAssertEqual(r.flight, "BR57")
        XCTAssertEqual(r.event, .cancel)
    }

    func testGeneralInfoHasNoFlight() {
        let r = read("Please keep your belongings with you at all times.")
        XCTAssertNil(r.flight)
        XCTAssertEqual(r.event, .info)
    }

    // MARK: Not my flight

    func testLongerFlightNumberIsNotMine() {
        let r = read("Final call for flight BR570 at gate A2.")
        XCTAssertEqual(r.flight, "BR570")
        XCTAssertNotEqual(r.flight, "BR57")
    }

    func testOtherFlightGateIsNotTakenFromMyClause() {
        let r = read("Passengers on BR51, your gate remains A7. Passengers on BR57, your new gate is D6.")
        XCTAssertEqual(r.flight, "BR57")
        XCTAssertEqual(r.gate, "D6")
    }

    // MARK: Speech recognition quirks (Muse Voice Transcribe output)

    func testSimplifiedChineseAndChineseNumbers() {
        // Recognizer output: Simplified, "CI" heard as 此, 一百 written in Chinese.
        let r = read("中华航空此一百班机登机门更改为B7。", myFlight: "CI100")
        XCTAssertEqual(r.flight, "CI100")
        XCTAssertEqual(r.event, .gateChange)
        XCTAssertEqual(r.gate, "B7")
    }

    func testAirlineNameRestoresLostLetters() {
        let r = read("长荣航空五十七班机起飞时间延后至 16 点 30 分。")
        XCTAssertEqual(r.flight, "BR57")
        XCTAssertEqual(r.event, .delay)
        XCTAssertEqual(r.time, "16:30")
    }

    func testStutterIsRemoved() {
        let r = read("此一百一百班机飞往东京的最后登机广播。", myFlight: "CI100")
        XCTAssertEqual(r.flight, "CI100")
        XCTAssertEqual(r.event, .finalCall)
    }

    func testDecimalTimeIsNotSplitIntoClauses() {
        let r = read("China Airlines flight CI 100 is delayed. The new departure time is 3.20 PM.", myFlight: "CI100")
        XCTAssertEqual(r.flight, "CI100")
        XCTAssertEqual(r.time, "15:20")
    }

    func testStrayCommaBetweenFlights() {
        let r = read("中华航空CI100与,CI110班机旅客请注意,CI100改至B7登机门,CI110维持A7。", myFlight: "CI100")
        XCTAssertEqual(r.gate, "B7")
    }

    func testGateWithLostDigitIsNotInvented() {
        // The recognizer dropped the 5 from A5. The rules must not make a gate up.
        let r = read("中华航空此一百班机现在开始登机，请至A登机门登机。", myFlight: "CI100")
        XCTAssertEqual(r.event, .boarding)
        XCTAssertNil(r.gate)
    }

    func testSpaceBetweenGateLetterAndDigit() {
        // Seen on the iPhone on 2026-10-28: "由A更改为B 7，请前往B 7登机门".
        let r = read("中华航空公司自100班机飞往东京成田的旅客请注意，本班机登机门由A更改为B 7，请前往B 7登机门候机，", myFlight: "CI100")
        XCTAssertEqual(r.gate, "B7")
        XCTAssertEqual(read("Flight CI 100, now gate D 14R.", myFlight: "CI100").gate, "D14R")
    }

    func testSpaceBetweenGateLetterAndChineseDigit() {
        XCTAssertEqual(read("長榮航空BR57班機登機門更改為 C 三。").gate, "C3")
    }

    // MARK: Destination check

    func testDroppedDigitIsCaughtByDestination() {
        // Live transcription turned "CI1000 to Hong Kong" into "CI 100" (seen on 2026-10-28).
        let r = read("Final call for China Airlines flight CI 100 to Hong Kong at gate D2.", myFlight: "CI100")
        XCTAssertEqual(r.flight, "CI100")
        XCTAssertEqual(r.match(for: UserFlight(code: "CI100", destination: "東京成田")),
                       .destinationConflict(heard: ["Hong Kong"]))
    }

    func testSameDestinationIsMine() {
        let r = read("中華航空CI100班機飛往東京成田，登機門更改為B7。", myFlight: "CI100")
        XCTAssertEqual(r.match(for: UserFlight(code: "CI100", destination: "Tokyo Narita")), .mine)
    }

    func testNoDestinationMentionedIsStillMine() {
        let r = read("CI100 passengers, your new gate is B7.", myFlight: "CI100")
        XCTAssertEqual(r.match(for: UserFlight(code: "CI100", destination: "Tokyo")), .mine)
    }

    func testOtherFlightIsNotMine() {
        let r = read("BR192 to Tokyo Haneda is now boarding at gate C3.", myFlight: "CI100")
        XCTAssertEqual(r.match(for: UserFlight(code: "CI100", destination: "Tokyo")), .notMine)
    }

    func testMacauAirlineIsNotADestination() {
        XCTAssertFalse(Destinations.heard(in: "澳門航空NX631班機取消").contains("Macau"))
        XCTAssertTrue(Destinations.heard(in: "飛往澳門的旅客").contains("Macau"))
    }

    // MARK: Normalizer details

    func testChineseHundreds() {
        XCTAssertEqual(Normalizer.chineseHundreds("一百一十"), "110")
        XCTAssertEqual(Normalizer.chineseHundreds("一百零五"), "105")
        XCTAssertEqual(Normalizer.chineseHundreds("一千"), "1000")
        XCTAssertEqual(Normalizer.chineseHundreds("一般"), "一般")
    }

    func testFlightNormalization() {
        XCTAssertEqual(AnnouncementRules.normalizeFlight("ci 0100"), "CI100")
        XCTAssertEqual(AnnouncementRules.normalizeFlight("BR57"), "BR57")
    }
}
