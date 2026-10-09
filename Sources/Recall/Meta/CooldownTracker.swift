import Foundation
import Observation

/// Manual enemy summoner-spell timers. The player clicks a spell when they see it used; nothing
/// is detected automatically and ability cooldowns are never tracked.
@Observable @MainActor
final class CooldownTracker {
    static let shared = CooldownTracker()

    struct Key: Hashable {
        let player: String
        let slot: Int
    }

    /// Game time (seconds) at which each marked spell is back up.
    private(set) var readyAt: [Key: Double] = [:]
    private var gameId: Int?

    /// Ionian Boots of Lucidity grant Summoner Spell Haste.
    static let ionianBoots = 3158
    static let ionianHaste = 10.0
    /// Shave a little off so a spell is never shown as down when it might already be back.
    static let safetyMargin = 2.0

    func resetIfNewGame(_ id: Int?) {
        guard id != gameId else { return }
        gameId = id
        readyAt = [:]
    }

    func toggle(player: LivePlayer, slot: Int, spell: SummonerSpellInfo, now: Double) {
        let key = Key(player: player.id, slot: slot)
        if let ready = readyAt[key], ready > now {
            readyAt[key] = nil
        } else {
            readyAt[key] = now + Self.cooldown(spell, for: player)
        }
    }

    func remaining(player: LivePlayer, slot: Int, now: Double) -> Double? {
        guard let ready = readyAt[Key(player: player.id, slot: slot)], ready > now else { return nil }
        return ready - now
    }

    static func cooldown(_ spell: SummonerSpellInfo, for player: LivePlayer) -> Double {
        let haste = player.items.contains { $0.itemID == ionianBoots } ? ionianHaste : 0
        return max(spell.cooldown * 100 / (100 + haste) - safetyMargin, 0)
    }
}

enum CooldownFormat: String, CaseIterable, Identifiable {
    case seconds, minutesSeconds, minutes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seconds: "Seconds (245)"
        case .minutesSeconds: "m:ss (4:05)"
        case .minutes: "Minutes (4m)"
        }
    }

    func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up))
        switch self {
        case .seconds: return "\(total)"
        case .minutesSeconds: return String(format: "%d:%02d", total / 60, total % 60)
        case .minutes: return total >= 60 ? "\(Int((Double(total) / 60).rounded(.up)))m" : "\(total)s"
        }
    }
}
