import Foundation

/// One player's line in a finished game.
struct HistoryPlayer: Identifiable, Hashable {
    let id: Int
    let puuid: String?
    let name: String?
    let championId: Int
    let teamId: Int
    let win: Bool
    let kills: Int
    let deaths: Int
    let assists: Int
    let cs: Int
    let gold: Int
    let damage: Int
    let vision: Int
    let level: Int
    /// Seven slots (the last is the trinket); 0 means empty.
    let items: [Int]
    let spells: [Int]
    let keystone: Int?
    let secondaryStyle: Int?

    var kda: Double { Double(kills + assists) / Double(max(deaths, 1)) }

    init(id: Int, puuid: String?, name: String?, championId: Int, teamId: Int, win: Bool,
         kills: Int, deaths: Int, assists: Int, cs: Int, gold: Int, damage: Int, vision: Int, level: Int,
         items: [Int], spells: [Int], keystone: Int?, secondaryStyle: Int?) {
        self.id = id
        self.puuid = puuid
        self.name = name
        self.championId = championId
        self.teamId = teamId
        self.win = win
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.cs = cs
        self.gold = gold
        self.damage = damage
        self.vision = vision
        self.level = level
        self.items = items
        self.spells = spells
        self.keystone = keystone
        self.secondaryStyle = secondaryStyle
    }

    init?(participant: LCUParticipant, identity: LCUParticipantIdentity.Player?) {
        guard let championId = participant.championId, let stats = participant.stats else { return nil }
        let riotID: String? = {
            if let name = identity?.gameName, !name.isEmpty {
                return identity?.tagLine.map { "\(name)#\($0)" } ?? name
            }
            return identity?.summonerName.flatMap { $0.isEmpty ? nil : $0 }
        }()
        self.init(
            id: participant.participantId ?? 0,
            puuid: identity?.puuid,
            name: riotID,
            championId: championId,
            teamId: participant.teamId ?? 0,
            win: stats.win ?? false,
            kills: stats.kills ?? 0,
            deaths: stats.deaths ?? 0,
            assists: stats.assists ?? 0,
            cs: (stats.totalMinionsKilled ?? 0) + (stats.neutralMinionsKilled ?? 0),
            gold: stats.goldEarned ?? 0,
            damage: stats.totalDamageDealtToChampions ?? 0,
            vision: stats.visionScore ?? 0,
            level: stats.champLevel ?? 0,
            items: stats.items,
            spells: [participant.spell1Id, participant.spell2Id].compactMap { $0 }.filter { $0 != 0 },
            keystone: stats.perk0.flatMap { $0 == 0 ? nil : $0 },
            secondaryStyle: stats.perkSubStyle.flatMap { $0 == 0 ? nil : $0 }
        )
    }
}

/// A game from the player's own history.
struct HistoryGame: Identifiable, Hashable {
    let gameId: Int
    let createdAt: Date
    let durationSeconds: Int
    let queueId: Int?
    let mapId: Int?
    let gameMode: String?
    let me: HistoryPlayer
    let endedInRemake: Bool

    var id: Int { gameId }
    var isRemake: Bool { endedInRemake || durationSeconds < 300 }
    var queueName: String { QueueNames.name(queueId, mode: gameMode) }
    var csPerMinute: Double { durationSeconds > 0 ? Double(me.cs) / (Double(durationSeconds) / 60) : 0 }

    init(gameId: Int, createdAt: Date, durationSeconds: Int, queueId: Int?, mapId: Int?, gameMode: String?,
         me: HistoryPlayer, endedInRemake: Bool = false) {
        self.gameId = gameId
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.queueId = queueId
        self.mapId = mapId
        self.gameMode = gameMode
        self.me = me
        self.endedInRemake = endedInRemake
    }

    init?(game: LCUGame, puuid: String) {
        guard let participant = game.participant(puuid: puuid),
              let me = HistoryPlayer(participant: participant, identity: game.identity(of: participant)) else { return nil }
        self.init(
            gameId: game.gameId,
            createdAt: Date(timeIntervalSince1970: Double(game.gameCreation ?? 0) / 1000),
            durationSeconds: game.gameDuration ?? 0,
            queueId: game.queueId,
            mapId: game.mapId,
            gameMode: game.gameMode,
            me: me,
            endedInRemake: participant.stats?.gameEndedInEarlySurrender ?? false
        )
    }
}

/// All ten players of one game, by team.
struct GameDetail {
    let players: [HistoryPlayer]

    var blue: [HistoryPlayer] { players.filter { $0.teamId == 100 } }
    var red: [HistoryPlayer] { players.filter { $0.teamId == 200 } }
    var maxDamage: Int { players.map(\.damage).max() ?? 0 }

    init(players: [HistoryPlayer]) {
        self.players = players
    }

    init(game: LCUGame) {
        players = (game.participants ?? []).compactMap { HistoryPlayer(participant: $0, identity: game.identity(of: $0)) }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All", ranked = "Ranked", normal = "Normal", aram = "ARAM", other = "Other"

    var id: String { rawValue }

    func matches(_ game: HistoryGame) -> Bool {
        switch self {
        case .all: true
        case .ranked: [420, 440].contains(game.queueId ?? -1)
        case .normal: [400, 430, 480, 490].contains(game.queueId ?? -1)
        case .aram: game.mapId == 12
        case .other: !(HistoryFilter.ranked.matches(game) || HistoryFilter.normal.matches(game) || HistoryFilter.aram.matches(game))
        }
    }
}

enum QueueNames {
    private static let names: [Int: String] = [
        0: "Custom", 400: "Normal Draft", 420: "Ranked Solo/Duo", 430: "Normal Blind", 440: "Ranked Flex",
        450: "ARAM", 480: "Swiftplay", 490: "Quickplay", 700: "Clash", 720: "ARAM Clash",
        830: "Co-op vs. AI", 840: "Co-op vs. AI", 850: "Co-op vs. AI", 870: "Co-op vs. AI", 880: "Co-op vs. AI",
        890: "Co-op vs. AI", 900: "ARURF", 1020: "One for All", 1300: "Nexus Blitz", 1700: "Arena", 1710: "Arena",
        1900: "URF", 2400: "ARAM: Mayhem",
    ]

    static func name(_ id: Int?, mode: String?) -> String {
        if let id, let name = names[id] { return name }
        return mode.map { $0.capitalized } ?? "Game"
    }
}

/// Totals across a set of games, remakes excluded.
struct HistorySummary {
    let games: Int
    let wins: Int
    let kda: Double?
    let csPerMinute: Double?
    let champions: [(champion: Int, games: Int, wins: Int)]

    init(_ history: [HistoryGame]) {
        let counted = history.filter { !$0.isRemake }
        games = counted.count
        wins = counted.filter(\.me.win).count
        let kills = counted.reduce(0) { $0 + $1.me.kills }
        let deaths = counted.reduce(0) { $0 + $1.me.deaths }
        let assists = counted.reduce(0) { $0 + $1.me.assists }
        kda = games > 0 ? Double(kills + assists) / Double(max(deaths, 1)) : nil
        let minutes = counted.reduce(0.0) { $0 + Double($1.durationSeconds) / 60 }
        csPerMinute = minutes > 0 ? Double(counted.reduce(0) { $0 + $1.me.cs }) / minutes : nil
        champions = Dictionary(grouping: counted, by: \.me.championId)
            .map { (champion: $0.key, games: $0.value.count, wins: $0.value.filter(\.me.win).count) }
            .sorted { $0.games > $1.games }
            .prefix(3)
            .map { $0 }
    }

    var winrate: Double? { games > 0 ? Double(wins) / Double(games) : nil }
}
