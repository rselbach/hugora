import SwiftUI

/// Structured editing panel for the current post's frontmatter. Reads
/// values through FrontmatterParser and writes them back through
/// FrontmatterRewriter, so the document text stays the source of truth.
struct FrontmatterInspectorView: View {
    private enum EditableField: Hashable {
        case title
        case slug
        case description
    }

    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var editorState: EditorState

    @FocusState private var focusedField: EditableField?
    @State private var title = ""
    @State private var slug = ""
    @State private var postDescription = ""
    @State private var date = Date()
    @State private var hasDate = false
    @State private var isDraft = false
    @State private var tags: [String] = []
    @State private var categories: [String] = []
    @State private var newTag = ""
    @State private var newCategory = ""
    /// Guards value-change handlers while state is being loaded from the
    /// document, so reloads don't echo back as edits.
    @State private var isReloading = false
    /// Text fields keep local drafts while they are being edited. A draft is
    /// cleared only after it has been written back to the document.
    @State private var dirtyFields: Set<EditableField> = []
    @State private var draftItemURL: URL?

    private static let isoLocalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    /// Rough limit search engines display for meta descriptions.
    private static let descriptionTarget = 155

    var body: some View {
        Group {
            if detectFrontmatterBlock(in: editorState.content) != nil {
                inspectorForm
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No front matter in this post")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            draftItemURL = editorState.currentItem?.url
            reload()
        }
        .onReceive(editorState.$currentItem) { item in
            DispatchQueue.main.async {
                guard draftItemURL != item?.url else { return }
                draftItemURL = item?.url
                dirtyFields.removeAll()
                reload()
            }
        }
        .onReceive(editorState.$content) { _ in
            DispatchQueue.main.async { reload() }
        }
        .onChange(of: focusedField) { oldField, _ in
            if let oldField {
                commitPendingEdit(oldField)
                reload()
            }
        }
    }

    private var inspectorForm: some View {
        Form {
            Section("Post") {
                TextField("Title", text: titleBinding)
                    .focused($focusedField, equals: .title)
                    .onSubmit { commitPendingEdit(.title) }

                TextField("Slug", text: slugBinding)
                    .focused($focusedField, equals: .slug)
                    .onSubmit { commitPendingEdit(.slug) }

                Toggle("Draft", isOn: $isDraft)
                    .onChange(of: isDraft) { _, newValue in
                        guard !isReloading else { return }
                        commit("draft", .bool(newValue))
                    }

                if hasDate {
                    DatePicker("Date", selection: $date)
                        .onChange(of: date) { _, newValue in
                            guard !isReloading else { return }
                            commit("date", .raw(Self.isoLocalFormatter.string(from: newValue)))
                        }
                }
            }

            Section("Description") {
                TextField("Meta description", text: descriptionBinding, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .description)
                    .onSubmit { commitPendingEdit(.description) }

                Text("\(postDescription.count) characters · ≤\(Self.descriptionTarget) recommended")
                    .font(.caption)
                    .foregroundStyle(postDescription.count > Self.descriptionTarget + 5 ? .orange : .secondary)
            }

            taxonomySection(
                header: "Tags",
                key: "tags",
                terms: $tags,
                newTerm: $newTag,
                suggestions: workspaceStore.allTags
            )

            taxonomySection(
                header: "Categories",
                key: "categories",
                terms: $categories,
                newTerm: $newCategory,
                suggestions: workspaceStore.allCategories
            )
        }
        .formStyle(.grouped)
        .onDisappear(perform: commitPendingEdits)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { title },
            set: {
                title = $0
                dirtyFields.insert(.title)
                commitPendingEdit(.title)
            }
        )
    }

    private var slugBinding: Binding<String> {
        Binding(
            get: { slug },
            set: {
                slug = $0
                dirtyFields.insert(.slug)
                commitPendingEdit(.slug)
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { postDescription },
            set: {
                postDescription = $0
                dirtyFields.insert(.description)
                commitPendingEdit(.description)
            }
        )
    }

    @ViewBuilder
    private func taxonomySection(
        header: String,
        key: String,
        terms: Binding<[String]>,
        newTerm: Binding<String>,
        suggestions: [String]
    ) -> some View {
        Section(header) {
            if !terms.wrappedValue.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading) {
                    ForEach(terms.wrappedValue, id: \.self) { term in
                        HStack(spacing: 2) {
                            Text(term)
                                .lineLimit(1)
                            Button {
                                setTerms(terms.wrappedValue.filter { $0 != term }, key: key, binding: terms)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(term)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                TextField("Add \(header.lowercased())", text: newTerm)
                    .onSubmit {
                        addTerm(newTerm.wrappedValue, key: key, binding: terms)
                        newTerm.wrappedValue = ""
                    }

                let unused = suggestions.filter { !terms.wrappedValue.contains($0) }
                if !unused.isEmpty {
                    Menu {
                        ForEach(unused, id: \.self) { suggestion in
                            Button(suggestion) {
                                addTerm(suggestion, key: key, binding: terms)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .accessibilityLabel("Add existing \(header.lowercased())")
                }
            }
        }
    }

    private func addTerm(_ raw: String, key: String, binding: Binding<[String]>) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !binding.wrappedValue.contains(term) else { return }
        setTerms(binding.wrappedValue + [term], key: key, binding: binding)
    }

    private func setTerms(_ terms: [String], key: String, binding: Binding<[String]>) {
        binding.wrappedValue = terms
        if terms.isEmpty {
            remove(key)
        } else {
            commit(key, .stringArray(terms))
        }
    }

    private func commitPendingEdits() {
        for field in Array(dirtyFields) {
            commitPendingEdit(field)
        }
    }

    private func commitPendingEdit(_ field: EditableField) {
        guard dirtyFields.contains(field) else { return }

        let didCommit: Bool
        switch field {
        case .title:
            didCommit = commit("title", .string(title))
        case .slug:
            didCommit = commitSlug()
        case .description:
            didCommit = commitDescription()
        }

        if didCommit {
            dirtyFields.remove(field)
        }
    }

    private func commitSlug() -> Bool {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let didRemove = remove("slug")
            if didRemove {
                slug = ""
            }
            return didRemove
        }
        let didCommit = commit("slug", .string(trimmed))
        if didCommit {
            slug = trimmed
        }
        return didCommit
    }

    private func commitDescription() -> Bool {
        let trimmed = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let didRemove = remove("description")
            if didRemove {
                postDescription = ""
            }
            return didRemove
        }
        let didCommit = commit("description", .string(trimmed))
        if didCommit {
            postDescription = trimmed
        }
        return didCommit
    }

    @discardableResult
    private func commit(_ key: String, _ value: FrontmatterValue) -> Bool {
        guard let updated = FrontmatterRewriter.set(key, to: value, in: editorState.content) else {
            reportRewriteFailure(for: key)
            return false
        }
        editorState.updateContent(updated)
        return confirmRewrite(updated, key: key)
    }

    @discardableResult
    private func remove(_ key: String) -> Bool {
        guard let updated = FrontmatterRewriter.remove(key, in: editorState.content) else {
            reportRewriteFailure(for: key)
            return false
        }
        editorState.updateContent(updated)
        return confirmRewrite(updated, key: key)
    }

    private func confirmRewrite(_ updated: String, key: String) -> Bool {
        guard editorState.content == updated else {
            reportRewriteFailure(for: key)
            return false
        }
        return true
    }

    private func reportRewriteFailure(for key: String) {
        editorState.lastError = FrontmatterInspectorError.rewriteFailed(key)
    }

    private func reload() {
        isReloading = true
        defer { isReloading = false }

        let content = editorState.content
        if focusedField != .title, !dirtyFields.contains(.title) {
            title = FrontmatterParser.value(forKey: "title", in: content) ?? ""
        }
        if focusedField != .slug, !dirtyFields.contains(.slug) {
            slug = FrontmatterParser.value(forKey: "slug", in: content) ?? ""
        }
        if focusedField != .description, !dirtyFields.contains(.description) {
            postDescription = FrontmatterParser.value(forKey: "description", in: content) ?? ""
        }
        isDraft = FrontmatterParser.bool(forKey: "draft", in: content) ?? false
        if let parsedDate = FrontmatterParser.date(forKey: "date", in: content) {
            date = parsedDate
            hasDate = true
        } else {
            hasDate = false
        }
        tags = FrontmatterParser.stringArray(forKey: "tags", in: content)
        categories = FrontmatterParser.stringArray(forKey: "categories", in: content)
    }
}

private enum FrontmatterInspectorError: LocalizedError {
    case rewriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .rewriteFailed(let key):
            return "Could not update the \(key) front matter field."
        }
    }
}
