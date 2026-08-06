import SwiftUI

/// N1MM-style entry row: call, RSTs, exchange with live validation and
/// dupe / new-mult badges. Enter logs from any field.
struct EntryBar: View {
    @Bindable var entry: EntryState
    let party: PartyDefinition?
    /// Whether this log is a POTA activation (Contest Setup has parks). The
    /// park-to-park field exists only then — P2P credit does not exist for a
    /// home station, and the bar stays exactly as it is for every non-POTA
    /// contest.
    let showsP2P: Bool
    let onLog: () -> Void

    enum Field: Hashable {
        case call, rstSent, rstRcvd, serialSent, serialRcvd, nameRcvd, exchange, memberRcvd
        case theirPark

        /// Where Space moves next, cycling back to the call from the exchange.
        /// Call jumps straight to the exchange because the RSTs are pre-filled
        /// — Tab still walks every field for the rare 579, which is how N1MM
        /// splits the two keys ("the spacebar … skips over signal report
        /// fields"; Tab walks them all).
        ///
        /// A received QSO number is the one numeric field an operator *must*
        /// type every contact, so where a party exchanges one, Call lands there
        /// first and it leads on to the exchange. A received name is the same
        /// kind of field, and it arrives before the location on the air
        /// ("TOM TX"), so it sits between the two. The member element arrives
        /// *after* the location ("559 NJ NR 13"), so its field trails the
        /// exchange and the cycle closes from there.
        func next(
            includesRST: Bool,
            includesSerial: Bool = false,
            includesName: Bool = false,
            includesMember: Bool = false
        ) -> Field {
            switch self {
            case .call: includesSerial ? .serialRcvd : (includesName ? .nameRcvd : .exchange)
            case .rstSent: includesRST ? .rstRcvd : .exchange
            case .rstRcvd: includesSerial ? .serialRcvd : (includesName ? .nameRcvd : .exchange)
            case .serialSent: .serialRcvd
            case .serialRcvd: includesName ? .nameRcvd : .exchange
            case .nameRcvd: .exchange
            case .exchange: includesMember ? .memberRcvd : .call
            case .memberRcvd: .call
            // Nothing routes *to* the park field: Space never lands there,
            // because most contest contacts are not park to park and the
            // fast path must not grow a stop. Tab reaches it in layout
            // order, and Space from it closes the cycle back to the call.
            case .theirPark: .call
            }
        }
    }

    @FocusState.Binding var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                field("Call", text: $entry.call.uppercasing, width: 140, focusTag: .call)
                if party?.exchangeIncludesRST ?? true {
                    field("RST S", text: $entry.rstSent, width: 60, focusTag: .rstSent)
                    field("RST R", text: $entry.rstRcvd, width: 60, focusTag: .rstRcvd)
                }
                if party?.exchangeIncludesSerial ?? false {
                    field("Ser S", text: $entry.serialSent, width: 60, focusTag: .serialSent)
                    field("Ser R", text: $entry.serialRcvd, width: 60, focusTag: .serialRcvd)
                }
                if party?.exchangeIncludesName ?? false {
                    field("Name", text: $entry.nameTyped.uppercasing, width: 100,
                          focusTag: .nameRcvd, provisional: entry.nameIsAutoFilled)
                }
                field(
                    exchangeLabel,
                    text: $entry.exchangeTyped.uppercasing,
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
                if let member = party?.memberExchange {
                    // After the location, the way it is sent ("559 NJ NR 13").
                    // A number or a power with its unit — "13" or "5W".
                    field(member.shortTerm, text: $entry.memberTyped.uppercasing, width: 80,
                          focusTag: .memberRcvd, provisional: entry.memberIsAutoFilled)
                        // The field is narrow and its label cannot say all
                        // three cases, of which the blank one is the least
                        // guessable.
                        .help("\(member.term), or their power (5W, 100W). "
                              + "Leave empty if they sent neither — that scores as QRO.")
                }
                if showsP2P {
                    field("P2P park(s)", text: $entry.theirParkTyped.uppercasing,
                          width: 110, focusTag: .theirPark)
                        .help("The other station's POTA reference(s) when they are "
                              + "in a park too — US-3315, comma-separated for an "
                              + "n-fer. Leave empty otherwise.")
                }
                statusBadge
                Spacer()
                Button("Log", action: onLog)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canLog)
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

    /// What the exchange field is asking for, in the party's own words. A
    /// party with no home region has no host-state codes to hint at — every
    /// token is a peer location — and one whose multipliers are not counties
    /// must not be told they are. The old "Cty" shorthand goes with them: the
    /// leading term already names what the code is.
    private var exchangeLabel: String {
        guard let party else { return "Exchange" }
        guard party.hasHomeRegion else { return "Location" }
        return "\(party.countyTerm.sentenceCased)/State "
            + "(\(party.homeState) ×\(party.countyAbbrLengthHint))"
    }

    private var canLog: Bool {
        if case .valid = entry.exchangeStatus, !entry.callNormalized.isEmpty {
            return !entry.missingName(party: party)
                && !entry.invalidMember(party: party)
                && !entry.invalidTheirPark()
        }
        return false
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
    private func field(
        _ label: String,
        text: Binding<String>,
        width: CGFloat,
        focusTag: Field,
        provisional: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(provisional ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: width)
                .focused($focus, equals: focusTag)
                .onSubmit(onLog)
                .autocorrectionDisabled()
                // Space advances rather than typing one, in every field — from
                // the exchange it wraps back to the call, so the row cycles.
                // Mults are separated with "/" or "," instead.
                .onKeyPress(.space) {
                    focus = focusTag.next(
                        includesRST: party?.exchangeIncludesRST ?? true,
                        includesSerial: party?.exchangeIncludesSerial ?? false,
                        includesName: party?.exchangeIncludesName ?? false,
                        includesMember: party?.memberExchange != nil
                    )
                    return .handled
                }
        }
    }
}
