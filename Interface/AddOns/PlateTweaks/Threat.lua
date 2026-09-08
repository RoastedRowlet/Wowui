local _, NS = ...

-- Threat rules. A colour chosen by the unit's threat state rather than by a
-- debuff, drawn ABOVE every spell rule on both the bar and the border.
--
-- Nothing here rides an aura button. A spell rule's tint is a texture on a
-- secure button precisely because aura state may not be read -- the button's
-- own visibility is the condition. Threat has no such problem:
-- UnitThreatSituation is a readable carve-out in instances (the same one
-- NS.UnitEngaged already leans on), so a threat rule is an ordinary texture on
-- an ordinary frame of ours, shown and hidden by a poll. That is also why it
-- can win against spell rules at all: our own frame takes a draw sublevel we
-- reserved before anything else was allocated, and Show/Hide on it is legal in
-- combat.
--
-- Priority is structural, not a comparison. Threat claims the top slots under
-- the host's ceiling before the missing ladder and the presence allocator ever
-- see the occupancy map, so a threat tint is above every spell rule for the
-- same reason ARTWORK spill is below them: position, decided once, at build.
--
-- "Respectfully" in the sense asked for: the spell rules below are still built
-- and still hold their own slots. A threat tint covers them while it is lit
-- and uncovers them the moment the state clears, with no rebuild and no rule
-- being dropped.

local pairs, ipairs, pcall, type = pairs, ipairs, pcall, type

local EMPTY = {}

-- Three states, and the client reports exactly one at a time -- so this is the
-- ceiling by construction, not a budget choice.
NS.MAX_THREAT_RULES = 3

-- How long a change-triggered rule stays lit after the transition that fired
-- it. Long enough to be seen across a pull, short enough not to sit on top of
-- the state rules it outranks.
local FLASH_SECONDS = 1.5

-- Three states.
--
-- The client reports four (0..3) and the first build exposed all four, which
-- was one distinction too many: "tanking securely" and "tanking, but only
-- just" are the same news on a nameplate you are reading at a glance. What
-- earns its own colour is the warning shot -- you are top of the list without
-- holding it yet -- because that is the one you can still act on.
--
--   aggro   status 2 or 3 -- it is on you
--   near    status 1      -- highest threat, not tanking it yet
--   none    status 0      -- someone else has it, comfortably
NS.THREAT_STATES = {
  { key = "aggro", statuses = { [2] = true, [3] = true } },
  { key = "near",  statuses = { [1] = true } },
  { key = "none",  statuses = { [0] = true } },
}

local STATUS_TO_KEY = {}
for _, state in ipairs(NS.THREAT_STATES) do
  for status in pairs(state.statuses) do STATUS_TO_KEY[status] = state.key end
end

-- Reading order, by role.
--
-- The list is the same three states; which one you look at first is not. For
-- everyone else the question is "have I pulled something", so Has Aggro leads.
-- For a tank it is the opposite -- losing a mob is the event, and holding one
-- is the resting state -- so No Aggro leads and Has Aggro is the one at the
-- bottom, switched off.
--
-- Order only. Nothing about matching, cost or storage reads this.
local TANK_ORDER = { "none", "near", "aggro" }

function NS.ThreatStatesOrdered()
  if NS.ThreatRole() ~= "tank" then return NS.THREAT_STATES end
  local out, byKey = {}, {}
  for _, state in ipairs(NS.THREAT_STATES) do byKey[state.key] = state end
  for _, key in ipairs(TANK_ORDER) do out[#out + 1] = byKey[key] end
  return out
end

-- Role. Threat means opposite things to a tank and to everyone else, so the
-- four states are labelled through a role rather than described in raw client
-- terms nobody should have to translate.
--
-- "auto" reads the player's own specialization, not a group role assignment:
-- assignment is frequently unset in a pug and always unset solo. The manual
-- settings exist for people who tank on an off-spec, or who want a healer's
-- reading while in a damage spec.
NS.THREAT_ROLES = {
  { key = "auto",   label = "Automatic (from your spec)" },
  { key = "tank",   label = "Tank" },
  { key = "dps",    label = "Damage" },
  { key = "healer", label = "Healer" },
}

-- One name per state, everywhere: the row in Edit, the chip tooltip on the
-- collapsed row, the slash-command report.
--
-- These were role-worded ("You lost it" for a tank, "Off it" for a damage
-- dealer), which made the same colour chip read differently depending on a
-- dropdown three lines up. The state is a fact about the mob -- it either has
-- you, nearly has you, or does not -- and the role only decides which of those
-- is worth colouring, which the shipped defaults already express.
NS.THREAT_LABELS = {
  aggro = "Has Aggro",
  near  = "Near Aggro",
  none  = "No Aggro",
}

-- One word differs for a tank, and it is the one that matters: status 1 is
-- "about to take it" for everyone else and "about to lose it" for the person
-- holding it. Same state, opposite news.
local TANK_LABELS = {
  aggro = "Has Aggro",
  near  = "Losing Aggro",
  none  = "No Aggro",
}

-- Shipped colours, per role. A tank is alarmed by losing a mob, everyone else
-- by drawing one -- and in both cases the safe state ships switched OFF:
-- colouring every plate in a pull green is noise, and it costs a draw slot
-- that a warning colour could have had.
NS.THREAT_DEFAULT_COLORS = {
  tank = {
    aggro = { enabled = false, color = { r = 0.25, g = 0.65, b = 0.35, a = 0.75 } },
    near  = { enabled = true,  color = { r = 0.95, g = 0.60, b = 0.15, a = 0.85 } },
    none  = { enabled = true,  color = { r = 0.85, g = 0.15, b = 0.15, a = 0.85 } },
  },
  dps = {
    aggro = { enabled = true,  color = { r = 0.85, g = 0.15, b = 0.15, a = 0.85 } },
    near  = { enabled = true,  color = { r = 0.95, g = 0.60, b = 0.15, a = 0.85 } },
    none  = { enabled = false, color = { r = 0.25, g = 0.65, b = 0.35, a = 0.75 } },
  },
}
NS.THREAT_DEFAULT_COLORS.healer = NS.THREAT_DEFAULT_COLORS.dps

local TANK_SPECS = {
  [250] = true, [66] = true, [104] = true, [268] = true, [581] = true, [73] = true,
}

-- Cached and refreshed on the spec-change event rather than asked per plate
-- per tick: GetSpecialization is cheap, but this is read at 4Hz times every
-- rigged plate and the answer changes about once an hour.
--
-- `known` is the important half. At ADDON_LOADED the client frequently has no
-- specialization yet, so the first ask returns nothing -- and caching that as
-- "not a tank" is how a Protection Paladin ends up reading as damage, with
-- damage's colours seeded onto their profile. An unanswered question is not an
-- answer of no: until the client says, the cache stays empty and the next
-- reader asks again.
local playerIsTank, roleKnown = false, false

function NS.RefreshThreatRole()
  local ok, index = pcall(GetSpecialization)
  if not ok or not index then return false end
  local okID, id = pcall(GetSpecializationInfo, index)
  if not okID or not id then return false end
  playerIsTank = TANK_SPECS[id] and true or false
  roleKnown = true
  return true
end

function NS.PlayerIsTank()
  if not roleKnown then NS.RefreshThreatRole() end
  return playerIsTank
end

function NS.ThreatRoleKnown() return roleKnown end

-- The role in force: the setting, or the spec when it is on "auto".
--
-- Healer and damage read threat identically -- neither should be holding a mob
-- -- so this collapses to two behaviours and three labels. Kept as three
-- because a healer reading "you pulled it off the tank" is being told about a
-- tank they are not.
function NS.ThreatRole()
  local setting = ((NS.db and NS.db.tints or EMPTY).threat or EMPTY).role or "auto"
  if setting ~= "auto" then return setting end
  -- Asks rather than reading a cache that may never have been filled.
  return NS.PlayerIsTank() and "tank" or "dps"
end

-- The role as a word for a person. "dps" is what the table calls it; nobody
-- says that in a sentence beginning "Role:".
local ROLE_NAMES = { tank = "Tank", dps = "Damage", healer = "Healer" }

function NS.ThreatRoleName()
  return ROLE_NAMES[NS.ThreatRole()] or "Damage"
end

function NS.ThreatStateLabel(key)
  if NS.ThreatRole() == "tank" then return TANK_LABELS[key] or key end
  return NS.THREAT_LABELS[key] or key
end

-- The unit's threat status, or nil when it cannot be read.
--
-- nil is NOT zero. Zero is a real answer meaning "you are on this mob's list
-- and last on it"; nil means the client refused, and a rule that treats those
-- the same lights every plate in the zone the moment the API goes quiet.
function NS.ThreatStatus(unit)
  if not unit then return nil end
  local ok, status = pcall(UnitThreatSituation, "player", unit)
  if not ok or status == nil then return nil end
  if issecretvalue and issecretvalue(status) then return nil end
  if type(status) ~= "number" then return nil end
  return status
end

-- Is anyone else in the group tanking this?
--
-- Walks the group, so it is opt-in per rule (the "other" preset) rather than
-- computed for every plate. Capped at the raid frame count the client gives
-- us, and every read is a pcall: one throw here would kill the poll ticker for
-- every rig at once.
function NS.OtherPlayerTanking(unit)
  if not unit then return false end
  local prefix, count
  if IsInRaid() then
    prefix, count = "raid", GetNumGroupMembers() or 0
  elseif IsInGroup() then
    prefix, count = "party", (GetNumGroupMembers() or 1) - 1
  else
    return false
  end
  for index = 1, count do
    local other = prefix .. index
    if not UnitIsUnit(other, "player") then
      local ok, status = pcall(UnitThreatSituation, other, unit)
      if ok and type(status) == "number"
        and not (issecretvalue and issecretvalue(status))
        and status >= 2 then
        return true
      end
    end
  end
  return false
end

-- Is this state's colour wanted on this unit right now?
--
-- One state is true at a time, so there is no ordering question between them:
-- the unit reports exactly one threat status and at most one entry matches it.
-- ALWAYS in combat, with no setting. Out of combat every plate reports the
-- same thing -- you are on nobody's threat table -- so the "not tanking"
-- colour would paint the whole screen and the others could never fire. The
-- option existed, defaulted to on, and the off position had no use case: it is
-- a switch whose only setting is the right one.
function NS.ThreatRuleMatches(rule, unit, status)
  if not rule or rule.enabled == false then return false end
  if not UnitAffectingCombat("player") then return false end
  if status == nil then return false end
  return STATUS_TO_KEY[status] == rule.stateKey
end

-- The four state entries, in the fixed order they are drawn and costed.
--
-- Bar and border are separate modules with separate entries, not two halves of
-- one: they live on different pages, they are switched on independently, and
-- they cost differently (a bar tint takes a draw slot, a border takes none).
-- Tying them together meant every border question had to be asked again inside
-- the bar's row, which is what made that row four columns wide.
--
-- These are the STORED tables, handed out as-is rather than copied: a colour
-- edited in the options window has to reach the texture without a rebuild, and
-- a fresh table each call would hand the engine a colour nobody can change.
--
-- `stateKey` is stamped on once so the matcher above needs nothing else.
local function EnsureStates(cfg, shipped)
  cfg.states = type(cfg.states) == "table" and cfg.states or {}
  local live = {}
  for _, state in ipairs(NS.THREAT_STATES) do
    local entry = cfg.states[state.key]
    if type(entry) ~= "table" then
      -- Seeded from the role's shipped set, so a profile that has never
      -- touched threat still reads correctly the first time it is switched on.
      local default = shipped[state.key]
      entry = {
        enabled = default.enabled,
        color = { r = default.color.r, g = default.color.g,
                  b = default.color.b, a = default.color.a },
      }
      cfg.states[state.key] = entry
    end
    entry.stateKey = state.key
    -- Dropped: threat is in-combat only now, and a stored value would keep
    -- overriding a decision the engine no longer asks about.
    entry.combatOnly = nil
    entry.barEnabled = nil
    live[state.key] = true
  end
  -- The four-state build wrote secure/insecure/over/low. Those keys can never
  -- be read again -- STATUS_TO_KEY no longer produces them -- so they are
  -- dropped rather than left in the profile for the next person to wonder
  -- which set is live. Their colours are not migrated: two states is not the
  -- top and bottom of four, and picking two of the old four would be guessing
  -- which pair someone meant.
  for key in pairs(cfg.states) do
    if not live[key] then cfg.states[key] = nil end
  end
  return cfg
end

-- Shipped colours are seeded per ROLE, and the role is often unknown the first
-- time this runs -- so a profile seeded before the client answered has damage's
-- set on a tank. Re-seeded once the role resolves, but only while nothing has
-- been changed by hand: `touched` is set the moment anyone edits a state, and
-- from then on the profile is theirs.
local function ReseedForRole(cfg, role, shipped)
  if cfg.touched then return end
  if cfg.seededRole == role then return end
  cfg.seededRole = role
  for _, state in ipairs(NS.THREAT_STATES) do
    local entry = cfg.states[state.key]
    local default = shipped[state.key]
    if entry and default then
      entry.enabled = default.enabled
      entry.color = { r = default.color.r, g = default.color.g,
                      b = default.color.b, a = default.color.a }
    end
  end
end

function NS.ThreatConfig()
  local tints = NS.db and NS.db.tints or EMPTY
  local cfg = tints.threat
  if type(cfg) ~= "table" then
    cfg = { enabled = true, role = "auto", states = {} }
    if NS.db then NS.db.tints.threat = cfg end
  end
  if NS.NormaliseLoad then cfg.load = NS.NormaliseLoad(cfg.load) end
  local role = NS.ThreatRole()
  local shipped = NS.THREAT_DEFAULT_COLORS[role] or NS.THREAT_DEFAULT_COLORS.dps
  EnsureStates(cfg, shipped)
  -- Only once the client has actually told us. Re-seeding against a guess is
  -- how the wrong colours got there in the first place.
  if NS.ThreatRoleKnown() then ReseedForRole(cfg, role, shipped) end
  return cfg
end

-- Marks the profile as hand-edited, so the role can never re-seed over it.
function NS.ThreatTouched(cfg)
  if cfg then cfg.touched = true end
end

-- The border half of threat: its own colours and its own thickness, and NO
-- enable of its own.
--
-- It had one, left from when it was a module on a page of its own, and it
-- defaulted to off -- so the chips in the threat row painted from their
-- per-state flags while everything that asked the module reported "off". One
-- row with one switch cannot have a second switch hidden behind it.
--
-- What draws a threat border is now the same thing that draws a threat tint:
-- threat is on, and that state is ticked for that half.
function NS.ThreatBorderConfig()
  local tints = NS.db and NS.db.tints or EMPTY
  local cfg = tints.threatBorder
  if type(cfg) ~= "table" then
    cfg = { states = {} }
    if NS.db then NS.db.tints.threatBorder = cfg end
  end
  -- Cleared rather than honoured: a stored false is the retired switch, and
  -- leaving it would keep half the row inert with nothing on screen saying so.
  cfg.enabled = nil
  cfg.thickness = cfg.thickness or 2
  cfg.grow = cfg.grow or "OUT"
  local role = NS.ThreatRole()
  return EnsureStates(cfg, NS.THREAT_DEFAULT_COLORS[role] or NS.THREAT_DEFAULT_COLORS.dps)
end

local function EnabledStates(cfg)
  local ordered = {}
  for _, state in ipairs(NS.THREAT_STATES) do
    local entry = cfg.states[state.key]
    if entry and entry.enabled ~= false then ordered[#ordered + 1] = entry end
  end
  return ordered
end

-- The page's own switch.
--
-- Health Coloring is one page carrying three stacks -- threat, target/focus
-- and the spell rules -- and its switch only ever silenced the third. Turning
-- the module off left threat and target colours on every plate, which is not
-- a state anyone asked for and not one the rail could explain.
local function HealthColoringOff()
  local tints = NS.db and NS.db.tints
  return tints and tints.enabled == false
end

function NS.GetOrderedThreatRules()
  local tints = NS.db and NS.db.tints or EMPTY
  if HealthColoringOff() then return EMPTY end
  if tints.threatEnabled == false then return EMPTY end
  local cfg = NS.ThreatConfig()
  if cfg.enabled == false then return EMPTY end
  -- Where threat is wanted. Solo there is nobody to lose a mob to, and in a
  -- delve the only other thing on your threat table is a brann, so "off
  -- outside group content" is a real profile rather than a preference.
  if NS.LoadAllows and not NS.LoadAllows(cfg.load) then return EMPTY end
  return EnabledStates(cfg)
end

function NS.GetOrderedThreatBorders()
  local tints = NS.db and NS.db.tints or EMPTY
  -- The border half too. It is free and it draws outside the bar, which is
  -- exactly why it kept showing after the module was switched off.
  if HealthColoringOff() then return EMPTY end
  if tints.threatEnabled == false then return EMPTY end
  -- The SAME switch the bar half answers to. There is one threat row and one
  -- control on it.
  if NS.ThreatConfig().enabled == false then return EMPTY end
  -- The same load conditions as the bar half: one row, one set of answers.
  if NS.LoadAllows and not NS.LoadAllows(NS.ThreatConfig().load) then return EMPTY end
  return EnabledStates(NS.ThreatBorderConfig())
end

-- Sublevels for threat, taken FIRST so everything else allocates around them.
--
-- Marks `occ` in place. Bar rules descend from just under the host ceiling;
-- border rules sit in our own band one above it, the same place a spell
-- rule's border goes, so a threat border replaces the plate outline rather
-- than drawing beside it.
function NS.ThreatSublevelPlan(occ, count, ceiling)
  local plan = {}
  if not count or count <= 0 then return plan end
  local top = ceiling and (ceiling - 1) or 4
  local sub = top
  for rank = 1, count do
    while sub >= -8 and occ.OVERLAY[sub] do sub = sub - 1 end
    if sub < -8 then break end
    occ.OVERLAY[sub] = true
    plan[rank] = sub
    sub = sub - 1
  end
  return plan
end

-- One holder frame per entry, one texture (bar) or four (border) on it. No
-- container, no mask, no aura group -- this is the cheapest thing the addon
-- draws, and the only one whose visibility we are allowed to change in combat.
--
-- Bar and border entries go into ONE list because the poll walks one list, but
-- they are built from two independent modules and neither knows about the
-- other. A state coloured on both gets two holders, and they light together
-- because they match the same status, not because they are linked.
local function ThreatHolder(rig, healthBar, entry, level)
  local holder = CreateFrame("Frame", nil, healthBar)
  holder:SetAllPoints(healthBar)
  pcall(holder.SetFrameLevel, holder, level)
  holder:Hide()
  entry.holder = holder
  entry.levelOffset = level - rig.baseLevel
  entry.lit = false
  entry.textures = 0
  table.insert(rig.threat.entries, entry)
  return holder
end

function NS.BuildThreat(rig, healthBar, barRules, borderRules, level, sublevels, borderTop)
  rig.threat = { entries = {}, failures = 0 }

  for rank, rule in ipairs(barRules or EMPTY) do
    local ok = pcall(function()
      local entry = { rule = rule, rank = rank, kind = "bar" }
      local holder = ThreatHolder(rig, healthBar, entry, level)
      local sublevel = (sublevels and sublevels[rank]) or (4 - rank)
      local wash = holder:CreateTexture(nil, "OVERLAY", nil, sublevel)
      NS.stats.textures = NS.stats.textures + 1
      NS.ApplyRuleFill(wash, healthBar, rule, 0)
      entry.wash = wash
      entry.sublevel = sublevel
      entry.textures = 1
    end)
    if not ok then rig.threat.failures = rig.threat.failures + 1 end
  end

  local cfg = NS.ThreatBorderConfig and NS.ThreatBorderConfig() or EMPTY
  for rank, rule in ipairs(borderRules or EMPTY) do
    local ok = pcall(function()
      local entry = { rule = rule, rank = rank, kind = "border" }
      local holder = ThreatHolder(rig, healthBar, entry, level)
      -- One above the host's border band, and one further up per rank so two
      -- lit borders cannot tie.
      local sublevel = math.min(7, (borderTop or 7) - (rank - 1))
      local bc = rule.color or { r = 1, g = 1, b = 1, a = 1 }
      local t = math.max(1, math.min(8, cfg.thickness or 2))
      local pad = math.max(0, math.min(12, cfg.padding or 0))
      local out = (cfg.grow == "IN") and -pad or (t + pad)
      local edges = {}
      for _, side in ipairs(NS.BORDER_SIDES) do
        local tex = holder:CreateTexture(nil, "OVERLAY", nil, sublevel)
        NS.stats.textures = NS.stats.textures + 1
        tex:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        tex:SetPoint(side.a, healthBar, side.a, side.ax * out, side.ay * out)
        tex:SetPoint(side.b, healthBar, side.b, side.bx * out, side.by * out)
        if side.vertical then tex:SetWidth(t) else tex:SetHeight(t) end
        table.insert(edges, tex)
      end
      entry.borders = edges
      entry.borderSublevel = sublevel
      entry.textures = #edges
    end)
    if not ok then rig.threat.failures = rig.threat.failures + 1 end
  end
end

-- Losing a mob is an EVENT, and a colour is a state.
--
-- The three states answer "what is true now". Dropping from holding a mob to
-- not holding it is a thing that HAPPENED, and by the time you notice the
-- plate has changed colour you have already missed the moment -- which is
-- exactly the moment a taunt is for. So the state that follows it can flash
-- for a second and a half rather than simply arriving.
--
-- Alpha, not a second texture: the colour is already correct, it only needs to
-- announce itself. Driven by the same 0.25s poll everything else here uses, so
-- it costs nothing when nobody has switched it on -- which is why the blink is
-- four steps a second rather than a smooth fade.
local FLASH_SECONDS = 1.5

function NS.ThreatFlashAlpha(rig, now)
  local until_ = rig and rig.threatFlashUntil
  if not until_ or now >= until_ then return 1 end
  -- Two frames of the poll on, two off. Anything faster reads as a flicker
  -- someone else's addon is causing.
  local elapsed = until_ - now
  return (math.floor(elapsed * 4) % 2 == 0) and 1 or 0.3
end

-- The poll. Called from the 0.25s ticker in Core.lua and from the threat
-- events, for bound rigs only.
--
-- At most one entry can match, since the unit reports one status, so this is a
-- straight walk rather than a first-match-wins search: every entry is asked,
-- and the one whose state is current lights.
function NS.UpdateThreat(rig)
  local threat = rig and rig.threat
  if not threat or #(threat.entries or EMPTY) == 0 then return end
  local unit = rig.unit
  if not unit then return end

  local status = NS.ThreatStatus(unit)
  local now = GetTime()

  -- Did this unit just come off you? Both sides have to be readable: an
  -- unreadable previous status is not "you had it", and treating it as one
  -- flashes every plate that comes back into range.
  local previous = rig.threatPrevious
  if NS.ThreatConfig().flashOnLoss and status ~= nil and previous ~= nil
    and previous >= 2 and status < 2 then
    rig.threatFlashUntil = now + FLASH_SECONDS
  end
  if status ~= nil then rig.threatPrevious = status end

  local alpha = NS.ThreatFlashAlpha(rig, now)
  for _, entry in ipairs(threat.entries) do
    local want = NS.ThreatRuleMatches(entry.rule, unit, status)
    if entry.lit ~= want then
      entry.lit = want
      pcall(entry.holder.SetShown, entry.holder, want)
    end
    -- Only the lit one, and only while a flash is running: SetAlpha on a
    -- hidden holder is work nobody sees.
    if want and entry.holderAlpha ~= alpha then
      entry.holderAlpha = alpha
      pcall(entry.holder.SetAlpha, entry.holder, alpha)
    end
  end
end

-- Is anything on this profile asking for the poll at all? Same gate shape as
-- AnyMissingCombatOnly in Core.lua -- with no threat rules the 4Hz walk across
-- every rig should not happen.
function NS.AnyThreatRules()
  return #NS.GetOrderedThreatRules() > 0 or #NS.GetOrderedThreatBorders() > 0
end

-- Summary line for the row and for /pt threat.
function NS.ThreatFlashOn()
  return NS.ThreatConfig().flashOnLoss and true or false
end

-- Cleared on unbind, alongside the tints. The holder is ours, so Hide is
-- always allowed; the stale `lit` must go with it, or the next unit on this
-- pooled bar starts from a flag describing the last one.
function NS.RetireThreat(rig)
  local threat = rig and rig.threat
  -- The history goes with the unit. This bar is pooled, so whatever it was
  -- last showing has nothing to do with the mob about to land on it -- and a
  -- stale "you had it" is a flash on a plate that changed nothing.
  rig.threatPrevious = nil
  rig.threatFlashUntil = nil
  for _, entry in ipairs((threat or EMPTY).entries or EMPTY) do
    entry.lit = false
    entry.holderAlpha = nil
    pcall(entry.holder.Hide, entry.holder)
    pcall(entry.holder.SetAlpha, entry.holder, 1)
  end
end
