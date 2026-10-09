import Foundation
import Observation

enum ConnectionStatus: Equatable {
    case searching, connected, demo
}

enum GamePhase: Equatable {
    case idle, lobby, matchmaking, readyCheck, champSelect, gameStart, inProgress, reconnect
    case waitingForStats, preEndOfGame, endOfGame
    case other(String)

    init(raw: String) {
        switch raw {
        case "None": self = .idle
        case "Lobby": self = .lobby
        case "Matchmaking": self = .matchmaking
        case "ReadyCheck": self = .readyCheck
        case "ChampSelect": self = .champSelect
        case "GameStart": self = .gameStart
        case "InProgress": self = .inProgress
        case "Reconnect": self = .reconnect
        case "WaitingForStats": self = .waitingForStats
        case "PreEndOfGame": self = .preEndOfGame
        case "EndOfGame": self = .endOfGame
        default: self = .other(raw)
        }
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .lobby: "In lobby"
        case .matchmaking: "In queue"
        case .readyCheck: "Match found"
        case .champSelect: "Champ select"
        case .gameStart: "Loading screen"
        case .inProgress: "In game"
        case .reconnect: "Reconnecting"
        case .waitingForStats, .preEndOfGame, .endOfGame: "Post game"
        case .other(let raw): raw
        }
    }

    var isInGame: Bool { self == .gameStart || self == .inProgress || self == .reconnect }
}

enum ProfileLoad {
    case loading
    case loaded(PlayerProfile)
    case failed(String)
}

struct PlayerSlot: Identifiable, Hashable {
    var id: String
    var puuid: String?
    var championId: Int?
    var position: String?
    var displayName: String?
    var isLocalPlayer = false
    /// Riot hides teammates' identities in ranked champ select; we don't try to reveal them.
    var isHidden = false
}

struct LobbyTeams: Equatable {
    var blue: [PlayerSlot]
    var red: [PlayerSlot]
}

enum MainScreen {
    case idle, champSelect, game
}

/// Polls the League client, tracks the gameflow phase, and loads a profile for every
/// visible player. All UI (main window, overlay, menu bar) observes this one object.
@Observable @MainActor
final class GameMonitor {
    static let shared = GameMonitor()

    private(set) var status: ConnectionStatus = .searching
    private(set) var me: LCUSummoner?
    private(set) var phase: GamePhase = .idle
    private(set) var champSelect: [PlayerSlot] = []
    /// Enemy picks as they're revealed in champ select (champion only; identities stay hidden).
    private(set) var enemyChampSelect: [PlayerSlot] = []
    private(set) var lobby: LobbyTeams?
    private(set) var gameId: Int?
    private(set) var queueId: Int?
    private(set) var queueName: String?
    private(set) var mapId: Int?
    private(set) var live: LiveGameData?
    private(set) var liveReceivedAt = Date.distantPast
    private(set) var profiles: [String: ProfileLoad] = [:]
    private(set) var loadoutImport: LoadoutImportStatus = .idle

    enum LoadoutImportStatus: Equatable {
        case idle
        case importing(champion: String)
        /// What was imported, e.g. ["runes", "item build", "spells"].
        case imported(champion: String, parts: [String])
        case failed(String)
    }

    /// The League client connection, for services that read or write through it.
    var lcu: LCUClient? { client }

    /// Called on every phase transition; the overlay uses it to show/hide itself.
    @ObservationIgnored var onPhaseChange: (@MainActor (GamePhase) -> Void)?

    @ObservationIgnored private var client: LCUClient?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var resolvedRiotIDs: [String: String] = [:]
    @ObservationIgnored private var attemptedRiotIDs: Set<String> = []
    @ObservationIgnored private var connectAttempts = 0
    @ObservationIgnored private var phaseFailures = 0
    /// The champion the loadout was last imported for in this champ select.
    @ObservationIgnored private var importedChampion: Int?
    /// When the current unanswered ready check was first seen; nil once it's answered or gone.
    @ObservationIgnored private var readyCheckPendingSince: Date?
    @ObservationIgnored private var readyCheckAccepted = false
    @ObservationIgnored private var lastSessionFetch = Date.distantPast

    // MARK: - Derived state

    var screen: MainScreen {
        if phase == .champSelect && !champSelect.isEmpty { return .champSelect }
        return lobby == nil ? .idle : .game
    }

    var myTeamIsBlue: Bool {
        !(lobby?.red.contains { $0.isLocalPlayer } ?? false)
    }

    var statusText: String {
        switch status {
        case .searching: "Waiting for League client"
        case .connected: "Connected · \(me?.riotID ?? "League client")"
        case .demo: "Demo mode"
        }
    }

    var gameMode: GameMode {
        GameMode(mapId: mapId, queueId: queueId)
    }

    var localSlot: PlayerSlot? {
        if phase == .champSelect, let slot = champSelect.first(where: \.isLocalPlayer) { return slot }
        return lobby.flatMap { ($0.blue + $0.red).first(where: \.isLocalPlayer) }
    }

    /// The player's own row in the live game data.
    var activeLivePlayer: LivePlayer? {
        guard let live, let riotID = live.activePlayer?.riotId else { return nil }
        return live.allPlayers.first { $0.riotId == riotID }
    }

    var myChampionId: Int? {
        activeLivePlayer.flatMap { DataDragon.shared.championKey(live: $0) } ?? localSlot?.championId
    }

    var myPosition: MetaPosition? {
        MetaPosition(clientPosition: activeLivePlayer?.position.nonEmpty ?? localSlot?.position)
    }

    var laneOpponentLive: LivePlayer? {
        guard let me = activeLivePlayer, let position = me.position.nonEmpty else { return nil }
        return live?.allPlayers.first { $0.isBlueSide != me.isBlueSide && $0.position == position }
    }

    var laneOpponentChampion: Int? {
        if let opponent = laneOpponentLive { return DataDragon.shared.championKey(live: opponent) }
        guard let lobby, let position = myPosition else { return nil }
        let enemies = myTeamIsBlue ? lobby.red : lobby.blue
        return enemies.first { MetaPosition(clientPosition: $0.position) == position }?.championId
    }

    var allyChampions: [Int] {
        if let live, let me = activeLivePlayer {
            return live.allPlayers.filter { $0.isBlueSide == me.isBlueSide }.compactMap { DataDragon.shared.championKey(live: $0) }
        }
        if phase == .champSelect { return champSelect.compactMap(\.championId) }
        guard let lobby else { return [] }
        return (myTeamIsBlue ? lobby.blue : lobby.red).compactMap(\.championId)
    }

    var enemyChampions: [Int] {
        if let live, let me = activeLivePlayer {
            return live.allPlayers.filter { $0.isBlueSide != me.isBlueSide }.compactMap { DataDragon.shared.championKey(live: $0) }
        }
        if phase == .champSelect { return enemyChampSelect.compactMap(\.championId) }
        guard let lobby else { return [] }
        return (myTeamIsBlue ? lobby.red : lobby.blue).compactMap(\.championId)
    }

    /// The game clock right now. Live data arrives every ~2 s, so the time since the last poll is
    /// added on top (capped, so the clock stops if the game stops responding). In a preview the
    /// sample game's clock keeps running from when the preview started.
    func estimatedGameTime(at date: Date = Date()) -> Double {
        let base = live?.gameData?.gameTime ?? 0
        let elapsed = max(date.timeIntervalSince(liveReceivedAt), 0)
        return base + (status == .demo ? elapsed : min(elapsed, 5))
    }

    /// One page of a player's match history, most recent first.
    func fetchHistory(puuid: String, begin: Int, count: Int) async throws -> [LCUGame] {
        guard let client else { throw LocalAPIError.notConnected }
        let path = "/lol-match-history/v1/products/lol/\(puuid)/matches?begIndex=\(begin)&endIndex=\(begin + count - 1)"
        return try await client.get(path, as: LCUMatchHistory.self).games?.games?.compactMap(\.value) ?? []
    }

    /// A finished game with all ten players.
    func fetchGame(_ id: Int) async throws -> LCUGame {
        guard let client else { throw LocalAPIError.notConnected }
        return try await client.get("/lol-match-history/v1/games/\(id)", as: LCUGame.self)
    }

    /// Writes the popular rune page to the client. Called only after the user confirms.
    func applyRunes(_ page: OPRunePage, championName: String) async throws {
        guard let client else { throw LocalAPIError.noData }
        try await RunePageWriter(client: client).apply(page, championName: championName)
    }

    func insight(for slot: PlayerSlot) -> PlayerInsight? {
        guard let puuid = slot.puuid, case .loaded(let profile)? = profiles[puuid] else { return nil }
        return PlayerInsight(profile: profile, championId: slot.championId, mapId: mapId)
    }

    func premadeGroups(for teams: [[PlayerSlot]]) -> [String: Int] {
        var loaded: [String: PlayerProfile] = [:]
        for (puuid, load) in profiles {
            if case .loaded(let profile) = load { loaded[puuid] = profile }
        }
        return PremadeDetector.groups(teams: teams.map { $0.compactMap(\.puuid) }, profiles: loaded)
    }

    // MARK: - Lifecycle

    func start() {
        guard loop == nil else { return }
        status = .searching
        loop = Task { [weak self] in
            await DataDragon.shared.load()
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    enum DemoStage {
        case champSelect, inGame
    }

    func enterDemo(_ stage: DemoStage = .inGame) {
        stop()
        client = nil
        let demo = DemoData.scenario()
        status = .demo
        me = demo.me
        gameId = 1
        // Ranked hides teammates in champ select, so the draft preview is a normal draft.
        queueId = stage == .champSelect ? 400 : 420
        queueName = stage == .champSelect ? "Normal Draft" : "Ranked Solo/Duo"
        mapId = 11
        profiles = demo.profiles.mapValues { .loaded($0) }
        CooldownTracker.shared.resetIfNewGame(gameId)
        PostGameTracker.shared.summary = DemoData.postGameSummary()
        switch stage {
        case .champSelect:
            lobby = nil
            live = nil
            setPhase(.champSelect)  // clears the champ select lists, so fill them afterwards
            champSelect = demo.lobby.blue
            enemyChampSelect = demo.lobby.red.map {
                PlayerSlot(id: "enemy-\($0.id)", championId: $0.championId, isHidden: true)
            }
        case .inGame:
            champSelect = []
            enemyChampSelect = []
            lobby = demo.lobby
            live = demo.live
            liveReceivedAt = Date()
            setPhase(.inProgress)
        }
    }

    func exitDemo() {
        PostGameTracker.shared.summary = nil
        me = nil
        lobby = nil
        live = nil
        gameId = nil
        champSelect = []
        enemyChampSelect = []
        profiles = [:]
        queueId = nil
        queueName = nil
        mapId = nil
        setPhase(.idle)
        start()
    }

    /// Drops cached profiles for everyone on screen and fetches them again.
    func refreshProfiles() {
        guard status == .connected else { return }
        let visible = champSelect.compactMap(\.puuid) + (lobby.map { ($0.blue + $0.red).compactMap(\.puuid) } ?? [])
        for puuid in visible { profiles[puuid] = nil }
        visible.forEach(ensureProfile)
    }

    // MARK: - Polling

    private func tick() async {
        if client == nil, !(await connect()) { return }
        guard let client else { return }

        guard let raw = try? await client.get("/lol-gameflow/v1/gameflow-phase", as: String.self, timeout: 4) else {
            // One slow or failed request (the client is busy during games) shouldn't tear the
            // overlay down; only treat the client as gone after several in a row.
            phaseFailures += 1
            if phaseFailures >= 3 {
                disconnect()
            } else if phase.isInGame {
                await refreshLive(client)
            }
            return
        }
        phaseFailures = 0
        setPhase(GamePhase(raw: raw))

        switch phase {
        case .readyCheck:
            await handleReadyCheck(client)
        case .champSelect:
            await refreshChampSelect(client)
        case .gameStart, .inProgress, .reconnect:
            await refreshGame(client)
        default:
            break
        }
    }

    /// Poll as slowly as each phase allows: champ select changes quickly, queues and lobbies don't,
    /// and in game the overlay interpolates the clock between polls.
    private var pollInterval: Duration {
        guard client != nil else { return .seconds(4) }
        switch phase {
        case .champSelect: return .milliseconds(1500)
        case .gameStart, .inProgress, .reconnect: return .seconds(2)
        case .readyCheck: return .seconds(1)
        default: return .seconds(3)
        }
    }

    private func connect() async -> Bool {
        connectAttempts += 1
        // With League in /Applications its lockfile is enough; scanning processes (spawning `ps`)
        // is only a fallback for other install locations, and then only every 5th attempt.
        let installedInApplications = FileManager.default.fileExists(atPath: LCUCredentialsLocator.defaultInstallPath)
        let scan = !installedInApplications && connectAttempts % 5 == 1
        let credentials = await Task.detached(priority: .utility) { LCUCredentialsLocator.locate(scanProcesses: scan) }.value
        guard let credentials else {
            status = .searching
            return false
        }
        let candidate = LCUClient(credentials: credentials)
        // Fails until the user has logged in; we simply retry on the next tick.
        guard let summoner = await candidate.fetch("/lol-summoner/v1/current-summoner", as: LCUSummoner.self),
              summoner.puuid != nil else { return false }
        client = candidate
        me = summoner
        status = .connected
        return true
    }

    private func disconnect() {
        client = nil
        phaseFailures = 0
        status = .searching
        live = nil
        setPhase(.idle)
    }

    private func setPhase(_ newPhase: GamePhase) {
        guard newPhase != phase else { return }
        let oldPhase = phase
        // A new game: fetch its session right away instead of trusting last game's teams.
        if newPhase.isInGame && !oldPhase.isInGame {
            lastSessionFetch = .distantPast
            if status == .connected { Task { await PostGameTracker.shared.gameStarted() } }
        }
        // The game ended normally (not a dropped connection): summarize it once stats are in.
        if oldPhase.isInGame && [.preEndOfGame, .endOfGame, .waitingForStats].contains(newPhase), status == .connected {
            PostGameTracker.shared.gameEnded(gameId: gameId, queueId: queueId)
        }
        if newPhase == .readyCheck {
            readyCheckPendingSince = nil
            readyCheckAccepted = false
            if AppSettings.shared.notifyMatchFound && !GameWindow.isFrontmost {
                Notifier.post(title: "Match found", body: AppSettings.shared.autoAccept ? "Recall is accepting it for you." : "Accept it in League.", sound: true)
            }
        }
        phase = newPhase
        if newPhase == .champSelect {
            champSelect = []
            enemyChampSelect = []
            importedChampion = nil
            loadoutImport = .idle
            if status != .demo {
                queueId = nil
                mapId = nil
            }
        }
        if !newPhase.isInGame { live = nil }
        onPhaseChange?(newPhase)
    }

    @discardableResult
    private func refreshQueueInfo(_ client: LCUClient) async -> LCUGameflowSession? {
        guard let session = await client.fetch("/lol-gameflow/v1/session", as: LCUGameflowSession.self) else { return nil }
        let queue = session.gameData?.queue
        if let id = queue?.id, id != queueId { queueId = id }
        if let name = queue?.description.nonEmpty, name != queueName { queueName = name }
        if let map = session.map?.id ?? queue?.mapId, map != mapId { mapId = map }
        return session
    }

    private func refreshChampSelect(_ client: LCUClient) async {
        if queueId == nil { await refreshQueueInfo(client) }
        guard let session = await client.fetch("/lol-champ-select/v1/session", as: LCUChampSelectSession.self) else { return }

        let slots = (session.myTeam ?? []).enumerated().map { index, player in
            let isLocal = player.cellId == session.localPlayerCellId
            let hidden = player.nameVisibilityType == "HIDDEN" && !isLocal
            let puuid = hidden ? nil : player.puuid.nonEmpty
            return PlayerSlot(
                id: puuid ?? "cell-\(player.cellId ?? index)",
                puuid: puuid,
                championId: player.championId.nonZero ?? player.championPickIntent.nonZero,
                position: player.assignedPosition.nonEmpty,
                displayName: hidden ? "Teammate \(index + 1)" : Self.riotID(player.gameName, player.tagLine),
                isLocalPlayer: isLocal,
                isHidden: hidden
            )
        }
        if slots != champSelect { champSelect = slots }
        slots.compactMap(\.puuid).forEach(ensureProfile)

        let enemies = (session.theirTeam ?? []).enumerated().map { index, player in
            PlayerSlot(
                id: "enemy-\(player.cellId ?? index)",
                championId: player.championId.nonZero,
                position: player.assignedPosition.nonEmpty,
                isHidden: true
            )
        }
        if enemies != enemyChampSelect { enemyChampSelect = enemies }

        // Rune import: once you lock in. ARAM has no lock-in (champions are assigned, then
        // rerolled or swapped), so there it follows your current champion.
        // After lock-in, follow your current champion rather than the one you locked: a pick-order
        // trade changes it.
        let current = slots.first(where: \.isLocalPlayer)?.championId
        let lockedIn = gameMode == .aram || (session.actions ?? []).joined().compactMap(\.value).contains {
            $0.actorCellId == session.localPlayerCellId && $0.type == "pick" && $0.completed == true
        }
        let locked = lockedIn ? current : nil
        if let locked, locked != importedChampion, AppSettings.shared.importsLoadout {
            importedChampion = locked
            Task { await importLoadout(for: locked) }
        }
    }

    /// Puts the common rune page, item build and summoner spells for a champion into League,
    /// each only if its setting is on.
    func importLoadout(for champion: Int) async {
        let settings = AppSettings.shared
        let mode = gameMode
        guard mode.metaMode != nil, let client, let info = DataDragon.shared.champion(champion) else { return }
        loadoutImport = .importing(champion: info.name)
        let position = myPosition
        await MetaStore.shared.ensureChampion(champion, position, mode)
        guard let meta = MetaStore.shared.champion(champion, position, mode)?.value else {
            loadoutImport = .failed("No build data for \(info.name)")
            return
        }

        var parts: [String] = []
        var problems: [String] = []
        // A newer champion (ARAM swap, trade) may take over while this runs; stop writing if so.
        var superseded: Bool { importedChampion != champion }
        if superseded { return }
        if settings.autoImportRunes, let page = meta.runes, page.isComplete {
            do {
                try await RunePageWriter(client: client).apply(page, championName: info.name)
                parts.append("runes")
            } catch {
                problems.append("Runes: \(error.localizedDescription)")
            }
        }
        if superseded { return }
        if settings.importItemSets, let summonerId = me?.summonerId {
            do {
                try await ItemSetWriter(client: client).apply(meta, champion: info, position: position, mode: mode,
                                                              summonerId: summonerId, accountId: me?.accountId)
                parts.append("item build")
            } catch {
                problems.append("Items: \(error.localizedDescription)")
            }
        }
        if superseded { return }
        if settings.importSpells, let spells = meta.spells?.ids, spells.count == 2 {
            do {
                try await SpellWriter(client: client).apply(spells, flashOnF: settings.flashOnF)
                parts.append("spells")
            } catch {
                problems.append("Spells: \(error.localizedDescription)")
            }
        }
        guard !superseded else { return }
        loadoutImport = problems.isEmpty ? .imported(champion: info.name, parts: parts) : .failed(problems.joined(separator: " · "))
    }

    /// The ready-check popup: optionally accept it for you after a short pause (so you can still
    /// decline), never after you've answered it yourself.
    private func handleReadyCheck(_ client: LCUClient) async {
        guard AppSettings.shared.autoAccept else { return }
        guard let check = await client.fetch("/lol-matchmaking/v1/ready-check", as: LCUReadyCheck.self),
              check.state == "InProgress", check.playerResponse == "None" else {
            // Answered (by you or by us) or over: the next check starts its own 2 s wait.
            readyCheckPendingSince = nil
            readyCheckAccepted = false
            return
        }
        guard let since = readyCheckPendingSince else {
            readyCheckPendingSince = Date()
            return
        }
        guard !readyCheckAccepted, Date().timeIntervalSince(since) >= 2 else { return }
        readyCheckAccepted = true
        _ = try? await client.send("POST", "/lol-matchmaking/v1/ready-check/accept")
    }

    /// Resolves a Riot ID ("Name#TAG") to a PUUID through the client.
    func lookupPUUID(gameName: String, tagLine: String) async -> String? {
        guard let client else { return nil }
        let name = LCUClient.queryEscape(gameName)
        let tag = LCUClient.queryEscape(tagLine)
        if let summoner = await client.fetch("/lol-summoner/v1/alias/lookup?gameName=\(name)&tagLine=\(tag)", as: LCUSummoner.self),
           let puuid = summoner.puuid.nonEmpty {
            return puuid
        }
        // Older clients look players up by "Name#TAG" instead.
        let combined = LCUClient.queryEscape("\(gameName)#\(tagLine)")
        return await client.fetch("/lol-summoner/v1/summoners?name=\(combined)", as: LCUSummoner.self)?.puuid.nonEmpty
    }

    private func refreshGame(_ client: LCUClient) async {
        // The game session only matters until both teams are known; after that, ask the (busy)
        // client for it rarely and spend the in-game polls on live data.
        let teamsKnown = (lobby.map { $0.blue.count + $0.red.count } ?? 0) >= 10
        let sessionDue = !teamsKnown || Date().timeIntervalSince(lastSessionFetch) > 30
        if sessionDue, let data = await refreshQueueInfo(client)?.gameData, let id = data.gameId, id != 0 {
            lastSessionFetch = Date()
            if id != gameId {
                gameId = id
                lobby = nil
                resolvedRiotIDs = [:]
                attemptedRiotIDs = []
                CooldownTracker.shared.resetIfNewGame(id)
            }
            let picks = Dictionary(
                (data.playerChampionSelections ?? []).compactMap(\.value).compactMap { selection in
                    selection.puuid.nonEmpty.map { ($0, selection.championId ?? 0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            var teams = LobbyTeams(blue: slots(from: data.teamOne, picks: picks), red: slots(from: data.teamTwo, picks: picks))
            // Keep a side we filled from live game data if the client doesn't report it.
            if let existing = lobby {
                if teams.blue.isEmpty { teams.blue = existing.blue }
                if teams.red.isEmpty { teams.red = existing.red }
            }
            if !(teams.blue.isEmpty && teams.red.isEmpty), teams != lobby { lobby = teams }
        }

        if phase != .gameStart {
            await refreshLive(client)
        }

        if let lobby {
            (lobby.blue + lobby.red).compactMap(\.puuid).forEach(ensureProfile)
        }
    }

    private func refreshLive(_ client: LCUClient) async {
        let snapshot = await LiveClientAPI.allGameData()
        // Keep the last snapshot through a single missed poll so the overlay doesn't blink.
        if let snapshot {
            live = snapshot
            liveReceivedAt = Date()
            await fillMissingPlayers(from: snapshot, client: client)
        } else if Date().timeIntervalSince(liveReceivedAt) > 6 {
            live = nil
        }
    }

    private func slots(from players: [Lossy<LCUGameflowPlayer>]?, picks: [String: Int]) -> [PlayerSlot] {
        let slots = (players ?? []).compactMap(\.value).enumerated().map { index, player in
            let puuid = player.puuid.nonEmpty
            let champion = player.championId.nonZero ?? puuid.flatMap { picks[$0] }.nonZero
            return PlayerSlot(
                id: puuid ?? "slot-\(index)",
                puuid: puuid,
                championId: champion,
                position: player.selectedPosition.nonEmpty,
                displayName: Self.riotID(player.gameName, player.tagLine) ?? player.summonerName.nonEmpty,
                isLocalPlayer: puuid != nil && puuid == me?.puuid
            )
        }
        return Role.sorted(slots)
    }

    /// If the client didn't report a team (some queues hide it until the game loads), build it
    /// from the in-game player list and resolve each Riot ID to a PUUID through the client.
    private func fillMissingPlayers(from live: LiveGameData, client: LCUClient) async {
        var teams = lobby ?? LobbyTeams(blue: [], red: [])
        var changed = false
        for player in live.allPlayers {
            let side = player.isBlueSide ? teams.blue : teams.red
            let sideCount = live.allPlayers.filter { $0.isBlueSide == player.isBlueSide }.count
            let championKey = DataDragon.shared.championKey(live: player)
            if side.count >= sideCount || side.contains(where: { $0.championId != nil && $0.championId == championKey }) {
                continue
            }
            let puuid = await resolvePUUID(riotID: player.riotId, client: client)
            let slot = PlayerSlot(
                id: puuid ?? "live-\(player.id)",
                puuid: puuid,
                championId: championKey,
                position: player.position.nonEmpty,
                displayName: player.displayName,
                isLocalPlayer: player.riotId != nil && player.riotId == live.activePlayer?.riotId
            )
            if player.isBlueSide { teams.blue.append(slot) } else { teams.red.append(slot) }
            changed = true
        }
        if changed {
            teams.blue = Role.sorted(teams.blue)
            teams.red = Role.sorted(teams.red)
            lobby = teams
        }
    }

    private func resolvePUUID(riotID: String?, client: LCUClient) async -> String? {
        guard let riotID, let hash = riotID.lastIndex(of: "#") else { return nil }
        if let known = resolvedRiotIDs[riotID] { return known }
        guard attemptedRiotIDs.insert(riotID).inserted else { return nil }
        let name = LCUClient.queryEscape(String(riotID[..<hash]))
        let tag = LCUClient.queryEscape(String(riotID[riotID.index(after: hash)...]))
        let summoner = await client.fetch("/lol-summoner/v1/alias/lookup?gameName=\(name)&tagLine=\(tag)", as: LCUSummoner.self)
        let puuid = summoner?.puuid.nonEmpty
        if let puuid { resolvedRiotIDs[riotID] = puuid }
        return puuid
    }

    private func ensureProfile(_ puuid: String) {
        guard profiles[puuid] == nil, let client else { return }
        profiles[puuid] = .loading
        Task {
            do {
                profiles[puuid] = .loaded(try await ProfileLoader(client: client).load(puuid: puuid))
            } catch {
                profiles[puuid] = .failed(error.localizedDescription)
            }
        }
    }

    private static func riotID(_ name: String?, _ tag: String?) -> String? {
        guard let name = name.nonEmpty else { return nil }
        return tag.nonEmpty.map { "\(name)#\($0)" } ?? name
    }
}

enum Role {
    static func rank(_ position: String?) -> Int {
        switch position?.uppercased() {
        case "TOP": 0
        case "JUNGLE": 1
        case "MIDDLE", "MID": 2
        case "BOTTOM", "BOT": 3
        case "UTILITY", "SUPPORT": 4
        default: 5
        }
    }

    static func label(_ position: String?) -> String? {
        switch position?.uppercased() {
        case "TOP": "Top"
        case "JUNGLE": "Jungle"
        case "MIDDLE", "MID": "Mid"
        case "BOTTOM", "BOT": "Bot"
        case "UTILITY", "SUPPORT": "Support"
        default: nil
        }
    }

    /// Stable sort into Top → Support order; unknown roles keep their original order at the end.
    static func sorted(_ slots: [PlayerSlot]) -> [PlayerSlot] {
        slots.enumerated()
            .sorted { (rank($0.element.position), $0.offset) < (rank($1.element.position), $1.offset) }
            .map(\.element)
    }

    static func sorted(_ players: [LivePlayer]) -> [LivePlayer] {
        players.enumerated()
            .sorted { (rank($0.element.position), $0.offset) < (rank($1.element.position), $1.offset) }
            .map(\.element)
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

extension Optional where Wrapped == Int {
    var nonZero: Int? {
        guard let self, self != 0 else { return nil }
        return self
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
