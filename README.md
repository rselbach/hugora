# Hugora

A Typora-like WYSIWYG Markdown editor for macOS, built specifically for editing [Hugo](https://gohugo.io) blogs.

## ⚠️ Fair Warning

**This is a personal project.** I built Hugora to edit my own blog at [rselbach.com](https://rselbach.com). It scratches my itch, follows my workflow, and makes the assumptions I need it to make.

It is **not** designed to be a flexible, general-purpose Markdown editor. There are plenty of excellent options out there if that's what you're looking for (Typora, iA Writer, Obsidian, etc.).

That said, if Hugora happens to fit your needs too, you're welcome to use it. Just don't expect it to bend over backwards to accommodate every Hugo setup under the sun.

## Features

- Live WYSIWYG Markdown editing (rich styling over source text)
- Hugo front matter support
- Workspace file browser for navigating your Hugo content directory
- Heading outline panel
- Focus and typewriter modes
- Auto-pairing for brackets, quotes, etc.
- macOS native (SwiftUI + AppKit)

## Requirements

- macOS 14.0+

## Building from Source

```bash
# Build
swift build

# Run
swift run Hugora

# Build release app bundle
just bundle
```

## License

MIT — see [LICENSE](LICENSE).
