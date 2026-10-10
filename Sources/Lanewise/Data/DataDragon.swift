import Foundation
import Observation

struct ChampionInfo: Hashable {
    let key: Int        // numeric id used by the APIs, e.g. 103
    let id: String      // asset id, e.g. "Ahri", "MonkeyKing"
    let name: String    // display name, e.g. "Wukong"
    let tags: [String]  // "Mage", "Tank", ...

    /// OP.GG accepts the asset id in upper case (AHRI, MONKEYKING, KAISA).
    var opggName: String { id.uppercased() }
}

struct ItemInfo: Hashable {
    let id: Int
    let name: String
    let total: Int
    /// Cost of the final combine step (total minus components).
    let base: Int
    let from: [Int]
    let tags: [String]
    let onSummonersRift: Bool
}

struct RuneInfo: Hashable {
    let id: Int
    let name: String
    let icon: String
    let shortDesc: String
    let longDesc: String
}

struct RuneTree: Hashable {
    let id: Int
    let name: String
    let icon: String
}

struct SummonerSpellInfo: Hashable {
    let key: Int        // 4
    let id: String      // "SummonerFlash"
    let name: String    // "Flash"
    let cooldown: Double
}

/// Riot's static data CDN: champions, items, runes, summoner spells and image assets.
@Observable @MainActor
final class DataDragon {
    static let shared = DataDragon()

    private static let base = "https://ddragon.leagueoflegends.com"

    private(set) var version = "16.20.1"
    private(set) var champions: [Int: ChampionInfo] = [:]
    private(set) var items: [Int: ItemInfo] = [:]
    private(set) var runes: [Int: RuneInfo] = [:]
    private(set) var runeTrees: [Int: RuneTree] = [:]
    private(set) var spellsByKey: [Int: SummonerSpellInfo] = [:]
    private var spellsByID: [String: SummonerSpellInfo] = [:]
    private var championKeysByNormalizedName: [String: Int] = [:]
    private var isLoaded = false

    func load() async {
        guard !isLoaded else { return }
        if let versions = await Self.fetch("\(Self.base)/api/versions.json", as: [String].self),
           let latest = versions.first {
            version = latest
        }
        let cdn = "\(Self.base)/cdn/\(version)/data/en_US"
        async let champFile = Self.fetch("\(cdn)/champion.json", as: ChampionFile.self)
        async let itemFile = Self.fetch("\(cdn)/item.json", as: ItemFile.self)
        async let runeFile = Self.fetch("\(cdn)/runesReforged.json", as: [RuneTreeFile].self)
        async let spellFile = Self.fetch("\(cdn)/summoner.json", as: SpellFile.self)

        if let file = await champFile {
            var byKey: [Int: ChampionInfo] = [:]
            var byName: [String: Int] = [:]
            for entry in file.data.values {
                guard let key = Int(entry.key) else { continue }
                byKey[key] = ChampionInfo(key: key, id: entry.id, name: entry.name, tags: entry.tags ?? [])
                byName[Self.normalize(entry.name)] = key
                byName[Self.normalize(entry.id)] = key
            }
            champions = byKey
            championKeysByNormalizedName = byName
        }
        if let file = await itemFile {
            var parsed: [Int: ItemInfo] = [:]
            for (id, item) in file.data {
                guard let id = Int(id) else { continue }
                parsed[id] = ItemInfo(
                    id: id,
                    name: item.name,
                    total: item.gold.total,
                    base: item.gold.base,
                    from: (item.from ?? []).compactMap(Int.init),
                    tags: item.tags ?? [],
                    onSummonersRift: (item.maps?["11"] ?? false) && (item.gold.purchasable ?? true)
                )
            }
            items = parsed
        }
        if let trees = await runeFile {
            var parsedRunes: [Int: RuneInfo] = [:]
            var parsedTrees: [Int: RuneTree] = [:]
            for tree in trees {
                parsedTrees[tree.id] = RuneTree(id: tree.id, name: tree.name, icon: tree.icon)
                for slot in tree.slots {
                    for rune in slot.runes {
                        parsedRunes[rune.id] = RuneInfo(
                            id: rune.id, name: rune.name, icon: rune.icon,
                            shortDesc: Self.stripTags(rune.shortDesc),
                            // Riot appends an italic flavor quote (<i>'...'</i>); keep only the mechanics.
                            longDesc: Self.stripTags(rune.longDesc.replacingOccurrences(
                                of: "<i>'[^<]*'</i>", with: "", options: .regularExpression))
                        )
                    }
                }
            }
            runes = parsedRunes
            runeTrees = parsedTrees
        }
        if let file = await spellFile {
            var byKey: [Int: SummonerSpellInfo] = [:]
            var byID: [String: SummonerSpellInfo] = [:]
            for spell in file.data.values {
                guard let key = Int(spell.key) else { continue }
                let info = SummonerSpellInfo(key: key, id: spell.id, name: spell.name, cooldown: spell.cooldown.first ?? 0)
                byKey[key] = info
                byID[spell.id] = info
            }
            spellsByKey = byKey
            spellsByID = byID
        }
        isLoaded = !champions.isEmpty && !items.isEmpty
    }

    // MARK: Champions

    func champion(_ key: Int?) -> ChampionInfo? {
        key.flatMap { champions[$0] }
    }

    func champion(named name: String) -> ChampionInfo? {
        championKeysByNormalizedName[Self.normalize(name)].flatMap { champions[$0] }
    }

    func championIcon(_ key: Int?) -> URL? {
        champion(key).flatMap { championIcon(id: $0.id) }
    }

    func championIcon(id: String) -> URL? {
        URL(string: "\(Self.base)/cdn/\(version)/img/champion/\(id).png")
    }

    /// Live Client data reports champions by display name and by a raw localization key
    /// such as `game_character_displayname_MonkeyKing`.
    func championID(live player: LivePlayer) -> String? {
        if let raw = player.rawChampionName, let range = raw.range(of: "displayname_") {
            return String(raw[range.upperBound...])
        }
        return champion(named: player.championName)?.id
    }

    func championKey(live player: LivePlayer) -> Int? {
        guard let id = championID(live: player) else { return nil }
        return championKeysByNormalizedName[Self.normalize(id)]
    }

    // MARK: Items

    func item(_ id: Int) -> ItemInfo? { items[id] }

    func itemIcon(_ id: Int) -> URL? {
        URL(string: "\(Self.base)/cdn/\(version)/img/item/\(id).png")
    }

    /// Total value of an item (including its components), falling back to the live price.
    func value(of item: LiveItem) -> Int {
        (items[item.itemID]?.total ?? item.price ?? 0) * max(item.count ?? 1, 1)
    }

    // MARK: Runes

    func runeIcon(_ id: Int) -> URL? {
        if let rune = runes[id] {
            return URL(string: "\(Self.base)/cdn/img/\(rune.icon)")
        }
        if let tree = runeTrees[id] {
            return URL(string: "\(Self.base)/cdn/img/\(tree.icon)")
        }
        return StatShard.icon(id)
    }

    func runeName(_ id: Int) -> String {
        runes[id]?.name ?? runeTrees[id]?.name ?? StatShard.name(id)
    }

    // MARK: Summoner spells

    func spell(_ key: Int) -> SummonerSpellInfo? { spellsByKey[key] }

    func spell(live: LiveSpell?) -> SummonerSpellInfo? {
        guard let live else { return nil }
        if let id = live.spellID {
            if let hit = spellsByID[id] { return hit }
            // Upgraded variants, e.g. "SummonerTeleportUpgrade" or Smite upgrades.
            if let hit = spellsByID.values.first(where: { id.hasPrefix($0.id) }) { return hit }
        }
        return spellsByKey.values.first { $0.name == live.displayName }
    }

    func spellIcon(_ spell: SummonerSpellInfo?) -> URL? {
        spell.flatMap { URL(string: "\(Self.base)/cdn/\(version)/img/spell/\($0.id).png") }
    }

    // MARK: Profiles

    func profileIcon(_ id: Int?) -> URL? {
        id.flatMap { URL(string: "\(Self.base)/cdn/\(version)/img/profileicon/\($0).png") }
    }

    // MARK: Helpers

    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetch<T: Decodable>(_ url: String, as type: T.Type) async -> T? {
        guard let url = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private struct ChampionFile: Decodable {
        var data: [String: Entry]
        struct Entry: Decodable {
            var id: String
            var key: String
            var name: String
            var tags: [String]?
        }
    }

    private struct ItemFile: Decodable {
        var data: [String: Item]
        struct Item: Decodable {
            var name: String
            var gold: Gold
            var from: [String]?
            var tags: [String]?
            var maps: [String: Bool]?
        }
        struct Gold: Decodable {
            var base: Int
            var total: Int
            var purchasable: Bool?
        }
    }

    private struct RuneTreeFile: Decodable {
        var id: Int
        var name: String
        var icon: String
        var slots: [Slot]
        struct Slot: Decodable { var runes: [Rune] }
        struct Rune: Decodable {
            var id: Int
            var name: String
            var icon: String
            var shortDesc: String
            var longDesc: String
        }
    }

    private struct SpellFile: Decodable {
        var data: [String: Spell]
        struct Spell: Decodable {
            var id: String
            var key: String
            var name: String
            var cooldown: [Double]
        }
    }
}

/// Stat shards aren't in Data Dragon's rune file; names and CommunityDragon icons are mapped here.
enum StatShard {
    private static let shards: [Int: (name: String, icon: String)] = [
        5001: ("Health Scaling", "statmodshealthplusicon"),
        5002: ("Armor", "statmodsarmoricon"),
        5003: ("Magic Resist", "statmodsmagicresicon"),
        5005: ("Attack Speed", "statmodsattackspeedicon"),
        5007: ("Ability Haste", "statmodscdrscalingicon"),
        5008: ("Adaptive Force", "statmodsadaptiveforceicon"),
        5010: ("Move Speed", "statmodsmovementspeedicon"),
        5011: ("Health", "statmodshealthscalingicon"),
        5013: ("Tenacity and Slow Resist", "statmodstenacityicon"),
    ]

    static func name(_ id: Int) -> String {
        shards[id]?.name ?? "Shard \(id)"
    }

    static func icon(_ id: Int) -> URL? {
        shards[id].flatMap {
            URL(string: "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/perk-images/statmods/\($0.icon).png")
        }
    }
}
