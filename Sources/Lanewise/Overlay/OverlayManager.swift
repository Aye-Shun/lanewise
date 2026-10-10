import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Decides what the overlay shows and owns its two windows: Lanes (loading-screen scouting) and
/// the HUD, which stacks Spell Timers, CS/min, Gold Diff and Next Item in one tile.
///
/// - Spell Timers and CS/min stay up during a Summoner's Rift game (timers so they can be
///   clicked any time; CS/min because it's one small row).
/// - Gold Diff and Next Item appear while Tab is held (no permission needed), or always if
///   "Keep everything on screen" is on. The shop key can optionally toggle Next Item.
/// - Lanes shows on the loading screen, and in game while Tab is held.
/// - The × on a tile hides it until the next game. Move mode (⌃⇧M) shows everything so it can be
///   dragged; positions are saved separately for Summoner's Rift, ARAM and Arena.
@Observable @MainActor
final class OverlayManager {
    static let shared = OverlayManager()

    /// Modules currently shown (the HUD renders the HUD modules in this set).
    private(set) var visiblePanels: Set<OverlayPanelKind> = []
    private(set) var tabHeld = false
    private(set) var shopLatched = false
    /// Windows hidden with their × button; cleared when the next game starts.
    private(set) var dismissed: Set<OverlayWindowKind> = []
    var isMoveMode = false {
        didSet {
            refresh()
            if !isMoveMode && !GameMonitor.shared.phase.isInGame { releaseWindows() }
        }
    }

    @ObservationIgnored private var windows: [OverlayWindowKind: OverlayWindow] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var shopWasDown = false
    @ObservationIgnored private var escapeWasDown = false
    @ObservationIgnored private var layout = "sr"
    @ObservationIgnored private var prefetchedKey: String?
    /// Diagnostics only: stands in for the Tab key (previews otherwise always show everything).
    @ObservationIgnored var debugTabOverride: Bool?

    /// Key polling only runs during a game; outside games Lanewise does no periodic overlay work
    /// and the windows are released.
    func handlePhase(_ phase: GamePhase) {
        if phase.isInGame {
            startPolling()
        } else {
            stopPolling()
            if shopLatched { shopLatched = false }
            if tabHeld { tabHeld = false }
            if !dismissed.isEmpty { dismissed = [] }
            if !isMoveMode { releaseWindows() }
        }
        refresh()
    }

    /// Hides a window until the next game (the × button).
    func dismiss(_ window: OverlayWindowKind) {
        dismissed.insert(window)
        refresh()
    }

    private func startPolling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // The game is frontmost during play, so without this App Nap would throttle Tab detection.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Watching for the Tab key during a League game"
        )
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func releaseWindows() {
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows = [:]
    }

    private func tick() {
        let settings = AppSettings.shared
        let inGame = GameMonitor.shared.phase.isInGame
        let held = inGame && KeyState.isDown(kVK_Tab)
        if held != tabHeld { tabHeld = held }

        if inGame && settings.showOnShopKey {
            let shopDown = KeyState.isDown(settings.shopKeyCode)
            if shopDown && !shopWasDown { shopLatched.toggle() }
            shopWasDown = shopDown
            let escapeDown = KeyState.isDown(kVK_Escape)
            if escapeDown && !escapeWasDown && shopLatched { shopLatched = false }
            escapeWasDown = escapeDown
        } else if shopLatched {
            shopLatched = false
        }
        refresh()
    }

    func desiredPanels() -> Set<OverlayPanelKind> {
        let monitor = GameMonitor.shared
        let settings = AppSettings.shared
        guard settings.overlayEnabled else { return [] }
        // Move mode shows every enabled module, even between games, so the windows can be placed.
        if isMoveMode { return settings.enabledPanels }
        guard monitor.phase.isInGame else { return [] }
        let demo = monitor.status == .demo
        if settings.onlyOverGame && !demo && !GameWindow.isFrontmost { return [] }

        let mode = monitor.gameMode
        let hasLive = monitor.live != nil
        let held = debugTabOverride ?? (tabHeld || settings.showAlways || demo)
        let shop = settings.showOnShopKey && shopLatched

        var result: Set<OverlayPanelKind> = []
        for panel in settings.enabledPanels where !dismissed.contains(panel.window.dismissGroup) {
            let supported: Bool
            switch panel {
            case .scout: supported = monitor.lobby != nil
            case .cooldowns: supported = hasLive && mode.showsCooldowns
            case .gold: supported = hasLive && mode.showsGold
            case .build: supported = mode.showsBuilds && monitor.myChampionId != nil
            case .farm: supported = hasLive && mode == .summonersRift
            }
            guard supported else { continue }

            let visible: Bool
            switch panel {
            case .scout: visible = !hasLive || held      // the loading screen is when scouting matters most
            case .cooldowns, .farm: visible = true
            case .gold: visible = held
            case .build: visible = held || shop
            }
            if visible { result.insert(panel) }
        }
        return result
    }

    /// Recomputes which modules are visible without touching any windows.
    @discardableResult
    func updateVisibility() -> Set<OverlayPanelKind> {
        let desired = desiredPanels()
        if desired != visiblePanels { visiblePanels = desired }
        return desired
    }

    func refresh() {
        prefetchMeta()
        let desired = updateVisibility()
        let newLayout = GameMonitor.shared.gameMode.layoutKey
        if newLayout != layout {
            layout = newLayout
            for (kind, window) in windows where kind != .hudTab { window.useLayout(kind: kind, layout: layout) }
        }

        let alpha = AppSettings.shared.overlayOpacity
        for kind in [OverlayWindowKind.lanes, .hud] {
            if desired.contains(where: { $0.window == kind }) {
                show(window(for: kind), alpha: alpha)
            } else if let window = windows[kind], window.isVisible {
                window.orderOut(nil)
            }
        }

        // The Tab section hangs under the HUD as a child window, so it moves with it.
        let hudShown = desired.contains { $0.window == .hud }
        if desired.contains(where: { $0.window == .hudTab }) {
            let hud = window(for: .hud)
            let tab = window(for: .hudTab)
            if !tab.isVisible {
                let anchor = hud.frame
                tab.setFrameTopLeftPoint(NSPoint(x: anchor.minX, y: hudShown ? anchor.minY - 6 : anchor.maxY))
            }
            if hudShown && tab.parent == nil {
                hud.addChildWindow(tab, ordered: .above)
            } else if !hudShown, let parent = tab.parent {
                parent.removeChildWindow(tab)
            }
            show(tab, alpha: alpha)
        } else if let tab = windows[.hudTab], tab.isVisible {
            tab.parent?.removeChildWindow(tab)
            tab.orderOut(nil)
        }
    }

    /// Shows a window, and puts it back if anything knocked it off screen or behind the game.
    private func show(_ window: OverlayWindow, alpha: CGFloat) {
        if abs(window.alphaValue - alpha) > 0.001 { window.alphaValue = alpha }
        if !window.isVisible || !window.isOnActiveSpace || !window.occlusionState.contains(.visible) {
            window.orderFrontRegardless()
        }
    }

    /// Loads the player's champion data once per champion/role so Next Item is ready when Tab is held.
    private func prefetchMeta() {
        let monitor = GameMonitor.shared
        guard monitor.phase.isInGame, let champion = monitor.myChampionId else { return }
        let key = MetaStore.championKey(champion, monitor.myPosition, monitor.gameMode)
        guard key != prefetchedKey else { return }
        prefetchedKey = key
        let position = monitor.myPosition
        let mode = monitor.gameMode
        Task { await MetaStore.shared.ensureChampion(champion, position, mode) }
    }

    /// Puts every window back at its default spot for the current mode.
    func resetPositions() {
        for (kind, window) in windows where kind != .hudTab { window.placeAtDefault(kind: kind) }
    }

    private func window(for kind: OverlayWindowKind) -> OverlayWindow {
        if let existing = windows[kind] { return existing }
        let window = OverlayWindow(content: OverlayHost(window: kind))
        // The Tab section's position comes from the HUD above it.
        if kind != .hudTab { window.useLayout(kind: kind, layout: layout) }
        // Both windows take clicks: Spell Timers and the × buttons. They're small and sit at the
        // screen edge, and Lanes only shows on the loading screen or while Tab is held.
        window.ignoresMouseEvents = false
        windows[kind] = window
        return window
    }
}

/// Borderless, non-activating panel above the game's fullscreen Space. It never becomes key, so
/// the game keeps keyboard focus even when a panel is clicked.
final class OverlayWindow: NSPanel {
    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)

        let host = FirstMouseHostingView(rootView: AnyView(
            content.reportSize { [weak self] size in self?.fit(size) }
        ))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Resize to the SwiftUI content while keeping the top-left corner fixed.
    private func fit(_ size: CGSize) {
        guard size.width > 1, size.height > 1, size != frame.size else { return }
        var rect = frame
        let top = rect.maxY
        rect.size = size
        rect.origin.y = top - size.height
        setFrame(rect, display: true)
        invalidateShadow()
    }

    func useLayout(kind: OverlayWindowKind, layout: String) {
        // "v2": the HUD moved to the left side, so earlier saved spots shouldn't carry over.
        let name = "Lanewise.overlay.v2.\(kind.rawValue).\(layout)"
        setFrameAutosaveName("")
        if !setFrameUsingName(name) { placeAtDefault(kind: kind) }
        setFrameAutosaveName(name)
    }

    /// Lanes top-right. The HUD down the left edge, starting just below where League shows the
    /// death recap (about a third of the way down the screen).
    func placeAtDefault(kind: OverlayWindowKind) {
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.frame else { return }
        let point: NSPoint = switch kind {
        case .lanes: NSPoint(x: screen.maxX - 430, y: screen.maxY - 40)
        case .hud, .hudTab: NSPoint(x: screen.minX + 10, y: screen.maxY - screen.height * 0.33)
        }
        setFrameTopLeftPoint(point)
    }
}

/// Lets clicks reach SwiftUI controls in a window that never becomes key.
final class FirstMouseHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    // Siblings that don't set the key report .zero; don't let them overwrite the measured size.
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    /// Lays the view out at its ideal size and reports that size whenever it changes.
    func reportSize(_ action: @escaping (CGSize) -> Void) -> some View {
        fixedSize()
            .background(GeometryReader { Color.clear.preference(key: ContentSizeKey.self, value: $0.size) })
            .onPreferenceChange(ContentSizeKey.self) { action($0) }
    }
}

enum KeyState {
    /// Reads whether a key is held. Tab works without permissions; letter keys need Input Monitoring.
    static func isDown(_ code: Int) -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
    }

    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }
}

enum GameWindow {
    /// True when League (or Lanewise itself) is the frontmost app, so panels don't float over
    /// other apps when the player alt-tabs out of a game.
    @MainActor
    static var isFrontmost: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        let id = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""
        return id.contains("riotgames") || name.contains("league of legends")
    }
}
