local _, NS = ...

-- Debuffs this account has actually applied.
--
-- No API answers "which spells put a debuff on something". The spellbook says
-- what you know, the aura APIs say what is on a unit right now, and nothing
-- joins the two. The Cooldown Manager is Blizzard's own curated answer and is
-- the best cold start there is -- but it only holds what they chose to put in
-- the viewer for your current spec, so procs, trinkets, weapon enchants,
-- off-spec debuffs and anything new in a patch are simply absent.
--
-- Curated libraries exist (LibPlayerSpells-1.0 is the real one) and they lag
-- patches, because a human has to notice a talent tree changed. Shipping a
-- stale list is worse than shipping none: it is wrong with confidence.
--
-- So this records what has been SEEN on a unit with a HARMFUL|PLAYER filter --
-- the game's own answer to "did you put that there". It cannot be wrong about
-- the population it describes, and it maintains itself across patches, talents
-- and gear with nobody curating anything.
--
-- Not the combat log. COMBAT_LOG_EVENT_UNFILTERED cannot be registered by an
-- addon on this client -- the attempt is refused outright as a protected call
-- -- which is the same restriction that makes aura data secret in instances.
-- The aura scan in Spells.lua is already running on a 3s ticker for a
-- neighbouring purpose, already handles secrecy, and sees exactly the same
-- debuffs a moment later, so this hangs off that rather than asking the game
-- for something it will not give.
--
-- Account-wide, because a warlock's Agony is the same spell on your next
-- warlock and re-learning it per character is make-work. Filtered on display
-- by whether the current character actually knows it, so a paladin is never
-- offered Corruption.

local ipairs, pairs, type = ipairs, pairs, type

-- The store. Its own SavedVariable rather than a corner of the profile: this
-- is knowledge about your account, not a setting, and it must survive profile
-- switches, deletions and imports untouched.
PLATETWEAKS_SPELLS = PLATETWEAKS_SPELLS or {}

local known = {}   -- spellIDs already in the store, so a rescan is not a write
local primed

-- Refreshes fire several times a second on a dotted pull. Everything after the
-- first sighting is a no-op against this set rather than a table write and a
-- SavedVariables dirty flag.
local function Remember(spellID, name, spec)
  if known[spellID] then return false end
  known[spellID] = true

  local entry = PLATETWEAKS_SPELLS[spellID]
  if entry then
    -- Seen again on another character or another patch: refresh the parts that
    -- can change, keep the rest.
    entry.name = name or entry.name
    entry.spec = spec or entry.spec
    return false
  end

  PLATETWEAKS_SPELLS[spellID] = {
    name = name,
    class = select(2, UnitClass("player")),
    spec = spec,
    -- The date, so a list that has grown for two expansions can be pruned by
    -- something other than guesswork.
    seen = time and time() or 0,
  }
  return true
end

function NS.LearnedCount()
  local count = 0
  for _ in pairs(PLATETWEAKS_SPELLS) do count = count + 1 end
  return count
end

-- Does THIS character have it?
--
-- The store is account-wide; the picker is not. A spell counts as available
-- when the client says the player has it -- talents, spec swaps and the
-- override system all move through IsPlayerSpell -- and, failing that, when it
-- was recorded on this class, which covers auras whose ID is not the castable
-- spell's ID (most damage-over-time effects are their own aura).
local function Available(spellID, entry)
  local ok, isPlayers = pcall(IsPlayerSpell, spellID)
  if ok and isPlayers then return true end
  if IsSpellKnownOrOverridesKnown then
    local okKnown, isKnown = pcall(IsSpellKnownOrOverridesKnown, spellID)
    if okKnown and isKnown then return true end
  end
  return entry.class ~= nil and entry.class == select(2, UnitClass("player"))
end

-- What the picker should offer, newest first.
--
-- Sorted by name rather than by when it was learned: a list you scan for a
-- word you already know is a list in alphabetical order.
function NS.LearnedDebuffs()
  local out = {}
  for spellID, entry in pairs(PLATETWEAKS_SPELLS) do
    if Available(spellID, entry) then
      local name = (NS.SpellName and NS.SpellName(spellID)) or entry.name
      if name then
        out[#out + 1] = { spellID = spellID, name = name, learned = true }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- Recorded by hand, for a debuff someone typed an ID for. If it is good enough
-- to build a rule on, it is good enough to offer next time.
function NS.LearnSpell(spellID)
  if type(spellID) ~= "number" then return false end
  local name = NS.SpellName and NS.SpellName(spellID)
  return Remember(spellID, name, GetSpecialization and GetSpecialization() or nil)
end

function NS.ForgetSpell(spellID)
  PLATETWEAKS_SPELLS[spellID] = nil
  known[spellID] = nil
end

-- ---------------------------------------------------------------------------
-- The intake
--
-- Called by the aura scan in Spells.lua for every HARMFUL aura it sees under a
-- PLAYER filter. That scan runs on a slow ticker and only where auras are
-- readable, which is all this needs: a debuff you keep applying will be on
-- something within three seconds, and one you applied once is not what a
-- picker is for.
-- ---------------------------------------------------------------------------
function NS.NoteAppliedAura(spellID, name)
  if type(spellID) ~= "number" then return false end
  return Remember(spellID, name, GetSpecialization and GetSpecialization() or nil)
end

-- Seeds the in-memory set the first time anything asks. Called from the addon's
-- own load path rather than an event, since there is no event to hang it on
-- that this client will grant.
function NS.PrimeLearned()
  if primed then return end
  primed = true
  for spellID in pairs(PLATETWEAKS_SPELLS) do known[spellID] = true end
end
