local _, NS = ...

-------------------------------------------------------------------------------
-- Spell sources.
--
-- Blizzard's Cooldown Manager is the only trustworthy source of aura IDs:
-- its aura categories store the ID of the aura that actually lands, which is
-- often not the cast ID (Corruption casts as 172 but applies 146739). Reading
-- it is a query about the player's own spell setup, not aura state, so the
-- secrets system does not restrict it.
-------------------------------------------------------------------------------

-- Aura-bearing categories first: their spellID is the aura ID, and being seen
-- first lets them win the dedupe against cast IDs from Essential/Utility.
-- Categories whose entries describe an AURA: their spellID is the thing that
-- lands on the unit, so it is safe to offer as something to track.
local CDM_AURA_CATEGORIES = {
  "TrackedBuff",
  "TrackedBar",
  "SpecAgnosticTracked",
}

-- Categories whose entries describe an ABILITY you cast. These often have
-- hasAura set -- the ability does apply something -- but their spellID is the
-- CAST, not the aura, and a filter built from it can never match. Scanned for
-- linked IDs only, never offered directly.
local CDM_ABILITY_CATEGORIES = {
  "Essential",
  "SpecAgnosticEssential",
  "Utility",
  "EquipSlotTracked",
}

-- Both, for the places that just need every entry.
local CDM_CATEGORIES = {}
for _, name in ipairs(CDM_AURA_CATEGORIES) do table.insert(CDM_CATEGORIES, name) end
for _, name in ipairs(CDM_ABILITY_CATEGORIES) do table.insert(CDM_CATEGORIES, name) end

-------------------------------------------------------------------------------
-- Fonts, via LibSharedMedia — the standard registry, so anything another addon
-- has registered (ElvUI, WeakAuras, SharedMedia packs) appears here too, and
-- names stay valid even if file paths change.
-------------------------------------------------------------------------------

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
NS.LSM = LSM

local EXPRESSWAY = "Interface\\AddOns\\PlateTweaks\\media\\fonts\\Expressway.ttf"

-- Shipped with the addon rather than borrowed. Expressway was already the UI
-- font, but only ever resolved when EllesmereUI or Plater happened to be
-- loaded and had registered it -- otherwise every string silently fell back
-- to Friz Quadrata. Registering our own copy makes the addon standalone.
if LSM and not LSM:Fetch("font", "Expressway", true) then
  pcall(LSM.Register, LSM, "font", "Expressway", EXPRESSWAY)
end

local FALLBACK_FONTS = {
  ["Expressway"] = EXPRESSWAY,
  ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
  ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
  ["Skurri"] = "Fonts\\SKURRI.TTF",
  ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
}

function NS.FontList()
  if LSM then
    local names = LSM:List("font")
    if names and #names > 0 then return names end
  end
  local names = {}
  for name in pairs(FALLBACK_FONTS) do table.insert(names, name) end
  table.sort(names)
  return names
end

function NS.FontPath(name)
  if LSM then
    local path = LSM:Fetch("font", name, true)
    if path then return path end
  end
  return FALLBACK_FONTS[name] or "Fonts\\FRIZQT__.TTF"
end

-- Outline goes straight to SetFont; "NONE" means no outline. Falls back to a
-- stock font if the chosen one fails to load, so a bad entry can never leave
-- a FontString with no font at all (which renders as nothing).
function NS.ApplyFont(fontString, name, size, outline)
  if not fontString then return end
  local flags = (outline and outline ~= "NONE") and outline or ""
  local ok = pcall(fontString.SetFont, fontString, NS.FontPath(name), size or 12, flags)
  if not ok or not fontString:GetFont() then
    pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", size or 12, flags)
  end
end

function NS.SpellName(spellID)
  return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("Spell " .. tostring(spellID))
end

function NS.SpellIcon(spellID)
  return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or 134400
end

-- Menu/list label with the spell's icon inline.
function NS.SpellLabel(spellID, prefix)
  return ("%s|T%s:16:16:0:0:64:64:5:59:5:59|t %s |cff808080(%d)|r")
    :format(prefix or "", NS.SpellIcon(spellID), NS.SpellName(spellID), spellID)
end

-- Set of spell IDs the Cooldown Manager reports as auras this character puts
-- on other units. A condition naming anything else is suspect: cast IDs never
-- appear as auras, so a filter built from one cannot match what you expect.
function NS.GetTargetAuraSet()
  local set = {}
  local onTargets = NS.GetCooldownManagerSpells()
  for _, item in ipairs(onTargets) do
    set[item.spellID] = true
    -- Also every ID linked to it. A resolved rule stores the AURA's id
    -- (Moonfire's debuff, not the cast), which the Cooldown Manager does not
    -- list on its own — without this the marker flagged exactly the IDs that
    -- had just been corrected to the right ones.
    if NS.RelatedSpellIDs then
      for id in pairs(NS.RelatedSpellIDs(item.spellID)) do
        set[id] = true
      end
    end
  end
  return set
end

-- Can THIS character ever apply this aura?
--
-- Used to skip building containers for rules that belong to another character
-- in a shared profile -- a 3-debuff rule costs about a thousand textures per
-- nameplate whether or not you can cast any of it.
--
-- Answers false only on POSITIVE evidence of absence, and true on anything it
-- cannot check. The failure modes are not symmetrical: a wrong "false" quietly
-- disables a rule that works, which is the single worst thing this addon can
-- do, while a wrong "true" costs some textures.
function NS.CanApplyAura(spellID)
  if not spellID then return true end

  -- The Cooldown Manager's own list of what you apply to other units, already
  -- expanded through RelatedSpellIDs. Empty means it is unavailable rather
  -- than that you can apply nothing, so that case has to fall through.
  local applied = NS.GetTargetAuraSet and NS.GetTargetAuraSet()
  local haveList = false
  if applied then
    for _ in pairs(applied) do haveList = true break end
  end
  if haveList and applied[spellID] then return true end

  -- The spellbook, talents included -- an aura whose ID is also the cast ID
  -- (most DoTs) resolves here even when the Cooldown Manager does not list it.
  local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(spellID)) or {}
  ids[spellID] = true
  local checkedAny = false
  if IsPlayerSpell then
    for id in pairs(ids) do
      local ok, known = pcall(IsPlayerSpell, id)
      if ok then
        checkedAny = true
        if known then return true end
      end
    end
  end

  -- Nothing could be checked at all: no list, no working IsPlayerSpell. Not
  -- evidence of anything.
  if not haveList and not checkedAny then return true end
  return false
end

-- Two arrays of { spellID }: auras this character puts on other units (what
-- a HARMFUL|PLAYER filter can match), and everything else it knows about.
-- Auras the Cooldown Manager does not list, keyed by the ability that applies
-- them. Offered in the "add a debuff" dropdown only when the player actually
-- knows that ability, so a Druid entry never appears on a Warlock.
--
-- The ability is named rather than given an ID: the name is what we can look
-- up and confirm you know, and it keeps the table readable. The AURA is an ID
-- because that is the part which must be exact.
--
-- To add one: put the debuff on something, note the ID it really uses, and
-- add a row here.
NS.EXTRA_AURAS = {
  { ability = "Ursol's Vortex", aura = 127797 },
}

-- Entries from EXTRA_AURAS whose ability this character knows.
function NS.ExtraAuraSpells()
  local out = {}
  if not (C_Spell and C_Spell.GetSpellIDForSpellIdentifier and IsPlayerSpell) then
    return out
  end

  for _, entry in ipairs(NS.EXTRA_AURAS) do
    local okID, castID = pcall(C_Spell.GetSpellIDForSpellIdentifier, entry.ability)
    if okID and castID then
      local okKnown, known = pcall(IsPlayerSpell, castID)
      if okKnown and known then
        local name = NS.SpellName(entry.aura)
        if name then
          table.insert(out, { spellID = entry.aura, name = name })
        end
      end
    end
  end
  return out
end

function NS.GetCooldownManagerSpells()
  local onTargets, other = {}, {}
  if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
    return onTargets, other
  end

  -- Deduped by NAME as well as ID. A spell can appear under several IDs —
  -- Corruption is 146739 as an aura and 172 as a cast — and only the first,
  -- which comes from the aura-bearing categories listed above, is trackable.
  -- Keeping both would offer an ID that can never match.
  local seen, seenName = {}, {}
  local function Consider(spellID, isTargetAura)
    if not spellID or seen[spellID] then return end
    seen[spellID] = true

    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name then return end -- unresolvable IDs are never useful

    -- Rules filter HARMFUL|PLAYER, so a helpful aura can never match one.
    -- Unknown counts as harmful: IsSpellHarmful is not readable everywhere,
    -- and dropping a real debuff because we could not confirm it is worse
    -- than leaving one heal in the list.
    if isTargetAura and C_Spell and C_Spell.IsSpellHarmful then
      local okHarm, harmful = pcall(C_Spell.IsSpellHarmful, spellID)
      if okHarm and not (issecretvalue and issecretvalue(harmful)) and harmful == false then
        isTargetAura = false
      end
    end

    if isTargetAura then
      if seenName[name] then return end
      seenName[name] = true
      table.insert(onTargets, { spellID = spellID, name = name })
    else
      table.insert(other, { spellID = spellID, name = name })
    end
  end

  -- Aura categories first, so they win the name dedupe against any ability
  -- entry that happens to share a name.
  for _, source in ipairs({ CDM_AURA_CATEGORIES, CDM_ABILITY_CATEGORIES }) do
    local isAuraSource = (source == CDM_AURA_CATEGORIES)
    for _, categoryName in ipairs(source) do
      local category = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
      if category then
        local okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
        if okSet and cooldownIDs then
          for _, cooldownID in ipairs(cooldownIDs) do
            local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
            if okInfo and info then
              -- Offered only from an aura category. hasAura is true for plenty
              -- of ABILITIES too -- they apply something -- but their spellID
              -- is the cast, which no aura filter can ever match.
              Consider(info.overrideSpellID or info.spellID,
                isAuraSource and info.hasAura and not info.selfAura)
              if info.linkedSpellIDs then
                for _, linked in ipairs(info.linkedSpellIDs) do
                  Consider(linked, false) -- alternates: candidates, never primary
                end
              end
            end
          end
        end
      end
    end
  end

  -- Curated additions, after the Cooldown Manager so a real CDM entry always
  -- wins the dedupe.
  for _, extra in ipairs(NS.ExtraAuraSpells()) do
    if not seen[extra.spellID] and not seenName[extra.name] then
      seen[extra.spellID] = true
      seenName[extra.name] = true
      table.insert(onTargets, extra)
    end
  end

  local function ByName(a, b)
    return NS.SpellName(a.spellID) < NS.SpellName(b.spellID)
  end
  table.sort(onTargets, ByName)
  table.sort(other, ByName)
  return onTargets, other
end

-- Every spell ID that could plausibly BE the aura this ability applies.
--
-- The Cooldown Manager points at the ABILITY, not at its aura: Rend's entry
-- is 772 while the debuff that lands is 388539, and Rallying Cry is 97462
-- with its buff at 97463. There is no auraSpellID field to read -- when a
-- separate aura exists it appears in linkedSpellIDs, which this file used to
-- discard as "alternates, never primary". That is what made a rule entered
-- correctly from the dropdown unable to match anything.
--
-- Rather than guess which of them is the aura, hand the container ALL of
-- them. includeSpellIDs is a set, so a group listing the cast ID and its
-- linked IDs matches whichever the engine actually sees, and the guess
-- disappears from the problem entirely.
local relatedCache = {}

function NS.RelatedSpellIDs(spellID)
  if not spellID then return {} end
  local cached = relatedCache[spellID]
  if cached then return cached end

  local set = { [spellID] = true }

  if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
    for _, categoryName in ipairs(CDM_CATEGORIES) do
      local category = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[categoryName]
      if category then
        local okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
        for _, cooldownID in ipairs((okSet and cooldownIDs) or {}) do
          local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
          if okInfo and info then
            -- Match the entry by either ID it advertises, since a rule may
            -- hold whichever one the dropdown happened to offer.
            if info.spellID == spellID or info.overrideSpellID == spellID then
              if info.spellID then set[info.spellID] = true end
              if info.overrideSpellID then set[info.overrideSpellID] = true end
              for _, linked in ipairs(info.linkedSpellIDs or {}) do
                set[linked] = true
              end
            end
          end
        end
      end
    end
  end

  -- Anything ever observed under the same name. This is what covers abilities
  -- whose aura the Cooldown Manager does not link at all -- the case that had
  -- Moonfire picked from the dropdown never matching.
  local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
  local learned = name and NS.LearnedAuraID and NS.LearnedAuraID(name)
  if learned then set[learned] = true end

  -- Only cache once there is more to say than "the ID you gave me". A lone
  -- entry means nothing has been learned or linked YET, and caching that
  -- would freeze the wrong answer in for the rest of the session -- the aura
  -- may well be observed a minute from now.
  local count = 0
  for _ in pairs(set) do count = count + 1 end
  if count > 1 then relatedCache[spellID] = set end
  return set
end

-- Talents and spec change what the Cooldown Manager reports, so the mapping
-- is only valid for the current build of this character.
function NS.WipeRelatedCache()
  wipe(relatedCache)
end

-------------------------------------------------------------------------------
-- Turning what the user typed into the ID that actually lands.
--
-- Three things can be typed: the aura's own ID (already right), the ability's
-- ID (Rend's 772, which never matches because the debuff is 388539), or a
-- name. All three should end up at the aura.
--
-- Evidence is used in order of how much it proves:
--
--   1. An aura of that name is on the target RIGHT NOW. Definitive — it is
--      literally the thing the engine would have to match.
--   2. The Cooldown Manager links the typed ID to other spells. Strong, but
--      it cannot say which of them is the aura, so this only narrows.
--   3. Nothing. Keep what was typed; the container filter includes every
--      linked ID anyway, so a cast ID still has a good chance of working.
--
-- Never silently wrong: the caller gets a note explaining what happened.
-------------------------------------------------------------------------------

-- Name -> spellID for every harmful aura the player currently has on target.
-- Returns an empty table when there is no target or auras are sealed, which
-- makes every caller degrade to the weaker evidence automatically.
local function LiveTargetAuras()
  local byName = {}
  if not UnitExists("target") then return byName end
  if NS.IsRestricted and NS.IsRestricted() then return byName end
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return byName end

  for index = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", index, "HARMFUL|PLAYER")
    if not ok or not aura then break end
    if issecretvalue and (issecretvalue(aura.spellId) or issecretvalue(aura.name)) then
      return {}
    end
    byName[aura.name:lower()] = aura.spellId
  end
  return byName
end
NS.LiveTargetAuras = LiveTargetAuras

-- Returns spellID, note, resolved
--   spellID  the best ID we can justify, or nil if the input meant nothing
--   note     one line for the user about what was chosen and why
--   resolved true when the returned ID differs from what was typed
-- Abilities whose applied aura is named differently from the ability itself.
--
-- Most cast/aura mismatches share a name -- Rend casts 772 and applies 388539,
-- both called "Rend" -- so matching on the name resolves them. These do not:
-- Fury of Elune applies a debuff called "Atmospheric Exposure", and no amount
-- of name matching gets from one to the other.
--
-- Keys and values are both lowercase names. The value is looked up exactly as
-- if the user had typed it, so it still goes through the live-target and
-- learned-aura checks and still ends up at a real ID.
--
-- To add one: cast the ability, hover the debuff it puts on the target, and
-- add ["ability name"] = "debuff name".
NS.AURA_ALIASES = {
  ["fury of elune"] = "atmospheric exposure",
}

-- Follows the alias chain once. One hop only: an alias pointing at another
-- alias is a mistake in the table rather than something to support.
local function ResolveAlias(name)
  if not name then return nil end
  return NS.AURA_ALIASES[name:lower()]
end

function NS.ResolveAuraInput(text)
  text = strtrim(tostring(text or ""))
  if text == "" then return nil, "Type a spell ID or a spell name.", false end

  local live = LiveTargetAuras()
  local typed = tonumber(text)
  local spellID, viaName

  if typed then
    spellID = typed
  else
    -- A name. Prefer what is on the target, since that is the aura itself;
    -- the generic lookup returns whatever spell owns the name, which for
    -- Rend is the ability rather than its debuff.
    local key = text:lower()
    if live[key] then
      return live[key], ("|cff55dd55%s|r is on your target as |cff55dd55[%d]|r — using that.")
        :format(text, live[key]), true
    end
    -- Learned from any earlier sighting. This is the path that removes the
    -- need to have the aura up right now.
    local remembered = NS.LearnedAuraID and NS.LearnedAuraID(text)
    if remembered then
      return remembered, ("|cff55dd55%s|r -> |cff55dd55[%d]|r, the aura ID seen when you last cast it.")
        :format(text, remembered), true
    end
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
      local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, text)
      if ok and id then spellID = id; viaName = true end
    end
    -- Nothing found under the typed name. If it is a known alias, retry once
    -- under the debuff's real name.
    if not spellID then
      local alias = ResolveAlias(text)
      if alias then
        local aliasID = live[alias] or (NS.LearnedAuraID and NS.LearnedAuraID(alias))
        if not aliasID and C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
          local okA, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, alias)
          if okA then aliasID = id end
        end
        if aliasID then
          return aliasID, ("|cff55dd55%s|r applies |cff55dd55%s|r — using [%d].")
            :format(text, alias, aliasID), true
        end
      end
      return nil, ("|cffff4040No spell called '%s'.|r Try its ID, or put the debuff on a target first.")
        :format(text), false
    end
  end

  local name = NS.SpellName and NS.SpellName(spellID)
  if not name or name == "" then
    return nil, ("|cffff4040[%s] is not a spell on this client.|r"):format(tostring(spellID)), false
  end

  -- Definitive: an aura of this name is up, and its ID differs from what we
  -- have. That is the cast-vs-aura split, caught with proof rather than a
  -- guess.
  local liveID = live[name:lower()]
  if liveID and liveID ~= spellID then
    return liveID, ("|cffffcc00[%d] is %s's cast ID.|r The aura on your target is |cff55dd55[%d]|r — using that.")
      :format(spellID, name, liveID), true
  end
  if liveID then
    return spellID, ("|cff55dd55%s [%d]|r is on your target — confirmed correct."):format(name, spellID), false
  end

  -- No target, or the aura is not up. Fall back to what was learned earlier,
  -- which is the whole point of learning it: this is what makes picking
  -- Moonfire from the Cooldown Manager dropdown work with nothing targeted.
  local remembered = NS.LearnedAuraID and NS.LearnedAuraID(name)
  if remembered and remembered ~= spellID then
    return remembered, ("|cffffcc00[%d] is %s's cast ID.|r Its aura is |cff55dd55[%d]|r — using that.")
      :format(spellID, name, remembered), true
  end
  if remembered then
    return spellID, ("|cff55dd55%s [%d]|r matches the aura seen previously."):format(name, spellID), false
  end

  -- No live evidence. Say so rather than implying the ID was verified: the
  -- filter includes linked IDs, so it may well work, but nothing here proved it.
  local related = NS.RelatedSpellIDs and NS.RelatedSpellIDs(spellID) or {}
  local extras = 0
  for id in pairs(related) do if id ~= spellID then extras = extras + 1 end end

  -- Is this an ability the player casts? IsPlayerSpell covers the spellbook
  -- including talents, which is exactly the set that produces this mistake.
  local castable = false
  if IsPlayerSpell then
    local okKnown, known = pcall(IsPlayerSpell, spellID)
    castable = okKnown and known and true or false
  end

  local note
  if viaName then
    note = ("Added |cff55dd55%s [%d]|r by name."):format(name, spellID)
  else
    note = ("Added |cff55dd55%s [%d]|r."):format(name, spellID)
  end
  if extras > 0 then
    note = note .. (" Also matching %d linked ID(s)."):format(extras)
  end

  if castable then
    -- Stated plainly, and the rule is still added: the guess may be right,
    -- and refusing it would leave no way to enter an ID we cannot verify.
    note = note .. "\n|cffffcc00That is an ability you can cast, which is usually NOT the ID of the"
      .. " aura it applies.|r Put it on a target and use |cffffff00On target...|r to be sure."
  else
    note = note .. " |cff808080Target it with the debuff up to verify.|r"
  end
  return spellID, note, false
end

-------------------------------------------------------------------------------
-- Learned aura IDs.
--
-- Resolving a cast ID to the aura it applies needs ONE observation of that
-- aura, ever -- not one at the moment you happen to open the options window.
-- Requiring a live target mid-combat is exactly the wrong time to ask.
--
-- So: whenever auras are readable, quietly record name -> the ID that is
-- actually on a unit. Stored account-wide, because a spell name maps to the
-- same aura ID on every character that can cast it. By the time you type
-- "Moonfire", the answer was learned the first time you cast it.
--
-- This never reads anything secret: the scan is skipped entirely while auras
-- are sealed, and a secret value aborts it.
-------------------------------------------------------------------------------

local function LearnStore()
  BOONPLATES_SETTINGS = BOONPLATES_SETTINGS or {}
  BOONPLATES_SETTINGS.auraIDs = BOONPLATES_SETTINGS.auraIDs or {}
  return BOONPLATES_SETTINGS.auraIDs
end

-- Only auras the PLAYER applied are useful here: those are the ones a
-- HARMFUL|PLAYER or HELPFUL|PLAYER filter can ever match.
local LEARN_FILTERS = { "HARMFUL|PLAYER", "HELPFUL|PLAYER" }

local function LearnFromUnit(unit, store)
  if not UnitExists(unit) then return 0 end
  local learned = 0
  for _, filter in ipairs(LEARN_FILTERS) do
    for index = 1, 40 do
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
      if not ok or not aura then break end
      if issecretvalue and (issecretvalue(aura.spellId) or issecretvalue(aura.name)) then
        return learned
      end
      local key = aura.name and aura.name:lower()
      if key and store[key] ~= aura.spellId then
        store[key] = aura.spellId
        learned = learned + 1
      end
    end
  end
  return learned
end

-- Cheap and idempotent. Safe to call from a ticker, on opening the options
-- window, or by hand.
function NS.LearnAuras()
  if NS.IsRestricted and NS.IsRestricted() then return 0 end
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return 0 end

  local store = LearnStore()
  local learned = 0
  learned = learned + LearnFromUnit("player", store)
  learned = learned + LearnFromUnit("target", store)
  learned = learned + LearnFromUnit("focus", store)
  for index = 1, 10 do
    learned = learned + LearnFromUnit("nameplate" .. index, store)
  end
  return learned
end

function NS.LearnedAuraID(name)
  if not name then return nil end
  return LearnStore()[name:lower()]
end

-- Scanning costs a handful of API calls and only runs where auras are
-- readable, so a slow tick is enough to have seen everything you cast.
C_Timer.NewTicker(3.0, function()
  if not NS.db then return end
  pcall(NS.LearnAuras)
end)
