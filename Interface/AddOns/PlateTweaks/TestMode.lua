local _, NS = ...

-------------------------------------------------------------------------------
-- Test mode.
--
-- Paints the currently SIMULATED rules onto every real nameplate, using frames
-- we own outright. Nothing here is aura-gated, so you see your exact colours,
-- thickness, gap and inside/outside geometry at real size, on your own
-- nameplate addon's plates, with no debuffs required.
--
-- This is deliberately NOT the tint engine. The engine's visuals only appear
-- when the game says the aura is present, and nothing can force that. Test
-- mode sidesteps the question entirely by drawing its own copies.
--
-- What it therefore CANNOT tell you: whether a rule would actually match. A
-- wrong spell ID looks perfect in test mode.
--
-- Toggled from the buttons on either colouring tab.
-------------------------------------------------------------------------------

local test = { on = false, plates = {}, ticker = nil }

-- Same four edges as the real border, and the same unit-vector scheme, so the
-- geometry cannot drift from what the engine draws.
local SIDES = {
  { a = "TOPLEFT",    b = "TOPRIGHT",    ax = -1, ay =  1, bx =  1, by =  1, vertical = false },
  { a = "BOTTOMLEFT", b = "BOTTOMRIGHT", ax = -1, ay = -1, bx =  1, by = -1, vertical = false },
  { a = "TOPLEFT",    b = "BOTTOMLEFT",  ax = -1, ay =  1, bx = -1, by = -1, vertical = true  },
  { a = "TOPRIGHT",   b = "BOTTOMRIGHT", ax =  1, ay =  1, bx =  1, by = -1, vertical = true  },
}

-- Top matching rule from a list against the debuffs ticked in the options
-- preview. Mirrors the preview's own logic rather than the engine's, because
-- the engine's answer is exactly the thing we are standing in for.
-- Set while the options window is sitting on ONE rule's page. The test buttons
-- there are testing that rule, not the rule list, so the ticked-debuff walk
-- below is the wrong question entirely: it would paint whichever rule the
-- ticks happen to select, which on a rule page is usually a different rule.
local focusRule
function NS.TestFocusRule() return focusRule end

local function Winner(list)
  -- Deliberately ignores enabled and conditions. You pressed test on this
  -- rule's own page; a disabled rule showing nothing would look like the
  -- button was broken.
  if focusRule then
    for _, rule in ipairs(list or {}) do
      if rule == focusRule then return rule end
    end
    return nil
  end

  local active = NS.PreviewActive and NS.PreviewActive() or {}
  for _, rule in ipairs(list or {}) do
    -- Missing rules never paint the bar, so one placing first here would win
    -- a contest it is not in and leave the bar blank. The ladder resolves
    -- them separately, further down in Paint.
    if not rule.showWhenMissing and rule.enabled ~= false and #(rule.conditions or {}) > 0 then
      local all = true
      for _, c in ipairs(rule.conditions) do
        if not active[c.spellID] then all = false break end
      end
      if all then return rule end
    end
  end
  -- Nothing ticked means no rule matches, so nothing is drawn. Falling back
  -- to some default rule would paint a colour no real debuff produces, which
  -- is worse than showing nothing; the banner explains the empty result.
end

local function BuildOverlay(healthBar)
  local o = CreateFrame("Frame", nil, healthBar)
  o:SetAllPoints(healthBar)
  -- Above everything the tint engine draws, so test mode is never the thing
  -- hidden by a real rule that happens to be firing.
  o:SetFrameLevel(healthBar:GetFrameLevel() + 60)

  o.tint = o:CreateTexture(nil, "OVERLAY", nil, 0)
  o.tint:Hide()

  -- Above the tint's own sublevel, not sharing it: the two are spatially
  -- disjoint (opposite sides of the live fill edge) but a texture-mode fill
  -- is only masked down to that edge, which can leave an unclipped sliver
  -- right at the boundary with an undefined winner if the sublevels tie.
  o.missingCover = o:CreateTexture(nil, "OVERLAY", nil, 2)
  o.missingCover:Hide()

  o.edges = {}
  for index = 1, 4 do
    o.edges[index] = o:CreateTexture(nil, "OVERLAY", nil, 7)
    o.edges[index]:Hide()
  end

  -- The missing wash. One texture rather than the engine's ladder: this
  -- overlay is above everything the engine draws, so it can simply paint
  -- whichever rank the simulated state resolves to.
  --
  -- Sublevel BELOW o.tint, matching the plate: the ladder is built under every
  -- presence rule (see ruleBase in NS.BuildTints), so a matching rule's colour
  -- wins the bar and the reminder shows where nothing matches.
  o.missingWash = o:CreateTexture(nil, "OVERLAY", nil, -1)
  o.missingWash:Hide()
  return o
end

local function Paint(healthBar, overlay)
  -- Suppress the ENGINE's own missing wash while test mode is on.
  --
  -- Test mode stands in for the engine, and for every other visual that works
  -- for free: the engine only draws when an aura is actually present, and in
  -- test mode you have applied nothing, so it draws nothing and the overlay
  -- has the plate to itself.
  --
  -- A missing rule is the first visual that is lit BECAUSE nothing is applied,
  -- so it is the first one still on screen underneath. The overlay covers it
  -- while the overlay is painting something, and stops covering it the moment
  -- you tick the debuff -- which reads as the test wash refusing to clear.
  --
  -- Only rank 1 needs this. Deeper washes live on aura buttons and require
  -- every debuff above them to be present, which in test mode they are not.
  -- The frame is ours (see NS.BuildMissingWash), so hiding it is allowed.
  if healthBar.ptMissingWash then pcall(healthBar.ptMissingWash.Hide, healthBar.ptMissingWash) end

  local barRule = Winner(NS.db.tints.rules)
  local borderRule = Winner(NS.db.tints.borderRules)

  -- Bar tint, matching the engine's inset so the two look the same.
  local healthOn = NS.db.tints.enabled
  local borderOn = NS.db.tints.borderEnabled ~= false

  if healthOn and barRule and barRule.barEnabled ~= false and barRule.color then
    -- Through the same fill logic the real engine uses, not a hand-rolled
    -- copy of it: this used to always SetColorTexture directly, so a rule
    -- set to Colored Texture previewed as flat solid in test mode even
    -- though it was texture-mode everywhere else. One shared function means
    -- the two cannot drift apart again.
    NS.ApplyRuleFill(overlay.tint, healthBar, barRule, 0)
    overlay.tint:Show()
    if NS.ApplyMissingCover then
      NS.ApplyMissingCover(overlay.missingCover, healthBar, barRule, 0)
    end
  else
    overlay.tint:Hide()
    if overlay.missingCover then overlay.missingCover:Hide() end
  end

  -- The missing wash. Drawn whether or not any rule "wins" -- a missing rule
  -- is lit precisely when nothing has matched. The ladder resolves to the
  -- highest-ranked rule still owed, which is what the engine's chain expresses
  -- structurally.
  local missingBar
  if healthOn then
    local active = NS.PreviewActive and NS.PreviewActive() or {}
    for _, rule in ipairs(NS.db.tints.rules or {}) do
      if rule.showWhenMissing and rule.enabled ~= false
        and #(rule.conditions or {}) == 1 and not missingBar then
        -- On a rule's own page the test button is testing THAT rule, so the
        -- ticked-debuff walk is the wrong question -- same carve-out Winner
        -- makes above. Focused means "show me this one lit".
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

-- A banner, because a test mode you can forget you left on is worse than no
-- test mode: every plate would look like your rules were firing constantly.
-- Small self-contained button. TestMode.lua loads before Options.lua and does
-- not share its widget helpers, so this is deliberately minimal rather than
-- reaching across files for a nicer one.
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

    -- Draggable: it sits centre-top by default, which is exactly where
    -- nameplates tend to be while you are looking at them.
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("TOP", 0, -7)
    NS.ApplyFont(f.text, "Expressway", 12, "NONE")
    f.text:SetTextColor(1, 0.82, 0.1)

    -- The two module switches, on the banner because A/B-ing them against a
    -- live plate is the whole reason you are in test mode.
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

-- Says WHAT is being simulated, so "my plates are unchanged" and "my plates
-- are all one colour" are both explained on screen rather than guessed at.
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
    -- The ticked debuffs are irrelevant while one rule is being tested, so
    -- listing them would be actively misleading.
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
  -- Width follows the longest line, with the two buttons setting the floor.
  test.banner:SetWidth(math.max(340, test.banner.text:GetStringWidth() + 40))

  local healthOn = NS.db.tints.enabled and true or false
  local borderOn = NS.db.tints.borderEnabled ~= false
  test.banner.health.label:SetText(healthOn and "Health Coloring: ON" or "Health Coloring: OFF")
  test.banner.border.label:SetText(borderOn and "Border Coloring: ON" or "Border Coloring: OFF")
  test.banner.health.Paint(healthOn)
  test.banner.border.Paint(borderOn)
end

-- Which plates to paint. Target only by default: it is the one you are
-- looking at while tuning a colour, and a direct GetNamePlateForUnit lookup
-- avoids guessing which of several plates you meant.
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
    -- The error is captured, not swallowed: reporting "no health bar" for
    -- every failure would be a diagnostic that lies.
    local ok, err = pcall(function()
      -- Deliberately independent of the rig table. Friendly plates are never
      -- rigged (nothing you apply can land on them), and test mode is a
      -- drawing tool rather than a matching one, so it finds the bar itself.
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

  -- Anything we painted before but are no longer covering.
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

-- Called on every page change. nil means "back to testing the whole list".
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
    -- Give the engine its missing wash back. Through NS.AnchorTints rather
    -- than a bare Show: whether the wash should be up at all depends on
    -- whether a ladder exists, and that answer lives in NS.BuildMissingWash --
    -- a blind Show would strand a wash on a profile with no missing rules.
    for _, rig in pairs(NS.rigs or {}) do
      if rig.healthBar then pcall(NS.AnchorTints, rig) end
    end
    return
  end

  Banner(true)
  -- Plates come and go constantly, so this re-attaches rather than assuming
  -- the set is stable. Cheap: a handful of SetPoint calls per plate.
  test.ticker = test.ticker or C_Timer.NewTicker(0.3, Refresh)
  Refresh()

  -- No chat output: the banner already says the scope, what is simulated,
  -- and how to stop.
end
