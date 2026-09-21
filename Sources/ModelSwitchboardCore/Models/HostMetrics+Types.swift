import Foundation

public struct HostStorageMetrics: Codable, Equatable, Sendable {
    public let usedMB: Double?
    public let totalMB: Double?
    public let percent: Double?
    public let source: String?

    public init(usedMB: Double? = nil, totalMB: Double? = nil, percent: Double? = nil, source: String? = nil) {
        self.usedMB = usedMB
        self.totalMB = totalMB
        self.percent = percent
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case usedMB = "used_mb"
        case totalMB = "total_mb"
        case percent
        case source
    }
}
