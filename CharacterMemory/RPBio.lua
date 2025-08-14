-- SavedVariablesPerCharacter: RPJournalDB

local ALIGNMENT_OPTIONS = {
  "Lawful Good","Neutral Good","Chaotic Good",
  "Lawful Neutral","True Neutral","Chaotic Neutral",
  "Lawful Evil","Neutral Evil","Chaotic Evil",
}

local AVAILABILITY_OPTIONS = { "Always", "Evenings", "Weekends", "By arrangement" }

local function ensureDB()
  RPJournalDB = RPJournalDB or {}
  RPJournalDB.bio = RPJournalDB.bio or {
    identity = {}, appearance = {}, lore = {}, personality = {},
    skills = {}, relationships = {}, rpPrefs = {}, notes = {},
  }
  return RPJournalDB.bio
end

local function g(name) return _G[name] end
local function getBox(name) local o = g(name); return o and o:GetText() or "" end
local function setBox(name, v) if g(name) then g(name):SetText(v or "") end end

-- InputScrollFrameTemplate helpers
local function getMulti(name)
  local eb = g(name.."EditBox"); return eb and eb:GetText() or ""
end
local function setMulti(name, v)
  local eb = g(name.."EditBox"); if eb then eb:SetText(v or "") end
end

local function initDropdown(frameName, options, savedValue)
  local frame = g(frameName)
  if not frame then return end
  UIDropDownMenu_SetWidth(frame, 180)
  UIDropDownMenu_Initialize(frame, function(self, level)
    for _, label in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.func = function()
        UIDropDownMenu_SetSelectedName(frame, label)
        frame.value = label
      end
      info.checked = (UIDropDownMenu_GetSelectedName(frame) == label)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  if savedValue and savedValue ~= "" then
    UIDropDownMenu_SetSelectedName(frame, savedValue)
    frame.value = savedValue
  else
    UIDropDownMenu_SetSelectedID(frame, 1)
    frame.value = options[1]
  end
end

local function splitList(s)
  local out = {}
  s = (s or ""):gsub("%s*,%s*", ",")
  for item in string.gmatch(s, "([^,]+)") do
    item = item:sub(1, 24)
    table.insert(out, item)
  end
  return out
end

function RPBio_Save()
  local db = ensureDB()

  db.identity.title        = getBox("RPBio_Title")
  db.identity.nicknames    = splitList(getBox("RPBio_Nicknames"))
  db.identity.pronouns     = getBox("RPBio_Pronouns")
  db.identity.race         = getBox("RPBio_Race")
  db.identity.homeland     = getBox("RPBio_Homeland")
  db.identity.residence    = getBox("RPBio_Residence")
  db.identity.affiliations = getBox("RPBio_Affiliations")

  db.appearance.height     = getBox("RPBio_Height")
  db.appearance.build      = getBox("RPBio_Build")
  db.appearance.eyes       = getBox("RPBio_Eyes")
  db.appearance.hair       = getBox("RPBio_Hair")
  db.appearance.features   = getBox("RPBio_Features")
  db.appearance.attire     = getBox("RPBio_Attire")

  local shortBio = getMulti("RPBio_ShortBio")
  if shortBio and #shortBio > 500 then shortBio = string.sub(shortBio, 1, 500) end
  db.lore.shortBio   = shortBio or ""
  db.lore.backstory  = getMulti("RPBio_Backstory"):sub(1, 12000)
  db.lore.alignment  = (g("RPBio_AlignmentDD") and g("RPBio_AlignmentDD").value) or ""
  db.lore.creed      = getBox("RPBio_Creed")
  db.lore.deeds      = getMulti("RPBio_Deeds")

  db.personality.traits = splitList(getBox("RPBio_Traits"))
  db.personality.ideals = getBox("RPBio_Ideals")
  db.personality.bonds  = getBox("RPBio_Bonds")
  db.personality.flaws  = getBox("RPBio_Flaws")
  db.personality.hooks  = getMulti("RPBio_Hooks")

  db.skills.occupation  = getBox("RPBio_Occupation")
  db.skills.languages   = splitList(getBox("RPBio_Languages"))
  db.skills.hobbies     = splitList(getBox("RPBio_Hobbies"))
  db.skills.combatFocus = getBox("RPBio_CombatFocus")

  db.relationships.partner      = { character = getBox("RPBio_Partner"), note = getBox("RPBio_PartnerNote") }
  db.relationships.family       = { getMulti("RPBio_Family") }
  db.relationships.allies       = { getMulti("RPBio_Allies") }
  db.relationships.rivals       = { getMulti("RPBio_Rivals") }
  db.relationships.pets         = { getMulti("RPBio_Pets") }

  db.rpPrefs.availability = (g("RPBio_AvailabilityDD") and g("RPBio_AvailabilityDD").value) or ""
  db.rpPrefs.tone         = splitList(getBox("RPBio_Tone"))
  db.rpPrefs.limits       = getMulti("RPBio_Limits")
  db.rpPrefs.oocContact   = getBox("RPBio_OOC")
  db.rpPrefs.limitsPrivate = g("RPBio_LimitsPrivate") and g("RPBio_LimitsPrivate"):GetChecked() or false

  db.notes.public = getMulti("RPBio_PublicNotes")
  db.notes.private = getMulti("RPBio_PrivateNotes")

  print("|cffffd100RP Character Sheet saved.|r")
end

local function loadIntoFields()
  local b = ensureDB()

  setBox("RPBio_Title", b.identity.title)
  setBox("RPBio_Nicknames", table.concat(b.identity.nicknames or {}, ", "))
  setBox("RPBio_Pronouns", b.identity.pronouns)
  setBox("RPBio_Race", b.identity.race)
  setBox("RPBio_Homeland", b.identity.homeland)
  setBox("RPBio_Residence", b.identity.residence)
  setBox("RPBio_Affiliations", b.identity.affiliations)

  setBox("RPBio_Height", b.appearance.height)
  setBox("RPBio_Build", b.appearance.build)
  setBox("RPBio_Eyes", b.appearance.eyes)
  setBox("RPBio_Hair", b.appearance.hair)
  setBox("RPBio_Features", b.appearance.features)
  setBox("RPBio_Attire", b.appearance.attire)

  setMulti("RPBio_ShortBio", b.lore.shortBio)
  setMulti("RPBio_Backstory", b.lore.backstory)
  initDropdown("RPBio_AlignmentDD", ALIGNMENT_OPTIONS, b.lore.alignment)
  setBox("RPBio_Creed", b.lore.creed)
  setMulti("RPBio_Deeds", b.lore.deeds)

  setBox("RPBio_Traits", table.concat(b.personality.traits or {}, ", "))
  setBox("RPBio_Ideals", b.personality.ideals)
  setBox("RPBio_Bonds", b.personality.bonds)
  setBox("RPBio_Flaws", b.personality.flaws)
  setMulti("RPBio_Hooks", b.personality.hooks)

  setBox("RPBio_Occupation", b.skills.occupation)
  setBox("RPBio_Languages", table.concat(b.skills.languages or {}, ", "))
  setBox("RPBio_Hobbies", table.concat(b.skills.hobbies or {}, ", "))
  setBox("RPBio_CombatFocus", b.skills.combatFocus)

  setBox("RPBio_Partner", (b.relationships.partner and b.relationships.partner.character) or "")
  setBox("RPBio_PartnerNote", (b.relationships.partner and b.relationships.partner.note) or "")
  setMulti("RPBio_Family", (b.relationships.family and b.relationships.family[1]) or "")
  setMulti("RPBio_Allies", (b.relationships.allies and b.relationships.allies[1]) or "")
  setMulti("RPBio_Rivals", (b.relationships.rivals and b.relationships.rivals[1]) or "")
  setMulti("RPBio_Pets", (b.relationships.pets and b.relationships.pets[1]) or "")

  initDropdown("RPBio_AvailabilityDD", AVAILABILITY_OPTIONS, b.rpPrefs.availability)
  setBox("RPBio_Tone", table.concat(b.rpPrefs.tone or {}, ", "))
  setMulti("RPBio_Limits", b.rpPrefs.limits)
  setBox("RPBio_OOC", b.rpPrefs.oocContact)
  if g("RPBio_LimitsPrivate") then g("RPBio_LimitsPrivate"):SetChecked(b.rpPrefs.limitsPrivate and true or false) end

  setMulti("RPBio_PublicNotes", b.notes.public)
  setMulti("RPBio_PrivateNotes", b.notes.private)

  local multi = {
    "RPBio_ShortBio","RPBio_Backstory","RPBio_Deeds","RPBio_Hooks",
    "RPBio_Family","RPBio_Allies","RPBio_Rivals","RPBio_Pets",
    "RPBio_Limits","RPBio_PublicNotes","RPBio_PrivateNotes",
  }
  for _, base in ipairs(multi) do
    local eb = g(base.."EditBox")
    if eb then eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(GameFontHighlightSmall) end
  end
end

RPBioFrame:HookScript("OnShow", function()
  loadIntoFields()
  if _G.RPBio_AlignmentDD and not _G.RPBio_AlignmentDD.value then initDropdown("RPBio_AlignmentDD", ALIGNMENT_OPTIONS, nil) end
  if _G.RPBio_AvailabilityDD and not _G.RPBio_AvailabilityDD.value then initDropdown("RPBio_AvailabilityDD", AVAILABILITY_OPTIONS, nil) end
end)

function CharacterMemory_OpenCharacterSheet()
  if not _G.RPBioFrame then return end
  _G.RPBioFrame:Show()
  _G.RPBioFrame:Raise()
  _G.RPBioFrame:SetFrameStrata("DIALOG")
  _G.RPBioFrame:SetToplevel(true)
  loadIntoFields()
end


