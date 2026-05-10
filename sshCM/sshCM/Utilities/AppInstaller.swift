import Foundation
import AppKit

enum InstallError: LocalizedError {
    case extractionFailed(String)
    case appNotFound
    case signatureInvalid(String)
    case bundleIDMismatch(expected: String, found: String?)
    case notWritable(path: String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Could not extract update archive: \(msg)"
        case .appNotFound: return "Update archive did not contain an app bundle."
        case .signatureInvalid(let msg): return "Update is not properly signed: \(msg)"
        case .bundleIDMismatch(let expected, let found):
            return "Update bundle ID mismatch (expected \(expected), got \(found ?? "?"))."
        case .notWritable(let path):
            return "Cannot replace app at \(path). Move sshCM.app to a writable location and try again."
        case .scriptFailed(let msg): return "Installer script failed: \(msg)"
        }
    }
}

enum AppInstaller {
    static func install(zipURL: URL, expectedBundleID: String) throws {
        let workDir = zipURL.deletingLastPathComponent().appendingPathComponent("extracted", isDirectory: true)
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, workDir.path])
            .throwing(InstallError.extractionFailed)

        guard let newApp = try findApp(in: workDir) else {
            throw InstallError.appNotFound
        }

        _ = try? runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        try runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            .throwing(InstallError.signatureInvalid)

        let infoURL = newApp.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
        let foundID = info?["CFBundleIdentifier"] as? String
        guard foundID == expectedBundleID else {
            throw InstallError.bundleIDMismatch(expected: expectedBundleID, found: foundID)
        }

        let currentApp = Bundle.main.bundleURL
        let parent = currentApp.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) {
            throw InstallError.notWritable(path: currentApp.path)
        }

        let scriptURL = zipURL.deletingLastPathComponent().appendingPathComponent("install.sh")
        try installerScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, String(pid), currentApp.path, newApp.path]
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
        } catch {
            throw InstallError.scriptFailed(error.localizedDescription)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func findApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if let direct = contents.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        for entry in contents {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir, let nested = try findApp(in: entry) {
                return nested
            }
        }
        return nil
    }

    private static let installerScript = """
    #!/bin/bash
    set -e
    PID="$1"
    OLD="$2"
    NEW="$3"
    LOG="${TMPDIR:-/tmp}/sshCM-installer.log"
    exec >>"$LOG" 2>&1
    echo "[$(date)] waiting for pid $PID"
    for i in $(seq 1 60); do
        if ! kill -0 "$PID" 2>/dev/null; then break; fi
        sleep 0.5
    done
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
    sleep 0.5
    echo "[$(date)] replacing $OLD with $NEW"
    rm -rf "$OLD"
    mv "$NEW" "$OLD"
    echo "[$(date)] launching $OLD"
    open "$OLD"
    """
}

private struct ProcessResult {
    let exitCode: Int32
    let stderr: String

    func throwing(_ make: (String) -> Error) throws {
        if exitCode != 0 {
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw make(msg.isEmpty ? "exit code \(exitCode)" : msg)
        }
    }
}

private func runProcess(_ path: String, _ args: [String]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let errPipe = Pipe()
    process.standardError = errPipe
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()
    let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
    return ProcessResult(
        exitCode: process.terminationStatus,
        stderr: String(data: errData, encoding: .utf8) ?? ""
    )
}
