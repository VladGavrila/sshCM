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

    // The full releases list (newest first), not /releases/latest: we want every release
    // between the user's current version and the newest so the update sheet can show the
    // accumulated changelog, not just the last bump.
    static let releasesAPI = URL(string: "https://api.github.com/repos/VladGavrila/sshCM/releases?per_page=30")!
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
            let (latest, all) = try await fetchReleases()
            lastCheck = Date()
            guard let current = currentVersion else {
                state = .error("Could not determine current app version.")
                return
            }
            if latest.version <= current {
                state = userInitiated ? .upToDate : .idle
                return
            }
            if !userInitiated, let skipped = skippedVersion, skipped == latest.tag {
                state = .idle
                return
            }
            state = .available(makeCombinedRelease(latest: latest, all: all, current: current))
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

    /// A parsed published release, used to accumulate the changelog across versions.
    private struct ReleaseInfo {
        let version: SemanticVersion
        let tag: String
        let notes: String
    }

    /// Fetches the full releases list and returns the newest installable release plus every
    /// parsed published release (newest first), so the caller can build a multi-version changelog.
    private func fetchReleases() async throws -> (latest: Release, all: [ReleaseInfo]) {
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("sshCM/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode(GHError.self, from: data).message) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "UpdateChecker", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let payload = try JSONDecoder().decode([GHRelease].self, from: data)

        // Keep only published (non-draft, non-prerelease) releases whose tag is a valid semver,
        // newest first.
        let published = payload
            .filter { !($0.draft ?? false) && !($0.prerelease ?? false) }
            .compactMap { gh -> (gh: GHRelease, version: SemanticVersion)? in
                guard let v = SemanticVersion(gh.tag_name) else { return nil }
                return (gh, v)
            }
            .sorted { $0.version > $1.version }

        // The newest release that actually ships an installable asset becomes the install target.
        guard let newest = published.first(where: { entry in
                  entry.gh.assets.contains { $0.name == Self.assetName }
              }),
              let asset = newest.gh.assets.first(where: { $0.name == Self.assetName }),
              let url = URL(string: asset.browser_download_url) else {
            throw NSError(domain: "UpdateChecker", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No release with a \(Self.assetName) asset was found."])
        }

        let latest = Release(
            version: newest.version,
            tag: newest.gh.tag_name,
            notes: newest.gh.body ?? "",
            downloadURL: url,
            assetSize: asset.size
        )
        let all = published.map { ReleaseInfo(version: $0.version, tag: $0.gh.tag_name, notes: $0.gh.body ?? "") }
        return (latest, all)
    }

    /// Builds the release shown in the update sheet: the newest installable release, but with the
    /// notes of every version the user is missing (current+1 … latest) concatenated newest-first,
    /// each under its own heading. A user several versions behind sees the full changelog, not just
    /// the last bump. With only a single missing version, the latest release's own notes are used as-is.
    private func makeCombinedRelease(latest: Release, all: [ReleaseInfo], current: SemanticVersion) -> Release {
        let missing = all
            .filter { $0.version > current && $0.version <= latest.version }
            .sorted { $0.version > $1.version }
        guard missing.count > 1 else { return latest }
        let combined = missing
            .map { entry -> String in
                let body = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let heading = "# sshCM \(entry.version.description)"
                return body.isEmpty ? heading : "\(heading)\n\n\(body)"
            }
            .joined(separator: "\n\n")
        return Release(
            version: latest.version,
            tag: latest.tag,
            notes: combined,
            downloadURL: latest.downloadURL,
            assetSize: latest.assetSize
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
        let draft: Bool?
        let prerelease: Bool?
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
