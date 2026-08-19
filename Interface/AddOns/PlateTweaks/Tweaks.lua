local _, NS = ...

-------------------------------------------------------------------------------
-- Optional Tweaks
--
-- Small quality-of-life changes that have nothing to do with nameplates. They
-- live here rather than in one of the modules because that is exactly what
-- they are: unrelated conveniences that happen to ship in the same addon, each
-- off by default and each switched on by itself.
--
-- Nothing in this file touches the tint engine, the rigs, or anything a rule
-- can reach, so a tweak can never be the reason a nameplate stopped colouring.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Tooltip IDs
--
-- Appends the numeric ID to game tooltips: spells, auras, items and creatures.
-- Based on the approach used by the TooltipID addon (VeepZy).
--
-- Registered ONCE at load and gated inside the callback, never registered and
-- unregistered as the setting changes. TooltipDataProcessor.AddTooltipPostCall
-- has no matching remove call -- a handler added here is added for the session
-- -- so "off" has to mean "the handler returns immediately", which it does.
-- The cost of that when switched off is one table lookup per tooltip.
--
-- Aura IDs are the reason this is worth having in THIS addon: a rule needs the
-- ID of the aura that lands, which is frequently not the ID of the spell you
-- cast, and hovering the debuff on a target is the most direct way to read it.
-------------------------------------------------------------------------------

local function TweakDB()
  return (NS.db and NS.db.tweaks) or {}
end

local function Enabled(kind)
  local db = TweakDB()
  if not db.tooltipIDs then return false end
  -- Each line type can be switched off on its own; absent means on, so that
  -- turning the tweak on shows everything until you narrow it.
  return db[kind] ~= false
end

-- 12.1 hands out secret values for anything that could leak unit identity.
-- Touching one with string.format, tostring or strsplit throws AND taints the
-- rest of the call chain with our name, so every value that reaches a string
-- operation has to be cleared first.
local function Secret(v)
  return issecretvalue and issecretvalue(v)
end

local function AddIDLine(tooltip, id, label)
  if not tooltip or not id or Secret(id) then return end
  -- IsForbidden: some tooltips are owned by protected UI and calling AddLine on
  -- one throws. Checked on every call rather than once, because which tooltip
  -- the handler receives changes per invocation.
  local ok, forbidden = pcall(tooltip.IsForbidden, tooltip)
  if not ok or forbidden then return end

  tooltip:AddLine(" ")
  tooltip:AddLine(("%s ID: |cffffffcf%s|r"):format(label, tostring(id)), 1, 1, 1)
end

function NS.SetupTweaks()
  if NS.tweaksRegistered then return end
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum
    and Enum.TooltipDataType) then
    return
  end
  NS.tweaksRegistered = true

  local kinds = {
    { field = "tooltipItem",  type = Enum.TooltipDataType.Item,     label = "Item" },
    { field = "tooltipSpell", type = Enum.TooltipDataType.Spell,    label = "Spell" },
    { field = "tooltipAura",  type = Enum.TooltipDataType.UnitAura, label = "Aura" },
  }
  for _, kind in ipairs(kinds) do
    if kind.type then
      TooltipDataProcessor.AddTooltipPostCall(kind.type, function(tooltip, data)
        if not Enabled(kind.field) or not data then return end
        AddIDLine(tooltip, data.id, kind.label)
      end)
    end
  end

  -- Units are a different shape: the ID has to be dug out of the GUID, and the
  -- fields are not populated until SurfaceArgs has run over the data.
  if Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
      if not Enabled("tooltipUnit") or not data then return end
      if TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, data)
      end
      local guid = data.guid
      if not guid then return end
      -- Tooltip GUIDs are secret in most situations now (world cursor, nameplates,
      -- anything that could identify a unit you are not allowed to enumerate).
      -- strsplit on one throws once per tooltip update, so bail before touching it
      -- rather than pcall'ing around it -- the ID is genuinely unavailable, and a
      -- swallowed error every frame is worse than no line.
      if Secret(guid) then return end
      local unitID = select(6, strsplit("-", guid))
      -- Players have no creature ID in their GUID, so this is nil for them --
      -- which is the correct outcome, not a failure.
      if not unitID then return end
      AddIDLine(tooltip, unitID, "Unit")
    end)
  end
end
