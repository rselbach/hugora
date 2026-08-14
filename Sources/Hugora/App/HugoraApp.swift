import SwiftUI
import AppKit
import Sparkle

@main
struct HugoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Sparkle can't initialize outside a real app bundle (`swift run`
        // dev builds have no Info.plist) and puts up an error dialog if it
        // tries. Leaving the updater stopped keeps the menu item disabled.
        let isBundledApp = Bundle.main.bundleIdentifier != nil
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isBundledApp,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var editorState = EditorState()
    @StateObject private var hugoServer = HugoServerController()

    var body: some Scene {
        Window("Hugora", id: "main") {
            ContentView()
                .environmentObject(workspaceStore)
                .environmentObject(editorState)
                .environmentObject(hugoServer)
                .onAppear {
                    appDelegate.editorState = editorState
                    appDelegate.workspaceStore = workspaceStore
                    appDelegate.hugoServer = hugoServer
                    appDelegate.handleLaunchArguments()
                }
                // hugora://open?path=/path/to/site — the CLI's handoff
                // channel; unlike launch arguments it also reaches an
                // already-running instance.
                .onOpenURL { url in
                    guard url.scheme == "hugora", url.host == "open" else { return }
                    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
                        !path.isEmpty
                    else { return }
                    workspaceStore.openFromExternalPath(URL(fileURLWithPath: path))
                }
        }
        .commands {
            AppCommands(editorState: editorState, updater: updaterController.updater)
            WorkspaceCommands(workspaceStore: workspaceStore)
            SiteCommands(workspaceStore: workspaceStore, hugoServer: hugoServer, editorState: editorState)
            FormatCommands(workspaceStore: workspaceStore)
            ViewCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var editorState: EditorState?
    var workspaceStore: WorkspaceStore? {
        didSet { handlePendingOpenURLs() }
    }
    var hugoServer: HugoServerController?
    private var didHandleLaunchArgs = false
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingOpenURLs.append(contentsOf: urls)
        handlePendingOpenURLs()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editorState, editorState.isDirty else { return .terminateNow }

        // With auto-save on, quitting mid-debounce just flushes the pending
        // save. With auto-save off, the user chose manual control — never
        // overwrite their file without asking.
        if !editorState.autoSaveEnabled {
            let alert = NSAlert()
            alert.messageText = "You have unsaved changes"
            alert.informativeText =
                "Do you want to save the changes to \u{201C}\(editorState.title)\u{201D} before quitting?"
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

    func applicationWillTerminate(_ notification: Notification) {
        // Kill the preview server: an orphaned hugo process would keep
        // serving (and holding the port) after the app quits.
        hugoServer?.stop()
    }

    func handleLaunchArguments() {
        guard !didHandleLaunchArgs else { return }
        didHandleLaunchArgs = true

        let args = ProcessInfo.processInfo.arguments
        guard let openIndex = args.firstIndex(of: "--open"),
            openIndex + 1 < args.count
        else { return }

        let folderPath = args[openIndex + 1]
        let url = URL(fileURLWithPath: folderPath)

        DispatchQueue.main.async { [weak self] in
            self?.workspaceStore?.openFromExternalPath(url)
        }
    }

    func handlePendingOpenURLs() {
        guard let workspaceStore, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        for url in urls {
            workspaceStore.openFromExternalPath(url)
        }
    }
}
