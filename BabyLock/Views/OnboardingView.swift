import AppKit
import SwiftUI

@MainActor
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var preferences = PreferencesStore.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @StateObject private var unlockTest = CommandUnlockTestModel()
    @State private var step: OnboardingStep
    @State private var navigationDirection: NavigationDirection = .forward

    let onComplete: () -> Void
    let onPreferredHeightChange: (CGFloat) -> Void

    init(
        initialStep: OnboardingStep = .welcome,
        onPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onComplete: @escaping () -> Void = {}
    ) {
        self._step = State(initialValue: initialStep)
        self.onPreferredHeightChange = onPreferredHeightChange
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            WindowGlassBackground()
                .ignoresSafeArea()

            ZStack {
                content
                    .id(step)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: OnboardingContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(stepTransition)
            }
            .padding(.horizontal, 36)
            .padding(.top, Self.contentTopPadding)
            .padding(.bottom, Self.contentBottomPadding)
            .clipped()
        }
        .onAppear {
            permissions.checkPermissions()

            if step != .permissions {
                onPreferredHeightChange(step.preferredContentHeight)
            }
        }
        .onDisappear {
            unlockTest.stop()
        }
        .task(id: step) {
            await refreshPermissionsWhileNeeded()
        }
        .onChange(of: step) { newStep in
            handleStepChange(newStep)

            if newStep != .permissions {
                onPreferredHeightChange(newStep.preferredContentHeight)
            }
        }
        .onPreferenceChange(OnboardingContentHeightKey.self) { height in
            guard step == .permissions, height > 0 else { return }
            onPreferredHeightChange(height + Self.contentTopPadding + Self.contentBottomPadding)
        }
    }

    private static let contentTopPadding: CGFloat = 34
    private static let contentBottomPadding: CGFloat = 28

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .move(edge: navigationDirection.insertionEdge).combined(with: .opacity),
            removal: .move(edge: navigationDirection.removalEdge).combined(with: .opacity)
        )
    }

    private var stepAnimation: Animation? {
        reduceMotion
            ? .easeInOut(duration: 0.16)
            : .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.08)
    }

    private func advance(to nextStep: OnboardingStep) {
        navigate(to: nextStep, direction: .forward)
    }

    private func retreat(to previousStep: OnboardingStep) {
        navigate(to: previousStep, direction: .backward)
    }

    private func navigate(to nextStep: OnboardingStep, direction: NavigationDirection) {
        navigationDirection = direction

        withAnimation(stepAnimation) {
            step = nextStep
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .permissions:
            permissionsStep
        case .unlockTest:
            unlockTestStep
        case .completed:
            completedStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Group {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)

                Text("Baby Lock")
                    .font(.system(size: 30, weight: .semibold))

                Text(text(.onboardingWelcomeSubtitle))
                    .font(.title3)
                    .multilineTextAlignment(.center)

                Text(text(.onboardingWelcomeBody))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 460)
            .offset(y: -18)

            Spacer()

            HStack {
                Spacer()

                Button(text(.onboardingContinue)) {
                    advance(to: .permissions)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text(.onboardingPermissionsTitle))
                .font(.system(size: 24, weight: .semibold))

            Text(text(.onboardingPermissionsDescription))
                .foregroundStyle(.secondary)

            PermissionRow(
                title: text(.onboardingAccessibilityTitle),
                description: text(.onboardingAccessibilityDescription),
                status: permissions.accessibilityStatus,
                action: {
                    permissions.openAccessibilitySettings()
                }
            )

            PermissionRow(
                title: text(.onboardingInputMonitoringTitle),
                description: text(.onboardingInputMonitoringDescription),
                status: permissions.inputMonitoringStatus,
                action: {
                    permissions.openInputMonitoringSettings()
                }
            )

            if !permissions.isRunningFromApplications {
                Text(text(.onboardingPermissionLocationWarning))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Button(text(.onboardingPermissionRepair)) {
                    permissions.repairPermissionsAndRelaunch()
                }
                .controlSize(.small)
                .disabled(!permissions.isRunningFromApplications)

                Text(text(.onboardingPermissionRepairHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(text(.onboardingPrivacyNote))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button(text(.onboardingBack)) {
                    retreat(to: .welcome)
                }
                .controlSize(.large)

                Spacer()

                Button(text(.onboardingContinue)) {
                    advance(to: .unlockTest)
                }
                .disabled(!permissions.canContinuePastPermissionStep)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
    }

    private var unlockTestStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Text(text(.onboardingUnlockTestTitle))
                    .font(.system(size: 26, weight: .semibold))

                Text(text(.onboardingUnlockTestDescription))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                UnlockProgressIndicator(
                    progress: unlockTest.visibleProgress,
                    isCompleted: unlockTest.isCompleted,
                    tint: .primary
                )
                .padding(.top, 8)
                .padding(.bottom, -2)

                HStack(spacing: 32) {
                    OnboardingCommandKeyView(
                        title: text(.onboardingLeftCommand),
                        isActive: unlockTest.commandKeyState.isLeftCommandPressed
                    )

                    OnboardingCommandKeyView(
                        title: text(.onboardingRightCommand),
                        isActive: unlockTest.commandKeyState.isRightCommandPressed
                    )
                }

                Text(text(.onboardingUnlockTestFootnote))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 500)
            .offset(y: -26)

            Spacer()

            HStack {
                Button(text(.onboardingBack)) {
                    retreat(to: .permissions)
                }
                .controlSize(.large)

                Spacer()

                Button(text(.onboardingContinue)) {
                    advance(to: .completed)
                }
                .disabled(!unlockTest.isCompleted)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var completedStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text(text(.onboardingCompletedTitle))
                    .font(.system(size: 28, weight: .semibold))

                Text(text(.onboardingCompletedDescription))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 500)
            .offset(y: -24)

            Spacer()

            HStack {
                Button(text(.onboardingBack)) {
                    retreat(to: .unlockTest)
                }
                .controlSize(.large)

                Spacer()

                Button(text(.onboardingDone)) {
                    PreferencesStore.shared.hasCompletedOnboarding = true
                    onComplete()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func handleStepChange(_ newStep: OnboardingStep) {
        switch newStep {
        case .unlockTest:
            unlockTest.start()
        case .completed:
            unlockTest.stop()
        case .welcome, .permissions:
            unlockTest.stop()
        }
    }

    private func refreshPermissionsWhileNeeded() async {
        guard step == .permissions else { return }

        while !Task.isCancelled {
            permissions.checkPermissions()

            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
        }
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: preferences.appLanguage)
    }
}

private enum NavigationDirection {
    case forward
    case backward

    var insertionEdge: Edge {
        switch self {
        case .forward:
            return .trailing
        case .backward:
            return .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward:
            return .leading
        case .backward:
            return .trailing
        }
    }
}

private struct OnboardingContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WindowGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}

struct WindowTitleHider: NSViewRepresentable {
    var extendsContentIntoTitlebar = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        hideTitleWhenWindowIsAvailable(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hideTitleWhenWindowIsAvailable(from: nsView)
    }

    private func hideTitleWhenWindowIsAvailable(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true

            if extendsContentIntoTitlebar {
                window.styleMask.insert(.fullSizeContentView)
                window.toolbar = nil
                window.titlebarSeparatorStyle = .none
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let status: PermissionState
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .frame(width: 22, height: 22, alignment: .center)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)

                    Spacer()

                    Text(status.title(language: PreferencesStore.shared.appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if status != .granted {
                        Button(AppStrings.text(.onboardingOpen, language: PreferencesStore.shared.appLanguage)) {
                            action()
                        }
                        .controlSize(.small)
                    }
                }

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbolName: String {
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .requiresRestart:
            return "exclamationmark.triangle"
        case .notGranted, .requiresManualCheck:
            return "exclamationmark.circle"
        }
    }

    private var symbolColor: Color {
        switch status {
        case .granted:
            return .green
        case .requiresRestart:
            return .orange
        case .notGranted, .requiresManualCheck:
            return .secondary
        }
    }
}

private struct OnboardingCommandKeyView: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .frame(width: 112, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isActive ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(isActive ? 0.34 : 0.18), lineWidth: 1)
            )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private final class CommandUnlockTestModel: ObservableObject {
    @Published private(set) var commandKeyState: CommandKeyState = .inactive
    @Published private(set) var isCompleted = false

    var visibleProgress: Double {
        if isCompleted {
            return 1
        }

        return commandKeyState.isLeftCommandPressed && commandKeyState.isRightCommandPressed
            ? commandKeyState.progress
            : 0
    }

    private static let leftCommandKeyCode: UInt16 = 55
    private static let rightCommandKeyCode: UInt16 = 54
    private static let leftCommandMask: UInt = 0x00000008
    private static let rightCommandMask: UInt = 0x00000010
    private static let sideCommandMask = leftCommandMask | rightCommandMask

    private let unlockDuration: TimeInterval = 3
    private var eventMonitor: Any?
    private var progressTimer: Timer?
    private var holdStartedAt: Date?
    private var isLeftCommandPressed = false
    private var isRightCommandPressed = false

    deinit {
        stop()
    }

    func start() {
        stop()
        guard !isCompleted else {
            commandKeyState = CommandKeyState(
                isLeftCommandPressed: false,
                isRightCommandPressed: false,
                progress: 1
            )
            return
        }

        resetForNewAttempt()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        stopProgressTimer(resetProgress: true)
        isLeftCommandPressed = false
        isRightCommandPressed = false
        commandKeyState = isCompleted
            ? CommandKeyState(isLeftCommandPressed: false, isRightCommandPressed: false, progress: 1)
            : .inactive
    }

    private func resetForNewAttempt() {
        isLeftCommandPressed = false
        isRightCommandPressed = false
        commandKeyState = .inactive
        stopProgressTimer(resetProgress: true)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard !isCompleted else { return }

        updateCommandState(from: event)

        let bothPressed = isLeftCommandPressed && isRightCommandPressed
        if bothPressed {
            startProgressTimerIfNeeded()
        } else {
            stopProgressTimer(resetProgress: true)
        }

        publishCommandState()
    }

    private func updateCommandState(from event: NSEvent) {
        let rawFlags = event.modifierFlags.rawValue
        let hasSideSpecificFlags = (rawFlags & Self.sideCommandMask) != 0

        if hasSideSpecificFlags || !event.modifierFlags.contains(.command) {
            isLeftCommandPressed = (rawFlags & Self.leftCommandMask) != 0
            isRightCommandPressed = (rawFlags & Self.rightCommandMask) != 0
            return
        }

        switch event.keyCode {
        case Self.leftCommandKeyCode:
            isLeftCommandPressed = event.modifierFlags.contains(.command)
        case Self.rightCommandKeyCode:
            isRightCommandPressed = event.modifierFlags.contains(.command)
        default:
            break
        }
    }

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else { return }

        holdStartedAt = Date()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
        updateProgress()
    }

    private func stopProgressTimer(resetProgress: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil
        holdStartedAt = nil

        if resetProgress {
            commandKeyState = CommandKeyState(
                isLeftCommandPressed: isLeftCommandPressed,
                isRightCommandPressed: isRightCommandPressed,
                progress: 0
            )
        }
    }

    private func updateProgress() {
        guard let holdStartedAt else { return }

        let elapsed = Date().timeIntervalSince(holdStartedAt)
        let progress = min(max(elapsed / unlockDuration, 0), 1)

        commandKeyState = CommandKeyState(
            isLeftCommandPressed: isLeftCommandPressed,
            isRightCommandPressed: isRightCommandPressed,
            progress: progress
        )

        if progress >= 1 {
            isCompleted = true
            stopProgressTimer(resetProgress: false)
        }
    }

    private func publishCommandState() {
        commandKeyState = CommandKeyState(
            isLeftCommandPressed: isLeftCommandPressed,
            isRightCommandPressed: isRightCommandPressed,
            progress: commandKeyState.progress
        )
    }

}
