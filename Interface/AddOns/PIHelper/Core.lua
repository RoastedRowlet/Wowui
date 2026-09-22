--[[
	PI Helper core: saved variables, priest/healer gating, Power Infusion
	cooldown policy, and event dispatch. Non-priests stay idle unless
	loadForAllClasses is on; that opt-in is account-wide.

	Midnight notes:
	- Unit aura data is secret in combat / M+ / encounters. This addon never
	  reads UnitAura or AuraButton visibility. One AuraContainer per DPS cell
	  shows its button while a watched buff is up. SetEnabled turns them off
	  after PI (if onlyWhenPIReady) and for everyone except a group focus.
	- C_Spell.GetSpellCooldown remaining is SecretWhenCooldownsRestricted
	  (combat / encounter / M+). Do not read duration / startTime / modRate.
	  isActive is NeverSecret: after PI, lock glows for 120 seconds as a
	  fallback, then after 100s poll isActive while locked so Voidbound CDR
	  can drop the lock early (max ~9s saved). Own
	  UNIT_SPELLCAST_SUCCEEDED for PI is readable
	  (RegisterUnitEvent on player so party/raid secret payloads never
	  arrive). Clear the lock on CHALLENGE_MODE_START (M+ key start) and
	  raid ENCOUNTER_END (kill or wipe). The lock end is saved as
	  GetServerTime() so /reload can re-arm it; GetTime() is session-relative
	  and would be wrong.
	- Debug is slash-only.
]]

local ADDON_NAME, addon = ...

local PI_SPELL_ID = addon.PI_SPELL_ID
local DEFAULTS = addon.DEFAULTS
local PI_DEFAULT_CD = 120
-- Voidbound saves at most ~9s on PI, so 100s is still on cooldown. Also
-- avoids a false "off cooldown" right after UNIT_SPELLCAST_SUCCEEDED.
local PI_CD_SETTLE = 100

local db
local eventFrame
local isPriest
local policyQueued
local piReadyTimer
local piCdEndsAt
local piLockExpires
local piLockReleased
local piCdSettleTimer
local piCdPollTicker
local piLockAllowReadyCheck
local cachedFocusFriendly = false
local cachedFocusGUID = nil
local groupGUIDs = {}

addon.listeners = {}

local runtimeOn = false
local classRuntimeStarted = false
local spellMapCache = {}
local filterCache = {}

local ACTIVE_EVENTS = {
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"ADDON_RESTRICTION_STATE_CHANGED",
	"GROUP_ROSTER_UPDATE",
	"PLAYER_FOCUS_CHANGED",
	"PLAYER_ROLES_ASSIGNED",
	"ENCOUNTER_END",
	"CHALLENGE_MODE_START",
}

local PRIEST_IDLE_EVENTS = {
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
}

local function IsSecret(value)
	return issecretvalue and issecretvalue(value)
end

function addon.FrameIsForbidden(frame)
	if not frame or not frame.IsForbidden then
		return false
	end
	local ok, value = pcall(frame.IsForbidden, frame)
	if not ok or IsSecret(value) then
		return true
	end
	return value == true
end

function addon.Call(object, method, ...)
	if not object then
		return false
	end
	local fn = object[method]
	if type(fn) ~= "function" then
		return false
	end
	local ok, a, b, c = pcall(fn, object, ...)
	if ok then
		return true, a, b, c
	end
	return false
end

function addon.SafeUnitIsUnit(a, b)
	if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then
		return false
	end
	if a == b then
		return true
	end
	local ok, matched = pcall(UnitIsUnit, a, b)
	if not ok or IsSecret(matched) then
		return false
	end
	return matched == true
end

local function SetEvents(frame, events, enabled)
	for i = 1, #events do
		if enabled then
			frame:RegisterEvent(events[i])
		else
			frame:UnregisterEvent(events[i])
		end
	end
end

-- Player-only. RegisterEvent would deliver party/raid casts whose payload is
-- SecretWhenUnitSpellCastRestricted; comparing those unit/spellID values errors.
local function SetPlayerCastEvent(frame, enabled)
	if enabled then
		frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	else
		frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	end
end

-- Same rule as casts: PLAYER_SPECIALIZATION_CHANGED is a unit event. RegisterEvent
-- delivers party/raid spec changes whose unit token is secret in combat / M+.
local function SetPlayerSpecEvent(frame, enabled)
	if enabled then
		frame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
	else
		frame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	end
end

local function CopyDefaults(src, dest)
	if type(src) ~= "table" then
		return {}
	end
	if type(dest) ~= "table" then
		dest = {}
	end
	for key, value in pairs(src) do
		if type(value) == "table" then
			dest[key] = CopyDefaults(value, dest[key])
		elseif dest[key] == nil then
			dest[key] = value
		end
	end
	return dest
end

function addon.On(event, fn)
	local list = addon.listeners[event]
	if not list then
		list = {}
		addon.listeners[event] = list
	end
	list[#list + 1] = fn
end

function addon.Fire(event, ...)
	local list = addon.listeners[event]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](...)
	end
end

function addon.IsSecret(value)
	return IsSecret(value)
end

function addon.SafeNumber(value, fallback)
	if type(value) ~= "number" or IsSecret(value) then
		return fallback or 0
	end
	return value
end

function addon.SafeString(value)
	if type(value) ~= "string" or IsSecret(value) then
		return nil
	end
	return value
end

-- nil if missing or secret. Never compare or boolean-test a value until this
-- returns a plain boolean; secret booleans error on `if` / `==` / `not`.
local function PlainBool(value)
	if type(value) ~= "boolean" or IsSecret(value) then
		return nil
	end
	return value
end

function addon.PlainBool(value)
	return PlainBool(value)
end

-- true / false, or nil when UnitExists is secret.
function addon.SafeUnitExists(unit)
	if type(unit) ~= "string" or unit == "" then
		return nil
	end
	return PlainBool(UnitExists(unit))
end

-- Current restriction state only. C_Secrets.HasSecretRestrictions is a build
-- flag (always true on Midnight) and must not be treated as "in combat".
local function RestrictionActive(restrictionType)
	if restrictionType == nil then
		return false
	end
	local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, restrictionType)
	return ok and PlainBool(active) == true
end

function addon.IsRestricted()
	local types = Enum.AddOnRestrictionType
	if types then
		if RestrictionActive(types.Combat)
			or RestrictionActive(types.Encounter)
			or RestrictionActive(types.ChallengeMode)
			or RestrictionActive(types.PvPMatch)
			or RestrictionActive(types.Map)
		then
			return true
		end
	end
	return InCombatLockdown()
end

function addon.IsActive()
	return runtimeOn
end

function addon.InCombat()
	if InCombatLockdown() then
		return true
	end
	if UnitAffectingCombat then
		local affecting = PlainBool(UnitAffectingCombat("player"))
		if affecting ~= nil then
			return affecting
		end
	end
	return false
end

function addon.IsPriest()
	return isPriest == true
end

-- Priests always; other classes only with the General opt-in.
function addon.ClassAllowed()
	if isPriest == true then
		return true
	end
	return db and db.loadForAllClasses == true
end

function addon.PlainGUID(value)
	if type(value) ~= "string" or IsSecret(value) then
		return nil
	end
	return value
end

local PlainGUID = addon.PlainGUID

local unitNameCache = {}
local trackNameKeySet = {}

function addon.NormalizeName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = strtrim(name)
	if name == "" then
		return nil
	end
	name = name:gsub(" ", "")
	if name == "" then
		return nil
	end
	return strlower(name)
end

function addon.NameKeys(name, realm)
	local keys = {}
	local short = addon.NormalizeName(name)
	if not short then
		return keys
	end
	keys[short] = true
	realm = addon.SafeString(realm)
	if type(realm) == "string" and realm ~= "" then
		keys[short .. "-" .. strlower(strtrim(realm))] = true
	end
	local dashed = short:match("^(.-)%-(.+)$")
	if dashed then
		keys[dashed] = true
	end
	return keys
end

function addon.GetUnitNameKeys(unit)
	if type(unit) ~= "string" or unit == "" then
		return nil
	end
	local guid = PlainGUID(UnitGUID(unit))
	local name, realm = UnitName(unit)
	name = addon.SafeString(name)
	realm = addon.SafeString(realm)
	if not name then
		name, realm = UnitFullName(unit)
		name = addon.SafeString(name)
		realm = addon.SafeString(realm)
	end
	if name then
		local keys = addon.NameKeys(name, realm)
		if guid then
			unitNameCache[guid] = keys
		end
		return keys
	end
	if guid then
		return unitNameCache[guid]
	end
	return nil
end

function addon.UnitMatchesNameSet(unit, listed)
	if type(listed) ~= "table" or not next(listed) then
		return false
	end
	local keys = addon.GetUnitNameKeys(unit)
	if not keys then
		return false
	end
	for key in pairs(keys) do
		if listed[key] then
			return true
		end
	end
	return false
end

function addon.AddUniqueName(names, text)
	if type(names) ~= "table" then
		return false
	end
	local name = strtrim(text or "")
	if name == "" then
		return false
	end
	local needle = addon.NormalizeName(name)
	if not needle then
		return false
	end
	for i = 1, #names do
		if addon.NormalizeName(names[i]) == needle then
			return false
		end
	end
	names[#names + 1] = name
	return true
end

function addon.RebuildTrackNameKeySet()
	wipe(trackNameKeySet)
	local names = db and db.trackNames
	if type(names) ~= "table" then
		return
	end
	for i = 1, #names do
		local keys = addon.NameKeys(names[i])
		for key in pairs(keys) do
			trackNameKeySet[key] = true
		end
	end
end

function addon.UnitMatchesTrackNames(unit)
	return addon.UnitMatchesNameSet(unit, trackNameKeySet)
end

function addon.GetTrackPlayerMode(kind)
	if not db then
		return "all"
	end
	if kind == "raid" then
		return db.trackRaidMode == "listed" and "listed" or "all"
	end
	if kind == "party" then
		return db.trackPartyMode == "listed" and "listed" or "all"
	end
	return "all"
end

local function RefreshGroupGUIDCache()
	local found = {}
	local any = false
	local function consider(unit)
		if addon.SafeUnitExists(unit) == false then
			return
		end
		local guid = PlainGUID(UnitGUID(unit))
		if guid then
			found[guid] = true
			any = true
		end
	end
	consider("player")
	for i = 1, 40 do
		consider("raid" .. i)
	end
	for i = 1, 4 do
		consider("party" .. i)
	end
	if any then
		groupGUIDs = found
		for guid in pairs(unitNameCache) do
			if not found[guid] then
				unitNameCache[guid] = nil
			end
		end
	end
end

local function ReadFocusGUID()
	if addon.SafeUnitExists("focus") == false then
		return nil
	end
	return PlainGUID(UnitGUID("focus"))
end

-- true / false, or nil when combat secrets hide the answer.
local function ComputeFriendlyPlayerFocus()
	local exists = addon.SafeUnitExists("focus")
	if exists == nil then
		return nil, nil
	end
	if not exists then
		return false, nil
	end
	local guid = ReadFocusGUID()
	local isPlayer = PlainBool(UnitIsPlayer("focus"))
	if isPlayer == nil then
		return nil, guid
	end
	if not isPlayer then
		return false, guid
	end
	if UnitCanAttack then
		local attack = PlainBool(UnitCanAttack("player", "focus"))
		if attack == nil then
			return nil, guid
		end
		if attack then
			return false, guid
		end
	end
	if UnitIsEnemy then
		local enemy = PlainBool(UnitIsEnemy("player", "focus"))
		if enemy == nil then
			return nil, guid
		end
		if enemy then
			return false, guid
		end
	end
	return true, guid
end

local function ClearFocusCache()
	cachedFocusFriendly = false
	cachedFocusGUID = nil
end

local function FocusUnitPresent()
	return addon.SafeUnitExists("focus")
end

local function RefreshFocusCache()
	if FocusUnitPresent() == false then
		ClearFocusCache()
		return
	end
	local friendly, guid = ComputeFriendlyPlayerFocus()
	if friendly == false then
		cachedFocusFriendly = false
		cachedFocusGUID = guid
		return
	end
	-- New focus is fully secret: do not keep the previous person.
	if friendly == nil and not guid then
		ClearFocusCache()
		return
	end
	if guid and cachedFocusGUID and guid ~= cachedFocusGUID and friendly == nil then
		cachedFocusFriendly = groupGUIDs[guid] == true
	end
	if guid then
		cachedFocusGUID = guid
	end
	if friendly == true then
		cachedFocusFriendly = true
	elseif friendly == nil and guid and groupGUIDs[guid] then
		cachedFocusFriendly = true
	end
end

local focusSyncGen = 0

local function SyncFocus()
	RefreshFocusCache()
	addon.Fire("FOCUS")
end

local function QueueFocusSync()
	SyncFocus()
	focusSyncGen = focusSyncGen + 1
	local gen = focusSyncGen
	C_Timer.After(0, function()
		if gen ~= focusSyncGen then
			return
		end
		SyncFocus()
	end)
end

function addon.HasFriendlyPlayerFocus()
	if FocusUnitPresent() == false then
		return false
	end
	return cachedFocusFriendly == true
end

function addon.HasGroupFocus()
	if FocusUnitPresent() == false then
		return false
	end
	local guid = cachedFocusGUID
	if not guid then
		return false
	end
	return groupGUIDs[guid] == true
end

function addon.UnitIsFocus(unit)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	if FocusUnitPresent() == false then
		return false
	end
	if unit == "focus" then
		return FocusUnitPresent() == true
	end
	if addon.SafeUnitIsUnit(unit, "focus") then
		return true
	end
	local guid = PlainGUID(UnitGUID(unit))
	if not guid then
		return false
	end
	local focusGuid = cachedFocusGUID or ReadFocusGUID()
	return focusGuid ~= nil and guid == focusGuid
end

function addon.IsHealerSpec()
	local specIndex = C_SpecializationInfo.GetSpecialization()
	if type(specIndex) ~= "number" or IsSecret(specIndex) then
		return false
	end
	local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
	if type(specID) ~= "number" or IsSecret(specID) then
		return false
	end
	return addon.HEALER_SPEC_IDS[specID] == true
end

local function PIGrace()
	local grace = db and db.piGrace or 0
	if type(grace) ~= "number" then
		return 0
	end
	if grace < 0 then
		return 0
	end
	if grace > 15 then
		return 15
	end
	return grace
end

-- After our own PI cast, hide glows until this lock expires. Do not read
-- GetSpellCooldown remaining. The live countdown is GetTime() (fractional).
-- Saved expiry is GetServerTime() so a /reload can restore remaining; that
-- conversion happens only when there is no live session timer.
-- isActive is NeverSecret, so we can still notice when the CD actually ends
-- (M+ Voidbound CDR) and drop the lock early.
local function WallClock()
	if GetServerTime then
		return GetServerTime()
	end
	return time()
end

local function PlayerLockKey()
	local name = addon.SafeString(UnitName("player"))
	if not name then
		return nil
	end
	local realm = addon.SafeString(GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName())
	if realm then
		return name .. "-" .. realm
	end
	return name
end

local function PersistPILock()
	if not db then
		return
	end
	if not piLockExpires or (piLockExpires - WallClock()) <= 1.5 then
		db.piLockExpires = nil
		db.piLockChar = nil
		return
	end
	local key = PlayerLockKey()
	if not key then
		return
	end
	db.piLockExpires = piLockExpires
	db.piLockChar = key
end

local function CancelPIReadyTimer()
	if piReadyTimer then
		piReadyTimer:Cancel()
		piReadyTimer = nil
	end
end

-- Poll GetSpellCooldown().isActive while locked. Never read duration,
-- startTime, or modRate; those are secret in combat / M+.
local function StopPICooldownWatch()
	if piCdSettleTimer then
		piCdSettleTimer:Cancel()
		piCdSettleTimer = nil
	end
	if piCdPollTicker then
		piCdPollTicker:Cancel()
		piCdPollTicker = nil
	end
	piLockAllowReadyCheck = nil
end

local function ClearPILock()
	CancelPIReadyTimer()
	StopPICooldownWatch()
	piCdEndsAt = nil
	piLockExpires = nil
	piLockReleased = nil
	PersistPILock()
end

local function SchedulePILockTimer()
	CancelPIReadyTimer()
	piLockReleased = nil
	if not piCdEndsAt then
		return
	end
	local wait = (piCdEndsAt - GetTime()) - PIGrace()
	if wait <= 0 then
		return
	end
	piReadyTimer = C_Timer.NewTimer(wait, function()
		piReadyTimer = nil
		piLockReleased = true
		addon.QueuePolicy()
	end)
end

-- true / false, or nil when the API is missing or isActive is unusable.
local function IsPISpellCooldownActive()
	if not C_Spell or not C_Spell.GetSpellCooldown then
		return nil
	end
	local ok, info = pcall(C_Spell.GetSpellCooldown, PI_SPELL_ID)
	if not ok or type(info) ~= "table" then
		return nil
	end
	local isActive = info.isActive
	if type(isActive) ~= "boolean" or IsSecret(isActive) then
		return nil
	end
	return isActive
end

local function ReleaseIfPICooldownDone()
	if not piCdEndsAt or not piLockAllowReadyCheck then
		return
	end
	if IsPISpellCooldownActive() ~= false then
		return
	end
	addon.Debug("PI cooldown finished before static lock")
	ClearPILock()
	addon.QueuePolicy()
end

local function BeginPICooldownWatch()
	piLockAllowReadyCheck = true
	if piCdPollTicker then
		piCdPollTicker:Cancel()
	end
	piCdPollTicker = C_Timer.NewTicker(1, ReleaseIfPICooldownDone)
	ReleaseIfPICooldownDone()
end

-- Fresh casts wait 100s; Voidbound cannot finish PI before then. A restored
-- lock can check immediately: if CDR already finished PI, drop it.
local function StartPICooldownWatch(immediate)
	StopPICooldownWatch()
	if immediate then
		BeginPICooldownWatch()
		return
	end
	piCdSettleTimer = C_Timer.NewTimer(PI_CD_SETTLE, function()
		piCdSettleTimer = nil
		if not piCdEndsAt then
			return
		end
		BeginPICooldownWatch()
	end)
end

-- duration: seconds remaining on this session's GetTime() clock.
-- expires: optional GetServerTime() deadline from a saved lock; omit on a
-- fresh PI cast so we snapshot both clocks once.
local function ArmPILock(duration, expires)
	if type(duration) ~= "number" or duration <= 1.5 then
		ClearPILock()
		return
	end
	CancelPIReadyTimer()
	piLockReleased = nil
	piCdEndsAt = GetTime() + duration
	if type(expires) == "number" then
		piLockExpires = expires
	else
		piLockExpires = WallClock() + duration
	end
	PersistPILock()
	SchedulePILockTimer()
	StartPICooldownWatch(type(expires) == "number")
end

local function RestorePILock()
	if piCdEndsAt then
		return
	end
	if not db then
		return
	end
	local expires = db.piLockExpires
	local char = db.piLockChar
	local key = PlayerLockKey()
	if type(expires) ~= "number" or type(char) ~= "string" or not key or char ~= key then
		return
	end
	local remaining = expires - WallClock()
	if remaining > 1.5 then
		ArmPILock(remaining, expires)
	else
		ClearPILock()
	end
end

-- Re-arm the grace timer when grace changes; do not rebase the CD end.
local function RefreshPILock()
	if not piCdEndsAt then
		return
	end
	SchedulePILockTimer()
end

function addon.IsPIReady()
	if piLockReleased then
		return true
	end
	if piCdEndsAt then
		return (piCdEndsAt - GetTime()) <= PIGrace()
	end
	-- No lock this session (login with no saved lock, or a known CD reset).
	return true
end

function addon.IsAlertsAllowed()
	if not db or not db.enabled then
		return false
	end
	if not addon.ClassAllowed() then
		return false
	end
	if db.healerOnly and not addon.IsHealerSpec() and not addon.IsWatchSelf() then
		return false
	end
	if db.onlyWhenPIReady and not addon.IsPIReady() then
		return false
	end
	return true
end

function addon.IsWatchSelf()
	return db and db.watchSelf == true and addon.IsDebugEnabled and addon.IsDebugEnabled()
end

-- Raid instances (and raid groups in the world) vs dungeons/M+. A 5-man
-- raid group in a dungeon still counts as dungeon tracking.
function addon.WatchContentKind()
	local instanceType
	if GetInstanceInfo then
		instanceType = select(2, GetInstanceInfo())
	end
	if addon.IsSecret(instanceType) or type(instanceType) ~= "string" then
		instanceType = nil
	end
	if instanceType == "raid" then
		return "raid"
	end
	if instanceType == "party" then
		return "party"
	end
	if IsInRaid and IsInRaid() then
		return "raid"
	end
	if IsInGroup and IsInGroup() then
		return "party"
	end
	return nil
end

-- Track cooldowns with no glow/alert/duration/sound is a no-op. Require at
-- least one output so we do not scan units for a context that shows nothing.

function addon.ContextHasOutput(kind)
	if not db then
		return false
	end
	if kind == "raid" then
		return db.alertRaid == true or db.glowRaid == true or db.durationRaid == true or db.raidSound == true
	end
	if kind == "party" then
		return db.alertParty == true or db.glowParty == true or db.durationParty == true or db.partySound == true
	end
	if kind == "focus" then
		return db.alertFocus == true or db.glowFocus == true or db.focusSound == true
	end
	return false
end

function addon.ContextIsWatching(kind)
	if not db then
		return false
	end
	if kind == "raid" then
		return db.watchRaid == true and addon.ContextHasOutput("raid")
	end
	if kind == "party" then
		return db.watchParty == true and addon.ContextHasOutput("party")
	end
	if kind == "focus" then
		return db.watchFocus == true and addon.ContextHasOutput("focus")
	end
	return false
end

function addon.NormalizeContextWatch(target)
	target = target or db
	if not target then
		return
	end
	if target.watchRaid == true and not (target.alertRaid == true or target.glowRaid == true or target.durationRaid == true or target.raidSound == true) then
		target.watchRaid = false
	end
	if target.watchParty == true and not (target.alertParty == true or target.glowParty == true or target.durationParty == true or target.partySound == true) then
		target.watchParty = false
	end
	if target.watchFocus == true and not (target.alertFocus == true or target.glowFocus == true or target.focusSound == true) then
		target.watchFocus = false
	end
end

function addon.SyncAlertSource()
	if not db then
		return
	end
	local tracked = (db.watchRaid == true and db.alertRaid == true) or (db.watchParty == true and db.alertParty == true)
	local focus = db.watchFocus == true and db.alertFocus == true
	local whisper = db.alertWhisper == true
	db.alertTracked = tracked
	if (tracked or focus) and whisper then
		db.alertSource = "all"
	elseif tracked or focus then
		db.alertSource = "focus"
	elseif whisper then
		db.alertSource = "whisper"
	else
		db.alertSource = "none"
	end
	db.whisperAlertEnabled = whisper
	db.alertEnabled = tracked or focus or whisper
end

function addon.AlertShowsTracked()
	if not db then
		return false
	end
	local content = addon.WatchContentKind and addon.WatchContentKind()
	if content == "raid" then
		return db.watchRaid == true and db.alertRaid == true
	end
	if content == "party" then
		return db.watchParty == true and db.alertParty == true
	end
	return false
end

function addon.AlertShowsFocus()
	return db and db.watchFocus == true and db.alertFocus == true
end

function addon.AlertShowsWhisper()
	return db and db.alertWhisper == true
end

function addon.AlertShowsSelf()
	return addon.IsWatchSelf() == true
end

function addon.IsGlowAllowed()
	if not db or not db.enabled then
		return false
	end
	if not addon.ClassAllowed() then
		return false
	end
	if db.healerOnly and not addon.IsHealerSpec() and not addon.IsWatchSelf() then
		return false
	end
	if db.onlyWhenPIReady and not addon.IsPIReady() then
		return false
	end
	return true
end

function addon.SpellScopeEnabled()
	return db and db.perBuffScope == true
end

function addon.GetSpellScope(spellID)
	if type(spellID) ~= "number" or not db then
		return { raid = true, party = true, focus = true }
	end
	local persist = addon.SpellScopeEnabled()
	if persist and type(db.spellScope) ~= "table" then
		db.spellScope = {}
	end
	local scope = db.spellScope and db.spellScope[spellID]
	if type(scope) ~= "table" then
		scope = { raid = true, party = true, focus = true }
		if persist then
			db.spellScope[spellID] = scope
		end
		return scope
	end
	if scope.raid == nil then
		scope.raid = true
	end
	if scope.party == nil then
		scope.party = true
	end
	if scope.focus == nil then
		scope.focus = true
	end
	return scope
end

local function SpellAllowedForKind(spellID, kind)
	if not kind or kind == "all" then
		return true
	end
	if not addon.SpellScopeEnabled() then
		return true
	end
	return addon.GetSpellScope(spellID)[kind] ~= false
end

function addon.InvalidateSpellMaps()
	wipe(spellMapCache)
	wipe(filterCache)
end

function addon.GetEnabledSpellMap(kind)
	if not kind then
		kind = "all"
	end
	if not db then
		return {}
	end
	local cached = spellMapCache[kind]
	if cached then
		return cached
	end
	local map = {}
	spellMapCache[kind] = map
	local spells = addon.DEFAULT_SPELLS
	local enabled = db.spellEnabled or {}
	for i = 1, #spells do
		local spell = spells[i]
		local on = enabled[spell.spellID]
		if on == nil then
			on = not spell.isPotion
		end
		if on and SpellAllowedForKind(spell.spellID, kind) then
			map[spell.spellID] = true
		end
	end
	local custom = db.customSpells or {}
	for i = 1, #custom do
		local extra = custom[i]
		if extra and extra.enabled ~= false then
			local spellID = extra.spellID
			if type(spellID) == "string" then
				spellID = tonumber(spellID)
			end
			if type(spellID) == "number" then
				spellID = math.floor(spellID)
				if spellID > 0 and SpellAllowedForKind(spellID, kind) then
					map[spellID] = true
				end
			end
		end
	end
	return map
end

function addon.GetAuraCandidateFilters(kind)
	if not kind or kind == "all" then
		kind = "all"
	end
	if not db then
		return { includeSpellIDs = {} }
	end
	local cached = filterCache[kind]
	if cached then
		return cached
	end
	cached = { includeSpellIDs = addon.GetEnabledSpellMap(kind) }
	filterCache[kind] = cached
	return cached
end

function addon.HasAuraSpellFilters()
	return next(addon.GetEnabledSpellMap("all")) ~= nil
end

function addon.GetGlowColor()
	if not db then
		return 234 / 255, 162 / 255, 33 / 255, 0.90
	end
	local a = db.glowA
	if type(a) ~= "number" then
		a = 0.90
	elseif a < 0.05 then
		a = 0.05
	elseif a > 1 then
		a = 1
	end
	return db.glowR, db.glowG, db.glowB, a
end

function addon.GetAlertGlowColor()
	if not db then
		return addon.GetGlowColor()
	end
	if db.alertGlowR == nil then
		return addon.GetGlowColor()
	end
	local a = db.alertGlowA
	if type(a) ~= "number" then
		a = 0.90
	elseif a < 0.05 then
		a = 0.05
	elseif a > 1 then
		a = 1
	end
	return db.alertGlowR, db.alertGlowG, db.alertGlowB, a
end

function addon.RefreshPolicy()
	policyQueued = false
	addon.Fire("POLICY")
end

function addon.QueuePolicy()
	if policyQueued then
		return
	end
	policyQueued = true
	C_Timer.After(0.05, addon.RefreshPolicy)
end

local function StartClassRuntime()
	if classRuntimeStarted then
		return
	end
	if not addon.ClassAllowed() then
		return
	end
	classRuntimeStarted = true
	SetEvents(eventFrame, PRIEST_IDLE_EVENTS, true)
	SetPlayerSpecEvent(eventFrame, true)
	addon.Fire("LOADED")
end

function addon.SyncRuntime()
	local allowed = addon.ClassAllowed()
	local firstStart = not classRuntimeStarted and allowed
	if allowed then
		StartClassRuntime()
	elseif not isPriest then
		SetEvents(eventFrame, PRIEST_IDLE_EVENTS, false)
		SetPlayerSpecEvent(eventFrame, false)
	end

	local want = allowed and db and db.enabled == true
	if want and not runtimeOn then
		runtimeOn = true
		SetEvents(eventFrame, ACTIVE_EVENTS, true)
		if isPriest then
			SetPlayerCastEvent(eventFrame, true)
		end
		RefreshGroupGUIDCache()
		RefreshFocusCache()
		addon.Fire("ACTIVATE")
	elseif runtimeOn and not want then
		runtimeOn = false
		SetEvents(eventFrame, ACTIVE_EVENTS, false)
		SetPlayerCastEvent(eventFrame, false)
		ClearPILock()
		addon.Fire("DEACTIVATE")
	end

	-- Enabling loadForAllClasses after login never gets PLAYER_LOGIN.
	if firstStart then
		local loggedIn = PlainBool(IsLoggedIn and IsLoggedIn())
		if loggedIn == true then
			RefreshGroupGUIDCache()
			RefreshFocusCache()
			addon.Fire("LOGIN")
			if runtimeOn then
				RestorePILock()
				addon.QueuePolicy()
			end
		end
	end
end

-- Glow/alert sliders: retint existing holders. No spell-map invalidation,
-- attach, or aura-sound re-register.
local function ApplyPaintSettings()
	if addon.RefreshContainerGlows then
		addon.RefreshContainerGlows(true)
	end
	if addon.RefreshAlertGlows then
		addon.RefreshAlertGlows()
	end
	if addon.RefreshAlerts then
		addon.RefreshAlerts()
	end
	if addon.RefreshTestPreviews then
		addon.RefreshTestPreviews()
	end
	if addon.LayoutAlertAnchor then
		addon.LayoutAlertAnchor()
	end
end

-- mode: nil/"full" rebuilds tracking. "paint" is glow/alert visuals.
-- "grace" only re-arms the PI lock and refreshes ready-state.
function addon.ApplySettings(mode)
	if mode == "paint" then
		ApplyPaintSettings()
		return
	end
	if mode == "grace" then
		RefreshPILock()
		addon.QueuePolicy()
		return
	end
	addon.InvalidateSpellMaps()
	addon.RebuildTrackNameKeySet()
	addon.SyncRuntime()
	RefreshPILock()
	addon.QueuePolicy()
	if addon.ApplySpellFilters then
		addon.ApplySpellFilters()
	end
	if addon.RefreshContainerGlows then
		addon.RefreshContainerGlows()
	end
	if addon.QueueAttach then
		addon.QueueAttach()
	end
	if addon.RefreshAlerts then
		addon.RefreshAlerts()
	end
	if addon.RefreshAlertGlows then
		addon.RefreshAlertGlows()
	end
	if addon.RefreshTestPreviews then
		addon.RefreshTestPreviews()
	end
	if addon.RefreshWhisperDisplay then
		addon.RefreshWhisperDisplay()
	end
	if addon.LayoutAlertAnchor then
		addon.LayoutAlertAnchor()
	end
	if addon.QueueRegisterAuraSounds then
		addon.QueueRegisterAuraSounds()
	end
	if addon.RefreshFocusReminder then
		addon.RefreshFocusReminder()
	end
	if addon.SyncMinimap then
		addon.SyncMinimap()
	end
end

function addon.OnPowerInfusionCast()
	addon.Debug("Power Infusion cast detected")
	ArmPILock(PI_DEFAULT_CD)
	addon.Fire("PI_CAST")
	addon.QueuePolicy()
end

-- Raid boss kill/wipe resets CDs. Dungeon and M+ bosses also fire
-- ENCOUNTER_END (and ENCOUNTER_START on pull) but do not reset CDs.
-- difficultyID comes from the event; GetDifficultyInfo.groupType is "raid"
-- for raid difficulties and "party" for dungeons / mythic keystone (8).
local function EncounterEndResetsCooldowns(difficultyID)
	if type(difficultyID) ~= "number" or IsSecret(difficultyID) then
		return false
	end
	if not GetDifficultyInfo then
		return false
	end
	local ok, _, groupType, _, isChallengeMode = pcall(GetDifficultyInfo, difficultyID)
	if not ok then
		return false
	end
	if PlainBool(isChallengeMode) == true then
		return false
	end
	if IsSecret(groupType) or type(groupType) ~= "string" then
		return false
	end
	return groupType == "raid"
end

local function OnCooldownReset(reason, extra)
	addon.Debug("Cooldown reset", reason, extra)
	ClearPILock()
	addon.QueuePolicy()
end

local function InitDB()
	if type(PIHelperDB) ~= "table" then
		PIHelperDB = {}
	end
	if PIHelperDB.alertSource == nil then
		local focusOn = PIHelperDB.alertEnabled ~= false
		local whisperOn
		if PIHelperDB.whisperAlertEnabled == nil then
			whisperOn = PIHelperDB.alertEnabled ~= false
		else
			whisperOn = PIHelperDB.whisperAlertEnabled ~= false
		end
		if focusOn and whisperOn then
			PIHelperDB.alertSource = "all"
		elseif focusOn then
			PIHelperDB.alertSource = "focus"
		elseif whisperOn then
			PIHelperDB.alertSource = "whisper"
			PIHelperDB.alertEnabled = true
		else
			PIHelperDB.alertSource = "all"
		end
	end
	if PIHelperDB.whisperAlertEnabled == nil then
		PIHelperDB.whisperAlertEnabled = PIHelperDB.alertEnabled ~= false
	end
	if PIHelperDB.whisperRaidGlow == nil then
		PIHelperDB.whisperRaidGlow = true
	end
	if PIHelperDB.alertFocus == nil or PIHelperDB.alertWhisper == nil then
		local source = PIHelperDB.alertSource
		if source == "whisper" then
			PIHelperDB.alertFocus = false
			PIHelperDB.alertWhisper = true
		elseif source == "focus" then
			PIHelperDB.alertFocus = true
			PIHelperDB.alertWhisper = false
		elseif source == "none" then
			PIHelperDB.alertFocus = false
			PIHelperDB.alertWhisper = false
		else
			PIHelperDB.alertFocus = true
			PIHelperDB.alertWhisper = true
		end
	end
	local savedSoundName = PIHelperDB.soundName
	db = CopyDefaults(DEFAULTS, PIHelperDB)
	if type(db.spellEnabled) ~= "table" then
		db.spellEnabled = {}
	end
	if type(db.customSpells) ~= "table" then
		db.customSpells = {}
	end
	if type(db.spellScope) ~= "table" then
		db.spellScope = {}
	end
	if type(db.whisperNames) ~= "table" then
		db.whisperNames = {}
	end
	if type(db.sequenceNames) ~= "table" then
		db.sequenceNames = {}
	end
	if type(db.trackNames) ~= "table" then
		db.trackNames = {}
	end
	if type(db.trackingCollapsed) ~= "table" then
		db.trackingCollapsed = {}
	end
	if type(db.cooldownCollapsed) ~= "table" then
		db.cooldownCollapsed = {}
	end
	if db.durationRaid == nil then
		db.durationRaid = false
	end
	if db.durationParty == nil then
		db.durationParty = false
	end
	if db.trackRaidMode ~= "listed" then
		db.trackRaidMode = "all"
	end
	if db.trackPartyMode ~= "listed" then
		db.trackPartyMode = "all"
	end
	if db.whisperNames == db.sequenceNames then
		db.sequenceNames = {}
	end
	if db.whisperMode ~= "listed" and db.whisperMode ~= "sequence" then
		db.whisperMode = db.whisperSequence and "sequence" or "listed"
	end
	db.whisperSequence = db.whisperMode == "sequence"
	-- Dominion of Argus replaced Tyrant's Oblation as the Demonology Tyrant tracker.
	if db.spellEnabled[1276166] == nil and db.spellEnabled[1276767] ~= nil then
		db.spellEnabled[1276166] = db.spellEnabled[1276767]
	end
	if db.spellScope[1276166] == nil and db.spellScope[1276767] ~= nil then
		db.spellScope[1276166] = db.spellScope[1276767]
	end
	db.spellEnabled[1276767] = nil
	db.spellScope[1276767] = nil
	local spells = addon.DEFAULT_SPELLS
	for i = 1, #spells do
		local spell = spells[i]
		local spellID = spell.spellID
		if db.spellEnabled[spellID] == nil then
			db.spellEnabled[spellID] = spell.isPotion ~= true
		end
	end
	if not db.potionRowsMigrated then
		if db.watchPotions ~= true then
			for i = 1, #spells do
				local spell = spells[i]
				if spell.isPotion then
					db.spellEnabled[spell.spellID] = false
				end
			end
		end
		db.potionRowsMigrated = true
	end
	if db.glowStyle ~= "starburst" and db.glowStyle ~= "border" and db.glowStyle ~= "fill" and db.glowStyle ~= "pixel" and db.glowStyle ~= "countdown" then
		db.glowStyle = "pixel"
	end
	if type(db.glowThickness) ~= "number" or db.glowThickness < 1 then
		db.glowThickness = 2
	elseif db.glowThickness > 6 then
		db.glowThickness = 6
	end
	if type(db.glowSpeed) ~= "number" or db.glowSpeed < 0.05 then
		db.glowSpeed = 1.5
	elseif db.glowSpeed > 5 then
		db.glowSpeed = 5
	end
	if type(db.glowPixelLines) ~= "number" then
		db.glowPixelLines = 10
	else
		db.glowPixelLines = math.max(4, math.min(16, math.floor(db.glowPixelLines + 0.5)))
	end
	if type(db.glowPixelLength) ~= "number" then
		db.glowPixelLength = 20
	else
		db.glowPixelLength = math.max(4, math.min(36, math.floor(db.glowPixelLength + 0.5)))
	end
	if db.glowBorderPulse == nil then
		db.glowBorderPulse = true
	end
	if not db.glowFocusMerged then
		if db.raidGlowEnabled == false and db.raidGlowFocus ~= false then
			db.raidGlowEnabled = true
		end
		db.glowFocusMerged = true
	end
	if db.contextAlertsMigrated ~= true then
		db.glowRaid = db.raidGlowEnabled ~= false
		db.glowParty = db.raidGlowEnabled ~= false
		db.glowFocus = db.raidGlowEnabled ~= false
		db.alertRaid = db.alertTracked == true
		db.alertParty = db.alertTracked == true
		db.contextAlertsMigrated = true
	end
	if db.contextSoundsMigrated ~= true then
		db.raidSound = false
		db.partySound = false
		db.contextSoundsMigrated = true
	end
	db.raidSound = db.raidSound == true
	db.partySound = db.partySound == true
	addon.NormalizeContextWatch(db)
	addon.SyncAlertSource()
	if db.alertGlowStyle ~= "none" and db.alertGlowStyle ~= "starburst" then
		db.alertGlowStyle = "starburst"
	end
	if db.alertGlow == false then
		db.alertGlowStyle = "none"
		db.alertGlow = true
	end
	if db.alertGlowR == nil then
		db.alertGlowR = db.glowR
		db.alertGlowG = db.glowG
		db.alertGlowB = db.glowB
		db.alertGlowA = db.glowA
	end
	local OLD_SOUND_PRESETS = {
		RAID_WARNING = true,
		READY_CHECK = true,
		AUCTION_WINDOW_OPEN = true,
		LEVEL_UP = true,
		UI_BONUS_LOOT_ROLL_START = true,
		ALARM_CLOCK_WARNING_2 = true,
		MAP_PING = true,
		UI_AUTO_QUEST_COMPLETE = true,
	}
	if type(savedSoundName) ~= "string" or savedSoundName == "" or OLD_SOUND_PRESETS[savedSoundName] then
		db.soundName = "ALARM_CLOCK_WARNING_3"
		db.soundKitID = 12889
	end
	if addon.ResolveSoundPresets then
		addon.ResolveSoundPresets()
	end
	if db.glowR == 0.95 and db.glowG == 0.82 and db.glowB == 0.18 then
		db.glowR = 234 / 255
		db.glowG = 162 / 255
		db.glowB = 33 / 255
	end
	PIHelperDB = db
	addon.db = db
	addon.RebuildTrackNameKeySet()
	RestorePILock()
end

local function DetectClass()
	local classFile
	if UnitClassBase then
		classFile = UnitClassBase("player")
	end
	if type(classFile) ~= "string" then
		local _, file = UnitClass("player")
		classFile = file
	end
	isPriest = classFile == "PRIEST"
	addon.isPriest = isPriest
end

local function PrintHelp()
	print("|cffeaa221PI Helper|r v" .. addon.VERSION)
	print("  |cffffff00/pih|r, |cffffff00/pihelper|r - open options")
	print("  |cffffff00/pih export|r - copy a shareable settings string")
	print("  |cffffff00/pih import|r - paste a settings string")
	print("  |cffffff00/pih debug|r - toggle debug printing")
	print("  |cffffff00/pih log|r - show debug log")
end

local function HandleSlash(msg)
	msg = strtrim(msg or "")
	local command = string.lower(msg)
	if command == "" or command == "options" or command == "config" then
		if addon.ToggleOptions then
			addon.ToggleOptions()
		end
	elseif command == "export" then
		if addon.ShowProfileExport then
			addon.ShowProfileExport()
		end
	elseif command == "import" then
		if addon.ShowProfileImport then
			addon.ShowProfileImport()
		end
	elseif command == "debug" then
		addon.ToggleDebug()
	elseif command == "log" then
		addon.ShowDebugLog()
	else
		PrintHelp()
	end
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= ADDON_NAME then
			return
		end
		eventFrame:UnregisterEvent("ADDON_LOADED")
		DetectClass()
		InitDB()
		if not addon.ClassAllowed() then
			addon.Debug("Not a priest; PI Helper stays idle")
		end
		addon.SyncRuntime()
		if addon.SyncMinimap then
			addon.SyncMinimap()
		end
		return
	end

	if not db or not addon.ClassAllowed() then
		return
	end

	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		DetectClass()
		RefreshGroupGUIDCache()
		RefreshFocusCache()
		addon.SyncRuntime()
		if addon.SyncMinimap then
			addon.SyncMinimap()
		end
		addon.Fire("LOGIN")
		if runtimeOn then
			RestorePILock()
			addon.QueuePolicy()
		end
		return
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if type(unit) ~= "string" or IsSecret(unit) or unit ~= "player" then
			return
		end
		if type(spellID) ~= "number" or IsSecret(spellID) then
			return
		end
		if spellID == PI_SPELL_ID then
			addon.OnPowerInfusionCast()
		end
		return
	end

	if event == "CHALLENGE_MODE_START" then
		OnCooldownReset(event)
		return
	end

	if event == "ENCOUNTER_END" then
		local _, _, difficultyID, _, success = ...
		if EncounterEndResetsCooldowns(difficultyID) then
			local outcome
			if type(success) == "number" and not IsSecret(success) then
				outcome = (success == 1 and "kill") or (success == 0 and "wipe") or success
			end
			OnCooldownReset(event, outcome)
		else
			addon.Debug("ENCOUNTER_END ignored; dungeon/M+ bosses do not reset CDs")
		end
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		RefreshGroupGUIDCache()
		RefreshFocusCache()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		RefreshGroupGUIDCache()
		RefreshFocusCache()
		addon.Fire("COMBAT_END")
		return
	end

	if event == "PLAYER_FOCUS_CHANGED" then
		QueueFocusSync()
		return
	end

	if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
		RefreshGroupGUIDCache()
		RefreshFocusCache()
		addon.Fire("ROSTER")
		return
	end

	if event == "PLAYER_SPECIALIZATION_CHANGED" then
		local unit = ...
		if type(unit) ~= "string" or IsSecret(unit) or unit ~= "player" then
			return
		end
		addon.QueuePolicy()
		return
	end

	if event == "ADDON_RESTRICTION_STATE_CHANGED" then
		RefreshFocusCache()
		addon.QueuePolicy()
		return
	end
end)

SLASH_PIHELPER1 = "/pih"
SLASH_PIHELPER2 = "/pihelper"
SlashCmdList.PIHELPER = HandleSlash

function PIHelper_OnAddonCompartmentClick()
	if addon.ToggleOptions then
		addon.ToggleOptions()
	end
end
