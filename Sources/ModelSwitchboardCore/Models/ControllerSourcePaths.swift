import Foundation

public struct ControllerSourcePaths: Equatable, Sendable {
    public let profilesDirectory: String?
    public let controllerRoot: String?

    public init(profilesDirectory: String?, controllerRoot: String?) {
        self.profilesDirectory = profilesDirectory
        self.controllerRoot = controllerRoot
    }
}

public protocol ControllerSourcePathProviding {
    var profilesDirectory: String? { get }
    var controllerRoot: String? { get }
}

public extension ControllerSourcePathProviding {
    var sourcePaths: ControllerSourcePaths {
        ControllerSourcePaths(
            profilesDirectory: profilesDirectory,
            controllerRoot: controllerRoot
        )
    }
}
