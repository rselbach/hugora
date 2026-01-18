import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var editorState: EditorState
    @StateObject private var viewModel = EditorViewModel()
    @State private var showSidebar = true

    var body: some View {
        HSplitView {
            if showSidebar {
                PostListView()
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
        .onChange(of: workspaceStore.selectedFileURL) { _, newURL in
            guard let url = newURL else { return }
            openPostAtURL(url)
            workspaceStore.selectedFileURL = nil
        }
        .onAppear {
            // Set up image context for restored session
            if let post = editorState.currentPost, let blogDir = workspaceStore.blogDirectoryURL {
                viewModel.imageContext = ImageContext(postURL: post.url, blogDirectoryURL: blogDir)
                viewModel.setText(editorState.content)
            }
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        if editorState.currentPost != nil {
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

    private func openPostAtURL(_ url: URL) {
        guard let post = workspaceStore.posts.first(where: { $0.url == url }) else { return }
        editorState.openPost(post)
        viewModel.setText(editorState.content)
        
        // Set up image context for resolving image paths
        if let blogDir = workspaceStore.blogDirectoryURL {
            viewModel.imageContext = ImageContext(postURL: post.url, blogDirectoryURL: blogDir)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkspaceStore())
        .environmentObject(EditorState())
}
