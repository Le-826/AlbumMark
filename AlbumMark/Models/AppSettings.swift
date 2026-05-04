import Foundation
import Combine
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    @Published var hideCompletedThreshold: Double {
        didSet {
            hideCompletedThreshold = min(max(hideCompletedThreshold, 0.5), 1.0)
            defaults.set(hideCompletedThreshold, forKey: Keys.hideCompletedThreshold)
        }
    }

    @Published var saveInterval: TimeInterval {
        didSet {
            saveInterval = min(max(saveInterval, 5), 60)
            defaults.set(saveInterval, forKey: Keys.saveInterval)
        }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published var settingsMessage: String?

    private let defaults: UserDefaults

    private enum Keys {
        static let hideCompletedThreshold = "hideCompletedThreshold"
        static let saveInterval = "saveInterval"
    }

    init(defaults: UserDefaults = .standard, readsLaunchAtLoginStatus: Bool = true) {
        self.defaults = defaults

        let storedThreshold = defaults.object(forKey: Keys.hideCompletedThreshold) as? Double
        hideCompletedThreshold = storedThreshold ?? 0.95

        let storedInterval = defaults.object(forKey: Keys.saveInterval) as? Double
        saveInterval = storedInterval ?? 15

        launchAtLogin = readsLaunchAtLoginStatus ? SMAppService.mainApp.status == .enabled : false
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsMessage = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsMessage = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }
}
