--[[
	PI Helper options. Window, tabs, General, Appearance, reset, profiles.
]]

local ADDON_NAME, addon = ...

local WIN_W, WIN_H = 880, 680
local PAD = 16
local HEADER_H = 46
local FOOTER_H = 46

local C = addon.C
local UI = addon.UI
local Fill = UI.Fill
local AddBorder = UI.AddBorder
local Hairline = UI.Hairline
local MakeHelp = UI.MakeHelp
local BeginCard = UI.BeginCard
local EndCard = UI.EndCard
local MakeCheckbox = UI.MakeCheckbox
local MakeSlider = UI.MakeSlider
local MakeButton = UI.MakeButton
local PaintChoice = UI.PaintChoice
local MakeChoiceRow = UI.MakeChoiceRow
local MakeColorSwatch = UI.MakeColorSwatch
local Stack = UI.Stack
local SetOptionLocked = UI.SetOptionLocked
local MakeDropdown = UI.MakeDropdown
local MakeScrollArea = UI.MakeScrollArea
local CloseDropMenu = UI.CloseDropMenu

local optionsFrame
local tabButtons = {}
local tabFrames = {}
local activeScroll
local activeTab = "tracking"

local RefreshAll
local SelectTab
local LayoutBody
local HideProfileDialog
local HideResetConfirm
local Build

local function DB()
	return addon.db
end

function UI.SetWindowMovable(on)
	if optionsFrame then
		optionsFrame:SetMovable(on and true or false)
	end
end

local OPTIONS_SCALE_MIN = 50
local OPTIONS_SCALE_MAX = 150

local function ClampOptionsScalePct(pct)
	if type(pct) ~= "number" then
		pct = addon.DEFAULTS.optionsScale or 100
	end
	pct = math.floor(pct + 0.5)
	if pct < OPTIONS_SCALE_MIN then
		return OPTIONS_SCALE_MIN
	end
	if pct > OPTIONS_SCALE_MAX then
		return OPTIONS_SCALE_MAX
	end
	return pct
end

function addon.GetOptionsScale()
	local db = DB()
	return ClampOptionsScalePct(db and db.optionsScale) / 100
end

-- SetPoint offsets are in the frame's scaled space, so visual screen
-- position is offset * scale. Divide to keep a corner glued while scaling.
local function PinOptionsTopLeft(frame, visLeft, visTop)
	if not frame or visLeft == nil or visTop == nil then
		return
	end
	local s = frame:GetScale() or 1
	if s == 0 then
		s = 1
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", visLeft / s, visTop / s)
end

local function GetVisualTopLeft(frame)
	if not frame then
		return
	end
	return frame:GetLeft(), frame:GetTop()
end

function addon.ApplyOptionsScale()
	if not optionsFrame then
		return
	end
	local scale = addon.GetOptionsScale()
	local changed = math.abs((optionsFrame:GetScale() or 1) - scale) > 0.0001
	if changed then
		local left, top = GetVisualTopLeft(optionsFrame)
		optionsFrame:SetScale(scale)
		PinOptionsTopLeft(optionsFrame, left, top)
		CloseDropMenu()
	end
	if UI.RefreshPixels then
		UI.RefreshPixels()
	end
	if changed and LayoutBody then
		LayoutBody()
	end
	C_Timer.After(0, function()
		if not optionsFrame then
			return
		end
		if UI.RefreshPixels then
			UI.RefreshPixels()
		end
		if changed and LayoutBody then
			LayoutBody()
		end
	end)
end

local function ChannelItems()
	local items = {}
	local list = addon.SOUND_CHANNELS
	for i = 1, #list do
		items[i] = { id = list[i], name = list[i] }
	end
	return items
end

local function ResetToDefaults()
	local db = DB()
	for k, v in pairs(addon.DEFAULTS) do
		if type(v) ~= "table" then
			db[k] = v
		end
	end
	db.spellEnabled = {}
	for i = 1, #addon.DEFAULT_SPELLS do
		local spell = addon.DEFAULT_SPELLS[i]
		db.spellEnabled[spell.spellID] = not spell.isPotion
	end
	db.spellScope = {}
	db.customSpells = {}
	db.whisperNames = {}
	db.sequenceNames = {}
	db.trackNames = {}
	db.trackingCollapsed = {}
	db.cooldownCollapsed = {}
	db.trackRaidMode = "all"
	db.trackPartyMode = "all"
	db.potionRowsMigrated = true
	db.contextSoundsMigrated = true
	if addon.ResetTrackingSearch then
		addon.ResetTrackingSearch()
	end
	RefreshAll()
	if addon.RefreshAppearanceLayout then
		addon.RefreshAppearanceLayout()
	end
	if addon.RefreshDebugOptions then
		addon.RefreshDebugOptions()
	end
	if addon.ApplySettings then
		addon.ApplySettings()
	end
	if addon.ApplyOptionsScale then
		addon.ApplyOptionsScale()
	end
	print("|cffeaa221PI Helper:|r settings reset to defaults.")
end

local resetDialog

HideResetConfirm = function()
	if resetDialog then
		resetDialog:Hide()
	end
	if resetDialog and resetDialog.catcher then
		resetDialog.catcher:Hide()
	end
end

local function ConfirmResetToDefaults()
	HideProfileDialog()
	if resetDialog then
		resetDialog.catcher:Show()
		resetDialog:Show()
		return
	end
	local parent = optionsFrame
	local catcher = CreateFrame("Button", nil, parent)
	catcher:SetAllPoints()
	catcher:SetFrameStrata("DIALOG")
	catcher:SetFrameLevel((parent:GetFrameLevel() or 1) + 40)
	local dim = catcher:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints()
	dim:SetColorTexture(0, 0, 0, 0.55)
	catcher:EnableMouse(true)

	local dialog = CreateFrame("Frame", "PIHelperResetConfirm", parent)
	dialog:SetSize(340, 148)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(catcher:GetFrameLevel() + 2)
	Fill(dialog, "BACKGROUND", C.bg[1], C.bg[2], C.bg[3], 1)
	AddBorder(dialog, C.windowBorder[1], C.windowBorder[2], C.windowBorder[3])

	local title = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Reset to Defaults?")
	title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

	local body = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	body:SetPoint("TOPLEFT", 16, -42)
	body:SetPoint("TOPRIGHT", -16, -42)
	body:SetJustifyH("LEFT")
	body:SetWordWrap(true)
	body:SetText("This restores all PI Helper settings. Custom spell IDs, whisper lists, and tracked player names will be cleared.")
	body:SetTextColor(C.text[1], C.text[2], C.text[3])

	local cancel = MakeButton(dialog, "Cancel")
	cancel:SetWidth(80)
	cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 14)
	cancel:SetScript("OnClick", HideResetConfirm)

	local confirm = MakeButton(dialog, "Reset", true)
	confirm:SetWidth(80)
	confirm:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
	confirm:SetScript("OnClick", function()
		HideResetConfirm()
		ResetToDefaults()
	end)

	catcher:SetScript("OnClick", HideResetConfirm)
	dialog.catcher = catcher
	resetDialog = dialog
	catcher:Show()
	dialog:Show()
end

local profileDialog
local profileMode = "export"
local profileSource

HideProfileDialog = function()
	if profileDialog then
		profileDialog:Hide()
	end
	if profileDialog and profileDialog.catcher then
		profileDialog.catcher:Hide()
	end
	if profileDialog and profileDialog.edit then
		profileDialog.edit:ClearFocus()
	end
end

local function SetProfileStatus(text, isError)
	if not profileDialog or not profileDialog.status then
		return
	end
	profileDialog.status:SetText(text or "")
	if isError then
		profileDialog.status:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
	else
		profileDialog.status:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	end
end

local function FitProfileEdit()
	if not profileDialog or not profileDialog.edit or not profileDialog.scroll then
		return
	end
	local edit = profileDialog.edit
	local scroll = profileDialog.scroll
	local width = math.max(100, scroll:GetWidth() or 100)
	edit:SetWidth(width)
	local text = edit:GetText() or ""
	local lines = 1
	for _ in string.gmatch(text, "\n") do
		lines = lines + 1
	end
	local wrapped = math.ceil(#text / math.max(1, math.floor(width / 7)))
	if wrapped > lines then
		lines = wrapped
	end
	edit:SetHeight(math.max(scroll:GetHeight() or 120, lines * 16 + 16))
end

local function ShowProfileDialog(mode)
	HideResetConfirm()
	if not optionsFrame then
		return
	end
	profileMode = mode == "import" and "import" or "export"
	if not profileDialog then
		local parent = optionsFrame
		local catcher = CreateFrame("Button", nil, parent)
		catcher:SetAllPoints()
		catcher:SetFrameStrata("DIALOG")
		catcher:SetFrameLevel((parent:GetFrameLevel() or 1) + 40)
		local dim = catcher:CreateTexture(nil, "BACKGROUND")
		dim:SetAllPoints()
		dim:SetColorTexture(0, 0, 0, 0.55)
		catcher:EnableMouse(true)

		local dialog = CreateFrame("Frame", "PIHelperProfileDialog", parent)
		dialog:SetSize(460, 320)
		dialog:SetPoint("CENTER")
		dialog:SetFrameStrata("DIALOG")
		dialog:SetFrameLevel(catcher:GetFrameLevel() + 2)
		Fill(dialog, "BACKGROUND", C.bg[1], C.bg[2], C.bg[3], 1)
		AddBorder(dialog, C.windowBorder[1], C.windowBorder[2], C.windowBorder[3])

		local title = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontLarge")
		title:SetPoint("TOPLEFT", 16, -14)
		title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

		local body = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
		body:SetPoint("TOPLEFT", 16, -40)
		body:SetPoint("TOPRIGHT", -16, -40)
		body:SetJustifyH("LEFT")
		body:SetWordWrap(true)
		body:SetTextColor(C.text[1], C.text[2], C.text[3])

		local inset = CreateFrame("Frame", nil, dialog)
		inset:SetPoint("TOPLEFT", 16, -88)
		inset:SetPoint("BOTTOMRIGHT", -16, 64)
		Fill(inset, "BACKGROUND", 0.07, 0.08, 0.09, 1)
		AddBorder(inset, C.border[1], C.border[2], C.border[3])

		local scroll = CreateFrame("ScrollFrame", nil, inset)
		scroll:SetPoint("TOPLEFT", 6, -6)
		scroll:SetPoint("BOTTOMRIGHT", -6, 6)
		scroll:EnableMouseWheel(true)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFont(addon.FONT, 12, "")
		edit:SetTextColor(C.text[1], C.text[2], C.text[3])
		edit:SetTextInsets(4, 4, 4, 4)
		edit:SetMaxLetters(50000)
		edit:SetScript("OnEscapePressed", HideProfileDialog)
		edit:SetScript("OnCursorChanged", function(self, _, y, _, lineH)
			local view = scroll:GetHeight() or 0
			local cur = scroll:GetVerticalScroll() or 0
			local top = -(y or 0)
			local bottom = top + (lineH or 16)
			if top < cur then
				scroll:SetVerticalScroll(math.max(0, top))
			elseif bottom > cur + view then
				scroll:SetVerticalScroll(math.max(0, bottom - view))
			end
		end)
		edit:SetScript("OnTextChanged", function(self, userInput)
			if profileMode == "export" and userInput then
				self:SetText(profileSource or "")
				self:HighlightText()
				return
			end
			FitProfileEdit()
		end)
		edit:SetScript("OnEditFocusGained", function(self)
			if profileMode == "export" then
				self:HighlightText()
			end
		end)
		scroll:SetScrollChild(edit)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local range = math.max(0, edit:GetHeight() - self:GetHeight())
			self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - delta * 36)))
		end)

		local status = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
		status:SetPoint("BOTTOMLEFT", 16, 42)
		status:SetPoint("BOTTOMRIGHT", -16, 42)
		status:SetJustifyH("LEFT")
		status:SetWordWrap(false)
		status:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

		local close = MakeButton(dialog, "Close")
		close:SetWidth(80)
		close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 14)
		close:SetScript("OnClick", HideProfileDialog)

		local action = MakeButton(dialog, "Import", true)
		action:SetWidth(80)
		action:SetPoint("RIGHT", close, "LEFT", -8, 0)
		action:SetScript("OnClick", function()
			if profileMode ~= "import" then
				HideProfileDialog()
				return
			end
			local ok, err, warning = addon.ImportProfile(edit:GetText())
			if not ok then
				SetProfileStatus(err or "could not import this profile.", true)
				return
			end
			HideProfileDialog()
			print("|cffeaa221PI Helper:|r profile imported. Whisper names and tracked player names were kept.")
			if warning then
				print("|cffeaa221PI Helper:|r " .. warning)
			end
		end)

		catcher:SetScript("OnClick", HideProfileDialog)
		dialog:SetScript("OnSizeChanged", FitProfileEdit)

		dialog.catcher = catcher
		dialog.title = title
		dialog.body = body
		dialog.edit = edit
		dialog.scroll = scroll
		dialog.status = status
		dialog.close = close
		dialog.action = action
		profileDialog = dialog
	end

	local dialog = profileDialog
	dialog.catcher:Show()
	dialog:Show()
	SetProfileStatus("")
	if profileMode == "import" then
		profileSource = nil
		dialog.title:SetText("Import profile")
		dialog.body:SetText("Paste a PI Helper profile string. Whisper names and tracked player names are not changed.")
		dialog.action:Show()
		dialog.action.label:SetText("Import")
		dialog.close.label:SetText("Cancel")
		dialog.edit:SetText("")
		dialog.edit:SetFocus()
		dialog.scroll:SetVerticalScroll(0)
		FitProfileEdit()
		C_Timer.After(0, FitProfileEdit)
		return
	end

	local str, err = addon.ExportProfile()
	if not str then
		dialog.catcher:Hide()
		dialog:Hide()
		print("|cffeaa221PI Helper:|r " .. (err or "could not export settings."))
		return
	end
	profileSource = str
	dialog.title:SetText("Export profile")
	dialog.body:SetText("Copy this string and send it to other players. Whisper names and tracked player names are not included.")
	dialog.action:Hide()
	dialog.close.label:SetText("Close")
	dialog.edit:SetText(str)
	dialog.edit:SetCursorPosition(0)
	dialog.edit:SetFocus()
	dialog.edit:HighlightText()
	dialog.scroll:SetVerticalScroll(0)
	FitProfileEdit()
	SetProfileStatus("Ctrl+C to copy.")
	C_Timer.After(0, function()
		if not profileDialog or profileMode ~= "export" or not profileDialog:IsShown() then
			return
		end
		FitProfileEdit()
		profileDialog.edit:SetFocus()
		profileDialog.edit:HighlightText()
	end)
end

local function EnsureOptionsShown()
	if not addon.db then
		return false
	end
	Build()
	if not optionsFrame:IsShown() then
		optionsFrame:Show()
		RefreshAll()
	end
	return true
end

function addon.ShowProfileExport()
	if not EnsureOptionsShown() then
		return
	end
	SelectTab("general")
	ShowProfileDialog("export")
end

function addon.ShowProfileImport()
	if not EnsureOptionsShown() then
		return
	end
	SelectTab("general")
	ShowProfileDialog("import")
end

function addon.RefreshOptionsAfterImport()
	if not optionsFrame then
		return
	end
	RefreshAll()
	if addon.RefreshAppearanceLayout then
		addon.RefreshAppearanceLayout()
	end
	if addon.RefreshDebugOptions then
		addon.RefreshDebugOptions()
	end
end

local function BuildGeneralTab(parent)
	local y = 0
	local panel, inner = BeginCard(parent, y, "Addon")
	inner = Stack(panel, {
		MakeCheckbox(panel, "Enable addon", nil, function()
			return DB().enabled
		end, function(v) DB().enabled = v end),
		MakeCheckbox(panel, "Load on all classes", nil, function()
			return DB().loadForAllClasses
		end, function(v) DB().loadForAllClasses = v end, "Also run tracking and glows on characters that are not priests."),
		MakeCheckbox(panel, "Healer specs only", nil, function()
			return DB().healerOnly
		end, function(v) DB().healerOnly = v end, "Only active while you are in a healer specialization."),
		MakeCheckbox(panel, "Track different cooldowns per group", nil, function()
			return DB().perBuffScope
		end, function(v)
			DB().perBuffScope = v
			if addon.RebuildCooldownList then
				addon.RebuildCooldownList()
			end
		end, "When disabled, buffs are tracked for all three types by default. Enable this to pick different buffs for Raid, Dungeons, and Focus."),
		MakeCheckbox(panel, "Minimap button", nil, function()
			return DB().showMinimap
		end, function(v)
			DB().showMinimap = v
		end),
		MakeSlider(panel, "Options menu scale", OPTIONS_SCALE_MIN, OPTIONS_SCALE_MAX, 1, function(v)
			return v .. "%"
		end, function()
			return ClampOptionsScalePct(DB().optionsScale)
		end, function(v)
			DB().optionsScale = ClampOptionsScalePct(v)
		end, nil, "optionsScale"),
	}, inner, 6, 12)
	y = y - EndCard(panel, inner) - 10

	panel, inner = BeginCard(parent, y, "Power Infusion")
	local onlyWhenPI = MakeCheckbox(panel, "Only when PI is available", nil, function()
		return DB().onlyWhenPIReady
	end, function(v)
		DB().onlyWhenPIReady = v
		if addon.RefreshPIReadyLockout then
			addon.RefreshPIReadyLockout()
		end
	end, "Hide tracking, alerts, whisper requests, and raidframe glows while Power Infusion is on cooldown.")
	local graceSlider = MakeSlider(panel, "PI grace period", 0, 15, 1, function(v) return v .. "s" end, function()
		return DB().piGrace or 0
	end, function(v) DB().piGrace = v end, "Seconds before Power Infusion is ready that tracking and glows come back. 0 waits until PI is fully ready.", "grace")
	inner = Stack(panel, { onlyWhenPI, graceSlider }, inner, 6, 12)
	local function RefreshPIReadyLockout()
		SetOptionLocked(graceSlider, DB().onlyWhenPIReady == true)
	end
	addon.RefreshPIReadyLockout = RefreshPIReadyLockout
	RefreshPIReadyLockout()
	y = y - EndCard(panel, inner) - 10

	local remindCard
	remindCard, inner = BeginCard(parent, y, "Focus reminder")
	local remindHelp = MakeHelp(remindCard, "Shows a popup in raid and dungeon instances until you focus a friendly player. Ignore until next reload hides it until you /reload.")
	remindHelp:SetPoint("LEFT", remindCard.header, "RIGHT", 6, 0)
	local enableRemind = MakeCheckbox(remindCard, "Enable reminder", nil, function()
		return DB().focusRemindEnabled
	end, function(v)
		DB().focusRemindEnabled = v
		if addon.RefreshFocusRemindLockout then
			addon.RefreshFocusRemindLockout()
		end
	end)
	local raidRemind = MakeCheckbox(remindCard, "Remind in raid instances", nil, function()
		return DB().focusRemindRaid
	end, function(v) DB().focusRemindRaid = v end)
	local dungeonRemind = MakeCheckbox(remindCard, "Remind in dungeon instances", nil, function()
		return DB().focusRemindDungeon
	end, function(v) DB().focusRemindDungeon = v end)
	inner = Stack(remindCard, { enableRemind, raidRemind, dungeonRemind }, inner, 4, 12)
	inner = inner - 10
	local testRemind = MakeButton(remindCard, "Test Reminder")
	testRemind:SetWidth(110)
	testRemind:SetPoint("TOPLEFT", remindCard, "TOPLEFT", 12, inner)
	function testRemind:Refresh()
		PaintChoice(self, addon.IsTestFocusReminderOn and addon.IsTestFocusReminderOn())
	end
	testRemind:SetScript("OnClick", function()
		if addon.ToggleTestFocusReminder then
			addon.ToggleTestFocusReminder()
		end
		testRemind:Refresh()
	end)
	testRemind:Refresh()
	UI.RegisterWidget(testRemind)
	inner = inner - 32
	local function RefreshFocusRemindLockout()
		local on = DB().focusRemindEnabled == true
		SetOptionLocked(raidRemind, on)
		SetOptionLocked(dungeonRemind, on)
		SetOptionLocked(testRemind, on)
	end
	addon.RefreshFocusRemindLockout = RefreshFocusRemindLockout
	RefreshFocusRemindLockout()
	y = y - EndCard(remindCard, inner) - 10
	local heightWithoutDebug = math.max(420, -y + 12)

	local debugPanel
	debugPanel, inner = BeginCard(parent, y, "Debug")
	debugPanel:SetAlpha(0.72)
	inner = Stack(debugPanel, {
		MakeCheckbox(debugPanel, "Track and alert on myself", nil, function()
			return DB().watchSelf
		end, function(v) DB().watchSelf = v end, "Glow your own raid or party cell and show the on-screen alert so you can test without a focus. Show raid frames while solo to test out of group. Works while Healer specs only is on."),
	}, inner, 6, 12)
	y = y - EndCard(debugPanel, inner) - 10
	local heightWithDebug = math.max(420, -y + 12)

	local function LayoutDebugCard()
		local on = addon.IsDebugEnabled and addon.IsDebugEnabled()
		debugPanel:SetShown(on)
		parent:SetHeight(on and heightWithDebug or heightWithoutDebug)
		if tabFrames.generalScroll then
			tabFrames.generalScroll:Layout()
			tabFrames.generalScroll:Update()
		end
	end
	addon.RefreshDebugOptions = LayoutDebugCard
	LayoutDebugCard()
	return parent:GetHeight()
end

local function CardTestButton(panel, text, isOn, onClick)
	local btn = MakeButton(panel, text)
	btn:SetHeight(20)
	btn:SetWidth(math.max(84, (btn.label:GetStringWidth() or 50) + 18))
	btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -8)
	btn:SetFrameLevel((panel:GetFrameLevel() or 1) + 4)
	function btn:Refresh()
		PaintChoice(self, isOn and isOn())
	end
	btn:SetScript("OnClick", function()
		onClick()
		btn:Refresh()
	end)
	btn:Refresh()
	UI.RegisterWidget(btn)
	return btn
end

local function MakeLockHint(card, text)
	local overlay = CreateFrame("Frame", nil, card)
	overlay:EnableMouse(false)
	overlay:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -30)
	overlay:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -30)
	overlay:SetHeight(28)
	local fs = overlay:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	fs:SetAllPoints()
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetText(text)
	fs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	overlay:Hide()
	overlay._locked = false
	function overlay:SetLocked(locked)
		self._locked = locked and true or false
		if locked then
			self:SetFrameLevel((card:GetFrameLevel() or 1) + 8)
		end
		self:SetShown(locked)
	end
	function overlay:IsLocked()
		return self._locked
	end
	return overlay
end

local function BuildAlertsTab(parent)
	local free = { free = true }
	local COL_GAP = 10

	local glowCard = BeginCard(parent, 0, "Raidframe glow", free)
	local glowHelp = MakeHelp(glowCard, "Glows for players who appear mid-combat may only attach after combat.")
	glowHelp:SetPoint("LEFT", glowCard.header, "RIGHT", 6, 0)
	local testGlowBtn = CardTestButton(glowCard, "Test Glow", function()
		return addon.IsTestGlowOn and addon.IsTestGlowOn()
	end, function()
		if addon.ToggleTestGlow then
			addon.ToggleTestGlow()
		end
	end)
	local styleLbl = glowCard:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	styleLbl:SetText("Style")
	styleLbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local styleRow = MakeChoiceRow(glowCard, addon.GLOW_STYLES, function()
		return DB().glowStyle
	end, function(id)
		DB().glowStyle = id
	end)
	local swatch = MakeColorSwatch(glowCard, "Glow color")
	local speedSlider = MakeSlider(glowCard, "Speed", 5, 500, 1, function(v) return string.format("%.2f", v / 100) end, function()
		return math.floor((DB().glowSpeed or 1.5) * 100 + 0.5)
	end, function(v) DB().glowSpeed = v / 100 end)
	local opacitySlider = MakeSlider(glowCard, "Opacity", 5, 100, 1, function(v) return v .. "%" end, function()
		return math.floor((DB().glowA or 0.9) * 100 + 0.5)
	end, function(v)
		DB().glowA = v / 100
		swatch:Refresh()
	end)
	local thickSlider = MakeSlider(glowCard, "Thickness", 1, 6, 1, nil, function()
		return DB().glowThickness or 2
	end, function(v) DB().glowThickness = v end)
	local linesSlider = MakeSlider(glowCard, "Lines", 4, 16, 1, nil, function()
		return DB().glowPixelLines or 10
	end, function(v) DB().glowPixelLines = v end)
	local lengthSlider = MakeSlider(glowCard, "Length", 4, 36, 1, nil, function()
		return DB().glowPixelLength or 20
	end, function(v) DB().glowPixelLength = v end)
	local function PulseDesc(style)
		if style == "fill" then
			return "Fade the highlight in and out. Off keeps a steady glow."
		end
		return "Fade the border in and out. Off keeps a steady glow."
	end
	local pulseCb = MakeCheckbox(glowCard, "Pulse", PulseDesc(DB().glowStyle), function()
		return DB().glowBorderPulse ~= false
	end, function(v) DB().glowBorderPulse = v and true or false end)
	local countdownAnchor = MakeDropdown(glowCard, "Position", addon.COUNTDOWN_ANCHORS, function()
		return DB().countdownAnchor or "top"
	end, function(id)
		DB().countdownAnchor = id
	end, { maxRows = 3 })
	local countdownX = MakeSlider(glowCard, "X offset", -40, 40, 1, nil, function()
		return DB().countdownX or 0
	end, function(v) DB().countdownX = v end)
	local countdownY = MakeSlider(glowCard, "Y offset", -40, 40, 1, nil, function()
		return DB().countdownY or 0
	end, function(v) DB().countdownY = v end)
	local countdownHeight = MakeSlider(glowCard, "Height", 0, 40, 1, function(v)
		if v <= 0 then
			return "Frame"
		end
		return tostring(v)
	end, function()
		local v = DB().countdownHeight
		if type(v) ~= "number" then
			return 0
		end
		return v
	end, function(v) DB().countdownHeight = v end, "0 matches the raid frame height.")

	local durationCard = BeginCard(parent, 0, "Duration text", free)
	local durationHelp = MakeHelp(durationCard, "Remaining time on the raidframe glow, the on-screen alert, or both. Turn it on in Tracking under Raid or Dungeons. The engine drives the countdown, so it still works in dungeons and raids.")
	durationHelp:SetPoint("LEFT", durationCard.header, "RIGHT", 6, 0)
	local testDurationBtn = CardTestButton(durationCard, "Test Duration", function()
		return addon.IsTestDurationOn and addon.IsTestDurationOn()
	end, function()
		if addon.ToggleTestDuration then
			addon.ToggleTestDuration()
		end
	end)
	local durationHostLbl = durationCard:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	durationHostLbl:SetText("Show on")
	durationHostLbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local durationHostRow = MakeChoiceRow(durationCard, addon.DURATION_HOSTS, function()
		return DB().durationHost or "frame"
	end, function(id)
		DB().durationHost = id
	end)
	local durationAnchor = MakeDropdown(durationCard, "Position", addon.DURATION_ANCHORS, function()
		return DB().durationAnchor or "center"
	end, function(id)
		DB().durationAnchor = id
	end, { maxRows = 9 })
	local durationX = MakeSlider(durationCard, "X offset", -40, 40, 1, nil, function()
		return DB().durationX or 0
	end, function(v) DB().durationX = v end)
	local durationY = MakeSlider(durationCard, "Y offset", -40, 40, 1, nil, function()
		return DB().durationY or 0
	end, function(v) DB().durationY = v end)
	local durationFont = MakeDropdown(durationCard, "Font", function()
		if addon.GetFontItems then
			return addon.GetFontItems()
		end
		return addon.FONT_PRESETS
	end, function()
		return DB().durationFont or "default"
	end, function(id)
		DB().durationFont = id
	end, {
		maxRows = 16,
		tooltip = "Game fonts plus anything registered with SharedMedia.",
	})
	local durationSize = MakeSlider(durationCard, "Font size", 8, 32, 1, nil, function()
		return DB().durationSize or 12
	end, function(v) DB().durationSize = v end)
	local durationSwatch = MakeColorSwatch(durationCard, "Font color", function()
		local db = DB()
		return db.durationR or 1, db.durationG or 1, db.durationB or 1, db.durationA or 1
	end, function(r, g, b, a)
		local db = DB()
		db.durationR, db.durationG, db.durationB, db.durationA = r, g, b, a
	end)

	local alertCard = BeginCard(parent, 0, "On-screen alert", free)
	local testAlertBtn = CardTestButton(alertCard, "Test Alert", function()
		return addon.IsTestAlertOn and addon.IsTestAlertOn()
	end, function()
		if addon.ToggleTestAlert then
			addon.ToggleTestAlert()
		end
	end)
	local glowStyleLbl = alertCard:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	glowStyleLbl:SetText("Glow type")
	glowStyleLbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local alertGlowRow = MakeChoiceRow(alertCard, addon.ALERT_GLOW_STYLES, function()
		return DB().alertGlowStyle or "starburst"
	end, function(id)
		DB().alertGlowStyle = id
	end)
	local alertSwatch = MakeColorSwatch(alertCard, "Glow color", function()
		return addon.GetAlertGlowColor()
	end, function(r, g, b, a)
		local db = DB()
		db.alertGlowR, db.alertGlowG, db.alertGlowB, db.alertGlowA = r, g, b, a
	end)
	local alertOpacity = MakeSlider(alertCard, "Opacity", 5, 100, 1, function(v) return v .. "%" end, function()
		return math.floor((select(4, addon.GetAlertGlowColor()) or 0.9) * 100 + 0.5)
	end, function(v)
		DB().alertGlowA = v / 100
		alertSwatch:Refresh()
	end)
	local layoutLbl = alertCard:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	layoutLbl:SetText("Layout")
	layoutLbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local layoutRow = MakeChoiceRow(alertCard, addon.ALERT_LAYOUTS, function()
		return DB().alertLayout
	end, function(id)
		DB().alertLayout = id
	end)
	local alertIconSize = MakeSlider(alertCard, "Alert icon size", 32, 128, 2, nil, function()
		return DB().alertIconSize or 64
	end, function(v) DB().alertIconSize = v end)
	local alertTextSize = MakeSlider(alertCard, "Alert text size", 10, 32, 1, nil, function()
		return DB().alertTextSize or 16
	end, function(v) DB().alertTextSize = v end)
	local alertClassColor = MakeCheckbox(alertCard, "Class color name", nil, function()
		return DB().alertClassColor
	end, function(v) DB().alertClassColor = v end, "Tint the player name on the alert with their class color.")
	local alertLock = MakeCheckbox(alertCard, "Lock on-screen alert", nil, function()
		return DB().alertLocked
	end, function(v) DB().alertLocked = v end)
	local resetPos = MakeButton(alertCard, "Reset Position")
	resetPos:SetWidth(120)
	resetPos:SetScript("OnClick", function()
		DB().alertX = addon.DEFAULTS.alertX
		DB().alertY = addon.DEFAULTS.alertY
		if addon.LayoutAlertAnchor then
			addon.LayoutAlertAnchor()
		end
	end)

	local soundCard = BeginCard(parent, 0, "Sound", free)
	local testSoundBtn = CardTestButton(soundCard, "Test Sound", nil, function()
		if addon.PlayAlertSound then
			addon.PlayAlertSound()
		end
	end)
	local soundDrop = MakeDropdown(soundCard, "Sound", function()
		if addon.GetSoundItems then
			return addon.GetSoundItems()
		end
		return addon.SOUND_PRESETS
	end, function()
		return DB().soundName or DB().soundKitID
	end, function(id)
		DB().soundName = id
		if addon.PlaySoundByID then
			addon.PlaySoundByID(id)
		end
	end, {
		previewSounds = true,
		maxRows = 16,
		tooltip = "Blizzard presets plus anything registered with SharedMedia (BigWigs, SharedMedia packs, and similar).",
	})
	local channelDrop = MakeDropdown(soundCard, "Channel", ChannelItems(), function()
		return DB().soundChannel or "Master"
	end, function(id)
		DB().soundChannel = id
	end)

	local durationLockables = {
		durationHostLbl, durationHostRow, durationAnchor, durationX, durationY,
		durationFont, durationSize, durationSwatch, testDurationBtn,
	}
	local glowLockables = {
		styleLbl, styleRow, swatch, speedSlider, thickSlider, linesSlider, lengthSlider, pulseCb,
		countdownAnchor, countdownX, countdownY, countdownHeight, opacitySlider, testGlowBtn,
	}
	local alertLockables = {
		glowStyleLbl, alertGlowRow, alertSwatch, alertOpacity, layoutLbl, layoutRow,
		alertIconSize, alertTextSize, alertClassColor, alertLock, resetPos, testAlertBtn,
	}
	local soundLockables = { soundDrop, channelDrop, testSoundBtn }
	local glowHint = MakeLockHint(glowCard, "Enable Show glow in Tracking or Whispers to edit appearance.")
	local durationHint = MakeLockHint(durationCard, "Enable Show duration in Tracking to edit appearance.")
	local alertHint = MakeLockHint(alertCard, "Enable Show alert in Tracking or Whispers to edit appearance.")
	local soundHint = MakeLockHint(soundCard, "Enable Play sound in Tracking or Whispers to edit appearance.")

	local function GlowItemsFor(style)
		local thick = style == "border" or style == "pixel"
		local speed = style == "border" or style == "fill" or style == "pixel"
		local pixel = style == "pixel"
		local pulse = style == "border" or style == "fill"
		local countdown = style == "countdown"
		local items = { { swatch, opacitySlider } }
		if speed and thick then
			items[#items + 1] = { speedSlider, thickSlider }
		elseif speed then
			items[#items + 1] = speedSlider
		elseif thick then
			items[#items + 1] = thickSlider
		end
		if pixel then
			items[#items + 1] = { linesSlider, lengthSlider }
		end
		if pulse then
			items[#items + 1] = pulseCb
		end
		if countdown then
			items[#items + 1] = countdownAnchor
			items[#items + 1] = { countdownX, countdownY }
			items[#items + 1] = countdownHeight
		end
		return items, thick, speed, pixel, pulse, countdown
	end
	local function RowHeight(item)
		if type(item) == "table" and item[1] and item[2] then
			if item[1].FitDesc then
				item[1]:FitDesc()
			end
			if item[2].FitDesc then
				item[2]:FitDesc()
			end
			return math.max(item[1]:GetHeight() or 0, item[2]:GetHeight() or 0)
		end
		if item.FitDesc then
			item:FitDesc()
		end
		return item:GetHeight() or 0
	end
	local function ItemsHeight(items, gap)
		local total = 0
		for i = 1, #items do
			total = total + RowHeight(items[i])
			if i < #items then
				total = total + gap
			end
		end
		return total
	end
	local function MaxGlowItemsHeight(gap)
		local maxH = 0
		for i = 1, #addon.GLOW_STYLES do
			maxH = math.max(maxH, ItemsHeight(GlowItemsFor(addon.GLOW_STYLES[i].id), gap))
		end
		return maxH
	end
	local function HintPad(hint)
		if hint and hint.IsLocked and hint:IsLocked() then
			return 32
		end
		return 0
	end
	local function PlaceCol(card, side, y)
		card:ClearAllPoints()
		local half = COL_GAP / 2
		if side == "left" then
			card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
			card:SetPoint("TOPRIGHT", parent, "TOP", -half, y)
		else
			card:SetPoint("TOPLEFT", parent, "TOP", half, y)
			card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
		end
	end
	local function PlaceLabeledRow(card, label, row, inner)
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", card, "TOPLEFT", 12, inner)
		inner = inner - 16
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", card, "TOPLEFT", 12, inner)
		row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, inner)
		if row.LayoutChoices then
			row:LayoutChoices()
		end
		return inner - (row:GetHeight() or 24) - 6
	end

	local RelayoutAppearance
	local relayouting
	RelayoutAppearance = function()
		if relayouting then
			return
		end
		relayouting = true
		local glowStyle = DB().glowStyle or "pixel"
		local glowItems, thick, speed, pixel, pulse, countdown = GlowItemsFor(glowStyle)
		local alertGlowOn = (DB().alertGlowStyle or "starburst") ~= "none"
		speedSlider:SetShown(speed)
		thickSlider:SetShown(thick)
		linesSlider:SetShown(pixel)
		lengthSlider:SetShown(pixel)
		pulseCb:SetShown(pulse)
		if pulseCb.desc then
			pulseCb.desc:SetText(PulseDesc(glowStyle))
		end
		countdownAnchor:SetShown(countdown)
		countdownX:SetShown(countdown)
		countdownY:SetShown(countdown)
		countdownHeight:SetShown(countdown)
		alertSwatch:SetShown(alertGlowOn)
		alertOpacity:SetShown(alertGlowOn)

		PlaceCol(glowCard, "left", 0)
		PlaceCol(alertCard, "right", 0)
		PlaceCol(durationCard, "left", 0)
		PlaceCol(soundCard, "right", 0)

		local glowInner = PlaceLabeledRow(glowCard, styleLbl, styleRow, -32 - HintPad(glowHint))
		local glowAfterStyle = glowInner
		glowInner = Stack(glowCard, glowItems, glowInner, 6, 12)
		glowInner = glowAfterStyle - math.max(glowAfterStyle - glowInner, MaxGlowItemsHeight(6))
		local glowH = EndCard(glowCard, glowInner)

		local durationInner = PlaceLabeledRow(durationCard, durationHostLbl, durationHostRow, -32 - HintPad(durationHint))
		durationInner = Stack(durationCard, {
			{ durationAnchor, durationFont },
			{ durationX, durationY },
			{ durationSize, durationSwatch },
		}, durationInner, 6, 12)
		local durationH = EndCard(durationCard, durationInner)

		local alertInner = PlaceLabeledRow(alertCard, glowStyleLbl, alertGlowRow, -32 - HintPad(alertHint))
		local alertItems = {}
		if alertGlowOn then
			alertItems[#alertItems + 1] = { alertSwatch, alertOpacity }
		end
		alertInner = Stack(alertCard, alertItems, alertInner, 6, 12)
		if #alertItems > 0 then
			alertInner = alertInner - 6
		end
		alertInner = PlaceLabeledRow(alertCard, layoutLbl, layoutRow, alertInner)
		alertInner = Stack(alertCard, {
			{ alertIconSize, alertTextSize },
			alertClassColor,
			{ alertLock, resetPos },
		}, alertInner, 6, 12)
		if not alertGlowOn then
			alertInner = alertInner - (RowHeight({ alertSwatch, alertOpacity }) + 6)
		end
		local alertH = EndCard(alertCard, alertInner)

		local soundInner = Stack(soundCard, { soundDrop, channelDrop }, -32 - HintPad(soundHint), 6, 12)
		local soundH = EndCard(soundCard, soundInner)

		local topH = math.max(glowH, alertH)
		local botH = math.max(durationH, soundH)
		local viewH = 0
		if tabFrames.alertsScroll and tabFrames.alertsScroll.frame then
			viewH = tabFrames.alertsScroll.frame:GetHeight() or 0
		end
		local extra = math.max(0, viewH - (topH + 10 + botH))
		botH = botH + extra
		glowCard:SetHeight(topH)
		alertCard:SetHeight(topH)
		durationCard:SetHeight(botH)
		soundCard:SetHeight(botH)

		PlaceCol(glowCard, "left", 0)
		PlaceCol(alertCard, "right", 0)
		PlaceCol(durationCard, "left", -topH - 10)
		PlaceCol(soundCard, "right", -topH - 10)

		parent:SetHeight(math.max(200, topH + 10 + botH))
		if tabFrames.alertsScroll then
			tabFrames.alertsScroll:Layout()
			tabFrames.alertsScroll:Update()
		end
		relayouting = false
	end

	for i = 1, #styleRow.buttons do
		local btn = styleRow.buttons[i]
		local id = btn.id
		btn:SetScript("OnClick", function()
			DB().glowStyle = id
			styleRow:Refresh()
			RelayoutAppearance()
			if addon.ApplySettings then
				addon.ApplySettings()
			end
		end)
	end
	for i = 1, #alertGlowRow.buttons do
		local btn = alertGlowRow.buttons[i]
		local id = btn.id
		btn:SetScript("OnClick", function()
			DB().alertGlowStyle = id
			alertGlowRow:Refresh()
			RelayoutAppearance()
			if addon.ApplySettings then
				addon.ApplySettings()
			end
		end)
	end

	local function SetLockGroup(items, on)
		for i = 1, #items do
			SetOptionLocked(items[i], on)
		end
	end
	local function RefreshAppearanceLockouts()
		local db = DB()
		local glowOn = db.glowRaid == true or db.glowParty == true or db.glowFocus == true or db.whisperRaidGlow == true
		local durationOn = db.durationRaid == true or db.durationParty == true
		local alertOn = db.alertRaid == true or db.alertParty == true or db.alertFocus == true or db.alertWhisper == true
		local soundOn = db.focusSound == true or db.raidSound == true or db.partySound == true or db.whisperSound == true
		SetLockGroup(glowLockables, glowOn)
		SetLockGroup(durationLockables, durationOn)
		SetLockGroup(alertLockables, alertOn)
		SetLockGroup(soundLockables, soundOn)
		glowHint:SetLocked(not glowOn)
		durationHint:SetLocked(not durationOn)
		alertHint:SetLocked(not alertOn)
		soundHint:SetLocked(not soundOn)
		RelayoutAppearance()
	end
	addon.RefreshAppearanceLockouts = RefreshAppearanceLockouts
	addon.RefreshDurationLockout = RefreshAppearanceLockouts
	addon.RefreshAppearanceLayout = RelayoutAppearance
	RefreshAppearanceLockouts()
	return parent:GetHeight()
end

RefreshAll = function()
	UI.RefreshWidgets()
	addon.ApplyOptionsScale()
	if addon.RefreshTrackingTab then
		addon.RefreshTrackingTab()
	end
	if addon.RefreshWhispersTab then
		addon.RefreshWhispersTab()
	end
	if addon.RefreshFocusRemindLockout then
		addon.RefreshFocusRemindLockout()
	end
	if addon.RefreshPIReadyLockout then
		addon.RefreshPIReadyLockout()
	end
	if addon.RefreshAppearanceLockouts then
		addon.RefreshAppearanceLockouts()
	end
end

SelectTab = function(id)
	CloseDropMenu()
	activeTab = id
	for key, frame in pairs(tabFrames) do
		if key == "general" or key == "tracking" or key == "alerts" or key == "whispers" then
			frame:SetShown(key == id)
		end
	end
	for key, btn in pairs(tabButtons) do
		local on = key == id
		if on then
			btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
			btn.label:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
		else
			btn:SetBorderColor(C.border[1], C.border[2], C.border[3], 0)
			btn.label:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
		end
	end
	if id == "general" then
		activeScroll = tabFrames.generalScroll
	elseif id == "tracking" then
		activeScroll = tabFrames.trackingScroll
	elseif id == "alerts" then
		activeScroll = tabFrames.alertsScroll
	elseif id == "whispers" then
		activeScroll = tabFrames.whispersScroll
	end
	if activeScroll then
		activeScroll.frame:SetVerticalScroll(0)
		activeScroll:Layout()
		activeScroll:Update()
	end
	LayoutBody()
end

local layingOut
LayoutBody = function()
	if not optionsFrame or layingOut then
		return
	end
	layingOut = true
	UI.LayoutAll()
	if addon.RefreshAppearanceLayout then
		addon.RefreshAppearanceLayout()
	end
	layingOut = false
end

Build = function()
	if optionsFrame then
		return
	end

	local f = CreateFrame("Frame", "PIHelperOptions", UIParent)
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(false)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PIHelperOptions")
	optionsFrame = f
	Fill(f, "BACKGROUND", C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 0.98)
	AddBorder(f, C.windowBorder[1], C.windowBorder[2], C.windowBorder[3])

	local titleIcon = f:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(20, 20)
	titleIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
	titleIcon:SetTexture("Interface\\Icons\\spell_holy_powerinfusion")
	titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = f:CreateFontString(nil, "OVERLAY", "PIH_FontTitle")
	title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
	title:SetText("PI Helper")
	title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

	local close = CreateFrame("Button", nil, f)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -12)
	Fill(close, "BACKGROUND", C.danger[1], C.danger[2], C.danger[3], 1)
	local closeLbl = close:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	closeLbl:SetPoint("CENTER", 0.5, 0.5)
	closeLbl:SetText("X")
	closeLbl:SetTextColor(1, 1, 1, 1)
	close:SetScript("OnClick", function()
		f:Hide()
	end)

	local tabs = {
		{ "general", "General" },
		{ "tracking", "Tracking" },
		{ "whispers", "Whispers" },
		{ "alerts", "Appearance" },
	}
	local prevTab
	for i = 1, #tabs do
		local id, label = tabs[i][1], tabs[i][2]
		local btn = CreateFrame("Button", nil, f)
		btn:SetHeight(22)
		AddBorder(btn, C.border[1], C.border[2], C.border[3], 0)
		btn:SetBorderColor(C.border[1], C.border[2], C.border[3], 0)
		local fs = btn:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
		fs:SetPoint("CENTER", 0, 1)
		fs:SetText(label)
		fs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
		btn:SetWidth((fs:GetStringWidth() or 60) + 20)
		btn.label = fs
		if i == 1 then
			btn:SetPoint("LEFT", title, "RIGHT", 28, -1)
		else
			btn:SetPoint("LEFT", prevTab, "RIGHT", 10, 0)
		end
		btn:SetScript("OnEnter", function()
			if activeTab ~= id then
				fs:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
			end
		end)
		btn:SetScript("OnLeave", function()
			if activeTab == id then
				fs:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
			else
				fs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
			end
		end)
		btn:SetScript("OnClick", function()
			SelectTab(id)
		end)
		tabButtons[id] = btn
		prevTab = btn
	end

	local headerLine = f:CreateTexture(nil, "ARTWORK")
	headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H)
	headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)
	headerLine:SetColorTexture(C.windowBorder[1], C.windowBorder[2], C.windowBorder[3], 0.7)
	Hairline(headerLine, "h")

	local footerLine = f:CreateTexture(nil, "ARTWORK")
	footerLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, FOOTER_H)
	footerLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOTER_H)
	footerLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
	Hairline(footerLine, "h")

	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEADER_H + 10))
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOTER_H + 10)
	body:EnableMouseWheel(true)
	body:SetScript("OnMouseWheel", function(_, delta)
		if activeScroll then
			activeScroll:ScrollBy(delta)
		end
	end)

	tabFrames.general = CreateFrame("Frame", nil, body)
	tabFrames.general:SetAllPoints()
	local generalHolder = CreateFrame("Frame", nil, tabFrames.general)
	generalHolder:SetAllPoints()
	local GENERAL_FOOTER_H = 34
	tabFrames.generalScroll = MakeScrollArea(generalHolder, { bottomInset = GENERAL_FOOTER_H })
	tabFrames.generalScroll.child:SetHeight(BuildGeneralTab(tabFrames.generalScroll.child))

	local creditBar = CreateFrame("Frame", nil, generalHolder)
	creditBar:SetHeight(GENERAL_FOOTER_H)
	creditBar:SetPoint("BOTTOMLEFT", generalHolder, "BOTTOMLEFT", 0, 0)
	creditBar:SetPoint("BOTTOMRIGHT", generalHolder, "BOTTOMRIGHT", 0, 0)
	creditBar:SetFrameLevel(tabFrames.generalScroll.frame:GetFrameLevel() + 2)
	local madeBy = creditBar:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	madeBy:SetPoint("LEFT", creditBar, "LEFT", 12, 0)
	madeBy:SetText("Made by:")
	madeBy:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local author = creditBar:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	author:SetPoint("LEFT", madeBy, "RIGHT", 8, 0)
	author:SetText("squided")
	author:SetTextColor(0x80 / 255, 0xE0 / 255, 0xE0 / 255)
	local authorIcon = creditBar:CreateTexture(nil, "ARTWORK")
	authorIcon:SetSize(24, 24)
	authorIcon:SetPoint("LEFT", author, "RIGHT", 6, 0)
	authorIcon:SetTexture(632858)

	local resetBtn = MakeButton(generalHolder, "Reset to Defaults")
	resetBtn:SetWidth(130)
	resetBtn:SetFrameLevel(creditBar:GetFrameLevel() + 1)
	resetBtn:SetPoint("BOTTOMRIGHT", generalHolder, "BOTTOMRIGHT", -12, 6)
	resetBtn:SetScript("OnClick", ConfirmResetToDefaults)

	local importBtn = MakeButton(generalHolder, "Import")
	importBtn:SetWidth(70)
	importBtn:SetFrameLevel(creditBar:GetFrameLevel() + 1)
	importBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
	importBtn:SetScript("OnClick", function()
		ShowProfileDialog("import")
	end)

	local exportBtn = MakeButton(generalHolder, "Export")
	exportBtn:SetWidth(70)
	exportBtn:SetFrameLevel(creditBar:GetFrameLevel() + 1)
	exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -6, 0)
	exportBtn:SetScript("OnClick", function()
		ShowProfileDialog("export")
	end)

	tabFrames.tracking = CreateFrame("Frame", nil, body)
	tabFrames.tracking:SetAllPoints()
	tabFrames.trackingScroll = addon.BuildTrackingTab(tabFrames.tracking)

	tabFrames.alerts = CreateFrame("Frame", nil, body)
	tabFrames.alerts:SetAllPoints()
	local alertsHolder = CreateFrame("Frame", nil, tabFrames.alerts)
	alertsHolder:SetAllPoints()
	tabFrames.alertsScroll = MakeScrollArea(alertsHolder)
	tabFrames.alertsScroll.child:SetHeight(BuildAlertsTab(tabFrames.alertsScroll.child))

	tabFrames.whispers = CreateFrame("Frame", nil, body)
	tabFrames.whispers:SetAllPoints()
	local whisperHolder = CreateFrame("Frame", nil, tabFrames.whispers)
	whisperHolder:SetAllPoints()
	tabFrames.whispersScroll = MakeScrollArea(whisperHolder)
	tabFrames.whispersScroll.child:SetHeight(addon.BuildWhispersTab(tabFrames.whispersScroll.child, tabFrames.whispersScroll))

	local version = f:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	version:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 14)
	version:SetText("v" .. addon.VERSION .. "   /pih  /pihelper")
	version:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
	grip:EnableMouse(true)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

	local scaling
	local scaleLeft, scaleTop, grabOffX, grabOffY
	local function ApplyScaleFromCursor()
		if not scaleLeft or not scaleTop then
			return
		end
		local cx, cy = GetCursorPosition()
		local uiScale = UIParent:GetEffectiveScale()
		if not uiScale or uiScale == 0 then
			return
		end
		cx = cx / uiScale + (grabOffX or 0)
		cy = cy / uiScale + (grabOffY or 0)
		local dx = cx - scaleLeft
		local dy = scaleTop - cy
		local denom = WIN_W * WIN_W + WIN_H * WIN_H
		if denom <= 0 then
			return
		end
		local pct = ClampOptionsScalePct(((dx * WIN_W) + (dy * WIN_H)) / denom * 100)
		local db = DB()
		if db.optionsScale == pct and math.abs((f:GetScale() or 1) - pct / 100) <= 0.0001 then
			return
		end
		db.optionsScale = pct
		f:SetScale(pct / 100)
		PinOptionsTopLeft(f, scaleLeft, scaleTop)
		if UI.RefreshPixels then
			UI.RefreshPixels()
		end
	end
	local function StopScaleDrag()
		if not scaling then
			return
		end
		scaling = false
		grip:SetScript("OnUpdate", nil)
		f:SetClampedToScreen(true)
		ApplyScaleFromCursor()
		if UI.RefreshWidgets then
			UI.RefreshWidgets()
		end
		addon.ApplyOptionsScale()
		if LayoutBody then
			LayoutBody()
			C_Timer.After(0, function()
				if optionsFrame then
					LayoutBody()
				end
			end)
		end
	end
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		CloseDropMenu()
		f:StopMovingOrSizing()
		scaleLeft, scaleTop = GetVisualTopLeft(f)
		if not scaleLeft or not scaleTop then
			return
		end
		local cx, cy = GetCursorPosition()
		local uiScale = UIParent:GetEffectiveScale() or 1
		if uiScale == 0 then
			uiScale = 1
		end
		cx, cy = cx / uiScale, cy / uiScale
		local s = f:GetScale() or 1
		grabOffX = (scaleLeft + WIN_W * s) - cx
		grabOffY = (scaleTop - WIN_H * s) - cy
		f:SetClampedToScreen(false)
		PinOptionsTopLeft(f, scaleLeft, scaleTop)
		scaling = true
		grip:SetScript("OnUpdate", function()
			if not IsMouseButtonDown("LeftButton") then
				StopScaleDrag()
				return
			end
			ApplyScaleFromCursor()
		end)
	end)
	grip:SetScript("OnMouseUp", StopScaleDrag)

	f:SetScript("OnSizeChanged", function()
		LayoutBody()
	end)
	f:SetScript("OnShow", function()
		RefreshAll()
		LayoutBody()
		C_Timer.After(0, LayoutBody)
		if addon.SetAlertConfigMode then
			addon.SetAlertConfigMode(true)
		end
	end)
	f:SetScript("OnHide", function()
		StopScaleDrag()
		if addon.StopWhisperNameDrag then
			addon.StopWhisperNameDrag(false)
		end
		CloseDropMenu()
		HideResetConfirm()
		HideProfileDialog()
		if addon.SetAlertConfigMode then
			addon.SetAlertConfigMode(false)
		end
		if addon.HideTestAlert then
			addon.HideTestAlert()
		end
		if addon.HideTestGlow then
			addon.HideTestGlow()
		end
		if addon.HideTestDuration then
			addon.HideTestDuration()
		end
		if addon.HideTestFocusReminder then
			addon.HideTestFocusReminder()
		end
	end)
	SelectTab("tracking")
	addon.ApplyOptionsScale()
	f:Hide()
end

function addon.ToggleOptions()
	if not addon.db then
		return
	end
	Build()
	if optionsFrame:IsShown() then
		optionsFrame:Hide()
	else
		optionsFrame:Show()
		RefreshAll()
	end
end
