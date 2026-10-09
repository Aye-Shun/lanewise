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

    /// Turns "open at login" on once, the first time this version runs; after that the
    /// Settings switch is the only thing that changes it.
    static func enableByDefaultOnce() {
        let key = "loginItemDefaulted"
        guard isAvailable, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? setEnabled(true)
    }
}
