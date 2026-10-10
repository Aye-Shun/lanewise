import SwiftUI

// MARK: - Next Item

/// The next item in a common build, adjusted to what the player already owns.
struct NextItemPanel: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(MetaStore.self) private var store
    @Environment(\.overlayScale) private var scale

    var body: some View {
        switch store.champion(monitor.myChampionId, monitor.myPosition, monitor.gameMode) {
        case .loaded(let meta)?: content(meta)
        case .failed(let message)?: PanelNote(text: message)
        default: ProgressView().controlSize(.mini).tint(.white)
        }
    }

    @ViewBuilder private func content(_ meta: ChampionMeta) -> some View {
        let inventory = monitor.activeLivePlayer?.items.map(\.itemID) ?? []
        let owned = Set(inventory)
        let progress = BuildProgress(meta: meta, inventory: inventory)

        VStack(alignment: .leading, spacing: 6 * scale) {
            if let next = progress.next {
                HStack(alignment: .top, spacing: 8 * scale) {
                    ItemIcon(id: next, size: 30, next: true)
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text(DataDragon.shared.item(next)?.name ?? "Item \(next)")
                            .sfont(12, .semibold)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let gold = progress.remainingGold, gold > 0 {
                            Text("\(Format.grouped(gold)) g needed").sfont(11, .medium, rounded: true)
                                .foregroundStyle(Palette.secondaryLabel)
                        } else {
                            Label("Ready to buy", systemImage: "checkmark.circle.fill")
                                .sfont(11, .semibold)
                                .foregroundStyle(Palette.positive)
                        }
                    }
                }
                if !progress.components.isEmpty {
                    HStack(spacing: 3 * scale) {
                        Text("Parts").sfont(10).foregroundStyle(Palette.secondaryLabel)
                        ForEach(progress.components) { ItemIcon(id: $0.itemID, size: 18, owned: $0.owned) }
                    }
                }
            } else if !progress.steps.isEmpty {
                Label("Core build complete", systemImage: "checkmark.seal.fill")
                    .sfont(12, .semibold)
                    .foregroundStyle(Palette.positive)
            }

            // Build order: owned items checked, the next one ringed.
            HStack(spacing: 3 * scale) {
                ForEach(progress.steps) { step in
                    ItemIcon(id: step.itemID, size: 22, owned: step.owned, next: step.itemID == progress.next)
                }
            }
            if let starter = meta.starter, inventory.isEmpty || (monitor.live?.gameData?.gameTime ?? 0) < 90 {
                HStack(spacing: 3 * scale) {
                    Text("Start").sfont(10).foregroundStyle(Palette.secondaryLabel)
                    ForEach(Array(starter.items.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 18, owned: owned.contains($0.element)) }
                }
            }
        }
    }
}

/// Damage mix for both teams, enemy hard CC, and defensive items to consider.
struct CompositionReadout: View {
    @Environment(MetaStore.self) private var store
    @Environment(\.overlayScale) private var scale
    let champion: Int?
    let allies: [Int]
    let enemies: [Int]
    let mode: GameMode

    var body: some View {
        let types = damageTypes
        let enemyComp = TeamComposition(champions: enemies, damageTypes: types)
        let allyComp = TeamComposition(champions: allies, damageTypes: types)
        let heavyCC = enemyComp.hardCCChampions.count >= 4

        VStack(alignment: .leading, spacing: 8 * scale) {
            DamageMixRow(title: "Enemy", composition: enemyComp)
            DamageMixRow(title: "Your team", composition: allyComp)
            HStack(spacing: 5 * scale) {
                Text("Hard CC").sfont(12)
                if heavyCC {
                    Image(systemName: "exclamationmark.triangle.fill").sfont(11).foregroundStyle(Palette.negative)
                }
                Text("\(enemyComp.ccLevel) (\(enemyComp.hardCCChampions.count))")
                    .sfont(12, .semibold)
                    .foregroundStyle(heavyCC ? Palette.negative : Palette.label)
                Spacer(minLength: 0)
                ForEach(enemyComp.hardCCChampions, id: \.self) { Avatar(champion: $0, size: 16) }
            }
        }
        .task(id: (allies + enemies).map(String.init).joined(separator: ",") + mode.rawValue) {
            for key in allies + enemies {
                await store.ensureChampion(key, nil, mode)
            }
        }
    }

    private var damageTypes: [Int: DamageType] {
        var types: [Int: DamageType] = [:]
        for key in allies + enemies {
            if let type = store.champion(key, nil, mode)?.value?.damageType { types[key] = type }
        }
        return types
    }
}
