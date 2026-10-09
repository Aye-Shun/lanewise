import Foundation

/// Riot's official in-game API, served by the game process on port 2999 while a match
/// is loaded. No authentication or API key is needed.
enum LiveClientAPI {
    static func allGameData() async -> LiveGameData? {
        guard let url = URL(string: "https://127.0.0.1:2999/liveclientdata/allgamedata") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.loopback.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(LiveGameData.self, from: data)
    }
}

struct LiveGameData: Decodable {
    var activePlayer: ActivePlayer?
    var allPlayers: [LivePlayer]
    var gameData: Info?

    struct ActivePlayer: Decodable {
        var riotId: String?
        var summonerName: String?
    }

    struct Info: Decodable {
        var gameMode: String?
        var gameTime: Double?
    }
}

struct LivePlayer: Decodable, Identifiable {
    var championName: String
    var rawChampionName: String?
    var riotId: String?
    var summonerName: String?
    /// "ORDER" (blue side) or "CHAOS" (red side).
    var team: String
    var level: Int?
    var position: String?
    var isDead: Bool?
    var respawnTimer: Double?
    var items: [LiveItem]
    var scores: LiveScores
    var summonerSpells: LiveSummonerSpells?

    var id: String { riotId ?? summonerName ?? championName }
    var displayName: String { riotId ?? summonerName ?? championName }
    var isBlueSide: Bool { team == "ORDER" }
}

struct LiveItem: Decodable, Identifiable {
    var itemID: Int
    var count: Int?
    var price: Int?
    var slot: Int
    var displayName: String?

    var id: Int { slot }
}

struct LiveScores: Decodable {
    var kills: Double?
    var deaths: Double?
    var assists: Double?
    var creepScore: Double?
    var wardScore: Double?
}

struct LiveSummonerSpells: Decodable {
    var summonerSpellOne: LiveSpell?
    var summonerSpellTwo: LiveSpell?

    var both: [LiveSpell?] { [summonerSpellOne, summonerSpellTwo] }
}

struct LiveSpell: Decodable {
    var displayName: String?
    /// e.g. `GeneratedTip_SummonerSpell_SummonerFlash_DisplayName`
    var rawDisplayName: String?

    /// The Data Dragon spell id, e.g. `SummonerFlash`.
    var spellID: String? {
        guard let raw = rawDisplayName,
              let start = raw.range(of: "SummonerSpell_"),
              let end = raw.range(of: "_DisplayName", range: start.upperBound..<raw.endIndex) else { return nil }
        return String(raw[start.upperBound..<end.lowerBound])
    }
}
