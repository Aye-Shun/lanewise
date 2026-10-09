import Foundation

/// Features are gated per mode so the app never shows a misleading number
/// (e.g. lane CS targets in ARAM, or gold in Arena where augments distort it).
enum GameMode: String {
    case summonersRift, aram, arena, unsupported

    /// Rotating modes that don't play like normal Summoner's Rift.
    private static let rotatingQueues: Set<Int> = [72, 73, 75, 76, 78, 83, 98, 310, 313, 317, 318, 325, 900, 920, 1010, 1020, 1300, 1400, 1900]

    init(mapId: Int?, queueId: Int?) {
        if let queueId, [1700, 1710].contains(queueId) {
            self = .arena
            return
        }
        switch mapId {
        case 12: self = .aram
        case 30: self = .arena
        case 11, nil:
            self = queueId.map { Self.rotatingQueues.contains($0) } == true ? .unsupported : .summonersRift
        default: self = .unsupported
        }
    }

    /// OP.GG `game_mode` argument, or nil when popular data shouldn't be shown.
    var metaMode: String? {
        switch self {
        case .summonersRift: "ranked"
        case .aram: "aram"
        case .arena, .unsupported: nil
        }
    }

    /// Key for per-mode saved panel positions.
    var layoutKey: String {
        switch self {
        case .summonersRift, .unsupported: "sr"
        case .aram: "aram"
        case .arena: "arena"
        }
    }

    var label: String {
        switch self {
        case .summonersRift: "Summoner's Rift"
        case .aram: "ARAM"
        case .arena: "Arena"
        case .unsupported: "Rotating mode"
        }
    }

    var showsGold: Bool { self != .arena }
    var showsCooldowns: Bool { self == .summonersRift }
    var showsBuilds: Bool { metaMode != nil }
}
