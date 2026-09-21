import Foundation
import OSLog

public enum ControllerStatusCache {
    static let logger = Logger(subsystem: "io.modelswitchboard.core", category: "controller-status-cache")

    public static let cacheURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/io.modelswitchboard/controller-status.json")
    }()
}
