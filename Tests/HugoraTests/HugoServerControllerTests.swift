import Foundation
import Testing

@testable import Hugora

@Suite("HugoServerController", .serialized)
@MainActor
struct HugoServerControllerTests {
    @Test("Parses the serving URL from hugo output")
    func parsesServerURL() {
        let output = """
            Watching for changes in /site/{archetypes,content,layouts}
            Web Server is available at http://localhost:1313/ (bind address 127.0.0.1)
            Press Ctrl+C to stop
            """
        #expect(HugoServerController.serverURL(in: output) == URL(string: "http://localhost:1313/"))

        let schemeless = "Web Server is available at //localhost:41313/ (bind address 127.0.0.1)"
        #expect(HugoServerController.serverURL(in: schemeless) == URL(string: "http://localhost:41313/"))

        #expect(HugoServerController.serverURL(in: "Building sites …") == nil)
    }

    @Test("Start reaches running state with a fake hugo and stop terminates it")
    func startAndStopLifecycle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeHugo = tempDir.appendingPathComponent("hugo")
        try """
        #!/bin/sh
        echo "Web Server is available at http://localhost:4242/ (bind address 127.0.0.1)"
        sleep 60
        """.write(to: fakeHugo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHugo.path)

        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: DefaultsKey.hugoExecutablePath)
        defaults.set(fakeHugo.path, forKey: DefaultsKey.hugoExecutablePath)
        defer {
            if let original {
                defaults.set(original, forKey: DefaultsKey.hugoExecutablePath)
            } else {
                defaults.removeObject(forKey: DefaultsKey.hugoExecutablePath)
            }
        }

        let controller = HugoServerController()
        controller.start(siteURL: tempDir, openBrowser: false)
        #expect(controller.state == .starting)
        #expect(controller.siteURL == tempDir)

        var sawRunning = false
        for _ in 0..<100 {
            if case .running(let url) = controller.state {
                #expect(url == URL(string: "http://localhost:4242/"))
                sawRunning = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(sawRunning)

        controller.stop()
        #expect(controller.state == .stopped)
        #expect(controller.siteURL == nil)
    }

    @Test("Missing hugo binary fails immediately")
    func missingBinaryFails() {
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: DefaultsKey.hugoExecutablePath)
        defaults.set("/nonexistent/hugo-\(UUID().uuidString)", forKey: DefaultsKey.hugoExecutablePath)
        defer {
            if let original {
                defaults.set(original, forKey: DefaultsKey.hugoExecutablePath)
            } else {
                defaults.removeObject(forKey: DefaultsKey.hugoExecutablePath)
            }
        }

        // Only when nothing else resolves either can we assert failure —
        // on machines with hugo installed the standard locations win.
        guard HugoExecutable.resolve() == nil else { return }

        let controller = HugoServerController()
        controller.start(siteURL: URL(fileURLWithPath: "/tmp"), openBrowser: false)
        if case .failed = controller.state {
            controller.stop()
            #expect(controller.state == .stopped)
            #expect(controller.siteURL == nil)
        } else {
            Issue.record("Expected .failed state, got \(controller.state)")
        }
    }
}
