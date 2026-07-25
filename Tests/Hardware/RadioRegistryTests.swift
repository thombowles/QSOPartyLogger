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

    /// `descriptor(id:)` is a lookup by id; two radios sharing one would make
    /// it silently return whichever was listed first.
    func testRadioIDsAreUnique() {
        let ids = RadioRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate radio id in RadioRegistry.all: \(ids)")
    }
}
