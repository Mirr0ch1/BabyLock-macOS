import CoreGraphics
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case unlockTest
    case completed

    var id: Int { rawValue }

    /// The permissions step carries two compact permission rows and the
    /// repair button; it needs less room than the centered welcome and
    /// unlock-test steps. Sizing the window per step avoids the large empty
    /// area that a single fixed height left under the permission controls.
    var preferredContentHeight: CGFloat {
        switch self {
        case .permissions:
            return 480
        case .welcome, .unlockTest, .completed:
            return 500
        }
    }
}
