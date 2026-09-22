--[[
	PI Helper whispers tab: name rows, drag/drop, and whisper lockout.
]]

local ADDON_NAME, addon = ...

local C = addon.C
local UI = addon.UI
local Fill = UI.Fill
local AddBorder = UI.AddBorder
local BeginCard = UI.BeginCard
local EndCard = UI.EndCard
local MakeCheckbox = UI.MakeCheckbox
local MakeButton = UI.MakeButton
local MakeHelp = UI.MakeHelp
local AttachChevron = UI.AttachChevron
local MakeChoiceRow = UI.MakeChoiceRow
local MakeEditBox = UI.MakeEditBox
local Stack = UI.Stack
local SetOptionLocked = UI.SetOptionLocked

local listedHost
local sequenceHost
local teammatesCard
local whisperCycle
local whisperNameEdit
local whisperAddBtn
local whisperClearBtn
local whisperAfterModeY = 0
local whisperTabY = 0
local whisperScroll

local RebuildWhisperRows

local function DB()
	return addon.db
end

local function ApplySettings()
	if addon.ApplySettings then
		addon.ApplySettings()
	end
end

local function SetWindowMovable(on)
	if UI.SetWindowMovable then
		UI.SetWindowMovable(on)
	end
end

local function WhisperNameList()
	local db = DB()
	if not db then
		return {}
	end
	if db.whisperMode == "sequence" then
		if type(db.sequenceNames) ~= "table" then
			db.sequenceNames = {}
		end
		return db.sequenceNames
	end
	if type(db.whisperNames) ~= "table" then
		db.whisperNames = {}
	end
	return db.whisperNames
end

local NAME_ROW_H = 26
local nameDrag = {}

local function PaintNameRowBg(row, a)
	if row and row.bg then
		row.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], a or 0)
	end
end

local function ClearNameRowHighlights(host)
	if not host or not host.rows then
		return
	end
	for i = 1, #host.rows do
		local row = host.rows[i]
		PaintNameRowBg(row, 0)
		row:SetAlpha(1)
	end
end

local function NameDropIndex(host, count)
	if not host or count < 1 then
		return nil
	end
	local scale = host:GetEffectiveScale() or 1
	local _, cy = GetCursorPosition()
	cy = cy / scale
	local top = host:GetTop()
	if not top then
		return nil
	end
	local idx = math.floor((top - cy) / NAME_ROW_H) + 1
	if idx < 1 then
		idx = 1
	elseif idx > count then
		idx = count
	end
	return idx
end

local function EnsureNameDragGhost()
	if nameDrag.ghost then
		return nameDrag.ghost
	end
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetHeight(22)
	ghost:EnableMouse(false)
	Fill(ghost, "BACKGROUND", 0.16, 0.18, 0.19, 0.94)
	AddBorder(ghost, C.accent[1], C.accent[2], C.accent[3])
	ghost.label = ghost:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	ghost.label:SetPoint("LEFT", 10, 0)
	ghost.label:SetPoint("RIGHT", -10, 0)
	ghost.label:SetJustifyH("LEFT")
	ghost.label:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
	nameDrag.ghost = ghost
	return ghost
end

local function StopNameDrag(apply)
	SetWindowMovable(true)
	local ghost = nameDrag.ghost
	if ghost then
		ghost:SetScript("OnUpdate", nil)
		ghost:Hide()
	end
	local host = nameDrag.host
	local names = nameDrag.names
	local from = nameDrag.from
	local to = nameDrag.target
	nameDrag.active = false
	nameDrag.host = nil
	nameDrag.names = nil
	nameDrag.from = nil
	nameDrag.target = nil
	if host then
		ClearNameRowHighlights(host)
	end
	if apply and names and from and to and from ~= to then
		local item = table.remove(names, from)
		table.insert(names, to, item)
		RebuildWhisperRows()
		ApplySettings()
	end
end

local function UpdateNameDrag()
	if not nameDrag.active or not nameDrag.host then
		return
	end
	local ghost = nameDrag.ghost
	if ghost then
		local scale = ghost:GetEffectiveScale() or 1
		local x, y = GetCursorPosition()
		ghost:ClearAllPoints()
		ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale - 8)
	end
	local count = nameDrag.names and #nameDrag.names or 0
	local to = NameDropIndex(nameDrag.host, count)
	nameDrag.target = to
	for i = 1, count do
		local row = nameDrag.host.rows[i]
		if row then
			if i == nameDrag.from then
				row:SetAlpha(0.4)
				PaintNameRowBg(row, 0)
			else
				row:SetAlpha(1)
				PaintNameRowBg(row, (i == to) and 0.18 or 0)
			end
		end
	end
end

local function StartNameDrag(row)
	if not row or not row.names or #row.names < 2 then
		return
	end
	StopNameDrag(false)
	nameDrag.active = true
	nameDrag.host = row:GetParent()
	nameDrag.names = row.names
	nameDrag.from = row.index
	nameDrag.target = row.index
	SetWindowMovable(false)
	local ghost = EnsureNameDragGhost()
	ghost:SetWidth(math.max(120, (row:GetWidth() or 200) - 80))
	ghost.label:SetText(row.label and row.label:GetText() or "")
	ghost:Show()
	ghost:SetScript("OnUpdate", UpdateNameDrag)
	UpdateNameDrag()
end

local function FillNameRows(host, names)
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
			row:RegisterForDrag("LeftButton")
			row.bg = Fill(row, "BACKGROUND", C.accent[1], C.accent[2], C.accent[3], 0)
			row.grips = {}
			for g = 1, 6 do
				local dot = row:CreateTexture(nil, "ARTWORK")
				dot:SetSize(2, 2)
				local col = (g - 1) % 2
				local gy = math.floor((g - 1) / 2)
				dot:SetPoint("LEFT", row, "LEFT", 1 + col * 4, 4 - gy * 4)
				dot:SetColorTexture(C.textMuted[1], C.textMuted[2], C.textMuted[3], 0.85)
				row.grips[g] = dot
			end
			row.label = row:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
			row.label:SetPoint("LEFT", 14, 0)
			row.label:SetJustifyH("LEFT")
			row.label:SetWordWrap(false)
			row.label:SetTextColor(C.text[1], C.text[2], C.text[3])
			row.up = MakeButton(row, "")
			row.down = MakeButton(row, "")
			row.del = MakeButton(row, "x")
			row.up:SetSize(22, 20)
			row.down:SetSize(22, 20)
			row.del:SetSize(22, 20)
			row.del:SetPoint("RIGHT")
			row.down:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
			row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
			AttachChevron(row.up, "up")
			AttachChevron(row.down, "down")
			row.label:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
			row.up:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
			row.down:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
			row.del:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
			row:SetScript("OnEnter", function(self)
				if not nameDrag.active then
					PaintNameRowBg(self, 0.10)
				end
			end)
			row:SetScript("OnLeave", function(self)
				if not nameDrag.active then
					PaintNameRowBg(self, 0)
				end
			end)
			row:SetScript("OnDragStart", function(self)
				StartNameDrag(self)
			end)
			row:SetScript("OnDragStop", function()
				StopNameDrag(true)
			end)
			host.rows[i] = row
		end
		row:Show()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, y)
		row.names = names
		row.index = index
		row.label:SetText(index .. ". " .. names[index])
		row.up:SetAlpha(index > 1 and 1 or 0.35)
		row.down:SetAlpha(index < #names and 1 or 0.35)
		row.up:SetScript("OnClick", function()
			if index > 1 then
				names[index], names[index - 1] = names[index - 1], names[index]
				RebuildWhisperRows()
				ApplySettings()
			end
		end)
		row.down:SetScript("OnClick", function()
			if index < #names then
				names[index], names[index + 1] = names[index + 1], names[index]
				RebuildWhisperRows()
				ApplySettings()
			end
		end)
		row.del:SetScript("OnClick", function()
			table.remove(names, index)
			RebuildWhisperRows()
			ApplySettings()
		end)
		y = y - NAME_ROW_H
	end
	local h = math.max(20, -y)
	host:SetHeight(h)
	return h
end

RebuildWhisperRows = function()
	if nameDrag.active then
		StopNameDrag(false)
	end
	if not listedHost or not sequenceHost or not teammatesCard then
		return
	end
	local sequence = DB().whisperMode == "sequence"
	local y = whisperAfterModeY
	if whisperCycle then
		whisperCycle:SetShown(sequence)
		if sequence then
			whisperCycle:ClearAllPoints()
			whisperCycle:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, y)
			whisperCycle:SetPoint("TOPRIGHT", teammatesCard, "TOPRIGHT", -12, y)
			y = y - (whisperCycle:GetHeight() + 8)
		end
	end
	if whisperNameEdit and whisperAddBtn then
		whisperAddBtn:ClearAllPoints()
		whisperAddBtn:SetPoint("TOPRIGHT", teammatesCard, "TOPRIGHT", -12, y)
		whisperNameEdit:ClearAllPoints()
		whisperNameEdit:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, y)
		whisperNameEdit:SetPoint("RIGHT", whisperAddBtn, "LEFT", -8, 0)
	end
	y = y - 34
	listedHost:ClearAllPoints()
	listedHost:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, y)
	listedHost:SetPoint("TOPRIGHT", teammatesCard, "TOPRIGHT", -12, y)
	listedHost:SetShown(not sequence)
	sequenceHost:ClearAllPoints()
	sequenceHost:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, y)
	sequenceHost:SetPoint("TOPRIGHT", teammatesCard, "TOPRIGHT", -12, y)
	sequenceHost:SetShown(sequence)
	local listedH = FillNameRows(listedHost, DB().whisperNames)
	local seqH = FillNameRows(sequenceHost, DB().sequenceNames)
	local hostH = sequence and seqH or listedH
	if whisperClearBtn then
		local names = WhisperNameList()
		whisperClearBtn:SetAlpha((names and #names > 0) and 1 or 0.4)
	end
	teammatesCard:SetHeight(math.max(80, -y + hostH + 16))
	if whisperScroll then
		whisperScroll.child:SetHeight(math.max(360, -(whisperTabY or 0) + teammatesCard:GetHeight() + 8))
		whisperScroll:Update()
	end
	if addon.RefreshWhisperLockout then
		addon.RefreshWhisperLockout()
	end
end

function addon.RefreshWhispersTab()
	RebuildWhisperRows()
end

function addon.StopWhisperNameDrag(apply)
	StopNameDrag(apply)
end

function addon.BuildWhispersTab(parent, scrollArea)
	whisperScroll = scrollArea
	local y = 0
	local panel, inner = BeginCard(parent, y, "Whisper requests")
	local intro = panel:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	intro:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, inner)
	intro:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
	intro:SetJustifyH("LEFT")
	intro:SetWordWrap(true)
	intro:SetText("Any in-game whisper while you are in combat with PI ready is treated as a PI request. Midnight cannot see who sent it or what they typed, so add the people you want to PI under Teammates.")
	intro:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local introH = intro:GetStringHeight()
	if type(introH) ~= "number" or introH < 12 then
		introH = 28
	end
	inner = inner - introH - 10
	local enableCb = MakeCheckbox(panel, "Enable whisper requests", nil, function()
		return DB().whisperEnabled
	end, function(v)
		DB().whisperEnabled = v
		if addon.RefreshWhisperLockout then
			addon.RefreshWhisperLockout()
		end
	end, "Any incoming whisper while you are in a group, in combat, with PI ready. Sender and text cannot be read; the Teammates list decides who to highlight.")
	local raidOnlyCb = MakeCheckbox(panel, "Only in raid", nil, function()
		return DB().whisperRaidOnly == true
	end, function(v)
		DB().whisperRaidOnly = v and true or false
	end, "Ignore whispers in dungeons and party groups. Only treat whispers as PI requests while you are in a raid.")
	local bnetCb = MakeCheckbox(panel, "Ignore Battle.net whispers", nil, function()
		return DB().whisperIgnoreBnet ~= false
	end, function(v)
		DB().whisperIgnoreBnet = v and true or false
	end, "Battle.net whispers will not count as a PI request.")
	local glowCb = MakeCheckbox(panel, "Show glow", nil, function()
		return DB().whisperRaidGlow == true
	end, function(v)
		DB().whisperRaidGlow = v
		if addon.RefreshAppearanceLockouts then
			addon.RefreshAppearanceLockouts()
		end
	end)
	local alertCb = MakeCheckbox(panel, "Show alert", nil, function()
		return DB().alertWhisper == true
	end, function(v)
		DB().alertWhisper = v
		if addon.SyncAlertSource then
			addon.SyncAlertSource()
		end
		if addon.RefreshAppearanceLockouts then
			addon.RefreshAppearanceLockouts()
		end
	end)
	local soundCb = MakeCheckbox(panel, "Play sound", nil, function()
		return DB().whisperSound == true
	end, function(v)
		DB().whisperSound = v
		if addon.RefreshAppearanceLockouts then
			addon.RefreshAppearanceLockouts()
		end
	end)
	inner = Stack(panel, { enableCb }, inner, 6, 12)
	inner = Stack(panel, { raidOnlyCb, bnetCb, alertCb, glowCb, soundCb }, inner - 2, 6, 24)
	y = y - EndCard(panel, inner) - 10

	whisperTabY = y
	teammatesCard, inner = BeginCard(parent, y, "Teammates")
	local teammatesHelp = MakeHelp(teammatesCard, "The addon cannot see who whispered you. It highlights a name from this list who is currently in the group. Character name is enough; add -Realm only if two people share a name.")
	teammatesHelp:SetPoint("LEFT", teammatesCard.header, "RIGHT", 6, 0)
	whisperClearBtn = MakeButton(teammatesCard, "Clear all")
	whisperClearBtn:SetHeight(22)
	whisperClearBtn:SetWidth(math.max(84, (whisperClearBtn.label:GetStringWidth() or 50) + 18))
	whisperClearBtn:SetPoint("TOPRIGHT", teammatesCard, "TOPRIGHT", -10, -8)
	whisperClearBtn:SetFrameLevel((teammatesCard:GetFrameLevel() or 1) + 4)
	whisperClearBtn:SetScript("OnClick", function()
		local names = WhisperNameList()
		if not names or #names == 0 then
			return
		end
		wipe(names)
		if addon.ResetWhisperSequence then
			addon.ResetWhisperSequence()
		end
		RebuildWhisperRows()
		ApplySettings()
	end)
	local namesNote = teammatesCard:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	namesNote:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, inner)
	namesNote:SetPoint("RIGHT", teammatesCard, "RIGHT", -12, 0)
	namesNote:SetJustifyH("LEFT")
	namesNote:SetWordWrap(true)
	namesNote:SetText("Character name is enough. Add -Realm only if two people share a name.")
	namesNote:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local namesNoteH = namesNote:GetStringHeight()
	if type(namesNoteH) ~= "number" or namesNoteH < 12 then
		namesNoteH = 12
	end
	inner = inner - namesNoteH - 10
	local modeLbl = teammatesCard:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	modeLbl:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, inner)
	modeLbl:SetText("Mode")
	modeLbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	inner = inner - 18
	local modeRow = MakeChoiceRow(teammatesCard, addon.WHISPER_MODES, function()
		return DB().whisperMode == "sequence" and "sequence" or "listed"
	end, function(id)
		DB().whisperMode = id
		DB().whisperSequence = id == "sequence"
		if addon.ResetWhisperSequence then
			addon.ResetWhisperSequence()
		end
		RebuildWhisperRows()
	end)
	modeRow:SetPoint("TOPLEFT", teammatesCard, "TOPLEFT", 12, inner)
	modeRow:SetPoint("TOPRIGHT", teammatesCard, "TOPRIGHT", -12, inner)
	inner = inner - 32
	whisperAfterModeY = inner

	whisperCycle = MakeCheckbox(teammatesCard, "Cycle", nil, function()
		return DB().whisperCycle
	end, function(v) DB().whisperCycle = v end, "After the last player in the rotation, return to the first.")

	whisperAddBtn = MakeButton(teammatesCard, "Add")
	whisperAddBtn:SetWidth(60)
	whisperNameEdit = MakeEditBox(teammatesCard, 200)
	whisperNameEdit:SetMaxLetters(48)
	local namePlaceholder = whisperNameEdit:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	namePlaceholder:SetPoint("LEFT", whisperNameEdit, "LEFT", 8, 0)
	namePlaceholder:SetPoint("RIGHT", whisperNameEdit, "RIGHT", -8, 0)
	namePlaceholder:SetJustifyH("LEFT")
	namePlaceholder:SetWordWrap(false)
	namePlaceholder:SetText("Name or Name-Realm")
	namePlaceholder:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	local function RefreshNamePlaceholder()
		local text = strtrim(whisperNameEdit:GetText() or "")
		namePlaceholder:SetShown(text == "")
	end
	whisperNameEdit:SetScript("OnTextChanged", RefreshNamePlaceholder)
	RefreshNamePlaceholder()
	local function addName(text)
		local names = WhisperNameList()
		if not addon.AddUniqueName or not addon.AddUniqueName(names, text) then
			return
		end
		whisperNameEdit:SetText("")
		RebuildWhisperRows()
		ApplySettings()
	end
	whisperNameEdit.OnSubmit = addName
	whisperAddBtn:SetScript("OnClick", function()
		addName(whisperNameEdit:GetText())
	end)

	listedHost = CreateFrame("Frame", nil, teammatesCard)
	sequenceHost = CreateFrame("Frame", nil, teammatesCard)

	local function RefreshWhisperLockout()
		local on = DB().whisperEnabled ~= false
		SetOptionLocked(raidOnlyCb, on)
		SetOptionLocked(glowCb, on)
		SetOptionLocked(alertCb, on)
		SetOptionLocked(soundCb, on)
		SetOptionLocked(bnetCb, on)
		SetOptionLocked(teammatesCard, on)
		if whisperClearBtn then
			local names = WhisperNameList()
			if on then
				whisperClearBtn:SetAlpha((names and #names > 0) and 1 or 0.4)
			else
				whisperClearBtn:SetAlpha(1)
			end
		end
	end
	addon.RefreshWhisperLockout = RefreshWhisperLockout
	RefreshWhisperLockout()

	RebuildWhisperRows()
	return math.max(360, -whisperTabY + (teammatesCard:GetHeight() or 80) + 8)
end
