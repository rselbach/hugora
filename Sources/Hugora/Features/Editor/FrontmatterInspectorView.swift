import SwiftUI

/// Structured editing panel for the current post's frontmatter. Reads
/// values through FrontmatterParser and writes them back through
/// FrontmatterRewriter, so the document text stays the source of truth.
struct FrontmatterInspectorView: View {
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @EnvironmentObject private var editorState: EditorState

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
        .onAppear(perform: reload)
        .onReceive(editorState.$content) { _ in
            DispatchQueue.main.async { reload() }
        }
    }

    private var inspectorForm: some View {
        Form {
            Section("Post") {
                TextField("Title", text: $title)
                    .onSubmit { commit("title", .string(title)) }

                TextField("Slug", text: $slug)
                    .onSubmit { commitSlug() }

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
                TextField("Meta description", text: $postDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .onSubmit { commitDescription() }

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
            guard let updated = FrontmatterRewriter.remove(key, in: editorState.content) else { return }
            editorState.updateContent(updated)
        } else {
            commit(key, .stringArray(terms))
        }
    }

    private func commitSlug() {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard let updated = FrontmatterRewriter.remove("slug", in: editorState.content) else { return }
            editorState.updateContent(updated)
        } else {
            commit("slug", .string(trimmed))
        }
    }

    private func commitDescription() {
        let trimmed = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard let updated = FrontmatterRewriter.remove("description", in: editorState.content) else { return }
            editorState.updateContent(updated)
        } else {
            commit("description", .string(trimmed))
        }
    }

    private func commit(_ key: String, _ value: FrontmatterValue) {
        guard let updated = FrontmatterRewriter.set(key, to: value, in: editorState.content) else { return }
        editorState.updateContent(updated)
    }

    private func reload() {
        isReloading = true
        defer { isReloading = false }

        let content = editorState.content
        title = FrontmatterParser.value(forKey: "title", in: content) ?? ""
        slug = FrontmatterParser.value(forKey: "slug", in: content) ?? ""
        postDescription = FrontmatterParser.value(forKey: "description", in: content) ?? ""
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
