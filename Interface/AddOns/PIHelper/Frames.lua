--[[
	Discover raid and party frames from Blizzard, ElvUI, Grid2,
	DandersFrames, EllesmereUI, BuzzardFrames, VuhDo, Mich's Raid Frames,
	and Cell. Player/target/focus unit frames are ignored.
]]

local ADDON_NAME, addon = ...

local FRAME_ADDONS = {
	ElvUI = true,
	Grid2 = true,
	DandersFrames = true,
	EllesmereUI = true,
	EllesmereUIRaidFrames = true,
	BuzzardFrames = true,
	VuhDo = true,
	Michs_RaidFrames = true,
	Cell = true,
}

local hookedAddons = {}
local seenScratch = {}
local unitFrameIndex = setmetatable({}, { __mode = "v" })
local GROUP_UNITS = { "player" }
for i = 1, 4 do
	GROUP_UNITS[#GROUP_UNITS + 1] = "party" .. i
end
for i = 1, 40 do
	GROUP_UNITS[#GROUP_UNITS + 1] = "raid" .. i
end

local function Safe(frame)
	if not frame then
		return false
	end
	if addon.FrameIsForbidden and addon.FrameIsForbidden(frame) then
		return false
	end
	return true
end

local function PlainUnitToken(value)
	if type(value) ~= "string" or value == "" then
		return nil
	end
	if addon.IsSecret and addon.IsSecret(value) then
		return nil
	end
	return value
end

function addon.GetFrameUnit(frame)
	if not Safe(frame) then
		return nil
	end
	local unit = PlainUnitToken(frame.displayedUnit or frame.unit or frame.unitid or frame.unitToken or frame.raidid)
	if not unit and frame.GetAttribute then
		local ok, attr = pcall(frame.GetAttribute, frame, "unit")
		if ok then
			unit = PlainUnitToken(attr)
		end
	end
	if not unit then
		return nil
	end
	local okPlate, isPlate = pcall(string.find, unit, "nameplate", 1, true)
	local okPet, isPet = pcall(string.find, unit, "pet", 1, true)
	if (okPlate and isPlate) or (okPet and isPet) then
		return nil
	end
	return unit
end

local playerUnitTokens = {}
local playerGUID

local function PlainUnitGUID(unit)
	if type(unit) ~= "string" or unit == "" then
		return nil
	end
	if addon.PlainGUID then
		return addon.PlainGUID(UnitGUID(unit))
	end
	local guid = UnitGUID(unit)
	if type(guid) ~= "string" then
		return nil
	end
	if addon.IsSecret and addon.IsSecret(guid) then
		return nil
	end
	return guid
end

local function RaidIndexIsPlayer(unit)
	if type(unit) ~= "string" then
		return false
	end
	local n = unit:match("^raid(%d+)$")
	if not n then
		return false
	end
	local index = UnitInRaid("player")
	if type(index) ~= "number" or (addon.IsSecret and addon.IsSecret(index)) then
		return false
	end
	return tonumber(n) == index
end

function addon.WipePlayerUnits()
	if addon.IsRestricted and addon.IsRestricted() then
		return
	end
	wipe(playerUnitTokens)
	playerGUID = PlainUnitGUID("player")
end

function addon.RememberPlayerUnit(unit)
	if type(unit) ~= "string" or unit == "" then
		return
	end
	if unit == "player" or RaidIndexIsPlayer(unit) then
		playerUnitTokens[unit] = true
		local guid = PlainUnitGUID("player")
		if guid then
			playerGUID = guid
		end
		return
	end
	local guid = PlainUnitGUID(unit)
	if not playerGUID then
		playerGUID = PlainUnitGUID("player")
	end
	if guid and playerGUID and guid == playerGUID then
		playerUnitTokens[unit] = true
		return
	end
	if addon.SafeUnitIsUnit and addon.SafeUnitIsUnit(unit, "player") then
		playerUnitTokens[unit] = true
		return
	end
	if addon.IsRestricted and addon.IsRestricted() then
		return
	end
	if guid and playerGUID and guid ~= playerGUID then
		playerUnitTokens[unit] = nil
	end
end

function addon.IsPlayerUnitToken(unit)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	if unit == "player" or playerUnitTokens[unit] then
		return true
	end
	if RaidIndexIsPlayer(unit) then
		playerUnitTokens[unit] = true
		return true
	end
	addon.RememberPlayerUnit(unit)
	return playerUnitTokens[unit] == true
end

local function NameLooksLikeGroup(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local n = string.lower(name)
	if n:find("nameplate", 1, true) or n:find("pihelper", 1, true) then
		return false
	end
	if n:find("focus", 1, true) or n:find("target", 1, true) or n:find("boss", 1, true) or n:find("arena", 1, true) then
		if not (n:find("raid", 1, true) or n:find("party", 1, true) or n:find("compact", 1, true)) then
			return false
		end
	end
	if n == "playerframe" or n:find("uf_player", 1, true) or n:find("playerframe", 1, true) then
		return false
	end
	if n:find("unitframe", 1, true) and not n:find("raid", 1, true) and not n:find("party", 1, true) then
		return false
	end
	if n:find("buffframe", 1, true) or n:find("debuff", 1, true) or n:find("privateaura", 1, true) then
		return false
	end
	if n:find("compactraid", 1, true) or n:find("compactparty", 1, true) then
		return true
	end
	if n:find("grid2", 1, true) then
		return true
	end
	if n:find("danders", 1, true) then
		return true
	end
	if n:find("erfgroupheader", 1, true) or n:find("erfflatheader", 1, true) then
		return true
	end
	-- SecureGroupHeader children: MRF_PartyHeaderUnitButtonN, MRF_RaidHeaderNUnitButtonM.
	if n:find("mrf_partyheader", 1, true) or n:find("mrf_raidheader", 1, true) then
		return true
	end
	-- SecureGroupHeader children: BFLayoutHeaderNUnitButtonM. Do not match
	-- generic "buzzard": oUF player/target/focus frames share that prefix.
	if n:find("bflayoutheader", 1, true) then
		return true
	end
	-- VuhDo heal buttons: Vd1H1 ... Vd10H51. Skip Tg / Tot / bar children.
	if n:match("^vd%d+h%d+$") then
		return true
	end
	-- Cell SecureGroupHeader children. Do not match generic "cell".
	if n == "cellsoloframeplayer"
		or n:match("^cellpartyframeheaderunitbutton%d+$")
		or n:match("^cellraidframeheader%d+unitbutton%d+$") then
		return true
	end
	if n:find("raid", 1, true) or n:find("party", 1, true) then
		return true
	end
	return nil
end

function addon.IsEllesmereRaidButton(frame)
	local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
	local ns = modules and modules.EllesmereUIRaidFrames
	if ns and type(ns._euiUnitButtons) == "table" and ns._euiUnitButtons[frame] then
		return true
	end
	return false
end

function addon.IsBuzzardRaidButton(frame)
	local BF = _G.BuzzardFrames
	if type(BF) ~= "table" or not frame then
		return false
	end
	if type(BF.activatedFrames) == "table" and BF.activatedFrames[frame] then
		return true
	end
	if type(BF.activeFrames) == "table" and BF.activeFrames[frame] then
		return true
	end
	if type(BF.registeredFrames) == "table" then
		local name = frame.GetName and frame:GetName()
		if type(name) == "string" and BF.registeredFrames[name] == frame then
			return true
		end
	end
	return false
end

function addon.IsVuhDoHealButton(frame)
	if not frame then
		return false
	end
	local name = frame.GetName and frame:GetName()
	if type(name) == "string" and name:match("^Vd%d+H%d+$") then
		return true
	end
	return false
end

function addon.IsMichsRaidButton(frame)
	if not frame then
		return false
	end
	local name = frame.GetName and frame:GetName()
	if type(name) == "string" then
		if name:match("^MRF_PartyHeaderUnitButton%d+$") or name:match("^MRF_RaidHeader%d+UnitButton%d+$") then
			return true
		end
	end
	local parent = frame.GetParent and frame:GetParent()
	local parentName = parent and parent.GetName and parent:GetName()
	if type(parentName) ~= "string" then
		return false
	end
	if parentName ~= "MRF_PartyHeader" and not parentName:match("^MRF_RaidHeader%d+$") then
		return false
	end
	return addon.GetFrameUnit(frame) ~= nil
end

function addon.IsCellUnitButton(frame)
	if not frame then
		return false
	end
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" then
		return false
	end
	if name == "CellSoloFramePlayer" then
		return true
	end
	if name:match("^CellPartyFrameHeaderUnitButton%d+$") then
		return true
	end
	return name:match("^CellRaidFrameHeader%d+UnitButton%d+$") ~= nil
end

-- ElvUI / Grid2 / Danders / Ellesmere / Buzzard / VuhDo / Mich's / Cell replace compact
-- raid/party. Those leftover cells still run PrivateAurasUI on encounter auras.
function addon.UsesReplacementGroupFrames()
	local DF = _G.DandersFrames
	if type(DF) == "table" then
		if DF.raidCombinedHeader or DF.raidSeparatedHeaders or DF.raidFrames
			or DF.partyHeader or DF.partyFrames or DF.FlatRaidFrames
			or _G.DandersRaidFramesContainer or _G.DandersFramesContainer
			or _G.DandersPartyGroupContainer then
			return true
		end
	end
	if _G.ElvUF_Party or _G.ElvUF_Raid1 or _G.ElvUF_Raid2 or _G.ElvUF_Raid3 or _G.ElvUF_Raid40 then
		return true
	end
	if Grid2Frame then
		return true
	end
	local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
	local ns = modules and modules.EllesmereUIRaidFrames
	if ns and (ns._euiUnitButtons or ns._flatButtons) then
		return true
	end
	if _G.ERFFlatHeader or _G.ERFGroupHeader1 then
		return true
	end
	local BF = _G.BuzzardFrames
	if type(BF) == "table" or _G.BFLayoutHeader1 then
		return true
	end
	if _G.VUHDO_CONFIG or _G.VUHDO_UNIT_BUTTONS or _G.Vd1 then
		return true
	end
	if _G.MRF_PartyHeader or _G.MRF_RaidHeader1 or _G.MRF_OnUnitChanged then
		return true
	end
	if _G.CellMainFrame or (_G.Cell and _G.Cell.unitButtons) then
		return true
	end
	return false
end

function addon.IsGroupUnitFrame(frame)
	if not Safe(frame) then
		return false
	end
	if addon.IsEllesmereRaidButton(frame) then
		return true
	end
	if addon.IsBuzzardRaidButton(frame) then
		return true
	end
	if addon.IsVuhDoHealButton(frame) then
		return true
	end
	if addon.IsMichsRaidButton(frame) then
		return true
	end
	if addon.IsCellUnitButton(frame) then
		return true
	end
	if frame.dfIsDandersFrame then
		return true
	end
	local named = NameLooksLikeGroup(frame.GetName and frame:GetName())
	if named == true then
		return true
	end
	if named == false then
		return false
	end
	local parent = frame.GetParent and frame:GetParent()
	for _ = 1, 8 do
		if not parent then
			break
		end
		local look = NameLooksLikeGroup(parent.GetName and parent:GetName())
		if look == true then
			return true
		end
		if look == false then
			return false
		end
		parent = parent.GetParent and parent:GetParent()
	end
	local unit = addon.GetFrameUnit(frame)
	if type(unit) == "string" and (unit == "player" or unit:find("^raid%d+$") or unit:find("^party%d+$")) then
		return true
	end
	return false
end

local function FrameIsVisible(frame)
	if not Safe(frame) or not frame.IsVisible then
		return false
	end
	local ok, visible = pcall(frame.IsVisible, frame)
	return ok and addon.PlainBool(visible) == true
end

-- Hidden leftover compact cells are skipped: IsVisible is false when
-- the parent party or raid container is hidden.
function addon.IsDisplayedGroupFrame(frame)
	return addon.IsGroupUnitFrame(frame) and FrameIsVisible(frame)
end

local function SkipFrame(frame)
	if not Safe(frame) then
		return true
	end
	local name = frame.GetName and frame:GetName()
	if type(name) == "string" then
		if name:find("PIHelper", 1, true) or name:find("NamePlate", 1, true) then
			return true
		end
	end
	if frame.GetObjectType then
		local ok, kind = pcall(frame.GetObjectType, frame)
		if ok and kind == "AuraContainer" then
			return true
		end
	end
	if frame.pihHasGroup ~= nil or frame.pihWanted or frame.pihDecorated or frame.pihGlowHost then
		return true
	end
	local parent = frame.GetParent and frame:GetParent()
	if parent then
		if parent.PIHelperGlow == frame or parent.PIHelperStarburst == frame then
			return true
		end
		if parent.PIHelperFrameGlowHost == frame or parent.PIHelperContainer == frame then
			return true
		end
	end
	return false
end

local function RememberUnitFrame(frame)
	local unit = addon.GetFrameUnit(frame)
	if not unit then
		return
	end
	local existing = unitFrameIndex[unit]
	if existing and existing ~= frame then
		local incomingLive = addon.IsDisplayedGroupFrame(frame)
		local existingLive = addon.IsDisplayedGroupFrame(existing)
		if existingLive and not incomingLive then
			return
		end
	end
	unitFrameIndex[unit] = frame
end

function addon.IndexGroupUnitFrame(frame)
	if frame and addon.IsGroupUnitFrame(frame) then
		RememberUnitFrame(frame)
	end
end

local function Consider(frame, callback, seen)
	if not frame or seen[frame] or SkipFrame(frame) then
		return
	end
	if not addon.IsGroupUnitFrame(frame) then
		return
	end
	seen[frame] = true
	RememberUnitFrame(frame)
	callback(frame)
end

local function WalkHeader(header, callback, seen, maxChildren)
	if not Safe(header) or not header.GetAttribute then
		return
	end
	maxChildren = maxChildren or 40
	for i = 1, maxChildren do
		local child = header:GetAttribute("child" .. i)
		if child then
			Consider(child, callback, seen)
		end
	end
end

local childPools = {}
local captureTarget
local function CaptureChildren(...)
	local t = captureTarget
	local n = select("#", ...)
	t.n = n
	for i = 1, n do
		t[i] = select(i, ...)
	end
end

local function WalkChildren(parent, callback, seen, depth)
	if not Safe(parent) or depth > 5 or not parent.GetChildren then
		return
	end
	local kids = childPools[depth]
	if not kids then
		kids = {}
		childPools[depth] = kids
	end
	captureTarget = kids
	CaptureChildren(parent:GetChildren())
	local n = kids.n or 0
	for i = 1, n do
		local child = kids[i]
		kids[i] = nil
		if child and not seen[child] then
			if addon.GetFrameUnit(child) and addon.IsGroupUnitFrame(child) then
				Consider(child, callback, seen)
			else
				WalkChildren(child, callback, seen, depth + 1)
			end
		end
	end
end

local function WalkNamed(prefix, maxN, callback, seen)
	for i = 1, maxN do
		Consider(_G[prefix .. i], callback, seen)
	end
end

local function CollectBlizzard(callback, seen)
	local function consider(frame)
		Consider(frame, callback, seen)
	end
	if CompactRaidFrameContainer and CompactRaidFrameContainer.ApplyToFrames then
		pcall(CompactRaidFrameContainer.ApplyToFrames, CompactRaidFrameContainer, "normal", consider)
		pcall(CompactRaidFrameContainer.ApplyToFrames, CompactRaidFrameContainer, "mini", consider)
	end
	if CompactPartyFrame and CompactPartyFrame.ApplyToFrames then
		pcall(CompactPartyFrame.ApplyToFrames, CompactPartyFrame, "normal", consider)
	end
	for i = 1, 5 do
		Consider(_G["CompactPartyFrameMember" .. i], callback, seen)
		Consider(_G["CompactPartyFramePet" .. i], callback, seen)
	end
	for g = 1, 8 do
		for m = 1, 5 do
			Consider(_G["CompactRaidGroup" .. g .. "Member" .. m], callback, seen)
		end
	end
	for i = 1, 40 do
		Consider(_G["CompactRaidFrame" .. i], callback, seen)
	end
	WalkChildren(CompactRaidFrameContainer, callback, seen, 1)
	WalkChildren(CompactPartyFrame, callback, seen, 1)
end

local function CollectElvUI(callback, seen)
	for g = 1, 8 do
		for m = 1, 5 do
			Consider(_G["ElvUF_PartyGroup" .. g .. "UnitButton" .. m], callback, seen)
			Consider(_G["ElvUF_Raid1Group" .. g .. "UnitButton" .. m], callback, seen)
			Consider(_G["ElvUF_Raid2Group" .. g .. "UnitButton" .. m], callback, seen)
			Consider(_G["ElvUF_Raid3Group" .. g .. "UnitButton" .. m], callback, seen)
			Consider(_G["ElvUF_Raid40Group" .. g .. "UnitButton" .. m], callback, seen)
		end
	end
	WalkChildren(_G.ElvUF_Party, callback, seen, 1)
	WalkChildren(_G.ElvUF_Raid1, callback, seen, 1)
	WalkChildren(_G.ElvUF_Raid2, callback, seen, 1)
	WalkChildren(_G.ElvUF_Raid3, callback, seen, 1)
	WalkChildren(_G.ElvUF_Raid40, callback, seen, 1)
end

local function CollectGrid2(callback, seen)
	if Grid2 and Grid2.GetUnitFrames then
		for i = 1, #GROUP_UNITS do
			local ok, frames = pcall(Grid2.GetUnitFrames, Grid2, GROUP_UNITS[i])
			if ok and type(frames) == "table" then
				for frame in pairs(frames) do
					Consider(frame, callback, seen)
				end
			end
		end
	end
	if Grid2Frame then
		if type(Grid2Frame.activatedFrames) == "table" then
			for frame in pairs(Grid2Frame.activatedFrames) do
				Consider(frame, callback, seen)
			end
		end
		if type(Grid2Frame.registeredFrames) == "table" then
			for frame in pairs(Grid2Frame.registeredFrames) do
				Consider(frame, callback, seen)
			end
		end
	end
end

local function CollectDanders(callback, seen)
	local DF = _G.DandersFrames
	if type(DF) == "table" then
		WalkHeader(DF.partyHeader, callback, seen, 5)
		WalkHeader(DF.raidCombinedHeader, callback, seen, 40)
		local separated = DF.raidSeparatedHeaders
		if type(separated) == "table" then
			for g = 1, 8 do
				WalkHeader(separated[g], callback, seen, 5)
			end
		end
		local flat = DF.FlatRaidFrames
		if type(flat) == "table" then
			WalkHeader(flat.header, callback, seen, 40)
		end
		local raidFrames = DF.raidFrames
		if type(raidFrames) == "table" then
			for i = 1, 40 do
				Consider(raidFrames[i], callback, seen)
			end
		end
		local partyFrames = DF.partyFrames
		if type(partyFrames) == "table" then
			for i = 1, 5 do
				Consider(partyFrames[i], callback, seen)
			end
		end
	end
	WalkChildren(_G.DandersFramesContainer, callback, seen, 1)
	WalkChildren(_G.DandersRaidFramesContainer, callback, seen, 1)
	WalkChildren(_G.DandersPartyGroupContainer, callback, seen, 1)
end

local function CollectEllesmere(callback, seen)
	local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
	local ns = modules and modules.EllesmereUIRaidFrames
	if ns and type(ns._euiUnitButtons) == "table" then
		for frame in pairs(ns._euiUnitButtons) do
			Consider(frame, callback, seen)
		end
	end
	if ns and type(ns._flatButtons) == "table" then
		for i = 1, #ns._flatButtons do
			Consider(ns._flatButtons[i], callback, seen)
		end
	end
	WalkHeader(_G.ERFFlatHeader, callback, seen, 40)
	if _G.ERFFlatHeader then
		for i = 1, 40 do
			Consider(_G.ERFFlatHeader[i], callback, seen)
		end
	end
	for g = 1, 8 do
		local hdr = _G["ERFGroupHeader" .. g]
		WalkHeader(hdr, callback, seen, 5)
		if hdr then
			for i = 1, 5 do
				Consider(hdr[i], callback, seen)
			end
		end
	end
	local prefixes = {
		"EllesmereRaidUnitButton",
		"EllesmerePartyUnitButton",
		"EUIRaidFrame",
		"EUIPartyFrame",
		"EllesmereUIRaidFrame",
		"oUF_EllesmereRaid",
		"oUF_EllesmereParty",
	}
	for p = 1, #prefixes do
		WalkNamed(prefixes[p], 40, callback, seen)
	end
	WalkChildren(_G.EllesmereRaidHeader, callback, seen, 1)
	WalkChildren(_G.EUIRaidHeader, callback, seen, 1)
end

local function CollectBuzzard(callback, seen)
	local BF = _G.BuzzardFrames
	if type(BF) ~= "table" then
		return
	end
	if type(BF.GetUnitFrames) == "function" then
		for i = 1, #GROUP_UNITS do
			local ok, frames = pcall(BF.GetUnitFrames, BF, GROUP_UNITS[i])
			if ok and type(frames) == "table" then
				for frame in pairs(frames) do
					Consider(frame, callback, seen)
				end
			end
		end
	end
	if type(BF.activatedFrames) == "table" then
		for frame in pairs(BF.activatedFrames) do
			Consider(frame, callback, seen)
		end
	elseif type(BF.activeFrames) == "table" then
		for frame in pairs(BF.activeFrames) do
			Consider(frame, callback, seen)
		end
	end
	-- registeredFrames is name -> frame (Grid2Frame is frame-keyed).
	if type(BF.registeredFrames) == "table" then
		for _, frame in pairs(BF.registeredFrames) do
			Consider(frame, callback, seen)
		end
	end
	if type(BF.groupsUsed) == "table" then
		for i = 1, #BF.groupsUsed do
			local header = BF.groupsUsed[i]
			WalkHeader(header, callback, seen, 40)
			WalkChildren(header, callback, seen, 1)
			if header then
				for m = 1, 40 do
					Consider(header[m], callback, seen)
				end
			end
		end
	end
	if type(_G.BuzzardFrames_GetAllFrames) == "function" then
		local ok, list = pcall(_G.BuzzardFrames_GetAllFrames)
		if ok and type(list) == "table" then
			for i = 1, #list do
				Consider(list[i], callback, seen)
			end
		end
	end
	for h = 1, 24 do
		local header = _G["BFLayoutHeader" .. h]
		WalkHeader(header, callback, seen, 40)
		WalkChildren(header, callback, seen, 1)
		if header then
			for m = 1, 40 do
				Consider(header[m], callback, seen)
				Consider(_G["BFLayoutHeader" .. h .. "UnitButton" .. m], callback, seen)
			end
		end
	end
end

local function CollectVuhDoButtons(list, callback, seen)
	if type(list) ~= "table" then
		return
	end
	for i = 1, #list do
		Consider(list[i], callback, seen)
	end
end

local function CollectMichs(callback, seen)
	local party = _G.MRF_PartyHeader
	WalkHeader(party, callback, seen, 5)
	if party then
		for i = 1, 5 do
			Consider(party[i], callback, seen)
			Consider(_G["MRF_PartyHeaderUnitButton" .. i], callback, seen)
		end
	end
	for g = 1, 8 do
		local hdr = _G["MRF_RaidHeader" .. g]
		WalkHeader(hdr, callback, seen, 5)
		if hdr then
			for i = 1, 5 do
				Consider(hdr[i], callback, seen)
				Consider(_G["MRF_RaidHeader" .. g .. "UnitButton" .. i], callback, seen)
			end
		end
	end
end

local function CollectVuhDo(callback, seen)
	local getter = _G.VUHDO_getUnitButtonsSafe or _G.VUHDO_getUnitButtons
	if type(getter) == "function" then
		for i = 1, #GROUP_UNITS do
			local ok, list = pcall(getter, GROUP_UNITS[i])
			if ok then
				CollectVuhDoButtons(list, callback, seen)
			end
		end
	end
	local buttons = _G.VUHDO_UNIT_BUTTONS
	if type(buttons) == "table" then
		for _, list in pairs(buttons) do
			CollectVuhDoButtons(list, callback, seen)
		end
	end
	-- VUHDO_MAX_PANELS = 10, VUHDO_MAX_BUTTONS_PANEL = 51
	for p = 1, 10 do
		for b = 1, 51 do
			Consider(_G["Vd" .. p .. "H" .. b], callback, seen)
		end
	end
end

local function CollectCellUnits(map, callback, seen)
	if type(map) ~= "table" then
		return
	end
	for unit, frame in pairs(map) do
		if type(unit) == "string" and (unit == "player" or unit:find("^raid%d+$") or unit:find("^party%d+$")) then
			Consider(frame, callback, seen)
		end
	end
end

local function CollectCell(callback, seen)
	local buttons = _G.Cell and _G.Cell.unitButtons
	if type(buttons) == "table" then
		CollectCellUnits(buttons.solo, callback, seen)
		if type(buttons.party) == "table" then
			CollectCellUnits(buttons.party.units, callback, seen)
		end
		if type(buttons.raid) == "table" then
			CollectCellUnits(buttons.raid.units, callback, seen)
		end
	end
	Consider(_G.CellSoloFramePlayer, callback, seen)
	WalkHeader(_G.CellPartyFrameHeader, callback, seen, 5)
	for h = 0, 8 do
		WalkHeader(_G["CellRaidFrameHeader" .. h], callback, seen, 40)
	end
end

function addon.ForEachUnitFrame(callback)
	if type(callback) ~= "function" then
		return
	end
	if not (addon.IsRestricted and addon.IsRestricted()) then
		wipe(unitFrameIndex)
	end
	wipe(seenScratch)
	if not addon.UsesReplacementGroupFrames() then
		CollectBlizzard(callback, seenScratch)
	end
	if ElvUI or _G.ElvUF_Party or _G.ElvUF_Raid1 then
		CollectElvUI(callback, seenScratch)
	end
	if Grid2 or Grid2Frame then
		CollectGrid2(callback, seenScratch)
	end
	if _G.DandersFrames then
		CollectDanders(callback, seenScratch)
	end
	if _G.EllesmereUI or _G.ERFFlatHeader or _G.ERFGroupHeader1 then
		CollectEllesmere(callback, seenScratch)
	end
	if _G.BuzzardFrames or _G.BFLayoutHeader1 then
		CollectBuzzard(callback, seenScratch)
	end
	if _G.VUHDO_CONFIG or _G.VUHDO_UNIT_BUTTONS or _G.Vd1 then
		CollectVuhDo(callback, seenScratch)
	end
	if _G.MRF_PartyHeader or _G.MRF_RaidHeader1 then
		CollectMichs(callback, seenScratch)
	end
	if _G.CellMainFrame or (_G.Cell and _G.Cell.unitButtons) then
		CollectCell(callback, seenScratch)
	end
end

function addon.ForEachPlayerGroupFrame(callback)
	if type(callback) ~= "function" then
		return 0
	end
	local seen = {}
	local count = 0
	local function consider(frame)
		if not frame or seen[frame] or not Safe(frame) then
			return
		end
		seen[frame] = true
		count = count + 1
		callback(frame)
	end
	addon.ForEachUnitFrame(function(frame)
		local unit = addon.GetFrameUnit(frame)
		if not addon.IsPlayerUnitToken(unit) then
			return
		end
		if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(frame) then
			return
		end
		consider(frame)
	end)
	return count
end

local function CachedUnitFrame(unit)
	local cached = unitFrameIndex[unit]
	if not cached or not Safe(cached) then
		if cached then
			unitFrameIndex[unit] = nil
		end
		return nil
	end
	if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(cached) then
		unitFrameIndex[unit] = nil
		return nil
	end
	local frameUnit = addon.GetFrameUnit(cached)
	if not frameUnit then
		-- Combat secrets can hide the token; keep the last known cell.
		return cached
	end
	if frameUnit == unit or (addon.SafeUnitIsUnit and addon.SafeUnitIsUnit(frameUnit, unit)) then
		return cached
	end
	unitFrameIndex[unit] = nil
	return nil
end

function addon.FindUnitFrame(unit)
	if type(unit) ~= "string" then
		return nil
	end
	local cached = CachedUnitFrame(unit)
	if cached then
		return cached
	end
	local found
	addon.ForEachUnitFrame(function(frame)
		if found then
			return
		end
		if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(frame) then
			return
		end
		local frameUnit = addon.GetFrameUnit(frame)
		if frameUnit == unit or (frameUnit and addon.SafeUnitIsUnit(frameUnit, unit)) then
			found = frame
		end
	end)
	if found then
		unitFrameIndex[unit] = found
	end
	return found
end

function addon.FindUnitFrameByName(playerName)
	if type(playerName) ~= "string" or playerName == "" then
		return nil
	end
	local needle = addon.NameKeys and addon.NameKeys(playerName) or nil
	if not needle or not next(needle) then
		return nil
	end
	local found
	addon.ForEachUnitFrame(function(frame)
		if found then
			return
		end
		if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(frame) then
			return
		end
		local unit = addon.GetFrameUnit(frame)
		if not unit then
			return
		end
		if addon.UnitMatchesNameSet and addon.UnitMatchesNameSet(unit, needle) then
			found = frame
			return
		end
	end)
	return found
end

local function HookThirdParty(name)
	if hookedAddons[name] then
		return
	end
	if name == "Grid2" and Grid2Frame then
		hookedAddons[name] = true
		if Grid2Frame.RegisterFrame then
			hooksecurefunc(Grid2Frame, "RegisterFrame", function(_, frame)
				if addon.IsActive and addon.IsActive() and addon.AttachUnitFrame then
					addon.AttachUnitFrame(frame)
				end
			end)
		end
	end
	if name == "EllesmereUIRaidFrames" or name == "EllesmereUI" or name == "BuzzardFrames" or name == "VuhDo" or name == "Michs_RaidFrames" or name == "Cell" then
		if addon.HookRaidFrameProviders then
			addon.HookRaidFrameProviders()
		end
	end
	if FRAME_ADDONS[name] and addon.QueueAttach then
		addon.QueueAttach()
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
	if FRAME_ADDONS[name] and addon.IsActive and addon.IsActive() then
		HookThirdParty(name)
	end
end)

addon.On("LOGIN", function()
	if not addon.IsActive or not addon.IsActive() then
		return
	end
	HookThirdParty("Grid2")
	HookThirdParty("ElvUI")
	HookThirdParty("DandersFrames")
	HookThirdParty("EllesmereUIRaidFrames")
	HookThirdParty("BuzzardFrames")
	HookThirdParty("VuhDo")
	HookThirdParty("Michs_RaidFrames")
	HookThirdParty("Cell")
	if addon.HookRaidFrameProviders then
		addon.HookRaidFrameProviders()
	end
	if addon.QueueAttach then
		addon.QueueAttach()
	end
end)
addon.On("ACTIVATE", function()
	HookThirdParty("Grid2")
	HookThirdParty("ElvUI")
	HookThirdParty("DandersFrames")
	HookThirdParty("EllesmereUIRaidFrames")
	HookThirdParty("BuzzardFrames")
	HookThirdParty("VuhDo")
	HookThirdParty("Michs_RaidFrames")
	HookThirdParty("Cell")
end)
