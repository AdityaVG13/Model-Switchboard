import Foundation
import AppKit

extension MenuBarContentView {
    static let appVersion: String = {
        // Override hook for preview/screenshot tooling running outside the app bundle.
        if let override = ProcessInfo.processInfo.environment["MSW_VERSION_OVERRIDE"], !override.isEmpty {
            return override
        }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()
}
