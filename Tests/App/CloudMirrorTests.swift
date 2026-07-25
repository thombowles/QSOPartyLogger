import XCTest
@testable import QSOPartyLogger

final class CloudMirrorTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudMirrorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The app container's temp dir is already accessible, so a
        // security-scoped bookmark for it can be minted inside the test host.
        let bookmark: Data
        do {
            bookmark = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw XCTSkip("cannot mint security-scoped bookmark in this environment: \(error)")
        }
        // Into the redirected test suite, never `.standard` — the teardown
        // below removes these keys, which against the real domain would delete
        // the operator's configured iCloud logs folder.
        Preferences.store.set(bookmark, forKey: "iCloudFolderBookmark")
        Preferences.store.set(true, forKey: "iCloudMirrorEnabled")
        CloudMirror._resetHeldAccessForTesting()
    }

    override func tearDownWithError() throws {
        Preferences.store.removeObject(forKey: "iCloudFolderBookmark")
        Preferences.store.removeObject(forKey: "iCloudMirrorEnabled")
        CloudMirror._resetHeldAccessForTesting()
        try? FileManager.default.removeItem(at: folder)
    }

    func testUniqueSaveURLAvoidsClobbering() throws {
        let first = try XCTUnwrap(CloudMirror.uniqueSaveURL(baseName: "2026-07-25 ALQP KE5CW"))
        XCTAssertEqual(first.lastPathComponent, "2026-07-25 ALQP KE5CW.qplog")
        try Data("x".utf8).write(to: first)
        let second = try XCTUnwrap(CloudMirror.uniqueSaveURL(baseName: "2026-07-25 ALQP KE5CW"))
        XCTAssertEqual(second.lastPathComponent, "2026-07-25 ALQP KE5CW 2.qplog")
    }

    func testMirrorWritesIntoFolder() throws {
        CloudMirror.mirror(data: Data("log".utf8), fileName: "2026-08-29 KSQP KE5CW")
        let target = folder.appendingPathComponent("2026-08-29 KSQP KE5CW.qplog")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "log")
    }

    func testFolderContains() throws {
        let inside = folder.appendingPathComponent("a.qplog")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("b.qplog")
        XCTAssertTrue(CloudMirror.folderContains(inside))
        XCTAssertFalse(CloudMirror.folderContains(outside))
        XCTAssertFalse(CloudMirror.folderContains(nil))
    }
}
