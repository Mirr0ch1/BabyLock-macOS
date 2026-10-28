import CoreGraphics
import Foundation

/// A key or key combination that keeps working while Baby Lock blocks the
/// keyboard. The Globe/Fn key is supported as a standalone exemption because
/// macOS delivers it as a modifier-only `flagsChanged` event.
struct InputExemption: Codable, Equatable {
    enum Kind: String, Codable {
        /// A regular key press, optionally with modifier keys.
        case key
        /// A modifier key used on its own, currently the Globe/Fn key.
        case modifier
    }

    let kind: Kind
    let keyCode: Int64
    /// Modifier flags that must be held for `.key` exemptions, stored as the
    /// raw `NSEvent.ModifierFlags` / `CGEventFlags` bits.
    let modifiers: UInt64
    /// Label captured while recording, so keys without a printable character
    /// keep a readable name.
    let label: String

    var displayText: String {
        switch kind {
        case .modifier:
            return label
        case .key:
            return Self.symbols(for: CGEventFlags(rawValue: modifiers)) + label
        }
    }

    var modifierFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiers)
    }

    static let globeKeyCode: Int64 = 63
    /// Undocumented synthetic key event macOS emits after a hardware Globe/Fn
    /// tap. This event is what actually performs the configured Globe action
    /// (dictation, emoji picker, input source, …).
    static let globeActionKeyCode: Int64 = 179
    static let globeLabel = "🌐 Fn"

    /// Only these modifiers take part in matching. Caps Lock, the numeric pad
    /// and device-specific bits are deliberately ignored.
    static let trackedModifierFlags: CGEventFlags = [
        .maskShift,
        .maskControl,
        .maskAlternate,
        .maskCommand,
        .maskSecondaryFn
    ]

    static func symbols(for flags: CGEventFlags) -> String {
        var symbols = ""

        if flags.contains(.maskSecondaryFn) {
            symbols += "fn "
        }

        if flags.contains(.maskControl) {
            symbols += "⌃"
        }

        if flags.contains(.maskAlternate) {
            symbols += "⌥"
        }

        if flags.contains(.maskShift) {
            symbols += "⇧"
        }

        if flags.contains(.maskCommand) {
            symbols += "⌘"
        }

        return symbols
    }

    static func keyLabel(forKeyCode keyCode: Int64, characters: String?) -> String {
        if let specialLabel = specialKeyLabels[keyCode] {
            return specialLabel
        }

        if let characters, !characters.isEmpty {
            return characters.uppercased()
        }

        return "Key \(keyCode)"
    }

    private static let specialKeyLabels: [Int64: String] = [
        36: "↩",
        48: "⇥",
        49: "␣",
        51: "⌫",
        53: "⎋",
        57: "⇪",
        64: "F17",
        76: "⌤",
        79: "F18",
        80: "F19",
        90: "F20",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        115: "↖",
        116: "⇞",
        117: "⌦",
        118: "F4",
        119: "↘",
        120: "F2",
        121: "⇟",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]
}
