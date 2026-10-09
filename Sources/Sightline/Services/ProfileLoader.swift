import Foundation

/// Builds a `PlayerProfile` from the League client's own endpoints, the same ones the
/// client's profile page uses. No Riot developer API key is required.
struct ProfileLoader {
    let client: LCUClient
    var historyCount = 20

    func load(puuid: String) async throws -> PlayerProfile {
        async let summonerRequest = client.fetch("/lol-summoner/v2/summoners/puuid/\(puuid)", as: LCUSummoner.self)
        async let rankedRequest = client.fetch("/lol-ranked/v1/ranked-stats/\(puuid)", as: LCURankedStats.self)
        async let historyRequest = client.fetch(
            "/lol-match-history/v1/products/lol/\(puuid)/matches?begIndex=0&endIndex=\(historyCount - 1)",
            as: LCUMatchHistory.self
        )

        let summoner = await summonerRequest
        async let masteryRequest = loadMastery(puuid: puuid, summonerId: summoner?.summonerId)

        let ranked = await rankedRequest
        let history = await historyRequest
        let mastery = await masteryRequest

        if summoner == nil && ranked == nil && history == nil {
            throw LocalAPIError.noData
        }

        return PlayerProfile(
            puuid: puuid,
            summoner: summoner,
            solo: Self.rank(ranked, queue: "RANKED_SOLO_5x5"),
            flex: Self.rank(ranked, queue: "RANKED_FLEX_SR"),
            matches: Self.summaries(from: history, puuid: puuid),
            mastery: mastery
        )
    }

    /// The mastery endpoint has moved between client versions; try the current one, then the older one.
    private func loadMastery(puuid: String, summonerId: Int?) async -> [Int: MasteryInfo]? {
        var entries = await client.fetch("/lol-champion-mastery/v1/\(puuid)/champion-mastery", as: [LCUMastery].self)
        if entries == nil, let summonerId {
            entries = await client.fetch("/lol-collections/v1/inventories/\(summonerId)/champion-mastery", as: [LCUMastery].self)
        }
        guard let entries else { return nil }
        return Dictionary(entries.map {
            ($0.championId, MasteryInfo(level: $0.championLevel ?? 0, points: $0.championPoints ?? 0))
        }, uniquingKeysWith: { first, _ in first })
    }

    static func rank(_ stats: LCURankedStats?, queue: String) -> RankInfo? {
        guard let entry = stats?.queueMap?[queue]?.value else { return nil }
        return RankInfo(
            tier: entry.tier ?? "",
            division: entry.division ?? "",
            leaguePoints: entry.leaguePoints ?? 0,
            wins: entry.wins ?? 0,
            losses: entry.losses ?? 0
        )
    }

    static func summaries(from history: LCUMatchHistory?, puuid: String) -> [MatchSummary] {
        let games = history?.games?.games?.compactMap(\.value) ?? []
        return games.compactMap { game -> MatchSummary? in
            guard let participant = game.participant(puuid: puuid),
                  let stats = participant.stats, let championId = participant.championId else {
                return nil
            }
            return MatchSummary(
                gameId: game.gameId,
                teamId: participant.teamId ?? 0,
                championId: championId,
                win: stats.win ?? false,
                kills: stats.kills ?? 0,
                deaths: stats.deaths ?? 0,
                assists: stats.assists ?? 0,
                cs: (stats.totalMinionsKilled ?? 0) + (stats.neutralMinionsKilled ?? 0),
                durationSeconds: game.gameDuration ?? 0,
                queueId: game.queueId,
                mapId: game.mapId,
                createdAt: Date(timeIntervalSince1970: Double(game.gameCreation ?? 0) / 1000),
                endedInRemake: stats.gameEndedInEarlySurrender ?? false
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}
