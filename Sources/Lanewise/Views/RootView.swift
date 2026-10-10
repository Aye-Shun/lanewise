import Observation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, history, lookup, draft, players, plan, scoreboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .history: "Match History"
        case .lookup: "Player Lookup"
        case .draft: "Draft"
        case .players: "Players"
        case .plan: "Game Plan"
        case .scoreboard: "Scoreboard"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        case .lookup: "magnifyingglass"
        case .draft: "person.2.crop.square.stack"
        case .players: "person.2"
        case .plan: "list.bullet.clipboard"
        case .scoreboard: "tablecells"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .history: "2"
        case .lookup: "3"
        case .draft: "4"
        case .players: "5"
        case .plan: "6"
        case .scoreboard: "7"
        }
    }
}

/// Shared so the Go menu (⌘1–⌘5) can drive the sidebar.
@Observable @MainActor
final class Navigation {
    static let shared = Navigation()
    var selection: SidebarItem = .overview
    var selectedPlayer: String?
    var selectedGame: Int?
    var showInspector = true
}

struct RootView: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings
    @Environment(OverlayManager.self) private var overlay
    @Environment(Navigation.self) private var navigation
    @Environment(MatchHistoryStore.self) private var history
    @Environment(PlayerLookupStore.self) private var lookup

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(selection: Binding(get: { navigation.selection }, set: { if let item = $0 { navigation.selection = item } })) {
                sidebarRow(.overview)
                sidebarRow(.history)
                sidebarRow(.lookup)
                Section("Match") {
                    sidebarRow(.draft)
                    sidebarRow(.players)
                    sidebarRow(.plan)
                    sidebarRow(.scoreboard)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 204, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarStatus() }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
                .navigationTitle(navigation.selection.title)
                .navigationSubtitle(subtitle)
                // Only Draft and Players have details to inspect.
                .inspector(isPresented: Binding(
                    get: { navigation.showInspector && hasInspector },
                    set: { navigation.showInspector = $0 }
                )) {
                    inspector
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Palette.canvas)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .toolbar { toolbar }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .onChange(of: monitor.phase) { _, phase in
            guard settings.autoSwitchToLive else { return }
            // Only move on a phase change, so we never fight a user who clicked elsewhere.
            if phase == .champSelect { navigation.selection = .draft }
            if phase.isInGame && navigation.selection != .plan { navigation.selection = .players }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(isNow(item) ? Text("Now") : nil)
            .tag(item)
    }

    private func isNow(_ item: SidebarItem) -> Bool {
        switch item {
        case .overview, .history, .lookup: false
        case .draft: monitor.phase == .champSelect
        case .players: monitor.phase.isInGame && monitor.live == nil
        case .plan: monitor.phase.isInGame && monitor.live != nil
        case .scoreboard: false
        }
    }

    private var subtitle: String {
        let champion = DataDragon.shared.champion(monitor.myChampionId)?.name
        let opponent = DataDragon.shared.champion(monitor.laneOpponentChampion)?.name
        let clock = monitor.live.map { Format.clock($0.gameData?.gameTime ?? 0) }
        let lastGame = monitor.lobby != nil && !monitor.phase.isInGame && monitor.screen == .game
        switch navigation.selection {
        case .overview:
            return ""
        case .history:
            return monitor.status == .demo ? "Sample player" : monitor.me?.riotID ?? ""
        case .lookup:
            return lookup.foundProfile?.riotID ?? ""
        case .draft:
            guard monitor.screen == .champSelect else { return "" }
            return [champion, monitor.myPosition?.label, monitor.queueName].compactMap { $0 }.joined(separator: " · ")
        case .players:
            guard monitor.lobby != nil else { return "" }
            if lastGame { return "Last game" }
            return [monitor.queueName, monitor.live == nil ? "Loading screen" : clock].compactMap { $0 }.joined(separator: " · ")
        case .plan:
            guard monitor.lobby != nil else { return "" }
            if lastGame { return "Last game" }
            let matchup = [champion, opponent].compactMap { $0 }.joined(separator: " vs ")
            return [matchup.isEmpty ? nil : matchup, clock].compactMap { $0 }.joined(separator: " · ")
        case .scoreboard:
            return lastGame ? "Last game" : clock ?? ""
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.selection {
        case .overview:
            OverviewView()
        case .history:
            if monitor.status == .searching && history.games.isEmpty {
                LeagueNotRunningView()
            } else {
                MatchHistoryView()
            }
        case .lookup:
            PlayerLookupView()
        case .draft:
            if monitor.screen == .champSelect {
                DraftView()
            } else if monitor.status == .searching {
                LeagueNotRunningView()
            } else {
                ContentUnavailableView {
                    Label("No Draft in Progress", systemImage: "person.2.crop.square.stack")
                } description: {
                    Text("Runes, a build, ban suggestions and enemy picks appear here during champ select.")
                } actions: {
                    Button("Draft Preview") { monitor.enterDemo(.champSelect) }
                }
            }
        case .players:
            if monitor.lobby != nil {
                PlayersView()
            } else if monitor.status == .searching {
                LeagueNotRunningView()
            } else {
                ContentUnavailableView("No Players Yet", systemImage: "person.3",
                                       description: Text("Both teams are looked up as soon as the loading screen starts."))
            }
        case .plan:
            if monitor.lobby != nil {
                GamePlanView()
            } else if monitor.status == .searching {
                LeagueNotRunningView()
            } else {
                ContentUnavailableView {
                    Label("Not in a Game", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Your next item, opponent and gold appear here during a match.")
                } actions: {
                    Button("In-Game Preview") { monitor.enterDemo(.inGame) }
                }
            }
        case .scoreboard:
            if let live = monitor.live {
                ScoreboardView(live: live)
            } else if monitor.status == .searching {
                LeagueNotRunningView()
            } else {
                ContentUnavailableView("Scoreboard Unavailable", systemImage: "tablecells",
                                       description: Text("Live stats appear once the game finishes loading."))
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        switch navigation.selection {
        case .draft where monitor.screen == .champSelect:
            DraftInspector()
        case .players where monitor.lobby != nil:
            PlayerInspector(slot: selectedSlot)
        case .history where !history.games.isEmpty:
            MatchDetailInspector(gameId: selectedGame(in: history))
        case .lookup where !(lookup.history?.games.isEmpty ?? true):
            if let store = lookup.history {
                MatchDetailInspector(gameId: selectedGame(in: store)).environment(store)
            }
        default:
            ContentUnavailableView("No Details", systemImage: "sidebar.trailing",
                                   description: Text("Match History, Player Lookup, Draft and Players show details here."))
        }
    }

    private var hasInspector: Bool {
        (navigation.selection == .draft && monitor.screen == .champSelect)
            || (navigation.selection == .players && monitor.lobby != nil)
            || (navigation.selection == .history && !history.games.isEmpty)
            || (navigation.selection == .lookup && !(lookup.history?.games.isEmpty ?? true))
    }

    /// The selected game if it belongs to this history, otherwise its newest game.
    private func selectedGame(in store: MatchHistoryStore) -> Int? {
        if let id = navigation.selectedGame, store.games.contains(where: { $0.gameId == id }) { return id }
        return store.games.first?.gameId
    }

    private var selectedSlot: PlayerSlot? {
        guard let id = navigation.selectedPlayer else { return nil }
        let slots = monitor.champSelect + (monitor.lobby.map { $0.blue + $0.red } ?? [])
        return slots.first { $0.id == id }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var settings = settings
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $settings.overlayEnabled) {
                Label("Overlay", systemImage: "rectangle.inset.topright.filled")
            }
            .help("Show or hide panels in game (⌃⇧O)")

            if overlay.isMoveMode {
                Button("Done") { overlay.isMoveMode = false }
                    .buttonStyle(.borderedProminent)
            } else {
                Button {
                    overlay.isMoveMode = true
                } label: {
                    Label("Arrange Panels", systemImage: "rectangle.3.group")
                }
                .help("Show every panel so you can drag it into place (⌃⇧M)")
            }

            Menu {
                Button("Draft Preview") { monitor.enterDemo(.champSelect) }
                Button("In-Game Preview") { monitor.enterDemo(.inGame) }
                if monitor.status == .demo {
                    Divider()
                    Button("End Preview") { monitor.exitDemo() }
                }
            } label: {
                Label("Preview", systemImage: "play.rectangle")
            }
            .help("Explore every screen with sample players")

            if hasInspector {
                Button {
                    navigation.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}

/// Connection state pinned to the bottom of the sidebar.
struct SidebarStatus: View {
    @Environment(GameMonitor.self) private var monitor

    var body: some View {
        let (symbol, color, state, detail): (String, Color, String, String) = switch monitor.status {
        case .searching:
            ("circle.dotted", Palette.tertiaryLabel, "Waiting for League", "Open the client to connect")
        case .connected:
            ("checkmark.circle.fill", Palette.positive, "Connected", [monitor.me?.riotID, monitor.phase.label].compactMap { $0 }.joined(separator: " · "))
        case .demo:
            ("play.circle.fill", Color.accentColor, "Preview", "Sample data · \(monitor.phase.label)")
        }
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.label)
                    Text(detail).font(.system(size: 10)).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

struct LeagueNotRunningView: View {
    var body: some View {
        ContentUnavailableView("League Isn't Running", systemImage: "bolt.horizontal.circle",
                               description: Text("Open League of Legends and sign in. Lanewise connects on its own, with no account or API key."))
    }
}

/// Scrollable detail page with the standard padding and an optional width cap.
struct DetailPage<Content: View>: View {
    var maxWidth: CGFloat? = 760
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
