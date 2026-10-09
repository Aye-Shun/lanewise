import SwiftUI

/// Champ select: your pick, runes (with apply), spells and skills, common build, and your team.
/// Opponent information (bans, enemy picks, duo synergy, damage mix) lives in the inspector.
struct DraftView: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(MetaStore.self) private var store

    var body: some View {
        let mode = monitor.gameMode
        let champion = monitor.myChampionId
        let position = monitor.myPosition
        let load = store.champion(champion, position, mode)
        let premades = monitor.premadeGroups(for: [monitor.champSelect])

        DetailPage {
            if mode.metaMode == nil {
                Label("Builds and runes aren't available for \(mode.label). Player lookups still work.", systemImage: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryLabel)
            }

            YourPickSection(champion: champion, position: position, load: load)

            if champion != nil, mode.metaMode != nil {
                if mode == .summonersRift {
                    RunesSection(champion: champion, load: load)
                }
                SpellsAndSkillsSection(load: load)
                CommonBuildSection(load: load, mode: mode)
            }

            PlayerTable(title: "Your team", side: nil, slots: monitor.champSelect, isMine: false, premades: premades)
            if monitor.champSelect.contains(where: \.isHidden) {
                Text("Ranked champ select hides names. Players are looked up when the loading screen starts.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryLabel)
                    .padding(.top, -14)
            }
        }
        .task(id: MetaStore.championKey(champion ?? 0, position, mode)) {
            await store.ensureChampion(champion, position, mode)
        }
    }
}

private struct YourPickSection: View {
    let champion: Int?
    let position: MetaPosition?
    let load: MetaLoad<ChampionMeta>?

    var body: some View {
        InsetSection("Your pick") {
            if let info = DataDragon.shared.champion(champion) {
                InsetRow(minHeight: 52) {
                    Avatar(champion: champion, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name).font(.system(size: 15, weight: .semibold))
                        Text([position?.label, info.tags.first].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                }
                if let meta = load?.value {
                    RowDivider(inset: 0)
                    InfoStrip(cells: [
                        .init(value: AnyView(RatedPercent(value: meta.winRate, games: 100, size: 17)), label: "Win rate"),
                        .init(value: AnyView(Text(Format.percent(meta.pickRate)).font(.numeral(17))), label: "Pick rate"),
                        .init(value: AnyView(Text(Format.percent(meta.banRate)).font(.numeral(17))), label: "Ban rate"),
                        .init(value: AnyView(tier(meta.tier)), label: "Tier"),
                    ])
                }
            } else {
                InsetRow {
                    Image(systemName: "hand.point.up.left").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                    Text("Hover or lock in a champion to see runes, a build, spells and opponents.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondaryLabel)
                }
            }
        }
    }

    private func tier(_ tier: Int?) -> some View {
        HStack(spacing: 3) {
            if let tier, tier <= 2 { Image(systemName: "star.fill").font(.system(size: 9)) }
            Text(tier.map(String.init) ?? "—").font(.numeral(17))
        }
    }
}

private struct RunesSection: View {
    @Environment(GameMonitor.self) private var monitor
    let champion: Int?
    let load: MetaLoad<ChampionMeta>?

    @State private var confirming = false
    @State private var applyState: ApplyState = .idle

    enum ApplyState: Equatable {
        case idle, applying, applied, failed(String)
    }

    var body: some View {
        let page = load?.value?.runes
        InsetSection("Runes", trailing: page.map { "\(Format.percent($0.pickRate)) pick · \(Format.percent($0.winRate)) win" }) {
            switch load {
            case .loaded(let meta)?:
                if let page = meta.runes {
                    RunePageView(page: page)
                    RowDivider(inset: 0)
                    footer(page)
                } else {
                    InsetRow { Text("No rune data for this pick.").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
                }
            case .failed(let message)?:
                InsetRow { Text(message).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
            default:
                LoadingRow()
            }
        }
        .onChange(of: champion) { _, _ in applyState = .idle }
    }

    private func footer(_ page: OPRunePage) -> some View {
        InsetRow {
            Text("Based on champion and role. Not adjusted for the enemy team.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryLabel)
            Spacer()
            switch applyState {
            case .applying: ProgressView().controlSize(.small)
            case .applied:
                Label("Added to League", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.positive)
            case .failed(let message):
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.negative).lineLimit(2)
            case .idle: EmptyView()
            }
            Button("Apply to Client…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!page.isComplete || applyState == .applying || monitor.status != .connected)
                .help(monitor.status == .connected ? "Add this page to League and select it" : "Connect to League to apply")
        }
        .confirmationDialog("Add this rune page to League?", isPresented: $confirming) {
            Button("Add and Select") { apply(page) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sightline creates a page named “Sightline: \(DataDragon.shared.champion(champion)?.name ?? "")” and selects it. Later uses replace only that page; your own pages are never changed.")
        }
    }

    private func apply(_ page: OPRunePage) {
        applyState = .applying
        let name = DataDragon.shared.champion(champion)?.name ?? "Champion"
        Task {
            do {
                try await monitor.applyRunes(page, championName: name)
                applyState = .applied
            } catch {
                applyState = .failed(error.localizedDescription)
            }
        }
    }
}

/// Two columns of rune rows. The keystone's description is its row subtitle.
struct RunePageView: View {
    let page: OPRunePage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                treeHeader(page.primaryPageId)
                ForEach(Array((page.primaryRuneIds ?? []).enumerated()), id: \.offset) { index, id in
                    RowDivider(inset: 42)
                    if index == 0 { keystoneRow(id) } else { runeRow(id) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Rectangle().fill(Palette.separator).frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                treeHeader(page.secondaryPageId)
                ForEach(page.secondaryRuneIds ?? [], id: \.self) { id in
                    RowDivider(inset: 42)
                    runeRow(id)
                }
                RowDivider(inset: 10)
                shardsRow(page.statModIds ?? [])
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func treeHeader(_ id: Int?) -> some View {
        HStack(spacing: 6) {
            if let id {
                RemoteImage(url: DataDragon.shared.runeIcon(id), shape: .rounded(0)).frame(width: 16, height: 16)
                Text(DataDragon.shared.runeName(id)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func keystoneRow(_ id: Int) -> some View {
        let info = DataDragon.shared.runes[id]
        return HStack(alignment: .top, spacing: 10) {
            RuneIcon(id: id, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(DataDragon.shared.runeName(id)).font(.system(size: 13, weight: .semibold))
                if let info {
                    Text(info.longDesc)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(info.longDesc)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 56, alignment: .topLeading)
    }

    private func runeRow(_ id: Int) -> some View {
        HStack(spacing: 10) {
            RuneIcon(id: id, size: 22)
            Text(DataDragon.shared.runeName(id)).font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private func shardsRow(_ ids: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shards").font(.system(size: 13))
            HStack(spacing: 4) {
                ForEach(Array(ids.enumerated()), id: \.offset) { RuneIcon(id: $0.element, size: 16) }
                Text(ids.map { StatShard.name($0).lowercased().capitalizedFirst }.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private struct SpellsAndSkillsSection: View {
    let load: MetaLoad<ChampionMeta>?

    var body: some View {
        InsetSection("Spells and skills") {
            switch load {
            case .loaded(let meta)?:
                if let spells = meta.spells, let ids = spells.ids {
                    InsetRow {
                        HStack(spacing: 4) { ForEach(ids, id: \.self) { SpellIcon(spell: DataDragon.shared.spell($0)) } }
                        Text(ids.compactMap { DataDragon.shared.spell($0)?.name }.joined(separator: " + ")).font(.system(size: 13))
                        Spacer()
                        Text("\(Format.percent(OPStat.rate(win: spells.win, play: spells.play))) win · \(Format.percent(spells.pickRate)) pick")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
                    }
                    RowDivider()
                }
                if !meta.skillMaxOrder.isEmpty {
                    InsetRow {
                        Text("Max order").font(.system(size: 13))
                        Spacer()
                        KeycapRow(keys: meta.skillMaxOrder, spacing: 4)
                    }
                    RowDivider()
                }
                if !meta.skillOrder.isEmpty {
                    SkillMatrix(order: meta.skillOrder).padding(.horizontal, 10).padding(.vertical, 10)
                }
            case .failed(let message)?:
                InsetRow { Text(message).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
            default:
                LoadingRow()
            }
        }
    }
}

/// Level-by-level skill order as a monochrome matrix: the shape carries the order.
struct SkillMatrix: View {
    let order: [String]

    var body: some View {
        let levels = Array(order.prefix(18))
        Grid(horizontalSpacing: 0, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 26, height: 12)
                ForEach(levels.indices, id: \.self) { index in
                    Text("\(index + 1)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryLabel)
                        .frame(width: 18)
                }
            }
            ForEach(["Q", "W", "E", "R"], id: \.self) { key in
                GridRow {
                    Keycap(key: key, size: 10).frame(width: 26, alignment: .leading)
                    ForEach(levels.indices, id: \.self) { index in
                        ZStack {
                            if [5, 10, 15].contains(index) { Palette.groupAlt }
                            if levels[index] == key {
                                Circle().fill(Palette.label).frame(width: 8, height: 8)
                            } else {
                                Circle().fill(Palette.tertiaryLabel).frame(width: 3, height: 3)
                            }
                        }
                        .frame(width: 18, height: 18)
                    }
                }
            }
        }
        .accessibilityLabel("Skill order: \(levels.joined(separator: ", "))")
    }
}

private struct CommonBuildSection: View {
    let load: MetaLoad<ChampionMeta>?
    let mode: GameMode

    var body: some View {
        InsetSection(mode == .aram ? "Common ARAM build" : "Common build", footer: "Core items are listed in build order.") {
            switch load {
            case .loaded(let meta)?:
                let rows: [(String, OPItemSet?)] = [("Start", meta.starter), ("Core", meta.core), ("Boots", meta.boots)]
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if let set = row.1, !set.items.isEmpty {
                        if index > 0 { RowDivider() }
                        itemSetRow(row.0, set)
                    }
                }
                ForEach(Array(zip(["Item 4", "Item 5", "Item 6"], [meta.fourth, meta.fifth, meta.sixth])), id: \.0) { title, options in
                    if !options.isEmpty {
                        RowDivider()
                        InsetRow(minHeight: 40) {
                            label(title)
                            HStack(spacing: 14) {
                                ForEach(Array(options.prefix(3).enumerated()), id: \.offset) { _, option in
                                    if let id = option.items.first {
                                        HStack(spacing: 4) {
                                            ItemIcon(id: id, size: 28)
                                            Text(Format.percent(option.pickRate)).font(.system(size: 11)).monospacedDigit()
                                                .foregroundStyle(Palette.secondaryLabel)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            case .failed(let message)?:
                InsetRow { Text(message).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
            default:
                LoadingRow()
            }
        }
    }

    private func itemSetRow(_ title: String, _ set: OPItemSet) -> some View {
        InsetRow(minHeight: 40) {
            label(title)
            HStack(spacing: 6) {
                ForEach(Array(set.items.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 28) }
            }
            Spacer()
            Text("\(Format.percent(set.winRate)) win · \(Format.percent(set.pickRate)) pick")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel).frame(width: 76, alignment: .leading)
    }
}

struct LoadingRow: View {
    var text = "Loading build data…"

    var body: some View {
        InsetRow {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
        }
    }
}

// MARK: - Inspector

struct DraftInspector: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(MetaStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @State private var tab = 0

    var body: some View {
        let mode = monitor.gameMode
        let champion = monitor.myChampionId
        let position = monitor.myPosition
        let load = store.champion(champion, position, mode)

        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Opponents").tag(0)
                Text("Player").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            if tab == 1 {
                PlayerInspector(slot: monitor.champSelect.first { $0.id == navigation.selectedPlayer })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if mode == .summonersRift, champion != nil {
                            BanSuggestions(load: load)
                        }
                        EnemyTeamSection(mode: mode)
                        if mode == .summonersRift, let position, position == .adc || position == .support {
                            DuoSynergySection(position: position, load: load)
                        }
                        if !monitor.allyChampions.isEmpty || !monitor.enemyChampions.isEmpty {
                            InsetSection("Damage mix") {
                                CompositionReadout(champion: champion, allies: monitor.allyChampions,
                                                   enemies: monitor.enemyChampions, mode: mode)
                                    .padding(10)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .onChange(of: navigation.selectedPlayer) { _, id in if id != nil { tab = 1 } }
    }
}

private struct BanSuggestions: View {
    let load: MetaLoad<ChampionMeta>?

    var body: some View {
        InsetSection("Ban suggestions", trailing: "Your win rate") {
            if let meta = load?.value {
                if meta.hardestMatchups.isEmpty {
                    InsetRow { Text("Not enough matchup data yet.").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
                }
                ForEach(Array(meta.hardestMatchups.prefix(5).enumerated()), id: \.element) { index, counter in
                    if index > 0 { RowDivider(inset: 46) }
                    InsetRow(minHeight: 40) {
                        Avatar(champion: counter.championId, size: 28)
                        Text(counter.championName ?? DataDragon.shared.champion(counter.championId)?.name ?? "").font(.system(size: 13))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            RatedPercent(value: counter.myWinRate, games: counter.play ?? 0)
                            if let play = counter.play {
                                Text("\(Format.grouped(play)) games").font(.system(size: 10)).foregroundStyle(Palette.secondaryLabel)
                            }
                        }
                    }
                }
            } else {
                LoadingRow()
            }
        }
    }
}

private struct EnemyTeamSection: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(MetaStore.self) private var store
    let mode: GameMode

    var body: some View {
        let enemies = monitor.enemyChampSelect
        InsetSection("Enemy team", trailing: mode == .summonersRift ? "Likely role and spells" : nil) {
            if mode == .arena {
                InsetRow { Text("Enemy picks are hidden in Arena.").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
            } else if enemies.isEmpty {
                InsetRow { Text("Enemy picks show up as they're locked in.").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
            } else {
                ForEach(Array(enemies.enumerated()), id: \.element.id) { index, slot in
                    if index > 0 { RowDivider(inset: 46) }
                    InsetRow(minHeight: 40) {
                        if let key = slot.championId, let info = DataDragon.shared.champion(key) {
                            Avatar(champion: key, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(info.name).font(.system(size: 13))
                                if let role = MetaPosition(clientPosition: slot.position) ?? store.primaryPositions[key] {
                                    Text(role.label).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                                }
                            }
                            Spacer()
                            if mode == .summonersRift, let spells = store.champion(key, nil, mode)?.value?.spells?.ids {
                                HStack(spacing: 4) { ForEach(spells, id: \.self) { SpellIcon(spell: DataDragon.shared.spell($0), size: 20) } }
                            }
                        } else {
                            Circle().fill(Palette.tertiaryLabel.opacity(0.25)).frame(width: 28, height: 28)
                                .overlay(Image(systemName: "questionmark").font(.system(size: 11)).foregroundStyle(Palette.tertiaryLabel))
                            Text("Not picked yet").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                        }
                    }
                }
            }
        }
        .task(id: enemies.compactMap(\.championId).map(String.init).joined(separator: ",")) {
            guard mode == .summonersRift else { return }
            for key in enemies.compactMap(\.championId) {
                await store.ensureChampion(key, nil, mode)
            }
        }
    }
}

/// Experimental ADC/support synergy for the exact duo, when OP.GG has a sample for it.
private struct DuoSynergySection: View {
    @Environment(GameMonitor.self) private var monitor
    let position: MetaPosition
    let load: MetaLoad<ChampionMeta>?

    var body: some View {
        let partnerRole: MetaPosition = position == .adc ? .support : .adc
        let partner = monitor.champSelect.first { !$0.isLocalPlayer && MetaPosition(clientPosition: $0.position) == partnerRole }?.championId
        let list = (position == .adc ? load?.value?.synergies?.support : load?.value?.synergies?.adc) ?? []

        InsetSection("Duo synergy", trailing: "Beta") {
            InsetRow(minHeight: 40) {
                if let partner, let name = DataDragon.shared.champion(partner)?.name {
                    Avatar(champion: partner, size: 28)
                    if let exact = list.first(where: { $0.synergyChampionId == partner }) {
                        Text("With \(name)").font(.system(size: 13))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            RatedPercent(value: exact.winRate, games: exact.play ?? 0)
                            Text("\(Format.grouped(exact.play ?? 0)) games").font(.system(size: 10)).foregroundStyle(Palette.secondaryLabel)
                        }
                    } else {
                        Text("No data for this exact duo with \(name).").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                    }
                } else {
                    Text("Your duo partner hasn't picked yet.").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                }
            }
            if !list.isEmpty {
                RowDivider()
                InsetRow {
                    Text("Strongest partners").font(.system(size: 13))
                    Spacer()
                    ForEach(list.prefix(3), id: \.self) { entry in
                        Avatar(champion: entry.synergyChampionId, size: 22)
                            .help("\(entry.synergyChampionName ?? "") · \(Format.percent(entry.winRate))")
                    }
                }
            }
        }
    }
}
