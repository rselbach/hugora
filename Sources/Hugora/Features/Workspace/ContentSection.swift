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
    static func < (lhs: ContentSection, rhs: ContentSection) -> Bool {
        // (root) always comes last
        if lhs.name == "(root)" { return false }
        if rhs.name == "(root)" { return true }

        let priority = ["blog", "posts", "pages"]
        let lhsIdx = priority.firstIndex(of: lhs.name.lowercased()) ?? Int.max
        let rhsIdx = priority.firstIndex(of: rhs.name.lowercased()) ?? Int.max
        
        if lhsIdx != rhsIdx {
            return lhsIdx < rhsIdx
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
