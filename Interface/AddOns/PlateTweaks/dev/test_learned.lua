-- The learned-debuff store.
--
-- It writes to SavedVariables from the busiest event in the game, and it
-- decides what a picker offers -- so what matters is that it records only what
-- it should, writes only when something changed, and hands back only what the
-- character in front of it can actually cast.
local dir = ...

local NS = {}

-- Client stubs. Everything here is a plain value the file reads through pcall
-- or directly.
_G.UnitClass = function() return className, classToken end
_G.GetSpecialization = function() return specIndex end
_G.IsPlayerSpell = function(id) return playerSpells[id] and true or false end
_G.IsSpellKnownOrOverridesKnown = function(id) return overrides[id] and true or false end
_G.time = function() return 1700000000 end

className, classToken = "Warlock", "WARLOCK"
specIndex = 1
playerSpells, overrides = {}, {}

local chunk = assert(loadfile(dir .. "/Learned.lua"))
chunk("PlateTweaks", NS)

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(name, tostring(got), tostring(want)))
  else
    print("ok   " .. name)
  end
end

-- What Spells.lua's aura scan hands over: a HARMFUL aura seen under a PLAYER
-- filter. The scan does the filtering -- source, harmfulness, secrecy -- so
-- this file only decides what to keep and what to offer.
--
-- The combat log would have been the obvious source and this client refuses
-- to register it for an addon, which is what the aura scan replaces.
local function Seen(spellID, spellName)
  NS.NoteAppliedAura(spellID, spellName)
end

NS.PrimeLearned()

-- ---- what gets recorded -----------------------------------------------------
Seen(980, "Agony")
check("a debuff you applied is recorded", PLATETWEAKS_SPELLS[980] ~= nil, true)
check("with its name", PLATETWEAKS_SPELLS[980].name, "Agony")
check("and the class that cast it", PLATETWEAKS_SPELLS[980].class, "WARLOCK")

Seen(172, "Corruption")
check("so is the next one", PLATETWEAKS_SPELLS[172] ~= nil, true)

check("a nil id is refused", NS.NoteAppliedAura(nil, "nothing"), false)
check("and so is a secret-shaped one", NS.NoteAppliedAura("980", "Agony"), false)

-- ---- and what it does not rewrite -------------------------------------------
--
-- Refreshes fire several times a second on a dotted pull. Everything after the
-- first sighting has to be a comparison, not a write.
PLATETWEAKS_SPELLS[980].seen = 1
check("a second sighting reports no change", NS.NoteAppliedAura(980, "Agony"), false)
check("and does not rewrite the row", PLATETWEAKS_SPELLS[980].seen, 1)

-- ---- what the picker is offered ---------------------------------------------
playerSpells[980] = true
local list = NS.LearnedDebuffs()
local names = {}
for _, item in ipairs(list) do names[item.name] = true end
check("a spell this character knows is offered", names["Agony"], true)
check("and one recorded on this class is too", names["Corruption"], true)

-- A different class: the store is account-wide, the picker is not.
className, classToken = "Paladin", "PALADIN"
playerSpells = {}
overrides = {}
check("nothing from another class is offered", #NS.LearnedDebuffs(), 0)

-- Unless this character actually has it -- a talent, a spec swap, an override.
playerSpells[172] = true
check("except what this character genuinely has", #NS.LearnedDebuffs(), 1)

-- ---- by hand ----------------------------------------------------------------
className, classToken = "Warlock", "WARLOCK"
check("a typed ID can be remembered", NS.LearnSpell(30108), true)
check("and remembering it twice is not a change", NS.LearnSpell(30108), false)
check("it is in the store", PLATETWEAKS_SPELLS[30108] ~= nil, true)
check("a non-number is refused", NS.LearnSpell("nope"), false)

NS.ForgetSpell(30108)
check("forgetting removes it", PLATETWEAKS_SPELLS[30108], nil)
Seen(30108, "Unstable Affliction")
check("and it comes back the next time it is seen",
  PLATETWEAKS_SPELLS[30108] ~= nil, true)

-- Agony, Corruption, Unstable Affliction. The three that were refused --
-- someone else's cast, a buff, a damage event -- were never stored.
check("the account count counts what was stored", NS.LearnedCount(), 3)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
return failures
