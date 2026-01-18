import SwiftUI

struct PostListView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("POSTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if let name = workspaceStore.siteName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Menu {
                Button("Open Hugo Site…") {
                    workspaceStore.openFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                if !workspaceStore.recentWorkspaces.isEmpty {
                    Divider()
                    Text("Recent")
                    ForEach(workspaceStore.recentWorkspaces) { ref in
                        Button(ref.displayName) {
                            workspaceStore.openRecent(ref)
                        }
                    }
                }

                if workspaceStore.currentFolderURL != nil {
                    Divider()
                    Button("Refresh") {
                        workspaceStore.refreshPosts()
                    }
                    .keyboardShortcut("r", modifiers: [.command])

                    Button("Close Site") {
                        workspaceStore.closeWorkspace()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = workspaceStore.lastError {
            errorState(error)
        } else if !workspaceStore.posts.isEmpty {
            postList
        } else if workspaceStore.currentFolderURL != nil {
            emptyPostsState
        } else {
            emptyState
        }
    }

    private var postList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(workspaceStore.posts) { post in
                    PostRow(post: post)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Hugo site open")
                .foregroundStyle(.secondary)
            Button("Open Hugo Site") {
                workspaceStore.openFolderPanel()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyPostsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No posts yet")
                .foregroundStyle(.secondary)
            Text("Create posts in content/blog")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ error: WorkspaceError) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Open Hugo Site") {
                workspaceStore.openFolderPanel()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct PostRow: View {
    let post: BlogPost

    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    if let date = post.date {
                        Text(dateFormatter.string(from: date))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    if post.format == .bundle {
                        Text("bundle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            workspaceStore.openFile(post.url)
        }
        .contextMenu {
            Button("Open") {
                workspaceStore.openFile(post.url)
            }
            Button("Reveal in Finder") {
                let revealURL = post.format == .bundle
                    ? post.url.deletingLastPathComponent()
                    : post.url
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            }
            Divider()
            Button("Delete…", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .confirmationDialog(
            "Delete \"\(post.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                workspaceStore.deletePost(post)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the post to Trash.")
        }
    }
}

#Preview {
    PostListView()
        .environmentObject(WorkspaceStore())
        .frame(width: 250, height: 400)
}
