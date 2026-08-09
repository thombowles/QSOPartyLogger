import XCTest
@testable import QSOPartyLogger

/// Article 10 keeps model names, radio ids, driver types and model-specific
/// constants out of `Sources/App` and `Sources/UI`, so the app layer's radio
/// defaults come from the registry instead. These are the half of that article
/// its `grep` cannot enforce: the check matches *names*, so a bare `4992` or
/// `38400` in the UI layer never appears in its output.
final class RadioRegistryTests: XCTestCase {

    // MARK: The defaults the app layer asks for

    /// `AppSettings.init` uses this instead of naming a model. A typo here
    /// leaves a fresh install pointed at a radio that does not exist, and
    /// `RadioController.connect` refuses it with "Unknown radio".
    func testDefaultRadioIDResolvesToADescriptor() {
        XCTAssertNotNil(
            RadioRegistry.descriptor(id: RadioRegistry.defaultRadioID),
            "defaultRadioID '\(RadioRegistry.defaultRadioID)' is not in the catalog"
        )
    }

    /// Starting value for the shared `tcpPort` preference, and the number the
    /// port field's help text quotes.
    func testDefaultNetworkPortComesFromTheFirstNetworkRadio() {
        XCTAssertEqual(
            RadioRegistry.defaultNetworkPort,
            RadioRegistry.all.compactMap(\.defaultNetworkPort).first
        )
        XCTAssertNotNil(
            RadioRegistry.defaultNetworkPort,
            "no network radio in the catalog — the port field would start at 0"
        )
    }

    /// Starting value for the shared `baudRate` preference. `connect` opens
    /// the serial port at exactly this rate, so it must be a rate the default
    /// radio actually accepts — there is no range check downstream.
    func testDefaultBaudIsARateTheDefaultRadioAccepts() {
        let defaultRadio = RadioRegistry.descriptor(id: RadioRegistry.defaultRadioID)
        XCTAssertEqual(RadioRegistry.defaultBaud, defaultRadio?.defaultBaud)
        XCTAssertTrue(
            defaultRadio?.baudRates.contains(RadioRegistry.defaultBaud) ?? false,
            "defaultBaud \(RadioRegistry.defaultBaud) is not offered by \(RadioRegistry.defaultRadioID)"
        )
    }

    // MARK: Descriptor contract

    /// `defaultNetworkPort` is the descriptor's answer to "which port?", so it
    /// exists exactly when the radio is reached over the network.
    func testDefaultNetworkPortIsPresentExactlyForNetworkRadios() {
        for descriptor in RadioRegistry.all {
            switch descriptor.connection {
            case .network(let port):
                XCTAssertEqual(descriptor.defaultNetworkPort, port, "\(descriptor.id)")
            case .serial:
                XCTAssertNil(descriptor.defaultNetworkPort, "\(descriptor.id) is serial but offers a port")
            }
        }
    }

    /// The baud picker takes its options from here rather than hardcoding one
    /// model's rates, so a serial radio that ships none leaves an empty picker.
    func testSerialRadiosSupplyTheirOwnBaudRates() {
        for descriptor in RadioRegistry.all where descriptor.connection == .serial {
            XCTAssertFalse(descriptor.baudRates.isEmpty, "\(descriptor.id) ships no baudRates")
            XCTAssertTrue(
                descriptor.baudRates.contains(descriptor.defaultBaud),
                "\(descriptor.id) defaultBaud \(descriptor.defaultBaud) is not among its baudRates"
            )
        }
    }

    /// Article 11's structural invariant: **every radio has exactly one way to
    /// send CW.** A radio with key lines is keyed directly and only directly;
    /// one without them keys through its own keyer and must say so by
    /// conforming to `InternalKeyerDriver`.
    ///
    /// Both failure modes are real and neither is loud on its own. A driver
    /// that offers both paths reintroduces the keyer preference this article
    /// withdrew; one that offers neither builds no sender at all, and the
    /// symptom is a radio that connects, polls, displays its frequency, and
    /// silently transmits nothing when you press F1.
    func testEveryRadioHasExactlyOneWayToSendCW() {
        for descriptor in RadioRegistry.all {
            let keysItself = descriptor.makeDriver() is any InternalKeyerDriver
            XCTAssertNotEqual(
                descriptor.supportsDirectKeying, keysItself,
                descriptor.supportsDirectKeying
                    ? "\(descriptor.id) is keyed directly, so its driver must not also be an "
                        + "InternalKeyerDriver"
                    : "\(descriptor.id) has no key lines, so its driver must be an "
                        + "InternalKeyerDriver or the radio cannot send at all"
            )
        }
    }

    /// `descriptor(id:)` is a lookup by id; two radios sharing one would make
    /// it silently return whichever was listed first.
    func testRadioIDsAreUnique() {
        let ids = RadioRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate radio id in RadioRegistry.all: \(ids)")
    }
}
