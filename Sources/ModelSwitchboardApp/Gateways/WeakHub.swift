import Foundation

/// Lets the tunnel's @Sendable callback reach the MainActor hub without a
/// retain cycle (hub → tunnel → callback → hub).
final class WeakHub: @unchecked Sendable {
    private weak var hub: GatewayHub?

    init(_ hub: GatewayHub) {
        self.hub = hub
    }

    @MainActor
    var value: GatewayHub? { hub }
}
