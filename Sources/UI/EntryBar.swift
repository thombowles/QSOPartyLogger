import SwiftUI

/// N1MM-style entry row: call, RSTs, exchange with live validation and
/// dupe / new-mult badges. Enter logs from any field. The empty call field
/// shows the spot under the VFO as a ghost call (N1MM's call frame); Space,
/// or Return under ESM, takes it.
struct EntryBar: View {
    @Bindable var entry: EntryState
    /// Still consulted for the row's `EntryState` questions (a missing name,
    /// an unreadable member element); the row's *shape* comes from `layout`.
    let party: PartyDefinition?
    /// The row's shape — which fields exist and where Space routes. Built by
    /// the window from the party/contest (`EntryLayout`); the bar itself
    /// decides nothing about contests.
    let layout: EntryLayout
    /// A quiet caption under the park field — the parsed reference(s) and the
    /// park's name when the offline directory knows it. Nil hides the line.
    var parkCaption: String? = nil
    /// The callbook's line for the call in the field — advisory garnish,
    /// nil-hidden. It never fills any field (spec 2026-08-25 decision 4's
    /// hard rule: the exchange is what was sent on the air).
    var callbookCaption: String? = nil
    /// The colour of the ghost call — the band map's colour for the spot under
    /// the VFO — and what Space does when the empty call field shows one.
    /// Defaulted so a bar built without a band map (the caret tests) is the
    /// bar it always was.
    var callFrameColor: Color = .secondary
    var onTakeCallFrame: () -> Void = {}
    let onLog: () -> Void

    enum Field: Hashable {
        case call, rstSent, rstRcvd, serialSent, serialRcvd, nameRcvd, exchange, memberRcvd
        case theirPark, theirState, notes
        // Space routing lives in `EntryLayout.swift` (`next(layout:)`): the
        // same rules this enum carried, driven by the row's layout — which
        // is how a POTA row's park joins the cycle while every party's
        // routing stays byte-for-byte (`EntryLayoutTests`).
    }

    @FocusState.Binding var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // One line wherever it fits — the fields are fixed width, so the
            // row's ideal is its minimum — and a flow of the same fields
            // below that, so a narrow window folds the member and P2P fields
            // onto a second line rather than clipping the Log button.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    fields
                    statusBadge
                    Spacer()
                    logButton
                }
                FlowLayout(horizontalSpacing: 10, verticalSpacing: 6) {
                    fields
                    statusBadge
                    logButton
                }
            }
            if let warning = entry.dupeWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if case .invalid(let message) = entry.exchangeStatus {
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if entry.exchangeIsUnconfirmed {
                Label("Exchange came from a spot — confirm it on the air before logging",
                      systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if entry.exchangeIsAutoFilled, entry.exchangeOrigin == .callHistory {
                // Quieter than the spot warning on purpose: the file is a
                // curated roster, not a stranger's live claim — but it is
                // still last season's data, and what is heard always wins.
                Label("From the call history file — log what you copy",
                      systemImage: "text.book.closed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // Its own line rather than another branch of the chain above:
            // a garbled park and a garbled exchange are separate mistakes,
            // and the operator should see whichever ones they have made.
            if entry.invalidTheirPark() {
                Label("P2P park doesn't parse — they look like US-3315; "
                      + "comma-separate an n-fer",
                      systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            // The park named back, when the offline directory knows it —
            // confirmation the reference points where the operator thinks.
            if let parkCaption {
                Label(parkCaption, systemImage: "leaf")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // Who the callbook says this is — name, state, grid, how far.
            // Advisory only; nothing here is ever written into a field.
            if let callbookCaption {
                Label(callbookCaption, systemImage: "person.text.rectangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: focus) { _, landed in
            guard landed == .rstSent || landed == .rstRcvd else { return }
            selectStrengthDigit()
        }
    }

    /// Landing in a signal report selects the S digit alone, so 599 → 579 is
    /// one keystroke rather than retyping the group — the behaviour the N1MM
    /// manual describes for Tab.
    ///
    /// SwiftUI's TextField exposes no selection, so this reaches the window's
    /// field editor, which becomes first responder a runloop turn after the
    /// focus change lands.
    private func selectStrengthDigit() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                // R S T — the strength digit is the middle one, and the second
                // character in both the CW (599) and phone (59) forms.
                guard editor.string.count >= 2 else { return }
                editor.setSelectedRange(NSRange(location: 1, length: 1))
            }
        }
    }

    private var canLog: Bool {
        guard !entry.callNormalized.isEmpty else { return false }
        // A row with an exchange field logs only a parsed exchange; a row
        // without one (POTA) has nothing to parse — call and parks decide.
        if layout.showsLocation {
            guard case .valid = entry.exchangeStatus else { return false }
        }
        return !entry.missingName(party: party)
            && !entry.invalidMember(party: party)
            && !entry.invalidTheirPark()
    }

    /// The entry fields in Tab order, as many as the party needs.
    @ViewBuilder
    private var fields: some View {
        field("Call", text: $entry.callTyped, width: 140, focusTag: .call,
              ghost: entry.call.isEmpty
                  ? entry.callFrame.map { (text: $0.call, color: callFrameColor) }
                  : nil)
        if layout.showsRST {
            field("RST S", text: $entry.rstSent, width: 60, focusTag: .rstSent)
            field("RST R", text: $entry.rstRcvd, width: 60, focusTag: .rstRcvd)
        }
        if layout.showsSerial {
            field("Ser S", text: $entry.serialSent, width: 60, focusTag: .serialSent)
            field("Ser R", text: $entry.serialRcvd, width: 60, focusTag: .serialRcvd)
        }
        if layout.showsName {
            field("Name", text: $entry.nameTyped, width: 100,
                  focusTag: .nameRcvd, provisional: entry.nameIsAutoFilled)
        }
        if layout.showsLocation {
            field(
                layout.locationLabel,
                text: $entry.exchangeTyped,
                width: 170,
                focusTag: .exchange,
                provisional: entry.exchangeIsAutoFilled
            )
            // Provisional text from our own log is something the operator
            // copied once already. A county from a spot is a stranger's
            // claim about a station never worked, so it gets the louder
            // treatment — what was heard must never look like what was
            // merely asserted.
            .overlay {
                if entry.exchangeIsUnconfirmed {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.orange)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .help(entry.exchangeIsUnconfirmed
                  ? "From a spot, not copied — confirm it before logging"
                  : "")
        }
        if let member = layout.member {
            // After the location, the way it is sent ("559 NJ NR 13").
            // A number or a power with its unit — "13" or "5W".
            field(member.shortTerm, text: $entry.memberTyped, width: 80,
                  focusTag: .memberRcvd, provisional: entry.memberIsAutoFilled)
                // The field is narrow and its label cannot say all
                // three cases, of which the blank one is the least
                // guessable.
                .help("\(member.term), or their power (5W, 100W). "
                      + "Leave empty if they sent neither — that scores as QRO.")
        }
        if layout.showsTheirPark {
            field("P2P park(s)", text: $entry.theirParkTyped,
                  width: 110, focusTag: .theirPark)
                .help("The other station's POTA reference(s) when they are "
                      + "in a park too — US-3315 (a bare number expands: "
                      + "3315 → US-3315), comma-separated for an n-fer. "
                      + "Leave empty otherwise.")
        }
        if layout.showsTheirState {
            field("State", text: $entry.stateTyped, width: 54,
                  focusTag: .theirState)
                .help("Their state as you copied it (\"59 Missouri\") — "
                      + "advisory, exported as ADIF STATE, counted in the "
                      + "activation panel. Leave empty when they didn't say.")
        }
        if layout.showsNotes {
            field("Notes", text: $entry.notesTyped, width: 140,
                  focusTag: .notes, uppercases: false)
                .help("Your note on this contact — ADIF COMMENT. "
                      + "Tab reaches it; Space stays out of prose.")
        }
    }

    private var logButton: some View {
        Button("Log", action: onLog)
            .keyboardShortcut(.defaultAction)
            .disabled(!canLog)
            .shortcutHint("⏎")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch entry.exchangeStatus {
        case .idle:
            EmptyView()
        case .valid(let locations):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if locations.count > 1 {
                    Text("COUNTY LINE ×\(locations.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                }
                if entry.isNewMult {
                    Text("NEW MULT")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.25), in: Capsule())
                }
            }
        case .invalid:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    /// `provisional` greys the text: the app put it there from what it knows
    /// about the station, and the first keystroke makes it the operator's.
    ///
    /// Every field in the row is built to hold upper case, including the two
    /// that never need it: a report and a QSO number are digits, which fold to
    /// themselves, so the reports cost nothing and the row stays one shape.
    private func field(
        _ label: String,
        text: Binding<String>,
        width: CGFloat,
        focusTag: Field,
        provisional: Bool = false,
        ghost: (text: String, color: Color)? = nil,
        uppercases: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Notes keep the operator's own case — "2-fer w/ Bob" is prose,
            // not a token; every other field folds to caps as always.
            Group {
                if uppercases {
                    uppercasingTextField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(provisional ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: width)
                // N1MM's call frame, drawn inside the field: the spot the VFO
                // is on, in the map's colour for it, while the field is empty.
                // Not interactive — Space or Return takes it.
                .overlay(alignment: .leading) {
                    if let ghost {
                        Text(ghost.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(ghost.color)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Spot under the VFO: \(ghost.text)")
                    }
                }
                .focused($focus, equals: focusTag)
                .onSubmit(onLog)
                .autocorrectionDisabled()
                // Space advances rather than typing one, in every field — from
                // the exchange it wraps back to the call, so the row cycles.
                // Mults are separated with "/" or "," instead.
                .onKeyPress(.space) {
                    // An empty call field showing a ghost: Space takes it —
                    // "if a call is in the callframe, space will load it into
                    // the call textbox" — and stays put. Otherwise it advances.
                    if focusTag == .call, entry.call.isEmpty, entry.callFrame != nil {
                        onTakeCallFrame()
                        return .handled
                    }
                    focus = focusTag.next(layout: layout)
                    return .handled
                }
        }
    }
}
