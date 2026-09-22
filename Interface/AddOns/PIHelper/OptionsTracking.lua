--[[
	PI Helper tracking tab: class headers, scope buttons, custom spells, search.
]]

local ADDON_NAME, addon = ...

local LEFT_W = 288

local C = addon.C
local CLASS_COLORS = addon.CLASS_COLORS
local UI = addon.UI
local Fill = UI.Fill
local AddBorder = UI.AddBorder
local Hairline = UI.Hairline
local MakeHeader = UI.MakeHeader
local MakeHelp = UI.MakeHelp
local MakePanel = UI.MakePanel
local BeginCard = UI.BeginCard
local EndCard = UI.EndCard
local PaintCheck = UI.PaintCheck
local MakeCheckBox = UI.MakeCheckBox
local MakeCheckbox = UI.MakeCheckbox
local MakeButton = UI.MakeButton
local MakeEditBox = UI.MakeEditBox
local MakeChoiceRow = UI.MakeChoiceRow
local FillNameList = UI.FillNameList
local Stack = UI.Stack
local SetOptionLocked = UI.SetOptionLocked
local MakeChevron = UI.MakeChevron
local SetChevronDir = UI.SetChevronDir
local MakeScrollArea = UI.MakeScrollArea

local cooldownState = {
	query = "",
	headers = {},
	rows = {},
	customRows = {},
	area = nil,
	host = nil,
	search = nil,
	placeholder = nil,
}

local RebuildCooldownList
local rebuildPlayers
local refreshLockouts = {}
local relayoutLeft

local ALERT_OVERLAP_TIP = "If several people pop cooldowns at once, their alerts can overlap."
local SOUND_COOLDOWN_WARNING = {
	warning = true,
	title = "Sounds cannot follow your PI cooldown",
	body = "Unlike glows, tracking sounds cannot be silenced while Power Infusion is on cooldown. Midnight addon restrictions do not support enabling/disabling sounds in combat.\n\nThe sound will play anytime a tracked buff is active, regardless of your own PI cooldown.",
}

local function DB()
	return addon.db
end

local function CooldownCollapsed()
	local db = DB()
	if type(db.cooldownCollapsed) ~= "table" then
		db.cooldownCollapsed = {}
	end
	return db.cooldownCollapsed
end

local function TrackingCollapsed()
	local db = DB()
	if type(db.trackingCollapsed) ~= "table" then
		db.trackingCollapsed = {}
	end
	return db.trackingCollapsed
end

local function ApplySettings()
	if addon.ApplySettings then
		addon.ApplySettings()
	end
end

local function SpellIcon(spellID)
	local tex = C_Spell.GetSpellTexture(spellID)
	if tex then
		return tex
	end
	local info = C_Spell.GetSpellInfo(spellID)
	if type(info) == "table" and info.iconID then
		return info.iconID
	end
	return 134400
end

local function SpellLabel(spellID, fallback)
	local name = C_Spell.GetSpellName(spellID)
	if type(name) == "string" and name ~= "" then
		return name
	end
	return fallback or tostring(spellID)
end

local function SpellIsOn(spell)
	local v = DB().spellEnabled[spell.spellID]
	if v == nil then
		return not spell.isPotion
	end
	return v and true or false
end

local function ClassColor(className)
	local c = CLASS_COLORS and CLASS_COLORS[className]
	if c then
		return c[1], c[2], c[3]
	end
	return C.accent[1], C.accent[2], C.accent[3]
end

local function MatchesQuery(...)
	local q = cooldownState.query
	if not q or q == "" then
		return true
	end
	local n = select("#", ...)
	for i = 1, n do
		local v = select(i, ...)
		if v ~= nil and string.find(string.lower(tostring(v)), q, 1, true) then
			return true
		end
	end
	return false
end

local SCOPE_TIPS = {
	raid = "Track this in raids",
	party = "Track this in dungeons",
	focus = "Track this on your focus",
}

local function PaintScopeBtn(btn, on)
	if on then
		btn:SetBorderColor(C.accent[1], C.accent[2], C.accent[3])
		btn.label:SetTextColor(C.textAccent[1], C.textAccent[2], C.textAccent[3])
	else
		btn:SetBorderColor(C.border[1], C.border[2], C.border[3])
		btn.label:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	end
end

local function MakeScopeBtn(parent, letter, key)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(22, 18)
	Fill(btn, "BACKGROUND", 0.10, 0.11, 0.12, 1)
	AddBorder(btn, C.border[1], C.border[2], C.border[3])
	local lbl = btn:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	lbl:SetPoint("CENTER", 0, 0)
	lbl:SetText(letter)
	btn.label = lbl
	btn.scopeKey = key
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(SCOPE_TIPS[key] or ("Track in " .. letter), 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn
end

local function LayoutScopeBtns(row)
	local show = addon.SpellScopeEnabled and addon.SpellScopeEnabled()
	if row.scopeRaid then
		row.scopeRaid:SetShown(show)
		row.scopeParty:SetShown(show)
		row.scopeFocus:SetShown(show)
	end
	if not row.hit then
		return
	end
	row.hit:ClearAllPoints()
	row.hit:SetPoint("TOPLEFT")
	row.hit:SetPoint("BOTTOMLEFT")
	if show and row.scopeRaid then
		row.hit:SetPoint("RIGHT", row.scopeRaid, "LEFT", -6, 0)
	elseif row.del then
		row.hit:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
	else
		row.hit:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	end
end

local function RefreshScopeBtns(row, spellID, masterOn)
	LayoutScopeBtns(row)
	if not row.scopeRaid then
		return
	end
	local scope = addon.GetSpellScope and addon.GetSpellScope(spellID) or { raid = true, party = true, focus = true }
	PaintScopeBtn(row.scopeRaid, scope.raid ~= false)
	PaintScopeBtn(row.scopeParty, scope.party ~= false)
	PaintScopeBtn(row.scopeFocus, scope.focus ~= false)
	local alpha = masterOn and 1 or 0.4
	row.scopeRaid:SetAlpha(alpha)
	row.scopeParty:SetAlpha(alpha)
	row.scopeFocus:SetAlpha(alpha)
end

local function BindScopeBtn(btn, getID)
	btn:SetScript("OnClick", function()
		local spellID = getID()
		if type(spellID) ~= "number" or not addon.GetSpellScope then
			return
		end
		local scope = addon.GetSpellScope(spellID)
		scope[btn.scopeKey] = not scope[btn.scopeKey]
		PaintScopeBtn(btn, scope[btn.scopeKey] ~= false)
		ApplySettings()
	end)
end

local function AcquireClassHeader(className)
	local header = cooldownState.headers[className]
	if header then
		return header
	end
	header = CreateFrame("Button", nil, cooldownState.host)
	header:SetHeight(22)
	header.caret = MakeChevron(header, "down")
	header.caret:SetPoint("LEFT", 2, 0)
	header.label = header:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	header.label:SetPoint("LEFT", header.caret, "RIGHT", 6, 0)
	header.line = header:CreateTexture(nil, "BACKGROUND")
	header.line:SetPoint("BOTTOMLEFT", 0, 0)
	header.line:SetPoint("BOTTOMRIGHT", 0, 0)
	header.line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.6)
	Hairline(header.line, "h")
	header:SetScript("OnClick", function()
		local collapsed = CooldownCollapsed()
		collapsed[className] = not collapsed[className]
		RebuildCooldownList()
	end)
	cooldownState.headers[className] = header
	return header
end

local function AcquireSpellRow(spellID)
	local row = cooldownState.rows[spellID]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, cooldownState.host)
	row:SetHeight(24)
	row.scopeFocus = MakeScopeBtn(row, "F", "focus")
	row.scopeFocus:SetPoint("RIGHT", -2, 0)
	row.scopeParty = MakeScopeBtn(row, "D", "party")
	row.scopeParty:SetPoint("RIGHT", row.scopeFocus, "LEFT", -4, 0)
	row.scopeRaid = MakeScopeBtn(row, "R", "raid")
	row.scopeRaid:SetPoint("RIGHT", row.scopeParty, "LEFT", -4, 0)
	BindScopeBtn(row.scopeRaid, function() return row.spellID end)
	BindScopeBtn(row.scopeParty, function() return row.spellID end)
	BindScopeBtn(row.scopeFocus, function() return row.spellID end)

	row.hit = CreateFrame("Button", nil, row)
	row.hit:SetPoint("TOPLEFT")
	row.hit:SetPoint("BOTTOMLEFT")
	row.hit:SetPoint("RIGHT", row.scopeRaid, "LEFT", -6, 0)

	row.box, row.mark = MakeCheckBox(row.hit, 13)
	row.box:SetPoint("LEFT", 4, 0)
	row.icon = row.hit:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.label = row.hit:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", row.hit, "RIGHT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetTextColor(C.text[1], C.text[2], C.text[3])
	row.hit:SetScript("OnEnter", function(self)
		if row.spellID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if GameTooltip.SetSpellByID then
				GameTooltip:SetSpellByID(row.spellID)
			else
				GameTooltip:SetText(row.label:GetText() or "", 1, 1, 1)
				GameTooltip:AddLine("Spell ID " .. row.spellID, C.textMuted[1], C.textMuted[2], C.textMuted[3])
			end
			GameTooltip:Show()
		end
	end)
	row.hit:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	cooldownState.rows[spellID] = row
	return row
end

local function AcquireCustomRow(index)
	local row = cooldownState.customRows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, cooldownState.host)
	row:SetHeight(24)
	row.del = MakeButton(row, "x")
	row.del:SetSize(22, 20)
	row.del:SetPoint("RIGHT", -2, 0)
	row.scopeFocus = MakeScopeBtn(row, "F", "focus")
	row.scopeFocus:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
	row.scopeParty = MakeScopeBtn(row, "D", "party")
	row.scopeParty:SetPoint("RIGHT", row.scopeFocus, "LEFT", -4, 0)
	row.scopeRaid = MakeScopeBtn(row, "R", "raid")
	row.scopeRaid:SetPoint("RIGHT", row.scopeParty, "LEFT", -4, 0)

	row.hit = CreateFrame("Button", nil, row)
	row.hit:SetPoint("TOPLEFT")
	row.hit:SetPoint("BOTTOMLEFT")
	row.hit:SetPoint("RIGHT", row.scopeRaid, "LEFT", -6, 0)

	row.box, row.mark = MakeCheckBox(row.hit, 13)
	row.box:SetPoint("LEFT", 4, 0)
	row.icon = row.hit:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.label = row.hit:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", row.hit, "RIGHT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetTextColor(C.text[1], C.text[2], C.text[3])
	cooldownState.customRows[index] = row
	return row
end

local function VisibleSpells()
	local out = {}
	for i = 1, #addon.DEFAULT_SPELLS do
		local spell = addon.DEFAULT_SPELLS[i]
		if MatchesQuery(spell.name, spell.label, spell.spellID) then
			out[#out + 1] = spell
		end
	end
	return out
end

local function UpdateCooldownNote()
	local note = cooldownState.note
	if not note then
		return
	end
	if addon.SpellScopeEnabled and addon.SpellScopeEnabled() then
		note:SetText("Looks for these buffs. R, D, and F turn each one on for Raid, Dungeons, or Focus.")
	else
		note:SetText("Looks for these buffs.")
	end
end

RebuildCooldownList = function()
	if not cooldownState.host then
		return
	end
	UpdateCooldownNote()
	for _, header in pairs(cooldownState.headers) do
		header:Hide()
	end
	for _, row in pairs(cooldownState.rows) do
		row:Hide()
	end
	for i = 1, #cooldownState.customRows do
		cooldownState.customRows[i]:Hide()
	end

	local grouped = {}
	for i = 1, #addon.DEFAULT_SPELLS do
		local spell = addon.DEFAULT_SPELLS[i]
		if MatchesQuery(spell.name, spell.label, spell.spellID) then
			local className = spell.class
			grouped[className] = grouped[className] or {}
			grouped[className][#grouped[className] + 1] = spell
		end
	end

	local y = 0
	local order = addon.CLASS_ORDER
	for i = 1, #order do
		local className = order[i]
		if className ~= "Custom" then
			local spells = grouped[className]
			if spells and #spells > 0 then
				local header = AcquireClassHeader(className)
				header:Show()
				header:ClearAllPoints()
				header:SetPoint("TOPLEFT", cooldownState.host, "TOPLEFT", 0, y)
				header:SetPoint("TOPRIGHT", cooldownState.host, "TOPRIGHT", 0, y)
				local r, g, b = ClassColor(className)
				header.label:SetText(className)
				header.label:SetTextColor(r, g, b)
				local collapsed = CooldownCollapsed()[className]
				SetChevronDir(header.caret, collapsed and "right" or "down")
				header.line:SetColorTexture(r, g, b, 0.35)
				y = y - 24
				if not collapsed then
					for s = 1, #spells do
						local spell = spells[s]
						local row = AcquireSpellRow(spell.spellID)
						row:Show()
						row:ClearAllPoints()
						row:SetPoint("TOPLEFT", cooldownState.host, "TOPLEFT", 0, y)
						row:SetPoint("TOPRIGHT", cooldownState.host, "TOPRIGHT", 0, y)
						row.spellID = spell.spellID
						row.icon:SetTexture(SpellIcon(spell.spellID))
						row.label:SetText(spell.label or SpellLabel(spell.spellID, spell.name))
						local on = SpellIsOn(spell)
						PaintCheck(row.box, row.mark, on)
						RefreshScopeBtns(row, spell.spellID, on)
						row.hit:SetScript("OnClick", function()
							DB().spellEnabled[spell.spellID] = not SpellIsOn(spell)
							local nowOn = SpellIsOn(spell)
							PaintCheck(row.box, row.mark, nowOn)
							RefreshScopeBtns(row, spell.spellID, nowOn)
							ApplySettings()
						end)
						y = y - 26
					end
				end
			end
		end
	end

	local list = DB().customSpells
	local hasVisible = false
	for i = 1, #list do
		if MatchesQuery(SpellLabel(list[i].spellID), list[i].spellID) then
			hasVisible = true
			break
		end
	end
	if hasVisible then
		local header = AcquireClassHeader("Custom")
		header:Show()
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", cooldownState.host, "TOPLEFT", 0, y)
		header:SetPoint("TOPRIGHT", cooldownState.host, "TOPRIGHT", 0, y)
		local r, g, b = ClassColor("Custom")
		header.label:SetText("Custom")
		header.label:SetTextColor(r, g, b)
		local collapsed = CooldownCollapsed().Custom
		SetChevronDir(header.caret, collapsed and "right" or "down")
		header.line:SetColorTexture(r, g, b, 0.35)
		y = y - 24
		if not collapsed then
			for i = 1, #list do
				local extra = list[i]
				local name = SpellLabel(extra.spellID)
				if MatchesQuery(name, extra.spellID) then
					local index = i
					local row = AcquireCustomRow(index)
					row:Show()
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", cooldownState.host, "TOPLEFT", 0, y)
					row:SetPoint("TOPRIGHT", cooldownState.host, "TOPRIGHT", 0, y)
					row.icon:SetTexture(SpellIcon(extra.spellID))
					row.label:SetText(name)
					row.spellID = extra.spellID
					local on = extra.enabled ~= false
					PaintCheck(row.box, row.mark, on)
					RefreshScopeBtns(row, extra.spellID, on)
					BindScopeBtn(row.scopeRaid, function() return extra.spellID end)
					BindScopeBtn(row.scopeParty, function() return extra.spellID end)
					BindScopeBtn(row.scopeFocus, function() return extra.spellID end)
					row.hit:SetScript("OnClick", function()
						extra.enabled = extra.enabled == false
						local nowOn = extra.enabled ~= false
						PaintCheck(row.box, row.mark, nowOn)
						RefreshScopeBtns(row, extra.spellID, nowOn)
						ApplySettings()
					end)
					row.del:SetScript("OnClick", function()
						table.remove(list, index)
						RebuildCooldownList()
						ApplySettings()
					end)
					y = y - 26
				end
			end
		end
	end

	cooldownState.host:SetHeight(math.max(40, -y + 8))
	if cooldownState.area then
		cooldownState.area:Update()
	end
end

function addon.RebuildCooldownList()
	RebuildCooldownList()
end

function addon.RefreshTrackingTab()
	RebuildCooldownList()
	for i = 1, #refreshLockouts do
		refreshLockouts[i]()
	end
	if relayoutLeft then
		relayoutLeft()
	end
end

function addon.ResetTrackingSearch()
	cooldownState.query = ""
	if cooldownState.search then
		cooldownState.search:SetText("")
	end
	if cooldownState.placeholder then
		cooldownState.placeholder:Show()
	end
	wipe(CooldownCollapsed())
end

function addon.BuildTrackingTab(parent)
	wipe(refreshLockouts)
	local leftHolder = CreateFrame("Frame", nil, parent)
	leftHolder:SetWidth(LEFT_W)
	leftHolder:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	leftHolder:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
	local leftArea = MakeScrollArea(leftHolder)
	local left = leftArea.child

	local right = MakePanel(parent)
	right:SetPoint("TOPLEFT", leftHolder, "TOPRIGHT", 10, 0)
	right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local leftStack = {}
	local HEADER_H = 34

	relayoutLeft = function()
		local y = 0
		for i = 1, #leftStack do
			local card = leftStack[i]
			if card.ApplyCollapse then
				card:ApplyCollapse()
			end
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", left, "TOPLEFT", 0, y)
			card:SetPoint("TOPRIGHT", left, "TOPRIGHT", 0, y)
			y = y - (card:GetHeight() or 0) - 10
		end
		left:SetHeight(math.max(400, -y + 8))
		leftArea:Layout()
		leftArea:Update()
	end

	local function MakeContextCard(id, title, helpText, opts)
		local card = MakePanel(left)
		local headerBtn = CreateFrame("Button", nil, card)
		headerBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
		headerBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
		headerBtn:SetHeight(HEADER_H)

		local caret = MakeChevron(headerBtn, "down")
		caret:SetPoint("LEFT", headerBtn, "LEFT", 12, 0)

		local header = MakeHeader(headerBtn, title)
		header:ClearAllPoints()
		header:SetPoint("LEFT", caret, "RIGHT", 6, 0)

		if helpText then
			local help = MakeHelp(headerBtn, helpText)
			help:SetPoint("LEFT", header, "RIGHT", 6, 0)
			help:SetFrameLevel((headerBtn:GetFrameLevel() or 1) + 2)
		end

		local status = headerBtn:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
		status:SetPoint("RIGHT", headerBtn, "RIGHT", -12, 0)
		status:SetJustifyH("RIGHT")
		status:SetWordWrap(false)
		status:Hide()

		local body = CreateFrame("Frame", nil, card)
		body:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -HEADER_H)
		body:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -HEADER_H)

		local lockables = {}
		local function hasOutput()
			if opts.getAlert and opts.getAlert() then
				return true
			end
			if opts.getGlow and opts.getGlow() then
				return true
			end
			if opts.getDuration and opts.getDuration() then
				return true
			end
			if opts.getSound and opts.getSound() then
				return true
			end
			return false
		end
		local function enableDefaultOutput()
			if opts.setGlow then
				opts.setGlow(true)
			elseif opts.setAlert then
				opts.setAlert(true)
			elseif opts.setSound then
				opts.setSound(true)
			elseif opts.setDuration then
				opts.setDuration(true)
			end
		end
		local function refreshLock()
			local on = opts.getTrack() == true
			local collapsed = TrackingCollapsed()[id] == true
			status:SetShown(collapsed)
			if not on then
				status:SetText("Off")
				status:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
			else
				local parts = { "On" }
				if opts.getAlert and opts.getAlert() then
					parts[#parts + 1] = "Alert"
				end
				if opts.getGlow and opts.getGlow() then
					parts[#parts + 1] = "Glow"
				end
				if opts.getDuration and opts.getDuration() then
					parts[#parts + 1] = "Duration"
				end
				if opts.getSound and opts.getSound() then
					parts[#parts + 1] = "Sound"
				end
				if opts.getMode and opts.getMode() == "listed" then
					parts[#parts + 1] = "Listed"
				end
				status:SetText(table.concat(parts, " / "))
				status:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
			end
			for i = 1, #lockables do
				SetOptionLocked(lockables[i], on)
			end
		end
		local durationCb, soundCb
		local refreshChecks
		local function afterOutputChange()
			if opts.getTrack() and not hasOutput() then
				opts.setTrack(false)
			end
			if refreshChecks then
				refreshChecks()
			else
				refreshLock()
			end
			if addon.RefreshAppearanceLockouts then
				addon.RefreshAppearanceLockouts()
			end
		end

		local trackCb = MakeCheckbox(body, "Track cooldowns", nil, opts.getTrack, function(v)
			opts.setTrack(v)
			if v and not hasOutput() then
				enableDefaultOutput()
			end
			if refreshChecks then
				refreshChecks()
			else
				refreshLock()
			end
			if addon.RefreshAppearanceLockouts then
				addon.RefreshAppearanceLockouts()
			end
		end)
		local alertCb = MakeCheckbox(body, "Show alert", nil, opts.getAlert, function(v)
			opts.setAlert(v)
			if addon.SyncAlertSource then
				addon.SyncAlertSource()
			end
			afterOutputChange()
		end, opts.alertHelp)
		local glowCb = MakeCheckbox(body, "Show glow", nil, opts.getGlow, function(v)
			opts.setGlow(v)
			afterOutputChange()
		end)
		local inner = Stack(body, { trackCb }, 0, 6, 12)
		local childItems = { alertCb, glowCb }
		lockables[#lockables + 1] = alertCb
		lockables[#lockables + 1] = glowCb
		if opts.getDuration then
			durationCb = MakeCheckbox(body, "Show duration", nil, opts.getDuration, function(v)
				opts.setDuration(v)
				afterOutputChange()
			end)
			childItems[#childItems + 1] = durationCb
			lockables[#lockables + 1] = durationCb
		end
		if opts.getSound then
			soundCb = MakeCheckbox(body, "Play sound", nil, opts.getSound, function(v)
				opts.setSound(v)
				afterOutputChange()
			end, opts.soundHelp)
			childItems[#childItems + 1] = soundCb
			lockables[#lockables + 1] = soundCb
		end
		refreshChecks = function()
			trackCb:Refresh()
			alertCb:Refresh()
			glowCb:Refresh()
			if durationCb then
				durationCb:Refresh()
			end
			if soundCb then
				soundCb:Refresh()
			end
			refreshLock()
		end
		inner = Stack(body, childItems, inner - 2, 6, 24)
		if opts.getMode then
			local modeRow = MakeChoiceRow(body, addon.TRACK_PLAYER_MODES, opts.getMode, function(modeId)
				opts.setMode(modeId)
				refreshLock()
				if rebuildPlayers then
					rebuildPlayers()
				end
			end)
			modeRow:ClearAllPoints()
			modeRow:SetPoint("TOPLEFT", body, "TOPLEFT", 24, inner - 6)
			modeRow:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, inner - 6)
			lockables[#lockables + 1] = modeRow
			inner = inner - 6 - (modeRow:GetHeight() or 24)
		end
		local bodyH = math.max(40, -inner + 12)
		body:SetHeight(bodyH)

		function card:ApplyCollapse()
			local collapsed = TrackingCollapsed()[id] == true
			SetChevronDir(caret, collapsed and "right" or "down")
			body:SetShown(not collapsed)
			status:SetShown(collapsed)
			if collapsed then
				card:SetHeight(HEADER_H)
			else
				card:SetHeight(HEADER_H + bodyH)
			end
		end

		headerBtn:SetScript("OnEnter", function()
			caret:SetVertexColor(C.textAccent[1], C.textAccent[2], C.textAccent[3], 1)
		end)
		headerBtn:SetScript("OnLeave", function()
			caret:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
		end)
		headerBtn:SetScript("OnClick", function()
			local collapsed = TrackingCollapsed()
			collapsed[id] = not collapsed[id]
			relayoutLeft()
			refreshLock()
		end)

		refreshLockouts[#refreshLockouts + 1] = refreshLock
		refreshLock()
		leftStack[#leftStack + 1] = card
		return card
	end

	MakeContextCard("raid", "Raid", nil, {
		getTrack = function()
			return DB().watchRaid
		end,
		setTrack = function(v)
			DB().watchRaid = v
		end,
		alertHelp = ALERT_OVERLAP_TIP,
		getAlert = function()
			return DB().alertRaid == true
		end,
		setAlert = function(v)
			DB().alertRaid = v
		end,
		getGlow = function()
			return DB().glowRaid == true
		end,
		setGlow = function(v)
			DB().glowRaid = v
		end,
		getDuration = function()
			return DB().durationRaid == true
		end,
		setDuration = function(v)
			DB().durationRaid = v and true or false
		end,
		getSound = function()
			return DB().raidSound == true
		end,
		setSound = function(v)
			DB().raidSound = v and true or false
		end,
		soundHelp = SOUND_COOLDOWN_WARNING,
		getMode = function()
			return DB().trackRaidMode == "listed" and "listed" or "all"
		end,
		setMode = function(v)
			DB().trackRaidMode = v
		end,
	})
	MakeContextCard("party", "Dungeons", nil, {
		getTrack = function()
			return DB().watchParty
		end,
		setTrack = function(v)
			DB().watchParty = v
		end,
		alertHelp = ALERT_OVERLAP_TIP,
		getAlert = function()
			return DB().alertParty == true
		end,
		setAlert = function(v)
			DB().alertParty = v
		end,
		getGlow = function()
			return DB().glowParty == true
		end,
		setGlow = function(v)
			DB().glowParty = v
		end,
		getDuration = function()
			return DB().durationParty == true
		end,
		setDuration = function(v)
			DB().durationParty = v and true or false
		end,
		getSound = function()
			return DB().partySound == true
		end,
		setSound = function(v)
			DB().partySound = v and true or false
		end,
		soundHelp = SOUND_COOLDOWN_WARNING,
		getMode = function()
			return DB().trackPartyMode == "listed" and "listed" or "all"
		end,
		setMode = function(v)
			DB().trackPartyMode = v
		end,
	})
	MakeContextCard("focus", "Focus", "While you have a friendly player focused, only they are tracked. Raid and dungeon tracking come back when you clear your focus.", {
		getTrack = function()
			return DB().watchFocus
		end,
		setTrack = function(v)
			DB().watchFocus = v
		end,
		getAlert = function()
			return DB().alertFocus == true
		end,
		setAlert = function(v)
			DB().alertFocus = v
		end,
		getGlow = function()
			return DB().glowFocus == true
		end,
		setGlow = function(v)
			DB().glowFocus = v
		end,
		getSound = function()
			return DB().focusSound == true
		end,
		setSound = function(v)
			DB().focusSound = v
		end,
		soundHelp = SOUND_COOLDOWN_WARNING,
	})

	local playersCard, playersInner = BeginCard(left, 0, "Tracked players")
	local playersHelp = MakeHelp(playersCard, "When Raid or Dungeons is set to Listed, only these people get glows and alerts - even if they aren't DPS.")
	playersHelp:SetPoint("LEFT", playersCard.header, "RIGHT", 6, 0)
	local playersNote = playersCard:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	playersNote:SetPoint("TOPLEFT", playersCard, "TOPLEFT", 12, playersInner)
	playersNote:SetPoint("RIGHT", playersCard, "RIGHT", -12, 0)
	playersNote:SetJustifyH("LEFT")
	playersNote:SetWordWrap(true)
	playersNote:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	playersInner = playersInner - 28
	local playersEdit = MakeEditBox(playersCard, 140)
	playersEdit:SetMaxLetters(48)
	playersEdit:SetPoint("TOPLEFT", playersCard, "TOPLEFT", 12, playersInner)
	local playersAdd = MakeButton(playersCard, "Add")
	playersAdd:SetWidth(70)
	playersAdd:SetPoint("TOPRIGHT", playersCard, "TOPRIGHT", -12, playersInner)
	playersEdit:SetPoint("RIGHT", playersAdd, "LEFT", -8, 0)
	playersInner = playersInner - 32
	local playersHost = CreateFrame("Frame", nil, playersCard)
	playersHost:SetPoint("TOPLEFT", playersCard, "TOPLEFT", 12, playersInner)
	playersHost:SetPoint("TOPRIGHT", playersCard, "TOPRIGHT", -12, playersInner)

	local function TrackNames()
		local db = DB()
		if type(db.trackNames) ~= "table" then
			db.trackNames = {}
		end
		return db.trackNames
	end

	rebuildPlayers = function()
		local names = TrackNames()
		local db = DB()
		local raidListed = db.trackRaidMode == "listed"
		local dungeonListed = db.trackPartyMode == "listed"
		local listed = raidListed or dungeonListed
		if listed and #names == 0 then
			local scope
			if raidListed and dungeonListed then
				scope = "Raid and Dungeons are set to Listed"
			elseif raidListed then
				scope = "Raid is set to Listed"
			else
				scope = "Dungeons is set to Listed"
			end
			playersNote:SetText(scope .. " but this list is empty.")
			playersNote:SetTextColor(C.danger[1], C.danger[2], C.danger[3])
		else
			playersNote:SetText("Add names here, then set Raid or Dungeons to Listed.")
			playersNote:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
		end
		local noteH = playersNote:GetStringHeight() or 12
		if type(noteH) ~= "number" or noteH < 12 then
			noteH = 12
		end
		local addY = -32 - noteH - 8
		playersEdit:ClearAllPoints()
		playersAdd:ClearAllPoints()
		playersAdd:SetPoint("TOPRIGHT", playersCard, "TOPRIGHT", -12, addY)
		playersEdit:SetPoint("TOPLEFT", playersCard, "TOPLEFT", 12, addY)
		playersEdit:SetPoint("RIGHT", playersAdd, "LEFT", -8, 0)
		local listY = addY - 32
		playersHost:ClearAllPoints()
		playersHost:SetPoint("TOPLEFT", playersCard, "TOPLEFT", 12, listY)
		playersHost:SetPoint("TOPRIGHT", playersCard, "TOPRIGHT", -12, listY)
		local listH = FillNameList(playersHost, names, function()
			rebuildPlayers()
			ApplySettings()
		end)
		playersCard:SetHeight(math.max(80, -listY + listH + 16))
		if listed then
			playersCard:SetAlpha(1)
		else
			playersCard:SetAlpha(0.4)
		end
		if relayoutLeft then
			relayoutLeft()
		end
	end

	local function addPlayer(text)
		if not addon.AddUniqueName or not addon.AddUniqueName(TrackNames(), text) then
			return
		end
		playersEdit:SetText("")
		rebuildPlayers()
		ApplySettings()
	end
	playersEdit.OnSubmit = addPlayer
	playersAdd:SetScript("OnClick", function()
		addPlayer(playersEdit:GetText())
	end)
	leftStack[#leftStack + 1] = playersCard
	refreshLockouts[#refreshLockouts + 1] = rebuildPlayers
	rebuildPlayers()

	local cdHeader = MakeHeader(right, "Tracked cooldowns")
	cdHeader:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -12)
	local cdNote = right:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	cdNote:SetPoint("TOPLEFT", cdHeader, "BOTTOMLEFT", 0, -4)
	cdNote:SetPoint("RIGHT", right, "RIGHT", -12, 0)
	cdNote:SetJustifyH("LEFT")
	cdNote:SetWordWrap(true)
	cdNote:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	cooldownState.note = cdNote

	local function addCustomSpell(text)
		text = strtrim(text or "")
		if not string.match(text, "^%d+$") then
			return false
		end
		local id = tonumber(text)
		if type(id) ~= "number" or id < 1 or id ~= math.floor(id) then
			return false
		end
		id = math.floor(id)
		local list = DB().customSpells
		if type(list) ~= "table" then
			list = {}
			DB().customSpells = list
		end
		for i = 1, #list do
			if list[i].spellID == id then
				return true
			end
		end
		list[#list + 1] = { spellID = id, enabled = true }
		if addon.GetSpellScope then
			addon.GetSpellScope(id)
		end
		CooldownCollapsed()["Custom"] = nil
		RebuildCooldownList()
		ApplySettings()
		return true
	end

	local customDialog
	local function HideAddCustom()
		if customDialog then
			customDialog:Hide()
		end
		if customDialog and customDialog.catcher then
			customDialog.catcher:Hide()
		end
		if customDialog and customDialog.edit then
			customDialog.edit:ClearFocus()
		end
	end

	local function OptionsHost()
		local f = parent
		while f do
			local p = f:GetParent()
			if not p or p == UIParent then
				return f
			end
			f = p
		end
		return parent
	end

	local function ShowAddCustom()
		if customDialog then
			customDialog.catcher:Show()
			customDialog:Show()
			customDialog.edit:SetText("")
			customDialog.edit:SetFocus()
			return
		end
		local host = OptionsHost()
		local catcher = CreateFrame("Button", nil, host)
		catcher:SetAllPoints()
		catcher:SetFrameStrata("DIALOG")
		catcher:SetFrameLevel((host:GetFrameLevel() or 1) + 40)
		local dim = catcher:CreateTexture(nil, "BACKGROUND")
		dim:SetAllPoints()
		dim:SetColorTexture(0, 0, 0, 0.55)
		catcher:EnableMouse(true)

		local dialog = CreateFrame("Frame", "PIHelperAddCustomBuff", host)
		dialog:SetSize(340, 168)
		dialog:SetPoint("CENTER")
		dialog:SetFrameStrata("DIALOG")
		dialog:SetFrameLevel(catcher:GetFrameLevel() + 2)
		Fill(dialog, "BACKGROUND", C.bg[1], C.bg[2], C.bg[3], 1)
		AddBorder(dialog, C.windowBorder[1], C.windowBorder[2], C.windowBorder[3])

		local title = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontLarge")
		title:SetPoint("TOPLEFT", 16, -14)
		title:SetText("Add custom buff")
		title:SetTextColor(C.gold[1], C.gold[2], C.gold[3])

		local body = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontSmall")
		body:SetPoint("TOPLEFT", 16, -42)
		body:SetPoint("TOPRIGHT", -16, -42)
		body:SetJustifyH("LEFT")
		body:SetWordWrap(true)
		body:SetText("Type the buff's spell ID. You can copy it from the in-game tooltip or from Wowhead.")
		body:SetTextColor(C.text[1], C.text[2], C.text[3])

		local idLbl = dialog:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
		idLbl:SetPoint("TOPLEFT", 16, -78)
		idLbl:SetText("Spell ID")
		idLbl:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])

		local edit = MakeEditBox(dialog, 200)
		if edit.SetNumeric then
			edit:SetNumeric(true)
		end
		edit:SetMaxLetters(10)
		edit:SetPoint("TOPLEFT", 16, -94)
		edit:SetPoint("TOPRIGHT", -16, -94)

		local function submit()
			if addCustomSpell(edit:GetText()) then
				HideAddCustom()
			end
		end
		edit.OnSubmit = submit
		edit:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			HideAddCustom()
		end)

		local cancel = MakeButton(dialog, "Cancel")
		cancel:SetWidth(80)
		cancel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 14)
		cancel:SetScript("OnClick", HideAddCustom)

		local add = MakeButton(dialog, "Add", true)
		add:SetWidth(80)
		add:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
		add:SetScript("OnClick", submit)

		catcher:SetScript("OnClick", HideAddCustom)
		dialog.catcher = catcher
		dialog.edit = edit
		customDialog = dialog
		catcher:Show()
		dialog:Show()
		edit:SetText("")
		edit:SetFocus()
	end

	local addCustom = MakeButton(right, "Add Custom")
	addCustom:SetWidth(math.max(96, (addCustom.label:GetStringWidth() or 70) + 18))
	addCustom:SetPoint("TOPRIGHT", right, "TOPRIGHT", -12, -46)
	addCustom:SetScript("OnClick", ShowAddCustom)

	local disableAll = MakeButton(right, "Disable All")
	disableAll:SetWidth(88)
	disableAll:SetPoint("RIGHT", addCustom, "LEFT", -6, 0)

	local enableAll = MakeButton(right, "Enable All")
	enableAll:SetWidth(80)
	enableAll:SetPoint("RIGHT", disableAll, "LEFT", -6, 0)

	local search = MakeEditBox(right, 180)
	search:SetHeight(24)
	search:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -48)
	search:SetPoint("RIGHT", enableAll, "LEFT", -8, 0)
	search:SetTextInsets(24, 8, 0, 0)
	local searchIcon = search:CreateTexture(nil, "OVERLAY")
	searchIcon:SetSize(12, 12)
	searchIcon:SetPoint("LEFT", 6, 0)
	searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	searchIcon:SetVertexColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], 1)
	local placeholder = search:CreateFontString(nil, "OVERLAY", "PIH_FontTiny")
	placeholder:SetPoint("LEFT", search, "LEFT", 24, 0)
	placeholder:SetPoint("RIGHT", search, "RIGHT", -8, 0)
	placeholder:SetJustifyH("LEFT")
	placeholder:SetWordWrap(false)
	placeholder:SetText("Search")
	placeholder:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
	cooldownState.search = search
	cooldownState.placeholder = placeholder

	search:SetScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		cooldownState.query = string.lower(text)
		placeholder:SetShown(text == "")
		RebuildCooldownList()
	end)

	enableAll:SetScript("OnClick", function()
		local spells = VisibleSpells()
		for i = 1, #spells do
			DB().spellEnabled[spells[i].spellID] = true
		end
		local list = DB().customSpells
		for i = 1, #list do
			if MatchesQuery(SpellLabel(list[i].spellID), list[i].spellID) then
				list[i].enabled = true
			end
		end
		RebuildCooldownList()
		ApplySettings()
	end)
	disableAll:SetScript("OnClick", function()
		local spells = VisibleSpells()
		for i = 1, #spells do
			DB().spellEnabled[spells[i].spellID] = false
		end
		local list = DB().customSpells
		for i = 1, #list do
			if MatchesQuery(SpellLabel(list[i].spellID), list[i].spellID) then
				list[i].enabled = false
			end
		end
		RebuildCooldownList()
		ApplySettings()
	end)

	local collapseAll = MakeButton(right, "Collapse All")
	collapseAll:SetWidth(96)
	collapseAll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	collapseAll:SetScript("OnClick", function()
		local collapsed = CooldownCollapsed()
		for i = 1, #addon.CLASS_ORDER do
			collapsed[addon.CLASS_ORDER[i]] = true
		end
		RebuildCooldownList()
	end)
	local expandAll = MakeButton(right, "Expand All")
	expandAll:SetWidth(88)
	expandAll:SetPoint("LEFT", collapseAll, "RIGHT", 6, 0)
	expandAll:SetScript("OnClick", function()
		wipe(CooldownCollapsed())
		RebuildCooldownList()
	end)

	local listHolder = CreateFrame("Frame", nil, right)
	listHolder:SetPoint("TOPLEFT", collapseAll, "BOTTOMLEFT", 0, -10)
	listHolder:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -12, 10)
	local area = MakeScrollArea(listHolder)
	cooldownState.area = area
	cooldownState.host = area.child
	RebuildCooldownList()
	return area
end
