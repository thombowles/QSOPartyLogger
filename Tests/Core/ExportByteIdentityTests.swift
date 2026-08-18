// Tests/Core/ExportByteIdentityTests.swift
import XCTest
@testable import QSOPartyLogger

/// Cabrillo and ADIF for the fixture logs are pinned byte-for-byte in
/// `Tests/Fixtures/Exports`, recorded from the exporters as they were before
/// the engine switch. Re-record only with `TEST_RUNNER_QPL_RECORD_EXPORTS=1`,
/// and only when a sponsor's own template says the bytes should change.
final class ExportByteIdentityTests: XCTestCase {
    /// Where the recording test writes: the sandboxed test host cannot touch
    /// the source tree, so the files land in its container's temp folder
    /// (`~/Library/Containers/org.b5n.QSOPartyLogger/Data/tmp/QPLRecord/Exports`)
    /// and the shell copies them into `Tests/Fixtures/Exports`.
    static let recordDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("QPLRecord/Exports", isDirectory: true)

    private func fixtureText(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext),
                                "missing fixture \(name).\(ext) — record with TEST_RUNNER_QPL_RECORD_EXPORTS=1")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes every fixture's Cabrillo and ADIF into `recordDirectory`.
    func testRecordFixturesWhenAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QPL_RECORD_EXPORTS"] == "1", "recording is opt-in")
        try? FileManager.default.removeItem(at: Self.recordDirectory)
        try FileManager.default.createDirectory(at: Self.recordDirectory, withIntermediateDirectories: true)
        for f in try ExportFixtures.all() {
            let score = ScoreEngine.score(log: f.log, party: f.party)
            try CabrilloExporter.export(log: f.log, party: f.party, score: score)
                .write(to: Self.recordDirectory.appendingPathComponent("\(f.name).log"), atomically: true, encoding: .utf8)
            try AdifExporter.export(log: f.log, party: f.party)
                .write(to: Self.recordDirectory.appendingPathComponent("\(f.name).adi"), atomically: true, encoding: .utf8)
        }
        print("QPL_RECORD_DIR=\(Self.recordDirectory.path)")
    }

    func testCabrilloIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            let score = ScoreEngine.score(log: f.log, party: f.party)
            let actual = CabrilloExporter.export(log: f.log, party: f.party, score: score)
            let expected = try fixtureText(f.name, "log")
            XCTAssertEqual(actual, expected, f.name)
            XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "\(f.name): bytes differ")
        }
    }

    func testAdifIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            let actual = AdifExporter.export(log: f.log, party: f.party)
            let expected = try fixtureText(f.name, "adi")
            XCTAssertEqual(actual, expected, f.name)
            XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "\(f.name): bytes differ")
        }
    }

    func testCabrilloOnTheModelIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            let contest = try PartyLowering.lower(f.party)
            let score = ScoreEngine.score(log: f.log, contest: contest)
            XCTAssertEqual(CabrilloExporter.export(log: f.log, contest: contest, score: score), try fixtureText(f.name, "log"), f.name)
        }
    }

    func testAdifOnTheModelIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            XCTAssertEqual(AdifExporter.export(log: f.log, contest: try PartyLowering.lower(f.party)), try fixtureText(f.name, "adi"), f.name)
        }
    }

    func testFixturesCoverEveryShape() throws {
        XCTAssertEqual(try ExportFixtures.all().map(\.name), [
            "ksqp-inside-county-line", "ksqp-outside", "ksqp-outside-dx", "cqp-inside-serials", "naqpcw-name",
            "skeeter-member", "paqp-inside-sections", "sevenqp-inside-multistate", "warun-inside-prefix-dx", "mdc-inside-no-rst",
            "ksqp-outside-phone",
        ])
    }
}
