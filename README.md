# Recall

A lightweight, native macOS companion and in-game overlay for League of Legends.

Recall sets up your runes, item build and summoner spells when you lock in, scouts both teams at the
loading screen, times enemy summoner spells, tracks your CS per minute, gold lead and next item during
the game, and shows your match history with a summary after every game. It uses the League client
already running on your Mac plus public build data. No account, no API key, no Overwolf.

<p align="center">
  <img src="docs/screenshots/overlay.png" alt="The in-game HUD (left) and the Lanes tile as it appears in game while Tab is held (right)" width="640">
</p>

- **Native:** Swift and SwiftUI, a ~2 MB app that idles at 0% CPU
- **Hands off the game:** only Riot's local APIs (the League client's local API and the official
  Live Client Data API); no code injection, no memory reading, no automation of gameplay
- **Mac-like:** light and dark appearance, your system accent color, a sidebar, an inspector, ⌘ shortcuts

## Download

Get `Recall.zip` from the [latest release](https://github.com/Aye-Shun/recall/releases/latest),
unzip it and drag **Recall** to Applications. It runs on macOS 14 or later, on Apple silicon and Intel.

Recall isn't notarized by Apple, so the first time you open it macOS will refuse. Either right-click
Recall → **Open** → **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Recall.app
```

Or [build it yourself](#build-from-source).

## Features

### Champ select

When you lock in a champion, Recall sets up the common loadout for that champion and role:

- **Runes:** creates or replaces its own "Recall: *champion*" rune page and selects it
- **Item build:** adds a "Recall: *champion*" item set to the in-game shop (starter, core, boots and
  options for items 4 to 6)
- **Summoner spells:** sets the two common spells, keeping Flash on the key you choose (D or F)

Each part has its own switch in Settings. In ARAM it follows rerolls and swaps. Your own rune pages
and item sets are never changed.

The **Draft** screen also shows the rune page (with a manual *Apply to Client*), spells, skill order,
the common build, a scouting table for your team and enemy picks as they lock in. On Summoner's Rift
you also get ban suggestions and each enemy's likely role and spells.

### Queue

Optionally accept matches for you (Recall waits 2 seconds so you can still decline, and never accepts
after you've answered), and get a Mac notification when a match is found while you're in another app.

### In-game HUD

A narrow column on the left edge of the screen (press ⌃⇧M to drag it somewhere else):

| Section | What it does |
|---|---|
| **Spell Timers** | One row per enemy with their two summoner spells. Click a spell when you see it cast and it greys out and counts down live. Accounts for Ionian Boots; click again to clear. |
| **CS/min** | Your CS per minute and total CS, plus the share of lane minions you've collected if you play top, mid or bot. |
| **Gold Diff** *(hold Tab)* | Item-gold lead over your lane opponent, the team difference, and a per-lane chart. |
| **Next Item** *(hold Tab)* | The next item of the common build, adjusted to what you already own, with the gold you still need. |

Spell Timers and CS/min stay up all game. Gold Diff and Next Item appear in a second tile underneath
while Tab is held, or always if you turn on *Keep everything on screen*. The **×** on the HUD or the
Lanes tile hides it until the next game.

These sections are made for Summoner's Rift. In ARAM, holding Tab shows Gold Diff and Next Item;
Arena gets only the Lanes tile.

### Lanes tile

At the loading screen, the **Lanes** tile shows each lane's two players side by side: rank, season
win rate, notes such as win or loss streaks, first time on a champion or a possible smurf, and
premade groups. In game it comes back while Tab is held.

### After the game

A summary of your last game: LP gained or lost (and promotions), and how your KDA, CS per minute and
damage per minute compared to your recent average. It appears at the top of Match History and, if you
like, as a notification.

### Main window

| | |
|---|---|
| ![Match History](docs/screenshots/match-history.png) | **Match History.** The last-game summary, then your recent games with result, champion, queue, KDA, CS/min, spells, keystone and items. Filter by Ranked, Normal or ARAM, load older games, and select one to see both teams. |
| ![Player Lookup](docs/screenshots/player-lookup.png) | **Player Lookup.** Search any Riot ID for their rank, recent games, most-played champions and full game details. Open it for anyone in your lobby from the Players screen. |
| ![Draft](docs/screenshots/draft.png) | **Draft** (champ select). The loadout described above, plus scouting for both teams. Ranked champ select hides your teammates' names, so they're looked up at the loading screen. |
| ![Players](docs/screenshots/players.png) | **Players** (loading screen). Both teams as tables: rank, recent win rate and KDA, stats on their current champion, mastery, recent form and notes. Select a player for their Solo and Flex rank, last 10 games and champion pool. |
| ![Game Plan](docs/screenshots/game-plan.png) | **Game Plan.** The HUD's content at a larger size, for a second screen. |
| ![Scoreboard](docs/screenshots/scoreboard.png) | **Scoreboard.** Kills, item gold and every player's items, with each lane's gold difference. |
| ![Settings](docs/screenshots/settings.png) | **Settings.** Open at login, what to import when you lock in, auto-accept, notifications, the HUD's sections and look. |

Screenshots use Recall's sample players with live build data from OP.GG.

## Using Recall

Recall opens at login and lives in the menu bar (binoculars icon), so the overlay is ready when you
play; closing its window doesn't stop it. Use **Preview** in the toolbar to try every screen and the
overlay without a game.

**Overlay tips**
- Set League's window mode to **Borderless** for the most reliable overlay.
- If the HUD doesn't appear in game, turn off *Settings → Overlay → Hide when League isn't in front*.

**Shortcuts**

| Keys | Action |
|---|---|
| Hold Tab | Show Gold Diff, Next Item and the Lanes tile |
| ⌃⇧O | Overlay on or off |
| ⌃⇧M | Arrange (drag) the overlay tiles |
| ⌘1 – ⌘7 | Overview, Match History, Player Lookup, Draft, Players, Game Plan, Scoreboard |
| ⌘, | Settings |

## How it works

| Source | Used for |
|---|---|
| League client local API (127.0.0.1) | Your account, champ select, the game's players, ranks, match history, mastery and player lookups. Found through the client's lockfile, or its process arguments if League is installed outside /Applications. No API key. |
| Live Client Data API (127.0.0.1:2999) | Riot's official in-game API: the clock, scores, items and summoner spells. |
| [OP.GG](https://op.gg) public API | Common runes, builds, spells, skill orders, counters and synergies. Only champion names, roles and the game mode are sent. Cached for 6 hours. |
| [Data Dragon](https://developer.riotgames.com/docs/lol#data-dragon) | Champion, item, rune and summoner spell data and icons. |
| [CommunityDragon](https://communitydragon.org) | Icons for rune stat shards, which Data Dragon doesn't include. |

**What Recall changes in the client**, each only when its setting is on: its own "Recall: *champion*"
rune page and item set, and your summoner spells, when you lock in (or the rune page when you click
*Apply to Client*); and accepting a match when auto-accept is on. It never sends your client
credentials anywhere, and there are no accounts or analytics.

**Lightweight:** with League in /Applications, finding the client is just a file check; polling
slows to every 3–4 seconds outside ready checks, champ select and games; the Tab-key check runs only
during games; overlay windows are released after each game; and build data is cached on disk.

## Build from source

Requirements: macOS 14 or later and Xcode 15.3 or later (Swift 5.10+).

```bash
git clone https://github.com/Aye-Shun/recall.git
cd recall
./scripts/build-app.sh                 # this Mac's architecture
UNIVERSAL=1 ./scripts/build-app.sh     # Apple silicon and Intel
open build/Recall.app
```

`build-app.sh` makes an optimized, ad-hoc signed `build/Recall.app`. Move it to `/Applications` so
"open at login" keeps pointing at it.

## Development

```bash
swift run Recall --demo                                # launch straight into preview data
swift run Recall --snapshot /tmp/draft.png --scene draft --appearance light
```

Snapshot scenes: `overview`, `history`, `lookup`, `draft`, `players`, `players-inspector`, `plan`,
`scoreboard`, `settings`, `settings-general`, `overlays`. These render offscreen, without opening any
windows. Diagnostic scenes `window-sizing`, `tab-stress` and `timer-test` print checks for overlay
sizing and the spell timers.

```
Sources/Recall/
  App/          entry point, menu bar, settings model, snapshot renderer
  LCU/          League client discovery, REST client, models, rune page, item set and spell writers
  LiveClient/   in-game Live Client Data API
  Data/         Data Dragon static data, image cache
  Meta/         OP.GG client, popular data, game modes, team composition,
                build progress, spell timers, farm benchmark
  Model/        player profiles, stats, tags, premades, match history
  Services/     GameMonitor (polling and state), profile loader, match history,
                player lookup, post-game summary, notifications and login item
  Overlay/      overlay windows, hotkeys, HUD and Lanes tiles
  Views/        main window screens and design system
  Demo/         preview data
```

## License

[MIT](LICENSE)

## Disclaimer

Recall isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or
anyone officially involved in producing or managing Riot Games properties. Riot Games, and all
associated properties are trademarks or registered trademarks of Riot Games, Inc.

Recall is not affiliated with OP.GG or CommunityDragon. The League client's local API isn't
officially supported by Riot for third-party apps, so use Recall at your own risk and check Riot's
current policies.
