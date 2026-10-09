import Foundation
import Observation

enum MetaLoad<T> {
    case loading
    case loaded(T)
    case failed(String)

    var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// Fetches and caches OP.GG meta data for the UI. Views request what they need with
/// `.task(id:)` and read the results back from the observable dictionaries.
@Observable @MainActor
final class MetaStore {
    static let shared = MetaStore()

    private(set) var champions: [String: MetaLoad<ChampionMeta>] = [:]
    /// Most-played position per champion key, from OP.GG's lane meta (used for enemies in champ select).
    private(set) var primaryPositions: [Int: MetaPosition] = [:]
    private var laneMetaRequested: Date?
    /// When each champion's data was loaded; entries older than `maxAge` are fetched again.
    private var loadedAt: [String: Date] = [:]
    private static let maxAge: TimeInterval = 6 * 3600

    private static let analysisFields = [
        "data.summary.average_stats.{play,win_rate,pick_rate,ban_rate,tier,rank}",
        "data.damage_type",
        "data.runes.{id,primary_page_id,primary_rune_ids[],secondary_page_id,secondary_rune_ids[],stat_mod_ids[],play,win,pick_rate}",
        "data.starter_items.{ids[],play,win,pick_rate}",
        "data.core_items.{ids[],play,win,pick_rate}",
        "data.boots.{ids[],play,win,pick_rate}",
        "data.fourth_items[].{ids[],play,win,pick_rate}",
        "data.fifth_items[].{ids[],play,win,pick_rate}",
        "data.sixth_items[].{ids[],play,win,pick_rate}",
        "data.summoner_spells.{ids[],play,win,pick_rate}",
        "data.skills.{order[],pick_rate}",
        "data.skill_masteries.{ids[],pick_rate}",
        "data.weak_counters[].{champion_id,champion_name,my_win_rate,counter_win_rate,play}",
        "data.summary.positions[].counters[].{champion_id,champion_name,play,win}",
        "data.synergies.adc[].{champion_id,synergy_champion_id,synergy_champion_name,win_rate,play,score_rank}",
        "data.synergies.support[].{champion_id,synergy_champion_id,synergy_champion_name,win_rate,play,score_rank}",
    ]

    static func championKey(_ champion: Int, _ position: MetaPosition?, _ mode: GameMode) -> String {
        "\(champion)|\(position?.rawValue ?? "-")|\(mode.metaMode ?? "-")"
    }

    func champion(_ champion: Int?, _ position: MetaPosition?, _ mode: GameMode) -> MetaLoad<ChampionMeta>? {
        guard let champion else { return nil }
        return champions[Self.championKey(champion, position ?? primaryPositions[champion], mode)]
    }

    /// Loads popular data for a champion. With no position (enemies in champ select), the
    /// champion's most-played position is used.
    func ensureChampion(_ champion: Int?, _ position: MetaPosition?, _ mode: GameMode) async {
        guard let champion, let modeName = mode.metaMode else { return }
        if position == nil { await ensureLaneMeta() }
        let resolved = position ?? primaryPositions[champion] ?? .mid
        let key = Self.championKey(champion, position ?? primaryPositions[champion], mode)
        let stale = loadedAt[key].map { Date().timeIntervalSince($0) > Self.maxAge } ?? false
        guard champions[key] == nil || isFailed(champions[key]) || stale else { return }
        guard let info = DataDragon.shared.champion(champion) else { return }

        champions[key] = .loading
        do {
            let data = try await OPGGClient.shared.call(
                tool: "lol_get_champion_analysis",
                arguments: ["game_mode": modeName, "champion": info.opggName, "position": resolved.rawValue],
                fields: Self.analysisFields
            )
            let response = try Self.decoder.decode(OPResponse.self, from: data)
            guard let payload = response.data else { throw OPGGClient.OPGGError.badResponse }
            champions[key] = .loaded(ChampionMeta(payload))
            loadedAt[key] = Date()
        } catch {
            champions[key] = .failed(error.localizedDescription)
        }
    }

    func ensureLaneMeta() async {
        if let requested = laneMetaRequested, Date().timeIntervalSince(requested) < Self.maxAge { return }
        laneMetaRequested = Date()
        let fields = MetaPosition.allCases.map { "data.positions.\($0.rawValue)[].{champion,play}" }
        guard let data = try? await OPGGClient.shared.call(
            tool: "lol_list_lane_meta_champions", arguments: ["position": "all"], fields: fields
        ), let response = try? Self.decoder.decode(LaneMetaResponse.self, from: data) else {
            laneMetaRequested = nil
            return
        }

        var best: [Int: (MetaPosition, Int)] = [:]
        for position in MetaPosition.allCases {
            for entry in response.data?.positions?[position.rawValue] ?? [] {
                guard let name = entry.champion, let key = DataDragon.shared.champion(named: name)?.key else { continue }
                let play = entry.play ?? 0
                if play > (best[key]?.1 ?? -1) { best[key] = (position, play) }
            }
        }
        primaryPositions = best.mapValues(\.0)
    }

    private func isFailed<T>(_ load: MetaLoad<T>?) -> Bool {
        if case .failed? = load { return true }
        return false
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private struct LaneMetaResponse: Decodable {
        var data: Payload?
        struct Payload: Decodable {
            var positions: [String: [Entry]]?
        }
        struct Entry: Decodable {
            var champion: String?
            var play: Int?
        }
    }
}
