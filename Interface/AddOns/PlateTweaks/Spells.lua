local _, NS = ...

-- Spell sources.
--
-- The Cooldown Manager is the only trustworthy source of aura IDs: its aura
-- categories store the ID that actually lands, which is often not the cast ID
-- (Corruption casts as 172, applies 146739). Reading it is a query about the
-- player's own setup, not aura state, so secrets do not restrict it.

-- Aura-bearing categories first, so they win the dedupe against cast IDs.
local CDM_AURA_CATEGORIES = {
  "TrackedBuff",
  "TrackedBar",
  "SpecAgnosticTracked",
}

-- Categories describing an ABILITY you cast. Their spellID is the CAST, not
-- the aura, so a filter built from it can never match -- scanned for linked
-- IDs only, never offered directly.
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

-- Fonts via LibSharedMedia, so anything another addon registered appears here
-- and names stay valid if paths change.

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
NS.LSM = LSM

local EXPRESSWAY = "Interface\\AddOns\\PlateTweaks\\media\\fonts\\Expressway.ttf"

-- Shipped rather than borrowed: Expressway only resolved when EllesmereUI or
-- Plater happened to be loaded, otherwise everything fell back to Friz.
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
    -- Also every linked ID: a resolved rule stores the AURA's id, which the
    -- Cooldown Manager does not list -- without this the marker flagged
    -- exactly the IDs that had just been corrected.
    if NS.RelatedSpellIDs then
      for id in pairs(NS.RelatedSpellIDs(item.spellID)) do
        set[id] = true
      end
    end
  end
  return set
end

-- Direct proof this ID landed as a PLAYER aura on some unit, via NS.LearnAuras
-- below. Stronger than every heuristic in NS.CanApplyAura: a hero-talent
-- passive that applies a debuff without ever appearing as its own Cooldown
-- Manager entry or spellbook entry (Sentinel's Mark is one) is exactly what
-- the spellbook/CDM checks miss, and this catches it by direct observation
-- instead.
-- Per CHARACTER, not per account. PLATETWEAKS_SETTINGS.auraIDs stays a shared
-- name -> id map: knowing that "Agony" means 980 is a fact about the game,
-- useful on every character, and NS.LearnedAuraID depends on it.
--
-- But "have I seen this land" is a fact about ONE character, and reading it
-- out of the shared map made the known-spell gate useless. Measured: 25
-- minutes on Demonology running an Affliction profile still built 3 of the 4
-- rules on every plate -- 148 containers and 222 textures across 37 nameplates
-- for auras that spec cannot apply -- because Agony and Corruption sat in the
-- account-wide store from the Affliction character. One cast on any alt
-- defeated the gate for the entire account, permanently.
local function CharAuraStore(create)
  if not PLATETWEAKS_SETTINGS then return nil end
  local key = NS.CharacterKey and NS.CharacterKey()
  -- CharacterKey contains "?" while UnitName/GetRealmName are briefly
  -- unavailable at login; entries written under that would be stranded.
  if not key or key:find("?", 1, true) then return nil end
  local all = PLATETWEAKS_SETTINGS.charAuras
  if not all then
    if not create then return nil end
    all = {}
    PLATETWEAKS_SETTINGS.charAuras = all
  end
  local mine = all[key]
  if not mine and create then
    mine = {}
    all[key] = mine
  end
  return mine
end
NS.CharAuraStore = CharAuraStore

-- Per-character evidence FIRST, shared store second -- so this is a superset of
-- what it used to answer and can never say no where it previously said yes.
--
-- Reading only the per-character store was tried and reverted. It fixes the
-- CPU waste (see CharAuraStore above) but it is strictly more likely to refuse,
-- and refusing is the expensive direction: a wrong no silently kills a working
-- tint, a wrong yes costs some textures. The exposed case is an aura the
-- Cooldown Manager does not link and whose ID is not itself a player spell --
-- precisely the hero-talent case this function was written for -- on a
-- character not yet observed applying it.
--
-- The two properties cannot both come from this signal: "someone on this
-- account has applied it" and "this character can apply it" are the same
-- evidence at different scopes. Sharing it wastes CPU; splitting it drops
-- rules. The right discriminator for another spec's rules is the spec-bound
-- profile support that already exists, not a castability heuristic.
--
-- charAuras is still recorded, so a future version can act on it once there is
-- a safe way to. Nothing reads it for a negative decision today.
local function HasLearnedAura(spellID)
  if not spellID then return false end

  local mine = CharAuraStore(false)
  if mine and mine[spellID] then return true end

  local store = PLATETWEAKS_SETTINGS and PLATETWEAKS_SETTINGS.auraIDs
  if not store then return false end
  for _, id in pairs(store) do
    if id == spellID then return true end
  end
  return false
end

-- Can THIS character ever apply this aura? Used to skip building containers
-- for rules belonging to another character in a shared profile.
--
-- False only on positive evidence of absence, true on anything unchecked. The
-- failure modes are asymmetric: a wrong false quietly disables a working rule,
-- a wrong true costs some textures.
function NS.CanApplyAura(spellID)
  if not spellID then return true end

  -- Seen this land for real -- trust that over anything below.
  if HasLearnedAura(spellID) then return true end

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
      if HasLearnedAura(id) then return true end
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

-- Auras the Cooldown Manager does not list, keyed by the ability that applies
-- them. Offered in the dropdown only when the player knows that ability.
--
-- The ability is named because that is what we can confirm you know; the aura
-- is an ID because that part must be exact.
--
-- To add: put the debuff on something, note the ID it really uses, add a row.
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

  -- Deduped by NAME as well as ID: a spell can appear under several IDs, and
  -- only the first -- from the aura-bearing categories -- is trackable.
  local seen, seenName = {}, {}
  local function Consider(spellID, isTargetAura)
    if not spellID or seen[spellID] then return end
    seen[spellID] = true

    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name then return end -- unresolvable IDs are never useful

    -- Unknown counts as harmful: IsSpellHarmful is not readable everywhere,
    -- and dropping a real debuff is worse than leaving one heal in the list.
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
-- The Cooldown Manager points at the ABILITY: Rend's entry is 772 while the
-- debuff is 388539. There is no auraSpellID field -- a separate aura shows up
-- in linkedSpellIDs, which this file used to discard.
--
-- Rather than guess which is the aura, hand the container ALL of them.
-- includeSpellIDs is a set, so the engine matches whichever it actually sees.

-- Abilities whose applied aura the Cooldown Manager does NOT link, ID -> ID.
--
-- Last resort. Everything else here is discovered at runtime -- linkedSpellIDs,
-- and names observed landing on a real target. This covers only an ability
-- whose aura shares neither its name nor a CDM link, on a character that has
-- never applied it.
--
-- IDs, not names: NS.AURA_ALIASES is keyed on lowercase ENGLISH names and does
-- nothing on any other locale. Prefer adding here.
--
-- A wrong ID is worse than a missing one -- it matches nothing and looks like
-- the rule being broken. Verify in game: apply the ability, then check /pt bar
-- reports the rule matching.
NS.SPELL_APPLIES = {
  -- Voltaic Blaze (Stormbringer shaman) applies Flame Shock, which shares
  -- neither its name nor, on this build, a CDM link with it.
  [470057] = 188389,
}

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

  -- Hand-declared pairs, for the case none of the above can reach.
  local applies = NS.SPELL_APPLIES and NS.SPELL_APPLIES[spellID]
  if applies then set[applies] = true end

  -- Applied here as well as at input resolution: it used to run only when
  -- someone typed a name, so a rule already holding the ability's ID never
  -- benefited. Resolved through the learn store, so it lands on an observed ID.
  if name and NS.AURA_ALIASES then
    local aliasName = NS.AURA_ALIASES[name:lower()]
    local aliasID = aliasName and NS.LearnedAuraID and NS.LearnedAuraID(aliasName)
    if aliasID then set[aliasID] = true end
  end

  -- Only cache once there is more than "the ID you gave me" -- a lone entry
  -- means nothing has been learned yet, and caching that freezes the wrong
  -- answer for the session.
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

-- Turning what the user typed into the ID that actually lands.
--
-- Three things can be typed: the aura's ID (right already), the ability's ID
-- (772, which never matches), or a name. Evidence in order of what it proves:
--
--   1. An aura of that name is on the target now. Definitive.
--   2. The Cooldown Manager links the typed ID to others. Narrows only.
--   3. Nothing. Keep what was typed -- the filter includes every linked ID.
--
-- Never silently wrong: the caller gets a note explaining what happened.

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

-- Returns spellID, note, resolved.

-- Abilities whose applied aura is named differently from the ability.
--
-- Most mismatches share a name (Rend casts 772, applies 388539, both "Rend"),
-- so name matching resolves them. These do not: Fury of Elune applies
-- "Atmospheric Exposure".
--
-- Both sides are lowercase names, looked up as if typed, so it still goes
-- through the live-target and learned-aura checks.
--
-- To add: cast it, hover the debuff, add ["ability"] = "debuff".
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

-- Learned aura IDs.
--
-- Resolving a cast ID needs ONE observation of that aura, ever -- not one at
-- the moment you open the options window. So whenever auras are readable,
-- record name -> the ID actually on a unit. Account-wide, because a name maps
-- to the same ID on every character that can cast it.
--
-- Never reads anything secret: skipped while auras are sealed, and a secret
-- value aborts it.

local function LearnStore()
  -- PLATETWEAKS_SETTINGS, not BOONPLATES_SETTINGS: the latter is a leftover
  -- global from before the BoonPlates -> PlateTweaks rename and is not
  -- declared in the .toc's SavedVariables, so anything written there never
  -- survives a reload. Found while wiring HasLearnedAura into CanApplyAura.
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  PLATETWEAKS_SETTINGS.auraIDs = PLATETWEAKS_SETTINGS.auraIDs or {}
  return PLATETWEAKS_SETTINGS.auraIDs
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

      -- The same sighting, recorded against THIS character. The shared map
      -- above answers "what ID does this name use"; this answers "have I,
      -- personally, applied it" -- the only one of the two that the
      -- known-spell gate may act on.
      local mine = CharAuraStore(true)
      if mine and aura.spellId and not mine[aura.spellId] then
        mine[aura.spellId] = true
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
