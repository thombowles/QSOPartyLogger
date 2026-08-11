import Foundation
import Observation

/// How the client reaches n1mmwp.hamdocs.com — a seam, so tests script the
/// site's answers and never touch the network (constitution Article 5).
protocol CallHistoryFetching: Sendable {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse)
    /// Form POST with the file page as referer; cookies from the preceding
    /// `get` ride along in the session.
    func post(_ url: URL, form: [String: String], referer: String)
        async throws -> (Data, HTTPURLResponse)
}

/// Downloads the active party's N1MM call history file and keeps it fresh.
///
/// Deliberately quiet, like `HubSpotClient`: the listing is a volunteer-run
/// site, and a failure here must never disturb the entry path. Errors land in
/// `lastError` and the console, and whatever file is already cached stays in
/// service — a stale hint file beats none.
///
/// The flow, per `docs/research/n1mm_callhistory.md` (observed 2026-07-28):
/// search the category listing for the party's stable prefix (`sort=newest`),
/// take the first filename the source claims, fetch that file's page for the
/// CM Download Manager form, POST its nonce, and verify the bytes declare the
/// party before installing them. Revisions get new pages, which is why no URL
/// is ever bundled.
@MainActor
@Observable
final class CallHistoryClient {

    enum Status: Equatable {
        case idle
        case checking
        case downloading
        /// A parsed file is published for this party.
        case ready(partyID: String, revision: String, records: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastError: String?
    /// Recent activity, newest last (capped) — the same diagnostic surface
    /// the cluster node window and hub client give.
    private(set) var console: [String] = []

    /// A freshly available index for a party: the cached file at activation,
    /// or a just-installed download. May fire for a party the operator has
    /// already left — the receiver checks, not us.
    var onIndex: ((String, CallHistoryFile.Parsed) -> Void)?

    private let store: CallHistoryStore
    private let fetcher: CallHistoryFetching

    /// How long a listing check satisfies the throttle. The maintainers
    /// refresh files in the days before a contest, so once a day is enough
    /// to catch a new revision without leaning on a volunteer's site.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static let listingURL =
        "https://n1mmwp.hamdocs.com/mmfiles/categories/callhistory/"

    private static let maxConsoleLines = 200

    init(store: CallHistoryStore = CallHistoryStore(folder: CallHistoryStore.defaultFolder),
         fetcher: CallHistoryFetching = URLSessionCallHistoryFetcher()) {
        self.store = store
        self.fetcher = fetcher
    }

    /// What the setup sheet shows for a party: the cached revision and its
    /// dates, independent of whichever party this client last refreshed.
    func cachedMeta(partyID: String) -> CallHistoryStore.Meta? {
        store.loadMeta(partyID: partyID)
    }

    /// The cached index for a party, published immediately — what a party
    /// selection calls before any network is considered.
    func publishCached(party: PartyDefinition) {
        guard party.callHistory != nil else { return }
        guard let cached = store.loadCached(partyID: party.id) else { return }
        status = .ready(
            partyID: party.id,
            revision: cached.meta?.sourceFileName ?? "local file",
            records: cached.parsed.recordCount
        )
        onIndex?(party.id, cached.parsed)
    }

    /// Consult the source when it has not been consulted lately, and install
    /// whatever newer data it shows. `force` is the operator's Refresh
    /// button; the automatic path holds to the once-a-day throttle.
    func refreshIfStale(
        party: PartyDefinition, now: Date = Date(), force: Bool = false
    ) async {
        guard let source = party.callHistory else { return }

        let meta = store.loadMeta(partyID: party.id)
        if !force, let meta,
           now.timeIntervalSince(meta.lastCheckedAt) < Self.checkInterval {
            return
        }

        switch source.kind {
        case .n1mm:
            await refreshFromListing(party: party, source: source, meta: meta, now: now)
        case .w2ljRosterPage:
            await refreshFromRosterPage(party: party, source: source, now: now)
        case .arsFobbRoster:
            await refreshFromFOBBRoster(party: party, source: source, now: now)
        }
    }

    private func refreshFromListing(
        party: PartyDefinition,
        source: CallHistorySource,
        meta: CallHistoryStore.Meta?,
        now: Date
    ) async {
        status = .checking
        lastError = nil
        log("*** checking the listing for \(source.filePrefix)")

        do {
            let newest = try await newestListing(source: source)
            if let meta,
               newest.filename == meta.sourceFileName,
               newest.listedDate == meta.listedDate {
                try? store.touchLastChecked(partyID: party.id, at: now)
                log("*** \(meta.sourceFileName) is still current")
                if case .ready = status {} else { publishCached(party: party) }
                return
            }

            status = .downloading
            log("> downloading \(newest.filename)")
            let parsed = try await download(newest, source: source)

            try store.save(
                partyID: party.id,
                data: parsed.data,
                meta: CallHistoryStore.Meta(
                    sourceFileName: newest.filename,
                    listedDate: newest.listedDate,
                    fetchedAt: now,
                    lastCheckedAt: now
                )
            )
            status = .ready(
                partyID: party.id,
                revision: newest.filename,
                records: parsed.file.recordCount
            )
            log("*** installed \(newest.filename) — \(parsed.file.recordCount) stations")
            onIndex?(party.id, parsed.file)
        } catch let error as RefreshProblem {
            fail(error.message)
        } catch {
            fail("Couldn't reach the call history listing: "
                 + "\(error.localizedDescription) The cached file, if any, "
                 + "stays in use.")
        }
    }

    /// The Skeeter Hunt arrangement: no N1MM file exists, so discovery starts
    /// from the sponsor page that links each season's roster sheet, and the
    /// CSV export is converted to the call-history text shape before the
    /// ordinary verification gates run. The sheet is **live** — numbers issue
    /// until the day before the event — so there is no unchanged-revision
    /// short circuit; the once-a-day throttle alone paces the re-download.
    private func refreshFromRosterPage(
        party: PartyDefinition,
        source: CallHistorySource,
        now: Date
    ) async {
        guard let pageURLString = source.pageURL,
              let pageURL = URL(string: Self.secured(pageURLString)) else {
            fail("This party's roster source names no page URL — "
                 + "the definition is incomplete.")
            return
        }
        status = .checking
        lastError = nil
        log("*** checking the sponsor page for the roster")

        do {
            let (pageData, pageResponse) = try await fetcher.get(pageURL)
            guard pageResponse.statusCode == 200,
                  let pageHTML = String(data: pageData, encoding: .utf8) else {
                throw RefreshProblem(message:
                    "The sponsor page answered \(pageResponse.statusCode). "
                    + "The cached roster, if any, stays in use.")
            }
            guard let sheetURLString =
                    SkeeterRosterParser.rosterSheetURL(inPageHTML: pageHTML),
                  let sheetURL = URL(string: sheetURLString) else {
                // Anchored to the page's own "roster" phrasing, so a
                // redesigned page is not something to guess at — same stance
                // as the listing parser.
                throw RefreshProblem(message:
                    "The sponsor page no longer links a roster this app can "
                    + "find — not guessing at one. The cached roster, if any, "
                    + "stays in use.")
            }

            status = .downloading
            log("> downloading the roster sheet")
            let (bytes, sheetResponse) = try await fetcher.get(sheetURL)
            guard sheetResponse.statusCode == 200, !looksLikeHTML(bytes),
                  let csv = String(data: bytes, encoding: .utf8) else {
                // Google answers a permissions problem with an HTML page,
                // status 200 — the same lookalike trap the N1MM site has.
                throw RefreshProblem(message:
                    "The roster sheet refused its CSV export. "
                    + "The cached roster, if any, stays in use.")
            }
            guard let converted = SkeeterRosterParser.n1mmText(
                fromCSV: csv, token: source.token ?? source.filePrefix) else {
                throw RefreshProblem(message:
                    "The roster sheet has changed shape — not reading it "
                    + "until the app is updated. The cached roster, if any, "
                    + "stays in use.")
            }

            let data = Data(converted.utf8)
            guard let parsed = CallHistoryFile.parse(data: data),
                  parsed.recordCount > 0,
                  source.isDeclared(inCommentTokens: parsed.tokens) else {
                throw RefreshProblem(message:
                    "The converted roster came back empty — not installing it.")
            }

            let revision = "roster " + Self.dayStamp(now)
            try store.save(
                partyID: party.id,
                data: data,
                meta: CallHistoryStore.Meta(
                    sourceFileName: revision,
                    listedDate: Self.dayStamp(now),
                    fetchedAt: now,
                    lastCheckedAt: now
                )
            )
            status = .ready(
                partyID: party.id,
                revision: revision,
                records: parsed.recordCount
            )
            log("*** installed the roster — \(parsed.recordCount) stations")
            onIndex?(party.id, parsed)
        } catch let error as RefreshProblem {
            fail(error.message)
        } catch {
            fail("Couldn't reach the sponsor's roster: "
                 + "\(error.localizedDescription) The cached roster, if any, "
                 + "stays in use.")
        }
    }

    /// The FOBB arrangement: the sponsor's self-serve number report is one
    /// HTML table at a stable URL, so there is no discovery hop — fetch the
    /// report, convert, install. Live data (numbers issue until the event,
    /// and the table resets for each running), so there is no
    /// unchanged-revision short circuit; the once-a-day throttle alone paces
    /// the re-download, exactly as for the roster-page kind above.
    private func refreshFromFOBBRoster(
        party: PartyDefinition,
        source: CallHistorySource,
        now: Date
    ) async {
        guard let pageURLString = source.pageURL,
              let pageURL = URL(string: Self.secured(pageURLString)) else {
            fail("This party's roster source names no page URL — "
                 + "the definition is incomplete.")
            return
        }
        status = .checking
        lastError = nil
        log("*** checking the sponsor's roster report")

        do {
            let (pageData, pageResponse) = try await fetcher.get(pageURL)
            guard pageResponse.statusCode == 200,
                  let pageHTML = String(data: pageData, encoding: .utf8) else {
                throw RefreshProblem(message:
                    "The roster page answered \(pageResponse.statusCode). "
                    + "The cached roster, if any, stays in use.")
            }
            guard let converted = FOBBRosterParser.n1mmText(
                fromHTML: pageHTML, token: source.token ?? source.filePrefix) else {
                // Positional reads of somebody else's markup, so a redesign
                // is not something to guess at — the listing parser's stance.
                throw RefreshProblem(message:
                    "The roster page has changed shape — not reading it "
                    + "until the app is updated. The cached roster, if any, "
                    + "stays in use.")
            }

            let data = Data(converted.utf8)
            guard let parsed = CallHistoryFile.parse(data: data),
                  parsed.recordCount > 0,
                  source.isDeclared(inCommentTokens: parsed.tokens) else {
                throw RefreshProblem(message:
                    "The converted roster came back empty — not installing it.")
            }

            let revision = "roster " + Self.dayStamp(now)
            try store.save(
                partyID: party.id,
                data: data,
                meta: CallHistoryStore.Meta(
                    sourceFileName: revision,
                    listedDate: Self.dayStamp(now),
                    fetchedAt: now,
                    lastCheckedAt: now
                )
            )
            status = .ready(
                partyID: party.id,
                revision: revision,
                records: parsed.recordCount
            )
            log("*** installed the roster — \(parsed.recordCount) stations")
            onIndex?(party.id, parsed)
        } catch let error as RefreshProblem {
            fail(error.message)
        } catch {
            fail("Couldn't reach the sponsor's roster: "
                 + "\(error.localizedDescription) The cached roster, if any, "
                 + "stays in use.")
        }
    }

    /// An `http://` URL upgraded to `https://`.
    ///
    /// App Transport Security refuses plain HTTP outright, so a bundled or
    /// user-supplied `http://` page URL is not "insecure but working" — it
    /// cannot load at all, and the operator sees an ATS message naming a
    /// policy rather than a site. Sponsors write their own links however
    /// they like (W2LJ's page is linked as `http://` and served fine over
    /// TLS), so the scheme is the app's business, not theirs. If the host
    /// genuinely has no TLS the request fails on its own merits, which is a
    /// better error than the one ATS produces.
    static func secured(_ urlString: String) -> String {
        guard urlString.lowercased().hasPrefix("http://") else { return urlString }
        return "https://" + urlString.dropFirst("http://".count)
    }

    private static func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: The two fetches

    private struct RefreshProblem: Error {
        let message: String
    }

    private func newestListing(
        source: CallHistorySource
    ) async throws -> CallHistoryPageParser.Listing {
        var components = URLComponents(string: Self.listingURL)!
        components.queryItems = [
            URLQueryItem(name: "view", value: "list"),
            URLQueryItem(name: "sort", value: "newest"),
            URLQueryItem(name: "CMDsearch", value: source.filePrefix),
        ]
        let (data, response) = try await fetcher.get(components.url!)
        guard response.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw RefreshProblem(message:
                "The call history listing answered \(response.statusCode).")
        }
        guard let listings = CallHistoryPageParser.parseListing(html: html) else {
            // Columns are read by position, so a changed layout is not
            // something to guess at — same stance as the hub table.
            throw RefreshProblem(message:
                "The call history listing has changed shape — not reading it "
                + "until the app is updated. The cached file, if any, stays in use.")
        }
        guard let newest = listings.first(
            where: { source.claims(fileNamed: $0.filename) }) else {
            throw RefreshProblem(message:
                "The listing shows no file matching \(source.filePrefix). "
                + "The cached file, if any, stays in use.")
        }
        return newest
    }

    private func download(
        _ listing: CallHistoryPageParser.Listing,
        source: CallHistorySource
    ) async throws -> (data: Data, file: CallHistoryFile.Parsed) {
        guard let pageURL = URL(string: listing.pageURL) else {
            throw RefreshProblem(message: "Bad file page URL for \(listing.filename).")
        }
        let (pageData, pageResponse) = try await fetcher.get(pageURL)
        guard pageResponse.statusCode == 200,
              let pageHTML = String(data: pageData, encoding: .utf8),
              let form = CallHistoryPageParser.parseFilePage(html: pageHTML)
        else {
            throw RefreshProblem(message:
                "The page for \(listing.filename) has changed shape — not "
                + "reading it until the app is updated.")
        }
        guard let action = URL(string: form.action) else {
            throw RefreshProblem(message: "Bad download URL for \(listing.filename).")
        }

        let (bytes, downloadResponse) = try await fetcher.post(
            action,
            form: ["cmdm_nonce": form.nonce, "id": form.id],
            referer: listing.pageURL
        )
        guard downloadResponse.statusCode == 200, !looksLikeHTML(bytes) else {
            // The site answers a refused download with its access-denied
            // *page*, status 200 — bytes that parse as zero stations and
            // would silently install as an empty file.
            throw RefreshProblem(message:
                "The site refused the download of \(listing.filename). "
                + "The cached file, if any, stays in use.")
        }
        guard let parsed = CallHistoryFile.parse(data: bytes),
              parsed.recordCount > 0 else {
            throw RefreshProblem(message:
                "\(listing.filename) came back unreadable or empty — not installing it.")
        }
        guard source.isDeclared(inCommentTokens: parsed.tokens) else {
            // The files say who they serve; one that does not name this
            // party is a lookalike, not an update.
            throw RefreshProblem(message:
                "\(listing.filename) does not declare \(source.token ?? "?") "
                + "— not installing it over the cached file.")
        }
        return (bytes, parsed)
    }

    private func looksLikeHTML(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(256), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return false }
        return head.hasPrefix("<!doctype") || head.hasPrefix("<html")
    }

    private func fail(_ message: String) {
        status = .failed(message)
        lastError = message
        log("*** \(message)")
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }
}

/// The real transport: one ephemeral session whose in-memory cookies carry
/// from the file page GET to the form POST, which the site requires.
struct URLSessionCallHistoryFetcher: CallHistoryFetching {
    private static let userAgent =
        "QSOPartyLogger/1.0 (+https://github.com/KE5CW) macOS"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: config)
    }

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    func post(
        _ url: URL, form: [String: String], referer: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        var components = URLComponents()
        components.queryItems = form
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
