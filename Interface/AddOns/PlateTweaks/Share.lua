local _, NS = ...

-------------------------------------------------------------------------------
-- Profile sharing.
--
-- SavedVariables are per account, so a text string is the only way a setup
-- reaches another install. Export writes one, import reads it back.
--
-- Encoding is the client's own: CBOR -> deflate -> base64, through
-- C_EncodingUtil. No library to ship, and nothing anywhere near loadstring --
-- an import string is DATA being decoded, never Lua being run, so a hostile
-- string cannot execute anything.
--
-- What it CAN still do is hand us a table of the wrong SHAPE, and the engine
-- reads these fields on a hot path without re-checking them. A string where a
-- number belongs, or a size of 1e9, reaches SetSize and then errors on every
-- nameplate, every frame. So everything crossing the boundary goes through the
-- whitelist below: known keys only, coerced to the expected type, clamped to a
-- sane range, unknown keys dropped.
--
-- Applied on the way OUT as well as IN. A profile that has picked up junk from
-- an older version should not pass it on, and sanitising both ends means the
-- two directions cannot disagree about what a profile is.
-------------------------------------------------------------------------------

-- Bumped only when the payload shape changes in a way an older client could
-- not read. Field ADDITIONS do not need it -- an older client drops unknown
-- keys and a newer one fills in defaults, which is the whole point of running
-- the result through NS.InitializeConfig afterwards.
local SCHEMA = 1

-- Short, and carries the schema number so a future format can be told apart
-- before it is decoded rather than after it fails.
local PREFIX = "PT1-"
NS.SHARE_PREFIX = PREFIX

-- Every call is behind this. C_EncodingUtil ships with the client this addon
-- targets, but a missing table would otherwise surface as "attempt to index a
-- nil value" inside a button handler, which says nothing useful.
local function Encoding()
  local api = _G.C_EncodingUtil
  if type(api) ~= "table" then return nil end
  local needed = {
    "SerializeCBOR", "DeserializeCBOR",
    "CompressString", "DecompressString",
    "EncodeBase64", "DecodeBase64",
  }
  for _, fn in ipairs(needed) do
    if type(api[fn]) ~= "function" then return nil end
  end
  return api
end

NS.ShareAvailable = function() return Encoding() ~= nil end

-------------------------------------------------------------------------------
-- Bounds
--
-- Not guesses at what a user would choose -- they are the point past which a
-- value stops being a setting and starts being a way to wedge the client.
-------------------------------------------------------------------------------

-- Comfortably past any screen dimension, and far short of what breaks a frame.
local MAX_ABS = 4096
-- Rule lists are drawn one row each in the rail. A hundred is already
-- unusable; this only has to stop a payload claiming a million.
local MAX_RULES = 100
local MAX_ICONS = 40
-- Texture and font names. The longest LibSharedMedia name in the wild is
-- nowhere near this.
local MAX_STRING = 64

local function Bool(value, default)
  if type(value) == "boolean" then return value end
  return default
end

local function Num(value, default)
  if type(value) ~= "number" then return default end
  -- NaN is the one value that fails a comparison with itself, and it survives
  -- every clamp written the obvious way. inf reaches SetSize intact.
  if value ~= value then return default end
  if value == math.huge or value == -math.huge then return default end
  if value > MAX_ABS then return MAX_ABS end
  if value < -MAX_ABS then return -MAX_ABS end
  return value
end

-- Integers where the game demands one: a fractional spell ID or icon count is
-- not a smaller problem than a string, it just fails further away.
local function Int(value, default)
  local n = Num(value, nil)
  if not n then return default end
  return math.floor(n)
end

local function Str(value)
  if type(value) ~= "string" then return nil end
  -- "|" opens a UI escape sequence. These are texture and font names picked
  -- from a dropdown in normal use, but an imported one is arbitrary text that
  -- ends up in a label -- and |H...|h would turn it into a clickable link, or
  -- |T...|t into an image. Control characters get the same treatment for the
  -- same reason.
  value = value:gsub("|", ""):gsub("%c", "")
  if value == "" then return nil end
  return value:sub(1, MAX_STRING)
end

local function OneOf(value, allowed, default)
  if type(value) == "string" and allowed[value] then return value end
  return default
end

local function Channel(value, default)
  local n = Num(value, default)
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

-- A colour is four channels in 0-1 and nothing else. `fallback` is used when
-- the whole table is missing or malformed, so a broken colour lands on the
-- rule's own default rather than on black.
local function Colour(value, fallback)
  if type(value) ~= "table" then
    return fallback and CopyTable(fallback) or nil
  end
  return {
    r = Channel(value.r, 1),
    g = Channel(value.g, 1),
    b = Channel(value.b, 1),
    -- Alpha absent means opaque. A tint that silently imported at alpha 0
    -- would look like the rule had not imported at all.
    a = Channel(value.a, 1),
  }
end

-- Deliberately NOT routed through Num/Int.
--
-- Those clamp to MAX_ABS, which is a bound for PIXEL values -- offsets, sizes,
-- thicknesses. Spell IDs are not pixels: Agony is 980 but Corruption's aura is
-- 146739, and almost every modern ID is above 4096.
--
-- Clamping one does not produce an obviously broken rule. It produces a
-- DIFFERENT REAL SPELL: 4096 is "Raptor Hide Harness". The rule then imports
-- cleanly, displays a plausible icon and name, and simply never matches. That
-- is far worse than dropping it, which is why the range is checked here and
-- an out-of-range value is discarded rather than pulled to a boundary.
local MAX_SPELL_ID = 10000000

local function SpellID(value)
  if type(value) ~= "number" then return nil end
  if value ~= value then return nil end
  if value == math.huge or value == -math.huge then return nil end
  local id = math.floor(value)
  if id < 1 or id > MAX_SPELL_ID then return nil end
  return id
end

-------------------------------------------------------------------------------
-- Schema
--
-- One table per shape. Adding a setting means adding it here too -- and
-- NS.ShareSchemaGaps below exists so that forgetting is noticed rather than
-- silently dropping the setting from every export.
-------------------------------------------------------------------------------

local ANCHORS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local ICON_GROW = { LEFT = true, CENTER = true, RIGHT = true }
local OUTLINES = { NONE = true, OUTLINE = true, THICKOUTLINE = true }
local BORDER_GROW = { IN = true, OUT = true }
local FILL_STYLES = { solid = true, texture = true }
local OUTLINE_SIDES = { top = true, bottom = true, left = true, right = true }

local function SanitiseBorder(source)
  if type(source) ~= "table" then return nil end
  return {
    enabled   = Bool(source.enabled, false),
    color     = Colour(source.color, { r = 1, g = 0.85, b = 0.1, a = 1 }),
    thickness = Num(source.thickness, 2),
    grow      = OneOf(source.grow, BORDER_GROW, "OUT"),
    padding   = Num(source.padding, 0),
  }
end

local function SanitiseConditions(source)
  local out, seen = {}, {}
  if type(source) ~= "table" then return out end
  for _, entry in ipairs(source) do
    -- Conditions are the one field where dropping a bad entry is worse than
    -- dropping the rule: a rule that quietly loses a debuff still matches, on
    -- looser terms than its author meant. Counted by the caller.
    local id = type(entry) == "table" and SpellID(entry.spellID) or nil
    -- The same debuff twice is not a stricter rule, it is the same rule with a
    -- wasted chain level -- and it is what a corrupted payload looks like when
    -- several different IDs have collapsed onto one value.
    if id and not seen[id] then
      seen[id] = true
      table.insert(out, { spellID = id })
    end
    if #out >= (NS.MAX_RULE_CONDITIONS or 4) then break end
  end
  return out
end

-- Shared by both rule lists. NormaliseRule / NormaliseBorderRule run over the
-- result later and settle whichever half does not apply, so this does not need
-- to know which list it is filling.
local function SanitiseRule(source)
  if type(source) ~= "table" then return nil end
  local conditions = SanitiseConditions(source.conditions)
  -- A rule with nothing to match on is not a rule. It would render in the rail
  -- as an empty row that can never fire.
  if #conditions == 0 then return nil end

  return {
    enabled           = Bool(source.enabled, true),
    barEnabled        = Bool(source.barEnabled, true),
    color             = Colour(source.color, NS.DefaultColor and NS.DefaultColor()),
    conditions        = conditions,
    border            = SanitiseBorder(source.border),
    showOnTarget      = Bool(source.showOnTarget, true),
    showOnFocus       = Bool(source.showOnFocus, true),
    fillStyle         = OneOf(source.fillStyle, FILL_STYLES, "solid"),
    -- Both may legitimately be nil: nil fillTexture is "Bar's own art" and nil
    -- barTexture is "Flat color", so absence is a real choice here, not a gap.
    fillTexture       = Str(source.fillTexture),
    fillTexturePicked = Bool(source.fillTexturePicked, false),
    barTexture        = Str(source.barTexture),
    missingCover      = Bool(source.missingCover, false),
    showWhenMissing   = Bool(source.showWhenMissing, false),
    missingCombatOnly = Bool(source.missingCombatOnly, false),
  }
end

local function SanitiseRuleList(source, dropped)
  local out = {}
  if type(source) ~= "table" then return out end
  for _, entry in ipairs(source) do
    if #out >= MAX_RULES then break end
    local rule = SanitiseRule(entry)
    if rule then
      table.insert(out, rule)
    elseif dropped then
      dropped.rules = (dropped.rules or 0) + 1
    end
  end
  return out
end

local function SanitiseOutlineSides(source)
  if type(source) ~= "table" then return nil end
  local out = {}
  -- Read as `~= false` everywhere (see PlateOutlineSide in Tints.lua), so only
  -- an explicit false is worth carrying and an unknown side key is noise.
  for side in pairs(OUTLINE_SIDES) do
    if source[side] == false then out[side] = false end
  end
  return out
end

local function SanitiseTints(source, dropped)
  source = type(source) == "table" and source or {}
  return {
    enabled             = Bool(source.enabled, true),
    borderEnabled       = Bool(source.borderEnabled, true),
    rules               = SanitiseRuleList(source.rules, dropped),
    borderRules         = SanitiseRuleList(source.borderRules, dropped),
    edgeAdjust          = Num(source.edgeAdjust, 0),
    missingCoverColor   = Colour(source.missingCoverColor,
                            { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }),
    gateUnknownSpells   = Bool(source.gateUnknownSpells, nil),
    plateOutline        = Bool(source.plateOutline, nil),
    plateOutlineColor   = Colour(source.plateOutlineColor, nil),
    plateOutlineSize    = Num(source.plateOutlineSize, nil),
    plateOutlineOffset  = Num(source.plateOutlineOffset, nil),
    plateOutlineSides   = SanitiseOutlineSides(source.plateOutlineSides),
    pandemic            = {
      enabled    = Bool(source.pandemic and source.pandemic.enabled, false),
      color      = Colour(source.pandemic and source.pandemic.color,
                     { r = 1, g = 1, b = 1, a = 0.45 }),
      pulse      = Bool(source.pandemic and source.pandemic.pulse, true),
      pulseSpeed = Num(source.pandemic and source.pandemic.pulseSpeed, 0.35),
    },
  }
end

local function SanitiseIconList(source)
  local out, seen = {}, {}
  if type(source) ~= "table" then return out end
  for _, entry in ipairs(source) do
    if #out >= MAX_ICONS then break end
    local id = type(entry) == "table" and SpellID(entry.spellID) or nil
    -- One icon per debuff. The list is a display order, so a repeat would draw
    -- the same icon twice in the row.
    if id and not seen[id] then
      seen[id] = true
      table.insert(out, { spellID = id })
    end
  end
  return out
end

local function SanitiseIcons(source)
  source = type(source) == "table" and source or {}
  local d = NS.Defaults.icons
  return {
    enabled           = Bool(source.enabled, d.enabled),
    list              = SanitiseIconList(source.list),
    size              = Num(source.size, d.size),
    spacing           = Num(source.spacing, d.spacing),
    anchor            = OneOf(source.anchor, ANCHORS, d.anchor),
    grow              = OneOf(source.grow, ICON_GROW, d.grow),
    padX              = Num(source.padX, d.padX),
    padY              = Num(source.padY, d.padY),
    maxPerRow         = Int(source.maxPerRow, d.maxPerRow),
    hideBlizzardAuras = Bool(source.hideBlizzardAuras, d.hideBlizzardAuras),
    borderSize        = Num(source.borderSize, d.borderSize),
    borderColor       = Colour(source.borderColor, d.borderColor),
    showSwirl         = Bool(source.showSwirl, d.showSwirl),
    showTimer         = Bool(source.showTimer, d.showTimer),
    timerFont         = Str(source.timerFont) or d.timerFont,
    timerSize         = Num(source.timerSize, d.timerSize),
    timerOutline      = OneOf(source.timerOutline, OUTLINES, d.timerOutline),
    timerAnchor       = OneOf(source.timerAnchor, ANCHORS, d.timerAnchor),
    timerX            = Num(source.timerX, d.timerX),
    timerY            = Num(source.timerY, d.timerY),
    timerPrecision    = Int(source.timerPrecision, d.timerPrecision),
    showCount         = Bool(source.showCount, d.showCount),
    countFont         = Str(source.countFont) or d.countFont,
    countSize         = Num(source.countSize, d.countSize),
    countOutline      = OneOf(source.countOutline, OUTLINES, d.countOutline),
    countAnchor       = OneOf(source.countAnchor, ANCHORS, d.countAnchor),
    countX            = Num(source.countX, d.countX),
    countY            = Num(source.countY, d.countY),
  }
end

local function SanitiseTweaks(source)
  source = type(source) == "table" and source or {}
  local out = {}
  -- The one place a Defaults walk is right: every tweak is a plain boolean and
  -- the defaults table is the complete list of them.
  for key, value in pairs(NS.Defaults.tweaks) do
    out[key] = Bool(source[key], value)
  end
  return out
end

-- The whole profile. Deliberately NOT everything in the table:
--
--   ui*            window position, rail state, which sections are open.
--                  Personal to the sender's screen; uiPosition would yank the
--                  recipient's window somewhere they did not put it.
--   *Migrated      one-shot markers for migrations that already ran on the
--                  sender's data. Carrying them across would tell the importer
--                  a migration had run on data that never saw it.
--   legacy keys    combos, list, spells, inset, exclusive and friends are
--                  migration INPUTS. They are consumed and cleared by
--                  InitializeConfig; exporting them would re-run migrations
--                  against a profile that is already current.
local function SanitiseProfile(source, dropped)
  source = type(source) == "table" and source or {}
  return {
    tints       = SanitiseTints(source.tints, dropped),
    icons       = SanitiseIcons(source.icons),
    tweaks      = SanitiseTweaks(source.tweaks),
    levelOffset = Num(source.levelOffset, NS.Defaults.levelOffset),
  }
end

-------------------------------------------------------------------------------
-- Export
-------------------------------------------------------------------------------

local function AddonVersion()
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not getMeta then return nil end
  local ok, version = pcall(getMeta, "PlateTweaks", "Version")
  return (ok and type(version) == "string") and version or nil
end

-- Returns string, note. `note` is non-nil when something was dropped on the
-- way out, so the page can say so rather than quietly exporting less than the
-- profile contains.
function NS.ExportProfile(name)
  local api = Encoding()
  if not api then
    return nil, "This client does not provide C_EncodingUtil, so sharing is unavailable."
  end

  name = name or NS.ProfileKey()
  local profile = PLATETWEAKS_PROFILES and PLATETWEAKS_PROFILES[name]
  if not profile then return nil, ("No profile named '%s'."):format(tostring(name)) end

  local dropped = {}
  local payload = {
    v       = SCHEMA,
    addon   = AddonVersion(),
    name    = name,
    profile = SanitiseProfile(profile, dropped),
  }

  local ok, serialized = pcall(api.SerializeCBOR, payload)
  if not ok or not serialized then return nil, "Could not serialize the profile." end
  local okC, compressed = pcall(api.CompressString, serialized)
  if not okC or not compressed then return nil, "Could not compress the profile." end
  local okE, encoded = pcall(api.EncodeBase64, compressed)
  if not okE or not encoded then return nil, "Could not encode the profile." end

  local note
  if dropped.rules and dropped.rules > 0 then
    note = ("%d rule(s) were skipped: no usable debuff on them.")
      :format(dropped.rules)
  end
  return PREFIX .. encoded, note
end

-------------------------------------------------------------------------------
-- Import
--
-- Split in two on purpose. Decode answers "what is in this string", and is
-- safe to call on every keystroke; Commit is the half that writes. Nothing
-- reaches a profile until someone has seen what they are about to get.
-------------------------------------------------------------------------------

function NS.DecodeShareString(text)
  local api = Encoding()
  if not api then
    return nil, "This client does not provide C_EncodingUtil, so sharing is unavailable."
  end
  if type(text) ~= "string" then return nil, "Paste an import string first." end

  text = strtrim(text)
  -- Pasting out of Discord or a forum commonly picks up wrapping. The payload
  -- is base64, which never legitimately contains whitespace.
  text = text:gsub("%s+", "")
  if text == "" then return nil, "Paste an import string first." end
  if text:sub(1, #PREFIX) ~= PREFIX then
    return nil, "That does not look like a PlateTweaks profile string."
  end

  local body = text:sub(#PREFIX + 1)
  local ok, compressed = pcall(api.DecodeBase64, body)
  if not ok or not compressed then return nil, "The string is damaged (bad encoding)." end
  local okD, serialized = pcall(api.DecompressString, compressed)
  if not okD or not serialized then return nil, "The string is damaged (bad compression)." end
  local okS, payload = pcall(api.DeserializeCBOR, serialized)
  if not okS or type(payload) ~= "table" then
    return nil, "The string is damaged (bad contents)."
  end

  local version = Int(payload.v, 0)
  if version > SCHEMA then
    return nil, ("This string was made by a newer version of PlateTweaks (format %d, this one reads %d). Update the addon.")
      :format(version, SCHEMA)
  end

  local dropped = {}
  return {
    schema  = version,
    addon   = Str(payload.addon),
    name    = Str(payload.name) or "Imported",
    profile = SanitiseProfile(payload.profile, dropped),
    dropped = dropped,
  }
end

-- What the string contains, in the terms the rule list uses, so the preview
-- can show it before anything is written.
--
-- The important column is `usable`. Rules name exact spell IDs, so a Warlock's
-- profile is inert on a Druid -- and nothing errors, it simply never matches,
-- which is the single most confusing way for an import to fail. CanApplyAura
-- answers honestly (it returns true when it genuinely cannot tell), so a
-- warning here is worth showing and never worth blocking on.
function NS.DescribeShare(payload)
  if type(payload) ~= "table" or type(payload.profile) ~= "table" then return nil end
  local tints = payload.profile.tints or {}

  local function Describe(list)
    local out = {}
    for _, rule in ipairs(list or {}) do
      local unusable = 0
      for _, condition in ipairs(rule.conditions or {}) do
        if NS.CanApplyAura and not NS.CanApplyAura(condition.spellID) then
          unusable = unusable + 1
        end
      end
      table.insert(out, {
        summary  = NS.RuleSummary and NS.RuleSummary(rule) or "",
        rule     = rule,
        unusable = unusable,
        missing  = rule.showWhenMissing and true or false,
      })
    end
    return out
  end

  local info = {
    name        = payload.name,
    addon       = payload.addon,
    rules       = Describe(tints.rules),
    borderRules = Describe(tints.borderRules),
    icons       = #((payload.profile.icons or {}).list or {}),
    modules     = {
      health = tints.enabled ~= false,
      border = tints.borderEnabled ~= false,
      icons  = (payload.profile.icons or {}).enabled and true or false,
    },
    dropped     = payload.dropped,
  }

  info.unusable = 0
  for _, list in ipairs({ info.rules, info.borderRules }) do
    for _, entry in ipairs(list) do
      if entry.unusable > 0 then info.unusable = info.unusable + 1 end
    end
  end
  return info
end

-- Writes it. `name` is the profile to create or replace; `overwrite` has to be
-- passed explicitly, so replacing someone's tuned setup is always a decision
-- rather than a consequence of picking a name that already existed.
function NS.CommitShare(payload, name, overwrite)
  if type(payload) ~= "table" or type(payload.profile) ~= "table" then
    return false, "Nothing to import."
  end
  name = name and strtrim(name) or ""
  if name == "" then return false, "Give the profile a name." end
  -- Same guard the rest of the profile UI uses: importing rebuilds every rig,
  -- and the game refuses that in combat.
  if InCombatLockdown() then return false, "Can't import in combat." end

  PLATETWEAKS_PROFILES = PLATETWEAKS_PROFILES or {}
  if PLATETWEAKS_PROFILES[name] and not overwrite then
    return false, ("'%s' already exists."):format(name)
  end

  -- Sanitised a second time. Decode already did it, but CommitShare is a
  -- public entry point and the payload could have been held across a reload or
  -- reached here from somewhere that skipped Decode.
  PLATETWEAKS_PROFILES[name] = SanitiseProfile(payload.profile)

  -- SelectProfile routes through SwitchTo, which forces a re-resolve and a
  -- full rebuild even when the resolved NAME is unchanged -- which is exactly
  -- the case when overwriting the profile that is already live.
  NS.SelectProfile(name)
  return true
end

-------------------------------------------------------------------------------
-- Drift check
--
-- The schema above is a second list of every setting, and second lists rot.
-- This reports keys the live profile has that the schema does not, so a
-- setting added without a matching entry here shows up as a diagnostic rather
-- than as "my import lost that option" a month later.
--
-- Legacy keys are named rather than inferred: they are SUPPOSED to be absent
-- from the schema, and treating them as gaps would make the check cry wolf
-- until someone stopped reading it.
-------------------------------------------------------------------------------

local LEGACY = {
  tints = { combos = true, comboSeq = true, combosMigrated = true,
            inset = true, list = true, exclusive = true },
  icons = { offset = true, offsetX = true, showCooldown = true },
}

-- Named explicitly rather than read back out of a sanitised table. Several
-- fields sanitise legitimately to nil -- an unset plateOutlineColor, a
-- gateUnknownSpells nobody has touched -- so "the sanitiser produced nil" does
-- not distinguish "not in the schema" from "in the schema and empty", and the
-- check would report settings that are working perfectly.
local KNOWN = {
  tints = {
    "enabled", "borderEnabled", "rules", "borderRules", "edgeAdjust",
    "missingCoverColor", "gateUnknownSpells", "plateOutline",
    "plateOutlineColor", "plateOutlineSize", "plateOutlineOffset",
    "plateOutlineSides", "pandemic",
  },
  icons = {
    "enabled", "list", "size", "spacing", "anchor", "grow", "padX", "padY",
    "maxPerRow", "hideBlizzardAuras", "borderSize", "borderColor",
    "showSwirl", "showTimer", "timerFont", "timerSize", "timerOutline",
    "timerAnchor", "timerX", "timerY", "timerPrecision",
    "showCount", "countFont", "countSize", "countOutline", "countAnchor",
    "countX", "countY",
  },
}

local function KnownSet(list)
  local set = {}
  for _, key in ipairs(list) do set[key] = true end
  return set
end

function NS.ShareSchemaGaps()
  local db = NS.db
  if not db then return {} end
  local gaps = {}
  for _, key in ipairs({ "tints", "icons" }) do
    local known = KnownSet(KNOWN[key])
    local legacy = LEGACY[key] or {}
    for field in pairs(db[key] or {}) do
      if not known[field] and not legacy[field] then
        table.insert(gaps, key .. "." .. field)
      end
    end
  end
  table.sort(gaps)
  return gaps
end
