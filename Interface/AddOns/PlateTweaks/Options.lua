local _, NS = ...

-- Standalone options window. Each tab is built the same way:
--
--   [ Enable module ]      always at the top, never scrolls away
--   [ Preview        ]     pinned, so it stays visible while you adjust
--   [ scrolling sections ] collapsible, remembered per character
--
-- Pinning the preview is the point: dragging a slider and watching the plate
-- change is only useful if both are on screen at once.
--
-- The colour preview runs the real rule-priority logic against pretend debuff
-- state — legal because the pretend state is ours, not the game's.

local window, tabButtons, tabPanels = nil, {}, {}
-- The three Global Settings pages, in rail order. Held separately from tabPanels
-- because their rebuild reaches into fields only they have.
local globalPanels
-- Height of the "PREVIEW & TEST" strip at the top of every page, and the
-- width of the test-controls column beside the preview plate.
-- Where a collapsible section actually lands, so the preview can sit on the
-- same edges. The body is a fixed SetSize(716) scroll child anchored at the
-- scroll frame's left (panel x=4), and LayoutSections insets each section by
-- 6 -- so a section spans panel x=10 to x=714, 704 wide. Matching the body
-- itself was still 6px out on each side.
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

local ROW_H = 26
local STAGE_H = 92

-- Shared control metrics. Every interactive widget in this window is this
-- tall, and boxy ones (tick box, switch) are this wide, so a row mixing a
-- button, a dropdown and a checkbox reads as one row rather than three
-- heights stacked. Border weight and colour are shared for the same reason.
local CTRL_H = 20
local CTRL_BOX_W = 20
local CTRL_EDGE = 1

-- Section metrics, in ONE place.
--
-- These were spelled out as bare numbers in CollapsibleSection and again in
-- LayoutSections, so "there is too much white space under the content" was two
-- separate edits that had to agree. Changing SECTION_PAD now moves every
-- section's bottom margin at once, which is the whole point of the widget
-- being shared.
local SECTION_HEAD_H = 30 -- header bar plus the 1px the backdrop insets it
local SECTION_PAD    = 6  -- under the content, inside the border
local SECTION_GAP    = 8  -- between stacked sections
local SECTION_INSET  = 6  -- left/right, from the body's edge

-------------------------------------------------------------------------------
-- Theme — every color the window chrome uses, in one place. Edit these and
-- /reload to re-skin the window; nothing else in this file needs to change.
-- Each entry is {r, g, b} or {r, g, b, a}, 0-1. See PlateTweaks_Theme.md
-- (shipped outside the addon folder) for a guide to what each one touches.
-------------------------------------------------------------------------------
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

-------------------------------------------------------------------------------
-- Tooltips
--
-- One helper, attached to a widget, explaining what that widget does. Held for
-- a second before it appears: this window is dense, and a tooltip that fires
-- the instant the cursor crosses something turns simply moving the mouse into
-- a flicker of popups.
--
-- HookScript, not SetScript. Half the widgets here already own OnEnter and
-- OnLeave -- hover painting, the grip highlight, the rule row's own tooltip --
-- and replacing those would silently break them.
--
-- Everything anchors to the cursor. The rail briefly opened off the window's
-- left edge on the theory that a cursor tooltip would cover the list, but in
-- practice it read as a different, unrelated panel -- one consistent place is
-- worth more than avoiding the overlap.
--
-- Text may be a string or a function returning one -- a rule row's tooltip has
-- to describe whichever rule it currently holds, and these widgets are pooled.
-------------------------------------------------------------------------------

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
  showWhen      = "Present colours the bar while the debuffs are up. MISSING flips it: the rule stays lit until you apply them. Absence has no direct expression under 12.1's aura rules, so a missing rule is drawn unconditionally and then COVERED once the debuff lands.",
  missingCombatOnly = "Holds the missing-rule wash off while the target is out of combat, so it only lights up on mobs you're actually fighting without the debuff on them -- not every untouched mob standing around before a pull. Off by default, since some missing rules are exactly for a pre-pull buff check.\n\nThis applies to ALL your missing rules at once, not just this one: only one missing wash is ever lit, and which one depends on aura state the game will not let an addon read -- so the choice cannot be made per rule. It takes effect once every missing rule has it ticked.",
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

-- The same, for a LABEL.
--
-- A fontstring is not a frame: it has no scripts, so it can never answer the
-- cursor. This lays an invisible mouse-enabled frame over its rect and tips
-- that instead. SetAllPoints against the fontstring rather than fixed
-- coordinates, so the hit area follows the text when a rebuild re-anchors it.
--
-- Worth knowing: the frame swallows clicks inside its rect. That is harmless
-- over label text, which nothing beneath needs to receive -- but it is why
-- this is not simply applied to every fontstring in the window.
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
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })

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

-- Flat checkbox: a small square that fills when on. Blizzard's template
-- carries a lot of chrome for what is a binary.
-- An ordinary tick box, for settings.
--
-- A switch is reserved for turning a MODULE on and off (see ToggleSwitch):
-- that is a different kind of statement -- power, not preference -- and if
-- every option were a switch the distinction would be gone.
local function Checkbox(parent, getValue, setValue)
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  c:SetSize(CTRL_BOX_W, CTRL_H)
  c:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
  c:SetBackdropColor(0.12, 0.12, 0.15, 1)

  c.fill = c:CreateTexture(nil, "OVERLAY")
  c.fill:SetPoint("TOPLEFT", 3, -3)
  c.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  c.fill:SetColorTexture(RGBA(THEME.accent))

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
    -- Derived from the SOURCE, not from the local `checked`.
    --
    -- These widgets are pooled and re-pointed at different rules as the list
    -- is reordered or rebuilt, and any external change (a rebuild, a profile
    -- switch, another control writing the same field) moves the real value
    -- without touching this local. Flipping the local then meant writing the
    -- opposite of what was on screen -- which is what "toggles at random"
    -- was: not a race, a stale copy.
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

-- A sliding switch, used ONLY for a module's on/off.
--
-- The distinction is the point: a tick box says "this option is set", a
-- switch says "this whole module is running or it is not". Keeping them
-- visually different is what lets the rail headings read as power controls
-- rather than as one more setting.
local function ToggleSwitch(parent, getValue, setValue)
  local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
  t:SetSize(26, 13)
  t:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })

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

-- A small square delete control.
--
-- Was a plain Button carrying the letter X, which read as a button someone
-- had forgotten to label. This one is sized like the tick boxes and swatches
-- it sits beside, and goes red on hover, so "this removes something" is
-- legible from the shape rather than from the caption.
local function CloseX(parent, onClick, size)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  size = size or CTRL_H
  b:SetSize(size, size)
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })

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
-- That template brings its own art -- a colour texture plus a border sized by
-- the TEMPLATE, not by the frame -- so SetSize moved the hit box and left the
-- visible square at whatever size Blizzard drew it. Beside a CTRL_BOX_W tick
-- box it was plainly a different control, which is why "the pickers and the
-- checkboxes are still not the same size" kept coming back however the frame
-- was sized.
--
-- This is the Checkbox's geometry exactly: same frame size, same backdrop,
-- same edge weight, same 3px inset on the fill. Change CTRL_BOX_W/CTRL_H and
-- both move together.
local function ColorSwatch(parent, getColor, setColor)
  local s = CreateFrame("Button", nil, parent, "BackdropTemplate")
  s:SetSize(CTRL_BOX_W, CTRL_H)
  s:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
  s:SetBackdropColor(0.12, 0.12, 0.15, 1)

  -- Behind the colour, so a low alpha reads as translucency against a known
  -- mid grey instead of as a darker shade of the colour itself.
  s.backing = s:CreateTexture(nil, "ARTWORK")
  s.backing:SetPoint("TOPLEFT", 3, -3)
  s.backing:SetPoint("BOTTOMRIGHT", -3, 3)
  s.backing:SetColorTexture(0.30, 0.30, 0.33, 1)

  s.Color = s:CreateTexture(nil, "OVERLAY")
  s.Color:SetPoint("TOPLEFT", 3, -3)
  s.Color:SetPoint("BOTTOMRIGHT", -3, 3)

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
    local c = getColor()
    -- Alpha is the fragile part. GetColorAlpha has returned nil on some
    -- builds, and a nil or zero alpha paints every tint fully transparent —
    -- which reads as "the coloring randomly stopped working", including in
    -- the preview, with no error anywhere because nothing actually threw.
    local previousAlpha = c.a or 1
    -- These callbacks run on every frame of a drag, so anything that prints
    -- from in here floods the chat frame. The missing-alpha case is still
    -- handled, just silently: falling back to the previous alpha is the right
    -- behaviour whether or not anyone is told about it.
    local function apply()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()
      if type(a) ~= "number" then a = previousAlpha end
      setColor(r, g, b, a)
      refresh()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
      r = c.r, g = c.g, b = c.b, opacity = c.a or 1, hasOpacity = true,
      swatchFunc = apply, opacityFunc = apply,
      cancelFunc = function(prev)
        setColor(prev.r, prev.g, prev.b, prev.opacity or 1)
        refresh()
      end,
    })
  end)
  s.Refresh = refresh
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

local function Dropdown(parent, width, entries, getValue, setValue)
  local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
  d:SetSize(width, CTRL_H)
  d:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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
  menu:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
  menu:SetBackdropColor(0.10, 0.10, 0.12, 0.98)
  menu:SetBackdropBorderColor(0.42, 0.42, 0.50, 1)
  menu:EnableMouse(true)
  menu:EnableMouseWheel(true)
  menu:Hide()
  menu.rows = {}
  menu.offset = 0
  d.menu = menu

  -- Scrollbar. The wheel alone was fine when every list was short, but the
  -- LibSharedMedia texture lists run to dozens of entries and a wheel gives
  -- no sense of where you are in one or how much is left.
  --
  -- Built by hand rather than with a Slider: the thumb has to RESIZE to show
  -- what fraction of the list is visible, which a Slider's fixed thumb cannot
  -- do, and the whole widget is drawn to match this panel rather than the
  -- default UI.
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
        if entry.isTitle then
          row.text:SetTextColor(RGBA(THEME.headerText))
        elseif getValue() == entry.value then
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

  local track = CreateFrame("Frame", nil, holder)
  track:SetPoint("LEFT", 0, 0)
  track:SetSize(width, 14)
  track:EnableMouse(true)

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

  local function Position()
    local current = math.max(min, math.min(max, getValue() or min))
    local pct = (max > min) and ((current - min) / (max - min)) or 0
    fill:SetWidth(math.max(1, width * pct))
    thumb:ClearAllPoints()
    thumb:SetPoint("CENTER", groove, "LEFT", width * pct, 0)
  end

  local function SetFromCursor()
    local cursorX = GetCursorPosition() / track:GetEffectiveScale()
    local left = track:GetLeft()
    if not left then return end
    local pct = math.max(0, math.min(1, (cursorX - left) / width))
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
  local function BuildEntries()
    local list = { { text = defaultText, value = nil, isTitle = true } }
    local onTargets = NS.GetCooldownManagerSpells()
    if #onTargets == 0 then
      table.insert(list, { text = "Cooldown Manager lists none — use the ID box", isTitle = true })
      return list
    end
    for _, item in ipairs(onTargets) do
      table.insert(list, {
        text = ("%s%s  |cff808080%d|r"):format(
          isTracked(item.spellID) and "|cff55dd55•|r " or "",
          NS.SpellName(item.spellID), item.spellID),
        value = item.spellID,
        icon = NS.SpellIcon(item.spellID),
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

-- Accepts a spell ID or a spell NAME. Not numeric-only any more: the ID that
-- has to go in is often one the Cooldown Manager never offers (Rend's debuff
-- is 388539, not the 772 it lists), and a name is easier to be right about
-- than a number nobody can memorise.
--
-- What is typed is not necessarily what is stored. NS.ResolveAuraInput checks
-- it against the auras actually on your target and substitutes the aura's own
-- ID when they differ, reporting what it did rather than doing it silently.
-- Resolve whatever the user chose -- typed text, or a spell ID picked from a
-- dropdown -- into the ID that actually lands, reporting any substitution.
--
-- Deliberately shared by the DROPDOWNS as well as the boxes. The Cooldown
-- Manager lists abilities: Moonfire and Sunfire come out of it as cast IDs,
-- so picking them from the list built rules that could never match, while
-- typing the same two names worked. Every path that adds a spell goes
-- through here so they cannot disagree again.
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
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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
  s:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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

  s.content = CreateFrame("Frame", nil, s)
  s.content:SetPoint("TOPLEFT", 0, -SECTION_HEAD_H)
  s.content:SetPoint("TOPRIGHT", 0, -SECTION_HEAD_H)

  s.open = NS.db.uiSections[key] ~= false

  function s:Resize(height)
    self.contentHeight = height
    self.content:SetHeight(math.max(1, height))
    self:SetHeight(self.open and (SECTION_HEAD_H + height + SECTION_PAD) or SECTION_HEAD_H)
    -- Anything anchored BELOW this section has to move when it changes size,
    -- and collapsing changes its size by its whole content height. Pushing
    -- that out as a notification rather than leaving each page to remember to
    -- re-run its own layout is the difference between "one page forgot" and
    -- "it cannot be forgotten" -- see BuildTabFrame, which uses it to re-anchor
    -- the scrolling body under the preview.
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

-- Turns the open rule's preview on. Its debuffs ARE the preview state, so
-- "preview this rule" means ticking every one of them.
--
-- Called when a rule is opened and whenever a test button is pressed: you
-- pressed test to look at something, and a rule page with its own preview
-- switched off is the one state where that would show you nothing.
local function EnsureRulePreview()
  if not expandedRule then return end
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

-- Applying a change reaches into every live nameplate, and a structural one
-- tears their containers down and builds them again — up to a thousand
-- textures per plate for a three-debuff rule. Doing that once per slider step
-- made dragging stutter, so the world-side work is coalesced: the preview
-- updates immediately (it is what you are looking at), the plates catch up
-- shortly after you stop moving.
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

-- Test-mode buttons, on both colouring tabs. Deliberately do NOT close the
-- window: the point is to tick different debuffs in the simulate row and watch
-- the plate change as you do.
--
-- The "all" argument picks which scope this button owns. Each one stops test mode if it is
-- already running in ITS scope, and switches to that scope otherwise -- so
-- clicking "all" while testing the target switches rather than stopping,
-- which is what you meant by clicking it.
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
  stage:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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
  -- bar itself at the top OVERLAY sublevel, exactly like stage.borderEdges
  -- does for rule borders a few lines below.
  --
  -- It used to be a backdrop on a separate frame sitting 2px OUTSIDE the
  -- plate, which was fine while it was only scene-setting. Once the engine
  -- began reserving a band INSIDE the bar for it, that frame had to win a
  -- draw-order fight against the bar it overlapped -- and lost, leaving the
  -- bar's own colour showing in the band where the border should have been.
  -- Textures on the bar have no such fight: sublevel decides, and 7 is the top.
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
  stage.bar:SetStatusBarColor(0.62, 0.11, 0.11)

  stage.barBG = stage.bar:CreateTexture(nil, "BACKGROUND")
  stage.barBG:SetAllPoints()
  stage.barBG:SetColorTexture(0.10, 0.03, 0.03, 0.95)

  -- OVERLAY sublayer 7 and anchored to the BAR FRAME, not to the status-bar
  -- fill texture.
  --
  -- Anchored to the fill, the preview inherited the fill's width and draw
  -- order: at a low health value it shrank, and on ARTWORK it shared a layer
  -- with the bar texture itself and could lose. This is a diagram of the rule
  -- logic, not a simulation of a health bar, so neither should be able to
  -- affect whether the colour is visible.
  -- Anchored to the status bar's FILL, exactly as the real tint is, so the
  -- colour covers only the health that is actually there. It was moved onto
  -- the bar frame while chasing a visibility bug; the real cause was the
  -- draw layer, and OVERLAY sublayer 5 is what fixed it.
  stage.tint = stage.bar:CreateTexture(nil, "OVERLAY", nil, 5)
  stage.tint:SetPoint("TOPLEFT", stage.bar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
  stage.tint:SetPoint("BOTTOMRIGHT", stage.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
  stage.tint:Hide()

  -- Missing-health cover preview. Anchored/repainted per refresh via
  -- NS.ApplyMissingCover, same as the tint is via NS.ApplyRuleFill -- the
  -- 72%-fixed stage bar always leaves a visible missing side to preview.
  -- Sublevel 6, not 5: above the tint's own sublevel so it reliably wins any
  -- unclipped sliver a texture-mode fill's mask leaves at the live edge
  -- (same reasoning as the real engine's missingCoverSublevel), and below
  -- stage.borderEdges at 7.
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

  -- The missing wash. Created here rather than per preview pane so every stage
  -- gets one and none can be forgotten -- the same reasoning as the note
  -- below.
  --
  -- BELOW stage.tint, mirroring the plate: the ladder is built at the rig's
  -- base level, under every presence rule (see ruleBase in NS.BuildTints), so
  -- a matching rule wins the bar and the reminder shows on mobs where nothing
  -- matches. On a real plate the ladder's own two halves sit on different
  -- frames and the engine's strata rules separate them, which a flat preview
  -- cannot reproduce -- so this draws ONE texture and paints it the colour the
  -- ladder would have resolved to.
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
  return stage
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
-- Resolved the way the engine resolves it, because the engine does not choose
-- -- it CONSTRUCTS the answer. Wash k is built to show only while D1..D(k-1)
-- are present and Dk is not, so the rule you see is simply the first one in
-- list order whose debuff is not up. Everything after it is covered by
-- definition; everything before it has already been applied.
--
-- Single-debuff and enabled only, matching the ladder's own admission rules
-- in NS.BuildTints. Health list only -- border rules have no wash.
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
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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

-- A single dummy icon for the Timer & Stacks section.
--
-- It is built at the icon's REAL pixel size and then the whole frame is
-- scaled up, so what you see is a magnified nameplate icon rather than a
-- bigger one: a 28pt timer on a 24px icon overflows it here exactly as much
-- as it will in the world. Drawing the dummy at a fixed 72px instead made
-- every font look far smaller than it really was.
local SWATCH_TARGET = 76 -- how many screen pixels the magnified icon fills
local SWATCH_MAX_ZOOM = 5

local function BuildTextSwatch(parent)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(120, 128)
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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

-------------------------------------------------------------------------------
-- Confirmation dialog
--
-- Hand-built rather than StaticPopupDialogs so it matches the rest of the
-- window. One shared instance, re-labelled per use.
-------------------------------------------------------------------------------

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
    d:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
    })
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

-------------------------------------------------------------------------------
-- Text prompt
--
-- ShowConfirm with an edit box. Separate instance rather than a mode flag on
-- the shared one: the two can never be open at once, but a stray edit box
-- left visible on an ordinary confirm is the kind of bug that lingers.
-------------------------------------------------------------------------------

local promptDialog

local function ShowPrompt(title, body, acceptText, onAccept, initialText)
  if not promptDialog then
    local d = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    d:SetSize(420, 200)
    d:SetPoint("CENTER", 0, 80)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:EnableMouse(true)
    d:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
    })
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

-------------------------------------------------------------------------------
-- First-run warning
--
-- Shown once per account, before the addon has done anything the user did not
-- ask for. Two real choices: accept, or unload. "Unload" genuinely disables
-- the addon and reloads -- there is no way to unload in place, and a button
-- that only hid itself would be a lie.
-------------------------------------------------------------------------------

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
    d:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
    })
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
    d.title:SetText("PlateTweaks")
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
        pcall(disable, "PlateTweaks")
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


-- The expand/collapse triangle.
--
-- A rotated texture, not a "+"/"-" or a ▶ character: the panels' own
-- collapsibles use text glyphs, but Expressway has no guaranteed triangle and
-- a missing glyph would leave an empty square. UI-SortArrow is a clean solid
-- triangle that ships with the client, pointing UP, so it is turned a quarter
-- clockwise for closed and a half for open.
local function Twisty(parent, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(14, 14)

  -- A real texture again, but the right one. Stepped bars were geometrically
  -- a triangle and looked it -- five hard steps at 10px is a staircase, not
  -- an edge. ChatFrameExpandArrow is a small SOLID triangle that ships with
  -- the client and is drawn antialiased, pointing RIGHT at rest, which is
  -- exactly the collapsed state. Expanded turns it a quarter clockwise.
  b.tex = b:CreateTexture(nil, "OVERLAY")
  b.tex:SetSize(10, 10)
  b.tex:SetPoint("CENTER")
  b.tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

  local open, hovered = true, false
  local function Paint()
    -- SetRotation takes counter-clockwise radians, so a quarter TURN
    -- clockwise -- right to down -- is negative. pcall'd so a client without
    -- rotation support shows a right-pointing triangle rather than erroring.
    pcall(b.tex.SetRotation, b.tex, open and (-math.pi / 2) or 0)
    local shade = hovered and 1 or 0.66
    b.tex:SetVertexColor(shade, shade, math.min(1, shade * 1.08), 1)
  end

  function b:SetOpen(value) open = value and true or false; Paint() end
  b:SetScript("OnEnter", function() hovered = true; Paint() end)
  b:SetScript("OnLeave", function() hovered = false; Paint() end)
  b:SetScript("OnClick", onToggle)
  Paint()
  return b
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
local railPool = {
  headers = {}, items = {}, rows = {},
  -- Bars behind group headings. Structure rather than decoration: they say
  -- what contains what, which indentation alone stopped managing once the
  -- rail went three levels deep (module -> list -> rule).
  headerBGs = {}, twisties = {}, adds = {}, switches = {},
  -- Hairline between the combo and single halves of a rule list. It replaced
  -- the "Combo Rules" / "Single Rules" heading rows and the inset panels
  -- behind them; naming each half moved onto the add row that closes it.
  dividers = {},
  -- No button pool: the rail has no buttons of its own any more -- adding is
  -- a row in the list, and collapsing is the twisty.
}
local RebuildRail

-- A combo rule used to cost roughly ten times a single-debuff one (~100 textures per
-- nameplate against ~10), so the two sections are tinted warm and cool. The
-- colour is carrying that fact, not just separating the lists.
local SECTION_TINT = {
  combo  = { 0.90, 0.70, 0.42 },
  single = { 0.55, 0.80, 0.62 },
}

-- The heading for one rule section, as a clickable row.
--
-- Was a small tinted fontstring, which said "these two lists are different
-- kinds of thing" but did not say "this opens" and did not look like anything
-- else in the rail. It reads as a menu item now -- same font, same size, same
-- resting colour, same hover wash as NavItem -- because that is what it
-- behaves like. The section's own colour survives on the panel edge beside its
-- rules, which is where it is doing structural work rather than decorating a
-- label.
-- The "New Rule" row that closes each rule section.
--
-- Built to the SAME internal offsets as RuleRow -- the button where the
-- colour swatch sits, the text where the rule name sits -- so the column of
-- swatches down a section stays unbroken and this reads as the next entry in
-- the list rather than a control bolted on underneath it.
--
-- The plus is drawn as two bars rather than typed: at 10px square, matching
-- the swatch, a font glyph is mostly padding and lands off centre.
local function AddRuleRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(20)
  r:EnableMouse(true)

  r.box = CreateFrame("Frame", nil, r, "BackdropTemplate")
  r.box:SetSize(10, 10)
  r.box:SetPoint("LEFT", 8, 0)
  r.box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })

  r.plusH = r.box:CreateTexture(nil, "OVERLAY")
  r.plusH:SetSize(6, 2)
  r.plusH:SetPoint("CENTER")
  r.plusV = r.box:CreateTexture(nil, "OVERLAY")
  r.plusV:SetSize(2, 6)
  r.plusV:SetPoint("CENTER")

  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.label:SetPoint("LEFT", 23, 0)
  r.label:SetPoint("RIGHT", -8, 0)
  r.label:SetJustifyH("LEFT")
  r.label:SetWordWrap(false)
  r.label:SetText("NEW RULE")
  -- Same face and size as the COMBO RULES / SINGLE RULES headings above.
  StyleText(r.label, 9)

  local hovered = false
  local tint = { 0.60, 0.60, 0.66 }
  local function Paint()
    local mul = hovered and 1 or 0.72
    local red, green, blue = tint[1] * mul, tint[2] * mul, tint[3] * mul
    r.label:SetTextColor(red, green, blue, 1)
    r.box:SetBackdropColor(0, 0, 0, hovered and 0.5 or 0.25)
    r.box:SetBackdropBorderColor(red, green, blue, 1)
    r.plusH:SetColorTexture(red, green, blue, 1)
    r.plusV:SetColorTexture(red, green, blue, 1)
  end

  -- Tinted to whichever section it closes, so it belongs to that block.
  function r:SetTint(colour) tint = colour; Paint() end

  r:SetScript("OnEnter", function() hovered = true; Paint() end)
  r:SetScript("OnLeave", function() hovered = false; Paint() end)
  Paint()
  return r
end

-- Rows currently on screen, keyed by GROUP rather than by list:
-- "health|combo", "health|single", and the same pair for border.
--
-- Rules are split by how many debuffs they require, and a drag is confined to
-- its own group. That is not decoration -- it makes the one ordering mistake
-- this addon allows structurally impossible. A rule dies when something above
-- it needs a SUBSET of its debuffs, which in practice is a single-debuff rule
-- sitting above a combo containing it. Keep every combo above every single
-- and that arrangement cannot be expressed at all, so dragging stops being
-- something to validate after the fact.
--
-- Module-level rather than local to each RebuildRail: the drag handlers used
-- to close over per-rebuild tables, which left every previous generation of
-- handlers pointing at a stale list.
-- Rows of the rule TABLE on a Color Rules page, per list, so a drag there can
-- find its neighbours. Separate from railRows: the same rule appears in both
-- places and each needs its own on-screen geometry.
local pageRows = {}
local pageRowCount = {}

local railRows = {}
local railRowCount = {}
local railDrag = nil

-- Forward-declared, because RuleRow's mouse handlers call all four and it is
-- defined above them. A local declared later is simply not in scope inside an
-- earlier closure -- the call resolves to a nil global and the handler dies
-- mid-way, which looks exactly like the mouse input never arriving.
local CursorY, DropIndexFor, RailIndicator, UpdateRailIndicator

-- A rule in the rail: priority number, its colour, its debuffs, and a grip.
--
-- The grip is the whole reason the row can be understood: WoW has no list
-- widget, so nothing about a frame says "this can be dragged" unless you draw
-- something that does.
local function RuleRow(parent)
  local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
  r:SetHeight(22)
  r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  -- Stated rather than relied on. Buttons are mouse-enabled by default, but
  -- this row lives inside a ScrollFrame and is pooled across rebuilds, and a
  -- row that silently stops taking input is indistinguishable from a drag
  -- implementation that does not work.
  r:EnableMouse(true)
  -- Deliberately no RegisterForDrag and no OnClick: both the click and the
  -- drag are driven from OnMouseDown/OnUpdate below, so the two cannot fight
  -- over the same press.

  -- No priority number. Position in the list IS the priority, and a column of
  -- digits restating it was noise -- worse, it read as an identifier, as
  -- though rule 2 stayed rule 2 after a drag.
  -- Offsets are small because the ROW is now inset as a whole (see
  -- RebuildRail) rather than each part being pushed right individually. The
  -- row's own left edge is the indent.
  r.swatch = r:CreateTexture(nil, "ARTWORK")
  r.swatch:SetSize(10, 10)
  r.swatch:SetPoint("LEFT", 8, 0)

  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.label:SetPoint("LEFT", 23, 0)
  r.label:SetPoint("RIGHT", -24, 0)
  r.label:SetJustifyH("LEFT")
  r.label:SetWordWrap(false)
  StyleText(r.label, 11.5)

  -- Two bars, like an equals sign. Drawn rather than typed: the addon's own
  -- typeface has no guaranteed glyph for this, and a missing one leaves a
  -- blank column exactly where the only hint that the row moves should be.
  --
  -- It brightens on hover (see Paint) because a static grey mark reads as
  -- decoration; something that responds to the cursor reads as a control.
  r.grip = CreateFrame("Frame", nil, r)
  r.grip:SetSize(14, 14)
  r.grip:SetPoint("RIGHT", -7, 0)
  r.grip.bars = {}
  for i = 1, 2 do
    local bar = r.grip:CreateTexture(nil, "OVERLAY")
    bar:SetHeight(2)
    bar:SetPoint("LEFT")
    bar:SetPoint("RIGHT")
    bar:SetPoint("TOP", 0, -3 - (i - 1) * 5)
    r.grip.bars[i] = bar
  end

  -- Marks a rule nothing can ever reach (see NS.ShadowedRules).
  r.dead = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.dead:SetPoint("RIGHT", r.grip, "LEFT", -3, 0)
  StyleText(r.dead, 12)
  r.dead:SetTextColor(1, 0.75, 0.1)
  r.dead:SetText("!")
  r.dead:Hide()

  local selected, hovered = false, false
  local function Paint()
    if selected then
      r:SetBackdropColor(RGBA(THEME.tabBGSelected))
      r.label:SetTextColor(RGBA(THEME.textNormal))
    else
      r:SetBackdropColor(RGBA(THEME.tabBGHover, hovered and 1 or 0))
      r.label:SetTextColor(RGBA(THEME.tabTextDim))
    end
    -- The grip is the affordance, so it is the thing that has to answer the
    -- cursor: dim at rest, near-white under it.
    for _, bar in ipairs(r.grip.bars) do
      if hovered or selected then
        bar:SetColorTexture(0.85, 0.85, 0.90, 1)
      else
        bar:SetColorTexture(0.42, 0.42, 0.48, 1)
      end
    end
  end
  function r:SetSelected(value) selected = value and true or false; Paint() end
  -- The label is truncated rather than wrapped, so the tooltip is the only
  -- place the full rule can be read. Wrapping was the alternative and it is
  -- the wrong trade here: it would make rows different heights, break the
  -- drag maths that assumes a uniform row, and still lose to a long enough
  -- rule -- while the whole rule is one click away on the right anyway.
  r:SetScript("OnEnter", function() hovered = true; Paint() end)
  r:SetScript("OnLeave", function() hovered = false; Paint() end)

  -- Through the shared tooltip system rather than driving GameTooltip here.
  -- It used to fire the instant the cursor touched a row, which made scanning
  -- the rail a strobe of popups; now it waits like every other tooltip and
  -- opens off the window's left edge instead of over the list.
  --
  -- Functions, not strings: these rows are pooled and re-pointed at a different
  -- rule on every rebuild, so text captured at construction would describe
  -- whichever rule happened to be first.
  Tip(r,
    function(self) return self.fullLabel end,
    function(self)
      if not self.rule then return nil end
      local count = #(self.rule.conditions or {})
      local lines = { count == 1 and "1 debuff" or (count .. " debuffs") }
      if self.rule.enabled == false then
        table.insert(lines, "|cffff8080Disabled|r")
      end
      if self.blockedBy then
        table.insert(lines, ("|cffffcc00Never shows -- rule %d above matches whenever this does.|r")
          :format(self.blockedBy))
      end
      return table.concat(lines, "|n")
    end,
    { note = "Click to edit. Drag to reorder." })

  -- Drag by tracking the cursor ourselves rather than through
  -- RegisterForDrag/OnDragStart. Same technique as the dropdown's scrollbar
  -- thumb, and for the same reason: we need the position DURING the drag to
  -- move the drop indicator, which the drag events do not give us. It also
  -- keeps click and drag on one code path, so a click cannot be swallowed by
  -- a drag that never started.
  local DRAG_THRESHOLD = 4

  -- Finishing a press: either a click (open the rule) or a drop (reorder).
  -- Called from OnUpdate's release poll AND from OnMouseUp, whichever notices
  -- first -- they guard each other, since OnMouseUp misses a release that
  -- happens off the row and OnUpdate misses nothing but only runs while the
  -- frame is shown.
  local function FinishPress(self)
    if not self.pressed then return end
    self.pressed = false

    local line = RailIndicator()
    if line then line:Hide() end
    self:SetAlpha(self.rule and self.rule.enabled == false and 0.45 or 1)

    if not self.moved then
      expandedRule = self.rule
      expandedSection = "rule"
      EnsureRulePreview()
      SelectTab(self.page)
      NS.Options_RebuildAll()
      return
    end

    local target = DropIndexFor(self.group)
    railDrag = nil
    self.moved = false
    if not target then return end
    local from = self.index
    -- Removing shifts everything after it up, so a drop below the original
    -- slot has to lose one to land where it was aimed.
    if target > from then target = target - 1 end
    if target == from then return end

    local group = self.groupRules
    local list = self.list
    if not group or not list then return end

    local moved = table.remove(group, from)
    table.insert(group, math.max(1, math.min(#group + 1, target)), moved)

    -- Write the master list back as combos-then-singles. The rail only ever
    -- reorders WITHIN a group, so rebuilding the whole list from the two
    -- groups is what keeps the stored order matching what is on screen -- and
    -- it re-establishes the combos-above-singles invariant for free, without
    -- anyone having to remember it.
    --
    -- Mutated in place rather than replaced: NS.db.tints.rules is held by
    -- reference in a few places, and swapping the table would strand them.
    wipe(list)
    for _, rule in ipairs(self.combos) do table.insert(list, rule) end
    for _, rule in ipairs(self.singles) do table.insert(list, rule) end
    Structural()
  end
  r.FinishPress = FinishPress

  r:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or not self.rule then return end
    self.pressY = CursorY(self)
    self.pressed = true
    self.moved = false
  end)

  r:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" then return end
    FinishPress(self)
  end)

  r:SetScript("OnUpdate", function(self)
    if not self.pressed then return end

    -- The button can come up anywhere -- off the row, off the window -- and
    -- OnMouseUp only fires while the cursor is still over this frame, so the
    -- release is polled for here as well.
    if not IsMouseButtonDown("LeftButton") then
      FinishPress(self)
      return
    end

    local y = CursorY(self)
    if not y or not self.pressY then return end
    if not self.moved and math.abs(y - self.pressY) >= DRAG_THRESHOLD then
      self.moved = true
      railDrag = self
      self:SetAlpha(0.4)
    end
    if self.moved then
      UpdateRailIndicator(self.group, DropIndexFor(self.group))
    end
  end)

  Paint()
  return r
end

-- Cursor Y in the same coordinate space frames report their own edges in.
-- GetCursorPosition is raw screen pixels; frame:GetTop() is already divided
-- by the frame's effective scale, so the cursor has to be too or every
-- comparison is off by the UI scale factor.
function CursorY(frame)
  local scale = frame and frame:GetEffectiveScale()
  if not scale or scale == 0 then return nil end
  local _, y = GetCursorPosition()
  return y / scale
end

-- Where a drag would drop, given where the cursor is over a list of rows.
--
-- Hand-rolled because WoW has no reorderable list: compare the cursor against
-- each row's own top and bottom.
function DropIndexFor(group)
  local rows, count = railRows[group], railRowCount[group]
  if not rows or count == 0 then return 1 end
  local cursorY = CursorY(rows[1])
  if not cursorY then return nil end

  for index = 1, count do
    local row = rows[index]
    local top, bottom = row:GetTop(), row:GetBottom()
    if top and bottom and cursorY <= top and cursorY >= bottom then
      -- Above a row's midpoint means "take its place", below means "after it".
      return cursorY >= (top + bottom) / 2 and index or index + 1
    end
  end
  -- Past the ends of the list entirely.
  local firstTop = rows[1]:GetTop()
  if firstTop and cursorY > firstTop then return 1 end
  return count + 1
end

-- A line showing where the row would land. Without it a drag gives no
-- feedback at all until you let go, which is indistinguishable from a drag
-- that is not working.
function RailIndicator()
  if not window or not window.railContent then return nil end
  local content = window.railContent
  if not content.dropLine then
    -- On its own elevated frame, not straight onto the content. Rows are
    -- frames with their own backdrop, and a texture belonging to their parent
    -- draws BEHIND them however high its draw layer -- so the indicator would
    -- have been hidden by the very rows it points between.
    local holder = CreateFrame("Frame", nil, content)
    holder:SetAllPoints(content)
    holder:SetFrameLevel(content:GetFrameLevel() + 10)
    local line = holder:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    line:SetColorTexture(RGBA(THEME.accent))
    line:Hide()
    content.dropHolder = holder
    content.dropLine = line
  end
  return content.dropLine
end

function UpdateRailIndicator(group, target)
  local line = RailIndicator()
  if not line then return end
  local rows, count = railRows[group], railRowCount[group]
  if not rows or count == 0 or not target then line:Hide() return end

  line:ClearAllPoints()
  if target > count then
    local last = rows[count]
    line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 4, 1)
    line:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", -4, 1)
  else
    local row = rows[target]
    line:SetPoint("TOPLEFT", row, "TOPLEFT", 4, 1)
    line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, 1)
  end
  line:Show()
end

-- Built from scratch rather than from PortraitFrameTemplate. Every widget in
-- here is already hand-drawn and flat, so the gold-bevelled chrome around
-- them was the last thing that still read as someone else's UI — and the
-- portrait ring in particular was only ever being worked around.
-- Width stays fixed: every row inside the pages is laid out at hardcoded pixel
-- offsets, so only height is free to resize until that layout is reworked.
--
-- Widened from 790 when the tab strip became a left rail. The rail could have
-- been carved out of the old width instead, but the page bodies are pinned at
-- SetSize(716, ...) and there are ~170 hardcoded left offsets inside them --
-- narrowing the content area would have put every one of those in scope.
-- Growing the window keeps all of them valid and costs nothing but pixels.
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
-- Import/export strings. Its own page rather than a section on Profiles: that
-- page is about which profile is in force on this account, and this one is
-- about moving a profile off it entirely.
--
-- Everything this page owns hangs off ONE table rather than a local each,
-- because this file's main chunk is at Lua's hard limit of 200 locals -- seven
-- more and it does not compile, which fails the whole addon rather than the
-- page. Anything added here from now on should go in this table too.
local share = { PAGE = 13 }
local PAGE_COUNT = 13

-- Reading order, not index order. Modules first because that is what people
-- come here to change; the global drawing settings next, under a heading that
-- says why they are not inside a module; setup last because it is visited
-- rarely.
--
-- Every entry is a page under a heading -- there is no second level -- so they
-- all share one indent. An earlier version indented some and not others,
-- which implied a hierarchy that does not exist.
local NAV_GROUP_INDENT = 10
local NAV_ITEM_INDENT = 22
-- Rules and the "New Rule" row that closes each section: one level in from
-- their section heading, which itself sits at NAV_ITEM_INDENT alongside the
-- page links. This is the ROW's left edge, not a text offset -- RuleRow and
-- AddRuleRow keep small fixed offsets inside themselves so their swatch
-- columns stay aligned with each other.
local RULE_ROW_INDENT = 22
-- Group heading bar. Taller than the 19 it started at: at four levels deep the
-- headings are the only thing giving the rail structure, so they earn the
-- extra pixels. Everything on the bar centres on RAIL_HEADER_H / 2.
local RAIL_HEADER_H = 24

-- Aura Icons is the one module set apart. It is off by default and most
-- people leave it that way -- their nameplate addon already draws an aura row
-- -- so listing it beside the modules everyone actually uses overstated it.
-- Everything else that paints the bar is a Module regardless of how often it
-- is switched on.
-- Each colouring module heads its own group with its rule list directly
-- underneath, because the rules ARE what you navigate that module for. A
-- shared "Modules" heading put one more level between you and the thing you
-- came to edit, and the rule list was buried inside a page besides.
--
-- ruleList marks where a live list gets injected -- see RebuildRail.
--
-- One level of nesting, not two. The rules hang directly under their page
-- link, behind its twisty; the combo/single split is a hairline between two
-- halves of that one list rather than two collapsible sections of its own.
-- Each half is named by the add row that closes it, so nothing is lost and
-- the rail loses a level.
local NAV_LAYOUT = {
  { group = "Health Coloring", module = "health", tip = "switchHealth" },
  { label = "Color Rules",      index = PAGE_HEALTH, collapse = "health", tip = "health" },
  { ruleList = "health" },
  { label = "Pandemic Flash",   index = PAGE_PANDEMIC, module = "pandemic", tip = "pandemic",
    switchTip = "switchPandemic" },
  { label = "General Settings", index = PAGE_GENERAL, tip = "general" },
  { group = "Border Coloring", module = "border", tip = "switchBorder" },
  { label = "Color Rules",      index = PAGE_BORDER, collapse = "border", tip = "border" },
  { ruleList = "border" },
  { group = "Aura Icons", module = "icons", tip = "switchIcons" },
  { label = "Filters",          index = PAGE_ICONS, tip = "icons" },
  { label = "Position & Size",  index = PAGE_ICON_LAYOUT, tip = "iconLayout" },
  { label = "Timer & Stacks",   index = PAGE_ICON_TEXT, tip = "iconText" },
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

local function RailOpen(kind)
  NS.db.uiRailOpen = NS.db.uiRailOpen or {}
  return NS.db.uiRailOpen[kind] ~= false
end

local function RuleListFor(kind)
  if kind == "border" then return NS.db.tints.borderRules or {} end
  return NS.db.tints.rules or {}
end

local function PageFor(kind)
  return kind == "border" and PAGE_BORDER or PAGE_HEALTH
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
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
  frame:SetBackdropColor(RGBA(THEME.windowBG))
  frame:SetBackdropBorderColor(RGBA(THEME.windowBorder))
  frame:Hide()

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
  frame.title:SetText("PlateTweaks")
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
  -- The strip was already full at five entries across 790px, and three of the
  -- sections it hid under "Health Coloring" were never about health colouring
  -- at all -- Plate Border, Bar Edges and Pandemic Flash draw on every plate
  -- whether or not a rule matches. They now have their own pages, which a
  -- horizontal strip had no room for. A vertical list also lets related pages
  -- sit under a heading rather than every page competing at the same level.
  local rail = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  rail:SetPoint("TOPLEFT", 8, -52)
  rail:SetPoint("BOTTOMLEFT", 8, 30)
  rail:SetWidth(RAIL_W)
  rail:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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

-- Lays the whole rail out: headings, pages, and a live row per rule.
--
-- Re-run on every rule change rather than patched in place, because priority
-- numbers, shadow warnings and ordering all shift together and a partial
-- update is how they drift apart.
-- The colour a rail row shows for a rule. A border rule's swatch has to read
-- its border colour: rule.color on a border rule is whatever the health half
-- happens to hold, which is usually the untouched default.
--
-- Declared ABOVE RebuildRail on purpose -- a local defined after it would not
-- be in scope inside it, and the call would silently resolve to a nil global.
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
  for _, f in ipairs(railPool.rows) do f:Hide() end
  for _, f in ipairs(railPool.headerBGs) do f:Hide() end
  for _, f in ipairs(railPool.twisties) do f:Hide() end
  for _, f in ipairs(railPool.adds) do f:Hide() end
  for _, f in ipairs(railPool.switches) do f:Hide() end
  for _, f in ipairs(railPool.dividers) do f:Hide() end
  local nHeader, nItem, nRow = 0, 0, 0
  local nHeaderBG, nTwisty, nAdd, nSwitch, nDivider = 0, 0, 0, 0, 0

  -- Emptied rather than replaced: the drag handlers hold references to these
  -- exact tables. Groups are re-created below as each section is laid out.
  for group in pairs(railRows) do
    wipe(railRows[group])
    railRowCount[group] = 0
  end
  local line = RailIndicator()
  if line then line:Hide() end

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

    -- Collapsed by the twisty on the Color Rules row above (entry.collapse).
    elseif entry.ruleList and RailOpen(entry.ruleList) then
      local kind = entry.ruleList
      local list = RuleListFor(kind)
      local shadowed = NS.ShadowedRules and NS.ShadowedRules(list) or {}

      -- Split by debuff count, preserving the stored order within each half.
      -- Combos first, then singles, with a divider between them -- the two
      -- groups no longer carry headings of their own, so the "New combo rule"
      -- and "New single rule" rows that close each group are what name them.
      -- That is the whole reason the add rows are labelled rather than plain.
      local combos, singles, blockerOf = {}, {}, {}
      for index, rule in ipairs(list) do
        local count = #(rule.conditions or {})
        -- Purely the debuff count. A rule is not created as one kind or the
        -- other any more -- add a second debuff and it moves down here by
        -- itself, which is the behaviour the single creation row implies.
        local isCombo = count >= 2
        table.insert(isCombo and combos or singles, rule)
        blockerOf[rule] = shadowed[index]
      end

      for groupIndex, section in ipairs({
        { rules = combos,  tag = "combo"  },
        { rules = singles, tag = "single" },
      }) do
        local groupKey = kind .. "|" .. section.tag
        railRows[groupKey] = railRows[groupKey] or {}
        wipe(railRows[groupKey])
        railRowCount[groupKey] = 0

        -- A hairline between the two halves, standing in for the headings
        -- they used to have. Only when BOTH have something in them: with one
        -- half empty it is a rule dividing a list from nothing, which reads as
        -- a mistake rather than as structure.
        if groupIndex == 2 and #combos > 0 and #singles > 0 then
          y = y - 4
          nDivider = nDivider + 1
          local divider = railPool.dividers[nDivider]
          if not divider then
            divider = content:CreateTexture(nil, "ARTWORK")
            railPool.dividers[nDivider] = divider
          end
          divider:ClearAllPoints()
          divider:SetPoint("TOPLEFT", content, "TOPLEFT", RULE_ROW_INDENT + 4, y)
          divider:SetPoint("TOPRIGHT", content, "TOPRIGHT", -12, y)
          divider:SetHeight(1)
          divider:SetColorTexture(0.35, 0.35, 0.40, 0.6)
          divider:Show()
          y = y - 6
        end

        for index, rule in ipairs(section.rules) do
          nRow = nRow + 1
          local row = railPool.rows[nRow]
          if not row then
            row = RuleRow(content)
            railPool.rows[nRow] = row
          end

          row.rule = rule
          row.kind = kind
          row.group = groupKey
          row.index = index
          row.groupRules = section.rules
          row.combos = combos
          row.singles = singles
          -- Selecting a rule opens the editor page, not the list page it
          -- came from: the rail row IS that rule.
          row.page = PAGE_RULE
          row.list = list

          local colour = RuleSwatchColor(rule, kind)
          row.swatch:SetColorTexture(colour.r, colour.g, colour.b, 1)
          -- Kept in full for the tooltip: the label itself is truncated.
          row.fullLabel = RuleLabel(rule)
          row.label:SetText(row.fullLabel)
          row:SetAlpha(rule.enabled == false and 0.45 or 1)

          local blocker = blockerOf[rule]
          row.dead:SetShown(blocker ~= nil)
          row.blockedBy = blocker

          -- One level in from the page link that owns the list.
          row:ClearAllPoints()
          row:SetPoint("TOPLEFT", RULE_ROW_INDENT, y)
          row:SetPoint("TOPRIGHT", -8, y)
          row:SetSelected(expandedRule == rule)
          row:Show()

          railRowCount[groupKey] = railRowCount[groupKey] + 1
          railRows[groupKey][railRowCount[groupKey]] = row

          y = y - 22
        end

      end

      -- ONE creation row for the whole list, after both halves.
      --
      -- There used to be two, because a rule's shape was fixed when you made
      -- it: the combo row set wantsCombo, which was the only thing that gave a
      -- rule a second condition slot. A rule now just grows -- add a second
      -- debuff and it re-sorts into the combo half on its own -- so a choice
      -- at creation time would be asking for something the rule no longer has
      -- to decide up front.
      nAdd = nAdd + 1
      local addRow = railPool.adds[nAdd]
      if not addRow then
        addRow = AddRuleRow(content)
        railPool.adds[nAdd] = addRow
      end
      addRow:SetTint(SECTION_TINT.single)
      addRow.label:SetText("NEW RULE")
      Tip(addRow, "New Rule", TIPS.addRule)
      addRow:SetScript("OnClick", function()
        -- Which normaliser depends on which list this is. NS.NormaliseRule
        -- leaves barEnabled=true and border.enabled=false -- correct for a bar
        -- rule, but the opposite of what a border rule needs. Getting this
        -- wrong doesn't error: the rule is created, just shaped like a bar
        -- rule, so it silently tries to paint a tint and never draws a border
        -- -- until the next /reload, whose DB migration force-normalises every
        -- entry in borderRules and fixes it retroactively. That "fixed by
        -- reload, nothing else" signature is what this bug looked like.
        local rule = (kind == "border") and NS.NewBorderRule()
          or NS.NormaliseRule({ color = NS.DefaultColor(), conditions = {}, enabled = true })
        table.insert(list, rule)
        expandedRule = rule
        expandedSection = "rule"
        SelectTab(PAGE_RULE)
        Structural()
      end)
      addRow:ClearAllPoints()
      addRow:SetPoint("TOPLEFT", RULE_ROW_INDENT, y)
      addRow:SetPoint("TOPRIGHT", -8, y)
      addRow:Show()
      y = y - 20

      y = y - 6

    elseif entry.ruleList then
      -- Collapsed: contributes no rows and no height. Caught here rather than
      -- falling through to the item branch below, which would read
      -- entry.label (nil) and index tabButtons with a nil page.

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
      item:SetSubheader(entry.collapse ~= nil)
      item:SetHeight(entry.collapse and 26 or 24)

      -- The twisty toggles the list; the rest of the row still navigates to
      -- the page. Separating them is what lets you collapse a long rule list
      -- without being taken somewhere, and open a page without being forced
      -- to expand.
      if entry.collapse then
        local kind = entry.collapse
        nTwisty = nTwisty + 1
        local twisty = railPool.twisties[nTwisty]
        if not twisty then
          twisty = Twisty(content, function() end)
          railPool.twisties[nTwisty] = twisty
        end
        twisty:SetScript("OnClick", function()
          NS.db.uiRailOpen = NS.db.uiRailOpen or {}
          NS.db.uiRailOpen[kind] = not RailOpen(kind)
          RebuildRail()
        end)
        twisty:SetOpen(RailOpen(kind))
        twisty:ClearAllPoints()
        twisty:SetPoint("LEFT", item, "LEFT", 4, 0)
        twisty:SetFrameLevel(item:GetFrameLevel() + 2)
        twisty:Show()
      end
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

      y = y - (entry.collapse and 26 or 24)
    end
    first = false
  end

  local contentHeight = math.max(1, -y + 8)
  content:SetHeight(contentHeight)

  -- Grow the window to fit the rail, unless the user has chosen a height.
  --
  -- The rail's length is not a fixed thing to design a window around: it is
  -- however many rules you have, plus whichever sections you left open. A
  -- default height picked once can only be right for one of those. So it is
  -- computed from what the rail actually contains, and stops the moment
  -- someone drags the resize grip -- their choice outranks this.
  --
  -- Only ever GROWS to fit. Shrinking to hug a short rail would fight the
  -- right-hand page, which usually wants more room than the rail does.
  if not (NS.db.uiSize and NS.db.uiSize.height) then
    -- 52 above the rail for the title bar, 30 below it for the footer.
    local wanted = math.min(WINDOW_MAX_H, math.max(WINDOW_MIN_H, contentHeight + 82))
    if wanted > window:GetHeight() then
      window:SetHeight(wanted)
    end
  end

  if window.railBar then window.railBar:Update() end
end

-- Repaints the rail's swatches from the rules themselves.
--
-- Called from the colour pickers, which fire on every frame of a drag -- far
-- too often for a full RebuildRail, and unnecessary: the row already knows
-- which rule it is showing, so only the texture is stale.
-- Repaints every swatch that already exists for the CURRENT rule set --
-- rail rows and the flat table's rows alike -- without going through
-- Structural(), which is overkill for a colour that changed nothing about
-- what gets built. A colour picker calls this on every drag frame, so a full
-- rebuild here would be the stutter Structural() itself exists to avoid.
--
-- Named for the rail originally, when the rail was the only place a rule's
-- swatch appeared live; the table's own swatch had a bug that hid the need
-- for this until the colour it read was fixed to be the right one at all.
local function RefreshRailColors()
  for _, row in ipairs(railPool.rows) do
    if row.rule and row:IsShown() then
      local colour = RuleSwatchColor(row.rule, row.kind)
      row.swatch:SetColorTexture(colour.r, colour.g, colour.b, 1)
    end
  end
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
-- plate beside them. Top-aligning them left the group floating against the
-- plate's top edge with all the slack underneath; centring reads as two
-- halves of one row.
--
-- The column is exactly as tall as its page's stage, and the offset is read
-- from the frame rather than from the constant -- the Aura Icons pages build
-- a taller one (ICON_STAGE_H).
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

-- Fixed head (module toggle + preview) with a scrolling body beneath it.
-- enableLabel nil = no module toggle on this page. The Global Settings pages
-- are not modules -- there is nothing to switch on or off at the page level, only
-- individual settings inside them -- but they still want the preview stage,
-- since every one of them changes how the bar is drawn and you should be able
-- to see that while you change it.
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

  -- Pages call this with the height their content needs; the section adds its
  -- own header and padding, exactly as it does for every other section, and
  -- collapsing is the section's own behaviour rather than a special case.
  -- Re-anchors the scrolling body directly under the preview section, whatever
  -- height that section currently has.
  --
  -- Driven by the section's own resize notification, NOT only by SetHeadHeight.
  -- Collapsing the preview fires Resize without any page code running, and
  -- Options_RebuildAll does not refresh previews -- so on every page whose
  -- rebuild did not happen to call RefreshPreview, collapsing left the body
  -- anchored at the open height: a page-sized hole above the first section.
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

-- The preview is a pure simulation of the rule logic. It never touches an
-- aura container and never asks the game anything: it answers "given exactly
-- these debuffs, which rule wins" using the same ordering the engine uses.
--
-- It used to disagree with live plates for one reason: preview.active was
-- never pruned. A tick for a spell that later left every rule -- most easily
-- by having its ID corrected from a cast ID to the aura's -- stayed set
-- forever. So "is anything ticked" answered yes when nothing was visibly
-- ticked, and a rule could match on a debuff that had no checkbox on screen.
-- Pruning first makes what is on screen the whole state.
local function PrunedPreviewState()
  -- BOTH lists. preview.active is shared by the health tab, the border tab
  -- and test mode, so pruning against health rules alone deleted any debuff
  -- only a border rule used -- the tick vanished the moment the health
  -- preview refreshed.
  local valid = {}
  for _, list in ipairs({ NS.db.tints.rules or {}, NS.db.tints.borderRules or {} }) do
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

  -- GetOrderedRules is exactly what Tints.lua builds from, so preview
  -- priority and plate priority cannot drift apart.
  --
  -- Missing rules are excluded. They never paint the bar body, so they cannot
  -- win or lose the "which rule colours the bar" question this answers -- and
  -- letting one place first would report a winner whose colour is nowhere on
  -- the bar. They preview on their own editor page instead.
  local matches = {}
  for _, rule in ipairs(NS.GetOrderedRules()) do
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
  local sources = { NS.db.tints.rules }
  if NS.db.uiPreviewCombine then
    table.insert(sources, NS.db.tints.borderRules)
  end
  for _, src in ipairs(sources) do
  for _, rule in ipairs(src) do
    for _, c in ipairs(rule.conditions or {}) do
      if not seen[c.spellID] then seen[c.spellID] = true; table.insert(list, c.spellID) end
    end
  end
  end
  return list
end

-- Style block for the expanded rule: which halves of the plate this rule
-- paints. Built once and repositioned, because only one rule is ever open.
--
-- Lives in the Edit panel rather than the row: thickness needs a slider and
-- the row is already six columns wide. The row shows two swatches so you can
-- still tell at a glance which halves a rule uses.
-- Re-checks every rig's target/focus gating without touching any container's
-- unit binding or rebuilding anything -- cheap enough to run straight from a
-- checkbox click rather than routing through the Live/Restyle/Structural
-- queue built for things that touch the world.
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

-- Everything about how a rule LOOKS, as opposed to what it requires: colour,
-- fill style and texture, target/focus gating, border shape. Lives behind
-- its own "Edit Color/Appearance" button on the row now rather than sharing space
-- with the debuff list -- the two were getting crowded together, and neither
-- needs the other open to be useful.
--
-- isBorder picks which extra controls this instance shows: border shape for
-- the border list, fill/texture for the bar list. Show-on-target/focus and
-- the colour swatch apply to both -- either list can have a rule you don't
-- want fighting your own target or focus selection glow, and both lists
-- still have exactly one colour per rule.
-- Adding a debuff to a rule, shared by the rule tables and the rule editor.
--
-- Was a local inside BuildHealthTab, which meant the editor could not reach
-- it -- and a second copy would have been a second place for the cost warning
-- and the duplicate/limit checks to drift.
local function RuleConditionLimit(rule)
  if not rule then return 1 end
  -- A missing rule is single-debuff and cannot be raised. Its rank in the
  -- ladder already spends a chain level on every rule above it plus one on its
  -- own debuff, and a second condition would need another interleaved into a
  -- sublevel budget with no room for it (see Tints.lua).
  if rule.showWhenMissing then return NS.MAX_MISSING_CONDITIONS or 1 end
  -- Every other rule gets the full allowance.
  --
  -- This used to gate a rule to ONE debuff unless it carried `wantsCombo`, set
  -- by whichever rail row created it. That flag existed because a rule's shape
  -- was fixed at creation time; with one creation row there is nothing to
  -- remember -- a rule simply grows, and re-sorts into the combo half of the
  -- rail once it reaches two. `wantsCombo` may still sit in saved profiles and
  -- is now ignored everywhere.
  return NS.MAX_RULE_CONDITIONS
end

local function AddConditionTo(rule, input, sortList)
  if not rule or not input then return end
  local spellID = ResolveAndReport(input)
  if not spellID then return end
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

  -- No cost warning here any more.
  --
  -- There used to be one, because a second debuff multiplied a rule's textures
  -- by ten: containers pooled ten buttons each and the rule had to cover every
  -- pairing. The engine uses aura SLOTS now, which pool one -- a combo rule
  -- costs one texture and one extra frame, the same as any other rule. A
  -- dialog interrupting someone to warn about a cost that no longer exists is
  -- worse than no dialog at all.
  Commit()
end

-- `part` selects which half gets built:
--   "all"         both halves, each under its own small heading
--   "appearance"  colour, fill, texture, border shape
--   "visibility"  the target/focus gating
--
-- The rule editor asks for the split forms because each half is its own
-- collapsible section there, and a section headed "Appearance" whose first
-- line reads APPEARANCE says it twice.
--
-- Both halves are always CREATED and merely hidden, so p.Refresh never has to
-- ask which widgets this instance happens to have.
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
    -- Non-border needs room for a THREE-line wrap on the texture-conflict
    -- warning at typical window width, plus the missing-health cover row
    -- below it, not just the two rows above it.
    -- Tall enough for the missing-health colour row beneath its checkbox. That
    -- row hides when the rule is not covering missing health, but the panel
    -- keeps the height either way: a panel that changes size as you tick a box
    -- shoves every rule below it up and down the list.
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
  -- that colour means -- "the bar looks like this" versus "you still owe this
  -- debuff". Everything below it still applies either way: a missing rule
  -- washes the bar exactly as a presence rule does, with the same fill style
  -- and texture, just on the opposite condition.
  --
  -- Bar rules only. A border rule paints an edge rather than the bar, and its
  -- cover would have nothing to restore -- occlusion needs a surface it can
  -- repaint, which is the bar itself.
  if not isBorder then
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

    -- Opacity advisory, in the gap under the fill row. A presence tint fires
    -- occasionally; a missing tint is lit BY DEFAULT on every mob you have not
    -- touched, so the same alpha reads completely differently. Advisory only
    -- -- the colour is never changed for you.
    p.missingAlphaWarn = ap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    StyleText(p.missingAlphaWarn, 11, "NONE")
    p.missingAlphaWarn:SetPoint("TOPLEFT", 14, -160)
    p.missingAlphaWarn:SetPoint("TOPRIGHT", -14, -160)
    p.missingAlphaWarn:SetJustifyH("LEFT")
    p.missingAlphaWarn:SetWordWrap(true)
    p.missingAlphaWarn:SetTextColor(1, 0.55, 0.15)
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
        -- Switching a rule to Texture Overlay for the first time lands it on
        -- an actual pattern rather than on "Bar's own art", which is the nil
        -- entry and therefore what an untouched rule would otherwise show --
        -- i.e. picking Texture Overlay would appear to do nothing at all.
        --
        -- Guarded by fillTexturePicked, not by "is fillTexture nil": nil is a
        -- legitimate choice (Bar's own art), so without the flag anyone who
        -- deliberately picked it would have it silently replaced every time
        -- they toggled fill style.
        if v == "texture" and not r.fillTexturePicked and r.fillTexture == nil then
          r.fillTexture = "stripes-spread"
        end
        Live()
        NS.Options_RebuildAll()
      end
    end)
    p.fillStyle:SetPoint("TOPLEFT", 60, -56)
    Tip(p.fillStyle, "Fill", TIPS.fillStyle)

    -- Two pickers sharing one slot, one per fill style, because the two
    -- overlays take completely different art: Texture Overlay tiles a pattern
    -- from the bundled library, Solid Overlay stretches a bar texture from
    -- LibSharedMedia. Only the one matching the current style is shown (see
    -- p.Refresh) -- a single combined list would offer every rule a pile of
    -- choices that do nothing in its current mode.
    --
    -- Separate rule fields too (fillTexture / barTexture), so switching style
    -- back and forth keeps both selections instead of clobbering whichever
    -- one is currently out of view.
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

    -- OUTLINE rather than the plain font every other label here uses: this
    -- is the one warning in the panel that needs to read as urgent rather
    -- than informational, since it is telling you about a conflict you will
    -- not see coming from inside this addon at all -- it shows up as visual
    -- noise on your nameplate art, sourced from a completely different
    -- addon, with nothing here to point at the cause.
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

    -- The colour, directly under the checkbox that turns it on -- the moment
    -- you decide you want this is the moment you want to pick the colour, and
    -- it used to be somewhere else entirely.
    --
    -- Shown only while this rule uses the option (see p.Refresh), because it
    -- is not a per-rule setting: every rule that covers missing health shares
    -- one colour, and the same swatch appears on Global Settings > Effects. Both
    -- edit the same value, so the label has to say so or this reads as a rule
    -- setting that mysteriously changes the other rules too.
    -- Laid out as a ROW, matching the tick box above it: control first at the
    -- same x, then its name, then the aside. The swatch is now exactly a tick
    -- box's size (see ColorSwatch), so the two left edges genuinely line up
    -- rather than nearly doing so.
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
    -- This whole block sits 20px lower than it used to (-38/-66 -> -58/-86).
    -- At the old offset "Border shape" started only 12px under the Color
    -- row above it -- both DIm() labels at the same x=14, 11pt font -- and the
    -- two lines rendered on top of each other. Every other second-row label in
    -- this panel (Fill, on the non-border side) keeps a 32px gap under Color;
    -- this now matches that.
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
      -- up to be refused on click. A missing rule is single-debuff by
      -- construction (NS.MAX_MISSING_CONDITIONS), so on a combo rule this
      -- control has exactly one reachable value -- and a dropdown whose other
      -- option always errors is worse than no dropdown.
      --
      -- Safe to hide: NS.NormaliseRule clears showWhenMissing on anything with
      -- too many conditions, so the control can never be hidden while holding
      -- the value it is hiding.
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

      -- "In combat" is a property of the whole missing LADDER, not of one rule
      -- (see NS.LadderCombatAllows in Tints.lua): only one missing wash is ever
      -- lit, and which one depends on aura state the addon is not allowed to
      -- read, so the gate cannot be resolved per rule. It engages only when
      -- every missing rule asks for it -- and a half-ticked set therefore does
      -- nothing at all, which is invisible unless it is said here.
      if isMissing and combatShown then
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

      p.missingAlphaWarn:SetShown(#notes > 0)
      if #notes > 0 then
        p.missingAlphaWarn:SetText(table.concat(notes, "\n\n"))
      end
    end
    if p.fillStyle then
      p.fillStyle.Refresh()
      -- Exactly one texture picker is up at a time, chosen by fill style:
      -- patterns for Texture Overlay, LibSharedMedia bar textures for Solid
      -- Overlay. Both live in the same slot, so showing both would stack them
      -- on top of each other.
      --
      -- The conflict warning stays tied to texture mode alone. A stretched
      -- bar texture is what the nameplate addon was already drawing there, so
      -- it does not collide with their art the way a tiled pattern overlay
      -- does -- warning about it in solid mode would be crying wolf.
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
      -- Rides with the texture warning: both belong to Texture Overlay and
      -- neither has anything to say about a flat fill.
      --
      -- Never on a missing rule. Its wash is anchored to the FILL, and so is
      -- the cover that hides it -- so a texture painted on the UNFILLED side
      -- would have nothing to hide it and would sit there permanently, which
      -- is the one thing a missing rule must not do.
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
local function BuildRuleRow(parent, getList, isBorder)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(690, ROW_H)
  row:EnableMouse(true)

  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, 0.03)

  -- The grip, then the rule's colour, then its name. UP/DOWN buttons and the
  -- type-a-number priority box are gone: position is set by dragging now, and
  -- three ways to express one ordering was two too many.
  row.grip = CreateFrame("Frame", nil, row)
  row.grip:SetSize(14, 14)
  row.grip:SetPoint("LEFT", 10, 0)
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

  row.swatch = row:CreateTexture(nil, "ARTWORK")
  row.swatch:SetSize(12, 12)
  row.swatch:SetPoint("LEFT", 32, 0)

  row.summary = Label(row, "")
  row.summary:SetPoint("LEFT", 52, 0)
  row.summary:SetWidth(300)
  row.summary:SetJustifyH("LEFT")
  row.summary:SetWordWrap(false)

  -- One button. Conditions and appearance both live on the rule's own page
  -- now, so the old pair of expanders had nothing left to expand.
  row.edit = Button(row, "Edit", 70, function()
    expandedRule = row.rule
    expandedSection = "rule"
    EnsureRulePreview()
    SelectTab(PAGE_RULE)
    NS.Options_RebuildAll()
  end)
  row.edit:SetPoint("LEFT", 470, 0)
  StyleText(row.edit.label, 11)

  -- A tick box, not a switch: switches are reserved for turning a whole
  -- MODULE on and off. One rule among several is a setting.
  row.enabled = Checkbox(row,
    function() return row.rule and row.rule.enabled ~= false end,
    function(v) if row.rule then row.rule.enabled = v; Structural() end end)
  row.enabled:SetPoint("LEFT", 600, 0)

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
  row.remove:SetPoint("LEFT", 556, 0)

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
    end
    if self.moved then ShowDropLine(self) end
  end)

  return row
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

  -- Preview-only, and shared with the border tab: someone running both wants
  -- to see how the two look together, not each in isolation.
  -- A button in the same column and the same format as the two test buttons,
  -- because it belongs to the same group of preview-and-test actions -- a
  -- lone checkbox hanging under them read as a different class of control.
  -- Shows the OTHER colouring module's rules on top of this one's, so you can
  -- judge how they look together. Named for what it adds, and hidden entirely
  -- when that module is switched off -- offering to overlay rules that cannot
  -- draw would be a button that does nothing.
  head.combine = Button(head.testColumn, "", 150, function()
    NS.db.uiPreviewCombine = not NS.db.uiPreviewCombine
    if head.combine.Refresh then head.combine.Refresh() end
    RefreshPreviews()
  end)
  head.combine.Refresh = function()
    local available = MODULE_SWITCH["border"].get()
    head.combine:SetShown(available)
    local on = available and NS.db.uiPreviewCombine and true or false
    head.combine:SetText(on and "Hide Border Rules" or "Show Border Rules")
    if on then
      head.combine.label:SetTextColor(1, 0.82, 0.1)
    else
      head.combine.label:SetTextColor(1, 1, 1)
    end
    -- Re-centre: this button appearing or vanishing changes the group size.
    if head.RestackTests then head.RestackTests() end
  end
  -- In the column beside the plate: actions on your real nameplates, grouped
  -- apart from the preview they sit next to.
  head.testButton = TestModeButton(head.testColumn, false)
  head.testAllButton = TestModeButton(head.testColumn, true)
  head.RestackTests = function()
    StackTestButtons(head.testColumn, { head.testButton, head.testAllButton, head.combine })
  end
  head.combine.Refresh()
  head.combineLabel = Dim(head, "")

  local body = panel.body
  body.sections = {}

  local rules = CollapsibleSection(body, "colourRules", "Color Rules",
    "higher rules override lower ones - the topmost match is what you see")
  table.insert(body.sections, rules)
  body.rules = rules

  local c = rules.content
  -- Centred over the whole UP / number / DOWN cluster (x 8 to 108) rather
  -- than left-aligned to its first pixel, which read as a label for the UP
  -- button alone.
  -- Headers sit over the columns the rebuilt row actually has. "Order"
  -- rather than "Priority" because the number is gone -- position in the
  -- list IS the priority, and you set it by dragging.
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

  -- One shared colour for every rule's "Cover missing health", below the
  -- table and behind a rule of its own -- it belongs to the list as a whole
  -- rather than to any single rule, and the divider is what says so.
  --
  -- The same swatch also sits under the checkbox in each rule's appearance
  -- panel, where the decision to switch it on gets made. Both edit one value.
  -- Built only for the health list: border rules paint no bar, so they can
  -- never use the option at all.
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

  -- Shared by the dropdown and the ID box below. The Cooldown Manager cannot
  -- offer every usable ID — an ability whose aura is a separate spell (Rend
  -- casts 772 and applies 388539) has no CDM entry for the aura at all — so
  -- typing one in has to be a first-class way to build a rule, exactly as it
  -- already is on the icon tab.
  -- `input` is a spell ID from the dropdown or raw text from the box; both
  -- are resolved to the aura's own ID before anything else looks at them, so
  -- the duplicate check below compares what will actually be stored.
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
    if headFrame.combine then headFrame.combine.Refresh() end
    if headFrame.enable then headFrame.enable.Refresh() end

    local stage = headFrame.stage

    -- The missing wash, drawn whether or not a presence rule matches -- it is
    -- lit precisely when you have not applied something, so "nothing matched"
    -- is its normal state rather than an edge case.
    --
    -- Safe to show here now that presence tints draw ABOVE it (see ruleBase in
    -- NS.BuildTints). While it sat on top this washed over whatever tint you
    -- were trying to look at, which is why it was pulled; the layering change
    -- is what makes it previewable.
    local missingRule = PreviewMissingRule()
    if missingRule then
      NS.ApplyRuleFill(stage.missingWash, stage.bar, missingRule)
      stage.missingWash:Show()
    else
      stage.missingWash:Hide()
    end
    if #spells == 0 then
      headFrame.verdict:SetText("|cff808080Add a rule below and it will be previewed here.|r")
      headFrame.togglesLabel:Hide()
      stage.tint:Hide()
      stage.missingCover:Hide()
      for _, e in ipairs(stage.borderEdges) do e:Hide() end
    else
      headFrame.togglesLabel:Show()
      local winner, matches, ticked = EvaluatePreview()

      -- Show the edge inset, but against the BAR rather than the fill: the
      -- point is to see how much border the inset leaves, and tying it to a
      -- 72%-wide fill made the preview shrink for reasons unrelated to rules.
      local inset = NS.FillInset and NS.FillInset() or 1
      stage.tint:ClearAllPoints()
      local fill = stage.bar:GetStatusBarTexture()
      stage.tint:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
      stage.tint:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -inset, inset)

      if winner then
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
        -- The border shown here is whatever the BORDER list would draw, not
        -- anything from this rule: the two lists are independent.
        DrawStageBorder(stage, NS.db.uiPreviewCombine
          and PreviewWinner(NS.db.tints.borderRules) or nil)
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
        stage.missingCover:Hide()
        DrawStageBorder(stage, NS.db.uiPreviewCombine
          and PreviewWinner(NS.db.tints.borderRules) or nil)
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

          local missing
          for _, rule in ipairs(NS.GetOrderedRules()) do
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
    panel:SetHeadHeight(6 + STAGE_H + 32 + rows * 26)
  end
end

-- Renders ONE rule list into ONE section. Both the bar list and the border
-- list go through here, so their behaviour -- pooling, expansion, the add
-- row, warnings -- cannot drift apart.
local function RenderRuleSection(sec, list, rowPool, condPool, isBorder, getList, messages, targetAuras)
  local expandedHere = false
    -- Sits above the rows, under the column headers. Only on the health list:
    -- borders draw outside the bar and cover nothing.
    if sec.note then
      sec.note:ClearAllPoints()
      sec.note:SetPoint("TOPLEFT", 12, -26)
      sec.note:SetPoint("TOPRIGHT", -12, -26)
      sec.note:Show()
    end

    local y = sec.note and -56 or -28
    local cursor, condsShown, appearanceShown = 0, false, false

    -- Emptied rather than replaced: the drag handlers hold a reference to
    -- these exact tables, same as the rail's.
    local listKey = isBorder and "border" or "health"
    pageRows[listKey] = pageRows[listKey] or {}
    wipe(pageRows[listKey])
    pageRowCount[listKey] = 0

    for index, rule in ipairs(list) do
      local row = rowPool[index]
      if not row then row = BuildRuleRow(sec.content, getList, isBorder); rowPool[index] = row end
      row:SetParent(sec.content)
      row.index, row.rule = index, rule
      row.listKey = listKey
      pageRowCount[listKey] = pageRowCount[listKey] + 1
      pageRows[listKey][pageRowCount[listKey]] = row
      row.summary:SetText(NS.RuleSummary(rule))
      row.enabled.Refresh()
      -- RuleSwatchColor, not a bare rule.color: a border rule's editable
      -- colour lives at rule.border.color, and rule.color is a leftover
      -- unused field on it (NS.NormaliseBorderRule sets it but nothing ever
      -- writes to it again). Reading it directly meant every border rule's
      -- row showed the default pink forever, regardless of what its border
      -- colour actually was -- the swatch, and the swatch alone, was wrong.
      local colour = RuleSwatchColor(rule, listKey)
      row.swatch:SetColorTexture(colour.r, colour.g, colour.b, 1)
      -- Always false now. Editing happens on the rule's own page, so this
      -- table never expands -- and because the flag is computed here rather
      -- than stored, anyone whose table was left stuck open by the old
      -- expanders gets it closed the first time this runs, with nothing to
      -- clear and no migration needed.
      local openRule = false
      row.stripe:SetShown(index % 2 == 0)
      row:SetPoint("TOPLEFT", 0, y)
      row:Show()
      y = y - ROW_H - 2
  
      if openRule and expandedSection == "rule" then
        for ci, condition in ipairs(rule.conditions) do
          cursor = cursor + 1
          local cr = condPool[cursor]
          if not cr then cr = BuildConditionRow(sec.content); condPool[cursor] = cr end
          cr:SetParent(sec.content)
          cr.rule, cr.condition, cr.conditionIndex = rule, condition, ci
          cr.icon:SetTexture(NS.SpellIcon(condition.spellID))
          cr.name:SetText(("%s%s |cff808080(%d)|r"):format(
            targetAuras[condition.spellID] and "" or "|cffff4040!|r ",
            NS.SpellName(condition.spellID), condition.spellID))
          cr:SetPoint("TOPLEFT", 0, y)
          cr:Show()
          y = y - 24
        end
        sec.addCondDrop:ClearAllPoints()
        sec.addCondDrop:SetPoint("TOPLEFT", 144, y - 2)
        sec.addCondDrop:Show()

        -- Pooled rows accumulate anchors, so every repositioned widget clears
        -- first: pooled rows otherwise accumulate anchors across refreshes.
        sec.addCondBoxLabel:ClearAllPoints()
        sec.addCondBoxLabel:SetPoint("LEFT", sec.addCondDrop, "RIGHT", 10, 0)
        sec.addCondBoxLabel:Show()
        sec.addCondBox:ClearAllPoints()
        sec.addCondBox:SetPoint("LEFT", sec.addCondBoxLabel, "RIGHT", 8, 0)
        sec.addCondBox:Show()
        y = y - 34

        condsShown = true
      elseif openRule and expandedSection == "appearance" then
        if sec.style then
          sec.style:ClearAllPoints()
          sec.style:SetPoint("TOPLEFT", 8, y - 6)
          sec.style:SetPoint("TOPRIGHT", -8, y - 6)
          sec.style.Refresh()
          sec.style:Show()
          y = y - sec.style:GetHeight() - 10
        end

        appearanceShown = true
      end
    end

    if not condsShown then
      sec.addCondDrop:Hide()
      sec.addCondBox:Hide()
      sec.addCondBoxLabel:Hide()
    end
    if not appearanceShown and sec.style then
      sec.style:Hide()
    end
  
    if #messages > 0 then
      sec.warning:SetText(table.concat(messages, "\n"))
      sec.warning:ClearAllPoints()
      sec.warning:SetPoint("TOPLEFT", 12, y - 6)
      sec.warning:Show()
      y = y - 32
    else
      sec.warning:Hide()
    end
  
    -- Anchored to each other, not to hardcoded x positions. The two lists
    -- have different button widths ("New Rule" vs "New Border Rule"), so a
    -- fixed 118 was correct for one and overlapping for the other.
    sec.newButton:ClearAllPoints()
    sec.newButton:SetPoint("TOPLEFT", 10, y - 8)
    sec.sortButton:ClearAllPoints()
    sec.sortButton:SetPoint("LEFT", sec.newButton, "RIGHT", 8, 0)

    local bottom = y - 8 - 26 -- below the New Rule / Auto sort row

    -- Missing-health colour, under the buttons and behind a divider. Built
    -- only on the health table (the border table never creates these), and
    -- shown only once some rule here actually covers missing health --
    -- otherwise it is a control for something nothing on screen uses. Each
    -- rule's appearance panel carries the same swatch, so it stays reachable
    -- either way.
    if sec.missingDivider then
      local anyCovering = false
      for _, rule in ipairs(list) do
        if rule.missingCover then anyCovering = true break end
      end

      sec.missingDivider:SetShown(anyCovering)
      sec.missingLabel:SetShown(anyCovering)
      sec.missingSwatch:SetShown(anyCovering)
      sec.missingHint:SetShown(anyCovering)

      if anyCovering then
        sec.missingDivider:ClearAllPoints()
        sec.missingDivider:SetPoint("TOPLEFT", 10, bottom - 10)
        sec.missingDivider:SetPoint("TOPRIGHT", -10, bottom - 10)

        sec.missingLabel:ClearAllPoints()
        sec.missingLabel:SetPoint("TOPLEFT", 12, bottom - 28)

        sec.missingSwatch:ClearAllPoints()
        sec.missingSwatch:SetPoint("LEFT", sec.missingLabel, "RIGHT", 10, 2)
        sec.missingSwatch:Refresh()

        sec.missingHint:ClearAllPoints()
        sec.missingHint:SetPoint("LEFT", sec.missingSwatch, "RIGHT", 10, -2)

        bottom = bottom - 50
      end
    end

    sec:Resize(-bottom + 42)
  return expandedHere
end

local borderTab

-- Border colouring, on its own tab. It was a second section under Health
-- Color, which meant anyone using only borders scrolled past a list they
-- never touch. The two are independent features and now read that way.
local function BuildBorderTab()
  -- Same shell as Health Coloring: module toggle, live preview, scrolling body.
  -- The toggle drives the same master switch -- borders and health colouring
  -- are one module -- so turning it off here turns off both, as it should.
  -- Its OWN flag, not the health one: the two are independent modules that
  -- happen to share a rule engine, so turning borders off must leave health
  -- colouring alone.
  -- Enable lives on the rail heading now (see MODULE_SWITCH).
  local panel = BuildTabFrame(tabPanels[2])

  local head = panel.head
  head.verdict = Label(head, "")
  head.verdict:SetPoint("TOPLEFT", HEAD_PAD, -(6 + STAGE_H + 8))
  head.togglesLabel = Dim(head, "")
  head.togglesLabel:SetPoint("TOPLEFT", HEAD_PAD, -(6 + STAGE_H + 30))
  head.toggles = {}

  -- A button in the same column and the same format as the two test buttons,
  -- because it belongs to the same group of preview-and-test actions -- a
  -- lone checkbox hanging under them read as a different class of control.
  -- Shows the OTHER colouring module's rules on top of this one's, so you can
  -- judge how they look together. Named for what it adds, and hidden entirely
  -- when that module is switched off -- offering to overlay rules that cannot
  -- draw would be a button that does nothing.
  head.combine = Button(head.testColumn, "", 150, function()
    NS.db.uiPreviewCombine = not NS.db.uiPreviewCombine
    if head.combine.Refresh then head.combine.Refresh() end
    RefreshPreviews()
  end)
  head.combine.Refresh = function()
    local available = MODULE_SWITCH["health"].get()
    head.combine:SetShown(available)
    local on = available and NS.db.uiPreviewCombine and true or false
    head.combine:SetText(on and "Hide Health Rules" or "Show Health Rules")
    if on then
      head.combine.label:SetTextColor(1, 0.82, 0.1)
    else
      head.combine.label:SetTextColor(1, 1, 1)
    end
    -- Re-centre: this button appearing or vanishing changes the group size.
    if head.RestackTests then head.RestackTests() end
  end
  -- In the column beside the plate: actions on your real nameplates, grouped
  -- apart from the preview they sit next to.
  head.testButton = TestModeButton(head.testColumn, false)
  head.testAllButton = TestModeButton(head.testColumn, true)
  head.RestackTests = function()
    StackTestButtons(head.testColumn, { head.testButton, head.testAllButton, head.combine })
  end
  head.combine.Refresh()
  head.combineLabel = Dim(head, "")
  head.combineLabel:SetPoint("LEFT", head.combine, "RIGHT", 6, 0)

  local body = panel.body
  body.sections = {}

  -----------------------------------------------------------------------------
  -- Border rules: their own list, their own priority.
  --
  -- Separate from the bar list rather than a second half of each rule. Someone
  -- who only wants borders never sees a bar control, and the two stacks order
  -- independently -- the top bar rule and the top border rule both apply.
  -----------------------------------------------------------------------------
  local brules = CollapsibleSection(body, "colourBorders", "Border Rules",
    "draw a coloured border, independent of health colouring")
  table.insert(body.sections, brules)
  body.borderRules = brules

  local bc2 = brules.content
  -- Headers sit over the columns the rebuilt row actually has. "Order"
  -- rather than "Priority" because the number is gone -- position in the
  -- list IS the priority, and you set it by dragging.
  brules.hOrder = Header(bc2, "Order")
  brules.hOrder:SetPoint("TOPLEFT", 8, -6)
  brules.hDebuffs = Header(bc2, "Rule")
  brules.hDebuffs:SetPoint("TOPLEFT", 52, -6)
  brules.hEdit = Header(bc2, "Edit")
  brules.hEdit:SetPoint("TOPLEFT", 470, -6)
  brules.hDelete = Header(bc2, "Del")
  brules.hDelete:SetPoint("TOPLEFT", 556, -6)
  brules.hOn = Header(bc2, "On")
  brules.hOn:SetPoint("TOPLEFT", 600, -6)

  brules.divider = bc2:CreateTexture(nil, "ARTWORK")
  brules.divider:SetPoint("TOPLEFT", 10, -22)
  brules.divider:SetPoint("TOPRIGHT", -10, -22)
  brules.divider:SetHeight(1)
  brules.divider:SetColorTexture(0.4, 0.4, 0.45, 0.6)

  brules.warning = Label(bc2, "")
  brules.warning:SetWidth(650)
  brules.warning:SetJustifyH("LEFT")

  brules.newButton = Button(bc2, "New Border Rule", 130, function()
    local rule = NS.NewBorderRule()
    table.insert(NS.db.tints.borderRules, rule)
    expandedRule = rule
    Structural()
  end)
  brules.sortButton = Button(bc2, "Auto sort", 100, function()
    NS.SortRules(NS.db.tints.borderRules)
    expandedRule = nil
    Structural()
  end)

  local function AddBorderCondition(input)
    local rule = expandedRule
    if not rule or not input then return end
    local spellID = ResolveAndReport(input)
    if not spellID then return end
    for _, cond in ipairs(rule.conditions) do if cond.spellID == spellID then return end end
    -- Through RuleConditionLimit like every other add path. It used to be
    -- MAX_RULE_CONDITIONS directly, because the shared helper gated a bar rule
    -- to one debuff until it was explicitly made a combo and border rules
    -- never had that gate. That gate is gone, so the two now agree -- and a
    -- border rule can never be a missing rule (the Show when control is
    -- bar-only), which is the only case the helper still special-cases.
    local limit = RuleConditionLimit(rule)
    if #rule.conditions >= limit then
      NS.Print(("A rule can require at most %d debuffs."):format(limit))
      return
    end
    table.insert(rule.conditions, { spellID = spellID })
    NS.SortRules(NS.db.tints.borderRules)
    Structural()
  end

  brules.addCondDrop = AddSpellDropdown(bc2, 250, "Add a debuff to this rule...",
    function(spellID)
      local rule = expandedRule
      if not rule then return false end
      for _, cond in ipairs(rule.conditions) do if cond.spellID == spellID then return true end end
      return false
    end,
    AddBorderCondition)
  brules.addCondBox = IDBox(bc2, AddBorderCondition)
  brules.addCondBoxLabel = Dim(bc2, "or ID/name:")

  -- Shape controls, shared shape with the bar list's Edit panel.
  brules.style = BuildStylePanel(bc2, true)
  brules.style:Hide()


  -- The border tab's own preview. Shares preview.active with the health tab,
  -- so ticking a debuff on one shows its effect on both -- they are the same
  -- simulated target seen two ways.
  borderTab = panel
  panel.RefreshPreview = function()
    local headFrame = panel.head
    local stage = headFrame.stage

    -- Checkboxes for every debuff any BORDER rule names.
    local seen, spells = {}, {}
    local sources = { NS.db.tints.borderRules or {} }
    if NS.db.uiPreviewCombine then
      table.insert(sources, NS.db.tints.rules or {})
    end
    for _, src in ipairs(sources) do
      for _, rule in ipairs(src) do
        for _, c in ipairs(rule.conditions or {}) do
          if not seen[c.spellID] then
            seen[c.spellID] = true
            table.insert(spells, c.spellID)
          end
        end
      end
    end

    for _, t in ipairs(headFrame.toggles) do t:Hide() end
    for index, spellID in ipairs(spells) do
      local t = headFrame.toggles[index]
      if not t then
        local box
        box = Checkbox(headFrame,
          function() return box ~= nil and preview.active[box.spellID] and true or false end,
          function(value)
            if box then preview.active[box.spellID] = value; RefreshPreviews() end
          end)
        t = box
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
    if headFrame.combine then headFrame.combine.Refresh() end
    if headFrame.enable then headFrame.enable.Refresh() end

    local barRule = NS.db.uiPreviewCombine and PreviewWinner(NS.db.tints.rules) or nil
    if barRule and barRule.barEnabled ~= false and barRule.color then
      NS.ApplyRuleFill(stage.tint, stage.bar, barRule)
      stage.tint:Show()
      if NS.ApplyMissingCover then
        NS.ApplyMissingCover(stage.missingCover, stage.bar, barRule)
      end
    else
      stage.tint:Hide()
      stage.missingCover:Hide()
    end

    if #spells == 0 then
      headFrame.verdict:SetText("|cff808080Add a border rule below and it will be previewed here.|r")
      headFrame.togglesLabel:Hide()
      for _, e in ipairs(stage.borderEdges) do e:Hide() end
    else
      headFrame.togglesLabel:Show()
      -- Border rules have their own stack, so the winner is found among them
      -- alone -- a health rule matching changes nothing here.
      local winner
      for _, rule in ipairs(NS.GetOrderedBorderRules()) do
        local all = true
        for _, c in ipairs(rule.conditions) do
          if not preview.active[c.spellID] then all = false break end
        end
        if all then winner = rule break end
      end

      DrawStageBorder(stage, winner)
      if winner then
        headFrame.verdict:SetText(("Winning border rule: |cff55dd55%s|r")
          :format(NS.RuleSummary(winner)))
      else
        local ticked = 0
        for _, on in pairs(preview.active) do if on then ticked = ticked + 1 end end
        headFrame.verdict:SetText(ticked == 0
          and "|cffffcc00Tick a debuff below to preview a border rule.|r"
          or "|cff808080No border rule requires exactly those debuffs.|r")
      end
    end

    -- Measured, not padded. The toggles start at STAGE_H + 28 and step 26, so
    -- the last row's bottom is exactly this -- the old constant reserved a
    -- row's worth of space that nothing ever occupied, and with no rules at
    -- all (rows = 0) it reserved a whole row for a verdict line alone.
    local rows = math.ceil(#spells / 3)
    panel:SetHeadHeight(6 + STAGE_H + 32 + rows * 26)
  end

  return panel
end

local function RebuildBorderTab()
  local panel = borderTab
  if not panel then return end
  for _, r in ipairs(borderRows) do r:Hide() end
  for _, r in ipairs(borderCondRows) do r:Hide() end

  -- Same as the health tab. This is what recomputes the head height from the
  -- number of debuff toggles; without it the border page's preview kept
  -- whatever height it was last given, which after adding or removing a rule
  -- was the wrong one.
  if panel.RefreshPreview then panel.RefreshPreview() end

  local targetAuras = NS.GetTargetAuraSet()
  local brules = panel.body.borderRules
  if brules then
    RenderRuleSection(brules, NS.db.tints.borderRules, borderRows, borderCondRows, true,
      function() return NS.db.tints.borderRules end, {}, targetAuras)
  end
  LayoutSections(panel.body, panel.body.sections)
end

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

  -- The "N rule(s) require three debuffs" warning is gone. It dated from the
  -- AddAuraGroup engine, where a third debuff meant ~111 containers and 1000
  -- textures per plate and genuinely did not work. Aura slots pool ONE button,
  -- so a chain costs one container and one texture per level -- three debuffs
  -- is now an ordinary rule, not an artefact of an older version.
  -- A rule with both halves off silently does nothing. Easy to reach by
  -- unticking one and forgetting the other, and impossible to diagnose from
  -- the plate, so it is called out here.
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

  -- A MISSING rule sitting above a normal one promises something the engine
  -- cannot deliver.
  --
  -- Priority in this table is one list, but the engine builds two stacks from
  -- it: presence rules, and the missing ladder underneath them (see ruleBase
  -- in Tints.lua). A missing rule's position therefore ranks it against OTHER
  -- MISSING rules only -- against a normal rule it means nothing, and the
  -- normal rule wins the bar whenever it matches regardless of which is
  -- higher here.
  --
  -- Worth saying out loud precisely because the table looks like it should
  -- work: dragging a missing rule to the top is the obvious thing to try when
  -- a reminder is not showing, and it changes nothing.
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

-- Taller than every other page's preview, and only here.
--
-- The colouring pages draw entirely ON the bar, so STAGE_H frames it exactly.
-- Aura icons sit ABOVE the bar with their own timer and stack text, and at
-- STAGE_H the icon row was pressed against the top edge of the stage with its
-- text clipped. Nothing else uses this number, which is the point -- the other
-- previews are unchanged.
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
  -- BELOW the stage, not above it.
  --
  -- This sat at -6 from the head's top, which was clear when the head began
  -- with a module-toggle row. It does not any more -- the switch moved to the
  -- rail -- so the stage starts at 6 and drew straight over this, leaving a
  -- checkbox poking out of the preview's top-left corner with its label hidden
  -- behind the plate.
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

-------------------------------------------------------------------------------
-- Tab 3 — profiles
--
-- Deliberately not built on BuildTabFrame: that shell assumes a module toggle
-- and a live preview, and a profile has neither. Just a scrolling body.
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- Tab 4 — about
--
-- The priority diagram is DRAWN, not a screenshot. A shipped image would need
-- a .tga in the addon, would not follow the theme colours, and would go stale
-- the moment the rules UI changed. Frames and textures cost nothing here and
-- always match what the user is actually looking at.
-------------------------------------------------------------------------------

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
  row.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE })
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
  edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE })
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
-- were built. None is conditional on a rule matching: the plate border is
-- redrawn on every plate, the edge inset applies to health and border tints
-- alike, and the pandemic flash is a global toggle. Filing them inside one
-- module made the other module look like it was missing settings.
--
-- The CollapsibleSection keys are unchanged (colourOutline / colourEdge /
-- colourPandemic), so everyone's open/closed state survives the move -- the
-- key is what that state is stored against, not the page it sits on.

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

  globalPanels = { panel }
end

-- Pandemic Flash, as its own module rather than a section inside a settings
-- page. It has an on/off of its own, its own colour and its own timing -- the
-- same shape as Health Coloring or Border Coloring -- and burying that under
-- a page called "Effects" made a feature look like a checkbox.
--
-- Worth knowing while reading this: the flash only ever applies to
-- single-debuff rules (see the pandemic block in Tints.lua), because a flash
-- region doubles a rule's texture count and a combo rule cannot afford it.
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
    ob.perf:Resize(116)
  end

  -- One layout pass at the end, after every section has been given its height.
  LayoutSections(ob, ob.sections)
end

-------------------------------------------------------------------------------
-- Rule editor — one rule, the whole pane
-------------------------------------------------------------------------------

-- Selecting a rule in the rail opens it here instead of expanding a row
-- inside a table. The table had to fit an editor between two other rules, so
-- everything competed for a few hundred pixels; here the rule is the only
-- thing on screen and each concern gets its own card.
--
-- The appearance controls are the SAME BuildStylePanel the tables use, not a
-- reimplementation -- it already knows fills, textures, missing-health cover,
-- target/focus gating and border shape, and it reads whatever expandedRule
-- points at. Two instances exist because isBorder is fixed at construction.
local rulePanel

local function RuleEditorList()
  -- Which list the open rule belongs to. Identity, not a flag on the rule:
  -- nothing on a rule says which stack it came from.
  for _, rule in ipairs(NS.db.tints.rules or {}) do
    if rule == expandedRule then return NS.db.tints.rules, false end
  end
  for _, rule in ipairs(NS.db.tints.borderRules or {}) do
    if rule == expandedRule then return NS.db.tints.borderRules, true end
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

  -- One toggle, not one per debuff.
  --
  -- The colouring pages simulate a whole rule LIST, so they need each debuff
  -- separately to work out which rule wins. Here exactly one rule is on
  -- screen and the only question is "show it or not" -- a row of per-debuff
  -- boxes asked you to assemble that answer by hand.
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
  head.testButton = TestModeButton(head.testColumn, false)
  head.testAllButton = TestModeButton(head.testColumn, true)

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
  StackTestButtons(head.testColumn, { head.previewRule, head.testButton, head.testAllButton })

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
    local isMissing = (not isBorder) and expandedRule and expandedRule.showWhenMissing

    -- Only on a missing rule's own page, and only for THIS rule.
    --
    -- Showing the whole ladder here meant a higher-ranked missing rule washed
    -- over the one you opened, and showing it on any other page meant one
    -- missing rule covered every preview in the window -- it is lit by
    -- default, so that was its normal state rather than an edge case. The
    -- stage is shared with the border editor too, which is why this is gated
    -- here rather than at the stage.
    if isMissing and not matches then
      NS.ApplyRuleFill(stage.missingWash, stage.bar, expandedRule)
      stage.missingWash:Show()
    else
      stage.missingWash:Hide()
    end

    if isMissing then
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
    -- INLINE with the first debuff, right-aligned, rather than on a line of
    -- its own beneath the list. A rule has one or two debuffs, so a dedicated
    -- row for the button was a third of this block's height spent on a
    -- control that is idle most of the time -- and it pushed the appearance
    -- and visibility groups below the fold on the rule page.
    --
    -- Right-aligned so it clears the remove X at the other end of the row,
    -- whatever the debuff's name happens to be.
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

-- The same facts /pt status prints, on a page instead of in chat.
--
-- Chat is where this information went to die: it scrolls away, it cannot be
-- selected, and it is the first thing anyone is asked for in a bug report. The
-- numbers come from NS.CollectDiagnostics, shared with the slash command, so
-- the two can never disagree.
local function DiagStat(parent, label)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(150, 44)
  -- Frames take no mouse input by default, so without this the stat boxes
  -- could never answer a hover.
  box:EnableMouse(true)
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = CTRL_EDGE,
  })
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

-------------------------------------------------------------------------------
-- Import / Export
--
-- Two halves that never touch: the top turns a profile into a string, the
-- bottom turns a string into a profile.
--
-- Import is deliberately three presses rather than one -- paste, Check,
-- Import. Check only DECODES, so the summary is on screen before anything is
-- written, and a string from a stranger can be inspected without committing to
-- it. NS.CommitShare is the only call here that writes, and nothing reaches it
-- until the name box has been seen.
--
-- Everything lives on the `share` table declared with the page constants, not
-- in locals -- see the note there. The fields used here:
--
--   share.tab      the panel
--   share.pending  the decoded payload waiting to be committed, or nil. Cleared
--                  whenever the box changes, so Import can never write a
--                  payload belonging to a string since edited away.
--   share.Rebuild  reachable from the builder, because this page's Check button
--                  calls its own rebuild. Every other page in this file gets
--                  away with declaring that afterwards; this one cannot.
-------------------------------------------------------------------------------

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
    if panel.Render then panel.Render() end
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
  panel.copyHint:SetPoint("BOTTOMLEFT", 12, 14)

  panel.copy = Button(panel, "Select All for Copy", 150, function()
    edit:SetFocus()
    edit:HighlightText()
    panel.copyHint:SetText("Selected - press |cff55dd55Ctrl+C|r to copy.")
  end)
  panel.copy:SetPoint("BOTTOMRIGHT", -10, 10)
  Tip(panel.copy, "Select All for Copy", TIPS.diagCopy)

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
    local version = getMeta and select(1, getMeta("PlateTweaks", "Version")) or nil
    table.insert(out, ("PlateTweaks %s"):format(version or "(version unknown)"))
    table.insert(out, ("profile %s | combat %s | auras secret %s"):format(
      info.profile, info.inCombat and "yes" or "no", info.restricted and "yes" or "no"))
    table.insert(out, ("plates %d | rigged %d | bound %d | no health bar %d | friendly skipped %d | hostility unknown %d")
      :format(info.plates, info.rigged, info.bound, info.pending, info.skipped, info.unknown or 0))
    table.insert(out, ("built objects %d"):format((info.textures or 0) + (info.containers or 0)))
    if info.errored > 0 then
      table.insert(out, ("build errors on %d rig(s): %s"):format(info.errored, tostring(info.firstError)))
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
        table.insert(out, ("  bar %s | frame level %s | plater-style %s"):format(
          t.bar, tostring(t.frameLevel), tostring(t.isPlater)))
      end
      if t.rigged then
        table.insert(out, ("  rig base level %s | tints shown %d of %d"):format(
          tostring(t.baseLevel), t.tintsShown or 0, t.tintsTotal or 0))
      end
    end

    edit:SetText(table.concat(out, "\n"))
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
  if NS.db.tints.borderEnabled ~= false then table.insert(modules, "Border Coloring") end
  if NS.db.icons.enabled then table.insert(modules, "Aura Icons") end

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
  -- Before the pages: the rail now carries the rule list itself, so priority
  -- numbers, colours, labels and the unreachable-rule warnings all have to
  -- follow any edit made on a page.
  -- Each one guarded and NAMED.
  --
  -- These used to be nine bare calls, so an error in any of them aborted every
  -- rebuild after it -- and since most people run with Lua errors hidden, the
  -- symptom was a page that silently stopped populating with nothing in chat
  -- to say why. The page that broke is now the only one that suffers, and it
  -- says which one it was.
  local passes = {
    { "rail", RebuildRail },
    { "health", RebuildHealthTab },
    { "border", RebuildBorderTab },
    { "aura icons", RebuildAuraIconTab },
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
function NS.OpenOptions()
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
        { "border", BuildBorderTab },
        { "aura icons", BuildAuraIconTab },
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
  proxy.name = "PlateTweaks"
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
  local category = Settings.RegisterCanvasLayoutCategory(proxy, "PlateTweaks")
  Settings.RegisterAddOnCategory(category)
end)
