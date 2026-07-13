import Testing
@testable import Hugora

@Suite("CLIInstallerError")
struct CLIInstallerErrorTests {
    @Test("Install path in use error is actionable")
    func installPathInUseMessage() {
        let error = CLIInstallerError.installPathInUse("/usr/local/bin/hugora")
        #expect(error.localizedDescription.contains("already in use"))
    }

    @Test("Not managed install error is actionable")
    func notManagedInstallMessage() {
        let error = CLIInstallerError.notManagedInstall("/usr/local/bin/hugora")
        #expect(error.localizedDescription.contains("not managed by Hugora"))
    }

    @Test("Manual command error carries the exact command")
    func manualCommandMessage() {
        let command = "sudo ln -sf '/Applications/Hugora.app/Contents/MacOS/hugora-cli' '/usr/local/bin/hugora'"
        let error = CLIInstallerError.requiresManualCommand(command: command)
        #expect(error.localizedDescription.contains(command))
        #expect(error.localizedDescription.contains("administrator privileges"))
    }
}
