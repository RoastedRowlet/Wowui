--[[
	One AuraContainer per DPS raid/party cell, filtered to tracked spell IDs.

	The engine shows the AuraButton while a matching buff is up. That button
	is the glow. SetEnabled turns it off after PI (if onlyWhenPIReady) and
	for everyone except a group focus when Track Focus is on.

	Use AddAuraSlot (one button, we anchor it to the cell). Do not hook
	AuraButton scripts. Do not add the same slot key twice. Duration text
	is a FontString on that same AuraButton, or on the on-screen alert
	AuraButton, depending on durationHost. SetDurationText lets the
	engine drive the countdown. Do not read aura remaining time.
]]

local ADDON_NAME, addon = ...

local GROUP_KEY = addon.GROUP_KEY or "pihelper"

local roleCache = {}
local containers = setmetatable({}, { __mode = "k" })
local attachLateGen = 0
local hooked
local FrameIsForbidden = addon.FrameIsForbidden

local helpfulFilter

local function AuraFilterString()
	if helpfulFilter then
		return helpfulFilter
	end
	if AuraUtil and AuraUtil.AuraFilters and AuraUtil.AuraFilters.Helpful then
		helpfulFilter = AuraUtil.AuraFilters.Helpful
	else
		helpfulFilter = "HELPFUL"
	end
	return helpfulFilter
end

local function UnitKind(unit)
	if type(unit) ~= "string" then
		return nil
	end
	if unit == "player" then
		if IsInRaid() then
			return "raid"
		end
		return "party"
	end
	if unit:find("^raid") then
		return "raid"
	end
	if unit:find("^party") then
		return "party"
	end
	return nil
end

local function IsPlayerUnit(unit)
	if addon.IsPlayerUnitToken then
		return addon.IsPlayerUnitToken(unit)
	end
	return unit == "player"
end

local function FrameUnit(frame)
	if addon.GetFrameUnit then
		return addon.GetFrameUnit(frame)
	end
	return frame and (frame.displayedUnit or frame.unit)
end

local function UnitKey(unit)
	if type(unit) ~= "string" or unit == "" then
		return nil
	end
	if addon.PlainGUID then
		return addon.PlainGUID(UnitGUID(unit))
	end
	local guid = UnitGUID(unit)
	if type(guid) ~= "string" or (addon.IsSecret and addon.IsSecret(guid)) then
		return nil
	end
	return guid
end

-- Assigned group role. Readable for party/raid members even in M+/encounters;
-- secret only when the unit identity is secret (not in the group). Cache the
-- last plain string so a secret blip does not drop a known tank/healer.
local function ReadAssignedRole(unit)
	if type(unit) ~= "string" or unit == "" then
		return nil
	end
	local role = addon.SafeString and addon.SafeString(UnitGroupRolesAssigned(unit))
	if not role or role == "" or role == "NONE" then
		return nil
	end
	return role
end

local function PruneRoleCache()
	local keep = {}
	local function mark(unit)
		local guid = UnitKey(unit)
		if guid then
			keep[guid] = true
		end
	end
	mark("player")
	mark("focus")
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers()) or 0 do
			mark("raid" .. i)
		end
	elseif IsInGroup and IsInGroup() then
		for i = 1, 4 do
			mark("party" .. i)
		end
	end
	for guid in pairs(roleCache) do
		if not keep[guid] then
			roleCache[guid] = nil
		end
	end
end

local function CacheRole(unit)
	local guid = UnitKey(unit)
	local role = ReadAssignedRole(unit)
	if role and guid then
		roleCache[guid] = role
	end
	return role
end

local function IsDPSUnit(unit)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	if addon.SafeUnitExists and addon.SafeUnitExists(unit) == false then
		return false
	end
	local role = CacheRole(unit)
	if not role then
		local guid = UnitKey(unit)
		role = guid and roleCache[guid]
	end
	return role ~= "TANK" and role ~= "HEALER"
end

function addon.EnsureAuraContainerLoaded()
	if C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		return true
	end
	pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	return C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
end

local function ExclusiveFocus()
	return addon.ContextIsWatching and addon.ContextIsWatching("focus") and addon.HasGroupFocus and addon.HasGroupFocus() == true
end

local function GlowWanted()
	local db = addon.db
	if not db then
		return false
	end
	if ExclusiveFocus() then
		return db.glowFocus == true
	end
	local content = addon.WatchContentKind and addon.WatchContentKind()
	if content == "raid" then
		return db.watchRaid == true and db.glowRaid == true
	end
	if content == "party" then
		return db.watchParty == true and db.glowParty == true
	end
	return false
end

local function DurationWanted()
	local db = addon.db
	if not db then
		return false
	end
	local content = addon.WatchContentKind and addon.WatchContentKind()
	if content == "raid" then
		return db.watchRaid == true and db.durationRaid == true
	end
	if content == "party" then
		return db.watchParty == true and db.durationParty == true
	end
	return false
end

function addon.DurationHost()
	local id = addon.db and addon.db.durationHost
	if id == "alert" or id == "both" then
		return id
	end
	return "frame"
end

function addon.DurationShowsOnFrame()
	local id = addon.DurationHost()
	return id == "frame" or id == "both"
end

function addon.DurationShowsOnAlert()
	local id = addon.DurationHost()
	return id == "alert" or id == "both"
end

function addon.HasExclusiveGroupFocus()
	return ExclusiveFocus()
end

local function FilterKind(unit)
	if ExclusiveFocus() and addon.UnitIsFocus and addon.UnitIsFocus(unit) then
		return "focus"
	end
	if addon.IsWatchSelf and addon.IsWatchSelf() and IsPlayerUnit(unit) then
		return "all"
	end
	return UnitKind(unit) or "raid"
end

-- DPS in raid/party we are watching. No frame required. Player only with watch-self.
function addon.ShouldWatchContentUnit(unit)
	if type(unit) ~= "string" or unit == "" or unit:find("pet", 1, true) then
		return false
	end
	if addon.HasAuraSpellFilters and not addon.HasAuraSpellFilters() then
		return false
	end
	if addon.RememberPlayerUnit then
		addon.RememberPlayerUnit(unit)
	end
	local watchSelf = addon.IsWatchSelf and addon.IsWatchSelf()
	if IsPlayerUnit(unit) and not watchSelf then
		return false
	end
	if not addon.db then
		return false
	end
	-- Track Focus still watches the focused group member when raid/dungeon is off.
	if addon.ContextIsWatching("focus") and addon.HasGroupFocus and addon.HasGroupFocus() and addon.UnitIsFocus and addon.UnitIsFocus(unit) then
		if watchSelf and IsPlayerUnit(unit) then
			return true
		end
		return IsDPSUnit(unit)
	end
	local content = addon.WatchContentKind and addon.WatchContentKind()
	if content == "raid" then
		if not addon.ContextIsWatching("raid") then
			return false
		end
	elseif content == "party" then
		if not addon.ContextIsWatching("party") then
			return false
		end
	else
		return false
	end
	local kind = UnitKind(unit)
	if kind ~= "raid" and kind ~= "party" then
		return false
	end
	if watchSelf and IsPlayerUnit(unit) then
		return true
	end
	if addon.GetTrackPlayerMode and addon.GetTrackPlayerMode(content) == "listed" then
		return addon.UnitMatchesTrackNames and addon.UnitMatchesTrackNames(unit)
	end
	return IsDPSUnit(unit)
end

-- DPS in raid/party we are watching. Player only with watch-self debug.
local function ShouldTrack(frame, unit)
	if not frame or FrameIsForbidden(frame) then
		return false
	end
	if addon.IsGroupUnitFrame and not addon.IsGroupUnitFrame(frame) then
		return false
	end
	if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(frame) then
		return false
	end
	return addon.ShouldWatchContentUnit(unit)
end

-- Off after PI, and off for everyone except the focused group member.
local function ShouldEnable(frame, unit)
	if not addon.IsActive or not addon.IsActive() then
		return false
	end
	if not GlowWanted() or not addon.IsGlowAllowed or not addon.IsGlowAllowed() then
		return false
	end
	if not ShouldTrack(frame, unit) then
		return false
	end
	if ExclusiveFocus() then
		local watchSelf = addon.IsWatchSelf and addon.IsWatchSelf()
		if watchSelf and IsPlayerUnit(unit) then
			return true
		end
		return addon.UnitIsFocus and addon.UnitIsFocus(unit)
	end
	return true
end

local function HostSize(host)
	local w, h = 40, 40
	if host and host.GetWidth then
		local ok, value = pcall(host.GetWidth, host)
		if ok then
			value = addon.SafeNumber(value, 0)
			if value >= 8 then
				w = value
			end
		end
	end
	if host and host.GetHeight then
		local ok, value = pcall(host.GetHeight, host)
		if ok then
			value = addon.SafeNumber(value, 0)
			if value >= 8 then
				h = value
			end
		end
	end
	return w, h
end

local DURATION_PAD = 3

local DURATION_POINTS = {
	center      = { point = "CENTER",      justifyH = "CENTER", x = 0,            y = 0 },
	top         = { point = "TOP",         justifyH = "CENTER", x = 0,            y = -DURATION_PAD },
	bottom      = { point = "BOTTOM",      justifyH = "CENTER", x = 0,            y = DURATION_PAD },
	left        = { point = "LEFT",        justifyH = "LEFT",   x = DURATION_PAD,  y = 0 },
	right       = { point = "RIGHT",       justifyH = "RIGHT",  x = -DURATION_PAD, y = 0 },
	topleft     = { point = "TOPLEFT",     justifyH = "LEFT",   x = DURATION_PAD,  y = -DURATION_PAD },
	topright    = { point = "TOPRIGHT",    justifyH = "RIGHT",  x = -DURATION_PAD, y = -DURATION_PAD },
	bottomleft  = { point = "BOTTOMLEFT",  justifyH = "LEFT",   x = DURATION_PAD,  y = DURATION_PAD },
	bottomright = { point = "BOTTOMRIGHT", justifyH = "RIGHT",  x = -DURATION_PAD, y = DURATION_PAD },
}

local function GetLSM()
	local stub = _G.LibStub
	if type(stub) ~= "function" and type(stub) ~= "table" then
		return nil
	end
	local ok, lib = pcall(stub, "LibSharedMedia-3.0", true)
	if ok and type(lib) == "table" then
		return lib
	end
	return nil
end

local FONT_PATH_ALTS = {
	default = { "Fonts\\ARIALN.TTF" },
	friz = { "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT___CYR.TTF" },
	skurri = { "Fonts\\SKURRI.TTF", "Fonts\\SKURRI_CYR.TTF", "Fonts\\skurri.ttf" },
	morpheus = { "Fonts\\MORPHEUS.TTF", "Fonts\\MORPHEUS_CYR.TTF" },
}

local FONT_OBJECT_ALTS = {
	default = { "ChatFontNormal", "SystemFont_Small" },
	friz = { "GameFontNormal", "GameFontNormalSmall" },
	skurri = { "NumberFontNormalLarge", "NumberFont_Outline_Med", "GameFontNormalHuge" },
	morpheus = { "QuestFont_Super_Huge", "QuestTitleFont", "Fancy12Font" },
}

local LSM_FONT_NAMES = {
	default = "Arial Narrow",
	friz = "Friz Quadrata TT",
	skurri = "Skurri",
	morpheus = "Morpheus",
}

local function PathFromFontObject(name)
	local obj = _G[name]
	if not obj or not obj.GetFont then
		return nil
	end
	local ok, path = pcall(obj.GetFont, obj)
	if ok and type(path) == "string" and path ~= "" then
		return path
	end
	return nil
end

local function CollectDurationFontPaths()
	local db = addon.db
	local id = db and db.durationFont
	local out = {}
	local seen = {}
	local function add(path)
		if type(path) ~= "string" or path == "" or seen[path] then
			return
		end
		seen[path] = true
		out[#out + 1] = path
	end
	local function addFromObject(name)
		add(PathFromFontObject(name))
	end
	local function addLSM(name)
		if type(name) ~= "string" or name == "" then
			return
		end
		local lsm = GetLSM()
		if lsm and lsm.Fetch then
			add(lsm:Fetch("font", name, true))
		end
	end

	local preset
	local presets = addon.FONT_PRESETS
	if type(id) == "string" and id ~= "" and type(presets) == "table" then
		for i = 1, #presets do
			if presets[i].id == id then
				preset = presets[i]
				break
			end
		end
	end

	if preset then
		addLSM(LSM_FONT_NAMES[preset.id] or preset.name)
		add(preset.path)
		local alts = FONT_PATH_ALTS[preset.id]
		if alts then
			for i = 1, #alts do
				add(alts[i])
			end
		end
		local objects = FONT_OBJECT_ALTS[preset.id]
		if objects then
			for i = 1, #objects do
				addFromObject(objects[i])
			end
		end
	elseif type(id) == "string" and id ~= "" then
		addLSM(id)
		addFromObject(id)
	end

	add(addon.FONT)
	if type(STANDARD_TEXT_FONT) == "string" then
		add(STANDARD_TEXT_FONT)
	end
	return out
end

local function TrySetFont(target, path, size, flags)
	if not target or not target.SetFont or type(path) ~= "string" or path == "" then
		return false
	end
	local ok, success = pcall(target.SetFont, target, path, size, flags)
	if not ok or success == false then
		return false
	end
	return true
end

local function ApplyFontTo(target, size)
	local paths = CollectDurationFontPaths()
	for i = 1, #paths do
		if TrySetFont(target, paths[i], size, "OUTLINE") then
			return paths[i]
		end
		if TrySetFont(target, paths[i], size, "") then
			return paths[i]
		end
	end
	TrySetFont(target, addon.FONT, size, "OUTLINE")
	return addon.FONT
end

function addon.GetFontItems()
	local items = {}
	local seen = {}
	local presets = addon.FONT_PRESETS
	if type(presets) == "table" then
		for i = 1, #presets do
			local preset = presets[i]
			if preset.id and not seen[preset.id] then
				seen[preset.id] = true
				if preset.name then
					seen[preset.name] = true
				end
				items[#items + 1] = { id = preset.id, name = preset.name or preset.id }
			end
		end
	end
	local lsm = GetLSM()
	if lsm and lsm.List then
		local list = lsm:List("font")
		if type(list) == "table" then
			for i = 1, #list do
				local name = list[i]
				if name and not seen[name] then
					seen[name] = true
					items[#items + 1] = { id = name, name = name }
				end
			end
		end
	end
	local db = addon.db
	local current = db and db.durationFont
	if type(current) == "string" and current ~= "" and not seen[current] then
		items[#items + 1] = { id = current, name = current }
	end
	return items
end

local durationFormatter

local function DurationFormatter()
	if durationFormatter then
		return durationFormatter
	end
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
		return nil
	end
	local ok, fmt = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not fmt then
		return nil
	end
	local down = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
	pcall(fmt.AddBreakpoint, fmt, {
		threshold = 0,
		step = 1,
		rounding = down,
		format = "%.0f",
	})
	pcall(fmt.AddBreakpoint, fmt, {
		threshold = 60,
		step = 1,
		rounding = down,
		format = "%.0fm",
		components = { { div = 60 } },
	})
	pcall(fmt.AddBreakpoint, fmt, {
		threshold = 3600,
		step = 1,
		rounding = down,
		format = "%.0fh",
		components = { { div = 3600 } },
	})
	durationFormatter = fmt
	return fmt
end

function addon.GetDurationAnchorSpec()
	local db = addon.db
	local id = db and db.durationAnchor or "center"
	local spec = DURATION_POINTS[id] or DURATION_POINTS.center
	local x = spec.x
	local y = spec.y
	if db and type(db.durationX) == "number" then
		x = x + db.durationX
	end
	if db and type(db.durationY) == "number" then
		y = y + db.durationY
	end
	return spec.point, spec.justifyH, x, y
end

local function DurationAnchorSpec()
	return addon.GetDurationAnchorSpec()
end

function addon.FormatDurationSeconds(seconds)
	if type(seconds) ~= "number" or seconds < 0 then
		seconds = 0
	end
	local fmt = DurationFormatter()
	if fmt then
		local ok, text
		if fmt.Format then
			ok, text = pcall(fmt.Format, fmt, seconds)
		elseif fmt.GetFormattedString then
			ok, text = pcall(fmt.GetFormattedString, fmt, seconds)
		end
		if ok and type(text) == "string" and text ~= "" then
			return text
		end
	end
	if seconds >= 3600 then
		return string.format("%.0fh", math.floor(seconds / 3600))
	end
	if seconds >= 60 then
		return string.format("%.0fm", math.floor(seconds / 60))
	end
	return string.format("%.0f", math.floor(seconds))
end

local function PlainLevel(frame)
	if not frame or not frame.GetFrameLevel then
		return nil
	end
	local ok, value = pcall(frame.GetFrameLevel, frame)
	if not ok then
		return nil
	end
	return addon.SafeNumber(value, nil)
end

local function RaiseDurationHost(button, unitFrame)
	local host = button and button.pihDurationHost
	if not host then
		return
	end
	local level = 1
	local function consider(frame)
		local value = PlainLevel(frame)
		if value and value > level then
			level = value
		end
	end
	consider(unitFrame)
	consider(button)
	consider(button.pihGlowHost)
	local holder = button.pihGlowHost
	if holder then
		consider(holder.PIHelperGlow)
		consider(holder.PIHelperStarburst)
	end
	pcall(host.SetFrameLevel, host, level + 5)
end

local durationFontObj

local function DurationFontObject(size)
	if not durationFontObj then
		durationFontObj = CreateFont("PIH_DurationTextFont")
	end
	ApplyFontTo(durationFontObj, size)
	return durationFontObj
end

function addon.StyleDurationFontString(fs, db)
	if not fs then
		return
	end
	db = db or addon.db
	local size = 12
	if db and type(db.durationSize) == "number" then
		size = math.max(8, math.min(32, db.durationSize))
	end
	local fontObj = DurationFontObject(size)
	pcall(fs.SetFontObject, fs, fontObj)
	ApplyFontTo(fs, size)
	local _, justifyH = DurationAnchorSpec()
	pcall(fs.SetJustifyH, fs, justifyH)
	local r = (db and db.durationR) or 1
	local g = (db and db.durationG) or 1
	local b = (db and db.durationB) or 1
	local a = (db and db.durationA) or 1
	pcall(fs.SetTextColor, fs, r, g, b, a)
	pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.8)
	pcall(fs.SetShadowOffset, fs, 1, -1)
end

local function StyleDurationFontString(fs, db)
	addon.StyleDurationFontString(fs, db)
end

local function HideDuration(button)
	if not button then
		return
	end
	if button.pihDurationBound and button.ClearDurationText then
		pcall(button.ClearDurationText, button)
		button.pihDurationBound = nil
	end
	button.pihDurationFontStamp = nil
	if button.pihDurationFS then
		pcall(button.pihDurationFS.SetText, button.pihDurationFS, "")
		pcall(button.pihDurationFS.Hide, button.pihDurationFS)
	end
	if button.pihDurationHost then
		pcall(button.pihDurationHost.Hide, button.pihDurationHost)
	end
end

function addon.ApplyDurationText(button, unitFrame, isAlert)
	if not button then
		return
	end
	local db = addon.db
	local wanted = DurationWanted()
	if isAlert then
		wanted = wanted and addon.DurationShowsOnAlert()
	else
		wanted = wanted and addon.DurationShowsOnFrame()
	end
	if not db or not wanted then
		HideDuration(button)
		return
	end
	if FrameIsForbidden(button) then
		return
	end
	local host = button.pihDurationHost
	if not host then
		local ok
		ok, host = pcall(CreateFrame, "Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
		if not ok or not host then
			ok, host = pcall(CreateFrame, "Frame", nil, button)
		end
		if not ok or not host then
			return
		end
		host:EnableMouse(false)
		button.pihDurationHost = host
	end
	pcall(host.ClearAllPoints, host)
	local cover = unitFrame or button.pihGlowHost or button
	local okTL = pcall(host.SetPoint, host, "TOPLEFT", cover, "TOPLEFT")
	local okBR = pcall(host.SetPoint, host, "BOTTOMRIGHT", cover, "BOTTOMRIGHT")
	if not (okTL and okBR) then
		pcall(host.SetAllPoints, host, cover)
	end
	RaiseDurationHost(button, unitFrame)
	pcall(host.Show, host)

	local fs = button.pihDurationFS
	if not fs then
		local ok
		ok, fs = pcall(host.CreateFontString, host, nil, "OVERLAY")
		if not ok or not fs then
			return
		end
		button.pihDurationFS = fs
	end
	local point, _, x, y = DurationAnchorSpec()
	pcall(fs.ClearAllPoints, fs)
	pcall(fs.SetPoint, fs, point, host, point, x, y)
	StyleDurationFontString(fs, db)
	pcall(fs.Show, fs)

	if not button.SetDurationText then
		HideDuration(button)
		return
	end

	local size = 12
	if db and type(db.durationSize) == "number" then
		size = math.max(8, math.min(32, db.durationSize))
	end
	local stamp = tostring(db.durationFont or "default") .. "|" .. tostring(size)
	if button.pihDurationBound and button.pihDurationFontStamp ~= stamp and button.ClearDurationText then
		pcall(button.ClearDurationText, button)
		button.pihDurationBound = nil
		button.pihDurationFontStamp = nil
		StyleDurationFontString(fs, db)
	end

	if button.pihDurationBound then
		button.pihDurationFontStamp = stamp
		return
	end
	local opts = {}
	local formatter = DurationFormatter()
	if formatter then
		opts.textFormatter = formatter
	end
	local ok = pcall(button.SetDurationText, button, fs, opts)
	if not ok then
		local created
		created, fs = pcall(button.CreateFontString, button, nil, "OVERLAY")
		if created and fs then
			button.pihDurationFS = fs
			pcall(fs.ClearAllPoints, fs)
			pcall(fs.SetPoint, fs, point, host, point, x, y)
			StyleDurationFontString(fs, db)
			ok = pcall(button.SetDurationText, button, fs, opts)
		end
	end
	if ok then
		button.pihDurationBound = true
		button.pihDurationFontStamp = stamp
		StyleDurationFontString(fs, db)
	else
		HideDuration(button)
	end
end

local function InitSlotButton(button, host)
	if not button then
		return
	end
	if host and host.PIHelperContainer then
		host.PIHelperContainer.pihSlotButton = button
	end
	if not button.pihDecorated then
		button.pihDecorated = true
		pcall(button.EnableMouse, button, false)
		if button.SetMouseClickEnabled then
			pcall(button.SetMouseClickEnabled, button, false)
		end
		button:ClearAllPoints()
		pcall(button.SetPoint, button, "CENTER", host, "CENTER")
		pcall(button.SetSize, button, 1, 1)
		local dummy = button.pihDummyIcon
		if not dummy then
			dummy = button:CreateTexture(nil, "BACKGROUND")
			dummy:SetSize(1, 1)
			dummy:SetPoint("CENTER")
			dummy:SetAlpha(0)
			dummy:SetColorTexture(0, 0, 0, 0)
			button.pihDummyIcon = dummy
		end
		pcall(button.SetIcon, button, dummy)
	end
	if addon.DecorateAuraGlow then
		local w, h = HostSize(host)
		pcall(addon.DecorateAuraGlow, button, { host = host, width = w, height = h })
	end
	addon.ApplyDurationText(button, host)
end

local function SetSlotFilters(container, kind)
	local filters = addon.GetAuraCandidateFilters(kind)
	if container.SetAuraSlotCandidateFilters then
		pcall(container.SetAuraSlotCandidateFilters, container, GROUP_KEY, filters)
	elseif container.SetAuraGroupCandidateFilters then
		pcall(container.SetAuraGroupCandidateFilters, container, GROUP_KEY, filters)
	end
end

local function AddSlot(container, kind, host)
	if container.pihHasGroup then
		return true
	end
	local opts = {
		maxFrameCount = 1,
		initializeFrame = function(button)
			if container.pihSlotButton then
				return
			end
			InitSlotButton(button, host)
			container.pihSlotButton = button
		end,
		candidateFilters = addon.GetAuraCandidateFilters(kind),
	}
	local filter = AuraFilterString()
	local added, slot
	if container.AddAuraSlot then
		local ok, result = pcall(container.AddAuraSlot, container, GROUP_KEY, filter, opts)
		if ok then
			added = true
			slot = result
		else
			addon.Debug("AddAuraSlot failed", kind, result)
		end
	end
	if not added and container.AddAuraGroup then
		local ok, err = pcall(container.AddAuraGroup, container, GROUP_KEY, filter, opts)
		if ok then
			added = true
		else
			addon.Debug("AddAuraGroup failed", kind, err)
		end
	end
	if not added then
		return false
	end
	if type(slot) == "table" and slot.SetPoint and not container.pihSlotButton then
		InitSlotButton(slot, host)
		container.pihSlotButton = slot
	end
	container.pihHasGroup = true
	return true
end

-- AuraKit: point + 1x1 so the engine has a visible rect to run layout from.
local function CreateContainer(parent)
	if not addon.EnsureAuraContainerLoaded() then
		addon.Debug("Blizzard_AuraContainer not loaded")
		return nil
	end
	if FrameIsForbidden(parent) then
		return nil
	end
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not container then
		addon.Debug("AuraContainer create failed", ok and "nil" or container)
		return nil
	end
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", parent, "TOPLEFT")
	container:SetSize(1, 1)
	pcall(container.EnableMouse, container, false)
	if parent.GetFrameLevel then
		local okLevel, raw = pcall(parent.GetFrameLevel, parent)
		if okLevel then
			local level = addon.SafeNumber(raw, 0)
			pcall(container.SetFrameLevel, container, level + 8)
		end
	end
	container.pihHasGroup = false
	return container
end

local function SetLive(container, enabled)
	if not container then
		return
	end
	container.pihLive = enabled and true or false
	if container.SetEnabled then
		pcall(container.SetEnabled, container, enabled and true or false)
	end
end

-- CompactUnitFrame_SetUnit, RFC_OnUnitAssigned, and MRF_OnUnitChanged run
-- after unit assign. Do not HookScript OnAttributeChanged on raid cells:
-- PrivateAurasUI requires that slot (GetScript nil, then SetScript), and
-- a PIHelper handler taints SetAttribute("unit") into GetAllPrivateAuras.
local function HookFrameWatch(frame)
	if not frame or frame.PIHelperShowHooked then
		return
	end
	frame.PIHelperShowHooked = true
	pcall(frame.HookScript, frame, "OnShow", function(self)
		if addon.IsActive and addon.IsActive() then
			addon.AttachUnitFrame(self)
		end
	end)
end

local function SyncFrame(frame)
	if not frame or FrameIsForbidden(frame) then
		return
	end
	if addon.IndexGroupUnitFrame then
		addon.IndexGroupUnitFrame(frame)
	end
	HookFrameWatch(frame)
	local unit = FrameUnit(frame)
	local container = containers[frame] or frame.PIHelperContainer
	if not GlowWanted() or not addon.IsActive or not addon.IsActive() then
		SetLive(container, false)
		return
	end
	if not ShouldTrack(frame, unit) then
		SetLive(container, false)
		return
	end
	if not container then
		container = CreateContainer(frame)
		if not container then
			return
		end
		containers[frame] = container
		frame.PIHelperContainer = container
		addon.Debug("container", unit)
	end
	local kind = FilterKind(unit)
	local on = ShouldEnable(frame, unit)
	if not on then
		SetLive(container, false)
		return
	end
	if not AddSlot(container, kind, frame) then
		return
	end
	SetSlotFilters(container, kind)
	-- SetEnabled first so SetUnit can register UNIT_AURA. SetUnit while
	-- disabled does not stick; a later enable-only pass would show nothing.
	if container.pihHasGroup and container.pihUnit == unit and container.pihLive == on then
		return
	end
	container.pihUnit = unit
	SetLive(container, on)
	if container.SetUnit then
		pcall(container.SetUnit, container, unit)
	end
	if on and container.UpdateAllAuras then
		pcall(container.UpdateAllAuras, container)
	end
end

local function SyncAll()
	if not addon.ForEachUnitFrame then
		return
	end
	local seen = {}
	addon.ForEachUnitFrame(function(frame)
		seen[frame] = true
		SyncFrame(frame)
	end)
	for frame, container in pairs(containers) do
		if not seen[frame] then
			SetLive(container, false)
			containers[frame] = nil
		end
	end
end

local pendingFrames = setmetatable({}, { __mode = "k" })
local pendingFlush

function addon.AttachUnitFrame(unitFrame)
	if not unitFrame then
		return
	end
	pendingFrames[unitFrame] = true
	if pendingFlush then
		return
	end
	pendingFlush = true
	C_Timer.After(0, function()
		pendingFlush = false
		local frames = pendingFrames
		pendingFrames = setmetatable({}, { __mode = "k" })
		for frame in pairs(frames) do
			SyncFrame(frame)
		end
	end)
end

function addon.RestoreTrackedGlow(frame)
	SyncFrame(frame)
end

function addon.ApplySpellFilters()
	for frame, container in pairs(containers) do
		if container and container.pihHasGroup then
			local unit = FrameUnit(frame)
			local kind = FilterKind(unit)
			SetSlotFilters(container, kind)
			if container.UpdateAllAuras then
				pcall(container.UpdateAllAuras, container)
			end
		end
	end
end

function addon.RefreshContainerGlows(paintOnly)
	if paintOnly ~= true then
		SyncAll()
	end
	for frame, container in pairs(containers) do
		local button = container and container.pihSlotButton
		if button then
			if addon.DecorateAuraGlow then
				local w, h = HostSize(frame)
				pcall(addon.DecorateAuraGlow, button, { host = frame, width = w, height = h })
			end
			pcall(addon.ApplyDurationText, button, frame)
		end
	end
end

function addon.RebuildTrackers()
	PruneRoleCache()
	addon.HookRaidFrameProviders()
	if addon.WipePlayerUnits then
		addon.WipePlayerUnits()
	end
	SyncAll()
	local n = 0
	for _ in pairs(containers) do
		n = n + 1
	end
	addon.Debug("trackers", n)
	addon.Fire("TRACKERS_REBUILT")
end

function addon.QueueAttach()
	if not addon.IsActive or not addon.IsActive() then
		return
	end
	attachLateGen = attachLateGen + 1
	local gen = attachLateGen
	C_Timer.After(0.5, function()
		if gen ~= attachLateGen then
			return
		end
		if addon.IsActive and addon.IsActive() then
			addon.RebuildTrackers()
		end
	end)
end

local function DisableAll()
	for _, container in pairs(containers) do
		SetLive(container, false)
	end
end

local function HookCompact()
	if hooked then
		return
	end
	hooked = true
	if CompactUnitFrame_SetUnit then
		hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
			if addon.UsesReplacementGroupFrames and addon.UsesReplacementGroupFrames() then
				return
			end
			if addon.IsActive and addon.IsActive() then
				addon.AttachUnitFrame(frame)
			end
		end)
	end
end

local ellesmereHooked

local function HookEllesmereAssign()
	if ellesmereHooked then
		return
	end
	local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
	local ns = modules and modules.EllesmereUIRaidFrames
	if not ns or type(ns.RFC_OnUnitAssigned) ~= "function" then
		return
	end
	ellesmereHooked = true
	hooksecurefunc(ns, "RFC_OnUnitAssigned", function(button)
		if addon.IsActive and addon.IsActive() then
			addon.AttachUnitFrame(button)
		end
	end)
end

local buzzardHooked

local function HookBuzzardAssign()
	if buzzardHooked then
		return
	end
	local BF = _G.BuzzardFrames
	if type(BF) ~= "table" or type(BF.RegisterFrame) ~= "function" then
		return
	end
	buzzardHooked = true
	hooksecurefunc(BF, "RegisterFrame", function(_, frame)
		if addon.IsActive and addon.IsActive() then
			addon.AttachUnitFrame(frame)
		end
	end)
end

local vuhdoHooked

local function HookVuhDoAssign()
	if vuhdoHooked then
		return
	end
	if type(_G.VUHDO_setupAllHealButtonAttributes) ~= "function" then
		return
	end
	vuhdoHooked = true
	hooksecurefunc("VUHDO_setupAllHealButtonAttributes", function(button, _, _, _, isTg)
		if isTg then
			return
		end
		if addon.IsActive and addon.IsActive() then
			addon.AttachUnitFrame(button)
		end
	end)
end

local michsHooked

local function HookMichsAssign()
	if michsHooked then
		return
	end
	if type(_G.MRF_OnUnitChanged) ~= "function" then
		return
	end
	michsHooked = true
	hooksecurefunc("MRF_OnUnitChanged", function(frame)
		if not frame or frame.frameType == "boss" or frame.frameType == "test" or frame.frameType == "preview" then
			return
		end
		if addon.IsActive and addon.IsActive() then
			addon.AttachUnitFrame(frame)
		end
	end)
end

local cellHooked
local cellHeaderHooked

local function HookCellAssign()
	local Cell = _G.Cell
	if type(Cell) ~= "table" or type(Cell.RegisterCallback) ~= "function" then
		return
	end
	if not cellHooked then
		local function onCellFrames()
			if addon.IsActive and addon.IsActive() then
				addon.QueueAttach()
			end
		end
		local okGroup = pcall(Cell.RegisterCallback, "GroupTypeChanged", "PIHelper", onCellFrames)
		local okLayout = pcall(Cell.RegisterCallback, "UpdateLayout", "PIHelper", onCellFrames)
		if okGroup or okLayout then
			cellHooked = true
		end
	end
	if cellHeaderHooked then
		return
	end
	local header = _G.CellPartyFrameHeader
	if not header or type(header.UpdateButtonUnit) ~= "function" then
		return
	end
	cellHeaderHooked = true
	hooksecurefunc(header, "UpdateButtonUnit", function(_, bName)
		local button = type(bName) == "string" and _G[bName]
		if button and addon.IsActive and addon.IsActive() then
			addon.AttachUnitFrame(button)
		end
	end)
end

function addon.HookRaidFrameProviders()
	HookCompact()
	HookEllesmereAssign()
	HookBuzzardAssign()
	HookVuhDoAssign()
	HookMichsAssign()
	HookCellAssign()
end

addon.On("LOADED", addon.HookRaidFrameProviders)
local loginBurst
addon.On("LOGIN", function()
	addon.HookRaidFrameProviders()
	-- In-combat /reload: lockdown is still false in this window. Create
	-- containers now; delayed QueueAttach is for late-loading frame addons.
	if addon.IsActive and addon.IsActive() then
		addon.RebuildTrackers()
	end
	addon.QueueAttach()
	if loginBurst then
		return
	end
	loginBurst = true
	local delays = { 0.2, 0.5, 1, 2, 4, 8 }
	for i = 1, #delays do
		C_Timer.After(delays[i], function()
			if addon.IsActive and addon.IsActive() then
				addon.HookRaidFrameProviders()
				addon.RebuildTrackers()
			end
		end)
	end
end)
addon.On("ACTIVATE", function()
	addon.RebuildTrackers()
	addon.QueueAttach()
end)
addon.On("DEACTIVATE", DisableAll)
addon.On("ROSTER", addon.QueueAttach)
addon.On("COMBAT_END", addon.QueueAttach)
addon.On("FOCUS", SyncAll)
addon.On("POLICY", SyncAll)
addon.On("PI_CAST", SyncAll)
