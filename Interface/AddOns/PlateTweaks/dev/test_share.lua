-- Profile sharing.
--
-- An export is the only way one person's setup reaches another install, and
-- every failure it can have is silent: a setting that does not cross arrives
-- as the default and looks like a choice nobody made. So this walks a profile
-- with every feature switched on and checks the far side got it.
--
-- It also runs the two entry points end to end, because both were calling
-- helpers declared further down the file -- a global nil at runtime -- and
-- nothing here or in the game noticed until someone tried to export.
local dir = ...

local NS = {}

-- ---- client stubs -----------------------------------------------------------
--
-- The encoder is the identity: this is a test of what the schema carries, and
-- CBOR round-tripping is the client's problem, not this addon's.
-- Base64 hands back a STRING, because the addon concatenates it with the
-- prefix and trims whitespace off it -- so the stub keeps the table in a side
-- table and passes a handle, rather than pretending a table is text.
local vault, nextHandle = {}, 0
_G.C_EncodingUtil = {
  SerializeCBOR = function(t) return { payload = t } end,
  DeserializeCBOR = function(t) return t.payload end,
  CompressString = function(t) return t end,
  DecompressString = function(t) return t end,
  EncodeBase64 = function(t)
    nextHandle = nextHandle + 1
    local handle = "h" .. nextHandle
    vault[handle] = t
    return handle
  end,
  DecodeBase64 = function(handle) return vault[handle] end,
}
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.InCombatLockdown = function() return false end
_G.CopyTable = function(t)
  local out = {}
  for k, v in pairs(t) do out[k] = (type(v) == "table") and CopyTable(v) or v end
  return out
end

NS.ADDON = "PlateTweaks"
NS.MAX_RULE_CONDITIONS = 4
NS.DefaultColor = function() return { r = 1, g = 0.2, b = 0.2, a = 0.75 } end
NS.LOAD_ZONES = { { key = "mythicplus" }, { key = "raid" } }
NS.LOAD_GROUPS = { { key = "party" } }
NS.MARK_INDICATOR_SHAPES = { { key = "arrow" }, { key = "diamond" } }
NS.ProfileKey = function() return "Test" end
NS.SelectProfile = function() end
NS.Defaults = {
  tweaks = { tooltipIDs = false, tooltipItem = true },
  levelOffset = 1,
  useAuraSlots = true,
  icons = {
    enabled = false, size = 24, spacing = 2, anchor = "TOP", grow = "RIGHT",
    padX = 0, padY = 0, maxPerRow = 6, hideBlizzardAuras = false, tooltips = true,
    borderSize = 1, borderColor = { r = 0, g = 0, b = 0, a = 1 },
    showSwirl = true, showTimer = true, timerFont = "Friz", timerSize = 12,
    timerOutline = "OUTLINE", timerAnchor = "CENTER", timerX = 0, timerY = 0,
    timerPrecision = 0, showCount = true, countFont = "Friz", countSize = 10,
    countOutline = "OUTLINE", countAnchor = "BOTTOMRIGHT", countX = 0, countY = 0,
  },
  missingIcons = {
    enabled = false, size = 24, spacing = 2, anchor = "RIGHT", grow = "RIGHT",
    padX = 3, padY = 0, collapse = true, borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
  },
  tints = { missingAppliedClassColors = {} },
}

local chunk = assert(loadfile(dir .. "/Share.lua"))
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

-- ---- a profile with every feature touched -----------------------------------
--
-- Deliberately not a realistic setup: every switch is moved off its default,
-- because a field that crosses as its default is indistinguishable from a
-- field that did not cross at all.
local source = {
  levelOffset = 3,
  useAuraSlots = false,
  tweaks = { tooltipIDs = true, tooltipItem = false },
  tints = {
    enabled = true,
    borderEnabled = false,
    edgeAdjust = 2,
    maxRigRepairs = 7,
    missingMode = "occlude",
    gateUnknownSpells = true,
    plateOutline = true,
    plateOutlineSize = 3,
    plateOutlineOffset = 1,
    plateOutlineColor = { r = 0.1, g = 0.2, b = 0.3, a = 1 },
    plateOutlineSides = { top = false, bottom = true },
    missingAppliedByClass = true,
    rulesMerged = true,
    rules = {
      {
        enabled = true, barEnabled = false,
        color = { r = 0.5, g = 0.25, b = 0.75, a = 0.6 },
        conditions = { { spellID = 980 }, { spellID = 172 } },
        border = { enabled = true, thickness = 4, grow = "IN", padding = 2,
                   color = { r = 1, g = 0, b = 0, a = 1 } },
        showOnTarget = false, showOnFocus = false,
        fillStyle = "texture", fillTexture = "stripes-diag",
        barTexture = "Solid", missingCover = true,
        showWhenMissing = true, missingCombatOnly = true,
        load = { zones = { raid = true }, groups = { party = true } },
      },
    },
    threatEnabled = true,
    threat = {
      enabled = true, role = "tank", flashOnLoss = true,
      states = { aggro = { enabled = false, color = { r = 1, g = 0, b = 0, a = 1 } } },
      load = { zones = { mythicplus = true } },
    },
    threatBorder = { thickness = 5, grow = "IN", padding = 3, states = {} },
    mark = {
      enabled = true,
      states = {
        target = {
          enabled = true, color = { r = 1, g = 1, b = 1, a = 0.5 },
          fillStyle = "texture", fillTexture = "stripes-diag",
          rowHalves = { bar = true, border = false },
          indicator = { enabled = true, position = "BOTH", shape = "arrow",
                        size = 20, gap = 6 },
        },
        focus = { enabled = false, color = { r = 0, g = 1, b = 1, a = 0.5 } },
      },
    },
    markBorder = { thickness = 3, grow = "IN", padding = 1, states = {} },
    pandemic = { enabled = true, pulse = false, pulseSpeed = 0.9,
                 color = { r = 1, g = 1, b = 0, a = 0.5 } },
  },
  icons = {
    enabled = true, size = 31, spacing = 1, anchor = "TOP", grow = "RIGHT",
    maxPerRow = 4, hideBlizzardAuras = true, tooltips = false,
    timerSize = 18, countSize = 10,
    list = { { spellID = 980, enabled = false }, { spellID = 172 } },
  },
  missingIcons = {
    enabled = true, size = 21, spacing = 2, anchor = "RIGHT", grow = "LEFT",
    padX = 4, collapse = false, borderSize = 2,
    list = {
      { spellID = 980, enabled = true, useIcon = true, missingCombatOnly = true,
        color = { r = 0, g = 0.95, b = 1, a = 1 } },
    },
  },
}

_G.PLATETWEAKS_PROFILES = { Test = source }

-- ---- it runs at all ---------------------------------------------------------
local encoded, note = NS.ExportProfile("Test")
check("a profile exports", type(encoded), "string")
check("with nothing dropped", note, nil)

local payload, err = NS.DecodeShareString(encoded)
check("and decodes again", payload ~= nil, true)
if not payload then
  print("decode failed: " .. tostring(err))
  print(failures + 1 .. " FAILURES")
  return failures + 1
end

local out = payload.profile

-- ---- the profile's own settings ---------------------------------------------
check("levelOffset crosses", out.levelOffset, 3)
check("useAuraSlots crosses", out.useAuraSlots, false)
check("a tweak crosses", out.tweaks.tooltipIDs, true)
check("and so does one left at its default", out.tweaks.tooltipItem, false)

-- ---- health colouring -------------------------------------------------------
local tints = out.tints
check("the border module switch crosses", tints.borderEnabled, false)
check("edge adjust crosses", tints.edgeAdjust, 2)
check("the rig-repair cap crosses", tints.maxRigRepairs, 7)
check("missing mode crosses", tints.missingMode, "occlude")
check("the known-spell gate crosses", tints.gateUnknownSpells, true)
check("the plate outline crosses", tints.plateOutline, true)
check("its size crosses", tints.plateOutlineSize, 3)
check("a switched-off side crosses", tints.plateOutlineSides.top, false)
check("class colouring crosses", tints.missingAppliedByClass, true)

-- ---- one rule, every field --------------------------------------------------
local rule = tints.rules[1]
check("the rule survived", rule ~= nil, true)
check("its bar half stayed off", rule.barEnabled, false)
check("its colour crossed", rule.color.b, 0.75)
check("its opacity crossed", rule.color.a, 0.6)
check("both debuffs crossed", #rule.conditions, 2)
check("its border crossed", rule.border.thickness, 4)
check("growing inward crossed", rule.border.grow, "IN")
check("the border gap crossed", rule.border.padding, 2)
-- The two the in-place editor was writing under the wrong names.
check("draw-on-target crossed", rule.showOnTarget, false)
check("draw-on-focus crossed", rule.showOnFocus, false)
check("the fill style crossed", rule.fillStyle, "texture")
check("the pattern crossed", rule.fillTexture, "stripes-diag")
check("the missing-health cover crossed", rule.missingCover, true)
check("MISSING crossed", rule.showWhenMissing, true)
check("its combat gate crossed", rule.missingCombatOnly, true)
check("its zone crossed", rule.load.zones.raid, true)
check("its group size crossed", rule.load.groups.party, true)

-- ---- threat -----------------------------------------------------------------
check("the threat role crossed", tints.threat.role, "tank")
check("flash on loss crossed", tints.threat.flashOnLoss, true)
check("a switched-off state crossed", tints.threat.states.aggro.enabled, false)
check("threat's zone gate crossed", tints.threat.load.zones.mythicplus, true)
check("the threat border thickness crossed", tints.threatBorder.thickness, 5)

-- ---- target and focus -------------------------------------------------------
local target = tints.mark.states.target
check("the target's colour crossed", target.color.a, 0.5)
check("its fill crossed", target.fillTexture, "stripes-diag")
check("its marker crossed", target.indicator.enabled, true)
check("the marker's shape crossed", target.indicator.shape, "arrow")
check("the marker's size crossed", target.indicator.size, 20)
check("the row switch's memory crossed", target.rowHalves.border, false)
check("focus stayed off", tints.mark.states.focus.enabled, false)
check("the target/focus border thickness crossed", tints.markBorder.thickness, 3)
check("its gap crossed", tints.markBorder.padding, 1)

-- ---- pandemic ---------------------------------------------------------------
check("pandemic flash crossed", tints.pandemic.enabled, true)
check("its pulse crossed", tints.pandemic.pulse, false)
check("its speed crossed", tints.pandemic.pulseSpeed, 0.9)

-- ---- aura icons -------------------------------------------------------------
check("the icon module crossed", out.icons.enabled, true)
check("its size crossed", out.icons.size, 31)
check("hiding Blizzard's crossed", out.icons.hideBlizzardAuras, true)
check("the tooltip switch crosses", out.icons.tooltips, false)
check("both icons crossed", #out.icons.list, 2)
check("a switched-off icon stayed off", out.icons.list[1].enabled, false)

-- ---- missing debuffs --------------------------------------------------------
local missing = out.missingIcons
check("the missing-debuff module crossed", missing ~= nil and missing.enabled, true)
check("its size crossed", missing.size, 21)
check("its growth crossed", missing.grow, "LEFT")
check("collapsing crossed", missing.collapse, false)
check("its list crossed", #missing.list, 1)
check("the entry's colour crossed", missing.list[1].color.g, 0.95)
check("its combat gate crossed", missing.list[1].missingCombatOnly, true)

-- ---- and the junk that should not cross -------------------------------------
_G.PLATETWEAKS_PROFILES.Junk = {
  uiPosition = { x = 100 }, uiSections = { a = true },
  tints = { rules = {}, combos = { "legacy" } },
}
local junk = NS.DecodeShareString((NS.ExportProfile("Junk")))
check("window position does not cross", junk.profile.uiPosition, nil)
check("open sections do not cross", junk.profile.uiSections, nil)
check("legacy migration input does not cross", junk.profile.tints.combos, nil)

-- ---- a hostile payload ------------------------------------------------------
local hostile = NS.DecodeShareString((function()
  _G.PLATETWEAKS_PROFILES.Hostile = {
    tints = {
      edgeAdjust = 1e9,
      rules = {
        { conditions = { { spellID = "980" } } },
        { conditions = { { spellID = 980 } }, color = { r = 5, g = -1, b = 0, a = 99 } },
      },
    },
    icons = { size = 0 / 0 },
  }
  return (NS.ExportProfile("Hostile"))
end)())
check("an out-of-range number is clamped", hostile.profile.tints.edgeAdjust <= 4096, true)
check("a rule with no usable debuff is dropped", #hostile.profile.tints.rules, 1)
check("a colour channel is clamped", hostile.profile.tints.rules[1].color.r, 1)
check("and so is the other end", hostile.profile.tints.rules[1].color.g, 0)
check("NaN falls back to the default", hostile.profile.icons.size, 24)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
return failures
