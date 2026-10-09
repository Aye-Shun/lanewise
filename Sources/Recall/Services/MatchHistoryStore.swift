import Foundation
import Observation

/// The signed-in player's match history, loaded a page at a time from the League client, plus
/// full ten-player details for games the user opens.
@Observable @MainActor
final class MatchHistoryStore {
    static let shared = MatchHistoryStore()
    static let pageSize = 20

    private(set) var games: [HistoryGame] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var reachedEnd = false
    private(set) var details: [Int: MetaLoad<GameDetail>] = [:]

    /// Whose history is loaded: a PUUID, or "demo" for the preview.
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var loadedAt: Date?

    /// Loads (or reloads) when the player changed or the list is a few minutes old, so a game
    /// that just ended shows up without a manual refresh.
    func refreshIfNeeded() async {
        let current = Self.currentOwner
        let stale = loadedAt.map { Date().timeIntervalSince($0) > 120 } ?? true
        if current != owner || (stale && current != "demo") {
            await reload()
        }
    }

    func reload() async {
        games = []
        details = [:]
        reachedEnd = false
        error = nil
        owner = Self.currentOwner
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, let owner else { return }
        isLoading = true
        defer { isLoading = false }

        if owner == "demo" {
            games = DemoData.history()
            reachedEnd = true
            loadedAt = Date()
            return
        }
        do {
            let page = try await GameMonitor.shared.fetchHistory(puuid: owner, begin: games.count, count: Self.pageSize)
            guard owner == self.owner else { return }  // the player changed while loading
            let known = Set(games.map(\.gameId))
            let parsed = page.compactMap { HistoryGame(game: $0, puuid: owner) }.filter { !known.contains($0.gameId) }
            games = (games + parsed).sorted { $0.createdAt > $1.createdAt }
            reachedEnd = page.count < Self.pageSize
            loadedAt = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadDetail(_ gameId: Int) async {
        if case .loaded? = details[gameId] { return }
        if case .loading? = details[gameId] { return }
        details[gameId] = .loading
        if owner == "demo" {
            if let game = games.first(where: { $0.gameId == gameId }) {
                details[gameId] = .loaded(DemoData.gameDetail(for: game))
            }
            return
        }
        do {
            details[gameId] = .loaded(GameDetail(game: try await GameMonitor.shared.fetchGame(gameId)))
        } catch {
            details[gameId] = .failed(error.localizedDescription)
        }
    }

    private static var currentOwner: String? {
        let monitor = GameMonitor.shared
        if monitor.status == .demo { return "demo" }
        guard monitor.status == .connected else { return nil }
        return monitor.me?.puuid
    }
}
