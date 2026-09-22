--[[
	On-screen alert: a PI icon at a draggable anchor.

	Buff alerts: one AuraContainer per watched unit, parented to the
	anchor. The engine shows that button while a filtered CD is up.
	We only paint PI art, a name, and glow on the button. Do not hook
	it, do not read IsShown, do not Show/Hide it from Lua.

	Whisper and test alerts have no aura to watch, so those are normal
	frames we show ourselves.
]]

local ADDON_NAME, addon = ...

local anchor
local alertContainers = {}
local whisperFrame
local dragHint
local testFrame
local testAlertOn = false
local testGlowOn = false
local testGlowFrames = {}
local testDurationOn = false
local testDurationFrames = {}
local testDurationTicker
local testDurationStarted
local TEST_DURATION_SECONDS = 15
local configMode = false
local refreshingAlerts

local ALERT_GROUP = "pihelperAlert"
local Call = addon.Call

local function GetPIIcon()
	local tex = C_Spell.GetSpellTexture(addon.PI_SPELL_ID)
	if tex then
		return tex
	end
	return "Interface\\Icons\\spell_holy_powerinfusion"
end

local lastSafeNames = {}
local lastSafeClasses = {}

local CLASS_FILE_NAMES = {
	DEATHKNIGHT = "Death Knight",
	DEMONHUNTER = "Demon Hunter",
	DRUID = "Druid",
	EVOKER = "Evoker",
	HUNTER = "Hunter",
	MAGE = "Mage",
	MONK = "Monk",
	PALADIN = "Paladin",
	PRIEST = "Priest",
	ROGUE = "Rogue",
	SHAMAN = "Shaman",
	WARLOCK = "Warlock",
	WARRIOR = "Warrior",
}

local function PlainName(value)
	if type(value) ~= "string" then
		return nil
	end
	if addon.SafeString then
		return addon.SafeString(value)
	end
	if addon.IsSecret and addon.IsSecret(value) then
		return nil
	end
	return value
end

local function CacheSafeUnitName(unit)
	if type(unit) ~= "string" or unit == "" then
		return lastSafeNames[unit]
	end
	if unit == "focus" and addon.SafeUnitExists and addon.SafeUnitExists("focus") == false then
		lastSafeNames.focus = nil
		return nil
	end
	local safe = PlainName(UnitName(unit))
	if not safe then
		local fullName, fullRealm = UnitFullName(unit)
		safe = PlainName(fullName)
		fullRealm = PlainName(fullRealm)
		if safe and fullRealm and fullRealm ~= "" then
			safe = safe .. "-" .. fullRealm
		end
	end
	if safe then
		lastSafeNames[unit] = safe
	end
	return lastSafeNames[unit]
end

local function CacheSafeUnitClass(unit)
	if type(unit) ~= "string" or unit == "" then
		return lastSafeClasses[unit]
	end
	if unit == "focus" and addon.SafeUnitExists and addon.SafeUnitExists("focus") == false then
		lastSafeClasses.focus = nil
		return nil
	end
	local classFile
	local guid = addon.PlainGUID and addon.PlainGUID(UnitGUID(unit))
	if guid and UnitClassFromGUID then
		local ok, className, file = pcall(UnitClassFromGUID, guid)
		if ok then
			classFile = PlainName(file)
		end
	end
	if not classFile then
		local ok, file
		if UnitClassBase then
			ok, file = pcall(UnitClassBase, unit)
		else
			local className
			ok, className, file = pcall(UnitClass, unit)
		end
		if ok then
			classFile = PlainName(file)
		end
	end
	if classFile then
		lastSafeClasses[unit] = classFile
		if guid then
			lastSafeClasses[guid] = classFile
		end
		return classFile
	end
	if guid and lastSafeClasses[guid] then
		return lastSafeClasses[guid]
	end
	return lastSafeClasses[unit]
end

local function FindUnitByName(displayName)
	if type(displayName) ~= "string" or displayName == "" then
		return nil
	end
	local listed = addon.NameKeys and addon.NameKeys(displayName)
	if type(listed) ~= "table" or not next(listed) then
		return nil
	end
	local function check(unit)
		if addon.UnitMatchesNameSet and addon.UnitMatchesNameSet(unit, listed) then
			return unit
		end
		return nil
	end
	if check("player") then
		return "player"
	end
	if check("focus") then
		return "focus"
	end
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers()) or 0 do
			local unit = check("raid" .. i)
			if unit then
				return unit
			end
		end
	elseif IsInGroup and IsInGroup() then
		for i = 1, 4 do
			local unit = check("party" .. i)
			if unit then
				return unit
			end
		end
	end
	return nil
end

local function ClassFileRGB(classFile)
	classFile = PlainName(classFile)
	if not classFile then
		return nil
	end
	classFile = string.upper(classFile)
	if C_ClassColor and C_ClassColor.GetClassColor then
		local ok, color = pcall(C_ClassColor.GetClassColor, classFile)
		if ok and type(color) == "table" then
			local r, g, b
			local gotRGB
			if color.GetRGB then
				gotRGB, r, g, b = pcall(color.GetRGB, color)
			end
			if (not gotRGB or type(r) ~= "number") and type(color.r) == "number" then
				r, g, b = color.r, color.g, color.b
			end
			if type(r) == "number" and type(g) == "number" and type(b) == "number" then
				if addon.IsSecret and (addon.IsSecret(r) or addon.IsSecret(g) or addon.IsSecret(b)) then
					r = nil
				end
				if r then
					return r, g, b
				end
			end
		end
	end
	local named = CLASS_FILE_NAMES[classFile]
	local c = named and addon.CLASS_COLORS and addon.CLASS_COLORS[named]
	if c then
		return c[1], c[2], c[3]
	end
	return nil
end

local function ApplyNameColor(fs, unit, name)
	if not fs then
		return
	end
	local t = addon.C.text
	local r, g, b, a = t[1], t[2], t[3], 1
	local db = addon.db
	if db and db.alertClassColor then
		local classFile = CacheSafeUnitClass(unit)
		if not classFile and name then
			classFile = CacheSafeUnitClass(FindUnitByName(name))
		end
		local cr, cg, cb = ClassFileRGB(classFile)
		if cr then
			r, g, b = cr, cg, cb
		end
	end
	pcall(fs.SetTextColor, fs, r, g, b, a)
end

-- Glow overlays sit on the icon, so the name lives on a raised sibling.
local function RaiseName(frame)
	local host = frame and frame.nameHost
	if not host or not host.SetFrameLevel then
		return
	end
	local level = 1
	local function consider(f)
		if not f or not f.GetFrameLevel then
			return
		end
		local ok, value = pcall(f.GetFrameLevel, f)
		if not ok or type(value) ~= "number" then
			return
		end
		if addon.IsSecret and addon.IsSecret(value) then
			return
		end
		if value > level then
			level = value
		end
	end
	consider(frame)
	consider(frame.iconHost)
	local glowParent = frame.iconHost or frame
	consider(glowParent and glowParent.PIHelperGlow)
	consider(glowParent and glowParent.PIHelperStarburst)
	pcall(host.SetFrameLevel, host, level + 5)
end

local function AlertFrameUsable(frame)
	return frame and not (addon.FrameIsForbidden and addon.FrameIsForbidden(frame))
end

local function EnsureNameLayer(frame)
	if not AlertFrameUsable(frame) then
		return
	end
	if not frame.nameHost then
		local ok, host = pcall(CreateFrame, "Frame", nil, frame, "DisableUntrustedLayoutScriptsTemplate")
		if not ok or not host then
			ok, host = pcall(CreateFrame, "Frame", nil, frame)
		end
		if ok and host then
			pcall(host.EnableMouse, host, false)
			if host.SetClipsChildren then
				pcall(host.SetClipsChildren, host, false)
			end
			frame.nameHost = host
		end
	end
	local parent = frame.nameHost or frame
	if frame.name and not frame._pihNameRaised then
		pcall(frame.name.SetText, frame.name, "")
		frame.name = nil
	end
	if not frame.name then
		local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY")
		if ok and fs then
			frame.name = fs
			pcall(fs.SetTextColor, fs, addon.C.text[1], addon.C.text[2], addon.C.text[3], 1)
			frame._pihNameRaised = true
		end
	end
end

local function LayoutNameplate(frame, name, unit)
	if not AlertFrameUsable(frame) then
		return
	end
	local iconTex = frame.pihIcon or frame.icon
	if not iconTex then
		return
	end
	pcall(EnsureNameLayer, frame)
	local db = addon.db
	local size = db and db.alertIconSize or 64
	local textSize = db and db.alertTextSize or 16
	local layout = db and db.alertLayout or "overlay"
	local gap = 10
	local textWidth = math.max(80, textSize * 10)
	-- Keep the icon on the drag point. Side names hang off a larger nameHost
	-- so leftover FontString width cannot stretch the label after a swap.
	pcall(frame.SetSize, frame, size, size)
	if frame.SetClipsChildren then
		pcall(frame.SetClipsChildren, frame, false)
	end
	pcall(iconTex.SetTexture, iconTex, GetPIIcon())
	pcall(iconTex.SetTexCoord, iconTex, 0.08, 0.92, 0.08, 0.92)
	local icon = frame.iconHost or iconTex
	if frame.iconHost then
		pcall(icon.ClearAllPoints, icon)
		pcall(icon.SetSize, icon, size, size)
		pcall(icon.SetPoint, icon, "CENTER", frame, "CENTER", 0, 0)
		pcall(iconTex.SetAllPoints, iconTex, frame.iconHost)
	else
		pcall(iconTex.SetAllPoints, iconTex, frame)
	end
	if frame.nameHost then
		local host = frame.nameHost
		pcall(host.ClearAllPoints, host)
		if host.SetClipsChildren then
			pcall(host.SetClipsChildren, host, false)
		end
		if layout == "right" then
			pcall(host.SetPoint, host, "LEFT", icon, "LEFT", 0, 0)
			pcall(host.SetSize, host, size + gap + textWidth, size)
		elseif layout == "left" then
			pcall(host.SetPoint, host, "RIGHT", icon, "RIGHT", 0, 0)
			pcall(host.SetSize, host, size + gap + textWidth, size)
		else
			pcall(host.SetPoint, host, "CENTER", icon, "CENTER", 0, 0)
			pcall(host.SetSize, host, size, size)
		end
		pcall(RaiseName, frame)
	end
	local fs = frame.name
	if not fs then
		return
	end
	if layout == "none" then
		pcall(fs.ClearAllPoints, fs)
		pcall(fs.SetText, fs, "")
		pcall(fs.Hide, fs)
		return
	end
	pcall(fs.Show, fs)
	pcall(fs.ClearAllPoints, fs)
	pcall(fs.SetWidth, fs, 0)
	pcall(fs.SetHeight, fs, 0)
	pcall(fs.SetWordWrap, fs, false)
	if fs.SetMaxLines then
		pcall(fs.SetMaxLines, fs, 1)
	end
	pcall(fs.SetFont, fs, addon.FONT, textSize, "OUTLINE")
	pcall(fs.SetJustifyV, fs, "MIDDLE")
	if layout == "right" then
		pcall(fs.SetJustifyH, fs, "LEFT")
		pcall(fs.SetPoint, fs, "LEFT", icon, "RIGHT", gap, 0)
	elseif layout == "left" then
		pcall(fs.SetJustifyH, fs, "RIGHT")
		pcall(fs.SetPoint, fs, "RIGHT", icon, "LEFT", -gap, 0)
	else
		pcall(fs.SetWordWrap, fs, true)
		if fs.SetMaxLines then
			pcall(fs.SetMaxLines, fs, 2)
		end
		pcall(fs.SetWidth, fs, math.max(8, size - 4))
		pcall(fs.SetJustifyH, fs, "CENTER")
		pcall(fs.SetPoint, fs, "CENTER", icon, "CENTER", 0, 0)
	end
	pcall(fs.SetText, fs, name or "")
	pcall(ApplyNameColor, fs, unit, name)
	pcall(RaiseName, frame)
end

local function PaintAlert(frame, name, unit)
	pcall(LayoutNameplate, frame, name, unit)
	pcall(addon.StartAlertGlow, frame)
	pcall(RaiseName, frame)
end

local function CanDragAlert()
	return configMode and addon.db and not addon.db.alertLocked
end

local function UpdateDragHint()
	if not anchor then
		return
	end
	if not dragHint then
		dragHint = CreateFrame("Frame", nil, anchor)
		dragHint:SetAllPoints()
		dragHint:EnableMouse(false)
		local bg = dragHint:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(234 / 255, 162 / 255, 33 / 255, 0.18)
		dragHint.label = dragHint:CreateFontString(nil, "OVERLAY")
		dragHint.label:SetFont(addon.FONT, 12, "OUTLINE")
		dragHint.label:SetPoint("CENTER")
		dragHint.label:SetText("Drag on-screen alert")
		dragHint.label:SetTextColor(addon.C.text[1], addon.C.text[2], addon.C.text[3], 1)
	end
	local dragging = CanDragAlert()
	dragHint:SetShown(dragging)
	anchor:SetMovable(dragging)
	anchor:EnableMouse(dragging)
end

local function LayoutAnchor()
	local db = addon.db
	if not anchor or not db then
		return
	end
	local size = db.alertIconSize or 64
	if db.alertLayout == "right" or db.alertLayout == "left" then
		anchor:SetSize(size + 180, size)
	else
		anchor:SetSize(size, size)
	end
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", UIParent, "CENTER", db.alertX or 0, db.alertY or 180)
	UpdateDragHint()
end

local function CreateAnchor()
	if anchor then
		return anchor
	end
	anchor = CreateFrame("Frame", "PIHelperAlertAnchor", UIParent)
	anchor:SetClampedToScreen(true)
	anchor:SetFrameStrata("HIGH")
	anchor:SetFrameLevel(200)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self)
		if CanDragAlert() and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local db = addon.db
		if not db then
			return
		end
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		if cx and ux then
			db.alertX = (cx - ux) * scale
			db.alertY = (cy - uy) * scale
		end
		LayoutAnchor()
	end)
	LayoutAnchor()
	return anchor
end

function addon.SetAlertConfigMode(enabled)
	configMode = enabled and true or false
	if configMode then
		CreateAnchor()
		LayoutAnchor()
	end
	UpdateDragHint()
end

local function MakeNameplate(name, level)
	local frame = CreateFrame("Frame", name, CreateAnchor())
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(level)
	frame:EnableMouse(false)
	frame.iconHost = CreateFrame("Frame", nil, frame)
	frame.iconHost:EnableMouse(false)
	frame.icon = frame.iconHost:CreateTexture(nil, "ARTWORK")
	frame.icon:SetAllPoints()
	if frame.SetClipsChildren then
		pcall(frame.SetClipsChildren, frame, false)
	end
	frame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	frame:Hide()
	return frame
end

local function UnitTokenUsable(unit)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	local exists = UnitExists(unit)
	if addon.IsSecret and addon.IsSecret(exists) then
		return true
	end
	return exists ~= false
end

local function MatchesFocus(unit)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	if addon.UnitIsFocus and addon.UnitIsFocus(unit) then
		return true
	end
	return addon.SafeUnitIsUnit and addon.SafeUnitIsUnit(unit, "focus")
end

-- AuraContainer does not reliably track the "focus" token. Prefer raid/party.
local function ResolveFocusUnit()
	if addon.SafeUnitExists and addon.SafeUnitExists("focus") == false then
		return nil
	end
	if MatchesFocus("player") then
		return "player"
	end
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers()) or 0 do
			local unit = "raid" .. i
			if MatchesFocus(unit) then
				return unit
			end
		end
	else
		for i = 1, 4 do
			local unit = "party" .. i
			if MatchesFocus(unit) then
				return unit
			end
		end
	end
	if addon.HasFriendlyPlayerFocus and addon.HasFriendlyPlayerFocus() then
		return "focus"
	end
	return nil
end

local function CollectAlertSpecs()
	local db = addon.db
	local specs = {}
	if not db then
		return specs
	end
	if addon.IsAlertsAllowed and not addon.IsAlertsAllowed() then
		return specs
	end
	if addon.HasAuraSpellFilters and not addon.HasAuraSpellFilters() then
		return specs
	end
	local wantFocus = addon.AlertShowsFocus and addon.AlertShowsFocus()
	local wantTracked = addon.AlertShowsTracked and addon.AlertShowsTracked()
	local wantSelf = addon.AlertShowsSelf and addon.AlertShowsSelf()
	local exclusive = addon.HasExclusiveGroupFocus and addon.HasExclusiveGroupFocus()
	local focusUnit = ResolveFocusUnit()
	local function add(key, unit, kind)
		if not UnitTokenUsable(unit) then
			return
		end
		if not wantSelf and addon.IsPlayerUnitToken and addon.IsPlayerUnitToken(unit) then
			return
		end
		specs[key] = { unit = unit, kind = kind }
	end
	if focusUnit and wantFocus then
		add("focus", focusUnit, "focus")
	end
	if exclusive then
		if wantSelf then
			add("player", "player", "all")
		end
		return specs
	end
	if wantSelf then
		add("player", "player", "all")
	end
	if not wantTracked then
		return specs
	end
	local function addTracked(unit, kind)
		if specs.focus and (unit == focusUnit or MatchesFocus(unit)) then
			return
		end
		if addon.ShouldWatchContentUnit and addon.ShouldWatchContentUnit(unit) then
			add(unit, unit, kind)
		end
	end
	local content = addon.WatchContentKind and addon.WatchContentKind()
	if content == "raid" then
		if addon.ContextIsWatching and addon.ContextIsWatching("raid") then
			for i = 1, (GetNumGroupMembers and GetNumGroupMembers()) or 0 do
				addTracked("raid" .. i, "raid")
			end
		end
		return specs
	end
	if content == "party" and addon.ContextIsWatching and addon.ContextIsWatching("party") then
		if IsInRaid and IsInRaid() then
			for i = 1, (GetNumGroupMembers and GetNumGroupMembers()) or 0 do
				addTracked("raid" .. i, "raid")
			end
		else
			for i = 1, 4 do
				addTracked("party" .. i, "party")
			end
		end
	end
	return specs
end

local function AlertKeyStillPossible(key)
	if key == "focus" or key == "player" then
		return true
	end
	local raidIndex = type(key) == "string" and key:match("^raid(%d+)$")
	if raidIndex then
		local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
		return tonumber(raidIndex) <= n
	end
	local partyIndex = type(key) == "string" and key:match("^party(%d+)$")
	if partyIndex then
		if IsInRaid and IsInRaid() then
			return false
		end
		return tonumber(partyIndex) <= 4 and IsInGroup and IsInGroup()
	end
	return false
end

-- Icon and name are painted once. Glow lives on a child holder so Proc/None
-- can update later without hooking the AuraButton.
local function PaintAlertAuraGlow(button)
	if not button or not addon.DecorateAuraGlow then
		return
	end
	local size = addon.db and addon.db.alertIconSize or 64
	pcall(addon.DecorateAuraGlow, button, { width = size, height = size, alert = true })
end

local function ApplyAlertDuration(button)
	if addon.ApplyDurationText then
		pcall(addon.ApplyDurationText, button, button, true)
	end
end

local function InitAlertButton(button, container)
	if not AlertFrameUsable(button) then
		return
	end
	if container then
		container.pihSlotButton = button
	end
	if button.pihDecorated then
		if not button.pihIcon and button.icon then
			button.pihIcon = button.icon
		end
		PaintAlertAuraGlow(button)
		ApplyAlertDuration(button)
		pcall(EnsureNameLayer, button)
		if container then
			container.pihName = button.name
		end
		return
	end
	button.pihDecorated = true
	local size = addon.db and addon.db.alertIconSize or 64
	pcall(button.SetSize, button, size, size)
	local ok, pi = pcall(button.CreateTexture, button, nil, "OVERLAY")
	if ok and pi then
		button.pihIcon = pi
		pcall(pi.SetAllPoints, pi, button)
		pcall(pi.SetTexture, pi, GetPIIcon())
		pcall(pi.SetTexCoord, pi, 0.08, 0.92, 0.08, 0.92)
	end
	pcall(button.EnableMouse, button, false)
	if button.SetMouseClickEnabled then
		pcall(button.SetMouseClickEnabled, button, false)
	end
	if button.SetMouseMotionEnabled then
		pcall(button.SetMouseMotionEnabled, button, false)
	end
	if button.SetClipsChildren then
		pcall(button.SetClipsChildren, button, false)
	end
	pcall(EnsureNameLayer, button)
	if container then
		container.pihName = button.name
	end
	PaintAlertAuraGlow(button)
	ApplyAlertDuration(button)
	pcall(LayoutNameplate, button, container and container.pihPendingName, container and container.pihUnit)
end

local function StopAlertContainers()
	for _, container in pairs(alertContainers) do
		Call(container, "SetEnabled", false)
	end
end

local function EnsureAlertContainer(key, kind, name, unit)
	local existing = alertContainers[key]
	if existing then
		existing.pihPendingName = name
		existing.pihUnit = unit
		return existing
	end
	if addon.EnsureAuraContainerLoaded then
		addon.EnsureAuraContainerLoaded()
	end
	local host = CreateAnchor()
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not container then
		addon.Debug("Alert AuraContainer create failed", key, ok and "nil" or container)
		return nil
	end
	container:ClearAllPoints()
	container:SetPoint("CENTER", host, "CENTER")
	container:SetSize(1, 1)
	pcall(container.EnableMouse, container, false)
	local okLevel, raw = pcall(host.GetFrameLevel, host)
	local level = addon.SafeNumber(okLevel and raw, 1)
	pcall(container.SetFrameLevel, container, level + 1)
	container.pihPendingName = name
	container.pihUnit = unit
	local size = addon.db and addon.db.alertIconSize or 64
	local filter = AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Helpful or "HELPFUL"
	local opts = {
		maxFrameCount = 1,
		initializeFrame = function(button)
			InitAlertButton(button, container)
		end,
		candidateFilters = addon.GetAuraCandidateFilters(kind or "all"),
		layout = { elementWidth = size, elementHeight = size },
	}
	local added, err
	if container.AddAuraGroup then
		added, err = pcall(container.AddAuraGroup, container, ALERT_GROUP, filter, opts)
	end
	if not added and container.AddAuraSlot then
		local slotOk, slot = pcall(container.AddAuraSlot, container, ALERT_GROUP, filter, opts)
		added = slotOk
		err = slot
		if slotOk and type(slot) == "table" and slot.SetSize then
			InitAlertButton(slot, container)
		end
	end
	if not added then
		addon.Debug("Alert aura group failed", key, err)
		return nil
	end
	pcall(container.SetEnabled, container, false)
	alertContainers[key] = container
	return container
end

local function EnsureWhisperFrame()
	if not whisperFrame then
		whisperFrame = MakeNameplate("PIHelperWhisperAlert", 210)
	end
	return whisperFrame
end

function addon.ShowWhisperAlert(name)
	local db = addon.db
	if not db then
		return
	end
	if addon.AlertShowsWhisper and not addon.AlertShowsWhisper() then
		return
	end
	if not addon.IsAlertsAllowed() then
		return
	end
	CreateAnchor()
	LayoutAnchor()
	local frame = EnsureWhisperFrame()
	PaintAlert(frame, name, FindUnitByName(name))
	frame:Show()
end

function addon.HideWhisperAlert()
	if whisperFrame then
		addon.StopAlertGlow(whisperFrame)
		whisperFrame:Hide()
	end
end

function addon.RefreshAlerts()
	if refreshingAlerts then
		return
	end
	refreshingAlerts = true
	pcall(CacheSafeUnitName, "player")
	pcall(CacheSafeUnitName, "focus")
	pcall(CacheSafeUnitClass, "player")
	pcall(CacheSafeUnitClass, "focus")
	local db = addon.db
	if not addon.IsActive or not addon.IsActive() or not db then
		StopAlertContainers()
		addon.HideWhisperAlert()
		if configMode then
			CreateAnchor()
			LayoutAnchor()
		end
		refreshingAlerts = false
		return
	end
	CreateAnchor()
	LayoutAnchor()
	local wanted = CollectAlertSpecs()
	local n = 0
	for _ in pairs(wanted) do
		n = n + 1
	end
	addon.Debug("alerts", n)
	for key, container in pairs(alertContainers) do
		if not wanted[key] then
			Call(container, "SetEnabled", false)
			Call(container, "SetUnit", nil)
			if not InCombatLockdown() and not AlertKeyStillPossible(key) then
				pcall(container.Hide, container)
				pcall(container.SetParent, container, nil)
				alertContainers[key] = nil
			end
		end
	end
	for key, spec in pairs(wanted) do
		pcall(CacheSafeUnitName, spec.unit)
		pcall(CacheSafeUnitClass, spec.unit)
		local name
		local okName, result = pcall(CacheSafeUnitName, spec.unit)
		if okName then
			name = result
		end
		local container = EnsureAlertContainer(key, spec.kind, name, spec.unit)
		if container then
			-- Paint before SetUnit. Once the engine binds a secret aura, the
			-- AuraButton is forbidden and tainted layout calls error.
			local button = container.pihSlotButton
			if button then
				pcall(LayoutNameplate, button, name, spec.unit)
			else
				local fs = container.pihName
				if fs then
					pcall(fs.SetText, fs, name or "")
					pcall(ApplyNameColor, fs, spec.unit, name)
				end
			end
			local filters = addon.GetAuraCandidateFilters(spec.kind)
			Call(container, "SetAuraGroupCandidateFilters", ALERT_GROUP, filters)
			Call(container, "SetAuraSlotCandidateFilters", ALERT_GROUP, filters)
			Call(container, "SetEnabled", true)
			Call(container, "SetUnit", spec.unit)
			if container.UpdateAllAuras then
				pcall(container.UpdateAllAuras, container)
			end
			ApplyAlertDuration(container.pihSlotButton)
		end
	end
	if not addon.IsAlertsAllowed() then
		addon.HideWhisperAlert()
	elseif addon.AlertShowsWhisper and not addon.AlertShowsWhisper() then
		addon.HideWhisperAlert()
	end
	refreshingAlerts = false
end

function addon.RefreshAlertGlows()
	for _, container in pairs(alertContainers) do
		PaintAlertAuraGlow(container.pihSlotButton)
		ApplyAlertDuration(container.pihSlotButton)
	end
end

local function TestDurationUsesAlert()
	return testDurationOn and addon.DurationShowsOnAlert and addon.DurationShowsOnAlert()
end

local function HideTestAlertFrame()
	if testFrame then
		addon.StopAlertGlow(testFrame)
		testFrame:Hide()
	end
end

local function PaintTestAlertFrame()
	CreateAnchor()
	LayoutAnchor()
	if not testFrame then
		testFrame = MakeNameplate("PIHelperTestAlert", 220)
		testFrame:SetFrameStrata("DIALOG")
	end
	local name = "Player"
	local ok, result = pcall(CacheSafeUnitName, "player")
	if ok and result then
		name = result
	end
	PaintAlert(testFrame, name, "player")
	testFrame:ClearAllPoints()
	testFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	testFrame:Show()
end

function addon.HideTestAlert()
	testAlertOn = false
	if not TestDurationUsesAlert() then
		HideTestAlertFrame()
	end
end

local function ShowTestAlert()
	PaintTestAlertFrame()
	testAlertOn = true
end

function addon.IsTestAlertOn()
	return testAlertOn
end

function addon.ToggleTestAlert()
	if testAlertOn then
		addon.HideTestAlert()
	else
		ShowTestAlert()
	end
	return testAlertOn
end

local function CollectPlayerGroupFrames()
	local frames = {}
	local function add(frame)
		if not frame then
			return
		end
		if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(frame) then
			return
		end
		frames[#frames + 1] = frame
	end
	if addon.ForEachPlayerGroupFrame then
		addon.ForEachPlayerGroupFrame(add)
	end
	if #frames == 0 then
		add(addon.FindUnitFrame and addon.FindUnitFrame("player"))
	end
	return frames
end

function addon.HideTestGlow()
	for i = 1, #testGlowFrames do
		local frame = testGlowFrames[i]
		addon.StopFrameGlow(frame)
		if addon.RestoreTrackedGlow then
			addon.RestoreTrackedGlow(frame)
		end
	end
	wipe(testGlowFrames)
	testGlowOn = false
end

local function ShowTestGlow()
	local frames = CollectPlayerGroupFrames()
	if #frames == 0 then
		print("|cffeaa221PI Helper:|r no raid or party frame found for you. Open raid/party frames, then try again.")
		return false
	end
	addon.HideTestGlow()
	for i = 1, #frames do
		testGlowFrames[i] = frames[i]
		addon.StopFrameGlow(frames[i])
		addon.StartFrameGlow(frames[i], { countdownSeconds = 15, countdownRepeat = true })
	end
	testGlowOn = true
	return true
end

function addon.IsTestGlowOn()
	return testGlowOn
end

function addon.ToggleTestGlow()
	if testGlowOn then
		addon.HideTestGlow()
	else
		ShowTestGlow()
	end
	return testGlowOn
end

local function TestDurationShownSeconds()
	local started = testDurationStarted or GetTime()
	local elapsed = (GetTime() - started) % TEST_DURATION_SECONDS
	local left = TEST_DURATION_SECONDS - elapsed
	if left <= 0 or left > TEST_DURATION_SECONDS then
		left = TEST_DURATION_SECONDS
	end
	local shown = math.ceil(left - 0.0001)
	if shown < 1 then
		shown = TEST_DURATION_SECONDS
	end
	if shown > TEST_DURATION_SECONDS then
		shown = TEST_DURATION_SECONDS
	end
	return shown
end

local function LayoutTestDurationHost(host, frame)
	local strata = "HIGH"
	if frame and frame.iconHost then
		strata = "DIALOG"
	end
	pcall(host.SetFrameStrata, host, strata)
	local level = 20
	if frame and frame.GetFrameLevel then
		local ok, value = pcall(frame.GetFrameLevel, frame)
		if ok and type(value) == "number" then
			level = value + 20
		end
	end
	pcall(host.SetFrameLevel, host, level)
	pcall(host.ClearAllPoints, host)
	local cover = (frame and frame.iconHost) or frame
	if not pcall(host.SetAllPoints, host, cover) then
		pcall(host.SetPoint, host, "TOPLEFT", cover, "TOPLEFT")
		pcall(host.SetPoint, host, "BOTTOMRIGHT", cover, "BOTTOMRIGHT")
	end
end

local function EnsureTestDurationHost(frame)
	if not frame or (addon.FrameIsForbidden and addon.FrameIsForbidden(frame)) then
		return nil
	end
	local host = frame.PIHelperTestDurationHost
	if not host then
		local ok
		ok, host = pcall(CreateFrame, "Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
		if not ok or not host then
			ok, host = pcall(CreateFrame, "Frame", nil, UIParent)
		end
		if not ok or not host then
			return nil
		end
		host:EnableMouse(false)
		if host.SetClipsChildren then
			pcall(host.SetClipsChildren, host, false)
		end
		local fs = host:CreateFontString(nil, "OVERLAY")
		host.fs = fs
		frame.PIHelperTestDurationHost = host
		if not frame.PIHelperTestDurationHooked then
			frame.PIHelperTestDurationHooked = true
			pcall(frame.HookScript, frame, "OnHide", function(self)
				local durationHost = self.PIHelperTestDurationHost
				if durationHost then
					durationHost:Hide()
				end
			end)
			pcall(frame.HookScript, frame, "OnShow", function(self)
				local durationHost = self.PIHelperTestDurationHost
				if durationHost and durationHost.pihWanted then
					LayoutTestDurationHost(durationHost, self)
					durationHost:Show()
				end
			end)
		end
	end
	LayoutTestDurationHost(host, frame)
	host.pihWanted = true
	pcall(host.Show, host)
	return host
end

local function PaintTestDurationHost(host)
	if not host or not host.fs then
		return
	end
	local fs = host.fs
	local point, _, x, y = addon.GetDurationAnchorSpec()
	pcall(fs.ClearAllPoints, fs)
	pcall(fs.SetPoint, fs, point, host, point, x, y)
	if addon.StyleDurationFontString then
		addon.StyleDurationFontString(fs, addon.db)
	end
	local text = "15"
	if addon.FormatDurationSeconds then
		text = addon.FormatDurationSeconds(TestDurationShownSeconds())
	else
		text = tostring(TestDurationShownSeconds())
	end
	pcall(fs.SetText, fs, text)
	pcall(fs.Show, fs)
end

local function StopTestDurationTicker()
	if testDurationTicker then
		testDurationTicker:Cancel()
		testDurationTicker = nil
	end
end

local function HideTestDurationHost(frame)
	local host = frame and frame.PIHelperTestDurationHost
	if host then
		host.pihWanted = nil
		if host.fs then
			pcall(host.fs.SetText, host.fs, "")
		end
		host:Hide()
	end
end

function addon.HideTestDuration()
	StopTestDurationTicker()
	for i = 1, #testDurationFrames do
		HideTestDurationHost(testDurationFrames[i])
	end
	wipe(testDurationFrames)
	testDurationOn = false
	testDurationStarted = nil
	if not testAlertOn then
		HideTestAlertFrame()
	end
end

local function ShowTestDuration(keepTimer)
	local wantFrame = not addon.DurationShowsOnFrame or addon.DurationShowsOnFrame()
	local wantAlert = addon.DurationShowsOnAlert and addon.DurationShowsOnAlert()
	local frames = {}
	if wantFrame then
		frames = CollectPlayerGroupFrames()
	end
	if wantAlert then
		PaintTestAlertFrame()
	end
	if #frames == 0 and not wantAlert then
		print("|cffeaa221PI Helper:|r no raid or party frame found for you. Open raid/party frames, then try again.")
		return false
	end
	if not keepTimer or not testDurationStarted then
		testDurationStarted = GetTime()
	end
	local wanted = {}
	for i = 1, #frames do
		wanted[frames[i]] = true
	end
	if wantAlert and testFrame then
		wanted[testFrame] = true
	end
	for i = 1, #testDurationFrames do
		local old = testDurationFrames[i]
		if not wanted[old] then
			HideTestDurationHost(old)
		end
	end
	wipe(testDurationFrames)
	for i = 1, #frames do
		local frame = frames[i]
		testDurationFrames[#testDurationFrames + 1] = frame
		local host = EnsureTestDurationHost(frame)
		if host then
			PaintTestDurationHost(host)
		end
	end
	if wantAlert and testFrame then
		testDurationFrames[#testDurationFrames + 1] = testFrame
		local host = EnsureTestDurationHost(testFrame)
		if host then
			PaintTestDurationHost(host)
		end
	elseif testFrame and not testAlertOn then
		HideTestAlertFrame()
	end
	testDurationOn = true
	if not testDurationTicker then
		testDurationTicker = C_Timer.NewTicker(0.1, function()
			if not testDurationOn then
				return
			end
			for i = 1, #testDurationFrames do
				local frame = testDurationFrames[i]
				local host = frame and frame.PIHelperTestDurationHost
				if host and host.fs then
					local text = addon.FormatDurationSeconds and addon.FormatDurationSeconds(TestDurationShownSeconds()) or tostring(TestDurationShownSeconds())
					pcall(host.fs.SetText, host.fs, text)
				end
			end
		end)
	end
	return true
end

function addon.IsTestDurationOn()
	return testDurationOn
end

function addon.ToggleTestDuration()
	if testDurationOn then
		addon.HideTestDuration()
	else
		ShowTestDuration(false)
	end
	return testDurationOn
end

function addon.RefreshTestPreviews()
	if testAlertOn then
		ShowTestAlert()
	end
	if testGlowOn then
		ShowTestGlow()
	end
	if testDurationOn then
		ShowTestDuration(true)
	end
end

addon.On("LOGIN", addon.RefreshAlerts)
addon.On("ACTIVATE", addon.RefreshAlerts)
addon.On("DEACTIVATE", function()
	StopAlertContainers()
	addon.HideWhisperAlert()
	addon.HideTestAlert()
	addon.HideTestGlow()
	if addon.HideTestDuration then
		addon.HideTestDuration()
	end
end)
addon.On("ROSTER", addon.RefreshAlerts)
addon.On("FOCUS", addon.RefreshAlerts)
addon.On("TRACKERS_REBUILT", addon.RefreshAlerts)
addon.On("POLICY", addon.RefreshAlerts)
addon.On("PI_CAST", function()
	StopAlertContainers()
	addon.HideWhisperAlert()
end)

addon.LayoutAlertAnchor = LayoutAnchor
