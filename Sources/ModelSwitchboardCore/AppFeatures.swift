import Foundation

public enum AppEdition: String, Sendable {
    case base
    case plus
}

public struct AppFeatures: Equatable, Sendable {
    public let edition: AppEdition

    public init(edition: AppEdition) {
        self.edition = edition
    }

    public var appDisplayName: String {
        switch edition {
        case .base:
            return "Model Switchboard"
        case .plus:
            return "Model Switchboard Plus"
        }
    }

    public var supportsBenchmarks: Bool {
        edition == .plus
    }

    public var supportsDashboard: Bool {
        edition == .plus
    }

    public var supportsIntegrations: Bool {
        edition == .plus
    }

    public static func from(bundle: Bundle = .main) -> AppFeatures {
        let rawValue = (bundle.object(forInfoDictionaryKey: "MSWEdition") as? String)?.lowercased()
        return AppFeatures(edition: AppEdition(rawValue: rawValue ?? "") ?? .base)
    }

    public static let base = AppFeatures(edition: .base)
    public static let plus = AppFeatures(edition: .plus)
    public static let current = AppFeatures.from()
}
