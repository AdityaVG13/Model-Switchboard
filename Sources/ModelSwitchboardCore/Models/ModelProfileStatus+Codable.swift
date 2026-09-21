import Foundation

extension ModelProfileStatus {
    enum CodingKeys: String, CodingKey {
        case profile
        case displayName = "display_name"
        case runtime
        case runtimeLabel = "runtime_label"
        case runtimeTags = "runtime_tags"
        case launchMode = "launch_mode"
        case host
        case port
        case baseURL = "base_url"
        case requestModel = "request_model"
        case serverModelID = "server_model_id"
        case pid
        case running
        case ready
        case serverIDs = "server_ids"
        case rssMB = "rss_mb"
        case vramMB = "vram_mb"
        case command
        case logPath = "log_path"
        case origin = "source"
        case missingArtifacts = "missing_artifacts"
        case serving
    }
}
