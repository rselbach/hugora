import Foundation

enum PathSafety {
    /// Returns true when `candidate` is the same path as `root` or is nested under it.
    /// Resolves symlinks so a link inside the workspace pointing outside is rejected.
    /// Uses path components to enforce directory boundaries (`/site` does not match `/site2`).
    static func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateComponents = candidate.resolvingSymlinksInPath().pathComponents
        let rootComponents = root.resolvingSymlinksInPath().pathComponents

        guard candidateComponents.count >= rootComponents.count else { return false }

        for (idx, rootComponent) in rootComponents.enumerated() {
            if candidateComponents[idx] != rootComponent {
                return false
            }
        }

        return true
    }
}
