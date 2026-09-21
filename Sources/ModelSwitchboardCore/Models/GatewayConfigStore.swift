import Foundation

/// Persists remote gateway configurations as JSON in UserDefaults.
public enum GatewayConfigStore {
    public static let defaultsKey = "modelswitchboard.gateways.v1"
    public static let corruptBackupKey = "modelswitchboard.gateways.v1.corrupt"

    public enum LoadResult: Equatable {
        case missing
        case loaded([GatewayConfig])
        /// On-disk blob failed to decode. Callers must not treat this as an
        /// intentional empty list and must not persist `[]` over the blob.
        case corrupt
    }

    public static func loadResult(from defaults: UserDefaults = .standard) -> LoadResult {
        guard let data = defaults.data(forKey: defaultsKey) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode([GatewayConfig].self, from: data))
        } catch {
            if defaults.data(forKey: corruptBackupKey) == nil {
                defaults.set(data, forKey: corruptBackupKey)
            }
            return .corrupt
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> [GatewayConfig] {
        switch loadResult(from: defaults) {
        case .missing, .corrupt:
            return []
        case .loaded(let gateways):
            return gateways
        }
    }

    public static func save(_ gateways: [GatewayConfig], to defaults: UserDefaults = .standard) {
        // Never clobber a corrupt blob with an accidental empty write - that
        // permanently deletes every remote gateway after a schema glitch.
        if gateways.isEmpty, case .corrupt = loadResult(from: defaults) {
            return
        }
        guard let data = try? JSONEncoder().encode(gateways) else { return }
        defaults.set(data, forKey: defaultsKey)
        defaults.removeObject(forKey: corruptBackupKey)
    }
}
