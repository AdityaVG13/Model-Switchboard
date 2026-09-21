import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func markProfile(_ profile: String, running: Bool, ready: Bool) {
        guard let index = statuses.firstIndex(where: { $0.profile == profile }) else { return }
        var updated = statuses
        updated[index] = updated[index].updating(running: running, ready: ready)
        statuses = updated
    }

    func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
