import Foundation

/// Writes one app-owned rune page ("Lanewise: <champion>") and selects it. This is the only
/// write Lanewise makes to the client, and it only runs after the user confirms it.
struct RunePageWriter {
    enum WriteError: LocalizedError {
        case incompletePage
        case noFreeSlot

        var errorDescription: String? {
            switch self {
            case .incompletePage: "This rune page is missing runes, so it wasn't applied."
            case .noFreeSlot: "No free rune page slot. Delete one page in the League client and try again."
            }
        }
    }

    static let namePrefix = "Lanewise: "
    /// The prefix before the rename: the saved page id can still point at a page named with it.
    private static let legacyNamePrefix = "Recall: "
    private static let pageIDKey = "runePageID"

    let client: LCUClient

    func apply(_ page: OPRunePage, championName: String) async throws {
        guard page.isComplete, let primary = page.primaryPageId, let secondary = page.secondaryPageId else {
            throw WriteError.incompletePage
        }

        // Replace only the page Lanewise created last time (matched by id, not just by name), so
        // a page the player happened to name "Lanewise: …" is never touched.
        let pages = (try? await client.get("/lol-perks/v1/pages", as: [LCUPerkPage].self)) ?? []
        let ownID = UserDefaults.standard.object(forKey: Self.pageIDKey) as? Int
        if let ownID, let existing = pages.first(where: { $0.id == ownID && Self.isOwnName($0.name) && $0.isDeletable != false }) {
            try await client.send("DELETE", "/lol-perks/v1/pages/\(existing.id)")
        } else if let inventory = try? await client.get("/lol-perks/v1/inventory", as: LCUPerkInventory.self),
                  inventory.canAddCustomPage == false {
            throw WriteError.noFreeSlot
        }

        let body: [String: Any] = [
            "name": String((Self.namePrefix + championName).prefix(25)), // the client's name limit
            "primaryStyleId": primary,
            "subStyleId": secondary,
            "selectedPerkIds": page.allPerkIDs,
            "current": true,
        ]
        let created = try await client.send("POST", "/lol-perks/v1/pages", json: body)
        if let page = try? JSONDecoder().decode(LCUPerkPage.self, from: created) {
            UserDefaults.standard.set(page.id, forKey: Self.pageIDKey)
        }
    }

    private static func isOwnName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.hasPrefix(namePrefix) || name.hasPrefix(legacyNamePrefix)
    }
}
