import Foundation

/// Building one `Advisor.Input` from what the main view already holds.
///
/// It lives here rather than in the view for two reasons. The pane's body has
/// a type-checker budget that a dozen inline arguments would spend
/// (`MainView.leftPaneContent` carries the scar), and the derivations below —
/// which rows count as evidence, which bonus slots are filled — are rules, and
/// rules belong where they can be tested.
extension Advisor.Input {

    /// `spotsOnBand` is a closure rather than an array so the caller applies
    /// its **own** filter path per band — the same one the band map uses,
    /// including that band's worked-station set. The advisor and the band map
    /// can then never disagree about what is workable, which is the whole
    /// point of both reading one list.
    static func make(
        goal: Advisor.Goal,
        log: ContestLog,
        party: PartyDefinition?,
        score: ScoreEngine.ScoreBreakdown,
        reading: RateMeter.Reading,
        currentBand: Band?,
        currentModeClass: ModeClass,
        spotsOnBand: (Band) -> [Spot],
        spaceWeather: SpaceWeather?,
        followsBandPlan: Bool,
        mutedKinds: Set<Advisor.Advisory.Kind>,
        now: Date
    ) -> Advisor.Input {
        // Dupes, wrong-mode and out-of-scope rows are not contest QSOs, so
        // they are not evidence about a band either — the same exclusion
        // `ScoreSidebar` makes before handing timestamps to `RateMeter`.
        let excluded = score.dupeRowIDs
            .union(score.invalidRowIDs)
            .union(score.outOfScopeRowIDs)
        let counted = log.qsos.filter { !excluded.contains($0.id) }
        let grid = log.station.gridLocator.trimmingCharacters(in: .whitespaces)

        return Advisor.Input(
            goal: goal,
            reading: reading,
            mode: log.operatingMode,
            currentBand: currentBand,
            currentModeClass: currentModeClass,
            recent: postureSamples(counted, now: now),
            score: score,
            party: party,
            myLocation: log.myLocation,
            gridLocator: grid.isEmpty ? nil : grid,
            spaceWeather: spaceWeather,
            spots: party.map { $0.validBands.flatMap(spotsOnBand) } ?? [],
            bonusWorked: bonusWorked(counted, party: party),
            followsBandPlan: followsBandPlan,
            mutedKinds: mutedKinds
        )
    }

    /// The trailing hour's stamped rows. Rows logged by a build before
    /// `QSO.posture` existed carry no posture and are simply absent, which is
    /// what makes the first stamped weekend the first with run-rate strands.
    static func postureSamples(_ qsos: [QSO], now: Date) -> [Advisor.PostureSample] {
        let cutoff = now.addingTimeInterval(-Advisor.trailingWindow)
        return qsos.compactMap { qso in
            guard let posture = qso.posture,
                  qso.timestampUTC > cutoff, qso.timestampUTC <= now
            else { return nil }
            return Advisor.PostureSample(
                band: qso.band, posture: posture, timestamp: qso.timestampUTC
            )
        }
    }

    /// Which band/mode slots each `workStation` bonus call has already been
    /// worked in. Only those calls: the advisor has no business carrying an
    /// index of the whole log.
    static func bonusWorked(
        _ qsos: [QSO], party: PartyDefinition?
    ) -> [String: Set<Advisor.BonusSlot>] {
        guard let party else { return [:] }
        let calls = Set(party.bonuses.compactMap { bonus -> String? in
            guard case .workStation(let call, _, _) = bonus else { return nil }
            return call.uppercased()
        })
        guard !calls.isEmpty else { return [:] }

        var worked: [String: Set<Advisor.BonusSlot>] = [:]
        for qso in qsos where calls.contains(qso.call.uppercased()) {
            worked[qso.call.uppercased(), default: []]
                .insert(.init(band: qso.band, modeClass: qso.modeClass))
        }
        return worked
    }
}
