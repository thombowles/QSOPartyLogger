import Foundation
import Observation

/// The one place a `SpotDraft` becomes sends. Fans it out to every ticked
/// network through the transports it is given, and keeps the receipt — a
/// state per network — current as the clients report back and the node
/// echoes. Tests script the transports; nothing here touches TCP or HTTP.
@MainActor
@Observable
final class SpotDispatcher {

    struct Transports {
        /// Writes one command to the node. `false` when there is no session
        /// to write to.
        var sendClusterCommand: (String) -> Bool
        /// Fire-and-forget; the hub client reports through `update`.
        var postToHub: (HubSelfSpot.Fields, PartyDefinition) -> Void
        /// Fire-and-forget; the POTA client reports through `update`.
        var postToPota: (PotaSpot.Fields) -> Void
    }

    var transports: Transports
    private(set) var receipt: SpotReceipt?

    /// The cluster spot awaiting the node's echo, if any.
    private var pendingEcho: (fields: ClusterSpot.Fields, poster: String)?
    private var lastClusterSent: ClusterSpot.Fields?
    private var lastClusterSentAt: Date?

    init(transports: Transports) {
        self.transports = transports
    }

    /// The caller has confirmed the draft with the operator: this reaches
    /// public boards at once.
    func send(_ draft: SpotDraft, party: PartyDefinition, now: Date = Date()) {
        guard !draft.networks.isEmpty else { return }
        var states: [SpotNetwork: SpotSendState] = [:]
        for network in draft.networks { states[network] = .sending }
        receipt = SpotReceipt(
            station: draft.station.trimmingCharacters(in: .whitespaces).uppercased(),
            frequencyKHz: draft.frequencyKHz,
            states: states,
            changedAt: now
        )
        pendingEcho = nil

        if draft.networks.contains(.cluster) {
            let fields = draft.clusterFields(party: party)
            if SpotRepeat.isRepeat(fields, of: lastClusterSent, lastSentAt: lastClusterSentAt, now: now) {
                update(.cluster, state: .failed("That spot just went out to the node — nothing has changed since."), now: now)
            } else if transports.sendClusterCommand(ClusterSpot.command(fields)) {
                lastClusterSent = fields
                lastClusterSentAt = now
                pendingEcho = (fields, draft.poster)
                update(.cluster, state: .sent(now), now: now)
            } else {
                update(.cluster, state: .failed("Cluster not connected."), now: now)
            }
        }
        if draft.networks.contains(.hub) {
            transports.postToHub(draft.hubFields, party)
        }
        if draft.networks.contains(.pota) {
            transports.postToPota(draft.potaFields)
        }
    }

    /// A client's state for the network it serves. Only the current
    /// receipt's networks take it — a verdict for a network this send did not
    /// go to is somebody else's news.
    func update(_ network: SpotNetwork, state: SpotSendState, now: Date = Date()) {
        receipt?.set(state, for: network, at: now)
    }

    /// Every incoming cluster spot passes here: the one that is ours coming
    /// back is the node's proof of receipt.
    func noteIncomingSpot(_ spot: Spot, now: Date = Date()) {
        guard let pending = pendingEcho,
              case .sent = receipt?.states[.cluster] ?? .idle,
              ClusterSpot.isEcho(spot, of: pending.fields, poster: pending.poster)
        else { return }
        pendingEcho = nil
        update(.cluster, state: .confirmed, now: now)
    }

    func dismiss(now: Date = Date()) {
        receipt?.dismiss(at: now)
    }
}
