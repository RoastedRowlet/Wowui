local _, NS = ...

-- Standalone options window. Each tab:
--
--   [ Enable module ]      always at the top, never scrolls away
--   [ Preview        ]     pinned, so it stays visible while you adjust
--   [ scrolling sections ] collapsible, remembered per character
--
-- The colour preview runs the real rule-priority logic against pretend debuff
-- state -- legal because the pretend state is ours, not the game's.

local window, tabButtons, tabPanels = nil, {}, {}
-- The three Global Settings pages, in rail order. Held separately from tabPanels
-- because their rebuild reaches into fields only they have.
local globalPanels
-- Height of the preview strip, and the width of the test column beside it.

-- Where a collapsible section lands, so the preview can sit on the same edges.
-- The body is a fixed 716-wide scroll child at panel x=4, and LayoutSections
-- insets each section by 6 -- so a section spans x=10 to x=714.
local BODY_W = 704
local BODY_X = 10
-- One inset for everything inside the preview panel. Its contents were at 4,
-- 8 and 10 depending on which page put them there, so nothing lined up with
-- the header text above them or with each other. 10 matches the header's
-- title indent.
local HEAD_PAD = 10

-- The preview section's skin. Same widget as every other section, warm
-- instead of grey, because this is the one that SHOWS rather than configures.
local PREVIEW_PALETTE = {
  bg          = { 0.13, 0.11, 0.07, 0.6 },
  border      = { 0.40, 0.35, 0.22, 1 },
  headerBG    = { 0.21, 0.17, 0.09, 0.95 },
  headerHover = { 0.27, 0.22, 0.12, 1 },
}
local TEST_COL_W = 150


local healthTab, iconTab
-- The three Aura Icons pages in rail order -- filters, position, text. Each
-- has its own body and its own preview stage.
local iconPanels
local ruleRows, conditionRows, iconRows = {}, {}, {}
-- Border rules get their own pools: the two lists render independently and
-- sharing a pool would have rows fighting over which list they belong to.
local borderRows, borderCondRows = {}, {}
local expandedRule = nil
-- Which of the two panels an expanded rule shows: "rule" for its debuffs,
-- "appearance" for its colour/texture/target-focus controls. Only matters
-- while expandedRule is set -- the row's two buttons each claim one value.
local expandedSection = "rule"
local statusText, profileLabel
local preview = { active = {} }
-- Test mode paints the SIMULATED rules onto real plates, so it needs the same
-- ticked-debuff set the previews use.
function NS.PreviewActive() return preview.active end

-- What the PREVIEW PLATE is pretending is true, for the two modules that have
-- no debuff to tick.
--
-- Stage only. It paints the simulated plate at the top of the page and
-- touches nothing on a real nameplate -- previewing a colour is a question
-- about what it looks like, not a reason to repaint the pull you are standing
-- in. Session-only too: never written to the profile.
--
-- One key each, not a set. Two threat states cannot both be true on a mob and
-- a unit cannot be both your target and your focus at once, so a dropdown is
-- the honest control -- picking one clears the other by construction.
NS.stagePreview = { threat = nil, mark = nil }

-- The entry a previewed key names, for one half. nil when nothing is picked,
-- or when the state it names is switched off -- a preview of something that
-- would not draw is a lie about the profile.
function NS.StagePreviewThreat(kind)
  local key = NS.stagePreview.threat
  if not key or not NS.ThreatModule then return nil end
  local entry = NS.ThreatModule(kind).states[key]
  if entry and entry.enabled ~= false then return entry end
end

function NS.StagePreviewMark(kind)
  local key = NS.stagePreview.mark
  if not key or not NS.MarkModule then return nil end
  local entry = NS.MarkModule(kind).states[key]
  if not entry then return nil end
  if entry.enabled ~= false then return entry end
  -- A half that is off previews only when the state is off ENTIRELY.
  --
  -- With one half on, the switches are a real answer and the preview should
  -- honour them -- otherwise a border you deliberately turned off comes back
  -- on the preview and the two disagree. With both off there is no answer to
  -- honour, and refusing to draw is how focus became invisible in a control
  -- whose whole purpose is showing you what it would look like.
  local other = NS.MarkModule(kind == "border" and "bar" or "border").states[key]
  if other and other.enabled ~= false then return nil end
  return entry
end

local ROW_H = 26
local STAGE_H = 92

-- Shared control metrics. Every interactive widget in this window is this
-- tall, and boxy ones (tick box, switch) are this wide, so a row mixing a
-- button, a dropdown and a checkbox reads as one row rather than three
-- heights stacked. Border weight and colour are shared for the same reason.
local CTRL_H = 20
local CTRL_BOX_W = 20
local CTRL_EDGE = 1

-- Every border in this window, drawn on the physical pixel grid.
--
-- This is the fix for borders and tick boxes whose sides are visibly
-- different weights -- one edge fat, the opposite one thin or missing. The
-- cause is Backdrop: `edgeSize = 1` is one UI UNIT, and at any UI scale that
-- is not 1.0 (the default at most resolutions is not) a unit is a fractional
-- number of screen pixels. The GPU then resolves each of the four edges
-- against a different subpixel position, so one rounds up to two pixels and
-- another rounds down to nearly nothing. No amount of tuning edgeSize fixes
-- it, because the number is not the problem -- the units are.
--
-- So the edges stop being a backdrop and become four textures placed through
-- PixelUtil, which converts a size in UI units to the nearest WHOLE number of
-- physical pixels for the frame's own effective scale. Same treatment
-- NS.BuildOutline already gives the plate border and NS.FlexRule gives the
-- hairlines; this brings the window's controls onto it too.
--
-- SetBackdropBorderColor is overridden on the frame rather than replaced at
-- the call sites: every widget here already paints its border by calling it,
-- hover states included, and those calls keep working untouched.
local function PixelBorder(frame, thickness)
  if not frame or frame.ptEdges then return frame end
  local edges = {}
  for index = 1, 4 do
    edges[index] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    edges[index]:SetColorTexture(0.36, 0.36, 0.42, 1)
  end
  frame.ptEdges = edges
  frame.ptEdgeThickness = thickness or CTRL_EDGE

  local function Apply()
    local size = frame.ptEdgeThickness
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if PixelUtil and PixelUtil.GetNearestPixelSize then
      local ok, snapped = pcall(PixelUtil.GetNearestPixelSize, size, scale, size)
      if ok and snapped and snapped > 0 then size = snapped end
    end
    local SetPoint = (PixelUtil and PixelUtil.SetPoint)
      or function(region, ...) region:SetPoint(...) end
    for _, edge in ipairs(edges) do edge:ClearAllPoints() end
    -- Top and bottom run the full width; the sides run the full height, so the
    -- corners are painted twice in one colour rather than left as notches.
    SetPoint(edges[1], "TOPLEFT", frame, "TOPLEFT", 0, 0)
    SetPoint(edges[1], "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[1]:SetHeight(size)
    SetPoint(edges[2], "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    SetPoint(edges[2], "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(size)
    SetPoint(edges[3], "TOPLEFT", frame, "TOPLEFT", 0, 0)
    SetPoint(edges[3], "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[3]:SetWidth(size)
    SetPoint(edges[4], "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    SetPoint(edges[4], "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[4]:SetWidth(size)
  end
  frame.ptApplyEdges = Apply
  Apply()
  -- Effective scale follows the parent chain, and a control is often parented
  -- and sized after it is built, so the snap is redone when either could have
  -- changed rather than once at creation.
  if frame.HookScript then
    frame:HookScript("OnShow", Apply)
    frame:HookScript("OnSizeChanged", Apply)
  end

  function frame:SetBackdropBorderColor(r, g, b, a)
    for _, edge in ipairs(edges) do edge:SetColorTexture(r, g, b, a or 1) end
  end
  function frame:SetEdgeThickness(value)
    frame.ptEdgeThickness = value
    Apply()
  end
  function frame:SetEdgeShown(shown)
    for _, edge in ipairs(edges) do edge:SetShown(shown and true or false) end
  end
  return frame
end
NS.PixelBorder = PixelBorder

-- The inside of a small square control -- a tick box's fill, a swatch's
-- colour -- centred and sized, rather than pinned by four separate insets.
--
-- Four insets is why the ticked boxes looked lopsided. `TOPLEFT, 3, -3` and
-- `BOTTOMRIGHT, -3, 3` are four independent offsets in UI units, and at a
-- fractional UI scale each one rounds to physical pixels on its own -- so the
-- gap above the fill could land on 2 pixels while the gap below it landed on
-- 3, in a box 20 units across. One centred texture cannot disagree with
-- itself: the padding is the same measurement on both sides by construction,
-- whatever the scale does to it.
--
-- Re-applied on size change because the frame is laid out by Flex after it is
-- built, so the size it has at creation is not the size it keeps.
local function PixelFill(frame, tex, inset)
  local function Apply()
    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 0 or h <= 0 then return end
    local pad = (inset or 3) * 2
    tex:ClearAllPoints()
    tex:SetPoint("CENTER")
    tex:SetSize(math.max(1, w - pad), math.max(1, h - pad))
  end
  if frame.HookScript then
    frame:HookScript("OnShow", Apply)
    frame:HookScript("OnSizeChanged", Apply)
  end
  Apply()
  return tex
end

-- One hairline, in whole physical pixels, for the places that draw a single
-- line rather than a box: the selection outline on an open row, the table's
-- column separators, the dotted empty chip.
function NS.PixelWeight(region, size)
  size = size or 1
  local scale = region and region.GetEffectiveScale and region:GetEffectiveScale() or 1
  if PixelUtil and PixelUtil.GetNearestPixelSize then
    local ok, snapped = pcall(PixelUtil.GetNearestPixelSize, size, scale, size)
    if ok and snapped and snapped > 0 then return snapped end
  end
  return size
end

-- Section metrics in one place. These were spelled out as bare numbers in
-- CollapsibleSection and again in LayoutSections, so "too much white space"
-- was two edits that had to agree.
local SECTION_HEAD_H = 30 -- header bar plus the 1px the backdrop insets it
local SECTION_PAD    = 6  -- under the content, inside the border
local SECTION_GAP    = 8  -- between stacked sections
local SECTION_INSET  = 6  -- left/right, from the body's edge

-------------------------------------------------------------------------------
-- Layout spec
--
-- EVERY number that positions or sizes something on a Flex-laid page lives
-- here. Not "most of them": a single literal offset left in a row is a column
-- that can drift out from under its heading, and drift is invisible until a
-- screenshot shows a label sitting on a button.
--
-- On NS rather than as file-locals because this file is a handful of locals
-- under Lua's 200-per-chunk ceiling, and because dev/test_flex_layout.lua
-- reads the same table -- a test that hardcoded its own copy of these numbers
-- would pass while the window was wrong.
--
--   ROW_INSET   left and right edge every row, header and divider starts at
--   NOTE_INSET  explanatory text, indented PAST the row edge so it reads as
--               commentary on the list rather than another entry in it
--   COL_GAP     between columns, everywhere
--   ROW_H       one list row; the same height for every row on every page
--   HEAD_H      the column-heading strip above a list
--   CTRL_ROW_H  a row of controls that is not a list row (role, thickness)
--   DIVIDER     hairline rules; drawn through PixelUtil, see FlexRule
--   CHIP_W/H    a colour chip in a Bar or Border column
--   BOX         a tick box, and therefore the width of a tick column's control
-------------------------------------------------------------------------------
NS.UI = {
  ROW_INSET  = 12,
  NOTE_INSET = 26,
  COL_GAP    = 8,
  ROW_H      = ROW_H,
  HEAD_H     = 18,
  CTRL_ROW_H = 22,
  DIVIDER    = 1,
  -- The outline around the row whose editor is open. Two pixels, not one: it
  -- has to read as a box drawn AROUND something at a glance, and at one pixel
  -- it was the same weight as the table's own hairlines.
  SELECT_EDGE = 2,
  CHIP_W     = 30,
  CHIP_H     = 14,
  BOX        = CTRL_BOX_W,
  GRIP       = 14,   -- the drag handle's own texture

  -- Vertical rhythm. Three gaps, by what they separate, so "tighten the rows"
  -- and "tighten the blocks" are different edits.
  ROW_GAP    = 2,    -- between rows of one list
  GROUP_GAP  = 6,    -- between blocks inside a section
  FIELD_GAP  = 4,    -- between the lines of one block
  PAD_TOP    = 8,    -- inside a section, above its first block
  PAD_BOTTOM = 10,   -- and below its last

  -- Control widths. A dropdown's width is a layout decision (it sets the
  -- column everything after it starts at), not a property of the dropdown.
  DROP_W     = 200,
  DROP_SM_W  = 96,
  SLIDER_W   = 150,
  -- Short, because it shares its line with a label and a swatch rather than
  -- owning the row the way Thickness and Gap do.
  SLIDER_SM  = 96,

  -- The one-rule preview bar. Roughly a nameplate at 2x, which is the
  -- smallest size a tiled pattern is honest at.
  PREVIEW_W  = 300,
  PREVIEW_H  = 28,

  -- Label columns. A field's label gets a column so several rows start their
  -- controls on one line down the panel, instead of each label's own width.
  -- Four sizes because the words differ: "Color" against "Show on target".
  LABEL_W    = 56,
  LABEL_MD   = 70,
  LABEL_SM   = 60,
  LABEL_XS   = 50,
  LABEL_TINY = 40,
  LABEL_LG   = 110,

  -- Narrowest the style panel is laid out at before its own rows start
  -- wrapping their labels away.
  PANEL_MIN_W = 260,

  -- The threat row's chip strip: three states, side by side, inside one
  -- column. Three of these plus two CHIP_GAPs must equal RULE_COLS.bar, which
  -- dev/test_alignment.lua asserts rather than trusting the arithmetic in this
  -- comment -- it was wrong the first time it was written here.
  -- SQUARE, by construction: a state chip is the same measurement both ways,
  -- so the strip reads as a row of swatches rather than as three short bars.
  -- Derived from CHIP_H rather than written down again, which is what let the
  -- two drift to 12x15 in the first place.
  STRIP_CHIP = 14,

  -- The rule editor's blocks: one per half, plus the rule's own conditions.
  BLOCK_MIN_W = 210,
  BLOCK_PAD   = 8,
  SWATCH_GRID = 30,   -- one fill in the pattern picker
  PILL_H      = 20,   -- a debuff in the rule's own list
  PILL_ICON   = 16,
  PILL_PAD    = 4,
  CLOSE_X     = 16,   -- the remove control on a pill
  CHIP_GAP    = 4,    -- between swatches in that grid

  -- The dotted outline on a half that paints nothing: dash length, then the
  -- hole after it. Both in pixels, along every edge of the chip.
  CHIP_DASH     = 3,
  CHIP_DASH_GAP = 3,

  -- The resolution ladder: a rank column, then a stripe saying which band
  -- this is, then the band's name.
  BAND_H     = 24,
  BAND_RANK  = 18,
  BAND_STRIPE = 3,
  BAND_NAME  = 150,
}

-- Rule row columns, shared by the row and its header. One table, so a heading
-- cannot end up over the wrong control -- which is what happened every time
-- these were two lists of x offsets kept in step by hand.
--
-- A column is the space a control is CENTRED in, so it is at least as wide as
-- the control: `on` and `del` are the tick box plus breathing room, `edit` is
-- the button's own width.
NS.RULE_COLS = {
  -- Wide enough for the word "Order" over it. The grip itself is still
  -- NS.UI.GRIP wide and centres in the column: the heading is the widest
  -- thing here, and a column sized to the control forced the heading to be
  -- abbreviated to "Ord".
  grip   = 38,
  -- The two halves a rule paints. Both are always present: a rule that draws
  -- only its border is a rule with an empty bar cell, not a rule on another
  -- page.
  -- Wide enough for the threat row's three state chips, because that row is
  -- in this table and its cells are these columns. Sized for the widest thing
  -- a column holds, and every narrower thing centres in it -- which is what
  -- stopped the strips from shouldering the headers out of line.
  -- STRIP_CHIP * 3 + CHIP_GAP * 2, the threat strip's own width. Derived
  -- rather than picked:
  -- the column has to hold the widest thing in it, and that is the strip.
  bar    = NS.UI.STRIP_CHIP * 3 + NS.UI.CHIP_GAP * 2,
  border = NS.UI.STRIP_CHIP * 3 + NS.UI.CHIP_GAP * 2,
  -- The Slots column holds one integer now, not "3 slots", so it needs the
  -- width of its own heading and no more -- which is what pays for the wider
  -- Order column and the square state chips without pushing the table's
  -- minimum width past 460. dev/test_alignment.lua lays the table out at that
  -- width and fails if the last column stops landing on the row inset.
  cost   = 38,
  edit   = 70,
  del    = 24,
  on     = 24,
}

-- Threat rows use the same vocabulary: a swatch column, then a tick column.
NS.THREAT_COLS = {
  swatch = NS.UI.CHIP_W,
  strip  = NS.UI.CHIP_W,
  on     = 30,
}

-- Theme -- every colour the window chrome uses. Edit and /reload to re-skin;
-- nothing else in this file changes. {r,g,b} or {r,g,b,a}, 0-1. See
-- PlateTweaks_Theme.md for what each one touches.
local THEME = {
  accent        = { 0.35, 0.62, 0.98 },        -- selected tab, focus rings, slider fill, checkbox fill
  accentBorder  = { 0.45, 0.68, 1.00 },        -- border drawn around an active/checked control

  windowBG      = { 0.07, 0.07, 0.085, 0.96 }, -- outer window fill
  windowBorder  = { 0.34, 0.34, 0.40, 1 },     -- outer window edge

  titleBarBG    = { 0.13, 0.13, 0.16, 1 },     -- title bar strip
  titleText     = { 1, 1, 1 },

  tabBG         = { 0.12, 0.12, 0.14, 1 },     -- unselected tab
  tabBGHover    = { 0.16, 0.16, 0.19, 1 },
  tabBGSelected = { 0.20, 0.22, 0.27, 1 },
  tabBorder     = { 0.26, 0.26, 0.31, 1 },     -- unselected tab border
  tabTextDim    = { 0.66, 0.66, 0.70 },        -- unselected tab label

  divider       = { 0.40, 0.40, 0.45, 0.6 },   -- hairline rules inside a section
  tableSep      = { 1, 1, 1, 0.06 },           -- vertical column separators in the rule table
  -- The empty chip's dashes and its X are ONE mark, so they are one colour:
  -- a bright outline around a dim cross read as two different statements
  -- about the same chip.
  chipCross     = { 1, 1, 1, 0.30 },           -- the dotted outline AND the X inside an empty chip
  chipEdge      = { 0, 0, 0, 0.85 },           -- hairline around a chip that IS painting
  selection     = { 0.79, 0.64, 0.15, 1 },     -- the row whose editor is open
  bandThreat    = { 0.85, 0.20, 0.20, 1 },     -- resolution ladder, by band
  bandMark      = { 0.30, 0.72, 0.95, 1 },     -- target/focus, between threat and your rules
  bandRules     = { 1.00, 0.35, 0.75, 1 },
  bandMissing   = { 0.42, 0.35, 0.84, 1 },
  bandHost      = { 0.34, 0.34, 0.40, 1 },
  blockBG       = { 1, 1, 1, 0.03 },           -- a half's block in the editor
  blockBGOff    = { 0, 0, 0, 0.35 },           -- ...when that half is switched off
  rowRecessed   = 0.18,                        -- alpha of the rows an open editor is not about
  pageRecessed  = 0.15,                        -- ...and of every OTHER section on the page
  blockEdge     = { 0.30, 0.30, 0.36, 1 },
  panelBG       = { 0.10, 0.10, 0.12, 0.6 },   -- collapsible section body
  panelBorder   = { 0.30, 0.30, 0.34, 1 },
  headerBG      = { 0.17, 0.17, 0.20, 0.9 },   -- section header bar
  headerBGHover = { 0.22, 0.22, 0.26, 0.95 },
  headerText    = { 0.85, 0.75, 0.45 },        -- section header title / column headers

  stageBG       = { 0.20, 0.20, 0.22, 1 },     -- preview plate stage, icon swatches
  stageBorder   = { 0.05, 0.05, 0.06, 1 },

  textNormal    = { 1, 1, 1 },
  textDim       = { 0.62, 0.62, 0.66 },        -- Dim() labels, hints
  textDisabled  = { 0.45, 0.45, 0.45 },

  scrollTrack   = { 0.15, 0.15, 0.18, 0.55 },
  scrollThumb   = { 0.35, 0.35, 0.40, 1 },
  scrollThumbHover = { 0.45, 0.45, 0.52, 1 },
  scrollBarWidth   = 8,
  scrollWheelStep  = 44, -- pixels scrolled per notch
}
NS.OptionsTheme = THEME -- exposed for anyone who wants to poke at it from /run

-- Unpacks a THEME color, with an optional alpha override for the few spots
-- that want the same color at a different opacity (e.g. a hover state).
local function RGBA(color, alphaOverride)
  return color[1], color[2], color[3], alphaOverride or color[4] or 1
end

-- Shown in the icon preview only when nothing is tracked yet, so the layout
-- controls always have something to demonstrate on.
local SAMPLE_AURAS = { 980, 172, 48181, 589, 34914, 8921 }

-- Stand-in timer and stack text for the previews. Varied on purpose: a row of
-- identical values hides the fact that a two-digit timer is wider, or that
-- trailing zeros ("24.0") behave differently than a bare integer ("24").
local SAMPLE_TIME_VALUES = { 12, 8.234, 3.456, 24, 0.876, 17.5 }
local SAMPLE_COUNTS = { "3", "2", "9", "5", "1", "12" }

local PRECISION_ENTRIES = {
  { text = "3",     value = 0 },
  { text = "3.4",   value = 1 },
  { text = "3.45",  value = 2 },
  { text = "3.456", value = 3 },
}

local function FormatPreviewTime(value, precision)
  return ("%." .. (precision or 1) .. "f"):format(value)
end

local ANCHOR_POINTS = {
  { text = "Top Left",      value = "TOPLEFT" },
  { text = "Top",    value = "TOP" },
  { text = "Top Right",     value = "TOPRIGHT" },
  { text = "Left",   value = "LEFT" },
  { text = "Center",        value = "CENTER" },
  { text = "Right",  value = "RIGHT" },
  { text = "Bottom Left",   value = "BOTTOMLEFT" },
  { text = "Bottom", value = "BOTTOM" },
  { text = "Bottom Right",  value = "BOTTOMRIGHT" },
}

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------

-- Every piece of text in this window goes through StyleText, so the whole GUI
-- shares one typeface. Expressway comes from LibSharedMedia if another addon
-- (ElvUI, Details, a SharedMedia pack) has registered it; otherwise this
-- quietly falls back to the stock font.
local GUI_FONT = "Expressway"

local function StyleText(fontString, size, outline)
  NS.ApplyFont(fontString, GUI_FONT, size or 12, outline or "NONE")
  return fontString
end

local function Label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetText(text or "")
  StyleText(fs, template == "GameFontNormal" and 13 or 12)
  return fs
end

local function Dim(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetText(text or "")
  StyleText(fs, 11)
  fs:SetTextColor(RGBA(THEME.textDim))
  return fs
end

local function Header(parent, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetText(text or "")
  StyleText(fs, 11)
  fs:SetTextColor(RGBA(THEME.headerText))
  return fs
end

-- Tooltips.
--
-- Held for a second before appearing: this window is dense, and firing the
-- instant the cursor crosses something turns moving the mouse into a flicker.
--
-- HookScript, not SetScript -- half these widgets already own OnEnter/OnLeave.
--
-- Everything anchors to the cursor. Opening off the window's left edge was
-- tried and read as a different, unrelated panel.
--
-- Text may be a string or a function: a pooled rule row has to describe
-- whichever rule it currently holds.

-- Long enough that sweeping the cursor across a dense page stays quiet, short
-- enough that deliberately resting on something feels answered rather than
-- waited out. A full second was the latter.
local TIP_DELAY = 0.4
-- Bumped on every enter and leave. A timer that fires after its generation has
-- moved on is stale -- the cursor left, or moved to another widget -- and does
-- nothing. Cheaper and more reliable than cancelling timers.
local tipGeneration = 0

local function TipText(value, frame)
  if type(value) == "function" then
    local ok, result = pcall(value, frame)
    return ok and result or nil
  end
  return value
end

local function HideTip()
  tipGeneration = tipGeneration + 1
  if GameTooltip then GameTooltip:Hide() end
end

local function ShowTip(frame)
  local spec = frame.ptTip
  if not spec or not GameTooltip then return end
  -- The cursor may have moved on between the timer being set and it firing.
  if not frame:IsVisible() or not frame:IsMouseOver() then return end
  -- Label hit frames outlive their text: the fontstring can be hidden (the
  -- missing-health colour row, say) while the invisible frame over it stays
  -- put, which would answer the cursor over blank space.
  if frame.ptTipOwner and not frame.ptTipOwner:IsShown() then return end

  local title = TipText(spec.title, frame)
  local body = TipText(spec.body, frame)
  if not title and not body then return end

  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR_RIGHT", 8, 0)
  pcall(GameTooltip.SetClampedToScreen, GameTooltip, true)

  if title then GameTooltip:AddLine(title, 1, 0.82, 0.1) end
  -- wrap = true, or a sentence of explanation becomes one unreadable line the
  -- width of the screen.
  if body then GameTooltip:AddLine(body, 0.82, 0.82, 0.88, true) end
  local note = TipText(spec.note, frame)
  if note then GameTooltip:AddLine(note, 0.55, 0.75, 1, true) end
  GameTooltip:Show()
end

-- Tip(frame, title, body, opts)
--   opts.note -> a third line, for a caveat or a pointer elsewhere
-- Returns the frame, so it can wrap a constructor call inline.
local function Tip(frame, title, body, opts)
  if not frame or not frame.HookScript then return frame end
  opts = opts or {}
  frame.ptTip = { title = title, body = body, note = opts.note }

  -- Hooked once per widget. These are pooled and re-labelled on every rebuild,
  -- so hooking per rebuild would stack a new pair of handlers each time.
  if not frame.ptTipHooked then
    frame.ptTipHooked = true
    frame:HookScript("OnEnter", function(self)
      tipGeneration = tipGeneration + 1
      local generation = tipGeneration
      C_Timer.After(TIP_DELAY, function()
        if generation ~= tipGeneration then return end
        ShowTip(self)
      end)
    end)
    frame:HookScript("OnLeave", HideTip)
  end
  return frame
end

-- Tooltip copy, in one table rather than scattered through the builders.
--
-- Kept together so the explanations can be read as a set and stay consistent
-- about what things are called -- which is most of what makes help text useful.
local TIPS = {
  -- Rail: pages
  health      = "The rules that colour the health bar. Each rule says: when these debuffs are on the target, paint the bar this colour.",
  border      = "A second, independent stack of rules that draw a coloured border instead of filling the bar. Both can match at once.",
  pandemic    = "Flashes the bar as one of your debuffs nears the end of its refresh window, so you can see what needs reapplying without reading timers.",
  general     = "Settings that apply to every nameplate whether or not a rule matches: the plate's own border, how far tints sit from the bar edge, and what gets built.",
  icons       = "Which of your debuffs get their own icon drawn on the nameplate. Separate from colouring -- this draws icons, not colour.",
  iconLayout  = "Where the icon row sits, how big the icons are, and how they are spaced.",
  iconText    = "The cooldown timer and stack count drawn on each icon: font, size and position.",
  profiles    = "Saved sets of settings. Each character starts with its own, and a profile can be bound to a spec so it loads when you switch.",
  share       = "Turn a profile into a text string you can send someone, and turn one they send you back into a profile. Settings are saved per account, so a string is the only way a setup crosses to another one.",
  help        = "What the addon does, what it costs, and where to report a problem.",
  diagnostics = "What the addon has actually built on the nameplates in front of you right now. This is what to include in a bug report.",

  -- Rail: module switches
  switchHealth   = "Turns health colouring off entirely. Your rules are kept -- nothing is built on the plates while this is off.",
  switchBorder   = "Turns border colouring off entirely. Your border rules are kept.",
  switchIcons    = "Turns the aura icon module off entirely.",
  switchPandemic = "Turns the pandemic flash off. It only ever applies to single-debuff rules.",

  -- Rail: rule sections
  addRule       = "Creates a rule and opens it. Add one debuff or several -- a rule with two or more moves down into the combo half of this list on its own. The game will not let an addon read enemy auras, so a multi-debuff rule hands its conditions to nested aura containers and lets the game decide, which costs one extra frame per nameplate per debuff and nothing else.",

  -- Preview
  previewSection = "A simulated nameplate. It is an approximation -- your own nameplate addon may draw the bar differently.",
  testTarget     = "Paints your rules onto your real target's nameplate, ignoring whether the debuffs are actually present. Shows you the real colours at real size.",
  testAll        = "The same, on every nameplate on screen.",
  previewRule    = "Shows this rule in the preview above by ticking the debuffs it needs.",

  -- Rule editor
  ruleEnabled   = "Turns this one rule off without deleting it.",
  ruleDelete    = "Deletes this rule. There is no undo.",
  ruleDebuffs   = "The debuffs that must ALL be present for this rule to apply. Single rules take one; combo rules take two.",
  addDebuff     = "Pick a debuff from your Cooldown Manager, or type a name or spell ID. Many abilities apply an aura whose ID differs from the one you cast -- that is corrected for you.",
  ruleColor     = "The colour this rule paints. Alpha matters: a partly transparent tint lets the bar's own art show through.",
  fillStyle     = "Solid Overlay stretches a flat colour or a bar texture across the fill. Texture Overlay tiles a pattern over it at a fixed size instead.",
  fillTexture   = "The pattern tiled over the bar. Its tiles stay the same size as health drops, rather than squashing.",
  barTexture    = "A bar texture from LibSharedMedia, stretched across the fill and tinted by this rule's colour.",
  missingCover  = "Paints over the EMPTY part of the bar as well, hiding whatever your nameplate addon draws there.",
  missingColor  = "The colour used over missing health. Shared by every rule that covers it, not per rule.",
  appliedByClass = "Once a missing rule's debuff IS applied, paint the bar a flat colour chosen by the mob's tier -- boss, lieutenant, caster, rare, elite, normal -- instead of restoring the bar's own art.\n\nThat is the state you are in most of the time, so this is what keeps lieutenants and casters telling themselves apart while the reminder only shows on mobs you still owe. The trade is whatever the bar was encoding on its own, usually threat.\n\nTiers come from the client's own markers -- lieutenant flag, an actual mana pool for casters, and effective level against yours -- not from a list of creature IDs, which the game will not let an addon read inside a dungeon. So this keeps working in M+, where plain elite/rare classification would put nearly every mob in one bucket.\n\nShared by every missing rule. Occlusion mode only, and occlusion is no longer the default -- run |cffffff00/pt missingmode occlude|r to reach it. Displacement never covers the bar at all, so the mob's own colouring survives untouched and there is nothing here to colour.",
  showWhen      = "Present colours the bar while the debuffs are up. MISSING flips it: the rule stays lit until you apply them. Absence has no direct expression under 12.1's aura rules, so a missing rule is drawn unconditionally and then taken away once the debuff lands.\n\nOn a BORDER rule this needs |cffffff00/pt missingmode displace|r. Taking it away means one of two things -- covering it with a copy of what was underneath, or sliding it off screen -- and only the second works for a border, since the addon has no copy to make of whatever your nameplate addon drew there. In occlusion mode a missing border rule is simply not built, and |cffffff00/pt status|r says how many were skipped.",
  missingCombatOnly = "Holds the missing-rule wash off while the target is out of combat, so it only lights up on mobs you're actually fighting without the debuff on them -- not every untouched mob standing around before a pull. Off by default, since some missing rules are exactly for a pre-pull buff check.\n\nPer rule in the default displacement mode: each rule owns its own frame, so its setting is honoured on its own. Under |cffffff00/pt missingmode occlude|r it becomes all-or-nothing instead -- only one wash is ever lit there and which one depends on aura state the game will not let an addon read, so the gate engages only once every missing rule has it ticked.",
  showOnTarget  = "Untick to stop this rule colouring your current target's nameplate.",
  showOnFocus   = "Untick to stop this rule colouring your focus target's nameplate.",
  borderThick   = "How thick this rule's border is drawn, in pixels.",
  borderGrow    = "Inside keeps the border within the bar and never fights your nameplate addon's own border. Outside draws it beyond the bar, like a halo.",
  borderGap     = "Distance between the bar edge and the border, independent of thickness.",

  -- Global settings
  plateOutline  = "Redraws the nameplate's own black border on top of your colours. Without it, a rule that covers the fill paints over that border.",
  outlineSize   = "Match this to your nameplate addon's own border width.",
  outlineOffset = "Where the border sits relative to the bar's edge. Nameplate addons disagree about where that edge is, so if the border is hidden behind their art, push it outward a pixel or two. Your colors stop short of wherever this puts it.",
  outlineColor  = "Color and opacity of the redrawn border. Black at full opacity matches most nameplate addons.",
  outlineSides  = "Which edges to draw. Turn off the ones you do not want -- a line under the bar alone is a common look.",
  edgeInset     = "How far a tint stops short of the bar edge. Raise it if your colours are covering a border your nameplate addon draws.",
  perfGate      = "For profiles shared between characters. A rule you cannot trigger is still built on every nameplate. Off by default -- see the warning below it.",
  maxRigRepairs = "How many times a plate built during combat lockdown may be rebuilt once combat allows it. 1 is the original default -- see the warning below it.",

  -- Pandemic
  pandemicColor = "The colour washed over the bar during the refresh window.",
  pandemicPulse = "Untick for a steady wash instead of a pulse.",
  pandemicSpeed = "How fast the pulse cycles. Lower is faster.",

  -- Aura Icons: filters
  hideBliz      = "Stops Blizzard drawing its own aura row on nameplates, so this addon's icons are the only ones there. Turn it off if you want both.",
  textPreview   = "Preview only -- shows the timer and stack text on the sample icons. Does not change what is drawn on real plates.",
  iconAdd       = "Adds an aura to the tracked list. Only auras YOU applied are drawn, so tracking someone else's debuff will never show anything.",

  -- Aura Icons: position and size
  iconAnchor    = "Which point of the nameplate the icon row attaches to.",
  iconGrow      = "The direction icons fill as more of them appear.",
  iconOffsetX   = "Horizontal nudge from the anchor point, in pixels.",
  iconOffsetY   = "Vertical nudge from the anchor point, in pixels.",
  iconPerRow    = "How many icons before wrapping to a second row.",
  iconSize      = "Icon width and height in pixels.",
  iconSpacing   = "Gap between icons.",
  iconBorder    = "Thickness of the border drawn around each icon. Zero for none.",
  iconBorderCol = "Colour of that border.",

  -- Aura Icons: timer and stacks
  iconSwirl     = "The sweeping cooldown shading over the icon. Independent of the numeric timer below.",
  iconTimer     = "Draws the remaining time as text on the icon.",
  iconCount     = "Draws the stack count on the icon, for auras that stack.",
  fontFace      = "Font used for this text. The list comes from LibSharedMedia, so any font pack you have installed appears here.",
  fontSize      = "Text size in points.",
  fontOutline   = "An outline makes text readable against a bright bar. Thick outlines cost legibility at small sizes.",
  textAnchor    = "Which corner of the icon this text sits in.",
  textPrecision = "How much detail the timer shows -- whole seconds, or decimals as it runs out.",
  textOffsetX   = "Horizontal nudge from that corner.",
  textOffsetY   = "Vertical nudge from that corner.",

  -- Missing Debuff
  switchMissingIcons = "Turns the Missing Debuffs module off entirely. A different visual from the missing-debuff wash under Health/Border Coloring -- this one is an icon that gets pushed off the plate while the debuff is present, and returns once it drops.",
  missingList     = "Which debuffs get a reminder icon, in display order. Each one is its own independent icon: they can each have their own colour and their own combat-only setting.",
  missingLayout   = "Where the row sits, how big the icons are, and whether they collapse toward the anchor as debuffs land.",
  missingAdd      = "Adds a debuff to the tracked list. The icon shows while it is ABSENT and is pushed off the plate the moment you apply it.",
  missingUseIcon  = "Switch this entry between its spell icon and a flat colour.",
  missingColor    = "The flat colour used when this entry is set to Color instead of Icon.",
  missingCombatOnly = "Holds this one reminder off while you or the target are out of combat. Unlike the bar wash under Health/Border Coloring, each Missing Debuffs icon is independent, so this can be set per entry rather than for the whole list.",
  missingAnchor   = "Which point of the nameplate the row attaches to.",
  missingGrow     = "The direction icons fill as more of them are tracked.",
  missingOffsetX  = "Horizontal nudge from the anchor point, in pixels.",
  missingOffsetY  = "Vertical nudge from the anchor point, in pixels.",
  missingSize     = "Icon width and height in pixels.",
  missingSpacing  = "Gap between icons.",
  missingCollapse = "Icons past the first slide toward the anchor as the debuffs before them land, instead of leaving a gap. Turns off on its own past 4 tracked debuffs -- collapsing costs one extra secure container per debuff before it, and that adds up fast.",
  missingBorder     = "Thickness of the border drawn around each icon. Zero for none.",
  missingBorderCol  = "Colour of that border.",

  -- Profiles
  profileSelect = "The profile in use. Each character gets its own on first login rather than sharing a default.",
  profileNew    = "Creates an empty profile and switches to it.",
  profileCopy   = "Creates a new profile holding a copy of the current one's settings.",
  profileRename = "Renames the current profile. Anything bound to it follows the rename.",
  profileDelete = "Deletes the current profile. Characters using it fall back to their default.",
  profileBind   = "Loads this profile automatically whenever you switch to this specialisation.",

  -- Share
  shareWhich    = "Which profile to turn into a string. Defaults to the one you are using.",
  shareExport   = "Builds the string. Do this again after changing anything -- the string is a snapshot, not a link.",
  shareCopy     = "Selects the whole string so you can copy it with Ctrl+C.",
  shareBox      = "Paste a string here. Nothing is imported until you press Check, and nothing is written until you press Import.",
  shareCheck    = "Decodes the string and shows what is in it. Reads only -- it changes nothing.",
  shareName     = "The profile to create. Importing onto a name that already exists asks first.",
  shareCommit   = "Creates the profile and switches to it.",
  shareUnusable = "Rules naming a debuff this character cannot apply. They import intact and will work on a character that can -- but on this one they can never match.",

  -- Optional Tweaks
  tweakTooltips    = "Appends the numeric ID to game tooltips -- spells, auras, items and creatures. Nothing to do with nameplates; it is here because reading an aura's real ID is how you build a rule that matches.",
  switchTooltipIDs = "Turns the tooltip ID lines on or off. Nothing on your nameplates changes either way.",
  tipItem          = "Adds the item ID to item tooltips.",
  tipSpell         = "Adds the spell ID to spell and ability tooltips.",
  tipAura          = "Adds the aura ID to buff and debuff tooltips. This is the one that matters for building rules -- the aura an ability applies often has a different ID from the ability itself.",
  tipUnit          = "Adds the creature ID to unit tooltips. Blank on players, which have no creature ID.",

  -- Diagnostics
  diagPlates    = "Nameplates on screen right now.",
  diagRigged    = "How many of those this addon has built containers on. Friendly plates are skipped, so this is normally lower than the plate count.",
  diagNobar     = "Plates whose health bar could not be found. Non-zero here is a real problem -- it means a nameplate addon is drawing a bar this one cannot see.",
  diagSkipped   = "Plates skipped because you cannot attack them. Nothing you apply can land on a friendly unit, so there is nothing to build.",
  diagUnknown   = "Plates whose hostility no API would answer. These are deferred and retried rather than guessed at. Should settle to zero.",
  diagRefresh   = "Re-reads all of the above. These numbers change with every plate that appears, so they are taken on demand rather than on a timer.",
  diagCopy      = "Selects the whole report so you can copy it with Ctrl+C.",
}

-- The same, for a LABEL. A fontstring has no scripts, so this lays an
-- invisible mouse-enabled frame over its rect and tips that. SetAllPoints
-- against the fontstring, so the hit area follows a re-anchored rebuild.
--
-- The frame swallows clicks inside its rect -- harmless over label text, but
-- it is why this is not applied to every fontstring.
local function TipLabel(fontString, title, body, opts)
  if not fontString or not fontString.GetParent then return fontString end
  local hit = fontString.ptTipHit
  if not hit then
    hit = CreateFrame("Frame", nil, fontString:GetParent())
    hit:EnableMouse(true)
    hit:SetAllPoints(fontString)
    hit.ptTipOwner = fontString
    fontString.ptTipHit = hit
  end
  Tip(hit, title, body, opts)
  return fontString
end

-- Flat button, to match the rest of the panel. Blizzard's gold-bevelled
-- template reads far too heavy when a row has several of them.
local function Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, CTRL_H)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(b)

  local function Paint(bg, edge)
    b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
  end
  local NORMAL = { { 0.18, 0.18, 0.21, 1 }, { 0.36, 0.36, 0.42, 1 } }
  local HOVER  = { { 0.26, 0.28, 0.34, 1 }, { 0.50, 0.56, 0.70, 1 } }
  local OFF    = { { 0.13, 0.13, 0.15, 1 }, { 0.24, 0.24, 0.28, 1 } }

  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  b.label:SetText(text)
  StyleText(b.label, 12)

  Paint(NORMAL[1], NORMAL[2])
  b:SetScript("OnEnter", function(self)
    if self:IsEnabled() then Paint(HOVER[1], HOVER[2]) end
  end)
  b:SetScript("OnLeave", function(self)
    Paint(self:IsEnabled() and NORMAL[1] or OFF[1], self:IsEnabled() and NORMAL[2] or OFF[2])
  end)
  b:SetScript("OnClick", onClick)

  function b:SetText(value) self.label:SetText(value) end
  function b:Refresh()
    local on = self:IsEnabled()
    Paint(on and NORMAL[1] or OFF[1], on and NORMAL[2] or OFF[2])
    self.label:SetTextColor(on and 1 or 0.45, on and 1 or 0.45, on and 1 or 0.45)
  end

  hooksecurefunc(b, "Enable", function(self) self:Refresh() end)
  hooksecurefunc(b, "Disable", function(self) self:Refresh() end)
  return b
end

-- Flat checkbox: a small square that fills when on.
--
-- A switch is reserved for turning a MODULE on and off (see ToggleSwitch) --
-- power, not preference. If every option were a switch the distinction would
-- be gone.
local function Checkbox(parent, getValue, setValue)
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  c:SetSize(CTRL_BOX_W, CTRL_H)
  c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(c)
  c:SetBackdropColor(0.12, 0.12, 0.15, 1)

  c.fill = c:CreateTexture(nil, "OVERLAY")
  c.fill:SetColorTexture(RGBA(THEME.accent))
  PixelFill(c, c.fill, 3)

  local checked = false
  local function Paint(hover)
    c.fill:SetShown(checked)
    if checked then
      c:SetBackdropBorderColor(RGBA(THEME.accentBorder))
    else
      c:SetBackdropBorderColor(hover and 0.60 or 0.40, hover and 0.60 or 0.40, hover and 0.70 or 0.46, 1)
    end
  end

  c:SetScript("OnEnter", function() Paint(true) end)
  c:SetScript("OnLeave", function() Paint(false) end)
  c:SetScript("OnClick", function()
    -- Derived from the SOURCE, not the local `checked`. These widgets are
    -- pooled and re-pointed as the list is reordered, and any external change
    -- moves the real value without touching the local -- so flipping the local
    -- wrote the opposite of what was on screen. That was "toggles at random":
    -- a stale copy, not a race.
    local now = getValue() and true or false
    checked = not now
    Paint(true)
    setValue(checked)
    -- Re-read rather than trusting what we just wrote: a setter may refuse or
    -- adjust the value, and the box should show what is actually stored.
    c.Refresh()
  end)

  function c:GetChecked() return checked end
  function c:SetChecked(value)
    checked = value and true or false
    Paint(false)
  end
  c.Refresh = function()
    checked = getValue() and true or false
    Paint(false)
  end
  c.Refresh()
  return c
end

-- A sliding switch, used only for a module's on/off. Keeping it visually
-- distinct from a tick box is what lets the rail headings read as power
-- controls rather than one more setting.
local function ToggleSwitch(parent, getValue, setValue)
  local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
  t:SetSize(26, 13)
  t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(t)

  t.knob = t:CreateTexture(nil, "OVERLAY")
  t.knob:SetSize(9, 9)

  local accent = { 0.36, 0.78, 0.44 }
  local knobOn = { 0.55, 0.95, 0.62 }
  local hovered = false

  local function Paint()
    local on = getValue() and true or false
    t.knob:ClearAllPoints()
    -- The knob's SIDE carries the state as well as the colour does.
    t.knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    if on then
      t:SetBackdropColor(accent[1] * 0.34, accent[2] * 0.34, accent[3] * 0.34, 1)
      t:SetBackdropBorderColor(accent[1], accent[2], accent[3], hovered and 1 or 0.85)
      t.knob:SetColorTexture(knobOn[1], knobOn[2], knobOn[3], 1)
    else
      t:SetBackdropColor(0.12, 0.12, 0.15, 1)
      t:SetBackdropBorderColor(hovered and 0.52 or 0.34, hovered and 0.52 or 0.34,
        hovered and 0.60 or 0.40, 1)
      t.knob:SetColorTexture(0.48, 0.48, 0.54, 1)
    end
  end

  -- Per instance, so a switch can take the colour of whatever it governs.
  function t:SetAccent(colour)
    accent = colour
    knobOn = { math.min(1, colour[1] * 1.35), math.min(1, colour[2] * 1.35),
               math.min(1, colour[3] * 1.35) }
    Paint()
  end

  t.Refresh = Paint
  t:SetScript("OnEnter", function() hovered = true; Paint() end)
  t:SetScript("OnLeave", function() hovered = false; Paint() end)
  t:SetScript("OnClick", function()
    -- Same rule as Checkbox: read the source, write its opposite, then show
    -- whatever actually ended up stored.
    setValue(not (getValue() and true or false))
    Paint()
  end)
  Paint()
  return t
end

-- A small square delete control. Sized like the tick boxes and swatches it
-- sits beside, and red on hover, so "this removes something" is legible from
-- the shape rather than the caption.
local function CloseX(parent, onClick, size)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  size = size or CTRL_H
  b:SetSize(size, size)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(b)

  b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.glyph:SetPoint("CENTER", 0, 0)
  b.glyph:SetText("X")
  StyleText(b.glyph, 11)

  local function Paint(hovered)
    if hovered then
      b:SetBackdropColor(0.40, 0.12, 0.12, 1)
      b:SetBackdropBorderColor(0.95, 0.38, 0.38, 1)
      b.glyph:SetTextColor(1, 0.86, 0.86)
    else
      b:SetBackdropColor(0.16, 0.13, 0.14, 1)
      b:SetBackdropBorderColor(0.52, 0.28, 0.28, 1)
      b.glyph:SetTextColor(0.95, 0.45, 0.45)
    end
  end

  b:SetScript("OnEnter", function() Paint(true) end)
  b:SetScript("OnLeave", function() Paint(false) end)
  b:SetScript("OnClick", onClick)
  Paint(false)
  return b
end

-- Hand-built rather than Blizzard's ColorSwatchTemplate.
--
-- That template sizes its border by the TEMPLATE, not the frame, so SetSize
-- moved the hit box and left the visible square at Blizzard's size -- which is
-- why "the pickers and the checkboxes are still not the same size" kept coming
-- back however the frame was sized.
--
-- This is the Checkbox's geometry exactly, so CTRL_BOX_W/CTRL_H moves both.
local function ColorSwatch(parent, getColor, setColor)
  local s = CreateFrame("Button", nil, parent, "BackdropTemplate")
  s:SetSize(CTRL_BOX_W, CTRL_H)
  s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(s)
  s:SetBackdropColor(0.12, 0.12, 0.15, 1)

  -- Behind the colour, so a low alpha reads as translucency against a known
  -- mid grey instead of as a darker shade of the colour itself.
  s.backing = s:CreateTexture(nil, "ARTWORK")
  s.backing:SetColorTexture(0.30, 0.30, 0.33, 1)
  PixelFill(s, s.backing, 3)

  s.Color = s:CreateTexture(nil, "OVERLAY")
  PixelFill(s, s.Color, 3)

  local hovered = false
  local function refresh()
    local c = getColor()
    s.Color:SetColorTexture(c.r, c.g, c.b, c.a or 1)
    -- The tick box's own border treatment, hover included.
    s:SetBackdropBorderColor(hovered and 0.60 or 0.40, hovered and 0.60 or 0.40,
      hovered and 0.70 or 0.46, 1)
  end
  s:SetScript("OnEnter", function() hovered = true; refresh() end)
  s:SetScript("OnLeave", function() hovered = false; refresh() end)

  s:SetScript("OnClick", function()
    -- Ours, not Blizzard's. See ColorPicker.lua: opacity as a 0-100 number
    -- rather than an unlabelled slider, live writes through this swatch's own
    -- setter, and every fill on the page repainted as you drag -- including
    -- the pattern chips, which the game's picker has no way to know about.
    NS.OpenColorPicker(s, getColor(), function(r, g, b, a)
      setColor(r, g, b, a)
      refresh()
    end, { hasAlpha = s.hasAlpha ~= false })
  end)
  s.Refresh = refresh
  -- Repainted while another swatch is being dragged: a rule's colour appears
  -- in several places at once, and only one of them is the control under the
  -- cursor.
  NS.RegisterLiveSwatch(refresh)
  refresh()
  return s
end


-- Flat dropdown matching the rest of the panel. `entries` may be a table or a
-- function returning one (spell pickers rebuild theirs each time they open).
-- An entry is { text, value } plus optional icon = texturePath and
-- isTitle = true for a non-clickable header.
local ROW_HEIGHT = 20
local MAX_VISIBLE_ROWS = 14
local SCROLL_WIDTH = 8
-- Small enough to stay proportional on a long list, big enough to still be
-- grabbable when the list is hundreds of entries (a user with several media
-- packs installed).
local MIN_THUMB_HEIGHT = 20
local openMenu

local function CloseOpenMenu()
  if openMenu then
    openMenu:Hide()
    openMenu = nil
    -- A row can still be hovered when the list closes, and OnLeave does not
    -- fire for a frame hidden out from under the cursor.
    if GameTooltip then GameTooltip:Hide() end
  end
end

-- `opts.multi` turns this into a multi-select: rows toggle instead of
-- choosing, the list stays open, and the closed control shows a summary
-- rather than one entry. `opts.isChecked(value)`, `opts.onToggle(value)` and
-- `opts.summary()` are then required; getValue/setValue are unused.
--
-- One widget rather than a second one: a menu that scrolls, tooltips, the
-- click-outside blocker and the pixel border are all here already, and a
-- parallel implementation is a parallel set of bugs.
local function Dropdown(parent, width, entries, getValue, setValue, opts)
  local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
  d:SetSize(width, CTRL_H)
  d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(d)
  d:SetBackdropColor(0.14, 0.14, 0.17, 1)
  d:SetBackdropBorderColor(0.36, 0.36, 0.42, 1)

  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(14, 14)
  d.icon:SetPoint("LEFT", 6, 0)
  d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.icon:Hide()

  d.label = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.label:SetPoint("LEFT", 8, 0)
  d.label:SetPoint("RIGHT", -18, 0)
  d.label:SetJustifyH("LEFT")
  d.label:SetWordWrap(false)
  StyleText(d.label, 12)

  d.arrow = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.arrow:SetPoint("RIGHT", -6, -1)
  d.arrow:SetText("v")
  d.arrow:SetTextColor(0.65, 0.65, 0.7)
  StyleText(d.arrow, 10)

  d:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.50, 0.56, 0.70, 1) end)
  d:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.36, 0.36, 0.42, 1) end)

  -- The list lives on UIParent so it is never clipped by a scroll frame.
  local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(menu)
  menu:SetBackdropColor(0.10, 0.10, 0.12, 0.98)
  menu:SetBackdropBorderColor(0.42, 0.42, 0.50, 1)
  menu:EnableMouse(true)
  menu:EnableMouseWheel(true)
  menu:Hide()
  menu.rows = {}
  menu.offset = 0
  d.menu = menu

  -- Scrollbar. The wheel alone was fine while lists were short, but the LSM
  -- texture lists run to dozens and a wheel gives no sense of position.
  --
  -- Hand-built rather than a Slider: the thumb has to RESIZE to show what
  -- fraction is visible, which a Slider's fixed thumb cannot do.
  local track = CreateFrame("Frame", nil, menu)
  track:SetWidth(SCROLL_WIDTH)
  track:SetPoint("TOPRIGHT", -3, -3)
  track:SetPoint("BOTTOMRIGHT", -3, 3)
  track.bg = track:CreateTexture(nil, "BACKGROUND")
  track.bg:SetAllPoints()
  track.bg:SetColorTexture(0.18, 0.18, 0.22, 0.9)
  track:Hide()
  menu.track = track

  local thumb = CreateFrame("Button", nil, track)
  thumb:SetPoint("LEFT")
  thumb:SetPoint("RIGHT")
  thumb.bg = thumb:CreateTexture(nil, "ARTWORK")
  thumb.bg:SetAllPoints()
  thumb.bg:SetColorTexture(0.42, 0.42, 0.50, 1)
  menu.thumb = thumb

  -- Set by RenderRows, read by the drag handler: how far the thumb may
  -- travel, and how many rows that travel corresponds to.
  menu.maxOffset = 0
  menu.travel = 0

  local function OffsetFromThumbTop(top)
    if menu.travel <= 0 then return 0 end
    local fraction = math.max(0, math.min(1, top / menu.travel))
    return math.floor(fraction * menu.maxOffset + 0.5)
  end

  thumb:SetScript("OnMouseDown", function(self)
    local _, cursorY = GetCursorPosition()
    self.dragScale = menu:GetEffectiveScale()
    self.dragCursor = cursorY / self.dragScale
    -- Distance from the track's top to the thumb's top, in the same units.
    self.dragTop = track:GetTop() - self:GetTop()
    self.dragging = true
  end)

  local function StopDrag(self)
    self.dragging = false
  end
  thumb:SetScript("OnMouseUp", StopDrag)
  -- The cursor can leave the thumb mid-drag (moving faster than the thumb
  -- follows, or past the end of the track), and OnMouseUp then fires on
  -- whatever is under it instead -- leaving the thumb stuck to the cursor.
  thumb:SetScript("OnHide", StopDrag)

  thumb:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    if not IsMouseButtonDown("LeftButton") then
      self.dragging = false
      return
    end
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / (self.dragScale ~= 0 and self.dragScale or 1)
    -- Cursor Y grows upward, list offset grows downward.
    local moved = self.dragCursor - cursorY
    local offset = OffsetFromThumbTop(self.dragTop + moved)
    if offset ~= menu.offset then
      menu.offset = offset
      menu.Render()
    end
  end)

  -- Click the track above or below the thumb to page, the way any scrollbar
  -- does. Handled on the track itself, so the thumb keeps its own drag.
  track:EnableMouse(true)
  track:SetScript("OnMouseDown", function(self)
    if menu.maxOffset <= 0 then return end
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / menu:GetEffectiveScale()
    local page = MAX_VISIBLE_ROWS - 1
    if cursorY > thumb:GetTop() then
      menu.offset = math.max(0, menu.offset - page)
    elseif cursorY < thumb:GetBottom() then
      menu.offset = math.min(menu.maxOffset, menu.offset + page)
    else
      return
    end
    menu.Render()
  end)

  -- Catches a click anywhere else and dismisses the list.
  local blocker = CreateFrame("Button", nil, UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("FULLSCREEN")
  blocker:Hide()
  blocker:SetScript("OnClick", CloseOpenMenu)
  menu.blocker = blocker
  menu:SetScript("OnHide", function() blocker:Hide() end)

  local function CurrentEntries()
    return type(entries) == "function" and entries() or entries
  end

  local function RenderRows()
    local list = CurrentEntries()
    local visible = math.min(#list, MAX_VISIBLE_ROWS)

    -- Scrollbar geometry, before the rows: whether it is showing decides how
    -- much width the rows have.
    local maxOffset = math.max(0, #list - MAX_VISIBLE_ROWS)
    menu.maxOffset = maxOffset
    menu.offset = math.max(0, math.min(maxOffset, menu.offset))
    local needScroll = maxOffset > 0
    track:SetShown(needScroll)
    if needScroll then
      local trackHeight = track:GetHeight()
      -- Thumb length is the visible fraction of the list, which is what makes
      -- a scrollbar readable as "how much is there" rather than just "where".
      local thumbHeight = math.max(MIN_THUMB_HEIGHT, trackHeight * visible / #list)
      thumbHeight = math.min(thumbHeight, trackHeight)
      thumb:SetHeight(thumbHeight)
      menu.travel = trackHeight - thumbHeight
      thumb:ClearAllPoints()
      thumb:SetPoint("LEFT")
      thumb:SetPoint("RIGHT")
      thumb:SetPoint("TOP", track, "TOP", 0, -(menu.offset / maxOffset) * menu.travel)
    else
      menu.travel = 0
    end

    for index = 1, visible do
      local entry = list[index + menu.offset]
      local row = menu.rows[index]
      if not row then
        row = CreateFrame("Button", nil, menu)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", 3, 0)
        row:SetPoint("RIGHT", -3, 0)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(0.35, 0.45, 0.75, 0.55)
        row.highlight:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 5, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        StyleText(row.text, 12)
        row:SetScript("OnEnter", function(self)
          if self.isTitle then return end
          self.highlight:Show()
          -- Anchored to the row rather than the cursor: the menu is already a
          -- tall list and a cursor-following tooltip covers the entries below
          -- the one being read.
          if type(self.value) == "number" and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.value)
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
          end
        end)
        row:SetScript("OnLeave", function(self)
          self.highlight:Hide()
          if GameTooltip then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
          if self.isTitle then return end
          if opts and opts.multi then
            -- Stays open: picking three zones out of eleven through a menu
            -- that shuts on every click is the thing multi-select is for.
            opts.onToggle(self.value)
            d.Refresh()
            menu.Render()
            return
          end
          CloseOpenMenu()
          setValue(self.value)
          d.Refresh()
        end)
        menu.rows[index] = row
      end
      row:SetPoint("TOPLEFT", 3, -3 - (index - 1) * ROW_HEIGHT)
      -- Re-set every render: the same pooled row is reused by lists that do
      -- and do not need a scrollbar, and text running under the bar is the
      -- one thing that would make this look bolted on.
      row:SetPoint("RIGHT", needScroll and -(SCROLL_WIDTH + 5) or -3, 0)

      if entry then
        row.value = entry.value
        row.isTitle = entry.isTitle
        row.text:SetText(entry.text)
        local picked
        if opts and opts.multi then
          picked = opts.isChecked(entry.value)
          -- A tick in the text, not a texture: the row is pooled between a
          -- multi-select and an ordinary list, and a stray checkbox left
          -- showing on a single-choice menu is worse than a character.
          row.text:SetText((picked and "|cff77dd77x|r  " or "     ") .. entry.text)
        else
          picked = getValue() == entry.value
        end
        if entry.isTitle then
          row.text:SetTextColor(RGBA(THEME.headerText))
        elseif picked then
          row.text:SetTextColor(0.45, 0.95, 0.55)
        else
          row.text:SetTextColor(1, 1, 1)
        end
        if entry.icon then
          row.icon:SetTexture(entry.icon)
          row.icon:Show()
          row.text:SetPoint("LEFT", 24, 0)
        else
          row.icon:Hide()
          row.text:SetPoint("LEFT", entry.isTitle and 8 or 12, 0)
        end
        row:Show()
      else
        row:Hide()
      end
    end
    for index = visible + 1, #menu.rows do menu.rows[index]:Hide() end
  end

  -- The scrollbar's drag and paging handlers are defined above RenderRows
  -- (they hang off the frames created there) and need to redraw, so hand them
  -- the real function now that it exists.
  menu.Render = RenderRows

  menu:SetScript("OnMouseWheel", function(self, delta)
    local list = CurrentEntries()
    local maxOffset = math.max(0, #list - MAX_VISIBLE_ROWS)
    self.offset = math.max(0, math.min(maxOffset, self.offset - delta))
    RenderRows()
  end)

  d:SetScript("OnClick", function(self)
    if openMenu == menu then
      CloseOpenMenu()
      return
    end
    CloseOpenMenu()
    local list = CurrentEntries()
    menu.offset = 0
    menu:SetWidth(math.max(width, 140))
    menu:SetHeight(math.min(#list, MAX_VISIBLE_ROWS) * ROW_HEIGHT + 6)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    RenderRows()
    blocker:Show()
    menu:Show()
    openMenu = menu
  end)

  d.Refresh = function()
    if opts and opts.multi then
      d.icon:Hide()
      d.label:SetPoint("LEFT", 8, 0)
      d.label:SetText(opts.summary())
      if menu:IsShown() then RenderRows() end
      return
    end
    local current = getValue()
    local shown, icon
    for _, entry in ipairs(CurrentEntries()) do
      if not entry.isTitle and entry.value == current then
        shown, icon = entry.text, entry.icon
        break
      end
    end
    d.label:SetText(shown or tostring(current or ""))
    if icon then
      d.icon:SetTexture(icon)
      d.icon:Show()
      d.label:SetPoint("LEFT", 24, 0)
    else
      d.icon:Hide()
      d.label:SetPoint("LEFT", 8, 0)
    end
    if menu:IsShown() then RenderRows() end
  end
  d.Refresh()
  return d
end

-- A number that reads as plain text until you click it, then becomes an edit
-- box, then goes back to text on Enter. Avoids a row of permanent input
-- fields, which is what made the panel feel like a form.
local function EditableNumber(parent, width, getValue, setValue, onCommit)
  local holder = CreateFrame("Button", nil, parent)
  holder:SetSize(width, CTRL_H)

  holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  holder.text:SetAllPoints()
  holder.text:SetJustifyH("CENTER")
  StyleText(holder.text, 12)

  holder.hover = holder:CreateTexture(nil, "BACKGROUND")
  holder.hover:SetAllPoints()
  holder.hover:SetColorTexture(1, 1, 1, 0.08)
  holder.hover:Hide()

  holder.edit = CreateFrame("EditBox", nil, holder)
  holder.edit:SetAllPoints()
  holder.edit:SetAutoFocus(true)
  holder.edit:SetJustifyH("CENTER")
  holder.edit:SetFontObject("GameFontHighlightSmall")
  StyleText(holder.edit, 12)
  holder.edit:Hide()

  local function ShowText()
    holder.edit:Hide()
    holder.text:SetText(tostring(math.floor(getValue() + 0.5)))
    holder.text:Show()
  end

  holder:SetScript("OnEnter", function() holder.hover:Show() end)
  holder:SetScript("OnLeave", function() holder.hover:Hide() end)
  holder:SetScript("OnClick", function()
    holder.text:Hide()
    holder.edit:SetText(tostring(math.floor(getValue() + 0.5)))
    holder.edit:HighlightText()
    holder.edit:Show()
    holder.edit:SetFocus()
  end)

  holder.edit:SetScript("OnEnterPressed", function(self)
    local value = tonumber(self:GetText())
    self:ClearFocus()
    if value then
      setValue(value)
      if onCommit then onCommit(value) end
    end
    ShowText()
  end)
  holder.edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    ShowText()
  end)
  holder.edit:SetScript("OnEditFocusLost", ShowText)

  holder.Refresh = ShowText
  ShowText()
  return holder
end

-- Custom slider: a thin track with a small thumb and a click-to-edit value.
-- Blizzard's stepper template wastes width on arrows and reads heavy at this
-- density.
local function Slider(parent, width, min, max, steps, getValue, setValue)
  local step = (steps and steps > 0) and ((max - min) / steps) or 1

  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width + 46, 18)

  -- Anchored to BOTH edges of the holder, less the room the number needs,
  -- rather than given a fixed width. The holder is laid out by Flex and can
  -- end up narrower than it asked for; a track sized once at creation would
  -- keep its original length and run out past the block.
  local track = CreateFrame("Frame", nil, holder)
  track:SetPoint("LEFT", 0, 0)
  track:SetPoint("RIGHT", holder, "RIGHT", -46, 0)
  track:SetHeight(14)
  track:EnableMouse(true)
  -- The mouse lives on the TRACK, not on the holder, so a caller that wants
  -- to switch this slider off has to be able to reach it. See EditorBlock's
  -- SetOff: disabling the holder alone leaves the groove draggable.
  holder.track = track

  local groove = track:CreateTexture(nil, "ARTWORK")
  groove:SetPoint("LEFT")
  groove:SetPoint("RIGHT")
  groove:SetHeight(3)
  groove:SetColorTexture(0.28, 0.28, 0.32, 1)

  local fill = track:CreateTexture(nil, "OVERLAY")
  fill:SetPoint("LEFT", groove, "LEFT")
  fill:SetHeight(3)
  fill:SetColorTexture(RGBA(THEME.accent))

  local thumb = track:CreateTexture(nil, "OVERLAY", nil, 2)
  thumb:SetSize(10, 14)
  thumb:SetColorTexture(0.80, 0.82, 0.88, 1)

  local value = EditableNumber(holder, 40, getValue, function(v)
    setValue(math.max(min, math.min(max, v)))
  end, function() holder.Refresh() end)
  value:SetPoint("LEFT", track, "RIGHT", 6, 0)

  -- Read from the track, never from the `width` it was built with: those are
  -- the same number only until something resizes this.
  local function TrackWidth()
    local w = track:GetWidth()
    if not w or w < 1 then w = width end
    return w
  end

  local function Position()
    local current = math.max(min, math.min(max, getValue() or min))
    local pct = (max > min) and ((current - min) / (max - min)) or 0
    local w = TrackWidth()
    fill:SetWidth(math.max(1, w * pct))
    thumb:ClearAllPoints()
    thumb:SetPoint("CENTER", groove, "LEFT", w * pct, 0)
  end

  -- Flex sizes this frame AFTER the page has told the slider to refresh, so
  -- the fill and thumb computed a moment ago were measured against the old
  -- width. Re-run when the size actually lands.
  holder:HookScript("OnSizeChanged", function() Position() end)

  local function SetFromCursor()
    local cursorX = GetCursorPosition() / track:GetEffectiveScale()
    local left = track:GetLeft()
    if not left then return end
    local pct = math.max(0, math.min(1, (cursorX - left) / TrackWidth()))
    local raw = min + pct * (max - min)
    local snapped = min + math.floor((raw - min) / step + 0.5) * step
    snapped = math.max(min, math.min(max, snapped))
    -- Only when the step actually changes. OnUpdate runs every frame while
    -- the thumb is held, and each setValue reaches through to the live
    -- nameplates; re-applying the same number sixty times a second was most
    -- of what made dragging feel heavy.
    if math.abs((getValue() or min) - snapped) < step * 0.001 then return end
    setValue(snapped)
    Position()
    value.Refresh()
  end

  track:SetScript("OnMouseDown", function(self)
    self.dragging = true
    SetFromCursor()
  end)
  track:SetScript("OnMouseUp", function(self) self.dragging = false end)
  track:SetScript("OnHide", function(self) self.dragging = false end)
  track:SetScript("OnUpdate", function(self)
    if self.dragging then SetFromCursor() end
  end)

  holder.Refresh = function()
    Position()
    value.Refresh()
  end
  holder.Refresh()
  return holder
end

-- Spell picker built on the same dropdown: the list is regenerated each open
-- so already-tracked spells stay marked as you add them.
local function AddSpellDropdown(parent, width, defaultText, isTracked, onPick)
  -- Optional, because "mark what is already on this thing" is a question some
  -- callers have no answer to -- and a nil here used to be an error thrown
  -- while building the list, which reads as the whole page failing.
  isTracked = isTracked or function() return false end
  local function BuildEntries()
    local list = { { text = defaultText, value = nil, isTitle = true } }

    -- Two sources, one list.
    --
    -- The Cooldown Manager is Blizzard's own curated set for your spec: right
    -- when it has an entry, and silent about procs, trinkets, off-spec and
    -- anything a patch added. What this addon has SEEN you apply cannot be
    -- wrong about the same question, and covers all of it -- but starts empty
    -- on a fresh install.
    --
    -- So both, headed, deduped, with the curated one first because it is there
    -- before you have fought anything.
    local seen = {}
    local function Add(spellID)
      if not spellID or seen[spellID] then return false end
      local name = NS.SpellName(spellID)
      if not name then return false end
      seen[spellID] = true
      table.insert(list, {
        text = ("%s%s  |cff808080%d|r"):format(
          isTracked(spellID) and "|cff55dd55•|r " or "", name, spellID),
        value = spellID,
        icon = NS.SpellIcon(spellID),
      })
      return true
    end

    local onTargets = NS.GetCooldownManagerSpells()
    if #onTargets > 0 then
      table.insert(list, { text = "|cff808080From your Cooldown Manager|r", isTitle = true })
      for _, item in ipairs(onTargets) do Add(item.spellID) end
    end

    local learned = NS.LearnedDebuffs and NS.LearnedDebuffs() or {}
    local header = false
    for _, item in ipairs(learned) do
      if not seen[item.spellID] then
        if not header then
          header = true
          table.insert(list, { text = "|cff808080Debuffs you have applied|r", isTitle = true })
        end
        Add(item.spellID)
      end
    end

    if #list == 1 then
      table.insert(list, {
        text = "Nothing to offer yet — fight something, or use the ID box",
        isTitle = true,
      })
    end
    return list
  end

  local d = Dropdown(parent, width, BuildEntries,
    function() return nil end,           -- never shows a selection
    function(spellID) if spellID then onPick(spellID) end end)
  d.label:SetText(defaultText)
  -- Picking is an action, not a setting, so the face always reads as a prompt.
  d.Refresh = function() d.label:SetText(defaultText); d.icon:Hide(); d.label:SetPoint("LEFT", 8, 0) end
  d.Refresh()
  return d
end

-- Accepts a spell ID or a NAME. The ID that has to go in is often one the
-- Cooldown Manager never offers (Rend's debuff is 388539, not the 772 listed),
-- and a name is easier to be right about.
--
-- What is typed is not necessarily what is stored: NS.ResolveAuraInput checks
-- it against the auras on your target and substitutes the aura's own ID,
-- reporting what it did.
--
-- Shared by the DROPDOWNS too. The Cooldown Manager lists abilities, so
-- picking Moonfire from the list built rules that could never match while
-- typing the same name worked.
local function ResolveAndReport(input)
  local spellID, note, changed = NS.ResolveAuraInput(input)
  if spellID and changed then
    -- Easy to miss in a busy chat frame, so it gets its own line.
  end
  return spellID
end

local function IDBox(parent, onAdd, width)
  -- Built here rather than from InputBoxTemplate: that template brings
  -- Blizzard's beveled gold border and its own insets, which made the one
  -- text entry in this window the only control that did not match the flat
  -- widgets around it.
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(width or 110, CTRL_H)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(frame)
  frame:SetBackdropColor(0.10, 0.10, 0.13, 1)
  frame:SetBackdropBorderColor(0.36, 0.36, 0.42, 1)

  local b = CreateFrame("EditBox", nil, frame)
  b:SetPoint("TOPLEFT", 5, 0)
  b:SetPoint("BOTTOMRIGHT", -5, 0)
  b:SetAutoFocus(false)
  b:SetFontObject("GameFontHighlightSmall")
  StyleText(b, 12)

  -- The border answers focus, so it is obvious which field is taking input.
  b:HookScript("OnEditFocusGained", function()
    frame:SetBackdropBorderColor(RGBA(THEME.accentBorder))
  end)
  b:HookScript("OnEditFocusLost", function()
    frame:SetBackdropBorderColor(0.36, 0.36, 0.42, 1)
  end)

  -- Callers position and show/hide the widget, so hand them the frame while
  -- the edit box keeps its own API.
  b.frame = frame
  frame.editBox = b
  frame.SetTextValue = function(_, value) b:SetText(value or "") end
  -- Passes the RAW text through: resolution belongs to the add handler, so
  -- every entry point resolves exactly once and in the same way.
  b:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    self:SetText("")
    self:ClearFocus()
    onAdd(text)
  end)

  -- The FRAME is what callers anchor and show; every current caller only
  -- positions it and toggles it, so nothing needs the edit box directly --
  -- and it is reachable as .editBox if that ever changes.
  return frame
end

-------------------------------------------------------------------------------
-- Collapsible section
-------------------------------------------------------------------------------

-- palette is optional; omitted means the standard grey section. Passing one
-- recolours the same structure, which is how the preview panel is built --
-- one widget, two skins, instead of two implementations that have to be kept
-- looking alike by hand.
local function CollapsibleSection(parent, key, title, subtitle, palette)
  palette = palette or {}
  local paneBG     = palette.bg          or THEME.panelBG
  local paneBorder = palette.border      or THEME.panelBorder
  local headBG     = palette.headerBG    or THEME.headerBG
  local headHover  = palette.headerHover or THEME.headerBGHover
  local titleTint  = palette.title       or THEME.headerText

  local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  s.key = key
  s.headBG, s.headHover = headBG, headHover
  s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(s)
  s:SetBackdropColor(RGBA(paneBG))
  s:SetBackdropBorderColor(RGBA(paneBorder))

  s.header = CreateFrame("Button", nil, s)
  s.header:SetPoint("TOPLEFT", 1, -1)
  s.header:SetPoint("TOPRIGHT", -1, -1)
  s.header:SetHeight(28)

  s.headerBG = s.header:CreateTexture(nil, "BACKGROUND")
  s.headerBG:SetAllPoints()
  s.headerBG:SetColorTexture(RGBA(headBG))

  -- The same triangle the rail uses, so "this opens" looks identical
  -- wherever it appears. Was a "+"/"-" text glyph.
  s.arrow = s.header:CreateTexture(nil, "OVERLAY")
  s.arrow:SetSize(10, 10)
  s.arrow:SetPoint("LEFT", 10, 0)
  s.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  s.arrow:SetVertexColor(0.72, 0.72, 0.78, 1)

  s.title = Label(s.header, title, "GameFontNormal")
  s.title:SetPoint("LEFT", 28, 0)

  if subtitle then
    s.subtitle = Dim(s.header, subtitle)
    s.subtitle:SetPoint("LEFT", s.title, "RIGHT", 12, 0)
  end

  -- Explanatory prose belongs here, not in the section.
  --
  -- Every list on these pages carried a paragraph under it saying what the
  -- list was for. Read once, then permanent -- it cost a band of vertical
  -- space on every page, on every visit, forever. As a header button the text
  -- is one hover away and takes no room at all.
  --
  -- Created for every section, shown only for one that was given text: an
  -- empty "?" is a promise of help that is not there.
  s.help = CreateFrame("Button", nil, s.header, "BackdropTemplate")
  s.help:SetSize(20, 18)
  s.help:SetPoint("RIGHT", -8, 0)
  s.help:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(s.help)
  s.help:SetBackdropColor(0.16, 0.16, 0.20, 1)
  s.help:SetBackdropBorderColor(0.36, 0.36, 0.42, 1)
  s.help.label = s.help:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.help.label:SetPoint("CENTER")
  s.help.label:SetText("?")
  StyleText(s.help.label, 11)
  s.help.label:SetTextColor(0.72, 0.72, 0.78)
  s.help:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(0.50, 0.56, 0.70, 1)
    self.label:SetTextColor(1, 0.82, 0.1)
  end)
  s.help:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(0.36, 0.36, 0.42, 1)
    self.label:SetTextColor(0.72, 0.72, 0.78)
  end)
  s.help:Hide()

  -- Called by whoever builds the section. Takes the same (title, body) a
  -- tooltip anywhere else does, so the writing is not a special case.
  function s:SetHelp(title, body)
    Tip(self.help, title or self.title:GetText(), body)
    self.help:SetShown(body ~= nil)
  end

  s.content = CreateFrame("Frame", nil, s)
  s.content:SetPoint("TOPLEFT", 0, -SECTION_HEAD_H)
  s.content:SetPoint("TOPRIGHT", 0, -SECTION_HEAD_H)
  -- A backstop, not the fix: a section whose height is wrong should be
  -- corrected, but until it is, its contents must not draw over the section
  -- below. Dropdown menus are parented to UIParent, so they are not clipped.
  if s.content.SetClipsChildren then pcall(s.content.SetClipsChildren, s.content, true) end

  s.open = NS.db.uiSections[key] ~= false

  function s:Resize(height)
    self.contentHeight = height
    self.content:SetHeight(math.max(1, height))
    self:SetHeight(self.open and (SECTION_HEAD_H + height + SECTION_PAD) or SECTION_HEAD_H)
    -- Anything anchored below this section has to move when it changes size.
    -- Pushing that out as a notification rather than leaving each page to
    -- re-run its own layout is the difference between "one page forgot" and
    -- "it cannot be forgotten".
    if self.onResize then self.onResize(self) end
  end

  -- Points right when closed, quarter-turn clockwise when open. SetRotation
  -- takes counter-clockwise radians, hence the negative; pcall'd so a client
  -- without rotation shows a right-pointing triangle rather than erroring.
  local function PaintArrow(open)
    pcall(s.arrow.SetRotation, s.arrow, open and (-math.pi / 2) or 0)
  end

  function s:SetOpen(open)
    self.open = open
    NS.db.uiSections[self.key] = open
    PaintArrow(open)
    self.content:SetShown(open)
    self:Resize(self.contentHeight or 0)
    -- Distinct from onResize: that one fires on any size change, this one only
    -- on the open/closed transition. The rule editor uses it to switch its
    -- preview back on -- opening the preview is a request to SEE something.
    if self.onOpen then self.onOpen(self, open) end
  end

  s.header:SetScript("OnClick", function()
    s:SetOpen(not s.open)
    NS.Options_RebuildAll()
  end)
  s.header:SetScript("OnEnter", function() s.headerBG:SetColorTexture(RGBA(s.headHover)) end)
  s.header:SetScript("OnLeave", function() s.headerBG:SetColorTexture(RGBA(s.headBG)) end)

  PaintArrow(s.open)
  s.content:SetShown(s.open)
  return s
end

-- startY lets a page keep a fixed strip above its sections -- the rule editor
-- puts the rule's name, switch and delete control there. Defaults to the usual
-- top inset, so every existing caller is unaffected.
local function LayoutSections(body, sections, startY)
  local y = startY or -SECTION_INSET
  for _, section in ipairs(sections) do
    section:ClearAllPoints()
    section:SetPoint("TOPLEFT", SECTION_INSET, y)
    section:SetPoint("TOPRIGHT", -SECTION_INSET, y)
    y = y - section:GetHeight() - SECTION_GAP
  end
  body:SetHeight(-y + 12)
  -- Content height just changed, so the thumb size/position are stale.
  if body.scrollBar then body.scrollBar:Update() end
end

-- A thin track-and-thumb bar to replace Blizzard's UIPanelScrollFrameTemplate
-- scrollbar, matching the rest of the hand-drawn widgets. One instance per
-- scroll frame; `scrollFrame:GetScrollChild()` is read fresh on every Update
-- so it does not need telling when the body's content height changes, only
-- a nudge to re-check (LayoutSections does that above).
local function BuildScrollBar(scrollFrame)
  local bar = CreateFrame("Frame", nil, scrollFrame:GetParent())
  bar:SetWidth(THEME.scrollBarWidth)
  bar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 8, 0)

  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetAllPoints()
  bar.track:SetColorTexture(RGBA(THEME.scrollTrack))

  bar.thumb = CreateFrame("Button", nil, bar, "BackdropTemplate")
  bar.thumb:SetPoint("TOP")
  bar.thumb:SetWidth(THEME.scrollBarWidth)
  bar.thumb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  bar.thumb:SetBackdropColor(RGBA(THEME.scrollThumb))
  bar.thumb:SetScript("OnEnter", function(self) self:SetBackdropColor(RGBA(THEME.scrollThumbHover)) end)
  bar.thumb:SetScript("OnLeave", function(self) self:SetBackdropColor(RGBA(THEME.scrollThumb)) end)

  local function Range()
    local child = scrollFrame:GetScrollChild()
    if not child then return 0, 0 end
    return scrollFrame:GetHeight(), child:GetHeight()
  end

  function bar:Update()
    local visible, total = Range()
    if total <= visible or total <= 0 then
      bar:Hide()
      scrollFrame:SetVerticalScroll(0)
      return
    end
    bar:Show()
    local trackH = bar:GetHeight()
    local thumbH = math.max(20, trackH * (visible / total))
    bar.thumb:SetHeight(thumbH)
    local maxScroll = total - visible
    local pct = maxScroll > 0 and (scrollFrame:GetVerticalScroll() / maxScroll) or 0
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOP", bar, "TOP", 0, -(trackH - thumbH) * pct)
  end

  local dragging, dragStartCursorY, dragStartScroll = false, 0, 0

  bar.thumb:SetScript("OnMouseDown", function()
    dragging = true
    local _, y = GetCursorPosition()
    dragStartCursorY = y
    dragStartScroll = scrollFrame:GetVerticalScroll()
  end)
  bar.thumb:SetScript("OnMouseUp", function() dragging = false end)
  bar.thumb:SetScript("OnHide", function() dragging = false end)
  bar.thumb:SetScript("OnUpdate", function()
    if not dragging then return end
    local visible, total = Range()
    if total <= visible then return end
    local trackH, thumbH = bar:GetHeight(), bar.thumb:GetHeight()
    local travel = trackH - thumbH
    if travel <= 0 then return end
    local _, y = GetCursorPosition()
    local dy = (dragStartCursorY - y) / bar:GetEffectiveScale()
    local maxScroll = total - visible
    scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, dragStartScroll + dy * (maxScroll / travel))))
    bar:Update()
  end)

  -- Clicking the track (not the thumb) jumps a page toward the click.
  bar:SetScript("OnMouseDown", function()
    if bar.thumb:IsMouseOver() then return end
    local visible, total = Range()
    if total <= visible then return end
    local _, cursorY = GetCursorPosition()
    local y = cursorY / bar:GetEffectiveScale()
    local clickPct = (bar:GetTop() - y) / bar:GetHeight()
    local maxScroll = total - visible
    scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, clickPct * maxScroll)))
    bar:Update()
  end)

  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local visible, total = Range()
    if total <= visible then return end
    local maxScroll = total - visible
    local current = self:GetVerticalScroll()
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * THEME.scrollWheelStep)))
    bar:Update()
  end)

  scrollFrame:SetScript("OnSizeChanged", function() bar:Update() end)

  return bar
end

-- Turns the open rule's preview on: its debuffs ARE the preview state.
--
-- Called when a rule is opened and whenever a test button is pressed -- you
-- pressed test to look at something, and a rule page with its preview off is
-- the one state where that shows nothing.
local function EnsureRulePreview()
  if not expandedRule then return end
  -- Inverted for a missing rule, for the same reason: what shows it is the
  -- debuff NOT being there.
  if expandedRule.showWhenMissing then
    for _, condition in ipairs(expandedRule.conditions or {}) do
      preview.active[condition.spellID] = nil
    end
    return
  end
  for _, condition in ipairs(expandedRule.conditions or {}) do
    preview.active[condition.spellID] = true
  end
end

local function RefreshPreviews()
  -- Test mode reads the same simulated debuffs, so a tick has to reach the
  -- plates and the banner immediately rather than on the next 0.3s tick.
  if NS.TestModeActive and NS.TestModeActive() and NS.RefreshTestMode then
    pcall(NS.RefreshTestMode)
  end
  -- The plate border is a global setting, so every stage shows the same one --
  -- refreshed here rather than in each page's own RefreshPreview, which is
  -- four places to forget.
  for _, panel in ipairs(tabPanels) do
    local stage = panel.head and panel.head.stage
    if stage and stage.RefreshPlateBorder then pcall(stage.RefreshPlateBorder, stage) end
  end
  for _, panel in ipairs(tabPanels) do
    if panel.RefreshPreview then
      local ok, err = pcall(panel.RefreshPreview)
      if not ok then
        NS.Print("|cffff4040preview refresh failed|r: " .. tostring(err))
      end
    end
  end
end

-- Applying a change reaches every live nameplate, and a structural one
-- rebuilds their containers -- up to a thousand textures per plate. Doing that
-- per slider step made dragging stutter, so the world-side work is coalesced:
-- the preview updates immediately, the plates catch up when you stop.
local APPLY_DELAY = 0.25
local pendingLive, pendingStructural, applyTimer = false, false, nil

local function ApplyPending()
  applyTimer = nil
  local applied = true

  -- Runs from a timer, so an error here is invisible AND leaves the pending
  -- flags set — the next change then looks like it did nothing. Report it and
  -- always clear the flags.
  local ok, err = pcall(function()
    if pendingStructural then
      pendingStructural, pendingLive = false, false
      applied = NS.RebuildAllRigs()
    elseif pendingLive then
      pendingLive = false
      NS.ApplyTintColors()
      for _, rig in pairs(NS.rigs) do
        NS.AnchorTints(rig)
        NS.AnchorIcons(rig)
        NS.AnchorMissingIcons(rig)
      end
    end
  end)

  pendingStructural, pendingLive = false, false
  if not ok then
    NS.Print("|cffff4040apply failed|r: " .. tostring(err))
  end
  if statusText then
    statusText:SetText(
      (not ok) and "|cffff4040Error — see chat|r"
      or (applied and "|cff55dd55Settings Saved|r" or "|cffffcc00Queued until out of combat|r"))
  end
end

-- Restarted on every change, so a drag applies once when it ends rather than
-- once per frame while it is happening.
local function ScheduleApply()
  if applyTimer then applyTimer:Cancel() end
  if statusText then statusText:SetText("|cff808080Pending...|r") end
  applyTimer = C_Timer.NewTimer(APPLY_DELAY, ApplyPending)
end

-- Colour and placement of frames that already exist.
local function Live()
  -- The fill cache is derived from configuration, and this is one of the three
  -- doors configuration changes come through.
  if NS.InvalidateFillCache then NS.InvalidateFillCache() end
  pendingLive = true
  RefreshPreviews()
  ScheduleApply()
end

-- Anything that changes the aura groups themselves. Groups cannot be edited
-- after creation, so the containers have to be rebuilt — but the options rows
-- are describing the same lists as before, so leave them alone.
local function Restyle()
  if NS.InvalidateFillCache then NS.InvalidateFillCache() end
  pendingStructural = true
  RefreshPreviews()
  ScheduleApply()
end

-- ...and the same, for changes the options rows also have to redraw.
local function Structural()
  if NS.InvalidateFillCache then NS.InvalidateFillCache() end
  pendingStructural = true
  NS.Options_RebuildAll()
  -- Previews too: border thickness is a structural change, and without this
  -- the stage kept drawing the old shape until something else refreshed it.
  RefreshPreviews()
  ScheduleApply()
end

-------------------------------------------------------------------------------
-- Shared preview stage
-------------------------------------------------------------------------------

-- Test-mode buttons on both colouring tabs. Deliberately do not close the
-- window -- the point is to tick debuffs and watch the plate change.
--
-- Each button owns a scope: it stops test mode if already running in ITS
-- scope, and switches to that scope otherwise.
local function TestModeButton(parent, all)
  local b
  b = Button(parent, "", all and 170 or 190, function()
    local on = NS.TestModeActive and NS.TestModeActive()
    local isAll = NS.TestModeAll and NS.TestModeAll()
    if on and isAll == (all and true or false) then
      NS.TestMode("off")
    else
      NS.TestMode(all and "all" or "target")
    end
    EnsureRulePreview()
    RefreshPreviews()
  end)
  b.Refresh = function()
    local on = NS.TestModeActive and NS.TestModeActive()
    local isAll = NS.TestModeAll and NS.TestModeAll()
    local mine = on and isAll == (all and true or false)
    if all then
      b:SetText(mine and "Stop Testing All" or "Test All Nameplates")
    else
      b:SetText(mine and "Stop Testing Target" or "Test Coloring on Target")
    end
    if mine then
      b.label:SetTextColor(1, 0.82, 0.1)
    else
      b.label:SetTextColor(1, 1, 1)
    end
  end
  b.Refresh()
  Tip(b, all and "Test All Nameplates" or "Test Coloring on Target",
    all and TIPS.testAll or TIPS.testTarget,
    { note = "Test mode ignores whether the debuffs are actually present -- it cannot tell you whether a rule would MATCH, only what it looks like." })
  return b
end

-- height defaults to STAGE_H. The Aura Icons pages pass a taller one: their
-- preview has to show icons ABOVE the bar, which the colouring pages' stage
-- has no room for -- everything on those is drawn on the bar itself.
local function BuildStage(parent, height)
  local stage = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  stage:SetHeight(height or STAGE_H)
  stage:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(stage)
  -- Dark grey rather than near-black, so the plate's black border reads
  -- against it instead of disappearing.
  stage:SetBackdropColor(RGBA(THEME.stageBG))
  stage:SetBackdropBorderColor(RGBA(THEME.stageBorder))

  local plate = CreateFrame("Frame", nil, stage)
  plate:SetSize(220, 18)
  plate:SetPoint("CENTER", stage, "CENTER", 0, 0)
  stage.plate = plate

  stage.name = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  stage.name:SetPoint("BOTTOM", plate, "TOP", 0, 3)
  stage.name:SetText("Fearsome Dummy")
  StyleText(stage.name, 12)
  stage.name:SetTextColor(1, 0.82, 0)

  -- The plate border, drawn the way the ENGINE draws it: four textures on the
  -- bar at the top OVERLAY sublevel.
  --
  -- It used to be a backdrop on a frame 2px outside the plate. Once the engine
  -- reserved a band INSIDE the bar, that frame had to win a draw-order fight
  -- against the bar it overlapped, and lost. Textures on the bar have no such
  -- fight -- sublevel decides, and 7 is the top.
  stage.plateEdges = {}

  function stage:RefreshPlateBorder()
    local cfg = (NS.db and NS.db.tints) or {}
    local on = cfg.plateOutline ~= false
    local t = math.max(1, math.min(8, cfg.plateOutlineSize or 1))
    local off = math.max(-8, math.min(8, cfg.plateOutlineOffset or 0))
    local c = cfg.plateOutlineColor or { r = 0, g = 0, b = 0, a = 1 }

    -- top, bottom, left, right -- the same order and the same unit vectors the
    -- engine uses, so the two cannot disagree about which edge is which.
    local SIDES = {
      { key = "top",    a = "TOPLEFT",    b = "TOPRIGHT",    ax = -1, ay =  1, bx =  1, by =  1, vertical = false },
      { key = "bottom", a = "BOTTOMLEFT", b = "BOTTOMRIGHT", ax = -1, ay = -1, bx =  1, by = -1, vertical = false },
      { key = "left",   a = "TOPLEFT",    b = "BOTTOMLEFT",  ax = -1, ay =  1, bx = -1, by = -1, vertical = true  },
      { key = "right",  a = "TOPRIGHT",   b = "BOTTOMRIGHT", ax =  1, ay =  1, bx =  1, by = -1, vertical = true  },
    }
    local sides = cfg.plateOutlineSides

    for index, side in ipairs(SIDES) do
      local tex = stage.plateEdges[index]
      if not tex then
        tex = stage.bar:CreateTexture(nil, "OVERLAY", nil, 7)
        stage.plateEdges[index] = tex
      end
      if not on or (sides and sides[side.key] == false) then
        tex:Hide()
      else
        tex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
        tex:ClearAllPoints()
        tex:SetPoint(side.a, stage.bar, side.a, side.ax * -off, side.ay * -off)
        tex:SetPoint(side.b, stage.bar, side.b, side.bx * -off, side.by * -off)
        if side.vertical then tex:SetWidth(t) else tex:SetHeight(t) end
        tex:Show()
      end
    end
  end

  stage.bar = CreateFrame("StatusBar", nil, plate)
  stage.bar:SetAllPoints()
  -- Flat fill, so a tint reads as its true colour rather than through art.
  stage.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  stage.bar:SetMinMaxValues(0, 1)
  stage.bar:SetValue(0.72)
  -- The bar under everything this addon draws: Blizzard's hostile red, which
  -- is what a plate wears before anything here has painted it. Nothing else
  -- in this window is allowed to be red for a different reason, so a red
  -- preview bar means "no rule, no threat state, no target colour".
  stage.bar:SetStatusBarColor(0.62, 0.11, 0.11)

  stage.barBG = stage.bar:CreateTexture(nil, "BACKGROUND")
  stage.barBG:SetAllPoints()
  stage.barBG:SetColorTexture(0.10, 0.03, 0.03, 0.95)

  -- OVERLAY 7 and anchored to the BAR FRAME, not the fill texture. Anchored to
  -- the fill, the preview inherited its width and draw order: it shrank at low
  -- health and could lose on ARTWORK. This is a diagram of the rule logic, not
  -- a simulation of a health bar.

  -- Anchored to the FILL, exactly as the real tint is, so the colour covers
  -- only the health actually there.
  stage.tint = stage.bar:CreateTexture(nil, "OVERLAY", nil, 5)
  stage.tint:SetPoint("TOPLEFT", stage.bar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
  stage.tint:SetPoint("BOTTOMRIGHT", stage.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
  stage.tint:Hide()

  -- Missing-health cover preview, anchored and repainted per refresh via
  -- NS.ApplyMissingCover. Sublevel 6: above the tint so it wins any unclipped
  -- sliver a texture-mode mask leaves, and below borderEdges at 7.
  stage.missingCover = stage.bar:CreateTexture(nil, "OVERLAY", nil, 6)
  stage.missingCover:Hide()

  -- Preview border: four edges on the stage bar, mirroring what the engine
  -- builds per host. Without these a border-only rule previews as a blank
  -- bar, which is indistinguishable from a rule that does not match.
  stage.borderEdges = {}
  for index = 1, 4 do
    -- Above the preview tint (sublayer 7), same ordering as the plate.
    local e = stage.bar:CreateTexture(nil, "OVERLAY", nil, 7)
    e:Hide()
    stage.borderEdges[index] = e
  end

  -- The missing wash. Created here rather than per pane so no stage can be
  -- missing one.
  --
  -- BELOW stage.tint, mirroring the plate: the ladder is built under every
  -- presence rule, so a matching rule wins the bar and the reminder shows
  -- where nothing matches. On a real plate the ladder's halves sit on
  -- different frames and strata separates them, which a flat preview cannot
  -- reproduce -- so this draws one texture.
  stage.missingWash = stage.bar:CreateTexture(nil, "OVERLAY", nil, 4)
  stage.missingWash:Hide()

  stage.health = stage.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  stage.health:SetPoint("CENTER")
  StyleText(stage.health, 11)
  stage.health:SetText("72%")

  -- Inside the stage, so every preview that uses BuildStage gets it and none
  -- can be forgotten. The stage is a flat approximation: it cannot know your
  -- nameplate addon's bar art, size or its own border.
  stage.note = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  stage.note:SetPoint("BOTTOM", 0, 5)
  StyleText(stage.note, 10)
  stage.note:SetText("NOTE: PREVIEW IS A VISUAL APPROXIMATION, YOUR NAMEPLATES MIGHT DIFFER")
  stage.note:SetTextColor(0.55, 0.55, 0.62)

  stage.icons = {}

  -- Markers are drawn OUTSIDE the bar, so they need a frame that is not
  -- clipped to it. Its textures are thrown away and repainted on each refresh:
  -- shape, side, size and gap can all change between passes, and a pool keyed
  -- by nothing in particular would have to be reconciled against all four.
  stage.markerHost = CreateFrame("Frame", nil, stage)
  stage.markerHost:SetAllPoints(stage.bar)
  stage.markerHost:SetFrameLevel(stage.bar:GetFrameLevel() + 3)
  stage.markers = {}

  return stage
end

-- Paints a previewed unit's marker onto a stage, or clears it when entry is
-- nil. Through NS.PaintMarker, which is what the engine calls -- one painter,
-- so the preview cannot disagree with the plate about its own shape.
local function DrawStageMarkers(stage, entry)
  for _, tex in ipairs(stage.markers) do tex:Hide() end
  local ind = entry and entry.indicator
  if not (ind and ind.enabled) then
    stage.markerKey = nil
    return
  end
  -- The marker's own colour where it has one, exactly as the plate does.
  --
  -- This read entry.color -- the BAR's colour -- so a marker given its own
  -- was previewed in the wash's instead, and the cache key below was built
  -- from the same wrong colour: changing the marker's opacity did not alter
  -- the key, so the preview did not repaint at all.
  local colour = (NS.MarkerColor and NS.MarkerColor(entry))
    or entry.color or { r = 1, g = 1, b = 1, a = 1 }

  -- Repainted only when the marker actually changed.
  --
  -- A texture cannot be destroyed in WoW, and this refresh runs on every
  -- preview pass -- so painting unconditionally would leak a handful of
  -- textures per pass for as long as the window is open. The key covers
  -- everything PaintMarker reads.
  local key = table.concat({ ind.shape or "arrow", ind.position or "BOTH",
    ind.size or 10, ind.gap or 4,
    colour.r, colour.g, colour.b, colour.a or 1 }, ":")
  if key == stage.markerKey then
    for _, tex in ipairs(stage.markers) do tex:Show() end
    return
  end
  stage.markerKey = key
  wipe(stage.markers)
  for _, side in ipairs(NS.MarkerSides(ind.position)) do
    local _, textures = NS.PaintMarker(stage.markerHost, stage.bar, side, ind, colour, 7)
    for _, tex in ipairs(textures or {}) do
      stage.markers[#stage.markers + 1] = tex
    end
  end
end

-- Top matching rule from one list against the simulated debuffs. Used by both
-- previews so "which rule wins" is answered the same way on either tab.
local function PreviewWinner(list)
  for _, rule in ipairs(list or {}) do
    if rule.enabled ~= false and #(rule.conditions or {}) > 0 then
      local all = true
      for _, c in ipairs(rule.conditions) do
        if not preview.active[c.spellID] then all = false break end
      end
      if all then return rule end
    end
  end
end

-- Draws a rule's border onto a preview stage, or clears it when rule is nil.
-- Shared by both preview panes so the health tab and the border tab cannot
-- disagree about what a border looks like.
local function DrawStageBorder(stage, rule)
  local b = rule and rule.border
  for _, e in ipairs(stage.borderEdges) do e:Hide() end
  if not (b and b.enabled) then return end
  local t = math.max(1, math.min(8, b.thickness or 2))
  local bc = b.color or NS.DefaultBorder().color
  local pad = math.max(0, math.min(12, b.padding or 0))
  local out = (b.grow == "OUT") and (t + pad) or -pad
  local corners = {
    { "TOPLEFT", "TOPRIGHT", -1, 1, 1, 1, false },
    { "BOTTOMLEFT", "BOTTOMRIGHT", -1, -1, 1, -1, false },
    { "TOPLEFT", "BOTTOMLEFT", -1, 1, -1, -1, true },
    { "TOPRIGHT", "BOTTOMRIGHT", 1, 1, 1, -1, true },
  }
  for index, c in ipairs(corners) do
    local e = stage.borderEdges[index]
    e:ClearAllPoints()
    e:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
    e:SetPoint(c[1], stage.bar, c[1], c[3] * out, c[4] * out)
    e:SetPoint(c[2], stage.bar, c[2], c[5] * out, c[6] * out)
    if c[7] then e:SetWidth(t) else e:SetHeight(t) end
    e:Show()
  end
end

-- Which MISSING rule the ladder would be washing the bar with, or nil.
--
-- Resolved the way the engine constructs it: wash k shows only while D1..D(k-1)
-- are present and Dk is not, so the answer is the first rule in list order
-- whose debuff is not up.
--
-- Single-debuff and enabled only, matching the ladder's admission rules.
-- Health list only -- border rules have no wash.
local function PreviewMissingRule()
  if not (NS.db and NS.db.tints and NS.db.tints.enabled) then return end
  for _, rule in ipairs(NS.db.tints.rules or {}) do
    if rule.showWhenMissing and rule.enabled ~= false
      and #(rule.conditions or {}) == 1
      and not preview.active[rule.conditions[1].spellID] then
      return rule
    end
  end
end

-- Which auras the icon preview shows: what you actually track, falling back
-- to a sample so the layout controls always have something to move.
local function PreviewAuras()
  local list = {}
  for _, entry in ipairs(NS.db.icons.list) do
    if entry.enabled ~= false then table.insert(list, entry.spellID) end
  end
  if #list == 0 then return SAMPLE_AURAS, true end
  return list, false
end

-- Mirrors Icons.lua: one anchor point, its mirror, free X/Y padding. Drawn
-- regardless of the module toggle — this shows what icons WOULD look like.
local function LayoutStageIcons(stage)
  local db = NS.db.icons
  for _, icon in ipairs(stage.icons) do icon:Hide() end

  local auras = PreviewAuras()
  local size, gap = db.size, db.spacing
  local perRow = math.max(1, db.maxPerRow or 6)
  local cols = math.min(#auras, perRow)
  local rows = math.ceil(#auras / perRow)

  if not stage.iconHost then stage.iconHost = CreateFrame("Frame", nil, stage) end
  local host = stage.iconHost
  host:SetSize(math.max(1, cols * size + (cols - 1) * gap),
               math.max(1, rows * size + (rows - 1) * gap))
  host:ClearAllPoints()
  host:SetPoint(NS.AnchorMirror[db.anchor] or "BOTTOM", stage.bar, db.anchor or "TOP",
    db.padX or 0, db.padY or 0)

  local edge = db.borderSize or 1
  local border = db.borderColor or { r = 0, g = 0, b = 0, a = 1 }

  -- Timer and stack text are optional here: they are the thing the Timer &
  -- Stacks swatch exists to show up close, but seeing them at true size on
  -- the plate is the only way to tell whether they fit.
  local showText = NS.db.uiPreviewText ~= false

  for index, spellID in ipairs(auras) do
    local icon = stage.icons[index]
    if not icon then
      icon = {}
      icon.bg = host:CreateTexture(nil, "ARTWORK")
      icon.tex = host:CreateTexture(nil, "OVERLAY")
      icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      -- Parented to the host frame but anchored to the icon's own backing
      -- texture, so they follow it through every layout change.
      icon.timer = host:CreateFontString(nil, "OVERLAY")
      icon.count = host:CreateFontString(nil, "OVERLAY")
      icon.Hide = function(self)
        self.bg:Hide(); self.tex:Hide(); self.timer:Hide(); self.count:Hide()
      end
      icon.Show = function(self) self.bg:Show(); self.tex:Show() end
      stage.icons[index] = icon
    end
    icon.bg:SetSize(size, size)
    icon.bg:SetColorTexture(border.r, border.g, border.b, border.a or 1)
    icon.tex:SetTexture(NS.SpellIcon(spellID))

    local col = (index - 1) % perRow
    local row = math.floor((index - 1) / perRow)
    icon.bg:ClearAllPoints()
    if db.grow == "LEFT" then
      icon.bg:SetPoint("TOPRIGHT", host, "TOPRIGHT", -col * (size + gap), -row * (size + gap))
    else
      icon.bg:SetPoint("TOPLEFT", host, "TOPLEFT", col * (size + gap), -row * (size + gap))
    end
    icon.tex:ClearAllPoints()
    icon.tex:SetPoint("TOPLEFT", icon.bg, "TOPLEFT", edge, -edge)
    icon.tex:SetPoint("BOTTOMRIGHT", icon.bg, "BOTTOMRIGHT", -edge, edge)
    icon:Show()

    if showText and db.showTimer then
      NS.ApplyFont(icon.timer, db.timerFont, db.timerSize, db.timerOutline)
      icon.timer:SetText(FormatPreviewTime(SAMPLE_TIME_VALUES[index] or 8, db.timerPrecision))
      icon.timer:ClearAllPoints()
      icon.timer:SetPoint(db.timerAnchor or "CENTER", icon.bg, db.timerAnchor or "CENTER",
        db.timerX or 0, db.timerY or 0)
      icon.timer:Show()
    else
      icon.timer:Hide()
    end

    if showText and db.showCount then
      NS.ApplyFont(icon.count, db.countFont, db.countSize, db.countOutline)
      icon.count:SetText(SAMPLE_COUNTS[index] or "2")
      icon.count:ClearAllPoints()
      icon.count:SetPoint(db.countAnchor or "BOTTOMRIGHT", icon.bg, db.countAnchor or "BOTTOMRIGHT",
        db.countX or 0, db.countY or 0)
      icon.count:Show()
    else
      icon.count:Hide()
    end
  end
end

-- A small swatch of icons for the Style section: shows size, spacing, row
-- wrapping and border without the surrounding plate.
local function BuildIconSwatch(parent)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(210, 96)
  box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(box)
  box:SetBackdropColor(RGBA(THEME.stageBG))
  box:SetBackdropBorderColor(RGBA(THEME.stageBorder))
  box.icons = {}

  function box:Refresh()
    local db = NS.db.icons
    for _, icon in ipairs(self.icons) do icon.bg:Hide(); icon.tex:Hide() end

    local auras = PreviewAuras()
    local size, gap = db.size, db.spacing
    local perRow = math.max(1, db.maxPerRow or 6)
    local edge = db.borderSize or 1
    local border = db.borderColor or { r = 0, g = 0, b = 0, a = 1 }

    for index, spellID in ipairs(auras) do
      local icon = self.icons[index]
      if not icon then
        icon = { bg = self:CreateTexture(nil, "ARTWORK"), tex = self:CreateTexture(nil, "OVERLAY") }
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        self.icons[index] = icon
      end
      icon.bg:SetSize(size, size)
      icon.bg:SetColorTexture(border.r, border.g, border.b, border.a or 1)
      icon.tex:SetTexture(NS.SpellIcon(spellID))

      local col = (index - 1) % perRow
      local row = math.floor((index - 1) / perRow)
      icon.bg:ClearAllPoints()
      icon.bg:SetPoint("TOPLEFT", self, "TOPLEFT", 8 + col * (size + gap), -8 - row * (size + gap))
      icon.tex:ClearAllPoints()
      icon.tex:SetPoint("TOPLEFT", icon.bg, "TOPLEFT", edge, -edge)
      icon.tex:SetPoint("BOTTOMRIGHT", icon.bg, "BOTTOMRIGHT", -edge, edge)
      icon.bg:Show()
      icon.tex:Show()
    end
  end

  return box
end

-- A dummy icon for Timer & Stacks, built at the icon's REAL pixel size and
-- then scaled up, so a 28pt timer on a 24px icon overflows here exactly as
-- much as it will in the world. Drawing it at a fixed 72px made every font
-- look far smaller than it was.
local SWATCH_TARGET = 76 -- how many screen pixels the magnified icon fills
local SWATCH_MAX_ZOOM = 5

local function BuildTextSwatch(parent)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(120, 128)
  box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(box)
  box:SetBackdropColor(RGBA(THEME.stageBG))
  box:SetBackdropBorderColor(RGBA(THEME.stageBorder))

  box.icon = CreateFrame("Frame", nil, box)
  box.icon:SetPoint("CENTER", box, "CENTER", 0, 5)

  box.bg = box.icon:CreateTexture(nil, "BACKGROUND")
  box.bg:SetAllPoints()

  box.tex = box.icon:CreateTexture(nil, "ARTWORK")
  box.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  box.timer = box.icon:CreateFontString(nil, "OVERLAY")
  box.count = box.icon:CreateFontString(nil, "OVERLAY")

  -- Sits on the box, not the scaled icon, so it stays legible at any zoom.
  box.caption = Dim(box, "")
  box.caption:SetPoint("BOTTOM", 0, 5)

  function box:Refresh()
    local db = NS.db.icons
    local edge = db.borderSize or 1
    local border = db.borderColor or { r = 0, g = 0, b = 0, a = 1 }

    local size = db.size or 24
    local zoom = math.max(1, math.min(SWATCH_MAX_ZOOM, SWATCH_TARGET / size))
    self.icon:SetSize(size, size)
    self.icon:SetScale(zoom)
    self.caption:SetText(("%dpx icon · %.1f× zoom"):format(size, zoom))

    local auras = PreviewAuras()
    self.tex:SetTexture(NS.SpellIcon(auras[1] or 980))
    self.bg:SetColorTexture(border.r, border.g, border.b, border.a or 1)
    self.tex:ClearAllPoints()
    self.tex:SetPoint("TOPLEFT", edge, -edge)
    self.tex:SetPoint("BOTTOMRIGHT", -edge, edge)

    NS.ApplyFont(self.timer, db.timerFont, db.timerSize, db.timerOutline)
    self.timer:SetText(FormatPreviewTime(3.456, db.timerPrecision))
    self.timer:ClearAllPoints()
    self.timer:SetPoint(db.timerAnchor or "CENTER", self.icon, db.timerAnchor or "CENTER",
      db.timerX or 0, db.timerY or 0)
    self.timer:SetShown(db.showTimer and true or false)

    NS.ApplyFont(self.count, db.countFont, db.countSize, db.countOutline)
    self.count:SetText("3")
    self.count:ClearAllPoints()
    self.count:SetPoint(db.countAnchor or "BOTTOMRIGHT", self.icon, db.countAnchor or "BOTTOMRIGHT",
      db.countX or 0, db.countY or 0)
    self.count:SetShown(db.showCount and true or false)
  end

  return box
end

-- Confirmation dialog. Hand-built rather than StaticPopupDialogs so it matches
-- the window. One shared instance, re-labelled per use.

local confirmDialog

local function ShowConfirm(title, body, acceptText, onAccept)
  if not confirmDialog then
    local d = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    -- Width is fixed; the HEIGHT is measured from the body text every time it
    -- is shown (see below). A single fixed size meant a one-line "delete this
    -- rule?" got the same slab of empty space as the three-paragraph combo
    -- warning, which made the small confirms look far more serious than they
    -- are.
    d:SetSize(420, 160)
    d:SetPoint("CENTER", 0, 80)
    -- Above the options window, which sits at HIGH.
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true) -- swallow clicks so the window behind is inert
    d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    PixelBorder(d)
    d:SetBackdropColor(RGBA(THEME.windowBG))
    d:SetBackdropBorderColor(RGBA(THEME.accentBorder))
    d:Hide()

    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 14, -12)
    StyleText(d.title, 13)
    d.title:SetTextColor(RGBA(THEME.headerText))

    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.body:SetPoint("TOPLEFT", 14, -36)
    d.body:SetPoint("TOPRIGHT", -14, -36)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    StyleText(d.body, 12)
    d.body:SetTextColor(RGBA(THEME.textDim))

    d.accept = Button(d, "", 130, function()
      d:Hide()
      if d.onAccept then d.onAccept() end
    end)
    d.accept:SetPoint("BOTTOMRIGHT", -14, 12)

    d.cancel = Button(d, "Cancel", 90, function() d:Hide() end)
    d.cancel:SetPoint("BOTTOMLEFT", 14, 12)

    confirmDialog = d
  end

  confirmDialog.title:SetText(title)
  confirmDialog.body:SetText(body)
  confirmDialog.accept:SetText(acceptText)
  -- Measured AFTER SetText, and only works because the body has both a left
  -- and a right anchor -- a fontstring with no known width reports the height
  -- of a single unwrapped line.
  local textHeight = math.max(20, confirmDialog.body:GetStringHeight() or 20)
  confirmDialog.body:SetHeight(textHeight + 2)
  -- 36 above the text, then the button row and its padding below it.
  confirmDialog:SetHeight(36 + textHeight + 50)
  confirmDialog.onAccept = onAccept
  confirmDialog:Show()
  confirmDialog:Raise()
end

-- Text prompt: ShowConfirm with an edit box. Separate instance rather than a
-- mode flag -- a stray edit box left visible on an ordinary confirm is the
-- kind of bug that lingers.

local promptDialog

local function ShowPrompt(title, body, acceptText, onAccept, initialText)
  if not promptDialog then
    local d = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    d:SetSize(420, 200)
    d:SetPoint("CENTER", 0, 80)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    PixelBorder(d)
    d:SetBackdropColor(RGBA(THEME.windowBG))
    d:SetBackdropBorderColor(RGBA(THEME.accentBorder))
    d:Hide()

    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 16, -16)
    StyleText(d.title, 14)
    d.title:SetTextColor(RGBA(THEME.headerText))

    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.body:SetPoint("TOPLEFT", 16, -44)
    d.body:SetPoint("TOPRIGHT", -16, -44)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    d.body:SetHeight(56)
    StyleText(d.body, 12)
    d.body:SetTextColor(RGBA(THEME.textDim))

    d.edit = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
    d.edit:SetPoint("TOPLEFT", 20, -108)
    d.edit:SetPoint("TOPRIGHT", -20, -108)
    d.edit:SetHeight(22)
    d.edit:SetAutoFocus(true)
    StyleText(d.edit, 12)

    local function Accept()
      local text = d.edit:GetText()
      d:Hide()
      if d.onAccept then d.onAccept(text) end
    end
    d.edit:SetScript("OnEnterPressed", Accept)
    d.edit:SetScript("OnEscapePressed", function() d:Hide() end)

    d.accept = Button(d, "", 150, Accept)
    d.accept:SetPoint("BOTTOMRIGHT", -16, 14)
    d.cancel = Button(d, "Cancel", 100, function() d:Hide() end)
    d.cancel:SetPoint("BOTTOMLEFT", 16, 14)

    promptDialog = d
  end

  promptDialog.title:SetText(title)
  promptDialog.body:SetText(body)
  promptDialog.accept:SetText(acceptText)
  promptDialog.onAccept = onAccept
  promptDialog.edit:SetText(initialText or "")
  promptDialog:Show()
  promptDialog:Raise()
  promptDialog.edit:SetFocus()
  promptDialog.edit:HighlightText()
end

-- First-run warning, once per account, before the addon has done anything
-- unasked. Two real choices: accept, or unload. Unload genuinely disables and
-- reloads -- there is no way to unload in place, and a button that only hid
-- itself would be a lie.

local WARNING_TEXT =
  "This addon is in very early stages and completely experimental. "
  .. "You shouldn't experience too much performance loss from single-buff rules, "
  .. "but conditional coloring rules can be costly.\n\n"
  .. "This addon works alongside default Blizzard nameplates as well as other "
  .. "nameplate addons, just be sure to disable the Aura Icon module in this "
  .. "addon if you'd like to use them elsewhere.\n\n"
  .. "Confirm you have read this warning."

local firstRunDialog

function NS.ShowFirstRunWarning(force)
  PLATETWEAKS_SETTINGS = PLATETWEAKS_SETTINGS or {}
  if PLATETWEAKS_SETTINGS.warningAccepted and not force then return false end

  if not firstRunDialog then
    local d = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    d:SetSize(500, 370)
    d:SetPoint("CENTER", 0, 60)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    PixelBorder(d)
    d:SetBackdropColor(RGBA(THEME.windowBG))
    d:SetBackdropBorderColor(RGBA(THEME.accentBorder))

    -- Draggable, because it opens dead centre and may be over something the
    -- user wants to read before deciding.
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)

    d.titleBar = d:CreateTexture(nil, "ARTWORK")
    d.titleBar:SetPoint("TOPLEFT", 1, -1)
    d.titleBar:SetPoint("TOPRIGHT", -1, -1)
    d.titleBar:SetHeight(40)
    d.titleBar:SetColorTexture(RGBA(THEME.titleBarBG))

    d.logo = d:CreateTexture(nil, "OVERLAY")
    d.logo:SetSize(28, 28)
    d.logo:SetPoint("TOPLEFT", 14, -6)
    d.logo:SetTexture("Interface\\AddOns\\PlateTweaks\\media\\logo-64")

    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("LEFT", d.logo, "RIGHT", 8, 0)
    StyleText(d.title, 18)
    d.title:SetText(NS.WindowTitle())
    d.title:SetTextColor(RGBA(THEME.titleText))

    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.body:SetPoint("TOPLEFT", 20, -56)
    d.body:SetPoint("TOPRIGHT", -20, -56)
    d.body:SetJustifyH("LEFT")
    d.body:SetJustifyV("TOP")
    d.body:SetHeight(220)
    StyleText(d.body, 13)
    d.body:SetTextColor(RGBA(THEME.textNormal))
    d.body:SetText(WARNING_TEXT)

    d.slash = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.slash:SetPoint("BOTTOM", 0, 52)
    StyleText(d.slash, 18)
    d.slash:SetText("|cffffd24a/pt|r to open PlateTweaks settings")

    d.accept = Button(d, "OK, I accept", 160, function()
      PLATETWEAKS_SETTINGS.warningAccepted = true
      d:Hide()
    end)
    d.accept:SetPoint("BOTTOMRIGHT", -18, 16)

    d.decline = Button(d, "No thanks, Unload the addon", 220, function()
      d:Hide()
      -- There is no unload-in-place. Disabling plus a reload is the only
      -- honest version of this button, so say so rather than appearing to
      -- do nothing until the next session.
      local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
      if disable then
        pcall(disable, NS.ADDON)
      end
      NS.Print("Disabled. Reloading — re-enable from the AddOns menu any time.")
      C_Timer.After(1, ReloadUI)
    end)
    d.decline:SetPoint("BOTTOMLEFT", 18, 16)

    firstRunDialog = d
  end

  firstRunDialog:Show()
  firstRunDialog:Raise()
  return true
end

-------------------------------------------------------------------------------
-- Window shell
-------------------------------------------------------------------------------

local function SelectTab(index)
  -- The cross-module overlay is something you switch on to compare two rule
  -- sets while looking at them, not a setting. Leaving the page ends it, so
  -- it can never be left on and later mistaken for how the preview normally
  -- looks. Cleared on every navigation, including back to the same page --
  -- the button is one click away and re-arming it costs nothing.
  NS.db.uiPreviewCombine = false

  for i, panel in ipairs(tabPanels) do
    panel:SetShown(i == index)
    if tabButtons[i] then tabButtons[i]:SetSelected(i == index) end
  end
  RefreshPreviews()

  -- Work a page only wants done when it is actually opened. Diagnostics walks
  -- every rig and every rule to build its report, which is far too much to
  -- repeat on the general preview refresh -- that one runs on every frame of
  -- a colour-picker drag.
  local panel = tabPanels[index]

  -- A rule's own page tests THAT rule; every other page tests the list as the
  -- ticked debuffs select it. Flagged on the panel rather than compared
  -- against PAGE_RULE because that constant is declared further down the file
  -- and so is not in scope inside this function.
  if NS.SetTestFocus then
    NS.SetTestFocus(panel and panel.ruleFocus and expandedRule or nil)
  end

  if panel and panel.OnSelect then
    local ok, err = pcall(panel.OnSelect)
    if not ok then NS.Print("|cffff4040page refresh failed|r: " .. tostring(err)) end
  end
end



-- A row in the left rail, and the only navigation widget now -- the
-- horizontal tab strip it replaces was deleted with it. Selected state is a
-- bar down the LEFT edge rather than along the bottom, which is what makes a
-- rail read as a rail rather than as tabs turned sideways.
local function NavItem(parent, text, indent, onClick)
  local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
  t:SetHeight(24)
  t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

  t.label = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.label:SetPoint("LEFT", indent, 0)
  t.label:SetPoint("RIGHT", -6, 0)
  t.label:SetJustifyH("LEFT")
  t.label:SetText(text)
  t.label:SetWordWrap(false)
  StyleText(t.label, 12)

  t.accent = t:CreateTexture(nil, "OVERLAY")
  t.accent:SetPoint("TOPLEFT")
  t.accent:SetPoint("BOTTOMLEFT")
  t.accent:SetWidth(2)
  t.accent:SetColorTexture(RGBA(THEME.accent))

  local selected, hovered = false, false
  -- A subheader owns the list beneath it -- "Color Rules" over its rules --
  -- rather than being one more peer in the rail. It reads brighter and warmer
  -- at rest and carries a hairline under it, so the rows below are visibly
  -- its contents. Still a real page link, which is why it stays a NavItem
  -- rather than becoming an inert label with buttons parked on it.
  local isSub = false
  local function Paint()
    if selected then
      t:SetBackdropColor(RGBA(THEME.tabBGSelected))
      t.label:SetTextColor(RGBA(THEME.textNormal))
    else
      -- Fully transparent when idle, so the rail reads as one surface with a
      -- highlight moving over it rather than a stack of separate buttons.
      t:SetBackdropColor(RGBA(THEME.tabBGHover, hovered and 1 or 0))
      -- Branched rather than written as `isSub and RGBA(a) or RGBA(b)`:
      -- RGBA returns FOUR values, and inside an and/or chain Lua truncates a
      -- call to its first result -- SetTextColor would receive r with g and b
      -- nil and throw, taking the whole rail build down with it.
      if isSub then
        t.label:SetTextColor(RGBA(THEME.headerText))
      else
        t.label:SetTextColor(RGBA(THEME.tabTextDim))
      end
    end
    t.accent:SetShown(selected)
  end

  t.rule = t:CreateTexture(nil, "ARTWORK")
  t.rule:SetHeight(1)
  t.rule:SetPoint("BOTTOMLEFT", 10, 1)
  t.rule:SetPoint("BOTTOMRIGHT", -8, 1)
  t.rule:SetColorTexture(RGBA(THEME.edgeSoft or THEME.tabBorder))
  t.rule:Hide()

  -- Same font as every other rail entry -- only the colour and the hairline
  -- mark it as heading the list below. Sizing it up as well made it compete
  -- with the group heading above it.
  function t:SetSubheader(value)
    isSub = value and true or false
    t.rule:SetShown(isSub)
    Paint()
  end

  function t:SetSelected(value) selected = value and true or false; Paint() end
  t:SetScript("OnEnter", function() hovered = true; Paint() end)
  t:SetScript("OnLeave", function() hovered = false; Paint() end)
  t:SetScript("OnClick", onClick)
  Paint()
  return t
end

-- Pooled rail widgets. Rebuilt whenever the rule list changes, so everything
-- is hidden and re-laid-out rather than created afresh -- WoW cannot destroy
-- a frame, so building per rebuild would leak one per edit forever.
-- Two kinds of thing now: group headings, and the page links under them.
--
-- The rule rows, their add rows, the twisties that collapsed them and the
-- divider between combos and singles are all gone. The rail listed every rule
-- as its own entry from when it was how you picked one to edit; the Color
-- Rules page is that list now -- one table, both halves, dragged and edited in
-- place -- so the rail was carrying a second copy of it that could disagree
-- about order and about which rule was selected.
local railPool = {
  headers = {}, items = {},
  headerBGs = {}, switches = {},
}
local RebuildRail

-- The heading for one rule section, as a clickable row.
--
-- It reads as a menu item -- same font, size, resting colour and hover wash as
-- NavItem -- because that is what it behaves like. The section's own colour
-- survives on the panel edge beside its rules, where it is doing structural
-- work rather than decorating a label.


-- Rows on screen, keyed by GROUP: "health|combo", "health|single", and the
-- same pair for border.
--
-- A drag is confined to its group, which makes the one ordering mistake this
-- addon allows structurally impossible: a rule dies when something above it
-- needs a SUBSET of its debuffs, i.e. a single sitting above a combo
-- containing it. Keep every combo above every single and that cannot be
-- expressed at all.
--
-- Module-level rather than local to RebuildRail: the drag handlers used to
-- close over per-rebuild tables, leaving old generations on stale lists.

-- Rows of the rule TABLE on a Color Rules page, so a drag there can find its
-- neighbours. The rail no longer lists rules, so this is the only place a rule
-- appears as a draggable row.
local pageRows = {}
local pageRowCount = {}

-- The cursor's Y in a frame's own coordinate space.
--
-- GetCursorPosition reports in screen pixels; every rect this is compared
-- against (GetTop, GetBottom) is in UI units, so the scale has to come out or
-- the two are in different spaces and no row ever matches.
--
-- It lived with the rail's drag code and went out with it, which broke
-- dragging in the TABLE -- the one place that still reorders rules. Kept here
-- now, beside the rows that use it.
local function CursorY(frame)
  local scale = frame and frame:GetEffectiveScale()
  if not scale or scale == 0 then return nil end
  local _, y = GetCursorPosition()
  return y / scale
end


-- Built from scratch rather than PortraitFrameTemplate: every widget here is
-- hand-drawn and flat, so the gold chrome was the last thing that read as
-- someone else's UI.
--
-- Width is fixed -- the pages are laid out at hardcoded pixel offsets, so only
-- height is free. Widened from 790 when the tab strip became a left rail:
-- narrowing the content area instead would have put ~170 hardcoded left
-- offsets in scope.
local RAIL_W = 186
-- Sized to the content rather than the other way round. Sections are a fixed
-- BODY_W wide at BODY_X, so any width beyond what they need shows up entirely
-- as a wider right margin -- which is what made the gap beside the banners
-- uneven: 18px against the rail, 52px against the window edge.
local WINDOW_WIDTH = 756 + RAIL_W
-- Minimum raised from 420: the rail is a fixed-height list (4 headings and 9
-- pages, ~334px) and the window can be dragged shorter than its contents.
-- The rail spans the window minus 88px of chrome, so anything under ~422
-- clipped the last entry off the bottom -- with no scrollbar there to hint
-- that Diagnostics still existed.
local WINDOW_MIN_H, WINDOW_MAX_H = 460, 900

-- Page indices are the existing tab indices, deliberately unchanged: the five
-- original pages are still 1-5 everywhere else in this file, so the rail is a
-- presentation change rather than a renumbering that would have to be chased
-- through every panel builder.
local PAGE_HEALTH, PAGE_BORDER, PAGE_ICONS = 1, 2, 3
local PAGE_PROFILES, PAGE_HELP = 4, 5
-- Plate Border and Bar Edges share one General Settings page now. Neither
-- filled a page on its own, and both answer the same question -- how the bar
-- is drawn before any rule touches it.
local PAGE_GENERAL = 6
-- Pandemic Flash took over slot 8 from the old Effects page. Effects existed
-- to hold Pandemic Flash and the missing-health colour; the first became a
-- module of its own and the second moved next to the rules that use it, which
-- left the page with nothing on it.
local PAGE_PANDEMIC = 7
local PAGE_DIAG = 8
-- The rule editor. Not in NAV_LAYOUT: it has no rail entry of its own,
-- because the rail entry for a rule IS the rule's row. Selecting one opens
-- this page.
local PAGE_RULE = 9
-- Aura Icons split into its three concerns, each with its own preview.
-- PAGE_ICONS stays the filter page, so nothing that already referenced it
-- has to change.
local PAGE_ICON_LAYOUT, PAGE_ICON_TEXT = 10, 11
-- Optional Tweaks: conveniences that have nothing to do with nameplates. Its
-- own heading precisely so nobody looks for a colouring setting in it.
local PAGE_TWEAKS = 12
-- Import/export. Its own page rather than a section on Profiles: that page is
-- about which profile is in force, this one about moving one off the account.
--
-- Everything this page owns hangs off ONE table rather than a local each --
-- this file's main chunk is at Lua's hard limit of 200 locals, and seven more
-- fails the whole addon. Anything added here should go in this table too.
local share = { PAGE = 13 }
-- Missing Debuffs: same one-table-not-several-locals discipline as `share`
-- above, for the same reason -- this file's main chunk is already at Lua's
-- 200-local ceiling. Everything this module's pages own (page indices,
-- pooled rows, build/rebuild functions) hangs off this one table.
local missing = { PAGE_LIST = 14, PAGE_LAYOUT = 15, rows = {}, ROW_W = 620, STAGE_H = 100 }
local PAGE_COUNT = 15

-- Reading order, not index order: modules first, global drawing settings next
-- under a heading that says why they are not inside a module, setup last.
--
-- Every entry is a page under a heading -- there is no second level -- so they
-- share one indent. Indenting some and not others implied a hierarchy that
-- does not exist.
local NAV_GROUP_INDENT = 10
local NAV_ITEM_INDENT = 22
-- Group heading bar. Taller than the 19 it started at: at four levels deep the
-- headings are the only thing giving the rail structure, so they earn the
-- extra pixels. Everything on the bar centres on RAIL_HEADER_H / 2.
local RAIL_HEADER_H = 24

-- Aura Icons is set apart: it is off by default and most people leave it that
-- way, since their nameplate addon already draws an aura row.

-- Each colouring module heads its own group with its rule list directly under
-- it, because the rules ARE what you navigate that module for. A shared
-- "Modules" heading put another level between you and the thing you came for.
--
-- ruleList marks where a live list gets injected -- see RebuildRail.
--
-- One level of nesting, not two: the combo/single split is a hairline between
-- two halves of one list rather than two collapsible sections.
local NAV_LAYOUT = {
  { group = "Health Coloring", module = "health", tip = "switchHealth" },
  -- A plain nav row, like Pandemic Flash and General Settings beside it.
  --
  -- It used to carry a twisty that expanded every rule as its own rail entry,
  -- from when the rail was how you selected a rule to edit. The page itself is
  -- that list now -- one table, both halves, dragged in place and edited in
  -- place -- so the rail was showing a second copy of it, one level in, that
  -- could disagree about order and selection.
  { label = "Color Rules",      index = PAGE_HEALTH, tip = "health" },
  { label = "Pandemic Flash",   index = PAGE_PANDEMIC, module = "pandemic", tip = "pandemic",
    switchTip = "switchPandemic" },
  { label = "General Settings", index = PAGE_GENERAL, tip = "general" },
  -- No Border Coloring group. Bar and border are two halves of one rule in one
  -- list, so a second heading with a second copy of that list under it was
  -- describing a split that no longer exists. The module's on/off moved onto
  -- the Health heading's page as the Border column's own switch.
  { group = "Aura Icons", module = "icons", tip = "switchIcons" },
  { label = "Filters",          index = PAGE_ICONS, tip = "icons" },
  { label = "Position & Size",  index = PAGE_ICON_LAYOUT, tip = "iconLayout" },
  { label = "Timer & Stacks",   index = PAGE_ICON_TEXT, tip = "iconText" },
  { group = "Missing Debuffs", module = "missingIcons", tip = "switchMissingIcons" },
  { label = "Which Debuffs",    index = missing.PAGE_LIST, tip = "missingList" },
  { label = "Position & Size",  index = missing.PAGE_LAYOUT, tip = "missingLayout" },
  { group = "Optional Tweaks" },
  { label = "Tooltip IDs",      index = PAGE_TWEAKS, module = "tooltipIDs",
    tip = "tweakTooltips", switchTip = "switchTooltipIDs" },
  { group = "Setup" },
  { label = "Profiles",         index = PAGE_PROFILES, tip = "profiles" },
  { label = "Import / Export",  index = share.PAGE, tip = "share" },
  { label = "Help",             index = PAGE_HELP, tip = "help" },
  { label = "Diagnostics",      index = PAGE_DIAG, tip = "diagnostics" },
}

-- Whether a rule list is expanded in the rail. Open unless explicitly closed,
-- same convention as the collapsible sections on the pages.
-- Reading and writing a module's on/off, in one place, because each of the
-- three stores it differently: health is a plain flag, border defaults ON so
-- it tests `~= false`, and icons live under a different table entirely.
local MODULE_SWITCH = {
  health = {
    get = function() return NS.db.tints.enabled and true or false end,
    set = function(v) NS.db.tints.enabled = v end,
  },
  border = {
    get = function() return NS.db.tints.borderEnabled ~= false end,
    set = function(v) NS.db.tints.borderEnabled = v end,
  },
  icons = {
    get = function() return NS.db.icons.enabled and true or false end,
    set = function(v) NS.db.icons.enabled = v end,
  },
  missingIcons = {
    get = function() return NS.db.missingIcons.enabled and true or false end,
    set = function(v) NS.db.missingIcons.enabled = v end,
  },
  -- Neither of these is a nameplate module, but the rail switch does not care
  -- what a thing IS -- only how to read and write its on/off.
  tooltipIDs = {
    get = function() return NS.db.tweaks and NS.db.tweaks.tooltipIDs and true or false end,
    set = function(v)
      NS.db.tweaks = NS.db.tweaks or {}
      NS.db.tweaks.tooltipIDs = v
    end,
    -- Nothing on a nameplate changes, so a rig rebuild would be pure waste.
    -- The tooltip handlers read the setting on their next call; this only
    -- moves the footer off "Pending...".
    apply = function() ScheduleApply() end,
  },
  -- Not a group heading -- Pandemic Flash is one page, so its switch rides on
  -- the nav ROW instead. Same table either way, so the two kinds of switch
  -- cannot disagree about how a module is stored.
  pandemic = {
    get = function() return NS.db.tints.pandemic and NS.db.tints.pandemic.enabled and true or false end,
    set = function(v)
      NS.db.tints.pandemic = NS.db.tints.pandemic or {}
      NS.db.tints.pandemic.enabled = v
    end,
  },
}

local function PageFor(kind)
  -- One page. `kind` survives as the border/health VIEW of a row, not a page.
  return PAGE_HEALTH
end

-- A rule's label in the rail. Rules have no name of their own, so this is
-- built from its debuffs -- which also means it changes the moment the
-- conditions do.
local function RuleLabel(rule)
  local names = {}
  for _, condition in ipairs(rule.conditions or {}) do
    table.insert(names, NS.SpellName(condition.spellID) or tostring(condition.spellID))
  end
  if #names == 0 then return "(no debuffs yet)" end
  local label = table.concat(names, " + ")
  -- A missing rule fires on the opposite state to every other entry in the
  -- same list, and the rail is where you pick between them -- so it has to say
  -- so here as well as on the row. Prefixed, matching NS.RuleSummary: it
  -- changes how the name after it should be read, and labels truncate from
  -- the right.
  if rule.showWhenMissing then
    return "|cffffcc22MISSING|r " .. label
  end
  return label
end

local function CreateWindow()
  local frame = CreateFrame("Frame", "PlateTweaksWindow", UIParent, "BackdropTemplate")
  frame:SetSize(WINDOW_WIDTH, 680)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(WINDOW_WIDTH, WINDOW_MIN_H, WINDOW_WIDTH, WINDOW_MAX_H)
  else
    frame:SetMinResize(WINDOW_WIDTH, WINDOW_MIN_H)
    frame:SetMaxResize(WINDOW_WIDTH, WINDOW_MAX_H)
  end
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(frame)
  frame:SetBackdropColor(RGBA(THEME.windowBG))
  frame:SetBackdropBorderColor(RGBA(THEME.windowBorder))
  frame:Hide()

  -- Preview toggles are for looking at something while the window is open.
  -- Left on, they would paint every plate in the zone with no visible control
  -- anywhere saying why -- so closing the window clears them.
  frame:HookScript("OnHide", function()
    if not NS.stagePreview then return end
    NS.stagePreview.threat, NS.stagePreview.mark = nil, nil
  end)

  -- Title bar doubles as the drag handle, so the body stays click-through to
  -- the controls sitting on it.
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(40)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, _, x, y = frame:GetPoint()
    NS.db.uiPosition = { point = point, x = x, y = y }
  end)

  titleBar.bg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBar.bg:SetAllPoints()
  titleBar.bg:SetColorTexture(RGBA(THEME.titleBarBG))

  titleBar.rule = titleBar:CreateTexture(nil, "OVERLAY")
  titleBar.rule:SetPoint("BOTTOMLEFT")
  titleBar.rule:SetPoint("BOTTOMRIGHT")
  titleBar.rule:SetHeight(1)
  titleBar.rule:SetColorTexture(RGBA(THEME.accent, 0.55))

  frame.logo = titleBar:CreateTexture(nil, "ARTWORK")
  frame.logo:SetSize(28, 28)
  frame.logo:SetPoint("LEFT", 8, 0)
  frame.logo:SetTexture("Interface\\AddOns\\PlateTweaks\\media\\logo-64")

  frame.title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("LEFT", frame.logo, "RIGHT", 8, 0)
  frame.title:SetText(NS.WindowTitle())
  StyleText(frame.title, 18)
  frame.title:SetTextColor(RGBA(THEME.titleText))

  frame.close = Button(titleBar, "X", 26, function() frame:Hide() end)
  frame.close:SetPoint("RIGHT", -6, 0)

  tinsert(UISpecialFrames, "PlateTweaksWindow")

  -- Dropdown lists are parented to UIParent so a scroll frame cannot clip
  -- them, which also means they do not inherit this window's visibility.
  -- Without this an open list is left floating on screen after Escape or the
  -- X, with nothing behind it.
  frame:HookScript("OnHide", function()
    CloseOpenMenu()
    -- Test mode paints ungated colours on real plates, so leaving it running
    -- with no window open is how someone ends up believing their rules fire
    -- constantly. The banner says so, but closing the window is the clearest
    -- signal that you are done testing.
    if NS.TestModeActive and NS.TestModeActive() then
      NS.TestMode("off")
    end
  end)

  -- Status line at the BOTTOM. It is standing information -- which profile is
  -- loaded, which modules are on, whether a change has been written -- that
  -- you consult rather than act on, and at the top it was pushing the actual
  -- controls down a full row on every page.
  frame.footerRule = frame:CreateTexture(nil, "ARTWORK")
  frame.footerRule:SetPoint("BOTTOMLEFT", 8, 24)
  frame.footerRule:SetPoint("BOTTOMRIGHT", -8, 24)
  frame.footerRule:SetHeight(1)
  frame.footerRule:SetColorTexture(0.30, 0.30, 0.36, 0.6)

  profileLabel = Label(frame, "")
  profileLabel:SetPoint("BOTTOMLEFT", 14, 8)

  statusText = Label(frame, "")
  -- Clear of the resize grip in the corner (16px wide, inset 3), which the
  -- old -14 ran straight underneath -- "Settings Saved" and the grabber were
  -- drawing on top of each other.
  statusText:SetPoint("BOTTOMRIGHT", -26, 8)
  statusText:SetJustifyH("RIGHT")

  -- Left rail instead of the old five-tab strip.
  --
  -- The strip was full at five entries, and three sections hidden under
  -- "Health Coloring" were never about health colouring -- Plate Border, Bar
  -- Edges and Pandemic Flash draw on every plate whether or not a rule
  -- matches. A vertical list also lets related pages sit under a heading.
  local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  rail:SetPoint("TOPLEFT", 8, -52)
  rail:SetPoint("BOTTOMLEFT", 8, 30)
  rail:SetWidth(RAIL_W)
  rail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(rail)
  rail:SetBackdropColor(RGBA(THEME.tabBG))
  rail:SetBackdropBorderColor(RGBA(THEME.tabBorder))
  frame.rail = rail

  -- Scrollable, because the rail now lists every rule as well as every page
  -- and neither count is bounded. It was a fixed list while it held nine
  -- fixed entries; a tenth rule would simply have fallen off the bottom.
  local railScroll = CreateFrame("ScrollFrame", nil, rail)
  railScroll:SetPoint("TOPLEFT", 1, -1)
  railScroll:SetPoint("BOTTOMRIGHT", -1, 1)
  local railContent = CreateFrame("Frame", nil, railScroll)
  -- Narrower than the scroll frame by the scrollbar's width plus its inset, so
  -- rows, switches and heading bars stop short of the bar instead of running
  -- underneath it. Everything in the rail anchors to this frame, so reserving
  -- the space once here is all that is needed.
  railContent:SetSize(RAIL_W - 10, 10)
  railScroll:SetScrollChild(railContent)
  railScroll:EnableMouseWheel(true)
  railScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, railContent:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 28)))
  end)
  -- A hairline thumb inside the rail's right edge, not the page scrollbar:
  -- the rail is 186px wide and a full-width bar would take a readable slice of
  -- it away from the labels. No track, and it hides itself entirely when
  -- everything fits, so the rail looks exactly as it did until it cannot.
  local railBar = CreateFrame("Frame", nil, rail)
  railBar:SetWidth(4)
  railBar:SetPoint("TOPRIGHT", -2, -2)
  railBar:SetPoint("BOTTOMRIGHT", -2, 2)
  railBar:EnableMouse(true)
  -- Above everything in the rail. The contents are deliberately levelled up --
  -- nav rows sit at +4 and module switches at +6 so their controls win the hit
  -- test -- and this frame sat at the rail's own level, so the thumb was drawn
  -- underneath the very list it scrolls and looked clipped away.
  railBar:SetFrameLevel(rail:GetFrameLevel() + 20)
  railBar.thumb = railBar:CreateTexture(nil, "OVERLAY")
  railBar.thumb:SetWidth(4)
  railBar.thumb:SetColorTexture(0.45, 0.45, 0.52, 0.55)

  function railBar:Update()
    local visible = railScroll:GetHeight()
    local total = railContent:GetHeight()
    local overflow = total - visible
    if overflow <= 1 or visible <= 0 then
      self.thumb:Hide()
      return
    end
    local fraction = visible / total
    -- Clamped to the track. A texture is NOT clipped by its parent frame, so a
    -- thumb taller than the bar simply hangs out of the bottom of the window --
    -- which is what a stale height looked like after the window was shrunk.
    local thumbH = math.min(visible, math.max(24, math.floor(visible * fraction)))
    local scroll = railScroll:GetVerticalScroll()
    local travel = visible - thumbH
    local offset = travel * (overflow > 0 and math.min(1, scroll / overflow) or 0)
    self.thumb:SetHeight(thumbH)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self, "TOP", 0, -offset)
    self.thumb:Show()
  end

  -- Dragging the thumb. Position is derived from the cursor each frame rather
  -- than from a delta, so a fast drag that outruns the update cannot desync.
  local function ScrollToCursor()
    local visible = railScroll:GetHeight()
    local overflow = railContent:GetHeight() - visible
    if overflow <= 0 then return end
    local _, cursorY = GetCursorPosition()
    local scale = railBar:GetEffectiveScale()
    local top = railBar:GetTop()
    if not top then return end
    local fromTop = top - (cursorY / scale)
    railScroll:SetVerticalScroll(
      math.max(0, math.min(overflow, (fromTop / visible) * railContent:GetHeight() - visible / 2)))
    railBar:Update()
  end

  railBar:SetScript("OnMouseDown", function(self)
    self.dragging = true
    ScrollToCursor()
  end)
  railBar:SetScript("OnMouseUp", function(self) self.dragging = false end)
  railBar:SetScript("OnUpdate", function(self)
    if self.dragging then ScrollToCursor() end
  end)

  frame.railScroll = railScroll
  frame.railContent = railContent
  frame.railBar = railBar

  railScroll:HookScript("OnMouseWheel", function() railBar:Update() end)
  -- Resizing the window changes the track height and therefore the thumb's, and
  -- nothing else recalculates it -- RebuildRail only runs when the rule list
  -- changes, which dragging the grip is not.
  railScroll:HookScript("OnSizeChanged", function()
    railBar:Update()
    -- The scroll position can now be past the end of a shorter list.
    local overflow = math.max(0, railContent:GetHeight() - railScroll:GetHeight())
    if railScroll:GetVerticalScroll() > overflow then
      railScroll:SetVerticalScroll(overflow)
      railBar:Update()
    end
  end)

  -- One panel per page, all stacked in the same place to the right of the
  -- rail; SelectTab shows exactly one.
  for index = 1, PAGE_COUNT do
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", 8 + RAIL_W + 8, -52)
    panel:SetPoint("BOTTOMRIGHT", -8, 30)
    panel:Hide()
    tabPanels[index] = panel
  end

  -- Bottom-right grip, vertical only: width is locked because the rows
  -- inside each tab are placed at fixed pixel offsets, not a flexible
  -- layout, so a wider window would just leave empty space on the right.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    frame:StartSizing("BOTTOM")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    NS.db.uiSize = { height = frame:GetHeight() }
  end)

  window = frame
  -- After the assignment above, not before: RebuildRail reads `window` to
  -- find the rail's scroll content, so calling it any earlier is a silent
  -- no-op that leaves the rail empty until something else happens to rebuild
  -- it.
  RebuildRail()
  return frame
end

-- Lays out the whole rail: headings, pages, and a live row per rule. Re-run on
-- every rule change rather than patched, because priority numbers, shadow
-- warnings and ordering shift together and a partial update is how they drift.

-- The colour a rail row shows for a rule.
local function RuleSwatchColor(rule, kind)
  if kind == "border" then
    return (rule.border and rule.border.color) or NS.DefaultBorder().color
  end
  return rule.color or NS.DefaultColor()
end

function RebuildRail()
  if not window or not window.railContent then return end
  local content = window.railContent

  for _, f in ipairs(railPool.headers) do f:Hide() end
  for _, f in ipairs(railPool.items) do f:Hide() end
  for _, f in ipairs(railPool.headerBGs) do f:Hide() end
  for _, f in ipairs(railPool.switches) do f:Hide() end
  local nHeader, nItem = 0, 0
  local nHeaderBG, nSwitch = 0, 0

  local y = -8
  local first = true

  for _, entry in ipairs(NAV_LAYOUT) do
    if entry.group then
      if not first then y = y - 10 end

      -- A filled bar rather than bare text. With four levels in the rail, a
      -- heading that is only "slightly different text" reads as another
      -- entry; a band of its own reads as a division.
      nHeaderBG = nHeaderBG + 1
      local bar = railPool.headerBGs[nHeaderBG]
      if not bar then
        bar = content:CreateTexture(nil, "BACKGROUND")
        railPool.headerBGs[nHeaderBG] = bar
      end
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
      bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
      bar:SetHeight(RAIL_HEADER_H)
      bar:SetColorTexture(0.07, 0.07, 0.09, 1)
      bar:Show()

      nHeader = nHeader + 1
      local header = railPool.headers[nHeader]
      if not header then
        header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        railPool.headers[nHeader] = header
      end
      StyleText(header, 12)
      header:SetTextColor(RGBA(THEME.headerText))
      header:ClearAllPoints()
      -- Anchored by its LEFT edge to the bar's midline, which centres the text
      -- vertically no matter what size it is set to. TOPLEFT with a hand-tuned
      -- offset had to be re-tuned every time the font changed.
      header:SetPoint("LEFT", content, "TOPLEFT", NAV_GROUP_INDENT, y - RAIL_HEADER_H / 2)
      header:SetText(entry.group:upper())
      header:Show()

      -- The module's power switch, on its heading. It used to be the first
      -- checkbox inside the page, which meant you could not tell a module was
      -- off without opening it -- and "Health Coloring is off" explains far
      -- more than any single setting inside it.
      if entry.module and MODULE_SWITCH[entry.module] then
        nSwitch = nSwitch + 1
        -- The getter reads switch.spec rather than closing over the spec
        -- directly: these are pooled, so a closure made on the first rebuild
        -- would keep reporting the first module's state forever.
        local switch
        switch = railPool.switches[nSwitch]
        if not switch then
          switch = ToggleSwitch(content,
            -- `switch` is still nil while the constructor runs: it calls
            -- Paint(), which calls this getter, before the assignment below
            -- has completed. Same trap the preview checkboxes guard against.
            function()
              return switch ~= nil and switch.spec ~= nil and switch.spec.get() or false
            end,
            function() end)
          railPool.switches[nSwitch] = switch
        end
        switch.spec = MODULE_SWITCH[entry.module]
        -- The heading's own gold, so the switch reads as belonging to that
        -- heading rather than as one more green control in the list. Set on
        -- every rebuild, not at construction: the pool is shared with the
        -- row-level switches below, and a recycled widget would otherwise keep
        -- whichever accent it was first given.
        switch:SetAccent({ RGBA(THEME.headerText) })
        switch:SetScript("OnClick", function(self)
          self.spec.set(not self.spec.get())
          self.Refresh()
          -- apply, when the module defines one: not everything on this rail
          -- draws on a nameplate, and a rig rebuild for a tooltip setting is
          -- work with no possible effect.
          if self.spec.apply then self.spec.apply() else Structural() end
        end)
        switch.Refresh()
        switch:ClearAllPoints()
        -- Same midline as the heading text, so the two read as one row.
        Tip(switch, entry.group, entry.tip and TIPS[entry.tip])
        switch:SetPoint("RIGHT", content, "TOPRIGHT", -8, y - RAIL_HEADER_H / 2)
        switch:SetFrameLevel(content:GetFrameLevel() + 6)
        switch:Show()
      end

      y = y - (RAIL_HEADER_H + 4)

    else
      nItem = nItem + 1
      local item = railPool.items[nItem]
      if not item then
        item = NavItem(content, entry.label, NAV_ITEM_INDENT, function() end)
        railPool.items[nItem] = item
      end
      item.label:SetText(entry.label)
      -- Rail-anchored: a cursor tooltip here would cover the list itself.
      Tip(item, entry.label, entry.tip and TIPS[entry.tip])
      local index = entry.index
      item:SetScript("OnClick", function() SelectTab(index) end)
      -- Every entry is a plain page link now: no entry collapses, because
      -- nothing in the rail has children left to hide.
      item:SetSubheader(false)
      item:SetHeight(24)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", 0, y)
      item:SetPoint("TOPRIGHT", 0, y)
      tabButtons[index] = item
      item:Show()

      -- A module that is one page rather than a group gets its switch here, on
      -- the row itself. Parented to the ITEM and raised above it: the row is a
      -- full-width button, so a switch left at the same frame level loses the
      -- hit test to it and clicking the switch would merely open the page.
      if entry.module and MODULE_SWITCH[entry.module] then
        nSwitch = nSwitch + 1
        local switch
        switch = railPool.switches[nSwitch]
        if not switch then
          switch = ToggleSwitch(content,
            function()
              return switch ~= nil and switch.spec ~= nil and switch.spec.get() or false
            end,
            function() end)
          railPool.switches[nSwitch] = switch
        end
        switch.spec = MODULE_SWITCH[entry.module]
        -- Blue: not the headings' gold, and not the green the module switches
        -- use either, so a row-level switch does not read as one of those.
        switch:SetAccent({ 0.34, 0.60, 0.92 })
        switch:SetScript("OnClick", function(self)
          self.spec.set(not self.spec.get())
          self.Refresh()
          -- apply, when the module defines one: not everything on this rail
          -- draws on a nameplate, and a rig rebuild for a tooltip setting is
          -- work with no possible effect.
          if self.spec.apply then self.spec.apply() else Structural() end
        end)
        switch.Refresh()
        switch:ClearAllPoints()
        Tip(switch, entry.label, entry.switchTip and TIPS[entry.switchTip])
        switch:SetPoint("RIGHT", item, "RIGHT", -8, 0)
        switch:SetFrameLevel(item:GetFrameLevel() + 4)
        switch:Show()
      end

      y = y - 24
    end
    first = false
  end

  local contentHeight = math.max(1, -y + 8)
  content:SetHeight(contentHeight)

  -- Grow the window to fit the rail, unless the user has chosen a height.
  --
  -- The rail's length is however many rules you have plus whichever sections
  -- are open, so a fixed default can only ever be right for one of those. It
  -- stops the moment someone drags the resize grip.
  --
  -- Only ever GROWS: shrinking to hug a short rail would fight the page.
  if not (NS.db.uiSize and NS.db.uiSize.height) then
    -- 52 above the rail for the title bar, 30 below it for the footer.
    local wanted = math.min(WINDOW_MAX_H, math.max(WINDOW_MIN_H, contentHeight + 82))
    if wanted > window:GetHeight() then
      window:SetHeight(wanted)
    end
  end

  if window.railBar then window.railBar:Update() end
end

-- Repaints every existing table swatch from the rules themselves, without
-- going through Structural().
--
-- Colour pickers call this on every frame of a drag, which a full rebuild
-- could not survive, and the row already knows which rule it shows, so only
-- the texture is stale.
--
-- The rail half of this is gone with the rail's rule rows: there is one place
-- a rule's colour appears in the window now.
local function RefreshRailColors()
  for _, listKey in ipairs({ "health", "border" }) do
    for _, row in ipairs(pageRows[listKey] or {}) do
      if row.rule and row:IsShown() then
        local colour = RuleSwatchColor(row.rule, listKey)
        row.swatch:SetColorTexture(colour.r, colour.g, colour.b, 1)
      end
    end
  end
end

-- Lays the test-column buttons out as one block, centred against the preview
-- plate. Top-aligning left the group floating with all the slack underneath.
--
-- The column is as tall as its page's stage, read from the frame rather than
-- the constant -- the Aura Icons pages build a taller one.
local TEST_BTN_GAP = 6

local function StackTestButtons(column, buttons)
  -- Hidden buttons are skipped rather than laid out invisibly: the whole
  -- point of centring is that the group is centred, and a reserved gap for
  -- something not on screen would push the visible ones off-centre.
  local shown = {}
  for _, button in ipairs(buttons) do
    if button and button:IsShown() then table.insert(shown, button) end
  end
  buttons = shown

  local count = #buttons
  if count == 0 then return end
  local total = count * CTRL_H + (count - 1) * TEST_BTN_GAP
  local top = math.max(0, (column:GetHeight() - total) / 2)
  for index, button in ipairs(buttons) do
    local y = -(top + (index - 1) * (CTRL_H + TEST_BTN_GAP))
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", column, "TOPLEFT", 0, y)
    button:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, y)
  end
end

-- Fixed head (module toggle + preview) with a scrolling body beneath.
--
-- enableLabel nil = no module toggle. The Global Settings pages are not
-- modules, but still want the preview stage -- every one of them changes how
-- the bar is drawn.
local function BuildTabFrame(panel, enableLabel, enableGet, enableSet, stageHeight)
  -- Per page, because only the Aura Icons pages need the extra room. Stored on
  -- the panel so the pages' own SetHeadHeight arithmetic reads the same number
  -- this frame was built with instead of the module-wide default.
  stageHeight = stageHeight or STAGE_H
  -- The preview is a CollapsibleSection like every other section on the page,
  -- just in the warm palette. It used to be three hand-built frames -- a
  -- border box, a header bar and a body -- which is exactly why its header sat
  -- outside the border and its edges never matched the sections beneath it.
  local section = CollapsibleSection(panel, "previewTest", "Preview & Test",
    "a simulated plate - your real nameplates may differ", PREVIEW_PALETTE)
  section:SetPoint("TOPLEFT", BODY_X, 0)
  section:SetWidth(BODY_W)
  panel.previewSection = section
  panel.previewBar = section.header
  Tip(section.header, "Preview & Test", TIPS.previewSection)

  -- Pages put their controls in the section's content and measure from its
  -- top, which is the same origin the old hand-built head gave them.
  local head = section.content

  -- enableLabel nil = no module toggle on this page; the module switch lives
  -- on its rail heading. Pages that pass one still get it.
  local stageTop = 6
  if enableLabel then
    stageTop = 32
    head.enable = Checkbox(head, enableGet, enableSet)
    head.enable:SetPoint("TOPLEFT", HEAD_PAD, -4)
    head.enableLabel = Label(head, enableLabel, "GameFontNormal")
    head.enableLabel:SetPoint("LEFT", head.enable, "RIGHT", 6, 0)
  end
  head.stageTop = stageTop

  -- The content splits in two: the plate on the left, the test controls on
  -- the right. One shows what a rule will look like, the other paints it onto
  -- real nameplates, and stacking them made the second read as a footnote.
  head.testColumn = CreateFrame("Frame", nil, head)
  head.testColumn:SetPoint("TOPRIGHT", -HEAD_PAD, -stageTop)
  head.testColumn:SetWidth(TEST_COL_W)
  head.testColumn:SetHeight(stageHeight)

  -- Threat and Target/Focus have no debuff to tick, so the simulate row below
  -- the plate cannot reach them: they are decided by a mob's threat status and
  -- by who you have targeted, neither of which the preview can pretend at by
  -- ticking a spell. These two say "show me that state instead".
  --
  -- Dropdowns rather than tick boxes, because the states are exclusive in the
  -- game: a mob reports ONE threat status, and a unit is your target or your
  -- focus, not both at once. A list that holds one key cannot be asked to show
  -- two colours that could never appear together.
  --
  -- Between the two, the engine's own order decides: threat covers
  -- target/focus, which covers whichever rule won.
  head.threatPreview = Dropdown(head.testColumn, TEST_COL_W, NS.StageThreatEntries,
    function() return NS.stagePreview.threat or false end,
    function(value)
      NS.stagePreview.threat = value or nil
      RefreshPreviews()
    end)
  Tip(head.threatPreview, "Preview a threat state",
    "Paints the plate above with one of your threat colours.\n\nThe preview plate only -- your real nameplates are untouched, and nothing here is saved.")

  head.markPreview = Dropdown(head.testColumn, TEST_COL_W, NS.StageMarkEntries,
    function() return NS.stagePreview.mark or false end,
    function(value)
      NS.stagePreview.mark = value or nil
      RefreshPreviews()
    end)
  -- Placed here, not left to the page.
  --
  -- Only the rule page ever called StackTestButtons, so a control created in
  -- this function and positioned nowhere else simply never appeared -- which
  -- is what happened to these two on the Color Rules page. Pages that add
  -- their own test buttons re-stack the whole column and these come along.
  -- Test and Test All, on every page that has this head.
  --
  -- These were built only by the rule editor -- the page that was retired
  -- when rules moved in-place -- so the whole feature left with it: there was
  -- no way to paint your real nameplates from the Color Rules page, which is
  -- now the page you spend your time on.
  head.testButton = TestModeButton(head.testColumn, false)
  head.testAllButton = TestModeButton(head.testColumn, true)

  StackTestButtons(head.testColumn, { head.threatPreview, head.markPreview,
    head.testButton, head.testAllButton })

  Tip(head.markPreview, "Preview target or focus",
    "Paints the plate above as though it were your target or your focus.\n\nThreat outranks it, the same way it does on a real plate.")

  head.stage = BuildStage(head, stageHeight)
  head.stage:SetPoint("TOPLEFT", HEAD_PAD, -stageTop)
  head.stage:SetPoint("TOPRIGHT", head.testColumn, "TOPLEFT", -10, 0)

  -- No Blizzard template: EnableMouseWheel/OnMouseWheel and the scrollbar
  -- itself are built by hand in BuildScrollBar, to match every other widget
  -- in this window.
  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPRIGHT", -12, 0)
  scroll:SetPoint("BOTTOMLEFT", 4, 4)
  scroll:SetPoint("TOPLEFT", 4, 0)

  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(716, 600)
  scroll:SetScrollChild(body)
  body.scrollBar = BuildScrollBar(scroll)

  panel.head = head
  panel.scroll = scroll
  panel.body = body

  -- Pages pass the height their content needs; the section adds its own
  -- header and padding, so collapsing is ordinary section behaviour.

  -- Re-anchors the scrolling body under the preview, whatever height it has.
  --
  -- Driven by the section's own resize notification, NOT only SetHeadHeight:
  -- collapsing the preview fires Resize with no page code running, and
  -- Options_RebuildAll does not refresh previews -- so any page that did not
  -- happen to call RefreshPreview was left with a page-sized hole.
  local function ReanchorBody()
    local top = section:GetHeight()
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 4, -top - 6)
    scroll:SetPoint("TOPRIGHT", -12, -top - 6)
    scroll:SetPoint("BOTTOMLEFT", 4, 4)
  end
  section.onResize = ReanchorBody
  panel.ReanchorBody = ReanchorBody

  function panel:SetHeadHeight(height)
    panel.headHeight = height
    section:Resize(height) -- fires onResize, which re-anchors
  end

  panel.stageHeight = stageHeight
  panel:SetHeadHeight(stageTop + stageHeight + 8)
  return panel
end

-------------------------------------------------------------------------------
-- Tab 1 — nameplate colors
-------------------------------------------------------------------------------

-- The preview is a pure simulation: it never touches an aura container and
-- never asks the game anything, it answers "given exactly these debuffs, which
-- rule wins" using the engine's ordering.
--
-- It used to disagree with live plates because preview.active was never
-- pruned: a tick for a spell that later left every rule stayed set forever, so
-- "is anything ticked" said yes when nothing visibly was. Pruning first makes
-- what is on screen the whole state.
local function PrunedPreviewState()
  -- BOTH lists. preview.active is shared by the health tab, the border tab
  -- and test mode, so pruning against health rules alone deleted any debuff
  -- only a border rule used -- the tick vanished the moment the health
  -- preview refreshed.
  local valid = {}
  for _, list in ipairs({ NS.db.tints.rules or {} }) do
    for _, rule in ipairs(list) do
      for _, c in ipairs(rule.conditions or {}) do
        valid[c.spellID] = true
      end
    end
  end
  for spellID in pairs(preview.active) do
    if not valid[spellID] then preview.active[spellID] = nil end
  end
  return preview.active
end

-- Returns winner, matches, tickedCount. `matches` is every rule that would
-- fire, in priority order, so the verdict can explain itself instead of just
-- showing a colour and leaving you to work out why.
local function EvaluatePreview()
  local active = PrunedPreviewState()

  local ticked = 0
  for _, on in pairs(active) do
    if on then ticked = ticked + 1 end
  end

  -- GetOrderedRules is what Tints.lua builds from, so preview and plate
  -- priority cannot drift.
  --
  -- Missing rules are excluded: they never paint the bar body, so letting one
  -- place first would report a winner whose colour is nowhere on the bar.
  -- Load conditions are deliberately IGNORED here: the preview answers what
  -- the rule looks like, and where you happen to be standing while editing it
  -- is not part of that.
  local matches = {}
  for _, rule in ipairs(NS.GetOrderedRules(true)) do
    if not rule.showWhenMissing then
      local all = true
      for _, c in ipairs(rule.conditions) do
        if not active[c.spellID] then all = false break end
      end
      if all then table.insert(matches, rule) end
    end
  end

  return matches[1], matches, ticked
end


-- Every spell the simulate row needs a checkbox for. When the previews are
-- combined the other list's debuffs are included too -- otherwise there would
-- be no way to tick the debuff a border rule needs, and "also show borders"
-- would look broken.
local function RuleSpells()
  local seen, list = {}, {}
  -- One list holds both halves, so combining the two previews no longer means
  -- reading a second list -- it means not filtering this one.
  local sources = { NS.db.tints.rules }
  for _, src in ipairs(sources) do
  for _, rule in ipairs(src) do
    for _, c in ipairs(rule.conditions or {}) do
      if not seen[c.spellID] then seen[c.spellID] = true; table.insert(list, c.spellID) end
    end
  end
  end
  return list
end

-- Style block for the expanded rule. Built once and repositioned, since only
-- one rule is ever open. Lives in the Edit panel rather than the row --
-- thickness needs a slider and the row is already six columns wide.

-- Re-checks every rig's target/focus gating without touching a unit binding
-- or rebuilding, so it can run straight from a checkbox click.
local function ApplyGating()
  for _, rig in pairs(NS.rigs) do
    NS.SetTintsUnit(rig)
  end
  if statusText then statusText:SetText("|cff55dd55Settings Saved|r") end
end

-- Patterns for the TEXTURE overlay: "Bar's own art" (nil) first, then the
-- bundled tiled library, each with its own thumbnail. Lives here rather than
-- inline so the appearance panel and anything else wanting the same list
-- share one definition.
local function FillTextureEntries()
  local list = { { text = "Bar's own art", value = nil } }
  for _, t in ipairs(NS.FillTextures or {}) do
    table.insert(list, { text = t.label, value = t.key, icon = t.path })
  end
  return list
end

-- Bar textures for the SOLID overlay, from LibSharedMedia -- whatever the
-- user already has installed (SharedMedia, ElvUI, WeakAuras, Plater and so on
-- all register into the same table), so this ships nothing and grows with
-- their setup. "Flat color" is the nil entry and stays first: it is the
-- original behaviour of a solid fill and has to remain one click away.
local function BarTextureEntries()
  local list = { { text = "Flat color", value = nil } }
  for _, t in ipairs(NS.LSMStatusbars and NS.LSMStatusbars() or {}) do
    table.insert(list, { text = t.name, value = t.name, icon = t.path })
  end
  return list
end

-- Everything about how a rule LOOKS, as opposed to what it requires. Behind
-- its own button on the row rather than sharing space with the debuff list.
--
-- isBorder picks the extra controls: border shape for the border list,
-- fill/texture for the bar list. Colour and target/focus gating apply to both.

-- Adding a debuff to a rule, shared by the rule tables and the editor. Was a
-- local inside BuildHealthTab, which the editor could not reach -- and a
-- second copy would have been a second place for the checks to drift.
local function RuleConditionLimit(rule)
  if not rule then return 1 end
  -- A missing rule is single-debuff and cannot be raised. Its rank in the
  -- ladder already spends a chain level on every rule above it plus one on its
  -- own debuff, and a second condition would need another interleaved into a
  -- sublevel budget with no room for it (see Tints.lua).
  if rule.showWhenMissing then return NS.MAX_MISSING_CONDITIONS or 1 end
  -- This used to gate a rule to one debuff unless it carried wantsCombo, set
  -- by whichever rail row created it -- a rule's shape was fixed at creation.
  -- With one creation row there is nothing to remember. wantsCombo may still
  -- sit in saved profiles and is ignored everywhere.
  return NS.MAX_RULE_CONDITIONS
end

local function AddConditionTo(rule, input, sortList)
  if not rule or not input then return end
  local spellID = ResolveAndReport(input)
  if not spellID then return end
  -- Typed once, offered from then on. Someone who knows the ID of a debuff
  -- knows something the Cooldown Manager does not, and making them look it up
  -- twice is the addon forgetting on their behalf.
  if NS.LearnSpell then NS.LearnSpell(spellID) end
  for _, cond in ipairs(rule.conditions or {}) do
    if cond.spellID == spellID then return end
  end
  local limit = RuleConditionLimit(rule)
  if #rule.conditions >= limit then
    NS.Print(rule.showWhenMissing
      and "A rule that shows when MISSING can only have one debuff."
      or ("A rule can require at most %d debuffs."):format(limit))
    return
  end

  local function Commit()
    table.insert(rule.conditions, { spellID = spellID })
    -- Keep specific rules above general ones without the user thinking.
    -- Identity survives the reshuffle, so the rule stays open.
    NS.SortRules(sortList)
    Structural()
  end

  -- No cost warning any more. A second debuff used to multiply a rule's
  -- textures by ten, because containers pooled ten buttons each and the rule
  -- had to cover every pairing. Aura slots pool one, so a combo costs one
  -- texture and one frame.
  Commit()
end

-- part selects which half gets built:
--   "all"         both, each under its own small heading
--   "appearance"  colour, fill, texture, border shape
--   "visibility"  target/focus gating
--
-- The rule editor asks for the split forms because each half is its own
-- collapsible section there.
--
-- Both halves are always CREATED and merely hidden, so p.Refresh never has to
-- ask which widgets this instance has.
local function BuildStylePanel(parent, isBorder, part)
  part = part or "all"
  local split = part ~= "all"

  local p = CreateFrame("Frame", nil, parent)
  local height
  if part == "visibility" then
    height = 34
  elseif part == "appearance" then
    -- isBorder raised 62 -> 82: the border-shape block below Color moved down
    -- 20px to stop overlapping it (see that block for why).
    height = isBorder and 82 or 172
  else
    -- Room for a three-line wrap on the texture-conflict warning plus the
    -- missing-health cover row below it.

    -- Tall enough for the missing-health colour row even when hidden: a panel
    -- that resizes as you tick a box shoves every rule below it up and down.
    height = isBorder and 116 or 220
  end
  p:SetSize(660, height)

  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints()
  p.bg:SetColorTexture(1, 1, 1, 0.025)
  -- Inside a collapsible section the section already draws the card. A second
  -- wash on top of it just makes one band lighter than the rest of it.
  if split then p.bg:Hide() end

  local function Rule() return expandedRule end

  -- One container per half. Showing both, they sit at the origin and every
  -- offset below is exactly the one it has always been; split, the container
  -- slides up by however much the dropped heading was occupying, so the same
  -- offsets keep working.
  local APPEAR_SHIFT = split and 16 or 0
  local ap = CreateFrame("Frame", nil, p)
  ap:SetPoint("TOPLEFT", 0, APPEAR_SHIFT)
  ap:SetPoint("BOTTOMRIGHT")
  local vp = CreateFrame("Frame", nil, p)
  vp:SetPoint("TOPLEFT", 0, split and (isBorder and 54 or 180) or 0)
  vp:SetPoint("BOTTOMRIGHT")
  p.appearBox, p.visBox = ap, vp
  if part == "appearance" then vp:Hide() end
  if part == "visibility" then ap:Hide() end

  -- Grouped, with a heading each. Everything used to sit in one undivided
  -- block, which put "show on target" -- a rule about WHEN this rule applies
  -- -- on the same line as its colour. They are different questions and now
  -- read as different questions.
  p.appearHeader = Label(ap, "APPEARANCE", "GameFontNormal")
  p.appearHeader:SetPoint("TOPLEFT", 12, -6)
  StyleText(p.appearHeader, 10)
  p.appearHeader:SetTextColor(RGBA(THEME.headerText))
  p.appearHeader:SetShown(not split)

  p.colorLabel = Dim(ap, "Color")
  p.colorLabel:SetPoint("TOPLEFT", 14, -26)
  TipLabel(p.colorLabel, "Color", TIPS.ruleColor)
  p.swatch = ColorSwatch(ap,
    function()
      local r = Rule()
      if not r then return NS.DefaultColor() end
      if isBorder then return (r.border and r.border.color) or NS.DefaultBorder().color end
      return r.color or NS.DefaultColor()
    end,
    function(cr, cg, cb, ca)
      local r = Rule()
      if not r then return end
      if isBorder then
        r.border = r.border or NS.DefaultBorder()
        r.border.color = { r = cr, g = cg, b = cb, a = ca }
      else
        r.color = { r = cr, g = cg, b = cb, a = ca }
      end
      NS.ApplyTintColors()
      RefreshPreviews()
      -- The rail carries a swatch per rule, and it is on screen while you are
      -- dragging this picker. Repainting just the swatches, rather than
      -- rebuilding the rail, keeps that cheap enough to run per frame.
      RefreshRailColors()
    end)
  p.swatch:SetPoint("TOPLEFT", 58, -24)
  Tip(p.swatch, "Color", TIPS.ruleColor)

  -- Which STATE this rule fires on, on the colour row because it decides what
  -- that colour means. Everything below applies either way.
  --
  -- Both lists, by different machinery: a bar rule can be built either way, a
  -- border rule only by displacement. A missing border on occlude is dropped
  -- at build time and says so in /pt status.
  do
    p.whenLabel = Dim(ap, "Show when")
    p.whenLabel:SetPoint("TOPLEFT", 224, -26)
    TipLabel(p.whenLabel, "Show when", TIPS.showWhen)
    -- Structural: it changes which list the rule is built from and what
    -- objects exist for it, not just what colour they are.
    p.whenDrop = Dropdown(ap, 220, {
      { text = "Debuff is present", value = false },
      { text = "Debuff is MISSING", value = true },
    },
    function()
      local r = Rule()
      return (r and r.showWhenMissing) and true or false
    end,
    function(v)
      local r = Rule()
      if not r then return end
      -- A missing rule is single-debuff by construction: its rank in the
      -- ladder already spends a chain level per rule above it, and a second
      -- condition needs another interleaved into a sublevel budget with no
      -- room for it. Refused rather than silently dropping one of the two
      -- debuffs the user deliberately picked.
      if v and #(r.conditions or {}) > (NS.MAX_MISSING_CONDITIONS or 1) then
        NS.Print(("A rule that shows when MISSING can only have %d debuff. "
          .. "Remove one first."):format(NS.MAX_MISSING_CONDITIONS or 1))
        p.whenDrop.Refresh()
        return
      end
      r.showWhenMissing = v and true or false
      -- Structural already rebuilds the window, which repaints the row
      -- summary's and the rail's MISSING prefix and re-runs p.Refresh.
      Structural()
    end)
    p.whenDrop:SetPoint("TOPLEFT", 280, -24)
    Tip(p.whenDrop, "Show when", TIPS.showWhen)

    -- Same row as Show when, in the width left over after its dropdown --
    -- not a row of its own, since this panel is already tight and the two
    -- questions ("which state" and "when during that state") belong together.
    -- Shown only in MISSING mode (see p.Refresh): a presence rule has no
    -- "out of combat" state to hold anything off of.
    p.combatOnlyCheck = Checkbox(ap,
      function()
        local r = Rule()
        return r and r.missingCombatOnly or false
      end,
      function(v)
        local r = Rule()
        if r then r.missingCombatOnly = v; Structural() end
      end)
    p.combatOnlyCheck:SetPoint("TOPLEFT", 512, -24)
    Tip(p.combatOnlyCheck, "In combat only", TIPS.missingCombatOnly)
    p.combatOnlyLabel = Label(ap, "In combat")
    p.combatOnlyLabel:SetPoint("LEFT", p.combatOnlyCheck, "RIGHT", 6, 0)
    TipLabel(p.combatOnlyLabel, "In combat only", TIPS.missingCombatOnly)

    -- Opacity advisory. A presence tint fires occasionally; a missing tint is
    -- lit BY DEFAULT on every untouched mob, so the same alpha reads
    -- completely differently. Advisory only.
    --
    -- Bar rules only: both notes it carries are about a WASH, and a border is
    -- a few pixels at the bar's edge whose gate is genuinely per rule.
    if not isBorder then
      p.missingAlphaWarn = ap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      StyleText(p.missingAlphaWarn, 11, "NONE")
      p.missingAlphaWarn:SetPoint("TOPLEFT", 14, -160)
      p.missingAlphaWarn:SetPoint("TOPRIGHT", -14, -160)
      p.missingAlphaWarn:SetJustifyH("LEFT")
      p.missingAlphaWarn:SetWordWrap(true)
      p.missingAlphaWarn:SetTextColor(1, 0.55, 0.15)
    end
  end

  -- Checked (the default) is "show here too, same as any other rule" -- both
  -- default true in NS.NormaliseRule, so an unticked box is the exception
  -- someone deliberately carved out, not the common case.
  p.targetCheck = Checkbox(vp,
    function()
      local r = Rule()
      return not r or r.showOnTarget ~= false
    end,
    function(v)
      local r = Rule()
      if r then r.showOnTarget = v; ApplyGating() end
    end)
  p.visHeader = Label(vp, "VISIBILITY", "GameFontNormal")
  p.visHeader:SetPoint("TOPLEFT", 12, isBorder and -46 or -172)
  StyleText(p.visHeader, 10)
  p.visHeader:SetTextColor(RGBA(THEME.headerText))
  p.visHeader:SetShown(not split)

  p.targetCheck:SetPoint("TOPLEFT", 14, isBorder and -64 or -190)
  Tip(p.targetCheck, "Show on target", TIPS.showOnTarget)
  p.targetLabel = Label(vp, "Show on target")
  p.targetLabel:SetPoint("LEFT", p.targetCheck, "RIGHT", 6, 0)
  TipLabel(p.targetLabel, "Show on target", TIPS.showOnTarget)

  p.focusCheck = Checkbox(vp,
    function()
      local r = Rule()
      return not r or r.showOnFocus ~= false
    end,
    function(v)
      local r = Rule()
      if r then r.showOnFocus = v; ApplyGating() end
    end)
  p.focusCheck:SetPoint("LEFT", p.targetLabel, "RIGHT", 28, 0)
  Tip(p.focusCheck, "Show on focus", TIPS.showOnFocus)
  p.focusLabel = Label(vp, "Show on focus")
  p.focusLabel:SetPoint("LEFT", p.focusCheck, "RIGHT", 6, 0)
  TipLabel(p.focusLabel, "Show on focus", TIPS.showOnFocus)

  if not isBorder then
    -- Fill style: a flat colour, or the host bar's own art (whatever pattern
    -- the nameplate addon draws) tinted by this rule's colour instead of
    -- replaced by it. Live, not Restyle: the texture objects already exist,
    -- this only changes what gets painted onto them.
    p.fillLabel = Dim(ap, "Fill")
    p.fillLabel:SetPoint("TOPLEFT", 14, -58)
    TipLabel(p.fillLabel, "Fill", TIPS.fillStyle)
    p.fillStyle = Dropdown(ap, 150, {
      { text = "Solid Overlay", value = "solid" },
      { text = "Texture Overlay", value = "texture" },
    },
    function()
      local r = Rule()
      return (r and r.fillStyle) or "solid"
    end,
    function(v)
      local r = Rule()
      if r then
        r.fillStyle = v
        -- Switching to Texture Overlay for the first time lands on a real
        -- pattern rather than "Bar's own art" -- the nil entry, and what an
        -- untouched rule already shows, so picking Texture Overlay would
        -- appear to do nothing.
        --
        -- Guarded by fillTexturePicked, not "is fillTexture nil": nil is a
        -- legitimate choice, so without the flag anyone who deliberately
        -- picked it would have it replaced on every style toggle.
        if v == "texture" and not r.fillTexturePicked and r.fillTexture == nil then
          r.fillTexture = "stripes-spread"
        end
        Live()
        NS.Options_RebuildAll()
      end
    end)
    p.fillStyle:SetPoint("TOPLEFT", 60, -56)
    Tip(p.fillStyle, "Fill", TIPS.fillStyle)

    -- Two pickers sharing one slot, one per fill style: Texture Overlay tiles
    -- a bundled pattern, Solid Overlay stretches an LSM bar texture. Only the
    -- matching one is shown, or a rule would be offered choices that do
    -- nothing in its current mode.
    --
    -- Separate rule fields too, so switching style keeps both selections.
    p.textureLabel = Dim(ap, "Texture")
    p.textureLabel:SetPoint("TOPLEFT", 224, -58)
    TipLabel(p.textureLabel, "Texture", TIPS.fillTexture)
    p.textureDrop = Dropdown(ap, 220, FillTextureEntries,
      function()
        local r = Rule()
        return r and r.fillTexture
      end,
      function(v)
        local r = Rule()
        if r then
          r.fillTexture = v
          -- From here on this rule's pattern is the user's, including a
          -- deliberate "Bar's own art" (nil) -- see the fill style handler.
          r.fillTexturePicked = true
          Live()
        end
      end)
    p.textureDrop:SetPoint("TOPLEFT", 280, -56)
    Tip(p.textureDrop, "Texture", TIPS.fillTexture)

    p.barTexLabel = Dim(ap, "Texture")
    p.barTexLabel:SetPoint("TOPLEFT", 224, -58)
    TipLabel(p.barTexLabel, "Texture", TIPS.barTexture)
    p.barTexDrop = Dropdown(ap, 220, BarTextureEntries,
      function()
        local r = Rule()
        return r and r.barTexture
      end,
      function(v)
        local r = Rule()
        if r then
          r.barTexture = v
          Live()
        end
      end)
    p.barTexDrop:SetPoint("TOPLEFT", 280, -56)
    Tip(p.barTexDrop, "Texture", TIPS.barTexture)

    -- OUTLINE rather than the plain font: this is the one warning here that
    -- needs to read as urgent, since it describes a conflict sourced from a
    -- completely different addon with nothing here to point at the cause.
    p.textureWarning = ap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleText(p.textureWarning, 12, "OUTLINE")
    p.textureWarning:SetPoint("TOPLEFT", 14, -86)
    p.textureWarning:SetPoint("TOPRIGHT", -14, -86)
    p.textureWarning:SetJustifyH("LEFT")
    p.textureWarning:SetWordWrap(true)
    p.textureWarning:SetText(
      "WARNING: a Colored Texture can visually conflict with target/focus highlight "
        .. "art some nameplate addons (e.g. EllesmereUI) already draw over the health "
        .. "bar -- the two are not aware of each other and will overlap.")
    p.textureWarning:SetTextColor(1, 0.15, 0.15)

    -- Opaque cover for the bar's MISSING side. Structural, not Live: this is
    -- a new texture object, not a recolour of one that already exists.
    p.missingCoverCheck = Checkbox(ap,
      function()
        local r = Rule()
        return r and r.missingCover or false
      end,
      function(v)
        local r = Rule()
        if r then r.missingCover = v; Structural() end
      end)
    p.missingCoverCheck:SetPoint("TOPLEFT", 14, -120)
    Tip(p.missingCoverCheck, "Hide texture over missing health", TIPS.missingCover)
    p.missingCoverLabel = Label(ap, "Hide texture over missing health")
    p.missingCoverLabel:SetPoint("LEFT", p.missingCoverCheck, "RIGHT", 6, 0)
    TipLabel(p.missingCoverLabel, "Hide texture over missing health", TIPS.missingCover)

    -- Opaque and drawn above everything else this addon puts on the bar, so
    -- it does the same thing to any OTHER addon's overlay art that a
    -- Colored Texture fill does to target/focus highlights (see the warning
    -- above) -- just guaranteed rather than incidental, since covering
    -- exactly that is the point of the option.
    p.missingCoverWarn = ap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleText(p.missingCoverWarn, 11, "NONE")
    p.missingCoverWarn:SetPoint("LEFT", p.missingCoverLabel, "RIGHT", 10, 0)
    p.missingCoverWarn:SetText("(overwrites other addons' overlays on the missing health side)")
    p.missingCoverWarn:SetTextColor(1, 0.55, 0.15)

    -- The colour directly under the checkbox that turns it on.
    --
    -- Shown only while this rule uses the option, because it is not a per-rule
    -- setting: every rule that covers missing health shares one colour, and
    -- the same swatch is on Global Settings > Effects. The label has to say so
    -- or this reads as a rule setting that changes other rules.
    --
    -- Laid out as a ROW matching the tick box above: control first at the same
    -- x, then its name. The swatch is exactly a tick box's size.
    p.missingColorLabel = Label(ap, "Color")
    p.missingColor = ColorSwatch(ap,
      function()
        return (NS.MissingCoverColor and NS.MissingCoverColor())
          or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
      end,
      function(r, g, b, a)
        NS.db.tints.missingCoverColor = { r = r, g = g, b = b, a = a }
        if NS.ApplyTintColors then NS.ApplyTintColors() end
        RefreshPreviews()
      end)
    p.missingColor:SetPoint("TOPLEFT", 14, -144)
    Tip(p.missingColor, "Color", TIPS.missingColor)
    p.missingColorLabel:SetPoint("LEFT", p.missingColor, "RIGHT", 6, 0)
    TipLabel(p.missingColorLabel, "Color", TIPS.missingColor)
    p.missingColorNote = Dim(ap, "(shared by every rule that covers missing health)")
    p.missingColorNote:SetPoint("LEFT", p.missingColorLabel, "RIGHT", 10, 0)
  end

  if isBorder then
    -- 20px lower than it used to be. At the old offset "Border shape" started
    -- 12px under the Color row -- both Dim() labels at x=14, 11pt -- and the
    -- two rendered on top of each other. Fill, on the non-border side, keeps a
    -- 32px gap under Color; this matches it.
    p.growLabel = Dim(ap, "Grows")
    p.growLabel:SetPoint("TOPLEFT", 130, -86)
    TipLabel(p.growLabel, "Grows", TIPS.borderGrow)
    p.title = Dim(ap, "Border shape")
    p.title:SetPoint("TOPLEFT", 14, -58)

    p.thickLabel = Dim(ap, "Thickness")
    p.thickLabel:SetPoint("TOPLEFT", 130, -58)
    TipLabel(p.thickLabel, "Thickness", TIPS.borderThick)
    -- Structural, not Live: thickness is baked into each edge texture's size
    -- when it is created, so changing it needs the rule rebuilt.
    p.thickness = Slider(ap, 80, 1, 8, 7,
      function()
        local r = Rule()
        return (r and r.border and r.border.thickness) or 2
      end,
      function(v)
        local r = Rule()
        if r then
          r.border = r.border or NS.DefaultBorder()
          r.border.thickness = v
          Structural()
        end
      end)
    p.thickness:SetPoint("TOPLEFT", 190, -56)
    Tip(p.thickness, "Thickness", TIPS.borderThick)

    p.grow = Dropdown(ap, 96, {
      { text = "Inside bar", value = "IN" },
      { text = "Outside bar", value = "OUT" },
    },
    function()
      local r = Rule()
      return (r and r.border and r.border.grow) or "OUT"
    end,
    function(v)
      local r = Rule()
      if r then
        r.border = r.border or NS.DefaultBorder()
        r.border.grow = v
        Structural()
      end
    end)
    p.grow:SetPoint("TOPLEFT", 190, -84)
    Tip(p.grow, "Grows", TIPS.borderGrow)

    p.padLabel = Dim(ap, "Gap")
    p.padLabel:SetPoint("TOPLEFT", 360, -58)
    TipLabel(p.padLabel, "Gap", TIPS.borderGap)
    -- Distance between the bar edge and the border, independent of thickness.
    p.padding = Slider(ap, 80, 0, 12, 12,
      function()
        local r = Rule()
        return (r and r.border and r.border.padding) or 0
      end,
      function(v)
        local r = Rule()
        if r then
          r.border = r.border or NS.DefaultBorder()
          r.border.padding = v
          Structural()
        end
      end)
    p.padding:SetPoint("TOPLEFT", 396, -56)
    Tip(p.padding, "Gap", TIPS.borderGap)
  end

  p.Refresh = function()
    -- A missing rule washes the bar through the same ApplyRuleFill a presence
    -- rule does, so every fill control applies to it unchanged -- fill style,
    -- pattern, bar texture. Only the CONDITION is inverted.
    local isMissing = Rule() and Rule().showWhenMissing and true or false
    local inTextureMode = Rule() and Rule().fillStyle == "texture" and true or false
    p.swatch:Refresh()
    p.targetCheck:Refresh()
    p.focusCheck:Refresh()
    if p.whenDrop then
      p.whenDrop.Refresh()
      local r = Rule()

      -- Gone entirely once a rule has more than one debuff, rather than left
      -- to be refused on click: a missing rule is single-debuff, so on a combo
      -- this control has one reachable value, and a dropdown whose other
      -- option always errors is worse than none.
      --
      -- Safe to hide -- NS.NormaliseRule clears showWhenMissing on anything
      -- with too many conditions.
      local canMiss = #(r and r.conditions or {}) <= (NS.MAX_MISSING_CONDITIONS or 1)
      p.whenLabel:SetShown(canMiss)
      p.whenDrop:SetShown(canMiss)

      -- Only reachable, and only meaningful, in MISSING mode -- a presence
      -- rule has no "target is out of combat" state to hold anything off of.
      local combatShown = canMiss and isMissing
      p.combatOnlyCheck:SetShown(combatShown)
      p.combatOnlyLabel:SetShown(combatShown)
      if combatShown then p.combatOnlyCheck:Refresh() end

      -- One advisory block, several possible lines. Both notes below are about
      -- the same thing -- a missing rule behaving unlike a presence rule --
      -- and stacking two independently positioned warnings in a panel this
      -- tight was not worth the layout arithmetic.
      local notes = {}

      local alpha = (r and r.color and r.color.a) or 1
      if isMissing and alpha > 0.45 then
        notes[#notes + 1] = ("This color is %d%% opaque. A missing tint is lit by "
          .. "DEFAULT on every mob, not occasionally like a normal rule -- around 30%% "
          .. "reads as a reminder instead of covering the bar and everything on it.")
          :format(math.floor(alpha * 100 + 0.5))
      end

      -- "In combat" is a property of the whole missing LADDER: only one wash
      -- is ever lit and which one depends on aura state we may not read, so
      -- the gate cannot be resolved per rule. It engages only when every rule
      -- asks for it, and a half-ticked set does nothing at all.
      --
      -- OCCLUSION ONLY. That limitation belongs to the ladder, not the
      -- feature -- displacement honours each setting independently, and it is
      -- the default, so unguarded this told most users the opposite of what
      -- their client was doing.
      if isMissing and combatShown and NS.db.tints.missingMode == "occlude" then
        local total, gated = 0, 0
        for _, other in ipairs((NS.db.tints and NS.db.tints.rules) or {}) do
          if other.showWhenMissing and other.enabled ~= false then
            total = total + 1
            if other.missingCombatOnly then gated = gated + 1 end
          end
        end
        if total > 1 and gated > 0 and gated < total then
          notes[#notes + 1] = ("\"In combat\" applies to ALL of your missing rules together, "
            .. "not just this one -- so it stays off until every one of them has it ticked. "
            .. "%d of %d do right now."):format(gated, total)
        end
      end

      if p.missingAlphaWarn then
        p.missingAlphaWarn:SetShown(#notes > 0)
        if #notes > 0 then
          p.missingAlphaWarn:SetText(table.concat(notes, "\n\n"))
        end
      end
    end
    if p.fillStyle then
      p.fillStyle.Refresh()
      -- Exactly one texture picker is up at a time, chosen by fill style;
      -- both live in the same slot.
      --
      -- The conflict warning stays tied to texture mode alone: a stretched bar
      -- texture is what the nameplate addon was already drawing, so warning
      -- about it in solid mode would be crying wolf.
      p.textureLabel:SetShown(inTextureMode)
      p.textureDrop:SetShown(inTextureMode)
      p.textureWarning:SetShown(inTextureMode)
      p.barTexLabel:SetShown(not inTextureMode)
      p.barTexDrop:SetShown(not inTextureMode)
      if inTextureMode then
        p.textureDrop.Refresh()
      else
        p.barTexDrop.Refresh()
      end
    end
    if p.missingCoverCheck then
      p.missingCoverCheck:Refresh()
      -- Rides with the texture warning -- both belong to Texture Overlay.
      --
      -- Never on a missing rule: its wash is anchored to the FILL, and so is
      -- the cover that hides it, so a texture on the UNFILLED side would have
      -- nothing to hide it and would sit there permanently.
      local coverable = inTextureMode and not isMissing
      p.missingCoverCheck:SetShown(coverable)
      p.missingCoverLabel:SetShown(coverable)
      p.missingCoverWarn:SetShown(coverable)
      -- Only while this rule actually covers missing health: a colour picker
      -- for something switched off is a control that does nothing.
      local r = Rule()
      local covering = coverable and r and r.missingCover and true or false
      p.missingColorLabel:SetShown(covering)
      p.missingColor:SetShown(covering)
      p.missingColorNote:SetShown(covering)
      if covering then p.missingColor:Refresh() end
    end
    if p.thickness then
      p.thickness:Refresh()
      p.grow.Refresh()
      p.padding:Refresh()
    end

    -- Height follows what is actually on screen, so a solid-fill rule does not
    -- reserve the three lines of texture warning it is not showing. Only the
    -- split panels do this -- the "all" form is inside a fixed-height table
    -- row, where a panel that resized itself would shove the rows below it
    -- around as you ticked things.
    if split then
      -- Offsets below are ap-relative, the same numbers the SetPoint calls
      -- above use; APPEAR_SHIFT takes them back to panel space.
      local bottom
      if part == "visibility" then
        bottom = 10 + CTRL_H
      elseif isBorder then
        -- +20 alongside the border-shape block's own move (see that block).
        bottom = 84 + CTRL_H - APPEAR_SHIFT
      else
        bottom = 56 + CTRL_H - APPEAR_SHIFT
        if inTextureMode then
          local warnH = math.ceil(p.textureWarning:GetStringHeight() or 14)
          bottom = math.max(bottom, 86 + warnH - APPEAR_SHIFT)
          bottom = math.max(bottom, 120 + CTRL_H - APPEAR_SHIFT)
          if p.missingColor:IsShown() then
            bottom = math.max(bottom, 144 + CTRL_H - APPEAR_SHIFT)
          end
        end
        -- The opacity advisory sits below everything else and wraps, so it
        -- has to be measured rather than assumed.
        if p.missingAlphaWarn and p.missingAlphaWarn:IsShown() then
          bottom = math.max(bottom,
            160 + math.ceil(p.missingAlphaWarn:GetStringHeight() or 14) - APPEAR_SHIFT)
        end
      end
      p:SetHeight(bottom + 6)
    end
  end
  return p
end

-- One row shape for both lists. getList says which table it edits; isBorder
-- says which half its swatch drives. Parameterised rather than duplicated so
-- the two lists cannot drift apart in behaviour.
-- Draw-slot meter, pinned to the right of a section header.
--
-- A row of pips rather than a number alone: "6 / 8" answers how much is left,
-- the pips answer it without reading, and the pair together is what stops
-- someone adding a ninth rule and then wondering why two of them flicker.
--
-- The budget is a MEASUREMENT off a live nameplate where there is one -- the
-- host addon's own textures decide our ceiling, and it differs between skins
-- of the same addon. With no plate up it is the shipped assumption, and the
-- tooltip says so rather than presenting a guess as a reading.
-- On NS rather than a file-local: this file is within a handful of locals of
-- Lua's 200-per-chunk limit, and two more here was over it. Nothing about the
-- widget wants to be shared -- the scope is a budget decision.
-- Rule capacity, in the section header.
--
-- One line of text. It was a row of pips plus a count, which is a gauge -- and
-- a gauge earns its width when you watch it change, not when it reads the same
-- number every time you open the window. The percentage is the part that
-- transfers between nameplate addons anyway: the denominator is a measurement
-- of the host's leftover draw sublevels, a number nobody has a feel for and
-- one that differs between skins of the same addon.
--
-- Everything else lives in the tooltip, which is where the reason for a number
-- belongs.
function NS.SlotMeter(section)
  local header = section.header
  local meter = CreateFrame("Frame", nil, header)
  -- Left of the help button, which owns the right edge of every header.
  meter:SetPoint("RIGHT", section.help or header, section.help and "LEFT" or "RIGHT", -10, 0)
  meter:SetSize(150, 16)
  meter:EnableMouse(true)

  meter.text = Dim(meter, "")
  meter.text:SetPoint("RIGHT", 0, 0)
  meter.text:SetJustifyH("RIGHT")

  -- The section's subtitle runs left-to-right from the title and this runs
  -- right-to-left from the edge, so on a narrow window they met in the middle.
  -- Bounding the subtitle at the meter's left edge keeps them apart: it
  -- truncates instead.
  if section.subtitle then
    section.subtitle:SetPoint("RIGHT", meter, "LEFT", -12, 0)
    section.subtitle:SetJustifyH("LEFT")
    section.subtitle:SetWordWrap(false)
  end

  function meter.Refresh()
    -- The bar reference is used and dropped inside this call: nameplates are
    -- pooled, so holding one across a refresh would measure a plate that has
    -- since been recycled onto a different unit.
    local bar = NS.CurrentAdapterBar and NS.CurrentAdapterBar() or nil
    local report = NS.SlotReport and NS.SlotReport(bar)
    if not report then meter:Hide() return end
    meter:Show()

    local percent = (report.total or 0) > 0
      and math.floor(((report.used or 0) / report.total) * 100 + 0.5) or 0

    local colour
    if report.over then
      colour = "ffff4444"
    elseif percent >= 80 then
      colour = "ffffaa00"
    else
      colour = "ff9a9aa2"
    end
    meter.text:SetText(("|cff70707aRule Capacity:|r |c%s%d%%|r"):format(colour, percent))
    meter.report = report
  end

  Tip(meter, "Rule capacity",
    "How much of the room this nameplate addon leaves us on one health bar your rules currently spend.\n\n"
    .. "A rule costs one slot, plus one more for each of: an underlay (it sits above another rule whose debuffs it contains), Cover missing health, and Pandemic Flash. Threat states take theirs from the top, above every spell rule. Border rules cost nothing here -- they draw outside the bar.\n\n"
    .. "Run out and the lowest rules share a slot, where which of them draws on top is undefined -- the same rules then colour some plates and not others in one pull.\n\n"
    .. "Measured from a live nameplate when one is up, since the host addon's own art decides the ceiling. With no plate on screen this is the shipped estimate for your addon. Nameplate addons that give each rule its own frame level have room in the hundreds, so the percentage there is nowhere near a limit.")

  section.slotMeter = meter
  return meter
end


local function BuildRuleRow(parent, getList, isBorder)
  local Flex, C = NS.Flex, NS.RULE_COLS

  -- Still a Button with its own drag scripts; Flex only places what is inside
  -- it. FlexAdopt is what lets an existing widget be a container.
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(NS.UI.ROW_H)
  row:EnableMouse(true)
  local node = NS.FlexAdopt(row, {
    dir = "row", align = "center", height = NS.UI.ROW_H, gap = NS.UI.COL_GAP,
    pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET },
  })
  row.node = node

  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, 0.03)
  NS.PaintColumnSeps(row)

  -- Recessed while some OTHER row's editor is open, so the row being edited
  -- is the only one at full strength. One SetAlpha does it here: a rule row
  -- is a real frame and everything on it is its child.
  function row.SetRecessed(on)
    row:SetAlpha(on and THEME.rowRecessed or 1)
  end

  -- The open row is outlined on three sides and the band below closes the
  -- box, so a row and its editor read as one object rather than two stacked
  -- ones.
  row.sel = {}
  for index = 1, 4 do
    row.sel[index] = row:CreateTexture(nil, "OVERLAY")
    row.sel[index]:SetColorTexture(RGBA(THEME.selection))
    row.sel[index]:Hide()
  end
  row.sel[1]:SetPoint("TOPLEFT");    row.sel[1]:SetPoint("TOPRIGHT")
  row.sel[2]:SetPoint("BOTTOMLEFT"); row.sel[2]:SetPoint("BOTTOMRIGHT")
  row.sel[3]:SetPoint("TOPLEFT");    row.sel[3]:SetPoint("BOTTOMLEFT")
  row.sel[4]:SetPoint("TOPRIGHT");   row.sel[4]:SetPoint("BOTTOMRIGHT")
  local selWeight = NS.PixelWeight(row, NS.UI.SELECT_EDGE)
  row.sel[1]:SetHeight(selWeight); row.sel[2]:SetHeight(selWeight)
  row.sel[3]:SetWidth(selWeight);  row.sel[4]:SetWidth(selWeight)

  -- The grip, then the rule's colour, then its name. UP/DOWN buttons and the
  -- type-a-number priority box are gone: position is set by dragging now, and
  -- three ways to express one ordering was two too many.
  row.grip = CreateFrame("Frame", nil, row)
  row.grip:SetSize(NS.UI.GRIP, NS.UI.GRIP)
  row.grip.bars = {}
  for i = 1, 2 do
    local bar = row.grip:CreateTexture(nil, "OVERLAY")
    bar:SetHeight(2)
    bar:SetPoint("LEFT")
    bar:SetPoint("RIGHT")
    bar:SetPoint("TOP", 0, -3 - (i - 1) * 5)
    bar:SetColorTexture(0.42, 0.42, 0.48, 1)
    row.grip.bars[i] = bar
  end
  node:Add(NS.FlexCell(row, C.grip, Flex.Item(row.grip, { height = NS.UI.GRIP })))

  row.summary = Label(row, "")
  row.summary:SetJustifyH("LEFT")
  row.summary:SetWordWrap(false)
  -- The only child that grows and the only one that shrinks. Every control to
  -- its right is fixed, so a narrow window shortens the rule name rather than
  -- sliding Edit under the delete button.
  node:Add(Flex.Item(row.summary, { grow = 1, minW = 80, clipText = true }))

  -- The two halves, side by side.
  --
  -- These were two lists on two pages, so a rule that coloured both was
  -- authored twice and nothing in either list said the other existed. One row,
  -- two cells: filled means that half paints, empty means it does not.
  --
  -- The bar chip shows the rule's ACTUAL fill -- statusbar or tiled pattern --
  -- because two rules with one colour and different fills are two different
  -- things on a plate, and a list that draws them the same is a list you
  -- cannot trust. The border chip is flat by construction: an edge is a pixel
  -- or two, with nothing to tile across it.
  local function Half(width, getFill, tipTitle, tipBody)
    local chip = NS.FillChip(row, getFill, width, NS.UI.CHIP_H)
    chip:EnableMouse(true)
    chip:SetScript("OnMouseUp", function()
      -- Opens the rule rather than the colour picker: which half you are
      -- looking at is a question the editor answers, and a picker launched
      -- from a list gives you a colour with no idea what it belongs to.
      if row.edit and row.edit:GetScript("OnClick") then
        row.edit:GetScript("OnClick")(row.edit)
      end
    end)
    Tip(chip, tipTitle, tipBody)
    node:Add(NS.FlexCell(row, width, Flex.Item(chip, { height = NS.UI.CHIP_H })))
    return chip
  end

  row.barChip = Half(C.bar, function()
    if not row.rule or row.rule.barEnabled == false then return nil end
    return row.rule
  end, "Health bar",
    "What this rule paints on the bar, drawn the way it will actually draw.\n\nEmpty means the bar half is switched off -- the rule still paints its border, and costs no draw slot.")

  row.borderChip = Half(C.border, function()
    local border = row.rule and row.rule.border
    if not border or not border.enabled then return nil end
    return { color = border.color }
  end, "Plate border",
    "What this rule paints on the plate's border.\n\nFree: borders draw outside the health bar, so this costs no draw slot however many rules use it.")

  -- Kept for the render pass, which paints an empty cell in the rule's colour
  -- at low alpha so a switched-off half still says whose it is.
  row.swatchFrame = row.barChip
  row.swatch = row.barChip.fill

  -- What this rule spends out of the draw-slot budget, and on what. Health
  -- rules only: a border rule draws outside the bar and takes nothing from the
  -- pool, so a badge reading "0" on every row would be noise.
  do
    row.cost = Dim(row, "")
    row.cost:SetJustifyH("CENTER")
    row.cost:SetWordWrap(false)
    node:Add(Flex.Item(row.cost, { width = C.cost, shrink = 0, clipText = true }))
    TipLabel(row.cost, "What this rule costs",
      "Draw slots this rule takes on the health bar.\n\n"
      .. "One for its tint, plus one for an underlay (only when a rule BELOW it has a subset of its debuffs, so it has to hide that rule), one for Cover missing health, and one for Pandemic Flash.\n\n"
      .. "Turning a rule border-only drops it to nothing: borders draw outside the bar.")
  end

  -- One button. Conditions and appearance both live on the rule's own page
  -- now, so the old pair of expanders had nothing left to expand.
  row.edit = Button(row, "Edit", C.edit, function()
    local sec = row.section
    if not sec then return end
    -- One open at a time. Two open editors push the rules they are being
    -- compared against off the screen, which is the thing opening in place was
    -- for.
    sec.openRule = (sec.openRule ~= row.rule) and row.rule or nil
    if sec.openRule then
      sec.openThreat = false
      sec.openMark = false
      -- Point the page's preview at what is being edited. Only on OPEN, never
      -- on every render: these ticks are the user's, and re-asserting them
      -- each pass would fight anyone who unticked one to see what happens.
      wipe(preview.active)
      -- A MISSING rule is lit by its debuff being ABSENT, so ticking its
      -- debuffs on is the one state in which it cannot draw. Opening one used
      -- to switch its own preview off -- the rule looked broken at exactly the
      -- moment you opened it to look at it.
      if not sec.openRule.showWhenMissing then
        for _, condition in ipairs(sec.openRule.conditions or {}) do
          preview.active[condition.spellID] = true
        end
      end
    end
    expandedRule = sec.openRule
    EnsureRulePreview()
    NS.Options_RebuildAll()
  end)
  StyleText(row.edit.label, 11)
  node:Add(NS.FlexCell(row, C.edit, Flex.Item(row.edit, { width = C.edit })))

  -- Confirmed, because there is no undo. A rule can carry two debuffs, a
  -- colour, a fill texture and a border, and one stray click on a narrow
  -- button would take all of it with no way back.
  row.remove = CloseX(row, function()
    local rule = row.rule
    if not rule then return end
    ShowConfirm(
      "Delete this rule?",
      ("|cffffcc00%s|r will be removed. This cannot be undone."):format(RuleLabel(rule)),
      "Delete",
      function()
        local list = getList()
        for index, candidate in ipairs(list) do
          if candidate == rule then
            table.remove(list, index)
            break
          end
        end
        if expandedRule == rule then expandedRule = nil end
        Structural()
      end)
  end)
  node:Add(NS.FlexCell(row, C.del, Flex.Item(row.remove)))

  -- A tick box, not a switch: switches are reserved for turning a whole
  -- MODULE on and off. One rule among several is a setting.
  row.enabled = Checkbox(row,
    function() return row.rule and row.rule.enabled ~= false end,
    function(v) if row.rule then row.rule.enabled = v; Structural() end end)
  node:Add(NS.FlexCell(row, C.on, Flex.Item(row.enabled)))

  -- Where the row will land. On its own raised frame because rows are frames
  -- and a texture belonging to their parent draws BEHIND them, however high
  -- its layer -- the same trap the rail's indicator hit.
  local function DropLine()
    local host = row:GetParent()
    if not host then return nil end
    if not host.ptDropLine then
      local holder = CreateFrame("Frame", nil, host)
      holder:SetAllPoints(host)
      holder:SetFrameLevel(host:GetFrameLevel() + 10)
      local line = holder:CreateTexture(nil, "OVERLAY")
      line:SetHeight(2)
      line:SetColorTexture(RGBA(THEME.accent))
      line:Hide()
      host.ptDropLine = line
    end
    return host.ptDropLine
  end

  -- The index the cursor is currently over, shared by the live indicator and
  -- the drop itself so they can never disagree about where it lands.
  local function TargetIndex(self)
    local rows, count = pageRows[self.listKey], pageRowCount[self.listKey] or 0
    if not rows or count == 0 then return nil end
    local cursorY = CursorY(self)
    if not cursorY then return nil end
    for index = 1, count do
      local other = rows[index]
      local top, bottom = other:GetTop(), other:GetBottom()
      if top and bottom and cursorY <= top and cursorY >= bottom then
        return cursorY >= (top + bottom) / 2 and index or index + 1
      end
    end
    local firstTop = rows[1]:GetTop()
    if firstTop and cursorY > firstTop then return 1 end
    return count + 1
  end

  local function ShowDropLine(self)
    local line = DropLine()
    local target = TargetIndex(self)
    local rows, count = pageRows[self.listKey], pageRowCount[self.listKey] or 0
    if not line or not target or count == 0 then return end
    line:ClearAllPoints()
    if target > count then
      line:SetPoint("TOPLEFT", rows[count], "BOTTOMLEFT", 0, 1)
      line:SetPoint("TOPRIGHT", rows[count], "BOTTOMRIGHT", 0, 1)
    else
      line:SetPoint("TOPLEFT", rows[target], "TOPLEFT", 0, 1)
      line:SetPoint("TOPRIGHT", rows[target], "TOPRIGHT", 0, 1)
    end
    line:Show()
  end

  -- Same press-then-move handling as the rail's rows: OnMouseDown starts it,
  -- OnUpdate polls for the release (which can happen anywhere, including off
  -- this frame), and a 4px threshold separates a drag from a click.
  local DRAG_THRESHOLD = 4

  local function FinishPress(self)
    if not self.pressed then return end
    self.pressed = false
    self:SetAlpha(1)
    local line = DropLine()
    if line then line:Hide() end
    if not self.moved then return end
    self.moved = false

    local target = TargetIndex(self)
    if not target then return end
    local from = self.index
    if target > from then target = target - 1 end
    if target == from then return end
    local list = getList()
    local moved = table.remove(list, from)
    table.insert(list, math.max(1, math.min(#list + 1, target)), moved)
    Structural()
  end

  row:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or not self.rule then return end
    self.pressY = CursorY(self)
    self.pressed = true
    self.moved = false
  end)
  row:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then FinishPress(self) end
  end)
  row:SetScript("OnUpdate", function(self)
    if not self.pressed then return end
    if not IsMouseButtonDown("LeftButton") then FinishPress(self) return end
    local y = CursorY(self)
    if not y or not self.pressY then return end
    if not self.moved and math.abs(y - self.pressY) >= DRAG_THRESHOLD then
      self.moved = true
      self:SetAlpha(0.45)
      -- Close the editor before reordering. The band sits between two rows, so
      -- a drop aimed at the gap it occupies has no row under the cursor and
      -- lands at the bottom of the list -- a move nobody asked for. Reordering
      -- and editing are also different jobs: you drag to decide what beats
      -- what, and open a rule to decide what it looks like.
      local sec = self.section
      if sec and sec.openRule then
        sec.openRule = nil
        expandedRule = nil
        if sec.editorBand then sec.editorBand.hidden = true end
        if sec.style then sec.style:Hide() end
        NS.FlexResize(sec)
      end
    end
    if self.moved then ShowDropLine(self) end
  end)

  return row
end

-- The rule list's header, built from the SAME node shape as a row: a spacer
-- per fixed column, and a growing label where the rule name goes. That is what
-- keeps a heading over its control.
function NS.BuildRuleHeader(parent, isBorder)
  local Flex, C = NS.Flex, NS.RULE_COLS
  local head = Flex.Box(parent, {
    dir = "row", align = "center", height = NS.UI.HEAD_H, gap = NS.UI.COL_GAP,
    pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET },
  })

  head.order = select(1, NS.FlexHeaderCell(head.frame, "Order", C.grip))
  head:Add(head.order)

  head.rule = Header(head.frame, "Rule")
  head.rule:SetJustifyH("LEFT")
  head:Add(Flex.Item(head.rule, { grow = 1, minW = 80, clipText = true }))

  head.bar = select(1, NS.FlexHeaderCell(head.frame, "Bar", C.bar))
  head:Add(head.bar)
  head.border = select(1, NS.FlexHeaderCell(head.frame, "Border", C.border))
  head:Add(head.border)

  -- Right-aligned, over a right-aligned number.
  -- CENTRED, heading and value alike. It was right-aligned against a column
  -- sized for the word "Slots", so a single digit sat hard against the Edit
  -- button with the heading floating above the gap.
  head.slots = Header(head.frame, "Slots")
  head.slots:SetJustifyH("CENTER")
  head:Add(Flex.Item(head.slots, { width = C.cost, shrink = 0, clipText = true }))
  head.edit = select(1, NS.FlexHeaderCell(head.frame, "Edit", C.edit))
  head:Add(head.edit)
  head.del = select(1, NS.FlexHeaderCell(head.frame, "Del", C.del))
  head:Add(head.del)
  head.on = select(1, NS.FlexHeaderCell(head.frame, "On", C.on))
  head:Add(head.on)
  NS.PaintColumnSeps(head.frame)
  return head
end

local function BuildConditionRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(690, 24)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", 144, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = Label(row, "")
  row.name:SetPoint("LEFT", 168, 0)
  row.name:SetWidth(270)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.remove = CloseX(row, function()
    if row.rule then
      table.remove(row.rule.conditions, row.conditionIndex)
      NS.SortRules()
      Structural()
    end
  end)
  row.remove:SetPoint("LEFT", 452, 0)
  return row
end

-- Threat.
--
-- Two modules, not one: the bar tint lives on the Health Bar page and the
-- border on the Border page, each with its own switch and its own four
-- colours. They were one control with a "Bdr" column, which meant every
-- border question had to be asked inside the bar's row -- and put four tick
-- columns where two would do.
--
-- Each reads as ONE row: a strip of the four colours, what it is doing in
-- words, Edit, and a switch, with the situations themselves behind Edit.
-- Threat is one thing you turn on, not four rules you maintain.
--
-- Four fixed situations, because the client reports exactly one threat status
-- per unit. The role dropdown turns those states into sentences; same states
-- underneath, only the reading changes. There is no combat option: threat is
-- in-combat only, since out of combat every plate reports the same state.
--
-- LAID OUT WITH FLEX (Libs\Flex\Flex.lua, vendored from FlexProto). The
-- hand-written alternative anchors each control to an x from a constant while
-- the column headings take their x from a second copy of it, which is how the
-- first version of this section put its headings a column off and printed its
-- footnote through a button. Under Flex the header and a row are the same node
-- shape, so a column cannot be in two places, and the section's height is
-- measured rather than guessed.
--
-- Driven manually (Layout -> Apply -> Resize) rather than through Flex.Root's
-- own OnSizeChanged reflow: a section that resizes its content, which resizes
-- the section, is a loop.
--
-- Every widget hangs off NS rather than a file-local: Options.lua sits a
-- handful of locals under Lua's 200-per-chunk ceiling.

-- Flex.Box always makes its own frame, and a row here has to BE a widget we
-- already built -- a Button with drag handlers, or a frame carrying a stripe.
-- Handing the node an existing frame is enough: Add parents children to
-- node.frame, and Apply anchors them to it.
function NS.FlexAdopt(frame, props)
  local node = NS.Flex.Box(frame, props)
  -- The frame Box just created is thrown away rather than left parented and
  -- invisible. Nothing has been added to it yet, so nothing is orphaned.
  node.frame:Hide()
  node.frame:SetParent(nil)
  node.frame = frame
  return node
end

-- A fixed-width column with its content CENTRED in it.
--
-- Flex's `align` is the cross axis, so inside a row it controls vertical
-- placement -- there is no horizontal centring to be had from an item. A
-- one-child box with justify = center is how a 20px tick box sits in the
-- middle of a 30px column, and how the heading above it lands on the same
-- centre line rather than at the column's left edge.
function NS.FlexCell(parent, width, child, props)
  local cell = NS.Flex.Box(parent, {
    dir = "row", justify = "center", align = "center",
    width = width, shrink = 0,
  })
  if props then for key, value in pairs(props) do cell[key] = value end end
  cell:Add(child)
  return cell
end

-- Paints a rule's fill into one texture, at that texture's own size.
--
-- The single renderer behind every place a fill appears in this window: the
-- Bar and Border chips in a row, the picker grid, and the preview plate. Three
-- call sites, one implementation -- which is what stops the list from
-- disagreeing with the plate about what a rule looks like.
--
-- It mirrors the two branches ApplyRuleFill takes on a real bar:
--
--   pattern    the library TGA, tiled, at the period NS.FillTexCoords gives
--              for THIS rect -- a 30px chip repeats a 400px stripe sheet far
--              less than a 150px bar does, and pretending otherwise is what
--              made a chip look solid where the plate looked striped
--   statusbar  the LibSharedMedia bar the rule picked, tinted
--   neither    a flat colour, which is also what a rule with no media
--              installed falls back to on the plate
--
-- `fill` is the rule (or a threat state): anything with color, fillStyle,
-- barTexture and fillTexture.
function NS.PaintFill(tex, fill, width, height)
  local color = (fill and fill.color) or NS.DefaultColor()
  width = width or NS.UI.CHIP_W
  height = height or NS.UI.CHIP_H

  local drew = false
  if fill and fill.fillStyle == "texture" then
    local library = NS.FillTextureByKey and NS.FillTextureByKey(fill.fillTexture)
    if library then
      drew = pcall(function()
        tex:SetTexture(library.path, true, true)
        tex:SetTexCoord(NS.FillTexCoords(width, height, library))
        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
    end
  elseif fill then
    local path = NS.BarTexturePath and NS.BarTexturePath(fill.barTexture)
    if path then
      drew = pcall(function()
        tex:SetTexture(path)
        -- Reset: this texture may have been tiling a pattern a moment ago, and
        -- a stale TexCoord crops a statusbar to a sliver of itself.
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
    end
  end

  if not drew then
    pcall(function()
      tex:SetTexture(nil)
      tex:SetTexCoord(0, 1, 0, 1)
      tex:SetColorTexture(color.r, color.g, color.b, color.a or 1)
      tex:SetVertexColor(1, 1, 1)
      tex:SetAlpha(1)
    end)
  end
  return tex
end

-- A chip: one texture at chip size, on a frame so it can be clicked or sit in
-- a Flex cell. `getFill` is read on every Refresh, so a colour edited in the
-- picker reaches it without anything being rebuilt.
function NS.FillChip(parent, getFill, width, height)
  local chip = CreateFrame("Frame", nil, parent)
  chip:SetSize(width or NS.UI.CHIP_W, height or NS.UI.CHIP_H)

  chip.bg = chip:CreateTexture(nil, "BACKGROUND")
  chip.bg:SetAllPoints()
  chip.bg:SetColorTexture(0.06, 0.06, 0.08, 1)

  chip.fill = chip:CreateTexture(nil, "ARTWORK")
  chip.fill:SetAllPoints()

  -- A hairline around a chip that is painting.
  --
  -- These sit on a striped row, against a dark panel, next to each other --
  -- and a pale fill on a dark background has no edge of its own, so two chips
  -- side by side ran together. Black rather than a grey: it has to read as the
  -- chip's edge at any fill colour, and every colour in this window is lighter
  -- than black.
  chip.edge = {}
  for index = 1, 4 do
    chip.edge[index] = chip:CreateTexture(nil, "OVERLAY", nil, 1)
    chip.edge[index]:SetColorTexture(RGBA(THEME.chipEdge))
  end
  chip.edge[1]:SetPoint("TOPLEFT");    chip.edge[1]:SetPoint("TOPRIGHT")
  chip.edge[2]:SetPoint("BOTTOMLEFT"); chip.edge[2]:SetPoint("BOTTOMRIGHT")
  chip.edge[3]:SetPoint("TOPLEFT");    chip.edge[3]:SetPoint("BOTTOMLEFT")
  chip.edge[4]:SetPoint("TOPRIGHT");   chip.edge[4]:SetPoint("BOTTOMRIGHT")

  -- Two rotated hairlines, not an X glyph or an art file: at 14 pixels a font
  -- glyph is mostly padding and lands off centre, and a texture would be one
  -- more thing to ship. Rotation is about the texture's own centre, so both
  -- strokes cross exactly in the middle of the chip whatever size it is.
  chip.cross = {}
  for index = 1, 2 do
    chip.cross[index] = chip:CreateTexture(nil, "OVERLAY", nil, 2)
    chip.cross[index]:SetColorTexture(RGBA(THEME.chipCross))
    chip.cross[index]:SetPoint("CENTER")
    pcall(chip.cross[index].SetRotation, chip.cross[index],
      (index == 1) and (math.pi / 4) or (-math.pi / 4))
  end

  -- An empty chip is an OUTLINE, not a faint version of the colour.
  --
  -- A quarter-alpha wash reads as "this is painting, dimly" at a glance, which
  -- is the opposite of what it means. A hollow box reads as an empty slot,
  -- because that is what a hollow box is everywhere else.
  -- Dotted, and white: a solid grey box is a border a rule could be painting,
  -- so the empty state has to be drawn in something no rule can produce. WoW
  -- has no dashed-line primitive, so the dashes are textures laid along each
  -- edge, pooled and re-laid whenever the chip's size changes.
  chip.hollow = {}
  local function Dash(index)
    local dash = chip.hollow[index]
    if not dash then
      dash = chip:CreateTexture(nil, "OVERLAY")
      dash:SetColorTexture(RGBA(THEME.chipCross))
      chip.hollow[index] = dash
    end
    return dash
  end

  -- Symmetric by construction: the dashes on an edge are CENTRED along it, so
  -- both ends of every side finish the same distance from the corner. Laying
  -- them from one end instead left a full dash at the start and a clipped
  -- stub at the finish, which is what read as a lopsided outline.
  --
  -- Thickness goes through PixelBorder's rule -- whole physical pixels -- for
  -- the same reason the control borders do.
  local function LayDashes()
    local w, h = chip:GetWidth() or 0, chip:GetHeight() or 0
    if w <= 0 or h <= 0 then return end
    local dashLen, gap = NS.UI.CHIP_DASH, NS.UI.CHIP_DASH_GAP
    local weight = 1
    if PixelUtil and PixelUtil.GetNearestPixelSize then
      local ok, snapped = pcall(PixelUtil.GetNearestPixelSize, 1, chip:GetEffectiveScale(), 1)
      if ok and snapped and snapped > 0 then weight = snapped end
    end
    local used = 0
    local function Run(length, place)
      -- As many whole dashes as fit, then the remainder split evenly between
      -- the two ends.
      local count = math.max(1, math.floor((length + gap) / (dashLen + gap)))
      local span = count * dashLen + (count - 1) * gap
      local lead = (length - span) / 2
      for index = 0, count - 1 do
        used = used + 1
        local dash = Dash(used)
        dash:ClearAllPoints()
        place(dash, lead + index * (dashLen + gap))
        dash:Show()
      end
    end
    Run(w, function(dash, at)
      dash:SetSize(dashLen, weight)
      dash:SetPoint("TOPLEFT", at, 0)
    end)
    Run(w, function(dash, at)
      dash:SetSize(dashLen, weight)
      dash:SetPoint("BOTTOMLEFT", at, 0)
    end)
    Run(h, function(dash, at)
      dash:SetSize(weight, dashLen)
      dash:SetPoint("TOPLEFT", 0, -at)
    end)
    Run(h, function(dash, at)
      dash:SetSize(weight, dashLen)
      dash:SetPoint("TOPRIGHT", 0, -at)
    end)
    for index = used + 1, #chip.hollow do chip.hollow[index]:Hide() end
    chip.dashCount = used
    chip.dashW, chip.dashH = w, h

    -- The X spans the chip's shorter side, inset so its ends stop clear of
    -- the dashes rather than touching them.
    local reach = math.max(4, math.min(w, h) - 6)
    for _, stroke in ipairs(chip.cross) do
      stroke:SetSize(reach, weight)
    end
  end

  chip.Refresh = function()
    local fill = getFill and getFill() or nil
    chip.empty = fill == nil
    chip.fill:SetShown(not chip.empty)
    if chip.empty and (chip.dashW ~= chip:GetWidth() or chip.dashH ~= chip:GetHeight()) then
      LayDashes()
    end
    for index, edge in ipairs(chip.hollow) do
      edge:SetShown(chip.empty and index <= (chip.dashCount or 0))
    end
    for _, stroke in ipairs(chip.cross) do stroke:SetShown(chip.empty) end
    -- One outline or the other, never both: the dashes ARE the empty chip's
    -- edge, and a black hairline under them would only muddy them.
    local weight = NS.PixelWeight(chip)
    chip.edge[1]:SetHeight(weight); chip.edge[2]:SetHeight(weight)
    chip.edge[3]:SetWidth(weight);  chip.edge[4]:SetWidth(weight)
    for _, edge in ipairs(chip.edge) do edge:SetShown(not chip.empty) end
    if not chip.empty then
      NS.PaintFill(chip.fill, fill, chip:GetWidth(), chip:GetHeight())
    end
  end
  chip.Refresh()
  -- The reason this addon has its own picker: a striped chip has to follow a
  -- colour drag the same way a flat swatch does.
  NS.RegisterLiveSwatch(chip.Refresh)
  return chip
end

-- Lays the rule style panel out with Flex, over the widgets it already built.
--
-- The panel creates every control with its own SetPoint and a fixed 660x220
-- frame -- the last hand-anchored thing in the editor, and the reason its
-- blocks were tuned by nudging offsets ("isBorder raised 62 -> 82: the border
-- shape block moved down 20px to stop overlapping it"). None of that survives
-- a window the user can resize.
--
-- Only the PLACEMENT is replaced. Every getter, setter and Refresh in
-- BuildStylePanel is untouched, and the creation-time SetPoints are harmless:
-- Flex's Apply clears a node's points before setting its own.
--
-- Rows are declared, not positioned. A row whose widgets are all hidden
-- contributes nothing, so the panel's height is what it actually needs rather
-- than the tallest state it could reach -- which is what the old fixed height
-- was reserving space for.
function NS.StylePanelLayout(panel, isBorder)
  if panel.flex then return panel.flex end
  local Flex, UI = NS.Flex, NS.UI
  -- Adopted, not wrapped: the panel frame IS the container. Flex.Box would
  -- otherwise create a second frame inside it and leave it parented there
  -- forever, since a frame cannot be destroyed.
  local root = NS.FlexAdopt(panel, { dir = "column", gap = UI.FIELD_GAP,
    pad = { l = UI.ROW_INSET, r = UI.ROW_INSET, t = UI.FIELD_GAP, b = UI.FIELD_GAP } })

  -- A labelled row: the label in its own column so several rows line up, then
  -- whatever the field is.
  local function Row(label, ...)
    local row = Flex.Box(panel, { dir = "row", align = "center", gap = UI.COL_GAP,
      height = UI.CTRL_ROW_H })
    if label then
      label:SetJustifyH("LEFT")
      row:Add(Flex.Item(label, { width = UI.LABEL_W, shrink = 0, clipText = true }))
    end
    for _, spec in ipairs({ ... }) do
      row:Add(Flex.Item(spec[1], { width = spec[2], grow = spec[3], shrink = 0,
        minW = spec[3] and UI.LABEL_TINY or nil, clipText = spec[4] }))
    end
    root:Add(row)
    return row
  end

  -- Colour, and what the rule keys off. One row: they are the two things you
  -- change most and they belong side by side.
  local colour = Row(panel.colorLabel, { panel.swatch, UI.BOX })
  if panel.whenDrop then
    colour:Add(Flex.Item(panel.whenLabel, { width = NS.UI.LABEL_MD, shrink = 0, clipText = true }))
    colour:Add(Flex.Item(panel.whenDrop, { width = UI.DROP_W, shrink = 0 }))
    colour:Add(Flex.Item(panel.combatOnlyCheck, { width = UI.BOX, shrink = 0 }))
    colour:Add(Flex.Item(panel.combatOnlyLabel, { grow = 1, minW = UI.LABEL_TINY, clipText = true }))
  end
  panel.colourRow = colour

  if not isBorder then
    local fill = Row(panel.fillLabel, { panel.fillStyle, UI.SLIDER_W })
    fill:Add(Flex.Item(panel.textureLabel, { width = NS.UI.LABEL_SM, shrink = 0, clipText = true }))
    fill:Add(Flex.Item(panel.textureDrop, { width = UI.DROP_W, shrink = 0 }))
    fill:Add(Flex.Item(panel.barTexLabel, { width = NS.UI.LABEL_SM, shrink = 0, clipText = true }))
    fill:Add(Flex.Item(panel.barTexDrop, { width = UI.DROP_W, shrink = 0 }))
    panel.fillRow = fill

    -- Warnings wrap. They are the one thing here whose height depends on the
    -- window's width, which is exactly what the fixed panel could not express
    -- -- hence "room for a three-line wrap" reserved whether or not one was
    -- showing.
    --
    -- An empty warning is not a short warning: a FontString with no text still
    -- reports a line's height, so these are hidden on their text rather than
    -- left to measure to nothing.
    panel.textureWarnNode = root:Add(NS.FlexNote(panel, panel.textureWarning, UI.ROW_INSET))
    panel.alphaWarnNode = root:Add(NS.FlexNote(panel, panel.missingAlphaWarn, UI.ROW_INSET))

    local cover = Row(nil, { panel.missingCoverCheck, UI.BOX },
      { panel.missingCoverLabel, nil, 1, true })
    panel.coverRow = cover
    panel.coverWarnNode = root:Add(NS.FlexNote(panel, panel.missingCoverWarn, UI.ROW_INSET))

    local missing = Row(panel.missingColorLabel, { panel.missingColor, UI.BOX },
      { panel.missingColorNote, nil, 1, true })
    panel.missingRow = missing
  else
    local shape = Row(panel.title, { panel.thickLabel, UI.LABEL_MD }, { panel.thickness, UI.SLIDER_W })
    shape:Add(Flex.Item(panel.growLabel, { width = NS.UI.LABEL_XS, shrink = 0, clipText = true }))
    shape:Add(Flex.Item(panel.grow, { width = UI.DROP_SM_W, shrink = 0 }))
    shape:Add(Flex.Item(panel.padLabel, { width = NS.UI.LABEL_TINY, shrink = 0, clipText = true }))
    shape:Add(Flex.Item(panel.padding, { width = UI.DROP_SM_W, shrink = 0 }))
    panel.shapeRow = shape
  end

  local vis = Row(nil, { panel.targetCheck, UI.BOX }, { panel.targetLabel, UI.LABEL_LG, nil, true },
    { panel.focusCheck, UI.BOX }, { panel.focusLabel, nil, 1, true })
  panel.visRow = vis

  -- The two headings the split forms drop. Hidden here rather than removed:
  -- the rule editor page still builds those forms and reads these fields.
  if panel.appearHeader then panel.appearHeader:Hide() end
  if panel.visHeader then panel.visHeader:Hide() end

  panel.flex = root
  return root
end

-- Lays out the panel at a given width and returns the height it needs.
--
-- A row every one of whose widgets is hidden is hidden itself, so the panel
-- shrinks to what is actually on screen. Flex has no opinion about a frame
-- being :Hide()n -- `hidden` is the layout state -- so this is where the two
-- are reconciled.
function NS.StylePanelResize(panel, width)
  if not panel.flex then return 0 end

  -- Take the panel's own Hide() calls into the layout, per widget.
  --
  -- Refresh decides what this rule can show: a bar-texture dropdown and a
  -- pattern dropdown occupy the same column and exactly one is ever live, and
  -- "in combat" only exists on a missing rule. It expresses that with :Hide().
  --
  -- Flex does not read that. `hidden` is its own layout state, and Apply calls
  -- Show() on every node that is not hidden -- so a widget Refresh had just
  -- hidden was put back on screen AND kept its width. That is both dropdowns
  -- visible at once, over each other's column.
  --
  -- So visibility is copied into the layout before laying out, and only ever
  -- in that direction: Refresh owns what is shown, Flex owns where it goes.
  local function sync(node)
    local obj = node.frame or node.region
    if obj and obj.IsShown and not node.keepShown then
      node.hidden = not obj:IsShown()
    end
    for _, child in ipairs(node.children or {}) do sync(child) end
  end
  for _, row in ipairs(panel.flex.children) do
    for _, child in ipairs(row.children or {}) do sync(child) end
    -- A row whose every widget is hidden is hidden itself, so it contributes
    -- no height and no gap.
    local any = false
    for _, child in ipairs(row.children or {}) do
      if not child.hidden then any = true break end
    end
    row.hidden = not any
  end

  -- A warning with nothing to say takes no room. Text, not visibility: these
  -- are set by Refresh writing a string, and an empty one still measures a
  -- line high.
  for _, node in ipairs({ panel.textureWarnNode, panel.alphaWarnNode, panel.coverWarnNode }) do
    if node then
      local text = node.children[1]
      local obj = text and (text.region or text.frame)
      local body = obj and obj.GetText and obj:GetText()
      node.hidden = (body == nil or body == "")
    end
  end

  local height = panel.flex:Layout(width)
  panel.flex:Apply()
  panel:SetHeight(math.max(1, height))
  return height
end

-- What colours a plate, in the order it is decided.
--
-- The order is real and it is decided when a plate is BUILT, not while it is
-- painted: threat reserves its draw sublevel before the missing ladder, and
-- before any spell rule is allocated one. Nothing in this window has ever said
-- so, which is why "why is my rule not showing" is answered by /pt status
-- rather than by looking at the page the rules are on.
--
-- Live counts, not a static picture. A band that says "4 rules, 3 active" is
-- doing the same job the picture is, for the profile actually loaded.
function NS.ResolutionBands()
  local tints = (NS.db and NS.db.tints) or {}

  local threatOn = #(NS.GetOrderedThreatRules and NS.GetOrderedThreatRules() or {})
  local threatBorders = #(NS.GetOrderedThreatBorders and NS.GetOrderedThreatBorders() or {})
  local states = #(NS.THREAT_STATES or {})

  local rules, active, missing = tints.rules or {}, 0, 0
  for _, rule in ipairs(rules) do
    if rule.enabled ~= false and #(rule.conditions or {}) > 0 then
      if rule.showWhenMissing then missing = missing + 1 else active = active + 1 end
    end
  end

  -- The same reading for target/focus: off, on with nothing picked, or which
  -- halves are lit.
  local markBars = #(NS.GetOrderedMarkRules and NS.GetOrderedMarkRules() or {})
  local markBorders = #(NS.GetOrderedMarkBorders and NS.GetOrderedMarkBorders() or {})
  local markState
  if NS.MarkConfig and NS.MarkConfig().enabled == false then
    markState = "off"
  elseif markBars == 0 and markBorders == 0 then
    markState = "on, nothing picked"
  elseif markBars == 0 then
    markState = ("border only, %d of 2"):format(markBorders)
  elseif markBorders == 0 then
    markState = ("%d of 2"):format(markBars)
  else
    markState = ("%d of 2, %d with borders"):format(markBars, markBorders)
  end

  local threatState
  if (NS.db and NS.db.tints or {}).threatEnabled == false
    or NS.ThreatConfig().enabled == false then
    threatState = "off"
  elseif threatOn == 0 and threatBorders == 0 then
    threatState = "on, no states picked"
  elseif threatOn == 0 then
    threatState = ("border only, %d of %d states"):format(threatBorders, states)
  elseif threatBorders == 0 then
    threatState = ("%d of %d states"):format(threatOn, states)
  else
    -- Both halves, and they need not agree: two of three bars and one border
    -- is a real profile, and one number cannot say it.
    threatState = ("%d of %d states, %d with borders"):format(threatOn, states, threatBorders)
  end

  return {
    { key = "threat", colour = THEME.bandThreat, label = "Threat",
      state = threatState, tip = "Reserves its draw sublevel first, so it covers whatever a spell rule painted. Clears the moment the state does." },
    { key = "mark", colour = THEME.bandMark, label = "Target/Focus",
      state = markState,
      tip = "Claims its slots after threat and before your rules, so a target colour covers whatever a spell rule painted. Lit for as long as the unit is your target or focus." },
    { key = "rules", colour = THEME.bandRules, label = "Your spell rules",
      state = ("%d rule%s, %d active"):format(#rules, #rules == 1 and "" or "s", active),
      tip = "The topmost rule that matches is what you see. Drag to change that." },
    { key = "missing", colour = THEME.bandMissing, label = "Missing reminders",
      state = missing == 0 and "none" or ("%d rule%s"):format(missing, missing == 1 and "" or "s"),
      tip = "Below every rule that fires on a debuff being PRESENT, whatever order the list is in." },
    { key = "host", colour = THEME.bandHost, label = "Your nameplate addon",
      state = tostring((NS.CurrentAdapterName and NS.CurrentAdapterName()) or "whatever is loaded"),
      tip = "Whatever it draws wherever you did not cover it -- threat, execute range, mob type." },
  }
end

function NS.BuildResolutionLadder(section)
  local Flex, UI = NS.Flex, NS.UI
  local content = section.content
  local root = Flex.Root(content, { dir = "column", gap = UI.ROW_GAP,
    pad = { t = UI.PAD_TOP, b = UI.PAD_BOTTOM } })

  section.bands = {}
  for index = 1, #NS.ResolutionBands() do
    local row = Flex.Box(content, { dir = "row", align = "center", height = UI.BAND_H,
      gap = UI.COL_GAP, pad = { l = UI.ROW_INSET, r = UI.ROW_INSET } })

    row.rank = Dim(row.frame, tostring(index))
    row.rank:SetJustifyH("RIGHT")
    row:Add(Flex.Item(row.rank, { width = UI.BAND_RANK, shrink = 0 }))

    -- The stripe is the band's identity, and the reason the rows read as a
    -- stack rather than four sentences: colour down the left edge is the one
    -- thing you can follow without reading.
    row.stripeFrame = CreateFrame("Frame", nil, content)
    row.stripeFrame:SetSize(UI.BAND_STRIPE, UI.BAND_H)
    row.stripe = row.stripeFrame:CreateTexture(nil, "ARTWORK")
    row.stripe:SetAllPoints()
    row:Add(Flex.Item(row.stripeFrame, { width = UI.BAND_STRIPE, height = UI.BAND_H, shrink = 0 }))

    -- Word wrap OFF and the item pinned to the row's own height.
    --
    -- A FontString wraps by default, so a state as long as "2 of 3 states, 2
    -- with borders" measured two lines tall in a 24-high row. Flex centres the
    -- item, so a two-line box put its FIRST line half a row above the name
    -- beside it -- which is what made these rows read as unevenly spaced when
    -- every row is in fact the same height. Vertically centring both halves
    -- against the full row height is what keeps a long state on the same line
    -- as its name.
    row.label = Label(row.frame, "")
    row.label:SetJustifyH("LEFT")
    row.label:SetJustifyV("MIDDLE")
    row.label:SetWordWrap(false)
    row:Add(Flex.Item(row.label, { width = UI.BAND_NAME, height = UI.BAND_H,
      shrink = 0, clipText = true }))

    row.state = Dim(row.frame, "")
    row.state:SetJustifyH("LEFT")
    row.state:SetJustifyV("MIDDLE")
    row.state:SetWordWrap(false)
    row:Add(Flex.Item(row.state, { grow = 1, minW = UI.LABEL_TINY, height = UI.BAND_H,
      clipText = true }))

    section.bands[index] = root:Add(row)
  end

  section:SetHelp("What colors this plate",
    "The order these are resolved in, top to bottom. It is decided when a nameplate is built, not while it is painted -- which is why dragging a rule cannot move it above threat, and why a missing reminder cannot be dragged above a rule that fires on a debuff being present.\n\n"
    .. "Each band shows what your profile currently has in it. A band reading `off` or `none` draws nothing at all, and whatever is below it shows through.")

  section.flex = root
  return root
end

function NS.RenderResolutionLadder(sec)
  if not sec.flex then NS.BuildResolutionLadder(sec) end
  for index, band in ipairs(NS.ResolutionBands()) do
    local row = sec.bands[index]
    row.stripe:SetColorTexture(RGBA(band.colour))
    row.label:SetText(band.label)
    row.state:SetText(band.state)
    -- Dimmed as a whole when the band contributes nothing, so "what is
    -- actually painting" reads off the strip without counting.
    local live = band.state ~= "off" and band.state ~= "none"
    row.label:SetAlpha(live and 1 or 0.45)
    row.state:SetAlpha(live and 1 or 0.45)
    row.stripeFrame:SetAlpha(live and 1 or 0.3)
    Tip(row.frame, band.label, band.tip)
  end
  NS.FlexResize(sec)
end

-- Threat, as the top row of the rule list.
--
-- It was a section of its own above the list, which described the ordering
-- backwards: threat is not a thing beside your rules, it is the thing that
-- beats all of them. A row at the top of the same table, labelled TOP and with
-- no grip, says that in the place people read priority -- and there is now one
-- table on one page rather than a stack of sections each holding a list.
--
-- Its cells mean what every other row's cells mean: the Bar column shows what
-- it paints on the bar, the Border column what it paints on the border, Slots
-- what it costs. The differences are that it cannot be dragged and cannot be
-- deleted, which is what TOP and the missing controls say.
function NS.BuildThreatPinnedRow(parent)
  local Flex, UI, C = NS.Flex, NS.UI, NS.RULE_COLS
  local row = Flex.Box(parent, { dir = "row", align = "center", height = UI.ROW_H,
    gap = UI.COL_GAP, pad = { l = UI.ROW_INSET, r = UI.ROW_INSET } })

  row.bg = row.frame:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(RGBA(THEME.bandThreat))
  row.bg:SetAlpha(0.10)
  NS.PaintColumnSeps(row.frame)

  row.pin = Dim(row.frame, "TOP")
  row.pin:SetJustifyH("LEFT")
  row:Add(Flex.Item(row.pin, { width = C.grip, shrink = 0, clipText = true }))

  row.label = Label(row.frame, "")
  row.label:SetJustifyH("LEFT")
  row:Add(Flex.Item(row.label, { grow = 1, minW = 80, clipText = true }))

  -- One strip per half, three chips each, in the same columns the rules use.
  local function Strip(width, kind)
    local strip = Flex.Box(parent, { dir = "row", align = "center", gap = UI.CHIP_GAP,
      width = width, shrink = 0, justify = "center" })
    strip.chips = {}
    for _, state in ipairs(NS.ThreatStatesOrdered()) do
      local key = state.key
      local chip = NS.FillChip(parent, function()
        -- Hollow when threat is off, not just when this state is: a chip
        -- painting a colour nothing will draw is the row disagreeing with the
        -- ladder three inches above it.
        if NS.ThreatConfig().enabled == false then return nil end
        local entry = NS.ThreatModule(kind).states[key]
        if not entry or entry.enabled == false then return nil end
        return { color = entry.color }
      end, UI.STRIP_CHIP, UI.CHIP_H)
      -- Clickable, like a rule's chips: a colour you can see and not touch is
      -- a colour you go hunting for a control for.
      chip:EnableMouse(true)
      chip:SetScript("OnMouseUp", function()
        if row.onEdit then row.onEdit() end
      end)
      Tip(chip, NS.ThreatStateLabel(key), "Open the threat editor.")
      strip.chips[#strip.chips + 1] = chip
      strip:Add(Flex.Item(chip, { width = UI.STRIP_CHIP, height = UI.CHIP_H, shrink = 0 }))
    end
    row:Add(strip)
    return strip
  end
  row.barStrip = Strip(C.bar, "bar")
  row.borderStrip = Strip(C.border, "border")

  row.cost = Dim(row.frame, "")
  row.cost:SetJustifyH("CENTER")
  row:Add(Flex.Item(row.cost, { width = C.cost, shrink = 0, clipText = true }))
  TipLabel(row.cost, "What threat costs",
    "One draw slot per state you switch on for the bar, taken off the TOP of the budget so a threat colour always beats a spell rule.\n\nThe border half costs nothing: borders draw outside the bar.")

  row.edit = Button(parent, "Edit", C.edit, function()
    if row.onEdit then row.onEdit() end
  end)
  StyleText(row.edit.label, 11)
  row:Add(NS.FlexCell(parent, C.edit, Flex.Item(row.edit, { width = C.edit })))

  -- No delete. Threat is not a rule you added.
  -- Through FlexCell, like every other cell in the row.
  --
  -- A bare item sized to the column centres the TEXT inside the fontstring,
  -- which is not the same as centring the fontstring in the column: the
  -- string is laid out at its own measured width, so the dashes sat wherever
  -- that width started. Every real cell in this table is a centring box with
  -- one child, and this was the one that was not.
  row.spacer = Dim(row.frame, "--")
  row.spacer:SetJustifyH("CENTER")
  row:Add(NS.FlexCell(parent, C.del, Flex.Item(row.spacer)))

  row.enabled = Checkbox(parent,
    function() return NS.ThreatConfig().enabled ~= false end,
    function(v) NS.ThreatConfig().enabled = v; Structural() end)
  row:Add(NS.FlexCell(parent, C.on, Flex.Item(row.enabled)))

  row.recessable = { row.pin, row.label, row.cost, row.edit, row.spacer, row.enabled }
  for _, strip in ipairs({ row.barStrip, row.borderStrip }) do
    for _, chip in ipairs(strip.chips) do
      row.recessable[#row.recessable + 1] = chip
    end
  end

  -- The same recess, done the long way. A pinned row is a Flex box, and the
  -- controls on it are parented to the page's scroll content rather than to
  -- the box -- so there is no frame whose alpha carries them, and each one is
  -- set directly.
  function row.SetRecessed(on)
    local alpha = on and THEME.rowRecessed or 1
    row.bg:SetAlpha((on and THEME.rowRecessed or 1) * 0.10)
    for _, widget in ipairs(row.recessable or {}) do
      if widget and widget.SetAlpha then widget:SetAlpha(alpha) end
    end
  end
  return row
end

-- Target/Focus, as a second pinned row.
--
-- Deliberately the same shape as the threat row above rather than a shared
-- builder: the two modules agree on the row (a strip per half, Edit, one
-- switch) and disagree on everything inside the editor -- threat has a role,
-- a flash, and three states whose ORDER changes with that role; this has two
-- states and none of that. A builder parameterised over the parts that match
-- would leave the parts that do not spread across both call sites.
function NS.BuildMarkPinnedRow(parent, unitKey, rank)
  local Flex, UI, C = NS.Flex, NS.UI, NS.RULE_COLS
  local row = Flex.Box(parent, { dir = "row", align = "center", height = UI.ROW_H,
    gap = UI.COL_GAP, pad = { l = UI.ROW_INSET, r = UI.ROW_INSET } })
  row.unitKey = unitKey

  row.bg = row.frame:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(RGBA(THEME.bandMark))
  row.bg:SetAlpha(0.10)
  NS.PaintColumnSeps(row.frame)

  -- Under threat, over the rules. Two rows share the band, so they share the
  -- rank -- they do not outrank each other, a unit is one or the other.
  row.pin = Dim(row.frame, rank or "2ND")
  row.pin:SetJustifyH("LEFT")
  row:Add(Flex.Item(row.pin, { width = C.grip, shrink = 0, clipText = true }))

  row.label = Label(row.frame, "")
  row.label:SetJustifyH("LEFT")
  row:Add(Flex.Item(row.label, { grow = 1, minW = 80, clipText = true }))

  -- One chip per half, the same shape a rule row uses -- with one unit per
  -- row there is nothing to put a strip of.
  local function Half(width, kind)
    local chip = NS.FillChip(parent, function()
      if NS.MarkConfig().enabled == false then return nil end
      local entry = NS.MarkModule(kind).states[unitKey]
      if not entry or entry.enabled == false then return nil end
      if kind == "border" then return { color = entry.color } end
      return entry
    end, UI.CHIP_W, UI.CHIP_H)
    chip:EnableMouse(true)
    chip:SetScript("OnMouseUp", function()
      if row.onEdit then row.onEdit() end
    end)
    Tip(chip, NS.MarkStateLabel(unitKey),
      (kind == "border") and "The border this unit paints. Open the editor."
        or "What this unit paints on the bar. Open the editor.")
    row:Add(NS.FlexCell(parent, width, Flex.Item(chip, { height = UI.CHIP_H })))
    return chip
  end
  row.barChip = Half(C.bar, "bar")
  row.borderChip = Half(C.border, "border")

  row.cost = Dim(row.frame, "")
  row.cost:SetJustifyH("CENTER")
  row:Add(Flex.Item(row.cost, { width = C.cost, shrink = 0, clipText = true }))
  TipLabel(row.cost, "What this costs",
    "One draw slot while the bar half is on, claimed just under threat so this colour beats every spell rule.\n\nThe border and the marker cost nothing: both draw outside the bar.")

  row.edit = Button(parent, "Edit", C.edit, function()
    if row.onEdit then row.onEdit() end
  end)
  StyleText(row.edit.label, 11)
  row:Add(NS.FlexCell(parent, C.edit, Flex.Item(row.edit, { width = C.edit })))

  -- Through FlexCell, like every other cell in the row.
  --
  -- A bare item sized to the column centres the TEXT inside the fontstring,
  -- which is not the same as centring the fontstring in the column: the
  -- string is laid out at its own measured width, so the dashes sat wherever
  -- that width started. Every real cell in this table is a centring box with
  -- one child, and this was the one that was not.
  row.spacer = Dim(row.frame, "--")
  row.spacer:SetJustifyH("CENTER")
  row:Add(NS.FlexCell(parent, C.del, Flex.Item(row.spacer)))

  -- The MODULE's switch, on both rows. Target and focus are two halves of one
  -- module -- they share a slot budget and a set of load conditions -- so
  -- there is one thing to turn off, and either row can do it.
  row.enabled = Checkbox(parent,
    function() return NS.MarkConfig().enabled ~= false end,
    function(v) NS.MarkConfig().enabled = v; Structural() end)
  row:Add(NS.FlexCell(parent, C.on, Flex.Item(row.enabled)))

  row.recessable = { row.pin, row.label, row.cost, row.edit, row.spacer,
    row.enabled, row.barChip, row.borderChip }

  function row.SetRecessed(on)
    local alpha = on and THEME.rowRecessed or 1
    row.bg:SetAlpha((on and THEME.rowRecessed or 1) * 0.10)
    for _, widget in ipairs(row.recessable or {}) do
      if widget and widget.SetAlpha then widget:SetAlpha(alpha) end
    end
  end
  return row
end

-- Its editor, in the band shape the rules and threat already use.
-- One band per UNIT, built with the unit's key.
--
-- Target and focus were one editor holding six blocks, which is more than a
-- band can present at once -- and the two halves of it were never edited
-- together anyway: you set your target up, and come back to focus another
-- day. Two rows in the table, two editors, each opening on its own.
function NS.BuildMarkBand(sec, content, unitKey)
  local Flex, UI = NS.Flex, NS.UI
  local band = Flex.Box(content, { dir = "column", gap = UI.FIELD_GAP,
    pad = { l = UI.ROW_INSET, r = UI.ROW_INSET, t = UI.FIELD_GAP, b = UI.GROUP_GAP },
    hidden = true })

  local head = Flex.Box(content, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  band.title = Label(head.frame,
    ("Editing %s"):format(NS.MarkStateLabel(unitKey)), "GameFontNormal")
  band.title:SetJustifyH("LEFT")
  head:Add(Flex.Item(band.title, { grow = 1, minW = 80, clipText = true }))
  band:Add(head)

  local function MarkLoadDrop(field, summary, entries)
    return Dropdown(content, UI.DROP_W, entries, nil, nil, {
      multi = true,
      isChecked = function(key)
        local load = NS.NormaliseLoad(NS.MarkConfig().load)
        return (load[field][key]) and true or false
      end,
      onToggle = function(key)
        local cfg = NS.MarkConfig()
        cfg.load = NS.NormaliseLoad(cfg.load)
        cfg.load[field][key] = (not cfg.load[field][key]) or nil
        Structural()
      end,
      summary = function() return summary(NS.MarkConfig().load) end,
    })
  end

  local loadRow = Flex.Box(content, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  band.loadLabel = Dim(loadRow.frame, "Load in")
  loadRow:Add(Flex.Item(band.loadLabel, { width = UI.LABEL_W, shrink = 0, clipText = true }))
  band.zoneDrop = MarkLoadDrop("zones", NS.LoadZoneSummary, NS.LoadZoneEntries())
  loadRow:Add(Flex.Item(band.zoneDrop, { width = UI.DROP_W, shrink = 0 }))
  band.groupLabel = Dim(loadRow.frame, "Group")
  loadRow:Add(Flex.Item(band.groupLabel, { width = UI.LABEL_XS, shrink = 0, clipText = true }))
  band.groupDrop = MarkLoadDrop("groups", NS.LoadGroupSummary, NS.LoadGroupEntries())
  loadRow:Add(Flex.Item(band.groupDrop, { width = UI.DROP_W, shrink = 0 }))
  band:Add(loadRow)

  -- One block per unit, not one row per unit.
  --
  -- A row could carry two swatches and two tick boxes, and that is all it
  -- could ever carry -- there is nowhere on it to put a fill, a pattern, or a
  -- marker. These are the same kind of thing a spell rule paints, so they get
  -- the same kind of editor: the block shape the rules already use, one per
  -- unit, side by side.
  -- Three blocks per unit, each with its own switch in its own head.
  --
  -- One block per unit could not say which half a switch governed. The bar's
  -- switch sat in the block head and the border's ended up as a bare tick box
  -- beside a colour swatch, where it read as "disable the bar" or as nothing
  -- at all -- an unlabelled checkbox next to a colour is not a control anyone
  -- can name. Splitting the halves gives each switch a heading to sit under,
  -- and lets a half that is off go dark on its own rather than taking the
  -- other two with it.
  --
  -- The marker is a third block for the same reason: it is independent of
  -- both halves -- it draws outside the bar and costs no draw slot -- so it
  -- can be the only thing you have switched on.
  band.rows = {}

  do
    local key = unitKey
    local function Entry(kind) return NS.MarkModule(kind).states[key] end

    local unitRow = Flex.Box(content, { dir = "row", wrap = true, gap = UI.GROUP_GAP,
      crossGap = UI.GROUP_GAP, align = "stretch" })

    ---------------------------------------------------------------- the bar --
    local barBlock = NS.EditorBlock(content, "Healthbar")
    barBlock.enabled = Checkbox(content,
      function() local e = Entry("bar") return e and e.enabled ~= false end,
      function(v)
        local e = Entry("bar")
        if not e then return end
        e.enabled = v
        Structural()
      end)
    barBlock.head:Add(Flex.Item(barBlock.enabled, { width = UI.BOX, shrink = 0 }))
    Tip(barBlock.enabled, "Colour the health bar",
      "Paints this unit's colour across the bar. Costs one draw slot.\n\nOff still leaves the border and the marker, which cost nothing.")

    barBlock.colorLabel = Dim(content, "Color")
    barBlock.swatch = ColorSwatch(content,
      function() local e = Entry("bar") return e and e.color or NS.DefaultColor() end,
      function(r, g, b, a)
        local e = Entry("bar")
        if not e then return end
        e.color = { r = r, g = g, b = b, a = a }
        Restyle()
      end)
    NS.EditorRow(barBlock, content, barBlock.colorLabel, { barBlock.swatch, UI.BOX })

    barBlock.alpha = NS.OpacitySlider(content,
      function() local e = Entry("bar") return e and e.color or NS.DefaultColor() end,
      function(value)
        local e = Entry("bar")
        if not e or not e.color then return end
        e.color.a = value
        Restyle()
      end)
    barBlock.alphaLabel = Dim(content, "Opacity")
    NS.EditorRow(barBlock, content, barBlock.alphaLabel, { barBlock.alpha, UI.SLIDER_SM })

    -- The same two fills a rule's bar half has, reading the same fields:
    -- NS.ApplyRuleFill paints both, so a pattern picked here draws exactly as
    -- it does on a rule.
    barBlock.fillLabel = Dim(content, "Fill")
    barBlock.fillDrop = Dropdown(content, UI.DROP_W, {
      { text = "Bar texture", value = "bar" },
      { text = "Pattern overlay", value = "texture" },
    },
      function() local e = Entry("bar") return (e and e.fillStyle == "texture") and "texture" or "bar" end,
      function(value)
        local e = Entry("bar")
        if not e then return end
        e.fillStyle = (value == "texture") and "texture" or nil
        Structural()
      end)
    NS.EditorRow(barBlock, content, barBlock.fillLabel, { barBlock.fillDrop, UI.DROP_W })

    barBlock.barTexDrop = Dropdown(content, UI.DROP_W, BarTextureEntries,
      function() local e = Entry("bar") return e and e.barTexture end,
      function(value)
        local e = Entry("bar")
        if not e then return end
        e.barTexture = value
        Restyle()
      end)
    barBlock.barTexRow = NS.EditorRow(barBlock, content, nil, { barBlock.barTexDrop, UI.DROP_W })

    barBlock.grid = Flex.Box(content, { dir = "row", wrap = true,
      gap = UI.CHIP_GAP, crossGap = UI.CHIP_GAP })
    barBlock.gridChips = {}
    for _, texture in ipairs(NS.FillTextures or {}) do
      local textureKey = texture.key
      local chip = NS.FillChip(content, function()
        local e = Entry("bar")
        return { color = e and e.color or NS.DefaultColor(),
          fillStyle = "texture", fillTexture = textureKey }
      end, UI.SWATCH_GRID, UI.CHIP_H)
      chip:EnableMouse(true)
      chip:SetScript("OnMouseUp", function()
        local e = Entry("bar")
        if not e then return end
        e.fillStyle, e.fillTexture = "texture", textureKey
        Structural()
      end)
      Tip(chip, texture.label, "Tiles across the bar. The host addon's own colour shows through the gaps.")
      chip.sel = {}
      for index = 1, 4 do
        chip.sel[index] = chip:CreateTexture(nil, "OVERLAY")
        chip.sel[index]:SetColorTexture(RGBA(THEME.accent))
        chip.sel[index]:Hide()
      end
      chip.sel[1]:SetPoint("TOPLEFT", -2, 2);     chip.sel[1]:SetPoint("TOPRIGHT", 2, 2)
      chip.sel[2]:SetPoint("BOTTOMLEFT", -2, -2); chip.sel[2]:SetPoint("BOTTOMRIGHT", 2, -2)
      chip.sel[3]:SetPoint("TOPLEFT", -2, 2);     chip.sel[3]:SetPoint("BOTTOMLEFT", -2, -2)
      chip.sel[4]:SetPoint("TOPRIGHT", 2, 2);     chip.sel[4]:SetPoint("BOTTOMRIGHT", 2, -2)
      chip.sel[1]:SetHeight(2); chip.sel[2]:SetHeight(2)
      chip.sel[3]:SetWidth(2);  chip.sel[4]:SetWidth(2)
      chip.key = textureKey
      barBlock.gridChips[#barBlock.gridChips + 1] = chip
      barBlock:Register(chip)
      barBlock.grid:Add(Flex.Item(chip, { width = UI.SWATCH_GRID, height = UI.CHIP_H, shrink = 0 }))
    end
    local perRow = math.ceil(#barBlock.gridChips / 2)
    barBlock.grid.maxW = perRow * (UI.SWATCH_GRID + UI.CHIP_GAP) - UI.CHIP_GAP
    barBlock:Add(barBlock.grid)

    ------------------------------------------------------------- the border --
    local borderBlock = NS.EditorBlock(content, "Border")
    borderBlock.enabled = Checkbox(content,
      function() local e = Entry("border") return e and e.enabled ~= false end,
      function(v)
        local e = Entry("border")
        if not e then return end
        e.enabled = v
        Structural()
      end)
    borderBlock.head:Add(Flex.Item(borderBlock.enabled, { width = UI.BOX, shrink = 0 }))
    Tip(borderBlock.enabled, "Colour the plate border",
      "Draws this unit's colour around the plate.\n\nFree: borders draw outside the health bar, so this costs no draw slot.")

    borderBlock.colorLabel = Dim(content, "Color")
    borderBlock.swatch = ColorSwatch(content,
      function() local e = Entry("border") return e and e.color or NS.DefaultColor() end,
      function(r, g, b, a)
        local e = Entry("border")
        if not e then return end
        e.color = { r = r, g = g, b = b, a = a }
        Restyle()
      end)
    NS.EditorRow(borderBlock, content, borderBlock.colorLabel, { borderBlock.swatch, UI.BOX })

    borderBlock.alpha = NS.OpacitySlider(content,
      function() local e = Entry("border") return e and e.color or NS.DefaultColor() end,
      function(value)
        local e = Entry("border")
        if not e or not e.color then return end
        e.color.a = value
        Restyle()
      end)
    borderBlock.alphaLabel = Dim(content, "Opacity")
    NS.EditorRow(borderBlock, content, borderBlock.alphaLabel,
      { borderBlock.alpha, UI.SLIDER_SM })

    -- Shape, not just colour.
    --
    -- The engine has read thickness, grow and padding off the module since
    -- BuildMark was written, and nothing here set them -- so a target border
    -- was stuck at two pixels hard against the bar with no way to say
    -- otherwise, while the same three controls sat on every spell rule.
    --
    -- Module-wide rather than per state, which is where the engine reads them
    -- from: one border geometry, two colours. Two units whose edges sat at
    -- different distances would read as a misaligned plate, not as a setting.
    borderBlock.thickLabel = Dim(content, "Thickness")
    borderBlock.thickness = Slider(content, UI.SLIDER_SM, 1, 8, 7,
      function() return NS.MarkBorderConfig().thickness or 2 end,
      function(v)
        NS.MarkBorderConfig().thickness = v
        Structural()
      end)
    NS.EditorRow(borderBlock, content, borderBlock.thickLabel,
      { borderBlock.thickness, UI.SLIDER_SM })

    -- growDrop, not grow: Flex reads `grow` off a node as its share of
    -- leftover space, so a frame parked there is arithmetic on a table.
    borderBlock.growLabel = Dim(content, "Grows")
    borderBlock.growDrop = Dropdown(content, UI.DROP_SM_W, {
      { text = "Outward", value = "OUT" },
      { text = "Inward", value = "IN" },
    },
      function() return NS.MarkBorderConfig().grow or "OUT" end,
      function(value)
        NS.MarkBorderConfig().grow = value
        Structural()
      end)
    NS.EditorRow(borderBlock, content, borderBlock.growLabel,
      { borderBlock.growDrop, UI.DROP_SM_W })

    borderBlock.padLabel = Dim(content, "Gap")
    borderBlock.padding = Slider(content, UI.SLIDER_SM, 0, 12, 13,
      function() return NS.MarkBorderConfig().padding or 0 end,
      function(v)
        NS.MarkBorderConfig().padding = v
        Structural()
      end)
    NS.EditorRow(borderBlock, content, borderBlock.padLabel,
      { borderBlock.padding, UI.SLIDER_SM })

    ------------------------------------------------------------- the marker --
    local markerBlock = NS.EditorBlock(content, "Marker")
    markerBlock.enabled = Checkbox(content,
      function()
        local e = Entry("bar")
        return e and e.indicator and e.indicator.enabled and true or false
      end,
      function(v)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        e.indicator.enabled = v
        Structural()
      end)
    markerBlock.head:Add(Flex.Item(markerBlock.enabled, { width = UI.BOX, shrink = 0 }))
    Tip(markerBlock.enabled, "Show a marker",
      "A small shape beside the plate, in this unit's colour.\n\nCosts no draw slot -- it draws outside the health bar, like a border does -- so it works with both halves above switched off.")

    -- The marker's own colour, or the unit's when it has none.
    --
    -- Absent by default, so a marker follows the bar colour until someone
    -- deliberately parts them -- which is what you want when the bar half is
    -- ON. It stops being what you want the moment the bar half is off, since
    -- then the marker is the only thing carrying that colour and it should be
    -- free to be its own.
    markerBlock.colorLabel = Dim(content, "Color")
    markerBlock.swatch = ColorSwatch(content,
      function()
        local e = Entry("bar")
        return NS.MarkerColor(e)
      end,
      function(r, g, b, a)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        e.indicator.color = { r = r, g = g, b = b, a = a }
        Restyle()
      end)
    markerBlock.followOn = Checkbox(content,
      function()
        local e = Entry("bar")
        return not (e and e.indicator and e.indicator.color)
      end,
      function(v)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        if v then
          e.indicator.color = nil
        else
          local base = e.color or NS.DefaultColor()
          e.indicator.color = { r = base.r, g = base.g, b = base.b, a = base.a or 1 }
        end
        Restyle()
      end)
    NS.EditorRow(markerBlock, content, markerBlock.colorLabel,
      { markerBlock.swatch, UI.BOX })
    markerBlock.followLabel = Label(content, "Match the bar colour")
    NS.EditorRow(markerBlock, content, nil, { markerBlock.followOn, UI.BOX },
      { markerBlock.followLabel, nil, 1, true })

    markerBlock.alpha = NS.OpacitySlider(content,
      function() local e = Entry("bar") return NS.MarkerColor(e) end,
      function(value)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        local base = e.indicator.color or e.color or NS.DefaultColor()
        e.indicator.color = { r = base.r, g = base.g, b = base.b, a = value }
        Restyle()
      end)
    markerBlock.alphaLabel = Dim(content, "Opacity")
    NS.EditorRow(markerBlock, content, markerBlock.alphaLabel,
      { markerBlock.alpha, UI.SLIDER_SM })

    markerBlock.shapeLabel = Dim(content, "Shape")
    -- The function, not its result: which shapes exist depends on whether
    -- another addon is loaded, and that is not decided at build time.
    markerBlock.shape = Dropdown(content, UI.DROP_W, NS.MarkShapeEntries,
      function()
        local e = Entry("bar")
        return (e and e.indicator and e.indicator.shape) or "arrow"
      end,
      function(value)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        e.indicator.shape = value
        Structural()
      end)
    NS.EditorRow(markerBlock, content, markerBlock.shapeLabel, { markerBlock.shape, UI.DROP_W })

    markerBlock.posLabel = Dim(content, "Where")
    markerBlock.pos = Dropdown(content, UI.DROP_W, NS.MarkPositionEntries(),
      function()
        local e = Entry("bar")
        return (e and e.indicator and e.indicator.position) or "BOTH"
      end,
      function(value)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        e.indicator.position = value
        Structural()
      end)
    NS.EditorRow(markerBlock, content, markerBlock.posLabel, { markerBlock.pos, UI.DROP_W })

    markerBlock.sizeLabel = Dim(content, "Size")
    markerBlock.size = Slider(content, UI.SLIDER_SM, 4, 32, 28,
      function()
        local e = Entry("bar")
        return (e and e.indicator and e.indicator.size) or 10
      end,
      function(v)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        e.indicator.size = v
        Structural()
      end)
    NS.EditorRow(markerBlock, content, markerBlock.sizeLabel, { markerBlock.size, UI.SLIDER_SM })

    -- gapSlider, not gap.
    --
    -- A block IS a Flex node, and `gap` is one of Flex's own props -- the
    -- space between a box's children. Storing a frame there replaced that
    -- number with a table, and the next column layout tried to add a frame to
    -- a height. Anything hung on a block has to avoid Flex's vocabulary:
    -- width, height, gap, pad, align, grow, shrink, basis, minW, maxW.
    markerBlock.gapLabel = Dim(content, "Gap")
    markerBlock.gapSlider = Slider(content, UI.SLIDER_SM, 0, 40, 40,
      function()
        local e = Entry("bar")
        return (e and e.indicator and e.indicator.gap) or 4
      end,
      function(v)
        local e = Entry("bar")
        if not e or not e.indicator then return end
        e.indicator.gap = v
        Structural()
      end)
    NS.EditorRow(markerBlock, content, markerBlock.gapLabel,
      { markerBlock.gapSlider, UI.SLIDER_SM })

    unitRow:Add(barBlock)
    unitRow:Add(borderBlock)
    unitRow:Add(markerBlock)
    band:Add(unitRow)

    -- One Refresh per unit, driving all three blocks. The render pass calls
    -- this without knowing how many blocks a unit turned out to need.
    local unit = { key = key, bar = barBlock, border = borderBlock, marker = markerBlock }
    function unit.Refresh()
      local barEntry = Entry("bar")
      local borderEntry = Entry("border")

      barBlock:SetOff(not (barEntry and barEntry.enabled ~= false))
      barBlock.enabled.Refresh()
      barBlock.swatch.Refresh()
      barBlock.alpha.Refresh()
      barBlock.fillDrop.Refresh()
      local patterned = barEntry and barEntry.fillStyle == "texture"
      barBlock.barTexRow.hidden = patterned and true or false
      barBlock.grid.hidden = not patterned
      if not patterned then barBlock.barTexDrop.Refresh() end
      for _, chip in ipairs(barBlock.gridChips) do
        chip.Refresh()
        local on = patterned and barEntry.fillTexture == chip.key
        for _, edge in ipairs(chip.sel) do edge:SetShown(on) end
      end

      borderBlock:SetOff(not (borderEntry and borderEntry.enabled ~= false))
      borderBlock.enabled.Refresh()
      borderBlock.swatch.Refresh()
      borderBlock.alpha.Refresh()
      borderBlock.thickness.Refresh()
      borderBlock.growDrop.Refresh()
      borderBlock.padding.Refresh()

      local marker = barEntry and barEntry.indicator and barEntry.indicator.enabled
      markerBlock:SetOff(not marker)
      markerBlock.enabled.Refresh()
      markerBlock.swatch.Refresh()
      markerBlock.followOn.Refresh()
      markerBlock.alpha.Refresh()
      markerBlock.shape.Refresh()
      markerBlock.pos.Refresh()
      markerBlock.size.Refresh()
      markerBlock.gapSlider.Refresh()
    end

    band.rows[#band.rows + 1] = unit
  end

  band.note = Dim(content,
    "Lit for as long as the unit is your target or focus, in combat or out. A unit that is both takes the target colour. Keep the bar colours low in opacity -- this paints a plate you are already looking at.")
  band:Add(NS.FlexNote(content, band.note, 0))

  return band
end

-- The threat editor, in the same band the rules use.
function NS.BuildThreatBand(sec, content)
  local Flex, UI = NS.Flex, NS.UI
  local band = Flex.Box(content, { dir = "column", gap = UI.FIELD_GAP,
    pad = { l = UI.ROW_INSET, r = UI.ROW_INSET, t = UI.FIELD_GAP, b = UI.GROUP_GAP },
    hidden = true })

  local head = Flex.Box(content, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  band.title = Label(head.frame, "Editing threat", "GameFontNormal")
  band.title:SetJustifyH("LEFT")
  head:Add(Flex.Item(band.title, { grow = 1, minW = 80, clipText = true }))
  band.roleLabel = Dim(head.frame, "Read as")
  head:Add(Flex.Item(band.roleLabel, { width = UI.LABEL_W, shrink = 0, clipText = true }))
  band.roleDrop = Dropdown(content, UI.DROP_W, NS.ThreatRoleEntries(),
    function() return NS.ThreatConfig().role or "auto" end,
    function(v) NS.ThreatConfig().role = v; Structural() end)
  head:Add(Flex.Item(band.roleDrop, { width = UI.DROP_W, shrink = 0 }))
  band:Add(head)

  -- Where threat loads. Same two lists a rule gets, on the module rather than
  -- on one state: threat is one thing you switch on, so "not in delves" is an
  -- answer about threat, not about Near Aggro.
  local function ThreatLoadDrop(field, summary, entries)
    return Dropdown(content, UI.DROP_W, entries, nil, nil, {
      multi = true,
      isChecked = function(key)
        local load = NS.NormaliseLoad(NS.ThreatConfig().load)
        return (load[field][key]) and true or false
      end,
      onToggle = function(key)
        local cfg = NS.ThreatConfig()
        cfg.load = NS.NormaliseLoad(cfg.load)
        cfg.load[field][key] = (not cfg.load[field][key]) or nil
        Structural()
      end,
      summary = function() return summary(NS.ThreatConfig().load) end,
    })
  end

  local loadRow = Flex.Box(content, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  band.loadLabel = Dim(loadRow.frame, "Load in")
  loadRow:Add(Flex.Item(band.loadLabel, { width = UI.LABEL_W, shrink = 0, clipText = true }))
  band.zoneDrop = ThreatLoadDrop("zones", NS.LoadZoneSummary, NS.LoadZoneEntries())
  loadRow:Add(Flex.Item(band.zoneDrop, { width = UI.DROP_W, shrink = 0 }))
  band.groupLabel = Dim(loadRow.frame, "Group")
  loadRow:Add(Flex.Item(band.groupLabel, { width = UI.LABEL_XS, shrink = 0, clipText = true }))
  band.groupDrop = ThreatLoadDrop("groups", NS.LoadGroupSummary, NS.LoadGroupEntries())
  loadRow:Add(Flex.Item(band.groupDrop, { width = UI.DROP_W, shrink = 0 }))
  band:Add(loadRow)
  TipLabel(band.loadLabel, "Where threat colouring loads",
    "Tick the content you want threat colours in; nothing ticked means everywhere.\n\nSolo, or in a delve, there is nobody to lose a mob to -- switching threat off there gives its draw slots back to your spell rules.")

  -- One row per state, with both halves on it -- the same shape as the table
  -- above, for the same reason: bar and border are two cells of one thing.
  local header = Flex.Box(content, { dir = "row", align = "center", height = UI.HEAD_H,
    gap = UI.COL_GAP })
  header.state = Header(header.frame, "Situation")
  header.state:SetJustifyH("LEFT")
  header:Add(Flex.Item(header.state, { grow = 1, minW = 60, clipText = true }))
  header.bar = select(1, NS.FlexHeaderCell(header.frame, "Bar", NS.RULE_COLS.bar))
  header:Add(header.bar)
  header.barOn = select(1, NS.FlexHeaderCell(header.frame, "On", NS.THREAT_COLS.on))
  header:Add(header.barOn)
  header.border = select(1, NS.FlexHeaderCell(header.frame, "Border", NS.RULE_COLS.border))
  header:Add(header.border)
  header.borderOn = select(1, NS.FlexHeaderCell(header.frame, "On", NS.THREAT_COLS.on))
  header:Add(header.borderOn)
  band:Add(header)

  band.rows = {}
  for index, state in ipairs(NS.ThreatStatesOrdered()) do
    local key = state.key
    local row = Flex.Box(content, { dir = "row", align = "center", height = UI.ROW_H,
      gap = UI.COL_GAP })

    row.stripe = row.frame:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.03)
    row.stripe:SetShown(index % 2 == 0)

    row.label = Label(row.frame, "")
    row.label:SetJustifyH("LEFT")
    row:Add(Flex.Item(row.label, { grow = 1, minW = 60, clipText = true }))

    local function Half(kind, chipWidth)
      local swatch = ColorSwatch(content,
        function()
          local entry = NS.ThreatModule(kind).states[key]
          return entry and entry.color or NS.DefaultColor()
        end,
        function(r, g, b, a)
          local entry = NS.ThreatModule(kind).states[key]
          if not entry then return end
          entry.color = { r = r, g = g, b = b, a = a }
          NS.ThreatTouched(NS.ThreatModule(kind))
          Restyle()
        end)
      row:Add(NS.FlexCell(content, chipWidth, Flex.Item(swatch, { width = UI.BOX })))

      local box = Checkbox(content,
        function()
          local entry = NS.ThreatModule(kind).states[key]
          return entry and entry.enabled ~= false
        end,
        function(v)
          local entry = NS.ThreatModule(kind).states[key]
          if not entry then return end
          entry.enabled = v
          NS.ThreatTouched(NS.ThreatModule(kind))
          Structural()
        end)
      row:Add(NS.FlexCell(content, NS.THREAT_COLS.on, Flex.Item(box)))
      return swatch, box
    end

    row.barSwatch, row.barOn = Half("bar", NS.RULE_COLS.bar)
    row.borderSwatch, row.borderOn = Half("border", NS.RULE_COLS.border)
    row.key = key
    band.rows[index] = band:Add(row)
  end

  -- Losing a mob is the one threat change worth announcing rather than just
  -- showing, so it gets a switch of its own rather than living inside a state.
  local flashRow = Flex.Box(content, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  band.flash = Checkbox(content,
    function() return NS.ThreatConfig().flashOnLoss and true or false end,
    function(v)
      NS.ThreatConfig().flashOnLoss = v or nil
      NS.ThreatTouched(NS.ThreatConfig())
      Structural()
    end)
  flashRow:Add(Flex.Item(band.flash, { width = UI.BOX, shrink = 0 }))
  band.flashLabel = Label(content, "Flash when you lose aggro")
  band.flashLabel:SetJustifyH("LEFT")
  flashRow:Add(Flex.Item(band.flashLabel, { grow = 1, minW = UI.LABEL_TINY, clipText = true }))
  Tip(band.flash, "Flash when you lose aggro",
    "Blinks the plate for a second and a half the moment a mob comes off you.\n\nA colour tells you what is true now; by the time you notice it changed, the moment a taunt was for has passed. Costs no extra draw slot -- it is the same colour, announcing itself.")
  band:Add(flashRow)

  band.note = Dim(content,
    "Only ever coloured while you are in combat -- out of combat every plate reports the same state. The border half costs no draw slots.")
  band:Add(NS.FlexNote(content, band.note, 0))

  sec.threatBand = band
  return band
end

-- The rule editor.
--
-- Written here rather than hosting the old style panel. That panel is the
-- HEALTH variant -- its border controls only exist in the copy the border page
-- builds -- so with one list holding both halves, hosting it meant a rule
-- whose border you wanted to change had nowhere to change it.
--
-- Three blocks: what the rule fires on, then one per half. The two halves look
-- the same as each other and carry the same first control (a switch), because
-- they are the same kind of thing: a colour this rule paints somewhere.
-- On NS, not a file-local: this file sits a handful of locals under Lua's
-- 200-per-chunk ceiling, and two more helpers went straight through it.
function NS.EditorBlock(parent, title)
  local UI = NS.UI
  -- `basis` is what makes the four blocks the same width: without it each one
  -- starts from its own content and grow only shares out what is left over, so
  -- the block with the widest row stayed the widest block. Starting them all
  -- from the same number and growing equally is what "evenly spaced" means
  -- here.
  local block = NS.Flex.Box(parent, { dir = "column", gap = UI.FIELD_GAP,
    grow = 1, basis = UI.BLOCK_MIN_W, minW = UI.BLOCK_MIN_W,
    pad = { l = UI.BLOCK_PAD, r = UI.BLOCK_PAD, t = UI.BLOCK_PAD, b = UI.BLOCK_PAD } })

  block.bg = block.frame:CreateTexture(nil, "BACKGROUND")
  block.bg:SetAllPoints()
  block.bg:SetColorTexture(RGBA(THEME.blockBG))

  -- Everything inside the block that a switched-off half should take with it.
  --
  -- Registered rather than walked: these controls are parented to the page's
  -- scroll content, not to the block frame -- Flex places them, it does not
  -- own them -- so there is no child list to dim. NS.EditorRow adds whatever
  -- it lays out; anything added to the block directly registers itself.
  block.controls = {}
  function block:Register(widget)
    if widget then block.controls[#block.controls + 1] = widget end
    return widget
  end

  -- A half that is switched off goes DARK, and everything in it goes with it:
  -- dimmed and unclickable, so the block reads as one inert thing rather than
  -- as live controls on a dark background. The block's OWN switch is in the
  -- head and is never registered -- it is the way back.
  function block:SetOff(off)
    block.bg:SetColorTexture(RGBA(off and THEME.blockBGOff or THEME.blockBG))
    block.title:SetAlpha(off and 0.55 or 1)
    for _, widget in ipairs(block.controls) do
      if widget.SetAlpha then widget:SetAlpha(off and 0.35 or 1) end
      -- Two mechanisms, because these are not all the same kind of object: a
      -- Button has Enable/Disable and repaints itself, a plain frame (a
      -- slider's track) only has mouse input, and a FontString has neither.
      if widget.EnableMouse then pcall(widget.EnableMouse, widget, not off) end
      -- A composite control keeps its mouse on a child; Slider is the one
      -- here, and its holder is what gets registered.
      if widget.track and widget.track.EnableMouse then
        pcall(widget.track.EnableMouse, widget.track, not off)
      end
      if off then
        if widget.Disable then pcall(widget.Disable, widget) end
      elseif widget.Enable then
        pcall(widget.Enable, widget)
      end
    end
  end

  local head = NS.Flex.Box(parent, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  block.title = Label(head.frame, title, "GameFontNormal")
  block.title:SetJustifyH("LEFT")
  head:Add(NS.Flex.Item(block.title, { grow = 1, minW = 40, clipText = true }))
  block.head = head
  block:Add(head)
  return block
end

-- Opacity, on the colour's own line.
--
-- The alpha of a fill decides whether a rule reads as a tint or as paint over
-- the bar, and it was reachable only by opening the picker -- so the one
-- number most likely to be wrong was the one you could not see. Here it sits
-- beside the swatch it belongs to, and the picker still edits the same value.
--
-- 0-100, not 0-1: nobody describes a colour as "0.35 opaque".
--
-- Registered as a live swatch, so dragging opacity IN the picker moves this
-- slider as it goes. Two controls over one number have to agree at every
-- frame, not just when one of them closes.
function NS.OpacitySlider(parent, getColor, setAlpha)
  local slider = Slider(parent, NS.UI.SLIDER_SM, 0, 100, 100,
    function()
      local c = getColor()
      return math.floor(((c and c.a or 1) * 100) + 0.5)
    end,
    function(value) setAlpha(math.max(0, math.min(1, (value or 0) / 100))) end)
  NS.RegisterLiveSwatch(function()
    if slider.Refresh then slider.Refresh() end
  end)
  return slider
end

-- A heading INSIDE a block, for the blocks that hold more than one thing.
--
-- The Target/Focus blocks carry three subjects each -- the bar, the border and
-- the marker -- and without a break between them the rows read as one long
-- undifferentiated list where "Color" appears twice meaning two different
-- things. Same typeface as the column headings in the table, so a heading
-- looks like a heading wherever it is.
function NS.EditorHeading(block, parent, text)
  local UI = NS.UI
  local row = NS.Flex.Box(parent, { dir = "row", align = "center",
    height = UI.HEAD_H, pad = { t = UI.FIELD_GAP } })
  local label = Header(parent, text)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  row:Add(NS.Flex.Item(label, { grow = 1, height = UI.HEAD_H, clipText = true }))
  block:Add(row)
  block.headings = block.headings or {}
  block.headings[#block.headings + 1] = label
  if block.Register then block:Register(label) end
  return row, label
end

-- A labelled control line inside a block.
function NS.EditorRow(block, parent, label, ...)
  local UI = NS.UI
  local row = NS.Flex.Box(parent, { dir = "row", align = "center", gap = UI.COL_GAP,
    height = UI.CTRL_ROW_H })
  if label then
    label:SetJustifyH("LEFT")
    -- Shrinkable, down to a floor. See the note on the control items below:
    -- shrink = 0 is what made these rows overflow their block rather than
    -- fit inside it.
    row:Add(NS.Flex.Item(label, { width = UI.LABEL_W, minW = UI.LABEL_TINY,
      shrink = 1, clipText = true }))
  end
  if label and block.Register then block:Register(label) end
  for _, spec in ipairs({ ... }) do
    if block.Register then block:Register(spec[1]) end
    -- A FontString that GROWS reads LEFT. GameFontHighlight justifies CENTRE
    -- by default, so a caption next to a tick box drifted into the middle of
    -- whatever width was left over -- which is the huge gap between a box and
    -- its own label. The fixed-width labels are set by the caller; this is
    -- the growing one, and it is always a caption.
    if spec[3] and spec[1].SetJustifyH then spec[1]:SetJustifyH("LEFT") end
    -- shrink = 1, not 0.
    --
    -- These widths are what a control WANTS -- a dropdown asks for 200, a
    -- slider for its length plus its number -- and a block three-to-a-row is
    -- about 194 wide inside its padding. With shrink = 0 the row simply drew
    -- past the block's edge and over its neighbour; there was no width at
    -- which it would have fit. Now the label and the control give ground
    -- together, down to floors that keep both legible.
    --
    -- This is why Slider anchors its track to both its own edges rather than
    -- sizing it once: a control that is allowed to shrink has to mean it.
    local width = spec[2]
    row:Add(NS.Flex.Item(spec[1], { width = width, grow = spec[3],
      minW = spec[3] and UI.LABEL_TINY or (width and math.min(width, UI.LABEL_W)) or nil,
      shrink = 1, clipText = spec[4] }))
  end
  block:Add(row)
  return row
end

function NS.BuildRuleEditor(sec, content)
  local Flex, UI = NS.Flex, NS.UI
  local function Rule() return sec.openRule end

  local editor = Flex.Box(content, { dir = "column", gap = UI.GROUP_GAP,
    pad = { l = UI.ROW_INSET, r = UI.ROW_INSET } })

  -- Four blocks, one question each: what the rule watches, where it is
  -- allowed to load, and what it paints on each half. They were three, with
  -- "When" carrying both the debuffs and every restriction on them -- so the
  -- block that answered "what does this rule fire on" also answered "and in
  -- which raid difficulty", which are not the same question and are not
  -- edited at the same time.
  local when = NS.EditorBlock(content, "Tracked Spells")
  editor.when = when

  -- The debuffs themselves, editable.
  --
  -- This block described the rule and gave you no way to change what it fires
  -- on -- the one thing a rule IS. Adding a debuff meant the old rule page,
  -- which is gone, so a rule's conditions were fixed at creation.
  --
  -- A wrapping row of pills, each with its own remove, then the two ways to
  -- name a spell: the Cooldown Manager list for the ones the game will admit
  -- you cast, and an ID box for everything else.
  when.pills = Flex.Box(content, { dir = "row", wrap = true,
    gap = UI.CHIP_GAP, crossGap = UI.CHIP_GAP })
  when.pillPool = {}
  when:Add(when.pills)

  -- isTracked marks the ones this rule already has, so the list says which of
  -- your debuffs are spoken for. It is CALLED per entry, so it cannot be nil --
  -- passing nil there took the whole page down when the list was built.
  when.addDrop = AddSpellDropdown(content, UI.DROP_W, "Add a debuff", function(spellID)
    local rule = Rule()
    for _, condition in ipairs(rule and rule.conditions or {}) do
      if condition.spellID == spellID then return true end
    end
    return false
  end, function(spellID)
    local rule = Rule()
    if not rule then return end
    AddConditionTo(rule, spellID, false)
    Structural()
  end)
  NS.EditorRow(when, content, nil, { when.addDrop, UI.DROP_W })

  when.idBox = IDBox(content, function(text)
    local rule = Rule()
    if not rule then return end
    AddConditionTo(rule, text, false)
    Structural()
  end, UI.DROP_W)
  when.idLabel = Dim(content, "or a spell ID")
  when.idLabel:SetJustifyH("LEFT")
  NS.EditorRow(when, content, nil, { when.idBox, UI.DROP_W },
    { when.idLabel, nil, 1, true })

  when.limit = Dim(when.frame, "")
  when.limit:SetJustifyH("LEFT")
  when:Add(NS.FlexNote(content, when.limit, 0))

  when.modeDrop = Dropdown(content, UI.DROP_W, {
    { text = "The debuff is present", value = false },
    { text = "The debuff is MISSING", value = true },
  },
    function() local r = Rule() return (r and r.showWhenMissing) and true or false end,
    function(value)
      local r = Rule()
      if not r then return end
      -- Refused rather than silently dropping a debuff: a missing rule is
      -- single-debuff by construction, and a combo has no room for the second
      -- one in the ladder's sublevel budget.
      if value and #(r.conditions or {}) > (NS.MAX_MISSING_CONDITIONS or 1) then
        NS.Print("a MISSING rule can only carry one debuff.")
        return
      end
      r.showWhenMissing = value or nil
      Structural()
    end)
  NS.EditorRow(when, content, nil, { when.modeDrop, UI.DROP_W })

  -- Everything that decides WHERE and WHEN the rule is allowed to apply, as
  -- opposed to what it watches for.
  local load = NS.EditorBlock(content, "Load Conditions")
  editor.load = load

  -- Where the rule loads at all.
  --
  -- Not a condition on the plate: a rule ruled out here is never BUILT, so it
  -- spends no draw slot in the content it is switched off for. Both lists
  -- empty means everywhere, which is what every rule starts as.
  local function LoadDrop(getSet, summary, entries)
    return Dropdown(content, UI.DROP_W, entries, nil, nil, {
      multi = true,
      isChecked = function(key)
        local set = getSet(false)
        return (set and set[key]) and true or false
      end,
      onToggle = function(key)
        local set = getSet(true)
        if not set then return end
        -- nil, not false: an empty table is what "no opinion" reads as, and a
        -- table full of falses is not empty.
        set[key] = (not set[key]) or nil
        Structural()
      end,
      summary = summary,
    })
  end

  load.zoneDrop = LoadDrop(function(create)
    local r = Rule()
    if not r then return nil end
    if create then r.load = NS.NormaliseLoad(r.load) end
    return r.load and r.load.zones
  end, function()
    local r = Rule()
    return NS.LoadZoneSummary(r and r.load)
  end, NS.LoadZoneEntries())
  load.zoneLabel = Dim(content, "Load in")
  NS.EditorRow(load, content, load.zoneLabel, { load.zoneDrop, UI.DROP_W })
  TipLabel(load.zoneLabel, "Where this rule loads",
    "Tick the content you want this rule in. Nothing ticked means everywhere.\n\nA rule that does not load here is not built at all, so it costs no draw slot while you are somewhere it is switched off.")

  load.groupDrop = LoadDrop(function(create)
    local r = Rule()
    if not r then return nil end
    if create then r.load = NS.NormaliseLoad(r.load) end
    return r.load and r.load.groups
  end, function()
    local r = Rule()
    return NS.LoadGroupSummary(r and r.load)
  end, NS.LoadGroupEntries())
  load.groupLabel = Dim(content, "Group")
  NS.EditorRow(load, content, load.groupLabel, { load.groupDrop, UI.DROP_W })
  TipLabel(load.groupLabel, "Who you are with",
    "Solo, in a party, or in a raid. Nothing ticked means any of them.\n\nThis is ANDed with the zones above: dungeons plus In a party means dungeons, and only while grouped.")

  load.combat = Checkbox(content,
    function() local r = Rule() return r and r.missingCombatOnly and true or false end,
    function(v) local r = Rule() if r then r.missingCombatOnly = v or nil; Structural() end end)
  load.combatLabel = Label(content, "Only while you are in combat")
  load.combatRow = NS.EditorRow(load, content, nil, { load.combat, UI.BOX },
    { load.combatLabel, nil, 1, true })

  -- Your own target and focus. A restriction on which PLATES the rule may
  -- paint, which is the same kind of question the two lists above ask.
  load.target = Checkbox(content,
    function() local r = Rule() return r and r.onTarget ~= false end,
    function(v) local r = Rule() if r then r.onTarget = v; Structural() end end)
  load.targetLabel = Label(content, "Draw on your target")
  NS.EditorRow(load, content, nil, { load.target, UI.BOX }, { load.targetLabel, nil, 1, true })

  load.focus = Checkbox(content,
    function() local r = Rule() return r and r.onFocus ~= false end,
    function(v) local r = Rule() if r then r.onFocus = v; Structural() end end)
  load.focusLabel = Label(content, "Draw on your focus")
  NS.EditorRow(load, content, nil, { load.focus, UI.BOX }, { load.focusLabel, nil, 1, true })

  -- The bar half.
  local bar = NS.EditorBlock(content, "Healthbar Coloring")
  editor.bar = bar
  bar.enabled = Checkbox(content,
    function() local r = Rule() return r and r.barEnabled ~= false end,
    function(v)
      local r = Rule()
      if not r then return end
      -- NOT `v and nil or false`. Lua reads that as (v and nil) or false, and
      -- `true and nil` is nil, so the whole thing is false however the box was
      -- ticked -- a switch that could only ever turn the bar half OFF. Cleared
      -- rather than set true because every reader tests `~= false`, so absent
      -- means on.
      if v then r.barEnabled = nil else r.barEnabled = false end
      Structural()
    end)
  bar.head:Add(Flex.Item(bar.enabled, { width = UI.BOX, shrink = 0 }))

  bar.colorLabel = Dim(content, "Color")
  bar.swatch = ColorSwatch(content,
    function() local r = Rule() return r and r.color or NS.DefaultColor() end,
    function(r, g, b, a)
      local rule = Rule()
      if rule then rule.color = { r = r, g = g, b = b, a = a }; Restyle() end
    end)
  bar.alpha = NS.OpacitySlider(content,
    function() local r = Rule() return r and r.color or NS.DefaultColor() end,
    function(value)
      local rule = Rule()
      if not rule or not rule.color then return end
      rule.color.a = value
      Restyle()
    end)
  bar.alphaNote = Dim(content, "")
  NS.EditorRow(bar, content, bar.colorLabel, { bar.swatch, UI.BOX })
  bar.alphaLabel = Dim(content, "Opacity")
  NS.EditorRow(bar, content, bar.alphaLabel, { bar.alpha, UI.SLIDER_SM })
  NS.EditorRow(bar, content, nil, { bar.alphaNote, nil, 1, true })

  -- Fill: which of the two engines paints this rule.
  bar.fillLabel = Dim(content, "Fill")
  bar.fillDrop = Dropdown(content, UI.DROP_W, {
    { text = "Bar texture", value = "bar" },
    { text = "Pattern overlay", value = "texture" },
  },
    function() local r = Rule() return (r and r.fillStyle == "texture") and "texture" or "bar" end,
    function(value)
      local r = Rule()
      if not r then return end
      r.fillStyle = (value == "texture") and "texture" or nil
      Structural()
    end)
  NS.EditorRow(bar, content, bar.fillLabel, { bar.fillDrop, UI.DROP_W })

  -- The statusbar picker stays a dropdown: those come from LibSharedMedia, so
  -- the list is whatever the user has installed and can be a hundred long.
  bar.barTexDrop = Dropdown(content, UI.DROP_W, BarTextureEntries,
    function() local r = Rule() return r and r.barTexture end,
    function(value) local r = Rule() if r then r.barTexture = value; Restyle() end end)
  bar.barTexRow = NS.EditorRow(bar, content, nil, { bar.barTexDrop, UI.DROP_W })

  -- The patterns are ten fixed textures, so they are shown rather than named.
  -- A dropdown of "Stripes (Small, Spread)" against "Stripes (Medium)" is a
  -- reading comprehension test; the swatches answer it by being the thing.
  bar.grid = Flex.Box(content, { dir = "row", wrap = true,
    gap = UI.CHIP_GAP, crossGap = UI.CHIP_GAP })
  bar.gridChips = {}
  for _, entry in ipairs(NS.FillTextures or {}) do
    local key = entry.key
    local chip = NS.FillChip(content, function()
      local r = Rule()
      return { color = r and r.color or NS.DefaultColor(),
        fillStyle = "texture", fillTexture = key }
    end, UI.SWATCH_GRID, UI.CHIP_H)
    chip:EnableMouse(true)
    chip:SetScript("OnMouseUp", function()
      local r = Rule()
      if not r then return end
      r.fillStyle, r.fillTexture = "texture", key
      Structural()
    end)
    Tip(chip, entry.label, "Tiles across the bar. The host addon's own colour shows through the gaps.")
    -- Selection is a ring, drawn OUTSIDE the swatch. It was a filled overlay
    -- across the whole chip, which hid the one thing the chip exists to show.
    chip.sel = {}
    for index = 1, 4 do
      chip.sel[index] = chip:CreateTexture(nil, "OVERLAY")
      chip.sel[index]:SetColorTexture(RGBA(THEME.accent))
      chip.sel[index]:Hide()
    end
    chip.sel[1]:SetPoint("TOPLEFT", -2, 2);     chip.sel[1]:SetPoint("TOPRIGHT", 2, 2)
    chip.sel[2]:SetPoint("BOTTOMLEFT", -2, -2); chip.sel[2]:SetPoint("BOTTOMRIGHT", 2, -2)
    chip.sel[3]:SetPoint("TOPLEFT", -2, 2);     chip.sel[3]:SetPoint("BOTTOMLEFT", -2, -2)
    chip.sel[4]:SetPoint("TOPRIGHT", 2, 2);     chip.sel[4]:SetPoint("BOTTOMRIGHT", 2, -2)
    chip.sel[1]:SetHeight(2); chip.sel[2]:SetHeight(2)
    chip.sel[3]:SetWidth(2);  chip.sel[4]:SetWidth(2)
    chip.key = key
    bar.gridChips[#bar.gridChips + 1] = chip
    bar:Register(chip)
    bar.grid:Add(Flex.Item(chip, { width = UI.SWATCH_GRID, height = UI.CHIP_H, shrink = 0 }))
  end
  -- Two rows, always.
  --
  -- The box already wrapped, but nothing ever made it: a block's natural width
  -- is its widest child, so ten swatches in a line made this block half again
  -- as wide as the other three and the row of four could not be evenly
  -- spaced. Capping the box at half the swatches forces the wrap, and the cap
  -- is computed from the list rather than written down, so an eleventh pattern
  -- becomes six and five instead of overflowing.
  local perRow = math.ceil(#bar.gridChips / 2)
  bar.grid.maxW = perRow * (UI.SWATCH_GRID + UI.CHIP_GAP) - UI.CHIP_GAP
  bar:Add(bar.grid)

  bar.cover = Checkbox(content,
    function() local r = Rule() return r and r.missingCover and true or false end,
    function(v) local r = Rule() if r then r.missingCover = v or nil; Structural() end end)
  bar.coverLabel = Label(content, "Cover the missing-health side")
  bar.coverRow = NS.EditorRow(bar, content, nil, { bar.cover, UI.BOX },
    { bar.coverLabel, nil, 1, true })

  bar.coverColor = ColorSwatch(content,
    function() return NS.db.tints.missingCoverColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 } end,
    function(r, g, b, a)
      NS.db.tints.missingCoverColor = { r = r, g = g, b = b, a = a }
      Restyle()
    end)
  bar.coverAlpha = NS.OpacitySlider(content,
    function() return NS.db.tints.missingCoverColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 } end,
    function(value)
      local c = NS.db.tints.missingCoverColor
        or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
      c.a = value
      NS.db.tints.missingCoverColor = c
      Restyle()
    end)
  bar.coverColorNote = Dim(content, "shared by every rule that covers it")
  bar.coverAlphaLabel = Dim(content, "Opacity")
  bar.coverColorRow = NS.EditorRow(bar, content, nil, { bar.coverColor, UI.BOX },
    { bar.coverAlphaLabel, UI.LABEL_TINY }, { bar.coverAlpha, UI.SLIDER_SM })
  bar.coverNoteRow = NS.EditorRow(bar, content, nil,
    { bar.coverColorNote, nil, 1, true })

  -- The border half. Everything a border has, in the place the border is.
  local border = NS.EditorBlock(content, "Border Coloring")
  editor.border = border
  border.enabled = Checkbox(content,
    function() local r = Rule() return r and r.border and r.border.enabled and true or false end,
    function(v)
      local r = Rule()
      if not r then return end
      r.border = r.border or NS.DefaultBorder()
      r.border.enabled = v
      Structural()
    end)
  border.head:Add(Flex.Item(border.enabled, { width = UI.BOX, shrink = 0 }))

  border.colorLabel = Dim(content, "Color")
  border.swatch = ColorSwatch(content,
    function()
      local r = Rule()
      return (r and r.border and r.border.color) or { r = 1, g = 0.85, b = 0.1, a = 1 }
    end,
    function(r, g, b, a)
      local rule = Rule()
      if not rule then return end
      rule.border = rule.border or NS.DefaultBorder()
      rule.border.color = { r = r, g = g, b = b, a = a }
      Restyle()
    end)
  -- Says when the whole module is off, in the place you are trying to use it.
  -- A border half that is switched on inside a rule, in a module that is
  -- switched off, paints nothing -- and every control here would happily let
  -- you tune it for ten minutes first.
  border.alpha = NS.OpacitySlider(content,
    function()
      local r = Rule()
      return (r and r.border and r.border.color) or { r = 1, g = 0.85, b = 0.1, a = 1 }
    end,
    function(value)
      local rule = Rule()
      if not rule then return end
      rule.border = rule.border or NS.DefaultBorder()
      rule.border.color = rule.border.color or { r = 1, g = 0.85, b = 0.1, a = 1 }
      rule.border.color.a = value
      Restyle()
    end)
  border.freeNote = Dim(content, "")
  NS.EditorRow(border, content, border.colorLabel, { border.swatch, UI.BOX })
  border.alphaLabel = Dim(content, "Opacity")
  NS.EditorRow(border, content, border.alphaLabel, { border.alpha, UI.SLIDER_SM })
  NS.EditorRow(border, content, nil, { border.freeNote, nil, 1, true })

  border.thickLabel = Dim(content, "Thickness")
  border.thickness = Slider(content, UI.SLIDER_W, 1, 8, 7,
    function() local r = Rule() return (r and r.border and r.border.thickness) or 2 end,
    function(v)
      local r = Rule()
      if not r then return end
      r.border = r.border or NS.DefaultBorder()
      r.border.thickness = v
      Structural()
    end)
  NS.EditorRow(border, content, border.thickLabel, { border.thickness, UI.SLIDER_W })

  border.growLabel = Dim(content, "Grows")
  -- growDrop, not grow. These blocks ARE Flex nodes, and Flex reads `grow` off
  -- a node as its share of leftover space -- so storing a dropdown there had
  -- the layout doing arithmetic on a frame, which took the whole page down the
  -- moment a rule was opened. Anything hung on a node has to dodge the
  -- engine's own property names.
  border.growDrop = Dropdown(content, UI.DROP_SM_W, {
    { text = "Outward", value = "OUT" },
    { text = "Inward", value = "IN" },
  },
    function() local r = Rule() return (r and r.border and r.border.grow) or "OUT" end,
    function(value)
      local r = Rule()
      if not r then return end
      r.border = r.border or NS.DefaultBorder()
      r.border.grow = value
      Structural()
    end)
  NS.EditorRow(border, content, border.growLabel, { border.growDrop, UI.DROP_SM_W })

  border.padLabel = Dim(content, "Gap")
  border.padding = Slider(content, UI.SLIDER_W, 0, 12, 13,
    function() local r = Rule() return (r and r.border and r.border.padding) or 0 end,
    function(v)
      local r = Rule()
      if not r then return end
      r.border = r.border or NS.DefaultBorder()
      r.border.padding = v
      Structural()
    end)
  NS.EditorRow(border, content, border.padLabel, { border.padding, UI.SLIDER_W })

  -- Two rows of two, as a box:
  --
  --   Tracked Spells      Load Conditions
  --   Healthbar Coloring  Border Coloring
  --
  -- Two explicit rows rather than one wrapping row of four. Wrapping put
  -- three across and one underneath at most window widths, because how many
  -- fit is decided by measured width -- and "three and one" is never the
  -- layout that was wanted. Each row still wraps on its own, so a genuinely
  -- narrow window collapses to a single column instead of overflowing.
  local blocks = Flex.Box(content, { dir = "column", gap = UI.GROUP_GAP })
  local topRow = Flex.Box(content, { dir = "row", wrap = true, gap = UI.GROUP_GAP,
    crossGap = UI.GROUP_GAP, align = "stretch" })
  topRow:Add(when)
  topRow:Add(load)
  local bottomRow = Flex.Box(content, { dir = "row", wrap = true, gap = UI.GROUP_GAP,
    crossGap = UI.GROUP_GAP, align = "stretch" })
  bottomRow:Add(bar)
  bottomRow:Add(border)
  blocks:Add(topRow)
  blocks:Add(bottomRow)
  editor:Add(blocks)

  sec.editor = editor
  return editor
end

-- A debuff the rule fires on: its icon, its name, and the way off it.
function NS.EditorPill(parent)
  local pill = NS.Flex.Box(parent, { dir = "row", align = "center",
    gap = NS.UI.PILL_PAD, height = NS.UI.PILL_H,
    pad = { l = NS.UI.PILL_PAD, r = NS.UI.PILL_PAD } })

  pill.bg = pill.frame:CreateTexture(nil, "BACKGROUND")
  pill.bg:SetAllPoints()
  pill.bg:SetColorTexture(0.16, 0.16, 0.20, 1)

  pill.icon = pill.frame:CreateTexture(nil, "ARTWORK")
  pill.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  pill:Add(NS.Flex.Item(pill.icon,
    { width = NS.UI.PILL_ICON, height = NS.UI.PILL_ICON, shrink = 0 }))

  pill.label = Label(pill.frame, "")
  pill.label:SetJustifyH("LEFT")
  pill:Add(NS.Flex.Item(pill.label, { clipText = true }))

  pill.remove = CloseX(parent, function()
    if pill.onRemove then pill.onRemove() end
  end)
  pill:Add(NS.Flex.Item(pill.remove,
    { width = NS.UI.CLOSE_X, height = NS.UI.CLOSE_X, shrink = 0 }))
  return pill
end

function NS.RefreshRuleEditor(sec)
  local editor = sec.editor
  local rule = sec.openRule
  if not editor or not rule then return end
  local when, bar, border = editor.when, editor.bar, editor.border
  local load = editor.load

  -- One pill per debuff, pooled by position: which spell sits at index 2
  -- changes every time one is removed.
  local conditions = rule.conditions or {}
  for index, condition in ipairs(conditions) do
    local pill = when.pillPool[index]
    if not pill then
      pill = NS.EditorPill(sec.content)
      when.pillPool[index] = pill
      when.pills:Add(pill)
    end
    pill.hidden = false
    pill.icon:SetTexture(NS.SpellIcon(condition.spellID))
    pill.label:SetText(NS.SpellName(condition.spellID) or tostring(condition.spellID))
    pill.onRemove = function()
      for at, existing in ipairs(rule.conditions or {}) do
        if existing.spellID == condition.spellID then
          table.remove(rule.conditions, at)
          break
        end
      end
      Structural()
    end
  end
  for index = #conditions + 1, #when.pillPool do
    when.pillPool[index].hidden = true
  end

  -- What is left, and why. A limit that only announces itself by refusing a
  -- click is a limit people meet twice.
  local limit = RuleConditionLimit(rule)
  local room = limit - #conditions
  if room <= 0 then
    when.limit:SetText(rule.showWhenMissing
      and "|cffffcc00A MISSING rule can only carry one debuff.|r"
      or ("|cffffcc00Full: %d debuffs is the most a rule can require.|r"):format(limit))
  else
    when.limit:SetText(("%d of %d debuffs -- all of them must be on the target")
      :format(#conditions, limit))
  end
  when.addDrop.Refresh()
  when.addDrop:SetShown(room > 0)
  when.idBox:SetShown(room > 0)
  when.idLabel:SetShown(room > 0)

  when.modeDrop.Refresh()
  load.target.Refresh()
  load.focus.Refresh()
  load.zoneDrop.Refresh()
  load.groupDrop.Refresh()
  -- In-combat belongs to missing rules: a presence rule has no "not yet
  -- applied" state to hold anything off of.
  load.combatRow.hidden = not rule.showWhenMissing
  if not load.combatRow.hidden then load.combat.Refresh() end

  bar.enabled.Refresh()
  bar.swatch.Refresh()
  bar.alpha.Refresh()
  bar.fillDrop.Refresh()
  local textured = rule.fillStyle == "texture"
  bar.barTexRow.hidden = textured
  bar.grid.hidden = not textured
  if not textured then bar.barTexDrop.Refresh() end
  for _, chip in ipairs(bar.gridChips) do
    chip.Refresh()
    local on = textured and rule.fillTexture == chip.key
    for _, edge in ipairs(chip.sel) do edge:SetShown(on) end
  end

  -- A missing rule is lit by DEFAULT on every mob rather than occasionally, so
  -- an opaque colour covers the bar and everything on it all the time.
  local alpha = (rule.color and rule.color.a) or 1
  if rule.showWhenMissing and alpha > 0.45 then
    bar.alphaNote:SetText(("|cffffcc00%d%% opaque -- around 30%% reads as a reminder|r")
      :format(math.floor(alpha * 100 + 0.5)))
  else
    bar.alphaNote:SetText("")
  end

  bar.cover.Refresh()
  bar.coverColorRow.hidden = not rule.missingCover
  bar.coverNoteRow.hidden = not rule.missingCover
  if rule.missingCover then
    bar.coverColor.Refresh()
    bar.coverAlpha.Refresh()
  end

  local off = rule.barEnabled == false
  bar:SetOff(off)
  bar.colorLabel:SetAlpha(off and 0.4 or 1)
  bar.fillLabel:SetAlpha(off and 0.4 or 1)

  border.enabled.Refresh()
  border:SetOff(not (rule.border and rule.border.enabled))
  border.swatch.Refresh()
  border.alpha.Refresh()
  border.freeNote:SetText("")
  border.thickness.Refresh()
  border.growDrop.Refresh()
  border.padding.Refresh()
end

-- Move an existing child of a Flex box to sit directly after another child.
--
-- Flex fixes a node's order when it is added, and the editor band has to
-- follow whichever row is open. Reordering the children array is safe -- a
-- node's parent link and its frame parentage are untouched, and the next
-- Layout reads the array fresh. Rebuilding the band per row would leak a
-- frame per rule instead, since a frame cannot be destroyed.
function NS.FlexMoveAfter(parent, node, after)
  local kids = parent.children
  local from, to
  for index, child in ipairs(kids) do
    if child == node then from = index end
    if child == after then to = index end
  end
  if not from then return end
  table.remove(kids, from)
  if not to then
    kids[#kids + 1] = node
    return
  end
  -- Recomputed: removing the node may have shifted the target down one.
  for index, child in ipairs(kids) do
    if child == after then to = index break end
  end
  table.insert(kids, to + 1, node)
end

-- NS.RulePreview is gone. The page's own stage at the top is the only preview
-- now: two of them showing one rule updated on different passes, so one was
-- always a step behind the other, and a preview you cannot trust is worse than
-- the one you have to look up at.

-- A hairline divider as a Flex node.
--
-- Through PixelUtil where the client has it: at a non-integer UI scale a plain
-- 1px texture lands between physical pixels and renders as a soft two-pixel
-- smear, or vanishes. The same reason NS.BuildOutline uses it for the plate
-- border. Three separate copies of this existed, each with its own inset.
function NS.FlexRule(parent, inset)
  inset = inset or NS.UI.ROW_INSET
  local node = NS.Flex.Box(parent, { height = NS.UI.DIVIDER, pad = { l = inset, r = inset } })
  node.line = node.frame:CreateTexture(nil, "ARTWORK")
  node.line:SetAllPoints()
  node.line:SetColorTexture(RGBA(THEME.divider))
  if PixelUtil and PixelUtil.SetHeight then
    pcall(PixelUtil.SetHeight, node.line, NS.UI.DIVIDER)
  end
  return node
end

-- Vertical column separators for the rule table.
--
-- Drawn on the ROW's own frame rather than on each cell: the pinned threat row
-- places its cells with plain Flex.Items and the rule rows use FlexCells, so a
-- separator owned by a cell would appear on one row shape and not the other.
-- Every column right of the rule name is fixed width, so the offsets are
-- arithmetic off the right edge and every row agrees on them by construction.
--
-- To tune: THEME.tableSep for the colour (alpha is what makes it faint), and
-- the `order` list below for which boundaries get a line at all.
function NS.ColumnSepOffsets()
  local C, UI = NS.RULE_COLS, NS.UI
  local order = { C.on, C.del, C.edit, C.cost, C.border, C.bar }
  local offsets, x = {}, UI.ROW_INSET
  for _, width in ipairs(order) do
    x = x + width
    offsets[#offsets + 1] = x + UI.COL_GAP / 2
    x = x + UI.COL_GAP
  end
  return offsets
end

function NS.PaintColumnSeps(frame)
  frame.colSeps = frame.colSeps or {}
  for index, offset in ipairs(NS.ColumnSepOffsets()) do
    local line = frame.colSeps[index]
    if not line then
      line = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
      line:SetColorTexture(RGBA(THEME.tableSep))
      frame.colSeps[index] = line
    end
    line:ClearAllPoints()
    line:SetPoint("TOP", frame, "TOPRIGHT", -offset, 0)
    line:SetPoint("BOTTOM", frame, "BOTTOMRIGHT", -offset, 0)
    line:SetWidth(NS.PixelWeight(frame))
  end
  return frame.colSeps
end

-- A heading centred over a fixed column, for the same reason.
function NS.FlexHeaderCell(parent, text, width)
  local label = Header(parent, text)
  label:SetJustifyH("CENTER")
  return NS.FlexCell(parent, width, NS.Flex.Item(label)), label
end

-- Explanatory text, inset from the section's edges.
--
-- A Flex.Item cannot carry padding -- pad is read off BOXES, so `pad` on a
-- leaf is silently ignored, which is why every footnote on these pages sat
-- flush against the section's left edge while the rows above it were inset by
-- twelve. Wrapping the FontString in a one-child box is the fix, and the box
-- is what the indent belongs to anyway.
function NS.FlexNote(parent, fontString, indent)
  local node = NS.Flex.Box(parent, {
    dir = "column",
    pad = { l = indent or NS.UI.NOTE_INSET, r = NS.UI.NOTE_INSET, t = 2, b = 2 },
  })
  fontString:SetJustifyH("LEFT")
  node:Add(NS.Flex.Item(fontString, { wrapText = true, grow = 1 }))
  return node
end

-- What the two stage-preview dropdowns offer.
--
-- Only states that are switched ON. A dropdown listing a colour the profile
-- would never draw invites you to preview something and then wonder why the
-- plate in the game does not match.
function NS.StageThreatEntries()
  local out = { { text = "Threat: off", value = false } }
  for _, state in ipairs(NS.ThreatStatesOrdered and NS.ThreatStatesOrdered() or {}) do
    local bar = NS.ThreatModule("bar").states[state.key]
    local border = NS.ThreatModule("border").states[state.key]
    local on = (bar and bar.enabled ~= false) or (border and border.enabled ~= false)
    if on then
      out[#out + 1] = { text = NS.ThreatStateLabel(state.key), value = state.key }
    end
  end
  return out
end

function NS.StageMarkEntries()
  local out = { { text = "Target/Focus: off", value = false } }
  -- Every state, including the switched-off ones.
  --
  -- Focus ships off -- most people do not keep one -- and this hid it from
  -- the preview entirely, so the one state you would want to LOOK at before
  -- turning on was the one state you could not. A control that silently drops
  -- an option reads as a missing feature, not as a filter.
  --
  -- Said out loud rather than left to be inferred, so a preview that draws
  -- nothing on a real plate is explained where you picked it.
  for _, state in ipairs(NS.MARK_STATES or {}) do
    local bar = NS.MarkModule("bar").states[state.key]
    local border = NS.MarkModule("border").states[state.key]
    local on = (bar and bar.enabled ~= false) or (border and border.enabled ~= false)
    out[#out + 1] = {
      text = on and NS.MarkStateLabel(state.key)
        or ("%s  |cff808080(off)|r"):format(NS.MarkStateLabel(state.key)),
      value = state.key,
    }
  end
  return out
end

function NS.MarkShapeEntries()
  local out = {}
  -- The DRAWABLE list, not every shape defined: several come from
  -- EllesmereUI's own art and only exist while that addon is installed.
  for _, entry in ipairs(NS.MarkShapeList and NS.MarkShapeList() or {}) do
    out[#out + 1] = { text = entry.label, value = entry.key }
  end
  return out
end

-- Where a marker sits, as dropdown entries.
function NS.MarkPositionEntries()
  local out = {}
  for _, entry in ipairs(NS.MARK_INDICATOR_POSITIONS or {}) do
    out[#out + 1] = { text = entry.label, value = entry.key }
  end
  return out
end

function NS.ThreatRoleEntries()
  local entries = {}
  for _, role in ipairs(NS.THREAT_ROLES) do
    table.insert(entries, { text = role.label, value = role.key })
  end
  return entries
end

function NS.ThreatModule(kind)
  if kind == "border" then return NS.ThreatBorderConfig() end
  return NS.ThreatConfig()
end

-- "tank role - 3 of 4 states". Says what the strip cannot: which reading is in
-- force, and whether anything is switched off.
function NS.ThreatSummary(kind)
  local cfg = NS.ThreatModule(kind)
  local on = 0
  for _, state in ipairs(NS.THREAT_STATES) do
    local entry = cfg.states[state.key]
    if entry and entry.enabled ~= false then on = on + 1 end
  end
  local states = on == #NS.THREAT_STATES and ("%d states"):format(on)
    or ("%d of %d states"):format(on, #NS.THREAT_STATES)
  return ("%s role |cff5a5a62-|r %s |cff5a5a62-|r in combat only"):format(
    NS.ThreatRole(), states)
end

-- One clickable colour chip per state. Clicking opens the picker for that
-- state; a state that is switched off is drawn faint, so the strip shows what
-- is ACTIVE rather than four colours regardless.
-- The threat SECTION is gone. It was a card above the rule list holding a
-- summary row and, behind Edit, four state rows -- which is the rule table's
-- job, done twice, in a second place. Threat is the top row of that table now
-- (NS.BuildThreatPinnedRow) and its editor is a band in it
-- (NS.BuildThreatBand), so there is one table on one page.

-- Width-in, height-out. The content frame is anchored to both edges of the
-- section, so its width is real before anything has been sized; its height is
-- what this computes. Falling back to the section's own width covers the very
-- first render, before either has been laid out.
function NS.FlexResize(sec)
  local width = sec.content:GetWidth()
  if not width or width < 1 then width = sec:GetWidth() or 690 end
  local height = sec.flex:Layout(width)
  sec.flex:Apply()
  sec:Resize(height)
  if sec.onResize then sec.onResize(sec) end

  -- The sections BELOW this one have to move too, and nothing else does that:
  -- a body section carries no onResize (only the page head does), and each
  -- section is anchored at a y the page computed once. So growing one -- which
  -- is what opening Edit does -- left it drawing straight through its
  -- neighbour. LayoutSections re-anchors the whole stack from the new heights,
  -- and is cheap enough to run on any resize.
  local body = sec:GetParent()
  if body and body.sections then LayoutSections(body, body.sections) end
end

local function BuildHealthTab()
  -- No enable checkbox here any more: the module's switch lives on its
  -- heading in the rail (see MODULE_SWITCH), where it is visible without
  -- opening the page first.
  local panel = BuildTabFrame(tabPanels[1])

  local head = panel.head
  head.verdict = Label(head, "")
  head.verdict:SetPoint("TOPLEFT", HEAD_PAD, -(6 + STAGE_H + 8))
  head.togglesLabel = Dim(head, "")
  head.togglesLabel:SetPoint("TOPLEFT", HEAD_PAD, -(6 + STAGE_H + 30))
  head.toggles = {}

  -- Under the debuff list, because that is where someone stands at a dummy
  -- ticking boxes and believing what they see.
  --
  -- A training dummy never puts you in combat: UnitAffectingCombat is false
  -- the whole time you are hitting one, so every "only while you are in
  -- combat" condition -- rules, threat, missing-debuff timers -- reads as
  -- out of combat and the plate looks wrong for reasons that have nothing to
  -- do with the rule being tested.
  head.dummyWarn = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  StyleText(head.dummyWarn, 11)
  head.dummyWarn:SetJustifyH("LEFT")
  head.dummyWarn:SetText(
    "WARNING: TRAINING DUMMIES DO NOT ALLOW ACCURATE TESTING OF \"IN COMBAT\" CONDITIONS")
  head.dummyWarn:SetTextColor(1, 0.25, 0.25)

  -- Preview-only, shared with the border tab: someone running both wants to
  -- see how the two look together.
  --
  -- A button in the same column and format as the test buttons, since it
  -- belongs to the same group -- a lone checkbox read as a different class of
  -- control. Hidden entirely when the other module is off.
  -- No "Show Border Rules" button.
  --
  -- It existed to overlay one list's rules on the other list's preview. With
  -- one list there is nothing to combine: the preview already draws both
  -- halves of whichever rule is winning.


  local body = panel.body
  body.sections = {}

  -- Above everything, because it is the map of everything below it.
  local ladder = CollapsibleSection(body, "resolution", "What Colors This Plate",
    "top to bottom, the order these are decided in")
  table.insert(body.sections, ladder)
  body.ladder = ladder

  local rules = CollapsibleSection(body, "colourRules", "Spell Rules",
    "higher rules override lower ones - the topmost match is what you see")
  table.insert(body.sections, rules)
  body.rules = rules
  NS.SlotMeter(rules)

  local c = rules.content
  -- Centred over the whole UP / number / DOWN cluster rather than
  -- left-aligned, which read as a label for UP alone.

  -- "Order" rather than "Priority": the number is gone -- position IS the
  -- priority, and you set it by dragging.
  rules.hOrder = Header(c, "Order")
  rules.hOrder:SetPoint("TOPLEFT", 8, -6)
  rules.hDebuffs = Header(c, "Rule")
  rules.hDebuffs:SetPoint("TOPLEFT", 52, -6)
  rules.hEdit = Header(c, "Edit")
  rules.hEdit:SetPoint("TOPLEFT", 470, -6)
  rules.hDelete = Header(c, "Del")
  rules.hDelete:SetPoint("TOPLEFT", 556, -6)
  rules.hOn = Header(c, "On")
  rules.hOn:SetPoint("TOPLEFT", 600, -6)

  rules.divider = c:CreateTexture(nil, "ARTWORK")
  rules.divider:SetPoint("TOPLEFT", 10, -22)
  rules.divider:SetPoint("TOPRIGHT", -10, -22)
  rules.divider:SetHeight(1)
  rules.divider:SetColorTexture(0.4, 0.4, 0.45, 0.6)

  rules.note = Dim(c, "Fully opaque colors hide overlays other nameplate addons draw inside the bar (highlights, hash lines, absorb markers).")
  rules.note:SetWidth(650)
  rules.note:SetJustifyH("LEFT")

  rules.warning = Label(c, "")
  rules.warning:SetWidth(650)
  rules.warning:SetJustifyH("LEFT")

  rules.newButton = Button(c, "New Rule", 100, function()
    local rule = NS.NormaliseRule({ color = NS.DefaultColor(), conditions = {}, enabled = true })
    table.insert(NS.db.tints.rules, rule)
    expandedRule = rule
    Structural()
  end)
  rules.sortButton = Button(c, "Auto sort", 100, function()
    NS.SortRules()
    expandedRule = nil
    Structural()
  end)

  -- One shared colour for every rule's "Cover missing health", below the table
  -- and behind a rule of its own -- it belongs to the list, and the divider is
  -- what says so. The same swatch is in each rule's appearance panel; both
  -- edit one value.
  --
  -- Health list only: border rules paint no bar.
  rules.missingDivider = c:CreateTexture(nil, "ARTWORK")
  rules.missingDivider:SetHeight(1)
  rules.missingDivider:SetColorTexture(0.4, 0.4, 0.45, 0.6)
  rules.missingDivider:Hide()

  rules.missingLabel = Label(c, "Missing health color")
  rules.missingLabel:Hide()

  rules.missingSwatch = ColorSwatch(c,
    function()
      return (NS.MissingCoverColor and NS.MissingCoverColor())
        or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
    end,
    function(r, g, b, a)
      NS.db.tints.missingCoverColor = { r = r, g = g, b = b, a = a }
      if NS.ApplyTintColors then NS.ApplyTintColors() end
      RefreshPreviews()
    end)
  rules.missingSwatch:Hide()

  rules.missingHint = Dim(c, "shared by every rule that covers missing health")
  rules.missingHint:Hide()

  -- What a missing rule paints once its debuff is APPLIED. Global rather than
  -- per rule, for the same reason as the missing-health swatch above.
  -- Occlusion only -- displacement has no cover to colour.
  rules.classDivider = c:CreateTexture(nil, "ARTWORK")
  rules.classDivider:SetHeight(1)
  rules.classDivider:SetColorTexture(0.4, 0.4, 0.45, 0.6)
  rules.classDivider:Hide()

  rules.classCheck = Checkbox(c,
    function() return NS.db.tints.missingAppliedByClass and true or false end,
    function(v)
      NS.db.tints.missingAppliedByClass = v
      -- Covers are repainted by the poll, not rebuilt, so this is a repaint
      -- rather than a Structural().
      for _, rig in pairs(NS.rigs or {}) do
        if NS.UpdateCovers then pcall(NS.UpdateCovers, rig) end
      end
      NS.Options_RebuildAll()
      RefreshPreviews()
    end)
  rules.classCheck:Hide()
  Tip(rules.classCheck, "Color by mob rank once applied", TIPS.appliedByClass)

  rules.classLabel = Label(c, "Color by mob rank once applied")
  rules.classLabel:Hide()
  TipLabel(rules.classLabel, "Color by mob rank once applied", TIPS.appliedByClass)

  rules.classHint = Dim(c, "instead of restoring the bar's own color")
  rules.classHint:Hide()

  -- Order is strongest first, which is also the order they matter in.
  rules.classSwatches = {}
  for _, entry in ipairs({
    { key = "boss",       text = "Boss" },
    { key = "lieutenant", text = "Lieutenant" },
    { key = "caster",     text = "Caster" },
    { key = "rare",       text = "Rare" },
    { key = "elite",      text = "Elite" },
    { key = "normal",     text = "Normal" },
  }) do
    local key = entry.key
    local item = {}
    item.label = Dim(c, entry.text)
    item.label:Hide()
    item.swatch = ColorSwatch(c,
      function()
        local colors = NS.db.tints.missingAppliedClassColors or {}
        -- The default for THIS tier, not a placeholder grey: a key that has
        -- gone missing should read as its shipped colour rather than as a
        -- deliberate dark choice nobody made.
        return colors[key]
          or NS.Defaults.tints.missingAppliedClassColors[key]
      end,
      function(r, g, b, a)
        NS.db.tints.missingAppliedClassColors = NS.db.tints.missingAppliedClassColors or {}
        NS.db.tints.missingAppliedClassColors[key] = { r = r, g = g, b = b, a = a }
        for _, rig in pairs(NS.rigs or {}) do
          if NS.UpdateCovers then pcall(NS.UpdateCovers, rig) end
        end
        RefreshPreviews()
      end)
    item.swatch:Hide()
    table.insert(rules.classSwatches, item)
  end

  -- Shared by the dropdown and the ID box. The Cooldown Manager cannot offer
  -- every usable ID -- an ability whose aura is a separate spell has no CDM
  -- entry for the aura at all -- so typing one has to be first-class.
  --
  -- input is a dropdown ID or raw text; both resolve to the aura's own ID
  -- before the duplicate check, so it compares what will be stored.
  local function AddConditionToExpanded(input)
    local rule = expandedRule
    if not rule or not input then return end
    local spellID = ResolveAndReport(input)
    if not spellID then return end
    for _, cond in ipairs(rule.conditions) do if cond.spellID == spellID then return end end
    -- Missing rules are single-debuff and cannot be raised; see
    -- RuleConditionLimit, which is the shared answer for both add paths.
    local limit = RuleConditionLimit(rule)
    if #rule.conditions >= limit then
      NS.Print(rule.showWhenMissing
        and "A rule that shows when MISSING can only have one debuff."
        or ("A rule can require at most %d debuffs."):format(limit))
      return
    end

    local function Commit()
      table.insert(rule.conditions, { spellID = spellID })
      -- Keep specific rules above general ones without the user thinking.
      -- Identity survives the reshuffle, so the rule stays open.
      NS.SortRules()
      Structural()
    end

    -- Cost is multiplicative: containers pool ~10 buttons each, and a rule
    -- The cost warning that used to live here is gone: with aura slots a
    -- two-debuff rule costs one texture and one extra frame. See the matching
    -- note in AddConditionTo.
    Commit()
  end

  rules.addCondDrop = AddSpellDropdown(c, 250, "Add a debuff to this rule...",
    function(spellID)
      local rule = expandedRule
      if not rule then return false end
      for _, cond in ipairs(rule.conditions) do if cond.spellID == spellID then return true end end
      return false
    end,
    AddConditionToExpanded)

  rules.addCondBox = IDBox(c, AddConditionToExpanded)
  rules.addCondBoxLabel = Dim(c, "or ID/name:")

  -- Fill style plus show-on-target/focus, same panel shape as the border
  -- list's shape controls.
  rules.style = BuildStylePanel(c, false)
  rules.style:Hide()


  healthTab = panel
  panel.RefreshPreview = function()
    local headFrame = panel.head
    local spells = RuleSpells()
    for _, t in ipairs(headFrame.toggles) do t:Hide() end

    for index, spellID in ipairs(spells) do
      local t = headFrame.toggles[index]
      if not t then
        -- The closures read t.spellID rather than closing over the spell,
        -- because these are pooled by position: which spell sits at index 3
        -- changes every time the rule list does.
        -- Guarded against `box` still being nil: Checkbox runs its getter once
        -- during construction, before this assignment has completed.
        local box
        box = Checkbox(headFrame,
          function() return box ~= nil and preview.active[box.spellID] and true or false end,
          function(value)
            if box then
              preview.active[box.spellID] = value
              RefreshPreviews()
            end
          end)
        t = box
        -- Parented to the checkbox so one Hide() takes the whole entry with
        -- it; on the head frame they lingered after the list shrank.
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(18, 18)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.icon:SetPoint("LEFT", t, "RIGHT", 6, 0)
        t.label = Label(t, "")
        t.label:SetPoint("LEFT", t.icon, "RIGHT", 5, 0)
        headFrame.toggles[index] = t
      end
      t.spellID = spellID
      t.Refresh()
      t.label:SetText(NS.SpellName(spellID))
      t.icon:SetTexture(NS.SpellIcon(spellID))
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT",
        HEAD_PAD + ((index - 1) % 3) * 220,
        -(6 + STAGE_H + 28) - math.floor((index - 1) / 3) * 26)
      t:Show()
    end

    -- Every shared control in the head, not just the buttons. combine and the
    -- module toggle are driven from BOTH colouring tabs, so a change made on
    -- one leaves the other face stale until it is told to re-read.
    if headFrame.testButton then headFrame.testButton.Refresh() end
    if headFrame.testAllButton then headFrame.testAllButton.Refresh() end
    -- Rebuilt from the profile every pass: switching a threat state off has to
    -- take it out of the list, and clear it if it was the one being previewed.
    if headFrame.threatPreview then
      if NS.stagePreview.threat and not NS.StagePreviewThreat("bar")
        and not NS.StagePreviewThreat("border") then
        NS.stagePreview.threat = nil
      end
      headFrame.threatPreview.Refresh()
    end
    if headFrame.markPreview then
      if NS.stagePreview.mark and not NS.StagePreviewMark("bar")
        and not NS.StagePreviewMark("border") then
        NS.stagePreview.mark = nil
      end
      headFrame.markPreview.Refresh()
    end
    if headFrame.enable then headFrame.enable.Refresh() end
    -- The test buttons say whether test mode is running and in which scope,
    -- so they have to be refreshed wherever they appear -- not only on the
    -- page that used to own them.
    if headFrame.testButton then headFrame.testButton.Refresh() end
    if headFrame.testAllButton then headFrame.testAllButton.Refresh() end

    local stage = headFrame.stage

    -- The missing wash, drawn whether or not a presence rule matches -- it is
    -- lit precisely when you have not applied something.
    --
    -- Safe to show now that presence tints draw ABOVE it. While it sat on top
    -- this washed over whatever tint you were trying to look at.
    local missingRule = PreviewMissingRule()
    -- Its wash, but only if it HAS one. The bar half's switch was read by the
    -- engine and by the winning-rule branch below, and not here -- so turning
    -- Healthbar Coloring off on a MISSING rule left the preview painting the
    -- colour it had just been told to stop using, which reads as the switch
    -- doing nothing. The rule itself still stands: its border half is decided
    -- further down from the same variable.
    if missingRule and missingRule.barEnabled == false then
      stage.missingWash:Hide()
      if stage.missingCover then stage.missingCover:Hide() end
    elseif missingRule then
      NS.ApplyRuleFill(stage.missingWash, stage.bar, missingRule)
      stage.missingWash:Show()
      -- Its cover too. This only ever followed the winning PRESENCE rule, so
      -- ticking "cover the missing-health side" on a missing rule -- the rule
      -- most likely to want one -- changed nothing on the preview.
      if NS.ApplyMissingCover then
        NS.ApplyMissingCover(stage.missingCover, stage.bar, missingRule)
      end
    else
      stage.missingWash:Hide()
    end
    if #spells == 0 then
      headFrame.verdict:SetText("|cff808080Add a rule below and it will be previewed here.|r")
      headFrame.togglesLabel:Hide()
      stage.tint:Hide()
      if not missingRule then stage.missingCover:Hide() end
      -- Borders are decided above, for both kinds of rule.
      if not borderRule then
        for _, e in ipairs(stage.borderEdges) do e:Hide() end
      end
    else
      headFrame.togglesLabel:Show()
      local winner, matches, ticked = EvaluatePreview()

      -- Whose border is on the plate.
      --
      -- This lived inside `if winner then`, so a MISSING rule -- which lights
      -- precisely when no presence rule is matching -- could never show its
      -- border here. Same question, asked once, outside the branch that is
      -- about the BAR: the winning rule's border if it has one, otherwise a
      -- lit missing rule's.
      local borderRule
      if winner and winner.border and winner.border.enabled then
        borderRule = winner
      elseif missingRule and missingRule.border and missingRule.border.enabled then
        borderRule = missingRule
      end
      DrawStageBorder(stage, borderRule)

      -- Show the edge inset, but against the BAR rather than the fill: the
      -- point is to see how much border the inset leaves, and tying it to a
      -- 72%-wide fill made the preview shrink for reasons unrelated to rules.
      local inset = NS.FillInset and NS.FillInset() or 1
      stage.tint:ClearAllPoints()
      local fill = stage.bar:GetStatusBarTexture()
      stage.tint:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
      stage.tint:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -inset, inset)

      -- The previewed bands, in the order the engine resolves them: threat
      -- claims its slots first, target/focus next, spell rules under both. So
      -- a previewed threat state covers a previewed target colour, which
      -- covers whichever rule won -- and neither dropdown can be overridden
      -- by the other by accident, because each holds one key at a time.
      local topPreview = (NS.StagePreviewThreat and NS.StagePreviewThreat("bar"))
        or (NS.StagePreviewMark and NS.StagePreviewMark("bar"))
      local topBorderPreview, borderCfg
      if NS.StagePreviewThreat and NS.StagePreviewThreat("border") then
        topBorderPreview, borderCfg = NS.StagePreviewThreat("border"), NS.ThreatBorderConfig()
      elseif NS.StagePreviewMark and NS.StagePreviewMark("border") then
        topBorderPreview, borderCfg = NS.StagePreviewMark("border"), NS.MarkBorderConfig()
      end
      if topBorderPreview then
        DrawStageBorder(stage, { border = {
          enabled = true, color = topBorderPreview.color,
          thickness = borderCfg.thickness or 2,
          grow = borderCfg.grow or "OUT",
          padding = borderCfg.padding or 0,
        } })
      end

      -- The marker belongs to the target/focus preview only: threat has none.
      DrawStageMarkers(stage, NS.StagePreviewMark and NS.StagePreviewMark("bar"))

      if topPreview then
        NS.ApplyRuleFill(stage.tint, stage.bar, topPreview)
        stage.tint:Show()
      elseif winner then
        if winner.barEnabled ~= false then
          -- Through the same fill logic the real bar uses, so a rule set to
          -- Colored Texture actually PREVIEWS as a texture instead of always
          -- reading as solid regardless of what it is set to.
          NS.ApplyRuleFill(stage.tint, stage.bar, winner)
          stage.tint:Show()
          if NS.ApplyMissingCover then
            NS.ApplyMissingCover(stage.missingCover, stage.bar, winner)
          end
        else
          stage.tint:Hide()
          stage.missingCover:Hide()
        end
        -- Say how many rules matched, not just which won. A rule that is
        -- being outranked looks identical to one that never matched, and
        -- that ambiguity is most of what made this feel unreliable.
        local extra = (#matches > 1)
          and ("  |cff808080(%d matched, top one wins)|r"):format(#matches)
          or ""
        -- Say when a missing rule is lit UNDERNEATH the winner. Otherwise the
        -- bar is showing two rules and the verdict names one, and the missing
        -- one looks like it is not working when it is simply covered -- which
        -- is exactly what the table warning is about.
        if missingRule then
          extra = extra .. ("  |cffffcc22(covering a MISSING rule: %s)|r")
            :format(NS.SpellName(missingRule.conditions[1].spellID) or "?")
        end
        headFrame.verdict:SetText(("Winning rule: |cff55dd55%s|r%s")
          :format(NS.RuleSummary(winner), extra))
      else
        stage.tint:Hide()
        -- The branch a MISSING rule always lands in: no presence rule matched,
        -- which is when a missing one is lit. It was hiding that rule's cover
        -- and then redrawing the border from the retired two-list logic --
        -- overwriting the border decided above with nothing. That is why
        -- borders previewed on normal rules and never on missing ones.
        if not missingRule then
          stage.missingCover:Hide()
        end
        -- A missing rule is a RESULT, not a failure to match, so it is
        -- answered before the "nothing matched" states below -- otherwise the
        -- bar is visibly coloured while the verdict says no rule applies.
        if missingRule then
          headFrame.verdict:SetText(("|cffffcc22MISSING rule: %s is not applied.|r  |cff808080Tick it to clear the bar.|r")
            :format(NS.SpellName(missingRule.conditions[1].spellID) or "?"))
        -- Three distinct states. A single blank bar for all of them reads as
        -- a broken preview.
        elseif ticked == 0 then
          headFrame.verdict:SetText("|cffffcc00Tick a debuff below to preview a rule.|r")
        else
          -- Name what is ticked and what each rule still wants. "No rule
          -- matches" on its own is indistinguishable from a broken preview,
          -- which is exactly the complaint this replaces.
          local on = {}
          for _, spellID in ipairs(spells) do
            if preview.active[spellID] then table.insert(on, NS.SpellName(spellID)) end
          end

          -- Same reason as EvaluatePreview: this explains the preview, so it
          -- has to see the same rules the preview does.
          local missing
          for _, rule in ipairs(NS.GetOrderedRules(true)) do
            local want = {}
            for _, c in ipairs(rule.conditions) do
              if not preview.active[c.spellID] then
                table.insert(want, NS.SpellName(c.spellID))
              end
            end
            -- The closest rule: the one needing fewest more ticks.
            if #want > 0 and (not missing or #want < #missing.want) then
              missing = { rule = rule, want = want }
            end
          end

          headFrame.verdict:SetText(("|cff808080Ticked: %s. %s|r"):format(
            table.concat(on, ", "),
            missing and ("Nearest rule also needs " .. table.concat(missing.want, " + ") .. ".")
              or "No rule uses these together."))
        end
      end
    end

    -- Measured, not padded. The toggles start at STAGE_H + 28 and step 26, so
    -- the last row's bottom is exactly this -- the old constant reserved a
    -- row's worth of space that nothing ever occupied, and with no rules at
    -- all (rows = 0) it reserved a whole row for a verdict line alone.
    local rows = math.ceil(#spells / 3)
    -- Under the last row of debuffs, wherever that lands, and the head grows
    -- by exactly the line it adds.
    local warnTop = 6 + STAGE_H + 30 + rows * 26
    headFrame.dummyWarn:ClearAllPoints()
    headFrame.dummyWarn:SetPoint("TOPLEFT", HEAD_PAD, -warnTop)
    headFrame.dummyWarn:SetPoint("TOPRIGHT", headFrame, "TOPRIGHT", -HEAD_PAD, -warnTop)
    panel:SetHeadHeight(warnTop + 16 + 6)
  end
end

-- Renders ONE rule list into ONE section. Both the bar list and the border
-- list go through here, so their behaviour -- pooling, expansion, the add
-- row, warnings -- cannot drift apart.
-- The rule list, laid out by Flex.
--
-- What this replaces was a single running `y` threaded through every block --
-- rows, then the warning, then the buttons, then two optional panels -- with
-- each block responsible for subtracting its own height from it. Every
-- overlap on this page came from one block guessing that height wrong: a
-- wrapped warning counted as 32px, a button row as 26.
--
-- Under Flex each block is a node. Optional ones set `hidden`, which costs
-- exactly zero height, and the section's height is what the layout measured.
local function RuleSectionLayout(sec, isBorder, getList)
  if sec.flex then return sec.flex end
  local Flex = NS.Flex
  local content = sec.content
  local root = Flex.Root(content, { dir = "column", gap = NS.UI.FIELD_GAP,
    pad = { t = NS.UI.PAD_TOP, b = NS.UI.PAD_BOTTOM } })

  -- The hand-anchored headings and divider each tab built at x offsets are
  -- retired here rather than deleted at the call site: they are still
  -- referenced by name in a couple of places, and a hidden FontString costs
  -- nothing. The Flex header below replaces all of them.
  for _, key in ipairs({ "hOrder", "hDebuffs", "hEdit", "hDelete", "hOn", "divider" }) do
    local widget = sec[key]
    if widget and widget.Hide then widget:Hide() end
  end

  -- No border module switch.
  --
  -- A rule's border half is drawn because the rule has one and it is switched
  -- on -- which is exactly what the Bdr cell in its row says. A second switch
  -- governing all of them at once was a leftover from when borders were a
  -- separate list on a separate page with its own heading, and its only
  -- remaining job was to make every border silently stop working.

  root:Add(NS.BuildRuleHeader(content, isBorder))

  root:Add(NS.FlexRule(content))

  -- Rows live in their own column so the pool can grow without the surrounding
  -- blocks caring where the list ends.
  sec.rowsNode = root:Add(Flex.Box(content, { dir = "column", gap = NS.UI.ROW_GAP }))

  -- Threat, pinned above every rule, in the same table. Its position is not a
  -- preference: the engine reserves its draw sublevel before any spell rule is
  -- allocated one, so there is no grip on this row and no way to drag anything
  -- above it.
  if not isBorder then
    sec.threatRow = sec.rowsNode:Add(NS.BuildThreatPinnedRow(content))
    sec.threatRow.onEdit = function()
      sec.openThreat = not sec.openThreat
      if sec.openThreat then sec.openMark = false end
      -- One thing open at a time, same as the rules.
      if sec.openThreat then sec.openRule = nil end
      NS.Options_RebuildAll()
    end
    NS.BuildThreatBand(sec, content)
    sec.rowsNode:Add(sec.threatBand)

    -- Target and focus, directly under threat and above the rules: one row
    -- and one editor each, because six blocks in one band is more than a band
    -- can present and the two are not edited together anyway.
    sec.markRows, sec.markBands = {}, {}
    for _, state in ipairs(NS.MARK_STATES) do
      local key = state.key
      local row = sec.rowsNode:Add(NS.BuildMarkPinnedRow(content, key, "2ND"))
      row.onEdit = function()
        sec.openMark = (sec.openMark ~= key) and key or nil
        -- One editor open at a time across the whole table, the same rule the
        -- rule rows and threat already follow.
        if sec.openMark then
          sec.openRule = nil
          sec.openThreat = false
        end
        NS.Options_RebuildAll()
      end
      sec.markRows[key] = row
      sec.markBands[key] = NS.BuildMarkBand(sec, content, key)
      sec.rowsNode:Add(sec.markBands[key])
    end
  end

  -- The editor, as a row of the list rather than a page of its own or a column
  -- beside it.
  --
  -- Beside it was tried and is wrong: a side panel takes width the row's fixed
  -- controls cannot give back, so the list starts scrolling sideways exactly
  -- when you are making decisions about the columns that just left. A page of
  -- its own is worse -- a rule's meaning is RELATIVE, and "is this above the
  -- rule it has to beat" cannot be answered from somewhere the list is not.
  --
  -- One band, moved under whichever row is open, hidden when none is.
  local band = Flex.Box(content, { dir = "column", gap = NS.UI.FIELD_GAP,
    pad = { t = NS.UI.FIELD_GAP, b = NS.UI.GROUP_GAP }, hidden = true })
  sec.editorBand = sec.rowsNode:Add(band)

  -- The other three sides of the open row's outline.
  band.sel = {}
  for index = 1, 3 do
    band.sel[index] = band.frame:CreateTexture(nil, "OVERLAY")
    band.sel[index]:SetColorTexture(RGBA(THEME.selection))
  end
  -- The same weight the row's own three sides use, or the box would be
  -- thicker along the top than down the sides.
  local bandWeight = NS.PixelWeight(band.frame, NS.UI.SELECT_EDGE)
  band.sel[1]:SetPoint("BOTTOMLEFT"); band.sel[1]:SetPoint("BOTTOMRIGHT")
  band.sel[1]:SetHeight(bandWeight)
  band.sel[2]:SetPoint("TOPLEFT");    band.sel[2]:SetPoint("BOTTOMLEFT")
  band.sel[2]:SetWidth(bandWeight)
  band.sel[3]:SetPoint("TOPRIGHT");   band.sel[3]:SetPoint("BOTTOMRIGHT")
  band.sel[3]:SetWidth(bandWeight)

  local head = Flex.Box(content, { dir = "row", align = "center", gap = NS.UI.COL_GAP,
    height = NS.UI.CTRL_ROW_H, pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET } })
  band.title = Label(head.frame, "", "GameFontNormal")
  band.title:SetJustifyH("LEFT")
  head:Add(Flex.Item(band.title, { grow = 1, minW = 80, clipText = true }))
  -- No Done here. The row's own Edit button reads Done while its editor is
  -- open, and two buttons doing one thing, a few pixels apart, is a question
  -- about which one is different.
  band:Add(head)

  -- The preview first: what the controls under it are for.
  -- No preview in here.
  --
  -- The page already has one at the top, and two previews of the same rule
  -- disagreeing about what it looks like is worse than none: they update on
  -- different passes, so one is always a step behind. The one at the top wins
  -- because it is the real thing -- a plate with every rule fighting over it,
  -- and the test buttons beside it.
  --
  -- Opening a rule ticks that rule's debuffs up there, so the shared preview
  -- shows the rule being edited rather than whichever rule happened to win.
  -- Kept as a node, permanently hidden: the cost is on the row's Slots column
  -- and in that column's tooltip, and the editor repeated it in a sentence
  -- directly underneath. Hidden rather than deleted so the band's other rows
  -- keep the shape everything else here indexes them by.
  band.costLine = Dim(content, "")
  band.costLine:SetJustifyH("LEFT")
  band.costNode = NS.FlexNote(content, band.costLine, 0)
  band.costNode.hidden = true
  band:Add(band.costNode)

  -- The rule's own editor, not the page's style panel. That panel is built per
  -- page and the health copy has no border controls at all -- which, with one
  -- list holding both halves, left a rule's border with nowhere to edit it.
  band:Add(NS.BuildRuleEditor(sec, content))
  if sec.style then sec.style:Hide() end

  -- The footnote moved into the header's "?". It is still built by the page
  -- (other code reads it), just never placed.
  if sec.note then sec.note:Hide() end
  sec:SetHelp(isBorder and "Border Rules" or "Spell Rules",
    (isBorder
      and "Coloured borders driven by your own debuffs, on their own priority stack. The top border rule that matches draws, independently of whatever the health bar is doing.\n\n"
      or "Bar colours driven by your own debuffs. Higher rules override lower ones -- the topmost match is what you see -- and you set the order by dragging.\n\n")
    .. (sec.note and (sec.note:GetText() .. "\n\n") or "")
    .. "Threat colouring is drawn over everything here, and the engine decides that when a plate is built rather than while painting it.\n\n"
    .. "Drag a row by its grip to reorder. Auto sort puts rules with more debuffs above rules with fewer, which is the order that lets every one of them fire.")

  -- Warnings stay in the page. They are about THIS profile being wrong right
  -- now -- a rule that can never fire, a budget overrun -- and something you
  -- have to hover to discover is something you will not discover.
  sec.warningItem = root:Add(NS.FlexNote(content, sec.warning))

  local buttons = Flex.Box(content, { dir = "row", align = "center", gap = NS.UI.COL_GAP,
    height = NS.UI.ROW_H, pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET } })
  buttons:Add(Flex.Item(sec.newButton, { width = sec.newButton:GetWidth(), shrink = 0 }))
  if sec.sortButton then
    buttons:Add(Flex.Item(sec.sortButton, { width = sec.sortButton:GetWidth(), shrink = 0 }))
  end
  root:Add(buttons)

  -- Missing-health colour. Health list only, and shown only once some rule
  -- here covers missing health.
  if sec.missingSwatch then
    local block = Flex.Box(content, { dir = "column", gap = NS.UI.GROUP_GAP, hidden = true })
    sec.missingDivider:Hide()
    block:Add(NS.FlexRule(content))
    local strip = Flex.Box(content, { dir = "row", align = "center", gap = NS.UI.COL_GAP,
      height = NS.UI.CTRL_ROW_H, pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET } })
    sec.missingLabel:SetJustifyH("LEFT")
    strip:Add(Flex.Item(sec.missingLabel, { clipText = true, shrink = 0 }))
    strip:Add(Flex.Item(sec.missingSwatch, { width = NS.UI.BOX, shrink = 0, alignSelf = "center" }))
    strip:Add(Flex.Item(sec.missingHint, { grow = 1, clipText = true }))
    block:Add(strip)
    sec.missingBlock = root:Add(block)
  end

  -- Applied-state colour by mob rank. Shown once any rule here is a MISSING
  -- rule -- the only kind with a cover to colour -- and only in occlusion
  -- mode, which is the only mode that paints one.
  if sec.classCheck then
    local block = Flex.Box(content, { dir = "column", gap = NS.UI.GROUP_GAP, hidden = true })
    sec.classDivider:Hide()
    block:Add(NS.FlexRule(content))
    local strip = Flex.Box(content, { dir = "row", align = "center", gap = NS.UI.COL_GAP,
      height = NS.UI.CTRL_ROW_H, pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET } })
    sec.classLabel:SetJustifyH("LEFT")
    strip:Add(Flex.Item(sec.classCheck, { width = NS.UI.BOX, shrink = 0, alignSelf = "center" }))
    strip:Add(Flex.Item(sec.classLabel, { clipText = true, shrink = 0 }))
    strip:Add(Flex.Item(sec.classHint, { grow = 1, clipText = true }))
    block:Add(strip)

    -- The swatches wrap: six of them at a narrow window is two lines, and
    -- wrapping is the one thing a running `y` could never have done.
    local grid = Flex.Box(content, { dir = "row", wrap = true, gap = NS.UI.COL_GAP, crossGap = NS.UI.GROUP_GAP,
      pad = { l = NS.UI.ROW_INSET, r = NS.UI.ROW_INSET }, hidden = true })
    for _, item in ipairs(sec.classSwatches or {}) do
      local cell = Flex.Box(content, { dir = "row", align = "center", gap = NS.UI.GROUP_GAP, height = NS.UI.CTRL_ROW_H })
      cell:Add(Flex.Item(item.swatch, { width = NS.UI.BOX, shrink = 0, alignSelf = "center" }))
      cell:Add(Flex.Item(item.label, { clipText = true }))
      grid:Add(cell)
    end
    block:Add(grid)
    sec.classGrid = grid
    sec.classBlock = root:Add(block)
  end

  sec.flex = root
  return root
end

local function RenderRuleSection(sec, list, rowPool, condPool, isBorder, getList, messages, targetAuras)
  RuleSectionLayout(sec, isBorder, getList)

  local listKey = isBorder and "border" or "health"

  -- Costed once for the whole list, not once per row: an underlay depends on
  -- what sits BELOW a rule, so the answer is a property of the list and
  -- recomputing it per row would be both slower and free to disagree with the
  -- meter in the header.
  local slots = (not isBorder) and NS.SlotReport
    and NS.SlotReport(NS.CurrentAdapterBar and NS.CurrentAdapterBar() or nil) or nil
  local costByRule = {}
  for _, entry in ipairs((slots or {}).rules or {}) do
    costByRule[entry.rule] = entry
  end
  if sec.slotMeter then sec.slotMeter.Refresh() end

  -- Emptied rather than replaced: the drag handlers hold a reference to these
  -- exact tables, same as the rail's.
  pageRows[listKey] = pageRows[listKey] or {}
  wipe(pageRows[listKey])
  pageRowCount[listKey] = 0

  -- A rule that was deleted while open leaves nothing to edit.
  if sec.openRule then
    local stillThere = false
    for _, rule in ipairs(list) do
      if rule == sec.openRule then stillThere = true break end
    end
    if not stillThere then sec.openRule = nil end
  end

  -- Is ANY editor open on this page? One question asked once: every row below
  -- needs the same answer, and three rows working it out separately is how
  -- one of them ends up disagreeing.
  local editingSomething = (sec.openRule ~= nil) or sec.openThreat or sec.openMark

  -- The rest of the PAGE goes back too, not just the rest of the list.
  --
  -- A section frame owns everything drawn inside it -- header, help button,
  -- text, every control -- so one SetAlpha per section reaches the lot. That
  -- is the whole trick: the widgets in the rules list are parented to the
  -- page's scroll content and cannot be dimmed as a group, but the sections
  -- around it each have a frame of their own.
  --
  -- Restored on every render rather than only when the editor closes: a page
  -- whose alpha was set by the last pass has to be told when it is no longer
  -- the background.
  local body = sec.GetParent and sec:GetParent()
  if body and body.sections then
    for _, other in ipairs(body.sections) do
      if other ~= sec and other.SetAlpha then
        other:SetAlpha(editingSomething and THEME.pageRecessed or 1)
      end
    end
  end

  local openRow
  for index, rule in ipairs(list) do
    local row = rowPool[index]
    if not row then
      row = BuildRuleRow(sec.content, getList, isBorder)
      rowPool[index] = row
      sec.rowsNode:Add(row.node)
      -- Added before the bands were, so they are pushed back to the end each
      -- time the pool grows -- otherwise a new row lands underneath one.
      local bands = { sec.editorBand, sec.threatBand }
      for _, band in pairs(sec.markBands or {}) do bands[#bands + 1] = band end
      for _, band in ipairs(bands) do
        if band then
          NS.FlexMoveAfter(sec.rowsNode, band, sec.rowsNode.children[#sec.rowsNode.children])
        end
      end
    end
    row.section = sec
    row.node.hidden = false
    row.index, row.rule = index, rule
    row.listKey = listKey
    pageRowCount[listKey] = pageRowCount[listKey] + 1
    pageRows[listKey][pageRowCount[listKey]] = row
    -- A restricted rule says so on its own row. Without this a rule that is
    -- correct, enabled and simply not loaded in this zone looks identical to
    -- one that is broken -- which is the support question the whole feature
    -- would otherwise generate.
    local summary = NS.RuleSummary(rule)
    if NS.LoadIsRestricted and NS.LoadIsRestricted(rule.load) then
      local here = NS.LoadAllows(rule.load)
      summary = summary .. ("  |cff808080%s%s|r"):format(
        NS.LoadSummary(rule.load), here and "" or "  --  not loaded here")
    end
    row.summary:SetText(summary)
    -- Recessed unless this is the row the open editor belongs to. Done here
    -- rather than in the Edit handler because the list is re-rendered on
    -- every change, and a row that was dimmed by the last render has to be
    -- told when it is no longer the odd one out.
    if row.SetRecessed then
      row.SetRecessed(editingSomething and rule ~= sec.openRule)
    end
    row.enabled.Refresh()
    local open = rule == sec.openRule
    if open then openRow = row end
    row.edit:SetText(open and "Done" or "Edit")
    row.sel[1]:SetShown(open)
    row.sel[2]:SetShown(false)  -- the band draws this edge
    row.sel[3]:SetShown(open)
    row.sel[4]:SetShown(open)
    -- Both halves, through the one renderer every fill goes through. A half
    -- that is switched off still shows its own colour, at a quarter alpha:
    -- "off" and "never set" look different, and the colour is still the one
    -- turning it back on would use.
    row.barChip.Refresh()
    row.borderChip.Refresh()
    row.stripe:SetShown(index % 2 == 0)

    if row.cost then
      local entry = costByRule[rule]
      if not entry then
        -- A rule with no debuff yet, or switched off: it builds nothing, so it
        -- spends nothing. Left blank rather than "0 slots", which reads as a
        -- claim about a finished rule.
        row.cost:SetText("")
      elseif entry.cost == 0 then
        row.cost:SetText("|cff8080800|r")
      else
        -- The number, and nothing else. What the slots went ON is a question
        -- for the tooltip -- in a column this narrow "(tint+cover)" is longer
        -- than the fact it qualifies.
        row.cost:SetText(("%d"):format(entry.cost))
      end
    end
  end
  -- Pooled rows past the end of the list are hidden as NODES, so they take no
  -- height either.
  for index = #list + 1, #rowPool do
    if rowPool[index].node then rowPool[index].node.hidden = true end
  end

  -- Threat first, because it is the first row.
  if sec.threatRow and sec.threatRow.SetRecessed then
    sec.threatRow.SetRecessed(editingSomething and not sec.openThreat)
  end
  if sec.threatRow then
    local cfg = NS.ThreatConfig()
    local row = sec.threatRow
    NS.FlexMoveAfter(sec.rowsNode, row, nil)
    -- To the FRONT: FlexMoveAfter with no target appends, so the row is moved
    -- explicitly to index 1 -- the one position in this list that is not
    -- decided by the user.
    for index, child in ipairs(sec.rowsNode.children) do
      if child == row then
        table.remove(sec.rowsNode.children, index)
        table.insert(sec.rowsNode.children, 1, row)
        break
      end
    end

    local on = cfg.enabled ~= false
    -- The role, and nothing else. It read "tank role - 2 of 3 states - in
    -- combat only": three facts in a row that has columns for two of them.
    -- The chips beside it already say which states are on, and in-combat is
    -- not a setting any more.
    row.label:SetText(("Threat  |cff808080Role: %s%s%s|r"):format(NS.ThreatRoleName(),
      NS.ThreatFlashOn() and "  -  Flash on loss" or "",
      (NS.LoadIsRestricted and NS.LoadIsRestricted(cfg.load))
        and ("  -  " .. NS.LoadSummary(cfg.load)) or ""))
    row.label:SetAlpha(on and 1 or 0.5)
    for _, strip in ipairs({ row.barStrip, row.borderStrip }) do
      for _, chip in ipairs(strip.chips) do
        chip.Refresh()
        chip:SetAlpha(on and 1 or 0.35)
      end
    end
    row.cost:SetText(("%d"):format(slots and slots.threatCost or 0))
    row.edit:SetText(sec.openThreat and "Done" or "Edit")
    row.enabled.Refresh()

    sec.threatBand.hidden = not sec.openThreat
    if sec.openThreat then
      NS.FlexMoveAfter(sec.rowsNode, sec.threatBand, row)
      sec.threatBand.roleDrop.Refresh()
      sec.threatBand.flash.Refresh()
      -- Rebound every render: the order follows the role, and the role can
      -- change under a rebuild.
      sec.threatBand.zoneDrop.Refresh()
      sec.threatBand.groupDrop.Refresh()
      for index, state in ipairs(NS.ThreatStatesOrdered()) do
        local bandRow = sec.threatBand.rows[index]
        bandRow.key = state.key
        bandRow.label:SetText(NS.ThreatStateLabel(state.key))
        bandRow.barSwatch.Refresh()
        bandRow.barOn.Refresh()
        bandRow.borderSwatch.Refresh()
        bandRow.borderOn.Refresh()
      end
    end
  end

  -- Target/Focus, immediately under threat: same treatment, one rank down.
  if sec.markRows then
    local cfg = NS.MarkConfig()
    local on = cfg.enabled ~= false
    local restricted = NS.LoadIsRestricted and NS.LoadIsRestricted(cfg.load)
    -- Threat's band sits between threat and these while it is open, so each
    -- row is moved after whatever is currently last above it rather than
    -- after a fixed node.
    local previous = (sec.openThreat and sec.threatBand) or sec.threatRow
    for _, state in ipairs(NS.MARK_STATES) do
      local key = state.key
      local row = sec.markRows[key]
      local band = sec.markBands[key]
      NS.FlexMoveAfter(sec.rowsNode, row, previous)

      row.label:SetText(("%s%s"):format(NS.MarkStateLabel(key),
        restricted and ("  |cff808080%s|r"):format(NS.LoadSummary(cfg.load)) or ""))
      row.label:SetAlpha(on and 1 or 0.5)
      row.barChip.Refresh()
      row.borderChip.Refresh()
      for _, chip in ipairs({ row.barChip, row.borderChip }) do
        chip:SetAlpha(on and 1 or 0.35)
      end

      -- Per unit, not the module's total: this row's bar half is what this
      -- row's number is about.
      local barEntry = NS.MarkModule("bar").states[key]
      local spends = on and barEntry and barEntry.enabled ~= false
      row.cost:SetText(spends and "1" or "|cff8080800|r")
      row.edit:SetText((sec.openMark == key) and "Done" or "Edit")
      row.enabled.Refresh()
      if row.SetRecessed then
        row.SetRecessed(editingSomething and sec.openMark ~= key)
      end

      band.hidden = sec.openMark ~= key
      if not band.hidden then
        NS.FlexMoveAfter(sec.rowsNode, band, row)
        band.zoneDrop.Refresh()
        band.groupDrop.Refresh()
        for _, block in ipairs(band.rows) do block.Refresh() end
        previous = band
      else
        previous = row
      end
    end
  end

  -- Park the band under the open row, or hide it. Hidden is a LAYOUT state --
  -- the node costs no height at all, so a closed editor is not a gap.
  if sec.editorBand then
    sec.editorBand.hidden = openRow == nil
    if openRow then
      NS.FlexMoveAfter(sec.rowsNode, sec.editorBand, openRow.node)
      sec.editorBand.title:SetText(("Editing %s"):format(RuleLabel(sec.openRule)))
      -- The cost line is gone from the editor. The Slots column on the row
      -- above already carries the number, and its tooltip carries the
      -- breakdown -- a sentence repeating both, one line under the row it
      -- came from, was the same fact three times.
      sec.editorBand.costLine:SetText("")
      NS.RefreshRuleEditor(sec)
    end
  end

  if #messages > 0 then
    sec.warning:SetText(table.concat(messages, "\n"))
    sec.warningItem.hidden = false
  else
    sec.warning:SetText("")
    sec.warningItem.hidden = true
  end

  if sec.missingBlock then
    local anyCovering = false
    for _, rule in ipairs(list) do
      if rule.missingCover then anyCovering = true break end
    end
    sec.missingBlock.hidden = not anyCovering
    if anyCovering then sec.missingSwatch:Refresh() end
  end

  if sec.classBlock then
    local anyMissing = false
    for _, rule in ipairs(list) do
      if rule.showWhenMissing then anyMissing = true break end
    end
    -- Needs OCCLUSION, which is no longer the default, so outside that mode it
    -- is hidden outright. A disabled-but-visible version was tried and
    -- dropped: a dead control on the page everyone lands on, whose mode is
    -- reached by a slash command rather than anything nearby.
    local show = anyMissing and NS.db.tints.missingMode == "occlude"
    sec.classBlock.hidden = not show
    if show then
      sec.classCheck.Refresh()
      -- The swatches are a second row under the checkbox, and only earn their
      -- space once the option is actually on.
      sec.classGrid.hidden = not NS.db.tints.missingAppliedByClass
      if not sec.classGrid.hidden then
        for _, item in ipairs(sec.classSwatches or {}) do item.swatch:Refresh() end
      end
    end
  end

  -- The condition and appearance expanders are gone -- editing happens on the
  -- rule's own page -- so the pools they used stay hidden.
  if sec.addCondDrop then
    sec.addCondDrop:Hide()
    sec.addCondBox:Hide()
    sec.addCondBoxLabel:Hide()
  end
  for _, cr in ipairs(condPool or {}) do cr:Hide() end

  NS.FlexResize(sec)
  return false
end

-- BuildBorderTab and RebuildBorderTab are gone.
--
-- The page was a second view of one list once the two lists merged, and a
-- second place to switch a module on. Both halves of a rule are columns in the
-- one table now, and Border Coloring's switch lives on the Health heading --
-- so this page had nothing left that was not said better elsewhere.

local function RebuildHealthTab()
  local panel = healthTab
  if not panel then return end
  for _, r in ipairs(ruleRows) do r:Hide() end
  for _, r in ipairs(conditionRows) do r:Hide() end

  if panel.head.enable then panel.head.enable:Refresh() end
  panel.RefreshPreview()

  local rules = panel.body.rules
  local list = NS.db.tints.rules
  local messages = {}

  -- Through NS.ShadowedRules rather than a second copy of the same walk: the
  -- rail marks unreachable rules with a "!" from that function, and two
  -- implementations of "can this rule ever fire" would eventually disagree
  -- about which rule is broken.
  local shadowed = NS.ShadowedRules(list)
  for index = 1, #list do
    local blocker = shadowed[index]
    if blocker then
      table.insert(messages, ("|cffffcc00Rule %d can never show — rule %d matches whenever it does. Press Auto sort.|r")
        :format(index, blocker))
      break
    end
  end

  local targetAuras = NS.GetTargetAuraSet()
  local suspect = 0
  for _, rule in ipairs(list) do
    for _, cond in ipairs(rule.conditions or {}) do
      if not targetAuras[cond.spellID] then suspect = suspect + 1 end
    end
  end
  if suspect > 0 then
    table.insert(messages, ("|cffff4040%d debuff(s) marked ! use an ID the Cooldown Manager doesn't list as an aura you apply.|r"):format(suspect))
  end

  -- The "requires three debuffs" warning is gone: it dated from the
  -- AddAuraGroup engine, where a third debuff meant ~111 containers and 1000
  -- textures per plate. Aura slots make it an ordinary rule.

  -- A rule with both halves off silently does nothing, and is impossible to
  -- diagnose from the plate.
  local inert = 0
  for _, rule in ipairs(list) do
    if rule.enabled ~= false and rule.barEnabled == false
      and not (rule.border and rule.border.enabled) then
      inert = inert + 1
    end
  end
  if inert > 0 then
    table.insert(messages,
      ("|cffffcc00%d rule(s) have neither the bar nor the border enabled - they paint nothing. Open Edit and tick one.|r")
        :format(inert))
  end

  -- A MISSING rule above a normal one promises something the engine cannot
  -- deliver. Priority here is one list, but the engine builds two stacks:
  -- presence rules, and the missing ladder underneath them. A missing rule's
  -- position ranks it against other MISSING rules only.
  --
  -- Worth saying out loud because the table looks like it should work:
  -- dragging a missing rule to the top is the obvious thing to try when a
  -- reminder is not showing, and it changes nothing.
  local misplaced, presenceBelow = 0, 0
  for index = #list, 1, -1 do
    local rule = list[index]
    if rule.enabled ~= false then
      if rule.showWhenMissing then
        if presenceBelow > 0 then misplaced = misplaced + 1 end
      else
        presenceBelow = presenceBelow + 1
      end
    end
  end
  if misplaced > 0 then
    table.insert(messages,
      ("|cffffcc00%d MISSING rule(s) sit above normal rules. Priority between the two does nothing — a normal rule always draws over a missing one. Move them below to match what you see.|r")
        :format(misplaced))
  end

  RenderRuleSection(rules, NS.db.tints.rules, ruleRows, conditionRows, false,
    function() return NS.db.tints.rules end, messages, targetAuras)

  -- After the spell rules, deliberately: the threat rows are costed against
  -- the same budget, and RenderRuleSection is what refreshed the meter.
  if panel.body.ladder then NS.RenderResolutionLadder(panel.body.ladder) end


  -- Pandemic Flash, Bar Edges and Plate Border used to be refreshed here too.
  -- They now live on their own Global Settings pages -- see RebuildGlobalTabs.
  LayoutSections(panel.body, panel.body.sections)
end

-------------------------------------------------------------------------------
-- Tab 2 — aura icons
-------------------------------------------------------------------------------

local function BuildIconRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(690, ROW_H)

  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, 0.03)

  row.up = Button(row, "UP", 30, function()
    if NS.ListMove(NS.db.icons.list, row.index, -1) then Structural() end
  end)
  row.up:SetPoint("LEFT", 8, 0)
  StyleText(row.up.label, 10)
  row.priority = EditableNumber(row, 26,
    function() return row.index or 1 end,
    function(value)
      if NS.ListMoveTo(NS.db.icons.list, row.index, value) then Structural() end
    end)
  row.priority:SetPoint("LEFT", 41, 0)

  row.down = Button(row, "DOWN", 38, function()
    if NS.ListMove(NS.db.icons.list, row.index, 1) then Structural() end
  end)
  row.down:SetPoint("LEFT", 70, 0)
  StyleText(row.down.label, 10)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 118, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = Label(row, "")
  row.name:SetPoint("LEFT", 146, 0)
  row.name:SetWidth(280)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.id = Dim(row, "")
  row.id:SetPoint("LEFT", 400, 0)

  row.enabled = Checkbox(row,
    function() return row.entry and row.entry.enabled ~= false end,
    function(v) if row.entry then row.entry.enabled = v; Structural() end end)
  row.enabled:SetPoint("LEFT", 500, 0)

  row.remove = CloseX(row, function()
    table.remove(NS.db.icons.list, row.index)
    Structural()
  end)
  row.remove:SetPoint("LEFT", 634, 0)
  return row
end

-- Taller than every other page's preview, and only here. The colouring pages
-- draw entirely ON the bar; aura icons sit above it with timer and stack text,
-- which at STAGE_H was pressed against the top edge and clipped.
local ICON_STAGE_H = 140

local function BuildAuraIconTab()
  -- Enable lives on the rail heading now (see MODULE_SWITCH).
  local panel = BuildTabFrame(tabPanels[3], nil, nil, nil, ICON_STAGE_H)

  local head = panel.head

  -- Beside the module switch rather than buried in the aura list: it is a
  -- module-level decision about who owns the icon row on your plates.
  head.hideBliz = Checkbox(head,
    function() return NS.db.icons.hideBlizzardAuras end,
    function(v)
      NS.db.icons.hideBlizzardAuras = v
      -- Applied to every visible plate at once: this one is judged by looking
      -- at the screen, so waiting for the next plate to spawn feels broken.
      if NS.RefreshBlizzardAuras then NS.RefreshBlizzardAuras() end
      Structural()
    end)
  -- BELOW the stage. This sat at -6 from the head's top, which was clear while
  -- the head began with a module-toggle row. The switch moved to the rail, so
  -- the stage starts at 6 and drew straight over it.
  head.hideBliz:SetPoint("TOPLEFT", HEAD_PAD, -(6 + ICON_STAGE_H + 6))
  head.hideBlizLabel = Label(head, "Hide Blizzard's own aura icons on nameplates")
  head.hideBlizLabel:SetPoint("LEFT", head.hideBliz, "RIGHT", 6, 0)
  Tip(head.hideBliz, "Hide Blizzard's own aura icons", TIPS.hideBliz)
  TipLabel(head.hideBlizLabel, "Hide Blizzard's own aura icons", TIPS.hideBliz)
  head.note = Dim(head, "Preview always shows icons. Turn the module on to draw them on real plates.")
  -- A line below the two controls, since it explains them both.
  head.note:SetPoint("TOPLEFT", HEAD_PAD, -(6 + ICON_STAGE_H + 32))

  -- Preview-only, and stored with the other UI state rather than the icon
  -- settings: it changes what the preview draws, not what the plates do.
  head.textPreview = Checkbox(head,
    function() return NS.db.uiPreviewText ~= false end,
    function(v) NS.db.uiPreviewText = v; RefreshPreviews() end)
  -- Same row as the hide-Blizzard box, at the other end: both are about what
  -- you are looking at rather than about a particular aura.
  head.textPreview:SetPoint("TOPRIGHT", -HEAD_PAD, -(6 + ICON_STAGE_H + 6))
  head.textPreviewLabel = Dim(head, "Show timer & stacks in preview")
  head.textPreviewLabel:SetPoint("RIGHT", head.textPreview, "LEFT", -6, 0)
  Tip(head.textPreview, "Show timer & stacks in preview", TIPS.textPreview)
  TipLabel(head.textPreviewLabel, "Show timer & stacks in preview", TIPS.textPreview)

  -- Stage, then the control row, then the note beneath it.
  panel:SetHeadHeight(6 + ICON_STAGE_H + 56)

  -- Three pages, one per concern, each with its own copy of the head so the
  -- icon preview is present wherever you are changing it. `icons` holds the
  -- section references, since `body` moves between pages as they are built
  -- and nothing downstream should have to track which page it is on.
  local layoutPanel = BuildTabFrame(tabPanels[PAGE_ICON_LAYOUT], nil, nil, nil, ICON_STAGE_H)
  local textPanel = BuildTabFrame(tabPanels[PAGE_ICON_TEXT], nil, nil, nil, ICON_STAGE_H)
  iconPanels = { panel, layoutPanel, textPanel }

  local body = panel.body
  body.sections = {}

  -- Which auras
  local filter = CollapsibleSection(body, "iconFilter", "Which Auras",
    "your debuffs, in display order")
  table.insert(body.sections, filter)
  body.filter = filter

  local fc = filter.content
  filter.hOrder = Header(fc, "Priority")
  filter.hOrder:SetPoint("TOPLEFT", 8, -6)
  filter.hOrder:SetWidth(100)
  filter.hOrder:SetJustifyH("CENTER")
  filter.hAura = Header(fc, "Aura")
  filter.hAura:SetPoint("TOPLEFT", 118, -6)
  filter.hID = Header(fc, "Spell ID")
  filter.hID:SetPoint("TOPLEFT", 400, -6)
  filter.hShow = Header(fc, "Show")
  filter.hShow:SetPoint("TOPLEFT", 494, -6)

  filter.divider = fc:CreateTexture(nil, "ARTWORK")
  filter.divider:SetPoint("TOPLEFT", 10, -22)
  filter.divider:SetPoint("TOPRIGHT", -10, -22)
  filter.divider:SetHeight(1)
  filter.divider:SetColorTexture(0.4, 0.4, 0.45, 0.6)

  -- Shared by the dropdown and the box below, for the same reason the colour
  -- tab shares its handler: the dropdown's IDs come from the Cooldown Manager
  -- and are abilities, not the auras they apply.
  local function AddIconSpell(input)
    if not input then return end
    local spellID = ResolveAndReport(input)
    if not spellID then return end
    if not NS.ListIndexOf(NS.db.icons.list, spellID) then
      table.insert(NS.db.icons.list, { spellID = spellID, enabled = true })
      Structural()
    end
  end

  filter.addDrop = AddSpellDropdown(fc, 250, "Track another aura...",
    function(spellID) return NS.ListIndexOf(NS.db.icons.list, spellID) ~= nil end,
    AddIconSpell)
  filter.addBox = IDBox(fc, AddIconSpell)

  Tip(filter.addDrop, "Track another aura", TIPS.iconAdd)
  Tip(filter.addBox, "Track by ID or name", TIPS.iconAdd)
  filter.addBoxLabel = Dim(fc, "or ID/name:")

  -- Layout: placement and packing together, since they are judged against
  -- the same swatch. Size and border sit at the bottom as appearance.
  body = layoutPanel.body
  body.sections = {}
  local layout = CollapsibleSection(body, "iconLayout", "Position & Size",
    "where the row sits, and how the icons look")
  table.insert(body.sections, layout)
  body.layout = layout

  local lc = layout.content
  layout.swatch = BuildIconSwatch(lc)
  layout.swatch:SetPoint("TOPRIGHT", -14, -10)

  layout.anchorLabel = Label(lc, "Anchor to bar")
  layout.anchorLabel:SetPoint("TOPLEFT", 14, -12)
  TipLabel(layout.anchorLabel, "Anchor to bar", TIPS.iconAnchor)
  Tip(layout.anchor, "Anchor to bar", TIPS.iconAnchor)
  layout.anchor = Dropdown(lc, 150, ANCHOR_POINTS,
    function() return NS.db.icons.anchor end,
    function(v) NS.db.icons.anchor = v; Live() end)
  layout.anchor:SetPoint("TOPLEFT", 130, -10)

  layout.growLabel = Label(lc, "Grow direction")
  layout.growLabel:SetPoint("TOPLEFT", 14, -44)
  TipLabel(layout.growLabel, "Grow direction", TIPS.iconGrow)
  Tip(layout.grow, "Grow direction", TIPS.iconGrow)
  layout.grow = Dropdown(lc, 150, {
    { text = "Grow right", value = "RIGHT" },
    { text = "Centered", value = "CENTER" },
    { text = "Grow left", value = "LEFT" },
  }, function() return NS.db.icons.grow end, function(v) NS.db.icons.grow = v; Live() end)
  layout.grow:SetPoint("TOPLEFT", 130, -42)

  layout.padXLabel = Label(lc, "X padding")
  layout.padXLabel:SetPoint("TOPLEFT", 14, -78)
  TipLabel(layout.padXLabel, "X padding", TIPS.iconOffsetX)
  Tip(layout.padX, "X padding", TIPS.iconOffsetX)
  layout.padX = Slider(lc, 130, -60, 60, 120,
    function() return NS.db.icons.padX or 0 end,
    function(v) NS.db.icons.padX = v; Live() end)
  layout.padX:SetPoint("TOPLEFT", 130, -78)

  layout.padYLabel = Label(lc, "Y padding")
  layout.padYLabel:SetPoint("TOPLEFT", 14, -104)
  TipLabel(layout.padYLabel, "Y padding", TIPS.iconOffsetY)
  Tip(layout.padY, "Y padding", TIPS.iconOffsetY)
  layout.padY = Slider(lc, 130, -60, 60, 120,
    function() return NS.db.icons.padY or 0 end,
    function(v) NS.db.icons.padY = v; Live() end)
  layout.padY:SetPoint("TOPLEFT", 130, -104)

  layout.rowLabel = Label(lc, "Icons per row")
  layout.rowLabel:SetPoint("TOPLEFT", 14, -130)
  TipLabel(layout.rowLabel, "Icons per row", TIPS.iconPerRow)
  Tip(layout.perRow, "Icons per row", TIPS.iconPerRow)
  layout.perRow = Slider(lc, 130, 1, 10, 9,
    function() return NS.db.icons.maxPerRow or 6 end,
    function(v) NS.db.icons.maxPerRow = v; Live() end)
  layout.perRow:SetPoint("TOPLEFT", 130, -130)

  layout.divider = lc:CreateTexture(nil, "ARTWORK")
  layout.divider:SetPoint("TOPLEFT", 12, -156)
  layout.divider:SetPoint("TOPRIGHT", -12, -156)
  layout.divider:SetHeight(1)
  layout.divider:SetColorTexture(0.4, 0.4, 0.45, 0.5)

  layout.sizeLabel = Label(lc, "Icon size")
  layout.sizeLabel:SetPoint("TOPLEFT", 14, -168)
  TipLabel(layout.sizeLabel, "Icon size", TIPS.iconSize)
  Tip(layout.size, "Icon size", TIPS.iconSize)
  layout.size = Slider(lc, 130, 10, 48, 38,
    function() return NS.db.icons.size end,
    function(v) NS.db.icons.size = v; Live() end)
  layout.size:SetPoint("TOPLEFT", 130, -168)

  layout.spacingLabel = Label(lc, "Icon spacing")
  layout.spacingLabel:SetPoint("TOPLEFT", 14, -194)
  TipLabel(layout.spacingLabel, "Icon spacing", TIPS.iconSpacing)
  Tip(layout.spacing, "Icon spacing", TIPS.iconSpacing)
  layout.spacing = Slider(lc, 130, 0, 16, 16,
    function() return NS.db.icons.spacing end,
    function(v) NS.db.icons.spacing = v; Live() end)
  layout.spacing:SetPoint("TOPLEFT", 130, -194)

  layout.borderLabel = Label(lc, "Border size")
  layout.borderLabel:SetPoint("TOPLEFT", 14, -220)
  TipLabel(layout.borderLabel, "Border size", TIPS.iconBorder)
  Tip(layout.border, "Border size", TIPS.iconBorder)
  layout.border = Slider(lc, 130, 0, 5, 5,
    function() return NS.db.icons.borderSize or 1 end,
    function(v) NS.db.icons.borderSize = v; Restyle() end)
  layout.border:SetPoint("TOPLEFT", 130, -220)

  layout.borderColorLabel = Label(lc, "Border color")
  layout.borderColorLabel:SetPoint("TOPLEFT", 14, -246)
  TipLabel(layout.borderColorLabel, "Border color", TIPS.iconBorderCol)
  Tip(layout.borderColor, "Border color", TIPS.iconBorderCol)
  layout.borderColor = ColorSwatch(lc,
    function() return NS.db.icons.borderColor or { r = 0, g = 0, b = 0, a = 1 } end,
    function(r, g, b, a)
      NS.db.icons.borderColor = { r = r, g = g, b = b, a = a }
      Restyle()
    end)
  layout.borderColor:SetPoint("TOPLEFT", 130, -246)

  -- Timer & stacks, with one big dummy icon to judge the text against.
  body = textPanel.body
  body.sections = {}
  local text = CollapsibleSection(body, "iconText", "Timer & Stacks",
    "font, size and placement of the text on each icon")
  table.insert(body.sections, text)
  body.text = text

  local tc = text.content
  text.swatch = BuildTextSwatch(tc)
  text.swatch:SetPoint("TOPRIGHT", -14, -10)

  local fontEntries = {}
  local function RefreshFontEntries()
    wipe(fontEntries)
    for _, name in ipairs(NS.FontList()) do
      table.insert(fontEntries, { text = name, value = name })
    end
    return fontEntries
  end
  RefreshFontEntries()

  local OUTLINES = {
    { text = "None", value = "NONE" },
    { text = "Outline", value = "OUTLINE" },
    { text = "Thick outline", value = "THICKOUTLINE" },
  }

  text.swirl = Checkbox(tc,
    function() return NS.db.icons.showSwirl end,
    function(v) NS.db.icons.showSwirl = v; Restyle() end)
  text.swirl:SetPoint("TOPLEFT", 12, -8)
  text.swirlLabel = Label(tc, "Cooldown swirl")
  text.swirlLabel:SetPoint("LEFT", text.swirl, "RIGHT", 6, 0)
  Tip(text.swirl, "Cooldown swirl", TIPS.iconSwirl)
  TipLabel(text.swirlLabel, "Cooldown swirl", TIPS.iconSwirl)

  -- Timer block
  text.timer = Checkbox(tc,
    function() return NS.db.icons.showTimer end,
    function(v) NS.db.icons.showTimer = v; Restyle() end)
  text.timer:SetPoint("TOPLEFT", 12, -40)
  text.timerLabel = Label(tc, "Timer text", "GameFontNormal")
  text.timerLabel:SetPoint("LEFT", text.timer, "RIGHT", 6, 0)
  Tip(text.timer, "Timer text", TIPS.iconTimer)
  TipLabel(text.timerLabel, "Timer text", TIPS.iconTimer)

  text.timerFontLabel = Dim(tc, "Font")
  text.timerFontLabel:SetPoint("TOPLEFT", 34, -66)
  TipLabel(text.timerFontLabel, "Font", TIPS.fontFace)
  Tip(text.timerFont, "Font", TIPS.fontFace)
  text.timerFont = Dropdown(tc, 150, fontEntries,
    function() return NS.db.icons.timerFont end,
    function(v) NS.db.icons.timerFont = v; Restyle() end)
  text.timerFont:SetPoint("TOPLEFT", 110, -64)

  text.timerSizeLabel = Dim(tc, "Size")
  text.timerSizeLabel:SetPoint("TOPLEFT", 280, -66)
  TipLabel(text.timerSizeLabel, "Size", TIPS.fontSize)
  Tip(text.timerSize, "Size", TIPS.fontSize)
  text.timerSize = Slider(tc, 80, 6, 42, 36,
    function() return NS.db.icons.timerSize or 12 end,
    function(v) NS.db.icons.timerSize = v; Restyle() end)
  text.timerSize:SetPoint("TOPLEFT", 320, -66)

  text.timerOutlineLabel = Dim(tc, "Outline")
  text.timerOutlineLabel:SetPoint("TOPLEFT", 34, -94)
  TipLabel(text.timerOutlineLabel, "Outline", TIPS.fontOutline)
  Tip(text.timerOutline, "Outline", TIPS.fontOutline)
  text.timerOutline = Dropdown(tc, 130, OUTLINES,
    function() return NS.db.icons.timerOutline end,
    function(v) NS.db.icons.timerOutline = v; Restyle() end)
  text.timerOutline:SetPoint("TOPLEFT", 110, -92)

  text.timerAnchorLabel = Dim(tc, "Position")
  text.timerAnchorLabel:SetPoint("TOPLEFT", 254, -94)
  TipLabel(text.timerAnchorLabel, "Position", TIPS.textAnchor)
  Tip(text.timerAnchor, "Position", TIPS.textAnchor)
  text.timerAnchor = Dropdown(tc, 130, ANCHOR_POINTS,
    function() return NS.db.icons.timerAnchor end,
    function(v) NS.db.icons.timerAnchor = v; Restyle() end)
  text.timerAnchor:SetPoint("TOPLEFT", 320, -92)

  -- Only the preview honours this: the real countdown digits on a live
  -- nameplate are Blizzard's own cooldown-frame text, formatted by the
  -- client with no addon-facing precision control.
  text.timerPrecisionLabel = Dim(tc, "Decimals (preview only)")
  text.timerPrecisionLabel:SetPoint("TOPLEFT", 34, -122)
  TipLabel(text.timerPrecisionLabel, "Decimals", TIPS.textPrecision)
  Tip(text.timerPrecision, "Decimals", TIPS.textPrecision)
  text.timerPrecision = Dropdown(tc, 90, PRECISION_ENTRIES,
    function() return NS.db.icons.timerPrecision or 1 end,
    function(v) NS.db.icons.timerPrecision = v; RefreshPreviews() end)
  text.timerPrecision:SetPoint("TOPLEFT", 190, -120)

  text.timerXLabel = Dim(tc, "X offset")
  text.timerXLabel:SetPoint("TOPLEFT", 34, -150)
  TipLabel(text.timerXLabel, "X offset", TIPS.textOffsetX)
  Tip(text.timerX, "X offset", TIPS.textOffsetX)
  text.timerX = Slider(tc, 80, -20, 20, 40,
    function() return NS.db.icons.timerX or 0 end,
    function(v) NS.db.icons.timerX = v; Restyle() end)
  text.timerX:SetPoint("TOPLEFT", 110, -150)

  text.timerYLabel = Dim(tc, "Y offset")
  text.timerYLabel:SetPoint("TOPLEFT", 254, -150)
  TipLabel(text.timerYLabel, "Y offset", TIPS.textOffsetY)
  Tip(text.timerY, "Y offset", TIPS.textOffsetY)
  text.timerY = Slider(tc, 80, -20, 20, 40,
    function() return NS.db.icons.timerY or 0 end,
    function(v) NS.db.icons.timerY = v; Restyle() end)
  text.timerY:SetPoint("TOPLEFT", 320, -150)

  -- Stacks block
  text.count = Checkbox(tc,
    function() return NS.db.icons.showCount end,
    function(v) NS.db.icons.showCount = v; Restyle() end)
  text.count:SetPoint("TOPLEFT", 12, -180)
  text.countLabel = Label(tc, "Stack count", "GameFontNormal")
  text.countLabel:SetPoint("LEFT", text.count, "RIGHT", 6, 0)

  text.countFontLabel = Dim(tc, "Font")
  text.countFontLabel:SetPoint("TOPLEFT", 34, -206)
  TipLabel(text.countFontLabel, "Font", TIPS.fontFace)
  Tip(text.countFont, "Font", TIPS.fontFace)
  text.countFont = Dropdown(tc, 150, fontEntries,
    function() return NS.db.icons.countFont end,
    function(v) NS.db.icons.countFont = v; Restyle() end)
  text.countFont:SetPoint("TOPLEFT", 110, -204)

  text.countSizeLabel = Dim(tc, "Size")
  text.countSizeLabel:SetPoint("TOPLEFT", 280, -206)
  TipLabel(text.countSizeLabel, "Size", TIPS.fontSize)
  Tip(text.countSize, "Size", TIPS.fontSize)
  text.countSize = Slider(tc, 80, 6, 42, 36,
    function() return NS.db.icons.countSize or 10 end,
    function(v) NS.db.icons.countSize = v; Restyle() end)
  text.countSize:SetPoint("TOPLEFT", 320, -206)

  text.countOutlineLabel = Dim(tc, "Outline")
  text.countOutlineLabel:SetPoint("TOPLEFT", 34, -234)
  TipLabel(text.countOutlineLabel, "Outline", TIPS.fontOutline)
  Tip(text.countOutline, "Outline", TIPS.fontOutline)
  text.countOutline = Dropdown(tc, 130, OUTLINES,
    function() return NS.db.icons.countOutline end,
    function(v) NS.db.icons.countOutline = v; Restyle() end)
  text.countOutline:SetPoint("TOPLEFT", 110, -232)

  text.countAnchorLabel = Dim(tc, "Position")
  text.countAnchorLabel:SetPoint("TOPLEFT", 254, -234)
  TipLabel(text.countAnchorLabel, "Position", TIPS.textAnchor)
  Tip(text.countAnchor, "Position", TIPS.textAnchor)
  text.countAnchor = Dropdown(tc, 130, ANCHOR_POINTS,
    function() return NS.db.icons.countAnchor end,
    function(v) NS.db.icons.countAnchor = v; Restyle() end)
  text.countAnchor:SetPoint("TOPLEFT", 320, -232)

  text.countXLabel = Dim(tc, "X offset")
  text.countXLabel:SetPoint("TOPLEFT", 34, -262)
  TipLabel(text.countXLabel, "X offset", TIPS.textOffsetX)
  Tip(text.countX, "X offset", TIPS.textOffsetX)
  text.countX = Slider(tc, 80, -20, 20, 40,
    function() return NS.db.icons.countX or 0 end,
    function(v) NS.db.icons.countX = v; Restyle() end)
  text.countX:SetPoint("TOPLEFT", 110, -262)

  text.countYLabel = Dim(tc, "Y offset")
  text.countYLabel:SetPoint("TOPLEFT", 254, -262)
  TipLabel(text.countYLabel, "Y offset", TIPS.textOffsetY)
  Tip(text.countY, "Y offset", TIPS.textOffsetY)
  text.countY = Slider(tc, 80, -20, 20, 40,
    function() return NS.db.icons.countY or 0 end,
    function(v) NS.db.icons.countY = v; Restyle() end)
  text.countY:SetPoint("TOPLEFT", 320, -262)

  iconTab = panel

  -- Every icon page previews the same thing, so they share one refresh --
  -- each drawing into its OWN stage, which is why the stage comes from the
  -- panel being refreshed rather than from `panel`.
  local function RefreshIconPage(which)
    return function()
      LayoutStageIcons(which.head.stage)
      -- The section swatches are previews too: they must follow Live() edits
      -- (size, spacing), not just rebuilds.
      local lb = layoutPanel.body
      local tb = textPanel.body
      if lb.layout and lb.layout.swatch then lb.layout.swatch:Refresh() end
      if tb.text and tb.text.swatch then tb.text.swatch:Refresh() end
    end
  end
  panel.RefreshPreview = RefreshIconPage(panel)
  layoutPanel.RefreshPreview = RefreshIconPage(layoutPanel)
  textPanel.RefreshPreview = RefreshIconPage(textPanel)
end

local function RebuildAuraIconTab()
  local panel = iconTab
  if not panel then return end
  for _, r in ipairs(iconRows) do r:Hide() end

  if panel.head.enable then panel.head.enable:Refresh() end
  panel.head.hideBliz.Refresh()
  -- Each page draws its own stage.
  for _, iconPanel in ipairs(iconPanels or {}) do
    if iconPanel.RefreshPreview then iconPanel.RefreshPreview() end
  end

  local body = panel.body
  local filter = body.filter
  local list = NS.db.icons.list
  local y = -28
  for index, entry in ipairs(list) do
    local row = iconRows[index]
    if not row then row = BuildIconRow(filter.content); iconRows[index] = row end
    row:SetParent(filter.content)
    row.index, row.entry = index, entry
    row.icon:SetTexture(NS.SpellIcon(entry.spellID))
    row.name:SetText(NS.SpellName(entry.spellID))
    row.id:SetText(tostring(entry.spellID))
    row.enabled:Refresh()
    row.up:SetEnabled(index > 1)
    row.down:SetEnabled(index < #list)
    row.priority.Refresh()
    row.stripe:SetShown(index % 2 == 0)
    row:SetPoint("TOPLEFT", 0, y)
    row:Show()
    y = y - ROW_H - 2
  end

  filter.addDrop:SetPoint("TOPLEFT", 10, y - 10)
  filter.addBoxLabel:SetPoint("LEFT", filter.addDrop, "RIGHT", 14, 0)
  filter.addBox:SetPoint("LEFT", filter.addBoxLabel, "RIGHT", 8, 0)

  filter:Resize(-y + 46)

  local layout = iconPanels[2].body.layout
  layout.anchor:Refresh()
  layout.grow:Refresh()
  layout.padX:Refresh()
  layout.padY:Refresh()
  layout.perRow:Refresh()
  layout.size:Refresh()
  layout.spacing:Refresh()
  layout.border:Refresh()
  layout.borderColor:Refresh()
  layout.swatch:Refresh()
  layout:Resize(278)

  local text = iconPanels[3].body.text
  text.swirl:Refresh()
  text.timer:Refresh()
  text.count:Refresh()
  text.timerFont:Refresh()
  text.timerSize:Refresh()
  text.timerOutline:Refresh()
  text.timerAnchor:Refresh()
  text.timerPrecision:Refresh()
  text.timerX:Refresh()
  text.timerY:Refresh()
  text.countFont:Refresh()
  text.countSize:Refresh()
  text.countOutline:Refresh()
  text.countAnchor:Refresh()
  text.countX:Refresh()
  text.countY:Refresh()
  text.swatch:Refresh()
  text:Resize(294)

  -- One pass per page: each has its own body and its own single section.
  for _, iconPanel in ipairs(iconPanels or {}) do
    LayoutSections(iconPanel.body, iconPanel.body.sections)
  end
end

-- Missing Debuffs.
--
-- A different visual from the missing-debuff wash under Health/Border
-- Coloring: an icon that displaces off the plate while its debuff is present.
-- Styled on the Aura Icons pages -- same scaffold, same widgets -- but its own
-- row shape, since each entry carries an icon-or-colour choice and its own
-- combat-only toggle.
--
-- Everything hangs off the `missing` table, not a local per concern: this
-- file's main chunk is at Lua's 200-local ceiling.

function missing.BuildRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(missing.ROW_W, ROW_H)

  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, 0.03)

  row.up = Button(row, "UP", 30, function()
    if NS.ListMove(NS.db.missingIcons.list, row.index, -1) then Structural() end
  end)
  row.up:SetPoint("LEFT", 8, 0)
  StyleText(row.up.label, 10)
  row.priority = EditableNumber(row, 26,
    function() return row.index or 1 end,
    function(value)
      if NS.ListMoveTo(NS.db.missingIcons.list, row.index, value) then Structural() end
    end)
  row.priority:SetPoint("LEFT", 41, 0)

  row.down = Button(row, "DOWN", 38, function()
    if NS.ListMove(NS.db.missingIcons.list, row.index, 1) then Structural() end
  end)
  row.down:SetPoint("LEFT", 70, 0)
  StyleText(row.down.label, 10)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 118, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = Label(row, "")
  row.name:SetPoint("LEFT", 146, 0)
  row.name:SetWidth(160)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.id = Dim(row, "")
  row.id:SetPoint("LEFT", 312, 0)
  row.id:SetWidth(46)

  row.enabled = Checkbox(row,
    function() return row.entry and row.entry.enabled ~= false end,
    function(v) if row.entry then row.entry.enabled = v; Structural() end end)
  row.enabled:SetPoint("LEFT", 366, 0)

  -- Icon-or-colour, per entry. The button's own label says which mode this
  -- entry is in; the swatch beside it is only live in Color mode, and dims
  -- to a hint of itself otherwise -- picking a colour switches the mode for
  -- you, rather than needing the button pressed first.
  row.mode = Button(row, "Icon", 56, function()
    if not row.entry then return end
    row.entry.useIcon = row.entry.useIcon == false
    Structural()
  end)
  row.mode:SetPoint("LEFT", 398, 0)
  StyleText(row.mode.label, 10)

  row.swatch = ColorSwatch(row,
    function() return (row.entry and row.entry.color) or { r = 1, g = 0.25, b = 0.8, a = 1 } end,
    function(r, g, b, a)
      if not row.entry then return end
      row.entry.color = { r = r, g = g, b = b, a = a }
      row.entry.useIcon = false
      Structural()
    end)
  row.swatch:SetPoint("LEFT", 460, 0)

  row.combatOnly = Checkbox(row,
    function() return row.entry and row.entry.missingCombatOnly and true or false end,
    function(v) if row.entry then row.entry.missingCombatOnly = v; Structural() end end)
  row.combatOnly:SetPoint("LEFT", 494, 0)
  Tip(row.combatOnly, "Combat only", TIPS.missingCombatOnly)

  row.remove = CloseX(row, function()
    table.remove(NS.db.missingIcons.list, row.index)
    Structural()
  end)
  row.remove:SetPoint("LEFT", 528, 0)

  return row
end

-- Row-shape refresh, split out of missing.Rebuild so it never drifts from
-- what BuildRow actually laid out.
function missing.RefreshRow(row, index, entry)
  row.index, row.entry = index, entry
  row.icon:SetTexture(NS.SpellIcon(entry.spellID))
  row.icon:SetDesaturated(entry.useIcon == false)
  row.icon:SetAlpha(entry.useIcon == false and 0.35 or 1)
  row.name:SetText(NS.SpellName(entry.spellID))
  row.id:SetText(tostring(entry.spellID))
  row.enabled:Refresh()
  row.mode:SetText(entry.useIcon == false and "Color" or "Icon")
  row.swatch:Refresh()
  row.swatch:SetAlpha(entry.useIcon == false and 1 or 0.35)
  row.combatOnly:Refresh()
end

function missing.Build()
  local list = BuildTabFrame(tabPanels[missing.PAGE_LIST], nil, nil, nil, missing.STAGE_H)
  local layoutPanel = BuildTabFrame(tabPanels[missing.PAGE_LAYOUT], nil, nil, nil, missing.STAGE_H)
  missing.panels = { list, layoutPanel }
  missing.tab = list
  list:SetHeadHeight(6 + missing.STAGE_H + 12)
  layoutPanel:SetHeadHeight(6 + missing.STAGE_H + 12)

  -- RefreshPreviews() (the generic sweep every Live()/Structural() change
  -- goes through) only ever touches a panel's stage via this callback --
  -- see RefreshIconPage for the Aura Icons equivalent. Without it, a
  -- Live()-only change (anchor, padX, padY) never reached LayoutStage at
  -- all, since only Structural() happens to also rebuild the whole tab.
  local function RefreshMissingStage(panel)
    return function()
      if panel.head and panel.head.stage then missing.LayoutStage(panel.head.stage) end
    end
  end
  list.RefreshPreview = RefreshMissingStage(list)
  layoutPanel.RefreshPreview = RefreshMissingStage(layoutPanel)

  local body = list.body
  body.sections = {}
  local filter = CollapsibleSection(body, "missingFilter", "Which Debuffs",
    "reminder icons, in display order")
  table.insert(body.sections, filter)
  body.filter = filter

  local fc = filter.content
  filter.hOrder = Header(fc, "Priority")
  filter.hOrder:SetPoint("TOPLEFT", 8, -6)
  filter.hOrder:SetWidth(100)
  filter.hOrder:SetJustifyH("CENTER")
  filter.hAura = Header(fc, "Debuff")
  filter.hAura:SetPoint("TOPLEFT", 118, -6)
  filter.hID = Header(fc, "ID")
  filter.hID:SetPoint("TOPLEFT", 312, -6)
  filter.hShow = Header(fc, "Show")
  filter.hShow:SetPoint("TOPLEFT", 366, -6)
  filter.hMode = Header(fc, "Icon/Color")
  filter.hMode:SetPoint("TOPLEFT", 398, -6)
  filter.hCombat = Header(fc, "Combat")
  filter.hCombat:SetPoint("TOPLEFT", 494, -6)

  filter.divider = fc:CreateTexture(nil, "ARTWORK")
  filter.divider:SetPoint("TOPLEFT", 10, -22)
  filter.divider:SetPoint("TOPRIGHT", -10, -22)
  filter.divider:SetHeight(1)
  filter.divider:SetColorTexture(0.4, 0.4, 0.45, 0.6)

  local function AddMissingSpell(input)
    if not input then return end
    local spellID = ResolveAndReport(input)
    if not spellID then return end
    if not NS.ListIndexOf(NS.db.missingIcons.list, spellID) then
      table.insert(NS.db.missingIcons.list, { spellID = spellID, enabled = true })
      Structural()
    end
  end

  filter.addDrop = AddSpellDropdown(fc, 250, "Track a missing debuff...",
    function(spellID) return NS.ListIndexOf(NS.db.missingIcons.list, spellID) ~= nil end,
    AddMissingSpell)
  filter.addBox = IDBox(fc, AddMissingSpell)
  Tip(filter.addDrop, "Track a missing debuff", TIPS.missingAdd)
  Tip(filter.addBox, "Track by ID or name", TIPS.missingAdd)
  filter.addBoxLabel = Dim(fc, "or ID/name:")

  body = layoutPanel.body
  body.sections = {}
  local layout = CollapsibleSection(body, "missingLayout", "Position & Size",
    "where the row sits, and how the icons look")
  table.insert(body.sections, layout)
  body.layout = layout

  local lc = layout.content
  layout.anchorLabel = Label(lc, "Anchor to bar")
  layout.anchorLabel:SetPoint("TOPLEFT", 14, -12)
  layout.anchor = Dropdown(lc, 150, ANCHOR_POINTS,
    function() return NS.db.missingIcons.anchor end,
    function(v) NS.db.missingIcons.anchor = v; Live() end)
  layout.anchor:SetPoint("TOPLEFT", 150, -10)
  TipLabel(layout.anchorLabel, "Anchor to bar", TIPS.missingAnchor)
  Tip(layout.anchor, "Anchor to bar", TIPS.missingAnchor)

  layout.growLabel = Label(lc, "Grow direction")
  layout.growLabel:SetPoint("TOPLEFT", 14, -44)
  layout.grow = Dropdown(lc, 150, {
    { text = "Grow right", value = "RIGHT" },
    { text = "Grow left",  value = "LEFT" },
  }, function() return NS.db.missingIcons.grow end,
     -- Baked into each entry's displaced position at build time (see
     -- MissingIcons.lua), unlike Aura Icons' flow layout -- has to be a
     -- full rebuild, not a reposition.
     function(v) NS.db.missingIcons.grow = v; Structural() end)
  layout.grow:SetPoint("TOPLEFT", 150, -42)
  TipLabel(layout.growLabel, "Grow direction", TIPS.missingGrow)
  Tip(layout.grow, "Grow direction", TIPS.missingGrow)

  layout.padXLabel = Label(lc, "X padding")
  layout.padXLabel:SetPoint("TOPLEFT", 14, -78)
  layout.padX = Slider(lc, 130, -60, 60, 120,
    function() return NS.db.missingIcons.padX or 0 end,
    function(v) NS.db.missingIcons.padX = v; Live() end)
  layout.padX:SetPoint("TOPLEFT", 150, -78)
  TipLabel(layout.padXLabel, "X padding", TIPS.missingOffsetX)
  Tip(layout.padX, "X padding", TIPS.missingOffsetX)

  layout.padYLabel = Label(lc, "Y padding")
  layout.padYLabel:SetPoint("TOPLEFT", 14, -104)
  layout.padY = Slider(lc, 130, -60, 60, 120,
    function() return NS.db.missingIcons.padY or 0 end,
    function(v) NS.db.missingIcons.padY = v; Live() end)
  layout.padY:SetPoint("TOPLEFT", 150, -104)
  TipLabel(layout.padYLabel, "Y padding", TIPS.missingOffsetY)
  Tip(layout.padY, "Y padding", TIPS.missingOffsetY)

  layout.divider = lc:CreateTexture(nil, "ARTWORK")
  layout.divider:SetPoint("TOPLEFT", 12, -132)
  layout.divider:SetPoint("TOPRIGHT", -12, -132)
  layout.divider:SetHeight(1)
  layout.divider:SetColorTexture(0.4, 0.4, 0.45, 0.5)

  layout.sizeLabel = Label(lc, "Icon size")
  layout.sizeLabel:SetPoint("TOPLEFT", 14, -144)
  layout.size = Slider(lc, 130, 10, 48, 38,
    function() return NS.db.missingIcons.size end,
    function(v) NS.db.missingIcons.size = v; Structural() end)
  layout.size:SetPoint("TOPLEFT", 150, -144)
  TipLabel(layout.sizeLabel, "Icon size", TIPS.missingSize)
  Tip(layout.size, "Icon size", TIPS.missingSize)

  layout.spacingLabel = Label(lc, "Icon spacing")
  layout.spacingLabel:SetPoint("TOPLEFT", 14, -170)
  layout.spacing = Slider(lc, 130, 0, 16, 16,
    function() return NS.db.missingIcons.spacing end,
    function(v) NS.db.missingIcons.spacing = v; Structural() end)
  layout.spacing:SetPoint("TOPLEFT", 150, -170)
  TipLabel(layout.spacingLabel, "Icon spacing", TIPS.missingSpacing)
  Tip(layout.spacing, "Icon spacing", TIPS.missingSpacing)

  layout.borderLabel = Label(lc, "Border size")
  layout.borderLabel:SetPoint("TOPLEFT", 14, -196)
  layout.border = Slider(lc, 130, 0, 5, 5,
    function() return NS.db.missingIcons.borderSize or 0 end,
    function(v) NS.db.missingIcons.borderSize = v; Structural() end)
  layout.border:SetPoint("TOPLEFT", 150, -196)
  TipLabel(layout.borderLabel, "Border size", TIPS.missingBorder)
  Tip(layout.border, "Border size", TIPS.missingBorder)

  layout.borderColorLabel = Label(lc, "Border color")
  layout.borderColorLabel:SetPoint("TOPLEFT", 14, -222)
  layout.borderColor = ColorSwatch(lc,
    function() return NS.db.missingIcons.borderColor or { r = 1, g = 1, b = 1, a = 1 } end,
    function(r, g, b, a)
      NS.db.missingIcons.borderColor = { r = r, g = g, b = b, a = a }
      Structural()
    end)
  layout.borderColor:SetPoint("TOPLEFT", 150, -222)
  TipLabel(layout.borderColorLabel, "Border color", TIPS.missingBorderCol)
  Tip(layout.borderColor, "Border color", TIPS.missingBorderCol)

  layout.collapse = Checkbox(lc,
    function() return NS.db.missingIcons.collapse ~= false end,
    function(v) NS.db.missingIcons.collapse = v; Structural() end)
  layout.collapse:SetPoint("TOPLEFT", 14, -254)
  layout.collapseLabel = Label(lc, "Collapse")
  layout.collapseLabel:SetPoint("LEFT", layout.collapse, "RIGHT", 6, 0)
  Tip(layout.collapse, "Collapse", TIPS.missingCollapse)
  TipLabel(layout.collapseLabel, "Collapse", TIPS.missingCollapse)
end

-- Static preview only: no secure containers, so nothing here can be refused by
-- combat lockdown or thrown off by a debuff that happens to be up. It cannot
-- tell you whether a spell ID is correct -- same caveat as every preview.
function missing.LayoutStage(stage)
  for _, chip in ipairs(stage.missingChips or {}) do chip:Hide() end
  stage.missingChips = stage.missingChips or {}

  local db = NS.db.missingIcons
  local list = db.list
  if #list == 0 then return end

  local host = stage.missingHost
  if not host then
    host = CreateFrame("Frame", nil, stage)
    stage.missingHost = host
  end
  host:SetSize(NS.MissingIconRowWidth(db, #list), db.size)
  host:ClearAllPoints()
  host:SetPoint(NS.AnchorMirror[db.anchor] or "BOTTOM", stage.bar, db.anchor or "TOP",
    db.padX or 0, db.padY or 0)

  local bw = db.borderSize or 0
  local bc = db.borderColor or { r = 1, g = 1, b = 1, a = 1 }
  for index, entry in ipairs(list) do
    local chip = stage.missingChips[index]
    if not chip then
      chip = CreateFrame("Frame", nil, host)
      chip.bg = chip:CreateTexture(nil, "BACKGROUND")
      chip.bg:SetAllPoints()
      chip.art = chip:CreateTexture(nil, "ARTWORK")
      stage.missingChips[index] = chip
    end
    chip:SetSize(db.size, db.size)
    chip:ClearAllPoints()
    chip:SetPoint("LEFT", host, "LEFT", NS.MissingIconSlotOffset(db, index, #list), 0)
    chip.bg:SetColorTexture(bc.r, bc.g, bc.b, bc.a or 1)
    chip.art:ClearAllPoints()
    chip.art:SetPoint("TOPLEFT", chip, "TOPLEFT", bw, -bw)
    chip.art:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -bw, bw)
    if entry.useIcon == false then
      local ec = entry.color or { r = 1, g = 0.25, b = 0.8 }
      chip.art:SetColorTexture(ec.r, ec.g, ec.b, 0.9)
    else
      -- SetTexture alone is enough to replace what a prior SetColorTexture
      -- call left behind -- SetColorTexture(nil) is not a valid call
      -- (it needs real r,g,b), which is what was throwing here. Vertex
      -- colour is reset too, in case a colour-mode draw ever tinted it.
      chip.art:SetTexture(NS.SpellIcon(entry.spellID))
      chip.art:SetVertexColor(1, 1, 1)
      chip.art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    chip:Show()
  end
end

function missing.Rebuild()
  local panel = missing.tab
  if not panel then return end
  for _, r in ipairs(missing.rows) do r:Hide() end

  for _, p in ipairs(missing.panels or {}) do
    if p.head and p.head.stage then missing.LayoutStage(p.head.stage) end
  end

  local body = panel.body
  local filter = body.filter
  local list = NS.db.missingIcons.list
  local y = -28
  for index, entry in ipairs(list) do
    local row = missing.rows[index]
    if not row then row = missing.BuildRow(filter.content); missing.rows[index] = row end
    row:SetParent(filter.content)
    missing.RefreshRow(row, index, entry)
    row.up:SetEnabled(index > 1)
    row.down:SetEnabled(index < #list)
    row.priority.Refresh()
    row.stripe:SetShown(index % 2 == 0)
    row:SetPoint("TOPLEFT", 0, y)
    row:Show()
    y = y - ROW_H - 2
  end

  filter.addDrop:SetPoint("TOPLEFT", 10, y - 10)
  filter.addBoxLabel:SetPoint("LEFT", filter.addDrop, "RIGHT", 14, 0)
  filter.addBox:SetPoint("LEFT", filter.addBoxLabel, "RIGHT", 8, 0)
  filter:Resize(-y + 46)

  local layout = missing.panels[2].body.layout
  layout.anchor:Refresh()
  layout.grow:Refresh()
  layout.padX:Refresh()
  layout.padY:Refresh()
  layout.size:Refresh()
  layout.spacing:Refresh()
  layout.border:Refresh()
  layout.borderColor:Refresh()
  layout.collapse:Refresh()
  local overCap = #list > 4
  layout.collapseLabel:SetText(overCap and "Collapse (off past 4)" or "Collapse")
  layout:Resize(278)

  for _, p in ipairs(missing.panels or {}) do
    LayoutSections(p.body, p.body.sections)
  end
end

-- Tab 3 -- profiles. Not built on BuildTabFrame: that shell assumes a module
-- toggle and a live preview, and a profile has neither.

local profilesTab

-- Entries for any "pick a profile" dropdown. `includeInherit` adds the entry
-- that CLEARS a spec binding, which is how a spec goes back to following the
-- character default instead of pinning its own.
local function ProfileEntries(includeInherit)
  local list = {}
  if includeInherit then
    table.insert(list, { text = "|cff808080(use character default)|r", value = false })
  end
  for _, name in ipairs(NS.ListProfiles()) do
    table.insert(list, { text = name, value = name })
  end
  return list
end

local function BuildProfilesTab()
  local panel = tabPanels[4]

  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("TOPRIGHT", -12, -4)
  scroll:SetPoint("BOTTOMLEFT", 4, 4)

  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(716, 600)
  scroll:SetScrollChild(body)
  body.scrollBar = BuildScrollBar(scroll)

  panel.body = body
  body.sections = {}

  -----------------------------------------------------------------------------
  -- Active profile
  -----------------------------------------------------------------------------
  local active = CollapsibleSection(body, "profActive", "Active Profile",
    "what this character is using right now, and why")
  table.insert(body.sections, active)
  body.active = active

  local ac = active.content
  active.nameLabel = Label(ac, "Profile")
  active.nameLabel:SetPoint("TOPLEFT", 14, -12)
  active.drop = Dropdown(ac, 220, function() return ProfileEntries(false) end,
    function() return NS.ProfileKey() end,
    function(name)
      if name and name ~= NS.ProfileKey() then
        NS.SelectProfile(name)
        NS.Options_RebuildAll()
      end
    end)
  active.drop:SetPoint("TOPLEFT", 130, -10)
  Tip(active.drop, "Profile", TIPS.profileSelect)

  active.why = Dim(ac, "")
  active.why:SetPoint("TOPLEFT", 14, -42)

  active.newButton = Button(ac, "New", 70, function()
    ShowPrompt("New profile", "Starts blank. Use Copy to begin from this one instead.",
      "Create", function(name)
        local ok, err = NS.CreateProfile(name, nil)
        if not ok then NS.Print("|cffff4040" .. tostring(err) .. "|r") end
        NS.Options_RebuildAll()
      end)
  end)
  active.newButton:SetPoint("TOPLEFT", 14, -70)
  Tip(active.newButton, "New", TIPS.profileNew)

  active.copyButton = Button(ac, "Copy", 70, function()
    local from = NS.ProfileKey()
    ShowPrompt("Copy profile",
      ("A new profile starting as a copy of |cff55dd55%s|r."):format(from),
      "Copy", function(name)
        local ok, err = NS.CreateProfile(name, from)
        if not ok then NS.Print("|cffff4040" .. tostring(err) .. "|r") end
        NS.Options_RebuildAll()
      end, from .. " copy")
  end)
  active.copyButton:SetPoint("TOPLEFT", 90, -70)
  Tip(active.copyButton, "Copy", TIPS.profileCopy)

  active.renameButton = Button(ac, "Rename", 70, function()
    local from = NS.ProfileKey()
    ShowPrompt("Rename profile",
      ("Rename |cff55dd55%s|r. Every character and spec pointing at it follows."):format(from),
      "Rename", function(name)
        local ok, err = NS.RenameProfile(from, name)
        if not ok then NS.Print("|cffff4040" .. tostring(err) .. "|r") end
        NS.Options_RebuildAll()
      end, from)
  end)
  active.renameButton:SetPoint("TOPLEFT", 166, -70)
  Tip(active.renameButton, "Rename", TIPS.profileRename)

  active.deleteButton = Button(ac, "Delete", 70, function()
    local name = NS.ProfileKey()
    ShowConfirm("Delete profile",
      ("Delete |cffff4040%s|r permanently?\n\nAnything pointing at it falls back to the character default."):format(name),
      "Delete", function()
        local ok, err = NS.DeleteProfile(name)
        if not ok then NS.Print("|cffff4040" .. tostring(err) .. "|r") end
        NS.Options_RebuildAll()
      end)
  end)
  active.deleteButton:SetPoint("TOPLEFT", 242, -70)
  Tip(active.deleteButton, "Delete", TIPS.profileDelete)

  -----------------------------------------------------------------------------
  -- Per-spec assignment
  -----------------------------------------------------------------------------
  local specs = CollapsibleSection(body, "profSpecs", "Profile Per Specialization",
    "switch spec and the profile follows")
  table.insert(body.sections, specs)
  body.specs = specs

  local sc = specs.content
  specs.charLabel = Label(sc, "Character default")
  specs.charLabel:SetPoint("TOPLEFT", 14, -12)
  specs.charDrop = Dropdown(sc, 220, function() return ProfileEntries(false) end,
    function() return NS.GetCharacterDefault() end,
    function(name)
      if name then
        NS.SetCharacterDefault(name)
        NS.Options_RebuildAll()
      end
    end)
  specs.charDrop:SetPoint("TOPLEFT", 210, -10)
  Tip(specs.charDrop, "Character default", "The profile this character loads when no specialisation binding applies.")

  specs.note = Dim(sc, "Used by any spec left on (use character default).")
  specs.note:SetPoint("TOPLEFT", 14, -40)

  -- One row per spec, built from the class's own spec list, so four-spec
  -- Druids and one-spec low levels both come out right with no special case.
  specs.rows = {}
  local y = -68
  for _, spec in ipairs(NS.ClassSpecs()) do
    local row = { specID = spec.id }

    row.label = Label(sc, ("Profile for %s"):format(spec.name))
    row.label:SetPoint("TOPLEFT", 36, y)

    if spec.icon then
      row.icon = sc:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(16, 16)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.icon:SetPoint("TOPLEFT", 14, y + 2)
      row.icon:SetTexture(spec.icon)
    end

    -- `false` is the cleared value and has to stay distinct from nil: the
    -- setter receives false to unbind and a name to bind, and Dropdown uses
    -- nil to mean "no selection".
    row.drop = Dropdown(sc, 220, function() return ProfileEntries(true) end,
      function() return NS.GetSpecProfile(row.specID) or false end,
      function(value)
        NS.SetSpecProfile(row.specID, value or nil)
        NS.Options_RebuildAll()
      end)
    row.drop:SetPoint("TOPLEFT", 210, y + 2)
    Tip(row.drop, "Spec binding", TIPS.profileBind)

    table.insert(specs.rows, row)
    y = y - 32
  end
  specs.contentHeight = -y + 10

  if #specs.rows == 0 then
    specs.empty = Dim(sc, "|cffffcc00No specializations available yet.|r")
    specs.empty:SetPoint("TOPLEFT", 14, -68)
    specs.contentHeight = 100
  end

  profilesTab = panel
  return panel
end

local function RebuildProfilesTab()
  local panel = profilesTab
  if not panel then return end
  local body = panel.body

  local active = body.active
  active.drop:Refresh()

  -- Say WHICH assignment is in force, because picking a profile re-points
  -- that one and not the other. Guessing wrong is how you change every spec
  -- when you meant to change one.
  local specName = NS.SpecName()
  if NS.IsSpecBound() then
    active.why:SetText(("|cff55dd55Bound to %s.|r Choosing above re-points that binding.")
      :format(specName or "this spec"))
  else
    active.why:SetText(("|cff808080Following the character default.|r Choosing above changes it for %s.")
      :format(NS.CharacterKey()))
  end
  active:Resize(110)

  local specs = body.specs
  specs.charDrop:Refresh()
  for _, row in ipairs(specs.rows) do
    row.drop:Refresh()
  end
  specs:Resize(specs.contentHeight or 100)

  LayoutSections(body, body.sections)
end

-- Tab 4 -- about.
--
-- The priority diagram is DRAWN, not a screenshot: a shipped image would need
-- a .tga, would not follow the theme colours, and would go stale the moment
-- the rules UI changed.

local aboutTab

-- A fake rule row: swatch plus label, laid out like the real Color Rules list
-- so the diagram reads as the same thing rather than an abstraction of it.
local function MockRule(parent, y, r, g, b, text, note)
  local row = CreateFrame("Frame", nil, parent)
  row:SetPoint("TOPLEFT", 14, y)
  row:SetPoint("TOPRIGHT", -14, y)
  row:SetHeight(24)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, 0.03)

  row.swatch = row:CreateTexture(nil, "ARTWORK")
  row.swatch:SetSize(18, 18)
  row.swatch:SetPoint("LEFT", 8, 0)
  row.swatch:SetColorTexture(r, g, b, 1)

  row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.border:SetPoint("TOPLEFT", row.swatch, "TOPLEFT", -1, 1)
  row.border:SetPoint("BOTTOMRIGHT", row.swatch, "BOTTOMRIGHT", 1, -1)
  PixelBorder(row.border)
  row.border:SetBackdropBorderColor(0, 0, 0, 1)

  row.text = Label(row, text)
  row.text:SetPoint("LEFT", 36, 0)

  if note then
    row.note = Dim(row, note)
    row.note:SetPoint("LEFT", 210, 0)
  end
  return row
end

-- A miniature nameplate showing what a given set of debuffs produces.
-- borderColor is an optional {r,g,b}: the diagram has to show a health rule
-- and a border rule applying at the same time, which is the whole reason the
-- two lists exist.
local function MockPlate(parent, x, y, r, g, b, borderColor, caption)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("TOPLEFT", x, y)
  holder:SetSize(150, 40)

  local bar = CreateFrame("StatusBar", nil, holder)
  bar:SetPoint("TOPLEFT", 0, -14)
  bar:SetSize(150, 14)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)
  bar:SetStatusBarColor(0.55, 0.12, 0.12)

  local edge = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  PixelBorder(edge)
  edge:SetBackdropBorderColor(0, 0, 0, 1)

  if r then
    local tint = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    tint:SetPoint("TOPLEFT", 1, -1)
    tint:SetPoint("BOTTOMRIGHT", -1, 1)
    tint:SetColorTexture(r, g, b, 1)
  end

  if borderColor then
    local function Edge()
      local e = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      e:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)
      return e
    end
    local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
    top:SetPoint("TOPLEFT");       top:SetPoint("TOPRIGHT");       top:SetHeight(2)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(2)
    left:SetPoint("TOPLEFT");      left:SetPoint("BOTTOMLEFT");    left:SetWidth(2)
    right:SetPoint("TOPRIGHT");    right:SetPoint("BOTTOMRIGHT");  right:SetWidth(2)
  end

  holder.caption = Dim(holder, caption)
  holder.caption:SetPoint("TOPLEFT", 0, 0)
  return holder
end

local function BuildAboutTab()
  local panel = tabPanels[5]

  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("TOPRIGHT", -12, -4)
  scroll:SetPoint("BOTTOMLEFT", 4, 4)

  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(716, 900)
  scroll:SetScrollChild(body)
  body.scrollBar = BuildScrollBar(scroll)

  panel.body = body
  body.sections = {}

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  local help = CollapsibleSection(body, "aboutHelp", "Help & Feedback",
    "bugs, questions, suggestions")
  table.insert(body.sections, help)

  local hc = help.content
  help.text = Label(hc, "")
  help.text:SetPoint("TOPLEFT", 14, -12)
  help.text:SetPoint("TOPRIGHT", -14, -12)
  help.text:SetJustifyH("LEFT")
  help.text:SetText("This addon is early and changing quickly. If something breaks, "
    .. "looks wrong, or you want a feature, come and say so:")
  help.text:SetHeight(34)

  help.label = Label(hc, "Discord")
  help.label:SetPoint("TOPLEFT", 14, -54)

  -- Read-only rather than disabled: a disabled EditBox cannot be selected,
  -- and selecting is the entire point.
  help.link = CreateFrame("EditBox", nil, hc, "InputBoxTemplate")
  help.link:SetPoint("TOPLEFT", 90, -52)
  help.link:SetSize(240, 22)
  help.link:SetAutoFocus(false)
  StyleText(help.link, 12)
  help.link:SetText("https://discord.gg/cdKSgKyCVJ")
  help.link:SetCursorPosition(0)
  help.link:SetScript("OnTextChanged", function(self)
    -- Anything typed is reverted: the box exists to be copied FROM.
    if self:GetText() ~= "https://discord.gg/cdKSgKyCVJ" then
      self:SetText("https://discord.gg/cdKSgKyCVJ")
      self:SetCursorPosition(0)
    end
  end)
  help.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  help.link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  help.link:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  help.hint = Dim(hc, "Click the box to select, then Ctrl+C.")
  help.hint:SetPoint("TOPLEFT", 14, -82)
  help.height = 110

  local what = CollapsibleSection(body, "aboutWhat", "What PlateTweaks Does",
    "colour enemy nameplates by the debuffs you have on them")
  table.insert(body.sections, what)

  local wc = what.content
  what.text = Label(wc, "")
  what.text:SetPoint("TOPLEFT", 14, -12)
  what.text:SetPoint("TOPRIGHT", -14, -12)
  what.text:SetJustifyH("LEFT")
  what.text:SetJustifyV("TOP")
  what.text:SetText(
    "|cff55dd55Health Coloring|r  tints the health bar.\n"
    .. "|cff55dd55Border Coloring|r  draws a border around it.\n"
    .. "|cff55dd55Aura Icons|r  a row of icons on the plate. Off by default.\n\n"
    .. "Health and Border are separate lists with separate priorities, so you can "
    .. "use either, or both together. Works alongside Blizzard's nameplates and "
    .. "every nameplate addon we could test.")
  what.text:SetHeight(96)
  what.height = 116

  -----------------------------------------------------------------------------
  local rules = CollapsibleSection(body, "aboutRules", "How Rules Work",
    "the topmost matching rule in each list wins")
  table.insert(body.sections, rules)

  local rc = rules.content
  rules.intro = Label(rc, "")
  rules.intro:SetPoint("TOPLEFT", 14, -12)
  rules.intro:SetPoint("TOPRIGHT", -14, -12)
  rules.intro:SetJustifyH("LEFT")
  rules.intro:SetText(
    "A rule is a colour plus one or more debuffs. It matches when |cff55dd55ALL|r of "
    .. "them are on the target. Rules are checked top down; the first match wins. "
    .. "|cffffff00Auto sort|r puts the specific ones above the general ones for you.")
  rules.intro:SetHeight(44)

  rules.hExample = Dim(rc, "Health Coloring list")
  rules.hExample:SetPoint("TOPLEFT", 14, -62)
  MockRule(rc, -82, 0.20, 0.90, 0.25, "Moonfire |cff808080+|r Sunfire")
  MockRule(rc, -108, 0.85, 0.25, 0.95, "Moonfire")

  rules.bExample = Dim(rc, "Border Coloring list  |cff808080(its own priority)|r")
  rules.bExample:SetPoint("TOPLEFT", 14, -142)
  MockRule(rc, -162, 1.00, 0.55, 0.10, "Sunfire")

  rules.outcome = Dim(rc, "What you see:")
  rules.outcome:SetPoint("TOPLEFT", 14, -200)

  -- The fourth plate is the point of the two lists: a health rule and a
  -- border rule matching at once, each from its own stack.
  MockPlate(rc, 14,  -220, 0.85, 0.25, 0.95, nil,               "Moonfire only")
  MockPlate(rc, 190, -220, nil,  nil,  nil,  { 1, 0.55, 0.10 }, "Sunfire only")
  MockPlate(rc, 366, -220, 0.20, 0.90, 0.25, { 1, 0.55, 0.10 }, "both -- both apply")
  MockPlate(rc, 542, -220, nil,  nil,  nil,  nil,               "neither")
  rules.height = 292

  -----------------------------------------------------------------------------
  local cost = CollapsibleSection(body, "aboutCost", "Performance",
    "why combo rules are expensive")
  table.insert(body.sections, cost)

  local cc = cost.content
  cost.text = Label(cc, "")
  cost.text:SetPoint("TOPLEFT", 14, -12)
  cost.text:SetPoint("TOPRIGHT", -14, -12)
  cost.text:SetJustifyH("LEFT")
  cost.text:SetJustifyV("TOP")
  cost.text:SetText(
    "The game will not tell an addon which auras are on an enemy, so PlateTweaks "
    .. "never asks -- it hands the conditions to Blizzard's own aura containers and "
    .. "lets the game decide.\n\n"
    .. "A rule costs the same whether it needs one debuff or two.\n\n"
    .. "Two-debuff rules used to be far more expensive, and older versions warned "
    .. "you before creating one. That no longer applies -- build the rules you want.\n\n"
    .. "Friendly nameplates are skipped entirely, since nothing you apply can land "
    .. "on them.")
  cost.text:SetHeight(126)
  cost.height = 146

  -----------------------------------------------------------------------------
  local tips = CollapsibleSection(body, "aboutTips", "Tips",
    "small things that save trouble")
  table.insert(body.sections, tips)

  local tc = tips.content
  tips.text = Label(tc, "")
  tips.text:SetPoint("TOPLEFT", 14, -12)
  tips.text:SetPoint("TOPRIGHT", -14, -12)
  tips.text:SetJustifyH("LEFT")
  tips.text:SetJustifyV("TOP")
  tips.text:SetText(
    "|cff55dd55Adding a debuff|r  pick it from the dropdown or type a name or ID. Many "
    .. "abilities apply an aura whose ID differs from the one you cast; PlateTweaks "
    .. "corrects that and tells you when it does.\n\n"
    .. "|cff55dd55Mixing both|r  tick |cffffff00Also show...|r above either preview to see "
    .. "health and border together.\n\n"
    .. "|cff55dd55Border covered?|r  Health Coloring -> Bar Edges pulls the tint back off your "
    .. "nameplate addon's own border.\n\n"
    .. "|cff55dd55Nothing colouring?|r  check the debuff is one you actually apply, and that the module is enabled in the header.")
  tips.text:SetHeight(126)
  tips.height = 146


  aboutTab = panel
  return panel
end

local function RebuildAboutTab()
  local panel = aboutTab
  if not panel then return end
  for _, section in ipairs(panel.body.sections) do
    section:Resize(section.height or 120)
  end
  LayoutSections(panel.body, panel.body.sections)
end

-------------------------------------------------------------------------------
-- Global Settings — settings that draw on every nameplate, rule or no rule
-------------------------------------------------------------------------------

-- These three lived under "Health Coloring" purely because that is where they
-- were built. None is conditional on a rule matching -- the plate border is
-- redrawn on every plate, the edge inset applies to both tint kinds, and the
-- pandemic flash is a global toggle.
--
-- The CollapsibleSection keys are unchanged, so everyone's open/closed state
-- survives the move.

-- Every Global Settings page previews against the same simulated plate, painted
-- from the live global settings, so a change is visible on the page that makes
-- it rather than only on the Health Coloring page these used to share.
local function PaintGlobalStage(stage, showMissing)
  local cfg = NS.db.tints or {}

  -- The plate border is drawn by stage:RefreshPlateBorder, which RefreshPreviews
  -- runs for every stage. It is a global setting, so every preview shows the
  -- same one and this page has no reason to keep its own copy of the maths --
  -- which had already drifted: it clamped thickness to 4 while the engine
  -- allows 8, so the two disagreed the moment the slider went past four.
  if stage.RefreshPlateBorder then stage:RefreshPlateBorder() end

  -- A stand-in rule, not a real one: these pages have no rule of their own,
  -- but the edge inset is invisible without something drawn to be inset. It
  -- goes through the real ApplyRuleFill, so the slider moves this exactly as
  -- it moves a live tint.
  local sample = { color = { r = 0.29, g = 0.78, b = 0.43, a = 0.75 }, fillStyle = "solid" }
  pcall(NS.ApplyRuleFill, stage.tint, stage.bar, sample, 0)
  stage.tint:Show()

  if showMissing then
    pcall(NS.ApplyMissingCover, stage.missingCover, stage.bar, { missingCover = true })
  else
    stage.missingCover:Hide()
  end
  for _, e in ipairs(stage.borderEdges or {}) do e:Hide() end
end

-- One page, both sections. Plate Border and Bar Edges each filled a page
-- barely a third of the way, and they answer the same question -- how the bar
-- is drawn before any rule touches it -- so they read better together than as
-- two nav entries a click apart.
local function BuildGlobalTabs()
  local panel = BuildTabFrame(tabPanels[PAGE_GENERAL])
  panel.RefreshPreview = function() PaintGlobalStage(panel.head.stage) end
  local ob = panel.body
  ob.sections = {}

  local outline = CollapsibleSection(ob, "colourOutline", "Plate Border",
    "redraw the nameplate's own black border on top of your colors")
  table.insert(ob.sections, outline)
  ob.outline = outline
  local oc = outline.content

  outline.enable = Checkbox(oc,
    function() return NS.db.tints.plateOutline ~= false end,
    function(v) NS.db.tints.plateOutline = v; Structural() end)
  outline.enable:SetPoint("TOPLEFT", 12, -10)
  Tip(outline.enable, "Keep the plate's border visible", TIPS.plateOutline)
  outline.enableLabel = Label(oc, "Keep the plate's border visible", "GameFontNormal")
  outline.enableLabel:SetPoint("LEFT", outline.enable, "RIGHT", 6, 0)
  TipLabel(outline.enableLabel, "Keep the plate's border visible", TIPS.plateOutline)

  outline.thicknessLabel = Label(oc, "Thickness")
  outline.thicknessLabel:SetPoint("TOPLEFT", 14, -38)
  TipLabel(outline.thicknessLabel, "Thickness", TIPS.outlineSize)
  outline.thickness = Slider(oc, 150, 1, 8, 7,
    function() return NS.db.tints.plateOutlineSize or 1 end,
    function(v) NS.db.tints.plateOutlineSize = v; Structural() end)
  outline.thickness:SetPoint("TOPLEFT", 130, -36)
  Tip(outline.thickness, "Thickness", TIPS.outlineSize)
  -- Hints to the RIGHT of their control, not under it: the row below is
  -- another control, and a hint sitting between two of them reads as if it
  -- belongs to the wrong one.
  outline.thicknessHint = Dim(oc, "match your nameplate addon's own border")
  outline.thicknessHint:SetPoint("TOPLEFT", 340, -38)

  outline.offsetLabel = Label(oc, "Position")
  outline.offsetLabel:SetPoint("TOPLEFT", 14, -66)
  TipLabel(outline.offsetLabel, "Position", TIPS.outlineOffset)
  -- Runs both ways from zero: "the bar's edge" means different things to
  -- different nameplate addons, so this has to be able to go outside it as
  -- well as in.
  outline.offset = Slider(oc, 150, -8, 8, 16,
    function() return NS.db.tints.plateOutlineOffset or 0 end,
    function(v) NS.db.tints.plateOutlineOffset = v; Structural() end)
  outline.offset:SetPoint("TOPLEFT", 130, -64)
  Tip(outline.offset, "Position", TIPS.outlineOffset)
  outline.offsetHint = Dim(oc, "+ inside the bar, - outside it")
  outline.offsetHint:SetPoint("TOPLEFT", 340, -66)

  outline.colorLabel = Label(oc, "Color")
  outline.colorLabel:SetPoint("TOPLEFT", 14, -94)
  TipLabel(outline.colorLabel, "Color", TIPS.outlineColor)
  outline.color = ColorSwatch(oc,
    function() return NS.db.tints.plateOutlineColor or { r = 0, g = 0, b = 0, a = 1 } end,
    function(r, g, b, a)
      NS.db.tints.plateOutlineColor = { r = r, g = g, b = b, a = a }
      Structural()
    end)
  outline.color:SetPoint("TOPLEFT", 130, -92)
  Tip(outline.color, "Color", TIPS.outlineColor)

  -- Which edges to draw. All four by default -- the point of the feature is
  -- putting the plate's own border back on top of your colors -- but a line
  -- under the bar alone is a common look, and there is no reason to spend a
  -- texture per plate on edges nobody wants.
  outline.sidesLabel = Label(oc, "Edges")
  outline.sidesLabel:SetPoint("TOPLEFT", 14, -122)
  TipLabel(outline.sidesLabel, "Edges", TIPS.outlineSides)

  outline.sides = {}
  local SIDE_ROW = { { "top", "Top" }, { "bottom", "Bottom" }, { "left", "Left" }, { "right", "Right" } }
  for index, entry in ipairs(SIDE_ROW) do
    local key = entry[1]
    local check = Checkbox(oc,
      -- Absent means on, so a profile made before this setting existed keeps
      -- all four rather than silently losing its border.
      function()
        local sides = NS.db.tints.plateOutlineSides
        return not sides or sides[key] ~= false
      end,
      function(value)
        NS.db.tints.plateOutlineSides = NS.db.tints.plateOutlineSides or {}
        NS.db.tints.plateOutlineSides[key] = value
        Structural()
      end)
    check:SetPoint("TOPLEFT", 130 + (index - 1) * 78, -120)
    Tip(check, entry[2], TIPS.outlineSides)
    local label = Label(oc, entry[2])
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    TipLabel(label, entry[2], TIPS.outlineSides)
    outline.sides[index] = check
  end

  ---------------------------------------------------------------------------
  -- Bar Edges, second section on the same page
  ---------------------------------------------------------------------------
  local eb = ob

  local edge = CollapsibleSection(eb, "colourEdge", "Bar Edges",
    "keep the tint clear of your nameplate's border")
  table.insert(eb.sections, edge)
  eb.edge = edge
  local ec = edge.content

  -- Warning first, then a gate. These controls exist for one narrow problem
  -- and make things worse for everyone else, so the section stays inert until
  -- the warning has actually been acknowledged.
  edge.caution = Label(ec, "ONLY ADJUST IF HAVING ISSUES WITH COLOR OVERLAPPING EXISTING BORDERS",
    "GameFontNormal")
  edge.caution:SetPoint("TOPLEFT", 14, -12)
  edge.caution:SetTextColor(1, 0.82, 0.1)

  edge.ack = Checkbox(ec,
    function() return NS.db.uiEdgeAcknowledged end,
    function(v) NS.db.uiEdgeAcknowledged = v; NS.Options_RebuildAll() end)
  edge.ack:SetPoint("TOPLEFT", 12, -34)
  edge.ackLabel = Label(ec, "I understand and want to continue")
  edge.ackLabel:SetPoint("LEFT", edge.ack, "RIGHT", 6, 0)

  edge.insetLabel = Label(ec, "Edge inset")
  edge.insetLabel:SetPoint("TOPLEFT", 14, -66)
  TipLabel(edge.insetLabel, "Edge inset", TIPS.edgeInset)
  -- Zero is the good-looking default rather than an extreme, so the slider
  -- runs both ways from it.
  edge.inset = Slider(ec, 150, -4, 7, 11,
    function() return NS.db.tints.edgeAdjust or 0 end,
    function(v) NS.db.tints.edgeAdjust = v; Restyle() end)
  edge.inset:SetPoint("TOPLEFT", 130, -66)
  Tip(edge.inset, "Edge inset", TIPS.edgeInset)
  edge.insetHint = Dim(ec, "0 covers the bar exactly. + pulls in off a border, - overhangs.")
  edge.insetHint:SetPoint("TOPLEFT", 14, -90)
  edge.insetNote = Dim(ec, "")
  edge.insetNote:SetPoint("TOPLEFT", 14, -110)

  -- Performance. One opt-in switch, because the saving is real but so is the
  -- risk of the check being wrong about an aura you actually apply.
  local perf = CollapsibleSection(ob, "globalPerf", "Performance",
    "what gets built on your nameplates")
  table.insert(ob.sections, perf)
  ob.perf = perf

  local pfc = perf.content
  perf.gate = Checkbox(pfc,
    function() return NS.db.tints.gateUnknownSpells and true or false end,
    function(v) NS.db.tints.gateUnknownSpells = v; Structural() end)
  perf.gate:SetPoint("TOPLEFT", 12, -12)
  Tip(perf.gate, "Skip rules for debuffs this character cannot apply", TIPS.perfGate)
  perf.gateLabel = Label(pfc, "Skip rules for debuffs this character cannot apply")
  perf.gateLabel:SetPoint("LEFT", perf.gate, "RIGHT", 6, 0)
  TipLabel(perf.gateLabel, "Skip rules for debuffs this character cannot apply", TIPS.perfGate)

  perf.gateHint = Dim(pfc,
    "For profiles shared between characters. A rule you cannot trigger is still "
    .. "built on every nameplate for nothing.")
  perf.gateHint:SetPoint("TOPLEFT", 14, -36)
  perf.gateHint:SetPoint("TOPRIGHT", -14, -36)
  perf.gateHint:SetJustifyH("LEFT")
  perf.gateHint:SetHeight(28)

  perf.gateWarn = Dim(pfc,
    "|cffffcc00Off by default.|r A rule is only skipped on positive evidence -- the "
    .. "Cooldown Manager does not list the aura AND no linked spell is in your spellbook. "
    .. "If a rule stops working after switching this on, switch it back off and report it.")
  perf.gateWarn:SetPoint("TOPLEFT", 14, -68)
  perf.gateWarn:SetPoint("TOPRIGHT", -14, -68)
  perf.gateWarn:SetJustifyH("LEFT")
  perf.gateWarn:SetHeight(42)

  -- A rig built during combat lockdown is suspected structurally incomplete
  -- and gets ONE chance to be discarded and rebuilt once combat allows it --
  -- see the comment at OnPlateAdded in Core.lua. Raising this trades a small
  -- bounded amount of leaked frames (secure frames cannot be destroyed) for
  -- a better shot at recovering a plate whose one repair attempt itself
  -- landed mid-lockdown, e.g. a brief regen flicker between two pulls.
  perf.repairLabel = Label(pfc, "Rig repair attempts")
  perf.repairLabel:SetPoint("TOPLEFT", 14, -122)
  TipLabel(perf.repairLabel, "Rig repair attempts", TIPS.maxRigRepairs)
  perf.repair = Slider(pfc, 150, 1, 5, 4,
    function() return NS.db.tints.maxRigRepairs or 1 end,
    function(v) NS.db.tints.maxRigRepairs = v end)
  perf.repair:SetPoint("TOPLEFT", 130, -122)
  Tip(perf.repair, "Rig repair attempts", TIPS.maxRigRepairs)
  perf.repairHint = Dim(pfc, "how many times a plate built mid-combat may be rebuilt once combat allows it")
  perf.repairHint:SetPoint("TOPLEFT", 14, -146)
  perf.repairHint:SetPoint("TOPRIGHT", -14, -146)
  perf.repairHint:SetJustifyH("LEFT")
  perf.repairHint:SetHeight(28)

  perf.repairWarn = Dim(pfc,
    "|cffffcc00Each extra attempt leaks the previous rebuild's frames -- WoW cannot destroy "
    .. "secure frames once created.|r 1 is the addon's original, conservative default. Raise "
    .. "this only if plates that appear mid-fight (long boss fights, chained M+ pulls) are "
    .. "staying uncolored for the rest of that fight; the leak is small and bounded per plate, "
    .. "but it accumulates over a long session.")
  perf.repairWarn:SetPoint("TOPLEFT", 14, -178)
  perf.repairWarn:SetPoint("TOPRIGHT", -14, -178)
  perf.repairWarn:SetJustifyH("LEFT")
  perf.repairWarn:SetHeight(56)

  globalPanels = { panel }
end

-- Pandemic Flash as its own module rather than a section: it has an on/off, a
-- colour and timing of its own, the same shape as Health or Border Coloring.
--
-- Only ever applies to single-debuff rules -- a flash region doubles a rule's
-- texture count and a combo cannot afford it.
local pandemicPanel

local function BuildPandemicTab()
  -- No "Enable Module" row in the head: the switch lives on this page's own
  -- entry in the rail now, the same place the other three modules keep theirs,
  -- so the module's state is visible without opening it.
  local panel = BuildTabFrame(tabPanels[PAGE_PANDEMIC])
  panel.RefreshPreview = function() PaintGlobalStage(panel.head.stage) end

  local body = panel.body
  body.sections = {}

  -- Driven by AuraButton:AddPandemicRegion -- the engine owns when the region
  -- is revealed, we only own how it looks.
  local pand = CollapsibleSection(body, "colourPandemic", "Pandemic Flash",
    "flash the bar as a debuff nears its refresh window")
  table.insert(body.sections, pand)
  body.pandemic = pand
  local pc = pand.content
  local function PandemicDB() return NS.db.tints.pandemic end

  -- No enable checkbox in here any more: the module toggle in the page head
  -- is the same setting, and two controls for one value is how you end up
  -- with a section that looks off while the module is on.
  pand.colorLabel = Label(pc, "Flash color")
  pand.colorLabel:SetPoint("TOPLEFT", 14, -12)
  TipLabel(pand.colorLabel, "Flash color", TIPS.pandemicColor)
  pand.color = ColorSwatch(pc,
    function() return PandemicDB().color or { r = 1, g = 1, b = 1, a = 0.45 } end,
    function(r, g, b, a)
      PandemicDB().color = { r = r, g = g, b = b, a = a }
      Restyle()
    end)
  pand.color:SetPoint("TOPLEFT", 130, -10)
  Tip(pand.color, "Flash color", TIPS.pandemicColor)

  pand.pulse = Checkbox(pc,
    function() return PandemicDB().pulse ~= false end,
    function(v) PandemicDB().pulse = v; Restyle() end)
  pand.pulse:SetPoint("TOPLEFT", 12, -38)
  Tip(pand.pulse, "Pulse", TIPS.pandemicPulse)
  pand.pulseLabel = Label(pc, "Pulse (uncheck for a steady wash)")
  pand.pulseLabel:SetPoint("LEFT", pand.pulse, "RIGHT", 6, 0)
  TipLabel(pand.pulseLabel, "Pulse", TIPS.pandemicPulse)

  pand.speedLabel = Label(pc, "Pulse speed")
  pand.speedLabel:SetPoint("TOPLEFT", 14, -66)
  TipLabel(pand.speedLabel, "Pulse speed", TIPS.pandemicSpeed)
  -- Seconds per half-cycle. Shown x100 because the slider is integer-stepped.
  pand.speed = Slider(pc, 150, 10, 100, 18,
    function() return math.floor((PandemicDB().pulseSpeed or 0.35) * 100 + 0.5) end,
    function(v) PandemicDB().pulseSpeed = v / 100; Restyle() end)
  pand.speed:SetPoint("TOPLEFT", 130, -66)
  Tip(pand.speed, "Pulse speed", TIPS.pandemicSpeed)
  pand.speedHint = Dim(pc, "hundredths of a second — lower is faster")
  pand.speedHint:SetPoint("TOPLEFT", 14, -90)

  pandemicPanel = panel
end

local function RebuildPandemicTab()
  if not pandemicPanel then return end
  local body = pandemicPanel.body
  local pand = body.pandemic
  if not pand then return end
  -- No head.enable to refresh any more -- the module switch is on this page's
  -- rail entry. Calling it here errored before LayoutSections ran, which is
  -- why the whole page came up blank rather than merely missing a tick box.
  pand.pulse:Refresh()
  pand.speed:Refresh()
  pand.color:Refresh()
  pand:Resize(108)
  LayoutSections(body, body.sections)
end

local function RebuildGlobalTabs()
  if not globalPanels then return end

  local ob = globalPanels[1].body
  if ob.outline then
    ob.outline.enable:Refresh()
    ob.outline.thickness:Refresh()
    ob.outline.offset:Refresh()
    ob.outline.color:Refresh()
    for _, check in ipairs(ob.outline.sides or {}) do check:Refresh() end
    ob.outline:Resize(152)
  end

  -- Both sections share this page now, so the layout pass runs once at the
  -- end. Doing it per section would place the first against a height the
  -- second has not been given yet.
  local eb = ob
  local edge = eb.edge
  if edge then
    edge.ack.Refresh()

    -- Greyed out AND non-interactive until acknowledged. Alpha alone would
    -- look disabled while still responding to clicks, which is worse than no
    -- gate at all.
    local unlocked = NS.db.uiEdgeAcknowledged and true or false
    edge.inset:SetAlpha(unlocked and 1 or 0.35)
    edge.inset:EnableMouse(unlocked)
    for _, child in ipairs({ edge.inset:GetChildren() }) do
      pcall(child.EnableMouse, child, unlocked)
    end
    edge.insetLabel:SetAlpha(unlocked and 1 or 0.35)
    edge.insetHint:SetAlpha(unlocked and 1 or 0.35)
    edge.insetNote:SetAlpha(unlocked and 1 or 0.35)

    edge.inset:Refresh()
    -- Spell out the pixels, since the slider shows an adjustment and the
    -- actual geometry is one more than that.
    local actual = NS.FillInset and NS.FillInset() or 1
    edge.insetNote:SetText(("Tint sits |cff55dd55%d|r pixel(s) inside the bar edge.%s")
      :format(actual, actual < 0 and " |cffffcc00(overhanging)|r" or ""))
    edge:Resize(136)
  end

  if ob.perf then
    ob.perf.gate:Refresh()
    ob.perf.repair:Refresh()
    ob.perf:Resize(250)
  end

  -- One layout pass at the end, after every section has been given its height.
  LayoutSections(ob, ob.sections)
end

-------------------------------------------------------------------------------
-- Rule editor — one rule, the whole pane
-------------------------------------------------------------------------------

-- Selecting a rule in the rail opens it here instead of expanding a row inside
-- a table, where everything competed for a few hundred pixels.
--
-- The appearance controls are the SAME BuildStylePanel the tables use -- it
-- already knows fills, textures, cover, gating and border shape, and reads
-- whatever expandedRule points at. Two instances, since isBorder is fixed at
-- construction.
local rulePanel

local function RuleEditorList()
  -- Which list the open rule belongs to. Identity, not a flag on the rule:
  -- nothing on a rule says which stack it came from.
  -- Which list, and which half. There is only one list now, so the question
  -- that remains is which half the editor should be showing: a rule whose bar
  -- is switched off is being edited for its border.
  for _, rule in ipairs(NS.db.tints.rules or {}) do
    if rule == expandedRule then
      return NS.db.tints.rules, rule.barEnabled == false
    end
  end
  return nil, false
end

local function BuildRuleEditor()
  local panel = BuildTabFrame(tabPanels[PAGE_RULE])
  local head = panel.head
  local body = panel.body
  -- Read by SelectTab: while this page is up, test mode paints only the rule
  -- being edited.
  panel.ruleFocus = true

  -- Expanding the preview arms it. On a rule's page the preview is on by
  -- default (EnsureRulePreview, called when the rule is opened), so a collapsed
  -- preview that stays dark when you expand it reads as broken -- you opened it
  -- precisely to look at the rule.
  panel.previewSection.onOpen = function(_, open)
    if not open then return end
    EnsureRulePreview()
    RefreshPreviews()
  end

  -- One toggle, not one per debuff. The colouring pages simulate a whole rule
  -- LIST and need each debuff separately to work out which wins; here exactly
  -- one rule is on screen and the only question is show it or not.
  head.simulate = Checkbox(head,
    function()
      local conditions = expandedRule and expandedRule.conditions or {}
      if #conditions == 0 then return false end
      for _, condition in ipairs(conditions) do
        if not preview.active[condition.spellID] then return false end
      end
      return true
    end,
    function(value)
      -- Ticking sets every debuff this rule needs, which is exactly what
      -- "show me this rule" means to the shared preview state.
      for _, condition in ipairs(expandedRule and expandedRule.conditions or {}) do
        preview.active[condition.spellID] = value or nil
      end
      RefreshPreviews()
    end)
  -- Never shown: this became the "Preview this Rule" button below. The widget
  -- survives purely as the piece that knows how to read and write the shared
  -- preview state, so the button does not duplicate that logic. Anchored
  -- anyway -- an unanchored frame has no valid rect.
  head.simulate:SetPoint("TOPLEFT", 0, 0)
  head.simulate:Hide()

  -- The same three-button column every other page has, so testing works the
  -- same way wherever you are. Preview sits under the two test buttons
  -- because it is the local one -- it changes this plate, they change your
  -- real nameplates.
  -- head.testButton and head.testAllButton come from BuildTabFrame now; this
  -- page only re-stacks the column to fit its own extra button in.
  head.previewRule = Button(head.testColumn, "", 150, function()
    -- Drives the same preview state the switch did: ticking sets every
    -- debuff this rule needs.
    local on = head.simulate:GetChecked()
    for _, condition in ipairs(expandedRule and expandedRule.conditions or {}) do
      preview.active[condition.spellID] = (not on) or nil
    end
    RefreshPreviews()
  end)
  Tip(head.previewRule, "Preview this Rule", TIPS.previewRule)
  head.previewRule.Refresh = function()
    local on = head.simulate:GetChecked()
    head.previewRule:SetText(on and "Stop Previewing" or "Preview this Rule")
    if on then
      head.previewRule.label:SetTextColor(1, 0.82, 0.1)
    else
      head.previewRule.label:SetTextColor(1, 1, 1)
    end
  end
  StackTestButtons(head.testColumn, { head.threatPreview, head.markPreview,
    head.previewRule, head.testButton, head.testAllButton })

  head.verdict = Label(head, "")
  head.verdict:SetPoint("TOPLEFT", HEAD_PAD, -(6 + STAGE_H + 8))

  -- ONE banner for the whole rule: the rule's name is the header, and its
  -- switch and delete control ride on that header rather than sitting above
  -- it. Inside, the three groups are plain headings, not nested banners -- a
  -- card inside a card inside a scrolling page is one box too many, and the
  -- inner headers were competing with the one that actually names the rule.
  body.sections = {}
  local card = CollapsibleSection(body, "ruleCard", "", "-")
  table.insert(body.sections, card)
  body.card = card
  local cc = card.content
  StyleText(card.title, 14)

  -- Confirmed, because there is no undo -- the same guard the rule table's X
  -- has. A rule carries up to two debuffs, a colour, a fill texture and a
  -- border, and one stray click would take all of it.
  card.delete = CloseX(card.header, function()
    local rule = expandedRule
    if not rule then return end
    ShowConfirm(
      "Delete this rule?",
      ("|cffffcc00%s|r will be removed. This cannot be undone."):format(RuleLabel(rule)),
      "Delete",
      function()
        local list = RuleEditorList()
        if not list then return end
        for index, candidate in ipairs(list) do
          if candidate == rule then
            table.remove(list, index)
            break
          end
        end
        expandedRule = nil
        SelectTab(PAGE_HEALTH)
        Structural()
      end)
  end)
  card.delete:SetPoint("RIGHT", -8, 0)
  Tip(card.delete, "Delete rule", TIPS.ruleDelete)
  -- Above the header's own click target, which spans the full width. A child
  -- at the SAME frame level loses the hit test to it, so the delete and the
  -- switch would collapse the section instead of doing their own jobs.
  card.delete:SetFrameLevel(card.header:GetFrameLevel() + 2)

  -- A switch here, where the rule IS the subject, rather than the tick box it
  -- keeps in the table. The rail's rule entries carry switches for the same
  -- reason: this is the rule's power control, not one of its settings.
  card.enable = ToggleSwitch(card.header,
    function() return expandedRule and expandedRule.enabled ~= false end,
    function(v) if expandedRule then expandedRule.enabled = v; Structural() end end)
  card.enable:SetFrameLevel(card.header:GetFrameLevel() + 2)
  card.enableLabel = Label(card.header, "Enabled")
  card.enableLabel:SetPoint("RIGHT", card.delete, "LEFT", -12, 0)
  card.enable:SetPoint("RIGHT", card.enableLabel, "LEFT", -8, 0)
  Tip(card.enable, "Enabled", TIPS.ruleEnabled)

  -- Group headings inside the one card. Same treatment the style panel used
  -- for its own two halves, so a heading looks like a heading wherever it is.
  local function GroupHeading(text)
    local heading = Label(cc, text, "GameFontNormal")
    StyleText(heading, 11)
    heading:SetTextColor(RGBA(THEME.headerText))
    return heading
  end
  local function GroupRule()
    local line = cc:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(0.35, 0.35, 0.40, 0.5)
    return line
  end

  body.condHeading = GroupHeading("Requires these debuffs")
  body.visHeading = GroupHeading("Visibility")
  body.visDivider = GroupRule()
  body.appearHeading = GroupHeading("Appearance")
  body.appearDivider = GroupRule()

  body.condRows = {}
  -- isTracked is a PREDICATE the dropdown calls per entry, to mark the ones
  -- this rule already uses -- not a boolean flag.
  body.condDrop = AddSpellDropdown(cc, 260, "Add a debuff to this rule...",
    function(spellID)
      for _, condition in ipairs(expandedRule and expandedRule.conditions or {}) do
        if condition.spellID == spellID then return true end
      end
      return false
    end,
    function(spellID)
      local list = RuleEditorList()
      AddConditionTo(expandedRule, spellID, list)
      body.addOpen = false
      return true
    end)

  body.idBox = IDBox(cc, function(text)
    local list = RuleEditorList()
    AddConditionTo(expandedRule, text, list)
    body.addOpen = false
  end, 110)

  -- The add controls are put away until asked for. A dropdown and a text
  -- field sitting open under a finished rule made the rule look unfinished --
  -- every rule permanently showing the machinery for changing it.
  body.addOpen = false
  body.addToggle = Tip(Button(cc, "Add debuff", 110, function()
    body.addOpen = not body.addOpen
    NS.Options_RebuildAll()
  end), "Add debuff", TIPS.addDebuff)

  -- Appearance and visibility are two questions -- what this rule paints, and
  -- which plates it is allowed to paint it on. Both are the tables' own
  -- BuildStylePanel, asked for one half each, so the split is in the layout
  -- rather than in a second copy of the controls.
  body.styleHealth = BuildStylePanel(cc, false, "appearance")
  body.styleBorder = BuildStylePanel(cc, true, "appearance")

  -- One panel, not one per list: target/focus gating is the same two fields on
  -- a health rule and a border rule.
  body.visPanel = BuildStylePanel(cc, false, "visibility")

  panel.RefreshPreview = function()
    if not expandedRule then return end
    local stage = head.stage
    local spells = {}
    for _, condition in ipairs(expandedRule.conditions or {}) do
      table.insert(spells, condition.spellID)
    end

    -- One switch for the whole rule (see head.simulate) rather than a row of
    -- per-debuff boxes.
    head.simulate.Refresh()
    head.previewRule.Refresh()
    head.previewRule:SetShown(#spells > 0)
    if head.testButton then head.testButton.Refresh() end
    if head.testAllButton then head.testAllButton.Refresh() end

    -- Only this rule is simulated here, so the verdict is simply whether all
    -- of its debuffs are ticked -- no priority walk, because the rule being
    -- edited is the only one on screen.
    local active = PrunedPreviewState()
    local matches = #spells > 0
    for _, spellID in ipairs(spells) do
      if not active[spellID] then matches = false break end
    end

    local _, isBorder = RuleEditorList()
    local isMissing = expandedRule and expandedRule.showWhenMissing

    -- Only on a missing rule's own page, and only for THIS rule. Showing the
    -- whole ladder meant a higher-ranked rule washed over the one you opened,
    -- and showing it elsewhere meant one missing rule covered every preview in
    -- the window. The stage is shared with the border editor, which is why
    -- this is gated here rather than at the stage.
    --
    -- Bar rules only: a missing BORDER has no wash, just edges that leave.
    if isMissing and not isBorder and not matches
      and expandedRule.barEnabled ~= false then
      NS.ApplyRuleFill(stage.missingWash, stage.bar, expandedRule)
      stage.missingWash:Show()
    else
      stage.missingWash:Hide()
    end

    if isMissing and isBorder then
      -- Inverted against the presence case below: the border is what you see
      -- while the debuff is ABSENT, and it leaves once the debuff lands.
      head.verdict:SetText(#spells == 0
        and "|cff808080Add a debuff below to preview this rule.|r"
        or (matches
          and "|cff808080Debuff applied — the border disappears.|r"
          or "|cffffcc22Debuff missing — the border shows in this rule's color.|r"))
      stage.tint:Hide()
      stage.missingCover:Hide()
      DrawStageBorder(stage, (not matches) and expandedRule or nil)
    elseif isMissing then
      -- A missing rule draws no border and no presence tint. Its whole preview
      -- is the wash above, which the simulate switch drives on its own -- so
      -- there is nothing left to do here except say which state you are
      -- looking at, since "lit" and "satisfied" are both correct results and a
      -- blank bar would otherwise read as a broken preview.
      head.verdict:SetText(#spells == 0
        and "|cff808080Add a debuff below to preview this rule.|r"
        or (matches
          and "|cff808080Debuff applied — the bar goes back to normal.|r"
          or "|cffffcc22Debuff missing — the bar is washed in this rule's color.|r"))
      stage.tint:Hide()
      stage.missingCover:Hide()
      DrawStageBorder(stage, nil)
    elseif matches then
      head.verdict:SetText("")
      if isBorder then
        stage.tint:Hide()
        stage.missingCover:Hide()
        -- The same routine both colouring tabs use, so a border cannot look
        -- one way here and another there.
        DrawStageBorder(stage, expandedRule)
      else
        DrawStageBorder(stage, nil)
        NS.ApplyRuleFill(stage.tint, stage.bar, expandedRule)
        stage.tint:Show()
        NS.ApplyMissingCover(stage.missingCover, stage.bar, expandedRule)
      end
    else
      head.verdict:SetText(#spells == 0
        and "|cff808080Add a debuff below to preview this rule.|r"
        or "")
      stage.tint:Hide()
      stage.missingCover:Hide()
      DrawStageBorder(stage, nil)
    end

    -- Grow the fixed head to cover the verdict -- but only when there IS one.
    -- The verdict is empty whenever the rule matches, which is the normal
    -- state on this page, so reserving its line unconditionally left a band of
    -- empty card under the stage every time the preview was working.
    local hasVerdict = (head.verdict:GetText() or "") ~= ""
    panel:SetHeadHeight(6 + STAGE_H + (hasVerdict and 30 or 8))
  end

  rulePanel = panel
end

local function RebuildRuleEditor()
  if not rulePanel or not expandedRule then return end
  local body = rulePanel.body
  local list, isBorder = RuleEditorList()

  local card = body.card
  card.title:SetText(RuleLabel(expandedRule))
  local position, total = 0, 0
  if list then
    total = #list
    for index, rule in ipairs(list) do
      if rule == expandedRule then position = index break end
    end
  end
  card.subtitle:SetText(("%s rule - priority %d of %d"):format(
    isBorder and "Border" or "Health", position, total))
  card.enable:Refresh()

  -- Conditions
  local cc = card.content
  local y = -10
  body.condHeading:ClearAllPoints()
  body.condHeading:SetPoint("TOPLEFT", 14, y)
  y = y - 22
  -- The line the FIRST debuff occupies, remembered so the Add button can sit
  -- on it (see below) instead of taking a line of its own.
  local condTop = y
  for _, row in ipairs(body.condRows) do row:Hide() end
  for index, condition in ipairs(expandedRule.conditions or {}) do
    local row = body.condRows[index]
    if not row then
      -- Its own row rather than BuildConditionRow: that one is laid out for
      -- the rule TABLE, with its icon 144px in to clear the priority and
      -- colour columns. There are no columns here, so those offsets would
      -- read as a huge unexplained indent.
      row = CreateFrame("Frame", nil, cc)
      row:SetHeight(24)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(18, 18)
      row.icon:SetPoint("LEFT", 14, 0)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.name = Label(row, "")
      row.name:SetPoint("LEFT", 38, 0)
      row.remove = CloseX(row, function()
        if not row.rule then return end
        table.remove(row.rule.conditions, row.conditionIndex)
        local list = RuleEditorList()
        NS.SortRules(list)
        Structural()
      end)
      row.remove:SetPoint("LEFT", 340, 0)
      body.condRows[index] = row
    end
    row.rule = expandedRule
    row.conditionIndex = index
    row.icon:SetTexture(NS.SpellIcon(condition.spellID))
    row.name:SetText(("%s  |cff808080%d|r"):format(
      NS.SpellName(condition.spellID) or "?", condition.spellID))
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 12, y)
    row:SetPoint("TOPRIGHT", -12, y)
    row:Show()
    y = y - 26
  end

  -- At the limit there is nothing to add, so the controls and the button that
  -- reveals them both go -- which states the maximum without a caption.
  local full = #(expandedRule.conditions or {}) >= RuleConditionLimit(expandedRule)
  if full then body.addOpen = false end

  body.addToggle:SetShown(not full)
  body.condDrop:SetShown(not full and body.addOpen)
  body.idBox:SetShown(not full and body.addOpen)

  if not full then
    -- Inline with the first debuff, right-aligned, rather than on its own row:
    -- a rule has one or two debuffs, so a dedicated row spent a third of this
    -- block's height on a control that is idle most of the time, and pushed
    -- appearance and visibility below the fold.
    --
    -- Right-aligned so it clears the remove X whatever the debuff is called.
    body.addToggle:SetText(body.addOpen and "Done" or "Add debuff")
    body.addToggle:ClearAllPoints()
    body.addToggle:SetPoint("TOPRIGHT", -12, condTop - 2)

    -- With no debuffs yet there is no row beside it, so the line it sits on
    -- has to be reserved here -- otherwise the pickers below would open on
    -- top of it.
    if #(expandedRule.conditions or {}) == 0 then y = y - 26 end

    -- Pickers under the list when open. The button stays put and becomes
    -- Done: it closes what is below it, and moving it would make the row it
    -- is aligned with jump every time you opened the picker.
    if body.addOpen then
      body.condDrop:ClearAllPoints()
      body.condDrop:SetPoint("TOPLEFT", 12, y - 4)
      body.condDrop.Refresh()
      body.idBox:ClearAllPoints()
      body.idBox:SetPoint("TOPLEFT", 282, y - 4)
      y = y - 30
    end
  end

  -- Visibility. Ahead of appearance because it is the shorter, plainer
  -- question -- two tick boxes -- and burying it under the fill and texture
  -- controls is what made it easy to miss.
  y = y - 10
  body.visDivider:ClearAllPoints()
  body.visDivider:SetPoint("TOPLEFT", 14, y)
  body.visDivider:SetPoint("TOPRIGHT", -14, y)
  y = y - 12
  body.visHeading:ClearAllPoints()
  body.visHeading:SetPoint("TOPLEFT", 14, y)
  y = y - 22

  body.visPanel:ClearAllPoints()
  body.visPanel:SetPoint("TOPLEFT", 8, y)
  body.visPanel.Refresh()
  y = y - body.visPanel:GetHeight()

  -- Appearance
  y = y - 10
  body.appearDivider:ClearAllPoints()
  body.appearDivider:SetPoint("TOPLEFT", 14, y)
  body.appearDivider:SetPoint("TOPRIGHT", -14, y)
  y = y - 12
  body.appearHeading:ClearAllPoints()
  body.appearHeading:SetPoint("TOPLEFT", 14, y)
  y = y - 22

  local style = isBorder and body.styleBorder or body.styleHealth
  local other = isBorder and body.styleHealth or body.styleBorder
  other:Hide()
  style:ClearAllPoints()
  style:SetPoint("TOPLEFT", 8, y)
  style:Show()
  style.Refresh()
  y = y - style:GetHeight()

  card:Resize(-y + 8)
  LayoutSections(body, body.sections)
end

-------------------------------------------------------------------------------
-- Diagnostics
-------------------------------------------------------------------------------

-- The same facts /pt status prints, on a page instead of in chat -- which
-- scrolls away, cannot be selected, and is the first thing asked for in a bug
-- report. Numbers come from NS.CollectDiagnostics, shared with the command.
local function DiagStat(parent, label)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(150, 44)
  -- Frames take no mouse input by default, so without this the stat boxes
  -- could never answer a hover.
  box:EnableMouse(true)
  box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  PixelBorder(box)
  box:SetBackdropColor(RGBA(THEME.tabBG))
  box:SetBackdropBorderColor(RGBA(THEME.tabBorder))

  box.key = Dim(box, label)
  box.key:SetPoint("TOPLEFT", 8, -6)
  box.value = Label(box, "-", "GameFontNormal")
  box.value:SetPoint("TOPLEFT", 8, -20)
  StyleText(box.value, 16)
  return box
end

-------------------------------------------------------------------------------
-- Optional Tweaks
-------------------------------------------------------------------------------

-- No preview stage: nothing here draws on a nameplate, so BuildTabFrame's
-- simulated plate would be showing something these settings cannot change.
-- A plain scrolling body instead.
local tweaksPanel

local function BuildTweaksTab()
  local panel = tabPanels[PAGE_TWEAKS]

  local title = Label(panel, "Tooltip IDs", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  StyleText(title, 15)
  title:SetTextColor(RGBA(THEME.headerText))

  panel.subtitle = Dim(panel,
    "Adds the numeric ID to game tooltips. Switched on from its entry in the rail.")
  panel.subtitle:SetPoint("TOPLEFT", 10, -28)

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", 4, -50)
  body:SetPoint("BOTTOMRIGHT", -4, 4)
  body.sections = {}
  panel.body = body

  local lines = CollapsibleSection(body, "tweakTooltipLines", "Which tooltips",
    "each line type can be turned off on its own")
  table.insert(body.sections, lines)
  body.lines = lines
  local lc = lines.content

  -- One row per tooltip type. Ordered by how often they matter here: aura
  -- first, because reading an aura's real ID is the reason this tweak is worth
  -- shipping at all.
  local rows = {
    { field = "tooltipAura",  label = "Auras (buffs and debuffs)", tip = "tipAura" },
    { field = "tooltipSpell", label = "Spells and abilities",      tip = "tipSpell" },
    { field = "tooltipItem",  label = "Items",                     tip = "tipItem" },
    { field = "tooltipUnit",  label = "Units (creature ID)",       tip = "tipUnit" },
  }
  lines.rows = {}
  for index, row in ipairs(rows) do
    local field = row.field
    local check = Checkbox(lc,
      -- Absent means on, so switching the tweak on shows everything until you
      -- narrow it. Matches how Tweaks.lua reads the same fields.
      function() return NS.db.tweaks and NS.db.tweaks[field] ~= false end,
      function(value)
        NS.db.tweaks = NS.db.tweaks or {}
        NS.db.tweaks[field] = value
        -- Nothing to apply -- the value is already stored and the tooltip
        -- handlers read it on their next call. This is here for the footer's
        -- "Settings Saved", which would otherwise sit on "Pending..." from
        -- whatever was changed before.
        ScheduleApply()
      end)
    check:SetPoint("TOPLEFT", 12, -10 - (index - 1) * 26)
    local label = Label(lc, row.label)
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    Tip(check, row.label, TIPS[row.tip])
    TipLabel(label, row.label, TIPS[row.tip])
    lines.rows[index] = check
  end

  lines.note = Dim(lc,
    "Useful when building a rule: the aura an ability applies often has a different ID from the ability itself.")
  lines.note:SetPoint("TOPLEFT", 14, -10 - #rows * 26 - 6)

  tweaksPanel = panel
end

local function RebuildTweaksTab()
  local panel = tweaksPanel
  if not panel then return end
  local lines = panel.body.lines
  if not lines then return end
  for _, check in ipairs(lines.rows) do check:Refresh() end
  lines:Resize(10 + #lines.rows * 26 + 24)
  LayoutSections(panel.body, panel.body.sections)
end

-- Import / Export
--
-- Two halves that never touch: the top turns a profile into a string, the
-- bottom turns a string into a profile.
--
-- Import is three presses on purpose -- paste, Check, Import. Check only
-- DECODES, so the summary is on screen before anything is written.
-- NS.CommitShare is the only call here that writes.
--
-- Everything lives on the `share` table, not in locals -- see the note there:
--
--   share.tab      the panel
--   share.pending  decoded payload awaiting commit, or nil. Cleared whenever
--                  the box changes, so Import can never write a payload
--                  belonging to a string since edited away.
--   share.Rebuild  reachable from the builder, because this page's Check
--                  button calls its own rebuild.

-- A read-only multiline box in a scroll frame. Same reason as the Diagnostics
-- report: WoW gives an addon no way to write the clipboard, so handing someone
-- text means giving them something they can select and Ctrl+C themselves.
function share.Box(parent, height, readOnly, onChanged)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetHeight(height)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("GameFontHighlightSmall")
  edit:SetWidth(600)
  StyleText(edit, 11)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if readOnly then
    -- Not disabled: a disabled box cannot be selected, and selecting is the
    -- entire point. Re-highlighting on any keypress makes it read-only in the
    -- only way that matters -- the text cannot be edited into something that
    -- no longer decodes.
    edit:SetScript("OnTextChanged", function(self, user)
      if user then self:SetText(self.value or "") end
    end)
  elseif onChanged then
    edit:SetScript("OnTextChanged", function(self, user)
      if user then onChanged() end
    end)
  end
  scroll:SetScrollChild(edit)
  scroll.edit = edit
  return scroll
end

function share.Build()
  local panel = tabPanels[share.PAGE]
  share.tab = panel

  local title = Label(panel, "Import / Export", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  StyleText(title, 15)
  title:SetTextColor(RGBA(THEME.headerText))

  panel.subtitle = Dim(panel,
    "Settings are saved per account, so a text string is the only way a profile reaches another one.")
  panel.subtitle:SetPoint("TOPLEFT", 10, -28)

  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", 4, -50)
  scroll:SetPoint("TOPRIGHT", -12, -50)
  scroll:SetPoint("BOTTOMLEFT", 4, 4)

  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(716, 700)
  scroll:SetScrollChild(body)
  body.scrollBar = BuildScrollBar(scroll)
  panel.body = body
  body.sections = {}

  -----------------------------------------------------------------------------
  -- Export
  -----------------------------------------------------------------------------
  local out = CollapsibleSection(body, "shareOut", "Export",
    "turn a profile into a string you can send")
  table.insert(body.sections, out)
  body.out = out
  local oc = out.content

  out.whichLabel = Label(oc, "Profile")
  out.whichLabel:SetPoint("TOPLEFT", 14, -12)
  TipLabel(out.whichLabel, "Profile", TIPS.shareWhich)

  -- nil means "whatever is live", so the page follows a spec swap instead of
  -- pinning whichever profile happened to be current when it was built.
  out.selected = nil
  out.drop = Dropdown(oc, 220, function() return ProfileEntries(false) end,
    function() return out.selected or NS.ProfileKey() end,
    function(name)
      out.selected = name
      if out.Generate then out.Generate() end
    end)
  out.drop:SetPoint("TOPLEFT", 130, -10)
  Tip(out.drop, "Profile", TIPS.shareWhich)

  out.box = share.Box(oc, 78, true)
  out.box:SetPoint("TOPLEFT", 14, -44)
  out.box:SetPoint("TOPRIGHT", -34, -44)

  out.status = Dim(oc, "")
  out.status:SetPoint("TOPLEFT", 14, -130)
  out.status:SetPoint("TOPRIGHT", -20, -130)
  out.status:SetJustifyH("LEFT")

  out.copy = Button(oc, "Select All for Copy", 150, function()
    local edit = out.box.edit
    if not edit.value or edit.value == "" then return end
    edit:SetFocus()
    edit:HighlightText()
    out.status:SetText("Selected - press |cff55dd55Ctrl+C|r to copy.")
  end)
  out.copy:SetPoint("TOPLEFT", 14, -152)
  Tip(out.copy, "Select All for Copy", TIPS.shareCopy)

  out.Generate = function()
    local name = out.selected or NS.ProfileKey()
    local text, note = NS.ExportProfile(name)
    local edit = out.box.edit
    if not text then
      edit.value = ""
      edit:SetText("")
      out.status:SetText("|cffff4040" .. tostring(note or "Export failed.") .. "|r")
      return
    end
    edit.value = text
    edit:SetText(text)
    edit:ClearFocus()
    -- The length is the honest progress indicator here: a profile with forty
    -- rules produces a visibly longer string than one with two, and someone
    -- who exported the wrong profile usually spots it by size first.
    local summary = ("|cff55dd55%s|r - %d characters."):format(name, #text)
    out.status:SetText(note and (summary .. " |cffffcc00" .. note .. "|r") or summary)
  end

  out.regen = Button(oc, "Generate", 90, function() out.Generate() end)
  out.regen:SetPoint("TOPLEFT", 360, -10)
  Tip(out.regen, "Generate", TIPS.shareExport)

  -----------------------------------------------------------------------------
  -- Import
  -----------------------------------------------------------------------------
  local inc = CollapsibleSection(body, "shareIn", "Import",
    "paste a string someone sent you")
  table.insert(body.sections, inc)
  body.inc = inc
  local ic = inc.content

  local function ClearPending()
    share.pending = nil
    inc.preview:SetText("")
    inc.commit:Hide()
    inc.nameBox:Hide()
    inc.nameLabel:Hide()
    share.Rebuild()
  end

  inc.box = share.Box(ic, 64, false, function()
    -- Editing after a Check invalidates what Check found.
    if share.pending then ClearPending() end
  end)
  inc.box:SetPoint("TOPLEFT", 14, -12)
  inc.box:SetPoint("TOPRIGHT", -34, -12)

  -- Rows below the box, in order: the two buttons, then the status line, then
  -- the summary. The name row is placed by the rebuild instead, because it has
  -- to clear a summary whose height depends on the string.
  local BUTTON_Y  = -88
  local STATUS_Y  = -116
  local PREVIEW_Y = -138

  inc.status = Dim(ic, "")
  inc.status:SetPoint("TOPLEFT", 14, STATUS_Y)
  inc.status:SetPoint("TOPRIGHT", -20, STATUS_Y)
  inc.status:SetJustifyH("LEFT")

  inc.preview = Label(ic, "")
  inc.preview:SetPoint("TOPLEFT", 14, PREVIEW_Y)
  inc.preview:SetPoint("TOPRIGHT", -20, PREVIEW_Y)
  inc.preview:SetJustifyH("LEFT")
  inc.preview:SetJustifyV("TOP")
  inc.previewY = PREVIEW_Y
  TipLabel(inc.preview, "What is in the string", TIPS.shareUnusable)

  inc.nameLabel = Label(ic, "Import as")
  inc.nameLabel:Hide()
  TipLabel(inc.nameLabel, "Import as", TIPS.shareName)

  inc.nameBox = CreateFrame("EditBox", nil, ic, "InputBoxTemplate")
  inc.nameBox:SetSize(220, 22)
  inc.nameBox:SetAutoFocus(false)
  StyleText(inc.nameBox, 12)
  inc.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  inc.nameBox:Hide()
  Tip(inc.nameBox, "Import as", TIPS.shareName)

  local function DoImport()
    if not share.pending then return end
    local name = strtrim(inc.nameBox:GetText() or "")
    if name == "" then
      inc.status:SetText("|cffff4040Give the profile a name.|r")
      return
    end

    local function Commit(overwrite)
      local ok, err = NS.CommitShare(share.pending, name, overwrite)
      if not ok then
        inc.status:SetText("|cffff4040" .. tostring(err) .. "|r")
        return
      end
      inc.box.edit:SetText("")
      ClearPending()
      inc.status:SetText(("Imported as |cff55dd55%s|r and switched to it."):format(name))
      NS.Options_RebuildAll()
    end

    if NS.ProfileExists(name) then
      ShowConfirm("Replace profile",
        ("|cffff4040%s|r already exists.\n\nReplacing it discards everything in it. Every character and spec pointing at it gets the imported settings instead.")
          :format(name),
        "Replace", function() Commit(true) end)
      return
    end
    Commit(false)
  end

  inc.commit = Button(ic, "Import", 90, DoImport)
  inc.commit:Hide()
  Tip(inc.commit, "Import", TIPS.shareCommit)
  inc.nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); DoImport() end)

  inc.check = Button(ic, "Check String", 110, function()
    local payload, err = NS.DecodeShareString(inc.box.edit:GetText())
    if not payload then
      share.pending = nil
      inc.status:SetText("|cffff4040" .. tostring(err) .. "|r")
      inc.preview:SetText("")
      inc.commit:Hide()
      inc.nameBox:Hide()
      inc.nameLabel:Hide()
      share.Rebuild()
      return
    end
    share.pending = payload
    inc.status:SetText("")

    -- A name that already exists is legal (it prompts on Import), so this only
    -- has to be a sensible starting point, not a unique one.
    inc.nameBox:SetText(payload.name or "Imported")
    inc.nameBox:Show()
    inc.nameLabel:Show()
    inc.commit:Show()
    share.Rebuild()
  end)
  inc.check:SetPoint("TOPLEFT", 14, BUTTON_Y)
  Tip(inc.check, "Check String", TIPS.shareCheck)

  inc.clear = Button(ic, "Clear", 70, function()
    inc.box.edit:SetText("")
    inc.status:SetText("")
    ClearPending()
  end)
  inc.clear:SetPoint("TOPLEFT", 130, BUTTON_Y)

  -- Generated on open rather than on a button alone: the string is a snapshot,
  -- and the most likely reason to be on this page is to copy the profile as it
  -- stands right now. Pressing Generate again after an edit is still the way to
  -- refresh it -- this only means the box is never empty on arrival.
  panel.OnSelect = function()
    if not NS.ShareAvailable() then
      -- Said once, plainly, instead of letting every button fail its own way.
      out.status:SetText("|cffff4040This client does not provide C_EncodingUtil. Sharing is unavailable.|r")
      out.regen:Hide()
      out.copy:Hide()
      inc.check:Hide()
      inc.clear:Hide()
      return
    end
    out.Generate()
  end
end

-- Builds the summary text for a decoded payload. Kept out of the button so the
-- rebuild can redraw it without re-decoding -- CanApplyAura's answer changes
-- with the character's spec, and a summary left on screen across a spec swap
-- would otherwise still be flagging rules that are now fine.
function share.Summary(info)
  if not info then return "" end
  local lines = {}

  local head = ("|cff55dd55%s|r"):format(info.name or "Imported")
  if info.addon then head = head .. ("  |cff808080(made with %s)|r"):format(info.addon) end
  table.insert(lines, head)

  local counts = {}
  if #info.rules > 0 then table.insert(counts, ("%d health rule(s)"):format(#info.rules)) end
  if #info.borderRules > 0 then table.insert(counts, ("%d border rule(s)"):format(#info.borderRules)) end
  if info.icons > 0 then table.insert(counts, ("%d aura icon(s)"):format(info.icons)) end
  if #counts == 0 then
    table.insert(lines, "|cffffcc00No rules and no icons -- this profile is empty.|r")
  else
    table.insert(lines, table.concat(counts, ", "))
  end

  local on = {}
  if info.modules.health then table.insert(on, "Health") end
  if info.modules.border then table.insert(on, "Border") end
  if info.modules.icons then table.insert(on, "Aura Icons") end
  table.insert(lines, "Modules on: " .. (#on > 0 and table.concat(on, ", ") or "none"))

  -- The rules themselves, with their icons, so what is being imported is
  -- recognisable rather than a count to be taken on trust.
  local shown = 0
  for _, list in ipairs({ info.rules, info.borderRules }) do
    for _, entry in ipairs(list) do
      if shown >= 12 then break end
      shown = shown + 1
      local mark = entry.unusable > 0 and "|cffff8800!|r " or "  "
      local kind = entry.missing and " |cff808080(missing)|r" or ""
      table.insert(lines, mark .. entry.summary .. kind)
    end
  end
  local total = #info.rules + #info.borderRules
  if total > shown then
    table.insert(lines, ("  |cff808080...and %d more|r"):format(total - shown))
  end

  if info.unusable > 0 then
    table.insert(lines, ("|cffff8800%d rule(s) marked ! name a debuff this character cannot apply.|r")
      :format(info.unusable))
    table.insert(lines, "|cff808080They import intact and work on a character that can. Nothing is lost.|r")
  end
  if info.dropped and info.dropped.rules and info.dropped.rules > 0 then
    table.insert(lines, ("|cffff8800%d rule(s) in the string were unreadable and will be skipped.|r")
      :format(info.dropped.rules))
  end

  return table.concat(lines, "\n")
end

function share.Rebuild()
  local panel = share.tab
  if not panel then return end
  local body = panel.body
  local out, inc = body.out, body.inc
  if not out or not inc then return end

  out.drop:Refresh()
  out:Resize(186)

  local info = share.pending and NS.DescribeShare(share.pending) or nil
  inc.preview:SetText(share.Summary(info))

  -- The name box and Import button sit BELOW the summary, whose height depends
  -- on how many rules the string carried. Re-anchored after the text is set so
  -- they follow it, rather than being placed once at a fixed offset that a
  -- twelve-rule preview would run straight through.
  local previewH = info and (math.ceil(inc.preview:GetStringHeight()) + 12) or 0
  local rowY = inc.previewY - previewH

  inc.nameLabel:ClearAllPoints()
  inc.nameLabel:SetPoint("TOPLEFT", 14, rowY - 6)
  inc.nameBox:ClearAllPoints()
  inc.nameBox:SetPoint("TOPLEFT", 100, rowY - 4)
  inc.commit:ClearAllPoints()
  inc.commit:SetPoint("TOPLEFT", 330, rowY - 4)

  -- rowY is negative; the section height is the distance down to the name row
  -- plus room for the row itself.
  inc:Resize(info and (-rowY + 44) or (-inc.previewY + 8))
  LayoutSections(body, body.sections)
end

local function BuildDiagnosticsTab()
  local panel = tabPanels[PAGE_DIAG]

  local title = Label(panel, "Diagnostics", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  StyleText(title, 15)
  title:SetTextColor(RGBA(THEME.headerText))

  panel.subtitle = Dim(panel,
    "What the addon has actually built on the nameplates in front of you. Include this in any bug report.")
  panel.subtitle:SetPoint("TOPLEFT", 10, -28)

  panel.refresh = Button(panel, "Refresh", 90, function()
    -- The explicit way back to the live summary after loading a capture.
    panel.showingCapture = nil
    if panel.Render then panel.Render() end
    if panel.savedPick and panel.savedPick.Refresh then panel.savedPick.Refresh() end
  end)
  panel.refresh:SetPoint("TOPRIGHT", -10, -8)
  Tip(panel.refresh, "Refresh", TIPS.diagRefresh)

  panel.state = Label(panel, "")
  panel.state:SetPoint("TOPRIGHT", -110, -10)
  panel.state:SetJustifyH("RIGHT")

  panel.stats = {
    plates  = Tip(DiagStat(panel, "PLATES"), "Plates", TIPS.diagPlates),
    rigged  = Tip(DiagStat(panel, "RIGGED"), "Rigged", TIPS.diagRigged),
    nobar   = Tip(DiagStat(panel, "NO HEALTH BAR"), "No health bar", TIPS.diagNobar),
    skipped = Tip(DiagStat(panel, "FRIENDLY SKIPPED"), "Friendly skipped", TIPS.diagSkipped),
    -- Plates whose hostility no API would answer. They are deferred, not
    -- rigged, so a number that stays above zero is the one to report.
    unknown = Tip(DiagStat(panel, "HOSTILITY UNKNOWN"), "Hostility unknown", TIPS.diagUnknown),
  }
  local order = { "plates", "rigged", "nobar", "skipped", "unknown" }
  for index, key in ipairs(order) do
    panel.stats[key]:SetPoint("TOPLEFT", 10 + (index - 1) * 140, -52)
    panel.stats[key]:SetWidth(132)
  end

  -- A read-only multiline edit box, not a font string. WoW gives an addon no
  -- way to write the clipboard, so the only way to hand someone text they can
  -- paste into a bug report is to put it somewhere they can select it and
  -- press Ctrl+C themselves.
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -108)
  scroll:SetPoint("BOTTOMRIGHT", -30, 44)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("GameFontHighlightSmall")
  edit:SetWidth(660)
  StyleText(edit, 12)
  -- Escape gives focus back rather than trapping the player in the box.
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)
  panel.report = edit

  panel.copyHint = Dim(panel, "")
  -- One row ABOVE the buttons. It shared the row with them and the longer
  -- messages ran straight under Delete, which read as a rendering bug.
  panel.copyHint:SetPoint("BOTTOMLEFT", 12, 14 + CTRL_H + 6)

  panel.copy = Button(panel, "Select All for Copy", 150, function()
    edit:SetFocus()
    edit:HighlightText()
    panel.copyHint:SetText("Selected - press |cff55dd55Ctrl+C|r to copy.")
  end)
  panel.copy:SetPoint("BOTTOMRIGHT", -10, 10)
  Tip(panel.copy, "Select All for Copy", TIPS.diagCopy)

  -- The full report, in the box, ready to select. Same text /pt capture writes
  -- to SavedVariables -- but that route needs someone to reload, find the file
  -- and pick the right block out of it, which in practice means the report
  -- never arrives. This is two clicks in a window that is already open.
  panel.full = Button(panel, "Full Report", 110, function()
    if not NS.CaptureSave then return end
    -- Labelled by adapter, same as the slash command. Sorting a list of
    -- captures by which nameplate addon they came from is the whole reason
    -- the label exists.
    local item = NS.CaptureSave(NS.CurrentAdapterName and NS.CurrentAdapterName() or "window")
    -- Saved as well as shown. A report taken here is worth exactly as much as
    -- one taken from the slash command, and losing it because the box was
    -- later re-rendered would be its own bug.
    edit:SetText(table.concat(item.lines or {}, "\n"))
    panel.showingCapture = true
    edit:SetFocus()
    edit:HighlightText()
    panel.copyHint:SetText(
      UnitExists("target")
        and "Saved and selected - press |cff55dd55Ctrl+C|r to copy."
        -- Said here rather than left as an empty section in the pasted text:
        -- the two halves that need a target are the layering ones, which are
        -- exactly what a "colours do not show" report turns on.
        or "Saved, but |cffff8800target a mob and press again|r for the layout sections.")
    if panel.savedPick and panel.savedPick.Refresh then panel.savedPick.Refresh() end
  end)
  panel.full:SetPoint("RIGHT", panel.copy, "LEFT", -6, 0)
  Tip(panel.full, "Full Report",
    "Everything /pt status, /pt bar, /pt adapter and /pt layers know, in one block. Target a mob first. Saved as well as shown, so it is still here later.")

  -- Saved captures.
  --
  -- The whole point of the pairing: this window CANNOT open in combat, and the
  -- capture worth having is the one taken mid-pull. So /pt capture records it
  -- there, and this reads it back once you are out -- including next session,
  -- since it lives in SavedVariables.
  panel.savedPick = Dropdown(panel, 190,
    function()
      local out = {}
      local store = (PLATETWEAKS_DEBUG or {}).captures or {}
      -- Everything at once, first in the list.
      --
      -- Without this, someone with six captures loads and copies six times,
      -- which in practice means they send one and the picture is partial. The
      -- alternative on offer is "send me your whole SavedVariables file", and
      -- that carries every character name on their account -- so the safe
      -- route has to be at least as easy as the lazy one.
      if #store > 1 then
        out[#out + 1] = { text = ("All %d captures"):format(#store), value = "all" }
      end
      -- Newest first: it is the one you just took.
      for index = #store, 1, -1 do
        local item = store[index]
        out[#out + 1] = {
          text = ("%s  |cff808080%s|r"):format(tostring(item.label), tostring(item.when)),
          value = index,
        }
      end
      if #out == 0 then out[1] = { text = "none yet - use /pt capture", value = false } end
      return out
    end,
    function() return nil end,
    function(index)
      local store = (PLATETWEAKS_DEBUG or {}).captures or {}

      if index == "all" then
        local out = {}
        -- Oldest first here, unlike the menu. A file someone pastes reads top
        -- to bottom as the order things happened, which is what you want when
        -- comparing a run before and after a change.
        for position, item in ipairs(store) do
          out[#out + 1] = ("===== capture %d/%d: %s  %s ====="):format(
            position, #store, tostring(item.label), tostring(item.when))
          for _, line in ipairs(item.lines or {}) do out[#out + 1] = line end
          out[#out + 1] = ""
        end
        edit:SetText(table.concat(out, "\n"))
        panel.showingCapture = true
        edit:SetFocus()
        edit:HighlightText()
        panel.selectedCapture = nil
        panel.copyHint:SetText(("All |cff55dd55%d|r captures selected - press |cff55dd55Ctrl+C|r to copy."):format(#store))
        return
      end

      local item = index and store[index]
      if not item then return end
      -- Remembered so Delete knows what to remove. The dropdown is the only
      -- place a capture is ever identified, so without this the button would
      -- have nothing to act on.
      panel.selectedCapture = index
      edit:SetText(table.concat(item.lines or {}, "\n"))
      panel.showingCapture = true
      edit:SetFocus()
      edit:HighlightText()
      panel.copyHint:SetText(("Loaded |cff55dd55%s|r - press |cff55dd55Ctrl+C|r to copy."):format(
        tostring(item.label)))
    end)
  panel.savedPick:SetPoint("RIGHT", panel.full, "LEFT", -6, 0)

  -- Deleting ONE capture, not all of them. Captures pile up over a testing
  -- session and the useful one usually sits beside several throwaways; before
  -- this the only option was wiping the lot, so people kept the junk rather
  -- than risk losing the good run.
  panel.deleteCapture = Button(panel, "Delete", 70, function()
    local store = (PLATETWEAKS_DEBUG or {}).captures or {}
    local index = panel.selectedCapture
    local item = index and store[index]
    if not item then
      panel.copyHint:SetText("|cffff8800Pick a single capture first|r -- 'All' is not a single capture.")
      return
    end
    table.remove(store, index)
    panel.selectedCapture = nil
    panel.showingCapture = nil
    edit:SetText("")
    panel.copyHint:SetText(("Deleted |cff55dd55%s|r. %d capture(s) left."):format(
      tostring(item.label), #store))
    -- The dropdown indexes straight into this table, so it has to be rebuilt
    -- or the next pick reads a shifted entry.
    panel.savedPick.Refresh()
    if panel.Render then panel.Render() end
  end)
  -- Destructive controls together at the right-hand end, away from the two
  -- copy buttons people press constantly.
  panel.deleteAll = Button(panel, "Delete All", 90, function()
    local store = (PLATETWEAKS_DEBUG or {}).captures or {}
    if #store == 0 then
      panel.copyHint:SetText("No captures to delete.")
      return
    end
    -- Confirmed, unlike single Delete: this can wipe runs from earlier
    -- sessions that someone was keeping deliberately, and there is no undo.
    ShowConfirm("Delete all captures",
      ("This removes all %d saved capture(s), including any taken in earlier sessions. This cannot be undone."):format(#store),
      "Delete All",
      function()
        PLATETWEAKS_DEBUG.captures = {}
        panel.selectedCapture = nil
        panel.showingCapture = nil
        edit:SetText("")
        panel.copyHint:SetText("All captures deleted.")
        panel.savedPick.Refresh()
        if panel.Render then panel.Render() end
      end)
  end)
  Tip(panel.deleteAll, "Delete All",
    "Removes every saved capture, including ones from previous sessions. Asks first.")

  -- Anchored here rather than where each button is created: the row runs
  -- right to left from Delete All, and panel.copy is built before these exist.
  panel.deleteAll:SetPoint("BOTTOMRIGHT", -10, 10)
  panel.deleteCapture:SetPoint("RIGHT", panel.deleteAll, "LEFT", -6, 0)
  panel.copy:ClearAllPoints()
  panel.copy:SetPoint("RIGHT", panel.deleteCapture, "LEFT", -6, 0)
  Tip(panel.deleteCapture, "Delete capture",
    "Removes the capture currently loaded above. Delete All removes every one.")

  panel.savedPick.label:SetText("Saved captures")
  -- Always reads as a prompt: this picks something to load, it is not a
  -- setting with a current value.
  panel.savedPick.Refresh = function()
    panel.savedPick.label:SetText("Saved captures")
    panel.savedPick.icon:Hide()
    panel.savedPick.label:SetPoint("LEFT", 8, 0)
  end
  panel.savedPick.Refresh()
  Tip(panel.savedPick, "Saved captures",
    "Reports taken with /pt capture, including ones from a previous session. Take one mid-dungeon -- this window cannot open in combat -- then read it back here.")

  -- Rendered on demand rather than on a timer: these numbers change with
  -- every plate that appears, and a panel that rewrites itself while you are
  -- reading it is worse than one you refresh yourself.
  panel.Render = function()
    local info = NS.CollectDiagnostics and NS.CollectDiagnostics()
    if not info then return end

    panel.stats.plates.value:SetText(tostring(info.plates))
    panel.stats.rigged.value:SetText(tostring(info.rigged))
    panel.stats.nobar.value:SetText(tostring(info.pending))
    panel.stats.skipped.value:SetText(tostring(info.skipped))
    panel.stats.unknown.value:SetText(tostring(info.unknown or 0))
    -- Colour carries the same meaning as the number: plates we could not find
    -- a health bar for is the one stat here where non-zero is a problem.
    if info.pending > 0 then
      panel.stats.nobar.value:SetTextColor(1, 0.35, 0.35)
    else
      panel.stats.nobar.value:SetTextColor(0.55, 0.85, 0.55)
    end

    panel.state:SetText(("auras secret %s   combat %s"):format(
      info.restricted and "|cffffcc00yes|r" or "|cff55dd55no|r",
      info.inCombat and "|cffffcc00yes|r" or "|cff55dd55no|r"))

    local out = {}
    -- Straight from the .toc, so a report can never claim a version the
    -- person is not actually running.
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMeta and select(1, getMeta(NS.ADDON, "Version")) or nil
    table.insert(out, ("PlateTweaks %s"):format(version or "(version unknown)"))
    table.insert(out, ("profile %s | combat %s | auras secret %s"):format(
      info.profile, info.inCombat and "yes" or "no", info.restricted and "yes" or "no"))
    table.insert(out, ("plates %d | rigged %d | bound %d | no health bar %d | friendly skipped %d | hostility unknown %d")
      :format(info.plates, info.rigged, info.bound, info.pending, info.skipped, info.unknown or 0))
    table.insert(out, ("built objects %d"):format((info.textures or 0) + (info.containers or 0)))
    if info.errored > 0 then
      table.insert(out, ("build errors on %d rig(s): %s"):format(info.errored, tostring(info.firstError)))
    end
    if info.testMode then
      table.insert(out, "TEST MODE IS ON -- colours on screen are simulated, not driven by real debuffs")
    end
    table.insert(out, ("peak plates this session: %d (%d of them in combat)")
      :format(info.peakPlates or 0, info.peakPlatesInCombat or 0))
    if (info.containerRefusals or 0) > 0 then
      table.insert(out, ("containers refused this session: %d (%d under combat lockdown)")
        :format(info.containerRefusals or 0, info.containerRefusalsInCombat or 0))
    end
    if (info.rigsEmpty or 0) > 0 or (info.rigsFailed or 0) > 0 or (info.rigsUnsound or 0) > 0 then
      table.insert(out, ("rig health: %d bound plate(s) drawing nothing | %d with refused builds | %d unsound")
        :format(info.rigsEmpty or 0, info.rigsFailed or 0, info.rigsUnsound or 0))
    end

    table.insert(out, "")
    if #info.rules == 0 then
      table.insert(out, "no rules built (nothing rigged, or no rules configured)")
    end
    for _, rule in ipairs(info.rules) do
      local flags = #rule.flags > 0 and ("  " .. table.concat(rule.flags, " ")) or ""
      table.insert(out, ("rule %d: %d cond | hosts %d | containers %d | combos %d | tints %d | borders %d%s")
        :format(rule.index, rule.conditions, rule.hosts, rule.containers,
          rule.combos, rule.tints, rule.borders, flags))
      if rule.lastError then
        table.insert(out, "  first error: " .. rule.lastError)
      end
    end

    table.insert(out, "")
    local t = info.target
    if not t then
      table.insert(out, "target: none")
    else
      table.insert(out, ("target: %s"):format(t.name))
      if t.note then
        table.insert(out, "  " .. t.note)
      end
      if t.bar then
        -- flat-pinned is true for two different reasons -- real Plater, or
        -- a default Blizzard bar tagged to get the same treatment (see
        -- FindHealthBar) -- so it is reported on its own, not as
        -- "plater-style", which read as a claim about which addon this is.
        local why = t.isPlater and "plater" or (t.isDefaultBlizzard and "default-blizzard" or "no")
        table.insert(out, ("  bar %s | frame level %s | flat-pinned %s (%s)"):format(
          t.bar, tostring(t.frameLevel), tostring(t.flatPinned), why))
      end
      if t.rigged then
        table.insert(out, ("  rig base level %s | tints shown %d of %d"):format(
          tostring(t.baseLevel), t.tintsShown or 0, t.tintsTotal or 0))
        table.insert(out, ("  built in combat %s | sound %s | repairs used %d/%d"):format(
          tostring(t.builtInCombat), tostring(t.sound), t.repairs or 0, t.repairCap or 1))
      end
    end

    -- Never over a loaded capture. Render runs on every tab open, so without
    -- this, walking away from the page and back destroys the report you took
    -- in a dungeon -- silently, and with no way to get it back.
    -- Refresh clears the flag when you actually want the live view again.
    if not panel.showingCapture then
      edit:SetText(table.concat(out, "\n"))
    end
    edit:SetCursorPosition(0)
    panel.copyHint:SetText("")
  end

  -- Refreshed when you open the page, not on a timer and not from the general
  -- preview refresh (see SelectTab).
  panel.OnSelect = panel.Render
end

-------------------------------------------------------------------------------
-- Entry points
-------------------------------------------------------------------------------

function NS.Options_RebuildAll()
  if not window then return end
  -- Profile plus what is actually switched on. Both module toggles live one
  -- click away on separate tabs, so without this you cannot tell at a glance
  -- whether a plate is unpainted because of a rule or because the module is
  -- simply off.
  local modules = {}
  if NS.db.tints.enabled then table.insert(modules, "Health Coloring") end
  -- Borders are not a module any more, so the footer stops listing one.
  if NS.db.icons.enabled then table.insert(modules, "Aura Icons") end
  if NS.db.missingIcons.enabled then table.insert(modules, "Missing Debuffs") end

  profileLabel:SetText(("Profile |cff55dd55%s|r   |cff808080--|r   Enabled: %s"):format(
    NS.ProfileKey(),
    #modules > 0 and ("|cff55dd55" .. table.concat(modules, "|r, |cff55dd55") .. "|r")
      or "|cffff4040none|r"))

  -- The bar has to FOLLOW the profile, not only drive it: a spec swap changes
  -- which profile is live without anyone touching these controls.
  if window.profileDrop and window.profileDrop.Refresh then
    pcall(window.profileDrop.Refresh)
  end
  if window.bindBox then
    pcall(window.bindBox.Refresh)
    local spec = NS.SpecName()
    window.bindLabel:SetText(spec
      and (("Use this profile whenever I am |cff55dd55%s|r"):format(spec))
      or "|cffffcc00Spec not known yet - binding unavailable.|r")
  end
  -- Before the pages: the rail carries the rule list itself, so priority,
  -- colours, labels and the unreachable-rule warnings all follow any edit.
  local passes = {
    { "rail", RebuildRail },
    { "health", RebuildHealthTab },

    { "aura icons", RebuildAuraIconTab },
    { "missing debuff", missing.Rebuild },
    { "global", RebuildGlobalTabs },
    { "rule editor", RebuildRuleEditor },
    { "pandemic", RebuildPandemicTab },
    { "profiles", RebuildProfilesTab },
    { "share", share.Rebuild },
    { "about", RebuildAboutTab },
    { "optional tweaks", RebuildTweaksTab },
  }
  for _, pass in ipairs(passes) do
    local ok, err = pcall(pass[2])
    if not ok then
      NS.Print(("|cffff4040%s panel failed|r: %s"):format(pass[1], tostring(err)))
    end
  end
end

-- Errors in here used to vanish: most players run with script errors hidden,
-- so a failure while building the window aborted before Show() and /pt simply
-- did nothing. Report it through our own print instead, which is always
-- visible, and keep a partially-built window rather than retrying the whole
-- build on every subsequent /pt.
-- The window, for anything that has to sit over it -- the colour picker dims
-- and covers this exact frame rather than the whole screen.
function NS.OptionsWindow() return window end

function NS.OpenOptions()
  -- Every entry point ends here -- the slash command, the Blizzard settings
  -- panel, a keybind -- so the "there are no settings to show" check belongs
  -- here too, not only in front of the one caller that happened to have it.
  if not NS.db then
    NS.Print(NS.refusedTwin
      and ("|cffff4040this copy did not start|r -- |cffffff00%s|r is also enabled. Disable one, then reload.")
        :format(NS.refusedTwin)
      or "|cffff4040settings failed to load|r -- check for an earlier error, then /reload.")
    return
  end
  if not window then
    local ok, err = pcall(function()
      CreateWindow()
      -- Guarded individually and NAMED.
      --
      -- These were nine bare calls inside one pcall, so an error in any of them
      -- skipped every page after it -- one wrong variable name in Global
      -- Settings silently cost Pandemic, Profiles, Help, the rule editor and
      -- Diagnostics, and the one line it printed said only "failed to build the
      -- window". Now the broken page is the only one lost, and it is named.
      local builders = {
        { "health", BuildHealthTab },

        { "aura icons", BuildAuraIconTab },
        { "missing debuff", missing.Build },
        { "global settings", BuildGlobalTabs },
        { "pandemic", BuildPandemicTab },
        { "profiles", BuildProfilesTab },
        { "share", share.Build },
        { "help", BuildAboutTab },
        { "rule editor", BuildRuleEditor },
        { "optional tweaks", BuildTweaksTab },
        { "diagnostics", BuildDiagnosticsTab },
      }
      for _, builder in ipairs(builders) do
        local okBuild, errBuild = pcall(builder[2])
        if not okBuild then
          NS.Print(("|cffff4040%s page failed to build|r: %s")
            :format(builder[1], tostring(errBuild)))
        end
      end
      local pos = NS.db.uiPosition
      if pos then
        window:ClearAllPoints()
        window:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
      end
      local size = NS.db.uiSize
      if size and size.height then
        window:SetHeight(math.max(WINDOW_MIN_H, math.min(WINDOW_MAX_H, size.height)))
      end
    end)
    if not ok then
      NS.Print("|cffff4040failed to build the window|r: " .. tostring(err))
      if not window then return end
    end
  end

  if window:IsShown() then
    window:Hide()
    return
  end

  -- Second chance to see it: someone who reloaded past the login popup, or
  -- installed mid-session, still gets it the first time they open settings.
  NS.ShowFirstRunWarning()

  local ok, err = pcall(function()
    statusText:SetText("")
    -- Repopulate from the Cooldown Manager every time the window opens. Its
    -- contents are per-spec, and the dropdowns are built from a cached map --
    -- without this, opening the window after a spec change offered the
    -- previous spec's spells.
    if NS.WipeRelatedCache then NS.WipeRelatedCache() end
    -- One more chance to learn before anything is resolved: whatever is up
    -- right now costs nothing to record and may be the ID a rule needs.
    if NS.LearnAuras then pcall(NS.LearnAuras) end
    NS.Options_RebuildAll()
    -- Always the first tab. Remembering the last one means opening the
    -- window somewhere you did not expect after a session away from it.
    SelectTab(1)
  end)
  if not ok then
    NS.Print("|cffff4040failed to populate the window|r: " .. tostring(err))
  end
  -- Shown either way: a half-populated window is far easier to diagnose than
  -- a command that appears to do nothing.
  window:Show()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  local proxy = CreateFrame("Frame")
  proxy.name = NS.WindowTitle()
  local text = proxy:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", 16, -16)
  text:SetText("PlateTweaks uses its own window — /pt")
  StyleText(text, 12)
  local open = CreateFrame("Button", nil, proxy, "UIPanelButtonTemplate")
  open:SetSize(170, 24)
  open:SetPoint("TOPLEFT", 16, -44)
  open:SetText("Open PlateTweaks")
  open:SetScript("OnClick", function()
    if InCombatLockdown() then
      NS.Print("can't open in combat — try again once you're out of it.")
      return
    end
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    NS.OpenOptions()
  end)
  local category = Settings.RegisterCanvasLayoutCategory(proxy, NS.WindowTitle())
  Settings.RegisterAddOnCategory(category)
end)
