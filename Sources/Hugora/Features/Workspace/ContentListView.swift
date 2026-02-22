import SwiftUI

struct ContentListView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if workspaceStore.currentFolderURL != nil {
                searchField
            }
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
            .accessibilityLabel("Workspace actions menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        TextField("Search posts", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private enum ViewState {
        case error(WorkspaceError)
        case sections
        case noResults
        case emptyContent
        case noWorkspace
    }

    private var filteredSections: [ContentSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return workspaceStore.sections }

        return workspaceStore.sections.compactMap { section in
            let filteredItems = section.items.filter { item in
                item.title.lowercased().contains(query) || item.slug.lowercased().contains(query)
            }
            guard !filteredItems.isEmpty else { return nil }
            return ContentSection(name: section.name, url: section.url, items: filteredItems)
        }
    }

    private var viewState: ViewState {
        if let error = workspaceStore.lastError { return .error(error) }
        if !filteredSections.isEmpty { return .sections }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !workspaceStore.sections.isEmpty {
            return .noResults
        }
        if workspaceStore.currentFolderURL != nil { return .emptyContent }
        return .noWorkspace
    }

    @ViewBuilder
    private var content: some View {
        switch viewState {
        case .error(let error):
            errorState(error)
        case .sections:
            sectionList
        case .noResults:
            noResultsState
        case .emptyContent:
            emptyContentState
        case .noWorkspace:
            emptyState
        }

        if workspaceStore.isLoading {
            loadingOverlay
        }
    }

    private var sectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredSections) { section in
                    SectionGroup(section: section)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No matching posts")
                .foregroundStyle(.secondary)
            Text("Try a different title or slug")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.1)

            ProgressView()
                .controlSize(.large)
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
        }
        .allowsHitTesting(false)
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
        .accessibilityLabel("Section: \(section.displayName), \(section.itemCount) items")
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

    private func accessibilityDescription(for item: ContentItem) -> String {
        let dateString = item.date.map { Self.dateFormatter.string(from: $0) } ?? "no date"
        return "\(item.title), \(dateString)"
    }

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
        .accessibilityLabel(accessibilityDescription(for: item))
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
