local _, NS = ...

-- Target/Focus colouring. A colour chosen by WHICH UNIT THIS IS rather
-- than by a debuff or by threat.
--
-- Built exactly like threat and for the same reason: the question -- is this
-- plate my target -- is readable in combat, so this is an ordinary texture on
-- an ordinary frame of ours, shown and hidden by a poll and by the two events
-- that can change the answer. Nothing here rides an aura button, so none of
-- the secure-frame restrictions that shape the spell rules apply.
--
-- Priority is position, decided at build:
--
--   threat          claims its slots first
--   target/focus    claims next        <- this file
--   spell rules     allocate around both
--
-- Above the spell rules because "which one am I hitting" is a question you ask
-- before "what is on it", and below threat because a mob that has aggro on you
-- is news whether or not you had it targeted. Threat also clears itself the
-- moment the state does, while a target tint is lit for as long as you keep
-- the target -- a permanent colour should not be able to sit on top of a
-- warning one.

local ipairs, pairs, pcall, type = ipairs, pairs, pcall, type

local EMPTY = {}

-- Two states, and a unit can be both at once -- unlike threat, where the
-- client reports exactly one status. Ordered, because that is what decides
-- which colour a unit that is both your target AND your focus gets.
NS.MARK_STATES = {
  { key = "target", label = "Your target" },
  { key = "focus",  label = "Your focus" },
}
NS.MAX_MARK_RULES = 2

NS.MARK_LABELS = {
  target = "Your target",
  focus  = "Your focus",
}

-- Shipped colours. Target on, focus off: everyone has a target and most people
-- do not keep a focus, and a state nobody uses should not be spending a draw
-- slot on every plate.
--
-- Low alpha by construction. This lights on a plate you are already looking at
-- and stays lit, so anything heavier hides the bar rather than marking it.
NS.MARK_DEFAULT_COLORS = {
  target = {
    enabled = true,
    color = { r = 1.00, g = 1.00, b = 1.00, a = 0.50 },
    -- Striped, not solid.
    --
    -- A flat wash at any alpha that reads at a glance also hides the bar
    -- colour underneath, which is the one thing a nameplate is for. Diagonal
    -- stripes mark the plate and leave the health colour showing between
    -- them, so half opacity is legible instead of being a compromise.
    fillStyle = "texture",
    fillTexture = "stripes-diag",
    -- And a marker, because the wash alone cannot be seen from the edge of
    -- the screen where the plate you are attacking usually is.
    indicator = { enabled = true, position = "BOTH", shape = "arrow", size = 20 },
  },
  focus = {
    enabled = true,
    color = { r = 0.37, g = 0.90, b = 1.00, a = 0.50 },
    fillStyle = "texture",
    fillTexture = "stripes-diag",
    -- No marker: two marked plates is two things claiming to be the one you
    -- are looking at. Focus gets the colour and the border.
    indicator = { enabled = false, position = "BOTH", shape = "arrow" },
  },
}

function NS.MarkStateLabel(key) return NS.MARK_LABELS[key] or key end

-- What a marker paints in: its own colour when it has been given one, else
-- the unit's.
function NS.MarkerColor(entry)
  local ind = entry and entry.indicator
  return (ind and ind.color) or (entry and entry.color)
    or { r = 1, g = 1, b = 1, a = 1 }
end

-- The marker: a small diamond on the plate saying "this one", for people who
-- want target called out without a wash over the bar at all.
--
-- Drawn in the border band, so it costs no draw slot however it is
-- configured -- the same reason a border half is free.
NS.MARK_INDICATOR_POSITIONS = {
  { key = "LEFT",   label = "Left of the bar" },
  { key = "RIGHT",  label = "Right of the bar" },
  { key = "BOTH",   label = "Both sides" },
  { key = "TOP",    label = "Above the bar" },
  { key = "BOTTOM", label = "Below the bar" },
}

-- Marker shapes.
--
-- Our own art, at marker size, in this addon's own folder.
--
-- The previous set borrowed EllesmereUI's arrows, and they were soft however
-- they were drawn: that art is sized for a UI button, so a 10-pixel marker was
-- a heavy downscale, and turning one file four ways added a rotation resample
-- on top. Neither is fixable from this end -- the source is simply not the
-- size it is being drawn at.
--
-- So these are drawn for the job: 32x32, white with an alpha channel so
-- SetVertexColor tints them like every other texture here, one file per
-- direction so nothing is ever rotated, and antialiased at 8x on the way down
-- so the edge stays clean at 8 pixels as well as at 32. See
-- dev/make_marker_art.py, which generates them.
--
-- No `host` on any of these any more: they ship with this addon, so the list
-- no longer depends on what else is installed.
local ART = "Interface\\AddOns\\" .. (NS.ADDON or "PlateTweaks") .. "\\media\\markers\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function Sides(prefix)
  -- The file that POINTS AT the bar from each side: a marker on the left of
  -- the plate points right.
  return {
    LEFT   = ART .. prefix .. "-right.tga",
    RIGHT  = ART .. prefix .. "-left.tga",
    TOP    = ART .. prefix .. "-down.tga",
    BOTTOM = ART .. prefix .. "-up.tga",
  }
end

NS.MARK_INDICATOR_SHAPES = {
  { key = "arrow",     label = "Arrow",          directional = true, sides = Sides("arrow") },
  { key = "arrowbig",  label = "Arrow (large)",  directional = true, sides = Sides("arrow"),
    scale = 1.6 },
  { key = "arrow2",    label = "Double arrow",   directional = true, sides = Sides("arrow"),
    count = 2 },
  { key = "chevron",   label = "Chevron",        directional = true, sides = Sides("chevron") },
  { key = "chevron2",  label = "Double chevron", directional = true, sides = Sides("chevron"),
    count = 2 },
  { key = "diamond",   label = "Diamond",        texture = ART .. "diamond.tga" },
  { key = "circle",    label = "Circle",         texture = ART .. "circle.tga" },
  { key = "ring",      label = "Ring",           texture = ART .. "ring.tga" },
  { key = "spark",     label = "Spark",          texture = ART .. "spark.tga" },
  { key = "square",    label = "Square",         texture = WHITE },
}

local SHAPE_BY_KEY = {}
for _, shape in ipairs(NS.MARK_INDICATOR_SHAPES) do SHAPE_BY_KEY[shape.key] = shape end

-- Only the shapes this client can actually draw.
--
-- Everything ships with this addon now, so nothing is filtered out today --
-- but the check stays: it is what a shape sourced from elsewhere would need,
-- and a dropdown offering art you do not have is a list of entries that
-- silently draw nothing.
function NS.MarkShapeList()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
  local out = {}
  for _, shape in ipairs(NS.MARK_INDICATOR_SHAPES) do
    local ok = true
    if shape.host then
      ok = loaded and select(1, loaded(shape.host)) and true or false
    end
    if ok then out[#out + 1] = shape end
  end
  return out
end

function NS.MarkShape(key) return SHAPE_BY_KEY[key] or SHAPE_BY_KEY.diamond end

local function EnsureIndicator(entry, defaults)
  local ind = type(entry.indicator) == "table" and entry.indicator or {}
  if ind.enabled == nil then ind.enabled = defaults and defaults.enabled or false end
  -- Both sides by default: a marker on one side reads as decoration on that
  -- edge, and a pair reads as brackets around the plate you are on.
  ind.position = ind.position or "BOTH"
  -- Arrow by default: a marker is there to point at the plate, and the
  -- shapes that do not point are the specialised choice.
  ind.shape = SHAPE_BY_KEY[ind.shape] and ind.shape or "arrow"
  ind.size = tonumber(ind.size) or (defaults and defaults.size) or 10
  ind.gap = tonumber(ind.gap) or 4
  -- ind.color is deliberately left ABSENT by default: nil means "follow the
  -- unit's own colour", which is what a marker should do until someone says
  -- otherwise. A copy seeded here would freeze it at whatever the colour was
  -- the first time this ran.
  entry.indicator = ind
  return ind
end

local function EnsureStates(cfg)
  cfg.states = type(cfg.states) == "table" and cfg.states or {}
  local live = {}
  for _, state in ipairs(NS.MARK_STATES) do
    local entry = cfg.states[state.key]
    if type(entry) ~= "table" then
      local default = NS.MARK_DEFAULT_COLORS[state.key]
      entry = {
        enabled = default.enabled,
        color = { r = default.color.r, g = default.color.g,
                  b = default.color.b, a = default.color.a },
        -- The fill too, not just the colour. These are the shipped look, and
        -- seeding half of it left a new profile with a solid wash at an alpha
        -- chosen for stripes.
        fillStyle = default.fillStyle,
        fillTexture = default.fillTexture,
      }
      cfg.states[state.key] = entry
    end
    entry.stateKey = state.key
    EnsureIndicator(entry, (NS.MARK_DEFAULT_COLORS[state.key] or EMPTY).indicator)
    live[state.key] = true
  end
  for key in pairs(cfg.states) do
    if not live[key] then cfg.states[key] = nil end
  end
  return cfg
end

-- The module ships OFF. Everything else here is an addition to a profile that
-- already works; a new colour appearing on every plate after an update is not.
function NS.MarkConfig()
  local tints = NS.db and NS.db.tints or EMPTY
  local cfg = tints.mark
  if type(cfg) ~= "table" then
    cfg = { enabled = false, states = {} }
    if NS.db then NS.db.tints.mark = cfg end
  end
  if NS.NormaliseLoad then cfg.load = NS.NormaliseLoad(cfg.load) end
  return EnsureStates(cfg)
end

-- The border half: its own colours, no enable of its own. One row, one switch
-- -- the same shape threat settled on, for the same reason.
function NS.MarkBorderConfig()
  local tints = NS.db and NS.db.tints or EMPTY
  local cfg = tints.markBorder
  if type(cfg) ~= "table" then
    cfg = { states = {} }
    if NS.db then NS.db.tints.markBorder = cfg end
  end
  cfg.enabled = nil
  cfg.thickness = cfg.thickness or 2
  cfg.grow = cfg.grow or "OUT"
  EnsureStates(cfg)
  -- A border on a plate you are already looking at wants to be seen, so the
  -- border half seeds opaque rather than at the bar's wash alpha.
  for _, entry in pairs(cfg.states) do
    if entry.color and entry.seededAlpha == nil then
      entry.seededAlpha = true
      entry.color.a = 1
    end
  end
  return cfg
end

-- Which module a half's controls are editing. Same vocabulary as
-- NS.ThreatModule, so the options row can be built once for both.
function NS.MarkModule(kind)
  if kind == "border" then return NS.MarkBorderConfig() end
  return NS.MarkConfig()
end

local function EnabledStates(cfg)
  local ordered = {}
  for _, state in ipairs(NS.MARK_STATES) do
    local entry = cfg.states[state.key]
    if entry and entry.enabled ~= false then ordered[#ordered + 1] = entry end
  end
  return ordered
end

-- The Health Coloring switch, which governs this page's three stacks and not
-- just the spell rules -- see the same helper in Threat.lua.
local function HealthColoringOff()
  local tints = NS.db and NS.db.tints
  return tints and tints.enabled == false
end

function NS.GetOrderedMarkRules()
  local cfg = NS.MarkConfig()
  if HealthColoringOff() then return EMPTY end
  if cfg.enabled == false then return EMPTY end
  if NS.LoadAllows and not NS.LoadAllows(cfg.load) then return EMPTY end
  return EnabledStates(cfg)
end

function NS.GetOrderedMarkBorders()
  local cfg = NS.MarkConfig()
  if HealthColoringOff() then return EMPTY end
  if cfg.enabled == false then return EMPTY end
  if NS.LoadAllows and not NS.LoadAllows(cfg.load) then return EMPTY end
  return EnabledStates(NS.MarkBorderConfig())
end

-- Markers come off the BAR module's states -- there is one marker per unit,
-- not one per half -- but they are ordered and gated separately because a
-- marker is wanted by people who switch the wash off entirely.
function NS.GetOrderedMarkIndicators()
  local cfg = NS.MarkConfig()
  if HealthColoringOff() then return EMPTY end
  if cfg.enabled == false then return EMPTY end
  if NS.LoadAllows and not NS.LoadAllows(cfg.load) then return EMPTY end
  local out = {}
  for _, state in ipairs(NS.MARK_STATES) do
    local entry = cfg.states[state.key]
    if entry and entry.indicator and entry.indicator.enabled then
      out[#out + 1] = entry
    end
  end
  return out
end

function NS.AnyMarkRules()
  return #NS.GetOrderedMarkRules() > 0 or #NS.GetOrderedMarkBorders() > 0
    or #NS.GetOrderedMarkIndicators() > 0
end

-- Sublevels, taken AFTER threat and before everything else. `occ` is the same
-- occupancy map threat just marked, so this cannot be handed a slot threat is
-- using.
function NS.MarkSublevelPlan(occ, count, ceiling)
  local plan = {}
  if not count or count <= 0 then return plan end
  local sub = ceiling and (ceiling - 1) or 4
  for rank = 1, count do
    while sub >= -8 and occ.OVERLAY[sub] do sub = sub - 1 end
    if sub < -8 then break end
    occ.OVERLAY[sub] = true
    plan[rank] = sub
    sub = sub - 1
  end
  return plan
end

local function MarkHolder(rig, healthBar, entry, level)
  local holder = CreateFrame("Frame", nil, healthBar)
  holder:SetAllPoints(healthBar)
  pcall(holder.SetFrameLevel, holder, level)
  holder:Hide()
  entry.holder = holder
  entry.levelOffset = level - rig.baseLevel
  entry.lit = false
  entry.textures = 0
  table.insert(rig.mark.entries, entry)
  return holder
end

-- Where a marker sits, as one anchor pair plus the direction it steps away
-- in. Kept as data so a new position is a row here rather than a branch.
local INDICATOR_ANCHORS = {
  LEFT   = { point = "RIGHT",  relative = "LEFT",   x = -1, y =  0 },
  RIGHT  = { point = "LEFT",   relative = "RIGHT",  x =  1, y =  0 },
  TOP    = { point = "BOTTOM", relative = "TOP",    x =  0, y =  1 },
  BOTTOM = { point = "TOP",    relative = "BOTTOM", x =  0, y = -1 },
}

-- "Both sides" is two markers, not a third anchor.
local INDICATOR_SIDES = {
  BOTH = { "LEFT", "RIGHT" },
}

-- A directional shape faces the bar from wherever it is: the art points RIGHT,
-- so a marker on the left keeps that and one on the right turns around.
-- Non-directional shapes keep their own spin, which is what makes a square a
-- diamond.
local function MarkerRotation(shape, side)
  if not shape.directional then return shape.spin or 0 end
  if side == "RIGHT" then return math.pi end
  if side == "TOP" then return -math.pi / 2 end
  if side == "BOTTOM" then return math.pi / 2 end
  return 0
end

-- Which sides a position paints on. "Both sides" is two markers, not a third
-- anchor, and the options preview needs the same answer this file uses.
function NS.MarkerSides(position)
  return INDICATOR_SIDES[position] or { position or "LEFT" }
end

-- One marker, on one side. Returns how many textures it made.
--
-- On NS because the preview plate in the options window draws the same thing
-- against a fake bar: a marker that is drawn twice, by two functions, is a
-- marker whose preview can disagree with the plate about its own shape.
function NS.PaintMarker(holder, healthBar, side, ind, colour, sublevel)
  local shape = NS.MarkShape(ind.shape)
  local anchor = INDICATOR_ANCHORS[side] or INDICATOR_ANCHORS.LEFT
  local size = math.max(4, math.min(32, ind.size or 10)) * (shape.scale or 1)
  local gap = math.max(0, math.min(40, ind.gap or 4))
  -- A shape with per-side art needs no rotation at all; one without still
  -- gets turned, and takes the resampling that comes with it.
  local sideArt = shape.sides and shape.sides[side]
  local rotation = sideArt and 0 or MarkerRotation(shape, side)
  -- The textures are handed back as well as counted: the options preview
  -- reuses this painter and has to know which regions it just got, so it can
  -- hide them again without walking every texture on the frame.
  local made, textures = 0, {}

  for index = 1, (shape.count or 1) do
    local tex = holder:CreateTexture(nil, "OVERLAY", nil, sublevel)
    NS.stats.textures = NS.stats.textures + 1

    local drew = false
    if shape.atlas then
      drew = pcall(tex.SetAtlas, tex, shape.atlas, true)
    end
    if not drew then
      -- Either the shape is a plain texture, or its atlas is gone from this
      -- client. Both land here; the fallback is the diamond, which is
      -- WHITE8X8 and cannot fail.
      local path = sideArt or shape.texture or "Interface\\Buttons\\WHITE8X8"
      -- TRILINEAR, not the default.
      --
      -- These files are drawn far larger than a marker is: without mipmapped
      -- filtering the client point-samples one texel in four and the result
      -- is mush. The fourth argument is the filter mode; the two before it
      -- are wrap modes this does not want.
      if not pcall(tex.SetTexture, tex, path, nil, nil, "TRILINEAR") then
        pcall(tex.SetTexture, tex, path)
      end
      if shape.coords then
        pcall(tex.SetTexCoord, tex, shape.coords[1], shape.coords[2],
          shape.coords[3], shape.coords[4])
      end
    end
    -- Art that ships with colour of its own is flattened before it is tinted,
    -- or the colour picked here is only a wash over someone else's.
    if shape.desaturate then pcall(tex.SetDesaturated, tex, true) end
    tex:SetVertexColor(colour.r, colour.g, colour.b, colour.a or 1)
    -- Whole PHYSICAL pixels, both the size and the offset below.
    --
    -- A marker sized 10 UI units at a scale of 0.71 is 7.1 screen pixels, so
    -- its edges fall between pixels and the whole thing renders soft however
    -- good the art is. Same rule the borders and hairlines in the options
    -- window already follow.
    if PixelUtil and PixelUtil.SetSize then
      if not pcall(PixelUtil.SetSize, tex, size, size) then tex:SetSize(size, size) end
    else
      tex:SetSize(size, size)
    end
    pcall(tex.SetRotation, tex, rotation)

    -- Rotation turns a texture about its own centre, so a rotated square
    -- reaches past its box by part of its diagonal -- hence the size term in
    -- the offset. Each extra copy of a repeated shape steps one size further
    -- out, which is what makes a double arrow read as two chevrons rather
    -- than one blurred one.
    -- A rotated square reaches past its own box by part of its diagonal, so
    -- rotated shapes need the extra clearance and pre-drawn art does not.
    -- Each extra copy of a repeated shape steps one size further out, which
    -- is what makes a double arrow read as two chevrons rather than one
    -- smeared one.
    local reach = gap + (sideArt and 0 or size * 0.2) + (index - 1) * size * 0.75
    local x, y = anchor.x * reach, anchor.y * reach
    if PixelUtil and PixelUtil.SetPoint then
      if not pcall(PixelUtil.SetPoint, tex, anchor.point, healthBar,
        anchor.relative, x, y) then
        tex:SetPoint(anchor.point, healthBar, anchor.relative, x, y)
      end
    else
      tex:SetPoint(anchor.point, healthBar, anchor.relative, x, y)
    end
    made = made + 1
    textures[made] = tex
  end
  return made, textures
end

function NS.BuildMark(rig, healthBar, barRules, borderRules, level, sublevels, borderTop, indicatorRules)
  rig.mark = { entries = {}, failures = 0 }

  for rank, rule in ipairs(barRules or EMPTY) do
    local ok = pcall(function()
      local entry = { rule = rule, rank = rank, kind = "bar" }
      local holder = MarkHolder(rig, healthBar, entry, level)
      local sublevel = (sublevels and sublevels[rank]) or (3 - rank)
      local wash = holder:CreateTexture(nil, "OVERLAY", nil, sublevel)
      NS.stats.textures = NS.stats.textures + 1
      NS.ApplyRuleFill(wash, healthBar, rule, 0)
      entry.wash = wash
      entry.sublevel = sublevel
      entry.textures = 1
    end)
    if not ok then rig.mark.failures = rig.mark.failures + 1 end
  end

  local cfg = NS.MarkBorderConfig and NS.MarkBorderConfig() or EMPTY
  for rank, rule in ipairs(borderRules or EMPTY) do
    local ok = pcall(function()
      local entry = { rule = rule, rank = rank, kind = "border" }
      local holder = MarkHolder(rig, healthBar, entry, level)
      -- One band below the threat borders, for the same reason the bar half
      -- sits below the threat wash.
      local sublevel = math.min(7, (borderTop or 7) - (rank - 1))
      local bc = rule.color or { r = 1, g = 1, b = 1, a = 1 }
      local t = math.max(1, math.min(8, cfg.thickness or 2))
      local pad = math.max(0, math.min(12, cfg.padding or 0))
      local out = (cfg.grow == "IN") and -pad or (t + pad)
      local edges = {}
      for _, side in ipairs(NS.BORDER_SIDES) do
        local tex = holder:CreateTexture(nil, "OVERLAY", nil, sublevel)
        NS.stats.textures = NS.stats.textures + 1
        tex:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        tex:SetPoint(side.a, healthBar, side.a, side.ax * out, side.ay * out)
        tex:SetPoint(side.b, healthBar, side.b, side.bx * out, side.by * out)
        if side.vertical then tex:SetWidth(t) else tex:SetHeight(t) end
        table.insert(edges, tex)
      end
      entry.borders = edges
      entry.borderSublevel = sublevel
      entry.textures = #edges
    end)
    if not ok then rig.mark.failures = rig.mark.failures + 1 end
  end

  -- Markers. A rotated square is a diamond, which is the cheapest shape that
  -- is obviously deliberate: no art file to ship, no atlas to go missing on a
  -- patch, and it tints to the state's own colour like everything else here.
  for rank, rule in ipairs(indicatorRules or EMPTY) do
    local ok = pcall(function()
      local entry = { rule = rule, rank = rank, kind = "indicator" }
      local holder = MarkHolder(rig, healthBar, entry, level)
      local ind = rule.indicator or EMPTY
      local colour = NS.MarkerColor(rule)
      local sublevel = math.min(7, (borderTop or 7))
      local sides = NS.MarkerSides(ind.position)
      local made = 0
      for _, side in ipairs(sides) do
        made = made + NS.PaintMarker(holder, healthBar, side, ind, colour, sublevel)
      end
      entry.textures = made
    end)
    if not ok then rig.mark.failures = rig.mark.failures + 1 end
  end
end

-- The poll. Unlike threat, a unit can satisfy both states at once -- your
-- focus can be your target -- so this is first-match-wins per half rather than
-- a straight walk: the higher-ranked state lights and the lower one stays
-- dark, instead of two washes stacking into a colour neither of them is.
function NS.UpdateMark(rig)
  local mark = rig and rig.mark
  if not mark or #(mark.entries or EMPTY) == 0 then return end
  local unit = rig.unit
  local claimed = {}
  for _, entry in ipairs(mark.entries) do
    local key = entry.rule and entry.rule.stateKey
    local want = false
    if unit and key and not claimed[entry.kind] then
      local ok, is = pcall(UnitIsUnit, unit, key)
      want = (ok and is) and true or false
      if want then claimed[entry.kind] = true end
    end
    if entry.lit ~= want then
      entry.lit = want
      pcall(entry.holder.SetShown, entry.holder, want)
    end
  end
end

function NS.RetireMark(rig)
  local mark = rig and rig.mark
  for _, entry in ipairs((mark or EMPTY).entries or EMPTY) do
    entry.lit = false
    pcall(entry.holder.Hide, entry.holder)
  end
end
