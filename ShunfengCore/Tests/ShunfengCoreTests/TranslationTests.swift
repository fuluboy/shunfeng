import ShunfengCore
import XCTest

final class TranslationTests: XCTestCase {
    func testOnlyEnglishAndJapaneseAreTranslated() {
        XCTAssertTrue(MuseSparkOpen.needsTranslation("Passengers on flight BR57 to Vienna, please proceed to gate B7."))
        XCTAssertTrue(MuseSparkOpen.needsTranslation("日本航空8261便上海浦東行きをご利用のお客様"))
        XCTAssertFalse(MuseSparkOpen.needsTranslation("搭乘長榮航空BR57班機前往維也納的旅客請到B7登機門"))
        XCTAssertFalse(MuseSparkOpen.needsTranslation("CI 100"))
    }
}
