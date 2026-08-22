local _, NS = ...

-- Optional Tweaks -- unrelated conveniences that ship in the same addon.
-- Nothing here touches the tint engine or the rigs.

-- Tooltip IDs. Appends the numeric ID to spell, aura, item and creature
-- tooltips. Approach borrowed from TooltipID (VeepZy).
--
-- Registered once at load and gated inside the callback: AddTooltipPostCall has
-- no remove, so "off" has to mean the handler returns early.

local function TweakDB()
  return (NS.db and NS.db.tweaks) or {}
end

local function Enabled(kind)
  local db = TweakDB()
  if not db.tooltipIDs then return false end
  -- Absent means on, so switching the tweak on shows everything until narrowed.
  return db[kind] ~= false
end

-- Touching a secret with format/tostring/strsplit throws and taints the call
-- chain with our name.
local function Secret(v)
  return issecretvalue and issecretvalue(v)
end

local function AddIDLine(tooltip, id, label)
  if not tooltip or not id or Secret(id) then return end
  -- Protected tooltips throw on AddLine. Which tooltip we get changes per call,
  -- so this is checked every time.
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

  -- Units need the ID dug out of the GUID, and the fields are not populated
  -- until SurfaceArgs has run.
  if Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
      if not Enabled("tooltipUnit") or not data then return end
      if TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, data)
      end
      local guid = data.guid
      if not guid then return end
      -- Bail rather than pcall: a swallowed error every tooltip update is worse
      -- than no line, and the ID is genuinely unavailable here.
      if Secret(guid) then return end
      local unitID = select(6, strsplit("-", guid))
      -- nil for players, which is correct -- they have no creature ID.
      if not unitID then return end
      AddIDLine(tooltip, unitID, "Unit")
    end)
  end
end
