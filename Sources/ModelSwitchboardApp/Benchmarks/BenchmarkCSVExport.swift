import Foundation
import ModelSwitchboardCore

enum BenchmarkCSVExport {
    struct Notice: Equatable {
        let message: String
        let isError: Bool
    }

    static func defaultFileName(_ generatedAt: String?) -> String {
        return "model-switchboard-benchmark-\(timestampForFileName(generatedAt)).csv"
    }

    static func timestampForFileName(_ generatedAt: String?) -> String {
        let raw: String
        if let generatedAt, !generatedAt.isEmpty {
            raw = generatedAt
        } else {
            raw = ISO8601DateFormatter().string(from: .now)
        }
        return raw
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "T", with: "_")
            .replacingOccurrences(of: "Z", with: "")
    }
}
