import Foundation
import os

/// Defines a strategy for creating new Hugo content.
///
/// Allows decoupling the app from Hugo CLI by providing an interface that
/// can be swapped for different implementations (e.g., direct file creation,
/// alternate CLI tools, or test mocks).
protocol HugoContentCreator {
    /// Checks whether the Hugo CLI is available at the given site.
    ///
    /// - Parameter siteURL: The URL of the Hugo site directory.
    /// - Returns: `true` if Hugo CLI can be executed successfully.
    func isAvailable(at siteURL: URL) -> Bool

    /// Creates new content using Hugo's `hugo new` command.
    ///
    /// - Parameters:
    ///   - siteURL: The root URL of the Hugo site.
    ///   - contentDir: The content directory name (e.g., "content").
    ///   - relativePath: The relative path for the new content file.
    ///   - kind: Optional content kind for Hugo archetype selection.
    /// - Returns: The URL of the created content file.
    /// - Throws: ``HugoContentCreatorError`` if Hugo CLI fails or file cannot be located.
    func createNewContent(
        siteURL: URL,
        contentDir: String,
        relativePath: String,
        kind: String?
    ) throws -> URL
}

enum HugoContentCreatorError: LocalizedError, CustomDebugStringConvertible {
    case executableNotFound
    case commandFailed(command: String, status: Int32, output: String)
    case couldNotResolveCreatedPath(expectedPath: String, output: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not find Hugo CLI. Set HUGORA_HUGO_PATH or install Hugo in a standard location."
        case .commandFailed:
            return "Could not create the post. Hugo reported an error."
        case .couldNotResolveCreatedPath:
            return "The post was created but couldn't be found at the expected location."
        }
    }

    var debugDescription: String {
        switch self {
        case .executableNotFound:
            return "Hugo executable not found in HUGORA_HUGO_PATH, /opt/homebrew/bin/hugo, /usr/local/bin/hugo, or /usr/bin/hugo"
        case .commandFailed(let command, let status, let output):
            return "Hugo command failed (exit \(status)): \(command)\nOutput: \(output)"
        case .couldNotResolveCreatedPath(let expectedPath, let output):
            return "Hugo reported success, but file not found at: \(expectedPath)\nOutput: \(output)"
        }
    }
}

struct HugoCLIContentCreator: HugoContentCreator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "HugoCLIContentCreator"
    )

    private static let standardExecutableLocations = [
        "/opt/homebrew/bin/hugo",
        "/usr/local/bin/hugo",
        "/usr/bin/hugo",
    ]

    func isAvailable(at siteURL: URL) -> Bool {
        do {
            let result = try runHugo(arguments: ["version"], siteURL: siteURL)
            return result.status == 0
        } catch {
            Self.logger.error("Failed to check Hugo availability: \(error.localizedDescription)")
            return false
        }
    }

    func createNewContent(
        siteURL: URL,
        contentDir: String,
        relativePath: String,
        kind: String?
    ) throws -> URL {
        var arguments = ["new", "content", relativePath]
        if let kind, !kind.isEmpty {
            arguments.append(contentsOf: ["-k", kind])
        }

        let result = try runHugo(arguments: arguments, siteURL: siteURL)
        let command = "hugo " + arguments.joined(separator: " ")

        guard result.status == 0 else {
            throw HugoContentCreatorError.commandFailed(
                command: command,
                status: result.status,
                output: mergedOutput(stdout: result.stdout, stderr: result.stderr)
            )
        }

        let expectedURL = siteURL
            .appendingPathComponent(contentDir)
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        if FileManager.default.fileExists(atPath: expectedURL.path) {
            return expectedURL
        }

        if let parsedURL = parseCreatedPath(from: result.stdout, siteURL: siteURL),
           FileManager.default.fileExists(atPath: parsedURL.path) {
            return parsedURL.standardizedFileURL
        }

        throw HugoContentCreatorError.couldNotResolveCreatedPath(
            expectedPath: expectedURL.path,
            output: mergedOutput(stdout: result.stdout, stderr: result.stderr)
        )
    }

    private func runHugo(arguments: [String], siteURL: URL) throws -> ProcessResult {
        guard let hugoExecutable = resolveHugoExecutable() else {
            throw HugoContentCreatorError.executableNotFound
        }

        let process = Process()
        process.executableURL = hugoExecutable
        process.arguments = arguments
        process.currentDirectoryURL = siteURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func resolveHugoExecutable() -> URL? {
        let fm = FileManager.default
        if let configuredPath = ProcessInfo.processInfo.environment["HUGORA_HUGO_PATH"],
           !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
            if fm.isExecutableFile(atPath: configuredURL.path) {
                return configuredURL
            }
        }

        for path in Self.standardExecutableLocations where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func mergedOutput(stdout: String, stderr: String) -> String {
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedStdout.isEmpty {
            return trimmedStderr
        }

        if trimmedStderr.isEmpty {
            return trimmedStdout
        }

        return "\(trimmedStdout)\n\(trimmedStderr)"
    }

    private func parseCreatedPath(from output: String, siteURL: URL) -> URL? {
        let pattern = #"Content "([^"]+)" created"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let pathRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }

        let path = String(output[pathRange])
        let url = URL(fileURLWithPath: path, relativeTo: siteURL)
        return url.standardizedFileURL
    }
}

private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}
