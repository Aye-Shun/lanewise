import Foundation

/// Writes the common build into League's in-game shop as one Recall item set.
///
/// The client's item-set endpoint replaces *all* of a player's sets at once, so the player's
/// existing sets are read and written back as raw JSON (nothing they contain is dropped), with only
/// Recall's own set (matched by `uid`) replaced.
struct ItemSetWriter {
    static let uid = "recall-build"

    let client: LCUClient

    func apply(_ meta: ChampionMeta, champion: ChampionInfo, position: MetaPosition?, mode: GameMode,
               summonerId: Int, accountId: Int?) async throws {
        let path = "/lol-item-sets/v1/item-sets/\(summonerId)/sets"
        var root: [String: Any]
        do {
            let data = try await client.data(path)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LocalAPIError.noData
            }
            root = parsed
        } catch LocalAPIError.http(404, _) {
            // No item sets saved yet.
            root = ["accountId": accountId ?? 0, "itemSets": [[String: Any]]()]
        }
        // Any other read error is thrown above: never write back without the player's sets.

        // If the sets aren't in the shape we expect, don't write: we'd lose the player's sets.
        guard root["itemSets"] == nil || root["itemSets"] is [[String: Any]] else { throw LocalAPIError.noData }
        var sets = root["itemSets"] as? [[String: Any]] ?? []
        sets.removeAll { ($0["uid"] as? String) == Self.uid }
        sets.append(Self.itemSet(meta, champion: champion, position: position, mode: mode))
        root["itemSets"] = sets
        root["timestamp"] = Int(Date().timeIntervalSince1970 * 1000)
        try await client.send("PUT", path, json: root)
    }

    static func itemSet(_ meta: ChampionMeta, champion: ChampionInfo, position: MetaPosition?, mode: GameMode) -> [String: Any] {
        var blocks: [[String: Any]] = []
        func add(_ title: String, _ items: [Int]) {
            guard !items.isEmpty else { return }
            // Repeated items (e.g. two potions) become one entry with a count.
            var counts: [(Int, Int)] = []
            for id in items {
                if let index = counts.firstIndex(where: { $0.0 == id }) { counts[index].1 += 1 } else { counts.append((id, 1)) }
            }
            blocks.append(["type": title, "items": counts.map { ["id": String($0.0), "count": $0.1] }])
        }
        add("Starter", meta.starter?.items ?? [])
        add("Core build", meta.core?.items ?? [])
        add("Boots", meta.boots?.items ?? [])
        add("4th item options", meta.fourth.prefix(3).compactMap(\.items.first))
        add("5th item options", meta.fifth.prefix(3).compactMap(\.items.first))
        add("6th item options", meta.sixth.prefix(3).compactMap(\.items.first))

        let role = mode == .aram ? "ARAM" : position?.label
        return [
            "uid": uid,
            "title": "Recall: \(champion.name)" + (role.map { " (\($0))" } ?? ""),
            "type": "custom",
            "map": "any",
            "mode": "any",
            "sortrank": 0,
            "startedFrom": "blank",
            "associatedChampions": [champion.key],
            "associatedMaps": [mode == .aram ? 12 : 11],
            "preferredItemSlots": [[String: Any]](),
            "blocks": blocks,
        ]
    }
}

/// Sets your two summoner spells in champ select, keeping Flash on the key you use.
struct SpellWriter {
    static let flash = 4

    let client: LCUClient

    func apply(_ spells: [Int], flashOnF: Bool) async throws {
        guard spells.count == 2 else { return }
        var d = spells[0], f = spells[1]
        if (d == Self.flash && flashOnF) || (f == Self.flash && !flashOnF) { swap(&d, &f) }
        try await client.send("PATCH", "/lol-champ-select/v1/session/my-selection", json: ["spell1Id": d, "spell2Id": f])
    }
}
