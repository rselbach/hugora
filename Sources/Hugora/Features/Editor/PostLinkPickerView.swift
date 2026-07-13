import SwiftUI

extension Notification.Name {
    /// Posted by the Format menu to ask the front window to show the
    /// internal-link picker.
    static let insertPostLink = Notification.Name("hugora.insertPostLink")
}

/// Searchable picker over the workspace's posts; selecting one inserts a
/// `[text]({{< relref "..." >}})` link into the editor.
struct PostLinkPickerView: View {
    let items: [ContentItem]
    let onSelect: (ContentItem) -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var filteredItems: [ContentItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.searchTitle.contains(trimmed) || $0.searchSlug.contains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search posts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .onSubmit {
                    if let first = filteredItems.first {
                        onSelect(first)
                    }
                }

            Divider()

            if filteredItems.isEmpty {
                Text("No matching posts")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(item.section)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let date = item.date {
                                        Text(Self.dateFormatter.string(from: date))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Text("Return inserts the first match")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 380)
    }
}
