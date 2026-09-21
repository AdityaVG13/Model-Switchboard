import Foundation

extension SSHTunnelManager {
    enum State: Equatable, Sendable {
        case idle
        case connecting
        case established
        case failed(String)

        var isEstablished: Bool { self == .established }

        var isFailed: Bool {
            if case .failed = self { true } else { false }
        }

        var failureMessage: String? {
            if case .failed(let message) = self { message } else { nil }
        }

        /// Why host-metrics polling must not hit the agent yet. `nil` once the
        /// tunnel is up (the `.established` arm is kept so the switch stays
        /// exhaustive if a caller drops the outer `!= .established` guard).
        var pollBlockedReason: String? {
            switch self {
            case .idle: return "SSH tunnel is off"
            case .connecting: return "SSH tunnel connecting…"
            case .established: return nil
            case .failed(let message): return message
            }
        }
    }
}
