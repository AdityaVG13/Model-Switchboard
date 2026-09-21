import Foundation

public extension ModelProfileStatus {
    var stateLabel: String {
        switch lifecycle {
        case .running, .readyUnowned: return "Running"
        case .starting: return "Starting"
        case .stopped: return "Not Running"
        }
    }

    var stateDescription: String {
        var parts: [String] = [runtimeLabel ?? runtime, stateLabel]
        switch lifecycle {
        case .starting:
            parts.append("endpoint pending")
        case .running, .readyUnowned:
            parts.append("endpoint healthy")
        case .stopped:
            break
        }
        if let vramMB {
            parts.append(String(format: "%.1f MB VRAM", vramMB))
        } else if let rssMB {
            parts.append(String(format: "%.1f MB RSS", rssMB))
        }
        return parts.joined(separator: " • ")
    }
}
