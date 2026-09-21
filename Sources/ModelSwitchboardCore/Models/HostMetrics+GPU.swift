import Foundation

public struct HostGPUMetrics: Codable, Equatable, Identifiable, Sendable {
    public let index: Int?
    public let name: String?
    public let utilPercent: Double?
    public let tempC: Double?
    public let vramUsedMB: Double?
    public let vramTotalMB: Double?

    /// Stable identity for chart/row continuity: the nvidia-smi index when
    /// present, else the GPU name, else a fixed fallback. The former
    /// `name?.hashValue` id was unstable across launches (Swift String hashing
    /// is randomized per process), so identical rows could change identity
    /// between polls (L28).
    public var id: String {
        if let index { return "gpu-\(index)" }
        if let name { return name }
        return "gpu-unknown"
    }

    public init(
        index: Int? = nil,
        name: String? = nil,
        utilPercent: Double? = nil,
        tempC: Double? = nil,
        vramUsedMB: Double? = nil,
        vramTotalMB: Double? = nil
    ) {
        self.index = index
        self.name = name
        self.utilPercent = utilPercent
        self.tempC = tempC
        self.vramUsedMB = vramUsedMB
        self.vramTotalMB = vramTotalMB
    }

    enum CodingKeys: String, CodingKey {
        case index
        case name
        case utilPercent = "util_percent"
        case tempC = "temp_c"
        case vramUsedMB = "vram_used_mb"
        case vramTotalMB = "vram_total_mb"
    }
}
