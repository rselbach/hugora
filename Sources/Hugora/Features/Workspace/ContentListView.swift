import SwiftUI

struct ContentListView: View {
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
                Text("CONTENT")
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
        } else if !workspaceStore.sections.isEmpty {
            sectionList
        } else if workspaceStore.currentFolderURL != nil {
            emptyContentState
        } else {
            emptyState
        }
    }

    private var sectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(workspaceStore.sections) { section in
                    SectionGroup(section: section)
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

    private var emptyContentState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No content yet")
                .foregroundStyle(.secondary)
            Text("Add content sections to your Hugo site")
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

struct SectionGroup: View {
    let section: ContentSection
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(section.items) { item in
                ContentRow(item: item)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(section.displayName)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(section.itemCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

struct ContentRow: View {
    let item: ContentItem

    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    if let date = item.date {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    if item.format == .bundle {
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
            workspaceStore.openFile(item.url)
        }
        .contextMenu {
            Button("Open") {
                workspaceStore.openFile(item.url)
            }
            Button("Reveal in Finder") {
                let revealURL = item.format == .bundle
                    ? item.url.deletingLastPathComponent()
                    : item.url
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            }
            Divider()
            Button("Delete…", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .confirmationDialog(
            "Delete \"\(item.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                workspaceStore.deleteContent(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the content to Trash.")
        }
    }
}

#Preview {
    ContentListView()
        .environmentObject(WorkspaceStore())
        .frame(width: 250, height: 400)
}
