import SwiftUI

/// The key-diagnostics readout — its own observable object so a keystroke
/// invalidates the notice strip alone. As `MainView` `@State` it invalidated
/// the whole window on every keyDown, log table and sidebar included.
@MainActor
@Observable
final class KeyReadout {
    /// The last key the monitor ruled on, for the shortcut-hints legend.
    var lastKeyReadout: String?
    /// The line under the messages row when the F row arrives as media keys —
    /// `KeyDiagnostics.fRowNotice`. Cleared by the next real function key.
    var fRowNotice: String?
}

/// Everything under the radio bar that follows the operator's typing: the
/// entry row, the super check strip, the messages row, the notice strip and
/// the worked-before table. Its own view so a keystroke invalidates exactly
/// this cluster — `MainView.body` reads no `EntryState` at all, and the log
/// table and sidebar re-render per contact, never per character.
///
/// `context` is a closure on purpose: it is evaluated inside this body, so
/// the radio/settings reads it makes register here rather than on the window.
struct EntrySection: View {
    let document: LogDocument
    let flow: EntryFlow
    @Bindable var settings: AppSettings
    let radio: RadioController
    let callbookClient: CallbookClient
    let potaParkClient: PotaParkClient
    var bandMapModel: BandMapModel?
    let keyReadout: KeyReadout
    let context: () -> EntryFlow.Context
    @FocusState.Binding var focus: EntryBar.Field?
    /// Reported up so the log table can give back exactly what this table
    /// takes — the window's frame reads a plain `@State`, so it re-renders
    /// only when the height actually changes, not per keystroke.
    @Binding var workedBeforeHeight: CGFloat
    @Binding var exportNotice: String?
    @Binding var repeatCQ: Bool
    let repeatPaused: Bool
    let cqFrequencyHz: Int?
    let onLog: () -> Void
    let onTakeCallFrame: () -> Void
    let onSendMessage: (Int) -> Void
    let onEditMessage: (Int) -> Void
    let onJumpToCQ: () -> Void

    private var entry: EntryState { flow.entry }
    private var party: PartyDefinition? { flow.party }

    var body: some View {
        let context = context()
        let contacts = workedBefore
        let archiveLine = workedBeforeArchiveLine(contacts: contacts)
        let tableHeight = WorkedBeforeTable.height(
            contacts: contacts.count, hasArchiveLine: archiveLine != nil
        )
        VStack(spacing: 0) {
            EntryBar(entry: entry, party: party, layout: entryLayout,
                     parkCaption: parkCaption,
                     callbookCaption: callbookCaption,
                     callFrameColor: callFrameColor, onTakeCallFrame: onTakeCallFrame,
                     onLog: onLog, focus: $focus)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: entry.exchange) { flow.revalidate(self.context()) }
                .onChange(of: entry.call) {
                    flow.callChanged(self.context())
                    callbookClient.noteCallChanged(entry.call)
                }
                // The park may pin the state down — typed, prefilled, or
                // pounced, the offer recomputes with it.
                .onChange(of: entry.theirParkTyped) { flow.theirParkEdited() }
                .onChange(of: callbookClient.record) {
                    flow.callbookRecord = callbookClient.record
                }
                // The member element can decide the NEW MULT badge (a party
                // may count the worked station itself), so it revalidates
                // like the exchange rather than only gating the log.
                .onChange(of: entry.memberRcvd) { flow.revalidate(self.context()) }

            superCheckStrip

            MessagesRow(
                operatingMode: operatingMode,
                keys: messageKeys(context),
                onSend: onSendMessage,
                onEdit: onEditMessage,
                enabled: radio.isConnected
                    && (context.modeClass == .cw
                        || (context.modeClass == .phone && phoneKeysEnabled(context))),
                pendingIndex: flow.pendingMessageIndex(context),
                repeatEnabled: $repeatCQ,
                repeatPaused: repeatPaused,
                repeatInterval: $settings.repeatIntervalSeconds,
                esmEnabled: $settings.esmEnabled,
                cqFrequencyLabel: cqFrequencyHz.map { String(format: "%.1f", Double($0) / 1000) },
                onJumpToCQ: onJumpToCQ
            )

            noticeStrip(context)

            if tableHeight > 0 {
                WorkedBeforeTable(
                    call: entry.callNormalized,
                    contacts: contacts,
                    archiveLine: archiveLine,
                    currentBand: context.band,
                    currentModeClass: context.modeClass
                )
            }
        }
        .onChange(of: tableHeight, initial: true) { workedBeforeHeight = tableHeight }
    }

    // MARK: The entry row's captions

    /// The entry row's shape for this log — party flags, or the contest's
    /// exchange spec for a v2-only contest (POTA).
    private var entryLayout: EntryLayout {
        EntryLayout(party: party, contest: flow.standaloneContest,
                    isActivation: !document.log.myPotaRefs.isEmpty)
    }

    /// The quiet line under the park field: the refs as parsed, each with its
    /// name when the offline directory knows it. Silent while empty or
    /// unparseable — the red refuse-to-log label owns that case. A park with
    /// an `@subdivision` looks up by its base reference.
    private var parkCaption: String? {
        let typed = entry.theirParkTyped.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        guard case .success(let parks) = PotaRef.parseList(PotaRef.expandShorthand(typed)), !parks.isEmpty else { return nil }
        let directory = potaParkClient.directory
        let parts = parks.map { ref -> String in
            let base = ref.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ref
            if let name = directory?.park(reference: base)?.name { return "\(ref) · \(name)" }
            return ref
        }
        return parts.joined(separator: "  ·  ")
    }

    /// The callbook's quiet line for the call in the field — only while the
    /// published record is for exactly that call, so a half-edited call
    /// never wears the last station's name.
    private var callbookCaption: String? {
        guard let known = callbookClient.record,
              !entry.call.isEmpty,
              known.call == entry.callNormalized else { return nil }
        guard let line = CallbookCaption.line(
            for: known, stationGrid: document.log.station.gridLocator) else { return nil }
        return "\(line) — \(known.source.label)"
    }

    /// The ghost call's colour — the band map's colour for that spot.
    private var callFrameColor: Color {
        entry.callFrame.flatMap { bandMapModel?.status(for: $0) }?.color ?? .secondary
    }

    // MARK: Messages row

    /// The document owns the mode so it survives a reopen. Writes go straight
    /// to `log` without registering undo — ⌘Z belongs to log edits (see the
    /// same binding note in `MainView`).
    private var operatingMode: Binding<OperatingMode> {
        Binding(
            get: { document.log.operatingMode },
            set: { document.log.operatingMode = $0 }
        )
    }

    /// What the messages row draws for F1–F8 right now.
    private func messageKeys(_ context: EntryFlow.Context) -> [MessagesRow.MessageKey] {
        (0..<8).map { index in
            switch flow.transmission(at: index, context: context) {
            case .cw(let text):
                MessagesRow.MessageKey(caption: text, isActive: true)
            case .voice(_, let caption), .recording(_, _, let caption):
                MessagesRow.MessageKey(caption: caption, isActive: true)
            case .silent:
                MessagesRow.MessageKey(caption: context.modeClass == .phone ? "—" : "",
                                       isActive: false)
            }
        }
    }

    /// Whether the phone F-keys can do anything at all: the radio's recorder
    /// is ready, or the recordings path is.
    private func phoneKeysEnabled(_ context: EntryFlow.Context) -> Bool {
        switch context.phoneSource {
        case .radioMemories: radio.voiceStatus.isReady
        case .recordings(let ready): ready
        }
    }

    // MARK: Notice strip

    /// Under the messages row: the shortcut legend while hints are on (⌘/),
    /// the F-row notice when the keyboard sent a media key where an F-key was
    /// expected, why silent phone keys are silent, and an export that could
    /// not run. Inline, dismissable, never a modal.
    @ViewBuilder
    private func noticeStrip(_ context: EntryFlow.Context) -> some View {
        if settings.showShortcutHints {
            VStack(alignment: .leading, spacing: 2) {
                Text(ShortcutLegend.line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ShortcutLegend.lastKeyLine(keyReadout.lastKeyReadout))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("What the logger last received from the keyboard, and what it did with it — "
                          + "press an F-key here to check the F row reaches the app")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        if let notice = keyReadout.fRowNotice {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    keyReadout.fRowNotice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss keyboard notice")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        // Silent phone keys say why, right where the dashes are — the same
        // gates that silence `transmission(at:)`, so this can only name a
        // blocker that is really blocking. No dismiss button: it reflects
        // live state and clears itself the moment the state is fixed.
        if let notice = flow.phoneKeysNotice(context: context, voiceStatus: radio.voiceStatus) {
            Label(notice, systemImage: "speaker.slash.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
        // An export that could not run says so here — the same inline place,
        // never a modal (Tom's rule), and never silence.
        if let notice = exportNotice {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(notice, systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    exportNotice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss export notice")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
    }

    // MARK: Super check

    /// Reserved height while the feature is live (option on, and a database
    /// or the party's call history loaded), so the strip filling and emptying
    /// under a 35 WPM exchange never reflows the window. Absent entirely
    /// otherwise.
    @ViewBuilder
    private var superCheckStrip: some View {
        if settings.superCheckEnabled, flow.superCheckLive {
            SuperCheckRow(matches: flow.superCheckMatches, typedCall: entry.callNormalized)
                .padding(.horizontal, 14)
        }
    }

    // MARK: Worked before

    /// Every prior contact with the call in the entry field — the history
    /// table's contents, and the reason it is on screen at all.
    private var workedBefore: [DupeChecker.WorkedContact] {
        DupeChecker.workedContacts(call: entry.callNormalized, log: document.log.qsos)
    }

    /// "KSQP 2025 — JOH" when previous contests know the station and this one
    /// does not — or, failing that, what the party's call history file says
    /// he sends. It is where a pre-filled exchange came from, which is why it
    /// belongs on screen rather than only in the field.
    private func workedBeforeArchiveLine(contacts: [DupeChecker.WorkedContact]) -> String? {
        guard contacts.isEmpty, !entry.callNormalized.isEmpty else { return nil }
        if let seen = flow.archiveIndex.entries(for: entry.callNormalized).first {
            return "\(seen.partyID.uppercased()) \(seen.year) — \(seen.theirLoc)"
        }
        guard let (partyID, parsed) = flow.callHistoryIndex,
              partyID == party?.id,
              let known = parsed.entry(for: entry.callNormalized),
              !known.isEmpty
        else { return nil }
        let bits = [known.name, known.locations.first, known.userText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return "Call history — \(bits.joined(separator: " · "))"
    }
}
