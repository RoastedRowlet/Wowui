-- Alignment contract for the Flex-laid pages.
--
-- The claim under test is the whole reason those pages moved onto Flex: a
-- heading sits on its control's centre line, a fixed control never changes
-- width, and only the name column absorbs a narrower window. Every number
-- comes from the addon's own NS.UI / NS.RULE_COLS / NS.THREAT_COLS -- a test
-- with its own copy of the spec would pass while the window was wrong.
local dir = ...

local NS = {}

local function stubregion(w, h, isText)
  local r = { w = w or 0, h = h or 0 }
  function r:GetWidth() return self.w end
  function r:GetHeight() return self.h end
  function r:SetWidth(v) self.w = v end
  function r:SetHeight(v) self.h = v end
  function r:SetSize(a, b) self.w, self.h = a, b end
  function r:ClearAllPoints() end
  function r:SetPoint(pt, rel, rp, x, y)
    if type(rel) == "number" then x, y = rel, rp end
    self.x, self.y = x or 0, y or 0
  end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown ~= false end
  function r:SetParent() end
  function r:HookScript() end
  function r:SetScript() end
  function r:EnableMouseWheel() end
  function r:CreateTexture() return stubregion(0, 0) end
  function r:SetVerticalScroll() end
  function r:SetScrollChild() end
  function r:SetColorTexture() end
  function r:SetAllPoints() end
  if isText then
    function r:GetStringWidth() return self.w end
    function r:GetStringHeight() return self.h end
    function r:SetWordWrap() end
    function r:SetJustifyH() end
    function r:SetText() end
  end
  return r
end

_G.CreateFrame = function() return stubregion(0, 0) end
_G.GetCursorPosition = function() return 0, 0 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local chunk = assert(loadfile(dir .. "/Libs/Flex/Flex.lua"))
chunk("PlateTweaks", NS)
local Flex = NS.Flex

-- The spec, read out of Options.lua rather than restated here. Parsing beats
-- loading: Options.lua builds real frames at load and pulls in half the addon,
-- while these three tables are plain literals with no dependencies.
local function ReadSpec(name, ui)
  local source = assert(io.open(dir .. "/Options.lua")):read("a")
  local body = source:match("NS%." .. name .. " = (%b{})")
  assert(body, name .. " not found in Options.lua")
  -- Resolve the few cross-references the tables use. Only on the VALUE side:
  -- `ROW_H = ROW_H` is a key named after the local it copies, and rewriting
  -- both halves produces `26 = 26`.
  --
  -- The UI numbers come from the UI table this function already read, not from
  -- copies written down here. They were literals -- 44 for the strip width, 15
  -- for a chip -- and the moment the shipped chip changed size the test failed
  -- against its own stale copy rather than against anything that was wrong.
  -- CTRL_BOX_W and ROW_H are file-locals in Options.lua rather than UI fields,
  -- so those two are still read out of the source directly.
  local function localNumber(key)
    return assert(tonumber(source:match("local " .. key .. " = (%d+)")), key)
  end
  if ui then
    body = body:gsub("(=%s*)NS%.UI%.STRIP_CHIP %* 3 %+ NS%.UI%.CHIP_GAP %* 2",
                     "%1" .. (ui.STRIP_CHIP * 3 + ui.CHIP_GAP * 2))
               :gsub("(=%s*)NS%.UI%.CHIP_W", "%1" .. ui.CHIP_W)
               :gsub("(=%s*)NS%.UI%.CHIP_H", "%1" .. ui.CHIP_H)
  end
  body = body:gsub("(=%s*)CTRL_BOX_W", "%1" .. localNumber("CTRL_BOX_W"))
             :gsub("(=%s*)ROW_H", "%1" .. localNumber("ROW_H"))
  return assert(load("return " .. body))()
end

local UI = ReadSpec("UI")
local RULE = ReadSpec("RULE_COLS", UI)
local THREAT = ReadSpec("THREAT_COLS", UI)

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(name, tostring(got), tostring(want)))
  else
    print("ok   " .. name)
  end
end

-- The two helpers Options.lua lays these pages out with, rebuilt here against
-- the same spec. Keeping them tiny is deliberate: what is being tested is the
-- SPEC and the engine, not a copy of the widget code.
local function Cell(parent, width, childW, childH)
  local cell = Flex.Box(parent, { dir = "row", justify = "center", align = "center",
    width = width, shrink = 0 })
  cell.child = Flex.Item(stubregion(childW, childH or 20), {})
  cell:Add(cell.child)
  return cell
end

local function centre(node) return node.rect.x + node.rect.w / 2 end

-- A rule row and its header, built from NS.RULE_COLS in the order the window
-- builds them.
local function RuleRow(parent, nameWidth)
  local row = Flex.Box(parent, { dir = "row", align = "center", height = UI.ROW_H,
    gap = UI.COL_GAP, pad = { l = UI.ROW_INSET, r = UI.ROW_INSET } })
  row.cells = {}
  row.cells.grip = row:Add(Cell(parent, RULE.grip, 14, 14))
  row.name = Flex.Item(stubregion(nameWidth, 12, true), { grow = 1, minW = 80, clipText = true })
  row:Add(row.name)
  -- The two halves a rule paints, each a chip in its own column.
  row.cells.bar = row:Add(Cell(parent, RULE.bar, UI.CHIP_W, UI.CHIP_H))
  row.cells.border = row:Add(Cell(parent, RULE.border, UI.CHIP_W, UI.CHIP_H))
  row.cost = Flex.Item(stubregion(40, 12, true), { width = RULE.cost, shrink = 0, clipText = true })
  row:Add(row.cost)
  row.cells.edit = row:Add(Cell(parent, RULE.edit, RULE.edit))
  row.cells.del = row:Add(Cell(parent, RULE.del, UI.BOX))
  row.cells.on = row:Add(Cell(parent, RULE.on, UI.BOX))
  return row
end

local function RuleHeader(parent)
  local head = Flex.Box(parent, { dir = "row", align = "center", height = UI.HEAD_H,
    gap = UI.COL_GAP, pad = { l = UI.ROW_INSET, r = UI.ROW_INSET } })
  head.cells = {}
  head.cells.ord = head:Add(Cell(parent, RULE.grip, 24, 12))
  head.rule = Flex.Item(stubregion(30, 12, true), { grow = 1, minW = 80, clipText = true })
  head:Add(head.rule)
  head.cells.bar = head:Add(Cell(parent, RULE.bar, 22, 12))
  head.cells.border = head:Add(Cell(parent, RULE.border, 22, 12))
  head.slots = Flex.Item(stubregion(34, 12, true), { width = RULE.cost, shrink = 0, clipText = true })
  head:Add(head.slots)
  head.cells.edit = head:Add(Cell(parent, RULE.edit, 26, 12))
  head.cells.del = head:Add(Cell(parent, RULE.del, 22, 12))
  head.cells.on = head:Add(Cell(parent, RULE.on, 18, 12))
  return head
end

-- ---- the contract, at two widths -------------------------------------------
for _, width in ipairs({ 690, 460 }) do
  local root = Flex.Root(stubregion(width, 400), { dir = "column", gap = 4 })
  local head = root:Add(RuleHeader(nil))
  -- A short name and a very long one: if a column came from its own row's
  -- content rather than from the spec, these two would not agree.
  local shortRow = root:Add(RuleRow(nil, 40))
  local longRow = root:Add(RuleRow(nil, 900))
  root:Layout(width)

  local tag = ("\n%d"):format(width)
  for _, key in ipairs({ "bar", "border", "edit", "del", "on" }) do
    check(("%s column is centred under its heading %s"):format(key, tag),
      centre(longRow.cells[key]), centre(head.cells[key]))
    check(("%s column keeps its width %s"):format(key, tag),
      longRow.cells[key].rect.w, RULE[key])
  end
  check("the Slots column lines up with its heading " .. tag,
    longRow.cost.rect.x, head.slots.rect.x)
  check("both rows give the name column the same width " .. tag,
    shortRow.name.rect.w, longRow.name.rect.w)
  check("the name column is the only thing that moved " .. tag,
    shortRow.cells.on.rect.x, longRow.cells.on.rect.x)
  check("rows start on the row inset " .. tag,
    longRow.cells.grip.rect.x, UI.ROW_INSET)
  check("the last column ends on the row inset " .. tag,
    width - (longRow.cells.on.rect.x + longRow.cells.on.rect.w), UI.ROW_INSET)
  check("a row is exactly one row high " .. tag, longRow.rect.h, UI.ROW_H)
end

-- ---- a control smaller than its column still centres ------------------------
local box = Flex.Box(nil, { dir = "row", height = UI.ROW_H })
local wide = box:Add(Cell(nil, THREAT.on, UI.BOX))
box:Layout(THREAT.on)
check("a tick box centres in the threat On column",
  centre(wide.child) + wide.rect.x, THREAT.on / 2)

-- ---- the editor band spans the row it belongs to ----------------------------
local list = Flex.Root(stubregion(690, 400), { dir = "column", gap = 0 })
local owner = list:Add(RuleRow(nil, 200))
local band = list:Add(Flex.Box(nil, { dir = "column", pad = { l = 0, r = 0 } }))
band:Add(Flex.Item(stubregion(100, 60), { grow = 1 }))
list:Layout(690)
check("the editor band starts at the row's left edge", band.rect.x, owner.rect.x)
check("the editor band is as wide as the row", band.rect.w, owner.rect.w)

-- ---- a hidden block costs exactly nothing ----------------------------------
local before = list:Layout(690)
local bandHeight = band.rect.h
band.hidden = true
local after = list:Layout(690)
check("hiding the editor gives back exactly its height", before - after, bandHeight)
check("a hidden block leaves the row untouched", owner.rect.h, UI.ROW_H)
band.hidden = false

-- ---- notes are indented past the rows, and measured ------------------------
local page = Flex.Root(stubregion(690, 400), { dir = "column", gap = 0 })
local pageRow = page:Add(RuleRow(nil, 100))
local noteBox = page:Add(Flex.Box(nil, { dir = "column",
  pad = { l = UI.NOTE_INSET, r = UI.NOTE_INSET, t = 2, b = 2 } }))
local note = Flex.Item(stubregion(1400, 12, true), { wrapText = true, grow = 1 })
noteBox:Add(note)
page:Layout(690)
check("a note is indented past the row inset", note.rect.x, UI.NOTE_INSET)
check("a note is inset on both sides", note.rect.w, 690 - UI.NOTE_INSET * 2)
check("a note sits inside the row's own columns",
  note.rect.x > pageRow.cells.grip.rect.x, true)

-- ---- the spec itself --------------------------------------------------------
check("a tick column is at least as wide as a tick box", RULE.on >= UI.BOX, true)
check("the bar column is at least as wide as a chip", RULE.bar >= UI.CHIP_W, true)
-- The threat row lives in this table and its cells are these columns, so the
-- three state chips have to FIT one. They were sized independently and came
-- out 66 wide under a 30-wide heading, which shouldered both colour columns
-- out of line with everything above them.
check("three threat chips fit the bar column exactly",
  UI.STRIP_CHIP * 3 + UI.CHIP_GAP * 2, RULE.bar)
check("and the border column matches it", RULE.border, RULE.bar)
check("so is the border column", RULE.border >= UI.CHIP_W, true)
check("the note indent clears the row inset", UI.NOTE_INSET > UI.ROW_INSET, true)

-- ---- the spec is actually USED ---------------------------------------------
--
-- Everything above tests the engine's contract against the spec, and builds
-- its rows FROM the spec -- so a wrong number in NS.UI moves both sides and
-- the checks stay green. What that cannot see is the failure that actually
-- happens: a builder in Options.lua writing `width = 24` instead of
-- `NS.RULE_COLS.on`, which lines up today and drifts the moment the spec
-- moves.
--
-- So this reads the builders' own source and refuses a bare number where a
-- layout value belongs. Not style policing: these six functions are the ones
-- whose columns have to agree with each other, and a literal in any of them
-- is a column that no longer takes its position from anywhere.
-- Carriage returns stripped first: the file is CRLF on disk, and every
-- newline in the patterns below is a bare newline.
local SOURCE = (PT_SOURCES and PT_SOURCES["Options.lua"]
  or assert(io.open(dir .. "/Options.lua")):read("a")):gsub(string.char(13), "")

local BUILDERS = {
  -- The threat SECTION builders are gone: threat is the top row of the rule
  -- table now, and its editor is a band in that table.
  "NS.BuildThreatPinnedRow", "NS.BuildThreatBand",
  "BuildRuleRow", "NS.BuildRuleHeader", "RuleSectionLayout",
  "NS.StylePanelLayout", "NS.BuildResolutionLadder",
  "NS.EditorBlock", "NS.EditorRow", "NS.BuildRuleEditor", "NS.EditorPill",
}

-- The keys Flex reads as geometry. `minW` is deliberately absent: a minimum
-- width is a judgement about the text in that column, not a shared column.
local GEOM = { "width", "height", "gap", "crossGap" }

for _, name in ipairs(BUILDERS) do
  -- From the declaration to the next one at column zero.
  local NL = string.char(10)
  local body = SOURCE:match(NL .. "[%a ]-function " .. name:gsub("%.", "%%.")
    .. "%b()(.-)" .. NL .. "end" .. NL)
  if not body then
    failures = failures + 1
    print(("FAIL %s: not found in Options.lua"):format(name))
  else
    local offenders = {}
    for _, key in ipairs(GEOM) do
      for value in body:gmatch(key .. "%s*=%s*(%-?%d+)") do
        -- 0 and 1 are structural (a spacer's height, a hairline), not layout.
        if value ~= "0" and value ~= "1" then
          offenders[#offenders + 1] = key .. " = " .. value
        end
      end
    end
    for value in body:gmatch("pad%s*=%s*{[^}]-[lrtb]%s*=%s*(%d+)") do
      if value ~= "0" and value ~= "2" then
        offenders[#offenders + 1] = "pad " .. value
      end
    end
    check(("%s takes every measurement from the spec"):format(name),
      #offenders == 0 and true or table.concat(offenders, ", "), true)

    -- A Flex box is a plain table, and these builders hang their widgets on
    -- it. Hang one on a name the ENGINE reads -- grow, width, hidden, pad --
    -- and the next Layout does arithmetic on a frame. That is not a wrong
    -- number on screen, it is the page failing to build: `border.grow =
    -- Dropdown(...)` took the whole health panel down the moment a rule was
    -- opened.
    local reserved = {
      "gap", "crossGap", "width", "height", "hidden", "pad", "align", "justify",
      "shrink", "basis", "grow", "minW", "maxW", "dir", "wrap", "alignSelf",
      "wrapText", "clipText", "rect", "kind", "children", "frame", "region", "parent",
    }
    local clashes = {}
    for _, key in ipairs(reserved) do
      for maker in body:gmatch("%." .. key .. "%s*=%s*([%w%.]+)%s*%(") do
        if maker:match("Dropdown") or maker:match("Slider") or maker:match("Checkbox")
          or maker:match("ColorSwatch") or maker:match("Button") or maker:match("Label")
          or maker:match("Dim") or maker:match("Header") or maker:match("CreateFrame")
          or maker:match("FillChip") then
          clashes[#clashes + 1] = key .. " = " .. maker
        end
      end
    end
    check(("%s keeps its widgets off the engine's own field names"):format(name),
      #clashes == 0 and true or table.concat(clashes, ", "), true)
  end
end

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
return failures
