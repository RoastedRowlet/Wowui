--[[
	PI Helper options widgets. Shared cards, controls, dropdown, and scroll area.
	Tabs talk to addon.db / addon.ApplySettings through these helpers.
	Sliders debounce 0.15s and use paint/grace applies instead of a full rebuild.
]]

local ADDON_NAME, addon = ...

local C = addon.C
local FONT = addon.FONT

local function NamedFont(name, size)
	local font = _G[name] or CreateFont(name)
	font:SetFont(FONT, size, "")
	return font
end
NamedFont("PIH_FontTitle", 18)
NamedFont("PIH_FontLarge", 15)
NamedFont("PIH_FontSmall", 12)
NamedFont("PIH_FontTiny", 11)

local widgets = {}
local scrollAreas = {}
local borderedFrames = {}
local hairlines = {}

local function DB()
	return addon.db
end

local function Fill(parent, layer, r, g, b, a)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetAllPoints()
	texture:SetColorTexture(r, g, b, a or 1)
	return texture
end

local function DisableSnap(tex)
	if tex.SetSnapToPixelGrid then
		pcall(tex.SetSnapToPixelGrid, tex, false)
	end
	if tex.SetTexelSnappingBias then
		pcall(tex.SetTexelSnappingBias, tex, 0)
	end
end

-- Local size that maps to a whole number of physical pixels after UI / options scale.
local function HairlineSize(region, pixels)
	pixels = pixels or 1
	local scale = region and region.GetEffectiveScale and region:GetEffectiveScale() or 1
	if not scale or scale == 0 then
		scale = 1
	end
	if PixelUtil and PixelUtil.GetNearestPixelSize then
		return PixelUtil.GetNearestPixelSize(pixels, scale, pixels)
	end
	local _, screenH = GetPhysicalScreenSize()
	if not screenH or screenH <= 0 then
		return pixels
	end
	local factor = 768 / screenH
	local num = math.floor((pixels * scale) / factor + 0.5)
	if num < pixels then
		num = pixels
	end
	return num * factor / scale
end

local function LayoutBorder(parent)
	local b = parent and parent.border
	if not b then
		return
	end
	local px = HairlineSize(parent, 1)
	b.top:SetHeight(px)
	b.bottom:SetHeight(px)
	b.left:SetWidth(px)
	b.right:SetWidth(px)
end

local function ApplyHairline(entry)
	local tex = entry and entry.tex
	if not tex then
		return
	end
	local px = HairlineSize(tex, entry.pixels or 1)
	if entry.axis == "v" then
		tex:SetWidth(px)
	else
		tex:SetHeight(px)
	end
end

local function RefreshPixels()
	for i = 1, #borderedFrames do
		LayoutBorder(borderedFrames[i])
	end
	for i = 1, #hairlines do
		ApplyHairline(hairlines[i])
	end
end

local function Hairline(tex, axis, pixels)
	if not tex then
		return tex
	end
	DisableSnap(tex)
	local entry = { tex = tex, axis = axis or "h", pixels = pixels or 1 }
	hairlines[#hairlines + 1] = entry
	ApplyHairline(entry)
	return tex
end

local function AddBorder(parent, r, g, b, a)
	parent.border = {
		top    = parent:CreateTexture(nil, "OVERLAY"),
		bottom = parent:CreateTexture(nil, "OVERLAY"),
		left   = parent:CreateTexture(nil, "OVERLAY"),
		right  = parent:CreateTexture(nil, "OVERLAY"),
	}
	parent.border.top:SetPoint("TOPLEFT")
	parent.border.top:SetPoint("TOPRIGHT")
	parent.border.bottom:SetPoint("BOTTOMLEFT")
	parent.border.bottom:SetPoint("BOTTOMRIGHT")
	parent.border.left:SetPoint("TOPLEFT")
	parent.border.left:SetPoint("BOTTOMLEFT")
	parent.border.right:SetPoint("TOPRIGHT")
	parent.border.right:SetPoint("BOTTOMRIGHT")
	for _, tex in pairs(parent.border) do
		DisableSnap(tex)
	end
	function parent:SetBorderColor(cr, cg, cb, ca)
		for _, tex in pairs(self.border) do
			tex:SetColorTexture(cr, cg, cb, ca or 1)
		end
	end
	parent:SetBorderColor(r, g, b, a)
	borderedFrames[#borderedFrames + 1] = parent
	LayoutBorder(parent)
end

local function ApplySettings()
	if addon.ApplySettings then
		addon.ApplySettings()
	end
end

local SLIDER_DEBOUNCE = 0.15
local sliderApplyQueued
local pendingPaint
local pendingGrace
local pendingFull
local pendingOptionsScale

local function FlushSliderApply()
	sliderApplyQueued = false
	local full, paint, grace, optScale = pendingFull, pendingPaint, pendingGrace, pendingOptionsScale
	pendingFull, pendingPaint, pendingGrace, pendingOptionsScale = nil, nil, nil, nil
	if optScale and addon.ApplyOptionsScale then
		addon.ApplyOptionsScale()
	end
	if not addon.ApplySettings then
		return
	end
	if full then
		addon.ApplySettings()
		return
	end
	if paint then
		addon.ApplySettings("paint")
	end
	if grace then
		addon.ApplySettings("grace")
	end
end

local function QueueSliderApply(mode)
	if mode == "none" then
		return
	end
	if mode == "optionsScale" then
		pendingOptionsScale = true
		return
	end
	if mode == "full" then
		pendingFull = true
	elseif mode == "grace" then
		pendingGrace = true
	else
		pendingPaint = true
	end
	if sliderApplyQueued then
		return
	end
	sliderApplyQueued = true
	C_Timer.After(SLIDER_DEBOUNCE, function()
		if sliderApplyQueued then
			FlushSliderApply()
		end
	end)
end

local function MakeHeader(parent, text)
	local lbl = parent:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	lbl:SetText(string.upper(text or ""))
	lbl:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	return lbl
end

local function MakeHelp(parent, text)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(14, 14)
	local mark = btn:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	mark:SetPoint("CENTER", 0, 1)
	mark:SetText("?")
	mark:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, C.text[1], C.text[2], C.text[3], 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn
end

local function MakeWarning(parent, title, body)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(24, 24)
	btn.keepMouse = true
	local mark = btn:CreateFontString(nil, "OVERLAY")
	mark:SetFont(FONT, 22, "OUTLINE")
	mark:SetPoint("CENTER", 0, 1)
	mark:SetText("!")
	mark:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
	btn:SetScript("OnEnter", function(self)
		mark:SetTextColor(1, 0.45, 0.48)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, C.danger[1], C.danger[2], C.danger[3], 1, true)
		if body then
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine(body, C.text[1], C.text[2], C.text[3], true)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		mark:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
		GameTooltip:Hide()
	end)
	btn:SetScript("OnClick", function() end)
	return btn
end

local function MakePanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	Fill(panel, "BACKGROUND", C.panel[1], C.panel[2], C.panel[3], 1)
	AddBorder(panel, C.border[1], C.border[2], C.border[3])
	return panel
end

local function BeginCard(parent, y, title, opts)
	opts = opts or {}
	local panel = MakePanel(parent)
	if not opts.free then
		panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
		panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
	end
	local header = MakeHeader(panel, title)
	header:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
	panel.header = header
	return panel, -32
end

local function EndCard(panel, y)
	local h = math.max(48, -y + 12)
	panel:SetHeight(h)
	return h
end

local function PaintCheck(box, mark, checked)
	if checked then
		box:SetBorderColor(C.accent[1], C.accent[2], C.accent[3])
		box.bg:SetColorTexture(0.28, 0.18, 0.05, 1)
		mark:Show()
	else
		box:SetBorderColor(C.border[1], C.border[2], C.border[3])
		box.bg:SetColorTexture(0.10, 0.11, 0.12, 1)
		mark:Hide()
	end
end

local function MakeCheckBox(parent, size)
	size = size or 14
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	box:EnableMouse(false)
	box.bg = Fill(box, "BACKGROUND", 0.10, 0.11, 0.12, 1)
	AddBorder(box, C.border[1], C.border[2], C.border[3])
	local mark = box:CreateTexture(nil, "OVERLAY")
	mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	mark:SetSize(size + 2, size + 2)
	mark:SetPoint("CENTER", 0, 0)
	mark:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	box.mark = mark
	return box, mark
end

local function RegisterWidget(frame)
	widgets[#widgets + 1] = frame
	return frame
end

local function MakeCheckbox(parent, text, desc, getter, setter, help)
	local frame = CreateFrame("Button", nil, parent)
	frame:SetHeight(desc and 38 or 22)

	local box, mark = MakeCheckBox(frame, 14)
	box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, desc and -2 or -4)

	local lbl = frame:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	lbl:SetPoint("LEFT", box, "RIGHT", 8, desc and 6 or 0)
	lbl:SetJustifyH("LEFT")
	lbl:SetText(text or "")
	lbl:SetTextColor(C.text[1], C.text[2], C.text[3])
	frame.box = box
	frame.label = lbl
	if type(help) == "table" and help.warning then
		if not desc then
			frame:SetHeight(26)
		end
		local warnBtn = MakeWarning(frame, help.title, help.body)
		warnBtn:SetPoint("RIGHT", frame, "RIGHT", 0, desc and 6 or 0)
		warnBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 2)
		frame.warningBtn = warnBtn
		lbl:SetPoint("RIGHT", warnBtn, "LEFT", -4, desc and 6 or 0)
	elseif help then
		local helpBtn = MakeHelp(frame, help)
		helpBtn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
		helpBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 2)
		frame.helpBtn = helpBtn
	else
		lbl:SetPoint("RIGHT", frame, "RIGHT", 0, desc and 6 or 0)
	end

	if desc then
		local d = frame:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
		d:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
		d:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
		d:SetJustifyH("LEFT")
		d:SetWordWrap(true)
		d:SetText(desc)
		d:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
		frame.desc = d
		function frame:FitDesc()
			local h = self.desc:GetStringHeight()
			if type(h) ~= "number" or h < 1 then
				h = 12
			end
			self:SetHeight(math.ceil(20 + h + 8))
		end
	end

	local checked = false
	local function apply()
		PaintCheck(box, mark, checked)
	end

	frame:SetScript("OnClick", function()
		checked = not checked
		apply()
		if setter then
			setter(checked)
		end
		ApplySettings()
	end)

	function frame:Refresh()
		checked = getter and getter() and true or false
		apply()
	end

	frame:Refresh()
	return RegisterWidget(frame)
end

local function MakeSlider(parent, label, minV, maxV, step, fmt, getter, setter, help, applyMode)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(36)
	applyMode = applyMode or "paint"

	local lbl = frame:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	lbl:SetPoint("TOPLEFT")
	lbl:SetText(label or "")
	lbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	if help then
		local helpBtn = MakeHelp(frame, help)
		helpBtn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
	end

	local valLbl = frame:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	valLbl:SetPoint("TOPRIGHT")
	valLbl:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])

	local track = frame:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -22)
	track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -22)
	track:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
	Hairline(track, "h", 2)

	local fill = frame:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	Hairline(fill, "h", 2)
	fill:SetWidth(1)

	local sl = CreateFrame("Slider", nil, frame)
	sl:SetHeight(14)
	sl:SetPoint("LEFT", track, "LEFT")
	sl:SetPoint("RIGHT", track, "RIGHT")
	sl:SetOrientation("HORIZONTAL")
	sl:EnableMouse(true)
	sl:SetMinMaxValues(minV, maxV)
	sl:SetValueStep(step)
	sl:SetObeyStepOnDrag(true)

	local thumb = sl:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(8, 8)
	thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	sl:SetThumbTexture(thumb)

	local function updateFill(val)
		local w = track:GetWidth()
		if not w or w <= 0 then
			return
		end
		local ratio = (val - minV) / math.max(maxV - minV, 0.001)
		fill:SetWidth(math.max(1, w * math.max(0, math.min(1, ratio))))
	end

	sl:SetScript("OnValueChanged", function(_, val)
		val = math.floor(val + 0.5)
		valLbl:SetText(fmt and fmt(val) or tostring(val))
		updateFill(val)
		if frame._silent then
			return
		end
		if setter then
			setter(val)
		end
		QueueSliderApply(applyMode)
	end)

	sl:SetScript("OnMouseUp", FlushSliderApply)

	function frame:Refresh()
		frame._silent = true
		local val = getter and getter() or minV
		sl:SetValue(val)
		valLbl:SetText(fmt and fmt(val) or tostring(val))
		updateFill(val)
		frame._silent = false
	end

	local function relayout()
		updateFill(sl:GetValue() or minV)
	end
	frame.LayoutFill = relayout
	frame:SetScript("OnShow", function()
		frame:Refresh()
	end)
	frame:SetScript("OnSizeChanged", function()
		relayout()
		C_Timer.After(0, relayout)
	end)
	return RegisterWidget(frame)
end

local function PaintButtonForeground(btn, r, g, b)
	if btn.label then
		btn.label:SetTextColor(r, g, b)
	end
	if btn.chevron then
		btn.chevron:SetVertexColor(r, g, b, 1)
	end
end

local function MakeButton(parent, text, accent)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(24)
	Fill(btn, "BACKGROUND", 0.16, 0.18, 0.19, 1)
	AddBorder(btn, C.border[1], C.border[2], C.border[3])
	local lbl = btn:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	lbl:SetPoint("CENTER")
	lbl:SetText(text)
	btn.label = lbl
	if accent then
		btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3])
		PaintButtonForeground(btn, C.textAccent[1], C.textAccent[2], C.textAccent[3])
	else
		PaintButtonForeground(btn, C.text[1], C.text[2], C.text[3])
	end
	btn:SetScript("OnEnter", function()
		btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3])
		PaintButtonForeground(btn, C.textAccent[1], C.textAccent[2], C.textAccent[3])
	end)
	btn:SetScript("OnLeave", function()
		if btn.selected or accent then
			btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3])
			PaintButtonForeground(btn, C.textAccent[1], C.textAccent[2], C.textAccent[3])
		else
			btn:SetBorderColor(C.border[1], C.border[2], C.border[3])
			PaintButtonForeground(btn, C.text[1], C.text[2], C.text[3])
		end
	end)
	return btn
end

local CHEVRON_TEX = "Interface\\AddOns\\PIHelper\\media\\chevron-up.tga"

local function SetChevronDir(tex, dir)
	if dir == "down" then
		tex:SetSize(12, 8)
		tex:SetTexCoord(0, 1, 1, 0)
	elseif dir == "right" then
		tex:SetSize(8, 12)
		tex:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
	elseif dir == "left" then
		tex:SetSize(8, 12)
		tex:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
	else
		tex:SetSize(12, 8)
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

local function MakeChevron(parent, dir)
	local tex = parent:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(CHEVRON_TEX)
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
	end
	if tex.SetTexelSnappingBias then
		tex:SetTexelSnappingBias(0)
	end
	SetChevronDir(tex, dir or "up")
	tex:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
	return tex
end

local function AttachChevron(btn, dir)
	if btn.label then
		btn.label:Hide()
	end
	local tex = MakeChevron(btn, dir)
	tex:SetPoint("CENTER", 0, dir == "up" and 0.5 or -0.5)
	btn.chevron = tex
	PaintButtonForeground(btn, C.text[1], C.text[2], C.text[3])
end

local function PaintChoice(btn, on)
	btn.selected = on and true or false
	if on then
		btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3])
		btn.label:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
	else
		btn:SetBorderColor(C.border[1], C.border[2], C.border[3])
		btn.label:SetTextColor(C.text[1], C.text[2], C.text[3])
	end
end

local function MakeChoiceRow(parent, items, getter, setter)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(24)
	row.buttons = {}
	for i = 1, #items do
		local item = items[i]
		local btn = MakeButton(row, item.name)
		local width = math.max(72, (btn.label:GetStringWidth() or 60) + 18)
		btn.naturalWidth = width
		btn:SetWidth(width)
		btn.id = item.id
		btn:SetScript("OnClick", function()
			setter(item.id)
			row:Refresh()
			ApplySettings()
		end)
		if item.tooltip then
			local onEnter = btn:GetScript("OnEnter")
			local onLeave = btn:GetScript("OnLeave")
			btn:SetScript("OnEnter", function(self)
				if onEnter then
					onEnter(self)
				end
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(item.tooltip, C.text[1], C.text[2], C.text[3], 1, true)
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function(self)
				if onLeave then
					onLeave(self)
				end
				GameTooltip:Hide()
			end)
		end
		row.buttons[i] = btn
	end
	function row:LayoutChoices()
		if self._layingOut then
			return
		end
		self._layingOut = true
		local width = self:GetWidth() or 0
		local gap = 6
		local btnH = 24
		local n = #self.buttons
		if n == 0 then
			self._layingOut = false
			return
		end
		if width > 10 then
			local equal = (width - (n - 1) * gap) / n
			if equal >= 68 then
				for i = 1, n do
					local btn = self.buttons[i]
					btn:SetWidth(equal)
					btn:ClearAllPoints()
					btn:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (equal + gap), 0)
				end
				self:SetHeight(btnH)
				self._layingOut = false
				return
			end
		end
		local lines = { { start = 1, count = 0 } }
		local x = 0
		for i = 1, n do
			local bw = self.buttons[i].naturalWidth or 72
			local cur = lines[#lines]
			if width > 10 and cur.count > 0 and (x + bw) > width + 0.5 then
				lines[#lines + 1] = { start = i, count = 0 }
				cur = lines[#lines]
				x = 0
			end
			cur.count = cur.count + 1
			x = x + bw + gap
		end
		if #lines >= 2 then
			local last = lines[#lines]
			local prev = lines[#lines - 1]
			if last.count == 1 and prev.count >= 3 then
				prev.count = prev.count - 1
				last.start = last.start - 1
				last.count = last.count + 1
			end
		end
		local index = 1
		for line = 1, #lines do
			x = 0
			for _ = 1, lines[line].count do
				local btn = self.buttons[index]
				local bw = btn.naturalWidth or 72
				btn:SetWidth(bw)
				btn:ClearAllPoints()
				btn:SetPoint("TOPLEFT", self, "TOPLEFT", x, -((line - 1) * (btnH + gap)))
				x = x + bw + gap
				index = index + 1
			end
		end
		self:SetHeight(#lines * btnH + math.max(0, #lines - 1) * gap)
		self._layingOut = false
	end
	row:SetScript("OnSizeChanged", function()
		row:LayoutChoices()
	end)
	function row:Refresh()
		local cur = getter()
		for i = 1, #self.buttons do
			PaintChoice(self.buttons[i], self.buttons[i].id == cur)
		end
	end
	row:LayoutChoices()
	row:Refresh()
	return RegisterWidget(row)
end

local function MakeColorSwatch(parent, label, getRGBA, setRGBA)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(28)
	local swatch = CreateFrame("Frame", nil, row)
	swatch:SetSize(22, 22)
	swatch:SetPoint("LEFT", 0, 0)
	swatch.bg = Fill(swatch, "ARTWORK", 234 / 255, 162 / 255, 33 / 255, 1)
	AddBorder(swatch, C.border[1], C.border[2], C.border[3])
	local lbl = row:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	lbl:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
	lbl:SetText(label or "Glow color")
	lbl:SetTextColor(C.text[1], C.text[2], C.text[3])

	local function current()
		if getRGBA then
			return getRGBA()
		end
		local db = DB()
		return db.glowR or (234 / 255), db.glowG or (162 / 255), db.glowB or (33 / 255), db.glowA or 0.9
	end

	local function paint()
		local r, g, b, a = current()
		swatch.bg:SetColorTexture(r, g, b, a or 1)
	end

	local function OpenPicker()
		local r0, g0, b0, a0 = current()
		local function apply()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = ColorPickerFrame:GetColorAlpha()
			if setRGBA then
				setRGBA(r, g, b, a)
			else
				local db = DB()
				db.glowR, db.glowG, db.glowB, db.glowA = r, g, b, a
			end
			paint()
			QueueSliderApply("paint")
		end
		local info = {
			r = r0,
			g = g0,
			b = b0,
			opacity = a0,
			hasOpacity = true,
			swatchFunc = apply,
			opacityFunc = apply,
			cancelFunc = function()
				local pr, pg, pb, pa = ColorPickerFrame:GetPreviousValues()
				pr, pg, pb, pa = pr or r0, pg or g0, pb or b0, pa or a0
				if setRGBA then
					setRGBA(pr, pg, pb, pa or a0)
				else
					local db = DB()
					db.glowR, db.glowG, db.glowB, db.glowA = pr, pg, pb, pa or a0
				end
				paint()
				if addon.ApplySettings then
					addon.ApplySettings("paint")
				end
			end,
		}
		ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
		ColorPickerFrame:SetToplevel(true)
		ColorPickerFrame:SetupColorPickerAndShow(info)
	end

	row:SetScript("OnClick", OpenPicker)
	function row:Refresh()
		paint()
	end
	row:Refresh()
	return RegisterWidget(row)
end

local function MakeEditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width or 180, 22)
	box:SetAutoFocus(false)
	box:SetFont(FONT, 12, "")
	box:SetTextColor(C.text[1], C.text[2], C.text[3])
	box:SetTextInsets(6, 6, 0, 0)
	Fill(box, "BACKGROUND", 0.07, 0.08, 0.09, 1)
	AddBorder(box, C.border[1], C.border[2], C.border[3])
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if self.OnSubmit then
			self.OnSubmit(self:GetText())
		end
	end)
	return box
end

local NAME_ROW_H = 26

local function FillNameList(host, names, onChange)
	if not host then
		return 20
	end
	host.rows = host.rows or {}
	for i = 1, #host.rows do
		host.rows[i]:Hide()
	end
	local y = 0
	for i = 1, #names do
		local index = i
		local row = host.rows[i]
		if not row then
			row = CreateFrame("Button", nil, host)
			row:SetHeight(22)
			row.bg = Fill(row, "BACKGROUND", C.accent[1], C.accent[2], C.accent[3], 0)
			row.label = row:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
			row.label:SetPoint("LEFT", 4, 0)
			row.label:SetJustifyH("LEFT")
			row.label:SetWordWrap(false)
			row.label:SetTextColor(C.text[1], C.text[2], C.text[3])
			row.del = MakeButton(row, "x")
			row.del:SetSize(22, 20)
			row.del:SetPoint("RIGHT")
			row.label:SetPoint("RIGHT", row.del, "LEFT", -8, 0)
			row.del:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
			row:SetScript("OnEnter", function(self)
				self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
			end)
			row:SetScript("OnLeave", function(self)
				self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0)
			end)
			host.rows[i] = row
		end
		row:Show()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, y)
		row.label:SetText(names[index])
		row.del:SetScript("OnClick", function()
			table.remove(names, index)
			if onChange then
				onChange()
			end
		end)
		y = y - NAME_ROW_H
	end
	local h = math.max(20, -y)
	host:SetHeight(h)
	return h
end

local function Pair(parent, left, right, y, inset, gap)
	inset = inset or 0
	gap = gap or 10
	left:ClearAllPoints()
	right:ClearAllPoints()
	left:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, y)
	left:SetPoint("TOPRIGHT", parent, "TOP", -gap / 2, y)
	right:SetPoint("TOPLEFT", parent, "TOP", gap / 2, y)
	right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, y)
	if left.FitDesc then
		left:FitDesc()
	end
	if right.FitDesc then
		right:FitDesc()
	end
	if left.LayoutFill then
		left:LayoutFill()
	end
	if right.LayoutFill then
		right:LayoutFill()
	end
	return math.max(left:GetHeight() or 0, right:GetHeight() or 0)
end

local function Stack(parent, items, startY, spacing, inset)
	local y = startY
	local pad = inset or 0
	local gap = spacing or 8
	for i = 1, #items do
		local item = items[i]
		local h
		if type(item) == "table" and item[1] and item[2] then
			h = Pair(parent, item[1], item[2], y, pad, 10)
		else
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
			item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, y)
			if item.FitDesc then
				item:FitDesc()
			end
			if item.LayoutChoices then
				item:LayoutChoices()
			end
			if item.LayoutFill then
				item:LayoutFill()
			end
			h = item:GetHeight() or 0
		end
		y = y - h
		if i < #items then
			y = y - gap
		end
	end
	return y
end

local function SetMouseDeep(frame, on)
	if not frame then
		return
	end
	if frame.keepMouse then
		return
	end
	if frame.EnableMouse then
		if frame._wantMouse == nil then
			frame._wantMouse = frame:IsMouseEnabled() and true or false
		end
		frame:EnableMouse(on and frame._wantMouse)
	end
	if frame.EnableKeyboard then
		if frame._wantKeyboard == nil then
			local want = true
			if frame.IsKeyboardEnabled then
				want = frame:IsKeyboardEnabled() and true or false
			end
			frame._wantKeyboard = want
		end
		frame:EnableKeyboard(on and frame._wantKeyboard)
	end
	if not on and frame.ClearFocus then
		frame:ClearFocus()
	end
	if not frame.GetChildren then
		return
	end
	local kids = { frame:GetChildren() }
	for i = 1, #kids do
		SetMouseDeep(kids[i], on)
	end
end

local function SetOptionLocked(frame, on)
	if not frame then
		return
	end
	if frame.SetAlpha then
		frame:SetAlpha(on and 1 or 0.4)
	end
	SetMouseDeep(frame, on)
end

local dropMenu
local dropCatcher
local dropOwner
local DROP_ROW_H = 22
local DROP_MAX_ROWS = 8

local function CloseDropMenu()
	if dropMenu then
		dropMenu:Hide()
	end
	if dropCatcher then
		dropCatcher:Hide()
	end
	dropOwner = nil
end

local function ItemList(items)
	if type(items) == "function" then
		return items() or {}
	end
	return items or {}
end

local function DropLabel(items, id)
	items = ItemList(items)
	for i = 1, #items do
		if items[i].id == id then
			return items[i].name
		end
	end
	if type(id) == "string" and id ~= "" then
		return id
	end
	if id ~= nil then
		return "Sound " .. tostring(id)
	end
	if items[1] then
		return items[1].name
	end
	return ""
end

local function EnsureDropMenu()
	if dropCatcher then
		return
	end
	dropCatcher = CreateFrame("Button", nil, UIParent)
	dropCatcher:SetAllPoints(UIParent)
	dropCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
	dropCatcher:SetFrameLevel(1)
	dropCatcher:Hide()
	dropCatcher:SetScript("OnClick", CloseDropMenu)

	dropMenu = CreateFrame("Frame", "PIHelperDropMenu", UIParent)
	dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
	dropMenu:SetFrameLevel(20)
	dropMenu:SetClampedToScreen(true)
	dropMenu:EnableMouse(true)
	dropMenu:EnableMouseWheel(true)
	Fill(dropMenu, "BACKGROUND", C.panel[1], C.panel[2], C.panel[3], 1)
	AddBorder(dropMenu, C.accent[1], C.accent[2], C.accent[3])
	dropMenu:Hide()

	local scroll = CreateFrame("ScrollFrame", nil, dropMenu)
	scroll:SetPoint("TOPLEFT", 1, -1)
	scroll:SetPoint("BOTTOMRIGHT", -1, 1)
	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, scroll)
	scroll:SetScrollChild(child)
	dropMenu.scroll = scroll
	dropMenu.child = child
	dropMenu.rows = {}

	local scrollBar = CreateFrame("Frame", nil, dropMenu)
	scrollBar:SetWidth(6)
	scrollBar:SetFrameLevel((dropMenu:GetFrameLevel() or 20) + 5)
	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
	local scrollThumb = CreateFrame("Button", nil, scrollBar)
	scrollThumb:SetWidth(6)
	local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetAllPoints()
	thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	dropMenu.bar = scrollBar
	dropMenu.thumb = scrollThumb

	local function UpdateDropScroll()
		local range = scroll:GetVerticalScrollRange() or 0
		local viewH = scroll:GetHeight() or 0
		if range <= 1 or viewH <= 0 then
			scrollBar:Hide()
			scroll:SetPoint("BOTTOMRIGHT", -1, 1)
			return
		end
		scroll:SetPoint("BOTTOMRIGHT", -8, 1)
		scrollBar:Show()
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -2, -2)
		scrollBar:SetPoint("BOTTOMRIGHT", dropMenu, "BOTTOMRIGHT", -2, 2)
		local trackH = scrollBar:GetHeight() or 0
		if trackH <= 0 then
			return
		end
		local thumbH = math.max(20, trackH * (viewH / (viewH + range)))
		if thumbH > trackH then
			thumbH = trackH
		end
		local cur = scroll:GetVerticalScroll() or 0
		local y = (trackH - thumbH) * (cur / range)
		scrollThumb:SetHeight(thumbH)
		scrollThumb:ClearAllPoints()
		scrollThumb:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, -y)
		scrollThumb:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, -y)
	end
	dropMenu.UpdateScroll = UpdateDropScroll

	local function ScrollDrop(delta)
		local range = scroll:GetVerticalScrollRange() or 0
		if range <= 0 then
			return
		end
		local nextVal = (scroll:GetVerticalScroll() or 0) - (delta * DROP_ROW_H * 3)
		if nextVal < 0 then
			nextVal = 0
		elseif nextVal > range then
			nextVal = range
		end
		scroll:SetVerticalScroll(nextVal)
		UpdateDropScroll()
	end
	scroll:SetScript("OnMouseWheel", function(_, delta)
		ScrollDrop(delta)
	end)
	dropMenu:SetScript("OnMouseWheel", function(_, delta)
		ScrollDrop(delta)
	end)
	scroll:SetScript("OnVerticalScroll", function()
		UpdateDropScroll()
	end)
	scrollBar:EnableMouse(true)
	scrollBar:EnableMouseWheel(true)
	scrollBar:SetScript("OnMouseWheel", function(_, delta)
		ScrollDrop(delta)
	end)

	local function ThumbToCursor()
		local scale = scrollBar:GetEffectiveScale()
		local _, cursorY = GetCursorPosition()
		cursorY = cursorY / scale
		local top = scrollBar:GetTop()
		local trackH = scrollBar:GetHeight() or 0
		local thumbH = scrollThumb:GetHeight() or 0
		local offset = (top - cursorY) - (thumbH / 2)
		local maxOff = math.max(1, trackH - thumbH)
		if offset < 0 then
			offset = 0
		elseif offset > maxOff then
			offset = maxOff
		end
		local range = scroll:GetVerticalScrollRange() or 0
		scroll:SetVerticalScroll(range * (offset / maxOff))
		UpdateDropScroll()
	end
	scrollThumb:SetScript("OnEnter", function()
		thumbTex:SetColorTexture(C.textAccent[1], C.textAccent[2], C.textAccent[3], 1)
	end)
	scrollThumb:SetScript("OnLeave", function()
		if not scrollThumb._dragging then
			thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
		end
	end)
	scrollThumb:SetScript("OnMouseDown", function()
		scrollThumb._dragging = true
		scrollThumb:SetScript("OnUpdate", ThumbToCursor)
	end)
	local function StopDrag()
		scrollThumb._dragging = false
		scrollThumb:SetScript("OnUpdate", nil)
		thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	end
	scrollThumb:SetScript("OnMouseUp", StopDrag)
	scrollThumb:SetScript("OnHide", StopDrag)
	scrollBar:SetScript("OnMouseDown", function()
		ThumbToCursor()
	end)
end

local function EnsureSoundPreview(row)
	if row.preview then
		return
	end
	local preview = CreateFrame("Button", nil, row)
	preview:SetSize(16, 16)
	preview:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	local icon = preview:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(130979)
	icon:SetAllPoints()
	local highlight = preview:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture(130977)
	highlight:SetAllPoints()
	preview:SetScript("OnClick", function(self)
		if addon.PlaySoundByID then
			addon.PlaySoundByID(self.soundID)
		end
	end)
	row.preview = preview
end

local function OpenDropMenu(owner, items, getter, setter, opts)
	EnsureDropMenu()
	if dropOwner == owner and dropMenu:IsShown() then
		CloseDropMenu()
		return
	end
	dropOwner = owner
	opts = opts or {}
	if addon.GetOptionsScale then
		dropMenu:SetScale(addon.GetOptionsScale())
	else
		dropMenu:SetScale(1)
	end
	RefreshPixels()
	items = ItemList(items)
	local selected = getter()
	local width = math.max(owner:GetWidth() or 180, 160)
	local rowH = DROP_ROW_H
	local child = dropMenu.child
	local scroll = dropMenu.scroll
	local previewSounds = opts.previewSounds and true or false
	for i = 1, #items do
		local item = items[i]
		local row = dropMenu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, child)
			row:SetHeight(rowH)
			row.bg = Fill(row, "BACKGROUND", 0, 0, 0, 0)
			row.label = row:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
			row.label:SetPoint("LEFT", 10, 0)
			row.label:SetPoint("RIGHT", -8, 0)
			row.label:SetJustifyH("LEFT")
			row:SetScript("OnEnter", function(self)
				self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
			end)
			row:SetScript("OnLeave", function(self)
				if self.selected then
					self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
				else
					self.bg:SetColorTexture(0, 0, 0, 0)
				end
			end)
			dropMenu.rows[i] = row
		end
		row:SetParent(child)
		row:Show()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((i - 1) * rowH))
		row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -((i - 1) * rowH))
		if previewSounds then
			EnsureSoundPreview(row)
			row.preview:Show()
			row.preview.soundID = item.id
			row.label:SetPoint("RIGHT", row.preview, "LEFT", -4, 0)
		else
			if row.preview then
				row.preview:Hide()
			end
			row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		end
		row.label:SetText(item.name)
		row.selected = item.id == selected
		if row.selected then
			row.label:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
			row.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
		else
			row.label:SetTextColor(C.text[1], C.text[2], C.text[3])
			row.bg:SetColorTexture(0, 0, 0, 0)
		end
		row:SetScript("OnClick", function()
			setter(item.id)
			CloseDropMenu()
			if owner.Refresh then
				owner:Refresh()
			end
			ApplySettings()
		end)
	end
	for i = #items + 1, #dropMenu.rows do
		dropMenu.rows[i]:Hide()
	end

	local contentH = math.max(rowH, #items * rowH)
	local maxH = (opts.maxRows or DROP_MAX_ROWS) * rowH
	local dropScale = dropMenu:GetEffectiveScale() or 1
	if dropScale == 0 then
		dropScale = 1
	end
	local ownerScale = owner:GetEffectiveScale() or 1
	local uiScale = UIParent:GetEffectiveScale() or 1
	local ownerBottom = (owner:GetBottom() or 0) * ownerScale / dropScale
	local ownerTop = (owner:GetTop() or 0) * ownerScale / dropScale
	local uiTop = (UIParent:GetTop() or 0) * uiScale / dropScale
	local spaceBelow = math.max(rowH, ownerBottom - 24)
	local spaceAbove = math.max(rowH, uiTop - ownerTop - 24)
	local needH = math.min(contentH, maxH)
	local openUp = spaceBelow < needH and spaceAbove > spaceBelow
	local viewH = math.min(needH, openUp and spaceAbove or spaceBelow)
	viewH = math.max(rowH, viewH)
	local needsBar = contentH > viewH + 1
	local innerW = math.max(80, width - 2 - (needsBar and 8 or 0))
	child:SetSize(innerW, contentH)

	dropMenu:SetSize(width, viewH + 2)
	dropMenu:ClearAllPoints()
	if openUp then
		dropMenu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	else
		dropMenu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
	local selectedY = 0
	for i = 1, #items do
		if items[i].id == selected then
			selectedY = (i - 1) * rowH
			break
		end
	end
	local maxScroll = math.max(0, contentH - viewH)
	local startScroll = selectedY - (viewH / 2) + (rowH / 2)
	if startScroll < 0 then
		startScroll = 0
	elseif startScroll > maxScroll then
		startScroll = maxScroll
	end
	scroll:SetVerticalScroll(startScroll)
	if dropMenu.UpdateScroll then
		dropMenu.UpdateScroll()
	end
	dropCatcher:Show()
	dropMenu:Show()
	if dropMenu.UpdateScroll then
		C_Timer.After(0, dropMenu.UpdateScroll)
	end
end

local function MakeDropdown(parent, label, items, getter, setter, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(42)
	local lbl = frame:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	lbl:SetPoint("TOPLEFT")
	lbl:SetText(label or "")
	lbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	if opts.tooltip then
		lbl:EnableMouse(true)
		lbl:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(opts.tooltip, C.text[1], C.text[2], C.text[3], 1, true)
			GameTooltip:Show()
		end)
		lbl:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	local btn = MakeButton(frame, "")
	btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -18)
	btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -18)
	btn.label:ClearAllPoints()
	btn.label:SetPoint("LEFT", 10, 0)
	btn.label:SetPoint("RIGHT", -18, 0)
	btn.label:SetJustifyH("LEFT")
	local caret = btn:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	caret:SetPoint("RIGHT", -8, 0)
	caret:SetText("v")
	caret:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

	function frame:Refresh()
		btn.label:SetText(DropLabel(items, getter()))
	end
	function btn:Refresh()
		frame:Refresh()
	end
	btn:SetScript("OnClick", function()
		OpenDropMenu(btn, ItemList(items), getter, setter, opts)
	end)
	frame:Refresh()
	return RegisterWidget(frame)
end

local function MakeScrollArea(holder, opts)
	opts = opts or {}
	local bottomInset = opts.bottomInset or 0
	local scrollFrame = CreateFrame("ScrollFrame", nil, holder)
	local child = CreateFrame("Frame", nil, scrollFrame)
	child:SetSize(200, 200)
	scrollFrame:SetScrollChild(child)
	scrollFrame:EnableMouse(false)
	scrollFrame:EnableMouseWheel(true)

	local scrollBar = CreateFrame("Frame", nil, holder)
	scrollBar:SetWidth(6)
	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)

	local scrollThumb = CreateFrame("Button", nil, scrollBar)
	scrollThumb:SetWidth(6)
	local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetAllPoints()
	thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

	local area = {
		holder = holder,
		frame = scrollFrame,
		child = child,
		bar = scrollBar,
		thumb = scrollThumb,
	}

	function area:Update()
		local range = scrollFrame:GetVerticalScrollRange() or 0
		local viewH = scrollFrame:GetHeight() or 0
		if range <= 1 or viewH <= 0 then
			scrollBar:Hide()
			return
		end
		scrollBar:Show()
		local trackH = scrollBar:GetHeight() or 0
		if trackH <= 0 then
			return
		end
		local thumbH = math.max(28, trackH * (viewH / (viewH + range)))
		if thumbH > trackH then
			thumbH = trackH
		end
		local scroll = scrollFrame:GetVerticalScroll() or 0
		local y = (trackH - thumbH) * (scroll / range)
		scrollThumb:SetHeight(thumbH)
		scrollThumb:ClearAllPoints()
		scrollThumb:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, -y)
		scrollThumb:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, -y)
	end

	function area:ScrollBy(delta)
		local range = scrollFrame:GetVerticalScrollRange() or 0
		local cur = scrollFrame:GetVerticalScroll() or 0
		local nextVal = cur - (delta * 48)
		if nextVal < 0 then
			nextVal = 0
		elseif nextVal > range then
			nextVal = range
		end
		scrollFrame:SetVerticalScroll(nextVal)
		self:Update()
	end

	function area:Layout()
		scrollFrame:ClearAllPoints()
		scrollFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		scrollFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, bottomInset)
		local w = scrollFrame:GetWidth() or 200
		child:SetScale(1)
		child:SetWidth(math.max(80, w))
		scrollFrame:SetScrollChild(child)
		if scrollFrame.UpdateScrollChildRect then
			scrollFrame:UpdateScrollChildRect()
		end
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, 0)
		scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 0)
		self:Update()
	end

	local function ThumbToCursor()
		local scale = scrollBar:GetEffectiveScale()
		local _, cursorY = GetCursorPosition()
		cursorY = cursorY / scale
		local top = scrollBar:GetTop()
		local trackH = scrollBar:GetHeight() or 0
		local thumbH = scrollThumb:GetHeight() or 0
		local offset = (top - cursorY) - (thumbH / 2)
		local maxOff = math.max(1, trackH - thumbH)
		if offset < 0 then
			offset = 0
		elseif offset > maxOff then
			offset = maxOff
		end
		local range = scrollFrame:GetVerticalScrollRange() or 0
		scrollFrame:SetVerticalScroll(range * (offset / maxOff))
		area:Update()
	end

	scrollThumb:SetScript("OnEnter", function()
		thumbTex:SetColorTexture(C.textAccent[1], C.textAccent[2], C.textAccent[3], 1)
	end)
	scrollThumb:SetScript("OnLeave", function()
		if not scrollThumb._dragging then
			thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
		end
	end)
	scrollThumb:SetScript("OnMouseDown", function()
		scrollThumb._dragging = true
		scrollThumb:SetScript("OnUpdate", ThumbToCursor)
	end)
	local function StopDrag()
		scrollThumb._dragging = false
		scrollThumb:SetScript("OnUpdate", nil)
		thumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
	end
	scrollThumb:SetScript("OnMouseUp", StopDrag)
	scrollThumb:SetScript("OnHide", StopDrag)
	scrollBar:EnableMouse(true)
	scrollBar:SetScript("OnMouseDown", function()
		ThumbToCursor()
	end)
	scrollFrame:SetScript("OnMouseWheel", function(_, delta)
		area:ScrollBy(delta)
	end)
	scrollFrame:SetScript("OnVerticalScroll", function()
		area:Update()
	end)
	scrollFrame:SetScript("OnScrollRangeChanged", function()
		area:Update()
	end)

	scrollAreas[#scrollAreas + 1] = area
	return area
end

local function RefreshWidgets()
	for i = 1, #widgets do
		if widgets[i].Refresh then
			widgets[i]:Refresh()
		end
	end
end

local function LayoutAll()
	for i = 1, #scrollAreas do
		scrollAreas[i]:Layout()
	end
	for i = 1, #widgets do
		if widgets[i].LayoutFill then
			widgets[i]:LayoutFill()
		end
	end
end

addon.UI = {
	Fill = Fill,
	AddBorder = AddBorder,
	Hairline = Hairline,
	RefreshPixels = RefreshPixels,
	MakeHeader = MakeHeader,
	MakeHelp = MakeHelp,
	MakeWarning = MakeWarning,
	MakePanel = MakePanel,
	BeginCard = BeginCard,
	EndCard = EndCard,
	PaintCheck = PaintCheck,
	MakeCheckBox = MakeCheckBox,
	MakeCheckbox = MakeCheckbox,
	MakeSlider = MakeSlider,
	MakeButton = MakeButton,
	AttachChevron = AttachChevron,
	MakeChevron = MakeChevron,
	SetChevronDir = SetChevronDir,
	PaintChoice = PaintChoice,
	MakeChoiceRow = MakeChoiceRow,
	MakeColorSwatch = MakeColorSwatch,
	MakeEditBox = MakeEditBox,
	FillNameList = FillNameList,
	Pair = Pair,
	Stack = Stack,
	SetOptionLocked = SetOptionLocked,
	MakeDropdown = MakeDropdown,
	MakeScrollArea = MakeScrollArea,
	CloseDropMenu = CloseDropMenu,
	RegisterWidget = RegisterWidget,
	RefreshWidgets = RefreshWidgets,
	LayoutAll = LayoutAll,
}
