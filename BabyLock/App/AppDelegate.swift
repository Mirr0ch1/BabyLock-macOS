import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hasCompletedOnboarding = PreferencesStore.shared.hasCompletedOnboarding
        NSApp.setActivationPolicy(hasCompletedOnboarding ? .accessory : .regular)

        let menuBarController = MenuBarController(lockModeManager: .shared)
        menuBarController.install()
        self.menuBarController = menuBarController
        installSystemObservers()

        if !hasCompletedOnboarding {
            menuBarController.showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        LockModeManager.shared.stopLockMode()
    }

    private func installSystemObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
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

    @objc private func handleScreenParametersChanged() {
        LockModeManager.shared.handleDisplayConfigurationChanged()
    }

    @objc private func handleLocaleChanged() {
        guard case .system = PreferencesStore.shared.languagePreference else {
            return
        }

        PreferencesStore.shared.notifyLanguageMayHaveChanged()
    }
}
