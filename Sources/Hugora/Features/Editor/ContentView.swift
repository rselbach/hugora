import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var editorState: EditorState
    @StateObject private var viewModel = EditorViewModel()
    @State private var showSidebar = true

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
                if editorState.isDirty {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .help("Unsaved changes")
                }

                Button {
                    withAnimation { showSidebar.toggle() }
                } label: {
                    Label("Posts", systemImage: "sidebar.left")
                }
            }
        }
        .navigationTitle(editorState.title)
        .onAppear {
            workspaceStore.onOpenFile = { [weak editorState, weak viewModel, weak workspaceStore] url in
                guard let editorState, let viewModel, let workspaceStore else { return }
                let item = workspaceStore.sections
                    .flatMap { $0.items }
                    .first { $0.url == url }
                guard let item else { return }
                editorState.openItem(item)
                viewModel.setText(editorState.content)
                if let siteURL = workspaceStore.currentFolderURL {
                    viewModel.imageContext = ImageContext(postURL: item.url, siteURL: siteURL)
                }
            }

            // Set up image context for restored session
            if let item = editorState.currentItem,
               let siteURL = workspaceStore.currentFolderURL {
                viewModel.imageContext = ImageContext(postURL: item.url, siteURL: siteURL)
                viewModel.setText(editorState.content)
            }
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
}
