import Foundation
import ModelSwitchboardCore

public actor ProbeRecorder {
    public private(set) var calls = 0

    public init() {}

    public func record(_ profiles: [ModelProfileStatus]) -> [String] {
        calls += 1
        return profiles.map(\.profile)
    }
}

public enum UserDefaultsTestHelpers {
    public static func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults = .standard) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public enum StressTestConfig {
    public static let iterationsKey = "MSW_STRESS_BUTTON_CLICKS"
    public static let baseURL = "http://model-switchboard-button-stress.test"
    public static let profile = "stress-profile"

    public static func iterations() -> Int {
        let rawValue = ProcessInfo.processInfo.environment[iterationsKey] ?? "100"
        return max(1, Int(rawValue) ?? 100)
    }
}
