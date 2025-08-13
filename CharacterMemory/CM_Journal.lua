-- CM_Journal.lua — Two-page journal (fixed 1024x512) with textures/icons

-- OPT: Diagnostics off for WoW API stub noise in editors; no runtime impact
---@diagnostic disable: undefined-field, param-type-mismatch, assign-type-mismatch, cast-local-type, need-check-nil

local ADDON_NAME = ...

-- OPT: Hoist globals for perf in hot UI paths
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local math_floor = math.floor
local math_max = math.max
local string_format = string.format
local SetPortraitTexture = SetPortraitTexture

CMJ = CMJ or {}
CMUI = CMUI or {}

-- Geometry
local GEO = {
  LEFT_INSET = 64, RIGHT_INSET = 64, TOP_INSET = 56, BOTTOM_INSET = 60,
  GUTTER_HALF = 22, PAD = 12, ROW_H = 56, LINE = 20,
  WIDTH = 1024, HEIGHT = 512, CX = 512,
  COL_W = 220, COL_GAP = 20,
}

-- Pagination settings
local PAGE_SIZE = 5

-- Dev tint for page bounds (off by default)
local DEBUG_TINT = false

-- Mock model
local Model = {
  entries = {}, order = {}, sort = "name",
  selected = nil, scrollOffset = 0,
}

local function SeedMock()
  if next(Model.entries) then return end
  for i=1,25 do
    local id = "id"..i
    Model.entries[id] = {
      name = string.format("Player_%02d", i), level = (i%70)+1,
      tier = (i%2==0) and "Friend" or "Stranger",
      lastSeenAt = string.format("2025-08-%02d 12:%02d UTC", (i%28)+1, i%60),
      firstMetAt = string.format("2025-07-%02d 09:%02d UTC", (i%28)+1, (i*3)%60),
      lastSeenWhere = "Zone", firstMetWhere = "Zone",
      stats = { parties=i%5, raids=i%3, pvpMatches=i%7, duels=i%2, trades=i%4, whispers=i%6, bossKillsDungeon=i%3, bossKillsRaid=i%2, groupTicks=i%9 },
      xp = i*50, notes = "",
    }
  end
end

function CMJ.RefreshAchievements()
  local R=CMJ.refs; if not R or not R.achRows then return end
  local sel = nil
  if CharacterMemoryDB and CharacterMemoryDB.settings and CharacterMemoryDB.settings.ui and CharacterMemoryDB.settings.ui.journal then
    sel = CharacterMemoryDB.settings.ui.journal.lastSelected
  end
  -- Prefer current selected in model
  sel = Model.selected or sel
  if not sel then for _,row in ipairs(R.achRows) do if row then row:Hide() end end return end
  local list = (_G.CharacterMemory_GetAchievements and _G.CharacterMemory_GetAchievements(sel)) or {}
  local offset = 0
  if R.achFaux and FauxScrollFrame_GetOffset then offset = FauxScrollFrame_GetOffset(R.achFaux) or 0 end
  for i,row in ipairs(R.achRows) do
    local idx = offset + i
    local a = list[idx]
    if a and row then
      if row.title then row.title:SetText(a.name or "") end
      if row.desc then row.desc:SetText(a.desc or "") end
      if row.progress then
        local prog = a.valueIsSeconds and string_format("%dm / %dm", math_floor((a.cur or 0)/60), math_floor((a.goal or 0)/60)) or string_format("%d / %d", a.cur or 0, a.goal or 0)
        row.progress:SetText(prog)
      end
      if row.claim then
        row.claim:SetShown(a.claimable and true or false)
        row.claim:SetScript("OnClick", function()
          if _G.CharacterMemory_ClaimAchievement then _G.CharacterMemory_ClaimAchievement(sel, a.id) end
          if CMJ.RefreshAchievements then CMJ.RefreshAchievements() end
          if CMJ.PopulateDetail then CMJ.PopulateDetail(sel) end
        end)
      end
      row:Show()
    elseif row then
      row:Hide()
    end
  end
  if R.achFaux and FauxScrollFrame_Update then
    FauxScrollFrame_Update(R.achFaux, #list, #R.achRows, 34)
  end
end

-- Optimize SortFunc by caching frequently accessed data
local function SortFunc(a, b)
  local ea, eb = Model.entries[a] or {}, Model.entries[b] or {}
  local sortKey = Model.sort
  if sortKey == "last" then
    return (ea.lastSeenAt or "") > (eb.lastSeenAt or "")
  elseif sortKey == "tier" then
    return (ea.tier or "") < (eb.tier or "")
  elseif sortKey == "level" then
    return (ea.level or 0) > (eb.level or 0)
  else
    return (ea.name or "") < (eb.name or "")
  end
end

-- OPT: small debounce helper for UI updates
local pendingTimers = {}
local function Debounce(key, delay, fn)
  if pendingTimers[key] then pendingTimers[key]:Cancel() end
  pendingTimers[key] = C_Timer.NewTimer(delay, function()
    pendingTimers[key] = nil
    fn()
  end)
end

-- OPT: UI helpers
local function UpdateSortButtonLabel() end -- no-op (sort control removed)

-- Class color name helper (Blizzard native colors)
local function ColorizeNameByClass(name, classFile)
  if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    return string_format("|cff%02x%02x%02x%s|r", c.r*255, c.g*255, c.b*255, name or "")
  end
  return name or ""
end

-- Try to set a portrait for a given GUID by scanning common unit tokens
local function SetPortraitByGUID(texture, guid)
  if not texture or not guid or not UnitGUID then return false end
  local function try(unit)
    if unit and UnitExists(unit) and UnitGUID(unit) == guid then
      SetPortraitTexture(texture, unit)
      if texture.SetTexCoord then texture:SetTexCoord(0.07,0.93,0.07,0.93) end
      return true
    end
    return false
  end
  if try("target") or try("focus") or try("mouseover") then return true end
  if UnitGUID("player") == guid then
    SetPortraitTexture(texture, "player")
    if texture.SetTexCoord then texture:SetTexCoord(0.07,0.93,0.07,0.93) end
    return true
  end
  for i=1,4 do if try("party"..i) then return true end end
  for i=1,40 do if try("raid"..i) then return true end end
  for i=1,5 do if try("arena"..i) then return true end end
  if _G.C_NamePlate and _G.C_NamePlate.GetNamePlateForUnit then
    for i=1,40 do if try("nameplate"..i) then return true end end
  end
  return false
end

-- Apply a race/gender-based silhouette fallback when real portrait is unavailable
local function SetFallbackSilhouette(texture, entry)
  if not texture or not entry then return end
  local gender = entry.gender -- 2 male, 3 female
  local raceFile = entry.raceFile
  local genderToken = (gender == 3) and "Female" or "Male"

  local function fileExists(path)
    if not path or path == "" then return false end
    local ok = pcall(GetFileIDFromPath, path)
    return ok and true or false
  end

  -- Try race-specific temporary portrait variants if they exist (guarded)
  local candidates = {}
  if type(raceFile) == "string" and raceFile ~= "" then
    -- Common race tokens
    local raceToken = raceFile
    local alias = {
      Scourge = "Undead",
      HighmountainTauren = "HighmountainTauren",
      ZandalariTroll = "ZandalariTroll",
      VoidElf = "VoidElf",
      LightforgedDraenei = "LightforgedDraenei",
      MagharOrc = "MagharOrc",
      Nightborne = "Nightborne",
      Mechagnome = "Mechagnome",
    }
    raceToken = alias[raceFile] or raceFile
    table.insert(candidates, string.format("Interface/CharacterFrame/TemporaryPortrait-%s-%s", raceToken, genderToken))
    table.insert(candidates, string.format("Interface/CharacterFrame/TemporaryPortrait-%s-%s", genderToken, raceToken))
  end

  -- Generic gender-only fallbacks
  table.insert(candidates, string.format("Interface/CharacterFrame/TemporaryPortrait-%s", genderToken))

  local chosen = nil
  for _, path in ipairs(candidates) do
    if fileExists(path) then chosen = path; break end
  end
  chosen = chosen or string.format("Interface/CharacterFrame/TemporaryPortrait-%s", genderToken)
  texture:SetTexture(chosen)
  texture:SetTexCoord(0.07,0.93,0.07,0.93)
end

-- Small badge helper for left list rows
local function setRowBadge(row, shouldShow)
  if not row then return end
  if row.badge and row.badge.SetShown then row.badge:SetShown(shouldShow and true or false) end
end

local function FindSelectedIndex()
  if not Model.selected then return nil end
  for i,id in ipairs(Model.order) do if id == Model.selected then return i end end
  return nil
end

local function SaveUIState()
  CharacterMemoryDB = CharacterMemoryDB or {}
  CharacterMemoryDB.settings = CharacterMemoryDB.settings or {}
  CharacterMemoryDB.settings.ui = CharacterMemoryDB.settings.ui or {}
  CharacterMemoryDB.settings.ui.journal = CharacterMemoryDB.settings.ui.journal or {}
  local J = CharacterMemoryDB.settings.ui.journal
  J.lastSelected = Model.selected
  J.scroll = Model.scrollOffset or 0
end

-- Adventure Guide-like card skin helper (file-scope so list builders can reuse)
local function SkinRowLikeAdventureCard(row)
  if not row or row._cardSkinned then return end
  row._cardSkinned = true
  row:SetBackdrop({
    bgFile = "Interface/FrameGeneral/UI-Background-Rock",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  row:SetBackdropColor(1, 1, 1, 0.12)
  row:SetBackdropBorderColor(0.92, 0.78, 0.45, 0.80)
  local glow = row:CreateTexture(nil, "BORDER")
  glow:SetAllPoints(true)
  glow:SetColorTexture(1, 1, 0.8, 0.06)
  glow:Hide()
  row._cardGlow = glow
end

local function ApplyFilter()
  -- Rebuild visible order without search filtering (search removed)
  wipe(Model.order)
  for id, e in pairs(Model.entries) do
    if type(id) == "string" and id:match("^Player%-") and (not e or e.isPlayer ~= false) then
      -- Hide strangers from friendship list
      local isStranger = true
      if type(e) == "table" then
        local level = tonumber(e.level or 0) or 0
        local xp = tonumber(e.xp or 0) or 0
        local tier = e.tier
        isStranger = (tier == "Stranger") or (level <= 0 and xp <= 0)
      end
      -- Always include the player's own entry even if it would be filtered
      local playerGUID = UnitGUID and UnitGUID("player")
      if not isStranger or (playerGUID and id == playerGUID) then
        table.insert(Model.order, id)
      end
    end
  end
  table.sort(Model.order, SortFunc)
  -- Keep selection stable; if previous selection no longer exists, select first
  local keep = false
  for _, id in ipairs(Model.order) do if id == Model.selected then keep = true break end end
  if not keep then Model.selected = Model.order[1] end
end

CMJ.refs = CMJ.refs or {}

-- File-scope row factory so both initial build and rebuild share identical visuals/behavior
local function CreateListRow(parent)
  local r = CreateFrame("Button", nil, parent, "CMJ_ListRowTemplate")
  -- Match the adjusted template height
  r:SetHeight(67)
  -- Map template keys
  -- portrait removed; map only needed keys
  r.name = r.name
  r.sub = r.sub
  r.date = r.date
  r.sel = r.sel
  r:SetHighlightTexture("Interface/FriendsFrame/UI-FriendsFrame-HighlightBar", "ADD")
  local htx = r:GetHighlightTexture(); if htx then htx:ClearAllPoints(); htx:SetPoint("TOPLEFT", 0, 0); htx:SetPoint("BOTTOMRIGHT", 0, 0); htx:SetAlpha(0.25) end
  r:SetScript("OnEnter", function(self)
    if self.id then
      local e = Model.entries[self.id] or {}
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(ColorizeNameByClass(e.name or "Unknown", e.classFile), 1,1,1)
      if e.charLevel then GameTooltip:AddLine(string_format("Level %s", e.charLevel), 0.9,0.9,0.9) end
      if e.lastSeenWhere or e.firstMetWhere then GameTooltip:AddLine(e.lastSeenWhere or e.firstMetWhere or "", 0.8,0.8,0.8) end
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  r:SetScript("OnClick", function(self)
    if not self.id then return end
    Model.selected = self.id; CMJ.RefreshList(); CMJ.PopulateDetail(self.id)
    if CharacterMemoryDB and CharacterMemoryDB.settings and CharacterMemoryDB.settings.ui and CharacterMemoryDB.settings.ui.journal then
      CharacterMemoryDB.settings.ui.journal.lastSelected = self.id
    end
  end)
  return r
end

-- Prefer saved entries when present
local function SyncFromDB()
  if _G.CharacterMemoryDB and _G.CharacterMemoryDB.entries then
    Model.entries = _G.CharacterMemoryDB.entries
    -- OPT: Sanity pass to avoid nils and ensure derived fields exist
    for guid, e in pairs(Model.entries) do
      if type(e) == "table" then
        e.name = e.name or guid
        e.notes = e.notes or ""
        e.xp = tonumber(e.xp) or 0
        if _G.computeLevelFromXP then
          e.level = e.level or _G.computeLevelFromXP(e.xp)
        end
        if _G.computeTierFromLevel and e.level then
          e.tier = e.tier or _G.computeTierFromLevel(e.level)
        end
        e.stats = e.stats or {}
      end
    end
  else
    Model.entries = {}
  end
end

-- External modules can call to force-refresh when data changes
function CMJ.NotifyDataChanged()
  if not CMJ.refs or not CMJ.refs.root or not CMJ.refs.root:IsShown() then return end
  SyncFromDB(); ApplyFilter();
  -- keep existing rows; just refresh content
  CMJ.RefreshList()
  if Model.selected then CMJ.PopulateDetail(Model.selected) end
  if CMJ.refs.achievements and CMJ.refs.achievements:IsShown() and CMJ.RefreshAchievements then CMJ.RefreshAchievements() end
end

-- FrameXML entry point (called from CharacterMemory.xml OnLoad)
local function BuildFromXML()
  if CMJ.refs.root then return CMJ.refs.root end

  local root = _G.CMJ_RootXML
  if not root then return nil end
  root:SetMovable(true); root:EnableMouse(true)
  root:EnableKeyboard(true); root:SetPropagateKeyboardInput(false)
  if UISpecialFrames then table.insert(UISpecialFrames, "CMJ_RootXML") end
  root:HookScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" and IsAltKeyDown() and (not InCombatLockdown or not InCombatLockdown()) then self:StartMoving() end
  end)
  root:HookScript("OnMouseUp", function(self, btn)
    if btn == "LeftButton" then self:StopMovingOrSizing() end
  end)
  root:HookScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Hide(); return end
    local idx = FindSelectedIndex() or 1
    if key == "UP" then idx = idx - 1
    elseif key == "DOWN" then idx = idx + 1
    elseif key == "PAGEUP" then idx = idx - #(CMJ.refs.rows or {})
    elseif key == "PAGEDOWN" then idx = idx + #(CMJ.refs.rows or {})
    elseif key == "HOME" then idx = 1
    elseif key == "END" then idx = #Model.order
    else return end
    if idx < 1 then idx = 1 elseif idx > #Model.order then idx = #Model.order end
    if Model.order[idx] then Model.selected = Model.order[idx]; CMJ.RefreshList(); CMJ.PopulateDetail(Model.selected); SaveUIState() end
  end)

  local base = root:GetFrameLevel() or 1
  local pageL = _G.CMJ_RootXMLPageL
  local pageR = _G.CMJ_RootXMLPageR
  if not pageL or not pageR then return nil end
  pageL:SetClipsChildren(true); pageR:SetClipsChildren(true)
  local pageLContent = pageL
  local pageRContent = pageR

  -- Use FauxScrollFrame only for compatibility; pagination replaces scrolling
  local faux = _G.CMJ_RootXMLPageLFaux
  if not faux then return nil end
  faux:Hide()
  faux:SetScript("OnVerticalScroll", nil)

  -- Next page button
  local nextBtn = _G.CMJ_RootXMLPageLNext
  if nextBtn then
    nextBtn:SetScript("OnClick", function()
      Model.page = (Model.page or 1) + 1
      local maxPages = math.max(1, math.ceil(#Model.order / PAGE_SIZE))
      if Model.page > maxPages then Model.page = 1 end
      CMJ.RefreshList()
    end)
  end

  -- Right page containers (from XML)
  local overview = _G.CMJ_RootXMLPageROverview
  local notes = _G.CMJ_RootXMLPageRNotes
  local settings = nil -- settings tab removed; now in interface options
  local profile = _G.CMJ_RootXMLPageRProfile
  local stats = nil
  local achievements = _G.CMJ_RootXMLPageRAchievements

  -- Tabs
  local tabOverview = _G.CMJ_RootXMLPageRTabBarTabOverview
  local tabProfile  = _G.CMJ_RootXMLPageRTabBarTabProfile
  local tabStats    = nil
  local tabNotes    = _G.CMJ_RootXMLPageRTabBarTabNotes
  local tabAchievements = _G.CMJ_RootXMLPageRTabBarTabAchievements
  local tabSettings = nil

  local function showTab(which)
    if overview then overview:SetShown(which=="Overview") end
    if profile then profile:SetShown(which=="Profile") end
    -- stats tab removed
    if notes then notes:SetShown(which=="Notes") end
    if achievements then achievements:SetShown(which=="Achievements") end
    if settings then settings:SetShown(which=="Settings") end
    if which == "Profile" and Model.selected and CMJ.PopulateDetail then
      -- Ensure Profile fields are freshly populated when switching tabs
      CMJ.PopulateDetail(Model.selected)
    end
    if which == "Achievements" and CMJ.RefreshAchievements then CMJ.RefreshAchievements() end
  end
  local function updateTabStates(which)
    local map = { Overview=tabOverview, Profile=tabProfile, Notes=tabNotes, Achievements=tabAchievements, Settings=tabSettings }
    for k, btn in pairs(map) do if btn then if k == which then btn:Disable() else btn:Enable() end end end
  end
  local function tabSwap(which)
    showTab(which); updateTabStates(which)
  end
  -- Expose tab swap for XML OnClick bindings
  function CMUI.TabSwap(which)
    tabSwap(which)
  end
  -- XML now calls CMUI.TabSwap; keep Lua bindings as fallback in case XML not loaded
  if tabOverview and not tabOverview:GetScript("OnClick") then tabOverview:SetScript("OnClick", function() tabSwap("Overview") end) end
  if tabProfile  and not tabProfile:GetScript("OnClick")  then tabProfile:SetScript("OnClick", function() tabSwap("Profile") end) end
  -- stats tab removed
  if tabNotes    and not tabNotes:GetScript("OnClick")    then tabNotes:SetScript("OnClick", function() tabSwap("Notes") end) end
  if tabAchievements and not tabAchievements:GetScript("OnClick") then tabAchievements:SetScript("OnClick", function() tabSwap("Achievements") end) end
  if tabSettings and not tabSettings:GetScript("OnClick") then tabSettings:SetScript("OnClick", function() tabSwap("Settings") end) end
  showTab("Overview"); updateTabStates("Overview")

  -- Expose a helper for row click from XML if desired in future
  function CMUI.Select(id)
    if not id then return end
    Model.selected = id
    CMJ.RefreshList()
    CMJ.PopulateDetail(id)
  end

  -- Bind overview widgets from XML
  local title = _G.CMJ_RootXMLPageROverviewTitle
  local tier  = _G.CMJ_RootXMLPageROverviewTier
  local relBar = nil
  local relFill = nil
  local relPct  = nil
  local portR   = _G.CMJ_RootXMLPageROverviewPortR
  local factsFrame = _G.CMJ_RootXMLPageROverviewFacts
  local affinFriend   = _G.CMJ_RootXMLPageROverviewAffinFriend
  local affinGuild    = _G.CMJ_RootXMLPageROverviewAffinGuild
  local relPips = {}
  for i=1,10 do
    relPips[i] = _G["CMJ_RootXMLPageROverviewRelPipsPip"..i]
  end

  -- Summary rows (stacked)
  local summary = { rows = {} }
  for i=1,6 do
    local row = _G["CMJ_RootXMLPageROverviewSummaryRow"..i]
    if row and row.label and row.value then
      -- Ensure consistent fonts and alignment
      if row.value.SetJustifyH then row.value:SetJustifyH("RIGHT") end
      table.insert(summary.rows, {label=row.label, value=row.value})
    end
  end

  -- Stats row items
  local statsRow = _G.CMJ_RootXMLPageROverviewStatsRow
  if statsRow then
    statsRow.items = {}
    for i=1,8 do
      local it = _G["CMJ_RootXMLPageROverviewStatsRowItem"..i]
      if it then table.insert(statsRow.items, { icon = it.icon, fs = it.fs }) end
    end
  end

  -- Facts grid labels/values (relation details)
  local factLabels, factValues = {}, {}
  for i=1,12 do
    factLabels[i] = _G["CMJ_RootXMLPageROverviewFactsLabel"..i]
    factValues[i] = _G["CMJ_RootXMLPageROverviewFactsValue"..i]
    if factLabels[i] and factLabels[i].Hide then factLabels[i]:Show() end
    if factValues[i] and factValues[i].Hide then factValues[i]:Show() end
  end
  -- Details header removed; nothing to wire

  -- Notes tab widgets
  local noteScroll = _G.CMJ_RootXMLPageRNotesScroll
  local noteEdit = _G.CMJ_RootXMLPageRNotesEdit
  local shareBtn = _G.CMJ_RootXMLPageRNotesShare
  if noteScroll and noteEdit then pcall(noteScroll.SetScrollChild, noteScroll, noteEdit) end
  if shareBtn then shareBtn:SetScript("OnClick", function()
    if Model.selected and CharacterMemory_Share then CharacterMemory_Share(Model.selected) end
  end) end

  -- Settings UI moved to Interface Options

  -- Profile widgets
  local ageEB     = _G.CMJ_RootXMLPageRProfileAgeEB
  local heightEB  = _G.CMJ_RootXMLPageRProfileHeightEB
  local weightEB  = _G.CMJ_RootXMLPageRProfileWeightEB
  local eyesEB    = _G.CMJ_RootXMLPageRProfileEyesEB
  local hairEB    = _G.CMJ_RootXMLPageRProfileHairEB
  local personalityEB = _G.CMJ_RootXMLPageRProfilePersonalityEB
  local idealsEB      = _G.CMJ_RootXMLPageRProfileIdealsEB
  local bondsEB       = _G.CMJ_RootXMLPageRProfileBondsEB
  local flawsEB       = _G.CMJ_RootXMLPageRProfileFlawsEB
  local backgroundEB  = _G.CMJ_RootXMLPageRProfileBackgroundEB
  local langEB    = _G.CMJ_RootXMLPageRProfileLangEB
  local profEB    = _G.CMJ_RootXMLPageRProfileProfEB
  local aliasEB   = _G.CMJ_RootXMLPageRProfileAliasEB
  local alignEB   = _G.CMJ_RootXMLPageRProfileAlignEB
  local saveBtn   = _G.CMJ_RootXMLPageRProfileSaveBtn
  -- Profile identity rows (display only)
  local identR1 = _G.CMJ_RootXMLPageRProfileIdentRow1
  local identR2 = _G.CMJ_RootXMLPageRProfileIdentRow2
  local identR3 = _G.CMJ_RootXMLPageRProfileIdentRow3
  CMJ.refs = CMJ.refs or {}
  CMJ.refs.identRows = { identR1, identR2, identR3 }
  -- Wire save to persist local profile and request bios from selected target
  if saveBtn and not saveBtn._wired then
    saveBtn._wired = true
    saveBtn:SetScript("OnClick", function()
      local sel = Model.selected
      if sel and CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[sel] then
        local e = CharacterMemoryDB.entries[sel]
        e.profile = e.profile or {}; e.profile.appearance = e.profile.appearance or {}
        if ageEB then e.profile.appearance.age = ageEB:GetText() or "" end
        if heightEB then e.profile.appearance.height = heightEB:GetText() or "" end
        if weightEB then e.profile.appearance.weight = weightEB:GetText() or "" end
        if eyesEB then e.profile.appearance.eyes = eyesEB:GetText() or "" end
        if hairEB then e.profile.appearance.hair = hairEB:GetText() or "" end
        if personalityEB then e.profile.personality = personalityEB:GetText() or "" end
        if idealsEB then e.profile.ideals = idealsEB:GetText() or "" end
        if bondsEB then e.profile.bonds = bondsEB:GetText() or "" end
        if flawsEB then e.profile.flaws = flawsEB:GetText() or "" end
        if backgroundEB then e.profile.background = backgroundEB:GetText() or "" end
        if langEB then e.profile.languages = langEB:GetText() or "" end
        if profEB then e.profile.proficiencies = profEB:GetText() or "" end
        if aliasEB then e.profile.alias = aliasEB:GetText() or "" end
        if alignEB then e.profile.alignment = alignEB:GetText() or "" end
      end
    end)
  end

  -- Stats tab rows (using CMJ_StatRow template)
  local statsGrid = {}
  for i=1,9 do
    local row = _G["CMJ_RootXMLPageRStatsRow"..i]
    if row and row.label and row.value then
      statsGrid[i] = { label = row.label, value = row.value }
    end
  end

  -- Achievements rows + faux scroll
  local achRows = {}
  for i=1,8 do achRows[i] = _G["CMJ_RootXMLPageRAchievementsRow"..i] end
  local achFaux = _G.CMJ_RootXMLPageRAchievementsFaux
  if achFaux then
    achFaux:SetScript("OnVerticalScroll", function(self, offset)
      FauxScrollFrame_OnVerticalScroll(self, offset, 34, CMJ.RefreshAchievements)
    end)
  end

  CMJ.refs = {
    root=root, pageLContent=pageLContent, pageRContent=pageRContent,
    nextBtn = nextBtn,
    -- overview
    title=title, tier=tier, relBar=relBar, relFill=relFill, relPct=relPct, relPips=relPips,
    summary=summary, statsRow=statsRow, factLabels=factLabels, factValues=factValues,
    portR=portR, facts=factsFrame,
    -- tabs
    overview=overview, notes=notes, profile=profile, stats=nil, achievements=achievements,
    -- achievements
    achRows=achRows, achFaux=achFaux,
    -- notes
    noteEdit=noteEdit,
    -- profile
    ageEB=ageEB, heightEB=heightEB, weightEB=weightEB, eyesEB=eyesEB, hairEB=hairEB,
    personalityEB=personalityEB, idealsEB=idealsEB, bondsEB=bondsEB, flawsEB=flawsEB,
    backgroundEB=backgroundEB, langEB=langEB, profEB=profEB, aliasEB=aliasEB, alignEB=alignEB, saveBtn=saveBtn,
    -- stats grid
    statsGrid=statsGrid,
    -- scrolling
    faux=faux,
  }

  -- OnShow: restore position and (re)build list; bind XML rows
  root:HookScript("OnShow", function(self)
    if CharacterMemoryDB and CharacterMemoryDB.settings and CharacterMemoryDB.settings.ui and CharacterMemoryDB.settings.ui.journal then
      local J = CharacterMemoryDB.settings.ui.journal
      self:ClearAllPoints(); self:SetPoint(J.point or "CENTER", UIParent, J.point or "CENTER", J.x or 0, J.y or 0)
    end
    -- Bind row references from XML
    CMJ.refs.rows = {
      _G.CMJ_RootXMLPageLRow1, _G.CMJ_RootXMLPageLRow2, _G.CMJ_RootXMLPageLRow3, _G.CMJ_RootXMLPageLRow4, _G.CMJ_RootXMLPageLRow5,
      _G.CMJ_RootXMLPageLRow6, _G.CMJ_RootXMLPageLRow7, _G.CMJ_RootXMLPageLRow8, _G.CMJ_RootXMLPageLRow9, _G.CMJ_RootXMLPageLRow10,
    }
    SyncFromDB(); ApplyFilter(); CMJ.RebuildList(); if Model.selected then CMJ.PopulateDetail(Model.selected) end
  end)

  -- Recompute visible rows on left page size changes
  pageL:HookScript("OnSizeChanged", function()
    if CMJ.RebuildList then CMJ.RebuildList() end
  end)

  return root
end

-- OPT: Debounced list rebuild to avoid layout thrash
function CMJ.RequestRebuildList()
  Debounce("rebuild", 0.02, function() CMJ.RebuildList() end)
end

function CMJ.RefreshList()
  local R=CMJ.refs; if not R or not R.rows then return end
  local faux = R.faux
  local total=#Model.order
  local visible = math.min(PAGE_SIZE, #(R.rows))
  local page = Model.page or 1
  local offset = (page - 1) * PAGE_SIZE
  for i=1,visible do local idx=offset+i; local row=R.rows[i]
    if idx<=total then local id=Model.order[idx]; local e=Model.entries[id] or {}
      row.id=id
      local tierText = string_format("Lv %d • %s", e.level or 0, e.tier or "Stranger")
      local dateText = (CMUI and CMUI.FmtDate and CMUI.FmtDate(e.lastSeenAt)) or (e.lastSeenAt and e.lastSeenAt:sub(1,10)) or "—"
      row.name:SetText(ColorizeNameByClass(e.name or "Unknown", e.classFile))
      row.sub:SetText(tierText)
      row.date:SetText(dateText)
      if row.date and row.date.SetJustifyH then row.date:SetJustifyH("RIGHT") end
      local isSel = (Model.selected==id)
      row.sel:SetShown(isSel); if row.selBG then row.selBG:SetShown(isSel) end
      -- no portrait rendering
      if row.affinFriend and row.affinGuild then
        if e.isFriend then row.affinFriend:Show(); row.affinGuild:Hide()
        elseif e.guildName and e.guildName ~= "" then row.affinFriend:Hide(); row.affinGuild:Show()
        else row.affinFriend:Hide(); row.affinGuild:Hide() end
      end
      -- Show badge for high-tier relationships
      setRowBadge(row, (e.level or 0) >= 15)
      row:Show()
    else row:Hide() end end
  -- Update next button enabled state
  if R.nextBtn then
    local maxPages = math.max(1, math.ceil(total / PAGE_SIZE))
    R.nextBtn:SetEnabled(maxPages > 1)
  end
end

function CMJ.RebuildList()
  local R=CMJ.refs; if not R then return end
  local container = R.pageLContent
  local faux = R.faux
  if not container or not faux then return end
  -- Use the XML-defined rows; we will show only PAGE_SIZE per page
  local visible = PAGE_SIZE
  R.rows = {
    _G.CMJ_RootXMLPageLRow1, _G.CMJ_RootXMLPageLRow2, _G.CMJ_RootXMLPageLRow3, _G.CMJ_RootXMLPageLRow4, _G.CMJ_RootXMLPageLRow5,
    _G.CMJ_RootXMLPageLRow6, _G.CMJ_RootXMLPageLRow7, _G.CMJ_RootXMLPageLRow8, _G.CMJ_RootXMLPageLRow9, _G.CMJ_RootXMLPageLRow10,
  }
  -- Hide extra rows beyond visible
  for i, r in ipairs(R.rows) do
    if i <= visible then
      r:Show()
    else
      r:Hide()
    end
  end
  -- Reset to first page when rebuilding
  Model.page = Model.page or 1
  CMJ.RefreshList()
end

function CMJ.PopulateDetail(id)
  local R=CMJ.refs; if not R then return end
  local e=Model.entries[id] or {}
  R.title:SetText(ColorizeNameByClass(e.name or "Unknown", e.classFile)); R.tier:SetText(e.tier or "Stranger")
  -- Optional subtitle if available
  if R.titleSub then R.titleSub:SetText(string_format("Lv %d • %s • %d XP", e.level or 0, e.tier or "Stranger", e.xp or 0)) end
  local lvl, tierName, pct
  if CMUI and CMUI.FmtRel then
    lvl, tierName, pct = CMUI.FmtRel(e.xp)
  else
    local xp = tonumber(e.xp) or 0
    local lv = math_floor(math.sqrt(xp/100))
    local cf = (lv*lv)*100
    local nf = ((lv+1)*(lv+1))*100
    local sp = nf - cf
    local p = sp>0 and math_floor(((xp-cf)/sp)*100+0.5) or 0
    lvl, tierName, pct = lv, (e.tier or "Stranger"), p
  end
  -- Relation section shows only metrics now
  -- No progress visuals remain
  if R.facts and R.facts.Show then R.facts:Show() end
  local sc=R.summary.rows; if sc then
    if sc[1] and sc[1].value then sc[1].value:SetText(e.race or e.raceFile or "—") end
    local genderText = (e.gender==2 and "Male") or (e.gender==3 and "Female") or "—"
    if sc[2] and sc[2].value then sc[2].value:SetText(genderText) end
    if sc[3] and sc[3].value then sc[3].value:SetText(tostring(e.charLevel or e.level or 0)) end
    if sc[4] and sc[4].value then sc[4].value:SetText(e.itemLevel and tostring(e.itemLevel) or "—") end
    if sc[5] and sc[5].value then sc[5].value:SetText(e.faction or "—") end
    if sc[6] and sc[6].value then sc[6].value:SetText(e.guildName or "—") end
  end
  -- Populate relation details grid with interaction/event metrics
  local s=e.stats or {}
  local groupedTimes = (s.parties or 0) + (s.raids or 0)
  local totalPvP = (s.pvpMatches or 0) + (s.arenaMatches or 0)
  local facts={
    {"Times Grouped", (CMUI and CMUI.FmtNum and CMUI.FmtNum(groupedTimes)) or tostring(groupedTimes)},
    {"Times Traded", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.trades or 0)) or tostring(s.trades or 0)},
    {"Duels", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.duels or 0)) or tostring(s.duels or 0)},
    {"Pet Duels", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.petDuels or 0)) or tostring(s.petDuels or 0)},
    {"PvP Matches", (CMUI and CMUI.FmtNum and CMUI.FmtNum(totalPvP)) or tostring(totalPvP)},
    {"Completed Dungeons", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.dungeonCompletions or 0)) or tostring(s.dungeonCompletions or 0)},
    {"Raid Boss Kills", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.bossKillsRaid or 0)) or tostring(s.bossKillsRaid or 0)},
    {"Group Time", (CMUI and CMUI.FmtTimeShort and CMUI.FmtTimeShort(s.groupSeconds or 0)) or "0m"},
    {"Invites", string_format("%s from • %s to", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.invitesFrom or 0)) or tostring(s.invitesFrom or 0), (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.invitesTo or 0)) or tostring(s.invitesTo or 0))},
    {"Nearby", (CMUI and CMUI.FmtNum and CMUI.FmtNum(s.nearbyTicks or 0)) or tostring(s.nearbyTicks or 0)},
  }
  for i=1,10 do
    if R.factLabels[i] then R.factLabels[i]:SetText(facts[i] and facts[i][1] or ""); R.factLabels[i]:Show() end
    if R.factValues[i] then R.factValues[i]:SetText(facts[i] and facts[i][2] or ""); R.factValues[i]:Show() end
  end
  local s=e.stats or {}
  local vals={
    s.parties or 0,
    s.raids or 0,
    s.pvpMatches or 0,
    s.duels or 0,
    s.trades or 0,
    s.whispers or 0,
    (s.bossKillsDungeon or 0)+(s.bossKillsRaid or 0),
    (s.readyChecks or 0) + (s.wipesWith or 0),
  }
  for i,it in ipairs(R.statsRow.items) do it.fs:SetText(vals[i] or 0) end
  if R.noteEdit then R.noteEdit:SetText(e.notes or "") end
  -- If we have a publicBio received, surface it under profile background when switching to Profile tab
  if R.backgroundEB then
    local p = e.profile or {}
    R.backgroundEB:SetText(p.publicBio or p.background or "")
  end
  -- OPT: right portrait populate (prefer class, else target/player portrait)
  if R.portR then
    local ok = SetPortraitByGUID(R.portR, id)
    if not ok then
      -- Try to build a unit token from the stored name if available
      if e and e.name then
        local base = e.name:match("([^%-]+)") or e.name
        if base and UnitExists(base) then ok = pcall(SetPortraitTexture, R.portR, base) end
    end
  end
  -- Friend/Guild badges (design in XML; show/hide only)
  do
    local fr = _G.CMJ_RootXMLPageROverviewAffinFriend
    local gu = _G.CMJ_RootXMLPageROverviewAffinGuild
    if fr and gu then
      if e.isFriend then fr:Show(); gu:Hide()
      elseif e.guildName and e.guildName ~= "" then fr:Hide(); gu:Show()
      else fr:Hide(); gu:Hide() end
    end
  end
    if not ok then
      SetFallbackSilhouette(R.portR, e)
      R.portR:SetTexCoord(0,1,0,1)
    else
      R.portR:SetTexCoord(0,1,0,1)
    end
  end
  -- (removed unused target portrait snippet)
  -- Profile fields populate
  if R.ageEB then
    local p = e.profile or {}
    local ap = p.appearance or {}
    -- Map identity display
    if CMJ.refs.identRows and CMJ.refs.identRows[1] and CMJ.refs.identRows[1].value then CMJ.refs.identRows[1].value:SetText(p.title or "") end
    if CMJ.refs.identRows and CMJ.refs.identRows[2] and CMJ.refs.identRows[2].value then CMJ.refs.identRows[2].value:SetText(p.pronouns or "") end
    if CMJ.refs.identRows and CMJ.refs.identRows[3] and CMJ.refs.identRows[3].value then CMJ.refs.identRows[3].value:SetText(p.tags or "") end
    R.ageEB:SetText(ap.age or "")
    R.heightEB:SetText(ap.height or "")
    R.weightEB:SetText(ap.weight or "")
    R.eyesEB:SetText(ap.eyes or "")
    R.hairEB:SetText(ap.hair or "")
    R.personalityEB:SetText(p.personality or "")
    R.idealsEB:SetText(p.ideals or "")
    R.bondsEB:SetText(p.bonds or "")
    R.flawsEB:SetText(p.flaws or "")
    R.backgroundEB:SetText(p.background or "")
    R.langEB:SetText(p.languages or "")
    R.profEB:SetText(p.proficiencies or "")
    R.aliasEB:SetText(p.alias or "")
    R.alignEB:SetText(p.alignment or "")
    -- XML-provided Request Bio button is wired below
    -- Wire Request Bio button from XML
    if _G.CMJ_RootXMLPageRProfileRequestBtn and not _G.CMJ_RootXMLPageRProfileRequestBtn._wired then
      _G.CMJ_RootXMLPageRProfileRequestBtn._wired = true
      _G.CMJ_RootXMLPageRProfileRequestBtn:SetScript("OnClick", function()
        if e and e.name and _G.CharacterMemory_RequestBioFrom then
          _G.CharacterMemory_RequestBioFrom(e.name)
        end
      end)
    end
    if R.saveBtn and not R.saveBtn._wired then
      R.saveBtn._wired = true
      R.saveBtn:SetScript("OnClick", function()
        e.profile = e.profile or {}; e.profile.appearance = e.profile.appearance or {}
        e.profile.appearance.age = R.ageEB:GetText() or ""
        e.profile.appearance.height = R.heightEB:GetText() or ""
        e.profile.appearance.weight = R.weightEB:GetText() or ""
        e.profile.appearance.eyes = R.eyesEB:GetText() or ""
        e.profile.appearance.hair = R.hairEB:GetText() or ""
        e.profile.personality = R.personalityEB:GetText() or ""
        e.profile.ideals = R.idealsEB:GetText() or ""
        e.profile.bonds = R.bondsEB:GetText() or ""
        e.profile.flaws = R.flawsEB:GetText() or ""
        e.profile.background = R.backgroundEB:GetText() or ""
        e.profile.languages = R.langEB:GetText() or ""
        e.profile.proficiencies = R.profEB:GetText() or ""
        e.profile.alias = R.aliasEB:GetText() or ""
        e.profile.alignment = R.alignEB:GetText() or ""
        -- OPT: persist journal scale
        if CMJ and CMJ.refs and CMJ.refs.root then
          CharacterMemoryDB = CharacterMemoryDB or {}; CharacterMemoryDB.settings = CharacterMemoryDB.settings or {}; CharacterMemoryDB.settings.ui = CharacterMemoryDB.settings.ui or {}
          CharacterMemoryDB.settings.ui.journal = CharacterMemoryDB.settings.ui.journal or {}
          CharacterMemoryDB.settings.ui.journal.scale = CMJ.refs.root:GetScale() or 1.0
        end
      end)
    end
  end
  -- stats tab removed; overview shows metrics
end

function CMJ.Toggle()
  if not CMJ.refs.root then BuildFromXML() end
  local f=CMJ.refs.root
  if f:IsShown() then f:Hide() else
    -- OPT: Avoid protected toggles during combat
    if InCombatLockdown and InCombatLockdown() then DEFAULT_CHAT_FRAME:AddMessage("Character Memory: UI blocked in combat") return end
    SyncFromDB(); ApplyFilter();
    -- Build rows and paint immediately to avoid any first-frame gap
    do
      local faux = CMJ.refs and CMJ.refs.faux
      local buildNow = (faux and (faux:GetHeight() or 0) > 0) or false
      if CMJ.RebuildList then
        if buildNow then
          CMJ.RebuildList()
        else
          C_Timer.After(0, function() if CMJ.RebuildList then CMJ.RebuildList() end end)
        end
      end
    end
    f:Show()
    -- Force a paint now as well (defensive)
    if CMJ.RefreshList then CMJ.RefreshList() end
    if Model.order[1] then Model.selected=Model.order[1]; if CMJ.PopulateDetail then CMJ.PopulateDetail(Model.selected) end end
  end
end

-- Bootstrap
local evt=CreateFrame("Frame")
evt:RegisterEvent("ADDON_LOADED")
evt:SetScript("OnEvent", function(_,e,name)
  if e=="ADDON_LOADED" and name==ADDON_NAME then
    BuildFromXML()
    SLASH_CMJ1="/cmjournal"; SLASH_CMJ2="/cmj"; SlashCmdList["CMJ"]=function() CMJ.Toggle() end
  end
end)

-- Back-compat entry point for other modules (/cm journal etc.)
function CharacterMemory_OpenJournal()
  if CMJ and CMJ.Toggle then CMJ.Toggle() end
end


