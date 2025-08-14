--[[
Character Memory — RP Relationship Journal with Leveling System

Retail WoW addon. No external libraries.

Features
- Per-target memory journal (players and NPCs) storing first/last seen context and notes
- Relationship leveling system with XP sources, cooldowns, and tiers
- Movable UI panel showing key info and a relationship bar
- Slash commands for notes, sharing, toggles, relation info, and manual XP adjust
- Per-character SavedVariables persistence

Implementation notes
- Uses UnitGUID as key; display short name (without realm) in UI
- Timestamps stored as ISO UTC via date("!%Y-%m-%d %H:%M:%S UTC")
- Zone context via C_Map.GetBestMapForUnit("player") and GetSubZoneText()
- UI hides in combat and restores after

Future TODOs (not required for MVP)
- Options panel (interface options)
- Full journal list/search UI
- Minimap button via LibDBIcon (if desired)
]]

-- OPT: Diagnostics off for WoW API stub noise in editors; no runtime impact
---@diagnostic disable: undefined-field, param-type-mismatch, assign-type-mismatch, cast-local-type, need-check-nil

local ADDON_NAME = ...

-- OPT: Hoist hot globals to locals to reduce global table lookups (CPU)
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitRace = UnitRace
local UnitLevel = UnitLevel
local UnitFactionGroup = UnitFactionGroup
local UnitSex = UnitSex
local UnitIsFriend = UnitIsFriend
local C_FriendList = C_FriendList
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local IsResting = IsResting
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local SendChatMessage = SendChatMessage
local SetPortraitTexture = SetPortraitTexture
local C_Map = C_Map
local time = time
local date = date
local print = print
local string_format = string.format
local math_floor = math.floor
local math_sqrt = math.sqrt

-- -----------------------------------------------------------------------------
-- SavedVariables bootstrap
-- -----------------------------------------------------------------------------

CharacterMemoryDB = CharacterMemoryDB or {}

-- OPT: Lightweight debug logger gated by CMUI.debug
_G.CMUI = _G.CMUI or {}
CMUI.debug = CMUI.debug or false
local function dbg(fmt, ...)
  if CMUI and CMUI.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff999999[CM]|r " .. (select('#', ...) > 0 and string_format(fmt, ...) or tostring(fmt)))
  end
end

-- Forward declarations to allow early helper usage
local computeLevelFromXP
local computeTierFromLevel
local getOrCreateEntry
local awardXP

local function initializeDatabase()
  CharacterMemoryDB.version = CharacterMemoryDB.version or 1
  CharacterMemoryDB.settings = CharacterMemoryDB.settings or {
    showOnTarget = true,
    shareEnabled = false,
    anchor = { point = "CENTER", x = 0, y = 200 },
  }
  CharacterMemoryDB.settings.ui = CharacterMemoryDB.settings.ui or {
    journal = { x = 0, y = 0, w = 900, h = 520, isShown = false, darkOverlay = true },
    targetPanel = { x = 0, y = 200, w = 420, h = 220, darkOverlay = true },
  }
  -- ensure new defaults exist
  if CharacterMemoryDB.settings.showOnTarget == nil then CharacterMemoryDB.settings.showOnTarget = true end
  if CharacterMemoryDB.settings.shareEnabled == nil then CharacterMemoryDB.settings.shareEnabled = false end
  CharacterMemoryDB.settings.anchor = CharacterMemoryDB.settings.anchor or { point = "CENTER", x = 0, y = 200 }
  if CharacterMemoryDB.settings.useSheetOnTarget == nil then CharacterMemoryDB.settings.useSheetOnTarget = true end
  CharacterMemoryDB.settings.minimap = CharacterMemoryDB.settings.minimap or { enabled = true, angle = 210 }
  CharacterMemoryDB.entries = CharacterMemoryDB.entries or {}
end

local function fixupEntries()
  -- Basic migration gate for future schema updates
  local ver = CharacterMemoryDB.version or 1
  if ver < 1 then
    -- placeholder for historical migrations
    ver = 1
  end
  CharacterMemoryDB.version = ver
  local entries = CharacterMemoryDB.entries or {}
  for _, e in pairs(entries) do
    -- Ensure profile and stats tables exist
    e.profile = e.profile or { alias = "", alignment = "", personality = "", ideals = "", bonds = "", flaws = "", backstory = "", languages = "", proficiencies = "" }
    e.stats = e.stats or {}
    -- Relationship fields are derived from XP — recompute to avoid prior name collisions
    e.xp = e.xp or 0
    e.level = computeLevelFromXP(e.xp)
    e.tier = computeTierFromLevel(e.level)
  end
end

-- -----------------------------------------------------------------------------
-- Constants and helpers
-- -----------------------------------------------------------------------------

local POSITIVE_EMOTES = {
  wave = true, bow = true, cheer = true, hug = true, salute = true, kiss = true, love = true,
}

local TIER_THRESHOLDS = {
  { level = 20, name = "Bonded" },
  { level = 15, name = "Trusted" },
  { level = 10, name = "Close Friend" },
  { level = 6,  name = "Friend" },
  { level = 3,  name = "Familiar" },
  { level = 1,  name = "Acquaintance" },
  { level = 0,  name = "Stranger" },
}

local CHAT_PREFIX = "|cffb48c55Character Memory|r"

local function printMessage(msg)
  -- OPT: Route through one concatenation; user-facing messages remain
  DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. " " .. (msg or ""))
end

-- -----------------------------------------------------------------------------
-- Addon message protocol (public bio sharing)
-- -----------------------------------------------------------------------------

local ADDON_MSG_PREFIX = "CM1"

local function escapePipes(s)
  if not s then return "" end
  return tostring(s):gsub("|", "||")
end

local function unescapePipes(s)
  if not s then return "" end
  return tostring(s):gsub("||", "|")
end

local function getPlayerGUID()
  return UnitGUID and UnitGUID("player") or nil
end

local function sendBioWhisper(toFullName)
  if not toFullName or toFullName == "" then return end
  local myGuid = getPlayerGUID()
  if not myGuid then return end
  -- Use player's own profile background as their public bio
  local me = CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[myGuid]
  local p = me and me.profile or {}
  local ap = p and p.appearance or {}
  local bio = p and p.background or ""
  bio = escapePipes(bio)
  local function esc(v) return escapePipes(v or "") end
  local payload = table.concat({
    bio,
    esc(p.title), esc(p.pronouns), esc(p.tags), esc(p.alias), esc(p.alignment),
    esc(p.languages), esc(p.proficiencies),
    esc(ap.age), esc(ap.height), esc(ap.weight), esc(ap.eyes), esc(ap.hair),
  }, "|")
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(ADDON_MSG_PREFIX, "BIO|"..myGuid.."|"..payload, "WHISPER", toFullName)
  end
end

-- -----------------------------------------------------------------------------
-- Interface Options panel wiring
-- -----------------------------------------------------------------------------

local function ensureOptionsPanelRegistered()
  if not _G.CM_OptionsPanel then return end
  if Settings and Settings.RegisterAddOnCategory then
    -- Dragonflight+ Settings UI
    if not _G.CM_OptionsCategory then
      local category = Settings.RegisterCanvasLayoutCategory(_G.CM_OptionsPanel, "Character Memory")
      category.ID = "CharacterMemoryOptions"
      Settings.RegisterAddOnCategory(category)
      _G.CM_OptionsCategory = category
    end
    -- Register RP Bio as a subcategory under the main category (left nav child)
    if _G.CM_OptionsCategory and _G.CM_BioPanel and not _G.CM_BioSubcategory then
      -- Use the existing CM_BioPanel as the subpage canvas, constrained by Settings container
      local canvas = _G.CM_BioPanel
      canvas:ClearAllPoints(); canvas:SetPoint("TOPLEFT"); canvas:SetPoint("BOTTOMRIGHT")
      local sub = Settings.RegisterCanvasLayoutSubcategory(_G.CM_OptionsCategory, canvas, "RP Bio")
      sub.ID = "CharacterMemoryBioSub"
      _G.CM_BioSubcategory = sub
    end
  elseif _G.InterfaceOptions_AddCategory then
    -- Classic/older
    _G.InterfaceOptions_AddCategory(_G.CM_OptionsPanel)
  end
end

-- Ensure our canvases close with Escape and edit boxes don't trap movement keys
local function wireEscapeAndFocus()
  -- Allow ESC to hide these frames if they are ever shown standalone
  if type(UISpecialFrames) == "table" then
    local names = { "CM_OptionsPanel", "CM_BioPanel", "CMJ_RootXML" }
    for _, frameName in ipairs(names) do
      if _G[frameName] then
        local already = false
        for i = 1, #UISpecialFrames do
          if UISpecialFrames[i] == frameName then already = true break end
        end
        if not already then table.insert(UISpecialFrames, frameName) end
      end
    end
  end

  -- Helper to apply common edit box behaviors
  local function configureEditBox(edit)
    if not edit or not edit.IsObjectType or not edit:IsObjectType("EditBox") then return end
    if edit.SetAutoFocus then edit:SetAutoFocus(false) end
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    if edit.SetPropagateKeyboardInput then edit:SetPropagateKeyboardInput(true) end
    if edit.HookScript then
      edit:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
      edit:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
  end

  -- Apply to RP Bio page fields (guard existence; XML may not be loaded yet)
  local editNames = {
    "CM_BioPanelTitleEdit",
    "CM_BioPanelPronounsEdit",
    "CM_BioPanelAlignmentEdit",
    "CM_BioPanelTagsEdit",
    "CM_BioPanelAgeEdit",
    "CM_BioPanelHeightEdit",
    "CM_BioPanelWeightEdit",
    "CM_BioPanelEyesEdit",
    "CM_BioPanelHairEdit",
    "CM_BioPanelAliasEdit",
    "CM_BioPanelLanguagesEdit",
    "CM_BioPanelProficienciesEdit",
    "CM_BioPanelBioEdit",
    -- Hidden legacy placeholder on options panel
    "CM_OptionsPanelBioEdit",
  }
  for _, name in ipairs(editNames) do configureEditBox(_G[name]) end

  -- Clear focus whenever panels are hidden
  local function clearAll()
    for _, name in ipairs(editNames) do
      local e = _G[name]
      if e and e.ClearFocus then pcall(function() e:ClearFocus() end) end
    end
  end
  if _G.CM_BioPanel and _G.CM_BioPanel.HookScript then
    _G.CM_BioPanel:HookScript("OnHide", clearAll)
  end
  if _G.CM_OptionsPanel and _G.CM_OptionsPanel.HookScript then
    _G.CM_OptionsPanel:HookScript("OnHide", clearAll)
  end
end

function CharacterMemory_OptionsOnShow()
  CharacterMemoryDB = CharacterMemoryDB or { settings = {} }
  CharacterMemoryDB.settings = CharacterMemoryDB.settings or {}
  CharacterMemoryDB.entries = CharacterMemoryDB.entries or {}
  -- Public Bio of player
  local guid = UnitGUID and UnitGUID("player")
  local e = guid and CharacterMemoryDB.entries[guid]
  local bio = (e and e.profile and (e.profile.publicBio or e.profile.background)) or ""
  if _G.CM_OptionsPanelBioEdit and _G.CM_OptionsPanelBioEdit.SetText then _G.CM_OptionsPanelBioEdit:SetText(bio) end
  if _G.CM_BioPanelBioEdit and _G.CM_BioPanelBioEdit.SetText then _G.CM_BioPanelBioEdit:SetText(bio) end
  -- Populate on the new Bio page when available
  if _G.CM_BioPanelTitleEdit then _G.CM_BioPanelTitleEdit:SetText((e and e.profile and e.profile.title) or "") end
  if _G.CM_BioPanelPronounsEdit then _G.CM_BioPanelPronounsEdit:SetText((e and e.profile and e.profile.pronouns) or "") end
  if _G.CM_BioPanelAlignmentEdit then _G.CM_BioPanelAlignmentEdit:SetText((e and e.profile and e.profile.alignment) or "") end
  if _G.CM_BioPanelTagsEdit then _G.CM_BioPanelTagsEdit:SetText((e and e.profile and e.profile.tags) or "") end
  if _G.CM_BioPanelAgeEdit then _G.CM_BioPanelAgeEdit:SetText((e and e.profile and e.profile.appearance and e.profile.appearance.age) or "") end
  if _G.CM_BioPanelHeightEdit then _G.CM_BioPanelHeightEdit:SetText((e and e.profile and e.profile.appearance and e.profile.appearance.height) or "") end
  if _G.CM_BioPanelWeightEdit then _G.CM_BioPanelWeightEdit:SetText((e and e.profile and e.profile.appearance and e.profile.appearance.weight) or "") end
  if _G.CM_BioPanelEyesEdit then _G.CM_BioPanelEyesEdit:SetText((e and e.profile and e.profile.appearance and e.profile.appearance.eyes) or "") end
  if _G.CM_BioPanelHairEdit then _G.CM_BioPanelHairEdit:SetText((e and e.profile and e.profile.appearance and e.profile.appearance.hair) or "") end
  if _G.CM_BioPanelAliasEdit then _G.CM_BioPanelAliasEdit:SetText((e and e.profile and e.profile.alias) or "") end
  if _G.CM_BioPanelLanguagesEdit then _G.CM_BioPanelLanguagesEdit:SetText((e and e.profile and e.profile.languages) or "") end
  if _G.CM_BioPanelProficienciesEdit then _G.CM_BioPanelProficienciesEdit:SetText((e and e.profile and e.profile.proficiencies) or "") end
  if _G.CM_BioPanelPersonalityEdit then _G.CM_BioPanelPersonalityEdit:SetText((e and e.profile and e.profile.personality) or "") end
  if _G.CM_BioPanelIdealsEdit then _G.CM_BioPanelIdealsEdit:SetText((e and e.profile and e.profile.ideals) or "") end
  if _G.CM_BioPanelBondsEdit then _G.CM_BioPanelBondsEdit:SetText((e and e.profile and e.profile.bonds) or "") end
  if _G.CM_BioPanelFlawsEdit then _G.CM_BioPanelFlawsEdit:SetText((e and e.profile and e.profile.flaws) or "") end
  if _G.CM_BioPanelHobbiesEdit then _G.CM_BioPanelHobbiesEdit:SetText((e and e.profile and e.profile.hobbies) or "") end
  -- Main page preview removed
  -- Bio panel no longer uses a scroll frame
  if _G.CM_OptionsPanelShowOnTarget then _G.CM_OptionsPanelShowOnTarget:SetChecked(CharacterMemoryDB.settings.showOnTarget and true or false) end
  if _G.CM_OptionsPanelShowBadges then _G.CM_OptionsPanelShowBadges:SetChecked((CharacterMemoryDB.settings.showBadges ~= false)) end
  if _G.CM_OptionsPanelEnableInspect then _G.CM_OptionsPanelEnableInspect:SetChecked((CharacterMemoryDB.settings.enableInspect ~= false)) end
  if _G.CM_OptionsPanelEnableProximity then _G.CM_OptionsPanelEnableProximity:SetChecked((CharacterMemoryDB.settings.enableProximity ~= false)) end
  if _G.CM_OptionsPanelAutoShare then _G.CM_OptionsPanelAutoShare:SetChecked((CharacterMemoryDB.settings.shareEnabled == true)) end
  -- Do not force tab swap here; Bio subpage calls this too
end

function CharacterMemory_OptionsSave()
  CharacterMemoryDB = CharacterMemoryDB or { settings = {} }
  CharacterMemoryDB.settings = CharacterMemoryDB.settings or {}
  CharacterMemoryDB.entries = CharacterMemoryDB.entries or {}
  -- Save show on target
  if _G.CM_OptionsPanelShowOnTarget then
    CharacterMemoryDB.settings.showOnTarget = _G.CM_OptionsPanelShowOnTarget:GetChecked() and true or false
  end
  if _G.CM_OptionsPanelShowBadges then CharacterMemoryDB.settings.showBadges = _G.CM_OptionsPanelShowBadges:GetChecked() and true or false end
  if _G.CM_OptionsPanelEnableInspect then CharacterMemoryDB.settings.enableInspect = _G.CM_OptionsPanelEnableInspect:GetChecked() and true or false end
  if _G.CM_OptionsPanelEnableProximity then CharacterMemoryDB.settings.enableProximity = _G.CM_OptionsPanelEnableProximity:GetChecked() and true or false end
  if _G.CM_OptionsPanelAutoShare then CharacterMemoryDB.settings.shareEnabled = _G.CM_OptionsPanelAutoShare:GetChecked() and true or false end
  -- Save player bio
  local guid = UnitGUID and UnitGUID("player")
  if guid then
    local e = CharacterMemoryDB.entries[guid] or { profile = {} }
    e.profile = e.profile or {}
    e.profile.appearance = e.profile.appearance or {}
    do
      local text = ""
      if _G.CM_BioPanelBioEdit and _G.CM_BioPanelBioEdit.GetText then
        text = _G.CM_BioPanelBioEdit:GetText() or ""
      elseif _G.CM_OptionsPanelBioEdit and _G.CM_OptionsPanelBioEdit.GetText then
        text = _G.CM_OptionsPanelBioEdit:GetText() or ""
      end
      -- Mirror user's authored RP Bio into both fields: background (for local profile)
      -- and publicBio (for sharing/preview by other users)
      e.profile.background = text
      e.profile.publicBio = text
    end
    -- Save identity fields
    -- Prefer values from Bio page if present
    if _G.CM_BioPanelTitleEdit then e.profile.title = _G.CM_BioPanelTitleEdit:GetText() or "" end
    if _G.CM_BioPanelPronounsEdit then e.profile.pronouns = _G.CM_BioPanelPronounsEdit:GetText() or "" end
    if _G.CM_BioPanelAlignmentEdit then e.profile.alignment = _G.CM_BioPanelAlignmentEdit:GetText() or "" end
    if _G.CM_BioPanelTagsEdit then e.profile.tags = _G.CM_BioPanelTagsEdit:GetText() or "" end
    if _G.CM_BioPanelAgeEdit then e.profile.appearance.age = _G.CM_BioPanelAgeEdit:GetText() or "" end
    if _G.CM_BioPanelHeightEdit then e.profile.appearance.height = _G.CM_BioPanelHeightEdit:GetText() or "" end
    if _G.CM_BioPanelWeightEdit then e.profile.appearance.weight = _G.CM_BioPanelWeightEdit:GetText() or "" end
    if _G.CM_BioPanelEyesEdit then e.profile.appearance.eyes = _G.CM_BioPanelEyesEdit:GetText() or "" end
    if _G.CM_BioPanelHairEdit then e.profile.appearance.hair = _G.CM_BioPanelHairEdit:GetText() or "" end
    if _G.CM_BioPanelAliasEdit then e.profile.alias = _G.CM_BioPanelAliasEdit:GetText() or "" end
    if _G.CM_BioPanelLanguagesEdit then e.profile.languages = _G.CM_BioPanelLanguagesEdit:GetText() or "" end
    if _G.CM_BioPanelProficienciesEdit then e.profile.proficiencies = _G.CM_BioPanelProficienciesEdit:GetText() or "" end
    if _G.CM_BioPanelPersonalityEdit then e.profile.personality = _G.CM_BioPanelPersonalityEdit:GetText() or "" end
    if _G.CM_BioPanelIdealsEdit then e.profile.ideals = _G.CM_BioPanelIdealsEdit:GetText() or "" end
    if _G.CM_BioPanelBondsEdit then e.profile.bonds = _G.CM_BioPanelBondsEdit:GetText() or "" end
    if _G.CM_BioPanelFlawsEdit then e.profile.flaws = _G.CM_BioPanelFlawsEdit:GetText() or "" end
    if _G.CM_BioPanelHobbiesEdit then e.profile.hobbies = _G.CM_BioPanelHobbiesEdit:GetText() or "" end
    -- Ensure player's own entry has core identity for list/profile
    e.isPlayer = true
    local name, realm = UnitName("player")
    e.name = (realm and realm ~= "" ) and (name.."-"..realm) or name or e.name
    local className, classFile = UnitClass("player"); e.class, e.classFile = className, classFile
    local raceName, raceFile = UnitRace("player"); e.race, e.raceFile = raceName, raceFile
    e.charLevel = UnitLevel("player") or e.charLevel
    e.faction = UnitFactionGroup("player") or e.faction
    e.gender = UnitSex("player") or e.gender
    e.guildName = select(1, GetGuildInfo("player")) or e.guildName
    CharacterMemoryDB.entries[guid] = e
  end
  CharacterMemory_UpdateUI()
  -- Select self in journal for immediate preview
  if _G.CMJ and _G.CMJ.Select and UnitGUID and UnitGUID("player") then
    pcall(_G.CMJ.Select, UnitGUID("player"))
  end
end

function CharacterMemory_OptionsClearSelected()
  local guid = (_G.State and _G.State.currentGUID) or (_G.CharacterMemoryDB and _G.CharacterMemoryDB.settings and _G.CharacterMemoryDB.settings.ui and _G.CharacterMemoryDB.settings.ui.journal and _G.CharacterMemoryDB.settings.ui.journal.lastSelected) or nil
  if guid then
    CharacterMemoryDB.entries[guid] = nil
    if _G.State then _G.State.currentGUID = nil end
    CharacterMemory_UpdateUI()
    printMessage("Cleared selected character memory.")
  end
end

function CharacterMemory_OptionsOnBioChanged(editBox)
  -- Only used on the Bio page now; char count there uses same name if needed
  if _G.CM_OptionsPanelBioCount and _G.CM_OptionsPanelBioCount.fs then
    _G.CM_OptionsPanelBioCount.fs:SetText(string.format("%d chars", #(editBox:GetText() or "")))
  end
end

-- Simple tab switcher for the settings canvas
function CharacterMemory_OptionsTabSwap(which)
  local generalVisible = (which == "General")
  -- Guard missing nodes during load; toggle the entire group
  if _G.CM_OptionsPanelPrefsHeader then _G.CM_OptionsPanelPrefsHeader:SetShown(generalVisible) end
  if _G.CM_OptionsPanelGeneralGroup then _G.CM_OptionsPanelGeneralGroup:SetShown(generalVisible) end
  -- Footer buttons are shared across tabs; always show

  local bioVisible = (which == "Bio")
  if _G.CM_BioPanel then _G.CM_BioPanel:SetShown(bioVisible) end
  -- Toggle tab button enabled states for feedback
  local tabG = _G.CM_OptionsPanelTabBarTabGeneral
  local tabB = _G.CM_OptionsPanelTabBarTabBio
  if tabG and tabG.Disable and tabG.Enable then if generalVisible then tabG:Disable() else tabG:Enable() end end
  if tabB and tabB.Disable and tabB.Enable then if bioVisible then tabB:Disable() else tabB:Enable() end end
end

function CharacterMemory_OptionsPublish()
  -- Share your bio to current group (addon whisper per member when possible)
  local guid = UnitGUID and UnitGUID("player")
  if not guid or not CharacterMemoryDB or not CharacterMemoryDB.entries then return end
  local e = CharacterMemoryDB.entries[guid]
  local bio = e and e.profile and e.profile.background
  if not bio or bio == "" then return end
  -- Iterate group roster and whisper via addon channel if available
  if IsInRaid() then
    for i=1, GetNumGroupMembers() do
      local name = GetRaidRosterInfo(i)
      if name and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage("CM1", "BIO|"..guid.."|"..escapePipes(bio), "WHISPER", name)
      end
    end
  elseif IsInGroup() then
    for i=1, GetNumSubgroupMembers() do
      local unit = "party"..i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n.."-"..r) or n
        if full and C_ChatInfo and C_ChatInfo.SendAddonMessage then
          C_ChatInfo.SendAddonMessage("CM1", "BIO|"..guid.."|"..escapePipes(bio), "WHISPER", full)
        end
      end
    end
  end
end

local function requestBioFrom(targetFullName)
  if not targetFullName or targetFullName == "" then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(ADDON_MSG_PREFIX, "REQBIO|"..(getPlayerGUID() or ""), "WHISPER", targetFullName)
  end
end

-- Exported wrapper so UI modules can request a bio by player name
function CharacterMemory_RequestBioFrom(targetFullName)
  requestBioFrom(targetFullName)
end

-- -----------------------------------------------------------------------------
-- Theme (fantasy parchment + gold accents)
-- -----------------------------------------------------------------------------

local THEME = {
  gold = { r = 0.95, g = 0.82, b = 0.31 },
  goldHex = "|cfff2d24f",
  silverHex = "|cffcfd5de",
  darkOverlayAlpha = 0.8,
  -- Prefer TGA parchment if provided; fallback to generic only if missing
  bgParchment = (function()
    local tga = "Interface/AddOns/CharacterMemory/Art/parchment.tga"
    local ok = pcall(GetFileIDFromPath, tga)
    if ok then return tga else return "Interface/FrameGeneral/UI-Background-Rock" end
  end)(),
  border = "Interface/Tooltips/UI-Tooltip-Border",
  quillTex = "Interface/PaperDollInfoFrame/Character-TitleIcon",
}

-- Prefer local TGA art if it exists; otherwise use provided fallback
local function preferArt(localBaseName, fallback)
  local tga = "Interface/AddOns/CharacterMemory/Art/" .. localBaseName .. ".tga"
  local ok = pcall(GetFileIDFromPath, tga)
  if ok then return tga end
  return fallback
end

THEME.quillTex = preferArt("quill", THEME.quillTex)

-- Remove PNG stylings from base module; Journal/Profile manage their own art
local MEDIA = { parchment = THEME.bgParchment }

-- safely add a round alpha mask to a texture if supported
local function tryApplyRoundMask(texture)
  if not texture or not texture.CreateMaskTexture then return end
  local ok, mask = pcall(texture.CreateMaskTexture, texture)
  if not ok or not mask then return end
  mask:SetAllPoints(true)
  mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask")
  if texture.AddMaskTexture then
    pcall(texture.AddMaskTexture, texture, mask)
  end
end

local function setGoldText(fontString, text, large)
  local prefix = THEME.goldHex
  local suffix = "|r"
  fontString:SetText((prefix)..(text or "")..suffix)
  if large then fontString:SetFontObject("GameFontNormalLarge") end
end

local function setTextureSafe(tex, path)
  if tex and path then
    pcall(tex.SetTexture, tex, path)
  end
end

local function setTexCoordSafe(tex, a,b,c,d)
  if tex and a then
    pcall(tex.SetTexCoord, tex, a,b,c,d)
  end
end

-- Forward declare for use before definition
local applyParchmentBackground

-- Creates a parchment skinned frame with an inner content canvas honoring padding
local function CM_CreateParchmentFrame(parent, width, height, padding)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(width or 900, height or 520)
  applyParchmentBackground(f)
  padding = padding or 18
  local canvas = CreateFrame("Frame", nil, f)
  canvas:SetPoint("TOPLEFT", padding, -padding)
  canvas:SetPoint("BOTTOMRIGHT", -padding, padding)
  f._cmCanvas = canvas
  return f, canvas
end

function applyParchmentBackground(frame)
  if frame._cmBgTex then frame._cmBgTex:Hide() end
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  setTextureSafe(bg, MEDIA.parchment)
  bg:SetPoint("CENTER")
  local function layout()
    local w = math.max(300, frame:GetWidth() or 900)
    local h = math.max(200, frame:GetHeight() or 520)
    local texW, texH = 1024, 512
    local scaledH = (w / texW) * texH
    if scaledH >= h then
      bg:SetSize(w, scaledH)
    else
      bg:SetSize((h / texH) * texW, h)
    end
  end
  frame:HookScript("OnSizeChanged", layout)
  layout()
  frame._cmBgTex = bg

  -- Gold corners
  local function corner(path, point, ox, oy)
    local t = frame:CreateTexture(nil, "BORDER")
    setTextureSafe(t, path)
    t:SetSize(24, 24)
    t:SetPoint(point, frame, point, ox or 0, oy or 0)
  end
  -- Guard optional corner art; only create if paths are present
  if MEDIA.cornerTL and MEDIA.cornerTR and MEDIA.cornerBL and MEDIA.cornerBR then
    corner(MEDIA.cornerTL, "TOPLEFT", 6, -6)
    corner(MEDIA.cornerTR, "TOPRIGHT", -6, -6)
    corner(MEDIA.cornerBL, "BOTTOMLEFT", 6, 6)
    corner(MEDIA.cornerBR, "BOTTOMRIGHT", -6, 6)
  end

  local overlay = frame:CreateTexture(nil, "BORDER")
  overlay:SetAllPoints(true)
  overlay:SetColorTexture(0, 0, 0, 0.22)
  frame._cmOverlay = overlay
end

-- Removed unused styleGoldButton; journal provides its own visuals

-- Removed unused styleSearchEdit helper

-- Removed unused createGoldBar helper

local function classColorHex(classFile)
  if not classFile or not RAID_CLASS_COLORS or not RAID_CLASS_COLORS[classFile] then return nil end
  local c = RAID_CLASS_COLORS[classFile]
  return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function colorizeNameByClass(name, classFile)
  local hex = classColorHex(classFile)
  if hex then return hex .. (name or "") .. "|r" end
  return name or ""
end

local function shortName(name)
  if not name then return "Unknown" end
  local base = name:match("([^%-]+)")
  return base or name
end

local function nowUTCString()
  return date("!%Y-%m-%d %H:%M:%S UTC")
end

-- OPT: Debounced zone context to avoid repeated C_Map calls (CPU); refreshed on zone change
local zoneCache = { name = nil, sub = nil, stamp = 0 }
local function getZoneContext()
  local t = GetTime()
  if (t - (zoneCache.stamp or 0)) < 0.5 and zoneCache.name then
    return zoneCache.sub and (zoneCache.name .. " - " .. zoneCache.sub) or zoneCache.name
  end
  local uiMapID = C_Map.GetBestMapForUnit("player")
  local info = uiMapID and C_Map.GetMapInfo(uiMapID)
  local zoneName = (info and info.name) or GetZoneText() or "Unknown"
  local subzone = GetSubZoneText()
  if subzone == "" or subzone == zoneName then subzone = nil end
  zoneCache.name, zoneCache.sub, zoneCache.stamp = zoneName, subzone, t
  return subzone and (zoneName .. " - " .. subzone) or zoneName
end

-- OPT: Defensive format helpers per spec
local function FmtDate(s)
  return (type(s) == "string" and #s >= 10) and s:sub(1,10) or "—"
end
local function FmtZone(z)
  return (type(z) == "string" and z ~= "") and z or "—"
end
local function FmtNum(n)
  n = tonumber(n or 0) or 0
  local s = tostring(math_floor(n))
  local k; repeat s,k = s:gsub("^(%-?%d+)(%d%d%d)", '%1,%2') until k==0
  return s
end
local function FmtTimeShort(secs)
  secs = tonumber(secs or 0) or 0
  local h = math_floor(secs/3600); local m = math_floor((secs%3600)/60)
  if h>0 then return string_format("%dh %dm", h, m) else return string_format("%dm", m) end
end
local function FmtRel(xp)
  xp = tonumber(xp) or 0
  local level = math_floor(math_sqrt(xp / 100))
  local tier = computeTierFromLevel(level)
  local curr = (level * level) * 100
  local nextF = ((level + 1) * (level + 1)) * 100
  local span = nextF - curr
  local pct = span > 0 and math_floor(((xp - curr) / span) * 100 + 0.5) or 100
  return level, tier, pct
end

-- OPT: Expose helpers for UI module usage
CMUI.FmtDate = FmtDate
CMUI.FmtZone = FmtZone
CMUI.FmtRel = FmtRel
CMUI.FmtNum = FmtNum
CMUI.FmtTimeShort = FmtTimeShort

function computeLevelFromXP(xp)
  -- OPT: Use local math bindings
  xp = xp or 0
  return math_floor(math_sqrt(xp / 100))
end

function computeTierFromLevel(level)
  for _, t in ipairs(TIER_THRESHOLDS) do
    if level >= t.level then
      return t.name
    end
  end
  return "Stranger"
end

-- Next level threshold helpers for progress bar
local function xpForLevel(level)
  -- Solve for xp such that level = floor(sqrt(xp/100)) => min xp for level L is (L^2)*100
  return (level * level) * 100
end

local function progressToNextLevel(xp)
  local level = computeLevelFromXP(xp)
  local currFloor = xpForLevel(level)
  local nextFloor = xpForLevel(level + 1)
  local span = nextFloor - currFloor
  local into = xp - currFloor
  local pct = span > 0 and math.min(100, math.max(0, (into / span) * 100)) or 100
  return level, pct
end

-- -----------------------------------------------------------------------------
-- Item Level capture and caching
-- -----------------------------------------------------------------------------

local lastInspectAt = 0
local function canInspectNow()
  local t = GetTime() or 0
  return (t - lastInspectAt) > 2.0 and not InCombatLockdown()
end

function CharacterMemory_UpdatePlayerItemLevel()
  if not UnitGUID or not GetAverageItemLevel then return end
  local guid = UnitGUID("player")
  if not guid then return end
  local e = getOrCreateEntry(guid)
  if not e then return end
  local avg, equipped = GetAverageItemLevel()
  if equipped and equipped > 0 then
    e.itemLevel = math_floor(equipped + 0.5)
    CharacterMemory_UpdateUI()
  end
end

function CharacterMemory_RequestTargetItemLevel()
  if not UnitExists or not UnitIsPlayer or not UnitGUID then return end
  if not canInspectNow() then return end
  if not CanInspect or not NotifyInspect then return end
  if not UnitExists("target") or not UnitIsPlayer("target") then return end
  if UnitIsUnit and UnitIsUnit("target", "player") then
    CharacterMemory_UpdatePlayerItemLevel(); return
  end
  if CheckInteractDistance and not CheckInteractDistance("target", 1) then return end -- 28 yards
  lastInspectAt = GetTime() or 0
  pcall(NotifyInspect, "target")
end

function CharacterMemory_OnInspectReady(inspectedGuid)
  if not inspectedGuid then return end
  local e = getOrCreateEntry(inspectedGuid)
  if not e then return end
  -- Some builds expose GetInspectItemLevel or C_PaperDollInfo.GetInspectItemLevel
  local ilvl = nil
  if _G.C_PaperDollInfo and _G.C_PaperDollInfo.GetInspectItemLevel then
    local ok, v = pcall(_G.C_PaperDollInfo.GetInspectItemLevel)
    if ok and type(v) == "number" and v > 0 then ilvl = v end
  end
  if not ilvl and _G.GetAverageItemLevel then
    -- Fallback: GetAverageItemLevel returns your own; not for inspected targets
    ilvl = nil
  end
  if ilvl and ilvl > 0 then
    e.itemLevel = math_floor(ilvl + 0.5)
    CharacterMemory_UpdateUI()
  end
end

-- -----------------------------------------------------------------------------
-- State and cooldowns
-- -----------------------------------------------------------------------------

local State = {
  -- legacy UI frame fields intentionally unused; kept to avoid runtime errors
  frame = nil,
  bar = nil,
  barText = nil,
  bodyFontString = nil,
  noteEditBox = nil,
  shareButton = nil,
  currentGUID = nil,
  wasOpenBeforeCombat = false,
}

-- Per-target cooldown tables (GUID -> timestamp)
local Cooldowns = {
  emote = {},       -- 10s
  whisper = {},     -- 60s
  retarget = {},    -- track last seen in entry; this table unused for logic but kept for clarity
  groupTick = {},   -- 300s gating per GUID
  tavernTick = {},  -- 120s gating per GUID
  instanceGroupTick = {}, -- 120s while inside instances
}

local function canFireCooldown(tbl, guid, cdSeconds)
  local last = tbl[guid]
  local t = GetTime()
  if not last or (t - last) >= cdSeconds then
    tbl[guid] = t
    return true
  end
  return false
end

-- Track counted group session per target to increment party/raid once per session
local GroupSessionCounted = {}
local GroupSessionStartAt = 0
local lastNearbyTickAt = 0
local lastChatTickAt = 0

-- -----------------------------------------------------------------------------
-- Data accessors
-- -----------------------------------------------------------------------------

function getOrCreateEntry(guid)
  if not guid then return nil end
  local e = CharacterMemoryDB.entries[guid]
  if not e then
    -- Only create entries for real player GUIDs; do not persist NPCs/creatures
    if type(guid) ~= "string" or not guid:match("^Player%-") then
      return nil
    end
    e = {
      name = "",
      isPlayer = false,
      class = nil,
      classFile = nil,
      race = nil,
      charLevel = nil,
      faction = nil,
      gender = nil,
      firstMetAt = nil,
      firstMetWhere = nil,
      lastSeenAt = nil,
      lastSeenWhere = nil,
      notes = "",
      metCount = 0,
      xp = 0,
      level = 0,
      tier = "Stranger",
      _lastSeenStamp = 0,
      profile = {
        alias = "",
        alignment = "",
        personality = "",
        ideals = "",
        bonds = "",
        flaws = "",
        plans = "",
        background = "",
        otherInfo = "",
        backstory = "",
        languages = "",
        proficiencies = "",
        appearance = { age = "", height = "", weight = "", eyes = "", hair = "" },
      },
      stats = {
        parties = 0,
        raids = 0,
        pvpMatches = 0,
        arenaMatches = 0,
        duels = 0,
        petDuels = 0,
        trades = 0,
        whispers = 0,
        emotes = 0,
        dungeonCompletions = 0,
        mplusCompletions = 0,
        scenarioCompletions = 0,
        bossKillsDungeon = 0,
        bossKillsRaid = 0,
        groupTicks = 0,
        instanceTicks_party = 0,
        instanceTicks_raid = 0,
        instanceTicks_pvp = 0,
        instanceTicks_arena = 0,
        tavernTicks = 0,
        reconnects = 0,
        firstMeets = 0,
      },
    }
    CharacterMemoryDB.entries[guid] = e
  end
  return e
end

-- Expose for achievements module
_G.CharacterMemory_GetOrCreateEntry = getOrCreateEntry

local function deleteEntry(guid)
  if guid and CharacterMemoryDB.entries[guid] then
    CharacterMemoryDB.entries[guid] = nil
    if State.currentGUID == guid then
      State.currentGUID = nil
    end
  end
end

-- -----------------------------------------------------------------------------
-- XP engine
-- -----------------------------------------------------------------------------

local function refreshRelationship(entry)
  entry.level = computeLevelFromXP(entry.xp)
  
  -- Hard requirement: Strangers need 3 completed achievements to become Acquaintances
  if entry.level == 1 then
    local achievementSummary = _G.CharacterMemory_GetAchievementSummary and _G.CharacterMemory_GetAchievementSummary(entry.guid or "")
    local completedAchievements = achievementSummary and achievementSummary.done or 0
    
    if completedAchievements < 3 then
      -- Force them to stay at level 0 (Stranger) until they complete 3 achievements
      entry.level = 0
      entry.tier = "Stranger"
      return
    end
  end
  
  entry.tier = computeTierFromLevel(entry.level)
end

local function ensureStats(entry)
  entry.stats = entry.stats or {}
  local s = entry.stats
  local defaults = {
    parties=0, raids=0, pvpMatches=0, arenaMatches=0, duels=0, petDuels=0,
    trades=0, whispers=0, emotes=0, dungeonCompletions=0, mplusCompletions=0,
    scenarioCompletions=0, bossKillsDungeon=0, bossKillsRaid=0, groupTicks=0,
    instanceTicks_party=0, instanceTicks_raid=0, instanceTicks_pvp=0, instanceTicks_arena=0,
    tavernTicks=0, reconnects=0, firstMeets=0,
    readyChecks=0, wipesWith=0,
    bgWins=0, bgLosses=0, arenaWins=0, arenaLosses=0,
    groupSeconds=0,
    invitesFrom=0, invitesTo=0,
    nearbyTicks=0,
    partyChatMsgs=0, raidChatMsgs=0,
  }
  for k,v in pairs(defaults) do if s[k] == nil then s[k] = v end end
  return s
end

-- Achievements are defined and exposed from CM_Achievements.lua

local function incStat(guid, key, amount)
  local e = getOrCreateEntry(guid)
  if not e then return end
  local s = ensureStats(e)
  s[key] = (s[key] or 0) + (amount or 1)
end

local function toastXP(entry, amount, reason)
  if not entry or not entry.isPlayer then return end
  -- Only notify on level-ups (rank ups), not every XP award. Detect a level change
  -- by comparing computed level from XP before and after inside awardXP.
  if entry._justRankedUp then
    local message = string_format("%s: Rank up! Lv %d (%s)", shortName(entry.name), entry.level, entry.tier)
    printMessage(message)
    entry._justRankedUp = nil
  end
end

function awardXP(guid, amount, reason)
  local entry = getOrCreateEntry(guid)
  if not entry or not amount or amount <= 0 then return end
  local beforeLevel = entry.level or computeLevelFromXP(entry.xp or 0)
  entry.xp = (entry.xp or 0) + amount
  
  -- Compute what the level would be without the achievement requirement
  local computedLevel = computeLevelFromXP(entry.xp)
  local wouldHaveRankedUp = computedLevel > beforeLevel
  
  refreshRelationship(entry)
  local afterLevel = entry.level
  
  -- Check if they were blocked by achievement requirement
  local wasBlocked = false
  if wouldHaveRankedUp and afterLevel == beforeLevel then
    -- They would have ranked up but didn't - check if it's due to achievement requirement
    local achievementSummary = _G.CharacterMemory_GetAchievementSummary and _G.CharacterMemory_GetAchievementSummary(guid)
    local completedAchievements = achievementSummary and achievementSummary.done or 0
    
    if completedAchievements < 3 then
      wasBlocked = true
      -- Show a helpful message about the requirement
      local message = string_format("%s: Need 3 achievements to rank up! (%d/3 completed)", 
        shortName(entry.name), completedAchievements)
      printMessage(message)
    end
  end
  
  if wouldHaveRankedUp and not wasBlocked then
    entry._justRankedUp = true
  end
  
  -- update UI if this is the active target
  if State.currentGUID == guid then CharacterMemory_UpdateUI() end
  if _G.CMJ and _G.CMJ.NotifyDataChanged then _G.CMJ.NotifyDataChanged() end
  toastXP(entry, amount, reason)
end

-- Make awardXP available for slash manual award
_G.CharacterMemory_AwardXP = awardXP

-- -----------------------------------------------------------------------------
-- UI
-- -----------------------------------------------------------------------------

-- Compact floating panel removed; journal UI handles display

-- Legacy journal UI removed; CM_Journal.lua provides CMUI journal
-- (journal list helpers removed here to avoid duplicate UI; CM_Journal.lua owns the journal UI)

-- Legacy CharacterMemory_ToggleJournal removed; CMUI.Toggle handles journal

function CharacterMemory_UpdateUI()
  -- No-op: compact panel removed; use the journal instead (/cm journal)
  -- OPT: Nudge the journal to refresh if it is open so selection/details stay in sync
  if _G.CMJ and _G.CMJ.refs and _G.CMJ.refs.root and _G.CMJ.refs.root:IsShown() then
    if _G.CMJ.RefreshList then _G.CMJ.RefreshList() end
    if _G.CMJ.PopulateDetail and _G.CMJ.refs and _G.CMJ.refs.root then
      local sel = _G.CharacterMemoryDB and _G.CharacterMemoryDB.settings and _G.CharacterMemoryDB.settings.ui and _G.CharacterMemoryDB.settings.ui.journal and _G.CharacterMemoryDB.settings.ui.journal.lastSelected
      if sel then pcall(_G.CMJ.PopulateDetail, sel) end
    end
  end
end

local function showIfSettingAllows()
  if CharacterMemoryDB.settings.showOnTarget then
    CharacterMemory_UpdateUI()
  else
    if State.frame then State.frame:Hide() end
  end
end

-- -----------------------------------------------------------------------------
-- Event handling and business logic
-- -----------------------------------------------------------------------------

local function shareToGroupOrSay(text)
  if IsInRaid() then
    SendChatMessage(text, "RAID")
  elseif IsInGroup() then
    SendChatMessage(text, "PARTY")
  else
    SendChatMessage(text, "SAY")
  end
end

function CharacterMemory_Share(guid)
  guid = guid or State.currentGUID
  if not guid then return end
  local e = CharacterMemoryDB.entries[guid]
  if not e then return end
  local msg = string.format("%s — First met %s in %s. Lv %d (%s), %d XP.", shortName(e.name), e.firstMetAt or "—", e.firstMetWhere or "—", e.level or 0, e.tier or "Stranger", e.xp or 0)
  shareToGroupOrSay(msg)
end

local function isCurrentTargetGroupmate()
  if not UnitExists("target") then return false end
  local tName, tRealm = UnitName("target")
  local check = tRealm and (tName .. "-" .. tRealm) or tName
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name = GetRaidRosterInfo(i)
      if name and (name == check or shortName(name) == shortName(check)) then return true end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n .. "-" .. r) or n
        if full == check or shortName(full) == shortName(check) then return true end
      end
    end
  end
  return false
end

-- Track one-time awards to avoid double-credit inside the same encounter/session
local AwardedEncounters = {} -- [guid] = { [encounterID] = true }

-- Track a simple dungeon run state for non-LFG 5-man dungeons so we can
-- credit "Dungeons" on exit even when LFG-specific events don't fire.
local DungeonRun = {
  active = false,        -- we killed at least one boss in a 5-man instance this run
  instanceID = nil,      -- GetInstanceInfo() instanceID captured when we first succeed a boss
  lastBossKillAt = 0,    -- time of the most recent successful boss
  credited = false       -- whether we already counted a completion for this run
}

local function resetDungeonRun()
  DungeonRun.active, DungeonRun.instanceID, DungeonRun.lastBossKillAt, DungeonRun.credited = false, nil, 0, false
end

local function maybeCreditDungeonOnExit()
  -- If we recently killed a boss in a 5-man and we leave the instance without
  -- seeing LFG/Scenario/Challenge completion events, count a completion once.
  if not DungeonRun.active or DungeonRun.credited then return end
  local now = GetTime and GetTime() or 0
  if (now - (DungeonRun.lastBossKillAt or 0)) > 900 then -- safety window 15m
    resetDungeonRun()
    return
  end
  awardToAllGroupmates(100, "dungeon complete")
  incStatForAllGroupmates("dungeonCompletions", 1)
  DungeonRun.credited = true
  resetDungeonRun()
end

local function isInInstanceOfTypes(types)
  local inInstance, instType = IsInInstance()
  if not inInstance then return false end
  for _, t in ipairs(types) do
    if instType == t then return true end
  end
  return false
end

-- Iterate current group's member GUIDs (excluding the player) and invoke a callback
local function forEachGroupmateGUID(callback)
  if type(callback) ~= "function" then return end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) and not UnitIsUnit(unit, "player") then
        local guid = UnitGUID(unit)
        if guid then callback(guid, unit) end
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) and not UnitIsUnit(unit, "player") then
        local guid = UnitGUID(unit)
        if guid then callback(guid, unit) end
      end
    end
  end
end

local function awardToAllGroupmates(amount, reason)
  if not amount or amount <= 0 then return end
  forEachGroupmateGUID(function(guid)
    awardXP(guid, amount, reason)
  end)
end

local function incStatForAllGroupmates(key, amount)
  forEachGroupmateGUID(function(guid)
    incStat(guid, key, amount or 1)
  end)
end

local function awardIfTargetGroupmate(amount, reason)
  if not State.currentGUID then return end
  if not UnitExists("target") or not UnitIsPlayer("target") then return end
  if not isCurrentTargetGroupmate() then return end
  awardXP(State.currentGUID, amount, reason)
end

-- Find a current groupmate by short name and return their GUID (and unit token)
local function getGroupmateGUIDByName(name)
  if not name or name == "" then return nil, nil end
  local targetShort = shortName(name)
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n .. "-" .. r) or n
        if shortName(full) == targetShort then return UnitGUID(unit), unit end
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n .. "-" .. r) or n
        if shortName(full) == targetShort then return UnitGUID(unit), unit end
      end
    end
  end
  return nil, nil
end

local function handleTargetChanged()
  if not UnitExists("target") then
    State.currentGUID = nil
    if State.frame then State.frame:Hide() end
    return
  end

  local guid = UnitGUID("target")
  if not guid then return end
  -- Ignore non-player GUIDs; do not create or update entries for NPCs/creatures
  if not guid:match("^Player%-") then
    State.currentGUID = nil
    return
  end
  State.currentGUID = guid

  local entry = getOrCreateEntry(guid)
  if not entry then return end
  local name, realm = UnitName("target")
  local fullName = realm and (name .. "-" .. realm) or name
  entry.displayName = fullName
  entry.name = fullName or entry.name or "Unknown"
  entry.isPlayer = UnitIsPlayer("target") and true or false
  if entry.isPlayer then
    local className, classFile = UnitClass("target")
  local raceName, raceFile = UnitRace("target")
    local level = UnitLevel("target")
    local faction = UnitFactionGroup("target")
    local gender = UnitSex("target") -- 2 male, 3 female
    local guildName = GetGuildInfo and select(1, GetGuildInfo("target")) or nil
    entry.class = className
    entry.classFile = classFile
    entry.race = raceName
    entry.raceFile = raceFile
    entry.charLevel = level
    entry.faction = faction
    entry.gender = gender
    entry.guildName = guildName
    -- Friend flag (simple heuristic)
    if C_FriendList and C_FriendList.IsFriend then
      local isFriend = C_FriendList.IsFriend(guid) or false
      entry.isFriend = isFriend and true or false
    end
  end

  -- Request an inspect to fetch item level for the target player (throttled)
  if entry.isPlayer then
    CharacterMemory_RequestTargetItemLevel()
  end

  local nowStamp = time()
  local where = getZoneContext()

  local firstMeet = false
  if entry.metCount == 0 then
    entry.firstMetAt = nowUTCString()
    entry.firstMetWhere = where
    firstMeet = true
  end

  entry.metCount = (entry.metCount or 0) + 1
  entry.lastSeenAt = nowUTCString()
  entry.lastSeenWhere = where

  -- Retarget XP if >= 10 minutes
  if entry._lastSeenStamp and entry._lastSeenStamp > 0 then
    if (nowStamp - entry._lastSeenStamp) >= 600 then
      awardXP(guid, 10, "retarget")
      incStat(guid, "reconnects", 1)
    end
  end
  entry._lastSeenStamp = nowStamp

  -- First meet XP
  if firstMeet then
    awardXP(guid, 50, "first meet")
    incStat(guid, "firstMeets", 1)
    if CharacterMemoryDB.settings.shareEnabled then
      shareToGroupOrSay(string_format("First met %s in %s.", FmtDate(entry.firstMetAt), FmtZone(entry.firstMetWhere)))
    end
  end

  showIfSettingAllows()
  if _G.CMJ and _G.CMJ.NotifyDataChanged then _G.CMJ.NotifyDataChanged() end
end

-- CHAT_MSG_TEXT_EMOTE: positive emotes
local function handleTextEmote(event, text, playerName)
  -- Emotes are target/proximity based (no group required), but must be tied to current target
  if not State.currentGUID then return end
  local entry = CharacterMemoryDB.entries[State.currentGUID]
  if not entry or not entry.isPlayer then return end
  local emote = text and text:match("^%*(%w+)") -- rarely of the form "PlayerName waves" in text emotes; safer is to use standard parsing
  -- Fallback: try find keyword present in text
  local matched = nil
  for k in pairs(POSITIVE_EMOTES) do
    if text and text:lower():find(k) then matched = k break end
  end
  if not matched then return end

  -- verify sender matches the target or player
  local targetShort = shortName(entry.name)
  if playerName and (shortName(playerName) == targetShort or shortName(playerName) == shortName(UnitName("player"))) then
    if canFireCooldown(Cooldowns.emote, State.currentGUID, 10) then
      awardXP(State.currentGUID, 8, "emote")
      incStat(State.currentGUID, "emotes", 1)
    end
    -- Track per-emote history for achievements regardless of cooldown
    local tl = matched and matched:lower() or ""
    if tl == "hug" or tl == "kiss" or tl == "love" then
      if _G.CM_LogEmoteForAchievements then pcall(_G.CM_LogEmoteForAchievements, State.currentGUID, tl) end
    end
  end
end

-- Whisper exchange
local function handleWhisper(event, text, otherName)
  -- Whispers are target-based (no group required)
  if not State.currentGUID then return end
  local entry = CharacterMemoryDB.entries[State.currentGUID]
  if not entry or not entry.isPlayer then return end
  -- otherName is sender for CHAT_MSG_WHISPER, recipient for CHAT_MSG_WHISPER_INFORM
  if not otherName then return end
  if shortName(otherName) ~= shortName(entry.name) then return end
  if canFireCooldown(Cooldowns.whisper, State.currentGUID, 60) then
    awardXP(State.currentGUID, 12, "whisper")
    incStat(State.currentGUID, "whispers", 1)
  end
end

-- Trade
local function handleTradeClosed()
  -- Trades are target-based (no group required)
  if not State.currentGUID then return end
  local e = CharacterMemoryDB.entries[State.currentGUID]
  if not e or not e.isPlayer then return end
  awardXP(State.currentGUID, 60, "trade")
  incStat(State.currentGUID, "trades", 1)
end

-- Duel
local function handleDuelFinished()
  -- Duels are target-based (no group required)
  if not State.currentGUID then return end
  local e = CharacterMemoryDB.entries[State.currentGUID]
  if not e or not e.isPlayer then return end
  awardXP(State.currentGUID, 40, "duel")
  incStat(State.currentGUID, "duels", 1)
end

-- Group tick (every 300s)
local function groupTick()
  -- Credit all current groupmates every 5 minutes
  forEachGroupmateGUID(function(guid)
    if canFireCooldown(Cooldowns.groupTick, guid, 300) then
      awardXP(guid, 25, "group time")
      incStat(guid, "groupTicks", 1)
      local e = getOrCreateEntry(guid)
      if e then
        e.stats = ensureStats(e)
        local now = GetTime()
        if GroupSessionStartAt == 0 then GroupSessionStartAt = now end
        e.stats.groupSeconds = (e.stats.groupSeconds or 0) + 300
      end
      if not GroupSessionCounted[guid] then
        GroupSessionCounted[guid] = true
        if IsInRaid() then
          incStat(guid, "raids", 1)
        else
          incStat(guid, "parties", 1)
        end
      end
    end
  end)
end

-- Tavern tick (every 120s) while resting and target exists and is player
local function tavernTick()
  -- Award only when resting and with nearby groupmates (roughly within interact range)
  if not IsResting() then return end
  forEachGroupmateGUID(function(guid, unit)
    local nearby = false
    if CheckInteractDistance then nearby = CheckInteractDistance(unit, 1) and true or false end -- ~28 yards
    if nearby and canFireCooldown(Cooldowns.tavernTick, guid, 120) then
      awardXP(guid, 20, "tavern")
      incStat(guid, "tavernTicks", 1)
    end
  end)
end

-- Instance group tick (every 120s) while in dungeon/raid/bg/arena with target groupmate
local function instanceGroupTick()
  local inInstance, instType = IsInInstance()
  if not inInstance then return end
  local amount = 0
  if instType == "party" then amount = 15
  elseif instType == "raid" then amount = 20
  elseif instType == "pvp" then amount = 12
  elseif instType == "arena" then amount = 18 end
  if amount <= 0 then return end
  forEachGroupmateGUID(function(guid)
    if canFireCooldown(Cooldowns.instanceGroupTick, guid, 120) then
      awardXP(guid, amount, "instance time")
      if instType == "party" then incStat(guid, "instanceTicks_party", 1)
      elseif instType == "raid" then incStat(guid, "instanceTicks_raid", 1)
      elseif instType == "pvp" then incStat(guid, "instanceTicks_pvp", 1)
      elseif instType == "arena" then incStat(guid, "instanceTicks_arena", 1) end
    end
  end)
end

-- Boss kills and completions
local function handleEncounterEnd(encounterID, encounterName, difficultyID, raidSize, endStatus)
  if endStatus ~= 1 then return end -- only on success
  local inInstance, instType = IsInInstance()
  if not inInstance then return end
  -- Credit all current groupmates once per encounterID
  forEachGroupmateGUID(function(guid)
    AwardedEncounters[guid] = AwardedEncounters[guid] or {}
    if not AwardedEncounters[guid][encounterID] then
      AwardedEncounters[guid][encounterID] = true
      if instType == "party" then
        awardXP(guid, 40, "boss kill")
        incStat(guid, "bossKillsDungeon", 1)
        -- Mark that we have an active dungeon run with at least one boss kill
        DungeonRun.active = true
        DungeonRun.lastBossKillAt = GetTime and GetTime() or 0
        DungeonRun.instanceID = select(8, GetInstanceInfo())
      elseif instType == "raid" then
        awardXP(guid, 80, "boss kill")
        incStat(guid, "bossKillsRaid", 1)
      end
    end
  end)
end

-- Wipe tracking
local function handleEncounterStart(encounterID)
  forEachGroupmateGUID(function(guid)
    AwardedEncounters[guid] = AwardedEncounters[guid] or {}
    AwardedEncounters[guid][encounterID] = AwardedEncounters[guid][encounterID] or false
  end)
end

local function handleEncounterEndAny(encounterID, encounterName, difficultyID, raidSize, endStatus)
  if endStatus ~= 1 then
    incStatForAllGroupmates("wipesWith", 1)
  end
end

local function handleLFGCompletion()
  awardToAllGroupmates(100, "dungeon complete")
  incStatForAllGroupmates("dungeonCompletions", 1)
end

local function handleChallengeModeCompleted()
  awardToAllGroupmates(120, "mythic+ complete")
  incStatForAllGroupmates("mplusCompletions", 1)
end

local function handleScenarioCompleted()
  awardToAllGroupmates(60, "scenario complete")
  incStatForAllGroupmates("scenarioCompletions", 1)
end

local function handlePvpMatchComplete()
  local inInstance, instType = IsInInstance()
  if not inInstance then return end
  if instType == "pvp" then
    awardToAllGroupmates(40, "battleground match")
    incStatForAllGroupmates("pvpMatches", 1)
  elseif instType == "arena" then
    awardToAllGroupmates(50, "arena match")
    incStatForAllGroupmates("arenaMatches", 1)
  end
end

-- -----------------------------------------------------------------------------
-- Slash commands
-- -----------------------------------------------------------------------------

local function printHelp()
  printMessage("/cm help — Show commands")
  printMessage("/cm note <text> — Save note for current target")
  printMessage("/cm share — Share current memory")
  printMessage("/cm show — Show the panel")
  printMessage("/cm hide — Hide the panel")
  printMessage("/cm delete — Delete current target memory")
  printMessage("/cm toggle — Toggle show-on-target")
  printMessage("/cm autoshares — Toggle first-meet auto-share")
  printMessage("/cm rel — Show relationship info")
  printMessage("/cm reladd <xp> — Add XP to current target")
  printMessage("/cm journal — Toggle the journal window")
  printMessage("/cm profile — Show profile for current target")
  if GetCVar and GetCVar("scriptProfile") == "1" then
    printMessage("/cm cpu — AddOn CPU usage and top funcs (dev)")
    printMessage("/cm mem — AddOn memory usage (dev)")
  end
end

SLASH_CHARACTERMEMORY1 = "/cm"
SLASH_CHARACTERMEMORY2 = "/cmem"
SLASH_CHARACTERMEMORY3 = "/charactermemory"
SLASH_CHARACTERMEMORY4 = "/cmemory"
SlashCmdList["CHARACTERMEMORY"] = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower() or "help"

  if cmd == "help" or cmd == "" then
    printHelp()

  elseif cmd == "note" then
    if not State.currentGUID then printMessage("No target.") return end
    local e = getOrCreateEntry(State.currentGUID)
    e.notes = rest or ""
    printMessage("Saved note for " .. shortName(e.name))
    CharacterMemory_UpdateUI()

  elseif cmd == "share" then
    CharacterMemory_Share()

  elseif cmd == "show" then
    if _G.CharacterMemory_OpenJournal then _G.CharacterMemory_OpenJournal() else printMessage("Use /cm journal.") end

  elseif cmd == "hide" then
    printMessage("Compact panel removed. Close the journal instead.")

  elseif cmd == "delete" then
    if not State.currentGUID then printMessage("No target.") return end
    deleteEntry(State.currentGUID)
    printMessage("Deleted memory for target.")
    if State.frame then State.frame:Hide() end

  elseif cmd == "toggle" then
    CharacterMemoryDB.settings.showOnTarget = not CharacterMemoryDB.settings.showOnTarget
    printMessage("Show on target: " .. (CharacterMemoryDB.settings.showOnTarget and "ON" or "OFF"))

  elseif cmd == "autoshares" then
    CharacterMemoryDB.settings.shareEnabled = not CharacterMemoryDB.settings.shareEnabled
    printMessage("Auto-share on first meet: " .. (CharacterMemoryDB.settings.shareEnabled and "ON" or "OFF"))

  elseif cmd == "rel" then
    if not State.currentGUID then printMessage("No target.") return end
    local e = getOrCreateEntry(State.currentGUID)
    printMessage(string.format("%s — Lv %d (%s), %d XP", shortName(e.name), e.level or 0, e.tier or "Stranger", e.xp or 0))

  elseif cmd == "reladd" then
    if not State.currentGUID then printMessage("No target.") return end
    local val = tonumber(rest or "0") or 0
    if val <= 0 then printMessage("Usage: /cm reladd <xp>") return end
    awardXP(State.currentGUID, val, "manual")

  elseif cmd == "journal" then
    -- Ensure the external CM_Journal UI is used; fallback safely if not loaded
    if _G.CharacterMemory_OpenJournal then
      _G.CharacterMemory_OpenJournal()
    elseif CMUI and CMUI.Toggle then
      CMUI.Toggle()
    else
      printMessage("Journal UI not loaded.")
    end

  elseif cmd == "profile" or cmd == "sheet" or cmd == "prof" then
    printMessage("Profile view has moved to the journal. Use /cm journal.")

  elseif GetCVar and GetCVar("scriptProfile") == "1" and (cmd == "cpu" or cmd == "mem") then
    -- OPT: Dev-only profiling helpers (to be removed in release)
    if cmd == "cpu" then
      UpdateAddOnCPUUsage()
      local addonCPU = GetAddOnCPUUsage("CharacterMemory")
      printMessage(string_format("CPU: %d ms", addonCPU or 0))
      local profList = _G.CharacterMemory_ProfiledFunctions or {}
      local scores = {}
      for name, fn in pairs(profList) do
        local cpuFn = rawget(_G, "GetFunctionCPUUsage")
        local used = (type(cpuFn) == "function") and cpuFn(fn, true) or 0 -- OPT: guard for linter
        table.insert(scores, {name=name, used=used or 0})
      end
      table.sort(scores, function(a,b) return a.used > b.used end)
      for i=1, math.min(5, #scores) do
        printMessage(string_format("%d) %s — %d ms", i, scores[i].name, scores[i].used))
      end
    else
      UpdateAddOnMemoryUsage()
      local mem = GetAddOnMemoryUsage("CharacterMemory")
      printMessage(string_format("Mem: %.1f KB", tonumber(mem or 0)))
    end

  else
    printHelp()
  end
end

-- -----------------------------------------------------------------------------
-- Event frame
-- -----------------------------------------------------------------------------

local evt = CreateFrame("Frame")

evt:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == ADDON_NAME then
      initializeDatabase()
      wireEscapeAndFocus()
      fixupEntries()
      ensureOptionsPanelRegistered()
      -- Seed player's own item level immediately
      CharacterMemory_UpdatePlayerItemLevel()
      -- do not spawn legacy compact frame at load; journal handles main UI
      if State.frame then State.frame:Hide() end
      -- ensure slash command is bound to this handler
      SlashCmdList["CHARACTERMEMORY"] = SlashCmdList["CHARACTERMEMORY"] or function(msg) end
      -- Position
      local anch = CharacterMemoryDB.settings.anchor
      if State.frame then
        State.frame:ClearAllPoints()
        State.frame:SetPoint(anch.point or "CENTER", UIParent, anch.point or "CENTER", anch.x or 0, anch.y or 200)
      end
      printMessage("Loaded. Type /cm journal or /cmjournal")
    end

  elseif event == "PLAYER_TARGET_CHANGED" then
    handleTargetChanged()

  elseif event == "CHAT_MSG_TEXT_EMOTE" then
    handleTextEmote(event, ...)

  elseif event == "READY_CHECK" then
    if State.currentGUID then incStat(State.currentGUID, "readyChecks", 1) end

  elseif event == "PARTY_INVITE_REQUEST" then
    -- Someone invited us; if it's current target, count invitesFrom
    local inviter = ...
    if inviter and State.currentGUID then
      local e = getOrCreateEntry(State.currentGUID)
      if e and e.name and shortName(inviter) == shortName(e.name) then
        incStat(State.currentGUID, "invitesFrom", 1)
      end
    end

  elseif event == "GROUP_ROSTER_UPDATE" then
    -- If we have a target and we invite them (target in our party after invite), count invitesTo
    if State.currentGUID and UnitExists("target") and UnitGUID("target") == State.currentGUID then
      if isCurrentTargetGroupmate() then
        incStat(State.currentGUID, "invitesTo", 1)
      end
    end

  elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
    handleWhisper(event, ...)

  elseif event == "TRADE_CLOSED" then
    handleTradeClosed()

  elseif event == "DUEL_FINISHED" then
    handleDuelFinished()

  elseif event == "ENCOUNTER_END" then
    handleEncounterEnd(...)
    handleEncounterEndAny(...)

  elseif event == "ENCOUNTER_START" then
    handleEncounterStart(...)

  elseif event == "LFG_COMPLETION_REWARD" then
    handleLFGCompletion()
    resetDungeonRun()

  elseif event == "CHALLENGE_MODE_COMPLETED" then
    handleChallengeModeCompleted()
    resetDungeonRun()

  elseif event == "SCENARIO_COMPLETED" then
    handleScenarioCompleted()
    resetDungeonRun()

  elseif event == "PVP_MATCH_COMPLETE" or event == "BATTLEFIELDS_CLOSED" then
    handlePvpMatchComplete()

  elseif event == "PLAYER_REGEN_DISABLED" then
    -- entering combat
    if State.frame and State.frame:IsShown() then
      State.wasOpenBeforeCombat = true
      State.frame:Hide()
    else
      State.wasOpenBeforeCombat = false
    end

  elseif event == "PLAYER_REGEN_ENABLED" then
    -- leaving combat
    if State.wasOpenBeforeCombat then
      CharacterMemory_UpdateUI()
      State.wasOpenBeforeCombat = false
    end

  elseif event == "INSPECT_READY" then
    local inspectedGuid = ...
    CharacterMemory_OnInspectReady(inspectedGuid)

  elseif event == "UNIT_INVENTORY_CHANGED" then
    local unit = ...
    if unit == "player" then CharacterMemory_UpdatePlayerItemLevel() end

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    CharacterMemory_UpdatePlayerItemLevel()

  elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "FRIENDLIST_UPDATE" then
    -- Refresh guild/friend flags for current target if visible
    if State.currentGUID and UnitExists("target") and UnitGUID("target") == State.currentGUID then
      local e = getOrCreateEntry(State.currentGUID)
      if e then
        e.guildName = GetGuildInfo and select(1, GetGuildInfo("target")) or e.guildName
        if C_FriendList and C_FriendList.IsFriend then
          e.isFriend = C_FriendList.IsFriend(State.currentGUID) or e.isFriend
        end
      end
      CharacterMemory_UpdateUI()
    end

  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
    -- OPT: Refresh zone cache quickly on zone transitions
    zoneCache.stamp = 0
    -- If leaving a 5-man after a successful boss and we never saw a completion
    -- event (e.g., non-LFG classic dungeons), grant a completion once.
    maybeCreditDungeonOnExit()

  elseif event == "PLAYER_LOGOUT" then
    -- OPT: Cancel tickers to avoid orphan timers on reload
    if _G.CharacterMemory_Tickers then
      for _, tk in ipairs(_G.CharacterMemory_Tickers) do pcall(tk.Cancel, tk) end
    end

  elseif event == "NAME_PLATE_UNIT_ADDED" then
    local unit = ...
    if not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or guid ~= State.currentGUID then return end
    -- Only count proximity when not already grouped; throttle to once every 30s
    if isCurrentTargetGroupmate() then return end
    local now = GetTime() or 0
    if (now - (lastNearbyTickAt or 0)) >= 30 then
      lastNearbyTickAt = now
      incStat(State.currentGUID, "nearbyTicks", 1)
      CharacterMemory_UpdateUI()
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    -- no-op; presence is counted on added with throttle
  end
end)

evt:RegisterEvent("ADDON_LOADED")
evt:RegisterEvent("PLAYER_TARGET_CHANGED")
evt:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
evt:RegisterEvent("READY_CHECK")
evt:RegisterEvent("PARTY_INVITE_REQUEST")
evt:RegisterEvent("GROUP_ROSTER_UPDATE")
evt:RegisterEvent("CHAT_MSG_WHISPER")
evt:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
evt:RegisterEvent("TRADE_CLOSED")
evt:RegisterEvent("DUEL_FINISHED")
evt:RegisterEvent("ENCOUNTER_END")
evt:RegisterEvent("ENCOUNTER_START")
evt:RegisterEvent("LFG_COMPLETION_REWARD")
evt:RegisterEvent("CHALLENGE_MODE_COMPLETED")
evt:RegisterEvent("SCENARIO_COMPLETED")
evt:RegisterEvent("PVP_MATCH_COMPLETE")
evt:RegisterEvent("BATTLEFIELDS_CLOSED")
evt:RegisterEvent("PLAYER_REGEN_DISABLED")
evt:RegisterEvent("PLAYER_REGEN_ENABLED")
evt:RegisterEvent("ZONE_CHANGED")
evt:RegisterEvent("ZONE_CHANGED_INDOORS")
evt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
evt:RegisterEvent("PLAYER_LOGOUT")
evt:RegisterEvent("GUILD_ROSTER_UPDATE")
evt:RegisterEvent("PLAYER_GUILD_UPDATE")
evt:RegisterEvent("FRIENDLIST_UPDATE")
evt:RegisterEvent("NAME_PLATE_UNIT_ADDED")
evt:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
evt:RegisterEvent("INSPECT_READY")
evt:RegisterEvent("UNIT_INVENTORY_CHANGED")
evt:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

-- Addon message handling for bio exchange
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_MSG_PREFIX)
end

local function onAddonMessage(prefix, message, channel, sender)
  if prefix ~= ADDON_MSG_PREFIX then return end
  local tag, a, b = string.match(message or "", "^(.-)|([^|]*)|?(.*)$")
  if tag == "REQBIO" then
    -- Another user is requesting our bio
    sendBioWhisper(sender)
  elseif tag == "BIO" then
    local guid = a and a ~= "" and a or nil
    -- Split remaining payload fields by pipe
    local parts = {}
    if b and b ~= "" then for s in string.gmatch(b, "([^|]*)|?") do if s == nil then break end table.insert(parts, s) end end
    local function part(i) return unescapePipes(parts[i] or "") end
    local bio = part(1)
    local title, pronouns, tags, alias, alignment = part(2), part(3), part(4), part(5), part(6)
    local languages, proficiencies = part(7), part(8)
    local age, height, weight, eyes, hair = part(9), part(10), part(11), part(12), part(13)
    if guid and bio then
      CharacterMemoryDB.entries = CharacterMemoryDB.entries or {}
      local e = CharacterMemoryDB.entries[guid] or { profile = {} }
      e.profile = e.profile or {}
      -- Store received bio into publicBio field
      e.profile.publicBio = bio
      -- Also hydrate identity/details for display if provided
      if title ~= "" then e.profile.title = title end
      if pronouns ~= "" then e.profile.pronouns = pronouns end
      if tags ~= "" then e.profile.tags = tags end
      if alias ~= "" then e.profile.alias = alias end
      if alignment ~= "" then e.profile.alignment = alignment end
      if languages ~= "" then e.profile.languages = languages end
      if proficiencies ~= "" then e.profile.proficiencies = proficiencies end
      e.profile.appearance = e.profile.appearance or {}
      if age ~= "" then e.profile.appearance.age = age end
      if height ~= "" then e.profile.appearance.height = height end
      if weight ~= "" then e.profile.appearance.weight = weight end
      if eyes ~= "" then e.profile.appearance.eyes = eyes end
      if hair ~= "" then e.profile.appearance.hair = hair end
      CharacterMemoryDB.entries[guid] = e
      CharacterMemory_UpdateUI()
    end
  end
end

local bioEvt = CreateFrame("Frame")
bioEvt:RegisterEvent("CHAT_MSG_ADDON")
bioEvt:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
  onAddonMessage(prefix, message, channel, sender)
end)

-- Tickers
-- OPT: Store ticker refs for cleanup on reload/disable
_G.CharacterMemory_Tickers = _G.CharacterMemory_Tickers or {}
table.insert(_G.CharacterMemory_Tickers, C_Timer.NewTicker(300, groupTick))
table.insert(_G.CharacterMemory_Tickers, C_Timer.NewTicker(120, tavernTick))
table.insert(_G.CharacterMemory_Tickers, C_Timer.NewTicker(120, instanceGroupTick))

-- OPT: Removed duplicate/no-op event frame, tooltip, and unused options panel to avoid taint and redundant handlers

-- OPT: Build profiling registry for /cm cpu (dev only)
_G.CharacterMemory_ProfiledFunctions = {
  awardXP = awardXP,
  handleTargetChanged = handleTargetChanged,
  handleTextEmote = handleTextEmote,
  handleWhisper = handleWhisper,
  groupTick = groupTick,
  tavernTick = tavernTick,
  instanceGroupTick = instanceGroupTick,
}

-- Delete entry confirmation dialog
StaticPopupDialogs["CONFIRM_DELETE_CHARACTER_MEMORY_ENTRY"] = {
  text = "Are you sure you want to delete this character from your memory? This action cannot be undone.",
  button1 = "Delete",
  button2 = "Cancel",
  OnAccept = function(self, data)
    if data and data.guid then
      -- Remove the entry from the database
      if CharacterMemoryDB and CharacterMemoryDB.entries then
        CharacterMemoryDB.entries[data.guid] = nil
      end
      
      -- Update UI if this was the selected entry
      if _G.CMJ and _G.CMJ.NotifyDataChanged then
        _G.CMJ.NotifyDataChanged()
      end
      
      -- Clear selection if this was the selected entry
      if _G.CMJ and _G.CMJ.refs and _G.CMJ.refs.root and _G.CMJ.refs.root:IsShown() then
        if _G.CMJ.Model and _G.CMJ.Model.selected == data.guid then
          _G.CMJ.Model.selected = nil
          _G.CMJ.PopulateDetail(nil)
        end
      end
      
      printMessage("Character deleted from memory.")
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
