RP Relationship Journal (CharacterMemory) – Optimize Notes

Hotspots and changes

- Event hygiene — OPT:
  - Consolidated all gameplay events on a single controller in `CharacterMemory.lua`. Removed duplicate/no-op frames, tooltip hook, and options panel to avoid taint and double handlers.
  - Added zone-change events to refresh a small cache instead of recomputing every call.

- CPU & GC — OPT:
  - Hoisted hot globals to locals at top of `CharacterMemory.lua` and `CM_Journal.lua`.
  - Replaced repeated concatenations with `string.format` in hot paths.
  - Debounced `C_Map.GetBestMapForUnit("player")` via `getZoneContext()` cache (0.5s window).
  - Precomputed relationship percent helper `FmtRel(xp)` and reused it in the journal.
  - Row list recycles visible rows; rebuilds only when size changes; refresh is allocation-light.

- Taint-safety — OPT:
  - `CMJ.Toggle()` gates on `InCombatLockdown()` to avoid protected UI work in combat.
  - Unsafe UI changes can be deferred by callers via `C_Timer.After(0, fn)` (no change to behavior).

- UI polish — OPT:
  - Added `SetClipsChildren(true)` to left/right pages and list scroll container.
  - Enforced single-line with truncation on row texts to prevent overflow.
  - Overview layout recalculates on `OnSizeChanged`; columns and facts snap cleanly without drift.

- I/O & persistence — OPT:
  - Notes write on focus lost only; no per-keystroke DB churn.
  - Defensive format helpers added: `FmtDate`, `FmtZone`, `FmtRel`; used in journal and sharing text.

- Timers & cleanup — OPT:
  - Stored ticker refs in `_G.CharacterMemory_Tickers`; canceled on addon unload/logout.

- Logging & Profiling — OPT:
  - Added `CMUI.debug` flag and `dbg()` logger.
  - Dev-only profiling helpers (gated by `GetCVar("scriptProfile")=="1"`): `/cm cpu`, `/cm mem`.
  - Note: remove these commands for release if desired.

Acceptance checkpoints

- /reload: no errors; no taint introduced by new frames.
- `/rpjournal` or `/cmjournal`: background aspect preserved; list/detail panes do not overflow; header/tab bar properly aligned; divider visually aligns with spine.
- Smooth list scroll and selection always updates right page.
- SavedVariables schema unchanged (`CharacterMemoryDB`).

Touch points

- `CharacterMemory.lua`: event controller, helpers (Fmt*), debounced zone, profiling hooks, tickers cleanup, message formatting, globals hoist.
- `CM_Journal.lua`: clips, hot locals, row text truncation, layout polish, Fmt* usage for safety, combat gating for toggle.


To Do (pre-release)

- [x] Fix duplicate drag stop handlers; keep single saver on the drag handle (CM_Journal.lua)
- [x] Use `CMJ.refs.faux` instead of nonexistent `refs.scroll` in toggle path (CM_Journal.lua)
- [x] Remove duplicate relation spark update logic (CM_Journal.lua)
- [x] Set `SetPropagateKeyboardInput(false)` on root to prevent leaking arrow keys
- [x] Add `SetMaxLetters` bounds to inputs/edits to prevent excessive SavedVariables bloat
- [x] Guard optional corner art creation; avoid creating textures when assets missing (CharacterMemory.lua)
- [x] Enhance TOC metadata (icon, category, website); bump version
- [x] Unify list row creation (remove duplication between BuildRows and RebuildList)
- [x] Prune unused helpers and theme assets that are not shipped (removed unused `styleGoldButton`, `styleSearchEdit`, `createGoldBar`; guarded MEDIA corners)
- [x] Add `CharacterMemoryDB.version` and migration gate in `fixupEntries()`
- [ ] Optional: migrate left list to ScrollBox/ScrollUtil for modern virtualization
- [ ] Decide on keeping/removing dev `/cm cpu` and `/cm mem` commands for release

Character-sheet polish (tracked)

- [x] Remove search UI and clear button from left list; migrate to FrameXML-only design
- [x] Fix undefined globals and redundant `end`; scope `BuildFromXML` correctly
- [x] Move `CMJ_ListRowTemplate` before usages in XML; fix inheritance error
- [x] Ensure only Player- GUIDs are saved and shown; ignore NPCs
- [x] Robust portraits with fallbacks; right-align and constrain date in rows
- [x] Fix left list overlapping and scrolling; use FauxScrollFrame correctly with XML rows
- [x] Add public bio share via addon messages; display received bio under Profile
- [x] Add `CMJ_CategoryHeader` template and apply to Overview (Relation, Summary, Activity)
- [x] Add `CMJ_StatRow` template and refactor Stats tab to 9 stat rows with labels/values
- [x] Add title bar (`CMJ_TitleBar`) and reposition tabs; keep right pane transparent to preserve parchment
- [ ] Race/gender-specific silhouette fallbacks for portraits
- [ ] Move tab OnClick bindings into XML `<Scripts>` blocks (keep Lua data-only)
- [ ] Add gamification accents (badges, pips) defined in XML; Lua sets values only

