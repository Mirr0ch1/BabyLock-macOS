import Foundation

enum BlackoutScope: String, CaseIterable, Identifiable {
    case allDisplays
    case mainDisplay

    var id: String { rawValue }

    var title: String {
        title(language: .current)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .allDisplays:
            return AppStrings.text(.scopeAllDisplays, language: language)
        case .mainDisplay:
            return AppStrings.text(.scopeMainDisplay, language: language)
        }
    }
}
