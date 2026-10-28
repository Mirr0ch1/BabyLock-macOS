import AppKit
import Foundation

@MainActor
final class LockModeManager: ObservableObject {
    static let shared = LockModeManager()

    @Published private(set) var state: LockModeState = .inactive {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((LockModeState) -> Void)?
    var onPermissionsRequired: (() -> Void)?

    var isLockActive: Bool {
        state.isActive
    }

    private let inputBlocker: InputBlocker
    private let overlayManager: OverlayManager
    private let preferences: PreferencesStore
    private let pointerDeviceSeizer: PointerDeviceSeizer
    private let cursorController: CursorController
    private var autoUnlockTimer: Timer?
    private var unlockCompletionTask: Task<Void, Never>?

    private convenience init() {
        self.init(
            inputBlocker: InputBlocker(),
            overlayManager: OverlayManager(),
            preferences: PreferencesStore.shared,
            pointerDeviceSeizer: PointerDeviceSeizer(),
            cursorController: CursorController()
        )
    }

    init(
        inputBlocker: InputBlocker,
        overlayManager: OverlayManager,
        preferences: PreferencesStore,
        pointerDeviceSeizer: PointerDeviceSeizer,
        cursorController: CursorController
    ) {
        self.inputBlocker = inputBlocker
        self.overlayManager = overlayManager
        self.preferences = preferences
        self.pointerDeviceSeizer = pointerDeviceSeizer
        self.cursorController = cursorController

        self.inputBlocker.onCommandStateChanged = { [weak self] commandState in
            Task { @MainActor in
                self?.handleCommandStateChanged(commandState)
            }
        }

        self.inputBlocker.onUnlockCompleted = { [weak self] in
            Task { @MainActor in
                self?.completeUnlockAndStopLockMode()
            }
        }

        self.inputBlocker.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.stopLockModeAfterFailure(message: message)
            }
        }
    }

    func startLockMode() {
        guard !state.isActive else { return }

        unlockCompletionTask?.cancel()
        unlockCompletionTask = nil
        state = .starting

        let permissionManager = PermissionManager.shared
        permissionManager.checkPermissions()

        guard permissionManager.canAttemptLockMode else {
            state = .inactive
            onPermissionsRequired?()
            return
        }

        let blockPointer = preferences.blockPointerInput

        do {
            try overlayManager.showOverlay(
                blackoutEnabled: preferences.blackoutEnabled,
                scope: preferences.blackoutScope,
                autoUnlockDuration: preferences.autoUnlockDuration
            )

            if blockPointer {
                pointerDeviceSeizer.start()
                cursorController.hideAndFreezeCursor()
            }

            try inputBlocker.start(
                blockPointer: blockPointer,
                exemption: preferences.inputExemption
            )
            scheduleAutoUnlockIfNeeded()
            state = .active
        } catch {
            autoUnlockTimer?.invalidate()
            autoUnlockTimer = nil
            inputBlocker.stop()
            pointerDeviceSeizer.stop()
            cursorController.restoreCursor()
            overlayManager.hideOverlay()
            state = .inactive
            showMessage(
                title: text(.errorLockNotStarted),
                message: error.localizedDescription
            )
        }
    }

    func stopLockMode() {
        guard state.isActive else { return }

        unlockCompletionTask?.cancel()
        unlockCompletionTask = nil
        state = .stopping
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        inputBlocker.stop()
        pointerDeviceSeizer.stop()
        cursorController.restoreCursor()
        overlayManager.hideOverlay()
        state = .inactive
    }

    func handleSystemWillSleep() {
        stopLockMode()
    }

    func handleDisplayConfigurationChanged() {
        guard state.isActive else { return }

        // The HUD is a small panel and can simply stay where it is. Only the
        // full-screen blackout depends on the display layout.
        guard preferences.blackoutEnabled else { return }

        stopLockMode()
        showMessage(
            title: text(.errorLockDisabled),
            message: text(.errorDisplayConfigurationChanged)
        )
    }

    private func handleCommandStateChanged(_ commandState: CommandKeyState) {
        switch state {
        case .active, .unlocking:
            break
        case .inactive, .starting, .stopping:
            return
        }

        overlayManager.updateCommandKeyState(commandState)

        if commandState.progress > 0 {
            state = .unlocking(progress: commandState.progress)
        } else {
            state = .active
        }
    }

    private func completeUnlockAndStopLockMode() {
        guard state.isActive else { return }

        state = .stopping
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        inputBlocker.stop()
        pointerDeviceSeizer.stop()
        cursorController.restoreCursor()
        overlayManager.markUnlockCompleted()

        unlockCompletionTask?.cancel()
        unlockCompletionTask = Task { @MainActor in
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let delay: UInt64 = reduceMotion ? 150_000_000 : 450_000_000
            try? await Task.sleep(nanoseconds: delay)

            guard !Task.isCancelled else { return }

            overlayManager.hideOverlay()
            state = .inactive
            unlockCompletionTask = nil
        }
    }

    private func stopLockModeAfterFailure(message: String) {
        let wasActive = state.isActive
        stopLockMode()

        if wasActive {
            showMessage(
                title: text(.errorLockDisabled),
                message: message
            )
        }
    }

    private func scheduleAutoUnlockIfNeeded() {
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil

        let interval = preferences.autoUnlockDuration.timeInterval

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopLockMode()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        autoUnlockTimer = timer
    }

    private func showMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: text(.alertOK))
        alert.runModal()
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: preferences.appLanguage)
    }
}
