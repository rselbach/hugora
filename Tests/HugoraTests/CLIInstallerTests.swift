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
}
