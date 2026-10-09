import Carbon.HIToolbox
import Foundation
import Observation

/// What the overlay can show. Lanes is its own window (loading-screen scouting); the rest are
/// modules stacked together in one HUD window.
enum OverlayPanelKind: String, CaseIterable, Identifiable {
    case scout, cooldowns, gold, build, farm

    var id: String { rawValue }

    /// HUD modules, top to bottom. The always-visible ones (Spell Timers, CS/min) come first so
    /// they never move when the Tab-only modules appear below them.
    static let hudModules: [OverlayPanelKind] = [.cooldowns, .farm, .gold, .build]

    var window: OverlayWindowKind {
        switch self {
        case .scout: .lanes
        case .cooldowns, .farm: .hud
        case .gold, .build: .hudTab
        }
    }

    var title: String {
        switch self {
        case .scout: "Lanes"
        case .cooldowns: "Spell Timers"
        case .gold: "Gold Diff"
        case .build: "Next Item"
        case .farm: "CS/min"
        }
    }

    var symbol: String {
        switch self {
        case .scout: "person.2.fill"
        case .cooldowns: "timer"
        case .gold: "plusminus"
        case .build: "bag.fill"
        case .farm: "chart.bar.fill"
        }
    }

    var summary: String {
        switch self {
        case .scout: "Each lane's two players with rank, win rate and notes. Shown at the loading screen, and in game while Tab is held."
        case .cooldowns: "Click an enemy's summoner spell when you see it cast; it counts down live."
        case .gold: "Item gold against your lane opponent, plus team totals."
        case .build: "The next item in a common build, adjusted to what you own."
        case .farm: "A small row with your CS per minute, total CS and share of lane minions."
        }
    }
}

/// The overlay windows. The HUD is two tiles: the always-visible one, and the Tab section that
/// hangs directly under it (a child window, so it moves with it). Showing the Tab section is a
/// plain show/hide rather than a resize of the HUD.
enum OverlayWindowKind: String, CaseIterable {
    case lanes = "scout"
    case hud
    case hudTab

    var title: String {
        switch self {
        case .lanes: "Lanes"
        case .hud: "HUD"
        case .hudTab: "HUD (Tab)"
        }
    }

    /// The window whose × hides this one.
    var dismissGroup: OverlayWindowKind { self == .hudTab ? .hud : self }
}

/// User preferences, persisted to UserDefaults and applied live (no Apply button).
@Observable @MainActor
final class AppSettings {
    static let shared = AppSettings()

    var enabledPanels: Set<OverlayPanelKind> {
        didSet { defaults.set(enabledPanels.map(\.rawValue), forKey: "panels") }
    }
    var overlayEnabled: Bool { didSet { defaults.set(overlayEnabled, forKey: "overlayEnabled") } }
    /// Tab (hold) always shows panels; these two triggers are additive.
    var showOnShopKey: Bool { didSet { defaults.set(showOnShopKey, forKey: "showOnShopKey") } }
    var showAlways: Bool { didSet { defaults.set(showAlways, forKey: "showAlways") } }
    var shopKeyCode: Int { didSet { defaults.set(shopKeyCode, forKey: "shopKeyCode") } }
    var cooldownFormat: CooldownFormat { didSet { defaults.set(cooldownFormat.rawValue, forKey: "cooldownFormat") } }
    var overlayOpacity: Double { didSet { defaults.set(overlayOpacity, forKey: "overlayOpacity") } }
    /// Shared text size for the app window and every overlay panel.
    var textScale: Double { didSet { defaults.set(textScale, forKey: "textScale") } }
    var onlyOverGame: Bool { didSet { defaults.set(onlyOverGame, forKey: "onlyOverGame") } }
    var autoSwitchToLive: Bool { didSet { defaults.set(autoSwitchToLive, forKey: "autoSwitchToLive") } }
    /// Put the common rune page into League as soon as you lock in a champion.
    var autoImportRunes: Bool { didSet { defaults.set(autoImportRunes, forKey: "autoImportRunes") } }

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        // Version 2 merged the in-game panels into one HUD; start everyone on the new defaults.
        // Version 3 turns on the CS/min row, keeping the other switches as they were.
        let version = d.integer(forKey: "settingsVersion")
        var panels = Self.defaultPanels
        if version >= 2, let stored = d.stringArray(forKey: "panels") {
            panels = Set(stored.compactMap(OverlayPanelKind.init(rawValue:)))
            if version < 3 { panels.insert(.farm) }
        }
        if version < 3 {
            d.set(panels.map(\.rawValue), forKey: "panels")
            d.set(3, forKey: "settingsVersion")
        }
        enabledPanels = panels
        overlayEnabled = d.object(forKey: "overlayEnabled") as? Bool ?? true
        showOnShopKey = d.bool(forKey: "showOnShopKey")
        showAlways = d.bool(forKey: "showAlways")
        shopKeyCode = d.object(forKey: "shopKeyCode") as? Int ?? kVK_ANSI_P
        cooldownFormat = d.string(forKey: "cooldownFormat").flatMap(CooldownFormat.init(rawValue:)) ?? .minutesSeconds
        overlayOpacity = d.object(forKey: "overlayOpacity") as? Double ?? 0.95
        textScale = d.object(forKey: "textScale") as? Double ?? 1.0
        onlyOverGame = d.object(forKey: "onlyOverGame") as? Bool ?? true
        autoSwitchToLive = d.object(forKey: "autoSwitchToLive") as? Bool ?? true
        autoImportRunes = d.object(forKey: "autoImportRunes") as? Bool ?? true
    }

    static let defaultPanels: Set<OverlayPanelKind> = [.scout, .cooldowns, .farm, .gold, .build]

    func isEnabled(_ panel: OverlayPanelKind) -> Bool {
        enabledPanels.contains(panel)
    }

    func setEnabled(_ panel: OverlayPanelKind, _ on: Bool) {
        if on { enabledPanels.insert(panel) } else { enabledPanels.remove(panel) }
    }

    var shopKeyName: String {
        KeyNames.name(for: shopKeyCode)
    }
}

enum KeyNames {
    private static let letters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Tab: "Tab", kVK_Space: "Space", kVK_Escape: "Esc",
    ]

    static func name(for code: Int) -> String {
        letters[code] ?? "Key \(code)"
    }
}
