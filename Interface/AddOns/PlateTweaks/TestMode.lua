local _, NS = ...

-- Test mode.
--
-- Paints the SIMULATED rules onto every real nameplate using frames we own.
-- Nothing here is aura-gated, so you see your exact colours and geometry at
-- real size with no debuffs required.
--
-- Deliberately NOT the tint engine -- the engine only draws when the game says
-- the aura is present, and nothing can force that. So this cannot tell you
-- whether a rule would actually match: a wrong spell ID looks perfect here.

local test = { on = false, plates = {}, ticker = nil }

-- Same four edges and unit vectors as the real border, so the geometry cannot
-- drift from what the engine draws.
local SIDES = {
  { a = "TOPLEFT",    b = "TOPRIGHT",    ax = -1, ay =  1, bx =  1, by =  1, vertical = false },
  { a = "BOTTOMLEFT", b = "BOTTOMRIGHT", ax = -1, ay = -1, bx =  1, by = -1, vertical = false },
  { a = "TOPLEFT",    b = "BOTTOMLEFT",  ax = -1, ay =  1, bx = -1, by = -1, vertical = true  },
  { a = "TOPRIGHT",   b = "BOTTOMRIGHT", ax =  1, ay =  1, bx =  1, by = -1, vertical = true  },
}

-- Top matching rule against the debuffs ticked in the preview. Mirrors the
-- preview's logic, not the engine's -- the engine's answer is what we stand in
-- for.
--
-- focusRule is set while the options window sits on ONE rule's page: the test
-- buttons there test that rule, so the ticked-debuff walk would paint whichever
-- rule the ticks happen to select instead.
local focusRule
function NS.TestFocusRule() return focusRule end

local function Winner(list)
  -- Ignores enabled and conditions: you pressed test on this rule's page, and
  -- a disabled rule showing nothing would look like a broken button.
  if focusRule then
    for _, rule in ipairs(list or {}) do
      if rule == focusRule then return rule end
    end
    return nil
  end

  local active = NS.PreviewActive and NS.PreviewActive() or {}
  for _, rule in ipairs(list or {}) do
    -- Missing rules never paint the bar, so one placing first would win a
    -- contest it is not in and leave the bar blank.
    if not rule.showWhenMissing and rule.enabled ~= false and #(rule.conditions or {}) > 0 then
      local all = true
      for _, c in ipairs(rule.conditions) do
        if not active[c.spellID] then all = false break end
      end
      if all then return rule end
    end
  end
  -- Nothing ticked means nothing drawn. A fallback rule would paint a colour
  -- no real debuff produces; the banner explains the empty result.
end

local function BuildOverlay(healthBar)
  local o = CreateFrame("Frame", nil, healthBar)
  o:SetAllPoints(healthBar)
  -- Above everything the engine draws, so test mode is never the thing hidden
  -- by a real rule that happens to be firing.
  o:SetFrameLevel(healthBar:GetFrameLevel() + 60)

  o.tint = o:CreateTexture(nil, "OVERLAY", nil, 0)
  o.tint:Hide()

    -- Above the tint's sublevel, not sharing it: a texture-mode fill is only
    -- masked to the live edge and can leave a sliver with an undefined winner.
  o.missingCover = o:CreateTexture(nil, "OVERLAY", nil, 2)
  o.missingCover:Hide()

  o.edges = {}
  for index = 1, 4 do
    o.edges[index] = o:CreateTexture(nil, "OVERLAY", nil, 7)
    o.edges[index]:Hide()
  end

    -- The missing wash. One texture rather than the engine's ladder, since
    -- this overlay is above everything the engine draws.
    --
    -- Sublevel BELOW o.tint, matching the plate: the ladder is built under
    -- every presence rule, so a matching rule wins the bar.
  o.missingWash = o:CreateTexture(nil, "OVERLAY", nil, -1)
  o.missingWash:Hide()
  return o
end

local function Paint(healthBar, overlay)
  -- Suppress the ENGINE's own missing wash while test mode is on.
  --
  -- Everything else the engine draws needs a real aura, so in test mode it
  -- draws nothing. A missing rule is the first visual lit BECAUSE nothing is
  -- applied, so it is the first one still on screen underneath -- and the
  -- overlay stops covering it the moment you tick the debuff, which reads as
  -- the test wash refusing to clear.
  --
  -- Only rank 1: deeper washes need every debuff above them present.
  if healthBar.ptMissingWash then pcall(healthBar.ptMissingWash.Hide, healthBar.ptMissingWash) end

  local barRule = Winner(NS.db.tints.rules)
  local borderRule = Winner(NS.db.tints.borderRules)

  local healthOn = NS.db.tints.enabled
  local borderOn = NS.db.tints.borderEnabled ~= false

  if healthOn and barRule and barRule.barEnabled ~= false and barRule.color then
    -- Through the same fill logic the engine uses. This used to
    -- SetColorTexture directly, so a Colored Texture rule previewed as flat.
    NS.ApplyRuleFill(overlay.tint, healthBar, barRule, 0)
    overlay.tint:Show()
    if NS.ApplyMissingCover then
      NS.ApplyMissingCover(overlay.missingCover, healthBar, barRule, 0)
    end
  else
    overlay.tint:Hide()
    if overlay.missingCover then overlay.missingCover:Hide() end
  end

  -- The missing wash, drawn whether or not any rule wins -- a missing rule is
  -- lit precisely when nothing has matched.
  local missingBar
  if healthOn then
    local active = NS.PreviewActive and NS.PreviewActive() or {}
    for _, rule in ipairs(NS.db.tints.rules or {}) do
      if rule.showWhenMissing and rule.enabled ~= false
        and #(rule.conditions or {}) == 1 and not missingBar then
    -- On a rule's own page the button tests THAT rule, so the ticked-debuff
    -- walk is the wrong question. Same carve-out Winner makes.
        local owed
        if focusRule then
          owed = (rule == focusRule)
        else
          owed = not active[rule.conditions[1].spellID]
        end
        if owed then missingBar = rule end
      end
    end
  end

  if missingBar then
    NS.ApplyRuleFill(overlay.missingWash, healthBar, missingBar, 0)
    overlay.missingWash:Show()
  else
    overlay.missingWash:Hide()
  end

  local b = borderRule and borderRule.border
  if borderOn and b and b.enabled then
    local t = math.max(1, math.min(8, b.thickness or 2))
    local pad = math.max(0, math.min(12, b.padding or 0))
    local out = (b.grow == "OUT") and (t + pad) or -pad
    local bc = b.color or NS.DefaultBorder().color
    for index, side in ipairs(SIDES) do
      local e = overlay.edges[index]
      e:ClearAllPoints()
      e:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
      e:SetPoint(side.a, healthBar, side.a, side.ax * out, side.ay * out)
      e:SetPoint(side.b, healthBar, side.b, side.bx * out, side.by * out)
      if side.vertical then e:SetWidth(t) else e:SetHeight(t) end
      e:Show()
    end
  else
    for _, e in ipairs(overlay.edges) do e:Hide() end
  end
end

  -- A banner, because a test mode you forget you left on is worse than none.
  -- Minimal on purpose: TestMode loads before Options and cannot use its
  -- widget helpers.
local function BannerButton(parent, width, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 20)
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
  })
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  NS.ApplyFont(b.label, "Expressway", 11, "NONE")
  b:SetScript("OnClick", onClick)
  b.Paint = function(on)
    if on then
      b:SetBackdropColor(0.16, 0.30, 0.18, 1)
      b:SetBackdropBorderColor(0.35, 0.75, 0.40, 1)
      b.label:SetTextColor(0.6, 1, 0.65)
    else
      b:SetBackdropColor(0.26, 0.14, 0.14, 1)
      b:SetBackdropBorderColor(0.70, 0.32, 0.32, 1)
      b.label:SetTextColor(1, 0.6, 0.6)
    end
  end
  return b
end

local function Banner(show)
  if not test.banner then
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(460, 58)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    f:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
    f:SetBackdropBorderColor(1, 0.82, 0.1, 1)

  -- Draggable: it defaults to centre-top, which is where plates tend to be.
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOP", 0, -7)
    NS.ApplyFont(f.text, "Expressway", 12, "NONE")
    f.text:SetTextColor(1, 0.82, 0.1)

  -- The module switches, because A/B-ing them against a live plate is the
  -- reason you are in test mode.
    f.health = BannerButton(f, 150, function()
      NS.db.tints.enabled = not NS.db.tints.enabled
      NS.RebuildAllRigs()
      if NS.Options_RebuildAll then pcall(NS.Options_RebuildAll) end
      NS.UpdateTestBanner()
    end)
    f.health:SetPoint("BOTTOMLEFT", 12, 8)

    f.border = BannerButton(f, 150, function()
      NS.db.tints.borderEnabled = not (NS.db.tints.borderEnabled ~= false)
      NS.RebuildAllRigs()
      if NS.Options_RebuildAll then pcall(NS.Options_RebuildAll) end
      NS.UpdateTestBanner()
    end)
    f.border:SetPoint("BOTTOMRIGHT", -12, 8)

    test.banner = f
  end
  test.banner:SetShown(show and true or false)
  if show then NS.UpdateTestBanner() end
end

  -- Says WHAT is simulated, so "unchanged" and "all one colour" are both
  -- explained on screen.
function NS.UpdateTestBanner()
  if not test.banner then return end
  local active = NS.PreviewActive and NS.PreviewActive() or {}

  local names = {}
  for spellID, on in pairs(active) do
    if on then table.insert(names, NS.SpellName(spellID)) end
  end
  table.sort(names)

  local scope = test.all and "ALL PLATES" or "TARGET"
  if focusRule then
  -- Ticked debuffs are irrelevant while one rule is tested.
    local label = {}
    for _, c in ipairs(focusRule.conditions or {}) do
      table.insert(label, NS.SpellName(c.spellID) or ("#" .. tostring(c.spellID)))
    end
    test.banner.text:SetText(("TEST MODE (%s) - single rule |cff55dd55%s|r")
      :format(scope, #label > 0 and table.concat(label, " + ") or "unnamed"))
    test.banner:SetWidth(math.max(340, test.banner.text:GetStringWidth() + 40))
    local healthOn = NS.db.tints.enabled and true or false
    local borderOn = NS.db.tints.borderEnabled ~= false
    test.banner.health.label:SetText(healthOn and "Health Coloring: ON" or "Health Coloring: OFF")
    test.banner.border.label:SetText(borderOn and "Border Coloring: ON" or "Border Coloring: OFF")
    test.banner.health.Paint(healthOn)
    test.banner.border.Paint(borderOn)
    return
  end
  if #names == 0 then
    test.banner.text:SetText(("TEST MODE (%s) - |cffff8040no debuffs ticked, plates unchanged|r")
      :format(scope))
  else
    test.banner.text:SetText(("TEST MODE (%s) - simulating |cff55dd55%s|r")
      :format(scope, table.concat(names, ", ")))
  end
  test.banner:SetWidth(math.max(340, test.banner.text:GetStringWidth() + 40))

  local healthOn = NS.db.tints.enabled and true or false
  local borderOn = NS.db.tints.borderEnabled ~= false
  test.banner.health.label:SetText(healthOn and "Health Coloring: ON" or "Health Coloring: OFF")
  test.banner.border.label:SetText(borderOn and "Border Coloring: ON" or "Border Coloring: OFF")
  test.banner.health.Paint(healthOn)
  test.banner.border.Paint(borderOn)
end

  -- Target only by default: it is the plate you are looking at, and a direct
  -- GetNamePlateForUnit avoids guessing which of several you meant.
local function Plates()
  if test.all then
    return C_NamePlate.GetNamePlates() or {}
  end
  local plate = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
  return plate and { plate } or {}
end

local function Refresh()
  if not test.on then return end
  NS.UpdateTestBanner()
  test.plateCount, test.painted = 0, 0
  test.lastError = nil

  for _, plate in ipairs(Plates()) do
    test.plateCount = test.plateCount + 1
    -- Captured, not swallowed: reporting "no health bar" for every failure
    -- would be a diagnostic that lies.
    local ok, err = pcall(function()
  -- Independent of the rig table: friendly plates are never rigged, and test
  -- mode is a drawing tool rather than a matching one.
      local unit = plate.namePlateUnitToken
      local rig = unit and NS.UnitRig and NS.UnitRig(unit)
      local healthBar = (rig and rig.healthBar)
        or (NS.FindHealthBar and NS.FindHealthBar(plate))
      if not healthBar then return end

      local overlay = test.plates[healthBar]
      if not overlay then
        overlay = BuildOverlay(healthBar)
        test.plates[healthBar] = overlay
      end
      overlay:Show()
      Paint(healthBar, overlay)
      test.painted = test.painted + 1
    end)
    if not ok then test.lastError = tostring(err) end
  end

  for healthBar, overlay in pairs(test.plates) do
    local stillWanted = false
    for _, plate in ipairs(Plates()) do
      local unit = plate.namePlateUnitToken
      local rig = unit and NS.UnitRig and NS.UnitRig(unit)
      local hb = (rig and rig.healthBar) or (NS.FindHealthBar and NS.FindHealthBar(plate))
      if hb == healthBar then stillWanted = true break end
    end
    if not stillWanted then pcall(overlay.Hide, overlay) end
  end
end
NS.RefreshTestMode = Refresh

-- nil means back to testing the whole list.
function NS.SetTestFocus(rule)
  if focusRule == rule then return end
  focusRule = rule
  if test.on then Refresh() end
end

function NS.TestModeActive() return test.on and true or false end
function NS.TestModeAll() return test.all and true or false end

function NS.TestMode(arg)
  arg = strtrim(arg or ""):lower()
  if arg == "off" then
    test.on = false
  elseif arg == "all" then
    test.all, test.on = true, true
  elseif arg == "target" then
    test.all, test.on = false, true
  else
    test.on = not test.on
  end

  if not test.on then
    for _, overlay in pairs(test.plates) do pcall(overlay.Hide, overlay) end
    if test.ticker then test.ticker:Cancel(); test.ticker = nil end
    Banner(false)
  -- Give the engine its missing wash back through NS.AnchorTints, not a bare
  -- Show -- whether it should be up depends on whether a ladder exists.
    for _, rig in pairs(NS.rigs or {}) do
      if rig.healthBar then pcall(NS.AnchorTints, rig) end
    end
    return
  end

  Banner(true)
  -- Plates come and go, so this re-attaches rather than assuming a stable set.
  test.ticker = test.ticker or C_Timer.NewTicker(0.3, Refresh)
  Refresh()

  -- No chat output: the banner already says scope, simulation and how to stop.
end
