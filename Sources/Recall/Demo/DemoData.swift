import Foundation

/// Sample lobby used by Demo mode and snapshot rendering. Player names are fictional; champion,
/// item and spell ids are real so icons and OP.GG data load for them.
enum DemoData {
    struct Scenario {
        let me: LCUSummoner
        let lobby: LobbyTeams
        let profiles: [String: PlayerProfile]
        let live: LiveGameData
    }

    private struct Spec {
        let name: String
        let tag: String
        let champion: Int
        let championName: String
        let role: String
        let level: Int
        let icon: Int
        let tier: String
        let division: String
        let lp: Int
        let wins: Int
        let losses: Int
        let champShare: Double
        let recentWinRate: Double
        let streak: Int
        let mastery: (level: Int, points: Int)?
        let kdaBias: Int
        let spells: (String, String)
        let live: (kills: Int, deaths: Int, assists: Int, cs: Int, level: Int, items: [(Int, Int)])
    }

    private static let specs: [Spec] = [
        Spec(name: "Noxian Axe", tag: "TOP1", champion: 122, championName: "Darius", role: "TOP", level: 184, icon: 4,
             tier: "PLATINUM", division: "IV", lp: 38, wins: 61, losses: 55, champShare: 0.55, recentWinRate: 0.55, streak: 0,
             mastery: (7, 142_000), kdaBias: 0, spells: ("Flash", "Teleport"),
             live: (2, 1, 1, 121, 11, [(3071, 3000), (3047, 1100), (1054, 450)])),
        Spec(name: "Insec Pending", tag: "LEE", champion: 64, championName: "Lee Sin", role: "JUNGLE", level: 402, icon: 7,
             tier: "EMERALD", division: "III", lp: 71, wins: 88, losses: 79, champShare: 0.8, recentWinRate: 0.6, streak: 1,
             mastery: (10, 612_000), kdaBias: 1, spells: ("Flash", "Smite"),
             live: (4, 2, 6, 88, 10, [(6692, 3000), (3158, 900), (1036, 350)])),
        Spec(name: "Moonlit Fox", tag: "NA1", champion: 103, championName: "Ahri", role: "MIDDLE", level: 213, icon: 18,
             tier: "GOLD", division: "I", lp: 54, wins: 64, losses: 52, champShare: 0.45, recentWinRate: 0.6, streak: 4,
             mastery: (8, 187_000), kdaBias: 1, spells: ("Flash", "Ignite"),
             live: (5, 1, 4, 138, 12, [(3118, 2700), (3020, 1100), (1058, 1200), (1056, 400)])),
        Spec(name: "Get Excited", tag: "BOOM", champion: 222, championName: "Jinx", role: "BOTTOM", level: 156, icon: 12,
             tier: "GOLD", division: "II", lp: 12, wins: 40, losses: 37, champShare: 0.5, recentWinRate: 0.52, streak: 0,
             mastery: (7, 98_000), kdaBias: 0, spells: ("Flash", "Heal"),
             live: (3, 2, 3, 129, 10, [(3032, 2800), (3006, 1100), (1055, 450), (1037, 875)])),
        Spec(name: "Lantern Please", tag: "HOOK", champion: 412, championName: "Thresh", role: "UTILITY", level: 297, icon: 23,
             tier: "GOLD", division: "III", lp: 77, wins: 51, losses: 49, champShare: 0.6, recentWinRate: 0.5, streak: 0,
             mastery: (9, 214_000), kdaBias: 0, spells: ("Flash", "Ignite"),
             live: (0, 3, 11, 21, 8, [(3190, 2200), (3009, 1000), (2055, 75)])),
        Spec(name: "Demacia Daily", tag: "SPIN", champion: 86, championName: "Garen", role: "TOP", level: 121, icon: 25,
             tier: "SILVER", division: "I", lp: 90, wins: 70, losses: 61, champShare: 0.7, recentWinRate: 0.53, streak: 0,
             mastery: (12, 402_000), kdaBias: 0, spells: ("Flash", "Ghost"),
             live: (1, 2, 0, 112, 10, [(3078, 3333), (3111, 1250)])),
        Spec(name: "Ruined King", tag: "VGO", champion: 234, championName: "Viego", role: "JUNGLE", level: 265, icon: 28,
             tier: "PLATINUM", division: "II", lp: 33, wins: 58, losses: 66, champShare: 0.4, recentWinRate: 0.35, streak: -4,
             mastery: (6, 64_000), kdaBias: -1, spells: ("Flash", "Smite"),
             live: (1, 4, 2, 76, 9, [(3153, 3200), (3006, 1100)])),
        Spec(name: "Windwall", tag: "YAS", champion: 157, championName: "Yasuo", role: "MIDDLE", level: 41, icon: 9,
             tier: "DIAMOND", division: "IV", lp: 15, wins: 52, losses: 21, champShare: 0.55, recentWinRate: 0.75, streak: 2,
             mastery: (6, 71_000), kdaBias: 2, spells: ("Flash", "Ignite"),
             live: (6, 1, 1, 145, 12, [(3046, 2650), (3006, 1100), (1055, 450), (1018, 600)])),
        Spec(name: "Void Hunter", tag: "KSA", champion: 145, championName: "Kai'Sa", role: "BOTTOM", level: 188, icon: 14,
             tier: "PLATINUM", division: "III", lp: 61, wins: 47, losses: 44, champShare: 0.35, recentWinRate: 0.5, streak: 0,
             mastery: (7, 120_000), kdaBias: 0, spells: ("Flash", "Barrier"),
             live: (2, 3, 2, 118, 10, [(6672, 3000), (3006, 1100), (1055, 450)])),
        Spec(name: "Anchor Down", tag: "NAUT", champion: 111, championName: "Nautilus", role: "UTILITY", level: 143, icon: 20,
             tier: "GOLD", division: "IV", lp: 0, wins: 33, losses: 36, champShare: 0.0, recentWinRate: 0.45, streak: 0,
             mastery: nil, kdaBias: -1, spells: ("Flash", "Ignite"),
             live: (0, 2, 4, 18, 7, [(3047, 1100), (2055, 75)])),
    ]

    /// Pairs that queued together; the second player's recent games mirror the first's.
    private static let duos = [(3, 4), (8, 9)]

    private static let championPool = [266, 103, 222, 412, 64, 122, 99, 145, 89, 234, 157, 61, 86, 81, 111, 104, 238, 517, 875, 887]

    private static let spellIDs = [
        "Flash": "SummonerFlash", "Teleport": "SummonerTeleport", "Smite": "SummonerSmite", "Ignite": "SummonerDot",
        "Heal": "SummonerHeal", "Ghost": "SummonerHaste", "Barrier": "SummonerBarrier",
    ]

    @MainActor
    static func scenario() -> Scenario {
        var rng = SeededGenerator(seed: 42)
        let now = Date()
        var matchesByIndex: [[MatchSummary]] = []

        for (index, spec) in specs.enumerated() {
            var matches: [MatchSummary] = []
            for game in 0..<20 {
                let win: Bool
                if game < abs(spec.streak) {
                    win = spec.streak > 0
                } else if game == abs(spec.streak) && spec.streak != 0 {
                    win = spec.streak < 0   // the game that started the streak
                } else {
                    win = Double.random(in: 0..<1, using: &rng) < spec.recentWinRate
                }
                let onChampion = Double.random(in: 0..<1, using: &rng) < spec.champShare
                let deaths = Int.random(in: 1...8, using: &rng) - (spec.kdaBias > 0 ? 1 : 0)
                matches.append(MatchSummary(
                    gameId: 7_000_000 + index * 100 + game,
                    teamId: Bool.random(using: &rng) ? 100 : 200,
                    championId: onChampion ? spec.champion : championPool.randomElement(using: &rng)!,
                    win: win,
                    kills: max(Int.random(in: 0...9, using: &rng) + spec.kdaBias * 2, 0),
                    deaths: max(deaths, 0),
                    assists: Int.random(in: 2...12, using: &rng),
                    cs: Int.random(in: 120...260, using: &rng),
                    durationSeconds: Int.random(in: 1300...2200, using: &rng),
                    queueId: 420,
                    mapId: 11,
                    createdAt: now.addingTimeInterval(-Double(game + 1) * 5 * 3600),
                    endedInRemake: false
                ))
            }
            matchesByIndex.append(matches)
        }

        for (lead, partner) in duos {
            for game in 0..<6 {
                let shared = matchesByIndex[lead][game]
                let own = matchesByIndex[partner][game]
                matchesByIndex[partner][game] = MatchSummary(
                    gameId: shared.gameId, teamId: shared.teamId, championId: own.championId, win: shared.win,
                    kills: own.kills, deaths: own.deaths, assists: own.assists, cs: own.cs,
                    durationSeconds: shared.durationSeconds, queueId: 420, mapId: 11,
                    createdAt: shared.createdAt, endedInRemake: false
                )
            }
        }

        var profiles: [String: PlayerProfile] = [:]
        var slots: [PlayerSlot] = []
        var livePlayers: [LivePlayer] = []

        for (index, spec) in specs.enumerated() {
            let puuid = "demo-\(index)"
            let summoner = LCUSummoner(puuid: puuid, gameName: spec.name, tagLine: spec.tag,
                                       summonerLevel: spec.level, profileIconId: spec.icon)
            var mastery = [Int: MasteryInfo]()
            for other in championPool where other != spec.champion {
                mastery[other] = MasteryInfo(level: 5, points: 30_000 + other * 97)
            }
            if let own = spec.mastery {
                mastery[spec.champion] = MasteryInfo(level: own.level, points: own.points)
            }
            profiles[puuid] = PlayerProfile(
                puuid: puuid,
                summoner: summoner,
                solo: RankInfo(tier: spec.tier, division: spec.division, leaguePoints: spec.lp, wins: spec.wins, losses: spec.losses),
                flex: index % 3 == 0 ? RankInfo(tier: "GOLD", division: "II", leaguePoints: 20, wins: 14, losses: 11) : nil,
                matches: matchesByIndex[index],
                mastery: mastery
            )
            slots.append(PlayerSlot(id: puuid, puuid: puuid, championId: spec.champion, position: spec.role,
                                    displayName: "\(spec.name)#\(spec.tag)", isLocalPlayer: index == 2))

            let rawName = DataDragon.shared.champion(spec.champion)?.id ?? spec.championName
            livePlayers.append(LivePlayer(
                championName: spec.championName,
                rawChampionName: "game_character_displayname_\(rawName)",
                riotId: "\(spec.name)#\(spec.tag)",
                team: index < 5 ? "ORDER" : "CHAOS",
                level: spec.live.level,
                position: spec.role,
                isDead: index == 6,
                respawnTimer: index == 6 ? 18 : 0,
                items: spec.live.items.enumerated().map { slot, item in
                    LiveItem(itemID: item.0, count: 1, price: item.1, slot: slot)
                } + [LiveItem(itemID: index % 5 == 4 ? 3364 : 3340, count: 1, price: 0, slot: 6)],
                scores: LiveScores(kills: Double(spec.live.kills), deaths: Double(spec.live.deaths),
                                   assists: Double(spec.live.assists), creepScore: Double(spec.live.cs), wardScore: 9),
                summonerSpells: LiveSummonerSpells(
                    summonerSpellOne: spell(spec.spells.0),
                    summonerSpellTwo: spell(spec.spells.1)
                )
            ))
        }

        let me = specs[2]
        return Scenario(
            me: LCUSummoner(puuid: "demo-2", gameName: me.name, tagLine: me.tag, summonerLevel: me.level, profileIconId: me.icon),
            lobby: LobbyTeams(blue: Array(slots[0..<5]), red: Array(slots[5..<10])),
            profiles: profiles,
            live: LiveGameData(
                activePlayer: .init(riotId: "\(me.name)#\(me.tag)"),
                allPlayers: livePlayers,
                gameData: .init(gameMode: "CLASSIC", gameTime: 872)
            )
        )
    }

    // MARK: - Match history

    private static let mageItems = [3118, 3020, 4645, 3157, 3089, 3135, 3165, 6655]
    private static let marksmanItems = [6672, 3006, 3031, 3036, 3046, 3072, 3094, 3085]
    private static let fighterItems = [3071, 3047, 3053, 6333, 3065, 3075, 3143, 3742]

    @MainActor
    private static func items(for champion: Int, minutes: Int, rng: inout SeededGenerator) -> [Int] {
        let tags = DataDragon.shared.champion(champion)?.tags ?? []
        let pool = tags.contains("Mage") ? mageItems : tags.contains("Marksman") ? marksmanItems : fighterItems
        let count = min(max(minutes / 6, 2), 6)
        var slots = Array(pool.shuffled(using: &rng).prefix(count))
        slots += Array(repeating: 0, count: 6 - slots.count)
        return slots + [3340]
    }

    /// The sample player's recent games, built from the same seeded matches the Players screen uses.
    @MainActor
    static func history() -> [HistoryGame] {
        guard let matches = scenario().profiles["demo-2"]?.matches else { return [] }
        var rng = SeededGenerator(seed: 7)
        return matches.enumerated().map { index, match in
            let aram = index % 7 == 3
            let queue = aram ? 450 : (index % 5 == 4 ? 440 : 420)
            let minutes = match.durationSeconds / 60
            let me = HistoryPlayer(
                id: 1, puuid: "demo-2", name: "Moonlit Fox#NA1", championId: match.championId, teamId: match.teamId,
                win: match.win, kills: match.kills, deaths: match.deaths, assists: match.assists, cs: match.cs,
                gold: 300 * minutes + Int.random(in: 0...2500, using: &rng),
                damage: 600 * minutes + Int.random(in: 0...9000, using: &rng),
                vision: Int.random(in: 8...40, using: &rng), level: min(6 + minutes / 3, 18),
                items: items(for: match.championId, minutes: minutes, rng: &rng),
                spells: aram ? [4, 32] : [4, 14], keystone: 8112, secondaryStyle: 8200
            )
            return HistoryGame(gameId: match.gameId, createdAt: match.createdAt, durationSeconds: match.durationSeconds,
                               queueId: queue, mapId: aram ? 12 : 11, gameMode: aram ? "ARAM" : "CLASSIC", me: me)
        }
    }

    /// Ten sample players for a history game, with the sample player on their real team.
    @MainActor
    static func gameDetail(for game: HistoryGame) -> GameDetail {
        var rng = SeededGenerator(seed: UInt64(game.gameId))
        let minutes = game.durationSeconds / 60
        var champions = championPool.filter { $0 != game.me.championId }.shuffled(using: &rng)
        let others = specs.enumerated().filter { $0.offset != 2 }.map { "\($0.element.name)#\($0.element.tag)" }.shuffled(using: &rng)
        let enemyTeam = game.me.teamId == 100 ? 200 : 100
        var players = [game.me]
        for (index, name) in others.prefix(9).enumerated() {
            let team = index < 4 ? game.me.teamId : enemyTeam
            let champion = champions.removeFirst()
            players.append(HistoryPlayer(
                id: index + 2, puuid: nil, name: name, championId: champion, teamId: team,
                win: team == game.me.teamId ? game.me.win : !game.me.win,
                kills: Int.random(in: 0...12, using: &rng), deaths: Int.random(in: 1...9, using: &rng),
                assists: Int.random(in: 1...15, using: &rng), cs: Int.random(in: 2...9, using: &rng) * minutes + 10,
                gold: 280 * minutes + Int.random(in: 0...3000, using: &rng),
                damage: 500 * minutes + Int.random(in: 0...12000, using: &rng),
                vision: Int.random(in: 5...60, using: &rng), level: min(5 + minutes / 3, 18),
                items: items(for: champion, minutes: minutes, rng: &rng), spells: [4, 14], keystone: nil, secondaryStyle: nil
            ))
        }
        return GameDetail(players: players)
    }

    private static func spell(_ name: String) -> LiveSpell {
        LiveSpell(displayName: name, rawDisplayName: "GeneratedTip_SummonerSpell_\(spellIDs[name] ?? name)_DisplayName")
    }

    /// Every remote image the demo screens show, so snapshots can pre-warm the cache.
    @MainActor
    static func imageURLs() -> [URL] {
        let dragon = DataDragon.shared
        var urls: [URL] = []
        for spec in specs {
            urls += [dragon.championIcon(spec.champion), dragon.profileIcon(spec.icon)].compactMap { $0 }
            urls += spec.live.items.compactMap { dragon.itemIcon($0.0) }
        }
        urls += [3340, 3364].compactMap { dragon.itemIcon($0) }
        urls += championPool.compactMap { dragon.championIcon($0) }
        urls += [4, 12, 11, 14, 7, 6, 21].compactMap { dragon.spellIcon(dragon.spell($0)) }
        return urls
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
