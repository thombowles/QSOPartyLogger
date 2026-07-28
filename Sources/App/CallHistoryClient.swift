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

    /// Consult the listing when it has not been consulted lately, and install
    /// whatever newer revision it shows. `force` is the operator's Refresh
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
