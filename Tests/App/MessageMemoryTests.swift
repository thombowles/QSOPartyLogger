import XCTest
@testable import QSOPartyLogger

/// The operator's F-key messages, remembered per party between logs — as
/// files, one per party, in the iCloud logs folder when one is chosen so the
/// other Macs see them (2026-08-16: "save those in the icloud folder, same as
/// the voice macros, so I can use them across computers"), else this Mac's
/// Application Support.
final class MessageMemoryTests: XCTestCase {

    private func scratchFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageMemoryTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private var custom: MessageSets {
        var sets = MessageSets.standard
        sets.run[0] = "CQ SKEETER {MYCALL} {MYCALL}"
        sets.phoneRun = [5, nil, nil, nil, nil, nil, nil, nil]
        sets.voiceMemoryNames[4] = "CQ long"
        return sets
    }

    func testAnUnknownPartyHasNothing() throws {
        let memory = MessageMemory(folder: try scratchFolder())
        XCTAssertNil(memory.messages(for: "skeeter"))
    }

    /// The whole set comes back — CW text, the phone mapping and the memory
    /// names alike — through a second memory on the same folder, which is
    /// what "between logs" and "on the other Mac" both mean.
    func testRemembersAWholeSetAcrossAReRead() throws {
        let folder = try scratchFolder()
        try MessageMemory(folder: folder).remember(custom, for: "skeeter")
        XCTAssertEqual(MessageMemory(folder: folder).messages(for: "skeeter"), custom)
    }

    /// One readable JSON file per party — `Messages/skeeter.json` — so iCloud
    /// syncs and merges parties independently and a person can read it.
    func testOneReadableFilePerParty() throws {
        let folder = try scratchFolder()
        let memory = MessageMemory(folder: folder)
        try memory.remember(custom, for: "skeeter")
        let file = folder.appendingPathComponent("skeeter.json")
        XCTAssertEqual(memory.fileURL(partyID: "skeeter"), file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("CQ SKEETER {MYCALL} {MYCALL}"), text)
        XCTAssertTrue(text.contains("\n"), "pretty-printed, not one line")
    }

    func testPartiesAreIndependent() throws {
        let memory = MessageMemory(folder: try scratchFolder())
        try memory.remember(custom, for: "skeeter")
        try memory.remember(.standard, for: "ksqp")
        XCTAssertEqual(memory.messages(for: "skeeter"), custom)
        XCTAssertEqual(memory.messages(for: "ksqp"), .standard)
        XCTAssertNil(memory.messages(for: "cqp"))
    }

    func testRememberingAgainReplaces() throws {
        let memory = MessageMemory(folder: try scratchFolder())
        try memory.remember(.standard, for: "skeeter")
        try memory.remember(custom, for: "skeeter")
        XCTAssertEqual(memory.messages(for: "skeeter"), custom)
    }

    func testForgetting() throws {
        let memory = MessageMemory(folder: try scratchFolder())
        try memory.remember(custom, for: "skeeter")
        try memory.remember(.standard, for: "ksqp")
        try memory.forget("skeeter")
        XCTAssertNil(memory.messages(for: "skeeter"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: memory.fileURL(partyID: "skeeter").path))
        XCTAssertEqual(memory.messages(for: "ksqp"), .standard, "forgetting one leaves the rest")
        try memory.forget("skeeter")  // twice is fine
    }

    /// A hand-edited or half-synced file must never take the memory down with
    /// it: unreadable reads as nothing remembered, and the next save writes
    /// over it.
    func testUnreadableFileReadsAsEmptyAndIsOverwritten() throws {
        let folder = try scratchFolder()
        let memory = MessageMemory(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: memory.fileURL(partyID: "skeeter"))
        XCTAssertNil(memory.messages(for: "skeeter"))
        try memory.remember(custom, for: "skeeter")
        XCTAssertEqual(memory.messages(for: "skeeter"), custom)
    }

    /// Party ids are file names: only what the catalogue's own ids use.
    func testAnInvalidPartyIDIsRefused() throws {
        let folder = try scratchFolder()
        let memory = MessageMemory(folder: folder)
        XCTAssertThrowsError(try memory.remember(custom, for: "../escape"))
        XCTAssertNil(memory.messages(for: "../escape"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "nothing was written")
    }

    /// Sets saved before an iCloud folder was chosen follow it — moved once,
    /// whole, never overwriting a set the folder already has (the same rule
    /// as the voice recordings' `adoptSets`).
    func testAdoptsLegacySetsWithoutOverwriting() throws {
        let legacy = MessageMemory(folder: try scratchFolder())
        try legacy.remember(custom, for: "ksqp")
        try legacy.remember(custom, for: "skeeter")
        let cloud = MessageMemory(folder: try scratchFolder())
        try cloud.remember(.standard, for: "skeeter")

        XCTAssertEqual(try cloud.adoptSets(from: legacy), ["ksqp"])
        XCTAssertEqual(cloud.messages(for: "ksqp"), custom, "moved")
        XCTAssertNil(legacy.messages(for: "ksqp"), "moved, not copied")
        XCTAssertEqual(cloud.messages(for: "skeeter"), .standard, "the folder's own set wins")
        XCTAssertEqual(legacy.messages(for: "skeeter"), custom, "and the legacy copy is left alone")
        XCTAssertEqual(try cloud.adoptSets(from: legacy), [], "a second adoption moves nothing")
    }

    /// With no legacy folder at all there is nothing to adopt, and no error.
    func testAdoptingFromNowhereIsNothing() throws {
        let cloud = MessageMemory(folder: try scratchFolder())
        XCTAssertEqual(try cloud.adoptSets(from: MessageMemory(folder: try scratchFolder())), [])
    }
}

/// The app's memory follows the iCloud logs folder the way `VoiceStore` does:
/// its `Messages` subfolder when a folder is chosen, this Mac's Application
/// Support otherwise — decided at each use, so a folder chosen mid-session is
/// followed at once.
final class MessageMemoryLocationTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageMemoryLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark: Data
        do {
            bookmark = try folder.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw XCTSkip("cannot mint security-scoped bookmark in this environment: \(error)")
        }
        // Into the redirected test suite, never `.standard` (see CloudMirrorTests).
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

    func testTheAppsMemoryLivesInTheCloudFoldersMessagesSubfolder() throws {
        XCTAssertEqual(
            MessageMemory.standard.folder.standardizedFileURL,
            folder.appendingPathComponent("Messages", isDirectory: true).standardizedFileURL
        )
    }

    func testWithNoCloudFolderTheAppsMemoryIsThisMacs() throws {
        Preferences.store.removeObject(forKey: "iCloudFolderBookmark")
        CloudMirror._resetHeldAccessForTesting()
        XCTAssertEqual(MessageMemory.standard.folder, MessageMemory.defaultFolder)
        XCTAssertTrue(MessageMemory.defaultFolder.path.hasSuffix("QSOPartyLogger/Messages"))
    }

    /// Reading the folder moves nothing; adoption is its own step, and it
    /// brings this Mac's sets into the cloud folder once, keeping the
    /// folder's own. Both "Macs" are temp folders here — the real
    /// Application Support is never touched by a test.
    func testAdoptionBringsThisMacsSetsIntoTheCloudFolderOnce() throws {
        let thisMac = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageMemoryLocationTests-thisMac-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: thisMac) }
        var local = MessageSets.standard
        local.run[0] = "CQ FROM THIS MAC {MYCALL}"
        try MessageMemory(folder: thisMac).remember(local, for: "ksqp")
        try MessageMemory(folder: thisMac).remember(local, for: "skeeter")
        let cloud = MessageMemory(folder: folder.appendingPathComponent("Messages", isDirectory: true))
        try cloud.remember(.standard, for: "skeeter")

        let memory = MessageMemory(followingCloudSettingWithThisMacFolder: thisMac)
        XCTAssertEqual(memory.folder.standardizedFileURL, cloud.folder.standardizedFileURL)
        XCTAssertNil(cloud.messages(for: "ksqp"), "resolving the folder moved nothing")

        XCTAssertEqual(try memory.adoptThisMacsSetsIfNeeded(), ["ksqp"])
        XCTAssertEqual(memory.messages(for: "ksqp"), local, "moved into the cloud folder")
        XCTAssertEqual(memory.messages(for: "skeeter"), .standard, "the folder's own set wins")
        XCTAssertNil(MessageMemory(folder: thisMac).messages(for: "ksqp"), "moved, not copied")
    }

    /// With no cloud folder there is nothing to adopt into.
    func testAdoptionWithNoCloudFolderMovesNothing() throws {
        Preferences.store.removeObject(forKey: "iCloudFolderBookmark")
        CloudMirror._resetHeldAccessForTesting()
        let thisMac = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageMemoryLocationTests-thisMac-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: thisMac) }
        try MessageMemory(folder: thisMac).remember(.standard, for: "ksqp")
        let memory = MessageMemory(followingCloudSettingWithThisMacFolder: thisMac)
        XCTAssertEqual(try memory.adoptThisMacsSetsIfNeeded(), [])
        XCTAssertEqual(memory.messages(for: "ksqp"), .standard, "still read from this Mac")
    }
}
