import Foundation

/// The operator's F-key messages, remembered per party between logs — and
/// between Macs.
///
/// Messages live in the log file (`ContestLog.messages`), so each contest
/// window carries its own — but a *new* log for a party the operator had
/// already customised started from the party defaults, and the work was
/// redone every year (2026-08-16: "make sure CW memories are remembered per
/// contest"). So the set saved last for each party is kept as a file, one per
/// party — `Messages/skeeter.json` — in the **iCloud logs folder** when one is
/// chosen, exactly where the voice recordings go (`VoiceStore`, `Voice/`), so
/// the other Macs start from the same set ("save those in the icloud folder,
/// same as the voice macros, so I can use them across computers"); on this
/// Mac's Application Support otherwise. One file per party rather than one
/// dictionary, so iCloud syncs and resolves each party on its own.
///
/// Written by `LogDocument.updateMessages` (the editor's Save, and its undo);
/// read by `LogDocument.updateStation` when a log takes on a party whose set
/// it has not customised itself. Injected into the document by the window
/// (`.standard`), nil in tests — see `LogDocument.messageMemory`. Party ids
/// are file names, so only the catalogue's own shape is accepted
/// (`VoiceLibrary.isValidPartyID`).
struct MessageMemory {
    /// Where the files are. The app's memory follows the iCloud folder
    /// setting at every use, so a folder chosen mid-session is followed at
    /// once — falling back to this Mac's own folder; a fixed folder is for
    /// tests.
    enum Location {
        case fixed(URL)
        case followCloudSetting(thisMac: URL)
    }

    let location: Location

    /// The app's: the iCloud logs folder's `Messages` subfolder when one is
    /// chosen, else `defaultFolder`.
    static let standard = MessageMemory(location: .followCloudSetting(thisMac: defaultFolder))

    /// The subfolder of the iCloud logs folder, beside `Voice`.
    static let cloudSubfolderName = "Messages"

    /// `~/Library/Application Support/QSOPartyLogger/Messages`
    /// (container-relative when sandboxed), beside the voice recordings'.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Messages", isDirectory: true)
    }

    init(folder: URL) {
        location = .fixed(folder)
    }

    /// The app's shape with this Mac's folder chosen by the caller — for a
    /// test of the cloud-following behaviour that must not touch the real
    /// Application Support.
    init(followingCloudSettingWithThisMacFolder thisMac: URL) {
        location = .followCloudSetting(thisMac: thisMac)
    }

    private init(location: Location) {
        self.location = location
    }

    /// The folder in use right now. Pure — reading it moves nothing; see
    /// `adoptThisMacsSetsIfNeeded`.
    var folder: URL {
        switch location {
        case .fixed(let url):
            url
        case .followCloudSetting(let thisMac):
            CloudMirror.activeFolder()?
                .appendingPathComponent(Self.cloudSubfolderName, isDirectory: true) ?? thisMac
        }
    }

    /// The iCloud folder is chosen (now, or before this launch): bring along,
    /// once, every set this Mac saved before it was — moved whole, never
    /// overwriting a set the folder already has (the voice recordings'
    /// `adoptSets` rule) — so nothing is lost by choosing a folder late.
    /// Nothing to do with no folder chosen, or for a fixed memory. Returns the
    /// party ids moved.
    @discardableResult
    func adoptThisMacsSetsIfNeeded() throws -> [String] {
        guard case .followCloudSetting(let thisMac) = location,
              let cloud = CloudMirror.activeFolder() else { return [] }
        let cloudMemory = MessageMemory(
            folder: cloud.appendingPathComponent(Self.cloudSubfolderName, isDirectory: true))
        return try cloudMemory.adoptSets(from: MessageMemory(folder: thisMac))
    }

    enum MemoryError: Error, LocalizedError, Equatable {
        case invalidPartyID(String)

        var errorDescription: String? {
            switch self {
            case .invalidPartyID(let id):
                "'\(id)' is not a party id this app can keep messages for."
            }
        }
    }

    func fileURL(partyID: String) -> URL {
        folder.appendingPathComponent(partyID).appendingPathExtension("json")
    }

    private func validated(_ partyID: String) throws {
        guard VoiceLibrary.isValidPartyID(partyID) else { throw MemoryError.invalidPartyID(partyID) }
    }

    /// The set saved last for `partyID`, or nil when none was — or when the
    /// file is unreadable: a hand-edited or half-synced file must never take
    /// the memory down with it, and the next save writes over it. A file
    /// iCloud has not brought down yet is asked for, so the next look finds
    /// it.
    func messages(for partyID: String) -> MessageSets? {
        guard VoiceLibrary.isValidPartyID(partyID) else { return nil }
        let url = fileURL(partyID: partyID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            requestDownloadIfPlaceholder(url)
            return nil
        }
        return (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(MessageSets.self, from: $0) }
    }

    func remember(_ sets: MessageSets, for partyID: String) throws {
        try validated(partyID)
        let url = fileURL(partyID: partyID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Self.encoder.encode(sets).write(to: url, options: .atomic)
    }

    /// A party that is not there is already forgotten.
    func forget(_ partyID: String) throws {
        try validated(partyID)
        let url = fileURL(partyID: partyID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Move every party file `legacy` has and this memory lacks, and return
    /// the ids moved, sorted. Files already here are left alone, and so are
    /// the legacy copies of those.
    func adoptSets(from legacy: MessageMemory) throws -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: legacy.folder.path)) ?? []
        var moved: [String] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let partyID = String(name.dropLast(".json".count))
            guard VoiceLibrary.isValidPartyID(partyID),
                  !FileManager.default.fileExists(atPath: fileURL(partyID: partyID).path) else { continue }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: legacy.fileURL(partyID: partyID),
                                             to: fileURL(partyID: partyID))
            moved.append(partyID)
        }
        return moved
    }

    /// iCloud Drive may hold a not-yet-downloaded placeholder where the file
    /// should be. Ask for it; the next look finds it. Best effort — a folder
    /// that is not in iCloud simply has no placeholders.
    private func requestDownloadIfPlaceholder(_ url: URL) {
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
        guard FileManager.default.fileExists(atPath: placeholder.path) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Pretty and sorted — the file is meant to be read by a person, and to
    /// diff cleanly when iCloud shows two Macs' versions side by side.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
