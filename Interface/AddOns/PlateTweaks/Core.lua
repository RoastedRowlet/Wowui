local _, NS = ...

-- PlateTweaks: nameplate coloring and aura icons driven by your own debuffs,
-- for whatever nameplate addon you run.
--
-- Nothing here reads aura state — 12.x secrets forbid that. Secure aura
-- containers evaluate the conditions and hand back visibility; we only build
-- and place frames. See Tints.lua for the AND/NOT gate mechanics.

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
    -- Off by default: most nameplate addons already draw aura icons, so this
    -- is for people running Blizzard's default plates (or who want a second,
    -- differently-filtered row).
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
    -- 0-3 decimal places. Only reaches the preview: the real countdown digits
    -- on a live nameplate are Blizzard's own cooldown-frame text, formatted
    -- by the client itself with no addon-facing precision control.
    timerPrecision = 1,
    showCount = true,
    countFont = "Expressway",
    countSize = 10,
    countOutline = "OUTLINE",
    countAnchor = "BOTTOMRIGHT",
    countX = 0,
    countY = 0,
  },
  -- A tint rule is a color plus debuffs that must ALL be on the unit:
  --   { color = {...}, conditions = { {spellID = n} }, enabled = true }
  -- Singles and combos are the same thing at different lengths.
  tints = {
    -- Two independent modules that happen to share a rule engine. Health
    -- colouring and border colouring can be run on their own or together, so
    -- each tab's toggle drives its own flag.
    enabled = true,        -- health (bar) colouring
    borderEnabled = true,  -- border colouring
    rules = {},       -- bar rules; ordered, index 1 wins overlaps
    borderRules = {}, -- border rules; their OWN independent priority stack
    -- Adjustment either side of a one-pixel inset, NOT an absolute inset.
    -- Tints draw above the bar, so a nameplate addon's border sits underneath
    -- and gets painted over; one pixel in is the setting that looks right, so
    -- it is the zero point. Positive pulls further in, negative pushes back
    -- out over the border.
    edgeAdjust = 0,
    -- Pandemic flash, via AuraButton:AddPandemicRegion. The engine owns the
    -- region's visibility and reveals it inside the aura's refresh window —
    -- no duration read, no timer, no polling on our side. Costs one extra
    -- texture per built combination, so it is opt-in.
    pandemic = {
      enabled = false,
      color = { r = 1, g = 1, b = 1, a = 0.45 },
      pulse = true,        -- animate, rather than a steady wash
      pulseSpeed = 0.35,   -- seconds per half-cycle; lower is faster
    },
    -- Every matching rule draws, so translucent tints from several matching
    -- rules would blend into a muddy third color instead of the top one
    -- winning. With this on, each rule also paints an opaque replica of the
    -- bar beneath its own tint, masking lower-priority rules.
    exclusive = true,
    -- One shared color for every rule's "Cover missing health" option (see
    -- NS.NormaliseRule) -- a fixed, dark "damage taken" look by default,
    -- deliberately NOT derived from the bar's own fill color, so the missing
    -- side reads as missing rather than as more full health.
    missingCoverColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.95 },
  },
  levelOffset = 1,
}

-- 75% rather than fully opaque. An opaque tint covers everything the host
-- nameplate draws INSIDE its health bar -- EllesmereUI's hash line, target and
-- mouseover highlights and absorb divider all live there, and our texture sits
-- on a child frame so it is always above them regardless of draw layer.
-- Three quarters keeps the colour readable while letting those through.
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
    -- Outside by default: an inside border eats the health bar and fights
    -- whatever the nameplate addon already draws at that edge, while an
    -- outside one reads as a halo and needs no reserve carved out of the bar.
    grow = "OUT",
    padding = 0,      -- gap between the bar edge and the border
  }
end

-- Fills in the halves a rule may be missing. Rules predate the border feature
-- and the bar-enable flag, so every read path has to tolerate their absence
-- rather than assume a migration ran.
function NS.NormaliseRule(rule)
  if not rule then return end
  if rule.barEnabled == nil then rule.barEnabled = true end
  rule.color = rule.color or DefaultColor()
  if not rule.border then rule.border = NS.DefaultBorder() end
  -- Whether this rule is allowed to paint your OWN target/focus plate. A
  -- rule can still match there; these just say the rule opts out of that one
  -- plate, e.g. so a debuff tint does not fight the game's own target glow.
  if rule.showOnTarget == nil then rule.showOnTarget = true end
  if rule.showOnFocus == nil then rule.showOnFocus = true end
  -- "solid" paints a flat colour (the original behaviour). "texture" copies
  -- the host bar's own art (atlas/texture/tex-coords) and tints it via vertex
  -- colour instead, so whatever pattern the nameplate addon draws survives
  -- underneath the rule's colour.
  rule.fillStyle = rule.fillStyle or "solid"
  -- Opaque cover over the MISSING (unfilled) side of the bar, painted as a
  -- live replica of the bar's own current art -- same technique as the
  -- underlay covers below use to hide a lower rule. Off by default: most
  -- host bars already draw something opaque there themselves, and this is
  -- only useful when they don't (the missing side reads as see-through).
  if rule.missingCover == nil then rule.missingCover = false end
  -- Inverts what the rule means: wash the bar while this debuff is ABSENT
  -- rather than while it is present. Not a second kind of rule -- same
  -- condition, same colour, same priority field -- so everything that reads a
  -- rule keeps working. See the Missing-debuff rules header in Tints.lua for
  -- how several coexist despite each one's cover being an opaque repaint of
  -- the whole bar.
  if rule.showWhenMissing == nil then rule.showWhenMissing = false end
  -- Single-debuff by construction. The options window never offers a second
  -- one on a missing rule and never offers MISSING on a rule that already has
  -- two, so this only catches data from before the feature -- and it drops the
  -- missing flag rather than a condition, since throwing away a debuff someone
  -- chose is the more destructive of the two.
  if rule.showWhenMissing
    and #(rule.conditions or {}) > (NS.MAX_MISSING_CONDITIONS or 1) then
    rule.showWhenMissing = false
  end
  -- Holds the wash off while the target is out of combat, so an untouched
  -- reminder doesn't light up every mob standing around before a pull --
  -- only ones you're actually fighting without the debuff on them. Off by
  -- default: some missing rules are exactly for a pre-pull buff check, where
  -- "out of combat" is precisely when you want the reminder.
  if rule.missingCombatOnly == nil then rule.missingCombatOnly = false end
  return rule
end

-- A border rule is the same structure with the halves swapped: it paints no
-- bar, and its border is on by definition. Kept as one shape so RuleSummary,
-- SortRules and RuleCovers work on either list without knowing which.
function NS.NormaliseBorderRule(rule)
  if not rule then return end
  rule.barEnabled = false
  rule.border = rule.border or NS.DefaultBorder()
  rule.border.enabled = true
  -- Never leave grow unset: the engine and the dropdown would each have to
  -- pick a fallback, and the moment those two disagree a rule draws one way
  -- and reports another.
  rule.border.grow = rule.border.grow or "OUT"
  rule.color = rule.color or DefaultColor()
  if rule.showOnTarget == nil then rule.showOnTarget = true end
  if rule.showOnFocus == nil then rule.showOnFocus = true end
  return rule
end

function NS.NewBorderRule()
  return NS.NormaliseBorderRule({ conditions = {}, enabled = true })
end


-- Per-character profiles. Rules are built from specific spell IDs, so one
-- shared config is wrong the moment you log into another class. Each
-- character gets its own store, seeded on first login by copying whatever
-- was in use before (so nobody loses a setup they already tuned).
--
-- Optionally per SPEC as well: an Affliction rule set is as wrong on Destro
-- as a Warlock one is on a Druid, and the spell IDs differ just as much.
function NS.CharacterKey()
  local name = UnitName("player") or "?"
  local realm = GetRealmName() or "?"
  return name .. " - " .. realm
end

-- Returns the spec's display name, or nil when it cannot be determined —
-- which is the normal state for a moment during login, before spec data has
-- arrived. nil is never treated as a spec: see ProfileKey.
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

-- The spec's numeric ID. Used for binding rather than the name, because the
-- name is localised and two classes can share one (there are several
-- "Restoration" specs).
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

-------------------------------------------------------------------------------
-- Profiles.
--
-- Named, account-wide, and shared: the same model every other addon uses.
-- A character points AT a profile rather than owning one, so two characters
-- can share a setup and one character can keep a different setup per spec.
--
--   PLATETWEAKS_PROFILES[name]        = the settings
--   PLATETWEAKS_SETTINGS.assign[char] = { default = name, specs = { [id] = name } }
--
-- Resolution is: this spec's binding, else this character's default, else
-- "Default". A spec binding is what "link this profile to a spec" means --
-- switch spec and the profile follows, with no separate scope switch.
-------------------------------------------------------------------------------

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

-- One-time move from the old per-character keys. Those keys become profile
-- NAMES, and the character is assigned to whichever it was using, so nobody
-- loses a setup they had tuned.
-- Fills in anything a saved profile predates. Kept separate from
-- InitializeConfig so the ordering is explicit: structure first, then defaults.
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

-- One-time: retire whatever is currently in "Default" and leave a clean one
-- behind.
--
-- "Default" was the profile every character fell through to, so it
-- accumulated one person's warlock rules and then handed them to their next
-- character, and their next. Now that a new character gets its own profile,
-- "Default" should be the blank slate its name implies -- but the setups
-- already living in it are real work and must not be deleted.
--
-- So it is RENAMED rather than cleared, and every assignment that resolved to
-- it is repointed at the renamed copy. Nobody's plates change appearance:
-- characters carry on using the same settings under a new profile name, and
-- "Default" is empty for whoever meets it next.
--
-- Includes assignments with no .default at all -- those resolve to
-- DEFAULT_PROFILE by fallback (see ProfileKey), so leaving them alone is
-- precisely how an existing character would silently lose everything.
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

-- A character seen for the first time gets its OWN profile, named after it,
-- rather than quietly sharing "Default" with every other character on the
-- account. Sharing was the old behaviour and it surprises people in one
-- direction only: you tune a rule on your warlock, log onto your druid, and
-- find you have changed the warlock too.
--
-- "First time" is deliberately strict: a character with NO assignment entry
-- at all. An entry that merely has no .default is an EXISTING character that
-- has been running on "Default" all along -- handing that one a fresh profile
-- on upgrade would read as losing every setting it had. Assignments() creates
-- an entry as a side effect, so this has to check before calling it.
--
-- Deliberately EMPTY, not seeded from "Default". Copying Default carried
-- whatever happened to be sitting in it onto every new character -- rules for
-- a class this one cannot cast, colours tuned for someone else -- which is
-- the opposite of a fresh start.
--
-- Empty is not bare: InitializeConfig merges NS.Defaults over any profile
-- missing keys, and NS.Defaults.tints.rules is itself {} -- so a new
-- character lands in exactly the state a brand new install does, which is the
-- state the addon is designed to be met in.
local function EnsureCharacterProfile()
  PLATETWEAKS_PROFILES = PLATETWEAKS_PROFILES or {}
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  PLATETWEAKS_SETTINGS.assign = PLATETWEAKS_SETTINGS.assign or {}

  local charKey = NS.CharacterKey()
  -- UnitName/GetRealmName can each be unavailable for a moment at login, and
  -- CharacterKey substitutes "?" for whichever is missing. Either half being
  -- unknown would otherwise mint a junk profile name that then persists.
  -- Skipping is safe: ProfileKey runs again (RefreshProfile on entering
  -- world) once both are known.
  if not charKey or charKey:find("%?") then return end

  -- Two cases get a profile: a character we have never seen (no entry), and
  -- one whose entry points at nothing.
  --
  -- The second is only safe to act on AFTER RetireLegacyDefault has run,
  -- which is what makes a nil .default unambiguous. Before it, nil meant
  -- "fall through to Default" and could be an existing character's real
  -- setup. After it, every pre-existing entry has been given an explicit
  -- name, so nil can only mean the profile was deleted (DeleteProfile clears
  -- the reference) -- and dropping that character onto the shared Default is
  -- the sharing this whole change exists to stop.
  --
  -- The one path that leaves nil untouched is a Default that held nothing, in
  -- which case those characters were resolving to an empty profile anyway and
  -- a blank personal one is the same thing by another name.
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

  -- Spec first: a binding is the more specific statement of intent. A nil
  -- specID (login, before spec data lands) simply falls through rather than
  -- inventing a key -- RefreshProfile re-resolves once it is known.
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

-- The key can change under us without a reload: a spec swap, or spec data
-- arriving late during login. Re-resolves and rebuilds only when the key
-- actually moved, so this is safe to call from any event.
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

-- Every path that changes which profile is live ends here, so none of them
-- can forget the rebuild. Forces a re-resolve even when the resulting name is
-- unchanged, since the profile's CONTENTS may have been replaced under it.
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

-- Point this character at an existing profile. Respects the spec binding: if
-- the current spec is bound, the choice re-points the BINDING, otherwise it
-- re-points the character default. Choosing while bound should not silently
-- change what every other spec uses.
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

-- Every specialization this class has, in the game's own order. Driven off
-- GetNumSpecializations so classes with four (Druid) or one (early levels)
-- need no special case.
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

-- Rename in place, carrying every assignment across. Done by moving the table
-- rather than copying it, so anything already holding a reference to the live
-- profile keeps working.
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
  db.tints = db.tints or CopyTable(NS.Defaults.tints)
  db.levelOffset = db.levelOffset or NS.Defaults.levelOffset

  for key, value in pairs(NS.Defaults.icons) do
    if db.icons[key] == nil then
      db.icons[key] = type(value) == "table" and CopyTable(value) or value
    end
  end
  for key, value in pairs(NS.Defaults.tints) do
    if db.tints[key] == nil then
      db.tints[key] = type(value) == "table" and CopyTable(value) or value
    end
  end

  db.tints.rules = db.tints.rules or {}
  db.tints.borderRules = db.tints.borderRules or {}
  for _, rule in ipairs(db.tints.rules) do NS.NormaliseRule(rule) end
  for _, rule in ipairs(db.tints.borderRules) do NS.NormaliseBorderRule(rule) end

  -- Borders used to be a half of a bar rule. They are their own list now, so
  -- any rule carrying one is SPLIT: the bar half stays put, the border half
  -- becomes a border rule with the same conditions. Nothing is lost and the
  -- plate looks identical afterwards.
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
  -- The Color Rules rail entry's whole-list twisty reads db.uiRailOpen.health
  -- / .border -- the same key it has always used. Mid-development this session
  -- that twisty was removed entirely (the list was always open, no toggle to
  -- persist), then reinstated. Anyone who had EVER collapsed it, at any point
  -- before or during that window, has a dormant `false` sitting under that key
  -- -- inert while there was no twisty reading it, live again the moment there
  -- was, with no click of their own. That reads as "my rules vanished". One
  -- clear, once, same shape as the border-rule migration above.
  if not db.railOpenMigrated then
    db.railOpenMigrated = true
    if db.uiRailOpen then
      db.uiRailOpen.health = nil
      db.uiRailOpen.border = nil
    end
  end

  db.uiSections = db.uiSections or {}

  -- Sections already default to open -- uiSections only ever stores an
  -- explicit false. But the settings window was reorganised into pages that
  -- mostly carry one section each, and anything collapsed under the old
  -- layout carried its collapsed state onto its new page, where a single
  -- closed section makes the page look empty.
  --
  -- Cleared once, not on every load: collapsing something afterwards still
  -- sticks, which is the whole point of storing it.
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

  -- Expressway became the default font, but a profile created before that
  -- still carries the old default and would keep it forever. Only the OLD
  -- DEFAULT is moved -- anyone who deliberately chose Friz Quadrata is
  -- indistinguishable from someone who never touched it, and this is the
  -- less annoying way to be wrong.
  if not db.fontsMigrated then
    db.fontsMigrated = true
    if db.icons.timerFont == "Friz Quadrata TT" then
      db.icons.timerFont = "Expressway"
    end
    if db.icons.countFont == "Friz Quadrata TT" then
      db.icons.countFont = "Expressway"
    end
  end

  -- `inset` was an absolute pixel count with 0 meaning flush to the bar edge.
  -- It is now an adjustment around a 1px baseline, so the same appearance is
  -- one lower. Carried across rather than reset: someone who had tuned it to
  -- 2 should still see 2 pixels, reading as +1.
  if db.tints.inset ~= nil then
    db.tints.edgeAdjust = db.tints.inset - 1
    db.tints.inset = nil
  end

  -- "Inactive" conditions are gone: they were the only feature needing the
  -- bar repainted, which hid host art, forced ordering, and only ever worked
  -- one at a time. Drop them, and drop any rule left with nothing to match.
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

  -- Migrate separate singles/combos/missing lists into unified rules.
  -- Combos led on draw order, so they take the higher priority slots, and
  -- inactive-bearing rules end up last (they are forced there anyway).
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

-- Raised 2 -> 3 -> 4 (v1.5.0) because the reason for 2 stopped being true.
--
-- The old ceiling was a COST one, and the cost it described belongs to the
-- AddAuraGroup path: a group pools ~10 buttons and displays an arbitrary one,
-- so a rule had to cover every combination of live buttons -- 100 textures and
-- 11 containers for two debuffs, 1000 and 111 for three. Three did not hold up
-- in practice, and that was the whole argument.
--
-- AddAuraSlot pools ONE (see SlotsAvailable in Tints.lua), so a chain now
-- costs one container and one texture PER LEVEL. Four debuffs is 4 containers
-- and 1 texture per plate. There is nothing left of the original objection.
--
-- Still capped rather than unlimited, for two reasons that are about the RULE
-- and not the engine: each level is another aura that must be live for the
-- rule to fire at all -- a four-debuff rule is a narrow thing that mostly does
-- not match -- and the fallback path (a client with no slot API, or
-- /pt slots off) is still the pooled one, where the old exponent applies and
-- four would be hopeless. Test any further raise with /pt slots off too.
--
-- NOTE: 3 and 4 are both untested on a live plate as of writing. If a depth
-- misbehaves the symptom to expect is INTERMITTENT firing rather than an
-- error -- a chain missing from the button the engine chose to display fails
-- silently. Watch for a rule that works right after /reload and stops later.
NS.MAX_RULE_CONDITIONS = 4

-- Missing rules are single-debuff, full stop -- not a cap that can be raised.
-- A missing rule's rank in the ladder already spends a chain level per rule
-- above it, and its own debuff spends one more; a second condition would need
-- another level interleaved into a sublevel budget that has no room for it
-- (see MissingWashSublevel in Tints.lua). The options window never offers a
-- second debuff on a missing rule, so this is a guard for data that predates
-- the feature rather than a limit anyone can reach by using it.
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
  -- A missing rule fires on exactly the opposite state to every other row in
  -- the same list, so the list itself has to say which one it is. Prefixed
  -- rather than appended: it changes how the icons that follow should be
  -- read, and the row is truncated from the right.
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

-- Most debuffs first, preserving the user's order within each size. A rule
-- with fewer debuffs placed above a rule with more would shadow it forever,
-- so this runs automatically whenever rules or conditions change.
-- Sorts whichever list it is handed; defaults to the bar rules so existing
-- call sites are unchanged.
-- Which rules in this list can never fire, and what is blocking each.
--
-- Matching is first-from-the-top, so a rule is dead when something ABOVE it
-- matches everything it matches. That happens exactly when the higher rule's
-- conditions are a SUBSET of the lower one's: "Agony" above "Agony +
-- Corruption" means the pair can never show, because Agony alone always wins
-- first. It is the single ordering mistake this addon allows you to make, and
-- until now nothing said so -- the rule simply never appeared.
--
-- Auto sort prevents it by putting more conditions first. Dragging cannot be
-- allowed to silently undo that, so rather than refusing the drop (which
-- makes reordering feel broken for the many valid moves) the offending rule
-- is reported and marked.
--
-- Returns a map of index -> index of the first rule blocking it.
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
    -- MISSING rules always sort below every normal rule -- their priority
    -- only means anything against OTHER missing rules (see the ladder in
    -- Tints.lua), so leaving one sorted by debuff count would routinely land
    -- it above a normal rule it can never actually win against, which is
    -- exactly the arrangement the rule table now warns about. Auto Sort
    -- should never produce that arrangement itself.
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

-- Jump straight to a position. Remove-then-insert rather than a swap: typing
-- "1" on the bottom rule should lift it to the top and push everything else
-- down one, not trade places with whatever happens to be first.
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
        local w, h = child:GetSize()
        local area = (w or 0) * (h or 0)
        if area > 0 then
          local _, y = child:GetCenter()
          if not best or area > best.area or (area == best.area and (y or 0) > best.y) then
            best = { bar = child, area = area, y = y or 0 }
          end
        end
      end
      best = ScanForStatusBar(child, depth + 1, best)
    end
  end
  return best
end

function NS.FindHealthBar(nameplate)
  -- Plater: detaches and hides Blizzard's own nameplate.UnitFrame, then draws
  -- its own bar in nameplate.unitFrame (lowercase u) -- a real StatusBar, but
  -- not necessarily parented to the nameplate (its "use UIParent" option
  -- reparents it to UIParent instead). A direct field read rather than a
  -- child-walk, so it works under aura secrecy and regardless of that option.
  if IsStatusBar(nameplate.unitFrame and nameplate.unitFrame.healthBar) then
    return nameplate.unitFrame.healthBar
  end

  -- EllesmereUI: plate child with a .health StatusBar.
  -- PlateTweaks: root child with a .bar StatusBar.
  -- Platynator: display child with .widgets; health widget has .statusBar.
  --
  -- IsShown() gates every branch here. Addons that swap display styles (e.g.
  -- Platynator switching bar skins on a combat/reaction change) can leave a
  -- retired or not-yet-active display as a sibling child rather than
  -- destroying it outright -- an unguarded match could latch onto that one
  -- instead of the currently-visible bar, building a rig whose textures are
  -- real but sit under a hidden ancestor and never render. This is exactly
  -- what "rig looks built per /pt status but nothing shows, only on some
  -- plates" turned out to be.
  for _, child in ipairs({nameplate:GetChildren()}) do
    if child:IsShown() then
      if IsStatusBar(child.health) and child.health:IsShown() then
        return child.health
      end
      if IsStatusBar(child.bar) and child.bar:IsShown() and (child.textFrame or child.iconContainer) then
        return child.bar
      end
      if child.widgets and child.AurasManager then
        for _, w in ipairs(child.widgets) do
          if w.kind == "bars" and w.details and w.details.kind == "health"
              and IsStatusBar(w.statusBar) and w.statusBar:IsShown() then
            return w.statusBar
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
      return healthBar
    end
  end

  -- Measuring the plate subtree can hit 12.1 restrictions, so only scan when
  -- unrestricted; the pending queue retries later.
  if not NS.IsRestricted() then
    local ok, best = pcall(ScanForStatusBar, nameplate, 1, nil)
    if ok and best then
      return best.bar
    end
  end
end

-------------------------------------------------------------------------------
-- Rig lifecycle
-------------------------------------------------------------------------------

local rigs = {}
local unitRigs = {}
local pendingUnits = {}
-- Unit tokens with a nameplate currently on screen, maintained from
-- NAME_PLATE_UNIT_ADDED/REMOVED. The authoritative list: those events pass
-- the token as an argument, whereas plate.namePlateUnitToken read back off
-- the frame proved unreliable (see ResyncVisiblePlates).
local activeUnits = {}
local rebuildPending = false

NS.rigs = rigs
-- Exposed for /pt status: a non-empty queue means plates arrived whose health
-- bar we could not find, which is invisible from anywhere else.
NS.pendingUnits = pendingUnits

-- Rig currently bound to a unit token, for callers that have a token rather
-- than a health bar.
function NS.UnitRig(unit) return unit and unitRigs[unit] or nil end

local eventFrame = CreateFrame("Frame")

-- Re-assigning the same unit churns the container's internal button pool,
-- which is what drove the runaway button counts (a max-1 group had pooled
-- ten buttons). Skip the call when nothing changed.
-- Always re-assign on plate add. Unit tokens ("nameplate1") are recycled for
-- different creatures, so caching the token and skipping SetUnit risks a
-- container staying bound to a dead mob. The earlier skip-if-same-token
-- optimization had exactly that hazard and measurably did not shrink pools.
-- `record` is optional: callers that just want the plain unit/no-unit
-- behaviour (there are none left, but nothing requires it) can omit it. When
-- present, its rule's showOnTarget/showOnFocus can veto this ONE rule's
-- containers for this one unit, without touching any other rule on the same
-- plate.
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
  -- The missing ladder carries a combat gate of its own, and this function is
  -- called on every rebind -- so without this, binding a plate would switch a
  -- closed ladder straight back on and the poll would only notice up to a
  -- quarter of a second later. `== false` rather than `not`: nil means the
  -- gate has not been evaluated yet, which is not the same as closed.
  -- Only when the gate is actually using ENABLEMENT to do its work. On the
  -- visibility lever the container is meant to stay enabled and simply not
  -- render, and disabling it here would fight the gate rather than help it.
  if unit and record and record.missingStack and rig.missingGateOpen == false
    and record.gateLever ~= "shown" then
    unit = nil
  end
  if unit then
    frame:SetUnit(unit)
    frame:SetEnabled(true)
  else
    frame:SetEnabled(false)
  end
end

-- Every stage is isolated: a failure in one subsystem must not stop the
-- others from being built, anchored, or — most importantly — handed a unit,
-- since a rig that never gets SetUnit shows nothing at all.
local function BuildRig(healthBar)
  local rig = { healthBar = healthBar, unit = nil, buildErrors = {} }
  rig.baseLevel = NS.BaseLevelFor(healthBar)

  local okTints, tintErr = pcall(NS.BuildTints, rig, healthBar)
  if not okTints then
    table.insert(rig.buildErrors, "tints: " .. tostring(tintErr))
  end
  local okIcons, iconErr = pcall(NS.BuildIcons, rig, healthBar)
  if not okIcons then
    table.insert(rig.buildErrors, "icons: " .. tostring(iconErr))
  end

  rigs[healthBar] = rig
  return rig
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
end

local function SetRigUnit(rig, unit)
  rig.unit = unit
  NS.SetTintsUnit(rig)
  NS.SetIconsUnit(rig)
end

-- BUILDING frames is blocked by COMBAT. Reading aura state is blocked by
-- SECRECY. These are different conditions and were being conflated:
-- NS.IsRestricted() is true for the whole of a dungeon, not just its fights,
-- because ShouldAurasBeSecret stays true between pulls. Gating rebuilds on it
-- meant a rule added inside a key could never take effect — the retry ran
-- behind the same test that was already failing, so it only landed once you
-- left the instance entirely.
--
-- Creating and colouring our own frames out of combat is fine in restricted
-- content; the addon does it on every plate. So the gate is combat alone.
function NS.CanBuild()
  return not InCombatLockdown()
end

-- Config changes alter the aura groups, which cannot be edited after
-- creation. Rather than forcing a /reload we retire the old containers and
-- build fresh ones; the retired frames stay hidden and unused.
-- A deterministic fingerprint of the configuration a rebuild would read.
--
-- Deliberately OVER-inclusive: it serialises the whole tints and icons config
-- rather than an enumerated list of "structural" fields. Getting such a list
-- wrong means a setting that silently never applies, which is a far worse
-- failure than occasionally rebuilding for a change that turned out not to
-- matter. Colour and alpha never reach here at all -- those go through the
-- Live path, which repaints existing textures instead of building new ones.
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
    levelOffset = NS.db and NS.db.levelOffset,
  }, {}, 0))

  -- The spell gate's answer comes from the SPELLBOOK, not the config, so a
  -- talent change can alter what would be built while every setting stays
  -- byte-identical. Folded in, and only computed while the gate is on.
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

  -- Nothing a rebuild reads has changed, so it would create an identical set
  -- of containers and textures and orphan the current ones. WoW can destroy
  -- neither, so that is permanent growth for no visible change -- which is
  -- most of "my memory climbs while I change settings out of combat": the
  -- options window calls Structural() from 30-odd places, and plenty of those
  -- edits leave the built result identical.
  -- Config may have changed since the last pass; anything derived from it has
  -- to be dropped before it is read again.
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

-- Every rule filters HARMFUL|PLAYER, and a debuff you applied can only exist
-- on something you can attack. So a friendly plate can never match any rule,
-- and rigging one costs a container and a texture per rule for nothing.
-- In a city or a busy raid group that was most of the work the addon did.
--
-- This used to answer "not sure" with YES, on the reasoning that a missed tint
-- is worse than a wasted container. In restricted content that reasoning
-- inverted: UnitCanAttack returns a secret value there, so EVERY plate came
-- back "not sure" and every friendly plate in the raid got rigged -- which is
-- both the biggest cost the addon pays and precisely where it can least afford
-- it. Aura secrecy is on exactly when the group is largest.
--
-- So: ask several independent questions, take the first that gives a real
-- answer, and if none of them do, do not guess -- defer. The plate goes back
-- into pendingUnits and the 1s backstop asks again. Almost every "unknown" is
-- a plate that appeared before its unit data was queryable, and it resolves on
-- the next tick.
local skippedPlates = 0
local unknownPlates = 0
NS.SkippedPlates = function() return skippedPlates end
NS.UnknownPlates = function() return unknownPlates end

-- A value we can actually branch on: present, and not a secret.
local function Usable(ok, value)
  if not ok or value == nil then return false end
  if issecretvalue and issecretvalue(value) then return false end
  return true
end

-- true = can carry our debuffs, false = cannot, nil = ask again later.
--
-- None of these are aura APIs, so none of them are secret for the reason
-- UnitCanAttack is; they are listed in order of how directly they answer the
-- question rather than by how likely they are to work.
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
    -- Some nameplate addons (Platynator among them) build their real bar
    -- frame a beat after the plate itself appears, so the very first lookup
    -- can lose a timing race that has nothing to do with combat or aura
    -- secrecy. One same-frame retry catches the common case; anything slower
    -- than that used to be abandoned forever once out of restricted content
    -- (the old gate here only ever queued a retry while NS.IsRestricted()
    -- was true) -- now every failure queues into pendingUnits, which the 1s
    -- backstop ticker keeps retrying for as long as the plate exists.
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
      -- Not "friendly", just not answerable yet. Left in pendingUnits so the
      -- backstop retries; nothing is built in the meantime, which is the whole
      -- point -- an unknown plate costs nothing until it is known.
      unknownPlates = unknownPlates + 1
      pendingUnits[unit] = true
    else
      skippedPlates = skippedPlates + 1
    end
    -- Health bars are pooled and recycled, so one that carried a hostile mob
    -- a moment ago can come back holding a friendly NPC. Retiring the unit is
    -- not optional: a rig left bound to a dead token keeps its containers
    -- enabled against whatever the token now points at.
    local existing = rigs[healthBar]
    if existing then
      SetRigUnit(existing, nil)
    end
    unitRigs[unit] = nil
    return
  end

  -- Blizzard's own aura row, if the user asked for it to be out of the way.
  if NS.ApplyBlizzardAuras then pcall(NS.ApplyBlizzardAuras, nameplate) end

  -- The bar object under this unit can be REPLACED, not just restyled --
  -- Platynator swaps in a different display frame when a unit becomes your
  -- target, which is why a plate that tinted fine stopped the moment it was
  -- targeted. Without this, the old rig stays in `rigs` with its containers
  -- still enabled against a frame nothing renders any more, and the new bar
  -- gets a second rig layered on top of that mess.
  local previous = unitRigs[unit]
  if previous and previous.healthBar ~= healthBar then
    SetRigUnit(previous, nil)
    pcall(NS.RetireTints, previous)
    pcall(NS.RetireIcons, previous)
    rigs[previous.healthBar] = nil
  end

  local rig = rigs[healthBar] or BuildRig(healthBar)
  AnchorRig(rig)
  -- Runs unconditionally: without it every container stays disabled.
  SetRigUnit(rig, unit)
  unitRigs[unit] = rig
end

-- A target/focus swap does not add or remove any plate, so the usual
-- Reapply path never runs -- it needs its own trigger. Cheap: this only
-- re-checks each already-built container's enabled state, it builds nothing.
local function ReapplyGating()
  for _, rig in pairs(unitRigs) do
    NS.SetTintsUnit(rig)
  end
end

local function OnPlateRemoved(unit)
  pendingUnits[unit] = nil
  local rig = unitRigs[unit]
  if rig then
    SetRigUnit(rig, nil)
    unitRigs[unit] = nil
  end
end

-- Re-attach to every plate the client currently shows. NAME_PLATE_UNIT_ADDED
-- fired for these once already, but if that happened while we could not build
-- (in combat) or before the config existed, the rig was never made. Cheap
-- enough to run on any event that suggests the world changed under us.
--
-- Driven by activeUnits (maintained from NAME_PLATE_UNIT_ADDED/REMOVED, which
-- hand us the token directly) rather than by walking C_NamePlate.GetNamePlates()
-- and reading plate.namePlateUnitToken off each frame. That field is NOT
-- reliably populated -- verified in-game: the frame GetNamePlateForUnit
-- returns for a live target was not even findable in the GetNamePlates()
-- list, so every token came back nil and this whole function silently
-- iterated nothing. It looked like it ran on every trigger and healed
-- nothing, which is exactly how a stale bar reference survived every
-- resync path in the addon.
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
-- Some nameplate addons swap a plate's bar for a different frame rather than
-- restyling the one they have -- Platynator does this when a unit becomes
-- your target -- which strands our rig on a frame that is no longer drawn.
-- The rig still looks healthy from the outside (built, bound, tints present),
-- so nothing else in the addon can detect this.
--
-- Comparing bar identity first is what keeps this safe to call often, and
-- keeps it invisible to addons that DON'T swap (EllesmereUI, Plater): their
-- bar is the same object every time, so this costs one FindHealthBar and a
-- table compare per plate and touches nothing. Calling the full
-- ResyncVisiblePlates instead would run SetRigUnit on every plate, churning
-- the secure aura button pools for every addon to fix a bug only one has.
local function ResyncSwappedBars()
  for unit in pairs(activeUnits) do
    local rig = unitRigs[unit]
    if rig and UnitExists(unit) then
      local plate = C_NamePlate.GetNamePlateForUnit(unit)
      if plate then
        local okBar, current = pcall(NS.FindHealthBar, plate)
        if okBar and current and current ~= rig.healthBar then
          pcall(OnPlateAdded, unit)
        end
      end
    end
  end
end
NS.ResyncVisiblePlates = ResyncVisiblePlates

-- One place that decides what "catch up" means, so every trigger below does
-- the same thing and none of them can drift.
--
-- `reason` is unread on purpose: it was a debug hook, and it is kept because
-- every call site reads as Reapply("combat ended") / Reapply("spec/talents"),
-- which documents the trigger at the point it happens better than a comment
-- would. Deleting it would only make those calls anonymous.
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
    for unit in pairs(pendingUnits) do
      pendingUnits[unit] = nil
      if UnitExists(unit) then
        OnPlateAdded(unit)
      end
    end

  -- Zoning rebuilds the whole nameplate world. Entering a key is also the
  -- moment aura secrecy flips on, which used to be the point everything
  -- quietly stopped being applied.
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Before anything else: the user should get the choice to unload while
    -- the addon has still done nothing they did not ask for.
    C_Timer.After(2, function()
      if NS.ShowFirstRunWarning then pcall(NS.ShowFirstRunWarning) end
    end)
    -- Spec data is often not ready at login, so the first profile resolve can
    -- land on the character key even when spec scope is on. This is where it
    -- gets corrected.
    C_Timer.After(0.5, function()
      if not NS.RefreshProfile("entering world") then
        Reapply("entering world")
      end
      -- Said once, and only to someone whose Default actually held something
      -- (see RetireLegacyDefault). Without it the rename is invisible until
      -- you happen to open the profile list, and "my Default is empty" is
      -- exactly the kind of thing that reads as data loss.
      if NS.pendingProfileNotice then
        local retired = NS.pendingProfileNotice
        NS.pendingProfileNotice = nil
        NS.Print(("your old Default profile was kept as |cff55dd55%s|r, and your characters still use it. |cffffcc00Default|r is now empty, so new characters start clean.")
          :format(retired))
      end
    end)

  -- Rules are lists of spell IDs, and which of those you actually have
  -- changes with spec and talents. Neither was handled at all before, which
  -- is why switching spec appeared to break colouring until a /reload.
  -- Neither event means a rule's DEBUFFS changed, only whether one of them is
  -- still allowed to show on this particular plate -- so no rebuild, just a
  -- re-check of who's enabled.
  elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
    -- Re-find health bars first, not just re-gate the containers. Targeting a
    -- unit can make its nameplate addon swap in a DIFFERENT bar frame
    -- (Platynator does exactly this), leaving our rig bound to the frame that
    -- just stopped being drawn -- the tint is still there, on a bar nobody can
    -- see any more. ReapplyGating alone never noticed: it only asks "should
    -- this container be enabled", never "is this still the right bar".
    -- Gated on the bar actually having changed, so this is a no-op for every
    -- addon that keeps one bar frame per plate.
    ResyncSwappedBars()
    ReapplyGating()

  elseif event == "PLAYER_SPECIALIZATION_CHANGED"
      or event == "ACTIVE_TALENT_GROUP_CHANGED"
      or event == "TRAIT_CONFIG_UPDATED" then
    rebuildPending = true
    -- Cast-to-aura mapping comes from the Cooldown Manager, whose contents
    -- change with spec and talents.
    if NS.WipeRelatedCache then NS.WipeRelatedCache() end
    -- Delayed: the spec API still reports the OLD spec for a moment after
    -- this event, so resolving immediately would load the profile you just
    -- left. RefreshProfile handles the swap when the scope is per-spec;
    -- Reapply covers the case where it is not and only a rebuild is due.
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

    -- Slot-API detection lives in Tints.lua now, on the container it is about
    -- to use. Probing here was too early: Blizzard_AuraContainer may not be
    -- loaded yet, so the probe failed and cached "unavailable" for the session.
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

-- Backstop. Every trigger above is an event that MIGHT not fire — a rebuild
-- queued during combat that ends without PLAYER_REGEN_ENABLED reaching us, a
-- profile copy, a plate that arrived while the config was still loading. This
-- costs one boolean check a second and closes all of them at once.
C_Timer.NewTicker(1.0, function()
  if not NS.db then return end
  if rebuildPending and NS.CanBuild() then
    Reapply("pending rebuild")
  elseif NS.colorPending and not InCombatLockdown() then
    NS.ApplyTintColors()
  end
  -- Plates whose health bar we could not find yet -- either genuinely
  -- restricted, or just lost the one-frame retry race above. Retried here
  -- regardless of restriction state, since that race is unrelated to it.
  for unit in pairs(pendingUnits) do
    if UnitExists(unit) then
      OnPlateAdded(unit)
    else
      pendingUnits[unit] = nil
    end
  end
  -- Backstop for bar swaps we have no event for. PLAYER_TARGET_CHANGED covers
  -- the trigger we can name; this covers the ones we cannot. Same identity
  -- check, so it stays free for addons that never swap.
  ResyncSwappedBars()
end)

-- "On Missing" tints are hidden by a cover painted to match the host bar,
-- whose color changes with threat and unit type. Cheap poll: a handful of
-- GetStatusBarColor reads, and only while a missing tint is configured.
C_Timer.NewTicker(0.25, function()
  if not NS.db then return end
  -- Covers exist only for "on missing" rules. Without this the tick still
  -- walked every rig and every rule to discover there was nothing to do,
  -- which is most setups paying for a feature they do not use.
  if not NS.AnyCovers() then return end
  for _, rig in pairs(rigs) do
    NS.UpdateCovers(rig)
  end
end)

-- A missing rule's "only while target is in combat" option (rule.
-- missingCombatOnly) has no config event to hook -- a target enters or
-- leaves combat with nothing in the addon's own settings changing, so it has
-- to be polled. UnitAffectingCombat is plain, unlike almost everything else
-- this addon reads, so this is a genuine per-unit check rather than the
-- predicate machinery the rest of the file needs.
--
-- Gated the same way the cover ticker above is: walked only while at least
-- one missing rule actually uses the option, so setups that never touch it
-- pay nothing for it.
local function AnyMissingCombatOnly()
  for _, rule in ipairs((NS.db.tints and NS.db.tints.rules) or {}) do
    if rule.showWhenMissing and rule.missingCombatOnly then return true end
  end
  return false
end

C_Timer.NewTicker(0.25, function()
  if not NS.db then return end
  if not AnyMissingCombatOnly() then return end
  for _, rig in pairs(rigs) do
    if rig.missingLadder and #rig.missingLadder > 0 and NS.UpdateMissingCombatGate then
      NS.UpdateMissingCombatGate(rig)
    end
  end
end)

-- The background pairing pump used to run here at 10Hz. Pairings are now built
-- in each aura button's own initializeFrame callback -- the only context the
-- engine permits -- so there is nothing left for a ticker to drain.


SLASH_PLATETWEAKS1 = "/platetweaks"
SLASH_PLATETWEAKS2 = "/pt"
-- Old names kept working: muscle memory outlives a rename.
SLASH_PLATETWEAKS3 = "/bp"
SLASH_PLATETWEAKS4 = "/bplates"
-- Read-only state dump. Deliberately usable in combat and inside a key: those
-- are the conditions worth inspecting, and the options window refuses to open
-- in either. Touches nothing but our own tables, so it cannot taint anything.
-- Everything /pt status knows, as data rather than as chat lines.
--
-- Split out so the Diagnostics page and the slash command render the same
-- facts and cannot drift apart -- the panel exists precisely because this
-- information is what someone needs when reporting a bug, and two versions of
-- it that disagree would be worse than one that scrolls away.
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
      -- Ladder only. `lever` says which mechanism the combat gate settled on
      -- (shown = cheap, enabled = re-initialises buttons), and `reinit` counts
      -- how many times a button came back through initializeFrame after
      -- already being built. A climbing reinit count is the signature of the
      -- gate churning; anything above zero on the "shown" lever would mean
      -- something ELSE is re-initialising and is worth knowing about.
      if record.gateLever then
        table.insert(flags, "lever=" .. tostring(record.gateLever))
      end
      if record.reinits and record.reinits > 0 then
        table.insert(flags, ("reinit=%d"):format(record.reinits))
      end
      if record.failures and record.failures > 0 then
        table.insert(flags, ("failures=%d"):format(record.failures))
      end
      table.insert(info.rules, {
        index = index,
        conditions = record.spellCount or 0,
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

  -- What the addon found on the current target specifically, which is the
  -- question /pt bar answers and the one that matters when a single plate
  -- misbehaves while everything else looks healthy.
  if UnitExists("target") then
    local target = { name = UnitName("target") or "target" }
    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    if not nameplate then
      target.note = "no nameplate on screen"
    else
      local healthBar = NS.FindHealthBar(nameplate)
      if not healthBar then
        target.note = "no health bar found by any adapter"
      else
        target.bar = tostring(healthBar)
        target.isPlater = NS.IsPlaterBar and NS.IsPlaterBar(healthBar) or false
        local okLevel, level = pcall(healthBar.GetFrameLevel, healthBar)
        target.frameLevel = okLevel and level or nil
        local rig = rigs[healthBar]
        if not rig then
          target.note = "health bar found, but no rig built for it"
        else
          target.rigged = true
          target.baseLevel = rig.baseLevel
          local shown, total = 0, 0
          for _, record in ipairs(rig.rules or {}) do
            for _, tex in ipairs(record.tints or {}) do
              total = total + 1
              local okShown, isShown = pcall(tex.IsShown, tex)
              if okShown and isShown then shown = shown + 1 end
            end
          end
          target.tintsShown, target.tintsTotal = shown, total
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
    slotState = "|cff808080not determined yet|r -- no rig built since login"
  end
  NS.Print(("aura slots: %s"):format(slotState))
  NS.Print(("plates %d | rigged %d | bound %d | no health bar %d | friendly skipped %d | hostility unknown %d")
    :format(info.plates, info.rigged, info.bound, info.pending, info.skipped, info.unknown or 0))
  if info.errored > 0 then
    NS.Print(("build errors on %d rig(s): %s"):format(info.errored, tostring(info.firstError)))
  end

  for _, rule in ipairs(info.rules) do
    local flags = #rule.flags > 0 and (" " .. table.concat(rule.flags, " ")) or ""
    NS.Print(("rule %d: %d cond | hosts %d | containers %d | combos %d | tints %d | borders %d%s")
      :format(rule.index, rule.conditions, rule.hosts, rule.containers,
        rule.combos, rule.tints, rule.borders, flags))
    if rule.lastError then
      NS.Print("  first error: " .. rule.lastError)
    end
  end
end

-- Diagnostic for "the rig says it built tints but nothing is visible" reports
-- (see PrintStatus): dumps exactly what got created for your current
-- target's nameplate -- the health bar object itself, its frame level, and
-- every tint texture's actual on-screen state (shown/alpha/size/level)
-- rather than just the counts PrintStatus already gives.
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
    -- Everything read off an aura button has to survive being SECRET.
    --
    -- The first version of this used the strata as a table key and threw
    -- "cannot be indexed with secret keys" -- which is itself the answer to
    -- part of the question: the container hands these frames out with their
    -- strata hidden, so it is not something this addon can read, compare, or
    -- reason about at runtime.
    local function Describe(value)
      if value == nil then return "nil" end
      if issecretvalue and issecretvalue(value) then return "|cffffcc00secret|r" end
      return tostring(value)
    end

    local okStrata, outStrata = pcall(rig.outline.GetFrameStrata, rig.outline)
    local highest, where, hiStrata = -1, "?", "nil"
    local secretStrata, readableStrata = 0, 0
    for index, record in ipairs(rig.rules or {}) do
      for name, group in pairs({ containers = record.containers, hosts = record.hosts,
                                 tintHosts = record.tintHosts }) do
        for _, host in ipairs(group or {}) do
          local okS, hostStrata = pcall(host.GetFrameStrata, host)
          if okS and issecretvalue and issecretvalue(hostStrata) then
            secretStrata = secretStrata + 1
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
    NS.Print(("  highest rule frame: strata %s level %s (%s)"):format(
      hiStrata, tostring(highest), where))
    NS.Print(("  rule frames with a readable strata: %d | secret: %d"):format(
      readableStrata, secretStrata))
  end

  NS.Print(("healthBar: %s | frameLevel %s | strata %s | isPlaterBar %s | rig.baseLevel %s"):format(
    tostring(healthBar and healthBar:GetName() or healthBar),
    tostring(healthBar and healthBar:GetFrameLevel()),
    tostring(healthBar and healthBar.GetFrameStrata and healthBar:GetFrameStrata()),
    tostring(healthBar and NS.IsPlaterBar and NS.IsPlaterBar(healthBar)),
    tostring(rig.baseLevel)))

  for index, record in ipairs(rig.rules or {}) do
    if #(record.tints or {}) > 0 or #(record.hosts or {}) > 0 then
      NS.Print(("rule %d: recordLevel %s | hosts %d | tints %d"):format(
        index, tostring(record.level), #(record.hosts or {}), #(record.tints or {})))
      for ti, tex in ipairs(record.tints) do
        local okShown, shown = pcall(tex.IsShown, tex)
        local okAlpha, alpha = pcall(tex.GetAlpha, tex)
        local okW, w = pcall(tex.GetWidth, tex)
        local okH, h = pcall(tex.GetHeight, tex)
        local owner = tex:GetParent()
        local okLevel, level = pcall(owner.GetFrameLevel, owner)
        local okOwnerShown, ownerShown = pcall(owner.IsShown, owner)
        local okVisible, visible = pcall(owner.IsVisible, owner)
        NS.Print(("  tint %d: shown %s | alpha %s | size %sx%s | ownerLevel %s | ownerShown %s | ownerVisible %s"):format(
          ti, tostring(okShown and shown), tostring(okAlpha and alpha),
          tostring(okW and w), tostring(okH and h), tostring(okLevel and level),
          tostring(okOwnerShown and ownerShown), tostring(okVisible and visible)))
      end
    end
  end
end

-- What this addon costs, in the units that actually matter.
--
-- Lua CPU is the wrong measure here and will read as ~0: almost nothing runs
-- per frame. The cost is what the engine renders and keeps resident -- secure
-- aura containers and textures, multiplied by every nameplate on screen -- so
-- that is what this counts, plus a projection at a full plate count since a
-- quiet test spot is not what a pull looks like.
local function PrintPerf()
  local BUSY_PLATES = 40

  local rigCount = 0
  local totals = { containers = 0, textures = 0 }
  local rows = {}

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

  local busyTextures = totals.textures / rigCount * BUSY_PLATES
  NS.Print(("busy pull estimate: %.0f textures, %.0f frames")
    :format(busyTextures, totals.containers / rigCount * BUSY_PLATES))

  -- The texture count on its own says nothing to most people. Multiplied by a
  -- measured per-texture cost it becomes the number that matters: how long the
  -- game stops for when this many plates are rebuilt at once, which is exactly
  -- what happens as combat ends with a rebuild queued.
  --
  -- The default is a rough figure; /pt bench build replaces it with a reading
  -- from this machine, which is the only one worth quoting back at anyone.
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

-- /pt bench -- the fill path, measured on its own.
--
-- Solo, in a city, with no group and no nameplates. The loop it times is the
-- one that dominates a raid (ApplyRuleFill over every texture on every rig),
-- and none of that loop needs a real plate, so it can be measured somewhere
-- quiet and repeatable instead of inferred from a raid log.
--
-- Runs the same work twice, cache off then on. An A/B against the same rule on
-- the same frame settles what the cache is worth; a single number would not.
-- /pt bench build -- the BUILD path, which is a different animal entirely.
--
-- Anchoring re-points textures that already exist. Building CREATES them, plus
-- the secure aura containers behind them, and that is what a plate appearing
-- costs. Measured with a real rebuild over whatever is on screen, because
-- there is no way to fake a secure container.
--
-- Honest cost of running this: a rebuild orphans everything the previous one
-- made, and WoW cannot destroy a frame or texture. Measuring is not free --
-- see the orphan count in /pt perf afterwards.
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

-- Every probe below writes to BOTH chat and PLATETWEAKS_DEBUG.cdm (a plain
-- array of strings). Chat truncates and scrolls; the SavedVariables file does
-- not -- WoW serializes it to plain Lua on /reload, so a dump too big for
-- chat is still there afterward, readable outside the game entirely, at:
--   WTF\Account\<account>\SavedVariables\PlateTweaks.lua
-- The table is rebuilt from scratch on every run rather than appended to, so
-- stale lines from a previous probe never linger into the next reading.
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

-- What does the spellbook actually hand us on THIS character?
--
-- The question this exists to settle: NS.CanApplyAura currently asks
-- IsPlayerSpell about one ID at a time, which can only ever confirm an ID it
-- is already holding. Enumerating the book instead would let it ask "does this
-- character have any spell that could produce this aura", which is the
-- question that actually matters and the one that would make the spell gate
-- safe enough to turn on by default.
--
-- Nothing here is assumed. Every namespace, function and field is checked for
-- existence before it is called and reported as absent when it is missing, so
-- the output is evidence about this client rather than a restatement of what
-- the code expected to find. Read-only throughout.
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

-- /pt probe container -- what the aura container will actually let us ask for.
--
-- The reason a combo rule costs ~100 textures per plate is NOT the number of
-- aura combinations. It is the POOL. The engine pre-creates a set of buttons
-- per aura group and calls initializeFrame on every one of them, and a texture
-- is attached in that callback because it is the only context where the button
-- is touchable. Chain two groups and the count is pool x pool.
--
-- SetAuraGroupMaxFrameCount(key, 1) already says "display at most one". If the
-- engine also exposes a way to size the POOL, the whole cost collapses --
-- a single rule from ~10 textures to ~1, a combo from ~100 to ~1. Nothing in
-- this addon has ever enumerated that surface, so this asks.
--
-- Read-only. Creates one container and one texture, which are then abandoned;
-- that is unavoidable and is why this is a probe rather than something the
-- addon does at runtime.
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

  -- The other multiplier: a rule border is FOUR textures per combination, so a
  -- combo rule with a border is ~400. One sliced texture would draw the same
  -- hollow rectangle, if the client supports slicing on a plain texture.
  -- The number this whole investigation turns on: how many buttons does the
  -- engine actually pool for one group? Every one of them gets initializeFrame
  -- and therefore a texture, and a combo rule is this number SQUARED.
  --
  -- Measured rather than assumed. If it comes back 1, the pool model is wrong
  -- and ~100 textures per combo is coming from somewhere else entirely -- which
  -- would be worth knowing before optimising the wrong thing.
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

-- /pt probe slot -- the AuraSlot API, which may be the whole answer.
--
-- An aura GROUP pools ten frames and calls initializeFrame on every one, so a
-- rule pays ten textures and a combo pays a hundred. The container also
-- exposes AddAuraSlot / SetAuraSlotCandidateFilters / SetAuraSlotFilterString
-- / SetAuraSlotSortMethod -- a parallel surface this addon has never used, and
-- one whose name suggests ONE frame for one aura rather than a pool of ten.
--
-- If that is what it is, a single rule costs 1 texture instead of 10 and a
-- combo 1 instead of 100.
--
-- The signature is unknown, so this calls it wrong on purpose: WoW's C
-- functions answer a bad call with a Usage: string that documents the real
-- one. Cheaper than guessing, and the error text is the actual documentation.
local slotProbeRun = 0

-- /pt probe slot -- can an aura SLOT carry our textures?
--
-- Established so far: AddAuraSlot(slotKey, filterString, options) accepts an
-- options table and fires initializeFrame exactly ONCE, where an aura group
-- pools ten frames and fires ten times. Slots are not visible to the group
-- getters, so the only handle on that single frame is the argument the
-- callback receives -- which the previous run threw away.
--
-- Everything below happens INSIDE the callback on purpose. That is the one
-- context where an aura button is touchable; from anywhere else it is a
-- forbidden object, which is the constraint the whole engine is built around.
--
-- If a texture can be created there, a rule costs 1 texture instead of 10, and
-- a combo -- nesting a second slot inside the first -- costs 1 instead of 100.
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

-- /pt probe slotlive <spellID> -- the last question slots have to answer.
--
-- The static probe settled that a slot pools ONE frame, that the frame takes a
-- texture, and that a second slot nests inside it. What it could not settle is
-- GATING: it reported IsShown() = true on a button with no unit and a disabled
-- container, and if a slot button is simply always shown then its texture is
-- always painted and the whole mechanism is useless -- ancestry being the AND
-- is the entire reason the current design works.
--
-- So: attach a real slot to the real target's real health bar, paint it
-- magenta, and watch. Apply the debuff and it should appear; drop it and it
-- should go. Nothing else in the addon can answer this -- it needs a live
-- aura, which is exactly what cannot be simulated.
--
-- Leaves a container and a texture on that bar until /reload. It is a probe.
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
  ---------------------------------------------------------------------
  -- COOLDOWN MANAGER SOUND SURFACE.
  --
  -- The default Cooldown Manager (Edit Mode) already plays sounds on its
  -- own tracked items -- that is engine-driven, not addon-driven, so it is
  -- not gated the way arbitrary aura sound registration is. The question
  -- is whether anything about that sound behavior is exposed to addons:
  -- a setter to arm/disarm it, a field on the info struct, or a method on
  -- the actual viewer FRAMES (not just the C_ namespace) that we have
  -- never enumerated before.
  --
  -- Three surfaces, in order of how likely each is to matter:
  --   1. Full C_CooldownViewer function list -- we have only ever called
  --      three of these (GetCooldownViewerCategorySet,
  --      GetCooldownViewerCooldownInfo, and whatever Consider() uses).
  --   2. The REAL fields of a live info struct -- the addon only ever
  --      reads spellID/overrideSpellID/hasAura/selfAura/linkedSpellIDs.
  --      Dumping the whole table may show fields nobody has looked at.
  --   3. The actual global viewer frames Blizzard ships
  --      (EssentialCooldownViewer, UtilityCooldownViewer,
  --      BuffIconCooldownViewer, BuffBarCooldownViewer) -- these are real
  --      UI frames with their own mixins, separate from the C_ API, and
  --      per-item child frames may carry sound-kit setters the way aura
  --      buttons carry SetIcon/SetDurationText.
  ---------------------------------------------------------------------
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

  -- Dump every live info struct we can find, not just one -- a sound-related
  -- field might only ride along on aura-category entries, or only on
  -- ability entries, and a single sample could easily miss it. Chat gets a
  -- count plus the UNION of every field name ever seen (the actually
  -- decision-relevant summary); every full struct, with values, goes to the
  -- file only.
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
