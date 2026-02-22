import AppKit
import Foundation
import os

enum CLIInstaller {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "CLIInstaller"
    )
    static let installPath = "/usr/local/bin/hugora"
    private static let managedCLISuffix = "/Hugora.app/Contents/MacOS/hugora-cli"

    private enum InstallPathState {
        case missing
        case managedSymlink
        case unmanagedSymlink(destination: String)
        case occupied
    }

    static var bundledCLIURL: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("hugora-cli")
    }

    static var isInstalled: Bool {
        guard let bundledURL = bundledCLIURL else { return false }

        let fm = FileManager.default
        guard fm.fileExists(atPath: installPath) else { return false }

        // Check if symlink points to our bundled CLI
        do {
            let destination = try fm.destinationOfSymbolicLink(atPath: installPath)
            return destination == bundledURL.path
        } catch {
            logger.error("Failed to read symlink at \(installPath): \(error.localizedDescription)")
        }

        return false
    }

    static var canInstallWithoutAuth: Bool {
        let fm = FileManager.default
        let binDir = "/usr/local/bin"

        // Check if /usr/local/bin exists and is writable
        if fm.fileExists(atPath: binDir) {
            return fm.isWritableFile(atPath: binDir)
        }

        // Check if /usr/local exists and is writable (can create bin)
        if fm.isWritableFile(atPath: "/usr/local") {
            return true
        }

        return false
    }

    static func install(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let bundledURL = bundledCLIURL else {
            completion(.failure(CLIInstallerError.cliNotBundled))
            return
        }

        let fm = FileManager.default

        // Ensure bundled CLI exists
        guard fm.fileExists(atPath: bundledURL.path) else {
            completion(.failure(CLIInstallerError.cliNotBundled))
            return
        }

        switch installPathState(currentBundledPath: bundledURL.path) {
        case .missing, .managedSymlink:
            break
        case .unmanagedSymlink, .occupied:
            completion(.failure(CLIInstallerError.installPathInUse(installPath)))
            return
        }

        // Try without auth first
        if canInstallWithoutAuth {
            do {
                try installSymlink(from: bundledURL.path)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
            return
        }

        // Need admin privileges - use AppleScript
        installWithAdminPrivileges(bundledURL: bundledURL, completion: completion)
    }

    static func uninstall(completion: @escaping (Result<Void, Error>) -> Void) {
        switch installPathState(currentBundledPath: bundledCLIURL?.path) {
        case .missing:
            completion(.success(()))
            return
        case .managedSymlink:
            break
        case .unmanagedSymlink, .occupied:
            completion(.failure(CLIInstallerError.notManagedInstall(installPath)))
            return
        }

        let fm = FileManager.default

        // Try without auth first
        if fm.isDeletableFile(atPath: installPath) {
            do {
                try fm.removeItem(atPath: installPath)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
            return
        }

        // Need admin privileges
        uninstallWithAdminPrivileges(completion: completion)
    }

    private static func installSymlink(from source: String) throws {
        let fm = FileManager.default
        let binDir = "/usr/local/bin"

        // Create /usr/local/bin if needed
        if !fm.fileExists(atPath: binDir) {
            try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        }

        switch installPathState(currentBundledPath: source) {
        case .missing:
            break
        case .managedSymlink:
            try fm.removeItem(atPath: installPath)
        case .unmanagedSymlink, .occupied:
            throw CLIInstallerError.installPathInUse(installPath)
        }

        // Create symlink
        try fm.createSymbolicLink(atPath: installPath, withDestinationPath: source)
    }

    private static func installWithAdminPrivileges(
        bundledURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        runPrivilegedCommand("/bin/mkdir", args: ["-p", "/usr/local/bin"]) {
            result in
            switch result {
            case .success:
                runPrivilegedCommand("/bin/rm", args: ["-f", installPath]) {
                    result in
                    switch result {
                    case .success:
                        runPrivilegedCommand("/bin/ln", args: ["-s", bundledURL.path, installPath],
                                              completion: completion)
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func uninstallWithAdminPrivileges(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        runPrivilegedCommand("/bin/rm", args: ["-f", installPath], completion: completion)
    }

    private static func runPrivilegedCommand(
        _ command: String,
        args: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let escapedArgs = args.map { escapeShellPath($0) }.map { "'\($0)'" }.joined(separator: " ")
        let script = """
            do shell script "\(command) \(escapedArgs)" with administrator privileges
            """

        runAppleScript(script, completion: completion)
    }

    private static func runAppleScript(
        _ source: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                guard let error else {
                    completion(.success(()))
                    return
                }

                let message =
                    error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                if message.contains("User canceled") {
                    completion(.failure(CLIInstallerError.userCancelled))
                    return
                }
                completion(.failure(CLIInstallerError.scriptFailed(message)))
            }
        }
    }

    private static func escapeShellPath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func installPathState(currentBundledPath: String?) -> InstallPathState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installPath) else {
            return .missing
        }

        do {
            let destination = try fm.destinationOfSymbolicLink(atPath: installPath)
            if isManagedDestination(destination, currentBundledPath: currentBundledPath) {
                return .managedSymlink
            }
            return .unmanagedSymlink(destination: destination)
        } catch {
            return .occupied
        }
    }

    private static func isManagedDestination(_ destination: String, currentBundledPath: String?) -> Bool {
        if let currentBundledPath, destination == currentBundledPath {
            return true
        }
        return destination.hasSuffix(managedCLISuffix)
    }
}

enum CLIInstallerError: LocalizedError {
    case cliNotBundled
    case installPathInUse(String)
    case notManagedInstall(String)
    case userCancelled
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliNotBundled:
            "The command line tool is not bundled with this version of Hugora."
        case .installPathInUse(let path):
            "Cannot install because \(path) is already in use by another tool."
        case .notManagedInstall(let path):
            "Cannot uninstall because \(path) is not managed by Hugora."
        case .userCancelled:
            "Installation was cancelled."
        case .scriptFailed(let message):
            "Installation failed: \(message)"
        }
    }
}
