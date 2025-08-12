## Character Memory — RP Relationship Journal for World of Warcraft (Retail)

Character Memory is a lightweight, lore‑friendly RP relationship journal that tracks how your character connects with other players through shared activities. It records first meetings, zones, and interactions; awards XP for time spent together; unlocks tiers like Friend, Trusted, and Bonded; and offers an in‑game journal UI with Overview, Profile, Notes, and Achievements tabs.

No external libraries. Per‑character SavedVariables. Modern Settings UI on Dragonflight+ with fallback to Interface Options on earlier clients.

Repository: https://github.com/zerovalueinc/RPJournal-WoW

### Features

- Relationship XP model with tiers based on your shared gameplay
- Per‑target journal: first met, last seen, where, notes, and stats
- Achievements with claimable XP rewards (some repeatable)
- Two‑page parchment journal UI with tabs:
  - Overview: quick summary, activity stats, identity highlights
  - Profile: identity and narrative fields (appearance, bonds, flaws, background, etc.)
  - Notes: freeform notes plus one‑click share to group chat
  - Achievements: progress list with claim buttons
- Options panel for identity and preferences (Title, Pronouns, Tags, etc.)
- Optional auto‑share of “first meet” message to group chat
- Nameplate proximity tracking (lightweight presence signal)
- Optional item‑level display (self and inspected targets)

### Installation

1. Download or clone this repository.
2. Copy the `CharacterMemory` folder to your WoW `Interface/AddOns` directory:
   - Windows: `World of Warcraft/_retail_/Interface/AddOns/CharacterMemory`
3. Restart or reload the game (`/reload`).
4. Type `/cm journal` (or `/cmj`) in chat to open the journal.

### The Journal UI

Open the journal with `/cm journal`, `/cmj`, or `/cmjournal`.

- Left page: paginated list of known players (non‑strangers and your own character). Use the Next button to page.
- Right page: tabbed content (Overview, Profile, Notes, Achievements).
- Move the window: Alt+Left‑drag the page background.

Tabs

- Overview
  - Title and tier
  - Summary stats: Race, Gender, Level, iLvl, Faction, Guild
  - Activity strip: counts of grouped time, PvP matches, duels, trades, etc.
  - Relation facts grid: grouped sessions, raid kills, invites, nearby ticks, and more

- Profile
  - Identity display and editable fields (age, height, weight, eyes, hair, personality, ideals, bonds, flaws, background, languages, proficiencies, alias, alignment)
  - Save button stores details in your local SavedVariables

- Notes
  - Freeform note field per target
  - Share button posts a short relationship summary to your current chat context (party/raid/say)

- Achievements
  - Progress view for each achievement with claim buttons when eligible

### Options and Settings

Open via Game Menu → Options → AddOns → Character Memory (Dragonflight+) or Interface → AddOns (older clients). Identity fields live here with a compact RP Bio preview.

- Identity: Title, Pronouns, Alignment, Tags
- Appearance quick stats: Age, Height, Weight, Eyes, Hair, Alias
- Skills: Languages, Proficiencies/Professions
- Narrative: Personality, Ideals, Bonds, Flaws, Hobbies/Interests
- RP Bio: read‑only preview in Settings; edit the full text on the Profile tab
- Preferences:
  - Show journal when targeting players
  - Show friend/guild badges
  - Allow inspecting item level (where supported)
  - Track nearby presence (nameplates)
  - Auto‑share first meet in chat

Buttons: Save, Clear Selected, Open Journal, Publish to Group

### Relationship XP, Levels, and Tiers

XP grows with shared activities. Level is computed as: `level = floor(sqrt(xp / 100))`.

Tiers are unlocked at:

- Stranger (0)
- Acquaintance (1)
- Familiar (3)
- Friend (6)
- Close Friend (10)
- Trusted (15)
- Bonded (20)

XP Sources

- First meet: +50
- Retarget after 10 minutes: +10
- Positive emote (wave/bow/cheer/hug/salute/kiss/love): +8 (10s cooldown)
- Whisper exchange: +12 (60s cooldown)
- Trade completed: +60
- Duel finished: +40
- Group time tick: +25 every 300s while grouped (accumulates `groupSeconds`)
- Tavern tick: +20 every 120s while resting with target
- Instance group tick (every 120s while in the same instance):
  - Dungeon/party: +15
  - Raid: +20
  - Battleground: +12
  - Arena: +18
- Boss kill: Dungeon +40, Raid +80
- LFG dungeon complete: +100
- Mythic+ complete: +120
- Scenario complete: +60
- PvP: Battleground +40, Arena match +50

XP is only awarded when your current target is a valid player and, for some events, when they’re grouped with you.

### Events and Stats Tracked

Per‑target counters (SavedVariables):

- Grouped sessions: `parties`, `raids`
- PvP: `pvpMatches`, `arenaMatches`
- Duels: `duels`, `petDuels`
- Social: `trades`, `whispers`, `emotes`
- PvE: `dungeonCompletions`, `mplusCompletions`, `scenarioCompletions`, `bossKillsDungeon`, `bossKillsRaid`
- Timers/Ticks: `groupTicks`, `tavernTicks`, `instanceTicks_party`, `instanceTicks_raid`, `instanceTicks_pvp`, `instanceTicks_arena`
- Misc: `reconnects` (retarget after cooldown), `firstMeets`, `readyChecks`, `wipesWith`
- Time: `groupSeconds`
- Invites: `invitesFrom`, `invitesTo`
- Proximity: `nearbyTicks` (nameplate presence, throttled)

Identity snapshot fields per entry include: name, class/race, level, faction, gender, guild, and a `profile` table for narrative and appearance details.

### Achievements

Each achievement tracks progress and may grant XP when claimed. Some are weekly repeatable.

- First Impression (`first_meet`): goal 1, +50 XP
- First Kiss (`first_kiss`): emote `kiss`, goal 1, +30 XP
- Shows of Affection (`show_affection`): emote `love`, goal 1, +20 XP
- Hug Buddy (`hug_weekly_10`): emote `hug` 10 times within 7 days, repeatable weekly, +50 XP
- Dungeon Crawler (`dungeon_crawler`): 1 dungeon complete, +80 XP
- Battle Buddy (`pvp_partner`): sum of PvP+Arena 5, +100 XP
- Dueling Duo (`duelists`): 3 duels, +40 XP
- Whisper Network (`whisperer`): 10 whispers, +25 XP
- Tavern Buddies (`tavern_buddies`): 5 tavern ticks, +25 XP
- Quality Time (`group_time_30m`): 30m grouped (`groupSeconds`), +60 XP (value shown in minutes)
- Raid Bond (`raid_bond`): 1 raid boss kill, +120 XP
- Arena Team (`arena_team`): 3 arena matches, +90 XP

Claiming an achievement adjusts your relationship XP and tier immediately.

### Bio Sharing (Addon Messages)

The addon supports lightweight cross‑user bio sharing:

- Prefix: `CM1`
- Request: `REQBIO|<senderGuid>` (sent as an addon whisper)
- Response: `BIO|<guid>|<escapedBio>` (pipes are escaped as `||`)

Received bios are stored as `publicBio` alongside your local `background`, and are displayed in the Profile tab when viewing another player.

### Slash Commands

- `/cm` — help
- `/cm note <text>` — save a note for the current target
- `/cm share` — share a short memory summary to group/say
- `/cm show` — show panel (redirects to journal)
- `/cm hide` — hide legacy panel (journal is the primary UI)
- `/cm delete` — delete the current target’s memory
- `/cm toggle` — toggle “show on target” setting
- `/cm autoshares` — toggle auto‑share on first meet
- `/cm rel` — print level/tier/xp for current target
- `/cm reladd <xp>` — manually add XP to current target
- `/cm journal` — open/close the Character Memory journal

Journal shortcuts: `/cmjournal`, `/cmj`.

### Compatibility and Notes

- Retail clients supported. No external libraries.
- Uses the modern Settings API when available; falls back to `InterfaceOptions_AddCategory` otherwise.
- UI actions that would taint are blocked in combat.

### Privacy

All data is stored locally in SavedVariables. Public bios received from other users are only shown in your UI. Auto‑share (if enabled) posts a brief “first meet” message to group or say.

### Contributing

Issues and PRs are welcome. Coding style emphasizes clarity, explicit naming, and defensive guards for WoW API calls. Please avoid introducing heavy dependencies.

### License

MIT

