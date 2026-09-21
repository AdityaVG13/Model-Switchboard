import Foundation

let controllerLaunchAgentPlistName = "io.modelswitchboard.controller.plist"

/// Bundle layout used by ``ControllerServiceManager`` so tests can inject an incomplete app.
struct ControllerBundleLayout {
    var resourceURL: URL?
    var bundleURL: URL
    var fileManager: FileManager

    init(
        resourceURL: URL?,
        bundleURL: URL,
        fileManager: FileManager = .default
    ) {
        self.resourceURL = resourceURL
        self.bundleURL = bundleURL
        self.fileManager = fileManager
    }

    static var main: ControllerBundleLayout {
        ControllerBundleLayout(
            resourceURL: Bundle.main.resourceURL,
            bundleURL: Bundle.main.bundleURL
        )
    }
}
