import AppKit
import Foundation
import os

/// Runs `hugo server` for the open site so edits can be previewed in the
/// real theme. `--navigateToChanged` makes the browser follow the post
/// being saved; drafts and future posts are built so everything in the
/// sidebar is previewable.
@MainActor
final class HugoServerController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running(URL)
        case failed(String)
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "HugoServerController"
    )
    private static let maxBufferedOutput = 16 * 1024
    private static let startupTimeout: UInt64 = 10_000_000_000

    @Published private(set) var state: State = .stopped

    /// The site the server was started for; used to stop it when the
    /// workspace changes.
    private(set) var siteURL: URL?

    var isRunning: Bool {
        switch state {
        case .starting, .running: true
        case .stopped, .failed: false
        }
    }

    private var process: Process?
    private var outputBuffer = ""
    private var openBrowserWhenReady = false
    private var startupTimeoutTask: Task<Void, Never>?

    /// Starts the preview server for `siteURL`, replacing any running
    /// instance. When `openBrowser` is set, the site opens in the default
    /// browser as soon as hugo reports it is serving.
    func start(siteURL: URL, openBrowser: Bool = true) {
        stop()

        guard let hugo = HugoExecutable.resolve() else {
            state = .failed(
                "Could not find Hugo CLI. Set its path in Settings → General or install Hugo in a standard location."
            )
            return
        }

        let process = Process()
        process.executableURL = hugo
        process.arguments = [
            "server",
            "--buildDrafts",
            "--buildFuture",
            "--navigateToChanged",
        ]
        process.currentDirectoryURL = siteURL
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.consumeOutput(text, from: process)
            }
        }

        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.handleTermination(of: finished)
            }
        }

        do {
            try process.run()
        } catch {
            Self.logger.error("Failed to launch hugo server: \(error.localizedDescription)")
            state = .failed("Failed to launch hugo server: \(error.localizedDescription)")
            return
        }

        self.process = process
        self.siteURL = siteURL
        self.outputBuffer = ""
        self.openBrowserWhenReady = openBrowser
        state = .starting
        startupTimeoutTask = Task { @MainActor [weak self, weak process] in
            do {
                try await Task.sleep(nanoseconds: Self.startupTimeout)
            } catch {
                return
            }
            guard let self, let process, process === self.process, case .starting = self.state else { return }
            self.fail(
                process: process,
                message: "Hugo started but did not report a preview URL within 10 seconds."
            )
        }
    }

    /// Stops the preview server if it is running.
    func stop() {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        guard let process else {
            siteURL = nil
            state = .stopped
            return
        }
        // Clearing the reference first makes the termination handler treat
        // this as a deliberate stop rather than a crash.
        self.process = nil
        self.siteURL = nil
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        state = .stopped
    }

    /// Opens the served site in the default browser.
    func openInBrowser() {
        guard case .running(let url) = state else { return }
        NSWorkspace.shared.open(url)
    }

    private func consumeOutput(_ text: String, from source: Process) {
        guard source === process else { return }

        outputBuffer += text
        if outputBuffer.count > Self.maxBufferedOutput {
            outputBuffer = String(outputBuffer.suffix(Self.maxBufferedOutput))
        }

        guard case .starting = state else { return }
        guard let url = Self.serverURL(in: outputBuffer) else { return }

        state = .running(url)
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        if openBrowserWhenReady {
            openBrowserWhenReady = false
            NSWorkspace.shared.open(url)
        }
    }

    private func handleTermination(of finished: Process) {
        guard finished === process else { return }
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        process = nil
        siteURL = nil

        let tail =
            outputBuffer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .suffix(4)
            .joined(separator: "\n")
        Self.logger.error("hugo server exited (status \(finished.terminationStatus)): \(tail)")
        state = .failed(tail.isEmpty ? "hugo server exited unexpectedly." : tail)
    }

    private func fail(process: Process, message: String) {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        self.process = nil
        siteURL = nil
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        Self.logger.error("Hugo preview failed: \(message)")
        state = .failed(message)
    }

    /// Extracts the serving URL from hugo's startup output, e.g.
    /// "Web Server is available at http://localhost:1313/ (bind address 127.0.0.1)".
    static func serverURL(in output: String) -> URL? {
        let pattern = #"Web Server is available at (\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
            let urlRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }

        var candidate = String(output[urlRange])
        // Hugo may print //localhost:1313/ for baseURL-less sites.
        if candidate.hasPrefix("//") {
            candidate = "http:" + candidate
        }
        return URL(string: candidate)
    }
}
