import Foundation

/// Lane minion math for Summoner's Rift (current schedule):
/// - waves spawn from 0:30 every 30s, every 25s from 14:00, every 20s from 30:00
/// - 3 melee + 3 casters per wave; a siege minion every 3rd wave from 1:30, every 2nd after
///   13:30 and every wave after 25:15 (one fewer melee on siege waves after 14:00, one fewer
///   caster after 30:00)
enum FarmBenchmark {
    /// Rough time for a wave to walk from the Nexus to the middle of a lane.
    static let travelTime = 25.0

    static func minionsReachedLane(by gameTime: Double) -> Int {
        let horizon = gameTime - travelTime
        var time = 30.0
        var wave = 0
        var lastSiegeWave: Int?
        var lastSiegeTime = 0.0
        var total = 0

        while time <= horizon {
            wave += 1
            let siege: Bool
            if let last = lastSiegeWave {
                let spacing = lastSiegeTime < 810 ? 3 : (lastSiegeTime < 1515 ? 2 : 1)
                siege = wave - last == spacing
            } else {
                siege = wave == 3
            }
            if siege {
                lastSiegeWave = wave
                lastSiegeTime = time
            }

            let melee = siege && time >= 840 ? 2 : 3
            let casters = time > 1800 ? 2 : 3
            total += melee + casters + (siege ? 1 : 0)

            time += time < 840 ? 30 : (time < 1790 ? 25 : 20)
        }
        return total
    }

    struct Reading {
        let cs: Int
        let perMinute: Double?
        let laneShare: Double?
    }

    /// Lane share is only meaningful for top, mid and bottom on Summoner's Rift.
    static func reading(cs: Int, gameTime: Double, position: MetaPosition?, mode: GameMode) -> Reading {
        let perMinute = gameTime > 60 ? Double(cs) / (gameTime / 60) : nil
        var share: Double?
        if mode == .summonersRift, let position, [.top, .mid, .adc].contains(position) {
            let available = minionsReachedLane(by: gameTime)
            share = available > 0 ? min(Double(cs) / Double(available), 1) : nil
        }
        return Reading(cs: cs, perMinute: perMinute, laneShare: share)
    }
}
