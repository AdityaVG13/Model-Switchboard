import Foundation

public extension ModelProfileStatus {
    /// Typed origin. Wire values map 1:1; anything unrecognized (or absent)
    /// becomes `.unknown`. `listening` is the legacy wire value for discovery
    /// rows and stays folded into the synthetic-discovery census.
    enum Origin: String, Equatable, Sendable {
        case profile
        case claim
        case discovery
        case listening
        case unknown

        public init(wireValue: String?) {
            self = wireValue.flatMap(Origin.init(rawValue:)) ?? .unknown
        }
    }

    /// Single owner of launch-folder claim-ness: the wire `source` field.
    /// Name prefixes (`port-`) and runtime tags are data, not identity.
    var isLaunchFolderClaim: Bool { origin == .claim }
}
