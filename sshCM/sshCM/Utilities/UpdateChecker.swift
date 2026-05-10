import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable, Identifiable {
        let version: SemanticVersion
        let tag: String
        let notes: String
        let downloadURL: URL
        let assetSize: Int64
        var id: String { tag }
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case error(String)
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/VladGavrila/sshCM/releases/latest")!
    static let assetName = "sshCM.zip"

    private let autoCheckKey = "autoCheckForUpdates"
    private let lastCheckKey = "updateLastCheck"
    private let skippedVersionKey = "skippedUpdateVersion"
    private let checkInterval: TimeInterval = 86_400

    var state: State = .idle
    var lastCheck: Date? {
        get {
            let v = UserDefaults.standard.double(forKey: lastCheckKey)
            return v == 0 ? nil : Date(timeIntervalSince1970: v)
        }
        set {
            if let d = newValue {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: lastCheckKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastCheckKey)
            }
        }
    }

    var autoCheckForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedVersionKey) }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: skippedVersionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: skippedVersionKey)
            }
        }
    }

    var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var currentVersion: SemanticVersion? {
        SemanticVersion(currentVersionString)
    }

    private var downloadTask: Task<Void, Never>?

    func checkAtLaunchIfNeeded() {
        guard autoCheckForUpdates else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < checkInterval { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        if case .checking = state { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            lastCheck = Date()
            guard let current = currentVersion else {
                state = .error("Could not determine current app version.")
                return
            }
            if release.version <= current {
                state = userInitiated ? .upToDate : .idle
                return
            }
            if !userInitiated, let skipped = skippedVersion, skipped == release.tag {
                state = .idle
                return
            }
            state = .available(release)
        } catch {
            if userInitiated {
                state = .error("Could not check for updates: \(error.localizedDescription)")
            } else {
                state = .idle
            }
        }
    }

    func dismissTransient() {
        switch state {
        case .upToDate, .error, .available:
            state = .idle
        default:
            break
        }
    }

    func skip(_ release: Release) {
        skippedVersion = release.tag
        state = .idle
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    func downloadAndInstall(_ release: Release) {
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            await self?.performDownloadAndInstall(release)
        }
    }

    private func performDownloadAndInstall(_ release: Release) async {
        state = .downloading(0)
        do {
            let zipURL = try await downloadZip(release)
            try Task.checkCancellation()
            state = .installing
            try AppInstaller.install(
                zipURL: zipURL,
                expectedBundleID: Bundle.main.bundleIdentifier ?? "com.vgdev.sshCM"
            )
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .error("Update failed: \(error.localizedDescription)")
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("sshCM/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode(GHError.self, from: data).message) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "UpdateChecker", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let payload = try JSONDecoder().decode(GHRelease.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name == Self.assetName }),
              let url = URL(string: asset.browser_download_url) else {
            throw NSError(domain: "UpdateChecker", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Latest release has no \(Self.assetName) asset."])
        }
        guard let version = SemanticVersion(payload.tag_name) else {
            throw NSError(domain: "UpdateChecker", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not parse release tag '\(payload.tag_name)'."])
        }
        return Release(
            version: version,
            tag: payload.tag_name,
            notes: payload.body ?? "",
            downloadURL: url,
            assetSize: asset.size
        )
    }

    private func downloadZip(_ release: Release) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshCM-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let zipURL = destination.appendingPathComponent(Self.assetName)

        var request = URLRequest(url: release.downloadURL)
        request.setValue("sshCM/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "UpdateChecker", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."])
        }
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : release.assetSize

        FileManager.default.createFile(atPath: zipURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: zipURL)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0
        var lastReport: Double = -1

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    let p = min(1.0, Double(written) / Double(total))
                    if p - lastReport >= 0.01 {
                        lastReport = p
                        state = .downloading(p)
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        if total > 0 {
            state = .downloading(min(1.0, Double(written) / Double(total)))
        } else {
            state = .downloading(1.0)
        }
        return zipURL
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let body: String?
        let assets: [GHAsset]
    }

    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
    }

    private struct GHError: Decodable {
        let message: String
    }
}
