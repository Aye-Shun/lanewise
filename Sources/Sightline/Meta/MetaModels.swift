import Foundation

// Codable shapes for OP.GG payloads. The champion-analysis tool returns single objects
// (`runes`, `boots`, ...) while the matchup guide returns arrays of the same shapes, so those
// fields decode through `OneOrMany`.

struct OneOrMany<T: Decodable>: Decodable {
    let values: [T]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([Lossy<T>].self) {
            values = many.compactMap(\.value)
        } else if let one = try? container.decode(T.self) {
            values = [one]
        } else {
            values = []
        }
    }
}

struct OPStat {
    static func rate(win: Int?, play: Int?) -> Double? {
        guard let win, let play, play > 0 else { return nil }
        return Double(win) / Double(play)
    }
}

struct OPItemSet: Decodable, Hashable {
    var ids: [Int]?
    var play: Int?
    var win: Int?
    var pickRate: Double?

    var items: [Int] { ids ?? [] }
    var winRate: Double? { OPStat.rate(win: win, play: play) }
}

struct OPRunePage: Decodable, Hashable {
    var id: Int?
    var primaryPageId: Int?
    var primaryRuneIds: [Int]?
    var secondaryPageId: Int?
    var secondaryRuneIds: [Int]?
    var statModIds: [Int]?
    var play: Int?
    var win: Int?
    var pickRate: Double?

    var winRate: Double? { OPStat.rate(win: win, play: play) }
    var keystone: Int? { primaryRuneIds?.first }
    var allPerkIDs: [Int] { (primaryRuneIds ?? []) + (secondaryRuneIds ?? []) + (statModIds ?? []) }
    var isComplete: Bool { primaryPageId != nil && secondaryPageId != nil && allPerkIDs.count == 9 }
}

struct OPSpellSet: Decodable, Hashable {
    var ids: [Int]?
    var play: Int?
    var win: Int?
    var pickRate: Double?
}

struct OPSkills: Decodable, Hashable {
    /// Level-by-level skill order ("Q", "W", "E", "R", ...).
    var order: [String]?
    var pickRate: Double?
}

struct OPSkillMasteries: Decodable, Hashable {
    /// Max order, e.g. ["Q", "W", "E"].
    var ids: [String]?
    var pickRate: Double?
}

struct OPCounter: Decodable, Hashable {
    var championId: Int?
    var championName: String?
    var myWinRate: Double?
    var counterWinRate: Double?
    var play: Int?
}

struct OPRawCounter: Decodable, Hashable {
    var championId: Int?
    var championName: String?
    var play: Int?
    var win: Int?
}

struct OPSynergy: Decodable, Hashable {
    var championId: Int?
    var synergyChampionId: Int?
    var synergyChampionName: String?
    var winRate: Double?
    var play: Int?
    var scoreRank: Int?
}

struct OPSynergies: Decodable, Hashable {
    var adc: [OPSynergy]?
    var support: [OPSynergy]?
}

struct OPAverageStats: Decodable, Hashable {
    var play: Int?
    var winRate: Double?
    var pickRate: Double?
    var banRate: Double?
    var tier: Int?
    var rank: Int?
}

struct OPSummary: Decodable {
    var averageStats: OPAverageStats?
    var positions: [Position]?

    struct Position: Decodable {
        var counters: [Lossy<OPRawCounter>]?
    }
}

struct OPAnalysisData: Decodable {
    var summary: OPSummary?
    var damageType: String?
    var runes: OneOrMany<OPRunePage>?
    var starterItems: OneOrMany<OPItemSet>?
    var coreItems: OneOrMany<OPItemSet>?
    var boots: OneOrMany<OPItemSet>?
    var fourthItems: OneOrMany<OPItemSet>?
    var fifthItems: OneOrMany<OPItemSet>?
    var sixthItems: OneOrMany<OPItemSet>?
    var summonerSpells: OneOrMany<OPSpellSet>?
    var skills: OneOrMany<OPSkills>?
    var skillMasteries: OneOrMany<OPSkillMasteries>?
    var weakCounters: [Lossy<OPCounter>]?
    var strongCounters: [Lossy<OPCounter>]?
    var synergies: OPSynergies?
}

struct OPResponse: Decodable {
    var data: OPAnalysisData?
}

// MARK: - Domain models

enum DamageType: String {
    case ad = "AD", ap = "AP", hybrid = "BOTH"
}

/// Popular data for one champion in one role and mode.
struct ChampionMeta {
    var winRate: Double?
    var pickRate: Double?
    var banRate: Double?
    var tier: Int?
    var damageType: DamageType?
    var runes: OPRunePage?
    var starter: OPItemSet?
    var core: OPItemSet?
    var boots: OPItemSet?
    var fourth: [OPItemSet] = []
    var fifth: [OPItemSet] = []
    var sixth: [OPItemSet] = []
    var spells: OPSpellSet?
    var skillOrder: [String] = []
    var skillMaxOrder: [String] = []
    /// Champions that beat this one (good ban ideas), hardest first.
    var hardestMatchups: [OPCounter] = []
    var synergies: OPSynergies?

    init(_ data: OPAnalysisData) {
        let stats = data.summary?.averageStats
        winRate = stats?.winRate
        pickRate = stats?.pickRate
        banRate = stats?.banRate
        tier = stats?.tier
        damageType = data.damageType.flatMap(DamageType.init(rawValue:))
        runes = data.runes?.values.first
        starter = data.starterItems?.values.first
        core = data.coreItems?.values.first
        boots = data.boots?.values.first
        fourth = data.fourthItems?.values ?? []
        fifth = data.fifthItems?.values ?? []
        sixth = data.sixthItems?.values ?? []
        spells = data.summonerSpells?.values.first
        skillOrder = data.skills?.values.first?.order ?? []
        skillMaxOrder = data.skillMasteries?.values.first?.ids ?? []
        // OP.GG's curated counters can be short; top up from the raw matchup table, keeping
        // only matchups with a meaningful sample.
        var counters = (data.weakCounters ?? []).compactMap(\.value)
        let raw = (data.summary?.positions ?? []).flatMap { ($0.counters ?? []).compactMap(\.value) }
        for entry in raw where (entry.play ?? 0) >= 50 && !counters.contains(where: { $0.championId == entry.championId }) {
            counters.append(OPCounter(championId: entry.championId, championName: entry.championName,
                                      myWinRate: OPStat.rate(win: entry.win, play: entry.play), play: entry.play))
        }
        hardestMatchups = counters
            .filter { ($0.myWinRate ?? 1) < 0.5 }
            .sorted { ($0.myWinRate ?? 1) < ($1.myWinRate ?? 1) }
        synergies = data.synergies
    }
}

/// OP.GG position names.
enum MetaPosition: String, CaseIterable {
    case top, jungle, mid, adc, support

    init?(clientPosition: String?) {
        switch clientPosition?.uppercased() {
        case "TOP": self = .top
        case "JUNGLE": self = .jungle
        case "MIDDLE", "MID": self = .mid
        case "BOTTOM", "BOT", "ADC": self = .adc
        case "UTILITY", "SUPPORT": self = .support
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .top: "Top"
        case .jungle: "Jungle"
        case .mid: "Mid"
        case .adc: "Bot"
        case .support: "Support"
        }
    }
}
