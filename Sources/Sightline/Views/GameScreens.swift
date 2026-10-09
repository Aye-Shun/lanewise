import SwiftUI

/// The overlay panels' content in window styling, for a second screen or between deaths.
struct GamePlanView: View {
    @Environment(GameMonitor.self) private var monitor

    var body: some View {
        let mode = monitor.gameMode
        let hasLive = monitor.live != nil
        DetailPage(maxWidth: nil) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    if hasLive && mode.showsCooldowns { section(.cooldowns) }
                    if hasLive && mode.showsGold { section(.gold) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                VStack(spacing: 20) {
                    if mode.showsBuilds { section(.build) }
                    if hasLive && mode == .summonersRift { section(.farm) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .environment(\.overlayScale, 1.15)
        .task(id: MetaStore.championKey(monitor.myChampionId ?? 0, monitor.myPosition, mode)) {
            await MetaStore.shared.ensureChampion(monitor.myChampionId, monitor.myPosition, mode)
        }
    }

    private func section(_ kind: OverlayPanelKind) -> some View {
        InsetSection(kind.title) {
            PanelContent(kind: kind)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Summary plus one table per team, with the item gold the in-game Tab screen doesn't show.
struct ScoreboardView: View {
    @Environment(GameMonitor.self) private var monitor
    let live: LiveGameData

    var body: some View {
        let blue = Role.sorted(live.allPlayers.filter(\.isBlueSide))
        let red = Role.sorted(live.allPlayers.filter { !$0.isBlueSide })
        let score = LiveMath.score(live, allyIsBlue: true)

        DetailPage(maxWidth: nil) {
            summary(score)
            ScoreTable(title: "Blue side", blue: true, players: blue, opponents: red, activeRiotID: live.activePlayer?.riotId)
            ScoreTable(title: "Red side", blue: false, players: red, opponents: blue, activeRiotID: live.activePlayer?.riotId)
        }
    }

    private func summary(_ score: LiveMath.Score) -> some View {
        let total = max(score.allyGold + score.enemyGold, 1)
        let blueShare = CGFloat(score.allyGold) / CGFloat(total)

        return InsetSection("Summary") {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Blue").font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                        Text("\(score.allyKills)").font(.numeral(34)).foregroundStyle(Palette.sideBlue)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(Format.clock(live.gameData?.gameTime ?? 0)).font(.numeral(17))
                        Text(live.gameData?.gameMode?.capitalized ?? "").font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Red").font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                        Text("\(score.enemyKills)").font(.numeral(34)).foregroundStyle(Palette.sideRed)
                    }
                }
                GeometryReader { proxy in
                    HStack(spacing: 1) {
                        Palette.sideBlue.frame(width: max(proxy.size.width * blueShare - 0.5, 0))
                        Palette.sideRed
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                HStack {
                    Text("\(Format.compact(score.allyGold)) item gold").foregroundStyle(Palette.sideBlue)
                    Spacer()
                    DeltaText(diff: score.allyGold - score.enemyGold)
                    Spacer()
                    Text("\(Format.compact(score.enemyGold)) item gold").foregroundStyle(Palette.sideRed)
                }
                .font(.system(size: 11))
            }
            .padding(12)
        }
    }
}

private struct ScoreTable: View {
    let title: String
    let blue: Bool
    let players: [LivePlayer]
    let opponents: [LivePlayer]
    let activeRiotID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Palette.side(blue: blue)).frame(width: 8, height: 8)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                    Text("K/D/A").frame(width: 72)
                    Text("CS").frame(width: 48, alignment: .trailing)
                    Text("Items").frame(width: 186, alignment: .leading)
                    Text("Item gold").frame(width: 64, alignment: .trailing)
                    Text("vs lane").frame(width: 64, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.horizontal, 10)
                .frame(height: 24)
                Rectangle().fill(Palette.separator).frame(height: 1)

                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    row(player).background(index.isMultiple(of: 2) ? Palette.group : Palette.groupAlt)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func row(_ player: LivePlayer) -> some View {
        let gold = LiveMath.itemGold(player)
        let opponent = opponents.first { $0.position.nonEmpty != nil && $0.position == player.position }
        let isActive = player.riotId != nil && player.riotId == activeRiotID
        let dead = player.isDead == true
        let kda = LiveMath.kda(player)

        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Avatar(champion: DataDragon.shared.championKey(live: player), size: 28, dead: dead)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(player.level ?? 1)")
                            .font(.numeral(9, .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(player.displayName).font(.system(size: 13, weight: isActive ? .semibold : .regular)).lineLimit(1)
                        if isActive { Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor) }
                    }
                    if dead {
                        Label("Respawn in \(Int((player.respawnTimer ?? 0).rounded(.up))) s", systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.negative)
                    } else {
                        Text([player.championName, Role.label(player.position)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KDAText(kills: kda.0, deaths: kda.1, assists: kda.2).frame(width: 72)
            Text("\(Int(player.scores.creepScore ?? 0))").font(.system(size: 13).monospacedDigit()).frame(width: 48, alignment: .trailing)
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { slot in
                    if let item = player.items.first(where: { $0.slot == slot }) {
                        ItemIcon(id: item.itemID, size: 24)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.tertiaryLabel.opacity(0.18))
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .frame(width: 186, alignment: .leading)
            Text(Format.compact(gold)).font(.system(size: 13).monospacedDigit()).frame(width: 64, alignment: .trailing)
            Group {
                if let opponent {
                    DeltaText(diff: gold - LiveMath.itemGold(opponent))
                } else {
                    Text("—").foregroundStyle(Palette.tertiaryLabel)
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 40)
        .background(isActive ? Color.accentColor.opacity(0.12) : .clear)
    }
}
