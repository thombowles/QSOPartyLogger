import UniformTypeIdentifiers
import XCTest
@testable import QSOPartyLogger

/// ⌘E must put a real `.adi` file on disk for every party.
///
/// The save panel behind `fileExporter` only keeps a filename whose extension
/// belongs to one of its allowed content types; anything else gets an allowed
/// extension appended. Both exports used to go through `.plainText`, and no
/// type conforming to plain text claims `adi` — on a machine with SmartSDR
/// installed the extension even resolves to its non-text
/// `de.roskosch.smartsdr.adilog` — so "KE5CW.adi" came back "KE5CW.adi.txt"
/// while Cabrillo's "KE5CW.log" sailed through via `com.apple.log`.
///
/// Two layers fix it, tested separately on purpose. `UTType.adi` is built by
/// *shape* (extension + plain-text conformance), so the panel keeps `.adi`
/// even when this Mac's LaunchServices database is shadowed by the twenty-odd
/// registered dev builds of this app — identifier lookup was observed
/// returning a conformance-less shape here while the plist was correct. The
/// Info.plist declaration supplies the Finder description and the `.adif`
/// claim, and is asserted straight from the bundle, not through the database.
final class AdifExportTypeTests: XCTestCase {

    // MARK: The runtime type the save panel is given

    /// Whatever LaunchServices resolves, the panel type's first extension must
    /// be `adi` — that is what lets "KE5CW.adi" survive the save panel.
    func testAdifTypeClaimsAdiAsPreferredExtension() {
        XCTAssertEqual(UTType.adi.preferredFilenameExtension, "adi")
    }

    /// ADIF's ADI serialization is plain text (ADIF 3.1.4 §Data Formats);
    /// conformance is also what lets `TextExportDocument` write through it.
    func testAdifTypeIsPlainText() {
        XCTAssertTrue(UTType.adi.conforms(to: .plainText))
    }

    /// The exporter document must offer the ADIF type, or `fileExporter`
    /// cannot write through it.
    func testExportDocumentCanWriteAdif() {
        XCTAssertTrue(TextExportDocument.writableContentTypes.contains(.adi))
    }

    // MARK: The bundle declaration behind it

    /// The imported declaration must ship in the app's Info.plist with the
    /// shape `UTType.adi` is built from: plain-text conformance and both
    /// extension spellings. Read from the bundle directly so a stale
    /// LaunchServices database on the build machine cannot fake a pass (or a
    /// failure) — tests run hosted in the real app.
    func testBundleDeclaresImportedAdifType() throws {
        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations")
                as? [[String: Any]]
        )
        let adif = try XCTUnwrap(
            declarations.first {
                $0["UTTypeIdentifier"] as? String == "org.b5n.qsopartylogger.adif"
            }
        )
        XCTAssertEqual(adif["UTTypeConformsTo"] as? [String], ["public.plain-text"])
        let tags = try XCTUnwrap(adif["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["adi", "adif"])
    }
}
