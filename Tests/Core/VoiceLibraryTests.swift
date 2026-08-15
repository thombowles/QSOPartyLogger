import XCTest
@testable import QSOPartyLogger

/// The per-party set on disk — sidecar and files under a temp folder. Nothing
/// here decodes audio; the "WAVs" are four bytes, because the library moves
/// files and never reads them.
final class VoiceLibraryTests: XCTestCase {
    private var folder: URL!
    private var library: VoiceLibrary!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceLibraryTests-\(UUID().uuidString)", isDirectory: true)
        library = VoiceLibrary(folder: folder)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func clip(_ n: Int, duration: TimeInterval = 2) -> VoiceClip {
        VoiceClip(fileName: VoiceLibrary.fileName(memory: n), duration: duration,
                  trimStart: 0, trimEnd: duration, gainDB: 0, recordedAt: Date(timeIntervalSince1970: 0))
    }

    private func writeFakeWAV(partyID: String, memory: Int) throws {
        let url = library.fileURL(partyID: partyID, fileName: VoiceLibrary.fileName(memory: memory))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
    }

    func testMissingPartyLoadsAnEmptySet() throws {
        let set = try library.load(partyID: "txqp")
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.version, VoiceMessageSet.currentVersion)
    }

    func testSaveThenLoadRoundTripsAndKeysAreMemoryNumbers() throws {
        var set = VoiceMessageSet()
        set[1] = clip(1)
        set[5] = clip(5, duration: 3.5)
        try library.save(set, partyID: "txqp")
        let back = try library.load(partyID: "txqp")
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.recordedMemories, [1, 5])
        // Human-readable sidecar: memory numbers are JSON object keys, not an array.
        let json = try String(contentsOf: library.sidecarURL(partyID: "txqp"), encoding: .utf8)
        XCTAssertTrue(json.contains("\"5\""), json)
    }

    func testCorruptSidecarThrowsRatherThanReplacing() throws {
        try FileManager.default.createDirectory(at: library.setFolder(partyID: "alqp"), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: library.sidecarURL(partyID: "alqp"))
        XCTAssertThrowsError(try library.load(partyID: "alqp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.sidecarURL(partyID: "alqp").path),
                      "the operator's file is never deleted on a read failure")
    }

    func testRemoveDeletesTheFileAndTheEntry() throws {
        var set = VoiceMessageSet(); set[2] = clip(2)
        try library.save(set, partyID: "txqp")
        try writeFakeWAV(partyID: "txqp", memory: 2)
        try library.remove(memory: 2, partyID: "txqp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.fileURL(partyID: "txqp", fileName: "M2.wav").path))
        XCTAssertNil(try library.load(partyID: "txqp")[2])
        // Removing what is not there is not an error.
        XCTAssertNoThrow(try library.remove(memory: 7, partyID: "txqp"))
    }

    func testCopyMissingFillsOnlyTheGaps() throws {
        var src = VoiceMessageSet(); src[1] = clip(1); src[3] = clip(3); src[4] = clip(4)
        try library.save(src, partyID: "alqp")
        for m in [1, 3, 4] { try writeFakeWAV(partyID: "alqp", memory: m) }
        var dst = VoiceMessageSet(); dst[3] = clip(3, duration: 9)   // already recorded here
        try library.save(dst, partyID: "txqp")

        let copied = try library.copyMissing(from: "alqp", to: "txqp")
        XCTAssertEqual(copied, 2)
        let after = try library.load(partyID: "txqp")
        XCTAssertEqual(after.recordedMemories, [1, 3, 4])
        XCTAssertEqual(after[3]?.duration, 9, "an existing recording is never overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(partyID: "txqp", fileName: "M1.wav").path))
        // A source entry whose file is missing is skipped, not copied as a dangling entry.
        var src2 = VoiceMessageSet(); src2[8] = clip(8)
        try library.save(src2, partyID: "nyqp")
        XCTAssertEqual(try library.copyMissing(from: "nyqp", to: "txqp"), 0)
    }

    func testPartiesWithRecordingsIsSortedAndSkipsEmptySets() throws {
        var a = VoiceMessageSet(); a[1] = clip(1)
        try library.save(a, partyID: "txqp")
        try library.save(a, partyID: "alqp")
        try library.save(VoiceMessageSet(), partyID: "empty")
        XCTAssertEqual(library.partiesWithRecordings(), ["alqp", "txqp"])
        XCTAssertEqual(VoiceLibrary(folder: folder.appendingPathComponent("nowhere")).partiesWithRecordings(), [])
    }

    func testPartyIDsAreValidatedBeforeTouchingDisk() {
        XCTAssertTrue(VoiceLibrary.isValidPartyID("nyqp"))
        XCTAssertTrue(VoiceLibrary.isValidPartyID("7qp_2026-x"))
        XCTAssertFalse(VoiceLibrary.isValidPartyID(""))
        XCTAssertFalse(VoiceLibrary.isValidPartyID("../etc"))
        XCTAssertFalse(VoiceLibrary.isValidPartyID("a b"))
        XCTAssertThrowsError(try library.load(partyID: "../x"))
        XCTAssertThrowsError(try library.save(VoiceMessageSet(), partyID: ""))
    }

    func testClipTrimmedDuration() {
        var c = clip(1, duration: 4)
        c.trimStart = 0.5; c.trimEnd = 3
        XCTAssertEqual(c.trimmedDuration, 2.5, accuracy: 1e-9)
        c.trimEnd = 0.2
        XCTAssertEqual(c.trimmedDuration, 0)
    }

    func testTheSettingEnumsRoundTripTheirTokens() {
        XCTAssertEqual(PhoneMessageSource(rawValue: "recordings"), .recordings)
        XCTAssertEqual(PhoneMessageSource(rawValue: "radioMemories"), .radioMemories)
        XCTAssertEqual(VoicePTTMode(rawValue: "radioCommand"), .radioCommand)
        XCTAssertEqual(VoicePTTMode(rawValue: "vox"), .vox)
    }
}
