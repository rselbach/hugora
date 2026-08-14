import Foundation
import Markdown
import Testing

@testable import Hugora

@Suite("Editor Modes")
struct EditorModesTests {
    @Test("Heading outline preserves order, levels, and Unicode ranges")
    func headingOutline() throws {
        let text = """
            # Greendale

            ## Troy & Abed

            Café
            ----
            """
        let document = Document(parsing: text)
        var collector = HeadingOutlineCollector(text: text)
        collector.visit(document)

        #expect(collector.headings.map(\.title) == ["Greendale", "Troy & Abed", "Café"])
        #expect(collector.headings.map(\.level) == [1, 2, 2])
        let cafe = try #require(collector.headings.last)
        #expect((text as NSString).substring(with: cafe.range).contains("Café"))
    }

    @Test("Focus mode dims only content outside the current paragraph")
    func focusRanges() {
        let ranges = EditorViewModel.dimmedRanges(
            visibleRange: NSRange(location: 10, length: 100),
            focusedRange: NSRange(location: 30, length: 20)
        )

        #expect(ranges == [NSRange(location: 10, length: 20), NSRange(location: 50, length: 60)])
    }

    @Test("Focus mode dims the visible range when its paragraph is offscreen")
    func offscreenFocusRange() {
        #expect(
            EditorViewModel.dimmedRanges(
                visibleRange: NSRange(location: 100, length: 40),
                focusedRange: NSRange(location: 10, length: 20)
            ) == [NSRange(location: 100, length: 40)]
        )
    }

    @Test("An immediate edit after loading is still parsed")
    @MainActor
    func immediateEditAfterLoad() async throws {
        let viewModel = EditorViewModel()
        viewModel.setText("# Old heading")
        viewModel.updateTextFromEditor("# New heading")

        for _ in 0..<100 where viewModel.headings.first?.title != "New heading" {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(viewModel.headings.first?.title == "New heading")
    }
}
