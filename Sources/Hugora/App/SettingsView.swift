import SwiftUI

struct SettingsView: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage("editorLineSpacing") private var lineSpacing: Double = 1.4
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled = true
    @AppStorage("spellCheckEnabled") private var spellCheckEnabled = true
    @AppStorage("autoRenameOnSave") private var autoRenameOnSave = false

    var body: some View {
        TabView {
            GeneralSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                autoSaveEnabled: $autoSaveEnabled,
                spellCheckEnabled: $spellCheckEnabled,
                autoRenameOnSave: $autoRenameOnSave
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            EditorSettingsView()
                .tabItem {
                    Label("Editor", systemImage: "text.alignleft")
                }

            ThemeSettingsView()
                .tabItem {
                    Label("Themes", systemImage: "paintpalette")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var autoSaveEnabled: Bool
    @Binding var spellCheckEnabled: Bool
    @Binding var autoRenameOnSave: Bool

    var body: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Size:")
                    Slider(value: $fontSize, in: 10...32, step: 1)
                    Text("\(Int(fontSize))pt")
                        .frame(width: 40)
                }

                HStack {
                    Text("Line Spacing:")
                    Slider(value: $lineSpacing, in: 1.0...2.5, step: 0.1)
                    Text(String(format: "%.1f", lineSpacing))
                        .frame(width: 40)
                }
            }

            Section("Behavior") {
                Toggle("Auto-save documents", isOn: $autoSaveEnabled)
                Toggle("Auto-rename on save (date-slug)", isOn: $autoRenameOnSave)
                Toggle("Spell checking", isOn: $spellCheckEnabled)
            }
        }
        .padding()
    }
}

struct EditorSettingsView: View {
    @AppStorage("autoPairEnabled") private var autoPairEnabled = true
    @AppStorage("newPostFormat") private var newPostFormat = ContentFormat.bundle.rawValue

    var body: some View {
        Form {
            Section("Typing") {
                Toggle("Auto-pair brackets and quotes", isOn: $autoPairEnabled)
            }

            Section("New Posts") {
                Picker("New post format", selection: $newPostFormat) {
                    ForEach(ContentFormat.allCases, id: \.rawValue) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .padding()
    }
}

struct ThemeSettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = "Default"

    private let themes = ["Default", "GitHub", "Dracula", "Solarized Light", "Solarized Dark", "rselbach.com"]

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Editor Theme", selection: $selectedTheme) {
                    ForEach(themes, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
