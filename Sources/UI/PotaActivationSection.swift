import SwiftUI

/// The POTA activation panel — shown by `ScoreSidebar` whenever the log's
/// Contest Setup carries own parks (spec 2026-08-25 decision 2: data-driven,
/// so it appears during a QSO party activation too; one log, both
/// submissions). The minute tick keeps the UTC-day figures and the midnight
/// countdown honest without touching the sidebar's other sections.
struct PotaActivationSection: View {
    let log: ContestLog

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let stats = PotaStats.compute(qsos: log.qsos,
                                          ownParks: log.myPotaRefs,
                                          now: timeline.date,
                                          myCall: log.station.callsign)
            VStack(alignment: .leading, spacing: 4) {
                Text("POTA ACTIVATION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(stats.parks) { park in
                    let valid = park.uniqueToday >= PotaStats.validationTarget
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(park.park).font(.caption.monospaced())
                            Spacer()
                            Text("\(park.uniqueToday) of \(PotaStats.validationTarget) today")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(valid ? .green : .secondary)
                        }
                        ProgressView(value: Double(min(park.uniqueToday, PotaStats.validationTarget)),
                                     total: Double(PotaStats.validationTarget))
                            .tint(valid ? .green : .accentColor)
                            .controlSize(.small)
                    }
                    .help("Unique call × band × mode this UTC day. POTA's rules "
                          + "ask for ten QSOs in a UTC day; whether duplicates "
                          + "count is not published, so this counts the stricter "
                          + "unique form.")
                }
                if stats.p2pContacts > 0 {
                    Text("P2P: \(stats.p2pContacts) contact\(stats.p2pContacts == 1 ? "" : "s") · \(stats.p2pDistinctParks) park\(stats.p2pDistinctParks == 1 ? "" : "s")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // The outing's spread — states from the typed field (or the
                // callbook's, where nothing was typed), DX from CTY. Whole
                // log, not today's slice: the QSL story of the trip.
                if stats.distinctStates > 0 || stats.dxEntities > 0 {
                    Text("\(stats.distinctStates) state\(stats.distinctStates == 1 ? "" : "s") · \(stats.dxEntities) DX")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("Distinct states worked this outing, and DXCC "
                              + "entities other than your own — from the "
                              + "State field, the callbook, and the calls.")
                }
                // The day boundary is the one clock an activator must not
                // miss — a 23:50Z contact validates today, a 00:05Z one
                // starts tomorrow's count from one.
                let remaining = PotaStats.secondsToUTCMidnight(now: timeline.date)
                if remaining <= 7200 {
                    let hours = remaining / 3600
                    let minutes = (remaining % 3600) / 60
                    Label("UTC day rolls in \(hours > 0 ? "\(hours) h " : "")\(minutes) min",
                          systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
