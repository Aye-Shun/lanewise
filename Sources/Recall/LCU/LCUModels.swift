import Foundation

// Decoding models for the LCU endpoints Recall uses. Every field is optional:
// the LCU is undocumented and Riot changes payloads between patches, so a missing
// field should degrade a stat, not fail the whole response.

/// Decodes an element if possible, otherwise yields nil instead of failing the array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Summoner

struct LCUSummoner: Decodable, Hashable {
    var puuid: String?
    var summonerId: Int?
    var gameName: String?
    var tagLine: String?
    var displayName: String?
    var summonerLevel: Int?
    var profileIconId: Int?
    var privacy: String?

    var riotID: String? {
        if let gameName, !gameName.isEmpty {
            if let tagLine, !tagLine.isEmpty { return "\(gameName)#\(tagLine)" }
            return gameName
        }
        return displayName.flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Ranked

struct LCURankedStats: Decodable {
    var queueMap: [String: Lossy<LCURankedQueue>]?
}

struct LCURankedQueue: Decodable {
    var tier: String?
    var division: String?
    var leaguePoints: Int?
    var wins: Int?
    var losses: Int?
}

// MARK: - Match history

struct LCUMatchHistory: Decodable {
    var games: Container?
    struct Container: Decodable {
        var games: [Lossy<LCUGame>]?
    }
}

struct LCUGame: Decodable {
    var gameId: Int
    var gameCreation: Int?
    var gameDuration: Int?
    var queueId: Int?
    var mapId: Int?
    var gameMode: String?
    var participants: [LCUParticipant]?
    var participantIdentities: [LCUParticipantIdentity]?

    /// A player's entry. History lists usually contain only the queried player, so a lone
    /// participant is taken as theirs.
    func participant(puuid: String) -> LCUParticipant? {
        let id = participantIdentities?.first { $0.player?.puuid == puuid }?.participantId
        return id.flatMap { id in participants?.first { $0.participantId == id } }
            ?? (participants?.count == 1 ? participants?.first : nil)
    }

    func identity(of participant: LCUParticipant) -> LCUParticipantIdentity.Player? {
        participantIdentities?.first { $0.participantId == participant.participantId }?.player
    }
}

struct LCUParticipant: Decodable {
    var participantId: Int?
    var championId: Int?
    var teamId: Int?
    var spell1Id: Int?
    var spell2Id: Int?
    var stats: Stats?

    struct Stats: Decodable {
        var win: Bool?
        var kills: Int?
        var deaths: Int?
        var assists: Int?
        var totalMinionsKilled: Int?
        var neutralMinionsKilled: Int?
        var gameEndedInEarlySurrender: Bool?
        var champLevel: Int?
        var goldEarned: Int?
        var totalDamageDealtToChampions: Int?
        var visionScore: Int?
        var item0: Int?
        var item1: Int?
        var item2: Int?
        var item3: Int?
        var item4: Int?
        var item5: Int?
        var item6: Int?
        /// Keystone rune.
        var perk0: Int?
        var perkSubStyle: Int?

        var items: [Int] { [item0, item1, item2, item3, item4, item5, item6].map { $0 ?? 0 } }
    }
}

struct LCUParticipantIdentity: Decodable {
    var participantId: Int?
    var player: Player?
    struct Player: Decodable {
        var puuid: String?
        var gameName: String?
        var tagLine: String?
        var summonerName: String?
    }
}

// MARK: - Champion mastery

struct LCUMastery: Decodable {
    var championId: Int
    var championLevel: Int?
    var championPoints: Int?
}

// MARK: - Champ select

struct LCUChampSelectSession: Decodable {
    var localPlayerCellId: Int?
    var myTeam: [LCUChampSelectPlayer]?
    var theirTeam: [LCUChampSelectPlayer]?
    /// Pick and ban turns, grouped by round. A completed "pick" by your cell is your lock-in.
    var actions: [[Lossy<LCUChampSelectAction>]]?
}

struct LCUChampSelectAction: Decodable {
    var actorCellId: Int?
    var championId: Int?
    var completed: Bool?
    var type: String?
}

struct LCUChampSelectPlayer: Decodable {
    var cellId: Int?
    var championId: Int?
    var championPickIntent: Int?
    var puuid: String?
    var assignedPosition: String?
    var gameName: String?
    var tagLine: String?
    /// "HIDDEN" in ranked queues. Recall respects this and does not look the player up.
    var nameVisibilityType: String?
}

// MARK: - Gameflow

struct LCUGameflowSession: Decodable {
    var gameData: GameData?
    var map: MapInfo?

    struct GameData: Decodable {
        var gameId: Int?
        var queue: Queue?
        var teamOne: [Lossy<LCUGameflowPlayer>]?
        var teamTwo: [Lossy<LCUGameflowPlayer>]?
        var playerChampionSelections: [Lossy<ChampionSelection>]?
    }

    struct Queue: Decodable {
        var id: Int?
        var description: String?
        var mapId: Int?
    }

    struct MapInfo: Decodable {
        var id: Int?
    }

    struct ChampionSelection: Decodable {
        var puuid: String?
        var championId: Int?
    }
}

struct LCUGameflowPlayer: Decodable {
    var puuid: String?
    var championId: Int?
    var summonerName: String?
    var gameName: String?
    var tagLine: String?
    var selectedPosition: String?
}

// MARK: - Rune pages

struct LCUPerkPage: Decodable {
    var id: Int
    var name: String?
    var isEditable: Bool?
    var isDeletable: Bool?
}

struct LCUPerkInventory: Decodable {
    var canAddCustomPage: Bool?
    var ownedPageCount: Int?
}
