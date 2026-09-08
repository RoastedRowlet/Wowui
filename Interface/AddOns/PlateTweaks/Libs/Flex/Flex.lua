local ADDON, NS = ...

-- Vendored from FlexProto 0.1 (Graham), unmodified apart from this note. It is
-- a library, not a copy of something that lives here too: fixes go upstream in
-- FlexProto and come back as a whole-file replacement, so nothing in
-- PlateTweaks may edit it in place.
--
-- A flexbox layout engine for WoW frames.
--
-- WoW gives you exactly one placement primitive, SetPoint, and no layout pass.
-- So everything here is arithmetic: measure what the children want, decide
-- where they go, then place each one with a single absolute anchor to its
-- container's TOPLEFT.
--
-- The rule that makes wrapping possible: NOTHING is anchored to a sibling.
-- Relative anchor chains are why hand-written layouts cannot reflow -- move
-- one widget and the six anchored off it follow whether you wanted them to or
-- not. Every node here gets an absolute (x, y) inside its own parent.
--
-- Two passes:
--   Layout(width, forcedHeight) -> height    width-in, height-out. Wrapping
--                                            needs this shape: you cannot know
--                                            how tall a row is until you know
--                                            how wide it is allowed to be.
--   Apply()                                  writes the results to real frames.
--
-- Nothing touches a frame during Layout except text measurement, so a layout
-- can be computed and thrown away (that is how the debug overlay costs nothing
-- when it is off).

local Flex = {}
NS.Flex = Flex

local floor, max, min = math.floor, math.max, math.min

-- Fractional offsets at a non-integer UI scale blur 1px borders, so every
-- coordinate that reaches a frame goes through here first.
local function snap(v) return floor(v + 0.5) end

local function clamp(v, lo, hi)
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

--------------------------------------------------------------------------------
-- Nodes
--------------------------------------------------------------------------------

-- Supported props, all optional:
--
--   dir        "row" | "column"          box only, default "column"
--   wrap       boolean                   box only, row direction only
--   gap        number                    between items on the main axis
--   crossGap   number                    between wrapped lines (default: gap)
--   pad        number | {x,y} | {l,t,r,b}
--   justify    start|center|end|between|evenly     main axis
--   align      start|center|end|stretch            cross axis, default stretch
--   alignContent  start|center|end|between|stretch  wrapped lines as a block
--   grow       number                    share of leftover main-axis space
--   shrink     number                    share of the overflow (default 1)
--   basis      number                    main size to start from, before grow
--   width/height  number                 hard size, wins over measurement
--   minW/maxW  number
--   minH       number    a floor to lay out against -- what scrolling needs
--   alignSelf  overrides the parent's align for this child
--   wrapText   boolean                   leaf FontStrings only, re-flows
--   clipText   boolean                   leaf FontStrings only, truncates
--   hidden     boolean                   skipped entirely, takes no space

local Node = {}
Node.__index = Node

local function defaults(n)
  n.children = n.children or {}
  n.rect = { x = 0, y = 0, w = 0, h = 0 }
  n.dir = n.dir or "column"
  n.gap = n.gap or 0
  n.crossGap = n.crossGap or n.gap
  n.justify = n.justify or "start"
  n.align = n.align or "stretch"
  return n
end

-- pad accepts whichever form is least noisy at the call site:
--   pad = 12                        all four sides
--   pad = { x = 12, y = 6 }         horizontal / vertical
--   pad = { l = 10, t = 0, r = 6, b = 0 }   per side, missing sides are 0
-- The forms mix: { x = 12, t = 4 } is 12 either side, 4 on top, 0 below.
local function padOf(n)
  local p = n.pad
  if type(p) == "number" then return p, p, p, p end
  if type(p) == "table" then
    local x, y = p.x or 0, p.y or 0
    return p.l or x, p.t or y, p.r or x, p.b or y
  end
  return 0, 0, 0, 0
end

-- Wraps an existing region (Frame, Button, Texture, FontString) as a leaf.
function Flex.Item(region, props)
  local n = defaults(setmetatable(props or {}, Node))
  n.kind = "leaf"
  n.region = region
  n.isText = region.GetStringWidth ~= nil
  return n
end

-- A container. Gets a real Frame of its own so it can be shown/hidden, take
-- mouse input, or wear a background as a unit.
function Flex.Box(parentFrame, props)
  local n = defaults(setmetatable(props or {}, Node))
  n.kind = "box"
  n.frame = CreateFrame("Frame", nil, parentFrame)
  return n
end

function Node:Add(child)
  child.parent = self
  self.children[#self.children + 1] = child
  -- Wrapped text is the one thing that needs a second measure pass, so the
  -- root remembers whether any exists rather than hunting for it every reflow.
  if child.wrapText or child.hasWrapText then
    local n = self
    while n do n.hasWrapText = true; n = n.parent end
  end
  local obj = child.frame or child.region
  local host = self.contentFrame or self.frame
  if obj and obj.SetParent and host then
    pcall(obj.SetParent, obj, host)
  end
  return child
end

--------------------------------------------------------------------------------
-- Measurement
--------------------------------------------------------------------------------

-- What this node would like to be on the main axis, before any distribution.
function Node:NaturalW()
  if self.width then return self.width end
  local w
  if self.kind == "leaf" then
    if self.wrapText then
      -- Wrapping text has no natural width -- it is whatever it is given. Say
      -- so, and let basis/grow decide.
      w = self.basis or self.maxW or 0
    elseif self.isText then
      w = self.region:GetStringWidth() or 0
    else
      w = self.region:GetWidth() or 0
    end
  else
    local l, _, r = padOf(self)
    local sum = 0
    if self.dir == "row" then
      for i, c in ipairs(self.children) do
        if not c.hidden then
          sum = sum + c:NaturalW() + (i > 1 and self.gap or 0)
        end
      end
    else
      for _, c in ipairs(self.children) do
        if not c.hidden then sum = max(sum, c:NaturalW()) end
      end
    end
    w = sum + l + r
  end
  return clamp(w, self.minW, self.maxW)
end

function Node:LayoutLeaf(w, forcedH)
  local h
  if self.height then
    h = self.height
  elseif self.isText then
    if self.wrapText then
      -- GetStringHeight is only correct once the width has been applied, so
      -- this one measurement does touch the frame. Some clients answer stale
      -- on the first call after a width change; Reflow runs a second pass to
      -- catch that (see NeedsRemeasure below).
      self.region:SetWidth(max(1, w))
      self.region:SetWordWrap(true)
      h = self.region:GetStringHeight() or 0
      self.measuredAt = w
    else
      h = self.region:GetStringHeight() or self.region:GetHeight() or 0
    end
  else
    h = self.region:GetHeight() or 0
  end
  if forcedH then h = forcedH end
  self.rect.w, self.rect.h = w, h
  return h
end

--------------------------------------------------------------------------------
-- Row layout (the only direction that wraps)
--------------------------------------------------------------------------------

function Node:LayoutRow(width, forcedH)
  local pl, pt, pr, pb = padOf(self)
  local inner = max(0, width - pl - pr)

  -- 1. Break children into lines.
  local lines, cur, curMain = {}, {}, 0
  for _, c in ipairs(self.children) do
    if not c.hidden then
      local base = clamp(c.basis or c:NaturalW(), c.minW, c.maxW)
      -- The half-pixel slack keeps a row that fits exactly from wrapping its
      -- last item because of accumulated float error.
      if self.wrap and #cur > 0 and curMain + self.gap + base > inner + 0.5 then
        lines[#lines + 1] = { items = cur, main = curMain }
        cur, curMain = {}, 0
      end
      curMain = curMain + base + (#cur > 0 and self.gap or 0)
      cur[#cur + 1] = { node = c, base = base }
    end
  end
  if #cur > 0 then lines[#lines + 1] = { items = cur, main = curMain } end

  -- 2. Distribute free space, then measure each item's height at its final width.
  local totalH = 0
  for li, line in ipairs(lines) do
    local free = inner - line.main
    if free > 0.5 then
      local g = 0
      for _, it in ipairs(line.items) do g = g + (it.node.grow or 0) end
      if g > 0 then
        for _, it in ipairs(line.items) do
          it.w = clamp(it.base + free * (it.node.grow or 0) / g, it.node.minW, it.node.maxW)
        end
      end
    elseif free < -0.5 then
      -- Overflow: shrink proportionally to size * shrink factor, floored at
      -- minW so a label never collapses to nothing.
      local s = 0
      for _, it in ipairs(line.items) do s = s + (it.node.shrink or 1) * it.base end
      if s > 0 then
        for _, it in ipairs(line.items) do
          local share = free * ((it.node.shrink or 1) * it.base) / s
          it.w = clamp(it.base + share, it.node.minW or 1, it.node.maxW)
        end
      end
    end
    local lineH = 0
    for _, it in ipairs(line.items) do
      it.w = it.w or it.base
      it.h = it.node:Layout(it.w)
      lineH = max(lineH, it.h)
    end
    line.height = lineH
    totalH = totalH + lineH + (li > 1 and self.crossGap or 0)
  end

  -- 3. Cross-axis distribution, when the row has been given more height than
  --    its lines need. A single line stretches by default -- that is what lets
  --    a growing row fill the leftover height of a window. Several lines stack
  --    from the top unless alignContent says otherwise, which is how a wrapped
  --    block gets centred vertically inside its section.
  local lineGap, startY = self.crossGap, pt
  if forcedH then
    local extra = forcedH - pt - pb - totalH
    if extra > 0.5 then
      local ac = self.alignContent or (#lines == 1 and "stretch" or "start")
      if ac == "stretch" then
        local share = extra / #lines
        for _, line in ipairs(lines) do line.height = line.height + share end
      elseif ac == "center" then
        startY = pt + extra / 2
      elseif ac == "end" then
        startY = pt + extra
      elseif ac == "between" and #lines > 1 then
        lineGap = self.crossGap + extra / (#lines - 1)
      end
    end
  end

  -- 4. Place.
  local y = startY
  for _, line in ipairs(lines) do
    local used = 0
    for i, it in ipairs(line.items) do used = used + it.w + (i > 1 and self.gap or 0) end
    local free = max(0, inner - used)
    local x, spacing = pl, self.gap
    local j = self.justify
    if j == "center" then
      x = pl + free / 2
    elseif j == "end" then
      x = pl + free
    elseif j == "between" and #line.items > 1 then
      spacing = self.gap + free / (#line.items - 1)
    elseif j == "evenly" then
      local unit = free / (#line.items + 1)
      x, spacing = pl + unit, self.gap + unit
    end

    for _, it in ipairs(line.items) do
      local n, h = it.node, it.h
      local a = n.alignSelf or self.align
      if a == "stretch" and not n.height then
        h = line.height
        n:Layout(it.w, h) -- re-run so the child distributes its own new height
      end
      local cy = y
      if a == "center" then
        cy = y + (line.height - h) / 2
      elseif a == "end" then
        cy = y + line.height - h
      end
      n.rect.x, n.rect.y, n.rect.w, n.rect.h = x, cy, it.w, h
      x = x + it.w + spacing
    end
    y = y + line.height + lineGap
  end

  local h = (#lines > 0 and (y - lineGap) or pt) + pb
  if forcedH then h = forcedH end
  self.rect.w, self.rect.h = width, h
  return h
end

--------------------------------------------------------------------------------
-- Column layout
--------------------------------------------------------------------------------

function Node:LayoutColumn(width, forcedH)
  local pl, pt, pr, pb = padOf(self)
  local inner = max(0, width - pl - pr)

  local items, total = {}, 0
  for _, c in ipairs(self.children) do
    if not c.hidden then
      local a = c.alignSelf or self.align
      local cw = (a == "stretch") and inner
        or min(clamp(c.basis or c:NaturalW(), c.minW, c.maxW), inner)
      local ch = c:Layout(cw)
      items[#items + 1] = { node = c, w = cw, h = ch }
      total = total + ch + (#items > 1 and self.gap or 0)
    end
  end

  -- Vertical grow and shrink only mean something when the column has been told
  -- a height. The root gets one from the window; everything else inherits it.
  local free = forcedH and (forcedH - pt - pb - total) or 0
  if forcedH and free > 0.5 then
    local g = 0
    for _, it in ipairs(items) do g = g + (it.node.grow or 0) end
    if g > 0 then
      for _, it in ipairs(items) do
        if (it.node.grow or 0) > 0 then
          it.h = it.h + free * it.node.grow / g
          it.node:Layout(it.w, it.h)
        end
      end
      free = 0
    end
  elseif forcedH and free < -0.5 then
    -- Over budget. Unlike a row, a column shrinks only what has opted in:
    -- squashing a stack of buttons and labels to fit is never what was meant.
    -- Flex.Scroll opts in by default, so the usual answer to "does not fit"
    -- is that the scrolling region gives way and grows a scrollbar.
    local sum = 0
    for _, it in ipairs(items) do sum = sum + (it.node.shrink or 0) * it.h end
    if sum > 0 then
      for _, it in ipairs(items) do
        local sh = it.node.shrink or 0
        if sh > 0 then
          it.h = max(it.node.minH or 20, it.h + free * (sh * it.h) / sum)
          it.node:Layout(it.w, it.h)
        end
      end
      total = 0
      for i, it in ipairs(items) do total = total + it.h + (i > 1 and self.gap or 0) end
      free = forcedH - pt - pb - total
    end
  end

  local y, spacing = pt, self.gap
  local j = self.justify
  if free > 0.5 then
    if j == "center" then
      y = pt + free / 2
    elseif j == "end" then
      y = pt + free
    elseif j == "between" and #items > 1 then
      spacing = self.gap + free / (#items - 1)
    elseif j == "evenly" then
      local unit = free / (#items + 1)
      y, spacing = pt + unit, self.gap + unit
    end
  end

  for _, it in ipairs(items) do
    local n = it.node
    local a = n.alignSelf or self.align
    local x = pl
    if a == "center" then
      x = pl + (inner - it.w) / 2
    elseif a == "end" then
      x = pl + inner - it.w
    end
    n.rect.x, n.rect.y, n.rect.w, n.rect.h = x, y, it.w, it.h
    y = y + it.h + spacing
  end

  local h = (#items > 0 and (y - spacing) or pt) + pb
  if forcedH then h = forcedH end
  self.rect.w, self.rect.h = width, h
  return h
end

function Node:LayoutRaw(w, forcedH)
  if self.kind == "leaf" then return self:LayoutLeaf(w, forcedH) end
  if self.isScroll then return self:LayoutScroll(w, forcedH) end
  if self.dir == "row" then return self:LayoutRow(w, forcedH) end
  return self:LayoutColumn(w, forcedH)
end

function Node:Layout(w, forcedH)
  -- A declared height is a forced height. Leaves handled this already; boxes
  -- did not, so a fixed-height title bar sized itself to its tallest button
  -- and every gap below it was off by the difference.
  forcedH = forcedH or self.height
  local h = self:LayoutRaw(w, forcedH)
  -- minH is what gives a section a floor to scroll against: without one, a
  -- content-sized box just shrinks forever and never overflows anything.
  if not forcedH and self.minH and h < self.minH then
    h = self:LayoutRaw(w, self.minH)
  end
  return h
end

--------------------------------------------------------------------------------
-- Scrolling
--------------------------------------------------------------------------------

-- A scroll node is an ordinary box whose children are laid out at their
-- natural height and then viewed through a window of whatever height the
-- parent gave it. That is the whole trick: inside a scroll, `grow` on the
-- cross axis stops meaning anything, because there is no leftover space --
-- content decides the height and the viewport decides what you see of it.

function Node:LayoutScroll(width, forcedH)
  local viewH = forcedH or 0
  local function measure(w)
    if self.dir == "row" then return self:LayoutRow(w) end
    return self:LayoutColumn(w)
  end

  local contentH = measure(width)
  local needBar = viewH > 0 and contentH > viewH + 0.5
  if needBar then
    -- The bar takes width from the content, which can make wrapped text taller,
    -- which can only ever make the bar more necessary -- so one re-measure is
    -- enough and there is no flip-flop to guard against.
    contentH = measure(width - self.barW)
  end

  self.needBar = needBar
  self.contentH = contentH
  self.contentW = needBar and (width - self.barW) or width
  self.viewH = viewH > 0 and viewH or contentH
  self.rect.w, self.rect.h = width, self.viewH
  return self.rect.h
end

function Node:MaxScroll()
  return max(0, (self.contentH or 0) - (self.viewH or 0))
end

function Node:ScrollTo(offset)
  local maxOff = self:MaxScroll()
  self.offset = clamp(offset or 0, 0, maxOff)
  self.viewport:SetVerticalScroll(snap(self.offset))
  self:UpdateThumb()
end

function Node:UpdateThumb()
  local maxOff = self:MaxScroll()
  if maxOff <= 0 then return end
  local trackH = max(1, self.viewH or 1)
  local thumbH = max(20, trackH * (self.viewH / self.contentH))
  self.thumb:SetHeight(snap(thumbH))
  self.thumb:SetPoint("TOP", self.bar, "TOP", 0, -snap((self.offset / maxOff) * (trackH - thumbH)))
end

function Node:ApplyScroll()
  self.viewport:ClearAllPoints()
  self.viewport:SetPoint("TOPLEFT")
  self.viewport:SetPoint("BOTTOMRIGHT", self.needBar and -self.barW or 0, 0)
  self.content:SetSize(max(1, snap(self.contentW)), max(1, snap(self.contentH)))
  self.bar:SetShown(self.needBar and true or false)
  -- Content may have shrunk out from under a scrolled-down view.
  self:ScrollTo(self.offset or 0)
end

function Flex.Scroll(parentFrame, props)
  local n = defaults(setmetatable(props or {}, Node))
  n.kind = "box"
  n.isScroll = true
  n.barW = n.barW or 8
  n.offset = 0
  -- The point of a scroll region is to be the thing that gives way when the
  -- window is too short, so it opts into column shrink unless told otherwise.
  if n.shrink == nil then n.shrink = 1 end

  n.frame = CreateFrame("Frame", nil, parentFrame)
  n.viewport = CreateFrame("ScrollFrame", nil, n.frame)
  n.content = CreateFrame("Frame", nil, n.viewport)
  n.viewport:SetScrollChild(n.content)
  n.contentFrame = n.content

  n.viewport:EnableMouseWheel(true)
  n.viewport:SetScript("OnMouseWheel", function(_, delta)
    n:ScrollTo((n.offset or 0) - delta * (n.wheelStep or 40))
  end)

  n.bar = CreateFrame("Frame", nil, n.frame)
  n.bar:SetWidth(n.barW)
  n.bar:SetPoint("TOPRIGHT")
  n.bar:SetPoint("BOTTOMRIGHT")
  n.bar.track = n.bar:CreateTexture(nil, "BACKGROUND")
  n.bar.track:SetAllPoints()
  n.bar.track:SetColorTexture(0.15, 0.15, 0.18, 0.55)

  n.thumb = CreateFrame("Button", nil, n.bar)
  n.thumb:SetPoint("LEFT")
  n.thumb:SetPoint("RIGHT")
  n.thumb.tex = n.thumb:CreateTexture(nil, "ARTWORK")
  n.thumb.tex:SetAllPoints()
  n.thumb.tex:SetColorTexture(0.45, 0.45, 0.52, 1)
  n.thumb:SetScript("OnEnter", function(s) s.tex:SetColorTexture(0.58, 0.58, 0.66, 1) end)
  n.thumb:SetScript("OnLeave", function(s) s.tex:SetColorTexture(0.45, 0.45, 0.52, 1) end)

  -- Thumb drag. Cursor coordinates come back in screen units, so they have to
  -- be divided by the frame's effective scale before they mean anything here.
  n.thumb:SetScript("OnMouseDown", function(s)
    local _, cy = GetCursorPosition()
    s.grabY, s.grabOffset = cy / s:GetEffectiveScale(), n.offset or 0
    s:SetScript("OnUpdate", function()
      local _, y = GetCursorPosition()
      y = y / s:GetEffectiveScale()
      local trackH = max(1, n.viewH or 1)
      local thumbH = s:GetHeight()
      local travel = max(1, trackH - thumbH)
      n:ScrollTo(s.grabOffset + ((s.grabY - y) / travel) * n:MaxScroll())
    end)
  end)
  n.thumb:SetScript("OnMouseUp", function(s) s:SetScript("OnUpdate", nil) end)

  n.bar:Hide()
  return n
end

--------------------------------------------------------------------------------
-- Applying the result
--------------------------------------------------------------------------------

function Node:Apply()
  -- A scroll node's children live on the scroll child, which moves under the
  -- viewport. Everything else anchors to the node's own frame.
  local anchor = self.contentFrame or self.frame
  if self.isScroll then self:ApplyScroll() end
  for _, c in ipairs(self.children) do
    local obj = c.frame or c.region
    if c.hidden then
      obj:Hide()
    else
      obj:Show()
      obj:ClearAllPoints()
      -- One absolute anchor per node. This single line is the whole reason
      -- reflow works.
      obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", snap(c.rect.x), -snap(c.rect.y))
      if c.isText then
        -- Sizing a FontString clips it, so a width is only applied to text that
        -- asked for one: wrapText to re-flow, clipText to truncate. Without
        -- clipText a shrunken label keeps drawing its full string over
        -- whatever the layout put beside it.
        if c.wrapText or c.clipText then obj:SetWidth(max(1, snap(c.rect.w))) end
      else
        obj:SetSize(max(1, snap(c.rect.w)), max(1, snap(c.rect.h)))
      end
      if c.kind == "box" then c:Apply() end
      if c.dbg then c:PaintDebug() end
    end
  end
end

--------------------------------------------------------------------------------
-- Reflow
--------------------------------------------------------------------------------

-- Frame resizes arrive as a storm -- one per drag frame, and our own SetSize
-- calls would re-enter the handler. So invalidation is a flag and the work
-- happens once, on the next OnUpdate.
local dirty, queue = {}, {}
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
  if not next(dirty) then return end
  wipe(queue)
  for node in pairs(dirty) do queue[#queue + 1] = node end
  wipe(dirty)
  for _, node in ipairs(queue) do node:Reflow() end
end)

function Node:Invalidate()
  local root = self
  while root.parent do root = root.parent end
  dirty[root] = true
end

Flex.passes = 0

function Node:Reflow()
  local frame = self.frame
  if not frame:IsShown() then return end
  local w, h = frame:GetWidth(), frame:GetHeight()
  if not w or w < 1 then return end

  self:Layout(w, h)
  self:Apply()

  -- Second pass for wrapped text: on some clients GetStringHeight lags the
  -- SetWidth by a frame, so the first answer can be a line short. Re-running
  -- once with the widths already applied settles it, and costs nothing when
  -- nothing changed.
  if self.hasWrapText then
    self:Layout(w, h)
    self:Apply()
  end

  Flex.passes = Flex.passes + 1
  if self.onReflow then self:onReflow() end
end

-- Attaches the engine to an existing frame -- the window itself, usually.
function Flex.Root(frame, props)
  local n = defaults(setmetatable(props or {}, Node))
  n.kind = "box"
  n.frame = frame
  frame:HookScript("OnSizeChanged", function() n:Invalidate() end)
  frame:HookScript("OnShow", function() n:Invalidate() end)
  return n
end

--------------------------------------------------------------------------------
-- Debug overlay
--------------------------------------------------------------------------------

local DEBUG_COLORS = {
  { 1, 0.3, 0.3 }, { 0.3, 1, 0.4 }, { 0.4, 0.6, 1 }, { 1, 0.9, 0.3 }, { 1, 0.4, 1 },
}

function Node:PaintDebug()
  local d = self.dbg
  if not d then return end
  local depth, p = 1, self.parent
  while p do depth, p = depth + 1, p.parent end
  local c = DEBUG_COLORS[(depth - 1) % #DEBUG_COLORS + 1]
  for _, t in ipairs(d) do t:SetColorTexture(c[1], c[2], c[3], 0.85) end
end

local function makeOutline(node)
  local f = node.frame
  local t = {}
  for i = 1, 4 do
    t[i] = f:CreateTexture(nil, "OVERLAY")
  end
  t[1]:SetPoint("TOPLEFT");     t[1]:SetPoint("TOPRIGHT");     t[1]:SetHeight(1)
  t[2]:SetPoint("BOTTOMLEFT");  t[2]:SetPoint("BOTTOMRIGHT");  t[2]:SetHeight(1)
  t[3]:SetPoint("TOPLEFT");     t[3]:SetPoint("BOTTOMLEFT");   t[3]:SetWidth(1)
  t[4]:SetPoint("TOPRIGHT");    t[4]:SetPoint("BOTTOMRIGHT");  t[4]:SetWidth(1)
  return t
end

function Flex.SetDebug(node, on)
  if node.kind == "box" and node.frame then
    if on then
      node.dbg = node.dbg or makeOutline(node)
      for _, t in ipairs(node.dbg) do t:Show() end
      node:PaintDebug()
    elseif node.dbg then
      for _, t in ipairs(node.dbg) do t:Hide() end
    end
  end
  for _, c in ipairs(node.children) do Flex.SetDebug(c, on) end
end
