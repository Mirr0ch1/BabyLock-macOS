import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAnotherInstanceIsRunning() else { return }

        let hasCompletedOnboarding = PreferencesStore.shared.hasCompletedOnboarding
        NSApp.setActivationPolicy(hasCompletedOnboarding ? .accessory : .regular)

        let menuBarController = MenuBarController(lockModeManager: .shared)
        menuBarController.install()
        self.menuBarController = menuBarController
        installSystemObservers()

        if !hasCompletedOnboarding {
            menuBarController.showOnboarding()
        }

        handlePendingPermissionPrompt()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        LockModeManager.shared.stopLockMode()
    }

    private func terminateIfAnotherInstanceIsRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard running.count > 1 else { return false }

        NSApp.terminate(nil)
        return true
    }

    private func installSystemObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocaleChanged),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep() {
        LockModeManager.shared.handleSystemWillSleep()
    }

    @objc private func handleDidWake() {
        LockModeManager.shared.handleSystemDidWake()
    }

    @objc private func handleScreenParametersChanged() {
        LockModeManager.shared.handleDisplayConfigurationChanged()
    }

    @objc private func handleLocaleChanged() {
        guard case .system = PreferencesStore.shared.languagePreference else {
            return
        }

        PreferencesStore.shared.notifyLanguageMayHaveChanged()
    }

    private func handlePendingPermissionPrompt() {
        guard PermissionManager.consumeNeedsPromptFlag() else { return }
        guard PreferencesStore.shared.hasCompletedOnboarding else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }

            PermissionManager.shared.checkPermissions()
            guard !PermissionManager.shared.hasRequiredPermissions else { return }

            self.menuBarController?.showOnboarding(initialStep: .permissions)
            PermissionManager.shared.requestPermissionsAfterRepair()
        }
    }
}
