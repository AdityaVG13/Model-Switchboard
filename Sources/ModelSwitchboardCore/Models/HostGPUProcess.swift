import Foundation

public struct HostGPUProcess: Codable, Equatable, Sendable {
    public let pid: Int?
    public let vramMB: Double?
    public let name: String?

    public init(pid: Int? = nil, vramMB: Double? = nil, name: String? = nil) {
        self.pid = pid
        self.vramMB = vramMB
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case vramMB = "vram_mb"
        case name
    }
}

extension HostGPUProcess {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        vramMB = try container.decodeIfPresent(Double.self, forKey: .vramMB)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}
