import AppKit
import Combine
import SwiftUI

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var currentTheme: Theme

    @AppStorage("selectedTheme") private var selectedThemeName = "Default"

    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?

    init() {
        currentTheme = Theme.named(UserDefaults.standard.string(forKey: "selectedTheme") ?? "Default")
        setupBindings()
        observeAppearance()
    }

    private func setupBindings() {
        UserDefaults.standard.publisher(for: \.selectedTheme)
            .receive(on: RunLoop.main)
            .sink { [weak self] name in
                self?.updateTheme(name: name ?? "Default")
            }
            .store(in: &cancellables)
    }

    private func observeAppearance() {
        appearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateTheme(name: self.selectedThemeName)
        }
    }

    private func updateTheme(name: String) {
        currentTheme = Theme.named(name)
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    deinit {
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
        }
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("com.hugora.themeDidChange")
}

extension UserDefaults {
    @objc dynamic var selectedTheme: String? {
        string(forKey: "selectedTheme")
    }
}
