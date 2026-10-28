import Foundation

/// Languages shipped with Baby Lock. The app follows the system language by
/// default and falls back to English for any language it does not support.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case french = "fr"
    case russian = "ru"

    var id: String { rawValue }

    /// The language name written in that language, which is what language
    /// pickers normally show.
    var nativeName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .french:
            return "Français"
        case .russian:
            return "Русский"
        }
    }

    /// Resolves the first preferred system language that Baby Lock supports.
    static var systemDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            if let language = match(identifier) {
                return language
            }
        }

        return .english
    }

    private static func match(_ identifier: String) -> AppLanguage? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let components = normalized.split(separator: "-").map(String.init)

        guard let code = components.first else { return nil }

        switch code {
        case "en":
            return .english
        case "fr":
            return .french
        case "ru":
            return .russian
        case "zh":
            let usesTraditionalScript = components.dropFirst().contains { component in
                component == "hant" || component == "tw" || component == "hk" || component == "mo"
            }
            return usesTraditionalScript ? .traditionalChinese : .simplifiedChinese
        default:
            return nil
        }
    }
}

/// Persisted language choice. `.system` keeps following the macOS language,
/// while `.language` pins one of the supported languages.
enum LanguagePreference: Hashable {
    case system
    case language(AppLanguage)

    var rawValue: String {
        switch self {
        case .system:
            return "system"
        case .language(let language):
            return language.rawValue
        }
    }

    init(rawValue: String) {
        if rawValue == "system" {
            self = .system
            return
        }

        if let language = AppLanguage(rawValue: rawValue) {
            self = .language(language)
            return
        }

        self = .system
    }

    var resolvedLanguage: AppLanguage {
        switch self {
        case .system:
            return .systemDefault
        case .language(let language):
            return language
        }
    }
}

/// Typed access to `Localizable.strings`. Every user-facing string lives in a
/// standard `.lproj` bundle so translators can work without touching Swift.
enum AppStrings {
    enum Key: String {
        // Menu bar
        case menuLockEnabled = "menu.lockEnabled"
        case menuStartLock = "menu.startLock"
        case menuSettings = "menu.settings"
        case menuCheckForUpdates = "menu.checkForUpdates"
        case menuCheckingForUpdates = "menu.checkingForUpdates"
        case menuUpToDate = "menu.upToDate"
        case menuUpdateAvailable = "menu.updateAvailable"
        case menuDownloadingUpdate = "menu.downloadingUpdate"
        case menuInstallingUpdate = "menu.installingUpdate"
        case menuUpdateFailed = "menu.updateFailed"
        case menuQuit = "menu.quit"

        // Settings
        case settingsTitle = "settings.title"
        case settingsWindowTitle = "settings.windowTitle"
        case settingsLaunchAtLogin = "settings.launchAtLogin"
        case settingsLanguage = "settings.language"
        case settingsLanguageSystem = "settings.languageSystem"
        case settingsAutoUnlock = "settings.autoUnlock"
        case settingsAutoUnlockSubtitle = "settings.autoUnlockSubtitle"
        case settingsBlackout = "settings.blackout"
        case settingsBlackoutSubtitle = "settings.blackoutSubtitle"
        case settingsBlackoutScope = "settings.blackoutScope"
        case settingsBlackoutScopeSubtitle = "settings.blackoutScopeSubtitle"
        case settingsPointer = "settings.pointer"
        case settingsPointerSubtitle = "settings.pointerSubtitle"
        case settingsExemption = "settings.exemption"
        case settingsExemptionSubtitle = "settings.exemptionSubtitle"
        case settingsExemptionNone = "settings.exemptionNone"
        case settingsExemptionRecording = "settings.exemptionRecording"
        case settingsExemptionClear = "settings.exemptionClear"
        case settingsExemptionLockedHint = "settings.exemptionLockedHint"
        case settingsExemptionBindFn = "settings.exemptionBindFn"

        // Durations
        case durationFiveMinutes = "duration.fiveMinutes"
        case durationTenMinutes = "duration.tenMinutes"
        case durationTwentyMinutes = "duration.twentyMinutes"

        // Display scope
        case scopeAllDisplays = "scope.allDisplays"
        case scopeMainDisplay = "scope.mainDisplay"

        // Permission status
        case permissionNotGranted = "permission.status.notGranted"
        case permissionGranted = "permission.status.granted"
        case permissionRequiresRestart = "permission.status.requiresRestart"
        case permissionRequiresManualCheck = "permission.status.requiresManualCheck"

        // Permission issues
        case permissionIssueAccessibility = "permission.issue.accessibility"
        case permissionIssueInputMonitoring = "permission.issue.inputMonitoring"
        case permissionIssueGeneric = "permission.issue.generic"

        // Onboarding
        case onboardingWelcomeSubtitle = "onboarding.welcomeSubtitle"
        case onboardingWelcomeBody = "onboarding.welcomeBody"
        case onboardingContinue = "onboarding.continue"
        case onboardingPermissionsTitle = "onboarding.permissionsTitle"
        case onboardingPermissionsDescription = "onboarding.permissionsDescription"
        case onboardingAccessibilityTitle = "onboarding.accessibilityTitle"
        case onboardingAccessibilityDescription = "onboarding.accessibilityDescription"
        case onboardingInputMonitoringTitle = "onboarding.inputMonitoringTitle"
        case onboardingInputMonitoringDescription = "onboarding.inputMonitoringDescription"
        case onboardingPrivacyNote = "onboarding.privacyNote"
        case onboardingPermissionRepair = "onboarding.permissionRepair"
        case onboardingPermissionRepairHint = "onboarding.permissionRepairHint"
        case onboardingPermissionLocationWarning = "onboarding.permissionLocationWarning"
        case onboardingBack = "onboarding.back"
        case onboardingUnlockTestTitle = "onboarding.unlockTestTitle"
        case onboardingUnlockTestDescription = "onboarding.unlockTestDescription"
        case onboardingLeftCommand = "onboarding.leftCommand"
        case onboardingRightCommand = "onboarding.rightCommand"
        case onboardingUnlockTestFootnote = "onboarding.unlockTestFootnote"
        case onboardingCompletedTitle = "onboarding.completedTitle"
        case onboardingCompletedDescription = "onboarding.completedDescription"
        case onboardingDone = "onboarding.done"
        case onboardingOpen = "onboarding.open"

        // Overlay / HUD
        case overlayTitle = "overlay.title"
        case overlayKeyboardBlocked = "overlay.keyboardBlocked"
        case overlayKeyboardAndPointerBlocked = "overlay.keyboardAndPointerBlocked"
        case overlayExitInstruction = "overlay.exitInstruction"
        case overlayAutoUnlockPrefix = "overlay.autoUnlockPrefix"
        case overlayNoScreens = "overlay.noScreens"

        // Errors
        case errorInputBlockerFailed = "error.inputBlockerFailed"
        case errorEventTapStopped = "error.eventTapStopped"
        case errorLockNotStarted = "error.lockNotStarted"
        case errorLockDisabled = "error.lockDisabled"
        case errorDisplayConfigurationChanged = "error.displayConfigurationChanged"

        // Alerts
        case alertOK = "alert.ok"
        case alertCancel = "alert.cancel"

        // Updates
        case updateConfirmTitle = "update.confirmTitle"
        case updateConfirmMessage = "update.confirmMessage"
        case updateInstallNow = "update.installNow"
        case updateFailedTitle = "update.failedTitle"
        case updateCheckFailedTitle = "update.checkFailedTitle"
        case updateErrorNetwork = "update.errorNetwork"
        case updateErrorMissingAsset = "update.errorMissingAsset"
        case updateErrorInvalidArchive = "update.errorInvalidArchive"
        case updateErrorVerification = "update.errorVerification"
        case updateErrorSignature = "update.errorSignature"
        case updateErrorNotInApplications = "update.errorNotInApplications"
        case updateErrorNotWritable = "update.errorNotWritable"
        case updateErrorLocked = "update.errorLocked"
        case updateErrorProcess = "update.errorProcess"
    }

    static func text(_ key: Key, language: AppLanguage = .current) -> String {
        let requestedBundle = bundle(for: language)
        let value = requestedBundle.localizedString(forKey: key.rawValue, value: nil, table: "Localizable")

        guard value == key.rawValue else {
            return value
        }

        // Missing translations fall back to English instead of showing a key.
        let englishBundle = bundle(for: .english)
        return englishBundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: "Localizable")
    }

    private static let bundleLock = NSLock()
    private static var cachedBundles: [AppLanguage: Bundle] = [:]

    private static func bundle(for language: AppLanguage) -> Bundle {
        bundleLock.lock()
        defer { bundleLock.unlock() }

        if let cached = cachedBundles[language] {
            return cached
        }

        let resolvedBundle: Bundle
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            resolvedBundle = languageBundle
        } else {
            resolvedBundle = .main
        }

        cachedBundles[language] = resolvedBundle
        return resolvedBundle
    }
}

extension AppLanguage {
    /// The language currently in effect, taking the saved preference into
    /// account. Used by models that do not observe `PreferencesStore`.
    static var current: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: PreferencesStore.Keys.languagePreference)
            ?? LanguagePreference.system.rawValue
        return LanguagePreference(rawValue: rawValue).resolvedLanguage
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}
