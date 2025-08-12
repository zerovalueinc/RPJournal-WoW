# Achievements Task Manager (RP Character Memory)

## Epic
- Add an Achievements system and tab to the right-side journal to grant XP and deepen relationship mechanics via “quests.”

## Goals
- UI only in FrameXML; logic only in Lua.
- Right-pane content anchored below `TabBar`, not the inset top; no arithmetic offsets.
- Preserve parchment background; use only light overlay if needed.

## Non-goals
- Do not alter the existing XP engine or external IPC/ICP logic.
- No external services; no login/auth changes.

---

## Milestones
- M1: UI scaffolding (XML)
- M2: Logic and data plumbing (Lua)
- M3: Integration and polish
- M4: QA matrix and release

---

## Work Breakdown

### M1 — FrameXML UI
- [x] ACH-UI-001: Add `CMJ_AchievementRowTemplate` (title, desc, progress right, Claim button right).
  - Acceptance: Rows render correctly; Claim button visible only when claimable.
- [x] ACH-UI-002: Add `TabAchievements` button on the right of Notes, within `PageR.TabBar`.
  - Acceptance: Clicking the tab toggles content and disables the active button.
- [x] ACH-UI-003: Add `PageR.Achievements` container anchored:
  - TopLeft: relative to `TabBar` bottom-left, x=8, y=-8
  - BottomRight: relative to `Inset` bottom-right, x=-8, y=8
  - Acceptance: No overlap; respects parchment; no dark background.
- [x] ACH-UI-004: Add 8 visible rows using the template; ensure vertical spacing 6px.
  - Acceptance: All rows align and truncate gracefully.
- [ ] ACH-UI-005: Optional: swap to `FauxScrollFrame` if more than 8 achievements needed.
  - Acceptance: Mouse wheel/scrollbar correctly updates row content.

### M2 — Lua Logic and Data
- [x] ACH-LUA-001: Extend `POSITIVE_EMOTES` to include `kiss`, `love`.
  - Acceptance: Emote handler recognizes new emotes without errors.
- [x] ACH-LUA-002: Add per-target emote history ring buffer for weekly goals:
  - `entry.ach.history.emotes[key] = {timestamps}` pruned to last 7 days.
  - Acceptance: Size remains bounded; pruning correct across reloads.
- [x] ACH-LUA-003: Define achievement catalog:
  - first_meet, first_kiss, show_affection, hug_weekly_10, dungeon_crawler, pvp_partner, duelists, whisperer, tavern_buddies, group_time_30m, raid_bond, arena_team.
  - Fields: id, name, desc, kind(stat|sumstats|emote|emote_weekly), goal, rewardXP, repeatable, periodDays, valueIsSeconds.
  - Acceptance: Catalog loads; no nil access; friendly names show in UI.
- [x] ACH-LUA-004: Public API:
  - `CharacterMemory_GetAchievements(guid)` → normalized list with cur/goal/done/claimable.
  - `CharacterMemory_ClaimAchievement(guid, id)` → grants XP and marks claimed timestamp; repeatables re-claimable after period.
  - Acceptance: Safe on missing data; idempotent claims; prints a short success message.
- [x] ACH-LUA-005: Hook emote handler to log `hug`, `kiss`, `love` events (no cooldown gating on logging).
  - Acceptance: Logs fire even if XP cooldown blocks; achievements progress.
- [x] ACH-LUA-006: Data init/migration:
  - Ensure `entry.ach = { claimed = {}, history = { emotes = {} } }` created lazily.
  - Acceptance: No migrations break existing saves; nil-safe everywhere.

### M3 — Integration
- [x] ACH-INT-001: Wire tab show/hide, add `CMJ.RefreshAchievements()` painter.
  - Acceptance: Switching tabs updates content; claim changes persist and re-render.
- [x] ACH-INT-002: Call `RefreshAchievements` inside `CMJ.NotifyDataChanged` if Achievements tab is visible.
  - Acceptance: Real-time progress updates after events (whispers, dungeon complete, etc.).
- [x] ACH-INT-003: Minor UI text polish; ensure fonts are consistent (GameFontNormal/Disable/HighlightSmall).
  - Acceptance: Readable; no visual regressions.

### M4 — QA and Release
- [ ] ACH-QA-001: Test matrix
  - First meet → claim
  - /hug x10 within 7 days; prune and re-earn after a week
  - /kiss, /love once → claim
  - Dungeon completion, arena 3x, PvP 5x, duels 3x, whispers 10, tavern 5
  - Group seconds → 30m; verify seconds formatting
  - NPC targets ignored; non-grouped instance ticks ignored
  - Reload/relog persistence
  - Acceptance: All achievements reachable; progress and claims persist.
- [ ] ACH-QA-002: Anchors and layout checks (right panel):
  - All content anchored below `TabBar` bottom; no arithmetic offsets.
  - Acceptance: No overlap at different UI scales.
- [ ] ACH-REL-001: Version bump in TOC and changelog entry.
  - Acceptance: TOC updated; changelog lists achievements feature.
- [ ] ACH-REL-002: Performance sanity
  - Emote prune O(n) with small n; no timers left running on logout.
  - Acceptance: No measurable hitching on events.

---

## Risks
- Win/loss detection for BGs/arena is limited with current hooks.
  - Mitigation: Use match-count goals now; add win/loss later if APIs allow.

## Definition of Done
- All M1–M4 tasks checked; QA matrix passed on a live session; changelog updated.
