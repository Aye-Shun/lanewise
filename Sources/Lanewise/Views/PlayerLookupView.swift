import SwiftUI

struct PlayerLookupView: View {
    @Environment(PlayerLookupStore.self) private var lookup

    var body: some View {
        @Bindable var lookup = lookup
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondaryLabel)
                TextField("Riot ID, like Name#TAG", text: $lookup.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { Task { await lookup.search() } }
                Button("Look Up") { Task { await lookup.search() } }
                    .disabled(lookup.query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            .background(Palette.group, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if !lookup.recent.isEmpty {
                HStack(spacing: 12) {
                    Text("Recent").font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                    ForEach(lookup.recent.prefix(5), id: \.self) { riotID in
                        Button(riotID) { Task { await lookup.search(riotID) } }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }

            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        switch lookup.state {
        case .idle:
            ContentUnavailableView("Look Up a Player", systemImage: "magnifyingglass",
                                   description: Text("Enter a Riot ID to see their rank, recent games and champion pool."))
        case .searching(let riotID):
            VStack(spacing: 10) {
                ProgressView()
                Text("Looking up \(riotID)…").foregroundStyle(Palette.secondaryLabel)
            }
        case .notFound(let riotID):
            ContentUnavailableView("No Player Found", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("Couldn't find \(riotID). Check the name and tag."))
        case .failed(let message):
            ContentUnavailableView("Can't Look Up", systemImage: "exclamationmark.triangle", description: Text(message))
        case .found(let profile):
            if let store = lookup.history {
                MatchHistoryView(topContent: AnyView(LookupHeader(profile: profile)), showsPostGame: false)
                    .environment(store)
            }
        }
    }
}

private struct LookupHeader: View {
    let profile: PlayerProfile

    var body: some View {
        InsetSection("Player") {
            InsetRow(minHeight: 60) {
                Avatar(url: DataDragon.shared.profileIcon(profile.summoner?.profileIconId), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.riotID ?? "Player").font(.system(size: 17, weight: .semibold))
                    if let level = profile.level {
                        Text("Level \(level)").font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    RankLabel(rank: profile.solo, queue: "Solo")
                    RankLabel(rank: profile.flex, queue: "Flex")
                }
            }
        }
    }
}

/// How the last game went, at the top of your own Match History.
struct PostGameCard: View {
    let summary: PostGameSummary

    var body: some View {
        let game = summary.game
        InsetSection("Last game", trailing: Format.relative(game.createdAt), accessory: {
            Button {
                PostGameTracker.shared.summary = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }) {
            InsetRow(minHeight: 48) {
                Avatar(champion: game.me.championId, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    ResultLabel(game: game)
                    Text("\(DataDragon.shared.champion(game.me.championId)?.name ?? "") · \(game.queueName) · \(Format.clock(Double(game.durationSeconds)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
                if let promotion = summary.promotion {
                    Label(promotion, systemImage: "rosette").font(.system(size: 13, weight: .semibold))
                }
            }
            RowDivider(inset: 0)
            InfoStrip(cells: [
                .init(value: AnyView(lpChange), label: "LP"),
                .init(value: compared(game.me.kda, summary.averageKDA, format: "%.1f"), label: "KDA vs your average"),
                .init(value: compared(game.csPerMinute, summary.averageCSPerMinute, format: "%.1f"), label: "CS/min vs average"),
                .init(value: compared(summary.damagePerMinute, summary.averageDamagePerMinute, format: "%.0f"), label: "Damage/min vs average"),
            ])
        }
    }

    @ViewBuilder private var lpChange: some View {
        if let lp = summary.lpChange {
            glyphText("\(abs(lp))", glyph: lp >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill", size: 17)
                .foregroundStyle(lp >= 0 ? Palette.positive : Palette.negative)
        } else {
            Text("—").font(.numeral(17)).foregroundStyle(Palette.tertiaryLabel)
        }
    }

    private func compared(_ value: Double, _ average: Double?, format: String) -> AnyView {
        AnyView(VStack(spacing: 0) {
            Text(String(format: format, value)).font(.numeral(17))
            if let average {
                let diff = value - average
                glyphText(String(format: format, abs(diff)),
                          glyph: diff >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill", size: 10, weight: .medium)
                    .foregroundStyle(diff >= 0 ? Palette.positive : Palette.negative)
            }
        })
    }
}
