local _, NS = ...

-- The addon's own colour picker.
--
-- Blizzard's ColorPickerFrame works, and three things about it do not suit
-- what this addon asks people to do:
--
--   * opacity is a slider from 0 to 1 with no readout, and every colour in
--     here has an alpha that matters -- 30% is a reminder, 85% is a statement,
--     and "somewhere left of the middle" is not a setting you can repeat on a
--     second rule
--   * it has no idea what a fill texture is, so dragging a colour updated a
--     flat swatch while the striped chip beside it stayed on the old one
--   * it is modal-ish, moves, and covers the list you are colouring
--
-- So: one instance, opened next to whatever asked for it, with a saturation /
-- value square, a hue strip, an opacity toggle with a 0-100 box, and a hex
-- field. Every change is applied LIVE through the same setter the swatch owns,
-- and everything that draws a colour is repainted on the spot -- including the
-- pattern chips, which is the part Blizzard's could never do.
--
-- Cancel restores what was there when it opened, since live editing means the
-- profile has already been written to by then.

local floor, min, max = math.floor, math.min, math.max

-- One gutter, everywhere. PAD is the frame's own margin and GAP is the space
-- between any two things inside it -- so nothing needs a number of its own and
-- nothing can drift. Width is derived from what it holds rather than picked:
-- the square, a gap, the hue strip, and a margin either side.
local PAD, GAP = 10, 8
local SV_SIZE = 150
local HUE_W = 16
local ROW_H = 18
local PICKER_W = PAD + SV_SIZE + GAP + HUE_W + PAD

-- ---------------------------------------------------------------------------
-- Colour maths. HSV because that is the shape of the control: a hue strip and
-- a square of saturation against value.
-- ---------------------------------------------------------------------------
local function HSVtoRGB(h, s, v)
  if s <= 0 then return v, v, v end
  h = (h % 360) / 60
  local i = floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v
  else return v, p, q end
end
NS.HSVtoRGB = HSVtoRGB

local function RGBtoHSV(r, g, b)
  local hi, lo = max(r, g, b), min(r, g, b)
  local d = hi - lo
  local h = 0
  if d > 0 then
    if hi == r then h = 60 * (((g - b) / d) % 6)
    elseif hi == g then h = 60 * (((b - r) / d) + 2)
    else h = 60 * (((r - g) / d) + 4) end
  end
  return h, hi > 0 and (d / hi) or 0, hi
end
NS.RGBtoHSV = RGBtoHSV

-- ---------------------------------------------------------------------------
-- Live repaint
--
-- A colour lives in the profile, and half a dozen things draw it: the swatch
-- itself, the chips in the rule row, the pattern grid, the preview plate.
-- Dragging inside the picker writes the profile on every frame, so all of
-- them have to be told -- otherwise the swatch tracks your cursor and the
-- striped chip beside it stays on the colour you started from.
--
-- A registry rather than a rebuild: rebuilding the page mid-drag would tear
-- down and recreate the frame you are dragging on.
-- ---------------------------------------------------------------------------
NS.liveSwatches = NS.liveSwatches or {}

function NS.RegisterLiveSwatch(refresh)
  if type(refresh) == "function" then
    NS.liveSwatches[#NS.liveSwatches + 1] = refresh
  end
end

function NS.RefreshLiveSwatches()
  for _, refresh in ipairs(NS.liveSwatches) do pcall(refresh) end
end

-- ---------------------------------------------------------------------------
-- The picker
-- ---------------------------------------------------------------------------
local picker, scrim

-- The window goes quiet behind it.
--
-- Not decoration: the picker writes the profile on every frame of a drag, so
-- while it is open every control behind it is showing a value that is being
-- changed from somewhere else. Dimming says which surface is live, and taking
-- the clicks stops someone tuning a slider whose colour is mid-edit.
local function Scrim()
  if scrim then return scrim end
  scrim = CreateFrame("Frame", nil, UIParent)
  scrim:SetFrameStrata("FULLSCREEN_DIALOG")
  scrim:EnableMouse(true)
  scrim:Hide()
  scrim.tex = scrim:CreateTexture(nil, "BACKGROUND")
  scrim.tex:SetAllPoints()
  scrim.tex:SetColorTexture(0, 0, 0, 0.55)
  -- Clicking the dimmed area is the ordinary way out of a popup like this.
  scrim:SetScript("OnMouseUp", function()
    if picker and picker.revert then picker.revert() else NS.CloseColorPicker() end
  end)
  return scrim
end

local function Build()
  local Flex = NS.Flex
  local frame = CreateFrame("Frame", "PlateTweaksColorPicker", UIParent, "BackdropTemplate")
  frame:SetWidth(PICKER_W)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  -- Pixel-snapped edges, the same treatment the options window gives its
  -- controls: a backdrop edge is one UI unit, which is a fraction of a
  -- screen pixel at most UI scales, and the four sides then round apart.
  if NS.PixelBorder then NS.PixelBorder(frame) end
  frame:SetBackdropColor(0.07, 0.07, 0.085, 0.98)
  frame:SetBackdropBorderColor(0.34, 0.34, 0.40, 1)
  frame:Hide()

  -- Laid out by the same engine as the options window, for the same reason:
  -- a stack of hand-placed offsets is how the first version ended up with a
  -- Cancel button sitting on top of the opacity row.
  local root = Flex.Box(frame, { dir = "column", gap = GAP,
    pad = { l = PAD, r = PAD, t = PAD, b = PAD } })
  root.frame:Hide()
  root.frame:SetParent(nil)
  root.frame = frame
  frame.root = root

  -- Title, and the close control every window in this addon uses.
  local titleRow = Flex.Box(frame, { dir = "row", align = "center", gap = GAP, height = ROW_H })
  frame.title = titleRow.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.title:SetText("Color")
  frame.title:SetJustifyH("LEFT")
  titleRow:Add(Flex.Item(frame.title, { grow = 1, minW = 40, clipText = true }))

  local close = CreateFrame("Button", nil, frame)
  close:SetSize(ROW_H, ROW_H)
  close.label = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  close.label:SetPoint("CENTER")
  close.label:SetText("X")
  close.label:SetTextColor(0.72, 0.72, 0.78)
  close:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.82, 0.1) end)
  close:SetScript("OnLeave", function(self) self.label:SetTextColor(0.72, 0.72, 0.78) end)
  frame.close = close
  titleRow:Add(Flex.Item(close, { width = ROW_H, height = ROW_H, shrink = 0 }))
  root:Add(titleRow)

  -- The square and the strip.
  local pickRow = Flex.Box(frame, { dir = "row", gap = GAP, height = SV_SIZE })

  local sv = CreateFrame("Frame", nil, frame)
  sv:EnableMouse(true)
  frame.sv = sv
  sv.hue = sv:CreateTexture(nil, "BACKGROUND")
  sv.hue:SetAllPoints()
  sv.hue:SetColorTexture(1, 1, 1, 1)

  -- White to the hue, left to right; transparent to black, top to bottom.
  sv.white = sv:CreateTexture(nil, "BORDER")
  sv.white:SetAllPoints()
  sv.white:SetTexture("Interface\\Buttons\\WHITE8X8")
  sv.black = sv:CreateTexture(nil, "ARTWORK")
  sv.black:SetAllPoints()
  sv.black:SetTexture("Interface\\Buttons\\WHITE8X8")
  if sv.white.SetGradient and CreateColor then
    sv.white:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
    sv.black:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))
  else
    -- Ancient clients: no gradients, so the square degrades to the hue alone
    -- and the hex box carries the work.
    sv.white:Hide()
    sv.black:Hide()
  end

  -- A hollow white ring. The cursor's job is to show the colour underneath it,
  -- so anything solid hides the exact pixel being chosen.
  sv.cursor = CreateFrame("Frame", nil, sv)
  sv.cursor:SetSize(11, 11)
  local function Ring(inset, r, g, b)
    local edges = {}
    for index = 1, 4 do
      local tex = sv.cursor:CreateTexture(nil, "OVERLAY")
      tex:SetColorTexture(r, g, b, 1)
      edges[index] = tex
    end
    edges[1]:SetPoint("TOPLEFT", inset, -inset)
    edges[1]:SetPoint("TOPRIGHT", -inset, -inset)
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", inset, inset)
    edges[2]:SetPoint("BOTTOMRIGHT", -inset, inset)
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", inset, -inset)
    edges[3]:SetPoint("BOTTOMLEFT", inset, inset)
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", -inset, -inset)
    edges[4]:SetPoint("BOTTOMRIGHT", -inset, inset)
    edges[4]:SetWidth(1)
  end
  -- One ring, white, no outline. A dark ring around it reads as a second
  -- marker on a light square and doubles the thing you are trying to see past.
  Ring(0, 1, 1, 1)
  pickRow:Add(Flex.Item(sv, { width = SV_SIZE, height = SV_SIZE, shrink = 0 }))

  local hue = CreateFrame("Frame", nil, frame)
  hue:EnableMouse(true)
  frame.hue = hue

  -- Six bands, because a hue wheel is six linear ramps and one gradient cannot
  -- express it.
  local BANDS = {
    { 1, 0, 0, 1, 1, 0 }, { 1, 1, 0, 0, 1, 0 }, { 0, 1, 0, 0, 1, 1 },
    { 0, 1, 1, 0, 0, 1 }, { 0, 0, 1, 1, 0, 1 }, { 1, 0, 1, 1, 0, 0 },
  }
  local band = SV_SIZE / #BANDS
  for index, stops in ipairs(BANDS) do
    local tex = hue:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 0, -(index - 1) * band)
    tex:SetSize(HUE_W, band)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    if tex.SetGradient and CreateColor then
      tex:SetGradient("VERTICAL",
        CreateColor(stops[4], stops[5], stops[6], 1),
        CreateColor(stops[1], stops[2], stops[3], 1))
    else
      tex:SetColorTexture(stops[1], stops[2], stops[3], 1)
    end
  end
  hue.marker = hue:CreateTexture(nil, "OVERLAY")
  hue.marker:SetHeight(2)
  hue.marker:SetColorTexture(1, 1, 1, 1)
  pickRow:Add(Flex.Item(hue, { width = HUE_W, height = SV_SIZE, shrink = 0 }))
  root:Add(pickRow)

  -- Was and is, then the hex for the one you are on.
  local swatchRow = Flex.Box(frame, { dir = "row", align = "center", gap = GAP, height = ROW_H })

  local compare = CreateFrame("Frame", nil, frame)
  compare.bg = compare:CreateTexture(nil, "BACKGROUND")
  compare.bg:SetAllPoints()
  compare.bg:SetColorTexture(0.30, 0.30, 0.33, 1)
  compare.was = compare:CreateTexture(nil, "ARTWORK")
  compare.was:SetPoint("TOPLEFT"); compare.was:SetPoint("BOTTOMLEFT")
  compare.was:SetWidth(31)
  compare.now = compare:CreateTexture(nil, "ARTWORK")
  compare.now:SetPoint("TOPRIGHT"); compare.now:SetPoint("BOTTOMRIGHT")
  compare.now:SetWidth(31)
  frame.compare = compare
  swatchRow:Add(Flex.Item(compare, { width = 62, height = ROW_H, shrink = 0 }))

  local function Field(width, numeric)
    local box = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    box:SetAutoFocus(false)
    box:SetNumeric(numeric and true or false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(5, 5, 0, 0)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    -- Pixel-snapped edges, the same treatment the options window gives its
    -- controls: a backdrop edge is one UI unit, which is a fraction of a
    -- screen pixel at most UI scales, and the four sides then round apart.
    if NS.PixelBorder then NS.PixelBorder(box) end
    box:SetBackdropColor(0.10, 0.10, 0.12, 1)
    box:SetBackdropBorderColor(0.34, 0.34, 0.40, 1)
    return box
  end

  frame.hex = Field(nil, false)
  swatchRow:Add(Flex.Item(frame.hex, { grow = 1, minW = 50, height = ROW_H }))
  root:Add(swatchRow)

  -- Opacity: a switch, a word, a number people can say out loud.
  local alphaRow = Flex.Box(frame, { dir = "row", align = "center", gap = GAP, height = ROW_H })

  local alphaBox = CreateFrame("Button", nil, frame, "BackdropTemplate")
  alphaBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  -- Pixel-snapped edges, the same treatment the options window gives its
  -- controls: a backdrop edge is one UI unit, which is a fraction of a
  -- screen pixel at most UI scales, and the four sides then round apart.
  if NS.PixelBorder then NS.PixelBorder(alphaBox) end
  alphaBox:SetBackdropColor(0.10, 0.10, 0.12, 1)
  alphaBox:SetBackdropBorderColor(0.34, 0.34, 0.40, 1)
  alphaBox.fill = alphaBox:CreateTexture(nil, "OVERLAY")
  alphaBox.fill:SetPoint("TOPLEFT", 3, -3)
  alphaBox.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  alphaBox.fill:SetColorTexture(0.35, 0.62, 0.98, 1)
  frame.alphaBox = alphaBox
  alphaRow:Add(Flex.Item(alphaBox, { width = 16, height = 16, shrink = 0 }))

  frame.alphaLabel = alphaRow.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.alphaLabel:SetText("Opacity")
  frame.alphaLabel:SetJustifyH("LEFT")
  -- Sized to the word, measured, rather than a guess. 48 was two pixels short
  -- of "Opacity" at this font, so the slider beside it pushed the last letter
  -- out of its own column.
  frame.alphaLabel:SetWidth(0)
  local labelW = math.max(48, math.ceil((frame.alphaLabel:GetStringWidth() or 48) + 2))
  alphaRow:Add(Flex.Item(frame.alphaLabel, { width = labelW, shrink = 0, clipText = true }))

  -- A slider AND the number.
  --
  -- They answer different questions: the slider is for "a bit less than that",
  -- which is how a colour is actually judged, and the field is for "the same
  -- 30% I used on the other rule", which a slider cannot hit twice. Both write
  -- the same value, and each redraws the other.
  --
  -- Its own control rather than the options window's: this file loads before
  -- Options.lua, so that Slider does not exist yet -- and a picker that cannot
  -- be opened from a slash command before the window is built is worse than
  -- twenty lines of track and thumb.
  local slider = CreateFrame("Frame", nil, frame)
  slider:EnableMouse(true)
  slider.track = slider:CreateTexture(nil, "BACKGROUND")
  slider.track:SetPoint("LEFT")
  slider.track:SetPoint("RIGHT")
  slider.track:SetHeight(4)
  slider.track:SetColorTexture(0.16, 0.16, 0.19, 1)
  slider.fill = slider:CreateTexture(nil, "ARTWORK")
  slider.fill:SetPoint("TOPLEFT", slider.track, "TOPLEFT")
  slider.fill:SetPoint("BOTTOMLEFT", slider.track, "BOTTOMLEFT")
  slider.fill:SetColorTexture(0.35, 0.62, 0.98, 1)
  slider.thumb = slider:CreateTexture(nil, "OVERLAY")
  slider.thumb:SetSize(6, 14)
  slider.thumb:SetColorTexture(0.86, 0.86, 0.90, 1)
  frame.alphaSlider = slider
  alphaRow:Add(Flex.Item(slider, { grow = 1, minW = 60, height = ROW_H }))

  frame.alphaEdit = Field(nil, true)
  frame.alphaEdit:SetMaxLetters(3)
  alphaRow:Add(Flex.Item(frame.alphaEdit, { width = 40, height = ROW_H, shrink = 0 }))

  frame.alphaPct = alphaRow.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.alphaPct:SetText("%")
  alphaRow:Add(Flex.Item(frame.alphaPct, { width = 10, shrink = 0 }))
  root:Add(alphaRow)

  -- One button. Cancel moved into the X, which is where every other window in
  -- this addon puts "stop, and put it back".
  local doneRow = Flex.Box(frame, { dir = "row", justify = "end", height = ROW_H })
  local done = CreateFrame("Button", nil, frame, "BackdropTemplate")
  done:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
  -- Pixel-snapped edges, the same treatment the options window gives its
  -- controls: a backdrop edge is one UI unit, which is a fraction of a
  -- screen pixel at most UI scales, and the four sides then round apart.
  if NS.PixelBorder then NS.PixelBorder(done) end
  done:SetBackdropColor(0.14, 0.14, 0.17, 1)
  done:SetBackdropBorderColor(0.34, 0.34, 0.40, 1)
  done.label = done:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  done.label:SetPoint("CENTER")
  done.label:SetText("Done")
  done:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.50, 0.56, 0.70, 1) end)
  done:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.34, 0.34, 0.40, 1) end)
  frame.accept = done
  doneRow:Add(Flex.Item(done, { width = 76, height = ROW_H, shrink = 0 }))
  root:Add(doneRow)

  -- Measured once: nothing in here changes height, so the frame is whatever
  -- the layout came to rather than a number kept in step by hand.
  frame:SetHeight(root:Layout(PICKER_W))
  root:Apply()
  return frame
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local state = { h = 0, s = 1, v = 1, a = 1, hasAlpha = true }

local function Current()
  local r, g, b = HSVtoRGB(state.h, state.s, state.v)
  return r, g, b, state.hasAlpha and state.a or 1
end

local function Paint()
  local frame = picker
  local r, g, b, a = Current()
  local hr, hg, hb = HSVtoRGB(state.h, 1, 1)

  frame.sv.hue:SetColorTexture(hr, hg, hb, 1)
  frame.sv.cursor:ClearAllPoints()
  frame.sv.cursor:SetPoint("CENTER", frame.sv, "TOPLEFT",
    state.s * SV_SIZE, -(1 - state.v) * SV_SIZE)
  local markY = -(state.h / 360) * SV_SIZE
  frame.hue.marker:ClearAllPoints()
  frame.hue.marker:SetPoint("LEFT", frame.hue, "TOPLEFT", -2, markY)
  frame.hue.marker:SetPoint("RIGHT", frame.hue, "TOPRIGHT", 2, markY)

  frame.compare.now:SetColorTexture(r, g, b, a)
  if not frame.hex:HasFocus() then
    frame.hex:SetText(("%02X%02X%02X"):format(
      floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)))
  end

  frame.alphaBox.fill:SetShown(state.hasAlpha)
  frame.alphaEdit:SetEnabled(state.hasAlpha)
  frame.alphaEdit:SetAlpha(state.hasAlpha and 1 or 0.4)
  frame.alphaLabel:SetAlpha(state.hasAlpha and 1 or 0.5)

  local slider = frame.alphaSlider
  local width = slider:GetWidth() or 0
  slider:SetAlpha(state.hasAlpha and 1 or 0.4)
  slider.fill:SetWidth(max(1, width * state.a))
  slider.thumb:ClearAllPoints()
  slider.thumb:SetPoint("CENTER", slider, "LEFT", width * state.a, 0)
  if not frame.alphaEdit:HasFocus() then
    frame.alphaEdit:SetText(tostring(floor(state.a * 100 + 0.5)))
  end
end

-- Writes through the swatch's own setter, then repaints everything that draws
-- a colour. This runs on every frame of a drag, so it must stay cheap and must
-- never rebuild a page.
local function Apply()
  local r, g, b, a = Current()
  if state.setColor then pcall(state.setColor, r, g, b, a) end
  Paint()
  NS.RefreshLiveSwatches()
end

local function Wire()
  local frame = picker

  local function TrackSV()
    local x, y = GetCursorPosition()
    local scale = frame.sv:GetEffectiveScale()
    x, y = x / scale, y / scale
    local left, top = frame.sv:GetLeft(), frame.sv:GetTop()
    if not left or not top then return end
    state.s = max(0, min(1, (x - left) / SV_SIZE))
    state.v = max(0, min(1, 1 - (top - y) / SV_SIZE))
    Apply()
  end

  frame.sv:SetScript("OnMouseDown", function(self)
    self.dragging = true
    TrackSV()
    self:SetScript("OnUpdate", function() if self.dragging then TrackSV() end end)
  end)
  frame.sv:SetScript("OnMouseUp", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)

  local function TrackHue()
    local _, y = GetCursorPosition()
    local scale = frame.hue:GetEffectiveScale()
    y = y / scale
    local top = frame.hue:GetTop()
    if not top then return end
    state.h = max(0, min(359.9, ((top - y) / SV_SIZE) * 360))
    Apply()
  end

  frame.hue:SetScript("OnMouseDown", function(self)
    self.dragging = true
    TrackHue()
    self:SetScript("OnUpdate", function() if self.dragging then TrackHue() end end)
  end)
  frame.hue:SetScript("OnMouseUp", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)

  local slider = frame.alphaSlider
  local function TrackAlpha()
    local x = GetCursorPosition() / slider:GetEffectiveScale()
    local left, width = slider:GetLeft(), slider:GetWidth()
    if not left or not width or width <= 0 then return end
    state.a = max(0, min(1, (x - left) / width))
    -- Dragging opacity is a statement that opacity matters, so the switch
    -- follows rather than sitting there contradicting the control beside it.
    state.hasAlpha = true
    Apply()
  end
  slider:SetScript("OnMouseDown", function(self)
    if not state.hasAlpha then state.hasAlpha = true end
    self.dragging = true
    TrackAlpha()
    self:SetScript("OnUpdate", function() if self.dragging then TrackAlpha() end end)
  end)
  slider:SetScript("OnMouseUp", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)

  frame.alphaBox:SetScript("OnClick", function()
    state.hasAlpha = not state.hasAlpha
    -- Switching opacity off means fully opaque, not "keep the number and
    -- ignore it": a colour that says 40% and paints 100% is a lie the next
    -- person to open this has to work out.
    if not state.hasAlpha then state.a = 1 end
    Apply()
  end)

  local function CommitAlpha(self)
    local value = tonumber(self:GetText()) or floor(state.a * 100 + 0.5)
    state.a = max(0, min(100, value)) / 100
    if state.a < 1 then state.hasAlpha = true end
    self:ClearFocus()
    Apply()
  end
  frame.alphaEdit:SetScript("OnEnterPressed", CommitAlpha)
  frame.alphaEdit:SetScript("OnEditFocusLost", CommitAlpha)
  frame.alphaEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Paint() end)

  local function CommitHex(self)
    local text = (self:GetText() or ""):gsub("#", ""):gsub("%s", "")
    local r, g, b = text:match("^(%x%x)(%x%x)(%x%x)$")
    if r then
      state.h, state.s, state.v =
        RGBtoHSV(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255)
      Apply()
    end
    self:ClearFocus()
    Paint()
  end
  frame.hex:SetScript("OnEnterPressed", CommitHex)
  frame.hex:SetScript("OnEditFocusLost", CommitHex)
  frame.hex:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Paint() end)

  frame.accept:SetScript("OnClick", function() NS.CloseColorPicker() end)

  -- The X is Cancel. Live editing means the profile already holds whatever was
  -- dragged over, so closing without Done is a RESTORE, not a no-op -- which
  -- is exactly what an X means everywhere: put it back the way it was.
  local function Revert()
    local was = state.original
    if was and state.setColor then
      pcall(state.setColor, was.r, was.g, was.b, was.a)
      NS.RefreshLiveSwatches()
    end
    NS.CloseColorPicker()
  end
  frame.close:SetScript("OnClick", Revert)
  frame.revert = Revert
end

function NS.CloseColorPicker()
  if picker then picker:Hide() end
  if scrim then scrim:Hide() end
  state.setColor = nil
end

-- anchor: the swatch that asked. opts.hasAlpha = false for a colour whose
-- alpha means nothing (a border edge reads as opaque or invisible).
function NS.OpenColorPicker(anchor, colour, setColor, opts)
  opts = opts or {}
  if not picker then
    picker = Build()
    Wire()
  end

  colour = colour or { r = 1, g = 1, b = 1, a = 1 }
  state.original = { r = colour.r, g = colour.g, b = colour.b, a = colour.a or 1 }
  state.setColor = setColor
  -- `hasAlpha = false` is a caller saying alpha means nothing for this colour.
  -- The switch still appears -- hiding a control because it is off is how you
  -- get "where did the opacity go" -- it simply starts off.
  state.hasAlpha = opts.hasAlpha ~= false
  state.a = state.hasAlpha and (colour.a or 1) or 1
  state.h, state.s, state.v = RGBtoHSV(colour.r, colour.g, colour.b)

  picker.compare.was:SetColorTexture(colour.r, colour.g, colour.b, colour.a or 1)

  -- Dim whatever this belongs to. The options window when there is one, the
  -- screen otherwise -- a colour can be picked from a slash command with no
  -- window open.
  local host = NS.OptionsWindow and NS.OptionsWindow() or nil
  local dim = Scrim()
  dim:ClearAllPoints()
  if host and host:IsShown() then
    dim:SetPoint("TOPLEFT", host, "TOPLEFT")
    dim:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT")
    dim:SetFrameLevel(math.max(1, (host:GetFrameLevel() or 1) + 20))
  else
    dim:SetAllPoints(UIParent)
  end
  dim:Show()

  picker:ClearAllPoints()
  if host and host:IsShown() then
    -- Over the window it dimmed, centred: the surface behind is deliberately
    -- out of play, so there is nothing to sit politely beside.
    picker:SetPoint("CENTER", host, "CENTER", 0, 0)
  elseif anchor then
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 8, 0)
  else
    picker:SetPoint("CENTER")
  end
  picker:SetFrameLevel(dim:GetFrameLevel() + 10)

  Paint()
  picker:Show()
  picker:Raise()
  return picker
end

function NS.ColorPickerShown()
  return picker and picker:IsShown()
end
