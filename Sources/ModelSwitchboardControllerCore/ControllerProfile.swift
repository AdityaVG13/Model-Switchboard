import Foundation
import ModelSwitchboardCore

public struct ControllerProfile: Sendable, Equatable {
    public let name: String
    public let values: [String: String]

    public init(name: String, values: [String: String]) throws {
        var normalized = values
        normalized["PROFILE_NAME"] = normalized["PROFILE_NAME"] ?? name
        normalized["DISPLAY_NAME"] = normalized["DISPLAY_NAME"] ?? name
        guard let requestModel = normalized["REQUEST_MODEL"], !requestModel.isEmpty else {
            throw ControllerError.invalidProfile("\(name): missing REQUEST_MODEL")
        }
        guard normalized["PORT"] != nil || normalized["BASE_URL"] != nil else {
            throw ControllerError.invalidProfile("\(name): missing PORT or BASE_URL")
        }
        normalized["REQUEST_MODEL"] = requestModel
        self.name = name
        self.values = normalized
    }

    public subscript(key: String) -> String? { values[key] }
    public var displayName: String { values["DISPLAY_NAME"] ?? name }
    public var runtime: String { RuntimeCatalog.canonical(values["RUNTIME"]) }
    public var runtimeSpec: RuntimeSpec { RuntimeCatalog.spec(for: self) }
    public var runtimeTags: [String] { RuntimeCatalog.tags(for: self) }
    public var requestModel: String { values["REQUEST_MODEL"] ?? name }
    public var serverModelID: String { values["SERVER_MODEL_ID"] ?? requestModel }
}
