import Foundation
import Markdown
import SwiftUI

struct HeadingOutlineItem: Identifiable, Equatable {
    let title: String
    let level: Int
    let range: NSRange

    var id: String {
        "\(range.location):\(range.length)"
    }
}

struct HeadingOutlineCollector: MarkupWalker {
    private let text: String
    private(set) var headings: [HeadingOutlineItem] = []

    init(text: String) {
        self.text = text
    }

    mutating func visitHeading(_ heading: Heading) {
        if let sourceRange = heading.range,
            let range = convertRange(sourceRange, in: text)
        {
            headings.append(
                HeadingOutlineItem(
                    title: heading.plainText.trimmingCharacters(in: .whitespacesAndNewlines),
                    level: heading.level,
                    range: range
                ))
        }
        descendInto(heading)
    }
}

struct HeadingOutlineView: View {
    let headings: [HeadingOutlineItem]
    let onSelect: (HeadingOutlineItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outline")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            if headings.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Add headings to navigate this post.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(headings) { heading in
                            Button {
                                onSelect(heading)
                            } label: {
                                Text(heading.title.isEmpty ? "Untitled heading" : heading.title)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 12)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Level \(heading.level) heading, \(heading.title)")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}
