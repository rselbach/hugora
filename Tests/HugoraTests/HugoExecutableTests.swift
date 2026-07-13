import Foundation
import Testing

@testable import Hugora

@Suite("HugoExecutable", .serialized)
struct HugoExecutableTests {
    private func withDefaultsValue(_ value: String?, body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: DefaultsKey.hugoExecutablePath)
        defer {
            if let original {
                defaults.set(original, forKey: DefaultsKey.hugoExecutablePath)
            } else {
                defaults.removeObject(forKey: DefaultsKey.hugoExecutablePath)
            }
        }
        if let value {
            defaults.set(value, forKey: DefaultsKey.hugoExecutablePath)
        } else {
            defaults.removeObject(forKey: DefaultsKey.hugoExecutablePath)
        }
        try body()
    }

    @Test("Configured path wins when it is executable")
    func configuredPathWins() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHugo = tempDir.appendingPathComponent("hugo")
        try "#!/bin/sh\n".write(to: fakeHugo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHugo.path)

        try withDefaultsValue(fakeHugo.path) {
            #expect(HugoExecutable.resolve()?.path == fakeHugo.resolvingSymlinksInPath().path)
        }
    }

    @Test("Non-executable configured path falls through")
    func nonExecutableConfiguredPathIgnored() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let notExecutable = tempDir.appendingPathComponent("hugo")
        try "not a binary".write(to: notExecutable, atomically: true, encoding: .utf8)

        try withDefaultsValue(notExecutable.path) {
            let resolved = HugoExecutable.resolve()
            #expect(resolved?.path != notExecutable.path)
        }
    }
}
