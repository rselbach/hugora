# Hugora - Hugo Blog Editor for macOS

A Typora-like WYSIWYG Markdown editor specialized for Hugo blog editing.

## Commands

```bash
swift build          # Build the app
swift test           # Run tests
swift run            # Run the app
```

## Architecture

- **Document-based SwiftUI app** with AppKit editor (NSTextView)
- **MVVM per document**: MarkdownDocument (model) + EditorViewModel (coming)
- **Live WYSIWYG**: Rich styling over source text, not HTML rendering

## Tech Stack

- Swift 5.9+ / SwiftUI + AppKit
- macOS 14+
- swift-markdown for parsing
- Sparkle for auto-updates

## Project Structure

```
Sources/Hugora/
  App/                    # App entry, commands, settings
  Documents/              # FileDocument implementation
  Features/
    Editor/               # NSTextView wrapper, styling
    Outline/              # Heading outline panel
    Workspace/            # File tree, folder management
  Resources/              # Themes, assets
```

## Implementation Phases

- [x] Phase 0: Skeleton + document lifecycle
- [x] Phase 1: Live Markdown styling (headings, emphasis, links, code)
- [x] Phase 2: Editor UX (focus/typewriter mode, auto-pair, find/replace)
- [x] Phase 3: Advanced blocks (tables) - partial, code highlighting/math/mermaid pending
- [x] Phase 4: File management workspace (file tree, folder open/close, recent folders, macOS window tabs)
- [ ] Phase 5: Export + theming + auto-updates

## Key Gotchas

1. **Cursor stability**: Never replace string content; only adjust attributes
2. **UTF-16 ranges**: NSTextView uses UTF-16; swift-markdown gives different offsets
3. **Performance**: Debounce parsing; only restyle visible range for large docs
4. **Attachments**: Math/mermaid need "enter block → show source" toggle behavior
