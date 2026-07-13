#!/usr/bin/env swift
// hugora - CLI launcher for Hugora.app
// Usage: hugora [folder]

import AppKit
import Foundation

let args = CommandLine.arguments.dropFirst()
let expectedBundleID = "com.selbach.hugora"

func isValidHugoraApp(at url: URL) -> Bool {
    guard let bundle = Bundle(url: url) else { return false }
    return bundle.bundleIdentifier == expectedBundleID
}

func findHugoraApp() -> URL? {
    let fm = FileManager.default

    // Check common locations
    let candidates = [
        "/Applications/Hugora.app",
        "\(NSHomeDirectory())/Applications/Hugora.app",
        // Development build location
        "\(fm.currentDirectoryPath)/.build/debug/Hugora.app",
        "\(fm.currentDirectoryPath)/.build/release/Hugora.app",
    ]

    for path in candidates {
        if fm.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if isValidHugoraApp(at: url) {
                return url
            }
        }
    }

    // Try mdfind as fallback
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    task.arguments = ["kMDItemCFBundleIdentifier == 'com.selbach.hugora'"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let paths = output.split(separator: "\n")
            for path in paths where !path.isEmpty {
                let url = URL(fileURLWithPath: String(path))
                if isValidHugoraApp(at: url) {
                    return url
                }
            }
        }
    } catch {
        fputs("warning: mdfind search failed: \(error.localizedDescription)\n", stderr)
    }

    return nil
}

func openHugora(with folderPath: String?) {
    guard let appURL = findHugoraApp() else {
        fputs("error: Hugora.app not found\n", stderr)
        fputs("Install Hugora.app in /Applications or ~/Applications\n", stderr)
        exit(1)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var openError: Error?
    let config = NSWorkspace.OpenConfiguration()

    if let folder = folderPath {
        // Hand the folder over via the hugora:// URL scheme: launch
        // arguments only reach a freshly launched instance, while an open
        // URL is delivered to a running app as well.
        let fileURL = URL(
            fileURLWithPath: folder,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL

        var components = URLComponents()
        components.scheme = "hugora"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]

        guard let openURL = components.url else {
            fputs("error: could not encode folder path\n", stderr)
            exit(1)
        }

        NSWorkspace.shared.open([openURL], withApplicationAt: appURL, configuration: config) { _, error in
            openError = error
            semaphore.signal()
        }
    } else {
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            openError = error
            semaphore.signal()
        }
    }

    semaphore.wait()

    if let error = openError {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// Handle --help
if args.contains("-h") || args.contains("--help") {
    fputs(
        """
        hugora - Hugo blog editor

        Usage: hugora [folder]

        Arguments:
            folder    Path to a Hugo site folder (optional)

        Examples:
            hugora                  # Open Hugora
            hugora ~/blog           # Open Hugora with ~/blog
            hugora .                # Open Hugora with current directory

        """, stdout)
    exit(0)
}

let folderPath = args.first
openHugora(with: folderPath)
