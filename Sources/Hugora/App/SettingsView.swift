import SwiftUI

struct SettingsView: View {
    @AppStorage(DefaultsKey.editorFontSize) private var fontSize: Double = 16
    @AppStorage(DefaultsKey.editorLineSpacing) private var lineSpacing: Double = 1.4
    @AppStorage(DefaultsKey.autoSaveEnabled) private var autoSaveEnabled = true
    @AppStorage(DefaultsKey.spellCheckEnabled) private var spellCheckEnabled = true
    @AppStorage(DefaultsKey.autoRenameOnSave) private var autoRenameOnSave = false

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
    @AppStorage(DefaultsKey.autoPairEnabled) private var autoPairEnabled = true
    @AppStorage(DefaultsKey.newPostFormat) private var newPostFormat = ContentFormat.bundle.rawValue
    @AppStorage(DefaultsKey.imagePasteLocation) private var imagePasteLocation = ImagePasteLocation.pageFolder.rawValue
    @AppStorage(DefaultsKey.imagePasteFormat) private var imagePasteFormat = ImagePasteFormat.png.rawValue
    @AppStorage(DefaultsKey.imagePasteJPEGQuality) private var imagePasteJPEGQuality = 0.85
    @AppStorage(DefaultsKey.imagePasteMaxDimension) private var imagePasteMaxDimension = 0.0
    @AppStorage(DefaultsKey.imagePasteNamingStrategy) private var imagePasteNamingStrategy = ImagePasteNamingStrategy.timestamp.rawValue

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

            Section("Images") {
                Picker("Paste destination", selection: $imagePasteLocation) {
                    ForEach(ImagePasteLocation.allCases) { location in
                        Text(location.displayName).tag(location.rawValue)
                    }
                }

                Picker("Output format", selection: $imagePasteFormat) {
                    ForEach(ImagePasteFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }

                Picker("Filename strategy", selection: $imagePasteNamingStrategy) {
                    ForEach(ImagePasteNamingStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy.rawValue)
                    }
                }

                HStack {
                    Text("Max dimension:")
                    Slider(value: $imagePasteMaxDimension, in: 0...4096, step: 64)
                    Text(imagePasteMaxDimension <= 0 ? "Off" : "\(Int(imagePasteMaxDimension))px")
                        .frame(width: 70)
                }

                if imagePasteFormat == ImagePasteFormat.jpeg.rawValue {
                    HStack {
                        Text("JPEG quality:")
                        Slider(value: $imagePasteJPEGQuality, in: 0.4...1.0, step: 0.05)
                        Text(String(format: "%.2f", imagePasteJPEGQuality))
                            .frame(width: 45)
                    }
                }
            }
        }
        .padding()
    }
}

struct ThemeSettingsView: View {
    @AppStorage(DefaultsKey.selectedTheme) private var selectedTheme = "Default"

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Editor Theme", selection: $selectedTheme) {
                    ForEach(Theme.availableThemeNames, id: \.self) { theme in
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
