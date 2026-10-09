import Foundation

/// Writes one app-owned rune page ("Recall: <champion>") and selects it. This is the only
/// write Recall makes to the client, and it only runs after the user confirms it.
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

    static let namePrefix = "Recall: "
    private static let pageIDKey = "runePageID"

    let client: LCUClient

    func apply(_ page: OPRunePage, championName: String) async throws {
        guard page.isComplete, let primary = page.primaryPageId, let secondary = page.secondaryPageId else {
            throw WriteError.incompletePage
        }

        // Replace only the page Recall created last time (matched by id, not just by name), so
        // a page the player happened to name "Recall: …" is never touched.
        let pages = (try? await client.get("/lol-perks/v1/pages", as: [LCUPerkPage].self)) ?? []
        let ownID = UserDefaults.standard.object(forKey: Self.pageIDKey) as? Int
        if let ownID, let existing = pages.first(where: { $0.id == ownID && $0.name?.hasPrefix(Self.namePrefix) == true && $0.isDeletable != false }) {
            try await client.send("DELETE", "/lol-perks/v1/pages/\(existing.id)")
        } else if let inventory = try? await client.get("/lol-perks/v1/inventory", as: LCUPerkInventory.self),
                  inventory.canAddCustomPage == false {
            throw WriteError.noFreeSlot
        }

        let body: [String: Any] = [
            "name": Self.namePrefix + championName,
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
}
