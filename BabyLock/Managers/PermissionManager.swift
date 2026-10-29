import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

enum PermissionState: Equatable {
    case notGranted
    case granted
    case requiresRestart
    case requiresManualCheck

    var title: String {
        title(language: .current)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .notGranted:
            return AppStrings.text(.permissionNotGranted, language: language)
        case .granted:
            return AppStrings.text(.permissionGranted, language: language)
        case .requiresRestart:
            return AppStrings.text(.permissionRequiresRestart, language: language)
        case .requiresManualCheck:
            return AppStrings.text(.permissionRequiresManualCheck, language: language)
        }
    }
}

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var accessibilityStatus: PermissionState = .notGranted
    @Published private(set) var inputMonitoringStatus: PermissionState = .notGranted

    var hasRequiredPermissions: Bool {
        accessibilityStatus == .granted && inputMonitoringStatus == .granted
    }

    var canAttemptLockMode: Bool {
        hasRequiredPermissions
    }

    var permissionIssueMessage: String {
        let language = PreferencesStore.shared.appLanguage

        if accessibilityStatus != .granted {
            return AppStrings.text(.permissionIssueAccessibility, language: language)
        }

        if inputMonitoringStatus == .notGranted {
            return AppStrings.text(.permissionIssueInputMonitoring, language: language)
        }

        return AppStrings.text(.permissionIssueGeneric, language: language)
    }

    var canContinuePastPermissionStep: Bool {
        hasRequiredPermissions
    }

    private init() {
        checkPermissions()
    }

    func checkPermissions() {
        // `AXIsProcessTrusted()` caches its answer for the lifetime of the
        // process, so the onboarding could keep showing "not granted" after
        // the user flipped the switch in System Settings. Calling the
        // options variant with `nil` asks tccd for a fresh answer without
        // prompting.
        accessibilityStatus = AXIsProcessTrustedWithOptions(nil) ? .granted : .notGranted
        inputMonitoringStatus = Self.currentInputMonitoringStatus()
    }

    var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    var isRunningFromApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// macOS ties TCC grants to the app's code signature. Ad-hoc builds get a
    /// new signature on every release, which leaves a ghost entry in System
    /// Settings: the toggle looks enabled, but the new binary is not trusted.
    /// Resetting our two entries and relaunching lets macOS prompt cleanly.
    func repairPermissionsAndRelaunch() {
        guard isRunningFromApplications else { return }

        resetTCCEntry(service: "Accessibility")
        resetTCCEntry(service: "ListenEvent")

        UserDefaults.standard.set(true, forKey: Self.needsPromptKey)
        _ = UserDefaults.standard.synchronize()
        relaunchApplication()
    }

    /// Called on the first launch after a permission reset or an app update.
    /// Triggers the macOS permission prompts and leaves System Settings to
    /// the user. Opening the pane here as well produced two competing
    /// prompts: the system alert plus a settings window on top of it.
    func requestPermissionsAfterRepair() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        checkPermissions()
    }

    static func consumeNeedsPromptFlag() -> Bool {
        let defaults = UserDefaults.standard
        let needsPrompt = defaults.bool(forKey: Self.needsPromptKey)
        if needsPrompt {
            defaults.removeObject(forKey: Self.needsPromptKey)
        }
        return needsPrompt
    }

    private static let needsPromptKey = "permissionsNeedPrompt"

    func refresh() {
        checkPermissions()
    }

    func openSystemSettingsForPermissions() {
        if accessibilityStatus != .granted {
            openAccessibilitySettings()
        } else {
            openInputMonitoringSettings()
        }
    }

    func openAccessibilitySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func openRequiredSettings() {
        openSystemSettingsForPermissions()
    }

    private func openSystemSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func resetTCCEntry(service: String) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mirr0ch1.babylock"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                NSLog("Baby Lock: tccutil reset \(service) exited with status \(process.terminationStatus)")
            }
        } catch {
            NSLog("Baby Lock: tccutil reset \(service) failed: \(error.localizedDescription)")
        }
    }

    private func relaunchApplication() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BabyLockRelaunch-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = tempDirectory.appendingPathComponent("relaunch.sh")
        let script = """
        #!/bin/sh
        set -u
        PID="$1"
        APP="$2"
        DIR="$3"
        TRIES=0
        while /bin/kill -0 "$PID" 2>/dev/null; do
            /bin/sleep 0.2
            TRIES=$((TRIES + 1))
            if [ "$TRIES" -ge 300 ]; then
                exit 1
            fi
        done
        /usr/bin/open "$APP"
        ( /bin/sleep 2; /bin/rm -rf "$DIR" ) >/dev/null 2>&1 &
        """

        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                Bundle.main.bundleURL.path,
                tempDirectory.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
        } catch {
            NSLog("Baby Lock: relaunch failed: \(error.localizedDescription)")
            showRelaunchError(error)
            return
        }

        NSApp.terminate(nil)
    }

    private func showRelaunchError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = AppStrings.text(.permissionIssueGeneric)
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppStrings.text(.alertOK))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func currentInputMonitoringStatus() -> PermissionState {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)

        switch access {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .notGranted
        case kIOHIDAccessTypeUnknown:
            return .requiresManualCheck
        default:
            return .requiresManualCheck
        }
    }
}
