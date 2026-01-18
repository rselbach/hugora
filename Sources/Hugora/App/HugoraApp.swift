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
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        editorState?.saveCurrentIfDirty()
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
