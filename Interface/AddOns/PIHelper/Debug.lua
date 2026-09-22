--[[
	Slash-only debug log. Never exposed in the options UI.
]]

local ADDON_NAME, addon = ...

local MAX_LINES = 250
local enabled = false
local lines = {}
local head = 0
local lineCount = 0

local function Push(text)
	head = head + 1
	if head > MAX_LINES then
		head = 1
	end
	if lineCount < MAX_LINES then
		lineCount = lineCount + 1
	end
	lines[head] = date("%H:%M:%S") .. " " .. text
end

local function LineAt(index)
	if lineCount < MAX_LINES then
		return lines[index]
	end
	local pos = head + index
	if pos > MAX_LINES then
		pos = pos - MAX_LINES
	end
	return lines[pos]
end

local function SafeArg(value)
	if value == nil then
		return "nil"
	end
	if addon.IsSecret and addon.IsSecret(value) then
		return "<secret>"
	end
	local ok, text = pcall(tostring, value)
	if not ok or type(text) ~= "string" then
		return "<unprintable>"
	end
	return text
end

local function Flag(fn, yes, no)
	local ok, value = pcall(fn)
	if not ok then
		return "?"
	end
	if addon.IsSecret and addon.IsSecret(value) then
		return "<secret>"
	end
	return value and yes or no
end

function addon.DebugStateText()
	return table.concat({
		"v" .. SafeArg(addon.VERSION),
		Flag(function()
			return addon.isPriest
		end, "priest", "not-priest"),
		Flag(function()
			return addon.IsHealerSpec and addon.IsHealerSpec()
		end, "healer", "dps-spec"),
		Flag(function()
			return addon.IsActive and addon.IsActive()
		end, "active", "idle"),
		Flag(function()
			return addon.IsRestricted and addon.IsRestricted()
		end, "restricted", "open"),
		Flag(function()
			return addon.InCombat and addon.InCombat()
		end, "combat", "nocombat"),
		Flag(function()
			return addon.IsPIReady and addon.IsPIReady()
		end, "pi-ready", "pi-cd"),
	}, " ")
end

function addon.Debug(...)
	if not enabled then
		return
	end
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = SafeArg(select(i, ...))
	end
	local text = table.concat(parts, " ")
	Push(text)
	print("|cffeaa221PIH:|r " .. text)
end

function addon.IsDebugEnabled()
	return enabled
end

function addon.ToggleDebug()
	enabled = not enabled
	if enabled then
		print("|cffeaa221PI Helper:|r debug on. Use |cffffff00/pih log|r to open the log.")
		addon.Debug("debug enabled", addon.DebugStateText())
	else
		print("|cffeaa221PI Helper:|r debug off")
	end
	if addon.QueuePolicy then
		addon.QueuePolicy()
	end
	if addon.RefreshDebugOptions then
		addon.RefreshDebugOptions()
	end
end

local logFrame

local function HideDebugLog()
	if logFrame then
		logFrame:Hide()
	end
end

local function EnsureDebugLogFrame()
	if logFrame then
		return logFrame
	end
	local C = addon.C
	local font = addon.FONT
	local frame = CreateFrame("Frame", "PIHelperDebugLogFrame", UIParent)
	frame:SetSize(560, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(200)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "PIHelperDebugLogFrame")

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 0.98)

	local function Edge(pointA, pointB, w, h)
		local tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetColorTexture(C.windowBorder[1], C.windowBorder[2], C.windowBorder[3], 1)
		tex:SetPoint(pointA)
		tex:SetPoint(pointB)
		if w then
			tex:SetWidth(w)
		end
		if h then
			tex:SetHeight(h)
		end
	end
	Edge("TOPLEFT", "TOPRIGHT", nil, 1)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

	local title = frame:CreateFontString(nil, "OVERLAY")
	title:SetFont(font, 15, "")
	title:SetPoint("TOPLEFT", 16, -12)
	title:SetText("PI Helper debug log")
	title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

	local hint = frame:CreateFontString(nil, "OVERLAY")
	hint:SetFont(font, 12, "")
	hint:SetPoint("TOPLEFT", 16, -32)
	hint:SetText("Ctrl+C to copy. Escape or Close to dismiss.")
	hint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(72, 24)
	close:SetPoint("BOTTOMRIGHT", -14, 12)
	local closeBg = close:CreateTexture(nil, "BACKGROUND")
	closeBg:SetAllPoints()
	closeBg:SetColorTexture(0.18, 0.20, 0.22, 1)
	local closeText = close:CreateFontString(nil, "OVERLAY")
	closeText:SetFont(font, 12, "")
	closeText:SetPoint("CENTER")
	closeText:SetText("Close")
	closeText:SetTextColor(C.text[1], C.text[2], C.text[3])
	close:SetScript("OnClick", HideDebugLog)
	close:SetScript("OnEnter", function()
		closeBg:SetColorTexture(0.28, 0.22, 0.12, 1)
	end)
	close:SetScript("OnLeave", function()
		closeBg:SetColorTexture(0.18, 0.20, 0.22, 1)
	end)

	local inset = CreateFrame("Frame", nil, frame)
	inset:SetPoint("TOPLEFT", 14, -52)
	inset:SetPoint("BOTTOMRIGHT", -14, 44)
	local insetBg = inset:CreateTexture(nil, "BACKGROUND")
	insetBg:SetAllPoints()
	insetBg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)

	local scroll = CreateFrame("ScrollFrame", nil, inset)
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -8, 8)
	scroll:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(true)
	edit:SetFont(font, 12, "")
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetScript("OnEscapePressed", HideDebugLog)
	edit:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(self.pihLog or "")
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, edit:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - delta * 36)))
	end)

	frame.edit = edit
	frame.scroll = scroll
	logFrame = frame
	return frame
end

function addon.ShowDebugLog()
	local out = { addon.DebugStateText() }
	for i = 1, lineCount do
		out[i + 1] = LineAt(i)
	end
	local chunk = table.concat(out, "\n")
	local frame = EnsureDebugLogFrame()
	local edit = frame.edit
	local scroll = frame.scroll
	local rows = #out
	edit.pihLog = chunk
	edit:SetWidth(math.max(100, scroll:GetWidth()))
	edit:SetText(chunk)
	edit:SetHeight(math.max(scroll:GetHeight(), rows * 16 + 16))
	edit:SetCursorPosition(0)
	frame:Show()
	edit:SetFocus()
	edit:HighlightText()
	C_Timer.After(0, function()
		if not frame:IsShown() then
			return
		end
		edit:SetWidth(math.max(100, scroll:GetWidth()))
		edit:SetHeight(math.max(scroll:GetHeight(), rows * 16 + 16))
		edit:HighlightText()
		edit:SetFocus()
	end)
	print("|cffeaa221PI Helper:|r debug log opened (" .. lineCount .. " lines). Ctrl+C to copy.")
end
