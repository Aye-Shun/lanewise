import Foundation

/// Tracks a popular build against the player's real inventory: which items are done, what to
/// buy next, and how much gold is still needed after crediting components already owned.
struct BuildProgress {
    struct Step: Identifiable, Hashable {
        let itemID: Int
        let owned: Bool
        var id: Int { itemID }
    }

    struct Component: Identifiable, Hashable {
        let itemID: Int
        let owned: Bool
        let index: Int
        var id: Int { index }
    }

    let steps: [Step]
    let next: Int?
    let remainingGold: Int?
    let components: [Component]
    let alternatives: [Int]

    /// Build order: first core item, boots, remaining core items, then the most popular
    /// 4th/5th/6th items.
    @MainActor
    init(meta: ChampionMeta, inventory: [Int]) {
        var order: [Int] = []
        let core = meta.core?.items ?? []
        if let first = core.first { order.append(first) }
        order += meta.boots?.items ?? []
        order += core.dropFirst()
        for options in [meta.fourth, meta.fifth, meta.sixth] {
            if let pick = options.first?.items.first(where: { !order.contains($0) }) { order.append(pick) }
        }

        let owned = Set(inventory)
        steps = order.map { Step(itemID: $0, owned: owned.contains($0)) }
        next = steps.first { !$0.owned }?.itemID

        if let next {
            var pool = inventory.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
            remainingGold = Self.costToComplete(next, pool: &pool)
            var componentPool = inventory.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
            components = (DataDragon.shared.item(next)?.from ?? []).enumerated().map { index, id in
                let have = (componentPool[id] ?? 0) > 0
                if have { componentPool[id, default: 0] -= 1 }
                return Component(itemID: id, owned: have, index: index)
            }
        } else {
            remainingGold = nil
            components = []
        }

        let used = Set(order)
        alternatives = (meta.fourth + meta.fifth + meta.sixth)
            .flatMap(\.items)
            .reduce(into: [Int]()) { result, id in
                if !used.contains(id) && !result.contains(id) { result.append(id) }
            }
            .prefix(4).map { $0 }
    }

    /// Gold needed to finish `item`, using owned components (each owned item counts once).
    @MainActor
    static func costToComplete(_ item: Int, pool: inout [Int: Int]) -> Int {
        if let count = pool[item], count > 0 {
            pool[item] = count - 1
            return 0
        }
        guard let info = DataDragon.shared.item(item) else { return 0 }
        guard !info.from.isEmpty else { return info.total }
        return info.base + info.from.reduce(0) { $0 + costToComplete($1, pool: &pool) }
    }
}
