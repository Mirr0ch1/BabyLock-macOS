import Foundation

enum AutoUnlockDuration: String, CaseIterable, Identifiable {
    case fiveMinutes
    case tenMinutes
    case twentyMinutes

    var id: String { rawValue }

    var title: String {
        title(language: .current)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .fiveMinutes:
            return AppStrings.text(.durationFiveMinutes, language: language)
        case .tenMinutes:
            return AppStrings.text(.durationTenMinutes, language: language)
        case .twentyMinutes:
            return AppStrings.text(.durationTwentyMinutes, language: language)
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .fiveMinutes:
            return 5 * 60
        case .tenMinutes:
            return 10 * 60
        case .twentyMinutes:
            return 20 * 60
        }
    }
}
