--[[
	Discover raid and party frames from Blizzard, ElvUI, Grid2,
	DandersFrames, EllesmereUI, BuzzardFrames, VuhDo, Mich's Raid Frames,
	Cell, Enhance QoL, Shadowed Unit Frames, and Nucleus. Player/target/focus
	unit frames are ignored.
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
	EnhanceQoLUnitFrames = true,
	ShadowedUnitFrames = true,
	Nucleus = true,
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
		unit = PlainUnitToken(frame._eqolUnit)
	end
	-- SUF leaves frame.unit empty. The secure attribute is the group token;
	-- unitSUF can be the vehicle pet while that attribute stays on the player.
	if not unit then
		unit = PlainUnitToken(frame.unitSUF)
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

-- Combat can hide the token without clearing it. Distinct from a button
-- whose unit was removed (player left, empty cell).
function addon.FrameUnitIsSecret(frame)
	if not frame or not addon.IsSecret then
		return false
	end
	local secret = addon.IsSecret
	if secret(frame.displayedUnit) or secret(frame.unit) or secret(frame.unitid)
		or secret(frame.unitToken) or secret(frame.raidid) or secret(frame._eqolUnit)
		or secret(frame.unitSUF) then
		return true
	end
	if frame.GetAttribute then
		local ok, attr = pcall(frame.GetAttribute, frame, "unit")
		if ok and secret(attr) then
			return true
		end
	end
	return false
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
	-- Enhance QoL SecureGroupHeader children. Anchors, pets, and the
	-- player/target/focus unit frames share the EQOLUF prefix.
	if n:find("eqoluf", 1, true) then
		if n:match("^eqolufpartyheaderunitbutton%d+$")
			or n:match("^eqolufraidheaderunitbutton%d+$")
			or n:match("^eqolufraidgroupheader%d+unitbutton%d+$")
			or n:match("^eqolufmtheaderunitbutton%d+$")
			or n:match("^eqolufmaheaderunitbutton%d+$")
			or n:match("^eqolufspotlightheaderunitbutton%d+$") then
			return true
		end
		return false
	end
	-- Nucleus SecureGroupHeader children. Holders, pets, and anchors share
	-- the NucleusHeader prefix. Spotlight and NPC buttons are decided by unit.
	if n:find("nucleusheader", 1, true) then
		if n:match("^nucleusheaderpartyunitbutton%d+$")
			or n:match("^nucleusheaderraidunitbutton%d+$")
			or n:match("^nucleusheaderraidg%d+unitbutton%d+$") then
			return true
		end
		if n:match("^nucleusheaderspotlightunitbutton%d+$")
			or n:match("^nucleusheadernpcunitbutton%d+$") then
			return nil
		end
		return false
	end
	-- Shadowed Unit Frames. SUFUnit* is player/target/focus. SUFChild* is
	-- pet or target-of-unit. Split raid groups are SUFHeaderraidNUnitButtonM.
	if n:find("sufheader", 1, true) or n:find("sufchild", 1, true) or n:find("sufunit", 1, true) then
		if n:match("^sufheaderpartyunitbutton%d+$")
			or n:match("^sufheaderraidunitbutton%d+$")
			or n:match("^sufheaderraid%d+unitbutton%d+$")
			or n:match("^sufheadermaintankunitbutton%d+$")
			or n:match("^sufheadermainassistunitbutton%d+$") then
			return true
		end
		return false
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

function addon.IsNucleusGroupButton(frame)
	if not frame then
		return false
	end
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" then
		return false
	end
	if name:match("^NucleusHeaderPartyUnitButton%d+$")
		or name:match("^NucleusHeaderRaidUnitButton%d+$")
		or name:match("^NucleusHeaderRaidG%d+UnitButton%d+$") then
		return true
	end
	-- Spotlight can pin target or focus. NPC frames include boss slots.
	-- Only group tokens belong on the glow.
	if name:match("^NucleusHeaderSpotlightUnitButton%d+$")
		or name:match("^NucleusHeaderNpcUnitButton%d+$") then
		local unit = addon.GetFrameUnit(frame)
		return unit == "player" or (type(unit) == "string" and (unit:find("^raid%d+$") or unit:find("^party%d+$")) ~= nil)
	end
	return false
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

function addon.IsEnhanceQoLGroupButton(frame)
	if not frame or frame._eqolPreview or frame._eqolPartyPet then
		return false
	end
	local kind = frame._eqolGroupKind
	if kind == "party" or kind == "raid" or kind == "mt" or kind == "ma" then
		return true
	end
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" then
		return false
	end
	return name:match("^EQOLUFPartyHeaderUnitButton%d+$") ~= nil
		or name:match("^EQOLUFRaidHeaderUnitButton%d+$") ~= nil
		or name:match("^EQOLUFRaidGroupHeader%d+UnitButton%d+$") ~= nil
		or name:match("^EQOLUFMTHeaderUnitButton%d+$") ~= nil
		or name:match("^EQOLUFMAHeaderUnitButton%d+$") ~= nil
		or name:match("^EQOLUFSpotlightHeaderUnitButton%d+$") ~= nil
end

local function EnhanceQoLGroupDB()
	local root = _G.EnhanceQoL
	local db = root and root.db and root.db.ufGroupFrames
	if type(db) ~= "table" then
		return nil
	end
	return db
end

local function EnhanceQoLKindEnabled(kind)
	local db = EnhanceQoLGroupDB()
	local cfg = db and db[kind]
	return type(cfg) == "table" and cfg.enabled == true
end

local function EnhanceQoLUnitFramesLoaded()
	return C_AddOns.IsAddOnLoaded("EnhanceQoLUnitFrames")
end

local function CompactFrameKind(frame)
	local current = frame
	for _ = 1, 6 do
		if not current then
			return nil
		end
		local name = current.GetName and current:GetName()
		if type(name) == "string" then
			local n = string.lower(name)
			if n:find("compactparty", 1, true) or n == "partyframe" then
				return "party"
			end
			if n:find("compactraid", 1, true) then
				return "raid"
			end
		end
		current = current.GetParent and current:GetParent()
	end
	return nil
end

-- Party and raid layouts are separate. Only the enabled one hides Blizzard.
function addon.EnhanceQoLReplacesCompactFrame(frame)
	if not frame or not EnhanceQoLUnitFramesLoaded() then
		return false
	end
	local kind = CompactFrameKind(frame)
	if kind ~= "party" and kind ~= "raid" then
		return false
	end
	return EnhanceQoLKindEnabled(kind)
end

local SHADOWED_GROUP_TYPES = {
	party = true,
	raid = true,
	maintank = true,
	mainassist = true,
}

function addon.IsShadowedGroupButton(frame)
	if not frame or frame.isHeaderFrame or frame.isChildUnit then
		return false
	end
	local kind = frame.unitType
	if type(kind) == "string" and SHADOWED_GROUP_TYPES[kind] then
		return true
	end
	local name = frame.GetName and frame:GetName()
	if type(name) ~= "string" then
		return false
	end
	return name:match("^SUFHeaderpartyUnitButton%d+$") ~= nil
		or name:match("^SUFHeaderraidUnitButton%d+$") ~= nil
		or name:match("^SUFHeaderraid%d+UnitButton%d+$") ~= nil
		or name:match("^SUFHeadermaintankUnitButton%d+$") ~= nil
		or name:match("^SUFHeadermainassistUnitButton%d+$") ~= nil
end

local function ShadowedHidesCompact(kind)
	local UF = _G.ShadowUF
	local hidden = UF and UF.db and UF.db.profile and UF.db.profile.hidden
	if type(hidden) ~= "table" then
		return false
	end
	return hidden[kind] == true
end

local function NucleusLoaded()
	return C_AddOns.IsAddOnLoaded("Nucleus") or _G.Nucleus ~= nil
end

-- Defaults hide Blizzard. A missing db still counts; an explicit false does not.
local function NucleusHidesCompact(kind)
	if not NucleusLoaded() then
		return false
	end
	local db = _G.Nucleus and _G.Nucleus.db
	local cfg = type(db) == "table" and db[kind]
	if type(cfg) ~= "table" then
		return true
	end
	return cfg.hideBlizzard ~= false
end

-- Party and raid hides are separate. Only the hidden layout replaces Blizzard.
function addon.NucleusReplacesCompactFrame(frame)
	if not frame or not NucleusLoaded() then
		return false
	end
	local kind = CompactFrameKind(frame)
	if kind ~= "party" and kind ~= "raid" then
		return false
	end
	return NucleusHidesCompact(kind)
end

-- SUF hides party frames by default and raid frames only when that option is on.
function addon.ShadowedReplacesCompactFrame(frame)
	if not frame or not _G.ShadowUF then
		return false
	end
	local kind = CompactFrameKind(frame)
	if kind ~= "party" and kind ~= "raid" then
		return false
	end
	return ShadowedHidesCompact(kind)
end

-- ElvUI / Grid2 / Danders / Ellesmere / Buzzard / VuhDo / Mich's / Cell /
-- Enhance QoL / Shadowed Unit Frames / Nucleus replace compact raid/party.
-- Those leftover cells still run PrivateAurasUI on encounter auras.
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
	if EnhanceQoLUnitFramesLoaded() and EnhanceQoLKindEnabled("party") and EnhanceQoLKindEnabled("raid") then
		return true
	end
	if _G.ShadowUF and ShadowedHidesCompact("party") and ShadowedHidesCompact("raid") then
		return true
	end
	if NucleusHidesCompact("party") and NucleusHidesCompact("raid") then
		return true
	end
	return false
end

function addon.IsGroupUnitFrame(frame)
	if not Safe(frame) then
		return false
	end
	if frame._eqolPreview or frame._eqolPartyPet then
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
	if addon.IsEnhanceQoLGroupButton(frame) then
		return true
	end
	if addon.IsShadowedGroupButton(frame) then
		return true
	end
	if addon.IsNucleusGroupButton(frame) then
		return true
	end
	if addon.EnhanceQoLReplacesCompactFrame(frame) or addon.ShadowedReplacesCompactFrame(frame) or addon.NucleusReplacesCompactFrame(frame) then
		return false
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

local function ReadChildren(parent)
	CaptureChildren(parent:GetChildren())
end

local function FrameName(frame)
	if not frame.GetName then
		return nil
	end
	local ok, name = pcall(frame.GetName, frame)
	if ok and type(name) == "string" and not (addon.IsSecret and addon.IsSecret(name)) then
		return name
	end
	return nil
end

-- Debuff icons from Blizzard_AuraContainerFrameProviders. GetChildren on
-- these throws in combat: forbidden object, even when IsForbidden is false.
local function IsAuraHost(frame, name)
	if frame.GetObjectType then
		local ok, kind = pcall(frame.GetObjectType, frame)
		if ok and kind == "AuraContainer" then
			return true
		end
	end
	local filter = frame.filter
	if addon.IsSecret and addon.IsSecret(filter) then
		return true
	end
	if type(filter) == "string" and frame.cooldown then
		return true
	end
	if type(name) ~= "string" then
		return false
	end
	local n = string.lower(name)
	if n:find("debuff", 1, true) or n:find("buffs", 1, true) or n:find("buffframe", 1, true) or n:find("privateaura", 1, true) then
		return true
	end
	return false
end

-- oUF / compact cells. Their children include aura buttons; the cell is the leaf.
local function IsLeafUnitButton(name)
	if type(name) ~= "string" then
		return false
	end
	local n = string.lower(name)
	if n:find("debuff", 1, true) or n:find("buffs", 1, true) or n:find("buffframe", 1, true) then
		return false
	end
	if n:find("unitbutton%d") or n:match("member%d+$") or n:match("^vd%d+h%d+$") then
		return true
	end
	return false
end

local function WalkChildren(parent, callback, seen, depth)
	if not Safe(parent) or depth > 5 or not parent.GetChildren then
		return
	end
	local parentName = FrameName(parent)
	if IsAuraHost(parent, parentName) or IsLeafUnitButton(parentName) then
		return
	end
	local kids = childPools[depth]
	if not kids then
		kids = {}
		childPools[depth] = kids
	end
	kids.n = 0
	captureTarget = kids
	-- A forbidden child fails the whole call. Skip that branch; do not error.
	if not pcall(ReadChildren, parent) then
		return
	end
	local n = kids.n or 0
	for i = 1, n do
		local child = kids[i]
		kids[i] = nil
		if child and not seen[child] then
			local name = FrameName(child)
			if IsAuraHost(child, name) then
				seen[child] = true
			else
				local unit = addon.GetFrameUnit(child)
				local hidden = not unit and addon.FrameUnitIsSecret(child)
				if (unit or hidden) and addon.IsGroupUnitFrame(child) then
					Consider(child, callback, seen)
				elseif IsLeafUnitButton(name) then
					seen[child] = true
				else
					WalkChildren(child, callback, seen, depth + 1)
				end
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

local function CollectNucleusHeader(header, callback, seen)
	if not header then
		return
	end
	WalkHeader(header, callback, seen, 80)
	WalkChildren(header, callback, seen, 1)
	local name = header.GetName and header:GetName()
	if type(name) ~= "string" then
		return
	end
	for i = 1, 80 do
		local button = _G[name .. "UnitButton" .. i]
		if not button then
			break
		end
		Consider(button, callback, seen)
	end
end

local function CollectNucleus(callback, seen)
	local headers = _G.Nucleus and _G.Nucleus.headers
	if type(headers) == "table" then
		CollectNucleusHeader(headers.party, callback, seen)
		CollectNucleusHeader(headers.raid, callback, seen)
		CollectNucleusHeader(headers.spotlight, callback, seen)
		CollectNucleusHeader(headers.npc, callback, seen)
		for g = 2, 8 do
			CollectNucleusHeader(headers["raidG" .. g], callback, seen)
		end
	end
	CollectNucleusHeader(_G.NucleusHeaderParty, callback, seen)
	CollectNucleusHeader(_G.NucleusHeaderRaid, callback, seen)
	CollectNucleusHeader(_G.NucleusHeaderSpotlight, callback, seen)
	CollectNucleusHeader(_G.NucleusHeaderNpc, callback, seen)
	for g = 2, 8 do
		CollectNucleusHeader(_G["NucleusHeaderRaidG" .. g], callback, seen)
	end
end

local function CollectEnhanceQoLHeader(header, callback, seen)
	if not header then
		return
	end
	WalkHeader(header, callback, seen, 100)
	WalkChildren(header, callback, seen, 1)
	local name = header.GetName and header:GetName()
	if type(name) ~= "string" then
		return
	end
	for i = 1, 100 do
		local button = _G[name .. "UnitButton" .. i]
		if not button then
			break
		end
		Consider(button, callback, seen)
	end
end

local function CollectEnhanceQoL(callback, seen)
	local root = _G.EnhanceQoL
	local GF = root and root.Aura and root.Aura.UF and root.Aura.UF.GroupFrames
	local headers = GF and GF.headers
	if type(headers) == "table" then
		for _, header in pairs(headers) do
			CollectEnhanceQoLHeader(header, callback, seen)
		end
	end
	local groups = GF and GF._raidGroupHeaders
	if type(groups) == "table" then
		for i = 1, 8 do
			CollectEnhanceQoLHeader(groups[i], callback, seen)
		end
	end
	CollectEnhanceQoLHeader(_G.EQOLUFPartyHeader, callback, seen)
	CollectEnhanceQoLHeader(_G.EQOLUFRaidHeader, callback, seen)
	CollectEnhanceQoLHeader(_G.EQOLUFMTHeader, callback, seen)
	CollectEnhanceQoLHeader(_G.EQOLUFMAHeader, callback, seen)
	CollectEnhanceQoLHeader(_G.EQOLUFSpotlightHeader, callback, seen)
	CollectEnhanceQoLHeader(GF and GF._spotlightHeader, callback, seen)
	for i = 1, 8 do
		CollectEnhanceQoLHeader(_G["EQOLUFRaidGroupHeader" .. i], callback, seen)
	end
end

local function CollectShadowedHeader(header, callback, seen)
	if not header then
		return
	end
	local kind = header.unitType
	if type(kind) == "string" and not SHADOWED_GROUP_TYPES[kind] then
		return
	end
	WalkHeader(header, callback, seen, 80)
	WalkChildren(header, callback, seen, 1)
	local name = header.GetName and header:GetName()
	if type(name) ~= "string" then
		return
	end
	for i = 1, 80 do
		local button = _G[name .. "UnitButton" .. i]
		if not button then
			break
		end
		Consider(button, callback, seen)
	end
end

local function CollectShadowed(callback, seen)
	local UF = _G.ShadowUF
	local headers = UF and UF.Units and UF.Units.headerFrames
	if type(headers) == "table" then
		for key, header in pairs(headers) do
			if type(key) == "string" and (key == "party" or key == "raid" or key == "maintank" or key == "mainassist" or key:match("^raid%d+$")) then
				CollectShadowedHeader(header, callback, seen)
			end
		end
	end
	CollectShadowedHeader(_G.SUFHeaderparty, callback, seen)
	CollectShadowedHeader(_G.SUFHeaderraid, callback, seen)
	CollectShadowedHeader(_G.SUFHeadermaintank, callback, seen)
	CollectShadowedHeader(_G.SUFHeadermainassist, callback, seen)
	for i = 1, 8 do
		CollectShadowedHeader(_G["SUFHeaderraid" .. i], callback, seen)
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
	if EnhanceQoLUnitFramesLoaded() or _G.EQOLUFPartyHeader or _G.EQOLUFRaidHeader then
		CollectEnhanceQoL(callback, seenScratch)
	end
	if _G.ShadowUF or _G.SUFHeaderparty or _G.SUFHeaderraid or _G.SUFHeaderraid1 then
		CollectShadowed(callback, seenScratch)
	end
	if NucleusLoaded() or _G.NucleusHeaderParty or _G.NucleusHeaderRaid then
		CollectNucleus(callback, seenScratch)
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
	if name == "EllesmereUIRaidFrames" or name == "EllesmereUI" or name == "BuzzardFrames" or name == "VuhDo" or name == "Michs_RaidFrames" or name == "Cell" or name == "EnhanceQoLUnitFrames" or name == "ShadowedUnitFrames" or name == "Nucleus" then
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
	HookThirdParty("EnhanceQoLUnitFrames")
	HookThirdParty("ShadowedUnitFrames")
	HookThirdParty("Nucleus")
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
	HookThirdParty("EnhanceQoLUnitFrames")
	HookThirdParty("ShadowedUnitFrames")
	HookThirdParty("Nucleus")
end)
