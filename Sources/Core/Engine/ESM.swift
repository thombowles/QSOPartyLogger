import Foundation

/// Enter-Sends-Message: what Return should do for the contact in progress.
/// Message indexes are 0-based F-key slots into the active mode's set.
///
/// ESM is a *sequence*, not a reading of whatever happens to be filled in.
/// A contact's middle message — S&P your call, Run their report — has either
/// gone out to this station or it has not, and only once it has can Return
/// log. That distinction is what stops a county prefilled from a spot before
/// pouncing from logging a QSO that was never made: the exchange field looks
/// exactly the same before and after you call.
///
/// Run:  empty call → F1 (CQ); otherwise F2 (their report), and once that has
///       been sent and the exchange is valid, log and send F3 (TU).
/// S&P:  F1 (my call), and once that has been sent and the exchange is valid,
///       log and send F2 (my report).
///
/// Modelled on N1MM Logger+, whose S&P ESM "sends your call once … then ready
/// to copy received exchange" — the Big Gun / Little Pistol switch, described
/// at https://n1mmwp.hamdocs.com/setup/the-configurer/ (fetched 2026-07-25).
enum ESM {

    enum Action: Equatable {
        case sendMessage(index: Int)
        case logAndSend(index: Int)
        case none

        /// The F-key slot this action keys, so the messages row can show what
        /// Return will send next. Nil only when Return would just log.
        var messageIndex: Int? {
            switch self {
            case .sendMessage(let index), .logAndSend(let index): index
            case .none: nil
            }
        }
    }

    static func nextAction(
        mode: OperatingMode,
        callEmpty: Bool,
        exchangeValid: Bool,
        middleSent: Bool
    ) -> Action {
        switch mode {
        case .run:
            if callEmpty { return .sendMessage(index: 0) }
            if middleSent, exchangeValid { return .logAndSend(index: 2) }
            return .sendMessage(index: 1)
        case .searchPounce:
            if !callEmpty, middleSent, exchangeValid { return .logAndSend(index: 1) }
            return .sendMessage(index: 0)
        }
    }
}
