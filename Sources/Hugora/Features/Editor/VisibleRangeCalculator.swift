import AppKit
import Foundation

/// Computes the text range that should be restyled for the current viewport.
///
/// Falls back to the full document range when layout/viewport information is
/// not ready yet. This prevents no-op style passes during initial view setup.
func computeRenderableRange(for textView: NSTextView, padding: Int = 2000) -> NSRange {
    let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
    guard fullRange.length > 0 else { return fullRange }

    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer,
          let scrollView = textView.enclosingScrollView else {
        return fullRange
    }

    layoutManager.ensureLayout(for: textContainer)
    let visibleRect = scrollView.documentVisibleRect
    guard visibleRect.width > 0, visibleRect.height > 0 else { return fullRange }

    let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
    guard glyphRange.length > 0 else { return fullRange }

    let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    guard charRange.length > 0 else { return fullRange }

    let effectivePadding = min(padding, fullRange.length)
    let start = max(0, charRange.location - effectivePadding)
    let end = min(fullRange.length, NSMaxRange(charRange) + effectivePadding)
    guard end > start else { return fullRange }

    return NSRange(location: start, length: end - start)
}
