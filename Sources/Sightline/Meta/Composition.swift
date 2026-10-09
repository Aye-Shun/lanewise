import Foundation

/// Team damage profile and crowd-control context, plus a defensive item shortlist.
struct TeamComposition {
    var physical = 0.0
    var magic = 0.0
    var hardCCChampions: [Int] = []
    var healers: [Int] = []
    var count = 0

    var adShare: Double { count > 0 ? physical / Double(count) : 0 }
    var apShare: Double { count > 0 ? magic / Double(count) : 0 }

    var ccLevel: String {
        switch hardCCChampions.count {
        case 0...1: "Low"
        case 2...3: "Medium"
        default: "High"
        }
    }

    /// Damage type comes from OP.GG when loaded, otherwise from Data Dragon's class tags.
    @MainActor
    init(champions: [Int], damageTypes: [Int: DamageType]) {
        for key in champions {
            count += 1
            switch damageTypes[key] ?? Self.estimatedType(key) {
            case .ad: physical += 1
            case .ap: magic += 1
            case .hybrid:
                physical += 0.5
                magic += 0.5
            }
            if let id = DataDragon.shared.champion(key)?.id {
                if Self.hardCC.contains(id) { hardCCChampions.append(key) }
                if Self.healing.contains(id) { healers.append(key) }
            }
        }
    }

    @MainActor
    private static func estimatedType(_ key: Int) -> DamageType {
        let tags = DataDragon.shared.champion(key)?.tags ?? []
        if tags.first == "Mage" || (tags.contains("Mage") && !tags.contains("Marksman")) { return .ap }
        if tags.first == "Tank" || tags.first == "Support" { return .hybrid }
        return .ad
    }

    /// Champions with reliable hard crowd control (stun, root, knock-up, charm, fear, suppression, pull).
    static let hardCC: Set<String> = [
        "Aatrox", "Ahri", "Alistar", "Amumu", "Anivia", "Annie", "Ashe", "AurelionSol", "Azir", "Bard",
        "Blitzcrank", "Brand", "Braum", "Caitlyn", "Camille", "Cassiopeia", "Chogath", "Diana", "Draven", "Ekko",
        "Elise", "Fiddlesticks", "Fizz", "Galio", "Gnar", "Gragas", "Hecarim", "Heimerdinger", "Hwei", "Irelia",
        "Ivern", "Janna", "JarvanIV", "Jax", "Jayce", "Jhin", "Jinx", "Karma", "Kalista", "Kennen", "KSante",
        "Leblanc", "LeeSin", "Leona", "Lillia", "Lissandra", "Lulu", "Lux", "Malphite", "Malzahar", "Maokai",
        "MonkeyKing", "Morgana", "Nami", "Nautilus", "Neeko", "Nocturne", "Nunu", "Orianna", "Ornn", "Pantheon",
        "Poppy", "Pyke", "Qiyana", "Rakan", "Rammus", "RekSai", "Rell", "Renata", "Renekton", "Riven", "Ryze",
        "Sejuani", "Senna", "Seraphine", "Sett", "Shaco", "Shen", "Singed", "Sion", "Skarner", "Sona", "Soraka",
        "Swain", "Sylas", "Syndra", "TahmKench", "Taliyah", "Taric", "Thresh", "Tristana", "Trundle", "TwistedFate",
        "Udyr", "Urgot", "Varus", "Vayne", "Veigar", "Velkoz", "Vex", "Vi", "Viktor", "Volibear", "Warwick",
        "Xayah", "Xerath", "XinZhao", "Yasuo", "Yone", "Yuumi", "Zac", "Zilean", "Zoe", "Zyra",
    ]

    /// Champions whose healing makes Grievous Wounds worth buying.
    static let healing: Set<String> = [
        "Aatrox", "Briar", "DrMundo", "Fiddlesticks", "Illaoi", "Nami", "Olaf", "Renata", "Sona", "Soraka",
        "Swain", "Sylas", "Vladimir", "Warwick", "Yuumi", "Milio", "Seraphine", "Maokai", "Kayn", "Trundle",
    ]
}
