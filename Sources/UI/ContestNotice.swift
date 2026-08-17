import SwiftUI

/// What the setup sheet says about the selected party, as data: one **headed**
/// group per tone.
///
/// The heading is the whole point of the type. The sheet used to print the
/// blocking caveats in orange and then run straight on into the advisory ones
/// in grey — same `•` glyph, same `.caption2` size — while suppressing the
/// second group's heading precisely when the first one was present. On the 19
/// bundled parties that carry both kinds, the list therefore changed colour
/// part-way down with nothing on screen to say why, and the severity of a line
/// was left to its colour alone.
///
/// Splitting the decision out of the view is what makes that testable: a
/// SwiftUI body cannot be asserted on, but "every group the sheet draws
/// announces itself" can.
struct ContestNotice: Equatable {

    /// How loud a group is, and the only thing colour is allowed to encode.
    ///
    /// String-backed because the tone namespaces the row identities below.
    enum Tone: String, Equatable, Hashable {
        /// The app will mis-score or mis-export this party — worth interrupting
        /// someone who is trying to start a contest.
        case warning
        /// Worth reading, not worth interrupting for.
        case informational
    }

    /// One line the sheet draws, carrying an identity that is unique across the
    /// **whole** notice.
    ///
    /// That uniqueness is the point. The sheet used to draw the two groups from
    /// two sibling `ForEach`es, each identifying its lines by `\.offset` — so
    /// inside one `Form` section the row id `0` existed twice, once for the
    /// first blocking caveat and once for the first advisory one. When the
    /// section re-diffed (opening *Rules provenance* is exactly that) the
    /// collision resolved to a single element: Missouri drew its grey
    /// county-line note in the first orange slot, the "40 and 80 m daytime
    /// bonus" line vanished, and the heading above still counted three. That is
    /// the alert that changes colour from orange to grey.
    ///
    /// Namespacing by tone makes every id distinct, and indexing within the
    /// tone keeps it stable across re-renders and across a change of party.
    struct Row: Identifiable, Equatable {
        let id: String
        let tone: Tone
        let text: String
        /// Set on a group's heading row, `nil` on its bullets — the icon that
        /// carries the tone where colour cannot.
        let systemImage: String?
    }

    struct Group: Equatable, Identifiable {
        let tone: Tone
        /// Never empty. A drawn group with no heading is the defect this type
        /// exists to prevent.
        let header: String
        /// Carries the same distinction as `tone` without using colour, for
        /// greyscale and for colour-blind operators.
        let systemImage: String
        /// Never empty — a group with no lines is not built at all.
        let lines: [String]

        /// There is at most one group per tone, so the tone is the identity.
        var id: Tone { tone }
    }

    /// The orange group. `nil` when the party has no blocking caveats.
    let warning: Group?

    /// The grey group. `nil` when there is nothing quiet to say.
    let informational: Group?

    /// Every group the sheet will actually draw, most severe first.
    var groups: [Group] { [warning, informational].compactMap { $0 } }

    /// Every line the sheet draws — headings and bullets both — flattened into
    /// **one** identity space, so the whole notice can be one `ForEach`. Two
    /// sibling `ForEach`es in a single `Form` section share their row
    /// identities; one cannot collide with itself.
    var rows: [Row] {
        groups.flatMap { group in
            [
                Row(
                    id: "\(group.tone.rawValue).heading",
                    tone: group.tone,
                    text: group.header,
                    systemImage: group.systemImage
                )
            ]
            + group.lines.enumerated().map { index, line in
                Row(
                    id: "\(group.tone.rawValue).\(index)",
                    tone: group.tone,
                    text: line,
                    systemImage: nil
                )
            }
        }
    }

    init(party: PartyDefinition) {
        let blocking = party.blockingCaveats
        // A party with no typed caveats -- not yet classified, or user-installed
        // -- still shows whatever its notes carry, in the quiet tone.
        let fallback = party.caveats.isEmpty ? party.operatorAlerts : []
        let quiet = party.advisoryCaveats.map(\.summary) + fallback

        warning = blocking.isEmpty ? nil : Group(
            tone: .warning,
            header: blocking.contains { $0.kind == .exportBlocking }
                ? "This log needs checking before you submit it."
                : "\(blocking.count) thing\(blocking.count == 1 ? "" : "s") this app "
                  + "cannot score for you here.",
            systemImage: "exclamationmark.triangle.fill",
            lines: blocking.map(\.summary)
        )

        // Headed even when the warning group precedes it. Two headings stacked
        // a few lines apart is a smaller cost than a bulleted list that changes
        // colour for no stated reason.
        informational = quiet.isEmpty ? nil : Group(
            tone: .informational,
            header: "\(quiet.count) note\(quiet.count == 1 ? "" : "s") on how this app "
                + "handles this party.",
            systemImage: "info.circle.fill",
            lines: quiet
        )
    }
}

extension ContestNotice.Tone {

    /// **Orange is reserved for `blockingCaveats`.** It is not keyed on
    /// `isPartiallyVerified`, which fired on 39 of 46 parties and so said
    /// nothing.
    var style: AnyShapeStyle {
        switch self {
        case .warning: return AnyShapeStyle(Color.orange)
        case .informational: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    /// A little more weight on the warning bullets, so the two tones stay
    /// distinguishable where colour is not.
    var bulletFont: Font {
        switch self {
        case .warning: return .caption2.weight(.medium)
        case .informational: return .caption2
        }
    }
}
