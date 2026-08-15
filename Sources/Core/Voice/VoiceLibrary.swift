import Foundation

/// The recordings on disk: one folder per party holding `voice.json` and the
/// WAVs it names, in the app's own Application Support folder — a temp dir in
/// tests. Kept per party rather than per log because a party's messages are
/// the same next year, and because eight WAVs do not belong in a JSON log
/// that autosaves on every contact.
///
/// This type moves and lists files; it never decodes audio. Reading and
/// writing samples is `AudioFileIO`'s job, one layer up.
struct VoiceLibrary: Sendable {
    let folder: URL

    /// `~/Library/Application Support/QSOPartyLogger/Voice`
    /// (container-relative when sandboxed), beside the user parties folder.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Voice", isDirectory: true)
    }

    static let sidecarName = "voice.json"

    enum LibraryError: Error, LocalizedError, Equatable {
        case invalidPartyID(String)

        var errorDescription: String? {
            switch self {
            case .invalidPartyID(let id):
                "'\(id)' is not a party id this app can keep recordings for."
            }
        }
    }

    /// Party ids are file-system path components. Only what the catalogue's
    /// own ids use — letters, digits, underscore, dash.
    static func isValidPartyID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

    static func fileName(memory: Int) -> String { "M\(memory).wav" }

    func setFolder(partyID: String) -> URL {
        folder.appendingPathComponent(partyID, isDirectory: true)
    }

    func sidecarURL(partyID: String) -> URL {
        setFolder(partyID: partyID).appendingPathComponent(Self.sidecarName)
    }

    func fileURL(partyID: String, fileName: String) -> URL {
        setFolder(partyID: partyID).appendingPathComponent(fileName)
    }

    private func validated(_ partyID: String) throws {
        guard Self.isValidPartyID(partyID) else { throw LibraryError.invalidPartyID(partyID) }
    }

    /// Empty when the party has no folder or no sidecar. A sidecar that exists
    /// but cannot be read throws — the WAVs beside it are the operator's work,
    /// and are never replaced by an empty set on a read failure.
    func load(partyID: String) throws -> VoiceMessageSet {
        try validated(partyID)
        let url = sidecarURL(partyID: partyID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            requestDownloadIfPlaceholder(url)
            return VoiceMessageSet()
        }
        return try JSONDecoder.voice.decode(VoiceMessageSet.self, from: Data(contentsOf: url))
    }

    func save(_ set: VoiceMessageSet, partyID: String) throws {
        try validated(partyID)
        try FileManager.default.createDirectory(at: setFolder(partyID: partyID), withIntermediateDirectories: true)
        try JSONEncoder.voice.encode(set).write(to: sidecarURL(partyID: partyID), options: .atomic)
    }

    /// Deletes the memory's file and its entry. A memory that is not there is
    /// already removed.
    func remove(memory: Int, partyID: String) throws {
        var set = try load(partyID: partyID)
        guard let clip = set[memory] else { return }
        let url = fileURL(partyID: partyID, fileName: clip.fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        set[memory] = nil
        try save(set, partyID: partyID)
    }

    /// Copies every memory `destination` lacks from `source` — file and entry
    /// — and returns how many. Existing recordings are never overwritten, and
    /// a source entry whose file is missing is skipped rather than copied as
    /// a dangling entry.
    func copyMissing(from source: String, to destination: String) throws -> Int {
        let src = try load(partyID: source)
        var dst = try load(partyID: destination)
        var copied = 0
        for (memory, clip) in src.clips.sorted(by: { $0.key < $1.key }) where dst[memory] == nil {
            let srcURL = fileURL(partyID: source, fileName: clip.fileName)
            guard FileManager.default.fileExists(atPath: srcURL.path) else { continue }
            let dstURL = fileURL(partyID: destination, fileName: Self.fileName(memory: memory))
            try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            var copy = clip
            copy.fileName = Self.fileName(memory: memory)
            dst[memory] = copy
            copied += 1
        }
        if copied > 0 { try save(dst, partyID: destination) }
        return copied
    }

    /// Move every party set `legacy` has and this library lacks — files and
    /// sidecar, whole — and return the ids moved, sorted. Sets already here
    /// are left alone, and so are the legacy copies of those. This is how
    /// recordings made before an iCloud folder was chosen follow it, once.
    func adoptSets(from legacy: VoiceLibrary) throws -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: legacy.folder.path)) ?? []
        var moved: [String] = []
        for partyID in names.filter({ Self.isValidPartyID($0) }).sorted() {
            let source = legacy.setFolder(partyID: partyID)
            guard FileManager.default.fileExists(atPath: legacy.sidecarURL(partyID: partyID).path),
                  !FileManager.default.fileExists(atPath: setFolder(partyID: partyID).path) else { continue }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: setFolder(partyID: partyID))
            moved.append(partyID)
        }
        return moved
    }

    /// iCloud Drive may hold a not-yet-downloaded placeholder where a file
    /// should be. Ask for it; the next load or render finds it. Best effort —
    /// a folder that is not in iCloud simply has no placeholders.
    func requestDownloadIfPlaceholder(_ url: URL) {
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
        guard FileManager.default.fileExists(atPath: placeholder.path) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Party ids with at least one recording, sorted — the "Copy from…" menu.
    func partiesWithRecordings() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { Self.isValidPartyID($0) }
            .filter { !((try? load(partyID: $0))?.isEmpty ?? true) }
            .sorted()
    }
}

extension JSONEncoder {
    /// Pretty, sorted, ISO dates — the sidecar is meant to be read by a person.
    static var voice: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var voice: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
