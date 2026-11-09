-- Headless check of the threat matcher and the draw-slot accounting.
-- Stubs only what the two files touch at load time or in these paths.
local dir = ...

local NS = {}
local function stubframe()
  local f = {}
  setmetatable(f, { __index = function() return function() return f end end })
  return f
end

_G.CreateFrame = function() return stubframe() end
_G.GetTime = function() return 100 end
_G.UnitAffectingCombat = function() return playerInCombat end
_G.UnitThreatSituation = function(a, b) return threatValue end
_G.UnitIsUnit = function() return false end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return false end
_G.GetNumGroupMembers = function() return 0 end
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return specID end
_G.InCombatLockdown = function() return false end
_G.issecretvalue = nil
_G.PixelUtil = nil

local function loadfile_ns(path)
  local chunk = assert(loadfile(dir .. "/" .. path))
  chunk("PlateTweaks", NS)
end

loadfile_ns("Threat.lua")
loadfile_ns("Tints.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(name, tostring(got), tostring(want)))
  else
    print("ok   " .. name)
  end
end

NS.DefaultBorder = function()
  return { enabled = false, color = { r = 1, g = 0.85, b = 0.1, a = 1 }, thickness = 2 }
end
NS.db = { tints = { pandemic = { enabled = false }, missingMode = "displace",
  threat = { enabled = true, role = "auto", states = {} },
  threatBorder = { enabled = false, thickness = 2, grow = "OUT", states = {} } } }

-- ---- role ------------------------------------------------------------------
-- An unanswered question is not an answer of no. At login the client often has
-- no specialization yet, and caching that as "not a tank" is what put damage's
-- colours on a Protection Paladin's profile.
specID = nil
NS.RefreshThreatRole()
check("an unknown spec is not cached as an answer", NS.ThreatRoleKnown(), false)
specID = 66 -- protection paladin
check("asking again once the client knows gets the real answer", NS.PlayerIsTank(), true)
check("and it is cached from then on", NS.ThreatRoleKnown(), true)
check("prot paladin reads as a tank", NS.ThreatRole(), "tank")
check("a tank is told it is LOSING aggro, not nearing it",
  NS.ThreatStateLabel("near"), "Losing Aggro")

specID = 250 -- blood dk
NS.RefreshThreatRole()
check("tank spec detected", NS.PlayerIsTank(), true)
check("auto resolves to tank", NS.ThreatRole(), "tank")
check("having it, and not having it, read the same for everyone",
  NS.ThreatStateLabel("none"), "No Aggro")

specID = 253 -- beast mastery hunter
NS.RefreshThreatRole()
check("auto resolves to damage", NS.ThreatRole(), "dps")
check("and damage is told it is NEARING aggro",
  NS.ThreatStateLabel("near"), "Near Aggro")
check("for a damage spec too", NS.ThreatStateLabel("none"), "No Aggro")

NS.db.tints.threat.role = "tank"
check("a manual role overrides the spec", NS.ThreatRole(), "tank")
NS.db.tints.threat.role = "auto"

-- ---- shipped state seeding -------------------------------------------------
local cfg = NS.ThreatConfig()
check("there are three states", #NS.THREAT_STATES, 3)
check("damage: having aggro is on by default", cfg.states.aggro.enabled, true)
check("damage: being off it is off by default", cfg.states.none.enabled, false)
check("state key is stamped for the matcher", cfg.states.aggro.stateKey, "aggro")
check("only enabled states are handed to the engine",
  #NS.GetOrderedThreatRules(), 2)
check("no aggro ships switched off", cfg.states.none.enabled, false)
check("near aggro ships on", cfg.states.near.enabled, true)

-- A profile written by the four-state build must not keep entries nothing can
-- ever read again.
NS.db.tints.threat.states.secure = { enabled = true, color = {} }
NS.ThreatConfig()
check("retired four-state keys are dropped", NS.db.tints.threat.states.secure, nil)

-- The stored table is handed out, not a copy: a colour edited in the options
-- window has to reach the texture with no rebuild.
check("the engine gets the stored entry, not a copy",
  NS.GetOrderedThreatRules()[1], cfg.states.aggro)

-- ---- matching --------------------------------------------------------------
playerInCombat = true
check("aggro matches secure tanking (3)",
  NS.ThreatRuleMatches(cfg.states.aggro, "target", 3), true)
check("aggro matches insecure tanking (2)",
  NS.ThreatRuleMatches(cfg.states.aggro, "target", 2), true)
check("aggro ignores over-threat (1)",
  NS.ThreatRuleMatches(cfg.states.aggro, "target", 1), false)
check("near aggro takes over-threat (1)",
  NS.ThreatRuleMatches(cfg.states.near, "target", 1), true)
check("near aggro ignores the bottom of the list (0)",
  NS.ThreatRuleMatches(cfg.states.near, "target", 0), false)
check("a disabled state never matches",
  NS.ThreatRuleMatches(cfg.states.none, "target", 0), false)
cfg.states.none.enabled = true
check("no-aggro matches only the bottom of the list (0)",
  NS.ThreatRuleMatches(cfg.states.none, "target", 0), true)
check("no-aggro leaves over-threat to near aggro",
  NS.ThreatRuleMatches(cfg.states.none, "target", 1), false)
cfg.states.none.enabled = false
check("unreadable status matches nothing",
  NS.ThreatRuleMatches(cfg.states.aggro, "target", nil), false)

playerInCombat = false
check("out of combat is quiet",
  NS.ThreatRuleMatches(cfg.states.secure, "target", 3), false)
-- There is no opt-out any more, and a stored one from an older profile must
-- not resurrect the behaviour.
cfg.states.aggro.combatOnly = false
NS.ThreatConfig()
check("a stored combat-only opt-out is dropped", cfg.states.aggro.combatOnly, nil)
check("out of combat stays quiet regardless",
  NS.ThreatRuleMatches(cfg.states.aggro, "target", 3), false)
playerInCombat = true

-- ---- the border half --------------------------------------------------------
--
-- One row, one switch. The border half had an enable of its own, defaulting to
-- off, so its chips painted colours while everything that asked reported the
-- module off.
local border = NS.ThreatBorderConfig()
check("the border half has no switch of its own", border.enabled, nil)
check("it keeps its own colours", border.states.aggro ~= cfg.states.aggro, true)
check("and answers the same switch the bar half does",
  #NS.GetOrderedThreatBorders(), #NS.GetOrderedThreatRules())

NS.db.tints.threat.enabled = false
check("threat off takes the border half with it", #NS.GetOrderedThreatBorders(), 0)
NS.db.tints.threat.enabled = true

-- A profile written by the build that had two switches.
NS.db.tints.threatBorder.enabled = false
NS.ThreatBorderConfig()
check("a stored border switch is dropped", NS.db.tints.threatBorder.enabled, nil)
check("so the border half draws again", #NS.GetOrderedThreatBorders() > 0, true)

NS.db.tints.threat.enabled = false
check("switching threat off empties the list", #NS.GetOrderedThreatRules(), 0)
NS.db.tints.threat.enabled = true

-- ---- sublevel reservation --------------------------------------------------
local occ = { OVERLAY = {}, ARTWORK = {} }
local plan = NS.ThreatSublevelPlan(occ, 2, 0)
check("threat rank 1 sits just under the host ceiling", plan[1], -1)
check("threat rank 2 sits below rank 1", plan[2], -2)
check("reserved slots are marked taken", occ.OVERLAY[-1], true)

-- ---- slot accounting -------------------------------------------------------
NS.RuleCovers = function(a, b)
  -- b's conditions are a subset of a's
  local have = {}
  for _, c in ipairs(a.conditions or {}) do have[c.spellID] = true end
  for _, c in ipairs(b.conditions or {}) do
    if not have[c.spellID] then return false end
  end
  return #(b.conditions or {}) > 0
end
NS.CurrentAdapterName = function() return adapterName end
NS.ADAPTER_DEFAULTS = { Plater = { pinFlat = true }, Platynator = {} }
adapterName = "Plater"

local combo = { enabled = true, conditions = { { spellID = 1 }, { spellID = 2 } } }
local single = { enabled = true, conditions = { { spellID = 1 } } }
local ruleList = { combo, single }
NS.GetOrderedRules = function() return ruleList end

check("combo above a subset pays for an underlay",
  select(1, NS.RuleSlotCost(combo, ruleList, 1, false)), 2)
check("bottom rule pays for its tint only",
  select(1, NS.RuleSlotCost(single, ruleList, 2, false)), 1)
check("pandemic flash costs a single-debuff rule one more",
  select(1, NS.RuleSlotCost(single, ruleList, 2, true)), 2)
single.missingCover = true
check("cover missing health costs one more",
  select(1, NS.RuleSlotCost(single, ruleList, 2, false)), 2)
single.missingCover = nil
local borderOnly = { enabled = true, barEnabled = false, conditions = { { spellID = 9 } } }
check("border-only rule spends nothing",
  select(1, NS.RuleSlotCost(borderOnly, { borderOnly }, 1, true)), 0)

-- Two enabled threat states on top of the two spell rules.
local report = NS.SlotReport(nil)
check("threat states are charged to the same budget", report.used, 5)
check("threat state count is reported", report.threatRules, 2)
check("estimated budget is reported as flat", report.budget.flat, true)
check("estimate is flagged as unmeasured", report.budget.measured, false)

-- The border half is a separate list and must never reach the bar's pool.
report = NS.SlotReport(nil)
check("border threat states cost no draw slots", report.threatCost, 2)
check("total is unchanged by the border module", report.used, 5)

adapterName = "Platynator"
report = NS.SlotReport(nil)
check("an elevated addon is not costed in sublevels", report.budget.flat, false)
check("an elevated addon reports level headroom", report.total > 50, true)

-- ---- fill tiling ------------------------------------------------------------
--
-- One formula, used by the bar and by every swatch in the options window. What
-- matters is not that a 30px chip and a 150px bar repeat the same number of
-- times -- they cannot -- but that both answers come from here, so a chip can
-- never be drawn by arithmetic the plate does not use.
local stripes = { tileW = 400, tileH = 48, tileVertical = false }
local dots    = { tileW = 64,  tileH = 64, tileVertical = true }

local function coords(w, h, lib) return select(2, NS.FillTexCoords(w, h, lib)), select(4, NS.FillTexCoords(w, h, lib)) end

local barX, barY = coords(150, 14, stripes)
check("a stripe sheet never repeats less than once across a bar", barX, 1)
check("a horizontal banner is one span tall, whatever the bar height", barY, 1)

local wideX = select(2, NS.FillTexCoords(1200, 14, stripes))
check("a wide bar repeats the sheet", wideX, 3)

local dotX, dotY = coords(128, 64, dots)
check("a tiling texture repeats across", dotX, 2)
check("and down, when it says it tiles vertically", dotY, 1)

local thinY = select(4, NS.FillTexCoords(128, 12, dots))
check("a thin bar still gets a whole tile, not a sliver", thinY, 1)

local noneX, noneY = coords(150, 14, nil)
check("no library means no tiling at all", noneX, 1)
check("and no vertical tiling either", noneY, 1)

-- ---- re-seeding when the role finally resolves ------------------------------
--
-- A profile seeded before the client answered has the wrong role's colours on
-- it. Re-seeding fixes that, and must never touch a profile someone has edited.
NS.db.tints.threat = { enabled = true, role = "auto", states = {} }
specID = 253
NS.RefreshThreatRole()
local seeded = NS.ThreatConfig()
check("damage seeds Has Aggro on", seeded.states.aggro.enabled, true)

specID = 66
NS.RefreshThreatRole()
seeded = NS.ThreatConfig()
check("becoming a tank re-seeds the set", seeded.states.aggro.enabled, false)
check("a tank is alarmed by losing it instead", seeded.states.none.enabled, true)

seeded.states.aggro.enabled = true
NS.ThreatTouched(seeded)
specID = 253
NS.RefreshThreatRole()
seeded = NS.ThreatConfig()
check("a hand-edited profile is never re-seeded", seeded.states.aggro.enabled, true)

-- ---- flash on losing aggro --------------------------------------------------
--
-- A colour says what is true now; losing a mob is a thing that happened, and
-- by the time the plate has simply changed colour the moment a taunt was for
-- has passed.
local rig = {}
check("no flash when none is running", NS.ThreatFlashAlpha(rig, 100), 1)

rig.threatFlashUntil = 101.5
-- The beat alternates every quarter second, counted from the END of the flash
-- so the last blink always lands the same way whatever time it started.
check("a running flash is full on one beat", NS.ThreatFlashAlpha(rig, 100.3), 1)
check("and dim on the next", NS.ThreatFlashAlpha(rig, 100.6), 0.3)
check("and back again", NS.ThreatFlashAlpha(rig, 100.9), 1)
check("an expired flash leaves the colour alone", NS.ThreatFlashAlpha(rig, 102), 1)
check("so does one that ends exactly now", NS.ThreatFlashAlpha(rig, 101.5), 1)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
return failures
