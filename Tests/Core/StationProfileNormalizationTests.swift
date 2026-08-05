import XCTest
@testable import QSOPartyLogger

/// What Contest Setup guarantees about the profile it saves. The sheet's fields
/// fold as they are typed, but a binding is a typing affordance, not a promise —
/// this is the promise.
final class StationProfileNormalizationTests: XCTestCase {

    func mixedCaseProfile() -> StationProfile {
        var profile = StationProfile()
        profile.callsign = "ke5cw"
        profile.name = "Tom"
        profile.email = "Tom.Bowles@Example.COM"
        profile.address = "123 Prairie Rd"
        profile.city = "Olathe"
        profile.stateProvince = "ks"
        profile.postalCode = "66061-1234"
        profile.country = "usa"
        profile.club = "Kansas City dx Club"
        profile.operators = "ke5cw n0ax"
        profile.gridLocator = "em28pw"
        return profile
    }

    func testEveryFieldButEmailFoldsToUpperCase() {
        let normalized = mixedCaseProfile().normalized()
        XCTAssertEqual(normalized.callsign, "KE5CW")
        XCTAssertEqual(normalized.name, "TOM")
        XCTAssertEqual(normalized.address, "123 PRAIRIE RD")
        XCTAssertEqual(normalized.city, "OLATHE")
        XCTAssertEqual(normalized.stateProvince, "KS")
        XCTAssertEqual(normalized.postalCode, "66061-1234")
        XCTAssertEqual(normalized.country, "USA")
        XCTAssertEqual(normalized.club, "KANSAS CITY DX CLUB")
        XCTAssertEqual(normalized.operators, "KE5CW N0AX")
        XCTAssertEqual(normalized.gridLocator, "EM28PW")
    }

    /// RFC 5321 leaves the local part case-sensitive, and this is the one
    /// header a sponsor may write back to. Rewriting somebody's address is not
    /// a normalisation the app has any business making.
    func testEmailKeepsTheCaseItWasTypedIn() {
        XCTAssertEqual(
            mixedCaseProfile().normalized().email, "Tom.Bowles@Example.COM"
        )
    }

    func testEveryFieldIsTrimmed() {
        var profile = StationProfile()
        profile.callsign = "  ke5cw  "
        profile.city = " Olathe "
        profile.email = "  tom@example.com  "
        let normalized = profile.normalized()
        XCTAssertEqual(normalized.callsign, "KE5CW")
        XCTAssertEqual(normalized.city, "OLATHE")
        XCTAssertEqual(normalized.email, "tom@example.com", "trimmed, not folded")
    }

    /// Setup saves on every visit, so normalising twice has to be the same as
    /// normalising once.
    func testNormalizationIsIdempotent() {
        let once = mixedCaseProfile().normalized()
        XCTAssertEqual(once.normalized(), once)
    }

    /// Categories and the rest of the profile are not text the operator types,
    /// and must survive untouched.
    func testNonTextFieldsSurvive() {
        var profile = mixedCaseProfile()
        profile.categoryOperator = .multiOp
        profile.categoryAssisted = .assisted
        profile.categoryPower = .qrp
        profile.categoryStation = .mobile
        profile.categoryTransmitter = .unlimited
        let normalized = profile.normalized()
        XCTAssertEqual(normalized.categoryOperator, .multiOp)
        XCTAssertEqual(normalized.categoryAssisted, .assisted)
        XCTAssertEqual(normalized.categoryPower, .qrp)
        XCTAssertEqual(normalized.categoryStation, .mobile)
        XCTAssertEqual(normalized.categoryTransmitter, .unlimited)
    }

    /// An empty profile normalises to an empty profile — no field acquires a
    /// value it did not have.
    func testAnEmptyProfileIsUnchangedApartFromItsDefaults() {
        let empty = StationProfile()
        XCTAssertEqual(empty.normalized(), empty)
    }
}
