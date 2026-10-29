import XCTest
@testable import ShunfengCore

/// Real transcripts from the phone, recorded on 2026-10-28 while a Haneda Airport T3 ambience video
/// (46:01–57:00) played from a speaker. The expected answers were checked by hand against the video.
/// Haneda never says airline codes, only names, and its gates are plain numbers.
final class HanedaRecordingTests: XCTestCase {
    func testDomesticAirlineNameGivesTheCode() {
        // Heard at Haneda during an iPhone test on Oct 29.
        let r = AnnouncementRules.read("This is the final call for Solaseed Air flight zero zero seven seven for Kagoshima.",
                                       myFlight: "6J77")
        XCTAssertEqual(r.flight, "6J77")
        XCTAssertEqual(r.event, .finalCall)
    }


    // 47:44 — Japanese final call, JAL 8261 to Shanghai Pudong (the gate came as a separate turn).
    let finalCallJapanese = "八十六号日本航空八千二百六十一便上海浦東行きはただいまご搭乗の最終案内をいたしております。"
    let finalCallGateJapanese = "お急ぎ百四十一番ゲートにお搭乗ください。"
    // 48:11 — the English version, listing all three codeshare flights (two turns).
    let finalCallEnglish = "Shanghai Airlines flight eight nine six China Eastern Airlines flight eight six three four Japan Airlines flight eight two six one departing for Shanghai Pudong"
    let finalCallEnglishGate = "passengers on this flight please proceed to gate one four one immediately"

    func testJapaneseFinalCallForJAL() {
        let r = AnnouncementRules.read(finalCallJapanese, myFlight: "JL8261")
        XCTAssertEqual(r.flight, "JL8261")
        XCTAssertEqual(r.event, .finalCall)
        XCTAssertEqual(r.match(for: UserFlight(code: "JL8261", destination: "上海")), .mine)
    }

    func testJapaneseGateWithoutLeadingDigit() {
        XCTAssertEqual(AnnouncementRules.read(finalCallGateJapanese, myFlight: "JL8261").gate, "141")
    }

    func testEnglishCodeshareListFindsEachFlight() {
        let text = finalCallEnglish + " " + finalCallEnglishGate
        for code in ["FM896", "MU8634", "JL8261"] {
            let r = AnnouncementRules.read(text, myFlight: code)
            XCTAssertEqual(r.flight, code, code)
            XCTAssertEqual(r.event, .finalCall, code)
            XCTAssertEqual(r.match(for: UserFlight(code: code, destination: "Shanghai")), .mine, code)
        }
        XCTAssertEqual(AnnouncementRules.read(text, myFlight: "MU8634").gate, "141")
    }

    func testOtherFlightAtHanedaIsNotMine() {
        let r = AnnouncementRules.read(finalCallJapanese, myFlight: "NH851")
        XCTAssertEqual(r.match(for: UserFlight(code: "NH851", destination: "台北")), .notMine)
    }

    // 46:42 — paging a passenger on flight 1068 (the airline name was not caught) to gate 47.
    func testJapanesePagingWithNumberedGate() {
        let r = AnnouncementRules.read("1068 便利用利用の奥の様、特に広志様、奥度様、奥の広志様、私たいことでございます。 それにもせ四十七番搭乗口までお越しください。",
                                       myFlight: "NH1068")
        XCTAssertEqual(r.event, .nameCall)
        XCTAssertEqual(r.gate, "47")
    }

    // 50:00 — moving walkway notice, and a YouTube ad that played in the middle of the test.
    func testGeneralNoticesAndAdsAreIgnored() {
        XCTAssertEqual(AnnouncementRules.read("まもなくご利用席です。足元にご注意ください。", myFlight: "JL8261").event, .info)
        XCTAssertEqual(AnnouncementRules.read("AI is changing the game for app development. Firebase is here to help.", myFlight: "JL8261").event, .info)
    }

    // 49:10 — no such sentence was announced. The recording passes escalators and moving walkways here,
    // so it is most likely an English safety notice ("please mind the gap / your step") misheard as an
    // instruction to go to a gate. It names no flight, so it must not turn into an alert.
    func testMisheardNoticeWithoutFlightIsNotAnAlert() {
        let r = AnnouncementRules.read("We have information for you. Please proceed to gate one thank you.", myFlight: "JL8261")
        XCTAssertNil(r.flight)
        XCTAssertEqual(r.event, .info)
    }

    // Second replay of the same clip: the Japanese came through (with 機 instead of 便), but the English
    // lost every flight number and half the gate.
    func testSecondPassJapaneseWithKiInsteadOfBin() {
        let r = AnnouncementRules.read("八千六百三十四日本航空八千二百六十一機はただいまご搭乗を最終案内をいたしています。 お急ぎ百四十一番ゲートにご搭乗ください。",
                                       myFlight: "JL8261")
        XCTAssertEqual(r.flight, "JL8261")
        XCTAssertEqual(r.event, .finalCall)
        XCTAssertEqual(r.gate, "141")
    }

    func testEnglishRepeatWithoutFlightConfirmsButFlagsTheGate() {
        let user = UserFlight(code: "JL8261", destination: "上海")
        let japanese = AnnouncementRules.read(finalCallJapanese + " " + finalCallGateJapanese, myFlight: user.code)
        XCTAssertEqual(AnnouncementRules.followUp("Passengers on this flight please proceed to gate one immediately",
                                                  to: japanese, user: user),
                       .confirms(conflictingGate: "1"))
        XCTAssertEqual(AnnouncementRules.followUp("passengers on this flight please proceed to gate one four one immediately",
                                                  to: japanese, user: user),
                       .confirms(conflictingGate: nil))
    }

    func testFragmentsAreNotFollowUps() {
        let user = UserFlight(code: "JL8261", destination: "上海")
        let japanese = AnnouncementRules.read(finalCallJapanese, myFlight: user.code)
        XCTAssertNil(AnnouncementRules.followUp("Airline", to: japanese, user: user))
        XCTAssertNil(AnnouncementRules.followUp("Shanghai Pudong", to: japanese, user: user))   // no event
        XCTAssertNil(AnnouncementRules.followUp("Please watch your step.", to: japanese, user: user))
        // A different event is not a repeat, even for "this flight".
        XCTAssertNil(AnnouncementRules.followUp("This flight is delayed.", to: japanese, user: user))
    }

    func testWordsThatLookLikeNumbersOrAirlines() {
        XCTAssertTrue(Normalizer.normalize("千葉方面").contains("千葉"))
        XCTAssertTrue(AnnouncementRules.flights(in: Normalizer.normalize("Air Canada 123 to Vancouver")).isEmpty)
    }
}
