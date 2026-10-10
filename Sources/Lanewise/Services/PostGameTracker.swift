import Foundation
import Observation

/// How the last game went: LP change and your numbers against your recent average.
struct PostGameSummary {
    let game: HistoryGame
    /// LP gained or lost, counting division changes as 100 LP (nil for unranked games).
    let lpChange: Int?
    let rankAfter: RankInfo?
    /// "Promoted to Gold I" / "Demoted to Silver I" when the division changed.
    let promotion: String?
    let averageKDA: Double?
    let averageCSPerMinute: Double?
    let averageDamagePerMinute: Double?

    var damagePerMinute: Double {
        game.durationSeconds > 0 ? Double(game.me.damage) / (Double(game.durationSeconds) / 60) : 0
    }
}

/// Snapshots your rank when a game starts; after it ends, waits for the game to reach your match
/// history (and for LP to update), then builds a `PostGameSummary` and optionally notifies you.
@Observable @MainActor
final class PostGameTracker {
    static let shared = PostGameTracker()

    var summary: PostGameSummary?
    @ObservationIgnored private var rankBefore: (solo: RankInfo?, flex: RankInfo?)?
    @ObservationIgnored private var tracking: Task<Void, Never>?

    func gameStarted() async {
        rankBefore = await currentRanks()
    }

    func gameEnded(gameId: Int?, queueId: Int?) {
        guard let gameId else { return }
        let before = rankBefore
        tracking?.cancel()
        tracking = Task { await track(gameId: gameId, queueId: queueId, before: before) }
    }

    private func track(gameId: Int, queueId: Int?, before: (solo: RankInfo?, flex: RankInfo?)?) async {
        let rankedQueue: Bool? = queueId == 420 ? true : queueId == 440 ? false : nil  // true = solo
        let rankBefore = rankedQueue.flatMap { $0 ? before?.solo : before?.flex }
        let history = MatchHistoryStore.shared
        var game: HistoryGame?
        var rankAfter: RankInfo?

        // Stats usually land within a minute; LP can take a little longer. Give up after ~2 min.
        for attempt in 0..<24 {
            if Task.isCancelled { return }
            if game == nil {
                await history.refreshLatest()
                game = history.games.first { $0.gameId == gameId }
            }
            if let solo = rankedQueue, rankBefore != nil, rankAfter == nil {
                let now = await currentRanks()
                let current = solo ? now?.solo : now?.flex
                if let current, current != rankBefore { rankAfter = current }
            }
            let rankSettled = rankedQueue == nil || rankBefore == nil || rankAfter != nil || attempt >= 12
            if game != nil && rankSettled { break }
            try? await Task.sleep(for: .seconds(5))
        }
        guard let game, !game.isRemake else { return }

        let others = history.games.filter { $0.gameId != gameId && !$0.isRemake }
        let recent = HistorySummary(others)
        let minutes = others.reduce(0.0) { $0 + Double($1.durationSeconds) / 60 }
        let damage = others.reduce(0) { $0 + $1.me.damage }

        var lpChange: Int?
        var promotion: String?
        if let before = rankBefore, let after = rankAfter, let a = Self.ladderPoints(before), let b = Self.ladderPoints(after) {
            lpChange = b - a
            if before.tier != after.tier || before.division != after.division {
                promotion = "\(b > a ? "Promoted" : "Demoted") to \(after.title)"
            }
        }

        let result = PostGameSummary(
            game: game, lpChange: lpChange, rankAfter: rankAfter, promotion: promotion,
            averageKDA: recent.kda, averageCSPerMinute: recent.csPerMinute,
            averageDamagePerMinute: minutes > 0 ? Double(damage) / minutes : nil
        )
        summary = result
        if AppSettings.shared.notifyPostGame { notify(result) }
    }

    private func notify(_ summary: PostGameSummary) {
        let game = summary.game
        let champion = DataDragon.shared.champion(game.me.championId)?.name ?? "your champion"
        var parts: [String] = []
        if let lp = summary.lpChange { parts.append("\(lp >= 0 ? "+" : "−")\(abs(lp)) LP") }
        if let promotion = summary.promotion { parts.append(promotion) }
        parts.append("\(game.me.kills)/\(game.me.deaths)/\(game.me.assists)")
        parts.append(String(format: "%.1f CS/min", game.csPerMinute))
        if let average = summary.averageCSPerMinute { parts.append(String(format: "(avg %.1f)", average)) }
        Notifier.post(title: "\(game.me.win ? "Victory" : "Defeat") · \(champion)", body: parts.joined(separator: " · "))
    }

    private func currentRanks() async -> (solo: RankInfo?, flex: RankInfo?)? {
        guard let client = GameMonitor.shared.lcu, let puuid = GameMonitor.shared.me?.puuid,
              let stats = await client.fetch("/lol-ranked/v1/ranked-stats/\(puuid)", as: LCURankedStats.self) else { return nil }
        return (ProfileLoader.rank(stats, queue: "RANKED_SOLO_5x5"), ProfileLoader.rank(stats, queue: "RANKED_FLEX_SR"))
    }

    /// Position on the ladder: 100 LP per division below Master, plain LP from Master up.
    static func ladderPoints(_ rank: RankInfo) -> Int? {
        let tiers = ["IRON", "BRONZE", "SILVER", "GOLD", "PLATINUM", "EMERALD", "DIAMOND", "MASTER", "GRANDMASTER", "CHALLENGER"]
        guard let tier = tiers.firstIndex(of: rank.tier) else { return nil }
        if tier >= 7 { return 7 * 400 + rank.leaguePoints }
        let division = ["IV": 0, "III": 1, "II": 2, "I": 3][rank.division] ?? 0
        return tier * 400 + division * 100 + rank.leaguePoints
    }
}
