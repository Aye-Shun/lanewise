import Foundation
import Observation

/// Look up any player by Riot ID: their profile through the League client, plus a match history
/// store of their own.
@Observable @MainActor
final class PlayerLookupStore {
    static let shared = PlayerLookupStore()

    enum State {
        case idle
        case searching(String)
        case found(PlayerProfile)
        case notFound(String)
        case failed(String)
    }

    var query = ""
    private(set) var state: State = .idle
    private(set) var history: MatchHistoryStore?
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentLookups") ?? []

    var foundProfile: PlayerProfile? {
        if case .found(let profile) = state { return profile }
        return nil
    }

    func search(_ text: String? = nil) async {
        let riotID = (text ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        query = riotID
        guard let hash = riotID.lastIndex(of: "#"), hash != riotID.startIndex, riotID.index(after: hash) != riotID.endIndex else {
            state = .failed("Enter a Riot ID with its tag, like Name#TAG.")
            return
        }
        let name = String(riotID[..<hash])
        let tag = String(riotID[riotID.index(after: hash)...])
        let monitor = GameMonitor.shared
        state = .searching(riotID)

        let puuid: String?
        let profile: PlayerProfile?
        switch monitor.status {
        case .demo:
            puuid = DemoData.puuid(forRiotID: riotID)
            profile = puuid.flatMap { DemoData.scenario().profiles[$0] }
        case .connected:
            puuid = await monitor.lookupPUUID(gameName: name, tagLine: tag)
            if let puuid, let client = monitor.lcu {
                profile = try? await ProfileLoader(client: client).load(puuid: puuid)
            } else {
                profile = nil
            }
        case .searching:
            state = .failed("Open League of Legends to look players up.")
            return
        }
        guard query == riotID else { return }  // a newer search started meanwhile
        guard let puuid else {
            state = .notFound(riotID)
            return
        }
        guard let profile else {
            state = .failed("Couldn't load \(riotID) from the League client.")
            return
        }

        let store = MatchHistoryStore(owner: monitor.status == .demo ? "demo" : puuid)
        history = store
        state = .found(profile)
        remember(profile.riotID ?? riotID)
        await store.reload()
    }

    private func remember(_ riotID: String) {
        recent.removeAll { $0.caseInsensitiveCompare(riotID) == .orderedSame }
        recent.insert(riotID, at: 0)
        recent = Array(recent.prefix(8))
        UserDefaults.standard.set(recent, forKey: "recentLookups")
    }
}
