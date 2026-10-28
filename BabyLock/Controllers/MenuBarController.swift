import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let lockModeManager: LockModeManager
    private let updateManager = UpdateManager.shared
    private var onboardingWindow: NSWindow?

    init(lockModeManager: LockModeManager) {
        self.lockModeManager = lockModeManager
        super.init()
    }

    func install() {
        lockModeManager.onStateChange = { [weak self] _ in
            self?.rebuildMenu()
        }
        lockModeManager.onPermissionsRequired = { [weak self] in
            self?.showOnboarding(initialStep: .permissions)
        }
        updateManager.onStateChange = { [weak self] in
            self?.rebuildMenu()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .appLanguageDidChange,
            object: nil
        )

        installStatusItemIfNeeded()
        updateManager.checkOnLaunch()
    }

    func showOnboarding(initialStep: OnboardingStep = .welcome) {
        NSApp.setActivationPolicy(.regular)

        if let onboardingWindow {
            if initialStep == .permissions {
                onboardingWindow.close()
                self.onboardingWindow = nil
            } else {
                onboardingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        let view = OnboardingView(initialStep: initialStep) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.installStatusItemIfNeeded()
            NSApp.setActivationPolicy(.accessory)
        }

        let window = makeWindow(
            title: "Baby Lock",
            size: NSSize(width: 560, height: 540),
            rootView: view
        )
        window.delegate = self

        onboardingWindow = window
        centerWindowOnMainScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusButton()
        rebuildMenu()
    }

    private func configureStatusButton() {
        guard let button = statusItem?.button else { return }

        button.image = StatusIcon.make()
        button.image?.isTemplate = true
        button.toolTip = "Baby Lock"
        button.setAccessibilityLabel("Baby Lock")
    }

    private func rebuildMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()

        if lockModeManager.isLockActive {
            let activeItem = NSMenuItem(title: text(.menuLockEnabled), action: nil, keyEquivalent: "")
            activeItem.isEnabled = false
            menu.addItem(activeItem)
        } else {
            menu.addItem(NSMenuItem(
                title: text(.menuStartLock),
                action: #selector(startLockMode),
                keyEquivalent: ""
            ))
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: text(.menuSettings),
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: updateItemTitle,
            action: #selector(handleUpdateItem),
            keyEquivalent: ""
        )
        updateItem.isEnabled = updateManager.isMenuActionEnabled
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem(
            title: text(.menuQuit),
            action: #selector(quitApplication),
            keyEquivalent: ""
        ))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func startLockMode() {
        guard PreferencesStore.shared.hasCompletedOnboarding else {
            showOnboarding()
            return
        }

        lockModeManager.startLockMode()
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func handleUpdateItem() {
        switch updateManager.state {
        case .updateAvailable:
            updateManager.installAvailableUpdate()
        case .checking, .downloading, .installing:
            break
        case .idle, .upToDate, .failed:
            Task { @MainActor in
                await updateManager.checkForUpdates(userInitiated: true)
            }
        }
    }

    private var updateItemTitle: String {
        switch updateManager.state {
        case .idle:
            return text(.menuCheckForUpdates)
        case .checking:
            return text(.menuCheckingForUpdates)
        case .upToDate:
            return text(.menuUpToDate)
        case .updateAvailable(let version):
            return text(.menuUpdateAvailable) + " v" + version
        case .downloading:
            return text(.menuDownloadingUpdate)
        case .installing:
            return text(.menuInstallingUpdate)
        case .failed:
            return text(.menuUpdateFailed)
        }
    }

    @objc private func quitApplication() {
        lockModeManager.stopLockMode()
        NSApp.terminate(nil)
    }

    @objc private func handleLanguageChanged() {
        rebuildMenu()
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: PreferencesStore.shared.appLanguage)
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.setContentSize(size)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        return window
    }

    private func centerWindowOnMainScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )

        window.setFrameOrigin(origin)
    }
}

extension MenuBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            onboardingWindow = nil

            if PreferencesStore.shared.hasCompletedOnboarding {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
