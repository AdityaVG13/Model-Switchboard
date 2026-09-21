import Foundation

public struct HostNetworkMetrics: Codable, Equatable, Sendable {
    public let rxKbps: Double?
    public let txKbps: Double?
    public let source: String?

    public init(rxKbps: Double? = nil, txKbps: Double? = nil, source: String? = nil) {
        self.rxKbps = rxKbps
        self.txKbps = txKbps
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case rxKbps = "rx_kbps"
        case txKbps = "tx_kbps"
        case source
    }
}

public struct HostMemoryMetrics: Codable, Equatable, Sendable {
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
