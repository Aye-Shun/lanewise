import SwiftUI

// MARK: - Lanes

/// One row per lane: your player on the left (ally ring), their opponent on the right (enemy
/// ring), rank and season win rate, notes, premade marks, and the lane's item-gold difference.
struct LanesPanel: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(\.overlayScale) private var scale

    var body: some View {
        let lanes = OverlayLane.build(monitor: monitor)
        let premades = monitor.lobby.map { monitor.premadeGroups(for: [$0.blue, $0.red]) } ?? [:]

        VStack(alignment: .leading, spacing: 4 * scale) {
            ForEach(lanes) { lane in
                let isMine = lane.ally?.isLocalPlayer == true
                HStack(spacing: 6 * scale) {
                    LanePlayerCell(slot: lane.ally, live: lane.allyLive,
                                   premadeGroup: lane.ally?.puuid.flatMap { premades[$0] }, mirrored: false)
                    Group {
                        if let ally = lane.allyLive, let enemy = lane.enemyLive {
                            DeltaText(diff: LiveMath.itemGold(ally) - LiveMath.itemGold(enemy), size: 12)
                        } else {
                            Text("vs").sfont(11).foregroundStyle(Color.white.opacity(0.35))
                        }
                    }
                    .frame(width: 52 * scale)
                    LanePlayerCell(slot: lane.enemy, live: lane.enemyLive,
                                   premadeGroup: lane.enemy?.puuid.flatMap { premades[$0] }, mirrored: true)
                }
                .frame(height: 36 * scale)
                .padding(.horizontal, 4 * scale)
                .background {
                    if isMine { RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).fill(HUD.well) }
                }
            }
        }
    }
}

struct OverlayLane: Identifiable {
    let id: Int
    let ally: PlayerSlot?
    let enemy: PlayerSlot?
    let allyLive: LivePlayer?
    let enemyLive: LivePlayer?

    @MainActor
    static func build(monitor: GameMonitor) -> [OverlayLane] {
        guard let lobby = monitor.lobby else { return [] }
        let allyIsBlue = monitor.myTeamIsBlue
        let allies = allyIsBlue ? lobby.blue : lobby.red
        let enemies = allyIsBlue ? lobby.red : lobby.blue
        let livePlayers = monitor.live?.allPlayers ?? []

        func live(_ slot: PlayerSlot?, blue: Bool) -> LivePlayer? {
            guard let champion = slot?.championId else { return nil }
            return livePlayers.first { $0.isBlueSide == blue && DataDragon.shared.championKey(live: $0) == champion }
        }

        return (0..<max(allies.count, enemies.count)).map { index in
            let ally = allies[safe: index]
            let enemy = enemies[safe: index]
            return OverlayLane(id: index, ally: ally, enemy: enemy,
                               allyLive: live(ally, blue: allyIsBlue), enemyLive: live(enemy, blue: !allyIsBlue))
        }
    }
}

struct LanePlayerCell: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(\.overlayScale) private var scale
    let slot: PlayerSlot?
    let live: LivePlayer?
    let premadeGroup: Int?
    let mirrored: Bool

    var body: some View {
        let insight = slot.flatMap { monitor.insight(for: $0) }
        HStack(spacing: 7 * scale) {
            if !mirrored { avatar }
            VStack(alignment: mirrored ? .trailing : .leading, spacing: 1) {
                rankLine(insight)
                detailLine(insight)
            }
            if mirrored { avatar }
        }
        .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)
    }

    private var avatar: some View {
        Avatar(champion: slot?.championId, size: 28, ally: !mirrored,
               dead: live?.isDead == true, respawn: live?.respawnTimer)
    }

    @ViewBuilder private func rankLine(_ insight: PlayerInsight?) -> some View {
        HStack(spacing: 4 * scale) {
            if let rank = insight?.profile.solo ?? nil, rank.isRanked {
                Text(rank.shortTitle).sfont(12, .semibold).foregroundStyle(Palette.tier(rank.tier))
                RatedPercent(value: rank.winrate, games: rank.games, size: 12)
            } else if insight != nil {
                Text("Unranked").sfont(12).foregroundStyle(Palette.secondaryLabel)
            } else if slot?.puuid != nil {
                ProgressView().controlSize(.mini).tint(.white)
            } else {
                Text(slot == nil ? "" : "—").sfont(12).foregroundStyle(Palette.secondaryLabel)
            }
        }
    }

    @ViewBuilder private func detailLine(_ insight: PlayerInsight?) -> some View {
        HStack(spacing: 4 * scale) {
            if let live {
                let kda = LiveMath.kda(live)
                KDAText(kills: kda.0, deaths: kda.1, assists: kda.2, size: 10.5)
                    .foregroundStyle(Palette.secondaryLabel)
            }
            ForEach((insight?.tags ?? []).prefix(3)) { TagLabel(tag: $0, iconOnly: true) }
            if let premadeGroup { PremadeMark(group: premadeGroup) }
        }
        .frame(height: 13 * scale)
    }
}

// MARK: - Spell Timers

/// One row per enemy, top to bottom: champion, name, and their two summoner spells. Click a spell
/// when you see it cast: it greys out, a pie wedge unwinds, and the countdown ticks live.
struct SpellTimersPanel: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(OverlayManager.self) private var overlay
    @Environment(AppSettings.self) private var settings
    @Environment(\.isHUD) private var isHUD
    @Environment(\.overlayScale) private var scale

    var body: some View {
        if let me = monitor.activeLivePlayer, let live = monitor.live {
            let enemies = Role.sorted(live.allPlayers.filter { $0.isBlueSide != me.isBlueSide })
            // Redraw twice a second so the countdown never lags the real clock by a whole second.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let now = monitor.estimatedGameTime(at: context.date)
                VStack(alignment: .leading, spacing: 5 * scale) {
                    ForEach(enemies) { enemy in
                        let dead = enemy.isDead == true
                        HStack(spacing: 6 * scale) {
                            Avatar(champion: DataDragon.shared.championKey(live: enemy), size: 24, ally: false, dead: dead)
                            Text(enemy.championName)
                                .sfont(11, .medium)
                                .foregroundStyle(dead ? Palette.secondaryLabel : Palette.label)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            spellButton(enemy, slot: 0, now: now)
                            spellButton(enemy, slot: 1, now: now)
                        }
                    }
                    if !isHUD || overlay.isMoveMode {
                        Text("Click a spell when you see it cast").sfont(10).foregroundStyle(Palette.secondaryLabel)
                    }
                }
            }
        }
    }

    private func spellButton(_ enemy: LivePlayer, slot: Int, now: Double) -> some View {
        let tracker = CooldownTracker.shared
        let spell = DataDragon.shared.spell(live: enemy.summonerSpells?.both[slot] ?? nil)
        let remaining = tracker.remaining(player: enemy, slot: slot, now: now)
        let total = spell.map { CooldownTracker.cooldown($0, for: enemy) } ?? 1
        let side = 26 * scale

        return Button {
            if let spell { tracker.toggle(player: enemy, slot: slot, spell: spell, now: monitor.estimatedGameTime()) }
        } label: {
            RemoteImage(url: DataDragon.shared.spellIcon(spell), shape: .rounded(6 * scale))
                .frame(width: side, height: side)
                .saturation(remaining == nil ? 1 : 0)
                .overlay {
                    if let remaining {
                        ZStack {
                            PieWedge(fraction: remaining / max(total, 1))
                                .fill(Color.black.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                            Text(settings.cooldownFormat.format(remaining))
                                .font(.numeral(10 * scale, .bold))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .padding(.horizontal, 1)
                                .shadow(color: .black, radius: 1)
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(spell.map { "\($0.name) · \(Int(CooldownTracker.cooldown($0, for: enemy))) s cooldown. Click again to clear." } ?? "")
    }
}

// MARK: - Gold Diff

/// Item gold against your lane opponent and the team, then a butterfly chart per lane.
struct GoldDiffPanel: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(\.overlayScale) private var scale

    var body: some View {
        if let live = monitor.live {
            let allyIsBlue = monitor.activeLivePlayer?.isBlueSide ?? monitor.myTeamIsBlue
            let allies = Role.sorted(live.allPlayers.filter { $0.isBlueSide == allyIsBlue })
            let enemies = Role.sorted(live.allPlayers.filter { $0.isBlueSide != allyIsBlue })
            let score = LiveMath.score(live, allyIsBlue: allyIsBlue)

            VStack(alignment: .leading, spacing: 6 * scale) {
                HStack(alignment: .top, spacing: 6 * scale) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let me = monitor.activeLivePlayer, let opponent = monitor.laneOpponentLive {
                            HeroDelta(diff: LiveMath.itemGold(me) - LiveMath.itemGold(opponent), size: 24)
                            Text("vs \(opponent.championName)").sfont(10.5).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                        } else {
                            Text("No lane opponent").sfont(10.5).foregroundStyle(Palette.secondaryLabel)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Team").sfont(10).foregroundStyle(Palette.secondaryLabel)
                        DeltaText(diff: score.allyGold - score.enemyGold, size: 13)
                    }
                }

                VStack(spacing: 1 * scale) {
                    ForEach(0..<max(allies.count, enemies.count), id: \.self) { index in
                        butterflyRow(ally: allies[safe: index], enemy: enemies[safe: index])
                    }
                }
            }
        }
    }

    private func butterflyRow(ally: LivePlayer?, enemy: LivePlayer?) -> some View {
        let allyGold = ally.map(LiveMath.itemGold) ?? 0
        let enemyGold = enemy.map(LiveMath.itemGold) ?? 0
        let diff = allyGold - enemyGold
        let half: CGFloat = 26 * scale
        let length = min(Double(abs(diff)) / 1500, 1) * half

        return HStack(spacing: 3 * scale) {
            Avatar(champion: ally.flatMap { DataDragon.shared.championKey(live: $0) }, size: 14, ally: true)
            Text(Format.compact(allyGold)).sfont(10, .semibold, rounded: true).frame(width: 28 * scale, alignment: .trailing)
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if diff > 0 { bar(length, Palette.positive) }
                }
                .frame(width: half)
                Rectangle().fill(HUD.hairline).frame(width: 1, height: 10 * scale)
                HStack(spacing: 0) {
                    if diff < 0 { bar(length, Palette.negative) }
                    Spacer(minLength: 0)
                }
                .frame(width: half)
            }
            Text(Format.compact(enemyGold)).sfont(10, .semibold, rounded: true).frame(width: 28 * scale, alignment: .leading)
            Avatar(champion: enemy.flatMap { DataDragon.shared.championKey(live: $0) }, size: 14, ally: false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 15 * scale)
        .accessibilityElement(children: .combine)
    }

    private func bar(_ length: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: max(length, 2), height: 5 * scale)
    }
}

/// Hero number: ▲/▼ for a real lead, "=" when it's within the noise threshold.
struct HeroDelta: View {
    @Environment(\.overlayScale) private var scale
    let diff: Int
    var size: CGFloat = 30

    var body: some View {
        let even = abs(diff) <= 150
        glyphText(Format.compact(abs(diff)),
                  glyph: even ? "equal" : (diff > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"),
                  size: size * scale)
            .foregroundStyle(even ? Palette.label : (diff > 0 ? Palette.positive : Palette.negative))
    }
}

// MARK: - CS

/// CS per minute up front; total CS and share of lane minions (lanes on Summoner's Rift only)
/// underneath, so it fits the narrow HUD.
struct CSPanel: View {
    @Environment(GameMonitor.self) private var monitor
    @Environment(\.overlayScale) private var scale

    var body: some View {
        if let me = monitor.activeLivePlayer {
            let reading = FarmBenchmark.reading(
                cs: Int(me.scores.creepScore ?? 0),
                gameTime: monitor.live?.gameData?.gameTime ?? 0,
                position: MetaPosition(clientPosition: me.position),
                mode: monitor.gameMode
            )
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                    Text(reading.perMinute.map { String(format: "%.1f", $0) } ?? "—").sfont(17, .semibold, rounded: true)
                    Text("CS/min").sfont(11, .semibold).foregroundStyle(Palette.secondaryLabel)
                }
                HStack(spacing: 3 * scale) {
                    Text("\(reading.cs) CS").foregroundStyle(Palette.secondaryLabel)
                    if let share = reading.laneShare {
                        let color: Color = share >= 0.8 ? Palette.positive : share >= 0.6 ? Palette.secondaryLabel : Palette.caution
                        Text("· \(Format.percent(share)) of lane").foregroundStyle(color)
                    }
                }
                .sfont(11, .medium, rounded: true)
            }
            .help("CS per minute counts from the start of the game. \"Of lane\" is the share of lane minions that have reached your lane so far.")
        }
    }
}
