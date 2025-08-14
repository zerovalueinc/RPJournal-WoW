-- CM_Achievements.lua — Achievement catalog and APIs

-- Local achievement catalog; referenced by exported APIs below
local CM_AchievementDefs = {
  {id="first_meet",        name="First Impression",   desc="First time you met.",                        goal=1,   kind="stat",       path="firstMeets",         rewardXP=50},
  {id="first_kiss",        name="First Kiss",         desc="Share a kiss emote.",                        goal=1,   kind="emote",      emote="kiss",              rewardXP=30},
  {id="show_affection",    name="Shows of Affection", desc="Express love.",                              goal=1,   kind="emote",      emote="love",              rewardXP=20},
  {id="hug_weekly_10",     name="Hug Buddy",          desc="Hug them 10 times in 7 days.",               goal=10,  kind="emote_weekly",emote="hug",  days=7, rewardXP=50, repeatable=true, periodDays=7},
  {id="dungeon_crawler",   name="Dungeon Crawler",    desc="Complete a dungeon together.",               goal=1,   kind="stat",       path="dungeonCompletions", rewardXP=80},
  {id="pvp_partner",       name="Battle Buddy",       desc="Play 5 PvP matches together.",               goal=5,   kind="sumstats",   paths={"pvpMatches","arenaMatches"}, rewardXP=100},
  {id="duelists",          name="Dueling Duo",        desc="Duel 3 times.",                              goal=3,   kind="stat",       path="duels",              rewardXP=40},
  {id="whisperer",         name="Whisper Network",    desc="Exchange 10 whispers.",                      goal=10,  kind="stat",       path="whispers",          rewardXP=25},
  {id="tavern_buddies",    name="Tavern Buddies",     desc="Hang out in taverns 5 times.",               goal=5,   kind="stat",       path="tavernTicks",       rewardXP=25},
  {id="group_time_30m",    name="Quality Time",       desc="Spend 30 minutes grouped.",                  goal=1800,kind="stat",       path="groupSeconds",      rewardXP=60, valueIsSeconds=true},
  {id="raid_bond",         name="Raid Bond",          desc="Kill a raid boss together.",                 goal=1,   kind="stat",       path="bossKillsRaid",     rewardXP=120},
  {id="arena_team",        name="Arena Team",         desc="Fight 3 arena matches together.",            goal=3,   kind="stat",       path="arenaMatches",      rewardXP=90},
}

-- Exported: return summary stats for a guid's achievements
function CharacterMemory_GetAchievementSummary(guid)
  if not guid then return { total=0, claimed=0, claimable=0, done=0, claimedXP=0 } end
  local getEntry = rawget(_G, "CharacterMemory_GetOrCreateEntry")
  local e = getEntry and getEntry(guid) or nil
  if not e then return { total=0, claimed=0, claimable=0, done=0, claimedXP=0 } end
  e.ach = e.ach or { claimed = {}, history = { emotes = {} } }
  local claimedMap = e.ach.claimed or {}
  local total = #CM_AchievementDefs
  local claimed, claimable, done, claimedXP = 0, 0, 0, 0
  local rewardById = {}
  for _,def in ipairs(CM_AchievementDefs) do rewardById[def.id] = def.rewardXP or 0 end
  local list = CharacterMemory_GetAchievements(guid)
  for _,a in ipairs(list) do
    if a.done then done = done + 1 end
    if a.claimable then claimable = claimable + 1 end
  end
  for id, ts in pairs(claimedMap) do
    if ts then
      claimed = claimed + 1
      claimedXP = claimedXP + (rewardById[id] or 0)
    end
  end
  return { total=total, claimed=claimed, claimable=claimable, done=done, claimedXP=claimedXP }
end

-- Exported: compute per-guid achievement list with progress and claimability
function CharacterMemory_GetAchievements(guid)
  if not guid then return {} end
  local getEntry = rawget(_G, "CharacterMemory_GetOrCreateEntry")
  local e = getEntry and getEntry(guid) or nil
  if not e then return {} end
  local s = (type(e.stats) == "table") and e.stats or {}
  e.ach = e.ach or { claimed = {}, history = { emotes = {} } }
  e.ach.claimed = e.ach.claimed or {}
  e.ach.history = e.ach.history or { emotes = {} }
  e.ach.history.emotes = e.ach.history.emotes or {}
  local out = {}
  local now = time()
  for _,def in ipairs(CM_AchievementDefs) do
    local cur = 0
    if def.kind=="stat" then
      cur = s[def.path] or 0
    elseif def.kind=="sumstats" then
      for _,p in ipairs(def.paths or {}) do cur = cur + (s[p] or 0) end
    elseif def.kind=="emote" then
      local arr = e.ach.history.emotes[def.emote] or {}; cur = #arr
    elseif def.kind=="emote_weekly" then
      local arr = e.ach.history.emotes[def.emote] or {}
      local cutoff = now - (def.days or 7)*86400
      local cnt=0; for _,t in ipairs(arr) do if t>=cutoff then cnt=cnt+1 end end
      cur = cnt
    end
    local done = cur >= def.goal
    local claimedAt = e.ach.claimed[def.id]
    local claimable = false
    if done then
      if def.repeatable then
        local cutoffClaim = now - (def.periodDays or 7)*86400
        claimable = (not claimedAt) or (claimedAt < cutoffClaim)
      else
        claimable = not claimedAt
      end
    end
    table.insert(out, {
      id=def.id, name=def.name, desc=def.desc, cur=cur, goal=def.goal,
      done=done, claimable=claimable, claimedAt=claimedAt, rewardXP=def.rewardXP, valueIsSeconds=def.valueIsSeconds
    })
  end
  return out
end

-- Exported: claim and award an achievement for a guid
function CharacterMemory_ClaimAchievement(guid, id)
  if not guid or not id then return end
  local getEntry = rawget(_G, "CharacterMemory_GetOrCreateEntry")
  local e = getEntry and getEntry(guid) or nil
  if not e then return end
  local list = CharacterMemory_GetAchievements(guid)
  local sel = nil
  for _,a in ipairs(list) do if a.id == id then sel = a; break end end
  if not sel or not sel.claimable then return end
  local award = _G.CharacterMemory_AwardXP
  if award then award(guid, sel.rewardXP or 0, "achievement:"..id) end
  e.ach = e.ach or {}; e.ach.claimed = e.ach.claimed or {}
  e.ach.claimed[id] = time()
  if _G.print then print("Character Memory: Achievement unlocked: " .. (sel.name or id) .. " +" .. tostring(sel.rewardXP or 0) .. " XP") end
  if _G.CMJ and _G.CMJ.NotifyDataChanged then _G.CMJ.NotifyDataChanged() end
end

-- Exported: achievement emote history tracker (per-target, pruned to last 7 days)
function CM_LogEmoteForAchievements(guid, emoteKey)
  if not guid or not emoteKey then return end
  local getEntry = rawget(_G, "CharacterMemory_GetOrCreateEntry")
  local e = getEntry and getEntry(guid) or nil
  if not e then return end
  e.ach = e.ach or {}; e.ach.history = e.ach.history or {}; e.ach.history.emotes = e.ach.history.emotes or {}
  local tbl = e.ach.history.emotes
  tbl[emoteKey] = tbl[emoteKey] or {}
  local now = time()
  table.insert(tbl[emoteKey], now)
  -- prune to last 7 days
  local cutoff = now - 7*24*60*60
  local pruned = {}
  for _, t in ipairs(tbl[emoteKey]) do if t >= cutoff then table.insert(pruned, t) end end
  tbl[emoteKey] = pruned
end


