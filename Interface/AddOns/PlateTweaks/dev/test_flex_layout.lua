-- Layout check for the threat section's Flex tree.
--
-- The claim being tested is the reason the section was moved onto Flex at all:
-- the header and a row are the same node shape, so their columns land on the
-- same x without a second list of offsets to keep in step -- and a hidden
-- block costs exactly zero height.
local dir = ...

local NS = {}

-- Enough of a frame for the engine: it reads sizes, writes points and sizes,
-- and shows or hides. Nothing else is touched during a layout.
local function stubregion(w, h, isText)
  local r = { w = w or 0, h = h or 0, points = {} }
  function r:GetWidth() return self.w end
  function r:GetHeight() return self.h end
  function r:SetWidth(v) self.w = v end
  function r:SetHeight(v) self.h = v end
  function r:SetSize(a, b) self.w, self.h = a, b end
  function r:ClearAllPoints() self.points = {} end
  function r:SetPoint(p, rel, rp, x, y)
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
  end
  return r
end

_G.CreateFrame = function() return stubregion(0, 0) end
_G.GetCursorPosition = function() return 0, 0 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local chunk = assert(loadfile(dir .. "/Libs/Flex/Flex.lua"))
chunk("PlateTweaks", NS)
local Flex = NS.Flex

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(name, tostring(got), tostring(want)))
  else
    print("ok   " .. name)
  end
end

local SWATCH, COL, WIDTH = 20, 34, 690

-- The two node shapes the section uses, built the same way the options file
-- builds them.
local function BuildRow(parent, labelWidth)
  local row = Flex.Box(parent, {
    dir = "row", align = "center", height = 26, gap = 8, pad = { l = 12, r = 12 },
  })
  row.first = Flex.Item(stubregion(SWATCH, 20), { width = SWATCH })
  row:Add(row.first)
  row.label = Flex.Item(stubregion(labelWidth, 12, true), { grow = 1, minW = 60, clipText = true })
  row:Add(row.label)
  row.cols = {}
  for index = 1, 4 do
    row.cols[index] = Flex.Item(stubregion(20, 20), { width = COL, alignSelf = "center" })
    row:Add(row.cols[index])
  end
  return row
end

local root = Flex.Root(stubregion(WIDTH, 400), { dir = "column", gap = 6, pad = { t = 8, b = 10 } })
-- A short heading and a long row label, so the two would NOT line up if the
-- columns came from each node's own content rather than from the layout.
local header = root:Add(BuildRow(nil, 40))
local row = root:Add(BuildRow(nil, 400))

root:Layout(WIDTH)

for index = 1, 4 do
  check(("column %d lines up with its heading"):format(index),
    row.cols[index].rect.x, header.cols[index].rect.x)
end
check("the label absorbs the slack, not the columns",
  row.label.rect.w, header.label.rect.w)
check("the last column ends inside the right padding",
  row.cols[4].rect.x + row.cols[4].rect.w <= WIDTH - 12, true)
check("a fixed-width control keeps its width", row.cols[1].rect.w, COL)
check("a row honours its declared height", row.rect.h, 26)

-- A long label must not push the columns off the row: clipText means it
-- shrinks instead.
check("an over-long label does not widen the row", row.rect.w, WIDTH)

-- Hidden blocks.
local detail = Flex.Box(nil, { dir = "column", gap = 4 })
detail:Add(BuildRow(nil, 100))
detail:Add(BuildRow(nil, 100))
root:Add(detail)

local shownHeight = root:Layout(WIDTH)
detail.hidden = true
local hiddenHeight = root:Layout(WIDTH)
check("hiding the detail block gives back exactly its height",
  shownHeight - hiddenHeight, (26 * 2 + 4) + 6)

-- Wrapped text is measured at the width it is given, not at its natural width.
local note = Flex.Item(stubregion(1200, 12, true), { wrapText = true })
local wrapper = Flex.Box(nil, { dir = "column" })
wrapper:Add(note)
wrapper:Layout(300)
check("wrapped text is measured at the width it gets", note.rect.w, 300)

-- The centring cell: a control narrower than its column sits in the middle of
-- it, and a heading built the same way lands on the same centre line. This is
-- what NS.FlexCell does in Options.lua, and the reason it exists -- a row's
-- `align` is the CROSS axis, so an item cannot centre itself horizontally.
local function Cell(width, childW)
  local cell = Flex.Box(nil, { dir = "row", justify = "center", align = "center",
    width = width, shrink = 0 })
  cell.child = Flex.Item(stubregion(childW, 20), {})
  cell:Add(cell.child)
  return cell
end

local cellRow = Flex.Box(nil, { dir = "row", gap = 0, height = 26 })
local wide = cellRow:Add(Cell(30, 20))
local narrow = cellRow:Add(Cell(30, 8))
cellRow:Layout(60)
check("a control is centred in its column",
  wide.child.rect.x + wide.child.rect.w / 2, 15)
-- Each child's rect is relative to its OWN cell, so both read 15: the point
-- is that a narrower control still centres rather than sitting flush left.
check("a narrower control shares that centre line",
  narrow.child.rect.x + narrow.child.rect.w / 2, 15)
check("the two cells sit side by side", narrow.rect.x, 30)

-- Explanatory text is indented past the rows, and a pad on a leaf ITEM does
-- nothing -- padding is read off boxes, which is why the note has to be
-- wrapped in one.
local rowInset, noteInset = 12, 26
local page = Flex.Box(nil, { dir = "column", gap = 0 })
local listRow = page:Add(BuildRow(nil, 100))
listRow.pad = { l = rowInset, r = rowInset }
local noteBox = page:Add(Flex.Box(nil, { dir = "column",
  pad = { l = noteInset, r = noteInset } }))
local noteText = Flex.Item(stubregion(900, 12, true), { wrapText = true, grow = 1 })
noteBox:Add(noteText)
page:Layout(WIDTH)
check("the note is indented past the row's own inset",
  noteText.rect.x > listRow.first.rect.x, true)
check("the note is inset on the right as well",
  noteText.rect.w, WIDTH - noteInset * 2)

-- Padding on an Item is ignored, which is the trap this replaced.
local bare = Flex.Box(nil, { dir = "column" })
local bareText = Flex.Item(stubregion(900, 12, true), { wrapText = true, pad = { l = 26 } })
bare:Add(bareText)
bare:Layout(WIDTH)
check("pad on a leaf item does nothing", bareText.rect.x, 0)

-- Reordering a box's children is how the editor band follows whichever rule is
-- open: the band is added once and moved, because a frame cannot be destroyed
-- and rebuilding it per rule would leak one per rule. What that relies on is
-- Flex reading the children array fresh on every Layout, so a node moved in it
-- lands in its new place with nothing else touched.
local list = Flex.Box(nil, { dir = "column", gap = 0 })
local rowA = list:Add(BuildRow(nil, 100))
local rowB = list:Add(BuildRow(nil, 100))
local band = list:Add(Flex.Box(nil, { dir = "column", height = 40 }))
list:Layout(WIDTH)
check("the band starts at the end", band.rect.y > rowB.rect.y, true)

table.remove(list.children, 3)
table.insert(list.children, 2, band)
list:Layout(WIDTH)
check("a moved band sits under the row it follows",
  band.rect.y, rowA.rect.y + rowA.rect.h)
check("and pushes the row below it down",
  rowB.rect.y, band.rect.y + band.rect.h)
check("the rows themselves are untouched", rowA.rect.h, 26)

band.hidden = true
local closed = list:Layout(WIDTH)
band.hidden = false
local open = list:Layout(WIDTH)
check("a closed band costs no height at all", open - closed, 40)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
return failures
