import Foundation

/// Infers premade groups: two players on the same team in this game who were also on the same
/// team in several of their recent games probably queued together.
enum PremadeDetector {
    static func groups(
        teams: [[String]],
        profiles: [String: PlayerProfile],
        threshold: Int = 2
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        var nextGroup = 0

        for team in teams {
            var parent = Dictionary(team.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
            func root(_ id: String) -> String {
                var id = id
                while let next = parent[id], next != id { id = next }
                return id
            }

            for (i, a) in team.enumerated() {
                guard let gamesA = profiles[a]?.matches else { continue }
                let teamByGame = Dictionary(gamesA.map { ($0.gameId, $0.teamId) }, uniquingKeysWith: { first, _ in first })
                for b in team.dropFirst(i + 1) {
                    guard let gamesB = profiles[b]?.matches else { continue }
                    let shared = gamesB.filter { teamByGame[$0.gameId] == $0.teamId }.count
                    if shared >= threshold {
                        parent[root(b)] = root(a)
                    }
                }
            }

            let members = Dictionary(grouping: team, by: root)
            for group in members.values.sorted(by: { ($0.first ?? "") < ($1.first ?? "") }) where group.count > 1 {
                for id in group { result[id] = nextGroup }
                nextGroup += 1
            }
        }
        return result
    }
}
