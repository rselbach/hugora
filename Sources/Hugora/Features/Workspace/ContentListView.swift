import SwiftUI

struct ContentListView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @State private var searchText = ""
    @State private var statusFilter: PostStatusFilter = .all

    enum PostStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case drafts = "Drafts"
        case published = "Published"

        var id: String { rawValue }

        func matches(_ item: ContentItem) -> Bool {
            switch self {
            case .all: true
            case .drafts: item.isDraft
            case .published: !item.isDraft
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if workspaceStore.currentFolderURL != nil {
                searchField
                statusFilterPicker
            }
            Divider()
            content
        }
        .background(.background)
    }

    private var statusFilterPicker: some View {
        Picker("Filter posts", selection: $statusFilter) {
            ForEach(PostStatusFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .accessibilityLabel("Filter posts by publish status")
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
        guard !query.isEmpty || statusFilter != .all else { return workspaceStore.sections }

        return workspaceStore.sections.compactMap { section in
            let filteredItems = section.items.filter { item in
                guard statusFilter.matches(item) else { return false }
                guard !query.isEmpty else { return true }
                return item.searchTitle.contains(query) || item.searchSlug.contains(query)
            }
            guard !filteredItems.isEmpty else { return nil }
            return ContentSection(name: section.name, url: section.url, items: filteredItems)
        }
    }

    private var viewState: ViewState {
        if let error = workspaceStore.lastError { return .error(error) }
        if !filteredSections.isEmpty { return .sections }
        let isFiltering =
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || statusFilter != .all
        if isFiltering, !workspaceStore.sections.isEmpty {
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
    @State private var showRenameDialog = false
    @State private var renameText = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func accessibilityDescription(for item: ContentItem) -> String {
        let dateString = item.date.map { Self.dateFormatter.string(from: $0) } ?? "no date"
        switch item.publishStatus {
        case .draft:
            return "\(item.title), \(dateString), draft"
        case .scheduled:
            return "\(item.title), \(dateString), scheduled"
        case .published:
            return "\(item.title), \(dateString)"
        }
    }

    /// The name the rename dialog starts from: the bundle folder name, or
    /// the file name without extension.
    private var currentDiskName: String {
        switch item.format {
        case .bundle:
            item.url.deletingLastPathComponent().lastPathComponent
        case .file:
            item.url.deletingPathExtension().lastPathComponent
        }
    }

    @ViewBuilder
    private func pill(_ label: String, tint: Color?) -> some View {
        Text(label)
            .font(.system(size: 9))
            .foregroundStyle(tint ?? Color.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background((tint ?? Color.secondary).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
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

                    switch item.publishStatus {
                    case .draft:
                        pill("draft", tint: .orange)
                    case .scheduled:
                        pill("scheduled", tint: .blue)
                    case .published:
                        EmptyView()
                    }

                    if item.format == .bundle {
                        pill("bundle", tint: nil)
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
                let revealURL =
                    item.format == .bundle
                    ? item.url.deletingLastPathComponent()
                    : item.url
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            }
            Divider()
            Button("Rename…") {
                renameText = currentDiskName
                showRenameDialog = true
            }
            Button("Duplicate") {
                workspaceStore.duplicateContent(item)
            }
            Divider()
            Button("Delete…", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .alert("Rename \u{201C}\(item.title)\u{201D}", isPresented: $showRenameDialog) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                workspaceStore.renameContent(item, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                item.format == .bundle
                    ? "Renames the bundle folder on disk."
                    : "Renames the file on disk (extension is kept)."
            )
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
