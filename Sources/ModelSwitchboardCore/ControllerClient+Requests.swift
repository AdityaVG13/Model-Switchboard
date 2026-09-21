import Foundation

extension ControllerClient {
    struct ProfileRequest: Encodable {
        let profile: String
    }

    struct IntegrationRequest: Encodable {
        let integration: String
        let action: String
    }

    struct BenchmarkRequest: Encodable {
        let suite: String
        let profiles: [String]?
    }

    struct EmptyRequest: Encodable {}

    struct ProfilesDirectoryRequest: Encodable {
        let profiles_dir: String
    }
}
