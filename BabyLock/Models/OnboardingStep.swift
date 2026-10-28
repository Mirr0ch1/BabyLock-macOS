import CoreGraphics
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case unlockTest
    case completed

    var id: Int { rawValue }

    /// Used as the initial window height before the permissions step reports
    /// its measured height. The measured height replaces it immediately.
    var preferredContentHeight: CGFloat {
        switch self {
        case .permissions:
            return 400
        case .welcome, .unlockTest, .completed:
            return 500
        }
    }
}
