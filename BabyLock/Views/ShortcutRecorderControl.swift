import AppKit
import SwiftUI

/// Records one key press and returns it as an exempt key.
///
/// A local monitor is enough here: the settings window is the active window
/// while recording, and it keeps the recording UI independent of the app's
/// normal responder chain.
final class ExemptKeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var onRecord: ((ExemptKey) -> Void)?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func toggle(onRecord: @escaping (ExemptKey) -> Void) {
        if isRecording {
            cancel()
        } else {
            start(onRecord: onRecord)
        }
    }

    func start(onRecord: @escaping (ExemptKey) -> Void) {
        guard !isRecording else { return }

        self.onRecord = onRecord
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        onRecord = nil
        isRecording = false
    }

    private func finish(_ key: ExemptKey) {
        let callback = onRecord
        cancel()
        callback?(key)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        if event.type == .flagsChanged {
            let keyCode = Int64(event.keyCode)

            // Caps Lock toggles instead of reporting a pressed state, so any
            // flagsChanged event for it is a deliberate press.
            if keyCode == 57 {
                finish(ExemptKey(keyCode: keyCode, label: "⇪"))
                return nil
            }

            guard let label = ExemptKey.modifierLabel(forKeyCode: keyCode) else {
                return event
            }

            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            guard ExemptKey.isModifierPressed(keyCode: keyCode, flags: flags) else {
                return event
            }

            finish(ExemptKey(
                keyCode: ExemptKey.canonicalKeyCode(keyCode),
                label: label
            ))
            return nil
        }

        guard event.type == .keyDown, !event.isARepeat else { return nil }

        // Escape cancels instead of being recorded, so the user always has a
        // way out without touching the mouse.
        if event.keyCode == 53 {
            cancel()
            return nil
        }

        // Some keyboards deliver the Globe key as a key press instead of a
        // flagsChanged event, and macOS may only deliver the synthetic
        // keycode 179 action event. Normalize all of them.
        if event.keyCode == Int(ExemptKey.globeKeyCode)
            || event.keyCode == Int(ExemptKey.globeActionKeyCode) {
            finish(.globe)
            return nil
        }

        finish(ExemptKey(
            keyCode: ExemptKey.canonicalKeyCode(Int64(event.keyCode)),
            label: ExemptKey.keyLabel(
                forKeyCode: Int64(event.keyCode),
                characters: event.charactersIgnoringModifiers
            )
        ))

        return nil
    }
}

@MainActor
struct ExemptionKeysControl: View {
    @Binding var keys: [ExemptKey]
    var isLocked: Bool = false

    @StateObject private var recorder = ExemptKeyRecorder()
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if keys.isEmpty {
                Text(text(.settingsExemptionNone))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ExemptionFlowLayout(spacing: 6) {
                    ForEach(keys) { key in
                        ExemptionKeyChip(key: key) {
                            remove(key)
                        }
                    }
                }
                .frame(width: 236, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Button {
                    recorder.toggle { recorded in
                        add(recorded)
                    }
                } label: {
                    Text(recorder.isRecording ? text(.settingsExemptionRecording) : text(.settingsExemptionAddKey))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(recorder.isRecording ? Color.orange : Color.accentColor)

                // A direct preset is needed because some input methods and
                // dictation tools consume the Globe key before an in-app key
                // monitor sees it.
                Button {
                    recorder.cancel()
                    add(.globe)
                } label: {
                    Text(text(.settingsExemptionBindFn))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(width: 236, alignment: .trailing)
        .disabled(isLocked)
        .onChange(of: isLocked) { locked in
            if locked {
                recorder.cancel()
            }
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private func add(_ key: ExemptKey) {
        let normalized = ExemptKey(
            keyCode: ExemptKey.canonicalKeyCode(key.keyCode),
            label: key.label
        )

        guard !keys.contains(where: { $0.keyCode == normalized.keyCode }) else {
            NSSound.beep()
            return
        }

        keys.append(normalized)
    }

    private func remove(_ key: ExemptKey) {
        keys.removeAll { $0.keyCode == key.keyCode }
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: preferences.appLanguage)
    }
}

private struct ExemptionKeyChip: View {
    let key: ExemptKey
    let onRemove: () -> Void

    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        HStack(spacing: 3) {
            Text(key.displayText)
                .font(.callout)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text(text(.settingsExemptionClear)))
            .accessibilityLabel(Text(text(.settingsExemptionClear)))
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: preferences.appLanguage)
    }
}

/// A small wrapping layout for the exempt-key chips. SwiftUI's built-in
/// stacks can only lay out in one line, and a horizontal scroll view would
/// hide keys the user added.
private struct ExemptionFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widestRow = max(widestRow, x - spacing)
        }

        return CGSize(
            width: proposal.width ?? widestRow,
            height: subviews.isEmpty ? 0 : y + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
