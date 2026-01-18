import AppKit
import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var editorState: EditorState
    @State private var cliInstalled = CLIInstaller.isInstalled

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()

            Button(cliInstalled ? "Uninstall Command Line Tool…" : "Install Command Line Tool…") {
                if cliInstalled {
                    uninstallCLI()
                } else {
                    installCLI()
                }
            }
        }



        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                editorState.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(editorState.currentItem == nil || !editorState.isDirty)
        }

        CommandGroup(replacing: .help) {
            Button("Hugora Help") {
                if let url = URL(string: "https://github.com/rselbach/hugora") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func installCLI() {
        CLIInstaller.install { result in
            switch result {
            case .success:
                cliInstalled = true
                showAlert(
                    title: "Command Line Tool Installed",
                    message: "You can now use 'hugora' from Terminal.\n\nUsage: hugora [folder]"
                )
            case .failure(let error):
                if case CLIInstallerError.userCancelled = error {
                    return
                }
                showAlert(title: "Installation Failed", message: error.localizedDescription)
            }
        }
    }

    private func uninstallCLI() {
        CLIInstaller.uninstall { result in
            switch result {
            case .success:
                cliInstalled = false
                showAlert(
                    title: "Command Line Tool Uninstalled",
                    message: "The 'hugora' command has been removed."
                )
            case .failure(let error):
                if case CLIInstallerError.userCancelled = error {
                    return
                }
                showAlert(title: "Uninstall Failed", message: error.localizedDescription)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct WorkspaceCommands: Commands {
    @ObservedObject var workspaceStore: WorkspaceStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Post") {
                workspaceStore.createNewPost()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(workspaceStore.currentFolderURL == nil)

            Divider()

            Button("Open Hugo Site…") {
                workspaceStore.openFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            if workspaceStore.currentFolderURL != nil {
                Button("Close Site") {
                    workspaceStore.closeWorkspace()
                }

                Button("Refresh Posts") {
                    workspaceStore.refreshPosts()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            if !workspaceStore.recentWorkspaces.isEmpty {
                Divider()
                Menu("Recent Sites") {
                    ForEach(workspaceStore.recentWorkspaces) { ref in
                        Button(ref.displayName) {
                            workspaceStore.openRecent(ref)
                        }
                    }
                }
            }
        }
    }
}


