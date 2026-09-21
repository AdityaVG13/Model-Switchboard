import Foundation
import ModelSwitchboardCore

extension GatewayHub {
    func pollForceUpdateRefresh(_ live: GatewayRuntime) async -> String? {
        var lastMessage: String?
        for _ in 0..<8 {
            if Task.isCancelled { return lastMessage }
            await live.store.refresh()
            lastMessage = forceUpdateRefreshMessage(live.store.refreshState) ?? lastMessage
            if live.store.refreshState == .refreshed { return lastMessage }
            if !live.store.isRecoveringFromTransportFailure { break }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return lastMessage
    }

    func forceUpdateRefreshMessage(_ state: SwitchboardStore.RefreshState) -> String? {
        switch state {
        case .refreshed:
            return nil
        case .failed(let message), .failedShowingCached(let message), .blocked(let message):
            return message
        case .refreshing(let held):
            return held?.message
        case .idle:
            return nil
        }
    }
}
