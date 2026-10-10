import AppKit
import SwiftUI

/// Renders screens with demo data to PNG files without showing any window, for checking the
/// UI without a running game: `Lanewise --snapshot out.png --scene draft`.
///
/// Scenes: overview, history, lookup, draft, players, players-inspector, plan, scoreboard, settings,
/// settings-general, overlays.
/// Add `--appearance light` to render the light appearance.
@MainActor
enum SnapshotRunner {
    private static var delegate: Delegate?

    static func run(output: String, arguments: [String]) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = Delegate(output: output, arguments: arguments)
        self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    final class Delegate: NSObject, NSApplicationDelegate {
        let output: String
        let scene: String
        let appearance: String
        private var window: NSWindow?

        init(output: String, arguments: [String]) {
            self.output = output
            if let index = arguments.firstIndex(of: "--scene"), index + 1 < arguments.count {
                scene = arguments[index + 1]
            } else {
                scene = "players"
            }
            if let index = arguments.firstIndex(of: "--appearance"), index + 1 < arguments.count {
                appearance = arguments[index + 1]
            } else {
                appearance = "dark"
            }
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            Task { @MainActor in
                await render()
                NSApp.terminate(nil)
            }
        }

        @MainActor
        private func render() async {
            await DataDragon.shared.load()
            let monitor = GameMonitor.shared
            monitor.enterDemo(["champselect", "draft"].contains(scene) ? .champSelect : .inGame)

            let enemies = Role.sorted((monitor.live?.allPlayers ?? []).filter { !$0.isBlueSide })
            if scene == "timer-test" {
                // Diagnostic: click an enemy's Flash, then watch it count down on the real clock.
                guard let enemy = enemies.first,
                      let spell = DataDragon.shared.spell(live: enemy.summonerSpells?.summonerSpellOne) else {
                    print("no enemy spell")
                    return
                }
                CooldownTracker.shared.toggle(player: enemy, slot: 0, spell: spell, now: monitor.estimatedGameTime())
                for second in 0...4 {
                    let left = CooldownTracker.shared.remaining(player: enemy, slot: 0, now: monitor.estimatedGameTime()) ?? -1
                    print(String(format: "t+%ds  %@ remaining %.1f s", second, spell.name, left))
                    try? await Task.sleep(for: .seconds(1))
                }
                return
            }
            if scene == "overlays" {
                // Show a couple of spells mid-cooldown in the render.
                let now = monitor.estimatedGameTime()
                for (index, slot) in [(1, 0), (3, 1)] where index < enemies.count {
                    let enemy = enemies[index]
                    if let spell = DataDragon.shared.spell(live: enemy.summonerSpells?.both[slot] ?? nil) {
                        CooldownTracker.shared.toggle(player: enemy, slot: slot, spell: spell, now: now - 70)
                    }
                }
            }

            // Warm meta data and images so the snapshot shows real content.
            let store = MetaStore.shared
            await store.ensureLaneMeta()
            await store.ensureChampion(monitor.myChampionId, monitor.myPosition, monitor.gameMode)
            for key in monitor.allyChampions + monitor.enemyChampions {
                await store.ensureChampion(key, nil, monitor.gameMode)
            }
            var urls = DemoData.imageURLs()
            if let meta = store.champion(monitor.myChampionId, monitor.myPosition, monitor.gameMode)?.value {
                let items = [meta.starter, meta.core, meta.boots].compactMap { $0?.items }.flatMap { $0 }
                    + (meta.fourth + meta.fifth + meta.sixth).flatMap(\.items)
                urls += items.compactMap { DataDragon.shared.itemIcon($0) }
                urls += (meta.runes?.allPerkIDs ?? []).compactMap { DataDragon.shared.runeIcon($0) }
                urls += [meta.runes?.primaryPageId, meta.runes?.secondaryPageId].compactMap { $0 }.compactMap { DataDragon.shared.runeIcon($0) }
                urls += meta.hardestMatchups.compactMap { DataDragon.shared.championIcon($0.championId) }
                urls += (meta.synergies?.support ?? []).compactMap { DataDragon.shared.championIcon($0.synergyChampionId) }
            }
            OverlayManager.shared.updateVisibility()
            await withTaskGroup(of: Void.self) { group in
                for url in Set(urls) { group.addTask { _ = await ImageCache.shared.image(for: url) } }
            }

            if scene == "tab-stress" {
                // Diagnostic: flip "Tab held" rapidly on a real, offscreen HUD window and check the
                // window always ends up the size of its content.
                OverlayManager.shared.debugTabOverride = false
                OverlayManager.shared.updateVisibility()
                let window = OverlayWindow(content: OverlayHost(window: .hud))
                window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
                window.orderFrontRegardless()
                try? await Task.sleep(for: .seconds(1.5))
                let settled = window.frame.size
                var resizes = 0
                var rng = SeededGenerator(seed: 99)
                var mismatches = 0
                for round in 1...60 {
                    OverlayManager.shared.debugTabOverride = Bool.random(using: &rng)
                    OverlayManager.shared.updateVisibility()
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 5...120, using: &rng)))
                    if window.frame.size != settled { resizes += 1 }
                    if round % 3 == 0 {
                        try? await Task.sleep(for: .milliseconds(400))
                        let measure = NSHostingView(rootView: OverlayHost(window: .hud).fixedSize())
                        let expected = measure.fittingSize
                        let actual = window.frame.size
                        if abs(expected.width - actual.width) > 1 || abs(expected.height - actual.height) > 1 {
                            mismatches += 1
                            print("round \(round): tab=\(OverlayManager.shared.debugTabOverride ?? false) window \(Int(actual.width))x\(Int(actual.height)) but content \(Int(expected.width))x\(Int(expected.height))")
                        }
                    }
                }
                print("checks done, mismatches: \(mismatches), HUD resized on Tab: \(resizes) times (size \(Int(settled.width))x\(Int(settled.height)))")
                window.close()
                return
            }
            if scene == "window-sizing" {
                // Diagnostic: real overlay windows, kept offscreen, should size to their content.
                var windows: [OverlayWindow] = []
                for kind in OverlayWindowKind.allCases {
                    let window = OverlayWindow(content: OverlayHost(window: kind))
                    window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
                    window.orderFrontRegardless()
                    windows.append(window)
                }
                try? await Task.sleep(for: .seconds(2))
                for (kind, window) in zip(OverlayWindowKind.allCases, windows) {
                    print("\(kind.title): \(Int(window.frame.width))x\(Int(window.frame.height))")
                    window.close()
                }
                return
            }

            let view: AnyView
            var size = CGSize(width: 1280, height: 860)
            let navigation = Navigation.shared
            switch scene {
            case "overview": navigation.selection = .overview
            case "lookup":
                navigation.selection = .lookup
                await PlayerLookupStore.shared.search("Windwall#YAS")
                if let store = PlayerLookupStore.shared.history {
                    let urls = store.games.flatMap { $0.me.items }.compactMap { DataDragon.shared.itemIcon($0) }
                        + store.games.compactMap { DataDragon.shared.championIcon($0.me.championId) }
                        + [DataDragon.shared.profileIcon(PlayerLookupStore.shared.foundProfile?.summoner?.profileIconId)].compactMap { $0 }
                    await withTaskGroup(of: Void.self) { group in
                        for url in Set(urls) { group.addTask { _ = await ImageCache.shared.image(for: url) } }
                    }
                    if let first = store.games.first {
                        navigation.selectedGame = first.gameId
                        await store.loadDetail(first.gameId)
                    }
                }
                size.height = 1000
            case "history":
                navigation.selection = .history
                await MatchHistoryStore.shared.reload()
                if let first = MatchHistoryStore.shared.games.first {
                    navigation.selectedGame = first.gameId
                    await MatchHistoryStore.shared.loadDetail(first.gameId)
                    let urls = (MatchHistoryStore.shared.games.flatMap { $0.me.items + [$0.me.championId] }).compactMap { DataDragon.shared.itemIcon($0) }
                        + MatchHistoryStore.shared.games.compactMap { DataDragon.shared.championIcon($0.me.championId) }
                        + (MatchHistoryStore.shared.details[first.gameId]?.value?.players ?? []).compactMap { DataDragon.shared.championIcon($0.championId) }
                    await withTaskGroup(of: Void.self) { group in
                        for url in Set(urls) { group.addTask { _ = await ImageCache.shared.image(for: url) } }
                    }
                }
                size.height = 1000
            case "champselect", "draft":
                navigation.selection = .draft
                size.height = 1200
            case "plan":
                navigation.selection = .plan
                size.height = 1000
            case "scoreboard": navigation.selection = .scoreboard
            case "players-inspector":
                navigation.selection = .players
                navigation.selectedPlayer = "demo-7"
                size.height = 1000
            default:
                navigation.selection = .players
                navigation.showInspector = false
            }
            switch scene {
            case "settings":
                view = AnyView(OverlaySettings().frame(width: 520))
                size = CGSize(width: 520, height: 1180)
            case "settings-general":
                view = AnyView(GeneralSettings().frame(width: 520))
                size = CGSize(width: 520, height: 1050)
            case "overlays":
                view = AnyView(OverlayGallery())
                size = CGSize(width: 700, height: 640)
            default:
                view = AnyView(RootView())
            }

            let host = NSHostingView(rootView: view.withAppEnvironment())
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            window.orderFrontRegardless()
            self.window = window

            try? await Task.sleep(for: .seconds(2))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: output))
            }
            window.orderOut(nil)
        }
    }
}

/// Both overlay windows over a game-like backdrop (snapshot only).
private struct OverlayGallery: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                OverlayHost(window: .hud)
                OverlayHost(window: .hudTab)
            }
            OverlayHost(window: .lanes)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.30, green: 0.42, blue: 0.28), Color(red: 0.55, green: 0.50, blue: 0.36),
                                    Color(red: 0.20, green: 0.30, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}
