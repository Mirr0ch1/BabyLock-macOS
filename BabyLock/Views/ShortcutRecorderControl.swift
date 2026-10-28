import AppKit
import SwiftUI

/// Records the next key press and stores it as an input exemption.
///
/// A local monitor is enough here: the settings window is the active window
/// while recording, and it keeps the recording UI independent of the app's
/// normal responder chain.
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var onRecord: ((InputExemption) -> Void)?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func toggle(onRecord: @escaping (InputExemption) -> Void) {
        if isRecording {
            cancel()
        } else {
            start(onRecord: onRecord)
        }
    }

    func start(onRecord: @escaping (InputExemption) -> Void) {
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

    private func finish(_ exemption: InputExemption) {
        let callback = onRecord
        cancel()
        callback?(exemption)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        if event.type == .flagsChanged {
            // fn / Globe only produces flagsChanged events, so a lone press is
            // the only way to record it.
            if event.keyCode == Int(InputExemption.globeKeyCode),
               event.modifierFlags.contains(.function) {
                finish(InputExemption(
                    kind: .modifier,
                    keyCode: InputExemption.globeKeyCode,
                    modifiers: 0,
                    label: InputExemption.globeLabel
                ))
                return nil
            }

            return event
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
        if event.keyCode == Int(InputExemption.globeKeyCode)
            || event.keyCode == Int(InputExemption.globeActionKeyCode) {
            finish(InputExemption(
                kind: .modifier,
                keyCode: InputExemption.globeKeyCode,
                modifiers: 0,
                label: InputExemption.globeLabel
            ))
            return nil
        }

        let modifiers = event.modifierFlags.intersection([
            .shift,
            .control,
            .option,
            .command,
            .function
        ])

        finish(InputExemption(
            kind: .key,
            keyCode: Int64(event.keyCode),
            modifiers: UInt64(modifiers.rawValue),
            label: InputExemption.keyLabel(
                forKeyCode: Int64(event.keyCode),
                characters: event.charactersIgnoringModifiers
            )
        ))

        return nil
    }
}

@MainActor
struct ShortcutRecorderControl: View {
    @Binding var exemption: InputExemption?
    var isLocked: Bool = false

    @StateObject private var recorder = ShortcutRecorder()
    @ObservedObject private var preferences = PreferencesStore.shared

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recorder.toggle { recorded in
                    exemption = recorded
                }
            } label: {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 64)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(recorder.isRecording ? Color.orange : Color.accentColor)

            if exemption != nil && !recorder.isRecording {
                Button {
                    exemption = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text(text(.settingsExemptionClear)))
                .accessibilityLabel(Text(text(.settingsExemptionClear)))
            }
        }
        .frame(width: 176, alignment: .trailing)
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

    private var title: String {
        if recorder.isRecording {
            return text(.settingsExemptionRecording)
        }

        return exemption?.displayText ?? text(.settingsExemptionNone)
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: preferences.appLanguage)
    }
}
