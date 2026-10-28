import AppKit
import CoreGraphics
import Foundation

struct CommandKeyState: Equatable {
    var isLeftCommandPressed: Bool
    var isRightCommandPressed: Bool
    var progress: Double

    static let inactive = CommandKeyState(
        isLeftCommandPressed: false,
        isRightCommandPressed: false,
        progress: 0
    )
}

enum InputBlockerError: LocalizedError {
    case eventTapCreationFailed

    var errorDescription: String? {
        switch self {
        case .eventTapCreationFailed:
            return AppStrings.text(.errorInputBlockerFailed)
        }
    }
}

final class InputBlocker {
    var onCommandStateChanged: ((CommandKeyState) -> Void)?
    var onUnlockCompleted: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private static let leftCommandKeyCode: Int64 = 55
    private static let rightCommandKeyCode: Int64 = 54
    private static let leftCommandMask: UInt64 = 0x00000008
    private static let rightCommandMask: UInt64 = 0x00000010
    private static let sideCommandMask = leftCommandMask | rightCommandMask
    private static let systemDefinedEventType = CGEventType(rawValue: 14)!
    private static let auxControlButtonSubtype = 8
    private static let powerKeyType = 6

    private let stateLock = NSLock()
    private let unlockDuration: TimeInterval = 3

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPointerBlockingEnabled = true
    private var exemption: InputExemption?
    private var isExemptionKeyDown = false
    private var progressTimer: Timer?
    private var holdStartedAt: Date?
    private var isLeftCommandPressed = false
    private var isRightCommandPressed = false

    private(set) var isRunning = false

    deinit {
        stop()
    }

    func start(blockPointer: Bool, exemption: InputExemption?) throws {
        guard !isRunning else { return }

        resetState()
        isPointerBlockingEnabled = blockPointer
        self.exemption = exemption

        var eventTypes: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            Self.systemDefinedEventType
        ]

        if blockPointer {
            eventTypes.append(contentsOf: [
                .leftMouseDown,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseUp,
                .otherMouseDown,
                .otherMouseUp,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel,
                .mouseMoved
            ])
        }

        let mask = Self.eventMask(for: eventTypes)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw InputBlockerError.eventTapCreationFailed
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw InputBlockerError.eventTapCreationFailed
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true

        publish(.inactive)
    }

    func stop() {
        stopProgressTimer(resetProgress: true)

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        isRunning = false
        isPointerBlockingEnabled = true
        exemption = nil
        resetState()
        publish(.inactive)
    }

    private static func eventMask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { partialResult, type in
            partialResult | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let blocker = Unmanaged<InputBlocker>.fromOpaque(userInfo).takeUnretainedValue()
        return blocker.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == Self.systemDefinedEventType {
            return shouldBlockSystemDefinedEvent(event)
                ? nil
                : Unmanaged.passUnretained(event)
        }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            attemptToRestoreEventTap()
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            handleFlagsChanged(event)
            return shouldPassThrough(event)
                ? Unmanaged.passUnretained(event)
                : nil

        case .keyDown, .keyUp:
            return shouldPassThrough(event)
                ? Unmanaged.passUnretained(event)
                : nil

        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged,
             .otherMouseDragged,
             .mouseMoved,
             .scrollWheel:
            return isPointerBlockingEnabled ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func shouldBlockSystemDefinedEvent(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return false
        }

        guard Int(nsEvent.subtype.rawValue) == Self.auxControlButtonSubtype else {
            return false
        }

        let keyType = (nsEvent.data1 & 0xFFFF0000) >> 16
        return keyType != Self.powerKeyType
    }

    /// Returns `true` when the event belongs to the user's exempted shortcut
    /// and must reach macOS instead of being swallowed.
    private func shouldPassThrough(_ event: CGEvent) -> Bool {
        guard let exemption else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isGlobeExemption = exemption.keyCode == InputExemption.globeKeyCode
            || exemption.keyCode == InputExemption.globeActionKeyCode

        switch event.type {
        case .keyDown:
            if isGlobeExemption {
                // macOS turns a hardware Globe tap into a synthetic keyDown
                // with keycode 179; that event is what runs the configured
                // Globe action. Pass it together with the Fn key itself.
                return keyCode == InputExemption.globeKeyCode
                    || keyCode == InputExemption.globeActionKeyCode
            }

            if exemption.kind == .modifier {
                return keyCode == exemption.keyCode
            }

            guard keyCode == exemption.keyCode,
                  Self.modifierFlagsMatch(event.flags, required: exemption.modifierFlags) else {
                return false
            }

            isExemptionKeyDown = true
            return true

        case .keyUp:
            if isGlobeExemption {
                return keyCode == InputExemption.globeKeyCode
                    || keyCode == InputExemption.globeActionKeyCode
            }

            if exemption.kind == .modifier {
                return keyCode == exemption.keyCode
            }

            guard keyCode == exemption.keyCode else {
                return false
            }

            // Modifiers may be released before the key itself. Once the
            // matching keyDown reached the app, deliver the keyUp too so the
            // app can never be left with a stuck key.
            let shouldPass = isExemptionKeyDown
                || Self.modifierFlagsMatch(event.flags, required: exemption.modifierFlags)
            isExemptionKeyDown = false
            return shouldPass

        case .flagsChanged:
            if isGlobeExemption {
                return keyCode == InputExemption.globeKeyCode
            }

            if exemption.kind == .modifier {
                return keyCode == exemption.keyCode
            }

            // Keep macOS' modifier state in sync for the modifiers that are
            // part of the shortcut; otherwise the delivered keyDown can look
            // like a bare key press to some apps.
            return Self.modifierKeyCodes(for: exemption.modifierFlags).contains(keyCode)

        default:
            return false
        }
    }

    private static func modifierFlagsMatch(_ flags: CGEventFlags, required: CGEventFlags) -> Bool {
        flags.intersection(InputExemption.trackedModifierFlags)
            == required.intersection(InputExemption.trackedModifierFlags)
    }

    private static func modifierKeyCodes(for flags: CGEventFlags) -> Set<Int64> {
        var keyCodes: Set<Int64> = []

        if flags.contains(.maskCommand) {
            keyCodes.formUnion([54, 55])
        }

        if flags.contains(.maskShift) {
            keyCodes.formUnion([56, 60])
        }

        if flags.contains(.maskAlternate) {
            keyCodes.formUnion([58, 61])
        }

        if flags.contains(.maskControl) {
            keyCodes.formUnion([59, 62])
        }

        if flags.contains(.maskSecondaryFn) {
            keyCodes.insert(InputExemption.globeKeyCode)
        }

        return keyCodes
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let rawFlags = event.flags.rawValue

        var stateToPublish = CommandKeyState.inactive
        var shouldStartProgress = false
        var shouldStopProgress = false

        stateLock.lock()

        updateCommandState(keyCode: keyCode, rawFlags: rawFlags, flags: event.flags)

        let bothPressed = isLeftCommandPressed && isRightCommandPressed
        if bothPressed {
            if holdStartedAt == nil {
                holdStartedAt = Date()
                shouldStartProgress = true
            }
        } else {
            if holdStartedAt != nil {
                shouldStopProgress = true
            }
            holdStartedAt = nil
        }

        stateToPublish = CommandKeyState(
            isLeftCommandPressed: isLeftCommandPressed,
            isRightCommandPressed: isRightCommandPressed,
            progress: bothPressed ? currentProgressLocked() : 0
        )

        stateLock.unlock()

        publish(stateToPublish)

        if shouldStartProgress {
            DispatchQueue.main.async { [weak self] in
                self?.startProgressTimerIfNeeded()
            }
        }

        if shouldStopProgress {
            DispatchQueue.main.async { [weak self] in
                self?.stopProgressTimer(resetProgress: true)
            }
        }
    }

    private func updateCommandState(keyCode: Int64, rawFlags: UInt64, flags: CGEventFlags) {
        let hasSideSpecificFlags = (rawFlags & Self.sideCommandMask) != 0

        if hasSideSpecificFlags || !flags.contains(.maskCommand) {
            isLeftCommandPressed = (rawFlags & Self.leftCommandMask) != 0
            isRightCommandPressed = (rawFlags & Self.rightCommandMask) != 0
            return
        }

        switch keyCode {
        case Self.leftCommandKeyCode:
            isLeftCommandPressed = flags.contains(.maskCommand)
        case Self.rightCommandKeyCode:
            isRightCommandPressed = flags.contains(.maskCommand)
        default:
            break
        }
    }

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else { return }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer(resetProgress: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil

        guard resetProgress else { return }

        let state: CommandKeyState
        stateLock.lock()
        holdStartedAt = nil
        state = CommandKeyState(
            isLeftCommandPressed: isLeftCommandPressed,
            isRightCommandPressed: isRightCommandPressed,
            progress: 0
        )
        stateLock.unlock()

        publish(state)
    }

    private func updateProgress() {
        var stateToPublish = CommandKeyState.inactive
        var completed = false

        stateLock.lock()

        if holdStartedAt != nil {
            let progress = currentProgressLocked(now: Date())
            completed = progress >= 1
            stateToPublish = CommandKeyState(
                isLeftCommandPressed: isLeftCommandPressed,
                isRightCommandPressed: isRightCommandPressed,
                progress: progress
            )
        }

        stateLock.unlock()

        publish(stateToPublish)

        if completed {
            stopProgressTimer(resetProgress: false)
            DispatchQueue.main.async { [weak self] in
                self?.onUnlockCompleted?()
            }
        }
    }

    private func currentProgressLocked(now: Date = Date()) -> Double {
        guard let holdStartedAt else { return 0 }
        return min(max(now.timeIntervalSince(holdStartedAt) / unlockDuration, 0), 1)
    }

    private func attemptToRestoreEventTap() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let eventTap = self.eventTap, CFMachPortIsValid(eventTap) else {
                self.onFailure?(AppStrings.text(.errorEventTapStopped))
                return
            }

            CGEvent.tapEnable(tap: eventTap, enable: true)

            if !CFMachPortIsValid(eventTap) || !CGEvent.tapIsEnabled(tap: eventTap) {
                self.onFailure?(AppStrings.text(.errorEventTapStopped))
            }
        }
    }

    private func resetState() {
        stateLock.lock()
        isLeftCommandPressed = false
        isRightCommandPressed = false
        holdStartedAt = nil
        stateLock.unlock()

        isExemptionKeyDown = false
    }

    private func publish(_ state: CommandKeyState) {
        DispatchQueue.main.async { [weak self] in
            self?.onCommandStateChanged?(state)
        }
    }
}
