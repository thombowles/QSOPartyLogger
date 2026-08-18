import XCTest
@testable import QSOPartyLogger

final class ContestCatalogTests: XCTestCase {
    func testBundledCatalogueIsEveryPartyLowered() {
        let contests = ContestCatalog.loadBundled()
        XCTAssertEqual(contests.count, 50)                    // no v2 file ships yet
        XCTAssertEqual(Set(contests.map(\.id)), Set(PartyCatalog.loadBundled().map(\.id)))
        XCTAssertEqual(contests.map(\.name), contests.map(\.name).sorted())
    }

    func testLookupByID() {
        XCTAssertEqual(ContestCatalog.contest(id: "ksqp")?.cabrillo.contest, "KS-QSO-PARTY")
        XCTAssertNil(ContestCatalog.contest(id: "nope"))
    }

    func testDecodesAV2FileFromAFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        try FileManager.default.copyItem(at: fixture, to: dir.appendingPathComponent("cqwwcw.json"))
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        let loaded = ContestCatalog.loadUserContests(in: dir)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.compactMap { try? $0.result.get() }.map(\.id), ["cqwwcw"])
        XCTAssertTrue(loaded.contains { $0.url.lastPathComponent == "broken.json" && (try? $0.result.get()) == nil })
    }

    func testUserV2FileOverridesAPartyOfTheSameID() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json")))) as! [String: Any]
        json["id"] = "ksqp"; json["name"] = "Kansas, overridden"
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("ksqp.json"))
        let all = ContestCatalog.all(userContestsDirectory: dir)
        XCTAssertEqual(all.first { $0.id == "ksqp" }?.name, "Kansas, overridden")
        XCTAssertEqual(all.count, 50)
    }
}
