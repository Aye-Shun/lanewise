import Foundation

struct MatchSummary: Hashable {
    let gameId: Int
    let teamId: Int
    let championId: Int
    let win: Bool
    let kills: Int
    let deaths: Int
    let assists: Int
    let cs: Int
    let durationSeconds: Int
    let queueId: Int?
    let mapId: Int?
    let createdAt: Date
    let endedInRemake: Bool

    var isRemake: Bool { endedInRemake || durationSeconds < 300 }
}

struct RankInfo: Hashable {
    let tier: String       // "GOLD", "MASTER", ...
    let division: String   // "II", or "NA" for apex tiers
    let leaguePoints: Int
    let wins: Int
    let losses: Int

    var isRanked: Bool { !["", "NONE", "UNRANKED"].contains(tier) }
    var games: Int { wins + losses }
    var winrate: Double? { games > 0 ? Double(wins) / Double(games) : nil }

    private var isApex: Bool { ["MASTER", "GRANDMASTER", "CHALLENGER"].contains(tier) }

    var title: String {
        let name = tier.capitalized
        return isApex || division.isEmpty || division == "NA" ? name : "\(name) \(division)"
    }

    /// Compact form for the overlay, e.g. "G2", "E4", "GM".
    var shortTitle: String {
        let letters = ["IRON": "I", "BRONZE": "B", "SILVER": "S", "GOLD": "G", "PLATINUM": "P",
                       "EMERALD": "E", "DIAMOND": "D", "MASTER": "M", "GRANDMASTER": "GM", "CHALLENGER": "C"]
        let numbers = ["I": "1", "II": "2", "III": "3", "IV": "4"]
        let letter = letters[tier] ?? "?"
        return isApex ? letter : letter + (numbers[division] ?? "")
    }
}

struct MasteryInfo: Hashable {
    let level: Int
    let points: Int
}

struct PlayerProfile {
    let puuid: String
    let summoner: LCUSummoner?
    let solo: RankInfo?
    let flex: RankInfo?
    /// Most recent first.
    let matches: [MatchSummary]
    /// nil when the client didn't expose mastery for this player.
    let mastery: [Int: MasteryInfo]?

    var riotID: String? { summoner?.riotID }
    var level: Int? { summoner?.summonerLevel }
}

struct StatLine {
    var games = 0
    var wins = 0
    var kills = 0
    var deaths = 0
    var assists = 0

    init(_ matches: [MatchSummary]) {
        for match in matches {
            games += 1
            wins += match.win ? 1 : 0
            kills += match.kills
            deaths += match.deaths
            assists += match.assists
        }
    }

    var losses: Int { games - wins }
    var winrate: Double? { games > 0 ? Double(wins) / Double(games) : nil }
    var kda: Double? { games > 0 ? Double(kills + assists) / Double(max(deaths, 1)) : nil }
}

struct PlayerTag: Identifiable, Hashable {
    enum Tone { case good, bad, warning, info }

    let text: String
    let symbol: String
    let tone: Tone

    var id: String { text }
}

/// Everything shown on a player card, derived from a cached profile plus the
/// champion they're on right now (which can change during champ select).
struct PlayerInsight {
    let profile: PlayerProfile
    let championId: Int?
    let matches: [MatchSummary]
    let recent: StatLine
    let onChampion: StatLine
    let mastery: MasteryInfo?
    /// Positive = consecutive wins, negative = consecutive losses.
    let streak: Int
    /// Most-played champions in recent games: (champion, games, wins).
    let championPool: [(champion: Int, games: Int, wins: Int)]

    init(profile: PlayerProfile, championId: Int?, mapId: Int?) {
        self.profile = profile
        self.championId = championId

        // Same map only (don't let ARAM games skew Summoner's Rift stats), no remakes.
        let relevant = profile.matches.filter { match in
            !match.isRemake && (mapId == nil || match.mapId == nil || match.mapId == mapId)
        }
        matches = relevant
        recent = StatLine(relevant)
        onChampion = StatLine(relevant.filter { $0.championId == championId })
        mastery = championId.flatMap { profile.mastery?[$0] }

        var streak = 0
        if let first = relevant.first {
            for match in relevant {
                guard match.win == first.win else { break }
                streak += 1
            }
            if !first.win { streak = -streak }
        }
        self.streak = streak

        championPool = Dictionary(grouping: relevant, by: \.championId)
            .map { (champion: $0.key, games: $0.value.count, wins: $0.value.filter(\.win).count) }
            .sorted { $0.games > $1.games }
            .prefix(3)
            .map { $0 }
    }

    var tags: [PlayerTag] {
        var tags: [PlayerTag] = []

        if streak >= 3 {
            tags.append(PlayerTag(text: "\(streak) win streak", symbol: "flame.fill", tone: .good))
        } else if streak <= -3 {
            tags.append(PlayerTag(text: "\(-streak) loss streak", symbol: "snowflake", tone: .bad))
        }

        if championId != nil {
            if let mastery {
                if mastery.points >= 250_000 {
                    tags.append(PlayerTag(text: "Champion veteran", symbol: "crown.fill", tone: .good))
                } else if mastery.points < 1_500 {
                    tags.append(PlayerTag(text: "First time", symbol: "exclamationmark.triangle.fill", tone: .bad))
                }
            } else if profile.mastery != nil {
                // Mastery list loaded but this champion isn't in it: never played.
                tags.append(PlayerTag(text: "First time", symbol: "exclamationmark.triangle.fill", tone: .bad))
            } else if recent.games >= 10 && onChampion.games == 0 {
                tags.append(PlayerTag(text: "Off-champion", symbol: "questionmark.circle", tone: .warning))
            }

            if onChampion.games >= 6 && onChampion.games * 2 >= recent.games {
                tags.append(PlayerTag(text: "One-trick", symbol: "target", tone: .info))
            }
            if onChampion.games >= 5, let wr = onChampion.winrate, wr >= 0.65 {
                tags.append(PlayerTag(text: "Strong on champ", symbol: "bolt.fill", tone: .good))
            }
        }

        if recent.games >= 5, let kda = recent.kda, kda >= 4 {
            tags.append(PlayerTag(text: "High KDA", symbol: "scope", tone: .good))
        }

        if let level = profile.level, level < 60,
           let solo = profile.solo, solo.games >= 15, let wr = solo.winrate, wr >= 0.65 {
            tags.append(PlayerTag(text: "Possible smurf", symbol: "eye.trianglebadge.exclamationmark", tone: .warning))
        }

        if let last = profile.matches.first, last.createdAt < Date().addingTimeInterval(-30 * 86_400) {
            tags.append(PlayerTag(text: "Returning player", symbol: "clock.arrow.circlepath", tone: .info))
        }
        return tags
    }
}
