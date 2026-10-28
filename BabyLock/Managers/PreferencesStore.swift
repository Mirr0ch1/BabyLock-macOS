import Foundation
import ServiceManagement

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let autoUnlockDuration = "autoUnlockDuration"
        static let blackoutEnabled = "blackoutEnabled"
        static let blackoutScope = "blackoutScope"
        static let blockPointerInput = "blockPointerInput"
        static let languagePreference = "languagePreference"
        static let hasAppliedDefaultLaunchAtLoginPreference = "hasAppliedDefaultLaunchAtLoginPreference"
        static let hasUserChangedLaunchAtLogin = "hasUserChangedLaunchAtLogin"
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var autoUnlockDuration: AutoUnlockDuration {
        didSet {
            defaults.set(autoUnlockDuration.rawValue, forKey: Keys.autoUnlockDuration)
        }
    }

    /// Off by default: Baby Lock normally leaves the desktop visible and only
    /// blocks input.
    @Published var blackoutEnabled: Bool {
        didSet {
            defaults.set(blackoutEnabled, forKey: Keys.blackoutEnabled)
        }
    }

    @Published var blackoutScope: BlackoutScope {
        didSet {
            defaults.set(blackoutScope.rawValue, forKey: Keys.blackoutScope)
        }
    }

    /// On by default: a child can hit the trackpad just as easily as the
    /// keyboard.
    @Published var blockPointerInput: Bool {
        didSet {
            defaults.set(blockPointerInput, forKey: Keys.blockPointerInput)
        }
    }

    @Published var languagePreference: LanguagePreference {
        didSet {
            defaults.set(languagePreference.rawValue, forKey: Keys.languagePreference)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
        }
    }

    var appLanguage: AppLanguage {
        languagePreference.resolvedLanguage
    }

    @Published private(set) var launchAtLoginEnabled: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        let durationRawValue = defaults.string(forKey: Keys.autoUnlockDuration)
        self.autoUnlockDuration = durationRawValue
            .flatMap(AutoUnlockDuration.init(rawValue:)) ?? .tenMinutes

        self.blackoutEnabled = defaults.object(forKey: Keys.blackoutEnabled) as? Bool ?? false

        let scopeRawValue = defaults.string(forKey: Keys.blackoutScope)
        self.blackoutScope = scopeRawValue
            .flatMap(BlackoutScope.init(rawValue:)) ?? .allDisplays

        self.blockPointerInput = defaults.object(forKey: Keys.blockPointerInput) as? Bool ?? true

        var storedLanguage = defaults.string(forKey: Keys.languagePreference)
        if storedLanguage == nil {
            // Migrate the previous appLanguage key if it exists.
            storedLanguage = defaults.string(forKey: "appLanguage")
        }
        self.languagePreference = LanguagePreference(rawValue: storedLanguage ?? LanguagePreference.system.rawValue)

        Self.disableLaunchAtLoginByDefaultIfNeeded(defaults: defaults)
        self.launchAtLoginEnabled = Self.isLaunchAtLoginEnabled
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = Self.isLaunchAtLoginEnabled
    }

    /// Called when the system language may have changed while the app follows
    /// the system. Forces SwiftUI views to re-read `appLanguage`.
    func notifyLanguageMayHaveChanged() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        defaults.set(true, forKey: Keys.hasUserChangedLaunchAtLogin)
        guard isEnabled != launchAtLoginEnabled else { return }

        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to update launch at login: \(error.localizedDescription)")
        }

        refreshLaunchAtLoginStatus()
    }

    private static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private static func disableLaunchAtLoginByDefaultIfNeeded(defaults: UserDefaults) {
        guard !defaults.bool(forKey: Keys.hasAppliedDefaultLaunchAtLoginPreference) else { return }
        defer {
            defaults.set(true, forKey: Keys.hasAppliedDefaultLaunchAtLoginPreference)
        }

        guard !defaults.bool(forKey: Keys.hasUserChangedLaunchAtLogin),
              isLaunchAtLoginEnabled else { return }

        do {
            try SMAppService.mainApp.unregister()
        } catch {
            NSLog("Failed to disable default launch at login: \(error.localizedDescription)")
        }
    }
}
