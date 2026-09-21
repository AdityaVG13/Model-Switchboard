import Foundation

/// Operator-visible progress for a Mac-driven remote gateway hard update.
enum GatewayForceUpdatePhase: Equatable, Sendable {
    case idle
    case updating(String)
    case failed(String)

    var isUpdating: Bool {
        if case .updating = self { true } else { false }
    }

    var updatingStep: String? {
        if case .updating(let step) = self { step } else { nil }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { message } else { nil }
    }
}
