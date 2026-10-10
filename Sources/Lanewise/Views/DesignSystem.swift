import AppKit
import SwiftUI

// Lanewise's look is deliberately plain macOS: neutral system grays, the user's own accent
// color, flat grouped sections with inset separators, sentence-case headers, SF Pro text and
// SF Pro Rounded numerals. The main window follows light/dark; overlay panels are fixed dark HUDs.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// Resolves per appearance, including inside overlay windows that force dark.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }
}

enum Palette {
    static let canvas = Color(light: 0xF5F5F7, dark: 0x1E1E1E)
    static let group = Color(light: 0xFFFFFF, dark: 0x2B2B2B)
    static let groupAlt = Color(light: 0xF9F9FB, dark: 0x303030)
    static let separator = Color(light: NSColor(white: 0, alpha: 0.1), dark: NSColor(white: 1, alpha: 0.1))

    static let label = Color(light: 0x1D1D1F, dark: 0xF2F2F7)
    /// Tuned to pass WCAG AA on both group and canvas (the system color doesn't on white).
    static let secondaryLabel = Color(light: 0x6E6E73, dark: 0xA1A1A6)
    /// Decorative only; never carries essential text.
    static let tertiaryLabel = Color(light: 0x8E8E93, dark: 0x6E6E73)

    static let positive = Color(light: 0x1A7F37, dark: 0x30D158)
    static let negative = Color(light: 0xD70015, dark: 0xFF6961)
    static let caution = Color(light: 0xB25000, dark: 0xFFB340)
    static let sideBlue = Color(light: 0x0A63D6, dark: 0x409CFF)
    static let sideRed = Color(light: 0xC4161C, dark: 0xFF6961)
    static let physical = Color(light: 0xC24E00, dark: 0xFF9F0A)
    static let magic = Color(light: 0x0071A4, dark: 0x64D2FF)

    static func side(blue: Bool) -> Color { blue ? sideBlue : sideRed }

    static func tier(_ tier: String) -> Color {
        switch tier {
        case "IRON": Color(light: 0x6B6560, dark: 0xA19D9A)
        case "BRONZE": Color(light: 0x8F4F2A, dark: 0xD4895A)
        case "SILVER": Color(light: 0x5E6B78, dark: 0xB8C4CF)
        case "GOLD": Color(light: 0x8A6400, dark: 0xF2C14E)
        case "PLATINUM": Color(light: 0x0F7A72, dark: 0x4FD1C5)
        case "EMERALD": Color(light: 0x12783F, dark: 0x3DDC84)
        case "DIAMOND": Color(light: 0x2F5BD3, dark: 0x7AA7FF)
        case "MASTER": Color(light: 0x8A3FC4, dark: 0xD08BFF)
        case "GRANDMASTER": Color(light: 0xB42318, dark: 0xFF7A7A)
        case "CHALLENGER": Color(light: 0x8A6A00, dark: 0xFFE08A)
        default: tertiaryLabel
        }
    }

    private static let premadeColors: [Color] = [
        Color(light: 0xC4245F, dark: 0xFF6482),
        Color(light: 0x0B7A5E, dark: 0x63E6BE),
        Color(light: 0x8F5A1E, dark: 0xE8A15C),
        Color(light: 0x4B44D6, dark: 0x9D9BFF),
    ]

    static func premade(_ group: Int) -> Color { premadeColors[group % premadeColors.count] }
    static func premadeLetter(_ group: Int) -> String { ["A", "B", "C", "D"][group % 4] }

    static func tone(_ tone: PlayerTag.Tone) -> Color {
        switch tone {
        case .good: positive
        case .bad: negative
        case .warning: caution
        case .info: secondaryLabel
        }
    }

    /// System Settings-style icon tile colors for each overlay panel.
    static func tile(_ kind: OverlayPanelKind) -> Color {
        switch kind {
        case .scout: Color(nsColor: NSColor(hex: 0x0A84FF))
        case .cooldowns: Color(nsColor: NSColor(hex: 0xFF9500))
        case .gold: Color(nsColor: NSColor(hex: 0xFFCC00))
        case .build: Color(nsColor: NSColor(hex: 0x8E8E93))
        case .farm: Color(nsColor: NSColor(hex: 0x34C759))
        }
    }
}

/// Fixed colors for the overlay panels, which always sit over the game.
enum HUD {
    static let fill = Color(nsColor: NSColor(hex: 0x1C1C1E, alpha: 0.97))
    static let well = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.12)
    static let ally = Color(nsColor: NSColor(hex: 0x409CFF))
    static let enemy = Color(nsColor: NSColor(hex: 0xFF6961))
}

// MARK: - Environment

private struct OverlayScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
private struct HUDStyleKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Size multiplier for panel content (text size setting × screen factor in the overlay).
    var overlayScale: CGFloat {
        get { self[OverlayScaleKey.self] }
        set { self[OverlayScaleKey.self] = newValue }
    }

    /// True inside overlay windows: avatars get side rings and keycaps use HUD colors.
    var isHUD: Bool {
        get { self[HUDStyleKey.self] }
        set { self[HUDStyleKey.self] = newValue }
    }
}

// MARK: - Typography

extension Font {
    /// SF Pro Rounded with tabular digits: Lanewise's numeral style.
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.overlayScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let rounded: Bool

    func body(content: Content) -> some View {
        content.font(rounded ? .numeral(size * scale, weight) : .system(size: size * scale, weight: weight))
    }
}

extension View {
    /// A font that grows with the text size setting.
    func sfont(_ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false) -> some View {
        modifier(ScaledFont(size: size, weight: weight, rounded: rounded))
    }
}

enum OverlayScale {
    /// Slightly larger panels on taller displays.
    @MainActor
    static var screenFactor: CGFloat {
        let height = (NSScreen.main ?? NSScreen.screens.first)?.frame.height ?? 1000
        return min(max(height / 1050, 0.9), 1.25)
    }
}

// MARK: - Ratings and deltas

/// Win-rate judgement that always comes with a glyph, so it never relies on color alone.
enum Rating {
    case good, neutral, bad, unknown

    init(winrate: Double?, games: Int) {
        guard let winrate, games >= 3 else {
            self = .unknown
            return
        }
        self = winrate >= 0.52 ? .good : winrate < 0.45 ? .bad : .neutral
    }

    var color: Color {
        switch self {
        case .good: Palette.positive
        case .bad: Palette.negative
        case .neutral: Palette.label
        case .unknown: Palette.secondaryLabel
        }
    }

    var glyph: String? {
        switch self {
        case .good: "arrowtriangle.up.fill"
        case .bad: "arrowtriangle.down.fill"
        case .neutral, .unknown: nil
        }
    }
}

/// A numeral with an optional ▲/▼ glyph at 0.55× size.
func glyphText(_ value: String, glyph: String?, size: CGFloat, weight: Font.Weight = .semibold) -> Text {
    let number = Text(value).font(.numeral(size, weight))
    guard let glyph else { return number }
    return Text(Image(systemName: glyph)).font(.system(size: size * 0.55, weight: .bold)).baselineOffset(size * 0.08)
        + Text(" ").font(.system(size: size * 0.3)) + number
}

struct RatedPercent: View {
    @Environment(\.overlayScale) private var scale
    let value: Double?
    let games: Int
    var size: CGFloat = 13
    var weight: Font.Weight = .semibold

    var body: some View {
        let rating = Rating(winrate: value, games: games)
        glyphText(Format.percent(value), glyph: rating.glyph, size: size * scale, weight: weight)
            .foregroundStyle(rating.color)
    }
}

/// Signed gold/CS difference: ▲ 600 / ▼ 150, plain when it's within the noise threshold.
struct DeltaText: View {
    @Environment(\.overlayScale) private var scale
    let diff: Int
    var size: CGFloat = 13
    var weight: Font.Weight = .semibold
    var threshold = 150

    var body: some View {
        if abs(diff) <= threshold {
            glyphText(Format.compact(abs(diff)), glyph: nil, size: size * scale, weight: weight)
                .foregroundStyle(Palette.secondaryLabel)
        } else {
            glyphText(Format.compact(abs(diff)),
                      glyph: diff > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill",
                      size: size * scale, weight: weight)
                .foregroundStyle(diff > 0 ? Palette.positive : Palette.negative)
        }
    }
}

// MARK: - Containers

/// A sentence-case header above a flat grouped box. No borders, no shadows, no icons.
struct InsetSection<Content: View, Accessory: View>: View {
    let title: String
    var trailing: String?
    var footer: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String, trailing: String? = nil, footer: String? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.footer = footer
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.label)
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
                }
                accessory
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.group, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Standard row padding inside an InsetSection.
struct InsetRow<Content: View>: View {
    var minHeight: CGFloat = 32
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    }
}

/// Inset separator: 10 pt, or 46 pt under rows that start with a 28 pt avatar.
struct RowDivider: View {
    var inset: CGFloat = 10

    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1).padding(.leading, inset)
    }
}

/// App Store-style strip of equal cells separated by hairlines.
struct InfoStrip: View {
    struct Cell: Identifiable {
        let id = UUID()
        let value: AnyView
        let label: String
    }

    let cells: [Cell]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 { Rectangle().fill(Palette.separator).frame(width: 1, height: 28) }
                VStack(spacing: 2) {
                    cell.value
                    Text(cell.label).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Small components

struct Keycap: View {
    @Environment(\.isHUD) private var isHUD
    @Environment(\.colorScheme) private var scheme
    @Environment(\.overlayScale) private var scale
    let key: String
    var size: CGFloat = 11

    var body: some View {
        let face: Color = isHUD ? .white.opacity(0.16) : Color(light: 0xFFFFFF, dark: 0x3A3A3C)
        let edge: Color = isHUD ? .black.opacity(0.6) : Color(light: NSColor(hex: 0xC7C7CC), dark: NSColor(white: 0, alpha: 0.6))
        Text(key)
            .font(.numeral(size * scale, .semibold))
            .foregroundStyle(isHUD ? Color.white : Palette.label)
            .padding(.horizontal, 5 * scale)
            .frame(minWidth: 20 * scale, minHeight: 20 * scale)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 5 * scale, style: .continuous).fill(edge).offset(y: 1)
                    RoundedRectangle(cornerRadius: 5 * scale, style: .continuous).fill(face)
                    if !isHUD && scheme == .light {
                        RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    }
                }
            }
    }
}

struct KeycapRow: View {
    let keys: [String]
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { Keycap(key: $0.element) }
        }
    }
}

/// Circular champion/profile avatar. Data Dragon art has a baked-in rim, so it's cropped 1.12×.
struct Avatar: View {
    @Environment(\.isHUD) private var isHUD
    @Environment(\.overlayScale) private var scale
    let url: URL?
    var size: CGFloat = 28
    /// Overlay only: ally/enemy ring.
    var ally: Bool?
    var dead = false
    var respawn: Double?

    init(champion: Int?, size: CGFloat = 28, ally: Bool? = nil, dead: Bool = false, respawn: Double? = nil) {
        self.init(url: DataDragon.shared.championIcon(champion), size: size, ally: ally, dead: dead, respawn: respawn)
    }

    init(url: URL?, size: CGFloat = 28, ally: Bool? = nil, dead: Bool = false, respawn: Double? = nil) {
        self.url = url
        self.size = size
        self.ally = ally
        self.dead = dead
        self.respawn = respawn
    }

    var body: some View {
        let side = size * scale
        RemoteImage(url: url, shape: .circle, crop: 1.12)
            .frame(width: side, height: side)
            .saturation(dead ? 0 : 1)
            .opacity(dead ? 0.5 : 1)
            .overlay {
                if isHUD, let ally {
                    Circle().strokeBorder(ally ? HUD.ally : HUD.enemy, lineWidth: 2)
                }
            }
            .overlay {
                if dead, let respawn, respawn > 0 {
                    Text("\(Int(respawn.rounded(.up)))")
                        .font(.numeral(11 * scale, .bold))
                        .foregroundStyle(.white)
                        .frame(width: side * 0.6, height: side * 0.6)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
    }
}

struct ItemIcon: View {
    @Environment(\.isHUD) private var isHUD
    @Environment(\.overlayScale) private var scale
    let id: Int
    var size: CGFloat = 24
    var owned = false
    var next = false

    var body: some View {
        let side = size * scale
        RemoteImage(url: DataDragon.shared.itemIcon(id), shape: .rounded(side * 0.18))
            .frame(width: side, height: side)
            .opacity(owned ? 0.4 : 1)
            .overlay(alignment: .bottomTrailing) {
                if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10 * scale, weight: .bold))
                        .foregroundStyle(Palette.positive)
                        .background(Circle().fill(Color.black).padding(1))
                        .offset(x: 2, y: 2)
                }
            }
            .overlay {
                if next {
                    RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                        .strokeBorder(isHUD ? Color.white : Color.accentColor, lineWidth: 2)
                }
            }
            .help(DataDragon.shared.item(id)?.name ?? "")
    }
}

struct SpellIcon: View {
    @Environment(\.overlayScale) private var scale
    let spell: SummonerSpellInfo?
    var size: CGFloat = 24

    var body: some View {
        RemoteImage(url: DataDragon.shared.spellIcon(spell), shape: .rounded(size * scale * 0.22))
            .frame(width: size * scale, height: size * scale)
            .help(spell?.name ?? "")
    }
}

struct RuneIcon: View {
    let id: Int
    var size: CGFloat = 22

    var body: some View {
        RemoteImage(url: DataDragon.shared.runeIcon(id), shape: .circle)
            .frame(width: size, height: size)
            .help(DataDragon.shared.runeName(id))
    }
}

/// Tag as icon + text, no background. The symbol carries the meaning, color only reinforces it.
struct TagLabel: View {
    @Environment(\.overlayScale) private var scale
    let tag: PlayerTag
    var iconOnly = false

    var body: some View {
        if iconOnly {
            Image(systemName: tag.symbol)
                .font(.system(size: 10 * scale))
                .foregroundStyle(Palette.tone(tag.tone))
                .help(tag.text)
        } else {
            HStack(spacing: 3) {
                Image(systemName: tag.symbol).font(.system(size: 10)).foregroundStyle(Palette.tone(tag.tone))
                Text(tag.text).font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
            }
        }
    }
}

struct PremadeMark: View {
    @Environment(\.overlayScale) private var scale
    let group: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "link")
            Text(Palette.premadeLetter(group))
        }
        .font(.system(size: 10 * scale, weight: .semibold))
        .foregroundStyle(Palette.premade(group))
        .help("Premade group \(Palette.premadeLetter(group))")
    }
}

/// Last games as bars: tall = win, short = loss, so it reads without color.
struct FormSparkline: View {
    let matches: [MatchSummary]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(matches, id: \.gameId) { match in
                RoundedRectangle(cornerRadius: 1)
                    .fill(match.win ? Palette.positive : Palette.negative)
                    .frame(width: 5, height: match.win ? 14 : 6)
                    .help("\(match.win ? "Win" : "Loss") · \(DataDragon.shared.champion(match.championId)?.name ?? "") \(match.kills)/\(match.deaths)/\(match.assists)")
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityLabel("Last \(matches.count): \(matches.filter(\.win).count) wins, \(matches.filter { !$0.win }.count) losses")
    }
}

/// Tier swatch + "Gold I" + "54 LP", with an optional second line of queue win rate.
struct RankLabel: View {
    let rank: RankInfo?
    var queue: String?
    var showsDetail = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                if let rank, rank.isRanked {
                    RoundedRectangle(cornerRadius: 2.5).fill(Palette.tier(rank.tier)).frame(width: 10, height: 10)
                    Text(rank.title).font(.system(size: 13)).foregroundStyle(Palette.label)
                    Text("\(rank.leaguePoints) LP").font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.secondaryLabel)
                } else {
                    RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(Palette.tertiaryLabel, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 10, height: 10)
                    Text("Unranked").font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                }
            }
            if showsDetail, let rank, rank.isRanked {
                HStack(spacing: 0) {
                    Text("\(queue ?? "Solo") · ").foregroundStyle(Palette.secondaryLabel)
                    RatedPercent(value: rank.winrate, games: rank.games, size: 11, weight: .regular)
                    Text(" · \(rank.games) games").foregroundStyle(Palette.secondaryLabel)
                }
                .font(.system(size: 11))
            }
        }
    }
}

/// Damage-mix row: words carry the numbers, the bar only illustrates them.
struct DamageMixRow: View {
    @Environment(\.overlayScale) private var scale
    let title: String
    let composition: TeamComposition

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack {
                Text(title).sfont(12)
                Spacer()
                (Text("Physical \(Format.percent(composition.adShare))").foregroundColor(Palette.physical)
                    + Text(" · ").foregroundColor(Palette.secondaryLabel)
                    + Text("Magic \(Format.percent(composition.apShare))").foregroundColor(Palette.magic))
                    .sfont(11, .semibold)
            }
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    Palette.physical.frame(width: max(proxy.size.width * composition.adShare - 0.5, 0))
                    Palette.magic
                }
            }
            .frame(height: 6 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
            .accessibilityLabel("Physical \(Format.percent(composition.adShare)), magic \(Format.percent(composition.apShare))")
        }
    }
}

/// Pie wedge drawn clockwise from 12 o'clock; used to shade a spell that's still cooling down.
struct PieWedge: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = hypot(rect.width, rect.height)
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(max(fraction, 0), 1)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Ring gauge for lane CS share.
struct ShareRing: View {
    @Environment(\.overlayScale) private var scale
    let share: Double

    var body: some View {
        let color: Color = share >= 0.8 ? Palette.positive : share >= 0.6 ? Palette.label : Palette.caution
        VStack(spacing: 2 * scale) {
            ZStack {
                Circle().stroke(Palette.label.opacity(0.14), lineWidth: 5 * scale)
                Circle().trim(from: 0, to: share)
                    .stroke(color, style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Format.percent(share)).sfont(12, .semibold, rounded: true)
            }
            .frame(width: 44 * scale, height: 44 * scale)
            Text("of lane").sfont(10).foregroundStyle(Palette.secondaryLabel)
        }
        .accessibilityLabel("\(Format.percent(share)) of lane minions")
    }
}

// MARK: - Formatting and live math

enum Format {
    static func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    static func decimal(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }

    static func compact(_ value: Int) -> String {
        switch abs(value) {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 100_000...: return "\(value / 1000)k"
        case 1_000...: return String(format: "%.1fk", Double(value) / 1000)
        default: return "\(value)"
        }
    }

    static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// "2 hr. ago", "3 days ago".
    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@MainActor
enum LiveMath {
    struct Score {
        var allyKills = 0
        var enemyKills = 0
        var allyGold = 0
        var enemyGold = 0
    }

    static func itemGold(_ player: LivePlayer) -> Int {
        player.items.reduce(0) { $0 + DataDragon.shared.value(of: $1) }
    }

    static func kda(_ player: LivePlayer) -> (Int, Int, Int) {
        let s = player.scores
        return (Int(s.kills ?? 0), Int(s.deaths ?? 0), Int(s.assists ?? 0))
    }

    static func score(_ live: LiveGameData, allyIsBlue: Bool) -> Score {
        var score = Score()
        for player in live.allPlayers {
            let kills = Int(player.scores.kills ?? 0)
            let gold = itemGold(player)
            if player.isBlueSide == allyIsBlue {
                score.allyKills += kills
                score.allyGold += gold
            } else {
                score.enemyKills += kills
                score.enemyGold += gold
            }
        }
        return score
    }
}

/// K/D/A with the slashes in secondary color.
struct KDAText: View {
    @Environment(\.overlayScale) private var scale
    let kills: Int
    let deaths: Int
    let assists: Int
    var size: CGFloat = 13

    var body: some View {
        (Text("\(kills)") + Text("/").foregroundColor(Palette.secondaryLabel)
            + Text("\(deaths)") + Text("/").foregroundColor(Palette.secondaryLabel) + Text("\(assists)"))
            .font(.system(size: size * scale).monospacedDigit())
    }
}
