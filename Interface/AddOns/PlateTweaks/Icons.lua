local _, NS = ...

-------------------------------------------------------------------------------
-- Nameplate aura icons.
--
-- One container holding a one-spell group per tracked debuff. Groups inside a
-- container lay out in the order they were added, so the config list order is
-- the display order. Each group holds one button because a given debuff of
-- yours can only be on a unit once.
--
-- Independent of the tint system: either can be used without the other.
-------------------------------------------------------------------------------

local flowAnchor = { LEFT = "TOPRIGHT", CENTER = "TOPLEFT", RIGHT = "TOPLEFT" }

-- Which corner of the icon row touches the chosen point on the bar. Mirrored
-- so the row sits OUTSIDE the bar: anchor TOPLEFT puts it above the bar,
-- aligned to its left edge.
NS.AnchorMirror = {
  TOPLEFT = "BOTTOMLEFT", TOP = "BOTTOM", TOPRIGHT = "BOTTOMRIGHT",
  LEFT = "RIGHT", CENTER = "CENTER", RIGHT = "LEFT",
  BOTTOMLEFT = "TOPLEFT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPRIGHT",
}

local function InitializeIcon(icons, button)
  local db = NS.db.icons
  table.insert(icons.buttons, button)

  pcall(function()
    button:SetSize(db.size, db.size)

    -- The "border" is a backing texture the icon is inset into, so its size
    -- and colour are both free.
    local edge = db.borderSize or 1
    local border = db.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    button.BG = button:CreateTexture(nil, "BACKGROUND")
    button.BG:SetAllPoints()
    button.BG:SetColorTexture(border.r, border.g, border.b, border.a or 1)

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetPoint("TOPLEFT", edge, -edge)
    button.Icon:SetPoint("BOTTOMRIGHT", -edge, edge)
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(button.Icon)

    if db.showSwirl or db.showTimer then
      button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
      button.Cooldown:SetAllPoints(button.Icon)
      button.Cooldown:SetDrawBling(false)
      button.Cooldown:SetDrawSwipe(db.showSwirl and true or false)
      button.Cooldown:SetDrawEdge(db.showSwirl and true or false)
      button.Cooldown:SetReverse(true)
      button.Cooldown:SetHideCountdownNumbers(not db.showTimer)
      button:SetDurationCooldown(button.Cooldown)

      if db.showTimer then
        local text = button.Cooldown:GetCountdownFontString()
        if text then
          NS.ApplyFont(text, db.timerFont, db.timerSize, db.timerOutline)
          text:ClearAllPoints()
          text:SetPoint(db.timerAnchor or "CENTER", button, db.timerAnchor or "CENTER",
            db.timerX or 0, db.timerY or 0)
        end
      end
    end

    if db.showCount then
      button.CountFrame = CreateFrame("Frame", nil, button)
      button.CountFrame:SetAllPoints()
      button.CountFrame:SetFrameLevel(button:GetFrameLevel() + 10)
      button.Count = button.CountFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      NS.ApplyFont(button.Count, db.countFont, db.countSize, db.countOutline)
      button.Count:SetPoint(db.countAnchor or "BOTTOMRIGHT", button, db.countAnchor or "BOTTOMRIGHT",
        db.countX or 0, db.countY or 0)
      button:SetApplicationCount(button.Count, {})
    end
  end)
end

function NS.BuildIcons(rig, healthBar)
  local db = NS.db.icons
  rig.icons = { buttons = {}, groupCount = 0, failures = 0 }

  if not db.enabled then return end

  local icons = rig.icons
  icons.frame = CreateFrame("AuraContainer", nil, healthBar, "CustomAuraContainerTemplate")
  icons.frame:SetEnabled(false)

  for _, entry in ipairs(db.list) do
    if entry.enabled ~= false then
      local key = "I" .. entry.spellID
      -- Guarded: icons build after tints, so an unhandled error here would
      -- take the rest of the plate setup with it.
      local ok = pcall(function()
        icons.frame:AddAuraGroup(key, "HARMFUL|PLAYER", {
          initializeFrame = function(button)
            InitializeIcon(icons, button)
          end,
        })
        -- Same trap as the tint filter: an ability whose aura is a separate
        -- spell needs the aura's ID here, not the cast's. Include both.
        local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(entry.spellID))
          or { [entry.spellID] = true }
        icons.frame:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
        icons.frame:SetAuraGroupMaxFrameCount(key, 1)
        icons.frame:SetAuraGroupLayout(key, { elementSpacingX = db.spacing, elementSpacingY = db.spacing })
      end)
      if ok then
        icons.groupCount = icons.groupCount + 1
      else
        icons.failures = icons.failures + 1
      end
    end
  end
end

function NS.AnchorIcons(rig)
  local icons = rig.icons
  if not icons or not icons.frame then return end

  local db = NS.db.icons
  local healthBar = rig.healthBar
  local frame = icons.frame

  -- One anchor point, one mirrored point, and raw X/Y padding that may be
  -- negative — so the row can also be pushed onto the bar itself.
  local anchor = db.anchor or "TOP"
  frame:ClearAllPoints()
  frame:SetPoint(NS.AnchorMirror[anchor] or "BOTTOM", healthBar, anchor,
    db.padX or 0, db.padY or 0)

  -- Constrain the row's width so the flow layout wraps at the requested
  -- count instead of running off the side of the plate.
  local perRow = math.max(1, db.maxPerRow or 6)
  pcall(frame.SetWidth, frame, perRow * db.size + (perRow - 1) * db.spacing)

  pcall(frame.SetFlowLayoutAnchorPoint, frame, flowAnchor[db.grow] or "TOPLEFT")
  if AnchorUtil and AnchorUtil.FlowDirection then
    if db.grow == "LEFT" then
      pcall(frame.SetFlowLayoutGrowthDirection, frame, AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Up)
    else
      pcall(frame.SetFlowLayoutGrowthDirection, frame, AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
    end
  end

  -- Well above the tints so icons are never washed out by them.
  frame:SetFrameLevel(rig.baseLevel + 20)
  for _, button in ipairs(icons.buttons) do
    pcall(button.SetSize, button, db.size, db.size)
    pcall(button.SetFrameLevel, button, rig.baseLevel + 20)
  end
end

function NS.SetIconsUnit(rig)
  local icons = rig.icons
  if icons and icons.frame then
    NS.ActivateContainer(rig, icons.frame)
  end
end

function NS.RetireIcons(rig)
  local icons = rig.icons
  if icons and icons.frame then
    icons.frame:SetEnabled(false)
    icons.frame:Hide()
  end
end

-------------------------------------------------------------------------------
-- Blizzard's own nameplate auras.
--
-- With this module on you get two rows of icons: ours and the default plate's.
-- Hiding theirs is the usual fix, but it has to be done carefully -- the frame
-- belongs to Blizzard, so every touch is pcall'd and the original state is
-- remembered so unticking the option genuinely restores it rather than
-- leaving the row hidden until a reload.
-------------------------------------------------------------------------------

-- Where the aura row lives varies by build and by which addon owns the plate,
-- so several names are tried rather than assuming one.
local function BlizzardAuraFrame(nameplate)
  if not nameplate then return nil end
  local unitFrame = nameplate.UnitFrame
  if not unitFrame then return nil end
  return unitFrame.BuffFrame or unitFrame.buffFrame or unitFrame.AuraContainer
end

function NS.ApplyBlizzardAuras(nameplate)
  local frame = BlizzardAuraFrame(nameplate)
  if not frame then return end

  local hide = NS.db and NS.db.icons and NS.db.icons.hideBlizzardAuras
  if hide then
    -- Remember what it was ONCE, before the first change, so restoring later
    -- puts back the real value instead of a guess.
    if frame.boonPrevAlpha == nil then
      local ok, alpha = pcall(frame.GetAlpha, frame)
      frame.boonPrevAlpha = ok and alpha or 1
    end
    -- Alpha rather than Hide: hiding a frame the plate's own code expects to
    -- be shown can fight that code every update, and in combat a protected
    -- Hide can be refused outright. Alpha 0 is never refused.
    pcall(frame.SetAlpha, frame, 0)
  elseif frame.boonPrevAlpha ~= nil then
    pcall(frame.SetAlpha, frame, frame.boonPrevAlpha)
    frame.boonPrevAlpha = nil
  end
end

-- Re-apply across every plate, for when the option itself changes.
function NS.RefreshBlizzardAuras()
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    pcall(NS.ApplyBlizzardAuras, plate)
  end
end
