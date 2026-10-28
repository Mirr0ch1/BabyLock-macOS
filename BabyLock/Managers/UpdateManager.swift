import AppKit
import Foundation

/// Checks GitHub Releases for a newer build and installs it in place.
///
/// The installer is a small detached shell script: it waits for this process
/// to exit, swaps the app bundle in place, resets the TCC entries (an ad-hoc
/// signed build gets a new signature on every release), and relaunches.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String)
        case downloading
        case installing
        case failed
    }

    @Published private(set) var state: State = .idle
    var onStateChange: (() -> Void)?

    private let owner = "Mirr0ch1"
    private let repository = "BabyLock-macOS"
    private let assetName = "BabyLock-macOS.zip"

    private var availableRelease: Release?
    private var resetTimer: Timer?
    private var launchCheckTask: Task<Void, Never>?
    private var hasScheduledLaunchCheck = false

    private struct Release {
        let version: String
        let downloadURL: URL
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }

    private enum UpdateError: LocalizedError {
        case network
        case missingAsset
        case invalidArchive
        case verification
        case signature
        case notInApplications
        case notWritable
        case lockActive
        case processFailed

        var errorDescription: String? {
            switch self {
            case .network:
                return AppStrings.text(.updateErrorNetwork)
            case .missingAsset:
                return AppStrings.text(.updateErrorMissingAsset)
            case .invalidArchive:
                return AppStrings.text(.updateErrorInvalidArchive)
            case .verification:
                return AppStrings.text(.updateErrorVerification)
            case .signature:
                return AppStrings.text(.updateErrorSignature)
            case .notInApplications:
                return AppStrings.text(.updateErrorNotInApplications)
            case .notWritable:
                return AppStrings.text(.updateErrorNotWritable)
            case .lockActive:
                return AppStrings.text(.updateErrorLocked)
            case .processFailed:
                return AppStrings.text(.updateErrorProcess)
            }
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var isMenuActionEnabled: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return false
        default:
            return true
        }
    }

    /// Called once after the menu bar item is installed.
    func checkOnLaunch() {
        guard !hasScheduledLaunchCheck else { return }
        hasScheduledLaunchCheck = true

        launchCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.checkForUpdates(userInitiated: false)
        }
    }

    func checkForUpdates(userInitiated: Bool) {
        switch state {
        case .checking, .downloading, .installing:
            return
        case .idle, .upToDate, .updateAvailable, .failed:
            break
        }

        // Set `.checking` synchronously so the menu row updates before the
        // menu tracking loop gets another event.
        resetTimer?.invalidate()
        resetTimer = nil
        setState(.checking)

        Task { @MainActor [weak self] in
            await self?.performCheckForUpdates(userInitiated: userInitiated)
        }
    }

    private func performCheckForUpdates(userInitiated: Bool) async {
        do {
            let release = try await fetchLatestRelease()

            if Self.isVersion(release.version, newerThan: currentVersion) {
                availableRelease = release
                setState(.updateAvailable(version: release.version))
            } else {
                availableRelease = nil
                if userInitiated {
                    setState(.upToDate)
                    scheduleReset(after: 3, expected: .upToDate)
                } else {
                    setState(.idle)
                }
            }
        } catch {
            availableRelease = nil

            if userInitiated {
                // Keep the feedback inside the open menu instead of covering
                // it with a modal alert. The row resets itself after a few
                // seconds so the user can retry.
                NSLog("Baby Lock update check failed: \(error.localizedDescription)")
                setState(.failed)
                scheduleReset(after: 4, expected: .failed)
            } else {
                // A launch-time check is best effort; stay quiet when offline.
                setState(.idle)
            }
        }
    }

    func installAvailableUpdate() {
        guard case .updateAvailable(let version) = state,
              let release = availableRelease else { return }

        guard !LockModeManager.shared.isLockActive else {
            showErrorAlert(title: AppStrings.text(.updateFailedTitle), error: UpdateError.lockActive)
            return
        }

        let alert = NSAlert()
        alert.messageText = AppStrings.text(.updateConfirmTitle)
        alert.informativeText = String(
            format: AppStrings.text(.updateConfirmMessage),
            "v" + version
        )
        alert.addButton(withTitle: AppStrings.text(.updateInstallNow))
        alert.addButton(withTitle: AppStrings.text(.alertCancel))
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor [weak self] in
            await self?.downloadAndInstall(release)
        }
    }

    private func downloadAndInstall(_ release: Release) async {
        setState(.downloading)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BabyLockUpdate-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            var request = URLRequest(url: release.downloadURL)
            request.setValue("BabyLock/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 90

            let (downloadedURL, response) = try await URLSession.shared.download(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw UpdateError.network
            }

            let zipURL = tempRoot.appendingPathComponent("BabyLock-macOS.zip")
            try FileManager.default.moveItem(at: downloadedURL, to: zipURL)

            guard !LockModeManager.shared.isLockActive else {
                throw UpdateError.lockActive
            }

            setState(.installing)

            UserDefaults.standard.set(true, forKey: "permissionsNeedPrompt")
            _ = UserDefaults.standard.synchronize()

            do {
                try prepareInstall(zipURL: zipURL, expectedVersion: release.version, tempRoot: tempRoot)
            } catch {
                UserDefaults.standard.removeObject(forKey: "permissionsNeedPrompt")
                throw error
            }

            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: tempRoot)
            availableRelease = release
            setState(.updateAvailable(version: release.version))
            showErrorAlert(title: AppStrings.text(.updateFailedTitle), error: error)
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest") else {
            throw UpdateError.network
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BabyLock/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let result: (Data, URLResponse)

        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network
        }

        let (data, response) = result

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.network
        }

        let latest: GitHubRelease

        do {
            latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.network
        }

        let version = latest.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        let exactAsset = latest.assets.first {
            $0.name.caseInsensitiveCompare(assetName) == .orderedSame
        }
        let asset = exactAsset ?? latest.assets.first {
            $0.name.lowercased().hasSuffix(".zip")
        }

        guard let asset, let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateError.missingAsset
        }

        return Release(version: version, downloadURL: downloadURL)
    }

    private func prepareInstall(zipURL: URL, expectedVersion: String, tempRoot: URL) throws {
        let extractDirectory = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDirectory.path])

        let extractedItems = try FileManager.default.contentsOfDirectory(
            at: extractDirectory,
            includingPropertiesForKeys: nil
        )
        let appBundles = extractedItems.filter { $0.pathExtension == "app" }
        guard let newAppURL = appBundles.first(where: { $0.lastPathComponent == "Baby Lock.app" })
                ?? appBundles.first else {
            throw UpdateError.invalidArchive
        }

        let infoURL = newAppURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil)

        guard let info = info as? [String: Any],
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              let mainBundleIdentifier = Bundle.main.bundleIdentifier,
              bundleIdentifier == mainBundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String,
              Self.versionsMatch(version, expectedVersion) else {
            throw UpdateError.verification
        }

        do {
            try runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", newAppURL.path])
        } catch {
            throw UpdateError.signature
        }

        let appURL = Bundle.main.bundleURL
        guard Self.isInstalledLocation(appURL) else {
            throw UpdateError.notInApplications
        }

        let parentDirectory = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw UpdateError.notWritable
        }

        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("BabyLock", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let backupURL = supportDirectory.appendingPathComponent("UpdateBackup.app", isDirectory: true)
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logURL = logDirectory.appendingPathComponent("BabyLock-update.log")

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let scriptURL = tempRoot.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/sh
        set -u
        APP="$1"
        NEW="$2"
        PID="$3"
        TEMP="$4"
        BACKUP="$5"
        BUNDLE_ID="$6"

        echo "[$(date)] update requested"

        while /bin/kill -0 "$PID" 2>/dev/null; do
            /bin/sleep 0.2
        done

        /bin/rm -rf "$BACKUP"

        if ! /bin/mv "$APP" "$BACKUP"; then
            echo "[$(date)] could not move the current app"
            /usr/bin/open "$APP"
            exit 1
        fi

        if /usr/bin/ditto "$NEW" "$APP"; then
            /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
            echo "[$(date)] installed new app"

            # Ad-hoc builds get a new signature, so TCC keeps a ghost entry for
            # the old binary. Clear it before the new app asks for access.
            /usr/bin/tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
            /usr/bin/tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true

            echo "[$(date)] relaunching"
            /usr/bin/open "$APP"
            ( /bin/sleep 2; /bin/rm -rf "$TEMP" ) >/dev/null 2>&1 &
        else
            echo "[$(date)] copy failed; restoring"
            /bin/rm -rf "$APP"
            /bin/mv "$BACKUP" "$APP"
            /usr/bin/open "$APP"
        fi
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let logHandle = try FileHandle(forWritingTo: logURL)
        logHandle.seekToEndOfFile()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            appURL.path,
            newAppURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            tempRoot.path,
            backupURL.path,
            Bundle.main.bundleIdentifier ?? "com.mirr0ch1.babylock"
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            throw UpdateError.processFailed
        }

        try? logHandle.close()
    }

    private func runProcess(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw UpdateError.processFailed
        }

        process.waitUntilExit()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            if let text = String(data: output, encoding: .utf8), !text.isEmpty {
                NSLog("Baby Lock update: \(executable) failed: \(text)")
            }
            throw UpdateError.processFailed
        }
    }

    private func showErrorAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppStrings.text(.alertOK))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?()
    }

    private func scheduleReset(after seconds: TimeInterval, expected: State) {
        resetTimer?.invalidate()

        // Use a common-mode timer instead of `Task.sleep`: a menu stays open
        // in NSEventTrackingRunLoopMode, where default-mode timers do not
        // fire. The row must reset to “Check for Updates” while the menu is
        // still open.
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == expected else { return }
                self.resetTimer = nil
                self.setState(.idle)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        resetTimer = timer
    }

    private static func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
        !isVersion(lhs, newerThan: rhs) && !isVersion(rhs, newerThan: lhs)
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = numericVersion(candidate)
        let rhs = numericVersion(current)

        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0

            if left != right {
                return left > right
            }
        }

        return false
    }

    private static func numericVersion(_ raw: String) -> [Int] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }

        let core = value.split(separator: "-").first.map { String($0) } ?? value
        return core.split(separator: ".").map { component in
            Int(component.prefix { $0.isNumber }) ?? 0
        }
    }

    private static func isInstalledLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}
