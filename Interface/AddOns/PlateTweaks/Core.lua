local _, NS = ...

-- PlateTweaks: nameplate coloring driven by your own debuffs.
--
-- Nothing here reads aura state -- 12.x secrets forbid it. Secure aura
-- containers evaluate the conditions and hand back visibility; we only build
-- and place frames. See Tints.lua for the gate mechanics.

NS.Defaults = {
  -- Optional Tweaks: unrelated conveniences, each off until asked for. Kept in
  -- their own table so nothing here can be mistaken for a nameplate setting.
  tweaks = {
    tooltipIDs = false,
    tooltipItem = true,
    tooltipSpell = true,
    tooltipAura = true,
    tooltipUnit = true,
  },
  icons = {
  -- Off by default: most nameplate addons already draw aura icons.
    enabled = false,
    list = {}, -- ordered; index 1 = leftmost/highest priority
    size = 24,
    spacing = 2,
    -- Any of the nine standard anchor points on the health bar.
    anchor = "TOP",
    grow = "RIGHT",   -- RIGHT | CENTER | LEFT
    padX = 0,         -- both may be negative
    padY = 4,
    maxPerRow = 6,
    -- Hide the default plate's own aura row, so ours is not a second one.
    hideBlizzardAuras = false,
    borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    -- Swirl and countdown numbers are separate: one checkbox for both meant
    -- you could not have a sweep without digits, or the reverse.
    showSwirl = true,
    showTimer = true,
    timerFont = "Expressway",
    timerSize = 12,
    timerOutline = "OUTLINE",
    timerAnchor = "CENTER",
    timerX = 0,
    timerY = 0,
  -- Preview only -- live countdown digits are Blizzard's own cooldown text.
    timerPrecision = 1,
    showCount = true,
    countFont = "Expressway",
    countSize = 10,
    countOutline = "OUTLINE",
    countAnchor = "BOTTOMRIGHT",
    countX = 0,
    countY = 0,
  },
  -- Missing Debuffs: an icon that displaces off the plate while the debuff is
  -- present, as opposed to the bar wash in Tints.lua. The two coexist.
  missingIcons = {
    enabled = false,
    list = {}, -- ordered; { spellID, enabled, useIcon, color, missingCombatOnly }
    size = 24,
    spacing = 2,
    anchor = "RIGHT",
    grow = "RIGHT",   -- RIGHT | LEFT
    padX = 3,
    padY = 0,
  -- Collapse entries toward the anchor as they resolve. Capped by PACK_MAX in
  -- MissingIcons.lua; past that, tracking continues without the collapse.
    collapse = true,
    borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
  },
  --   { color = {...}, conditions = { {spellID = n} }, enabled = true }
  -- Singles and combos are the same thing at different lengths.
  tints = {
    enabled = true,        -- health (bar) colouring
    borderEnabled = true,  -- border colouring
    rules = {},       -- bar rules; ordered, index 1 wins overlaps
    borderRules = {}, -- border rules; their OWN independent priority stack
    -- Adjustment either side of a one-pixel inset, not an absolute inset --
    -- one pixel in is what looks right, so it is the zero point.
    edgeAdjust = 0,
  -- Pandemic flash via AuraButton:AddPandemicRegion -- the engine owns the
  -- region's visibility. One extra texture per combination, so opt-in.
    pandemic = {
      enabled = false,
      color = { r = 1, g = 1, b = 1, a = 0.45 },
      pulse = true,        -- animate, rather than a steady wash
      pulseSpeed = 0.35,   -- seconds per half-cycle; lower is faster
    },
  -- Every matching rule draws, so translucent tints would blend into a muddy
  -- third colour. With this on, each rule paints an opaque replica beneath
  -- its own tint.
    exclusive = true,
  -- Shared by every rule's "Cover missing health". Deliberately not derived
  -- from the bar's fill, so the missing side reads as missing.
    missingCoverColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 },
    -- What a missing rule's cover paints once its debuff lands. Off is a live
    -- replica of the bar; on is a flat colour by tier, which costs whatever
    -- the bar was encoding (usually threat). Occlusion mode only.
    missingAppliedByClass = false,
    -- EllesmereUI's own nameplate defaults, so the applied state matches the
    -- plates rather than adding a second palette:
    --
    --   boss / miniboss  0.518 0.243 0.984   (one purple for both)
    --   caster           0.231 0.510 0.965
    --   enemyInCombat    0.800 0.137 0.137   (their catch-all)
    --
    -- Alpha 1 is structural, not taste: a cover must be opaque or the wash
    -- shows through and the rule reads as unsatisfied.
    missingAppliedClassColors = {
      boss       = { r = 0.518, g = 0.243, b = 0.984, a = 1 },
      lieutenant = { r = 0.518, g = 0.243, b = 0.984, a = 1 },
      caster     = { r = 0.231, g = 0.510, b = 0.965, a = 1 },
      -- Ellesmere has no rare/elite mob-type colour -- both fall to their
      -- enemy colour -- so these match it rather than inventing two shades.
      rare       = { r = 0.800, g = 0.137, b = 0.137, a = 1 },
      elite      = { r = 0.800, g = 0.137, b = 0.137, a = 1 },
      normal     = { r = 0.800, g = 0.137, b = 0.137, a = 1 },
    },
    -- How a missing wash is hidden once the debuff lands.
    --
    --   "occlude"   cover it with an opaque replica of the bar. One slot per
    --               rule, but the replica needs a poll, and because two covers
    --               would blank each other the rules form a ladder.
    --   "displace"  (default) the wash rides a mask shoved off screen. No
    --               replica, no poll, no ladder, per-rule combat gating.
    --               Costs a ten-button pool per rule.
    --
    -- Displace is default despite the cost: occlusion repaints the whole bar,
    -- so threat, mob-tier colours and execute range are gone for as long as
    -- the debuff is up. It is also the only mode that can express a missing
    -- border rule.
    missingMode = "displace",
  -- How many times a rig built during combat lockdown (and therefore
  -- suspected structurally incomplete) may be discarded and rebuilt once
  -- combat allows it. Each attempt that still lands mid-lockdown leaks the
  -- old container set, since secure frames cannot be destroyed -- see
  -- RigIsSound/OnPlateAdded in this file. 1 is the original, conservative
  -- behavior; raising it trades a small bounded frame cost for a better
  -- chance of recovering plates added during a long fight.
    maxRigRepairs = 1,
  },
  levelOffset = 1,
}

-- 75% rather than opaque. EllesmereUI's hash line, highlights and absorb
-- divider all live inside the bar, and our texture is always above them.
local function DefaultColor()
  return { r = 1, g = 0.35, b = 0.75, a = 0.75 }
end
NS.DefaultColor = DefaultColor

-- A rule's border half. Off by default so existing rules and new ones behave
-- exactly as before until someone asks for a border.
function NS.DefaultBorder()
  return {
    enabled = false,
    color = { r = 1, g = 0.85, b = 0.1, a = 1 },
    thickness = 2,
  -- Outside by default: an inside border eats the bar and fights whatever the
  -- host draws at that edge.
    grow = "OUT",
    padding = 0,      -- gap between the bar edge and the border
  }
end

  -- Rules predate the border feature and the bar-enable flag, so every read
  -- path has to tolerate their absence.
function NS.NormaliseRule(rule)
  if not rule then return end
  if rule.barEnabled == nil then rule.barEnabled = true end
  rule.color = rule.color or DefaultColor()
  if not rule.border then rule.border = NS.DefaultBorder() end
  -- Whether the rule may paint your own target/focus plate -- e.g. so a tint
  -- does not fight the game's target glow.
  if rule.showOnTarget == nil then rule.showOnTarget = true end
  if rule.showOnFocus == nil then rule.showOnFocus = true end
  -- "texture" copies the host bar's own art and tints it via vertex colour, so
  -- whatever pattern the nameplate addon draws survives underneath.
  rule.fillStyle = rule.fillStyle or "solid"
  -- Opaque cover over the unfilled side, a live replica of the bar's art. Off
  -- by default -- most host bars already draw something opaque there.
  if rule.missingCover == nil then rule.missingCover = false end
  -- Inverts the rule: wash while the debuff is ABSENT. Same condition, colour
  -- and priority field, so everything reading a rule keeps working.
  if rule.showWhenMissing == nil then rule.showWhenMissing = false end
  -- Single-debuff by construction. Only catches data predating the feature,
  -- and drops the flag rather than a debuff someone chose.
  if rule.showWhenMissing
    and #(rule.conditions or {}) > (NS.MAX_MISSING_CONDITIONS or 1) then
    rule.showWhenMissing = false
  end
  -- Holds the wash off while the target is out of combat. Off by default --
  -- some missing rules are exactly for a pre-pull buff check.
  if rule.missingCombatOnly == nil then rule.missingCombatOnly = false end
  return rule
end

  -- A border rule is the same shape with the halves swapped, so RuleSummary,
  -- SortRules and RuleCovers work on either list.
function NS.NormaliseBorderRule(rule)
  if not rule then return end
  rule.barEnabled = false
  rule.border = rule.border or NS.DefaultBorder()
  rule.border.enabled = true
  -- Never leave grow unset, or the engine and the dropdown pick different
  -- fallbacks and the rule draws one way and reports another.
  rule.border.grow = rule.border.grow or "OUT"
  rule.color = rule.color or DefaultColor()
  if rule.showOnTarget == nil then rule.showOnTarget = true end
  if rule.showOnFocus == nil then rule.showOnFocus = true end
  -- Same inversion and single-debuff constraint as a bar rule.
  --
  -- A missing BORDER exists only under displacement. The flag is still stored
  -- and edited in occlusion mode; BuildTints drops it and /pt status reports
  -- how many, rather than silently rewriting a choice.
  if rule.showWhenMissing == nil then rule.showWhenMissing = false end
  if rule.showWhenMissing
    and #(rule.conditions or {}) > (NS.MAX_MISSING_CONDITIONS or 1) then
    rule.showWhenMissing = false
  end
  if rule.missingCombatOnly == nil then rule.missingCombatOnly = false end
  return rule
end

function NS.NewBorderRule()
  return NS.NormaliseBorderRule({ conditions = {}, enabled = true })
end


-- Per-character profiles: rules are built from specific spell IDs, so one
-- shared config is wrong the moment you log into another class. Optionally per
-- spec too.
function NS.CharacterKey()
  local name = UnitName("player") or "?"
  local realm = GetRealmName() or "?"
  return name .. " - " .. realm
end

  -- nil during login before spec data arrives, and never treated as a spec.
function NS.SpecName()
  local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
    or GetSpecializationInfo
  if not (getIndex and getInfo) then return nil end

  local okIndex, index = pcall(getIndex)
  if not okIndex or not index then return nil end
  local okInfo, _, name = pcall(getInfo, index)
  if not okInfo or type(name) ~= "string" or name == "" then return nil end
  return name
end

  -- ID not name: names are localised and several classes share "Restoration".
function NS.SpecID()
  local getIndex = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
    or GetSpecializationInfo
  if not (getIndex and getInfo) then return nil end

  local okIndex, index = pcall(getIndex)
  if not okIndex or not index then return nil end
  local okInfo, id = pcall(getInfo, index)
  if not okInfo or type(id) ~= "number" then return nil end
  return id
end

-- Profiles: named, account-wide, shared. A character points AT a profile
-- rather than owning one, so two can share a setup and one can keep a
-- different setup per spec.
--
--   PLATETWEAKS_PROFILES[name]        = the settings
--   PLATETWEAKS_SETTINGS.assign[char] = { default = name, specs = { [id] = name } }
--
-- Resolution: this spec's binding, else this character's default, else
-- "Default".

local DEFAULT_PROFILE = "Default"
NS.DEFAULT_PROFILE = DEFAULT_PROFILE

local function Assignments()
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  PLATETWEAKS_SETTINGS.assign = PLATETWEAKS_SETTINGS.assign or {}
  local key = NS.CharacterKey()
  local entry = PLATETWEAKS_SETTINGS.assign[key]
  if not entry then
    entry = { specs = {} }
    PLATETWEAKS_SETTINGS.assign[key] = entry
  end
  entry.specs = entry.specs or {}
  return entry
end

-- One-time move from the old per-character keys: those keys become profile
-- names, and the character is assigned to whichever it was using.
local function MigrateProfiles()
  PLATETWEAKS_PROFILES = PLATETWEAKS_PROFILES or {}
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}

  if PLATETWEAKS_SETTINGS.profilesMigrated then return end
  PLATETWEAKS_SETTINGS.profilesMigrated = true

  -- A character with no assignment yet adopts a profile named after it, if
  -- one exists; otherwise ProfileKey falls through to "Default".
  local charKey = NS.CharacterKey()
  local assign = Assignments()
  if PLATETWEAKS_PROFILES[charKey] and not assign.default then
    assign.default = charKey
  end
end

-- One-time: retire whatever is in "Default" and leave a clean one behind.
--
-- Default was the fall-through for everyone, so it accumulated one
-- character's rules and handed them to the next. Renamed rather than cleared,
-- with every assignment repointed -- nobody's plates change.
--
-- Includes assignments with no .default: those resolve to Default by
-- fallback, so leaving them alone is exactly how a character loses
-- everything.
local function RetireLegacyDefault()
  PLATETWEAKS_PROFILES = PLATETWEAKS_PROFILES or {}
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  if PLATETWEAKS_SETTINGS.defaultRetired then return end

  local existing = PLATETWEAKS_PROFILES[DEFAULT_PROFILE]
  -- No Default, or one nobody ever touched: nothing worth preserving, and a
  -- pointless "Default (Old)" would just be clutter.
  if not existing or next(existing) == nil then
    PLATETWEAKS_SETTINGS.defaultRetired = true
    return
  end

  local retired = DEFAULT_PROFILE .. " (Old)"
  local suffix = 2
  while PLATETWEAKS_PROFILES[retired] do
    retired = ("%s (Old %d)"):format(DEFAULT_PROFILE, suffix)
    suffix = suffix + 1
  end

  PLATETWEAKS_PROFILES[retired] = existing
  PLATETWEAKS_PROFILES[DEFAULT_PROFILE] = {}

  for _, entry in pairs(PLATETWEAKS_SETTINGS.assign or {}) do
    if entry.default == nil or entry.default == DEFAULT_PROFILE then
      entry.default = retired
    end
    for specID, name in pairs(entry.specs or {}) do
      if name == DEFAULT_PROFILE then
        entry.specs[specID] = retired
      end
    end
  end

  PLATETWEAKS_SETTINGS.defaultRetired = true
  -- Printed once, from PLAYER_ENTERING_WORLD rather than here: this runs
  -- during ADDON_LOADED, where the chat frame is not reliably ready.
  NS.pendingProfileNotice = retired
end

-- A character seen for the first time gets its own profile rather than
-- silently sharing Default with every other character.
--
-- "First time" is strict: NO assignment entry at all. An entry with no
-- .default is an EXISTING character running on Default, and handing that one a
-- fresh profile reads as losing every setting. Assignments() creates an entry
-- as a side effect, so this must check first.
--
-- Deliberately empty, not seeded from Default -- InitializeConfig merges
-- NS.Defaults over it, so a new character lands where a new install does.
local function EnsureCharacterProfile()
  PLATETWEAKS_PROFILES = PLATETWEAKS_PROFILES or {}
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  PLATETWEAKS_SETTINGS.assign = PLATETWEAKS_SETTINGS.assign or {}

  local charKey = NS.CharacterKey()
  -- Either half can be briefly unavailable at login, and CharacterKey
  -- substitutes "?", which would mint a junk profile name that persists.
  if not charKey or charKey:find("%?") then return end

  -- Two cases get a profile: never seen (no entry), and an entry pointing at
  -- nothing.
  --
  -- The second is only safe after RetireLegacyDefault, which is what makes a
  -- nil .default unambiguous. Before it, nil meant "fall through to Default"
  -- and could be a real setup; after, every pre-existing entry has an explicit
  -- name, so nil can only mean the profile was deleted.
  local entry = PLATETWEAKS_SETTINGS.assign[charKey]
  if entry then
    local orphaned = PLATETWEAKS_SETTINGS.defaultRetired and entry.default == nil
    if not orphaned then return end
  end

  if not PLATETWEAKS_PROFILES[charKey] then
    PLATETWEAKS_PROFILES[charKey] = {}
  end
  PLATETWEAKS_SETTINGS.assign[charKey] = { default = charKey, specs = {} }
end

function NS.ProfileExists(name)
  return name ~= nil and PLATETWEAKS_PROFILES ~= nil and PLATETWEAKS_PROFILES[name] ~= nil
end

-- Which profile this character+spec should be using right now.
function NS.ProfileKey()
  MigrateProfiles()
  -- Before EnsureCharacterProfile: that one decides what a brand new
  -- character gets, and this one decides what "Default" contains.
  RetireLegacyDefault()
  -- Before Assignments(), which would create the very entry this tests for.
  EnsureCharacterProfile()
  local assign = Assignments()

  -- Spec first: a binding is the more specific intent. A nil specID falls
  -- through rather than inventing a key.
  local specID = NS.SpecID()
  if specID and assign.specs[specID] and NS.ProfileExists(assign.specs[specID]) then
    return assign.specs[specID]
  end
  if assign.default and NS.ProfileExists(assign.default) then
    return assign.default
  end
  return DEFAULT_PROFILE
end

-- True when the CURRENT spec has its own binding, i.e. the "use this profile
-- for <spec>" box should be ticked.
function NS.IsSpecBound()
  local specID = NS.SpecID()
  if not specID then return false end
  return Assignments().specs[specID] ~= nil
end

local function ResolveProfile()
  MigrateProfiles()
  local key = NS.ProfileKey()
  -- A fresh install starts blank rather than seeded. Rules name specific
  -- spell IDs, so inherited ones would mostly be rules that can never fire.
  if not PLATETWEAKS_PROFILES[key] then
    PLATETWEAKS_PROFILES[key] = {}
  end
  return PLATETWEAKS_PROFILES[key]
end

  -- The key can change without a reload -- a spec swap, or spec data arriving
  -- late. Rebuilds only when it actually moved.
local activeKey = nil

function NS.RefreshProfile(reason)
  local key = NS.ProfileKey()
  if key == activeKey then return false end

  activeKey = key
  NS.InitializeConfig()

  -- Different rules mean different aura groups, and groups cannot be edited
  -- after creation — so this is a full rebuild, not a recolour.
  if not NS.RebuildAllRigs() then
  elseif NS.Reapply then
    NS.Reapply("profile change")
  end

  if NS.Options_RebuildAll then pcall(NS.Options_RebuildAll) end
  return true
end

  -- Every path that changes the live profile ends here. Forces a re-resolve
  -- even when the name is unchanged, since the contents may have been replaced.
local function SwitchTo(reason)
  activeKey = nil
  NS.RefreshProfile(reason)
end

function NS.ListProfiles()
  MigrateProfiles()
  local names = {}
  for name in pairs(PLATETWEAKS_PROFILES or {}) do
    table.insert(names, name)
  end
  -- Guarantee the fallback is always offerable, even before it is written.
  if not PLATETWEAKS_PROFILES[DEFAULT_PROFILE] then
    table.insert(names, DEFAULT_PROFILE)
  end
  table.sort(names)
  return names
end

  -- Respects the spec binding: if the current spec is bound this re-points the
  -- BINDING, otherwise the character default. Choosing while bound should not
  -- silently change what every other spec uses.
function NS.SelectProfile(name)
  if not name then return false end
  MigrateProfiles()
  if not PLATETWEAKS_PROFILES[name] then
    PLATETWEAKS_PROFILES[name] = {}
  end

  local assign = Assignments()
  local specID = NS.SpecID()
  if specID and assign.specs[specID] then
    assign.specs[specID] = name
  else
    assign.default = name
  end

  SwitchTo("profile selected")
  return true
end

-- copyFrom nil means blank. A blank profile is the honest default: rules name
-- specific spell IDs, so a copy is only useful when you know it applies.
function NS.CreateProfile(name, copyFrom)
  name = name and strtrim(name) or ""
  if name == "" then return false, "Give the profile a name." end
  MigrateProfiles()
  if PLATETWEAKS_PROFILES[name] then return false, ("'%s' already exists."):format(name) end

  local source = copyFrom and PLATETWEAKS_PROFILES[copyFrom]
  PLATETWEAKS_PROFILES[name] = source and CopyTable(source) or {}
  NS.SelectProfile(name)
  return true
end

function NS.DeleteProfile(name)
  MigrateProfiles()
  if not name or not PLATETWEAKS_PROFILES[name] then return false, "No such profile." end
  -- Deleting the last one would leave every character pointing at nothing.
  local count = 0
  for _ in pairs(PLATETWEAKS_PROFILES) do count = count + 1 end
  if count <= 1 then return false, "That is the only profile." end

  PLATETWEAKS_PROFILES[name] = nil

  -- Drop every reference, on every character, not just this one -- a dangling
  -- assignment would silently resolve back to Default later with no clue why.
  for _, entry in pairs(PLATETWEAKS_SETTINGS.assign or {}) do
    if entry.default == name then entry.default = nil end
    for specID, assigned in pairs(entry.specs or {}) do
      if assigned == name then entry.specs[specID] = nil end
    end
  end

  SwitchTo("profile deleted")
  return true
end

-- Bind or unbind the CURRENT spec. Binding pins whatever is live now, so the
-- box can be ticked without also having to re-pick the profile.
function NS.SetSpecBound(bound)
  local specID = NS.SpecID()
  if not specID then return false, "Spec is not known yet." end

  local assign = Assignments()
  if bound then
    assign.specs[specID] = NS.ProfileKey()
  else
    assign.specs[specID] = nil
  end
  SwitchTo("spec binding changed")
  return true
end

-- Which profile each spec of this character is pinned to, for the UI.
function NS.SpecBindings()
  return Assignments().specs
end

  -- Driven off GetNumSpecializations, so four (Druid) or one needs no case.
function NS.ClassSpecs()
  local specs = {}
  local getCount = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializations)
    or GetNumSpecializations
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
    or GetSpecializationInfo
  if not (getCount and getInfo) then return specs end

  local okCount, count = pcall(getCount)
  if not okCount or not count then return specs end

  for index = 1, count do
    local okInfo, id, name, _, icon = pcall(getInfo, index)
    if okInfo and type(id) == "number" then
      table.insert(specs, { id = id, name = name or ("Spec " .. index), icon = icon })
    end
  end
  return specs
end

-- Assign one spec directly. `name` nil clears the binding, which is how the
-- "use the character default" entry in each dropdown works.
function NS.SetSpecProfile(specID, name)
  if not specID then return false end
  MigrateProfiles()
  local assign = Assignments()
  if name and not PLATETWEAKS_PROFILES[name] then
    PLATETWEAKS_PROFILES[name] = {}
  end
  assign.specs[specID] = name
  SwitchTo("spec assignment")
  return true
end

function NS.GetSpecProfile(specID)
  if not specID then return nil end
  return Assignments().specs[specID]
end

function NS.SetCharacterDefault(name)
  if not name then return false end
  MigrateProfiles()
  if not PLATETWEAKS_PROFILES[name] then
    PLATETWEAKS_PROFILES[name] = {}
  end
  Assignments().default = name
  SwitchTo("character default")
  return true
end

function NS.GetCharacterDefault()
  MigrateProfiles()
  return Assignments().default or DEFAULT_PROFILE
end

  -- Moves the table rather than copying, so anything holding a live reference
  -- keeps working.
function NS.RenameProfile(oldName, newName)
  newName = newName and strtrim(newName) or ""
  MigrateProfiles()
  if not oldName or not PLATETWEAKS_PROFILES[oldName] then return false, "No such profile." end
  if newName == "" then return false, "Give the profile a name." end
  if newName == oldName then return true end
  if PLATETWEAKS_PROFILES[newName] then
    return false, ("'%s' already exists."):format(newName)
  end

  PLATETWEAKS_PROFILES[newName] = PLATETWEAKS_PROFILES[oldName]
  PLATETWEAKS_PROFILES[oldName] = nil

  -- Across every character, not just this one: a missed reference would
  -- silently fall back to Default with nothing to explain why.
  for _, entry in pairs(PLATETWEAKS_SETTINGS.assign or {}) do
    if entry.default == oldName then entry.default = newName end
    for specID, assigned in pairs(entry.specs or {}) do
      if assigned == oldName then entry.specs[specID] = newName end
    end
  end

  SwitchTo("profile renamed")
  return true
end

function NS.InitializeConfig()
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  local db = ResolveProfile()

  db.tweaks = db.tweaks or CopyTable(NS.Defaults.tweaks)
  for key, value in pairs(NS.Defaults.tweaks) do
    if db.tweaks[key] == nil then db.tweaks[key] = value end
  end
  db.icons = db.icons or CopyTable(NS.Defaults.icons)
  db.missingIcons = db.missingIcons or CopyTable(NS.Defaults.missingIcons)
  db.tints = db.tints or CopyTable(NS.Defaults.tints)
  db.levelOffset = db.levelOffset or NS.Defaults.levelOffset

  for key, value in pairs(NS.Defaults.icons) do
    if db.icons[key] == nil then
      db.icons[key] = type(value) == "table" and CopyTable(value) or value
    end
  end
  for key, value in pairs(NS.Defaults.missingIcons) do
    if db.missingIcons[key] == nil then
      db.missingIcons[key] = type(value) == "table" and CopyTable(value) or value
    end
  end
  for key, value in pairs(NS.Defaults.tints) do
    if db.tints[key] == nil then
      db.tints[key] = type(value) == "table" and CopyTable(value) or value
    end
  end

  -- Tier colours are backfilled PER KEY, not as a whole table.
  --
  -- The first version keyed this on raw UnitClassification: minus, worldboss,
  -- rareelite. Switching to tiers renamed most of them, and the loop above
  -- only fills a key that is nil -- so a profile written before the rename
  -- kept its whole stale table, left boss/lieutenant/caster absent, and fell
  -- through to a placeholder grey.
  --
  -- Stale keys are dropped in the same pass: they can never be read again, and
  -- leaving them makes the next person wonder which set is live.
  -- pinFlat moved to db.adapters[<name>].pinFlat. A value left here from the
  -- slash command's first version would still win over every adapter default,
  -- so it is dropped rather than migrated: there is no way to know which
  -- adapter it was aimed at, and the shipped defaults are right for all of
  -- them anyway.
  db.tints.pinFlat = nil

  do
    local defaults = NS.Defaults.tints.missingAppliedClassColors
    local colors = db.tints.missingAppliedClassColors
    if type(colors) ~= "table" then
      colors = CopyTable(defaults)
      db.tints.missingAppliedClassColors = colors
    else
      for key, value in pairs(defaults) do
        if type(colors[key]) ~= "table" then colors[key] = CopyTable(value) end
      end
      for key in pairs(colors) do
        if defaults[key] == nil then colors[key] = nil end
      end
    end
  end

  db.tints.rules = db.tints.rules or {}
  db.tints.borderRules = db.tints.borderRules or {}
  for _, rule in ipairs(db.tints.rules) do NS.NormaliseRule(rule) end
  for _, rule in ipairs(db.tints.borderRules) do NS.NormaliseBorderRule(rule) end

  -- Borders used to be half of a bar rule. Any rule carrying one is SPLIT --
  -- bar half stays, border half becomes a border rule with the same
  -- conditions. The plate looks identical afterwards.
  if not db.borderRulesMigrated then
    db.borderRulesMigrated = true
    for _, rule in ipairs(db.tints.rules) do
      if rule.border and rule.border.enabled then
        local conditions = {}
        for _, c in ipairs(rule.conditions or {}) do
          table.insert(conditions, { spellID = c.spellID })
        end
        table.insert(db.tints.borderRules, NS.NormaliseBorderRule({
          conditions = conditions,
          enabled = rule.enabled,
          border = CopyTable(rule.border),
        }))
        rule.border.enabled = false
        -- A rule that existed ONLY for its border would now paint nothing.
        if rule.barEnabled == false then rule.barEnabled = true end
      end
    end
  end
  -- The Color Rules twisty reads db.uiRailOpen.health/.border. That twisty
  -- was removed and reinstated mid-development, so anyone who had ever
  -- collapsed it has a dormant false under that key -- live again the moment
  -- the twisty returned, with no click of their own. Reads as "my rules
  -- vanished". Cleared once.
  if not db.railOpenMigrated then
    db.railOpenMigrated = true
    if db.uiRailOpen then
      db.uiRailOpen.health = nil
      db.uiRailOpen.border = nil
    end
  end

  db.uiSections = db.uiSections or {}

  -- uiSections only stores an explicit false, and the window was reorganised
  -- into pages carrying one section each -- anything collapsed under the old
  -- layout makes its new page look empty. Cleared once.
  if not db.uiSectionsReset then
    db.uiSectionsReset = true
    wipe(db.uiSections)
  end

  -- Old single "distance"/"nudge" pair became free X/Y padding when the
  -- anchor grew from four sides to all nine points.
  if db.icons.offset ~= nil or db.icons.offsetX ~= nil then
    db.icons.padY = db.icons.padY or db.icons.offset or 4
    db.icons.padX = db.icons.padX or db.icons.offsetX or 0
    db.icons.offset, db.icons.offsetX = nil, nil
  end

  -- One cooldown checkbox became two.
  if db.icons.showCooldown ~= nil then
    db.icons.showSwirl = db.icons.showCooldown
    db.icons.showTimer = db.icons.showCooldown
    db.icons.showCooldown = nil
  end

  -- "Top match wins" is computed per rule now, not chosen.
  db.tints.exclusive = nil

  -- Only the OLD DEFAULT font moves: someone who chose Friz Quadrata is
  -- indistinguishable from someone who never touched it.
  if not db.fontsMigrated then
    db.fontsMigrated = true
    if db.icons.timerFont == "Friz Quadrata TT" then
      db.icons.timerFont = "Expressway"
    end
    if db.icons.countFont == "Friz Quadrata TT" then
      db.icons.countFont = "Expressway"
    end
  end

  -- inset was absolute with 0 meaning flush; it is now an adjustment around a
  -- 1px baseline, so the same appearance is one lower. Carried, not reset.
  if db.tints.inset ~= nil then
    db.tints.edgeAdjust = db.tints.inset - 1
    db.tints.inset = nil
  end

  -- "Inactive" conditions are gone -- they forced a bar repaint that hid host
  -- art and only ever worked one at a time. Drop any rule left empty.
  for index = #db.tints.rules, 1, -1 do
    local rule = db.tints.rules[index]
    local kept = {}
    for _, condition in ipairs(rule.conditions or {}) do
      if condition.state ~= "inactive" then
        table.insert(kept, { spellID = condition.spellID })
      end
    end
    rule.conditions = kept
    if #kept == 0 then
      table.remove(db.tints.rules, index)
    end
  end

  -- Combos led on draw order, so they take the higher priority slots.
  if db.tints.combos then
    for _, combo in ipairs(db.tints.combos) do
      local conditions = {}
      for _, spellID in ipairs(combo.spells or {}) do
        table.insert(conditions, { spellID = spellID, state = "active" })
      end
      if #conditions >= 2 then
        table.insert(db.tints.rules, {
          color = combo.color or DefaultColor(),
          conditions = conditions,
          enabled = combo.enabled ~= false,
        })
      end
    end
    db.tints.combos, db.tints.comboSeq, db.tints.combosMigrated = nil, nil, nil
  end
  if db.tints.list then
    for _, entry in ipairs(db.tints.list) do
      table.insert(db.tints.rules, {
        color = entry.color or DefaultColor(),
        conditions = { { spellID = entry.spellID, state = entry.mode == "missing" and "inactive" or "active" } },
        enabled = entry.enabled ~= false,
      })
    end
    db.tints.list = nil
  end

  -- Migrate the very first schema: db.spells was a spellID -> {color, priority}
  -- map, db.combos a parallel array.
  if db.combos then
    for _, combo in ipairs(db.combos) do
      local conditions = {}
      for _, spellID in ipairs(combo.spells or {}) do
        table.insert(conditions, { spellID = spellID, state = "active" })
      end
      if #conditions >= 2 then
        table.insert(db.tints.rules, {
          color = combo.color or DefaultColor(),
          conditions = conditions,
          enabled = true,
        })
      end
    end
    db.combos, db.comboSeq = nil, nil
  end
  if db.spells then
    local ordered = {}
    for spellID, entry in pairs(db.spells) do
      table.insert(ordered, { spellID = spellID, color = entry.color, priority = entry.priority or 5 })
    end
    table.sort(ordered, function(a, b)
      if a.priority ~= b.priority then return a.priority < b.priority end
      return a.spellID < b.spellID
    end)
    for _, entry in ipairs(ordered) do
      table.insert(db.tints.rules, {
        color = entry.color or DefaultColor(),
        conditions = { { spellID = entry.spellID, state = "active" } },
        enabled = true,
      })
    end
    db.spells = nil
  end

  -- Deliberately no starter rule: a new character begins blank, with icons
  -- off, because a seeded Warlock spell would be meaningless on a Druid.

  NS.db = db
end

-------------------------------------------------------------------------------
-- Rule helpers
-------------------------------------------------------------------------------

-- Raised 2 -> 3 -> 4 (v1.5.0) once aura slots removed the cost argument. The
-- old ceiling described the AddAuraGroup path, where a rule had to cover every
-- combination of live buttons: 100 textures for two debuffs, 1000 for three.
-- With slots a rule builds one combination.
NS.MAX_RULE_CONDITIONS = 4

-- Missing rules are single-debuff, full stop. Rank k already spends a chain
-- level per rule above it plus one for its own debuff, and a second condition
-- needs another with no sublevel room for it. A guard for old data, not a cap
-- anyone can reach.
NS.MAX_MISSING_CONDITIONS = 1

-- Inline icons via the |T escape: a rule is read at a glance by its icons,
-- and the names are there to disambiguate rather than to be scanned.
function NS.RuleSummary(rule)
  local parts = {}
  for _, condition in ipairs(rule.conditions or {}) do
    table.insert(parts, ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(
      NS.SpellIcon(condition.spellID), NS.SpellName(condition.spellID)))
  end
  if #parts == 0 then
    return "|cffff0000no debuffs — add one|r"
  end
  local summary = table.concat(parts, " |cff808080+|r ")
  -- A missing rule fires on the opposite state to every other row, so the list
  -- has to say which it is. Prefixed, since rows truncate from the right.
  if rule.showWhenMissing then
    return "|cffffcc22MISSING:|r " .. summary
  end
  return summary
end

-- True when `outer` requires everything `inner` does — i.e. whenever inner
-- matches, outer's extra debuffs are the only thing that can separate them.
function NS.RuleCovers(outer, inner)
  for _, condition in ipairs(inner.conditions or {}) do
    local found = false
    for _, mine in ipairs(outer.conditions or {}) do
      if mine.spellID == condition.spellID then found = true break end
    end
    if not found then return false end
  end
  return true
end

-- Most debuffs first, preserving the user's order within each size: a rule
-- with fewer debuffs above one with more shadows it forever. Sorts whichever
-- list it is handed, defaulting to the bar rules.

-- Which rules can never fire, and what blocks each.
--
-- Matching is first-from-the-top, so a rule is dead when something above it
-- matches everything it matches -- exactly when the higher rule's conditions
-- are a SUBSET of the lower one's. Auto sort prevents it; dragging can undo
-- that, so rather than refusing the drop the offending rule is reported.
--
-- Returns index -> index of the first rule blocking it.
function NS.ShadowedRules(list)
  local rules = list or NS.db.tints.rules or {}
  local shadowed = {}
  for lower = 1, #rules do
    local rule = rules[lower]
    if rule.enabled ~= false and #(rule.conditions or {}) > 0 then
      for upper = 1, lower - 1 do
        local above = rules[upper]
        if above.enabled ~= false and #(above.conditions or {}) > 0
          -- every condition of `above` also appears in `rule`
          and NS.RuleCovers(rule, above) then
          shadowed[lower] = upper
          break
        end
      end
    end
  end
  return shadowed
end

function NS.SortRules(list)
  local rules = list or NS.db.tints.rules
  local original = {}
  for index, rule in ipairs(rules) do original[rule] = index end
  table.sort(rules, function(a, b)
    -- Missing rules always sort below every normal rule -- their priority only
    -- means anything against other missing rules. Sorting one by debuff count
    -- would land it above a normal rule it can never win against.
    local ma = a.showWhenMissing and true or false
    local mb = b.showWhenMissing and true or false
    if ma ~= mb then return not ma end
    local ca, cb = #(a.conditions or {}), #(b.conditions or {})
    if ca ~= cb then return ca > cb end
    return original[a] < original[b]
  end)
end

-- Enabled, non-empty rules from one list, in priority order.
local function OrderList(list)
  local ordered = {}
  for _, rule in ipairs(list or {}) do
    if rule.enabled ~= false and #(rule.conditions or {}) > 0 then
      table.insert(ordered, rule)
    end
  end
  return ordered
end

function NS.GetOrderedRules()
  return OrderList(NS.db.tints.rules)
end

-- Border rules keep their own stack: the top BAR rule and the top BORDER rule
-- both apply, which is the whole point of splitting them.
function NS.GetOrderedBorderRules()
  return OrderList(NS.db.tints.borderRules)
end

function NS.IsRestricted()
  if C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() then
    return InCombatLockdown() or C_Secrets.ShouldAurasBeSecret()
  end
  return false
end

function NS.Print(msg)
  print("|cffff59bfPlateTweaks|r: " .. msg)
end

-- Ordered-list helpers shared by the options UI.
function NS.ListIndexOf(list, spellID)
  for index, entry in ipairs(list) do
    if entry.spellID == spellID then return index end
  end
end

function NS.ListMove(list, index, delta)
  local target = index + delta
  if target < 1 or target > #list then return false end
  list[index], list[target] = list[target], list[index]
  return true
end

  -- Remove-then-insert, not a swap: typing 1 on the bottom rule should lift it
  -- to the top and push the rest down.
function NS.ListMoveTo(list, index, target)
  if not index or not target then return false end
  target = math.max(1, math.min(#list, math.floor(target + 0.5)))
  if target == index or not list[index] then return false end
  local item = table.remove(list, index)
  table.insert(list, target, item)
  return true
end

-------------------------------------------------------------------------------
-- Health bar discovery: adapters for known addons, then a generic fallback.
-------------------------------------------------------------------------------

local function IsStatusBar(frame)
  return frame and frame.GetObjectType and frame:GetObjectType() == "StatusBar"
end

local function ScanForStatusBar(frame, depth, best)
  if depth > 4 then return best end
  for _, child in ipairs({frame:GetChildren()}) do
    if child:IsShown() then
      if IsStatusBar(child) then
        -- Size is readable on a nameplate; POSITION is not. GetCenter,
        -- GetLeft, GetRect and friends are all refused outright in 12.1 --
        -- verified with /pt layers. This read was unprotected, so it threw,
        -- and the pcall around this whole function turned that into "no bar
        -- found". The generic fallback -- the only adapter for a nameplate
        -- addon we do not recognise by name -- has therefore never worked
        -- since 12.1, silently, for everyone not on a named host.
        --
        -- Area alone decides now. The vertical tie-break existed to prefer
        -- the upper bar when two matched exactly, which is rare and was never
        -- worth a hard dependency on position.
        local okSize, w, h = pcall(child.GetSize, child)
        local area = okSize and (w or 0) * (h or 0) or 0
        if area > 0 and (not best or area > best.area) then
          best = { bar = child, area = area }
        end
      end
      best = ScanForStatusBar(child, depth + 1, best)
    end
  end
  return best
end

-- Which adapter branch below actually matched. Stamped on the bar rather
-- than re-derived, so a diagnostic never disagrees with what was used, and so
-- "works on Plater, not on X" reports arrive with X already named.
local function Adapter(bar, name)
  if bar then bar.ptAdapter = name end
  return bar
end

function NS.HostName(healthBar)
  return healthBar and healthBar.ptAdapter or "unknown"
end

-------------------------------------------------------------------------------
-- Per-adapter layout
--
-- Four settings describe the HOST's bar, not the user's taste: how far above it
-- to draw, whether to elevate at all, how far its border reaches inside, and
-- the gap between its bar frame and its fill texture. All four were global,
-- which is wrong the moment two people run different nameplate addons -- and
-- the outline offset already carried a comment admitting it.
--
-- Keyed by the adapter FindHealthBar matched, so most people never see any of
-- this: the shipped value for their addon is simply correct.
-------------------------------------------------------------------------------

-- Which config table each key really lives in, for the fallback below.
local ADAPTER_KEYS = {
  levelOffset        = "root",
  pinFlat            = "tints",
  edgeAdjust         = "tints",
  plateOutlineOffset = "tints",
}
NS.ADAPTER_KEYS = ADAPTER_KEYS

-- Only where there is EVIDENCE. Plater and Blizzard's default plate both keep
-- their name text on the bar itself, so elevating over the bar covers it --
-- that is what the old IsPlaterBar test encoded and it stays true.
--
-- Platynator and EllesmereUI are deliberately absent rather than guessed at.
-- Platynator was measured (bar at 513, text at 1010+, nothing on the bar) and
-- needs no deviation from the generic values; EllesmereUI has not been
-- measured at all, and inventing numbers for it would be worse than nothing.
NS.ADAPTER_DEFAULTS = {
  Plater   = { pinFlat = true },
  Blizzard = { pinFlat = true },
  -- Contributed, not measured. The user who added NDui support reports flat
  -- works for them; nobody here has run /pt layers on it. If it turns out
  -- wrong, an NDui user can flip it with /pt adapter pinflat off without
  -- waiting for a build -- which is the reason these are per-adapter.
  NDui     = { pinFlat = true },
}

-- Resolution order, nil meaning "keep falling through":
--
--   1. this adapter's own value, if the user set one
--   2. the matching global, but ONLY if the user moved it off the shipped
--      value -- otherwise an untouched global masks every adapter default
--   3. the shipped default for this adapter
--   4. the global as-is
--
-- Step 2 is what makes this additive: nobody's existing tuning changes
-- meaning, and no profile migration is needed.
function NS.AdapterSetting(healthBar, key)
  local scope = ADAPTER_KEYS[key]
  if not scope or not NS.db then return nil end

  local name = NS.HostName(healthBar)
  local per = NS.db.adapters and NS.db.adapters[name]
  if per and per[key] ~= nil then return per[key] end

  local live, shipped
  if scope == "root" then
    live, shipped = NS.db[key], NS.Defaults[key]
  else
    live, shipped = (NS.db.tints or {})[key], (NS.Defaults.tints or {})[key]
  end
  if live ~= nil and live ~= shipped then return live end

  local perAdapter = NS.ADAPTER_DEFAULTS[name]
  if perAdapter and perAdapter[key] ~= nil then return perAdapter[key] end
  return live
end

-- Writes go to the adapter, never to the global. nil clears back to inherited.
function NS.SetAdapterSetting(name, key, value)
  if not ADAPTER_KEYS[key] or not NS.db then return false end
  NS.db.adapters = NS.db.adapters or {}
  local per = NS.db.adapters[name]
  if not per then per = {}; NS.db.adapters[name] = per end
  per[key] = value
  -- Emptied entries are dropped so a profile does not accumulate a table per
  -- adapter anyone ever loaded.
  local any = false
  for _ in pairs(per) do any = true break end
  if not any then NS.db.adapters[name] = nil end
  return true
end

function NS.FindHealthBar(nameplate)
  -- Plater: hides Blizzard's UnitFrame and draws its own bar in
  -- nameplate.unitFrame (lowercase u), which is not necessarily parented to
  -- the nameplate. A direct field read, so it survives aura secrecy.
  if IsStatusBar(nameplate.unitFrame and nameplate.unitFrame.healthBar) then
    return Adapter(nameplate.unitFrame.healthBar, "Plater")
  end

  -- NDui: same nameplate.unitFrame as Plater but a .Health StatusBar on it,
  -- so this has to come after Plater's .healthBar check rather than before.
  -- Contributed by an NDui user; the field names are theirs, not measured here.
  local nduiHealth = nameplate.unitFrame and nameplate.unitFrame.Health
  if IsStatusBar(nduiHealth) and nduiHealth:IsShown() then
    return Adapter(nduiHealth, "NDui")
  end

  -- EllesmereUI: plate child with a .health StatusBar.
  -- PlateTweaks:  root child with a .bar StatusBar.
  -- Platynator:   display child with .widgets; health widget has .statusBar.
  --
  -- IsShown() gates every branch. Addons that swap display styles can leave a
  -- retired display as a sibling child, and latching onto that one builds a
  -- rig whose textures are real but sit under a hidden ancestor.
  for _, child in ipairs({nameplate:GetChildren()}) do
    if child:IsShown() then
      if IsStatusBar(child.health) and child.health:IsShown() then
        return Adapter(child.health, "EllesmereUI")
      end
      if IsStatusBar(child.bar) and child.bar:IsShown() and (child.textFrame or child.iconContainer) then
        return Adapter(child.bar, "PlateTweaks-style")
      end
      if child.widgets and child.AurasManager then
        for _, w in ipairs(child.widgets) do
          if w.kind == "bars" and w.details and w.details.kind == "health"
              and IsStatusBar(w.statusBar) and w.statusBar:IsShown() then
            return Adapter(w.statusBar, "Platynator")
          end
        end
      end
    end
  end

  local unitFrame = nameplate.UnitFrame
  if unitFrame and unitFrame:GetParent() == nameplate and unitFrame:IsShown() then
    local healthBar = (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar)
      or unitFrame.healthBar or unitFrame.HealthBar
    if IsStatusBar(healthBar) then
      -- Blizzard's default plate keeps its name text on unitFrame, a frame our
      -- tints never climb. Tagged so NS.IsPlaterBar pins this bar flat too,
      -- instead of letting per-rule elevation grow past unitFrame.
      healthBar.ptDefaultBlizzardBar = true
      return Adapter(healthBar, "Blizzard")
    end
  end

  -- Measuring the plate subtree can hit 12.1 restrictions, so only scan when
  -- unrestricted; the pending queue retries later.
  if not NS.IsRestricted() then
    local ok, best = pcall(ScanForStatusBar, nameplate, 1, nil)
    if ok and best then
      -- Second return: this one is a GUESS. Every branch above matched a
      -- named field a host actually publishes; this one just picked the
      -- biggest visible StatusBar in the subtree, which a cast bar can win
      -- for as long as it is up. Fine for a first attach, not evidence that
      -- a plate's bar has been REPLACED -- see ResyncSwappedBars.
      return Adapter(best.bar, "generic scan"), true
    end
  end
end

-------------------------------------------------------------------------------
-- Rig lifecycle
-------------------------------------------------------------------------------

local rigs = {}
local unitRigs = {}
local pendingUnits = {}
  -- Tokens with a plate on screen, from NAME_PLATE_UNIT_ADDED/REMOVED, which
  -- pass the token directly. plate.namePlateUnitToken read off the frame
  -- proved unreliable -- see ResyncVisiblePlates.
local activeUnits = {}
local rebuildPending = false
local rigRepairs = 0

NS.rigs = rigs
-- Exposed for /pt status: a non-empty queue means plates arrived whose health
-- bar we could not find, which is invisible from anywhere else.
NS.pendingUnits = pendingUnits

-- Rig currently bound to a unit token, for callers that have a token rather
-- than a health bar.
function NS.UnitRig(unit) return unit and unitRigs[unit] or nil end

local eventFrame = CreateFrame("Frame")

-- Re-assigning the same unit churns the container's button pool, which is what
-- drove runaway button counts. Skip when nothing changed.
--
-- Always re-assign on plate add, though: unit tokens are recycled for
-- different creatures, so caching the token risks a container staying bound to
-- a dead mob.
--
-- record is optional. When present, its rule's showOnTarget/showOnFocus can
-- veto this one rule's containers for this one unit.
function NS.ActivateContainer(rig, frame, record)
  local unit = rig.unit
  if unit and record and record.rule then
    local rule = record.rule
    if rule.showOnTarget == false and UnitIsUnit(unit, "target") then
      unit = nil
    elseif rule.showOnFocus == false and UnitIsUnit(unit, "focus") then
      unit = nil
    end
  end
  -- The ladder carries its own combat gate, and this runs on every rebind --
  -- without it, binding a plate switches a closed ladder back on until the
  -- poll notices. `== false` not `not`: nil means not yet evaluated.
  --
  -- Only when the gate is using ENABLEMENT. On the visibility lever the
  -- container stays enabled and simply does not render.
  if unit and record and record.missingStack and rig.missingGateOpen == false
    and record.gateLever ~= "shown" then
    unit = nil
  end
  if unit then
    -- Show BEFORE enabling. NS.RetireTints hides a container as well as
    -- disabling it, and health bars are pooled -- so a rig retired on a bar
    -- swap comes back for the next mob still hidden. A hidden container never
    -- lays out, so it never grows, so a displacement mask never moves and the
    -- wash is stuck ON permanently for that bar. Enabling alone did not undo
    -- it, and nothing else ever did.
    --
    -- pcall because a NESTED container is a child of an aura button and Show
    -- is refused there -- the same asymmetry RetireTints documents. Those were
    -- never hidden in the first place, so a refusal costs nothing.
    pcall(frame.Show, frame)
    frame:SetUnit(unit)
    frame:SetEnabled(true)
  else
    frame:SetEnabled(false)
  end
end

  -- Every stage is isolated: a failure in one must not stop the others, since
  -- a rig that never gets SetUnit shows nothing at all.
local function BuildRig(healthBar)
  local rig = { healthBar = healthBar, unit = nil, buildErrors = {} }
  rig.baseLevel = NS.BaseLevelFor(healthBar)
  -- Creating an AuraContainer is refused in combat, and every builder here
  -- COUNTS its failures instead of raising. So a rig built mid-pull can come
  -- back structurally empty and still look healthy. Recorded so it can be
  -- thrown away later; see RigIsSound.
  rig.builtInCombat = InCombatLockdown() and true or false

  local okTints, tintErr = pcall(NS.BuildTints, rig, healthBar)
  if not okTints then
    table.insert(rig.buildErrors, "tints: " .. tostring(tintErr))
  end
  local okIcons, iconErr = pcall(NS.BuildIcons, rig, healthBar)
  if not okIcons then
    table.insert(rig.buildErrors, "icons: " .. tostring(iconErr))
  end
  local okMissing, missingErr = pcall(NS.BuildMissingIcons, rig, healthBar)
  if not okMissing then
    table.insert(rig.buildErrors, "missing icons: " .. tostring(missingErr))
  end

  rigs[healthBar] = rig
  return rig
end

-- Did this rig come out of BuildRig whole?
--
-- Rigs are keyed by the HEALTH BAR, and health bars are pooled. Nothing ever
-- re-examined a rig once built, so a single plate that spawned during a pull
-- left a broken rig on that bar -- and every later mob handed that bar got it
-- too, for the rest of the session. That is the "first key fine, later pulls
-- dead" report.
local function RigIsSound(rig)
  if not rig then return false end
  if rig.builtInCombat then return false end
  if #(rig.buildErrors or {}) > 0 then return false end
  for _, record in ipairs(rig.rules or {}) do
    if (record.failures or 0) > 0 then return false end
  end
  if ((rig.missingDisplace or {}).failures or 0) > 0 then return false end
  if ((rig.icons or {}).failures or 0) > 0 then return false end
  if (rig.missingFailures or 0) > 0 then return false end
  return true
end

-- Unbind, tear down, and drop from the table. Both the bar-swap path and the
-- unsound-rig path do exactly this, and they drifted apart once already.
local function DiscardRig(rig, SetUnit)
  SetUnit(rig, nil)
  pcall(NS.RetireTints, rig)
  pcall(NS.RetireIcons, rig)
  pcall(NS.RetireMissingIcons, rig)
  if rigs[rig.healthBar] == rig then rigs[rig.healthBar] = nil end
end

local function AnchorRig(rig)
  local okTints, tintErr = pcall(NS.AnchorTints, rig)
  if not okTints then
    table.insert(rig.buildErrors, "anchor tints: " .. tostring(tintErr))
  end
  local okIcons, iconErr = pcall(NS.AnchorIcons, rig)
  if not okIcons then
    table.insert(rig.buildErrors, "anchor icons: " .. tostring(iconErr))
  end
  local okMissing, missingErr = pcall(NS.AnchorMissingIcons, rig)
  if not okMissing then
    table.insert(rig.buildErrors, "anchor missing icons: " .. tostring(missingErr))
  end
end

local function SetRigUnit(rig, unit)
  rig.unit = unit
  NS.SetTintsUnit(rig)
  NS.SetIconsUnit(rig)
  NS.SetMissingIconsUnit(rig)
end

-- Building frames is blocked by COMBAT; reading aura state is blocked by
-- SECRECY. NS.IsRestricted() is true for a whole dungeon, not just its fights,
-- so gating rebuilds on it meant a rule added inside a key only landed once
-- you left the instance. Creating and colouring our own frames out of combat
-- is fine in restricted content, so the gate is combat alone.
function NS.CanBuild()
  return not InCombatLockdown()
end

-- Config changes alter the aura groups, which cannot be edited after creation,
-- so old containers are retired and fresh ones built.

-- A deterministic fingerprint of the config a rebuild would read.
--
-- Deliberately over-inclusive: it serialises the whole tints and icons config
-- rather than an enumerated list of structural fields. Getting that list wrong
-- means a setting that silently never applies. Colour and alpha never reach
-- here -- those go through the Live path.
local function Fingerprint(value, out, depth)
  if depth > 8 then out[#out + 1] = "..." return out end
  if type(value) == "table" then
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    -- pairs() order is not stable between traversals, so a fingerprint built
    -- in that order would differ from itself and skip nothing.
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, key in ipairs(keys) do
      out[#out + 1] = tostring(key)
      out[#out + 1] = "="
      Fingerprint(value[key], out, depth + 1)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = tostring(value)
  end
  return out
end

local lastBuildPrint
local skippedRebuilds = 0
NS.SkippedRebuilds = function() return skippedRebuilds end

local function ConfigFingerprint()
  local base = table.concat(Fingerprint({
    tints = NS.db and NS.db.tints,
    icons = NS.db and NS.db.icons,
    missingIcons = NS.db and NS.db.missingIcons,
    levelOffset = NS.db and NS.db.levelOffset,
    -- Structural: every one of these changes what gets built or where.
    adapters = NS.db and NS.db.adapters,
  }, {}, 0))

  -- The spell gate reads the SPELLBOOK, so a talent change alters what would
  -- be built while every setting stays byte-identical.
  if NS.db and NS.db.tints and NS.db.tints.gateUnknownSpells and NS.CanApplyAura then
    local bits = {}
    for _, list in ipairs({ NS.db.tints.rules or {}, NS.db.tints.borderRules or {} }) do
      for _, rule in ipairs(list) do
        for _, condition in ipairs(rule.conditions or {}) do
          bits[#bits + 1] = tostring(condition.spellID)
            .. (NS.CanApplyAura(condition.spellID) and "1" or "0")
        end
      end
    end
    return base .. "|" .. table.concat(bits, ",")
  end

  return base
end

function NS.RebuildAllRigs(force)
  if not NS.CanBuild() then
    rebuildPending = true
    return false
  end

  -- Nothing a rebuild reads has changed, so it would build an identical set
  -- and orphan the current one -- permanent growth for no visible change.

  -- Config may have changed, so anything derived from it has to be dropped.
  if NS.InvalidateFillCache then NS.InvalidateFillCache() end

  local fingerprint = ConfigFingerprint()
  if not force and lastBuildPrint == fingerprint then
    rebuildPending = false
    skippedRebuilds = skippedRebuilds + 1
    return true
  end
  lastBuildPrint = fingerprint

  rebuildPending = false
  if NS.stats then NS.stats.rebuilds = NS.stats.rebuilds + 1 end

  -- Snapshot first: BuildRig re-adds the same keys, and adding keys during
  -- a pairs() traversal is undefined in Lua.
  local existing = {}
  for healthBar, rig in pairs(rigs) do
    table.insert(existing, { healthBar = healthBar, unit = rig.unit, rig = rig })
  end

  for _, item in ipairs(existing) do
    NS.RetireTints(item.rig)
    NS.RetireIcons(item.rig)
    NS.RetireMissingIcons(item.rig)
    rigs[item.healthBar] = nil
  end

  for _, item in ipairs(existing) do
    local fresh = BuildRig(item.healthBar)
    AnchorRig(fresh)
    if item.unit then
      SetRigUnit(fresh, item.unit)
      unitRigs[item.unit] = fresh
    end
  end
  return true
end

-- Every rule filters HARMFUL|PLAYER, so a friendly plate can never match one
-- and rigging it costs a container and texture per rule for nothing.
--
-- This used to answer "not sure" with YES. In restricted content that
-- inverted: UnitCanAttack returns a secret there, so every plate came back
-- unsure and every friendly plate in the raid got rigged -- the biggest cost
-- the addon pays, exactly where it can least afford it.
--
-- So: ask several independent questions, take the first real answer, and if
-- none come, defer rather than guess. The plate goes back into pendingUnits
-- and the 1s backstop asks again.
local skippedPlates = 0
local unknownPlates = 0
NS.SkippedPlates = function() return skippedPlates end
NS.UnknownPlates = function() return unknownPlates end
-- Rigs thrown away and rebuilt because the first build came back broken --
-- almost always one built under combat lockdown. A number climbing with pulls
-- is expected; one climbing while out of combat is not.
NS.RigRepairs = function() return rigRepairs end

-- A value we can actually branch on: present, and not a secret.
local function Usable(ok, value)
  if not ok or value == nil then return false end
  if issecretvalue and issecretvalue(value) then return false end
  return true
end

-- true = can carry our debuffs, false = cannot, nil = ask again later.
-- None of these are aura APIs, so none are secret the way UnitCanAttack is.
-- Ordered by how directly they answer, not by how likely they are to work.
local function CanCarryOurAuras(unit)
  local ok, canAttack = pcall(UnitCanAttack, "player", unit)
  if Usable(ok, canAttack) then return canAttack and true or false end

  -- Reaction runs 1 (hated) to 8 (exalted); 4 is neutral. Neutral units are
  -- attackable and can absolutely carry your debuffs, so the cut is above it.
  local okReaction, reaction = pcall(UnitReaction, "player", unit)
  if Usable(okReaction, reaction) and type(reaction) == "number" then
    return reaction <= 4
  end

  local okEnemy, isEnemy = pcall(UnitIsEnemy, "player", unit)
  if Usable(okEnemy, isEnemy) and isEnemy then return true end

  local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
  if Usable(okFriend, isFriend) and isFriend then return false end

  return nil
end

local function OnPlateAdded(unit, isRetry)
  if UnitIsUnit(unit, "player") then return end

  local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
  if not nameplate then return end

  local healthBar = NS.FindHealthBar(nameplate)
  if not healthBar then
    -- Some addons (Platynator) build the real bar a beat after the plate, so
    -- the first lookup can lose a timing race. One same-frame retry; anything
    -- slower queues for the 1s backstop.
    pendingUnits[unit] = true
    if not isRetry then
      C_Timer.After(0, function()
        if UnitExists(unit) then OnPlateAdded(unit, true) end
      end)
    end
    return
  end
  pendingUnits[unit] = nil

  local carries = CanCarryOurAuras(unit)
  if carries ~= true then
    if carries == nil then
    -- Not friendly, just not answerable yet. An unknown plate costs nothing
    -- until it is known.
      unknownPlates = unknownPlates + 1
      pendingUnits[unit] = true
    else
      skippedPlates = skippedPlates + 1
    end
    -- Health bars are pooled, so one that carried a hostile mob can come back
    -- holding a friendly NPC. A rig left bound to a dead token keeps its
    -- containers enabled against whatever the token now points at.
    --
    -- Only on a real NO. carries == nil means the question could not be
    -- answered yet, and this runs again every second off the backstop -- so
    -- unbinding here switched a working plate off once a second, forever, for
    -- any unit whose probes stay secret. Leaving it bound is the safe guess:
    -- the rules filter HARMFUL|PLAYER, so a friendly plate shows nothing
    -- anyway, and the next answerable tick corrects it either way.
    if carries == false then
      local existing = rigs[healthBar]
      if existing then
        SetRigUnit(existing, nil)
      end
      unitRigs[unit] = nil
    end
    return
  end

  -- Blizzard's own aura row, if the user asked for it to be out of the way.
  if NS.ApplyBlizzardAuras then pcall(NS.ApplyBlizzardAuras, nameplate) end

  -- The bar object can be REPLACED, not just restyled -- Platynator swaps in a
  -- different display frame when a unit becomes your target, which is why a
  -- plate that tinted fine stopped the moment it was targeted. Without this
  -- the old rig stays enabled against a frame nothing renders.
  local previous = unitRigs[unit]
  if previous and previous.healthBar ~= healthBar then
    DiscardRig(previous, SetRigUnit)
  end

  local rig = rigs[healthBar]
  -- Reuse only what came out whole. Gated on CanBuild as well: rebuilding
  -- under lockdown would fail in exactly the same way and churn every plate in
  -- the pull, so a broken rig is kept until combat drops and the regen handler
  -- walks back through here.
  --
  -- Capped, configurable (NS.db.tints.maxRigRepairs, default 1). Frames cannot
  -- be destroyed, so each rebuild leaks the old container set -- and a rule
  -- that fails for a reason other than lockdown fails again on the retry.
  -- Without a cap that is an unbounded leak on every plate add, which is worse
  -- than the bug being fixed. One attempt covers the case that matters: built
  -- in combat, rebuilt once out of it. Raising the cap trades a small bounded
  -- amount of leaked frames for a better chance of recovering a plate whose
  -- one repair attempt itself landed mid-lockdown (a brief regen flicker
  -- between two pulls).
  --
  -- CanBuild first, so mid-pull this whole branch is one boolean. Adds arrive
  -- in bursts, and there is no point walking a rig's records to grade it when
  -- lockdown means the answer cannot be acted on either way.
  local repairs = rig and rig.repairs or 0
  local repairCap = (NS.db and NS.db.tints and NS.db.tints.maxRigRepairs) or 1
  if rig and NS.CanBuild() and repairs < repairCap and not RigIsSound(rig) then
    DiscardRig(rig, SetRigUnit)
    rig = nil
    repairs = repairs + 1
    rigRepairs = rigRepairs + 1
  end
  if not rig then
    rig = BuildRig(healthBar)
    rig.repairs = repairs
  end
  AnchorRig(rig)
  -- Runs unconditionally: without it every container stays disabled.
  SetRigUnit(rig, unit)
  unitRigs[unit] = rig
end

  -- A target/focus swap adds no plate, so Reapply never runs. Cheap: this only
  -- re-checks enabled state, it builds nothing.
local function ReapplyGating()
  for _, rig in pairs(unitRigs) do
    NS.SetTintsUnit(rig)
  end
end

local function OnPlateRemoved(unit)
  pendingUnits[unit] = nil
  local rig = unitRigs[unit]
  unitRigs[unit] = nil
  -- Only if this rig is still OURS. Health bars are pooled, so the bar this
  -- token was using can already have been handed to another token and rebound
  -- -- ADDED for the new unit is not guaranteed to arrive after REMOVED for
  -- the old one. Unbinding unconditionally killed the plate that had just
  -- taken the bar over, and nothing rebound it until the next swap.
  if rig and rig.unit == unit then
    SetRigUnit(rig, nil)
  end
end

-- Re-attach to every plate the client currently shows: NAME_PLATE_UNIT_ADDED
-- fired once already, but if that happened in combat or before the config
-- existed, the rig was never made.
--
-- Driven by activeUnits rather than walking GetNamePlates() and reading
-- plate.namePlateUnitToken -- that field is not reliably populated. Verified:
-- the frame GetNamePlateForUnit returned was not even in the GetNamePlates()
-- list, so every token came back nil and this silently iterated nothing.
local function ResyncVisiblePlates()
  for unit in pairs(activeUnits) do
    if UnitExists(unit) then
      pcall(OnPlateAdded, unit)
    else
      activeUnits[unit] = nil
    end
  end
end

-- Rebuild ONLY the plates whose bar frame has actually been replaced.
--
-- Some addons swap a plate's bar rather than restyling it -- Platynator on
-- target change -- which strands our rig on a frame that is no longer drawn.
-- The rig still looks healthy from outside, so nothing else detects it.
--
-- Comparing bar identity first keeps this cheap and invisible to addons that
-- do not swap: one FindHealthBar and a table compare per plate. The full
-- ResyncVisiblePlates would churn every plate's button pools instead.
-- confirmed: require the same answer twice before acting. The 1s backstop
-- passes it; a target swap does not, because that one is a deliberate host
-- action and waiting a second for it is the bug this function was written to
-- fix in the first place.
local function ResyncSwappedBars(confirmed)
  for unit in pairs(activeUnits) do
    local rig = unitRigs[unit]
    if rig and UnitExists(unit) then
      local plate = C_NamePlate.GetNamePlateForUnit(unit)
      if plate then
        local okBar, current, guessed = pcall(NS.FindHealthBar, plate)
        -- guessed answers are excluded entirely. FindHealthBar's last resort
        -- picks the biggest visible StatusBar, which a cast bar wins while it
        -- is up -- so a casting mob looked like a bar swap, tore the plate
        -- down, rebuilt it on the cast bar, then tore it down again when the
        -- cast ended. Frames cannot be destroyed, so each round leaked a full
        -- container set.
        if okBar and current and current ~= rig.healthBar and not guessed then
          if not confirmed or rig.pendingSwapBar == current then
            rig.pendingSwapBar = nil
            pcall(OnPlateAdded, unit)
          else
            rig.pendingSwapBar = current
          end
        else
          rig.pendingSwapBar = nil
        end
      end
    end
  end
end
NS.ResyncVisiblePlates = ResyncVisiblePlates

-- One place that decides what "catch up" means, so no trigger can drift.
--
-- reason is unread on purpose -- call sites read as Reapply("combat ended"),
-- which documents the trigger better than a comment would.
local function Reapply(reason)
  if NS.InvalidateFillCache then NS.InvalidateFillCache() end
  if not NS.CanBuild() then
    rebuildPending = true
    return false
  end

  if rebuildPending then
    NS.RebuildAllRigs()
  else
    for _, rig in pairs(rigs) do
      AnchorRig(rig)
    end
  end

  ResyncVisiblePlates()
  -- Unconditional: colours are our own textures, and this is the step that
  -- was silently skipped for the whole of every dungeon.
  NS.ApplyTintColors()

  return true
end
NS.Reapply = Reapply

eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "NAME_PLATE_UNIT_ADDED" then
    activeUnits[arg1] = true
    OnPlateAdded(arg1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    activeUnits[arg1] = nil
    OnPlateRemoved(arg1)
  elseif event == "PLAYER_REGEN_ENABLED" then
    Reapply("combat ended")
    -- Snapshot first. OnPlateAdded clears this key and can then put it back,
    -- and re-adding a key that is currently nil counts as adding a NEW field
    -- mid-pairs() -- undefined in Lua. In practice it either skips the rest of
    -- the queue or throws, which aborts everything below in this handler.
    local retry = {}
    for unit in pairs(pendingUnits) do retry[#retry + 1] = unit end
    for _, unit in ipairs(retry) do
      pendingUnits[unit] = nil
      if UnitExists(unit) then
        OnPlateAdded(unit)
      end
    end

  -- Zoning rebuilds the nameplate world, and entering a key is also where aura
  -- secrecy flips on.
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Before anything else: the user should get the choice to unload while
    -- the addon has still done nothing they did not ask for.
    C_Timer.After(2, function()
      if NS.ShowFirstRunWarning then pcall(NS.ShowFirstRunWarning) end
    end)
  -- Spec data is often not ready at login, so the first resolve can land on the
  -- character key even with spec scope on. Corrected here.
    C_Timer.After(0.5, function()
      if not NS.RefreshProfile("entering world") then
        Reapply("entering world")
      end
  -- Once, and only to someone whose Default actually held something. Otherwise
  -- the rename is invisible and "my Default is empty" reads as data loss.
      if NS.pendingProfileNotice then
        local retired = NS.pendingProfileNotice
        NS.pendingProfileNotice = nil
        NS.Print(("your old Default profile was kept as |cff55dd55%s|r, and your characters still use it. |cffffcc00Default|r is now empty, so new characters start clean.")
          :format(retired))
      end
    end)

  -- Which spell IDs you actually have changes with spec and talents --
  -- switching spec appeared to break colouring until a /reload. Neither event
  -- changes a rule's debuffs, so no rebuild.
  elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
    -- Re-find health bars, not just re-gate: targeting a unit can make its
    -- addon swap in a different bar frame, leaving our rig on the frame that
    -- just stopped being drawn. ReapplyGating only ever asked "should this be
    -- enabled", never "is this still the right bar". Gated on the bar actually
    -- having changed, so it is a no-op for addons that keep one bar.
    ResyncSwappedBars(false)
    ReapplyGating()

  elseif event == "PLAYER_SPECIALIZATION_CHANGED"
      or event == "ACTIVE_TALENT_GROUP_CHANGED"
      or event == "TRAIT_CONFIG_UPDATED" then
    rebuildPending = true
    -- Cast-to-aura mapping comes from the Cooldown Manager, whose contents
    -- change with spec and talents.
    if NS.WipeRelatedCache then NS.WipeRelatedCache() end
  -- Delayed: the spec API still reports the OLD spec for a moment, so
  -- resolving now would load the profile you just left.
    C_Timer.After(0.5, function()
      if not NS.RefreshProfile("spec change") then
        Reapply("spec/talents")
      end
    end)

  elseif event == "ADDON_LOADED" and arg1 == "PlateTweaks" then
    eventFrame:UnregisterEvent("ADDON_LOADED")
    NS.InitializeConfig()
    activeKey = NS.ProfileKey()
    -- Registered once, for the session. The handlers gate themselves on the
    -- setting, because tooltip post-calls cannot be removed once added.
    if NS.SetupTweaks then pcall(NS.SetupTweaks) end

  -- Slot detection lives in Tints.lua, on the container it is about to use.
  -- Probing here was too early and cached "unavailable" for the session.
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
  end
end)
eventFrame:RegisterEvent("ADDON_LOADED")

  -- Backstop. Every trigger above is an event that MIGHT not fire -- a rebuild
  -- queued in combat that ends without PLAYER_REGEN_ENABLED reaching us, a
  -- plate that arrived while the config was loading. One boolean a second.
C_Timer.NewTicker(1.0, function()
  if not NS.db then return end
  if rebuildPending and NS.CanBuild() then
    Reapply("pending rebuild")
  elseif NS.colorPending and not InCombatLockdown() then
    NS.ApplyTintColors()
  end
  -- Plates whose bar we could not find -- restricted, or just lost the retry
  -- race. Retried regardless of restriction state.
  -- Snapshot, same reason as the regen handler: OnPlateAdded clears the key
  -- and may re-add it.
  local retry = {}
  for unit in pairs(pendingUnits) do retry[#retry + 1] = unit end
  for _, unit in ipairs(retry) do
    if UnitExists(unit) then
      OnPlateAdded(unit)
    else
      pendingUnits[unit] = nil
    end
  end
  -- Backstop for bar swaps with no event. Same identity check, so it stays
  -- free for addons that never swap.
  ResyncSwappedBars(true)
end)

  -- Covers are painted to match the host bar, whose colour changes with threat
  -- and unit type. A handful of GetStatusBarColor reads.
C_Timer.NewTicker(0.25, function()
  if not NS.db then return end
  -- Without this the tick walked every rig and rule to find nothing to do.
  if not NS.AnyCovers() then return end
  for _, rig in pairs(rigs) do
    -- Bound only: a cover repaints to match a bar nothing is displaying.
    if rig.unit then NS.UpdateCovers(rig) end
  end
end)

-- rule.missingCombatOnly has no config event to hook -- a target enters or
-- leaves combat with nothing in the settings changing -- so it is polled.
-- UnitAffectingCombat is plain, so this is a genuine per-unit check.
--
-- Walked only while at least one missing rule uses the option.
local function AnyMissingCombatOnly()
  local tints = NS.db.tints or {}
  for _, rule in ipairs(tints.rules or {}) do
    if rule.showWhenMissing and rule.missingCombatOnly then return true end
  end
  -- Border rules keep their own list. Left out here, a combat-gated missing
  -- BORDER was evaluated once at build time and never polled again, so the
  -- option silently did nothing for it.
  for _, rule in ipairs(tints.borderRules or {}) do
    if rule.showWhenMissing and rule.missingCombatOnly then return true end
  end
  return false
end

C_Timer.NewTicker(0.25, function()
  if not NS.db then return end
  if AnyMissingCombatOnly() then
    for _, rig in pairs(rigs) do
      -- Bound rigs only. Health bars are pooled and rigs are keyed by the bar,
      -- so a dungeon accumulates rigs for bars no plate is using -- 25 rigs
      -- for 6 plates was measured in a key. An unbound rig has its containers
      -- disabled already and nothing on screen, so gating it is pure waste at
      -- 4Hz, and the waste grows for the whole run.
      if rig.unit then
        -- Either shape. missingLadder alone missed a profile whose only
        -- missing rules are borders: that ladder is empty, so the gate was
        -- never polled.
        local hasLadder = rig.missingLadder and #rig.missingLadder > 0
        local hasDisplace = #((rig.missingDisplace or {}).entries or {}) > 0
        if (hasLadder or hasDisplace) and NS.UpdateMissingCombatGate then
          NS.UpdateMissingCombatGate(rig)
        end
      end
    end
  end
  -- Missing Debuffs icons have their own per-entry gate. Separate from
  -- AnyMissingCombatOnly: the two features are independent, and neither should
  -- force the other's walk across every rig.
  if NS.AnyMissingIconsCombatOnly and NS.AnyMissingIconsCombatOnly() then
    for _, rig in pairs(rigs) do
      -- Bound only, same reason as above.
      if rig.unit and rig.missingGated and #rig.missingGated > 0
        and NS.UpdateMissingIconsCombatGate then
        NS.UpdateMissingIconsCombatGate(rig)
      end
    end
  end
end)


SLASH_PLATETWEAKS1 = "/platetweaks"
SLASH_PLATETWEAKS2 = "/pt"
-- Old names kept working: muscle memory outlives a rename.
SLASH_PLATETWEAKS3 = "/bp"
SLASH_PLATETWEAKS4 = "/bplates"
-- Read-only state dump. Usable in combat and inside a key, where the options
-- window refuses to open. Touches only our own tables, so it cannot taint.

-- A unit name safe to put in a string.
--
-- UnitName is SECRET inside an instance, and a secret reaching string.format
-- makes the entire result secret -- which then throws the moment anything
-- indexes it. That is exactly how /pt layers died in a key: the header line
-- interpolated the target's name, so the one command most needed in a dungeon
-- was the one that could not run in one.
--
-- Declared ABOVE NS.CollectDiagnostics, not just above the printers: that
-- function uses it too, and a local declared after its caller resolves to a
-- nil global -- which is how /pt status broke.
local function PlainName(unit, fallback)
  local ok, name = pcall(UnitName, unit)
  if ok and name ~= nil and not (issecretvalue and issecretvalue(name)) then
    return name
  end
  return fallback or "(secret)"
end

-- Everything /pt status knows, as data. Split out so the Diagnostics page and
-- the slash command cannot drift apart.
function NS.CollectDiagnostics()
  local plates = C_NamePlate.GetNamePlates() or {}
  local info = {
    profile = tostring(NS.ProfileKey and NS.ProfileKey() or "?"),
    inCombat = InCombatLockdown() and true or false,
    restricted = NS.IsRestricted() and true or false,
    plates = #plates,
    rigged = 0,
    bound = 0,
    pending = 0,
    skipped = NS.SkippedPlates(),
    unknown = NS.UnknownPlates(),
    repairs = NS.RigRepairs(),
    errored = 0,
    firstError = nil,
    rules = {},
    textures = 0,
    containers = 0,
  }

  for _, rig in pairs(rigs) do
    info.rigged = info.rigged + 1
    if rig.unit then info.bound = info.bound + 1 end
    if rig.buildErrors and #rig.buildErrors > 0 then
      info.errored = info.errored + 1
      info.firstError = info.firstError or rig.buildErrors[1]
    end
    for _, record in ipairs(rig.rules or {}) do
      info.textures = info.textures
        + #(record.tints or {}) + #(record.underlays or {})
        + #(record.borders or {}) + #(record.pandemics or {})
        + #(record.missingCovers or {})
      info.containers = info.containers + #(record.containers or {})
    end
  -- Displacement entries are not in rig.rules, so their cost has to be added
  -- explicitly or the totals report the occlusion figure in both modes.
    for _, entry in ipairs((rig.missingDisplace or {}).entries or {}) do
      -- Container plus its pooled buttons -- see the same sum in PrintPerf.
      info.containers = info.containers + 1 + (entry.buttons or 0)
      -- Per entry, not a flat two: a border entry carries four edges plus its
      -- mask where a wash carries one plus its mask.
      info.textures = info.textures + (entry.textures or 2)
      info.missingDisplace = (info.missingDisplace or 0) + 1
      if entry.kind == "border" then
        info.missingBorderDisplace = (info.missingBorderDisplace or 0) + 1
      end
    end
  -- Max, not sum: every rig drops the same rules for the same reason, so this
  -- is a property of the config, not of any one plate.
    info.missingBorderSkipped =
      math.max(info.missingBorderSkipped or 0, rig.missingBorderSkipped or 0)
    info.missingBorderIncomplete =
      math.max(info.missingBorderIncomplete or 0, rig.missingBorderIncomplete or 0)
    info.borderRulesOff =
      math.max(info.borderRulesOff or 0, rig.borderRulesOff or 0)
  end

  for _ in pairs(pendingUnits) do info.pending = info.pending + 1 end

  -- One entry per rule from a single representative rig. Every rig builds the
  -- same rules, so walking them all would just repeat this N times.
  for _, rig in pairs(rigs) do
    for index, record in ipairs(rig.rules or {}) do
      local flags = {}
      if record.unsupported then table.insert(flags, "UNSUPPORTED") end
      if record.inert then table.insert(flags, "INERT") end
      if record.truncated then table.insert(flags, "TRUNCATED") end
      if record.blocked then table.insert(flags, "BLOCKED") end
      -- Ladder only. lever says which mechanism the combat gate settled on
      -- (shown = cheap, enabled = re-initialises buttons); reinit counts
      -- buttons that came back through initializeFrame after being built. A
      -- climbing reinit is the gate churning; anything above zero on the
      -- shown lever means something else is re-initialising.
      if record.gateLever then
        table.insert(flags, "lever=" .. tostring(record.gateLever))
      end
      if record.reinits and record.reinits > 0 then
        table.insert(flags, ("reinit=%d"):format(record.reinits))
      end
      if record.failures and record.failures > 0 then
        table.insert(flags, ("failures=%d"):format(record.failures))
      end
      -- Per condition, because the counts below cannot distinguish a rule
      -- that works from one that will never light. The chain is built from
      -- pooled buttons the moment the plate exists, so a wrong or untalented
      -- spell ID produces byte-identical numbers to a correct one -- it just
      -- never matches. A rule needs EVERY condition to land, so one bad ID in
      -- three is a silent total failure, and nothing reported it.
      --
      -- CanApplyAura is the same test the gateUnknownSpells option uses. As
      -- advice it is free; as a gate it silently DROPS rules, which is why
      -- that option is opt-in and this is not.
      local conditionList = {}
      for _, condition in ipairs((record.rule or {}).conditions or {}) do
        local id = condition.spellID
        local known = true
        if id and NS.CanApplyAura then
          local okKnown, value = pcall(NS.CanApplyAura, id)
          if okKnown then known = value and true or false end
        end
        conditionList[#conditionList + 1] =
          { spellID = id, name = id and NS.SpellName(id) or "?", known = known }
      end

      table.insert(info.rules, {
        index = index,
        conditions = record.spellCount or 0,
        conditionList = conditionList,
        hosts = #(record.hosts or {}),
        -- Containers rather than masks: a combo rule is a CHAIN, and the
        -- container count is what says how much of it got attached.
        containers = #(record.containers or {}),
        combos = record.combos or 0,
        tints = #(record.tints or {}),
        borders = #(record.borders or {}),
        flags = flags,
        lastError = record.lastError,
      })
    end
    break
  end

  -- What was found on the current target specifically -- the question /pt bar
  -- answers when one plate misbehaves and everything else looks healthy.
  if UnitExists("target") then
    local target = { name = PlainName("target", "target") }
    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    if not nameplate then
      target.note = "no nameplate on screen"
    else
      local healthBar = NS.FindHealthBar(nameplate)
      if not healthBar then
        target.note = "no health bar found by any adapter"
      else
        target.bar = tostring(healthBar)
        -- NS.IsPlaterBar means "flat-pinned to the bar's own frame level",
        -- true for two different reasons: real Plater, and tagged default
        -- Blizzard bars. Reported separately so "flat pin: yes" on a default
        -- plate does not read as "thinks this is Plater".
        target.isPlater = healthBar.unitName ~= nil
        target.isDefaultBlizzard = healthBar.ptDefaultBlizzardBar == true
        target.flatPinned = NS.IsPlaterBar and NS.IsPlaterBar(healthBar) or false
        local okLevel, level = pcall(healthBar.GetFrameLevel, healthBar)
        target.frameLevel = okLevel and level or nil
        local rig = rigs[healthBar]
        if not rig then
          target.note = "health bar found, but no rig built for it"
        else
          target.rigged = true
          target.baseLevel = rig.baseLevel
          local shown, total, secret = 0, 0, 0
          for _, record in ipairs(rig.rules or {}) do
            for _, tex in ipairs(record.tints or {}) do
              total = total + 1
              local okShown, isShown = pcall(tex.IsShown, tex)
              if okShown then
                -- A texture under a secret aura button can report a SECRET
                -- IsShown, and testing that throws. issecretvalue must gate
                -- every use of it, never follow one.
                if issecretvalue and issecretvalue(isShown) then
                  secret = secret + 1
                elseif isShown then
                  shown = shown + 1
                end
              end
            end
          end
          target.tintsShown, target.tintsTotal, target.tintsSecret = shown, total, secret
        end
      end
    end
    info.target = target
  end

  return info
end

local function PrintStatus()
  local info = NS.CollectDiagnostics()

  NS.Print(("profile %s | combat %s | auras secret %s")
    :format(info.profile,
      info.inCombat and "yes" or "no",
      info.restricted and "yes" or "no"))
  -- nil means no rig has been built yet, which is different from "off".
  local slotState
  if NS.db.useAuraSlots == false then
    slotState = "|cffffcc00off (turned off)|r -- 10 per rule, 100 per combo"
  elseif NS.slotApiPresent == true then
    slotState = "|cff55dd55on|r -- 1 texture per rule"
  elseif NS.slotApiPresent == false then
    slotState = "|cffffcc00unavailable on this client|r -- 10 per rule, 100 per combo"
  else
    -- Not "no rig built": there can be plenty. Slot support is probed on the
    -- first CONTAINER, and a profile whose only rules are missing-debuff ones
    -- builds no presence containers at all -- so this stays unanswered while
    -- everything works. Saying "no rig built" next to "rigged 25" just reads
    -- as a bug.
    slotState = "|cff808080not probed yet|r -- no presence rule has built a container"
  end
  NS.Print(("aura slots: %s"):format(slotState))
  -- Named on every status dump, because it changes what the missing rules
  -- COST as well as how they work -- a perf number is not comparable between
  -- the two modes without knowing which one produced it.
  do
    local mode = (NS.db.tints and NS.db.tints.missingMode) or "displace"
    NS.Print(("missing mode: %s"):format(mode == "displace"
      and "|cffffcc00displace|r -- 10-button pool per missing rule"
      or "|cff55dd55occlude|r -- 1 slot per missing rule"))
  end
  NS.Print(("plates %d | rigged %d | bound %d | no health bar %d | friendly skipped %d | hostility unknown %d")
    :format(info.plates, info.rigged, info.bound, info.pending, info.skipped, info.unknown or 0))
  -- Only when it has happened. A zero here is the normal case and would just
  -- be another number to scroll past in a bug report.
  if (info.repairs or 0) > 0 then
    local cap = (NS.db.tints and NS.db.tints.maxRigRepairs) or 1
    NS.Print(("rigs rebuilt after a bad build: %d (built in combat, or a container was refused; cap %d)")
      :format(info.repairs, cap))
  end
  if info.errored > 0 then
    NS.Print(("build errors on %d rig(s): %s"):format(info.errored, tostring(info.firstError)))
  end

  for _, rule in ipairs(info.rules) do
    local flags = #rule.flags > 0 and (" " .. table.concat(rule.flags, " ")) or ""
    NS.Print(("rule %d: %d cond | hosts %d | containers %d | combos %d | tints %d | borders %d%s")
      :format(rule.index, rule.conditions, rule.hosts, rule.containers,
        rule.combos, rule.tints, rule.borders, flags))
    -- One line for the whole chain: an ID nobody recognises is the single
    -- most common reason a rule that reports healthy shows nothing.
    if #(rule.conditionList or {}) > 0 then
      local parts, anyMissing = {}, false
      for _, condition in ipairs(rule.conditionList) do
        if condition.known then
          parts[#parts + 1] = ("%s |cff808080(%d)|r"):format(condition.name, condition.spellID)
        else
          anyMissing = true
          parts[#parts + 1] = ("|cffff8800%s (%d) NOT KNOWN|r"):format(condition.name, condition.spellID)
        end
      end
      NS.Print("  cond: " .. table.concat(parts, " |cff808080+|r "))
      if anyMissing then
        NS.Print("  |cffff8800every condition has to land for this rule to draw -- one ID you cannot apply means it never will|r")
      end
    end
    if rule.lastError then
      NS.Print("  first error: " .. rule.lastError)
    end
  end
  -- Missing rules in displace mode are absent from the list above -- they own
  -- no tints or borders, so they never became records. Counted separately
  -- rather than left out, since "my missing rules are missing from /pt status"
  -- reads as them not being built at all.
  if info.missingDisplace and info.missingDisplace > 0 then
    local borders = info.missingBorderDisplace or 0
    NS.Print(("missing rules (displace): %d built across all plates (%d border) | see |cffffff00/pt bar|r for per-rule state")
      :format(info.missingDisplace, borders))
  end
  -- Loud on purpose. A missing BORDER rule cannot exist in occlusion mode --
  -- there is no replica of the host addon's border art to cover it with -- so
  -- it is dropped at build time, and without saying so the only symptom is a
  -- rule in the options window that never does anything.
  if (info.missingBorderSkipped or 0) > 0 then
    NS.Print(("|cffff8800%d missing border rule(s) not built|r -- %s")
      :format(info.missingBorderSkipped,
        NS.MissingModeIsDisplace()
          and ("only " .. tostring(NS.MAX_MISSING_BORDER_RULES) .. " fit the border sublevel budget")
          or "missing borders need |cffffff00/pt missingmode displace|r"))
  end
  -- Reported apart from the budget line above: "you have too many" and "this
  -- one has no debuff yet" are different problems with different fixes, and
  -- rolling them together sent people looking for a cap they had not hit.
  -- Before the per-rule lines below: with the module off none of those can
  -- fire, so this is the only thing that would be said at all.
  if (info.borderRulesOff or 0) > 0 then
    NS.Print(("|cffff8800Border Coloring is OFF|r -- %d border rule(s) not built. Switch it on at the Border Coloring heading in |cffffff00/pt|r.")
      :format(info.borderRulesOff))
  end
  if (info.missingBorderIncomplete or 0) > 0 then
    NS.Print(("|cffff8800%d missing border rule(s) incomplete|r -- no debuff picked, or the border itself is off")
      :format(info.missingBorderIncomplete))
  end
end

-- For "the rig says it built tints but nothing is visible": dumps the health
-- bar, its frame level, and every tint texture's actual on-screen state,
-- rather than the counts /pt status already gives.
local function PrintBarDebug()
  if not UnitExists("target") then
    NS.Print("no target")
    return
  end
  local nameplate = C_NamePlate.GetNamePlateForUnit("target")
  if not nameplate then
    NS.Print("target has no nameplate on screen")
    return
  end
  -- unitRigs is keyed by the NAME_PLATE_UNIT_ADDED token (e.g. "nameplate3"),
  -- never literally "target" -- go through the health bar instead, which is
  -- what `rigs` is actually keyed by, so this works regardless of which
  -- token the plate is currently bound under.
  local healthBar = NS.FindHealthBar(nameplate)
  if not healthBar then
    NS.Print("target's nameplate: no health bar found by any adapter")
    return
  end
  local rig = rigs[healthBar]
  if not rig then
    -- Neither nameplate.namePlateUnitToken nor the GetNamePlates() list is
    -- reliable here (both came back empty/nil in testing) -- resolve against
    -- activeUnits, which NAME_PLATE_UNIT_ADDED populates directly.
    local token
    for u in pairs(activeUnits) do
      if UnitExists(u) and UnitIsUnit(u, "target") then
        token = u
        break
      end
    end
    local okAttack, canAttack = pcall(UnitCanAttack, "player", token or "target")
    NS.Print(("target's health bar found (%s), but no rig built for it | token %s | UnitCanAttack %s%s"):format(
      tostring(healthBar), tostring(token),
      tostring(okAttack and canAttack),
      (issecretvalue and okAttack and issecretvalue(canAttack)) and " (SECRET)" or ""))
    NS.Print(("  unit exists %s | reaction %s | classification %s | in pendingUnits %s"):format(
      tostring(token and UnitExists(token)),
      tostring(token and UnitReaction("player", token)),
      tostring(token and UnitClassification(token)),
      tostring(token and pendingUnits[token] or false)))
    -- Does ANY already-bound rig belong to this same target -- just pointed
    -- at a stale health bar object? If so, the two %s tables below will be
    -- different addresses, and that is the bar-swap theory confirmed: the
    -- rig that exists was built for a bar Platynator has since replaced.
    local staleRig, staleUnit
    for u, r in pairs(unitRigs) do
      if UnitExists(u) and UnitIsUnit(u, "target") then
        staleRig, staleUnit = r, u
        break
      end
    end
    if staleRig then
      NS.Print(("  BUT unitRigs has a rig for this target already, under token %s, healthBar %s -- stale/orphaned reference, not a fresh miss"):format(
        tostring(staleUnit), tostring(staleRig.healthBar)))
    else
      NS.Print("  and no rig anywhere is bound to this target under any token either")
    end
    return
  end
  if rig.outline then
    local okOut, outLevel = pcall(rig.outline.GetFrameLevel, rig.outline)
    -- Everything read off an aura button has to survive being SECRET. The
    -- first version used the strata as a table key and threw "cannot be
    -- indexed with secret keys" -- which is itself part of the answer.
    local function Describe(value)
      if value == nil then return "nil" end
      if issecretvalue and issecretvalue(value) then return "|cffffcc00secret|r" end
      return tostring(value)
    end

    local okStrata, outStrata = pcall(rig.outline.GetFrameStrata, rig.outline)
    local highest, where, hiStrata = -1, "?", "nil"
    local secretStrata, readableStrata = 0, 0
    -- Per rule AND per group -- "2 secret" alone doesn't say WHICH rule's
    -- containers they belong to, or whether it is the AuraContainer frame
    -- (irrelevant to what's drawn) or the actual button the tint is on
    -- (tintHosts -- the only one that matters for what you see).
    local secretByRule = {}
    for index, record in ipairs(rig.rules or {}) do
      for name, group in pairs({ containers = record.containers, hosts = record.hosts,
                                 tintHosts = record.tintHosts }) do
        for _, host in ipairs(group or {}) do
          local okS, hostStrata = pcall(host.GetFrameStrata, host)
          if okS and issecretvalue and issecretvalue(hostStrata) then
            secretStrata = secretStrata + 1
            local key = index .. ":" .. name
            secretByRule[key] = (secretByRule[key] or 0) + 1
          elseif okS then
            readableStrata = readableStrata + 1
          end
          local okH, hostLevel = pcall(host.GetFrameLevel, host)
          if okH and type(hostLevel) == "number" and hostLevel > highest then
            highest, where = hostLevel, ("rule %d %s"):format(index, name)
            hiStrata = okS and Describe(hostStrata) or "refused"
          end
        end
      end
    end

    NS.Print(("plate border: strata %s level %s"):format(
      Describe(okStrata and outStrata or nil), okOut and tostring(outLevel) or "refused"))
    if highest < 0 then
      -- No presence rules at all. Normal for a profile whose rules are all
      -- missing-debuff ones, and "strata nil level -1 (?)" read like a fault.
      NS.Print("  no presence rule frames -- this profile's rules are all missing-debuff ones")
    else
      NS.Print(("  highest rule frame: strata %s level %s (%s)"):format(
        hiStrata, tostring(highest), where))
    end
    NS.Print(("  rule frames with a readable strata: %d | secret: %d"):format(
      readableStrata, secretStrata))
    for key, count in pairs(secretByRule) do
      NS.Print(("  rule %s: %d frame(s) with secret strata"):format(key, count))
    end
  end

  NS.Print(("healthBar: %s | frameLevel %s | strata %s | pinned flat %s | rig.baseLevel %s"):format(
    tostring(healthBar and healthBar:GetName() or healthBar),
    tostring(healthBar and healthBar:GetFrameLevel()),
    tostring(healthBar and healthBar.GetFrameStrata and healthBar:GetFrameStrata()),
    tostring(healthBar and NS.IsPlaterBar and NS.IsPlaterBar(healthBar)),
    tostring(rig.baseLevel)))
  local adapterName = NS.HostName(healthBar)
  local overrides = (NS.db.adapters or {})[adapterName]
  local tuned = {}
  for key in pairs(overrides or {}) do tuned[#tuned + 1] = key end
  table.sort(tuned)
  NS.Print(("  adapter: |cff55dd55%s|r%s"):format(adapterName,
    #tuned > 0
      and (" |cffffcc00(overridden: %s)|r"):format(table.concat(tuned, ", "))
      or ""))

  -- Ground truth for the sublevel arithmetic: where Plater's OWN text
  -- actually sits, read directly off the object rather than re-derived.
  -- healthBar.unitName is a plain FontString Plater owns outright -- never
  -- secret -- so this is safe to read unconditionally.
  if healthBar and healthBar.unitName then
    local okTextLayer, textLayer, textSublevel = pcall(healthBar.unitName.GetDrawLayer, healthBar.unitName)
    local okFloor, floor = pcall(NS.PlaterTextFloor, healthBar)
    NS.Print(("plater name text: layer %s sublevel %s | NS.PlaterTextFloor() says %s"):format(
      okTextLayer and tostring(textLayer) or "?", okTextLayer and tostring(textSublevel) or "?",
      okFloor and tostring(floor) or "?"))
  end

  -- The default-Blizzard equivalent, and a real question: flat-pinning to
  -- healthBar's own level only keeps the tint below the name text if
  -- healthBar's level is already below unitFrame's. If Blizzard draws the fill
  -- at or above its own container, flat-pinning changed nothing. Never
  -- measured before shipping that fix.
  if healthBar and healthBar.ptDefaultBlizzardBar and nameplate and nameplate.UnitFrame then
    local unitFrame = nameplate.UnitFrame
    local okUL, unitLevel = pcall(unitFrame.GetFrameLevel, unitFrame)
    local okHL, healthLevel = pcall(healthBar.GetFrameLevel, healthBar)
    NS.Print(("default plate: unitFrame level %s | healthBar level %s | %s"):format(
      okUL and tostring(unitLevel) or "?", okHL and tostring(healthLevel) or "?",
      (okUL and okHL and healthLevel > unitLevel)
        and "|cffff4040healthBar is ABOVE unitFrame -- flat-pin cannot help|r"
        or "healthBar is not above unitFrame"))
    -- Any FontString living directly on unitFrame is a candidate for the
    -- name text -- same scan NS.PlaterTextFloor already does for Plater,
    -- just aimed at the frame that actually owns this text on default plates.
    local okRegions, regions = pcall(function() return { unitFrame:GetRegions() } end)
    if okRegions then
      for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
          -- A unit's name can itself be secret under 12.1 -- issecretvalue
          -- has to gate this exactly like every other secret-prone read in
          -- this file, before the value is ever tested or formatted.
          local okText, text = pcall(region.GetText, region)
          local shown
          if not okText then
            shown = "refused"
          elseif issecretvalue and issecretvalue(text) then
            shown = "secret"
          elseif text and text ~= "" then
            shown = text
          else
            shown = "?"
          end
          -- The number that decides it: both frames sit at the same level, so
          -- ordering falls entirely to sublevel -- and NS.PlaterTextFloor has
          -- only ever looked at healthBar's regions, never unitFrame's.
          local okDL, drawLayer, sublevel = pcall(region.GetDrawLayer, region)
          NS.Print(("  unitFrame fontstring: %s (owner level %s | layer %s sublevel %s)"):format(
            shown, okUL and tostring(unitLevel) or "?",
            okDL and tostring(drawLayer) or "?", okDL and tostring(sublevel) or "?"))
        end
      end
    end
  end

  -- Any of these can come back SECRET: they are read off a texture or frame
  -- under a secret aura button, and tostring() on one throws exactly like a
  -- boolean test does. Alpha, size and level are as unsafe as shown.
  local function DescribeField(ok, value)
    if not ok then return "refused" end
    if value == nil then return "nil" end
    if issecretvalue and issecretvalue(value) then return "secret" end
    return tostring(value)
  end

  -- Rank 1's missing wash -- never dumped before, even though it lives on
  -- OUR OWN frame (healthBar.ptMissingWash), not a secure aura button, so
  -- none of this should ever come back refused or secret. If it does, that
  -- itself is the finding.
  if rig.missingWash then
    local frame = rig.missingWash
    local okFShown, fShown = pcall(frame.IsShown, frame)
    local okFLevel, fLevel = pcall(frame.GetFrameLevel, frame)
    NS.Print(("missing wash frame: shown %s | level %s"):format(
      DescribeField(okFShown, fShown), DescribeField(okFLevel, fLevel)))
    if frame.wash then
      local tex = frame.wash
      local okShown, shown = pcall(tex.IsShown, tex)
      local okAlpha, alpha = pcall(tex.GetAlpha, tex)
      local okDL, drawLayer, sublevel = pcall(tex.GetDrawLayer, tex)
      NS.Print(("  wash tex: shown %s | alpha %s | layer %s sublevel %s"):format(
        DescribeField(okShown, shown), DescribeField(okAlpha, alpha),
        DescribeField(okDL, drawLayer), DescribeField(okDL, sublevel)))
    else
      NS.Print("  wash tex: never created (frame.wash is nil)")
    end
    NS.Print(("  gate: missingGateOpen %s | LadderCombatAllows() %s"):format(
      tostring(rig.missingGateOpen), tostring(NS.LadderCombatAllows and NS.LadderCombatAllows(rig))))
  else
    NS.Print("missing wash frame: none (rig.missingWash is nil)")
  end

  -- Displacement-mode missing rules. They are deliberately NOT in rig.rules
  -- -- they own no tints, borders or covers, only a wash each -- so without
  -- this they would be invisible to every diagnostic in this file.
  local displace = rig.missingDisplace
  if displace then
    NS.Print(("missing displace: %d entr(ies) | failures %d"):format(
      #(displace.entries or {}), displace.failures or 0))
    for _, entry in ipairs(displace.entries or {}) do
      local okShown, holderShown = pcall(entry.holder.IsShown, entry.holder)
      -- A border entry has no wash -- four edge textures ride the mask
      -- instead -- so the first edge stands in for it. Indexing entry.wash
      -- unguarded here errored on the border entries rather than reporting
      -- them, which is the one thing a diagnostic must not do.
      local painted = entry.wash or (entry.borders or {})[1]
      local okWash, washShown = false, nil
      if painted then okWash, washShown = pcall(painted.IsShown, painted) end
      local condition = (entry.rule.conditions or {})[1]
      NS.Print(("  rank %d (%s): spell %s | pooled buttons %d | combatOnly %s | holder shown %s | painted shown %s"):format(
        entry.rank, entry.kind or "wash", tostring(condition and condition.spellID),
        entry.buttons or 0,
        tostring(entry.rule.missingCombatOnly and true or false),
        tostring(okShown and holderShown), tostring(okWash and washShown)))
    end
  end

  -- Missing Debuffs (the displacing icon module, MissingIcons.lua) -- a
  -- separate mechanism from the wash above, with its own per-entry combat
  -- gate rather than one shared ladder-wide gate. Never dumped before.
  if rig.missingFrame then
    NS.Print(("missing icons: containers %d | entries gated %d"):format(
      #(rig.missingContainers or {}), #(rig.missingGated or {})))
    if rig.missingGated and #rig.missingGated > 0 then
      -- Ground truth, read directly rather than trusted from the gate's own
      -- bookkeeping -- UnitAffectingCombat is plain, not secret, so this is
      -- a real answer, not an inference.
      local unitCombat = rig.unit and UnitAffectingCombat(rig.unit)
      local playerCombat = UnitAffectingCombat("player")
      NS.Print(("  unit in combat %s | player in combat %s"):format(
        tostring(unitCombat and true or false), tostring(playerCombat and true or false)))
      for _, item in ipairs(rig.missingGated) do
        local okShown, chipShown = pcall(item.chip.IsShown, item.chip)
        NS.Print(("  entry %s: allowed %s | chip shown %s"):format(
          tostring(item.entry and item.entry.spellID),
          tostring(item.allowed), tostring(okShown and chipShown)))
      end
    end
  else
    NS.Print("missing icons: none built (rig.missingFrame is nil)")
  end

  for index, record in ipairs(rig.rules or {}) do
    if #(record.tints or {}) > 0 or #(record.hosts or {}) > 0 then
      NS.Print(("rule %d: recordLevel %s | hosts %d | tints %d"):format(
        index, tostring(record.level), #(record.hosts or {}), #(record.tints or {})))
      for ti, tex in ipairs(record.tints) do
        local okShown, shown = pcall(tex.IsShown, tex)
        local okAlpha, alpha = pcall(tex.GetAlpha, tex)
        local okW, w = pcall(tex.GetWidth, tex)
        local okH, h = pcall(tex.GetHeight, tex)
        -- GetParent itself can be refused while tainted, not just the reads
        -- made off what it returns, so the pcall has to wrap the fetch.
        -- `okOwner and pcall(...)` would truncate to one return and lose the
        -- value even on success, hence the branch.
        local okOwner, owner = pcall(tex.GetParent, tex)
        local okLevel, level, okOwnerShown, ownerShown, okVisible, visible
        if okOwner then
          okLevel, level = pcall(owner.GetFrameLevel, owner)
          okOwnerShown, ownerShown = pcall(owner.IsShown, owner)
          okVisible, visible = pcall(owner.IsVisible, owner)
        else
          okLevel, okOwnerShown, okVisible = false, false, false
        end
        -- What actually decides who wins against Plater's name text once
        -- level and strata both match (see the secret-strata breakdown
        -- above): the draw layer and its sublevel.
        local okDL, drawLayer, sublevel = pcall(tex.GetDrawLayer, tex)
        NS.Print(("  tint %d: shown %s | alpha %s | size %sx%s | ownerLevel %s | ownerShown %s | ownerVisible %s | layer %s sublevel %s"):format(
          ti, DescribeField(okShown, shown), DescribeField(okAlpha, alpha),
          DescribeField(okW, w), DescribeField(okH, h), DescribeField(okLevel, level),
          DescribeField(okOwnerShown, ownerShown), DescribeField(okVisible, visible),
          DescribeField(okDL, drawLayer), DescribeField(okDL, sublevel)))
      end
    end
  end
end

-- What this addon costs, in the units that matter.
--
-- Lua CPU reads as ~0 -- almost nothing runs per frame. The cost is what the
-- engine renders and keeps resident, multiplied by every plate on screen, plus
-- a projection at full plate count.
-- Which adapter these commands act on.
--
-- The target's plate first, because that is the bar you are looking at when
-- something is wrong. Falling back to any bound rig means the command still
-- works with nothing targeted, which matters in a key.
local function CurrentAdapter()
  if UnitExists("target") then
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local bar = plate and NS.FindHealthBar(plate)
    if bar then return NS.HostName(bar), bar end
  end
  for bar, rig in pairs(rigs) do
    if rig.unit then return NS.HostName(bar), bar end
  end
  for bar in pairs(rigs) do return NS.HostName(bar), bar end
  return nil, nil
end

-- Short name to real config key, so the command reads like English and the
-- stored shape stays the one the engine uses.
local ADAPTER_ALIASES = {
  leveloffset   = "levelOffset",
  pinflat       = "pinFlat",
  edgeadjust    = "edgeAdjust",
  outlineoffset = "plateOutlineOffset",
}

-- Just the name, for callers outside this file. CurrentAdapter also returns
-- the bar, which nothing outside wants and which would be a stale reference
-- the moment the plate is recycled.
function NS.CurrentAdapterName()
  return (CurrentAdapter())
end

local function PrintAdapter(arg)
  local name, bar = CurrentAdapter()
  if not name or name == "unknown" then
    NS.Print("|cffff8800no nameplate to read|r -- target a mob, or wait for one to appear.")
    return
  end

  local word, value = arg:match("^(%a+)%s*(.-)%s*$")
  local key = word and ADAPTER_ALIASES[word]

  if word == "reset" then
    NS.db.adapters = NS.db.adapters or {}
    NS.db.adapters[name] = nil
    NS.RebuildAllRigs(true)
    NS.Print(("|cff55dd55%s|r reset to shipped values."):format(name))
  elseif key then
    local parsed
    if key == "pinFlat" then
      if value == "on" then parsed = true
      elseif value == "off" then parsed = false
      elseif value == "auto" or value == "" then parsed = nil
      else
        NS.Print("pinflat takes |cffffff00on|off|auto|r")
        return
      end
    else
      if value == "auto" or value == "" then
        parsed = nil
      else
        parsed = tonumber(value)
        if not parsed then
          NS.Print(("%s takes a number, or |cffffff00auto|r to inherit"):format(word))
          return
        end
      end
    end
    NS.SetAdapterSetting(name, key, parsed)
    NS.RebuildAllRigs(true)
    NS.Print(("|cff55dd55%s|r %s = %s"):format(name, word,
      parsed == nil and "auto (inherited)" or tostring(parsed)))
  elseif arg ~= "" then
    NS.Print("usage: |cffffff00/pt adapter [leveloffset|pinflat|edgeadjust|outlineoffset] <value|auto>|r")
    NS.Print("       |cffffff00/pt adapter reset|r")
    return
  end

  NS.Print(("|cff66ccffadapter|r |cff55dd55%s|r -- values in use on this plate:"):format(name))
  local per = (NS.db.adapters or {})[name] or {}
  -- Where each value CAME from, not just what it is. "2" is not actionable;
  -- "2, inherited from the global" tells you which knob to reach for.
  for _, item in ipairs({
    { "leveloffset", "levelOffset" },
    { "pinflat", "pinFlat" },
    { "edgeadjust", "edgeAdjust" },
    { "outlineoffset", "plateOutlineOffset" },
  }) do
    local shortName, realKey = item[1], item[2]
    local resolved = NS.AdapterSetting(bar, realKey)
    local source
    if per[realKey] ~= nil then
      source = "|cff55dd55set for this adapter|r"
    elseif (NS.ADAPTER_DEFAULTS[name] or {})[realKey] ~= nil then
      source = "shipped default for " .. name
    else
      source = "|cff808080inherited global|r"
    end
    NS.Print(("  %-14s %-8s %s"):format(shortName,
      resolved == nil and "auto" or tostring(resolved), source))
  end
end

-- Where the HOST draws, relative to where we draw.
--
-- Written because "colouring does not work on <addon>" has no answer from any
-- other command: /pt status proves our objects exist, and the numbers look
-- identical whether we are on top of the host's artwork or buried under it.
-- This is the one paste that settles it.
local function PrintLayers()
  local unit = UnitExists("target") and "target" or nil
  if not unit then
    NS.Print("|cffff8800/pt layers needs a target|r -- it reads that plate specifically.")
    return
  end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then NS.Print("no nameplate on screen for your target") return end
  local healthBar = NS.FindHealthBar(plate)
  if not healthBar then NS.Print("no health bar found by any adapter") return end

  -- Anything read off the host can come back secret in an instance, and a
  -- secret used in string.format throws. Everything here goes through this.
  local function Show(value)
    if value == nil then return "nil" end
    if issecretvalue and issecretvalue(value) then return "|cffffcc00secret|r" end
    return tostring(value)
  end
  local function Level(frame)
    local ok, value = pcall(frame.GetFrameLevel, frame)
    return ok and Show(value) or "refused"
  end
  local function Strata(frame)
    local ok, value = pcall(frame.GetFrameStrata, frame)
    return ok and Show(value) or "refused"
  end

  NS.Print(("|cff66ccfflayers|r on |cff55dd55%s|r via adapter |cff55dd55%s|r"):format(
    PlainName(unit, unit), NS.HostName(healthBar)))
  NS.Print(("  nameplate: level %s strata %s"):format(Level(plate), Strata(plate)))
  NS.Print(("  healthBar: level %s strata %s | pinned flat %s"):format(
    Level(healthBar), Strata(healthBar), tostring(NS.IsPlaterBar(healthBar))))

  -- The host's own regions ON the bar. A FontString here is why Plater is
  -- pinned flat; a TEXTURE at a high sublevel is what buries a tint.
  local hostTopOverlay = nil
  local okRegions, regions = pcall(function() return { healthBar:GetRegions() } end)
  if okRegions then
    local shown = 0
    for _, region in ipairs(regions or {}) do
      local okType, kind = pcall(region.GetObjectType, region)
      local okLayer, layer, sublevel = pcall(region.GetDrawLayer, region)
      if okType and okLayer then
        shown = shown + 1
        -- Across ALL regions, not just the twelve printed. Textures count as
        -- much as FontStrings: the host's OVERLAY decoration is just as
        -- capable of sitting over a tint as its name text is.
        if layer == "OVERLAY" and type(sublevel) == "number"
          and (hostTopOverlay == nil or sublevel > hostTopOverlay) then
          hostTopOverlay = sublevel
        end
        if shown <= 12 then
          NS.Print(("    host region: %s on %s sublevel %s"):format(
            Show(kind), Show(layer), Show(sublevel)))
        end
      end
    end
    if shown > 12 then
      NS.Print(("    ... and %d more host regions"):format(shown - 12))
    end
    if shown == 0 then NS.Print("    host draws no readable regions on the bar itself") end
  end

  -- Every host frame on the plate, and every FontString, with the level that
  -- carries it.
  --
  -- Sibling levels alone proved nothing useful: they say a frame exists, not
  -- what is drawn on it or how high the host's stack really goes. Platynator
  -- turned out to put its text widgets at 1010-1070 while its bar sits at 513,
  -- which no reading of the sibling list would have shown.
  --
  -- The healthBar subtree is skipped outright -- everything under it is OURS
  -- (containers, holders, the outline), and counting our own frames as the
  -- host's is how the first version of this produced a false alarm. Text the
  -- host draws ON the bar is already listed above, so Plater is still covered.
  -- The bar's own rectangle, so a host frame can be asked whether it actually
  -- covers it. A frame sitting above our stack but off to one side -- a cast
  -- bar, an icon row -- cannot hide a tint no matter how high it is, and
  -- reporting it as a suspect just sends people chasing the wrong frame.
  local textFrames, hostFrames = {}, {}
  local function ScanPlate(frame, depth)
    if depth > 3 or frame == healthBar then return end
    local okShown, isShown = pcall(frame.IsShown, frame)
    if not (okShown and isShown) then return end

    local okLevel, level = pcall(frame.GetFrameLevel, frame)
    local numericLevel = (okLevel and type(level) == "number") and level or nil

    -- Shown textures only. A hidden one cannot cover anything, and plate
    -- addons keep plenty around for modes you are not using.
    local paint = 0
    local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
    for _, region in ipairs(okRegions and regions or {}) do
      local okType, kind = pcall(region.GetObjectType, region)
      local okRShown, rShown = pcall(region.IsShown, region)
      if okType and kind == "Texture" and okRShown and rShown then
        paint = paint + 1
      end
    end
    if numericLevel then
      hostFrames[#hostFrames + 1] = { level = numericLevel, paint = paint }
    end

    for _, region in ipairs(okRegions and regions or {}) do
      local okType, kind = pcall(region.GetObjectType, region)
      if okType and kind == "FontString" and #textFrames < 10 then
        local okLayer, layer, sublevel = pcall(region.GetDrawLayer, region)
        local okText, text = pcall(region.GetText, region)
        local okRegionShown, regionShown = pcall(region.IsShown, region)
        -- A unit name is secret in an instance, and truncating a secret string
        -- throws -- so never touch it, just say what it is.
        local label = "?"
        if okText then
          if issecretvalue and issecretvalue(text) then
            label = "|cffffcc00secret|r"
          elseif type(text) == "string" then
            label = (#text > 18) and (text:sub(1, 18) .. "...") or text
            if label == "" then label = "(empty)" end
          else
            label = tostring(text)
          end
        end
        textFrames[#textFrames + 1] = {
          level = numericLevel,
          levelText = okLevel and Show(level) or "refused",
          layer = okLayer and Show(layer) or "refused",
          sublevel = okLayer and Show(sublevel) or "refused",
          shown = okRegionShown and regionShown and true or false,
          label = label,
        }
      end
    end

    local okKids, kids = pcall(function() return { frame:GetChildren() } end)
    for _, kid in ipairs(okKids and kids or {}) do
      ScanPlate(kid, depth + 1)
    end
  end
  pcall(ScanPlate, plate, 1)

  -- Tracked while printing: the gap check below needs the level the host's
  -- text starts at, to tell a frame that could cover the bar from one that is
  -- just text sitting harmlessly far above everything.
  local highestText = -1
  for _, item in ipairs(textFrames) do
    NS.Print(("    host text: level %s on %s sublevel %s | shown %s | %s"):format(
      item.levelText, item.layer, item.sublevel, tostring(item.shown), item.label))
    if item.shown and item.level and item.level > highestText then
      highestText = item.level
    end
  end
  if #textFrames == 0 then
    NS.Print("    no readable text anywhere on this plate")
  end

  local rig = rigs[healthBar]
  if not rig then NS.Print("  |cffff8800no rig on this bar|r") return end
  NS.Print(("  ours -- baseLevel %s | levelOffset %s"):format(
    tostring(rig.baseLevel), tostring(NS.db.levelOffset)))
  -- Called out separately because it is the LOWEST thing we draw and the only
  -- band a host frame just above the bar can get over.
  local missingBand = rig.baseLevel and (rig.baseLevel + (rig.missingLevelOffset or 0))
  if missingBand then
    NS.Print(("    missing band: level %d"):format(missingBand))
  end
  local topRule = -1
  for index, record in ipairs(rig.rules or {}) do
    NS.Print(("    rule %d: recordLevel %s"):format(index, tostring(record.level)))
    if type(record.level) == "number" and record.level > topRule then
      topRule = record.level
    end
  end
  if rig.outline then
    NS.Print(("    plate outline: level %s strata %s"):format(
      Level(rig.outline), Strata(rig.outline)))
  end

  -- On a flat-pinned bar every number above is the SAME by design, so none of
  -- it says who draws on top. Draw sublevel is what arbitrates, and it was
  -- never printed -- which made Plater and Blizzard undiagnosable from here.
  local flat = NS.IsPlaterBar(healthBar)
  if flat and NS.PlaterRankSublevels then
    local floor = NS.PlaterTextFloor and NS.PlaterTextFloor(healthBar) or 7
    NS.Print("  |cff66ccffpinned flat -- draw sublevel decides here, not frame level|r")
    NS.Print(("    text floor: %s (lowest OVERLAY FontString sublevel on the bar)"):format(
      tostring(floor)))
    for index = 1, #(rig.rules or {}) do
      local tint, under, cover = NS.PlaterRankSublevels(index, floor)
      NS.Print(("    rule %d: tint sublevel %d | underlay %d | cover %d"):format(
        index, tint, under, cover))
    end
    if hostTopOverlay then
      local ourTop = select(1, NS.PlaterRankSublevels(1, floor))
      -- Reported, NOT flagged.
      --
      -- Plater draws Textures up to OVERLAY 7 while our top tint sits at -3,
      -- and it works perfectly -- those are borders and decoration, not bar
      -- fill, so being under them costs nothing. Calling that a problem would
      -- send every Plater user chasing a healthy configuration, which is the
      -- same mistake the frame-level overlap check made.
      --
      -- The numbers are here because they matter when something IS wrong.
      -- Nothing here can decide that on its own.
      NS.Print(("    host's highest OVERLAY sublevel on the bar: %d | your top tint: %d"):format(
        hostTopOverlay, ourTop))
    end
  end

  -- The verdict. Compared against host FRAME levels, not against text levels:
  -- text sitting far above our whole stack is normal and harmless (we are not
  -- covering it and it is not covering us). What matters is a host frame
  -- INTERLEAVED with our bands, which can bury one rule while the rest work.
  -- The stack's top is the highest thing we draw -- which is the missing band
  -- itself when a profile has no presence rules. Keying this on topRule alone
  -- meant such a profile got no verdict at all: the section simply vanished,
  -- which reads as the check having passed rather than never having run.
  local stackTop = math.max(topRule, missingBand or -1)
  if missingBand and stackTop >= 0 then
    local interleaved, highestInterleaved, above, highestAbove = 0, -1, 0, -1
    for _, item in ipairs(hostFrames) do
      local level = item.level
      if level >= missingBand and level <= stackTop then
        interleaved = interleaved + 1
        if level > highestInterleaved then highestInterleaved = level end
      elseif level > stackTop then
        above = above + 1
        if level > highestAbove then highestAbove = level end
      end
    end
    if flat then
      -- Deliberately silent about frame levels here. Our whole stack occupies
      -- ONE level by design, so "a host frame is inside our stack" is true of
      -- every host frame on the bar and means nothing. The sublevel report
      -- above is the real answer for this mode.
      NS.Print("|cff808080frame-level overlap not checked -- everything is pinned to one level here|r")
    elseif interleaved > 0 then
      NS.Print(("|cffff8800%d host frame(s) sit INSIDE our stack (up to level %d)|r -- these can bury one band while the others work")
        :format(interleaved, highestInterleaved))
      if highestInterleaved >= missingBand then
        NS.Print(("  your missing band (level %d) is the exposed one"):format(missingBand))
      end
    else
      NS.Print("|cff55dd55no host frame sits inside our stack|r")
    end
    if above > 0 then
      -- The LEVELS, not just how many and how high.
      --
      -- "9 frames above, highest 1510" cannot be acted on. What matters is
      -- whether any of them sit in the gap between our stack and the host's
      -- text: those are the ones that could paint over the bar. Frames up with
      -- the text are almost certainly text themselves and harmless.
      --
      -- This matters in the OPEN WORLD specifically. Inside an instance our
      -- tint hosts report a secret strata that outranks readable frames, so
      -- nothing here can cover them. Out of an instance they are ordinary
      -- BACKGROUND frames and lose to any higher level in the same strata --
      -- which is why "works in keys, not in the world" is a real shape.
      -- Whether one of these actually COVERS the bar cannot be answered:
      -- position reads are refused on a nameplate in 12.1 (GetRect, GetLeft
      -- and GetCenter all throw; only GetWidth/GetHeight survive), so there
      -- is no way to intersect two rectangles here. Do not re-attempt it.
      --
      -- What is left is whether a frame above us has anything shown to paint
      -- with at all. A frame carrying no texture cannot hide a tint wherever
      -- it sits, so this still rules most of them out.
      local seen, distinct, suspects = {}, {}, {}
      for _, item in ipairs(hostFrames) do
        if item.level > stackTop and not seen[item.level] then
          seen[item.level] = true
          distinct[#distinct + 1] = item.level
        end
        if item.level > stackTop and item.paint > 0 then
          suspects[#suspects + 1] = item
        end
      end
      table.sort(distinct)
      local shown = {}
      for index = 1, math.min(8, #distinct) do shown[index] = tostring(distinct[index]) end
      NS.Print(("  %d host frame(s) draw above our whole stack: levels %s%s"):format(
        above, table.concat(shown, ", "),
        #distinct > 8 and (", ... up to " .. tostring(distinct[#distinct])) or ""))

      if #suspects > 0 then
        table.sort(suspects, function(a, b) return a.level < b.level end)
        local parts = {}
        for index = 1, math.min(5, #suspects) do
          parts[#parts + 1] = ("%d(%dtex)"):format(suspects[index].level, suspects[index].paint)
        end
        NS.Print(("  of those, %d carr%s shown textures: %s"):format(
          #suspects, #suspects == 1 and "ies" or "y", table.concat(parts, ", ")))
        NS.Print("  |cff808080whether any covers the bar cannot be read -- 12.1 refuses position on a nameplate|r")
      else
        NS.Print("  |cff55dd55none of them has a shown texture|r -- they cannot hide a tint")
      end
    end
  end

  NS.Print("|cff808080Rules must out-level the host artwork that covers the bar.|r")
  NS.Print("|cff808080If a sibling or region above sits over our recordLevels, try |r|cffffff00/pt pinflat on|r|cff808080.|r")
end

local function PrintPerf()
  local BUSY_PLATES = 40

  local rigCount = 0
  local totals = { containers = 0, textures = 0 }
  local rows = {}
  -- Displacement entries are not in rig.rules and keep their own rows.
  --
  -- Keyed by KIND and rank, ordered separately: wash and border entries are
  -- numbered independently and both start at rank 1. Keying on rank alone
  -- merged them and counted the same plate twice, halving every per-plate
  -- figure.
  local missingRows, missingOrder = {}, {}

  for _, rig in pairs(rigs) do
    rigCount = rigCount + 1
    for index, record in ipairs(rig.rules or {}) do
      local textures = #(record.tints or {}) + #(record.underlays or {})
        + #(record.borders or {}) + #(record.pandemics or {}) + #(record.missingCovers or {})
      local containers = #(record.containers or {})

      totals.textures = totals.textures + textures
      totals.containers = totals.containers + containers

      local row = rows[index] or { cond = record.spellCount or 0, textures = 0, containers = 0, plates = 0 }
      row.textures = row.textures + textures
      row.containers = row.containers + containers
      row.plates = row.plates + 1
      rows[index] = row
    end

    -- Without this the estimate is identical in both modes, which makes
    -- displacement look free -- and it is the expensive one.
    for _, entry in ipairs((rig.missingDisplace or {}).entries or {}) do
      -- The container PLUS the buttons pooled inside it. Counting containers
      -- alone reported both modes as one frame per rule and made them look
      -- identical -- the whole difference is the pool: a slot holds one
      -- button, a group about ten, and displacement cannot use slots.
      local frames = 1 + (entry.buttons or 0)
      local textures = entry.textures or 2
      totals.containers = totals.containers + frames
      totals.textures = totals.textures + textures
      local kind = entry.kind or "wash"
      local key = kind .. ":" .. tostring(entry.rank)
      local row = missingRows[key]
      if not row then
        row = { textures = 0, containers = 0, plates = 0,
                kind = kind, rank = entry.rank }
        missingRows[key] = row
        -- Ordered as encountered rather than iterated with ipairs over a
        -- rank-keyed table: a rule that fails to build (no debuff picked yet)
        -- leaves its rank absent, and ipairs would stop at that hole and drop
        -- every remaining row without saying so.
        missingOrder[#missingOrder + 1] = row
      end
      row.textures = row.textures + textures
      row.containers = row.containers + frames
      row.plates = row.plates + 1
    end
  end

  if rigCount == 0 then
    NS.Print("no nameplates rigged — target something first")
    return
  end

  NS.Print(("%d plate(s) rigged | %d containers | %d textures")
    :format(rigCount, totals.containers, totals.textures))

  -- Per plate is the number that scales; the totals above are just whatever
  -- happens to be on screen this second.
  for index, row in ipairs(rows) do
    local tex = row.textures / row.plates
    local con = row.containers / row.plates
    NS.Print(("  rule %d (%d debuff): %.0f textures + %.0f frames per plate -> %.0f / %.0f at %d plates")
      :format(index, row.cond, tex, con, tex * BUSY_PLATES, con * BUSY_PLATES, BUSY_PLATES))
  end
  -- Named as missing rules rather than folded into the rule rows above, so a
  -- perf dump makes clear WHICH half of the cost the mode switch controls.
  for _, row in ipairs(missingOrder) do
    local tex = row.textures / row.plates
    local con = row.containers / row.plates
    NS.Print(("  |cffffcc00missing %s %d (displace)|r: %.0f textures + %.0f frames per plate -> %.0f / %.0f at %d plates")
      :format(row.kind, row.rank, tex, con, tex * BUSY_PLATES, con * BUSY_PLATES, BUSY_PLATES))
  end

  local busyTextures = totals.textures / rigCount * BUSY_PLATES
  NS.Print(("busy pull estimate: %.0f textures, %.0f frames")
    :format(busyTextures, totals.containers / rigCount * BUSY_PLATES))

  -- The texture count alone says nothing. Multiplied by a measured
  -- per-texture cost it becomes how long the game stops for when this many
  -- plates rebuild at once -- which is what happens as combat ends with a
  -- rebuild queued. /pt bench build replaces the default with a real reading.
  local msPerTexture = (PLATETWEAKS_SETTINGS and PLATETWEAKS_SETTINGS.msPerTexture) or 0.078
  local calibrated = PLATETWEAKS_SETTINGS and PLATETWEAKS_SETTINGS.msPerTexture
  local estimate = busyTextures * msPerTexture
  local colour = estimate > 250 and "|cffff4040" or (estimate > 80 and "|cffffcc00" or "|cff55dd55")
  NS.Print(("  rebuilding that many at once: %s%.0f ms|r%s")
    :format(colour, estimate, calibrated and "" or " |cff808080(uncalibrated -- run /pt bench build)|r"))
  if estimate > 250 then
    NS.Print("  |cffff4040That is a visible freeze.|r Check |cffffff00/pt status|r says aura slots are ON -- without them every rule costs ten times as much.")
  end

  -- Accumulation. WoW cannot destroy a frame or texture, so a rebuild orphans
  -- everything the previous one made -- hidden and disabled, but resident
  -- until /reload. Live vs created is the leak, and it should stay near zero
  -- unless rebuilds are happening.
  local stats = NS.stats or {}
  local orphanTex = (stats.textures or 0) - totals.textures
  local orphanCon = (stats.containers or 0) - totals.containers
  NS.Print(("created since login: %d containers, %d textures over %d rebuild(s)")
    :format(stats.containers or 0, stats.textures or 0, stats.rebuilds or 0))
  -- Rebuilds that were asked for and turned out to be no-ops. Every one of
  -- these would have orphaned a full set of containers and textures.
  local saved = NS.SkippedRebuilds and NS.SkippedRebuilds() or 0
  if saved > 0 then
    NS.Print(("  %d rebuild(s) skipped as no-ops (config unchanged)"):format(saved))
  end
  if orphanTex > 0 or orphanCon > 0 then
    NS.Print(("  orphaned (retired, unreclaimable until /reload): %d containers, %d textures")
      :format(math.max(0, orphanCon), math.max(0, orphanTex)))
  end

  -- Memory is real but secondary; it is mostly the saved config plus our own
  -- bookkeeping, not the rendered objects above.
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    pcall(UpdateAddOnMemoryUsage)
    local okMem, kb = pcall(GetAddOnMemoryUsage, "PlateTweaks")
    if okMem and kb then NS.Print(("memory: %.0f KB"):format(kb)) end
  end

  -- Only meaningful with scriptProfile enabled, which costs performance in
  -- itself, so it is reported when present rather than switched on.
  if GetCVar and GetCVar("scriptProfile") == "1" and GetAddOnCPUUsage then
    pcall(UpdateAddOnCPUUsage)
    local okCPU, ms = pcall(GetAddOnCPUUsage, "PlateTweaks")
    if okCPU and ms then NS.Print(("cpu: %.1f ms since login"):format(ms)) end
  else
    NS.Print("cpu: not profiled (scriptProfile off)")
  end
end

-- /pt bench -- the fill path on its own.
--
-- Solo, no group, no nameplates. The loop it times dominates a raid
-- (ApplyRuleFill over every texture on every rig) and none of it needs a real
-- plate. Runs twice, cache off then on -- a single number would not settle
-- what the cache is worth.

-- /pt bench build -- the BUILD path, a different animal.
--
-- Anchoring re-points textures that exist; building creates them plus the
-- secure containers behind them, which is what a plate appearing costs.
-- Measured with a real rebuild, since a secure container cannot be faked.
--
-- Not free: a rebuild orphans everything the previous one made, and neither
-- can be destroyed. See the orphan count in /pt perf afterwards.
-- /pt capture -- everything the other commands print, into SavedVariables.
--
-- Chat truncates long lines, scrolls away and cannot be selected. Testing one
-- config across four nameplate addons means a dozen dumps, and screenshots of
-- those are lossy and unreadable. This runs the same printers with NS.Print
-- redirected into a table, so a whole test session comes out as one block of
-- text after a single /reload.
--
-- Also the thing to hand a bug reporter: "run /pt capture, reload, paste the
-- file" beats asking someone for screenshots of chat.
local NAMEPLATE_ADDONS = {
  "Plater", "Platynator", "EllesmereUI", "NDui", "ElvUI", "NamePlateKit",
  "Kui_Nameplates", "TidyPlates", "ThreatPlates", "BetterBlizzPlates",
}

local function AddonLoaded(name)
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not fn then return nil end
  local ok, loaded = pcall(fn, name)
  return ok and loaded and true or false
end

-- Captures are APPENDED, never replaced, and survive to the next session.
--
-- The one you want is usually taken mid-key, when the options window cannot
-- open at all -- so it has to still be there afterwards. Nothing in here
-- overwrites an earlier capture; the only things that remove one are the cap
-- below and /pt capture clear.
--
-- Capped because SavedVariables is parsed at load: an unbounded list would
-- grow every pull forever. 25 is enough for a night of testing, and the OLDEST
-- goes first so the run you just did is never the one dropped.
local MAX_CAPTURES = 25

function NS.CaptureSave(label)
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.captures = PLATETWEAKS_DEBUG.captures or {}
  local store = PLATETWEAKS_DEBUG.captures

  local lines = NS.CaptureLines()
  store[#store + 1] = {
    label = (label ~= nil and label ~= "") and label or "capture",
    when = date("%Y-%m-%d %H:%M:%S"),
    lines = lines,
  }
  local dropped = 0
  while #store > MAX_CAPTURES do
    table.remove(store, 1)
    dropped = dropped + 1
  end
  return store[#store], #store, dropped
end

-- The capture text, as a table of lines.
--
-- Split out of the slash command because the Diagnostics page shows the same
-- thing in a box you can select and Ctrl+C. Telling someone to find
-- SavedVariables works but almost nobody does it; a button in the window they
-- already have open gets the report actually sent.
function NS.CaptureLines()
  local lines = {}
  local realPrint = NS.Print
  -- Colour and texture escapes are noise in a text file, and |cff...|r wrapped
  -- around a number makes it genuinely hard to read.
  NS.Print = function(msg)
    -- Belt and braces around the guards in the printers themselves.
    --
    -- A secret must never reach the table: every string operation on one
    -- throws, and SavedVariables cannot serialise it -- so one leaking through
    -- would not just lose a line, it could cost the whole file on logout.
    -- Checked before AND after tostring, because tostring of a secret is
    -- itself secret.
    if issecretvalue and issecretvalue(msg) then
      lines[#lines + 1] = "<secret value omitted>"
      return
    end
    msg = tostring(msg)
    if issecretvalue and issecretvalue(msg) then
      lines[#lines + 1] = "<secret value omitted>"
      return
    end
    msg = msg:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    lines[#lines + 1] = msg
  end

  -- Restored on every path, including a thrown printer -- leaving NS.Print
  -- swapped would silently eat the addon's entire chat output for the session.
  local ok, err = pcall(function()
    local hosts = {}
    for _, name in ipairs(NAMEPLATE_ADDONS) do
      if AddonLoaded(name) then hosts[#hosts + 1] = name end
    end
    local _, instanceType = pcall(function() return select(2, IsInInstance()) end)

    NS.Print(("PlateTweaks %s | %s"):format(
      tostring((C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata("PlateTweaks", "Version")) or "?"),
      date("%Y-%m-%d %H:%M:%S")))
    NS.Print(("nameplate addons loaded: %s"):format(
      #hosts > 0 and table.concat(hosts, ", ") or "none (Blizzard default)"))
    NS.Print(("class %s | spec %s | instance %s | combat %s"):format(
      tostring(select(2, UnitClass("player"))),
      tostring(NS.SpecName and NS.SpecName() or "?"),
      tostring(instanceType or "?"),
      tostring(InCombatLockdown() and true or false)))
    if not UnitExists("target") then
      NS.Print("NO TARGET -- /pt bar and /pt layers need one, so those sections are empty")
    end
    NS.Print("")

    -- Each in its own pcall: one printer erroring must not cost the others,
    -- which is the whole reason a capture beats a screenshot.
    for _, item in ipairs({
      { "status", PrintStatus }, { "bar", PrintBarDebug },
      { "adapter", function() PrintAdapter("") end }, { "layers", PrintLayers },
    }) do
      NS.Print(("---- /pt %s ----"):format(item[1]))
      local okOne, errOne = pcall(item[2])
      if not okOne then NS.Print("  FAILED: " .. tostring(errOne)) end
      NS.Print("")
    end
  end)
  NS.Print = realPrint
  if not ok then
    lines[#lines + 1] = "capture failed: " .. tostring(err)
  end
  return lines
end

local function Capture(arg)
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.captures = PLATETWEAKS_DEBUG.captures or {}
  local store = PLATETWEAKS_DEBUG.captures

  if arg == "clear" then
    PLATETWEAKS_DEBUG.captures = {}
    NS.Print("captures cleared.")
    return
  end
  if arg == "list" then
    if #store == 0 then
      NS.Print("no captures yet. |cffffff00/pt capture|r to take one.")
      return
    end
    for index, item in ipairs(store) do
      NS.Print(("  %d. %s -- %s (%d lines)"):format(
        index, tostring(item.label), tostring(item.when), #(item.lines or {})))
    end
    NS.Print("in |cffffff00PLATETWEAKS_DEBUG.captures|r -- written on /reload or logout.")
    return
  end

  local label = arg
  if label == "" then
    -- Default to the adapter in use: that is what distinguishes one run from
    -- the next when testing across nameplate addons.
    label = CurrentAdapter() or "capture"
  end
  local item, count, dropped = NS.CaptureSave(label)

  NS.Print(("|cff55dd55captured|r %d lines as |cffffff00%s|r (#%d of %d kept)."):format(
    #(item.lines or {}), label, count, MAX_CAPTURES))
  if dropped > 0 then
    NS.Print(("  |cffffcc00%d oldest capture(s) dropped|r to stay under the cap."):format(dropped))
  end
  -- The window is the easy route and the one people actually use. The file is
  -- still named because it is the only way to get a capture off the machine
  -- when someone cannot open the window at all.
  NS.Print("Read it back in |cffffff00/pt|r > Diagnostics > Saved captures -- works after combat,")
  NS.Print("and it is still there next session.")
end

local function PrintBuildBench()
  local rigCount = 0
  for _ in pairs(rigs) do rigCount = rigCount + 1 end
  if rigCount == 0 then
    NS.Print("|cffffcc00No rigged plates.|r Target something first -- this measures a real rebuild.")
    return
  end
  if InCombatLockdown() then
    NS.Print("|cffffcc00Cannot build in combat.|r")
    return
  end

  local before = (NS.stats and NS.stats.textures) or 0
  local start = debugprofilestop()
  NS.RebuildAllRigs(true) -- forced: the no-op skip would otherwise measure nothing
  local elapsed = debugprofilestop() - start
  local made = ((NS.stats and NS.stats.textures) or 0) - before

  -- Calibration, kept OUTSIDE the profile: how fast this machine creates a
  -- texture is a property of the machine, not of a set of colouring rules.
  -- /pt perf uses it to turn a texture count into a millisecond prediction.
  if made > 0 then
    PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
    PLATETWEAKS_SETTINGS.msPerTexture = elapsed / made
  end

  NS.Print(("build path: %d rig(s) rebuilt in |cffffcc00%.1f ms|r (%.2f ms per plate, %d textures created)")
    :format(rigCount, elapsed, elapsed / rigCount, made))
  if made > 0 then
    NS.Print(("  %.4f ms per texture -- calibration saved, /pt perf now predicts in milliseconds")
      :format(elapsed / made))
  end
  NS.Print(("  a 40-plate rebuild at this rate costs about |cffff8040%.0f ms|r")
    :format(elapsed / rigCount * 40))
  NS.Print("|cff808080This is what a plate appearing pays, and what every queued rebuild pays when combat ends.|r")
end

local function PrintBench(arg)
  if arg == "build" then return PrintBuildBench() end
  local count = tonumber(arg) or 100
  local iterations = 20

  if not (NS.BenchFillPath and NS.SetFillCacheEnabled) then
    NS.Print("benchmark unavailable")
    return
  end

  local rule = NS.db.tints.rules and NS.db.tints.rules[1]
  if not rule then
    NS.Print("|cffffcc00No health rule to measure.|r Create one first -- the bench times whatever the top rule is set to, so its fill style and texture are what you are measuring.")
    return
  end

  NS.Print(("fill path: %d textures x %d passes, rule = |cff55dd55%s|r (%s)")
    :format(count, iterations, NS.RuleSummary and NS.RuleSummary(rule) or "?",
      rule.fillStyle == "texture" and "Texture Overlay" or "Solid Overlay"))

  NS.SetFillCacheEnabled(false)
  local cold = NS.BenchFillPath(count, iterations, rule)
  NS.SetFillCacheEnabled(true)
  local warm = NS.BenchFillPath(count, iterations, rule)

  if type(cold) ~= "number" or type(warm) ~= "number" then
    NS.Print("benchmark did not run: " .. tostring(warm))
    return
  end

  local passes = iterations
  NS.Print(("  cache off: %.2f ms total | %.3f ms per pass | %.4f ms per texture")
    :format(cold, cold / passes, cold / (passes * count)))
  NS.Print(("  cache on:  %.2f ms total | %.3f ms per pass | %.4f ms per texture")
    :format(warm, warm / passes, warm / (passes * count)))
  if cold > 0 then
    NS.Print(("  |cff55dd55%.1fx faster|r (%.2f ms saved per pass)")
      :format(cold / math.max(0.0001, warm), (cold - warm) / passes))
  end

  -- The number that actually matters: one pass over one plate, times the
  -- plates a raid puts on screen.
  local perPlate = warm / passes
  NS.Print(("  at %d textures/plate this is %.2f ms per plate; a 40-plate reposition costs about %.0f ms")
    :format(count, perPlate, perPlate * 40))
  NS.Print("|cff808080Measures our Lua only. SetPoint/SetTexture cost inside the client is not included -- profile in game for that.|r")

  -- And the real thing, if there is anything real to measure: the whole
  -- AnchorTints pass over the rigs actually on screen. This one DOES include
  -- the client-side cost, and it is what Reapply pays on every combat end --
  -- so target a dummy, get a plate or two up, and multiply by your raid.
  local rigCount = 0
  for _ in pairs(rigs) do rigCount = rigCount + 1 end
  if rigCount == 0 then
    NS.Print("|cff808080No rigged plates: target something to also measure a real AnchorTints pass.|r")
    return
  end

  local passes = 10
  local startAll = debugprofilestop()
  for _ = 1, passes do
    for _, rig in pairs(rigs) do
      pcall(NS.AnchorTints, rig)
    end
  end
  local elapsed = debugprofilestop() - startAll
  local perRig = elapsed / (passes * rigCount)
  NS.Print(("AnchorTints over %d live rig(s): %.3f ms per rig per pass -> about %.0f ms for 40 plates")
    :format(rigCount, perRig, perRig * 40))
end

-- Probes write to chat AND PLATETWEAKS_DEBUG.cdm. Chat truncates and scrolls;
-- SavedVariables does not, and is readable outside the game at
--   WTF/Account/<account>/SavedVariables/PlateTweaks.lua
-- Rebuilt from scratch each run, so stale lines never linger.
local function DebugDump(line)
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.cdm = PLATETWEAKS_DEBUG.cdm or {}
  table.insert(PLATETWEAKS_DEBUG.cdm, line)
end

local function Log(line)
  NS.Print(line)
  DebugDump(line)
end

-- File-only: for the repetitive per-field / per-method detail that would
-- otherwise flood and truncate chat. The SavedVariables file has no such
-- limit, so the full detail is always there even when chat only shows a
-- header and a count.
local function LogQuiet(line)
  DebugDump(line)
end

local function EnumerateMethods(label, object)
  if not object then
    Log(label .. ": none available")
    return
  end
  local names = {}
  local ok = pcall(function()
    for key, value in pairs(object) do
      if type(value) == "function" then table.insert(names, key) end
    end
  end)
  if not ok then
    Log(label .. ": enumeration refused (forbidden object)")
    return
  end
  table.sort(names)
  Log(("%s -- %d methods (full list in PLATETWEAKS_DEBUG.cdm)"):format(label, #names))
  for index = 1, #names, 3 do
    LogQuiet("  " .. table.concat(names, "   ", index, math.min(index + 2, #names)))
  end
end

-- What the spellbook hands us on THIS character.
--
-- NS.CanApplyAura asks IsPlayerSpell about one ID at a time, which can only
-- confirm an ID it already holds. Enumerating the book would let it ask "does
-- this character have any spell that could produce this aura" -- the question
-- that would make the spell gate safe to turn on by default.
--
-- Read-only, and everything is existence-checked, so the output is evidence
-- about this client rather than a restatement of what the code expected.
local function SpellbookProbe()
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.cdm = {}

  Log("=== spellbook probe ===")
  EnumerateMethods("C_SpellBook", C_SpellBook)

  Log("Enum.SpellBookSpellBank")
  if Enum and Enum.SpellBookSpellBank then
    local keys = {}
    for key, value in pairs(Enum.SpellBookSpellBank) do
      table.insert(keys, ("%s=%s"):format(tostring(key), tostring(value)))
    end
    table.sort(keys)
    Log("  " .. table.concat(keys, ", "))
  else
    Log("  absent -- this client has no SpellBookSpellBank enum")
  end

  -- The enumeration itself. Guarded at every step: a missing function here is
  -- the answer to the question, not an error.
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  if not (C_SpellBook and C_SpellBook.GetNumSpellBookItems and C_SpellBook.GetSpellBookItemInfo) then
    Log("C_SpellBook enumeration: NOT AVAILABLE -- the per-ID IsPlayerSpell check is all we have")
  elseif bank == nil then
    Log("C_SpellBook present but no Player bank constant -- cannot enumerate")
  else
    local okCount, count = pcall(C_SpellBook.GetNumSpellBookItems, bank)
    if not okCount or type(count) ~= "number" then
      Log("GetNumSpellBookItems refused")
    else
      Log(("spellbook items: %d (full dump in PLATETWEAKS_DEBUG.cdm)"):format(count))

      -- First entry in full, so we can see every field the struct really
      -- carries rather than only the ones this addon happens to read.
      local okFirst, first = pcall(C_SpellBook.GetSpellBookItemInfo, 1, bank)
      if okFirst and type(first) == "table" then
        local fields = {}
        for key, value in pairs(first) do
          table.insert(fields, ("%s=%s(%s)"):format(tostring(key), tostring(value), type(value)))
        end
        table.sort(fields)
        Log("  item 1 fields: " .. table.concat(fields, ", "))
      else
        Log("  GetSpellBookItemInfo(1) returned " .. type(first))
      end

      -- Then names and IDs for the rest, file-only. What we are looking for is
      -- whether the spellID here is the CAST id (expected) and whether
      -- anything in the struct points at an aura -- the mapping no API has
      -- given us so far.
      local shown = 0
      for index = 1, count do
        local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
        if okItem and type(item) == "table" then
          shown = shown + 1
          LogQuiet(("  [%d] %s | spellID=%s actionID=%s type=%s passive=%s")
            :format(index, tostring(item.name), tostring(item.spellID),
              tostring(item.actionID), tostring(item.itemType), tostring(item.isPassive)))
        end
      end
      Log(("  %d item(s) dumped to file"):format(shown))
    end
  end

  -- Cross-check against the gate as it stands today: for every debuff in the
  -- current rules, what does each independent source say? A disagreement here
  -- is exactly the case that would make the gate skip a working rule.
  Log("--- current rule debuffs vs each source ---")
  local applied = NS.GetTargetAuraSet and NS.GetTargetAuraSet() or {}
  for _, list in ipairs({ NS.db.tints.rules or {}, NS.db.tints.borderRules or {} }) do
    for _, rule in ipairs(list) do
      for _, condition in ipairs(rule.conditions or {}) do
        local spellID = condition.spellID
        local okKnown, known = false, nil
        if IsPlayerSpell then okKnown, known = pcall(IsPlayerSpell, spellID) end
        local related = NS.RelatedSpellIDs and NS.RelatedSpellIDs(spellID) or {}
        local relatedKnown = false
        if IsPlayerSpell then
          for id in pairs(related) do
            local okR, r = pcall(IsPlayerSpell, id)
            if okR and r then relatedKnown = true break end
          end
        end
        Log(("  %s [%d] cdm=%s isPlayerSpell=%s viaLinked=%s -> gate says %s")
          :format(NS.SpellName(spellID) or "?", spellID,
            tostring(applied[spellID] and true or false),
            okKnown and tostring(known) or "refused",
            tostring(relatedKnown),
            tostring(NS.CanApplyAura and NS.CanApplyAura(spellID))))
      end
    end
  end

  Log("=== end ===  full output: WTF\\Account\\<account>\\SavedVariables\\PlateTweaks.lua")
end

-- /pt probe container -- what the aura container will let us ask for.
--
-- A combo rule costs ~100 textures because of the POOL, not the number of
-- combinations: the engine pre-creates buttons per group and calls
-- initializeFrame on every one. Chain two groups and it is pool x pool.
--
-- MaxFrameCount says "display at most one". If anything sizes the POOL, the
-- whole cost collapses. Nothing here has ever enumerated that surface.
--
-- Creates one container and one texture, then abandons them -- which is why
-- this is a probe and not something the addon does at runtime.
local function ContainerProbe()
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.cdm = {}

  Log("=== aura container probe ===")
  if InCombatLockdown() then
    Log("|cffffcc00In combat -- container creation is refused. Try again out of combat.|r")
    return
  end

  local holder = CreateFrame("Frame", nil, UIParent)
  holder:Hide()

  local ok, container = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
  if not ok or not container then
    Log("could not create an AuraContainer: " .. tostring(container))
  else
    -- To CHAT, not only to the file. The whole point of this run is reading
    -- the names, and a name that only reaches SavedVariables needs a /reload
    -- and a text editor before anyone can look at it.
    local names = {}
    pcall(function()
      for key, value in pairs(container) do
        if type(value) == "function" then table.insert(names, key) end
      end
    end)
    table.sort(names)
    Log(("AuraContainer: %d methods"):format(#names))
    for index = 1, #names, 3 do
      Log("  " .. table.concat(names, "   ", index, math.min(index + 2, #names)))
    end
    -- Specifically: anything that sounds like it sizes the pool rather than
    -- the number displayed. These are the names worth trying by hand.
    local wanted = {
      "SetAuraGroupMaxFrameCount", "SetAuraGroupPoolSize", "SetAuraGroupPoolLimit",
      "SetAuraGroupMaxPoolSize", "SetPoolSize", "SetMaxFrames", "SetAuraGroupPreallocate",
      "SetAuraGroupFrameCount", "GetAuraGroupFrameCount", "SetAuraGroupSortOrder",
    }
    Log("candidate pool controls:")
    for _, name in ipairs(wanted) do
      local present = false
      pcall(function() present = type(container[name]) == "function" end)
      Log(("  %s %s"):format(present and "|cff55dd55PRESENT|r" or "|cff808080absent |r", name))
    end
  end

  -- A rule border is four textures per combination, so a combo with a border
  -- is ~400. One sliced texture would draw the same rectangle, if the client
  -- supports slicing on a plain texture.

  -- How many buttons the engine actually pools for one group. Every one gets
  -- initializeFrame and therefore a texture, and a combo is this squared. If
  -- it comes back 1, the pool model is wrong and ~100 is coming from
  -- somewhere else.
  if ok and container then
    local okGroup = pcall(function()
      container:SetEnabled(false)
      container:AddAuraGroup("probe", "HARMFUL|PLAYER", { initializeFrame = function() end })
      container:SetAuraGroupCandidateFilters("probe", { includeSpellIDs = { [589] = true } })
      container:SetAuraGroupMaxFrameCount("probe", 1)
    end)
    if not okGroup then
      Log("could not add a probe aura group")
    else
      local okCount, count = pcall(container.GetAuraGroupFrameCount, container, "probe")
      Log(("pooled buttons for one group (MaxFrameCount = 1): |cffffcc00%s|r")
        :format(okCount and tostring(count) or "refused"))
      Log("  a combo rule creates this SQUARED textures per plate")
      -- And with the cap raised, to see whether the pool follows the cap at all.
      pcall(container.SetAuraGroupMaxFrameCount, container, "probe", 5)
      local okRaised, raised = pcall(container.GetAuraGroupFrameCount, container, "probe")
      Log(("  same group with MaxFrameCount = 5: |cffffcc00%s|r%s")
        :format(okRaised and tostring(raised) or "refused",
          (okCount and okRaised and count == raised) and " |cff808080(unchanged -- the cap does not size the pool)|r" or ""))
    end
  end

  local tex = holder:CreateTexture(nil, "OVERLAY")
  Log("texture slicing (would turn 4 border textures into 1):")
  for _, name in ipairs({ "SetTextureSliceMargins", "SetTextureSliceMode" }) do
    local present = false
    pcall(function() present = type(tex[name]) == "function" end)
    Log(("  %s %s"):format(present and "|cff55dd55PRESENT|r" or "|cff808080absent |r", name))
  end

  Log("=== end ===  full method list in PLATETWEAKS_DEBUG.cdm")
end

-- /pt probe slot -- the AuraSlot API.
--
-- A group pools ten frames, so a rule pays ten textures and a combo a hundred.
-- The container also exposes AddAuraSlot and friends, which this addon has
-- never used, and whose name suggests one frame rather than a pool.
--
-- The signature is unknown, so this calls it wrong on purpose: WoW's C
-- functions answer a bad call with a Usage: string that documents the real
-- one.
local slotProbeRun = 0

-- /pt probe slot -- can an aura SLOT carry our textures?
--
-- So far: AddAuraSlot(slotKey, filterString, options) fires initializeFrame
-- exactly once where a group fires ten times. Slots are invisible to the group
-- getters, so the only handle on that frame is the callback argument.
--
-- Everything below happens inside the callback: that is the one context where
-- an aura button is touchable.
local function SlotProbe()
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.cdm = {}

  Log("=== aura slot probe ===")
  if InCombatLockdown() then
    Log("|cffffcc00In combat -- container creation is refused.|r")
    return
  end

  local holder = CreateFrame("Frame", nil, UIParent)
  holder:Hide()
  local ok, container = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
  if not ok or not container then
    Log("could not create an AuraContainer: " .. tostring(container))
    return
  end
  pcall(container.SetEnabled, container, false)

  slotProbeRun = slotProbeRun + 1
  local key = ("PT%dA"):format(slotProbeRun)
  local nestedKey = ("PT%dB"):format(slotProbeRun)

  local report = {}
  local function Note(line) table.insert(report, line) end

  local fired = 0
  local okSlot, errSlot = pcall(function()
    container:AddAuraSlot(key, "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        fired = fired + 1
        if not button then Note("callback received NO button") return end
        Note(("callback received a %s"):format(type(button)))

        -- 1. A texture. This is the whole question.
        local okTex, errTex = pcall(function()
          local tex = button:CreateTexture(nil, "OVERLAY")
          tex:SetColorTexture(1, 1, 1, 1)
          tex:SetAllPoints(button)
        end)
        Note(okTex and "|cff55dd55CreateTexture on the slot button: YES|r"
          or ("|cffff4040CreateTexture refused: " .. tostring(errTex) .. "|r"))

        -- 2. A nested container, which is how a combo rule would AND two
        -- debuffs together -- slot inside slot instead of pool inside pool.
        local okNest, errNest = pcall(function()
          local inner = CreateFrame("AuraContainer", nil, button, "CustomAuraContainerTemplate")
          inner:SetEnabled(false)
          inner:AddAuraSlot(nestedKey, "HARMFUL|PLAYER", {
            initializeFrame = function(innerButton)
              local okInner = pcall(function()
                innerButton:CreateTexture(nil, "OVERLAY"):SetColorTexture(1, 1, 1, 1)
              end)
              Note(okInner and "|cff55dd55nested slot button also takes a texture|r"
                or "|cffff4040nested slot button refused a texture|r")
            end,
          })
        end)
        Note(okNest and "|cff55dd55nested AuraContainer inside a slot button: YES|r"
          or ("|cffff4040nesting refused: " .. tostring(errNest) .. "|r"))

        -- 3. Does it behave like a gated frame at all?
        local okShown, shown = pcall(button.IsShown, button)
        Note(("button:IsShown() = %s"):format(okShown and tostring(shown) or "refused"))
        local okLevel, level = pcall(button.GetFrameLevel, button)
        Note(("button:GetFrameLevel() = %s"):format(okLevel and tostring(level) or "refused"))
      end,
    })
    container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = { [589] = true } })
  end)

  if not okSlot then
    Log("slot setup refused: |cffff4040" .. tostring(errSlot) .. "|r")
  end
  Log(("initializeFrame fired |cffffcc00%d|r time(s) -- an aura group fires 10"):format(fired))
  for _, line in ipairs(report) do Log("  " .. line) end
  Log("=== end ===")
end

-- /pt probe slotlive <spellID> -- gating, the last question slots have to
-- answer.
--
-- The static probe settled that a slot pools one frame, takes a texture, and
-- nests. It could not settle GATING: it reported IsShown() = true on a button
-- with no unit and a disabled container. If a slot button is always shown, its
-- texture is always painted and the mechanism is useless.
--
-- So: attach a real slot to the real target's bar, paint it magenta, watch.
-- Needs a live aura, which is exactly what cannot be simulated.
--
-- Leaves a container and a texture until /reload. It is a probe.

-- Probe: can a DISPLACED MASK hide a normally-anchored wash?
--
-- Occlusion's cover is the expensive half -- a live copy of the bar kept
-- matching by a 4Hz poll, and the sole reason the ladder needs mutual
-- exclusion. Displacement would remove it entirely.
--
-- The obstacle is geometric: a displaced object carries one anchor plus an
-- explicit size, while a wash needs two corners pinned to the fill. So leave
-- the wash alone and displace a MASK instead.
--
-- Both objects are ours, on our own frame, so AddMaskTexture has no
-- forbidden-object problem. The mask is oversized on purpose -- a bar geometry
-- read that comes back secret costs nothing here.
--
-- The result is VISUAL and cannot be printed: a bound container's width is a
-- secret, so nothing can report "it moved".
local function MaskProbe(arg)
  local spellID = tonumber(arg)
  if not spellID then
    NS.Print("usage: |cffffff00/pt probe mask <spellID>|r -- a debuff YOU apply")
    return
  end
  if InCombatLockdown() then
    NS.Print("|cffffcc00Cannot create containers in combat.|r")
    return
  end
  if not UnitExists("target") then
    NS.Print("|cffffcc00Target something first.|r")
    return
  end

  local plate = C_NamePlate.GetNamePlateForUnit("target")
  local healthBar = plate and NS.FindHealthBar and NS.FindHealthBar(plate)
  if not healthBar then
    NS.Print("|cffffcc00No health bar found on the target's nameplate.|r")
    return
  end

  local function Secret(v) return issecretvalue and issecretvalue(v) end
  local okW, bw = pcall(healthBar.GetWidth, healthBar)
  local okH, bh = pcall(healthBar.GetHeight, healthBar)
  local geomNote = "read ok"
  if not okW or Secret(bw) or not bw or bw < 1 then bw = 150; geomNote = "FELL BACK (refused/secret)" end
  if not okH or Secret(bh) or not bh or bh < 1 then bh = 14 end

  -- Our own frame, so everything below is ours to show, hide and mask.
  local holder = CreateFrame("Frame", nil, healthBar)
  holder:SetAllPoints(healthBar)
  pcall(holder.SetFrameLevel, holder, healthBar:GetFrameLevel() + 1)

  -- The wash: unchanged from how a real one is built -- two corners on the
  -- fill, tracking health.
  local wash = holder:CreateTexture(nil, "OVERLAY", nil, 5)
  wash:SetColorTexture(1, 0, 1, 0.85)
  if NS.AnchorToFill then
    NS.AnchorToFill(wash, healthBar, 0)
  else
    wash:SetAllPoints(healthBar)
  end

  -- Container FIRST, with no groups on it, so the mask can still anchor to it.
  local okC, container = pcall(CreateFrame, "AuraContainer", nil, healthBar,
    "CustomAuraContainerTemplate")
  if not okC or not container then
    NS.Print("container refused: " .. tostring(container))
    return
  end
  container:SetEnabled(false)
  container:SetSize(1, bh)
  pcall(container.SetFrameLevel, container, healthBar:GetFrameLevel() + 2)
  pcall(container.SetFlowLayoutAnchorPoint, container, "LEFT")
  pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)
  container:ClearAllPoints()
  container:SetPoint("LEFT", healthBar, "LEFT", 0, 0)

  local okRest, rest = pcall(container.GetWidth, container)
  rest = (okRest and not Secret(rest) and rest) or 1

  -- The mask, on the wash's own frame, anchored to the container's moving edge.
  --
  -- WRAP MODE IS LOAD-BEARING, and its absence made the first version of this
  -- probe useless. The default treats outside the rect as WHITE -- fully
  -- masked IN -- so flying the mask away makes the whole wash visible, which
  -- is indistinguishable from displacement not working.
  local mask = holder:CreateMaskTexture(nil, "OVERLAY")
  local okWrap = pcall(mask.SetTexture, mask, "Interface\\Buttons\\WHITE8X8",
    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  if not okWrap then
    -- Argument shape differs between builds; a mask with no usable texture
    -- would mask nothing at all, so fall back rather than leave it blank.
    pcall(mask.SetTexture, mask, "Interface\\Buttons\\WHITE8X8")
  end
  mask:SetSize(bw + 100, bh + 100)
  mask:SetPoint("CENTER", container, "RIGHT", bw / 2 - rest, 0)

  local okMask, errMask = pcall(wash.AddMaskTexture, wash, mask)

  -- Control: a plain frame on the same container edge, built like the shipped
  -- Missing Debuffs chips, which displace correctly. Separates two failure
  -- modes that otherwise look identical:
  --   control moves, wash stays -> masking is the problem
  --   neither moves             -> the container is not growing
  local control = CreateFrame("Frame", nil, healthBar)
  control:SetSize(14, 14)
  pcall(control.SetFrameLevel, control, healthBar:GetFrameLevel() + 6)
  local dot = control:CreateTexture(nil, "OVERLAY")
  dot:SetAllPoints()
  dot:SetColorTexture(0, 1, 0, 1)
  control:SetPoint("CENTER", container, "RIGHT", 8 - rest, bh + 12)

  -- LAST. Registering seals the container against any further anchoring.
  local okReg, errReg = pcall(function()
    container:AddAuraGroup("PTMASK", "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        pcall(button.SetSize, button, 4000, bh)
        pcall(button.EnableMouse, button, false)
      end,
    })
    container:SetAuraGroupCandidateFilters("PTMASK", { includeSpellIDs = { [spellID] = true } })
    pcall(container.SetAuraGroupMaxFrameCount, container, "PTMASK", 1)
  end)

  container:SetUnit("target")
  container:SetEnabled(true)

  NS.Print(("|cff55dd55mask probe|r on %s (%d)"):format(NS.SpellName(spellID) or "?", spellID))
  NS.Print(("  bar geometry: %s (%dx%d)"):format(geomNote, math.floor(bw), math.floor(bh)))
  NS.Print(("  AddMaskTexture: %s"):format(okMask and "|cff55dd55accepted|r"
    or ("|cffff4040refused|r -- " .. tostring(errMask))))
  NS.Print(("  mask wrap mode: %s"):format(okWrap and "|cff55dd55set|r"
    or "|cffffcc00refused -- fell back to no wrap args|r"))
  NS.Print(("  AddAuraGroup: %s"):format(okReg and "|cff55dd55accepted|r"
    or ("|cffff4040refused|r -- " .. tostring(errReg))))
  NS.Print("  |cffffff00Watch TWO things:|r |cffff00ffmagenta|r on the bar, and a")
  NS.Print("  |cff00ff00green dot|r just above its left end. Apply the debuff, then:")
  NS.Print("    both vanish            -> |cff55dd55it works|r")
  NS.Print("    dot goes, magenta stays -> displacement fine, masking is the problem")
  NS.Print("    neither moves           -> the container is not growing at all")
  NS.Print("  |cff808080Frames cannot be destroyed -- /reload to clear this.|r")
end

local function SlotLiveProbe(arg)
  local spellID = tonumber(arg)
  if not spellID then
    NS.Print("usage: |cffffff00/pt probe slotlive <spellID>|r -- a debuff YOU apply, e.g. one from a rule")
    return
  end
  if InCombatLockdown() then
    NS.Print("|cffffcc00Cannot create containers in combat.|r")
    return
  end
  if not UnitExists("target") then
    NS.Print("|cffffcc00Target something first.|r")
    return
  end

  local plate = C_NamePlate.GetNamePlateForUnit("target")
  local healthBar = plate and NS.FindHealthBar and NS.FindHealthBar(plate)
  if not healthBar then
    NS.Print("|cffffcc00No health bar found on the target's nameplate.|r")
    return
  end

  local ok, container = pcall(CreateFrame, "AuraContainer", nil, healthBar, "CustomAuraContainerTemplate")
  if not ok or not container then
    NS.Print("container refused: " .. tostring(container))
    return
  end
  container:SetEnabled(false)
  pcall(container.SetAllPoints, container, healthBar)

  local watched
  local okSlot, errSlot = pcall(function()
    container:AddAuraSlot("PTLIVE", "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        watched = button
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(1, 0, 1, 0.85)
        tex:SetAllPoints(healthBar)
      end,
    })
    container:SetAuraSlotCandidateFilters("PTLIVE", { includeSpellIDs = { [spellID] = true } })
  end)
  if not okSlot then
    NS.Print("slot refused: " .. tostring(errSlot))
    return
  end

  -- Same activation the real engine uses.
  container:SetUnit("target")
  container:SetEnabled(true)

  NS.Print(("|cff55dd55Watching %s [%d] on your target.|r Apply and remove it; the bar should go magenta only while it is up.")
    :format(NS.SpellName(spellID) or "?", spellID))

  local ticks = 0
  local last
  C_Timer.NewTicker(1.0, function(ticker)
    ticks = ticks + 1
    local shown = watched and watched:IsShown()
    if shown ~= last then
      last = shown
      NS.Print(("  t+%ds  slot button shown: %s"):format(ticks, tostring(shown)))
    end
    if ticks >= 20 then
      ticker:Cancel()
      NS.Print("|cff808080Watch ended. The container stays until /reload.|r")
    end
  end)
end

local function CooldownManagerProbe()
  PLATETWEAKS_DEBUG = PLATETWEAKS_DEBUG or {}
  PLATETWEAKS_DEBUG.cdm = {}
  -- COOLDOWN MANAGER SOUND SURFACE.
  --
  -- The default Cooldown Manager plays sounds on its own tracked items --
  -- engine-driven, so not gated the way arbitrary aura sound registration is.
  -- The question is whether any of that is exposed to addons.
  --
  -- Three surfaces:
  --   1. The full C_CooldownViewer function list -- we have called three.
  --   2. The real fields of a live info struct -- the addon reads five.
  --   3. The global viewer frames (EssentialCooldownViewer and friends),
  --      which are real UI frames with their own mixins, separate from the
  --      C_ API, and whose children may carry sound-kit setters.
  EnumerateMethods("C_CooldownViewer", C_CooldownViewer)

  Log("Enum.CooldownViewerCategory")
  if Enum and Enum.CooldownViewerCategory then
    local keys = {}
    for k in pairs(Enum.CooldownViewerCategory) do table.insert(keys, tostring(k)) end
    table.sort(keys)
    Log("  " .. table.concat(keys, ", "))
  else
    Log("  absent")
  end

  -- Every live info struct, not just one: a sound field might ride only on
  -- aura entries or only on ability entries.
  if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and Enum and Enum.CooldownViewerCategory then
    local seen, found, allFieldNames = {}, 0, {}
    for categoryName, category in pairs(Enum.CooldownViewerCategory) do
      local okSet, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
      if okSet and ids then
        for _, id in ipairs(ids) do
          if not seen[id] then
            seen[id] = true
            local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
            if okInfo and info then
              found = found + 1
              LogQuiet(("live info struct — cooldownID %d, category %s"):format(id, tostring(categoryName)))
              local fields = {}
              for k, v in pairs(info) do
                allFieldNames[tostring(k)] = true
                table.insert(fields, ("  %s = %s"):format(tostring(k), tostring(v)))
              end
              table.sort(fields)
              for _, line in ipairs(fields) do LogQuiet(line) end
            end
          end
        end
      end
    end
    if found == 0 then
      Log("no live cooldown entries found — set up items in Edit Mode's Cooldown Manager first")
    else
      local names = {}
      for k in pairs(allFieldNames) do table.insert(names, k) end
      table.sort(names)
      Log(("info struct fields, all %d entries (full values in file): %s")
        :format(found, table.concat(names, ", ")))
    end
  end

  -- The actual viewer frames, not just the C_ namespace.
  for _, frameName in ipairs({
    "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
  }) do
    EnumerateMethods(frameName, _G[frameName])
  end
end

SlashCmdList["PLATETWEAKS"] = function(msg)
  if msg and msg:lower():match("^%s*cdm%s*$") then
    local ok, err = pcall(CooldownManagerProbe)
    if not ok then NS.Print("cdm probe failed: " .. tostring(err)) end
    return
  end
  local secretArg = msg and msg:lower():match("^%s*secretcheck%s*(.-)%s*$")
  if secretArg ~= nil then
    ---------------------------------------------------------------------
    -- PER-SPELL SECRECY CHECK.
    --
    -- C_Secrets.ShouldSpellAuraBeSecret(spellID) is a pre-flight predicate:
    -- it answers whether THAT spell's aura is classified secret at all,
    -- independent of reading any actual aura data. Per Blizzard's own docs
    -- this is per-spell, not blanket -- "raid buffs, many healer HoTs"
    -- are named as examples that come back NOT secret even under the same
    -- restrictions that seal everything else.
    --
    -- If Agony/Corruption/Haunt come back false here, the entire
    -- displacement/occlusion system built this session is unnecessary for
    -- them specifically -- C_UnitAuras.GetAuraDataBySpellID would just
    -- work, and the original "recolor the bar when my DoT is up" feature
    -- is back exactly as it was before 12.1, no workaround required.
    --
    -- Also cross-checks against a live read-back on your current target,
    -- since the predicate and the actual read could in principle disagree
    -- and that disagreement would itself be worth knowing about.
    ---------------------------------------------------------------------
    local DEFAULT_IDS = { 980, 172, 48181 } -- Agony, Corruption, Haunt
    local ids = {}
    for word in secretArg:gmatch("%S+") do
      local n = tonumber(word)
      if n then table.insert(ids, n) end
    end
    if #ids == 0 then ids = DEFAULT_IDS end

    NS.Print("|cff66ccffC_Secrets.ShouldSpellAuraBeSecret probe|r")
    local hasFn = _G.C_Secrets and _G.C_Secrets.ShouldSpellAuraBeSecret
    if not hasFn then
      NS.Print("  |cffff8800C_Secrets.ShouldSpellAuraBeSecret is ABSENT on this client|r")
    end

    for _, id in ipairs(ids) do
      local name = NS.SpellName(id)
      if hasFn then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if ok then
          local color = secret and "|cffff8800" or "|cff55dd55"
          NS.Print(("  %s (%d): %s%s|r"):format(name, id, color, secret and "SECRET" or "NOT secret"))
        else
          NS.Print(("  %s (%d): |cffff5555refused: %s|r"):format(name, id, tostring(secret):sub(1, 120)))
        end
      end

      -- Cross-check: does an actual read on the current target agree?
      if UnitExists("target") and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local okR, data = pcall(C_UnitAuras.GetAuraDataBySpellID, "target", id, "HARMFUL")
        if okR and data then
          local isSecretID = _G.issecretvalue and issecretvalue(data.spellId)
          NS.Print(("    read-back on %s: got data, spellId secret=%s")
            :format(UnitName("target") or "target", tostring(isSecretID)))
        elseif okR then
          NS.Print("    read-back: nil (not present on target, or suppressed)")
        else
          NS.Print(("    read-back: |cffff5555refused: %s|r"):format(tostring(data):sub(1, 120)))
        end
      end
    end
    return
  end

  local dispelArg = msg and msg:lower():match("^%s*dispel%s*(.-)%s*$")
  if dispelArg and dispelArg ~= "" then
    ---------------------------------------------------------------------
    -- DISPEL-USABILITY PROBE.
    --
    -- Retail now runs the same 12.1 secrets wall as PTR did (Midnight
    -- shipped live) -- this is no longer a "no restriction" control, it is
    -- the real environment. Kept for completeness; the buffless-target
    -- test already showed IsSpellUsable does not react to target content,
    -- so this specific mechanism is closed.
    ---------------------------------------------------------------------
    if dispelArg == "off" then
      if NS.dispelProbeTicker then
        NS.dispelProbeTicker:Cancel()
        NS.dispelProbeTicker = nil
        NS.Print("dispel probe: stopped")
      else
        NS.Print("dispel probe: not running")
      end
      return
    end

    local resolved = tonumber(dispelArg)
    if not resolved and NS.ResolveAuraInput then
      local id, note = NS.ResolveAuraInput(dispelArg)
      resolved = id
      if note then NS.Print(note) end
    end
    if not resolved then
      NS.Print("could not resolve: " .. dispelArg)
      return
    end
    NS.dispelProbeSpell = resolved

    if NS.dispelProbeTicker then
      NS.dispelProbeTicker:Cancel()
      NS.dispelProbeTicker = nil
    end

    local spellID = NS.dispelProbeSpell
    local lastLine = nil
    NS.Print(("dispel probe (retail control): watching %s (%d) on |cff55dd55target|r — swap targets to compare")
      :format(NS.SpellName(spellID), spellID))

    NS.dispelProbeTicker = C_Timer.NewTicker(0.5, function()
      if not UnitExists("target") then
        if lastLine ~= "none" then
          NS.Print("  target: |cff888888none|r")
          lastLine = "none"
        end
        return
      end

      local okU, usable, insufficientPower = pcall(C_Spell.IsSpellUsable, spellID)
      local targetName = UnitName("target") or "?"

      local okOld, usableOld
      if IsUsableSpell then
        okOld, usableOld = pcall(IsUsableSpell, spellID)
      end

      local line = ("%s | new:%s%s | old:%s"):format(
        targetName,
        okU and tostring(usable) or "refused",
        okU and insufficientPower ~= nil and (" (insufficientPower=" .. tostring(insufficientPower) .. ")") or "",
        okOld and tostring(usableOld) or (IsUsableSpell and "refused" or "absent"))

      if line ~= lastLine then
        local color = (okU and usable) and "|cff55dd55" or "|cffff8800"
        NS.Print("  " .. color .. line .. "|r")
        lastLine = line
      end
    end)
    return
  end
  local benchArg = msg and msg:lower():match("^%s*bench%s*(%a*%d*)%s*$")
  if benchArg then
    local ok, err = pcall(PrintBench, benchArg)
    if not ok then NS.Print("bench failed: " .. tostring(err)) end
    return
  end
  local liveArg = msg and msg:lower():match("^%s*probe%s+slotlive%s+(%d+)%s*$")
  if liveArg then
    local ok, err = pcall(SlotLiveProbe, liveArg)
    if not ok then NS.Print("slotlive probe failed: " .. tostring(err)) end
    return
  end
  local maskArg = msg and msg:lower():match("^%s*probe%s+mask%s+(%d+)%s*$")
  if maskArg then
    local ok, err = pcall(MaskProbe, maskArg)
    if not ok then NS.Print("mask probe failed: " .. tostring(err)) end
    return
  end
  if msg and msg:lower():match("^%s*probe%s+slot%s*$") then
    local ok, err = pcall(SlotProbe)
    if not ok then NS.Print("slot probe failed: " .. tostring(err)) end
    return
  end
  if msg and msg:lower():match("^%s*probe%s+container%s*$") then
    local ok, err = pcall(ContainerProbe)
    if not ok then NS.Print("container probe failed: " .. tostring(err)) end
    return
  end
  local modeArg = msg and msg:lower():match("^%s*missingmode%s*(%a*)%s*$")
  if modeArg then
    if modeArg == "displace" or modeArg == "occlude" then
      NS.db.tints.missingMode = modeArg
      -- Groups cannot be edited after creation and the two modes build
      -- entirely different objects, so this is a full rebuild, not a repaint.
      NS.RebuildAllRigs(true)
    elseif modeArg ~= "" then
      NS.Print("usage: |cffffff00/pt missingmode occlude|displace|r")
      return
    end
    local mode = NS.db.tints.missingMode or "displace"
    NS.Print(("missing-rule mode: |cff55dd55%s|r"):format(mode))
    if mode == "displace" then
      NS.Print("  the wash is pushed off screen when the debuff lands -- no bar")
      NS.Print("  replica, no repaint poll, and |cffffff00combat-only is per rule|r.")
      NS.Print("  |cffffcc00Costs a 10-button pool per rule|r where occlude costs 1. /pt perf")
    else
      NS.Print("  the wash is covered by a replica of the bar when the debuff lands.")
      NS.Print("  Cheapest, but combat-only applies to |cffffff00all|r missing rules together.")
    end
    return
  end
  local captureArg = msg and msg:lower():match("^%s*capture%s*(.-)%s*$")
  if captureArg then
    local ok, err = pcall(Capture, captureArg)
    if not ok then NS.Print("capture failed: " .. tostring(err)) end
    return
  end
  local adapterArg = msg and msg:lower():match("^%s*adapter%s*(.-)%s*$")
  if adapterArg then
    local ok, err = pcall(PrintAdapter, adapterArg)
    if not ok then NS.Print("adapter failed: " .. tostring(err)) end
    return
  end
  -- Kept because it is in the README and in people's muscle memory, but it
  -- now writes the ADAPTER's value, not a global. A global pinFlat overrode
  -- every adapter's shipped default at once, which is precisely the coupling
  -- per-adapter settings exist to remove.
  local pinArg = msg and msg:lower():match("^%s*pinflat%s*(%a*)%s*$")
  if pinArg then
    if pinArg ~= "" and pinArg ~= "on" and pinArg ~= "off" and pinArg ~= "auto" then
      NS.Print("usage: |cffffff00/pt pinflat on|off|auto|r")
      return
    end
    local ok, err = pcall(PrintAdapter, "pinflat " .. pinArg)
    if not ok then NS.Print("pinflat failed: " .. tostring(err)) end
    return
  end
  if msg and msg:lower():match("^%s*layers%s*$") then
    local ok, err = pcall(PrintLayers)
    if not ok then NS.Print("layers failed: " .. tostring(err)) end
    return
  end
  local slotsArg = msg and msg:lower():match("^%s*slots%s*(%a*)%s*$")
  if slotsArg then
    if slotsArg == "off" then
      NS.db.useAuraSlots = false
    elseif slotsArg == "on" then
      NS.db.useAuraSlots = true
    end
    local using = NS.slotApiPresent and NS.db.useAuraSlots ~= false
    NS.Print(("aura slots: %s%s|r%s"):format(
      using and "|cff55dd55" or "|cffffcc00",
      using and "ON (1 texture per rule)" or "OFF (10 per rule, 100 per combo)",
      NS.slotApiPresent and "" or " -- unavailable on this client"))
    if slotsArg == "off" or slotsArg == "on" then
      NS.RebuildAllRigs(true)
      NS.Print("rebuilt. |cffffff00/pt bench build|r to see the difference.")
    end
    return
  end
  if msg and msg:lower():match("^%s*perf%s*$") then
    local ok, err = pcall(PrintPerf)
    if not ok then NS.Print("perf failed: " .. tostring(err)) end
    return
  end
  if msg and msg:lower():match("^%s*status%s*$") then
    local ok, err = pcall(PrintStatus)
    if not ok then NS.Print("status failed: " .. tostring(err)) end
    return
  end
  if msg and msg:lower():match("^%s*bar%s*$") then
    local ok, err = pcall(PrintBarDebug)
    if not ok then NS.Print("bar failed: " .. tostring(err)) end
    return
  end
  if msg and msg:lower():match("^%s*spellbook%s*$") then
    local ok, err = pcall(SpellbookProbe)
    if not ok then NS.Print("spellbook probe failed: " .. tostring(err)) end
    return
  end
  if InCombatLockdown() then
    -- Opening rebuilds secure aura containers, which the game refuses in
    -- combat, so say so rather than opening a window that cannot act.
    NS.Print("can't open in combat — try again once you're out of it.")
    return
  end
  NS.OpenOptions()
end
