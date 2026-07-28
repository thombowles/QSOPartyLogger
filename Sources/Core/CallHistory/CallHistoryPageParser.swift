import Foundation

/// Reads the two n1mmwp.hamdocs.com pages the call history download needs:
/// the category listing (searched by prefix, sorted newest) and a file's own
/// page (whose CM Download Manager form carries the nonce the POST requires).
///
/// Pure and offline, like `HubSpotParser`, and with the same drift stance:
/// these are positional reads of somebody else's markup, so an unrecognized
/// page is an explicit `nil` — never a silent empty that reads as "no file
/// this year". Mechanics observed 2026-07-28; captured pages in
/// `Tests/Fixtures/CallHistory`, provenance in
/// `docs/research/n1mm_callhistory.md`.
enum CallHistoryPageParser {

    /// One row of the listing: a file revision and where its page lives.
    struct Listing: Equatable, Sendable {
        /// "QSOP_AL-2026-002.txt" — what `CallHistorySource.claims` judges.
        let filename: String
        let pageURL: String
        /// "2026-07-15" as printed. Compared for equality against the cached
        /// copy, never parsed — ordering comes from the listing's own
        /// `sort=newest`.
        let listedDate: String
    }

    /// The listing rows in page order (newest first), `[]` for a recognized
    /// listing with no matches, `nil` for a page that is not the listing —
    /// the site changed, and the caller must say so rather than shrug.
    static func parseListing(html: String) -> [Listing]? {
        guard html.range(of: "CMDM-list-view") != nil
                || html.range(of: "cmdm-search-form") != nil else { return nil }

        var out: [Listing] = []
        var remainder = Substring(html)
        while let marker = remainder.range(of: "cmdm-list-item-title") {
            // The anchor wrapping this title opened just before it; its href
            // is the file page.
            let before = remainder[..<marker.lowerBound]
            guard let href = before.range(of: "href=\"", options: .backwards),
                  let hrefEnd = before[href.upperBound...].firstIndex(of: "\"")
            else { return nil }
            let pageURL = String(before[href.upperBound..<hrefEnd])

            let afterMarker = remainder[marker.upperBound...]
            guard let titleStart = afterMarker.firstIndex(of: ">"),
                  let titleEnd = afterMarker[afterMarker.index(after: titleStart)...]
                    .firstIndex(of: "<")
            else { return nil }
            let filename = afterMarker[afterMarker.index(after: titleStart)..<titleEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let desc = afterMarker.range(of: "cmdm-list-item-desc"),
                  let dateStart = afterMarker[desc.upperBound...].firstIndex(of: ">"),
                  let dateEnd = afterMarker[afterMarker.index(after: dateStart)...]
                    .firstIndex(of: "<")
            else { return nil }
            let date = afterMarker[afterMarker.index(after: dateStart)..<dateEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !filename.isEmpty, pageURL.contains("/mmfiles/") else { return nil }
            out.append(Listing(filename: filename, pageURL: pageURL, listedDate: date))
            remainder = afterMarker[dateEnd...]
        }
        return out
    }

    /// The download form on a file's page: POST `cmdm_nonce` + `id` to
    /// `action` (with the page as referer, cookies kept) and the response is
    /// the file itself.
    struct DownloadForm: Equatable, Sendable {
        let action: String
        let nonce: String
        let id: String
    }

    static func parseFilePage(html: String) -> DownloadForm? {
        guard let action = attribute(
                "action", after: "class=\"CMDM-downloadForm\"", in: html),
              let nonce = attribute(
                "value", after: "name=\"cmdm_nonce\"", in: html),
              let id = attribute(
                "value", after: "name=\"id\"", in: html)
        else { return nil }
        return DownloadForm(action: action, nonce: nonce, id: id)
    }

    /// The value of `name="…"` appearing immediately after `marker` — the
    /// attribute order the site actually emits. Positional on purpose: if the
    /// markup is rearranged, failing loudly beats guessing at a nonce.
    private static func attribute(
        _ name: String, after marker: String, in html: String
    ) -> String? {
        guard let at = html.range(of: marker) else { return nil }
        let after = html[at.upperBound...]
        guard let attr = after.range(of: "\(name)=\"") else { return nil }
        // The attribute must belong to the marker's own tag, not one much
        // later in the page.
        guard html.distance(from: at.upperBound, to: attr.lowerBound) < 200
        else { return nil }
        guard let end = after[attr.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(after[attr.upperBound..<end])
    }
}
