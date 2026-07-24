import XCTest
@testable import QSOPartyLogger

/// The keyer picker's labels come from the connected radio's descriptor, not
/// from the persisted enum value — Article 11 keeps a shared keyer setting
/// radio-neutral, so a Flex never reads "K3" while CWX is doing the sending.
final class KeyerBackendLabelTests: XCTestCase {

    private var k3: RadioDescriptor {
        RadioRegistry.descriptor(id: "elecraft-k3")!
    }

    private var flex: RadioDescriptor {
        RadioRegistry.descriptor(id: "flex-6000")!
    }

    // MARK: Labels follow the connected radio

    func testInternalKeyerLabelNamesTheConnectedRadiosCommand() {
        XCTAssertEqual(
            AppSettings.KeyerBackend.radioInternal.displayName(for: k3),
            "Radio keyer (KY)"
        )
        XCTAssertEqual(
            AppSettings.KeyerBackend.radioInternal.displayName(for: flex),
            "Radio keyer (CWX)"
        )
    }

    func testInternalKeyerLabelIsNeutralWithNoRadioConnected() {
        XCTAssertEqual(
            AppSettings.KeyerBackend.radioInternal.displayName(for: nil),
            "Radio keyer"
        )
    }

    /// Direct DTR/RTS keying is timed in the app, so its label never varies.
    func testDirectKeyerLabelIsTheSameForEveryRadio() {
        XCTAssertEqual(AppSettings.KeyerBackend.direct.displayName(for: nil), "Direct DTR/RTS")
        for descriptor in RadioRegistry.all {
            XCTAssertEqual(
                AppSettings.KeyerBackend.direct.displayName(for: descriptor),
                "Direct DTR/RTS",
                "\(descriptor.id) changed the direct-keying label"
            )
        }
    }

    /// No label the operator can actually see may name a manufacturer or model
    /// — the same rule Article 10's `grep` enforces over `Sources/App` and
    /// `Sources/UI`, applied to the strings themselves.
    func testNoDisplayedLabelNamesAManufacturer() {
        let banned = ["k3", "kx3", "kx2", "flex", "icom", "yaesu", "kenwood", "elecraft", "ci-v"]
        var labels: [String] = []
        for backend in AppSettings.KeyerBackend.allCases {
            labels.append(backend.displayName(for: nil))
            labels.append(contentsOf: RadioRegistry.all.map { backend.displayName(for: $0) })
        }
        for label in labels {
            for term in banned {
                XCTAssertFalse(
                    label.lowercased().contains(term),
                    "keyer label '\(label)' names '\(term)' — Article 11 keeps these radio-neutral"
                )
            }
        }
    }

    // MARK: Persistence is frozen

    /// The raw values are the on-disk `keyerBackend` tokens in `UserDefaults`,
    /// kept verbatim from when they doubled as labels. Changing one silently
    /// resets an existing operator's keyer choice to `.direct`.
    func testStoredDefaultsStillDecode() {
        XCTAssertEqual(AppSettings.KeyerBackend(rawValue: "Direct DTR/RTS"), .direct)
        XCTAssertEqual(AppSettings.KeyerBackend(rawValue: "K3 internal (KY)"), .radioInternal)
    }

    func testUnrecognizedStoredValueIsRejectedSoTheCallerCanDefault() {
        XCTAssertNil(AppSettings.KeyerBackend(rawValue: "Radio keyer (KY)"))
        XCTAssertNil(AppSettings.KeyerBackend(rawValue: ""))
    }

    // MARK: Registry contract

    /// Article 10: adding a radio supplies its own keyer label in its
    /// descriptor, and nothing in the app or UI layer learns the model name.
    func testEveryRadioSuppliesItsOwnKeyerLabel() {
        for descriptor in RadioRegistry.all {
            XCTAssertFalse(
                descriptor.keyerLabel.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(descriptor.id) ships no keyerLabel"
            )
        }
    }
}
