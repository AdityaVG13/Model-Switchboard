import Foundation

public enum LoginItemBundleIdentifiers {
    public static func companion(for bundleIdentifier: String) -> String? {
        if bundleIdentifier.hasSuffix(".plus") {
            return String(bundleIdentifier.dropLast(".plus".count)) + ".app"
        }
        if bundleIdentifier.hasSuffix(".app") {
            return String(bundleIdentifier.dropLast(".app".count)) + ".plus"
        }
        return nil
    }
}
