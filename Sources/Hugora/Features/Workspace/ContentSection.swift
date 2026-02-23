import Foundation

struct ContentSection: Identifiable, Equatable, Comparable {
    var id: String { name }
    let name: String           // directory name, e.g. "blog", "pages", "docs"
    let url: URL               // full path to the section directory
    var items: [ContentItem]   // content items in this section
    
    var displayName: String {
        // Capitalize first letter for display
        name.prefix(1).uppercased() + name.dropFirst()
    }
    
    var itemCount: Int { items.count }
    
    // Sort sections: blog/posts/pages first, (root) last, others alphabetically
    private static let priorityMap: [String: Int] = ["blog": 0, "posts": 1, "pages": 2]

    static func < (lhs: ContentSection, rhs: ContentSection) -> Bool {
        if lhs.name == "(root)" { return false }
        if rhs.name == "(root)" { return true }

        let lhsIdx = priorityMap[lhs.name.lowercased()] ?? Int.max
        let rhsIdx = priorityMap[rhs.name.lowercased()] ?? Int.max

        if lhsIdx != rhsIdx {
            return lhsIdx < rhsIdx
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
