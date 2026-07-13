import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var editorState: EditorState
    @EnvironmentObject private var hugoServer: HugoServerController
    @StateObject private var viewModel = EditorViewModel()
    @State private var showSidebar = true
    @State private var showPostLinkPicker = false
    @State private var postLinkTarget: EditorTextView?

    var body: some View {
        HSplitView {
            if showSidebar {
                ContentListView()
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 350)
            }

            editorPane
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if editorState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .help("Loading...")
                        .accessibilityLabel("Loading document")
                } else if editorState.justSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Saved")
                        .accessibilityLabel("Document saved")
                } else if editorState.isDirty {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .help("Unsaved changes")
                        .accessibilityLabel("Document has unsaved changes")
                }

                previewServerIndicator

                Button {
                    withAnimation { showSidebar.toggle() }
                } label: {
                    Label("Posts", systemImage: "sidebar.left")
                }
                .accessibilityLabel("Toggle sidebar")
            }
        }
        .alert(
            "Editor Error",
            isPresented: Binding(
                get: { editorState.lastError != nil },
                set: { if !$0 { editorState.lastError = nil } }
            )
        ) {
            Button("OK") {
                editorState.lastError = nil
            }
        } message: {
            Text(editorState.lastError?.localizedDescription ?? "An unknown editor error occurred.")
        }
        .navigationTitle(editorState.title)
        .onAppear {
            workspaceStore.onOpenFile = { [weak editorState, weak workspaceStore] url in
                guard let editorState, let workspaceStore else { return }
                let item = workspaceStore.sections
                    .flatMap { $0.items }
                    .first { $0.url == url }
                guard let item else { return }
                editorState.openItem(item)
            }

            // Cover a session restore that completed before this view appeared.
            syncEditorContext()
            viewModel.setText(editorState.content)
        }
        // Follow the current item wherever it changes — open, session
        // restore finishing after onAppear, or auto-rename-on-save moving
        // the bundle folder — so the image context never goes stale.
        .onReceive(editorState.$currentItem) { _ in
            DispatchQueue.main.async { syncEditorContext() }
        }
        .onReceive(workspaceStore.$currentFolderURL) { _ in
            DispatchQueue.main.async {
                syncEditorContext()
                stopPreviewIfWorkspaceChanged()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .insertPostLink)) { _ in
            guard editorState.currentItem != nil else { return }
            // Capture the focused editor before the sheet steals focus.
            postLinkTarget = NSApp.keyWindow?.firstResponder as? EditorTextView
            showPostLinkPicker = true
        }
        .sheet(isPresented: $showPostLinkPicker) {
            PostLinkPickerView(
                items: workspaceStore.sections.flatMap(\.items),
                onSelect: { item in
                    insertPostLink(to: item)
                    showPostLinkPicker = false
                },
                onCancel: { showPostLinkPicker = false }
            )
        }
    }

    private func insertPostLink(to item: ContentItem) {
        guard let contentRoot = workspaceStore.contentDirectoryURL,
            let relrefPath = item.relrefPath(contentRoot: contentRoot),
            let editor = postLinkTarget
        else { return }
        editor.insertPostLink(relrefPath: relrefPath, fallbackText: item.title)
    }

    @ViewBuilder
    private var previewServerIndicator: some View {
        switch hugoServer.state {
        case .stopped:
            EmptyView()
        case .starting:
            ProgressView()
                .controlSize(.small)
                .help("Preview server starting…")
                .accessibilityLabel("Preview server starting")
        case .running:
            Button {
                hugoServer.openInBrowser()
            } label: {
                Image(systemName: "globe")
                    .foregroundStyle(.green)
            }
            .help("Preview server running — open in browser")
            .accessibilityLabel("Open preview in browser")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Preview server failed: \(message)")
                .accessibilityLabel("Preview server failed")
        }
    }

    private func stopPreviewIfWorkspaceChanged() {
        guard let servedSite = hugoServer.siteURL else { return }
        if workspaceStore.currentFolderURL?.standardizedFileURL != servedSite.standardizedFileURL {
            hugoServer.stop()
        }
    }

    /// Re-derives the editor's workspace-dependent context from settled
    /// state. Called via an async hop because @Published emits on willSet.
    private func syncEditorContext() {
        editorState.contentRootURL = workspaceStore.contentDirectoryURL
        if let item = editorState.currentItem, let siteURL = workspaceStore.currentFolderURL {
            viewModel.imageContext = ImageContext(postURL: item.url, siteURL: siteURL)
        } else {
            viewModel.imageContext = nil
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        if editorState.currentItem != nil {
            EditorView(
                text: contentBinding,
                viewModel: viewModel,
                initialCursorPosition: editorState.cursorPosition,
                initialScrollPosition: editorState.scrollPosition,
                onCursorChange: { editorState.cursorPosition = $0 },
                onScrollChange: { editorState.scrollPosition = $0 }
            )
            .frame(minWidth: 400)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a post to edit")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { editorState.content },
            set: { newValue in
                editorState.updateContent(newValue)
            }
        )
    }

}

#Preview {
    ContentView()
        .environmentObject(WorkspaceStore())
        .environmentObject(EditorState())
        .environmentObject(HugoServerController())
}
