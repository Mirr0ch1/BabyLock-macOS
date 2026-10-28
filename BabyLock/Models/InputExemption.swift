import CoreGraphics
import Foundation

/// A single key that stays usable while Baby Lock blocks the keyboard.
///
/// Exemptions are stored as a list instead of one shortcut so the user can
/// keep several keys working at once. For a shortcut, every key of the
/// shortcut has to be added separately: adding `⌃`, `C` and `V` makes both
/// `⌃C` and `⌃V` pass through.
struct ExemptKey: Codable, Equatable, Identifiable {
    let keyCode: Int64
    let label: String

    var id: Int64 { keyCode }
    var displayText: String { label }

    static let globeKeyCode: Int64 = 63
    /// Undocumented synthetic key event macOS emits after a hardware Globe/Fn
    /// tap. This event is what actually performs the configured Globe action
    /// (dictation, emoji picker, input source, …).
    static let globeActionKeyCode: Int64 = 179
    static let globeLabel = "🌐 Fn"

    static var globe: ExemptKey {
        ExemptKey(keyCode: globeKeyCode, label: globeLabel)
    }

    /// Right-side modifiers are folded onto their left-side counterpart, so
    /// adding "Control" once covers both sides of the keyboard.
    static func canonicalKeyCode(_ keyCode: Int64) -> Int64 {
        switch keyCode {
        case 54:
            return 55 // right ⌘ -> left ⌘
        case 60:
            return 56 // right ⇧ -> left ⇧
        case 61:
            return 58 // right ⌥ -> left ⌥
        case 62:
            return 59 // right ⌃ -> left ⌃
        case globeActionKeyCode:
            return globeKeyCode
        default:
            return keyCode
        }
    }

    /// Every hardware key code that should be treated as the same exempt key.
    static func equivalentKeyCodes(for keyCode: Int64) -> Set<Int64> {
        switch canonicalKeyCode(keyCode) {
        case 55:
            return [54, 55]
        case 56:
            return [56, 60]
        case 58:
            return [58, 61]
        case 59:
            return [59, 62]
        case globeKeyCode:
            return [globeKeyCode, globeActionKeyCode]
        default:
            return [keyCode]
        }
    }

    static func modifierLabel(forKeyCode keyCode: Int64) -> String? {
        switch canonicalKeyCode(keyCode) {
        case 55:
            return "⌘"
        case 56:
            return "⇧"
        case 58:
            return "⌥"
        case 59:
            return "⌃"
        case 57:
            return "⇪"
        case globeKeyCode:
            return globeLabel
        default:
            return nil
        }
    }

    static func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch canonicalKeyCode(keyCode) {
        case 55:
            return flags.contains(.maskCommand)
        case 56:
            return flags.contains(.maskShift)
        case 58:
            return flags.contains(.maskAlternate)
        case 59:
            return flags.contains(.maskControl)
        case globeKeyCode:
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    /// Modifier key codes represented by a set of event flags. Used when
    /// migrating the old single-shortcut preference.
    static func modifierKeyCodes(for flags: CGEventFlags) -> Set<Int64> {
        var keyCodes: Set<Int64> = []

        if flags.contains(.maskCommand) {
            keyCodes.insert(55)
        }

        if flags.contains(.maskShift) {
            keyCodes.insert(56)
        }

        if flags.contains(.maskAlternate) {
            keyCodes.insert(58)
        }

        if flags.contains(.maskControl) {
            keyCodes.insert(59)
        }

        if flags.contains(.maskSecondaryFn) {
            keyCodes.insert(globeKeyCode)
        }

        return keyCodes
    }

    static func keyLabel(forKeyCode keyCode: Int64, characters: String?) -> String {
        if let modifierLabel = modifierLabel(forKeyCode: keyCode) {
            return modifierLabel
        }

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
