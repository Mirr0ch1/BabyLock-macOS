import AppKit
import SwiftUI

/// Compact, always-on-top hint used when the screen is not blacked out.
/// It floats above the desktop without covering the screen or stealing focus.
@MainActor
struct LockHUDView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject private var preferences = PreferencesStore.shared

    private var bothCommandsPressed: Bool {
        state.commandKeyState.isLeftCommandPressed && state.commandKeyState.isRightCommandPressed
    }

    private var visibleProgress: Double {
        state.isUnlockCompleted || bothCommandsPressed
            ? state.commandKeyState.progress
            : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            AnimatedLockIcon(state: state.lockIconState)
                .scaleEffect(0.82)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(text(.overlayTitle))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))

                    Spacer(minLength: 8)

                    if let remainingSeconds = state.autoUnlockRemainingSeconds {
                        Text("\(text(.overlayAutoUnlockPrefix)) \(formattedTime(remainingSeconds))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                }

                Text(text(blockedStatusKey))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.62))

                HStack(spacing: 10) {
                    Text(text(.overlayExitInstruction))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.56))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 6)

                    UnlockProgressIndicator(
                        progress: visibleProgress,
                        isCompleted: state.isUnlockCompleted
                    )
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(HUDChrome())
        .padding(20)
        .frame(width: 600)
        .opacity(state.showsContent ? 1 : 0)
        .offset(y: state.contentYOffset)
        .accessibilityElement(children: .combine)
    }

    private var blockedStatusKey: AppStrings.Key {
        preferences.blockPointerInput ? .overlayKeyboardAndPointerBlocked : .overlayKeyboardBlocked
    }

    private func formattedTime(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    private func text(_ key: AppStrings.Key) -> String {
        AppStrings.text(key, language: preferences.appLanguage)
    }
}

private struct HUDChrome: View {
    var body: some View {
        ZStack {
            HUDMaterialView()
            Color.black.opacity(0.46)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.32), radius: 18, x: 0, y: 8)
    }
}

private struct HUDMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}
