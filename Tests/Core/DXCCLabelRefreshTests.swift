import XCTest
@testable import QSOPartyLogger

/// The automatic cty.dat check, driven entirely by scripted answers — no
/// network, per constitution Article 5.
final class DXCCLabelRefreshTests: XCTestCase {

    // MARK: A cty.dat, small enough to read and shaped like the real one

    /// Two DXCC records and one WAE-only record, in cty.dat's own layout:
    /// name, CQ, ITU, continent, lat, lon, offset, **primary prefix**, then
    /// alias lines terminated by ";".
    private func cty(germany: String = "DL", waeCount: Int = 6) -> String {
        var out = """
        Fed. Rep. of Germany:     14:  28:  EU:   51.00:   -10.00:    -1.0:  \(germany):
            DA,DB,DC,DD,DE,DF,DG,DH,DI,DJ,DK,DL,DM,DN,DO,DP,DQ,DR,=DA0BHV/LH;
        England:                  14:  27:  EU:   52.00:    -1.00:    -0.0:  G:
            G,GX,M,=G0ABC/P;
        """
        for i in 0..<waeCount {
            out += "\nWAE Region \(i):           14:  27:  EU:   50.00:    -1.00:    -1.0:  *WA\(i):\n    WA\(i);"
        }
        return out
    }

    private func entities() -> [DXCCTable.Entity] {
        [
            .init(code: "230", name: "Germany", continent: "EU",
                  prefixes: ["DA", "DB", "DC", "DD", "DE", "DF", "DG", "DH", "DI",
                             "DJ", "DK", "DL", "DM", "DN", "DO", "DP", "DQ", "DR"],
                  primaryPrefix: "DL"),
            .init(code: "223", name: "England", continent: "EU",
                  prefixes: ["G", "GX", "M"], primaryPrefix: "G"),
        ]
    }

    private let bytes = DXCCLabelRefresh.minimumBytes

    // MARK: Parsing

    func testReadsOnlyThePrimaryPrefixAndCountsWAERecords() {
        let (primaries, wae) = DXCCLabelRefresh.primaryPrefixes(in: cty())
        XCTAssertEqual(primaries, ["DL", "G"])
        XCTAssertEqual(wae, 6, "WAE-only records mark their primary with '*'")
        // The alias lines, and every =CALL override in them, are ignored —
        // they are what nearly every AD1C release changes.
        XCTAssertFalse(primaries.contains("DA"))
        XCTAssertFalse(primaries.contains("DJ"))
    }

    // MARK: The label rule, which must match gen_dxcc.py's

    func testLabelPrefersAnExactPrimaryThenTheClosestARRLKey() {
        let g = entities()[0].prefixes
        XCTAssertEqual(DXCCLabelRefresh.label(forPrefixes: g, primaries: ["DL"]), "DL")
        // cty.dat more specific than the ARRL block: CE0Y -> CE0.
        XCTAssertEqual(DXCCLabelRefresh.label(forPrefixes: ["CE0"], primaries: ["CE0Y"]), "CE0")
        // ...or shaped differently: JD/o -> JD1.
        XCTAssertEqual(DXCCLabelRefresh.label(forPrefixes: ["JD1"], primaries: ["JD/O"]), "JD1")
        // Ties go to the shorter key.
        XCTAssertEqual(DXCCLabelRefresh.label(forPrefixes: ["IS0", "IM0"], primaries: ["IS"]), "IS0")
        XCTAssertNil(DXCCLabelRefresh.label(forPrefixes: [], primaries: ["DL"]))
    }

    /// The same rule, run against the real bundled table, must reproduce every
    /// label the generator baked in — so the runtime path and the build-time
    /// path cannot drift apart.
    func testRuntimeRuleReproducesTheGeneratedLabels() throws {
        let table = DXCCTable.shared
        let text = try String(contentsOf: XCTUnwrap(ctyFixtureURL()), encoding: .utf8)
        let (primaries, wae) = DXCCLabelRefresh.primaryPrefixes(in: text)
        XCTAssertEqual(wae, 6)
        XCTAssertEqual(primaries.count, table.entities.count)
        for entity in table.entities where !entity.prefixes.isEmpty {
            XCTAssertEqual(
                DXCCLabelRefresh.label(forPrefixes: entity.prefixes, primaries: primaries),
                entity.primaryPrefix,
                entity.name
            )
        }
    }

    /// The committed cty.dat, read from the research folder rather than
    /// bundled — it is a build input, not a shipped resource.
    private func ctyFixtureURL() -> URL? {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { dir.deleteLastPathComponent() }
        let url = dir.appendingPathComponent("docs/research/cty.dat")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: What it refuses

    func testARefreshThatChangesNothingIsRejectedRatherThanStored() {
        XCTAssertThrowsError(
            try DXCCLabelRefresh.labels(fromCTY: cty(), entities: entities(), byteCount: bytes)
        ) { XCTAssertEqual($0 as? DXCCLabelRefresh.Rejection, .noLabelsChanged) }
    }

    func testATruncatedDownloadIsRefused() {
        XCTAssertThrowsError(
            try DXCCLabelRefresh.labels(fromCTY: cty(germany: "DA"), entities: entities(),
                                        byteCount: 1_024)
        ) { XCTAssertEqual($0 as? DXCCLabelRefresh.Rejection, .tooSmall(1_024)) }
    }

    func testAFileWithTheWrongNumberOfEntitiesIsRefused() {
        XCTAssertThrowsError(
            try DXCCLabelRefresh.labels(fromCTY: cty(), entities: entities() + [
                .init(code: "999", name: "Nowhere", continent: "EU",
                      prefixes: ["ZZ"], primaryPrefix: "ZZ"),
            ], byteCount: bytes)
        ) {
            XCTAssertEqual($0 as? DXCCLabelRefresh.Rejection,
                           .entityCountMismatch(found: 2, expected: 3))
        }
    }

    func testAFileWithTheWrongNumberOfWAERecordsIsRefused() {
        XCTAssertThrowsError(
            try DXCCLabelRefresh.labels(fromCTY: cty(waeCount: 2), entities: entities(),
                                        byteCount: bytes)
        ) { XCTAssertEqual($0 as? DXCCLabelRefresh.Rejection, .waeCountMismatch(found: 2)) }
    }

    // MARK: What it accepts, and how far it may reach

    /// A primary that really has moved is taken — and only the label moves.
    func testARealLabelChangeIsTakenAndTouchesNothingElse() throws {
        let labels = try DXCCLabelRefresh.labels(
            fromCTY: cty(germany: "DA"), entities: entities(), byteCount: bytes
        )
        XCTAssertEqual(labels, ["230": "DA"], "England is unchanged and absent")

        let updated = DXCCTable(
            source: "s", fetched: "f", entities: entities(),
            prefixes: ["DL": "230", "DJ": "230", "G": "223"],
            mergedPrefixes: [:], withoutPrefix: [:]
        ).applyingLabels(labels)

        XCTAssertEqual(updated.entities.first { $0.code == "230" }?.primaryPrefix, "DA")
        // Everything the engine actually scores from is untouched.
        XCTAssertEqual(updated.prefixes, ["DL": "230", "DJ": "230", "G": "223"])
        XCTAssertEqual(updated.entities.count, 2)
        XCTAssertEqual(updated.entities.first { $0.code == "230" }?.prefixes,
                       entities()[0].prefixes)
        XCTAssertEqual(updated.entity(forCallsign: "DJ2BB")?.code, "230",
                       "resolution is unaffected")
    }

    /// The confinement that makes a second source safe: a label the entity
    /// does not own is ignored, not trusted.
    func testALabelOutsideTheEntitysOwnARRLPrefixesIsIgnored() {
        let table = DXCCTable(
            source: "s", fetched: "f", entities: entities(),
            prefixes: ["DL": "230", "G": "223"], mergedPrefixes: [:], withoutPrefix: [:]
        ).applyingLabels(["230": "ZZ"])
        XCTAssertEqual(table.entities.first { $0.code == "230" }?.primaryPrefix, "DL",
                       "ZZ is not one of Germany's ARRL prefixes")
    }

    /// It cannot introduce an entity the ARRL list does not carry.
    func testAnUnknownEntityCodeInTheOverlayIsIgnored() {
        let table = DXCCTable(
            source: "s", fetched: "f", entities: entities(),
            prefixes: ["DL": "230", "G": "223"], mergedPrefixes: [:], withoutPrefix: [:]
        ).applyingLabels(["999": "ZZ"])
        XCTAssertEqual(table.entities.count, 2)
        XCTAssertNil(table.entities.first { $0.code == "999" })
    }
}
