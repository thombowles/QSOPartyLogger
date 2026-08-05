import Foundation

/// Re-derives DX multiplier **labels** from a freshly downloaded `cty.dat`.
///
/// ## What this can and cannot change
///
/// It changes **one thing: the prefix a DX entity is displayed as** — `DL` for
/// Germany. It cannot add an entity, remove one, change a prefix the engine
/// resolves against, or move any score. Those come from the ARRL DXCC List,
/// which is authority for them (constitution Article 1) and ships bundled;
/// `cty.dat` is a codified exception confined to this single field, and the
/// confinement is enforced here exactly as it is in `gen_dxcc.py`: a label is
/// only ever chosen *from the entity's own ARRL prefixes*.
///
/// So a new DXCC entity does **not** arrive this way. That still needs a
/// re-fetch of the ARRL list, a generator run and a release — which is the
/// point, because those are the changes that move a score and want tests.
///
/// ## Why it is worth doing at all
///
/// AD1C republishes every few days to weeks. Almost every release only adds
/// `=CALL` DXpedition entries this ignores, so in practice this is expected to
/// find nothing for years at a stretch. It exists so that when a primary
/// prefix *does* move, an operator is not reading a stale label and nobody has
/// to remember a command.
enum DXCCLabelRefresh {

    /// Why a downloaded file was refused. Refusal always means the bundled
    /// labels stay in service.
    enum Rejection: Equatable, LocalizedError {
        case tooSmall(Int)
        case entityCountMismatch(found: Int, expected: Int)
        case waeCountMismatch(found: Int)
        case noLabelsChanged
        /// A label was not one of that entity's own ARRL prefixes — the
        /// property that keeps `cty.dat` confined to display.
        case labelOutsideARRLPrefixes(entity: String, label: String)

        var errorDescription: String? {
            switch self {
            case .tooSmall(let n):
                "cty.dat was only \(n) bytes"
            case .entityCountMismatch(let found, let expected):
                "cty.dat designates \(found) primary prefixes; the ARRL list has \(expected) entities"
            case .waeCountMismatch(let found):
                "cty.dat has \(found) WAE-only records, expected 6"
            case .noLabelsChanged:
                "no label changed"
            case .labelOutsideARRLPrefixes(let entity, let label):
                "\(entity): '\(label)' is not one of its ARRL prefixes"
            }
        }
    }

    /// The smallest plausible cty.dat. The real file is ~350 KB; this only
    /// catches a truncated download or an error page served with a 200.
    static let minimumBytes = 300_000

    /// cty.dat's WAE-only records, which are not DXCC entities. They mark
    /// their primary with a leading `*`.
    static let expectedWAERecords = 6

    /// The primary prefixes cty.dat designates, one per DXCC entity.
    ///
    /// Only each record's **header line** is read — the field after the time
    /// offset. The alias lines that follow, including every `=CALL` override,
    /// are deliberately ignored: they are what nearly every release changes,
    /// and nothing here depends on them.
    static func primaryPrefixes(in text: String) -> (primaries: Set<String>, wae: Int) {
        var primaries: Set<String> = []
        var wae = 0
        for record in text.components(separatedBy: ";") {
            let header = record.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")[0]
            let fields = header.components(separatedBy: ":")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 8 else { continue }
            let primary = fields[7]
            guard !primary.isEmpty else { continue }
            if primary.hasPrefix("*") {
                wae += 1
            } else {
                primaries.insert(primary.uppercased())
            }
        }
        return (primaries, wae)
    }

    /// This entity's own ARRL prefix closest to a cty.dat primary, preferring
    /// an exact match — the same rule as `gen_dxcc.py`'s `label_for`, and the
    /// reason a label always resolves back to the entity it names.
    ///
    /// The fallback matters where cty.dat is more specific than the ARRL block
    /// (Easter I. is `CE0Y` against ARRL's `CE0`) or shaped differently
    /// (Ogasawara is `JD/o` against `JD1`).
    static func label(forPrefixes prefixes: [String], primaries: Set<String>) -> String? {
        guard !prefixes.isEmpty else { return nil }
        for p in prefixes where primaries.contains(p) { return p }
        var best: String?
        var score = -1
        for p in prefixes {
            for c in primaries {
                let n = p.commonPrefix(with: c).count
                // Ties go to the shorter key, as in the generator.
                let ties = (n == score) && (best.map { p.count < $0.count } ?? true)
                if n > score || ties {
                    best = p
                    score = n
                }
            }
        }
        return score > 0 ? best : prefixes.first
    }

    /// Entity code → new label, for the entities whose label actually moves.
    ///
    /// Throws rather than returning a partial map: a file this cannot fully
    /// account for is not one to take labels from.
    static func labels(
        fromCTY text: String,
        entities: [DXCCTable.Entity],
        byteCount: Int
    ) throws -> [String: String] {
        guard byteCount >= minimumBytes else { throw Rejection.tooSmall(byteCount) }
        let (primaries, wae) = primaryPrefixes(in: text)
        guard wae == expectedWAERecords else { throw Rejection.waeCountMismatch(found: wae) }
        guard primaries.count == entities.count else {
            throw Rejection.entityCountMismatch(found: primaries.count, expected: entities.count)
        }

        var changed: [String: String] = [:]
        for entity in entities {
            guard let new = label(forPrefixes: entity.prefixes, primaries: primaries) else {
                continue  // no ARRL prefix at all — Spratly, unreachable anyway
            }
            guard entity.prefixes.contains(new) else {
                throw Rejection.labelOutsideARRLPrefixes(entity: entity.name, label: new)
            }
            if new != entity.primaryPrefix { changed[entity.code] = new }
        }
        guard !changed.isEmpty else { throw Rejection.noLabelsChanged }
        return changed
    }
}
