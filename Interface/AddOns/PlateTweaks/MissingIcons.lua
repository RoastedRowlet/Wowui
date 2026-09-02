local _, NS = ...

-- Missing Debuffs icons.
--
-- Displacement, not occlusion: the icon sits at rest until the tracked debuff
-- lands, then is shoved off past the edge of the plate. Independent of the
-- missing-debuff wash in Tints.lua -- neither module needs the other.
--
-- An AuraContainer resizes to fit whatever buttons match its filters, and does
-- so whether or not anything is anchored to its edge. So: container with no
-- groups, anchor the icon to an edge, then register the filter group.
--
-- Two things this depends on, both measured:
--   * AddAuraGroup, never AddAuraSlot -- a slot's pool of one does not grow the
--     container, so nothing moves. This is the one place in the addon that
--     deliberately pays for the ten-frame pool. Capped by PACK_MAX.
--   * Container, then anchoring, then AddAuraGroup, in that order. Registering
--     makes the container reject further anchoring.

-- Packing costs one container per debuff before it, so groups run n+n(n-1)/2 --
-- at 4 that is 10 groups and 100 buttons on one plate. Past this, packing is
-- dropped and entries fall back to fixed slots. Tracking is not capped.
local PACK_MAX = 4

-- Far enough to clear any plate at any UI scale.
local HIDE_PUSH = 4000

local ENTRY_COLOR = { r = 1, g = 0.25, b = 0.8 }

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Fixed-layout geometry. LEFT growth fills from the right so slot 1 stays
-- nearest the anchor.
local function RowWidth(db, n)
  if n < 1 then return db.size end
  return n * db.size + (n - 1) * db.spacing
end

local function SlotOffset(db, i, n)
  local pitch = db.size + db.spacing
  if db.grow == "LEFT" then
    return RowWidth(db, n) - ((i - 1) * pitch + db.size)
  end
  return (i - 1) * pitch
end
NS.MissingIconSlotOffset = SlotOffset
NS.MissingIconRowWidth = RowWidth

-- No groups yet. Anything riding this container's edge must anchor first.
local function MakeContainer(rig, frame, sz)
  local ok, c = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
  if not ok or not c then return nil end
  c:SetEnabled(false)
  c:SetSize(1, sz)
  pcall(c.SetFrameLevel, c, frame:GetFrameLevel() + 2)
  pcall(c.SetFlowLayoutAnchorPoint, c, "LEFT")
  pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)
  table.insert(rig.missingContainers, c)
  NS.stats.containers = NS.stats.containers + 1
  return c
end

-- LAST, always. Registering seals the container against further anchoring.
local function RegisterGroups(c, spellIDs, buttonW, sz)
  for n, spellID in ipairs(spellIDs) do
    local key = "M" .. n
    local ok = pcall(function()
      c:AddAuraGroup(key, "HARMFUL|PLAYER", {
        initializeFrame = function(button)
          pcall(button.SetSize, button, buttonW, sz)
          -- A 4000px button with a live hitbox would blanket the screen.
          pcall(button.EnableMouse, button, false)
        end,
      })
      local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(spellID)) or { [spellID] = true }
      c:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
      pcall(c.SetAuraGroupMaxFrameCount, c, key, 1)
    end)
    if not ok then return false end
  end
  return true
end

-- One tracked debuff: its icon plus the one or two containers that place it.
--
-- The PACK container (entries past the first, when collapsing) holds a group
-- for every debuff before this one, pinned by the far edge so it grows back
-- toward the anchor. Its near edge lands at absent-before x pitch -- the packed
-- position, by subtraction, without knowing which debuffs are up. The HIDE
-- container rides that edge and throws the icon off screen when this entry's
-- own debuff lands.
local function BuildEntry(rig, frame, index, count, entry)
  local db = NS.db.missingIcons
  local sz, pitch = db.size, db.size + db.spacing
  local leftward = db.grow == "LEFT"
  local packing = rig.missingPacking and index > 1

  local anchorTo, anchorPoint, pack, hide, before

  if packing then
    before = {}
    for n = 1, index - 1 do before[n] = db.list[n].spellID end
    pack = MakeContainer(rig, frame, sz)
    if not pack then return false end
    if leftward then
      pack:SetPoint("LEFT", frame, "RIGHT", -((index - 1) * pitch), 0)
    else
      pack:SetPoint("RIGHT", frame, "LEFT", (index - 1) * pitch, 0)
    end
    anchorTo, anchorPoint = pack, (leftward and "RIGHT" or "LEFT")
  end

  hide = MakeContainer(rig, frame, sz)
  if not hide then return false end
  if anchorTo then
    hide:SetPoint(anchorPoint, anchorTo, anchorPoint, 0, 0)
  else
    hide:SetPoint("LEFT", frame, "LEFT", SlotOffset(db, index, count), 0)
  end

  local chip = CreateFrame("Frame", nil, frame)
  chip:SetSize(sz, sz)
  local okW, w0 = pcall(hide.GetWidth, hide)
  w0 = (okW and not Secret(w0) and w0) or 1
  -- w0 cancels out, so the icon centres in its slot whatever the container's
  -- resting width is.
  if leftward then
    chip:SetPoint("CENTER", hide, "LEFT", -(sz / 2 - w0), 0)
  else
    chip:SetPoint("CENTER", hide, "RIGHT", sz / 2 - w0, 0)
  end
  pcall(chip.SetFrameLevel, chip, frame:GetFrameLevel() + 5)
  NS.stats.textures = NS.stats.textures + 1

  local bw = db.borderSize or 0
  if bw > 0 then
    local bc = db.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    for _, side in ipairs({
      { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
      { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true },
    }) do
      local e = chip:CreateTexture(nil, "OVERLAY", nil, 1)
      e:SetColorTexture(bc.r, bc.g, bc.b, bc.a or 1)
      e:SetPoint(side[1], chip, side[1], 0, 0)
      e:SetPoint(side[2], chip, side[2], 0, 0)
      if side[3] then e:SetWidth(bw) else e:SetHeight(bw) end
      NS.stats.textures = NS.stats.textures + 1
    end
  end

  local art = chip:CreateTexture(nil, "ARTWORK")
  art:SetPoint("TOPLEFT", chip, "TOPLEFT", bw, -bw)
  art:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -bw, bw)
  -- useIcon absent means true, so older entries keep showing icons.
  local icon = entry.useIcon ~= false and NS.SpellIcon(entry.spellID) or nil
  if icon then
    art:SetTexture(icon)
    art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  else
    local ec = entry.color or ENTRY_COLOR
    art:SetColorTexture(ec.r, ec.g, ec.b, 0.9)
  end
  NS.stats.textures = NS.stats.textures + 1
  table.insert(rig.missingChips, chip)

  -- LAST. Nothing may anchor to `pack`/`hide` after this.
  if pack and not RegisterGroups(pack, before, pitch, sz) then return false end
  if hide and not RegisterGroups(hide, { entry.spellID }, HIDE_PUSH, sz) then return false end

  -- Combat-only gate, per entry.
  --
  -- Gates the chip, not the container. Hiding the container does nothing: the
  -- chip is only positioned relative to its edge, never parented to it, so
  -- hiding it just freezes the last position and leaves the icon visible.
  if entry.missingCombatOnly then
    -- Hidden now rather than at the first poll, or it flashes ungated for up
    -- to a quarter second.
    chip:Hide()
    table.insert(rig.missingGated, { chip = chip, entry = entry, allowed = false })
  end

  return true
end

function NS.BuildMissingIcons(rig, healthBar)
  local db = NS.db.missingIcons
  rig.missingContainers = {}
  rig.missingChips = {}
  rig.missingGated = {}
  rig.missingFrame = nil
  rig.missingFailures = 0

  if not db.enabled then return end
  local list = db.list
  if #list == 0 then return end

  -- Once per rig so the whole row agrees, and so /pt status can report it.
  rig.missingPacking = db.collapse and #list <= PACK_MAX

  local frame = CreateFrame("Frame", nil, healthBar)
  frame:SetSize(RowWidth(db, #list), db.size)
  pcall(frame.SetFrameLevel, frame, healthBar:GetFrameLevel() + 20)
  rig.missingFrame = frame

  for index, entry in ipairs(list) do
    if entry.enabled ~= false then
      if not BuildEntry(rig, frame, index, #list, entry) then
        rig.missingFailures = rig.missingFailures + 1
      end
    end
  end
end

function NS.AnchorMissingIcons(rig)
  local frame = rig.missingFrame
  if not frame then return end
  local db = NS.db.missingIcons
  local healthBar = rig.healthBar

  frame:ClearAllPoints()
  local anchor = db.anchor or "TOP"
  frame:SetPoint(NS.AnchorMirror[anchor] or "BOTTOM", healthBar, anchor,
    db.padX or 0, db.padY or 0)
end

-- Bind only after everything is anchored.
function NS.SetMissingIconsUnit(rig)
  -- Shown first. RetireMissingIcons hides this frame and nothing ever put it
  -- back -- the same asymmetry that left a displacement wash stuck on. Latent
  -- today only because every retire is followed by a discard; it stops being
  -- latent the moment a rig is reused after retirement.
  if rig.missingFrame then pcall(rig.missingFrame.Show, rig.missingFrame) end
  for _, c in ipairs(rig.missingContainers or {}) do
    NS.ActivateContainer(rig, c)
  end
  -- Settle the gate now rather than leaving chips wrong for up to a quarter
  -- second after every rebind. allowed is cleared because the gate is
  -- edge-triggered and the re-show above may have contradicted it.
  local gated = rig.missingGated
  if gated and #gated > 0 and NS.UpdateMissingIconsCombatGate then
    for _, item in ipairs(gated) do item.allowed = nil end
    NS.UpdateMissingIconsCombatGate(rig)
  end
end

function NS.RetireMissingIcons(rig)
  for _, c in ipairs(rig.missingContainers or {}) do
    pcall(c.SetEnabled, c, false)
    pcall(c.Hide, c)
  end
  if rig.missingFrame then pcall(rig.missingFrame.Hide, rig.missingFrame) end
end

-- Polled from the same 0.25s ticker as NS.UpdateMissingCombatGate.
function NS.UpdateMissingIconsCombatGate(rig)
  local gated = rig.missingGated
  if not gated or #gated == 0 then return end
  -- rig.unit is nil for a built-but-unbound rig; treat that as not allowed
  -- rather than passing nil to UnitAffectingCombat.
  for _, item in ipairs(gated) do
    local allowed = NS.UnitEngaged(rig.unit)
    if item.allowed ~= allowed then
      item.allowed = allowed
      item.chip:SetShown(allowed)
    end
  end
end

-- Core.lua's poll only walks rigs when this is true.
function NS.AnyMissingIconsCombatOnly()
  for _, entry in ipairs((NS.db and NS.db.missingIcons and NS.db.missingIcons.list) or {}) do
    if entry.enabled ~= false and entry.missingCombatOnly then return true end
  end
  return false
end
