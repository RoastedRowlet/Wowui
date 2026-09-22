--[[
	Whisper tracking. Midnight does not let addons read whisper text or
	sender names, so any incoming in-game whisper while you are in a group,
	in combat, with PI ready is treated as a PI request. Optional raid-only
	mode skips dungeons and party groups. Battle.net whispers are ignored
	unless that option is turned off.

	Priority: glow the first listed player who is currently in the group.
	Rotation: glow the current name on whisper. After you PI, move to the next
	name and wait for a new whisper in the next PI window.

	Old whispers are never replayed when PI comes back up.
]]

local ADDON_NAME, addon = ...

local sequenceIndex = 1
local requested = false
local activeFrames = {}
local whisperFrame

local function WhisperInAllowedContent()
	local db = addon.db
	if not db or not db.whisperRaidOnly then
		return true
	end
	return addon.WatchContentKind and addon.WatchContentKind() == "raid"
end

local function WhisperRequestAllowed()
	local db = addon.db
	if not db or not db.enabled or not db.whisperEnabled then
		return false
	end
	if not (IsInGroup and IsInGroup()) then
		return false
	end
	if not WhisperInAllowedContent() then
		return false
	end
	if not addon.IsPriest() then
		return false
	end
	if not addon.InCombat() then
		return false
	end
	if not addon.IsPIReady() then
		return false
	end
	if db.healerOnly and not addon.IsHealerSpec() then
		return false
	end
	return true
end

local function UnitMatchesName(unit, listed)
	if addon.UnitMatchesNameSet then
		return addon.UnitMatchesNameSet(unit, listed)
	end
	return false
end

function addon.IsWhisperSequenceMode()
	local db = addon.db
	if not db then
		return false
	end
	if db.whisperMode == "sequence" then
		return true
	end
	if db.whisperMode == "listed" then
		return false
	end
	return db.whisperSequence == true
end

local function NameList()
	local db = addon.db
	if not db then
		return {}
	end
	if addon.IsWhisperSequenceMode() then
		return db.sequenceNames or {}
	end
	return db.whisperNames or {}
end

local function ResolveGroupUnit(displayName)
	if not displayName then
		return nil
	end
	local listed = addon.NameKeys and addon.NameKeys(displayName) or {}
	if not next(listed) then
		return nil
	end
	local function check(unit)
		if UnitMatchesName(unit, listed) then
			return unit
		end
		return nil
	end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local unit = check("raid" .. i)
			if unit then
				return unit
			end
		end
		return nil
	end
	if IsInGroup() then
		if check("player") then
			return "player"
		end
		for i = 1, GetNumSubgroupMembers() do
			local unit = check("party" .. i)
			if unit then
				return unit
			end
		end
		return nil
	end
	return check("player")
end

local function NameIsInGroup(displayName)
	if ResolveGroupUnit(displayName) then
		return true
	end
	return addon.FindUnitFrameByName and addon.FindUnitFrameByName(displayName) ~= nil
end

local function FindWhisperFrame(displayName)
	local unit = ResolveGroupUnit(displayName)
	if unit and addon.FindUnitFrame then
		local frame = addon.FindUnitFrame(unit)
		if frame then
			return frame, unit
		end
	end
	if addon.FindUnitFrameByName then
		return addon.FindUnitFrameByName(displayName), unit
	end
	return nil, unit
end

local function FirstNameInGroup(startIndex)
	local list = NameList()
	local n = #list
	if n == 0 then
		return nil, nil
	end
	if type(startIndex) ~= "number" or startIndex < 1 then
		startIndex = 1
	end
	if startIndex > n then
		return nil, nil
	end
	local cycle = addon.IsWhisperSequenceMode() and addon.db and addon.db.whisperCycle
	local i = startIndex
	for _ = 1, n do
		local name = list[i]
		if NameIsInGroup(name) then
			return name, i
		end
		i = i + 1
		if i > n then
			if not cycle then
				return nil, nil
			end
			i = 1
		end
	end
	return nil, nil
end

local function StopAllWhisperGlows()
	if addon.HideWhisperAlert then
		addon.HideWhisperAlert()
	end
	for frame in pairs(activeFrames) do
		addon.StopFrameGlow(frame)
		if addon.RestoreTrackedGlow then
			addon.RestoreTrackedGlow(frame)
		end
	end
	wipe(activeFrames)
end

local function GlowName(displayName)
	local db = addon.db
	local showAlert = addon.AlertShowsWhisper and addon.AlertShowsWhisper()
	if showAlert then
		if addon.ShowWhisperAlert then
			addon.ShowWhisperAlert(displayName)
		end
	end
	if not db or not db.whisperRaidGlow then
		return showAlert == true
	end
	local frame, unit = FindWhisperFrame(displayName)
	if not frame then
		addon.Debug("No raid frame for whisper name", displayName, unit)
		return false
	end
	addon.StartFrameGlow(frame)
	activeFrames[frame] = true
	addon.Debug("Whisper glow on", displayName, unit)
	return true
end

local function TargetName()
	if addon.IsWhisperSequenceMode() then
		return FirstNameInGroup(sequenceIndex)
	end
	return FirstNameInGroup(1)
end

local function RefreshActiveGlow()
	StopAllWhisperGlows()
	if not requested or not WhisperRequestAllowed() then
		return
	end
	local name
	if addon.IsWhisperSequenceMode() then
		local list = NameList()
		name = list[sequenceIndex]
		if name and not NameIsInGroup(name) then
			name = nil
		end
	else
		name = FirstNameInGroup(1)
	end
	if name then
		GlowName(name)
	end
end

local function HandleWhisperRequest()
	if not WhisperRequestAllowed() then
		return
	end
	local name, index = TargetName()
	if not name then
		addon.Debug("Whisper request: no listed player in group")
		return
	end
	if addon.IsWhisperSequenceMode() then
		sequenceIndex = index
	end
	requested = true
	addon.Debug("Whisper request for", name)
	if addon.db.whisperSound then
		addon.PlayAlertSound()
	end
	StopAllWhisperGlows()
	GlowName(name)
end

function addon.OnWhisperPICast()
	StopAllWhisperGlows()
	requested = false
	if not addon.IsWhisperSequenceMode() then
		sequenceIndex = 1
		return
	end
	local list = NameList()
	sequenceIndex = sequenceIndex + 1
	if sequenceIndex > #list then
		if addon.db and addon.db.whisperCycle then
			sequenceIndex = 1
		end
	end
end

function addon.ResetWhisperSequence()
	requested = false
	sequenceIndex = 1
	StopAllWhisperGlows()
end

function addon.RefreshWhisperDisplay()
	local db = addon.db
	if not db or not db.whisperEnabled or not WhisperRequestAllowed() then
		requested = false
		StopAllWhisperGlows()
		return
	end
	RefreshActiveGlow()
end

local function WhisperEventsWanted()
	local db = addon.db
	return addon.IsActive and addon.IsActive()
		and db and db.whisperEnabled
		and IsInGroup and IsInGroup()
		and WhisperInAllowedContent()
end

local function SyncWhisperEvents()
	if WhisperEventsWanted() then
		if not whisperFrame then
			whisperFrame = CreateFrame("Frame")
			whisperFrame:SetScript("OnEvent", function(_, event)
				if event == "CHAT_MSG_BN_WHISPER" then
					local db = addon.db
					if not db or db.whisperIgnoreBnet ~= false then
						return
					end
				end
				HandleWhisperRequest()
			end)
		end
		whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
		if addon.db and addon.db.whisperIgnoreBnet == false then
			whisperFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
		else
			whisperFrame:UnregisterEvent("CHAT_MSG_BN_WHISPER")
		end
	elseif whisperFrame then
		whisperFrame:UnregisterAllEvents()
	end
end

addon.On("PI_CAST", addon.OnWhisperPICast)
addon.On("POLICY", function()
	SyncWhisperEvents()
	if not WhisperRequestAllowed() then
		requested = false
		StopAllWhisperGlows()
		return
	end
	RefreshActiveGlow()
end)
addon.On("ACTIVATE", SyncWhisperEvents)
addon.On("DEACTIVATE", function()
	if whisperFrame then
		whisperFrame:UnregisterAllEvents()
	end
	requested = false
	sequenceIndex = 1
	StopAllWhisperGlows()
end)
addon.On("LOGIN", SyncWhisperEvents)
addon.On("ROSTER", function()
	SyncWhisperEvents()
	if requested then
		if WhisperRequestAllowed() then
			RefreshActiveGlow()
		else
			requested = false
			StopAllWhisperGlows()
		end
	end
end)
