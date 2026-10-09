import AppKit
import SwiftUI

@main
enum Entry {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            SnapshotRunner.run(output: args[index + 1], arguments: args)
        } else {
            RecallApp.main()
        }
    }
}

struct RecallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Recall", id: "main") {
            RootView().withAppEnvironment()
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Go") {
                ForEach(SidebarItem.allCases) { item in
                    Button(item.title) { Navigation.shared.selection = item }
                        .keyboardShortcut(item.shortcut, modifiers: .command)
                }
            }
            CommandGroup(replacing: .help) {
                ReleaseNotesCommand()
            }
        }

        Window("Release Notes", id: "release-notes") {
            ReleaseNotesView()
        }
        .defaultSize(width: 520, height: 600)

        Settings {
            SettingsView().withAppEnvironment()
        }

        MenuBarExtra("Recall", systemImage: "binoculars") {
            MenuBarContent().withAppEnvironment()
        }
    }
}

private struct ReleaseNotesCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Recall Release Notes") { openWindow(id: "release-notes") }
    }
}

extension View {
    @MainActor
    func withAppEnvironment() -> some View {
        environment(GameMonitor.shared)
            .environment(AppSettings.shared)
            .environment(OverlayManager.shared)
            .environment(MetaStore.shared)
            .environment(Navigation.shared)
            .environment(MatchHistoryStore.shared)
            .environment(PlayerLookupStore.shared)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare binary (`swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        let monitor = GameMonitor.shared
        monitor.onPhaseChange = { phase in OverlayManager.shared.handlePhase(phase) }
        HotKeys.registerDefaults()
        LoginItem.enableByDefaultOnce()
        if AppSettings.shared.notifyMatchFound || AppSettings.shared.notifyPostGame {
            Notifier.requestAuthorization()
        }
        if CommandLine.arguments.contains("--demo") {
            Task { @MainActor in
                await DataDragon.shared.load()
                monitor.enterDemo()
            }
        } else {
            monitor.start()
        }
    }

    /// Closing the window keeps the app (and its overlay panels) running from the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuBarContent: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @Environment(OverlayManager.self) private var overlay
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings
        Text(monitor.statusText)
        Text(monitor.phase.label)
        Divider()
        Button("Open Recall") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Toggle("Overlay", isOn: $settings.overlayEnabled)
            .keyboardShortcut("o", modifiers: [.control, .shift])
        Button(overlay.isMoveMode ? "Done Arranging" : "Arrange Panels") { overlay.isMoveMode.toggle() }
            .keyboardShortcut("m", modifiers: [.control, .shift])
        Divider()
        Menu("Preview") {
            Button("Draft") { monitor.enterDemo(.champSelect) }
            Button("In Game") { monitor.enterDemo(.inGame) }
            if monitor.status == .demo {
                Button("End Preview") { monitor.exitDemo() }
            }
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Recall") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
