import SwiftUI

/// The signed-in player's recent games: a summary, a filterable list, and details in the inspector.
struct MatchHistoryView: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(MatchHistoryStore.self) private var store
    @Environment(Navigation.self) private var navigation
    @State private var filter: HistoryFilter = .all
    /// Shown above the summary (Player Lookup puts the player's profile here).
    var topContent: AnyView?
    /// The "Last game" card belongs to your own history only.
    var showsPostGame = true

    var body: some View {
        let games = store.games.filter { filter.matches($0) }
        DetailPage(maxWidth: nil) {
            if let topContent { topContent }
            if showsPostGame, let summary = PostGameTracker.shared.summary {
                PostGameCard(summary: summary)
            }
            summary(games)

            InsetSection("Games", accessory: {
                Picker("Filter", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }) {
                header
                Rectangle().fill(Palette.separator).frame(height: 1)
                if games.isEmpty {
                    if store.isLoading {
                        LoadingRow(text: "Loading match history…")
                    } else {
                        InsetRow {
                            Text(store.games.isEmpty ? "No games yet." : "No \(filter.rawValue.lowercased()) games in the loaded history.")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondaryLabel)
                        }
                    }
                }
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    HistoryRow(game: game, selected: navigation.selectedGame == game.gameId)
                        .background(index.isMultiple(of: 2) ? Palette.group : Palette.groupAlt)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigation.selectedGame = game.gameId
                            navigation.showInspector = true
                        }
                }
            }

            HStack(spacing: 10) {
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.caution)
                }
                Spacer()
                if store.isLoading && !store.games.isEmpty {
                    ProgressView().controlSize(.small)
                }
                if !store.reachedEnd && !store.games.isEmpty {
                    Button("Load More") { Task { await store.loadMore() } }
                        .disabled(store.isLoading)
                }
            }
        }
        .task(id: monitor.me?.puuid ?? monitor.status.debugName) {
            await store.refreshIfNeeded()
        }
    }

    private func summary(_ games: [HistoryGame]) -> some View {
        let stats = HistorySummary(games)
        return InsetSection("Summary", trailing: stats.games > 0 ? "\(stats.games) games, remakes excluded" : nil, accessory: {
            Button {
                Task { await store.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(store.isLoading)
        }) {
            InfoStrip(cells: [
                .init(value: AnyView(RatedPercent(value: stats.winrate, games: stats.games, size: 17)), label: "Win rate"),
                .init(value: AnyView(Text(stats.games > 0 ? "\(stats.wins)–\(stats.games - stats.wins)" : "—").font(.numeral(17))), label: "Record"),
                .init(value: AnyView(Text(Format.decimal(stats.kda)).font(.numeral(17))), label: "KDA"),
                .init(value: AnyView(Text(Format.decimal(stats.csPerMinute)).font(.numeral(17))), label: "CS/min"),
            ])
            if !stats.champions.isEmpty {
                RowDivider(inset: 0)
                InsetRow {
                    Text("Most played").font(.system(size: 13))
                    Spacer()
                    ForEach(stats.champions, id: \.champion) { entry in
                        HStack(spacing: 6) {
                            Avatar(champion: entry.champion, size: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(entry.games) games").font(.system(size: 11)).monospacedDigit()
                                RatedPercent(value: Double(entry.wins) / Double(entry.games), games: entry.games, size: 11, weight: .medium)
                            }
                        }
                        .help(DataDragon.shared.champion(entry.champion)?.name ?? "")
                        .padding(.leading, 10)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Result").frame(width: 56, alignment: .leading)
            Text("Champion").frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("KDA").frame(width: 96, alignment: .leading)
            Text("CS").frame(width: 76, alignment: .leading)
            Text("Build").frame(width: 226, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.secondaryLabel)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }
}

struct HistoryRow: View {
    let game: HistoryGame
    var selected = false

    var body: some View {
        let me = game.me
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                ResultLabel(game: game)
                Text(Format.clock(Double(game.durationSeconds))).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .frame(width: 56, alignment: .leading)

            HStack(spacing: 8) {
                Avatar(champion: me.championId, size: 28)
                    .overlay(alignment: .bottomTrailing) { LevelBadge(level: me.level) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(DataDragon.shared.champion(me.championId)?.name ?? "Champion")
                        .font(.system(size: 13, weight: .medium))
                    Text("\(game.queueName) · \(Format.relative(game.createdAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                KDAText(kills: me.kills, deaths: me.deaths, assists: me.assists)
                Text("\(Format.decimal(me.kda)) KDA").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(me.cs) CS").font(.system(size: 13).monospacedDigit())
                Text("\(String(format: "%.1f", game.csPerMinute))/min").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .frame(width: 76, alignment: .leading)

            BuildStrip(player: me)
                .frame(width: 226, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(selected ? Color.accentColor.opacity(0.18) : .clear)
    }
}

/// Win / Loss / Remake, always with a glyph so it doesn't rely on color.
struct ResultLabel: View {
    let game: HistoryGame

    var body: some View {
        Group {
            if game.isRemake {
                Label("Remake", systemImage: "arrow.uturn.backward").foregroundStyle(Palette.secondaryLabel)
            } else if game.me.win {
                Label("Win", systemImage: "checkmark").foregroundStyle(Palette.positive)
            } else {
                Label("Loss", systemImage: "xmark").foregroundStyle(Palette.negative)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .labelStyle(TightLabelStyle())
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .bold))
            configuration.title
        }
    }
}

struct LevelBadge: View {
    let level: Int

    var body: some View {
        if level > 0 {
            Text("\(level)")
                .font(.numeral(9, .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.black.opacity(0.75)))
                .offset(x: 3, y: 3)
        }
    }
}

/// Summoner spells and keystone, then the seven item slots.
struct BuildStrip: View {
    let player: HistoryPlayer
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(player.spells, id: \.self) { SpellIcon(spell: DataDragon.shared.spell($0), size: size) }
                if let keystone = player.keystone { RuneIcon(id: keystone, size: size) }
            }
            HStack(spacing: 2) {
                ForEach(Array(player.items.prefix(7).enumerated()), id: \.offset) { _, id in
                    if id > 0 {
                        ItemIcon(id: id, size: size)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.tertiaryLabel.opacity(0.18))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
    }
}

// MARK: - Inspector

struct MatchDetailInspector: View {
    @Environment(MatchHistoryStore.self) private var store
    let gameId: Int?

    var body: some View {
        if let gameId, let game = store.games.first(where: { $0.gameId == gameId }) {
            let me = game.me
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Avatar(champion: me.championId, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            ResultLabel(game: game)
                            Text(game.queueName).font(.system(size: 15, weight: .semibold))
                            Text("\(game.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(Format.clock(Double(game.durationSeconds)))")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondaryLabel)
                        }
                    }

                    InsetSection("Your game") {
                        keyValue("KDA", "\(me.kills)/\(me.deaths)/\(me.assists) · \(Format.decimal(me.kda))")
                        RowDivider()
                        keyValue("CS", "\(me.cs) · \(String(format: "%.1f", game.csPerMinute))/min")
                        RowDivider()
                        keyValue("Gold", Format.grouped(me.gold))
                        RowDivider()
                        keyValue("Damage", Format.grouped(me.damage))
                        RowDivider()
                        keyValue("Vision", "\(me.vision)")
                        RowDivider()
                        InsetRow { BuildStrip(player: me, size: 22) }
                    }

                    switch store.details[gameId] {
                    case .loaded(let detail)?:
                        team("Blue side", detail.blue, maxDamage: detail.maxDamage, me: me.puuid)
                        team("Red side", detail.red, maxDamage: detail.maxDamage, me: me.puuid)
                    case .failed(let message)?:
                        Text(message).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                    default:
                        InsetSection("Players") { LoadingRow(text: "Loading game…") }
                    }
                }
                .padding(16)
            }
            .task(id: gameId) { await store.loadDetail(gameId) }
        } else {
            ContentUnavailableView("No Game Selected", systemImage: "clock.arrow.circlepath",
                                   description: Text("Select a game to see both teams and your full stats."))
        }
    }

    private func team(_ title: String, _ players: [HistoryPlayer], maxDamage: Int, me: String?) -> some View {
        let won = players.first?.win == true
        return InsetSection(title, trailing: won ? "Victory" : "Defeat") {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                if index > 0 { RowDivider(inset: 40) }
                let isMe = player.puuid != nil && player.puuid == me
                InsetRow(minHeight: 36) {
                    Avatar(champion: player.championId, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(player.name ?? DataDragon.shared.champion(player.championId)?.name ?? "Player")
                                .font(.system(size: 12, weight: isMe ? .semibold : .medium))
                                .lineLimit(1)
                            if isMe { Image(systemName: "person.fill").font(.system(size: 9)).foregroundStyle(Color.accentColor) }
                        }
                        HStack(spacing: 0) {
                            KDAText(kills: player.kills, deaths: player.deaths, assists: player.assists, size: 11)
                            Text(" · \(player.cs) CS").font(.system(size: 11)).monospacedDigit()
                        }
                        .foregroundStyle(Palette.secondaryLabel)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.compact(player.damage)).font(.numeral(11, .medium))
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.accentColor.opacity(0.7))
                                .frame(width: proxy.size.width * CGFloat(player.damage) / CGFloat(max(maxDamage, 1)))
                        }
                        .frame(width: 44, height: 4)
                    }
                    .help("Damage to champions")
                }
            }
        }
    }

    private func keyValue(_ label: String, _ value: String) -> some View {
        InsetRow {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 13)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
        }
    }
}

extension ConnectionStatus {
    var debugName: String {
        switch self {
        case .searching: "searching"
        case .connected: "connected"
        case .demo: "demo"
        }
    }
}
