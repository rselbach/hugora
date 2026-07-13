import Foundation

/// A shortcode the editor can insert, with a template and the placeholder
/// to select so typing immediately fills the important argument.
struct ShortcodeTemplate: Identifiable {
    let name: String
    let template: String
    let selectionPlaceholder: String?

    var id: String { name }
}

/// Hugo's embedded shortcodes that make sense to insert from a menu.
enum ShortcodeCatalog {
    static let builtIn: [ShortcodeTemplate] = [
        ShortcodeTemplate(
            name: "figure",
            template: #"{{< figure src="image.png" alt="alt text" >}}"#,
            selectionPlaceholder: "image.png"
        ),
        ShortcodeTemplate(
            name: "highlight",
            template: "{{< highlight go >}}\ncode\n{{< /highlight >}}",
            selectionPlaceholder: "go"
        ),
        ShortcodeTemplate(
            name: "details",
            template: "{{< details summary=\"Summary\" >}}\ncontent\n{{< /details >}}",
            selectionPlaceholder: "Summary"
        ),
        ShortcodeTemplate(
            name: "youtube",
            template: "{{< youtube VIDEO_ID >}}",
            selectionPlaceholder: "VIDEO_ID"
        ),
        ShortcodeTemplate(
            name: "vimeo",
            template: "{{< vimeo VIDEO_ID >}}",
            selectionPlaceholder: "VIDEO_ID"
        ),
        ShortcodeTemplate(
            name: "x",
            template: #"{{< x user="USER" id="ID" >}}"#,
            selectionPlaceholder: "USER"
        ),
        ShortcodeTemplate(
            name: "instagram",
            template: "{{< instagram POST_ID >}}",
            selectionPlaceholder: "POST_ID"
        ),
        ShortcodeTemplate(
            name: "qr",
            template: #"{{< qr text="TEXT" />}}"#,
            selectionPlaceholder: "TEXT"
        ),
    ]

    /// Template for a site-defined shortcode discovered from
    /// layouts/shortcodes; parameters are unknown, so a placeholder is left
    /// selected.
    static func siteTemplate(named name: String) -> ShortcodeTemplate {
        ShortcodeTemplate(
            name: name,
            template: "{{< \(name) params >}}",
            selectionPlaceholder: "params"
        )
    }
}
