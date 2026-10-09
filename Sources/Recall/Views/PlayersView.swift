import AppKit
import SwiftUI

/// Loading-screen scouting as two Activity Monitor-style tables (one in Arena).
struct PlayersView: View {
    @Environment(GameMonitor.self) private var monitor

    var body: some View {
        if let lobby = monitor.lobby {
            let premades = monitor.premadeGroups(for: [lobby.blue, lobby.red])
            DetailPage(maxWidth: nil) {
                if monitor.gameMode == .arena {
                    PlayerTable(title: "All players", side: nil, slots: lobby.blue + lobby.red, isMine: false, premades: premades)
                } else {
                    PlayerTable(title: "Blue side", side: true, slots: lobby.blue, isMine: monitor.myTeamIsBlue, premades: premades)
                    PlayerTable(title: "Red side", side: false, slots: lobby.red, isMine: !monitor.myTeamIsBlue, premades: premades)
                }
            }
        }
    }
}

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    // Siblings that don't set the key report 0, so keep the largest value.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PlayerTable: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(Navigation.self) private var navigation
    let title: String
    /// true = blue, false = red, nil = no sides (Arena, your team in champ select).
    let side: Bool?
    let slots: [PlayerSlot]
    let isMine: Bool
    let premades: [String: Int]

    @State private var width: CGFloat = 1000

    /// Columns need ~780 pt with Form and Notes, ~680 with Notes only.
    private var showsForm: Bool { width >= 780 }
    private var showsNotes: Bool { width >= 680 }

    var body: some View {
        let ranked = slots.compactMap { monitor.insight(for: $0)?.profile.solo }.filter(\.isRanked)
        let wins = ranked.reduce(0) { $0 + $1.wins }
        let games = ranked.reduce(0) { $0 + $1.games }

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let side { Circle().fill(Palette.side(blue: side)).frame(width: 8, height: 8) }
                Text(title).font(.system(size: 13, weight: .semibold))
                if isMine { Text("· Your team").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel) }
                Spacer()
                if games > 0 {
                    Text("Average solo win rate \(Format.percent(Double(wins) / Double(games)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryLabel)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                header
                Rectangle().fill(Palette.separator).frame(height: 1)
                if slots.isEmpty {
                    InsetRow {
                        Text("This team hasn't loaded yet.").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    PlayerRow(slot: slot, premadeGroup: slot.puuid.flatMap { premades[$0] },
                              showsForm: showsForm, showsNotes: showsNotes,
                              selected: navigation.selectedPlayer == slot.id)
                        .background(index.isMultiple(of: 2) ? Palette.group : Palette.groupAlt)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigation.selectedPlayer = slot.id
                            navigation.showInspector = true
                        }
                }
            }
            .background(Palette.group)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(GeometryReader { Color.clear.preference(key: WidthKey.self, value: $0.size.width) })
            .onPreferenceChange(WidthKey.self) { width = $0 }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Player").frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("Rank").frame(width: 124, alignment: .leading)
            Text("Last 20").frame(width: 92, alignment: .leading)
            Text("On champion").frame(width: 100, alignment: .leading)
            if showsForm { Text("Form").frame(width: 68, alignment: .leading) }
            if showsNotes { Text("Notes").frame(minWidth: 110, maxWidth: .infinity, alignment: .leading) }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.secondaryLabel)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }
}

struct PlayerRow: View {
    @Environment(GameMonitor.self) private var monitor
    let slot: PlayerSlot
    let premadeGroup: Int?
    var showsForm = true
    var showsNotes = true
    var selected = false

    var body: some View {
        let insight = monitor.insight(for: slot)
        let load = slot.puuid.flatMap { monitor.profiles[$0] }
        let loading: Bool = if case .loading? = load { true } else { slot.puuid != nil && load == nil }

        HStack(spacing: 12) {
            playerCell(insight)
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            Group {
                if slot.isHidden {
                    dash.frame(width: 124, alignment: .leading)
                    dash.frame(width: 92, alignment: .leading)
                    dash.frame(width: 100, alignment: .leading)
                } else {
                    rankCell(insight).frame(width: 124, alignment: .leading)
                    recentCell(insight).frame(width: 92, alignment: .leading)
                    championCell(insight).frame(width: 100, alignment: .leading)
                }
            }
            .redacted(reason: loading ? .placeholder : [])

            if showsForm {
                Group {
                    if let insight, !insight.matches.isEmpty {
                        FormSparkline(matches: Array(insight.matches.prefix(10)))
                    } else {
                        dash
                    }
                }
                .frame(width: 68, alignment: .leading)
            }
            if showsNotes {
                notesCell(insight, load: load)
                    .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background {
            if selected { Color.accentColor.opacity(0.18) } else if slot.isLocalPlayer { Color.accentColor.opacity(0.12) }
        }
        .contextMenu {
            if let name = insight?.profile.riotID ?? slot.displayName, !slot.isHidden {
                Button("Copy Riot ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(name, forType: .string)
                }
            }
        }
    }

    private var dash: some View {
        Text("—").font(.system(size: 13)).foregroundStyle(Palette.tertiaryLabel)
    }

    private func playerCell(_ insight: PlayerInsight?) -> some View {
        HStack(spacing: 8) {
            Avatar(champion: slot.championId, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if slot.isHidden {
                        Text("Hidden in ranked champ select").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                    } else {
                        Text(insight?.profile.riotID ?? slot.displayName ?? "Unknown player")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if slot.isLocalPlayer {
                        Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                        Text("You").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondaryLabel)
                    }
                    if let premadeGroup { PremadeMark(group: premadeGroup) }
                }
                Text(subtitle(insight)).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
        }
    }

    private func subtitle(_ insight: PlayerInsight?) -> String {
        [
            DataDragon.shared.champion(slot.championId)?.name ?? (slot.championId == nil ? "Picking…" : nil),
            Role.label(slot.position),
            insight?.profile.level.map { "Lv \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func rankCell(_ insight: PlayerInsight?) -> some View {
        let solo = insight?.profile.solo
        let flex = insight?.profile.flex
        let useFlex = monitor.queueId == 440 || !(solo?.isRanked ?? false) && (flex?.isRanked ?? false)
        return RankLabel(rank: useFlex ? flex : solo, queue: useFlex ? "Flex" : "Solo", showsDetail: false)
    }

    @ViewBuilder private func recentCell(_ insight: PlayerInsight?) -> some View {
        if let recent = insight?.recent, recent.games > 0 {
            VStack(alignment: .leading, spacing: 1) {
                RatedPercent(value: recent.winrate, games: recent.games)
                Text("\(recent.wins)–\(recent.losses) · \(Format.decimal(recent.kda)) KDA")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
            }
        } else {
            valuePlaceholder("No games")
        }
    }

    @ViewBuilder private func championCell(_ insight: PlayerInsight?) -> some View {
        if let insight {
            let champ = insight.onChampion
            VStack(alignment: .leading, spacing: 1) {
                if champ.games > 0 {
                    RatedPercent(value: champ.winrate, games: champ.games)
                } else {
                    Text("—").font(.numeral(13)).foregroundStyle(Palette.tertiaryLabel)
                }
                Text([champ.games > 0 ? "\(champ.games) games" : "No games", insight.mastery.map { "M\($0.level)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
            }
        } else {
            valuePlaceholder("No games")
        }
    }

    private func valuePlaceholder(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("—").font(.numeral(13)).foregroundStyle(Palette.tertiaryLabel)
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
        }
    }

    @ViewBuilder private func notesCell(_ insight: PlayerInsight?, load: ProfileLoad?) -> some View {
        if case .failed(let message)? = load {
            Label("Couldn't load", systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.caution)
                .help(message)
        } else if let tags = insight?.tags, !tags.isEmpty {
            HStack(spacing: 10) {
                ForEach(tags.prefix(2)) { TagLabel(tag: $0) }
                if tags.count > 2 {
                    Text("+\(tags.count - 2)")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryLabel)
                        .help(tags.dropFirst(2).map(\.text).joined(separator: ", "))
                }
            }
            .lineLimit(1)
        } else {
            Text("").font(.system(size: 11))
        }
    }
}

/// Xcode-style inspector with everything known about one player.
struct PlayerInspector: View {
    @Environment(GameMonitor.self) private var monitor
    let slot: PlayerSlot?

    var body: some View {
        if let slot, !slot.isHidden, let insight = monitor.insight(for: slot) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(slot, insight)
                    InsetSection("Ranked") {
                        InsetRow { RankLabel(rank: insight.profile.solo, queue: "Solo") }
                        RowDivider()
                        InsetRow { RankLabel(rank: insight.profile.flex, queue: "Flex") }
                    }
                    InsetSection("Recent") {
                        keyValue("Last \(insight.recent.games)") {
                            Text("\(Format.percent(insight.recent.winrate)) · \(insight.recent.wins)–\(insight.recent.losses)")
                        }
                        RowDivider()
                        keyValue("KDA") { Text(Format.decimal(insight.recent.kda)) }
                        if let name = DataDragon.shared.champion(slot.championId)?.name {
                            RowDivider()
                            keyValue("On \(name)") {
                                Text(insight.onChampion.games > 0
                                     ? "\(Format.percent(insight.onChampion.winrate)) · \(insight.onChampion.games) games · \(Format.decimal(insight.onChampion.kda)) KDA"
                                     : "No recent games")
                            }
                        }
                        RowDivider()
                        keyValue("Mastery") {
                            Text(insight.mastery.map { "Level \($0.level) · \(Format.grouped($0.points)) pts" }
                                 ?? (insight.profile.mastery == nil ? "Unavailable" : "Never played"))
                        }
                    }
                    if !insight.matches.isEmpty {
                        InsetSection("Last 10 games") {
                            ForEach(Array(insight.matches.prefix(10).enumerated()), id: \.element.gameId) { index, match in
                                if index > 0 { RowDivider(inset: 38) }
                                InsetRow(minHeight: 28) {
                                    Avatar(champion: match.championId, size: 20)
                                    if match.win {
                                        Label("Win", systemImage: "checkmark").foregroundStyle(Palette.positive)
                                    } else {
                                        Label("Loss", systemImage: "xmark").foregroundStyle(Palette.negative)
                                    }
                                    Spacer()
                                    KDAText(kills: match.kills, deaths: match.deaths, assists: match.assists)
                                }
                                .font(.system(size: 13))
                            }
                        }
                    }
                    if !insight.championPool.isEmpty {
                        InsetSection("Champion pool") {
                            ForEach(Array(insight.championPool.enumerated()), id: \.element.champion) { index, entry in
                                if index > 0 { RowDivider(inset: 38) }
                                InsetRow(minHeight: 28) {
                                    Avatar(champion: entry.champion, size: 20)
                                    Text(DataDragon.shared.champion(entry.champion)?.name ?? "").font(.system(size: 13))
                                    Spacer()
                                    Text("\(entry.games) games · \(entry.wins)–\(entry.games - entry.wins)")
                                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
                                }
                            }
                        }
                    }
                    if !insight.tags.isEmpty {
                        InsetSection("Notes") {
                            ForEach(Array(insight.tags.enumerated()), id: \.element.id) { index, tag in
                                if index > 0 { RowDivider() }
                                InsetRow { TagLabel(tag: tag) }
                            }
                        }
                    }
                    if let name = insight.profile.riotID {
                        HStack {
                            Button("Match History") {
                                Navigation.shared.selection = .lookup
                                Task { await PlayerLookupStore.shared.search(name) }
                            }
                            Button("Copy Riot ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(name, forType: .string)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("No Player Selected", systemImage: "person.crop.circle",
                                   description: Text("Select a player to see ranked history, recent games and champion pool."))
        }
    }

    private func header(_ slot: PlayerSlot, _ insight: PlayerInsight) -> some View {
        HStack(spacing: 12) {
            Avatar(champion: slot.championId, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.profile.riotID ?? slot.displayName ?? "Unknown player")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text([DataDragon.shared.champion(slot.championId)?.name, Role.label(slot.position), insight.profile.level.map { "Lv \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryLabel)
                RankLabel(rank: insight.profile.solo, showsDetail: false)
            }
        }
    }

    private func keyValue<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        InsetRow {
            Text(label).font(.system(size: 13)).frame(width: 80, alignment: .leading)
            Spacer(minLength: 4)
            value()
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
