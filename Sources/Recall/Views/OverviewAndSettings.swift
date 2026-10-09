import AppKit
import SwiftUI

struct OverviewView: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                statusRows
                Toggle("Overlay", isOn: $settings.overlayEnabled)
            } header: {
                header
            } footer: {
                Text("Recall reads only the League client's local APIs. It never injects code or reads game memory.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section("Shortcuts") {
                LabeledContent("Show gold and items") {
                    HStack(spacing: 6) {
                        Keycap(key: "⇥ Tab")
                        Text("hold").font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                if settings.showOnShopKey {
                    LabeledContent("Toggle Next Item") { Keycap(key: settings.shopKeyName) }
                }
                LabeledContent("Time an enemy spell") { Text("Click its icon").foregroundStyle(Palette.secondaryLabel) }
                LabeledContent("Hide a tile until the next game") { Keycap(key: "×") }
                LabeledContent("Overlay on or off") { KeycapRow(keys: ["⌃", "⇧", "O"]) }
                LabeledContent("Arrange panels") { KeycapRow(keys: ["⌃", "⇧", "M"]) }
            }

            Section("Preview without a game") {
                HStack {
                    Text("Explore every screen with sample players and real build data.")
                        .foregroundStyle(Palette.secondaryLabel)
                    Spacer()
                    Button("Draft Preview") {
                        monitor.enterDemo(.champSelect)
                        Navigation.shared.selection = .draft
                    }
                    Button("In-Game Preview") {
                        monitor.enterDemo(.inGame)
                        Navigation.shared.selection = .players
                    }
                }
                .controlSize(.small)
            }

            Section {
                HStack(spacing: 16) {
                    SettingsLink { Text("Overlay Settings…") }
                    Button("Release Notes") { openWindow(id: "release-notes") }
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        let (symbol, color, headline): (String, Color, String) = switch monitor.status {
        case .connected: ("checkmark", Palette.positive, "Connected to League")
        case .searching: ("circle.dotted", Palette.secondaryLabel, "Waiting for League")
        case .demo: ("play.fill", Color.accentColor, "Previewing Sample Data")
        }
        let detail: String = switch monitor.status {
        case .connected: [monitor.me?.riotID, monitor.phase.label].compactMap { $0 }.joined(separator: " · ")
        case .searching: "Open League of Legends and sign in."
        case .demo: "Sample players · \(monitor.phase.label)"
        }
        return HStack(spacing: 12) {
            Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                .overlay(Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.label)
                Text(detail).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .textCase(nil)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var statusRows: some View {
        LabeledContent("League client") {
            switch monitor.status {
            case .connected: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.positive)
            case .searching: Label("Not running", systemImage: "circle.dotted").foregroundStyle(Palette.secondaryLabel)
            case .demo: Label("Preview", systemImage: "play.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        LabeledContent("Match", value: monitor.phase.label)
    }
}

// MARK: - Settings window

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            OverlaySettings().tabItem { Label("Overlay", systemImage: "rectangle.3.group") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Open Recall when you log in", isOn: Binding(
                    get: { opensAtLogin },
                    set: { on in
                        do {
                            try LoginItem.setEnabled(on)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        opensAtLogin = LoginItem.isEnabled
                    }
                ))
                .disabled(!LoginItem.isAvailable)
                Toggle("Show Draft when champ select starts", isOn: $settings.autoSwitchToLive)
            } header: {
                Text("Startup")
            } footer: {
                Text(loginFooter).foregroundStyle(Palette.secondaryLabel)
            }

            Section {
                Toggle("Import runes", isOn: $settings.autoImportRunes)
                Toggle("Import the item build into the shop", isOn: $settings.importItemSets)
                Toggle("Set summoner spells", isOn: $settings.importSpells)
                if settings.importSpells {
                    Picker("Keep Flash on", selection: $settings.flashOnF) {
                        Text("D").tag(false)
                        Text("F").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("When you lock in a champion")
            } footer: {
                Text("Recall uses the common setup for your champion and role. It only creates or replaces its own \"Recall: <champion>\" rune page and item set; your other pages and sets are never changed. In ARAM it follows rerolls and swaps.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section {
                Toggle("Accept matches automatically", isOn: $settings.autoAccept)
                Toggle("Notify me when a match is found", isOn: Binding(
                    get: { settings.notifyMatchFound },
                    set: { on in
                        settings.notifyMatchFound = on
                        if on { Notifier.requestAuthorization() }
                    }
                ))
            } header: {
                Text("Queue")
            } footer: {
                Text("Recall waits 2 seconds before accepting, so you can still decline, and never accepts after you've answered. Notifications only appear when League isn't the app in front.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section {
                Toggle("Notify me with a summary after each game", isOn: Binding(
                    get: { settings.notifyPostGame },
                    set: { on in
                        settings.notifyPostGame = on
                        if on { Notifier.requestAuthorization() }
                    }
                ))
            } header: {
                Text("After a game")
            } footer: {
                Text("Your LP change, and how your KDA, CS and damage compared to your recent average. The same summary appears at the top of Match History.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section("Text size") {
                HStack {
                    Slider(value: $settings.textScale, in: 0.8...1.5, step: 0.1)
                    Text("\(Int((settings.textScale * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { opensAtLogin = LoginItem.isEnabled }
    }

    private var loginFooter: String {
        if let loginError { return "Couldn't change the login item: \(loginError)" }
        if !LoginItem.isAvailable { return "Available when Recall runs as an app (scripts/build-app.sh)." }
        if LoginItem.needsApproval { return "Allow Recall in System Settings → General → Login Items." }
        return "Recall starts quietly in the menu bar, so the overlay is ready when you play. Closing its window keeps it running."
    }
}

struct OverlaySettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OverlayManager.self) private var overlay
    @State private var recordingKey = false
    @State private var keyMonitor: Any?
    @State private var hasInputMonitoring = KeyState.hasInputMonitoring

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.overlayEnabled) {
                    HStack {
                        Text("Show overlay in game")
                        Spacer()
                        KeycapRow(keys: ["⌃", "⇧", "O"])
                    }
                }
            } footer: {
                Text("The × on a tile hides it until the next game. The switches below turn things off for good.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section {
                ForEach(OverlayPanelKind.hudModules) { panel in moduleToggle(panel) }
            } header: {
                Text("In-game HUD")
            } footer: {
                Text("A narrow column on the left edge of the screen. Gold Diff and Next Item sit in a second tile underneath.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section("Loading screen") {
                moduleToggle(.scout)
            }

            Section {
                LabeledContent("Gold Diff and Next Item", value: "While Tab is held")
                Toggle("Toggle Next Item with shop key", isOn: Binding(
                    get: { settings.showOnShopKey },
                    set: { on in
                        settings.showOnShopKey = on
                        if on && !KeyState.hasInputMonitoring { KeyState.requestInputMonitoring() }
                        hasInputMonitoring = KeyState.hasInputMonitoring
                    }
                ))
                if settings.showOnShopKey {
                    LabeledContent("Shop key") {
                        Button {
                            recordKey()
                        } label: {
                            if recordingKey { Text("Press a key…") } else { Keycap(key: settings.shopKeyName) }
                        }
                    }
                    HStack {
                        if hasInputMonitoring {
                            Label("Input Monitoring allowed", systemImage: "checkmark.shield.fill").foregroundStyle(Palette.positive)
                        } else {
                            Label("Input Monitoring needed", systemImage: "exclamationmark.shield.fill").foregroundStyle(Palette.caution)
                            Spacer()
                            Button("Open Privacy Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                            }
                        }
                    }
                }
                Toggle("Keep everything on screen", isOn: $settings.showAlways)
                Toggle("Hide when League isn't in front", isOn: $settings.onlyOverGame)
            } header: {
                Text("When tiles appear")
            } footer: {
                Text("Spell Timers and CS/min stay visible during Summoner's Rift games.")
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Section {
                percentSlider("Opacity", value: $settings.overlayOpacity)
                Picker("Timer format", selection: $settings.cooldownFormat) {
                    ForEach(CooldownFormat.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Button(overlay.isMoveMode ? "Done Arranging" : "Arrange Tiles…") { overlay.isMoveMode.toggle() }
                    Button("Reset Positions") { overlay.resetPositions() }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Positions are remembered separately for Summoner's Rift, ARAM and Arena. For the most reliable overlay, set League to Borderless.")
                    .foregroundStyle(Palette.secondaryLabel)
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func moduleToggle(_ panel: OverlayPanelKind) -> some View {
        @Bindable var settings = settings
        return Toggle(isOn: Binding(get: { settings.isEnabled(panel) }, set: { settings.setEnabled(panel, $0) })) {
            HStack(spacing: 10) {
                PanelTile(kind: panel)
                VStack(alignment: .leading, spacing: 1) {
                    Text(panel.title)
                    Text(panel.summary).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                }
            }
        }
    }

    private func percentSlider(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: 0.4...1)
                Text("\(Int((value.wrappedValue * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            .frame(width: 240)
        }
    }

    private func recordKey() {
        stopRecording()
        recordingKey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            settings.shopKeyCode = Int(event.keyCode)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingKey = false
    }
}

struct PrivacySettings: View {
    private let rows: [(String, String, String)] = [
        ("desktopcomputer", "Player data", "Read from your League client on this Mac. Your client credentials never leave it."),
        ("globe", "Builds and opponents", "From OP.GG's public API. Only champion names, roles and the game mode are sent."),
        ("photo.on.rectangle", "Icons and game data", "From Riot's Data Dragon, plus a few rune icons from CommunityDragon."),
        ("square.and.pencil", "Changes to your client", "Only Recall's own rune page, when you lock in (if rune import is on) or click Apply. No accounts, no tracking."),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.1) { symbol, title, detail in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Palette.secondaryLabel).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ReleaseNotesView: View {
    private let releases: [(String, [String])] = [
        ("1.0", [
            "Match History: your recent games with builds and stats, filters, and full game details",
            "Draft: rune page with keystone details; imported automatically when you lock in, or applied with one click",
            "Draft: common build, spells, skill order, ban suggestions, enemy spells by likely role, duo synergy",
            "Players: rank, LP, season and recent win rates, champion stats, mastery, streak and smurf notes, premade detection",
            "In game: one HUD tile with live Spell Timers, CS per minute, Gold Diff and Next Item, plus Lanes at the loading screen",
            "Tiles your way: gold and items while Tab is held or always, × to hide until the next game, per-mode positions, text size and opacity",
        ]),
    ]

    var body: some View {
        Form {
            ForEach(releases, id: \.0) { version, notes in
                Section("Recall \(version)") {
                    ForEach(notes, id: \.self) { Text($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 400)
    }
}
