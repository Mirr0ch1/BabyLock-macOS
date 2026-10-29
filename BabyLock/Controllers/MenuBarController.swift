import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private static let updateItemTag = 1_001

    private var statusItem: NSStatusItem?
    private let lockModeManager: LockModeManager
    private let updateManager = UpdateManager.shared
    private var updateMenuItemView: UpdateMenuItemView?
    private var onboardingWindow: NSWindow?
    /// The menu only depends on whether the lock is active, not on the
    /// 60 Hz unlock progress. Comparing this prevents a full menu rebuild on
    /// every progress tick while the user holds the two Command keys.
    private var lastLockActive: Bool?
    private var isMenuOpen = false
    private var needsMenuRebuild = false

    init(lockModeManager: LockModeManager) {
        self.lockModeManager = lockModeManager
        super.init()
    }

    func install() {
        lockModeManager.onStateChange = { [weak self] state in
            self?.lockStateDidChange(state)
        }
        lockModeManager.onPermissionsRequired = { [weak self] in
            self?.showOnboarding(initialStep: .permissions)
        }
        updateManager.onStateChange = { [weak self] in
            self?.refreshUpdateMenuItem()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .appLanguageDidChange,
            object: nil
        )

        installStatusItemIfNeeded()
        lastLockActive = lockModeManager.isLockActive
        updateManager.checkOnLaunch()
    }

    private func lockStateDidChange(_ state: LockModeState) {
        let isActive = state.isActive
        guard lastLockActive != isActive else { return }
        lastLockActive = isActive
        rebuildMenu()
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

        let view = OnboardingView(
            initialStep: initialStep,
            onPreferredHeightChange: { [weak self] height in
                self?.resizeOnboardingWindow(to: height)
            }
        ) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.installStatusItemIfNeeded()
            NSApp.setActivationPolicy(.accessory)
        }

        let window = makeWindow(
            title: "Baby Lock",
            size: NSSize(width: 560, height: initialStep.preferredContentHeight),
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

        // Replacing the status item's menu while it is being tracked can
        // close the menu or confuse AppKit. Defer the rebuild until it closes.
        if isMenuOpen {
            needsMenuRebuild = true
            return
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        if lockModeManager.isLockActive {
            // While locked, management actions must not be reachable. In
            // particular, quitting the app would stop the input tap and
            // silently unlock the Mac when pointer blocking is disabled.
            let activeItem = NSMenuItem(title: text(.menuLockEnabled), action: nil, keyEquivalent: "")
            activeItem.isEnabled = false
            menu.addItem(activeItem)

            let hintItem = NSMenuItem(title: text(.overlayExitInstruction), action: nil, keyEquivalent: "")
            hintItem.isEnabled = false
            menu.addItem(hintItem)

            menu.delegate = self
            statusItem.menu = menu
            return
        }

        menu.addItem(NSMenuItem(
            title: text(.menuStartLock),
            action: #selector(startLockMode),
            keyEquivalent: ""
        ))

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: text(.menuSettings),
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        updateItem.tag = Self.updateItemTag
        updateItem.isEnabled = true
        menu.addItem(updateItem)
        menu.delegate = self
        installUpdateMenuItemView(in: menu)

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
        guard !lockModeManager.isLockActive else { return }
        SettingsWindowController.shared.show()
    }

    @objc private func handleUpdateItemClick() {
        guard !lockModeManager.isLockActive else { return }

        switch updateManager.state {
        case .updateAvailable:
            // The confirmation alert is modal; close the menu first so it
            // does not stay open behind the alert.
            statusItem?.menu?.cancelTracking()
            DispatchQueue.main.async { [weak self] in
                self?.updateManager.installAvailableUpdate()
            }
        case .checking, .downloading, .installing:
            break
        case .idle, .upToDate, .failed:
            updateManager.checkForUpdates(userInitiated: true)
        }
    }

    private func refreshUpdateMenuItem() {
        updateMenuItemView?.configure(
            title: updateItemTitle,
            isEnabled: updateManager.isMenuActionEnabled
        )
    }

    /// A menu item with a custom view can lose that view after repeated menu
    /// opens. Replacing it with a fresh view on every open keeps the update
    /// row from silently disappearing from the menu.
    private func installUpdateMenuItemView(in menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == Self.updateItemTag }) else {
            return
        }

        let view = UpdateMenuItemView()
        view.onClick = { [weak self] in
            self?.handleUpdateItemClick()
        }
        view.configure(
            title: updateItemTitle,
            isEnabled: updateManager.isMenuActionEnabled
        )

        item.view = view
        updateMenuItemView = view
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
            return String(
                format: text(.menuUpdateAvailable),
                "v" + version
            )
        case .downloading:
            return text(.menuDownloadingUpdate)
        case .installing:
            return text(.menuInstallingUpdate)
        case .failed:
            return text(.menuUpdateFailed)
        }
    }

    @objc private func quitApplication() {
        guard !lockModeManager.isLockActive else { return }
        lockModeManager.stopLockMode()
        NSApp.terminate(nil)
    }

    @objc private func handleLanguageChanged() {
        rebuildMenu()
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: PreferencesStore.shared.appLanguage)
    }

    /// The permission step has less content than the welcome and unlock
    /// steps, so the onboarding window changes height as the user advances
    /// instead of leaving a large empty area below the permission controls.
    private func resizeOnboardingWindow(to contentHeight: CGFloat) {
        guard let window = onboardingWindow else { return }

        let currentHeight = window.contentRect(forFrameRect: window.frame).height
        guard abs(currentHeight - contentHeight) > 0.5 else { return }

        let oldFrame = window.frame
        window.setContentSize(NSSize(width: 560, height: contentHeight))

        var newFrame = window.frame
        newFrame.origin.y = oldFrame.maxY - newFrame.height
        window.setFrame(newFrame, display: true, animate: true)
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        // The onboarding window manages its own height. Leaving the default
        // sizing options on lets the hosting controller impose the SwiftUI
        // view's intrinsic/minimum size, which overrides setContentSize and
        // makes the permissions step much taller than its content.
        hostingController.sizingOptions = []
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.setContentSize(size)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
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

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        isMenuOpen = true
        installUpdateMenuItemView(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false

        if needsMenuRebuild {
            needsMenuRebuild = false
            rebuildMenu()
        }
    }
}

/// A menu row that behaves like a button without dismissing the menu.
///
/// A regular `NSMenuItem` closes the menu as soon as its action fires, which
/// makes a multi-step update check (“checking…”, then “no updates”, then
/// “check again”) impossible to show. A custom view keeps the menu open, so
/// the row can update its own title while the user watches.
@MainActor
final class UpdateMenuItemView: NSView {
    var onClick: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "")
    private var isActionEnabled = true
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var isPressed = false {
        didSet { updateAppearance() }
    }
    private var trackingAreaReference: NSTrackingArea?

    private let horizontalPadding: CGFloat = 14
    private let preferredWidth: CGFloat = 280
    private let preferredHeight: CGFloat = 22

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: preferredHeight))

        titleField.font = NSFont.menuFont(ofSize: 0)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.textColor = .labelColor
        addSubview(titleField)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: preferredHeight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func layout() {
        super.layout()

        let fieldHeight = titleField.intrinsicContentSize.height
        titleField.frame = NSRect(
            x: horizontalPadding,
            y: (bounds.height - fieldHeight) / 2,
            width: max(bounds.width - horizontalPadding - 12, 0),
            height: fieldHeight
        )
    }

    func configure(title: String, isEnabled: Bool) {
        titleField.stringValue = title
        isActionEnabled = isEnabled
        setAccessibilityLabel(title)
        needsLayout = true
        titleField.needsDisplay = true
        updateAppearance()
    }

    override func draw(_ dirtyRect: NSRect) {
        if (isHovered || isPressed) && isActionEnabled {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 5, dy: 1),
                xRadius: 4,
                yRadius: 4
            ).fill()
        }

        super.draw(dirtyRect)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            isHovered = false
            isPressed = false
        }

        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isActionEnabled else { return }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isActionEnabled, isPressed else {
            isPressed = false
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        isPressed = false

        if bounds.contains(location) {
            onClick?()
        }
    }

    private func updateAppearance() {
        if !isActionEnabled {
            titleField.textColor = .disabledControlTextColor
        } else if isHovered || isPressed {
            titleField.textColor = .selectedMenuItemTextColor
        } else {
            titleField.textColor = .labelColor
        }

        needsDisplay = true
    }
}
