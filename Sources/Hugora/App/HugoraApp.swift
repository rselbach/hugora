import SwiftUI
import AppKit
import Sparkle

@main
struct HugoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var editorState = EditorState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspaceStore)
                .environmentObject(editorState)
                .onAppear {
                    appDelegate.editorState = editorState
                    appDelegate.workspaceStore = workspaceStore
                    appDelegate.handleLaunchArguments()
                }
        }
        .commands {
            AppCommands(editorState: editorState, updater: updaterController.updater)
            WorkspaceCommands(workspaceStore: workspaceStore)
        }

        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var editorState: EditorState?
    var workspaceStore: WorkspaceStore?
    private var didHandleLaunchArgs = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editorState, editorState.isDirty else { return .terminateNow }

        // With auto-save on, quitting mid-debounce just flushes the pending
        // save. With auto-save off, the user chose manual control — never
        // overwrite their file without asking.
        if !editorState.autoSaveEnabled {
            let alert = NSAlert()
            alert.messageText = "You have unsaved changes"
            alert.informativeText = "Do you want to save the changes to \u{201C}\(editorState.title)\u{201D} before quitting?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save and Quit")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard Changes")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertThirdButtonReturn:
                return .terminateNow
            default:
                return .terminateCancel
            }
        }

        editorState.saveCurrentIfDirty()
        // A failed save leaves the document dirty; stay open so the error
        // alert is visible instead of quitting past it.
        return editorState.isDirty ? .terminateCancel : .terminateNow
    }

    func handleLaunchArguments() {
        guard !didHandleLaunchArgs else { return }
        didHandleLaunchArgs = true

        let args = ProcessInfo.processInfo.arguments
        guard let openIndex = args.firstIndex(of: "--open"),
              openIndex + 1 < args.count else { return }

        let folderPath = args[openIndex + 1]
        let url = URL(fileURLWithPath: folderPath)

        DispatchQueue.main.async { [weak self] in
            self?.workspaceStore?.openFolder(url)
        }
    }
}
