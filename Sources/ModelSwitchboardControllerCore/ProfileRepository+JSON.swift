import Foundation
import ModelSwitchboardCore

extension ProfileRepository {
    func parseJSON(_ file: URL) throws -> [String: String] {
        let data = try Data(contentsOf: file)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ControllerError.invalidProfile("Profile JSON must be an object: \(file.path)")
        }
        var values: [String: String] = [:]
        for (key, value) in object {
            try Self.requireProfileKey(key, file: file, line: nil)
            values[key] = try Self.jsonStringValue(value)
        }
        return values
    }

    static func jsonStringValue(_ value: Any) throws -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case is NSNull: return ""
        case let collection as [Any]:
            return String(decoding: try JSONSerialization.data(withJSONObject: collection), as: UTF8.self)
        case let collection as [String: Any]:
            return String(decoding: try JSONSerialization.data(withJSONObject: collection), as: UTF8.self)
        default: return String(describing: value)
        }
    }
}
