import Foundation
import Testing
import ModelSwitchboardCore

@testable import ModelSwitchboardApp

@Test func sshInvocationAlwaysEndsOptionsBeforeDestination() {
    let arguments = SSHInvocation.arguments(
        to: SSHInvocation.Target(
            destination: "gpuadmin@spark.local",
            sshPort: 2222,
            identityFile: "~/.ssh/spark_ed25519",
            identityAgent: "/tmp/agent.sock"
        ),
        extraOptions: ["-o", "ConnectTimeout=10"],
        remoteCommand: "echo ok"
    )
    let joined = arguments.joined(separator: " ")
    #expect(arguments.contains("BatchMode=yes"))
    #expect(arguments.contains("-p"))
    #expect(arguments.contains("2222"))
    #expect(arguments.contains("IdentityAgent=/tmp/agent.sock"))
    #expect(joined.contains("/.ssh/spark_ed25519"))
    #expect(!joined.contains("~"))
    #expect(arguments.contains("--"))
    let dash = arguments.firstIndex(of: "--")
    #expect(dash != nil)
    #expect(arguments[dash! + 1] == "gpuadmin@spark.local")
    #expect(arguments.last == "echo ok")
    #expect(arguments.firstIndex(of: "gpuadmin@spark.local") == dash! + 1)
}

@Test func sshInvocationOmitsDefaultPortAndEmptyIdentity() {
    let ssh = GatewayConfig.Connection.SSH(sshUser: "a", sshHost: "box", sshPort: 22)
    let arguments = SSHInvocation.arguments(to: SSHInvocation.Target(ssh))
    #expect(!arguments.contains("-p"))
    #expect(!arguments.contains("-i"))
    #expect(!arguments.contains(where: { $0.hasPrefix("IdentityAgent=") }))
    #expect(Array(arguments.suffix(2)) == ["--", "a@box"])
}

@Test func sshAuthSockFallsBackToLaunchctlWhenAppHasNone() {
    let sock = SSHInvocation.resolvedSSHAuthSock(
        env: [:],
        fileExists: { $0 == "/tmp/fake-agent.sock" },
        launchctlValue: { " /tmp/fake-agent.sock\n" }
    )
    #expect(sock == "/tmp/fake-agent.sock")
}
