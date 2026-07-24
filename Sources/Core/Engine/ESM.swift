import Foundation

/// Enter-Sends-Message: what Return should do given the entry state.
/// Message indexes are 0-based F-key slots into the active mode's set.
///
/// Run:  empty call → F1 (CQ); call w/o valid exchange → F2 (their report);
///       valid exchange → log the QSO and send F3 (TU).
/// S&P:  no valid exchange yet → F1 (my call, answering a CQ);
///       valid exchange → log the QSO and send F2 (my report).
enum ESM {

    enum Action: Equatable {
        case sendMessage(index: Int)
        case logAndSend(index: Int)
        case none
    }

    static func nextAction(mode: OperatingMode, callEmpty: Bool, exchangeValid: Bool) -> Action {
        switch mode {
        case .run:
            if callEmpty { return .sendMessage(index: 0) }
            if !exchangeValid { return .sendMessage(index: 1) }
            return .logAndSend(index: 2)
        case .searchPounce:
            if !exchangeValid || callEmpty { return .sendMessage(index: 0) }
            return .logAndSend(index: 1)
        }
    }
}
