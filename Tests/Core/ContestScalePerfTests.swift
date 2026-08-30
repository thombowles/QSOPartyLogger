import XCTest
@testable import QSOPartyLogger

/// Measured baselines for the hot paths that run per keystroke, per render
/// pass, and per logged QSO, at contest log sizes. Prints a table; asserts
/// only sanity. The counts each primitive is multiplied by in practice are
/// established in the performance analysis (MainView body reads, revalidate
/// wiring, autosave path) — this file measures the primitives themselves.
final class ContestScalePerfTests: XCTestCase {

    var ksqp: PartyDefinition!
    var counties: [String] = []

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        counties = ksqp.counties.map(\.abbr)
        XCTAssertEqual(counties.count, 105)
    }

    /// An out-of-state (TX) KSQP log with `n` rows: a 600-station pool so
    /// mobiles recur across bands and counties, the full county roster in
    /// rotation, ~10% county-line contacts (two rows, one groupID), bands and
    /// modes mixed — the shape of a real weekend.
    func makeLog(n: Int) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        var qsos: [QSO] = []
        qsos.reserveCapacity(n + 1)
        let start = Date(timeIntervalSince1970: 1_787_997_600)
        let bands: [Band] = [.m20, .m40, .m15, .m80]
        let modes: [(ModeClass, String)] = [(.cw, "CW"), (.phone, "USB")]
        var i = 0
        while qsos.count < n {
            let call = "W0X" + String(format: "%03d", i % 599)
            let band = bands[i % bands.count]
            let (mc, raw) = modes[(i / 5) % modes.count]
            let t = start.addingTimeInterval(Double(i) * 30)
            let county = counties[i % counties.count]
            if i % 10 == 9 {
                let group = UUID()
                for c in [county, counties[(i + 1) % counties.count]] {
                    qsos.append(QSO(
                        groupID: group, timestampUTC: t, call: call, band: band,
                        modeClass: mc, rawMode: raw, freqKHz: 14040,
                        rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: c))
                }
            } else {
                qsos.append(QSO(
                    timestampUTC: t, call: call, band: band,
                    modeClass: mc, rawMode: raw, freqKHz: 14040,
                    rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: county))
            }
            i += 1
        }
        if qsos.count > n { qsos.removeLast(qsos.count - n) }
        log.qsos = qsos
        return log
    }

    /// Median wall time of `reps` runs, in milliseconds.
    func median(reps: Int = 15, _ body: () -> Void) -> Double {
        let clock = ContinuousClock()
        var samples: [Double] = []
        samples.reserveCapacity(reps)
        for _ in 0..<reps {
            let d = clock.measure(body)
            samples.append(Double(d.components.attoseconds) / 1e15
                + Double(d.components.seconds) * 1e3)
        }
        return samples.sorted()[reps / 2]
    }

    func testPerformanceBaselines() throws {
        let sizes = [500, 1_000, 2_000, 4_000]
        var lines: [String] = []
        lines.append("PERF | n | fold | wouldAddMult | revalidate | dupePairs | workedContacts | sort | groupSizes | workedSets | bandModeCounts | lastWhereMiss | bodyPass | saveEncode")

        for n in sizes {
            let log = makeLog(n: n)
            let party = ksqp!

            let fold = median { _ = ScoreEngine.score(log: log, party: party) }

            let wouldAdd = median {
                _ = ScoreEngine.wouldAddMultiplier(
                    theirLocs: [counties[42]], band: .m20, modeClass: .cw,
                    log: log, party: party, call: "W0BH")
            }

            // The engine work behind one exchange-field keystroke:
            // parse + NEW MULT badge (full fold) + dupe-pair set build.
            let entry = EntryState()
            entry.callTyped = "W0X123"
            entry.exchangeTyped = counties[42]
            let revalidate = median {
                entry.revalidate(party: party, log: log, band: .m20, modeClass: .cw)
            }

            let dupePairs = median {
                _ = DupeChecker.existingDupePairs(
                    call: "W0X123", band: .m20, modeClass: .cw,
                    myLocs: ["TX"], theirLocs: [counties[42]], log: log.qsos)
            }

            let worked = median { _ = DupeChecker.workedContacts(call: "W0X123", log: log.qsos) }

            let sort = median { _ = log.qsos.sortedChronologically() }

            let groupSizes = median {
                _ = Dictionary(grouping: log.qsos, by: \.groupID).mapValues(\.count)
            }

            let workedSets = median {
                _ = Set(log.qsos.filter { $0.band == .m20 && $0.modeClass == .cw }
                    .map { $0.call.uppercased() })
                _ = Set(log.qsos.filter { $0.band == .m20 && $0.modeClass == .cw }
                    .map { "\($0.call.uppercased())|\($0.theirLoc.uppercased())" })
            }

            let bandMode = median { _ = ScoreEngine.bandModeCounts(log: log, party: party) }

            let lastMiss = median {
                _ = log.qsos.last { $0.call == "NOTINLOG" && $0.theirPotaRefs != nil }
            }

            // One MainView body pass as verified: score ×2 (sidebar + table)
            // + sidebar bandModeCounts + workedBefore ×6 + the two onChange
            // set builds + the table sort + groupSizes ×30 (per visible row).
            let bodyPass = median(reps: 7) {
                _ = ScoreEngine.score(log: log, party: party)
                _ = ScoreEngine.score(log: log, party: party)
                _ = ScoreEngine.bandModeCounts(log: log, party: party)
                for _ in 0..<6 { _ = DupeChecker.workedContacts(call: "W0X123", log: log.qsos) }
                _ = Set(log.qsos.filter { $0.band == .m20 && $0.modeClass == .cw }
                    .map { $0.call.uppercased() })
                _ = Set(log.qsos.filter { $0.band == .m20 && $0.modeClass == .cw }
                    .map { "\($0.call.uppercased())|\($0.theirLoc.uppercased())" })
                _ = log.qsos.sortedChronologically().reversed()
                for _ in 0..<30 {
                    _ = Dictionary(grouping: log.qsos, by: \.groupID).mapValues(\.count)
                }
            }

            // The per-commit save: score snapshot (two more folds) + pretty JSON.
            let save = median(reps: 7) {
                _ = try? log.stampingScoreSnapshot().encoded()
            }

            lines.append(String(
                format: "PERF | %d | %.2f | %.2f | %.2f | %.2f | %.3f | %.3f | %.3f | %.3f | %.2f | %.4f | %.1f | %.1f",
                n, fold, wouldAdd, revalidate, dupePairs, worked, sort,
                groupSizes, workedSets, bandMode, lastMiss, bodyPass, save))
        }

        // The SCP strip: log-size independent, scanning a MASTER.SCP-sized list.
        let scpCalls = (0..<50_000).map { i -> String in
            let a = Character(UnicodeScalar(65 + (i % 26))!)
            let b = Character(UnicodeScalar(65 + ((i / 26) % 26))!)
            let c = Character(UnicodeScalar(65 + ((i / 676) % 26))!)
            return "K\(i % 10)\(a)\(b)\(c)"
        }.sorted()
        let scp = median {
            _ = SuperCheck.matches(for: "K5AB", scpCalls: scpCalls, historyCalls: [], limit: 24)
        }
        lines.append(String(format: "PERF | SCP 50k calls, 4-char fragment: %.2f ms", scp))

        for line in lines { print(line) }

        let bytes = try makeLog(n: 2_000).stampingScoreSnapshot().encoded().count
        print(String(format: "PERF | save size at n=2000: %.2f MB", Double(bytes) / 1_048_576))
        XCTAssertGreaterThan(bytes, 0)
    }

    /// The after-numbers: the same per-keystroke question answered against
    /// the key sets `LiveScore` already holds. `foldPerChange` is what one
    /// contact now costs the cache (the fold runs once per log change);
    /// `revalidateCached` + one worked-before scan is the whole engine bill
    /// for a keystroke.
    func testCachedPathBaselines() {
        var lines: [String] = []
        lines.append("PERF | n | foldPerChange | revalidateCached | keystrokeEngine")
        for n in [500, 1_000, 2_000, 4_000] {
            let log = makeLog(n: n)
            let party = ksqp!
            let multKeys = ScoreEngine.score(log: log, party: party).multiplierKeys
            let dupeKeys = Set(log.qsos.map(DupeChecker.key))

            let fold = median { _ = ScoreEngine.score(log: log, party: party) }

            let entry = EntryState()
            entry.callTyped = "W0X123"
            entry.exchangeTyped = counties[42]
            let cached = median {
                entry.revalidate(party: party, log: log, band: .m20, modeClass: .cw,
                                 currentMultKeys: multKeys, loggedDupeKeys: dupeKeys)
            }
            let keystroke = median {
                entry.revalidate(party: party, log: log, band: .m20, modeClass: .cw,
                                 currentMultKeys: multKeys, loggedDupeKeys: dupeKeys)
                _ = DupeChecker.workedContacts(call: "W0X123", log: log.qsos)
            }
            lines.append(String(format: "PERF | %d | %.2f | %.4f | %.4f",
                                n, fold, cached, keystroke))
        }
        for line in lines { print(line) }
        XCTAssertFalse(lines.isEmpty)
    }
}
