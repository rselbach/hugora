import AppKit
import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            checkForUpdatesViewModel.updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct AppCommands: Commands {
    @ObservedObject var editorState: EditorState
    @State private var cliInstalled = CLIInstaller.isInstalled

    private let updater: SPUUpdater

    init(editorState: EditorState, updater: SPUUpdater) {
        self.editorState = editorState
        self.updater = updater
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)

            Divider()

            Button(cliInstalled ? "Uninstall Command Line Tool…" : "Install Command Line Tool…") {
                cliInstalled ? uninstallCLI() : installCLI()
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
                if case CLIInstallerError.requiresManualCommand(let command) = error {
                    showManualCommandAlert(command: command)
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
                if case CLIInstallerError.requiresManualCommand(let command) = error {
                    showManualCommandAlert(command: command)
                    return
                }
                showAlert(title: "Uninstall Failed", message: error.localizedDescription)
            }
        }
    }

    private func showManualCommandAlert(command: String) {
        let alert = NSAlert()
        alert.messageText = "Administrator Privileges Required"
        alert.informativeText = """
            Hugora can't modify /usr/local/bin from inside the sandbox. \
            Run this command in Terminal:

            \(command)
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
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

struct ViewCommands: Commands {
    @AppStorage(DefaultsKey.showFrontmatterInspector) private var showInspector = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(showInspector ? "Hide Frontmatter Inspector" : "Show Frontmatter Inspector") {
                showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

struct FormatCommands: Commands {
    @ObservedObject var workspaceStore: WorkspaceStore

    var body: some Commands {
        CommandGroup(replacing: .textFormatting) {
            Button("Bold") {
                sendToEditor(#selector(EditorTextView.toggleBold(_:)))
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                sendToEditor(#selector(EditorTextView.toggleItalic(_:)))
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Inline Code") {
                sendToEditor(#selector(EditorTextView.toggleInlineCode(_:)))
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Strikethrough") {
                sendToEditor(#selector(EditorTextView.toggleStrikethrough(_:)))
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])

            Divider()

            Button("Insert Link") {
                sendToEditor(#selector(EditorTextView.insertLinkMarkup(_:)))
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Insert Link to Post…") {
                NotificationCenter.default.post(name: .insertPostLink, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(workspaceStore.currentFolderURL == nil)

            Divider()

            Menu("Insert Shortcode") {
                ForEach(ShortcodeCatalog.builtIn) { shortcode in
                    Button(shortcode.name) {
                        insertShortcode(shortcode)
                    }
                }

                if !workspaceStore.siteShortcodes.isEmpty {
                    Divider()
                    ForEach(workspaceStore.siteShortcodes, id: \.self) { name in
                        Button(name) {
                            insertShortcode(ShortcodeCatalog.siteTemplate(named: name))
                        }
                    }
                }
            }

            Button("Insert Summary Divider") {
                sendToEditor(#selector(EditorTextView.insertSummaryDivider(_:)))
            }
        }
    }

    /// Dispatches through the responder chain so the focused editor
    /// handles the action; a no-op when no editor has focus.
    private func sendToEditor(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    private func insertShortcode(_ shortcode: ShortcodeTemplate) {
        guard let editor = NSApp.keyWindow?.firstResponder as? EditorTextView else { return }
        editor.insertShortcodeTemplate(shortcode)
    }
}

struct SiteCommands: Commands {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var hugoServer: HugoServerController

    var body: some Commands {
        CommandMenu("Site") {
            if hugoServer.isRunning {
                Button("Stop Preview Server") {
                    hugoServer.stop()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            } else {
                Button("Start Preview Server") {
                    guard let siteURL = workspaceStore.currentFolderURL else { return }
                    hugoServer.start(siteURL: siteURL)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(workspaceStore.currentFolderURL == nil)
            }

            Button("Open Preview in Browser") {
                hugoServer.openInBrowser()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(
                {
                    guard case .running = hugoServer.state else { return true }
                    return false
                }())
        }
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
