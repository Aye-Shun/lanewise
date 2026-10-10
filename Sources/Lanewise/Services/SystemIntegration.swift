import AppKit
import ServiceManagement
import UserNotifications

/// macOS notifications. Only available when running as an app bundle (not `swift run`).
@MainActor
enum Notifier {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, sound: Bool = false) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

/// "Open at login", through the system's login items.
@MainActor
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }
    static var isEnabled: Bool { isAvailable && SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { isAvailable && SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ on: Bool) throws {
        guard isAvailable else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// Turns "open at login" on once, the first time Lanewise runs; after that the
    /// Settings switch is the only thing that changes it.
    static func enableByDefaultOnce() {
        let key = "loginItemDefaulted"
        guard isAvailable, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? setEnabled(true)
    }
}

/// Carries settings over from the app's old bundle id (it was called Recall before 1.1) so an
/// upgrade keeps them. Runs once at launch, before anything reads UserDefaults.
enum SettingsMigration {
    static func runOnce() {
        let doneKey = "migratedFromRecall"
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, !defaults.bool(forKey: doneKey) else { return }
        let current = defaults.persistentDomain(forName: id) ?? [:]
        let oldFrame = "NSWindow Frame Recall.overlay."
        // AppSettings writes these defaults on any run (including --demo), so they don't count as the user's.
        let seeded: Set<String> = ["panels", "settingsVersion"]
        // "loginItemDefaulted" stays behind so open-at-login is turned on once for the new app.
        for (key, value) in defaults.persistentDomain(forName: "local.recall.app") ?? [:] where key != "loginItemDefaulted" {
            let name = key.hasPrefix(oldFrame) ? "NSWindow Frame Lanewise.overlay.\(key.dropFirst(oldFrame.count))" : key
            if current[name] == nil || seeded.contains(name) { defaults.set(value, forKey: name) }
        }
        defaults.set(true, forKey: doneKey)
    }
}
