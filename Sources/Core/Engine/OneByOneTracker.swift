import Foundation

/// KSQP 1x1 word-spelling tracker. Words are spelled from the suffix letters of
/// worked 1x1 calls. Duplicate letters within a word require distinct calls;
/// calls may be reused across words; the wildcard call fills exactly one
/// missing letter across all words.
enum OneByOneTracker {

    struct WordProgress: Equatable {
        let word: String
        /// One entry per letter of `word`: the call credited, or nil if unfilled.
        let assignments: [String?]

        var complete: Bool { !assignments.contains(nil) }
        var filledCount: Int { assignments.compactMap { $0 }.count }
    }

    /// 1x1 format: prefix letter K/N/W, one digit, one suffix letter (e.g. "W0K").
    static func isOneByOne(_ call: String) -> Bool {
        let c = Array(call.uppercased())
        return c.count == 3
            && (c[0] == "K" || c[0] == "N" || c[0] == "W")
            && c[1].isNumber
            && c[2].isLetter
    }

    static func progress(
        calls: some Sequence<String>,
        config: PartyDefinition.OneByOneConfig
    ) -> [WordProgress] {
        let workedOneByOnes = Set(calls.map { $0.uppercased() }.filter(isOneByOne))
        let wildcardWorked = config.wildcard.map { wc in
            calls.contains { $0.uppercased() == wc.uppercased() }
        } ?? false

        // Group available calls by suffix letter, deterministic order.
        var callsByLetter: [Character: [String]] = [:]
        for call in workedOneByOnes.sorted() {
            callsByLetter[Array(call)[2], default: []].append(call)
        }

        var results: [WordProgress] = []
        for word in config.words {
            var used = Set<String>()
            var assignments: [String?] = []
            for letter in word.uppercased() {
                // Distinct call per duplicate letter within a word.
                if let call = callsByLetter[letter]?.first(where: { !used.contains($0) }) {
                    used.insert(call)
                    assignments.append(call)
                } else {
                    assignments.append(nil)
                }
            }
            results.append(WordProgress(word: word.uppercased(), assignments: assignments))
        }

        // Wildcard fills one missing letter, in the word closest to completion.
        if wildcardWorked, let wildcard = config.wildcard?.uppercased() {
            let candidates = results.indices
                .filter { !results[$0].complete }
                .sorted { a, b in
                    let gapsA = results[a].assignments.filter { $0 == nil }.count
                    let gapsB = results[b].assignments.filter { $0 == nil }.count
                    return gapsA != gapsB ? gapsA < gapsB : a < b
                }
            if let idx = candidates.first {
                var assignments = results[idx].assignments
                if let gap = assignments.firstIndex(of: nil) {
                    assignments[gap] = wildcard
                    results[idx] = WordProgress(word: results[idx].word, assignments: assignments)
                }
            }
        }
        return results
    }
}
