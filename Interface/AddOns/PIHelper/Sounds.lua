--[[
	Sounds.

	Tracking sounds use C_UnitAuras.AddAuraSound on unit tokens (focus,
	raid1-40, party1-4). Registrations must be in place before combat: Add
	is blocked in combat/encounters, and Challenge Mode stays restricted
	for a whole key. Existing registrations are kept if a refresh add fails
	(clear only after a successful add, or when sounds are turned off).

	These sounds are not wrapped around Power Infusion's cooldown. The
	client plays them whenever the watched buff appears, even if PI is
	unavailable. Glows can hide in that window; sounds cannot.

	AddAuraSound accepts soundFileName / soundFileID, not SOUNDKIT ids.
	Blizzard Sound\ paths are not playable; presets store a FileDataID.
	Test Sound uses PlaySoundFile for files and PlaySound for kits.

	Playback uses LibSharedMedia when present (same list BigWigs uses), with
	Blizzard presets still available if SharedMedia is missing.
]]

local ADDON_NAME, addon = ...

local SOUND_MEDIA = "sound"
local auraSoundIDs = {}
local pendingRegister
local queued
local lsmCallbacks
local RAID_TOKENS = {}
local PARTY_TOKENS = {}
local FOCUS_TOKENS = { "focus" }
local PLAYER_PARTY_TOKENS = { "player", "party1", "party2", "party3", "party4" }

for i = 1, 40 do
	RAID_TOKENS[i] = "raid" .. i
end
for i = 1, 4 do
	PARTY_TOKENS[i] = "party" .. i
end

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

local function Channel()
	local db = addon.db
	return (db and db.soundChannel) or "Master"
end

local function FileIDFromPath(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	if GetFileIDFromPath then
		local ok, fileID = pcall(GetFileIDFromPath, path)
		if ok and type(fileID) == "number" and fileID > 1 then
			return fileID
		end
	end
	local api = C_UIFileAsset
	if api and api.GetFileID then
		local ok, fileID = pcall(api.GetFileID, path)
		if ok and type(fileID) == "number" and fileID > 1 then
			return fileID
		end
	end
	return nil
end

local function PresetMedia(preset)
	local fileID = preset.fileID
	if type(fileID) ~= "number" or fileID < 2 then
		fileID = FileIDFromPath(preset.path)
	end
	if type(fileID) == "number" and fileID > 1 then
		return { kind = "fileid", id = fileID, kit = preset.id, name = preset.key, path = preset.path }
	end
	local path = preset.path
	if type(path) == "string" and path ~= "" and string.find(string.lower(path), "^interface") then
		return { kind = "file", path = path, kit = preset.id, name = preset.key }
	end
	if type(preset.id) == "number" then
		return { kind = "kit", kit = preset.id, name = preset.key }
	end
	return nil
end

local function FindPreset(id)
	local list = addon.SOUND_PRESETS
	if type(list) ~= "table" or id == nil then
		return nil
	end
	for i = 1, #list do
		local preset = list[i]
		if preset.key == id or preset.name == id or preset.id == id then
			return preset
		end
	end
	return nil
end

function addon.ResolveSound(id)
	local db = addon.db
	if id == nil and db then
		id = db.soundName
	end
	if id == nil and db then
		id = db.soundKitID
	end
	if id == "None" or id == "none" then
		return { kind = "none" }
	end
	if type(id) == "string" then
		local kitID = string.match(id, "^kit:(%d+)$")
		if kitID then
			return { kind = "kit", kit = tonumber(kitID), name = id }
		end
	end
	local preset = FindPreset(id)
	if preset then
		return PresetMedia(preset) or { kind = "kit", kit = preset.id, name = preset.key }
	end
	if type(id) == "number" then
		preset = FindPreset(id)
		if preset then
			return PresetMedia(preset) or { kind = "kit", kit = preset.id, name = preset.key }
		end
		return { kind = "kit", kit = id }
	end
	if type(id) == "string" then
		local lsm = GetLSM()
		if lsm and lsm.Fetch then
			local data = lsm:Fetch(SOUND_MEDIA, id, true)
			if data == nil or data == 1 then
				if lsm.IsValid and lsm:IsValid(SOUND_MEDIA, id) then
					return { kind = "none", name = id }
				end
			elseif type(data) == "string" then
				return { kind = "file", path = data, name = id }
			elseif type(data) == "number" then
				return { kind = "fileid", id = data, name = id }
			end
		end
	end
	local fallback = FindPreset("ALARM_CLOCK_WARNING_3")
	if fallback then
		return PresetMedia(fallback) or { kind = "fileid", id = 567458, kit = 12889, name = "ALARM_CLOCK_WARNING_3" }
	end
	return { kind = "fileid", id = 567458, kit = 12889, name = "ALARM_CLOCK_WARNING_3" }
end

function addon.GetSoundItems()
	local items = {
		{ id = "None", name = "None" },
	}
	local seen = { None = true, none = true }
	local presets = addon.SOUND_PRESETS
	if type(presets) == "table" then
		for i = 1, #presets do
			local preset = presets[i]
			local key = preset.key
			if key and not seen[key] then
				seen[key] = true
				seen[preset.name] = true
				items[#items + 1] = { id = key, name = preset.name }
			end
		end
	end
	local lsm = GetLSM()
	if lsm and lsm.List then
		local list = lsm:List(SOUND_MEDIA)
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
	local current = db and db.soundName
	if type(current) == "string" and current ~= "" and not seen[current] then
		items[#items + 1] = { id = current, name = current }
	end
	return items
end

local function PlayResolvedSound(media)
	if not media or media.kind == "none" then
		return
	end
	local channel = Channel()
	local function playFile(file)
		local ok, willPlay = pcall(PlaySoundFile, file, channel)
		return ok and willPlay and true
	end
	if media.kind == "fileid" and media.id then
		if playFile(media.id) then
			return
		end
	elseif media.kind == "file" and media.path then
		if playFile(media.path) then
			return
		end
	end
	if media.kind == "kit" and media.kit then
		pcall(PlaySound, media.kit, channel)
		return
	end
	if media.kit then
		pcall(PlaySound, media.kit, channel)
		return
	end
	local file = media.path or media.id
	if file then
		pcall(PlaySoundFile, file, channel)
	end
end

function addon.PlaySoundByID(id)
	PlayResolvedSound(addon.ResolveSound(id))
end

local function RestrictionActive(restrictionType)
	if restrictionType == nil then
		return false
	end
	local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, restrictionType)
	return ok and addon.PlainBool(active) == true
end

-- AddAuraSound is combat/encounter-locked. Challenge Mode and map
-- restrictions stay on for a whole dungeon, so IsRestricted() would
-- never let us register after the key starts.
local function AuraSoundsLocked()
	if InCombatLockdown() then
		return true
	end
	local types = Enum.AddOnRestrictionType
	if types and (RestrictionActive(types.Combat) or RestrictionActive(types.Encounter)) then
		return true
	end
	return false
end

local function FillAuraSoundInfo(info, unitToken)
	local db = addon.db
	local media = addon.ResolveSound()
	if not media or media.kind == "none" then
		return false
	end
	info.unitToken = unitToken
	info.outputChannel = db and db.soundChannel or "Master"
	if media.kind == "fileid" and media.id then
		info.soundFileID = media.id
		return true
	end
	if type(media.id) == "number" and media.id > 1 then
		info.soundFileID = media.id
		return true
	end
	local path = media.path
	if not path and media.kit then
		local preset = FindPreset(media.kit) or FindPreset(media.name)
		path = preset and preset.path
		if preset and type(preset.fileID) == "number" and preset.fileID > 1 then
			info.soundFileID = preset.fileID
			return true
		end
	end
	if type(path) ~= "string" or path == "" then
		return false
	end
	info.soundFileName = path
	return true
end

local function AuraSoundAPI()
	return C_UnitAuras
end

local function ClearAuraSounds()
	local api = AuraSoundAPI()
	if not api or not api.RemoveAuraSound then
		wipe(auraSoundIDs)
		return
	end
	for i = 1, #auraSoundIDs do
		pcall(api.RemoveAuraSound, auraSoundIDs[i])
	end
	wipe(auraSoundIDs)
end

local function TriggerAdded()
	if Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added then
		return Enum.UnitAuraSoundTrigger.Added
	end
	return 0
end

local function TryAddAuraSound(spellID, unitToken, dest)
	local api = AuraSoundAPI()
	if not api or not api.AddAuraSound or type(unitToken) ~= "string" then
		return false
	end
	local info = { spellID = spellID }
	if not FillAuraSoundInfo(info, unitToken) then
		return false
	end
	local ok, soundID = pcall(api.AddAuraSound, TriggerAdded(), info)
	if ok and type(soundID) == "number" then
		dest[#dest + 1] = soundID
		return true
	end
	addon.Debug("AddAuraSound failed for", spellID, unitToken, soundID)
	return false
end

local function AddSpellTokens(kind, tokens, dest)
	local map = addon.GetEnabledSpellMap and addon.GetEnabledSpellMap(kind)
	if type(map) ~= "table" or type(tokens) ~= "table" then
		return 0, 0
	end
	local count = 0
	local added = 0
	for spellID in pairs(map) do
		for i = 1, #tokens do
			count = count + 1
			if TryAddAuraSound(spellID, tokens[i], dest) then
				added = added + 1
			end
		end
	end
	return count, added
end

local unlockRetry

local function EnsureUnlockRetry()
	if unlockRetry then
		return unlockRetry
	end
	unlockRetry = CreateFrame("Frame")
	unlockRetry:SetScript("OnEvent", function(self)
		if AuraSoundsLocked() then
			return
		end
		self:UnregisterAllEvents()
		addon.RegisterAuraSounds()
	end)
	return unlockRetry
end

local function DeferAuraSounds(reason)
	if not pendingRegister then
		addon.Debug("AddAuraSound deferred;", reason or "restricted")
	end
	pendingRegister = true
	local frame = EnsureUnlockRetry()
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function addon.RegisterAuraSounds()
	if AuraSoundsLocked() then
		DeferAuraSounds("combat")
		return
	end
	pendingRegister = false
	local db = addon.db
	local function drop()
		ClearAuraSounds()
	end
	if not db or not db.enabled or not addon.ClassAllowed() then
		drop()
		return
	end
	if db.healerOnly and not addon.IsHealerSpec() then
		drop()
		return
	end
	local wantFocus = db.focusSound == true and db.watchFocus == true
	local wantRaid = db.raidSound == true and db.watchRaid == true
	local wantParty = db.partySound == true and db.watchParty == true
	if not wantFocus and not wantRaid and not wantParty then
		drop()
		return
	end
	local media = addon.ResolveSound()
	if not media or media.kind == "none" then
		drop()
		return
	end
	if media.kind ~= "file" and media.kind ~= "fileid" and not media.path then
		addon.Debug("AddAuraSound skipped; sound has no file")
		drop()
		return
	end
	-- Raid tokens in a raid, party tokens in a 5-man. Register both while
	-- solo so the first pull is already covered. Skip the other set in a
	-- group so party1-4 and raidN do not double-fire for the same person.
	local inRaid = IsInRaid and IsInRaid()
	local inGroup = IsInGroup and IsInGroup()
	local count = 0
	local added = 0
	local newIDs = {}
	local function take(n, ok)
		count = count + n
		added = added + ok
	end
	if wantFocus then
		take(AddSpellTokens("focus", FOCUS_TOKENS, newIDs))
	end
	if wantParty and not inRaid then
		local tokens = PARTY_TOKENS
		if addon.IsWatchSelf and addon.IsWatchSelf() then
			tokens = PLAYER_PARTY_TOKENS
		end
		take(AddSpellTokens("party", tokens, newIDs))
	end
	if wantRaid and (not inGroup or inRaid) then
		take(AddSpellTokens("raid", RAID_TOKENS, newIDs))
	end
	if count > 0 and added == 0 then
		if #auraSoundIDs > 0 then
			addon.Debug("AddAuraSound failed; keeping", #auraSoundIDs, "existing aura sounds")
		end
		DeferAuraSounds("add failed")
		return
	end
	-- Replace only after new adds succeeded, or when there is nothing to watch.
	ClearAuraSounds()
	for i = 1, #newIDs do
		auraSoundIDs[i] = newIDs[i]
	end
	addon.Debug("Registered", #auraSoundIDs, "aura sounds from", count, "spell-unit pairs")
end

function addon.QueueRegisterAuraSounds()
	if queued then
		return
	end
	queued = true
	C_Timer.After(0.15, function()
		queued = false
		addon.RegisterAuraSounds()
	end)
end

function addon.ResolveSoundPresets()
	local kits = SOUNDKIT
	local list = addon.SOUND_PRESETS
	if type(list) ~= "table" then
		return
	end
	for i = 1, #list do
		local preset = list[i]
		if kits and preset.key and type(kits[preset.key]) == "number" then
			preset.id = kits[preset.key]
		end
	end
end

function addon.PlayAlertSound()
	addon.PlaySoundByID()
end

local function WatchSharedMedia()
	if lsmCallbacks then
		return
	end
	local lsm = GetLSM()
	if not lsm or not lsm.RegisterCallback then
		return
	end
	lsmCallbacks = {}
	lsm.RegisterCallback(lsmCallbacks, "LibSharedMedia_Registered", function(_, mediatype)
		if mediatype == SOUND_MEDIA then
			addon.Fire("SOUND_MEDIA")
		end
	end)
end

addon.On("LOGIN", function()
	addon.ResolveSoundPresets()
	WatchSharedMedia()
	addon.QueueRegisterAuraSounds()
end)
addon.On("ACTIVATE", addon.QueueRegisterAuraSounds)
addon.On("DEACTIVATE", addon.RegisterAuraSounds)
addon.On("POLICY", addon.QueueRegisterAuraSounds)
addon.On("ROSTER", addon.QueueRegisterAuraSounds)
addon.On("COMBAT_END", addon.QueueRegisterAuraSounds)
addon.On("SOUND_MEDIA", addon.QueueRegisterAuraSounds)
