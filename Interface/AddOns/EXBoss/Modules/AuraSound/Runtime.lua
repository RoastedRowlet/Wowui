---@diagnostic disable: undefined-global

-- AuraSound V2 runtime.
-- Persistent data intentionally has one flat item per C_UnitAuras sound registration:
-- dungeonOptions[dungeonKey].auraSounds = { version = 2, items = { [actionID] = row } }

ExBoss = ExBoss or {}
ExBoss.AuraSound = ExBoss.AuraSound or {}
local AuraSound = ExBoss.AuraSound
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local active = {} -- [actionID .. "\31" .. unitToken] = { auraSoundID = number, fingerprint = string }
local refreshPending = false
local lastError = nil
local PARTY_UNIT_TOKENS = { "party1", "party2", "party3", "party4" }
local ENEMY_UNIT_TOKENS = { "target", "boss1", "boss2", "boss3", "boss4", "boss5" }
local TRIGGERS = {
    added = Enum.UnitAuraSoundTrigger.Added,
    applicationsIncreased = Enum.UnitAuraSoundTrigger.ApplicationsIncreased,
    removed = Enum.UnitAuraSoundTrigger.Removed,
}
for i = 1, 40 do ENEMY_UNIT_TOKENS[#ENEMY_UNIT_TOKENS + 1] = "nameplate" .. i end

local function ActiveCount()
    local count = 0
    for _ in pairs(active) do count = count + 1 end
    return count
end

local function RemoveRegistration(runtimeKey, registration)
    if not registration then return true end
    local remove = C_UnitAuras and C_UnitAuras.RemoveAuraSound
    if type(remove) ~= "function" then
        lastError = "C_UnitAuras.RemoveAuraSound unavailable"
        return false
    end
    -- This API is restricted and must be called only from our verified safe
    -- refresh path. Do not mask an API contract violation with pcall.
    remove(registration.auraSoundID)
    active[runtimeKey] = nil
    return true
end

local function ClearActive()
    local allRemoved = true
    for runtimeKey, registration in pairs(active) do
        if not RemoveRegistration(runtimeKey, registration) then allRemoved = false end
    end
    return allRemoved
end

local function GetState(key)
    return ExwindTools.State and ExwindTools.State[key]
end

-- Dungeon identity is battle metadata, not AuraSound configuration.  The
-- Factory-resolved aura leaf remains the sole configuration input below.
local function GetDungeonKeyForMapID(mapID)
    mapID = tonumber(mapID)
    if not mapID then return nil end
    local data = _G.EXBOSS_ENCOUNTER_DATA
    local maps = type(data) == "table" and data.maps or nil
    local map = type(maps) == "table" and (maps[mapID] or maps[tostring(mapID)]) or nil
    local bosses = type(map) == "table" and map.bosses or nil
    local registry = ExBoss and ExBoss.BossEncounters
    if type(bosses) ~= "table" or type(registry) ~= "table" or type(registry.Get) ~= "function" then
        return nil
    end
    for _, boss in pairs(bosses) do
        local encounterID = type(boss) == "table" and tonumber(boss.encounterID) or nil
        local def = encounterID and registry:Get(encounterID) or nil
        local dungeon = type(def) == "table" and def.dungeon or nil
        local key = type(dungeon) == "table" and tostring(dungeon.key or "") or ""
        if key ~= "" then return key end
    end
    return nil
end

local function GetDungeonKey()
    return GetDungeonKeyForMapID(GetState("InstanceID"))
        or GetDungeonKeyForMapID(GetState("MapID"))
        or GetDungeonKeyForMapID(GetState("MapGroup"))
end

local function CanRegisterNow()
    if GetState("InInstance") ~= true then return false, "not in instance" end
    if GetState("InCombat") == true then return false, "instance combat" end
    return true
end

-- A catalog record can be a tombstone (enabled = false), so sound selection and
-- enablement are deliberately evaluated separately.
local function HasSoundConfig(row)
    if type(row) ~= "table" then return false end
    local sourceType = tostring(row.sourceType or "pack")
    if sourceType == "lsm" then
        return tostring(row.customLSM or "") ~= ""
    end
    if sourceType == "file" then return tostring(row.customPath or "") ~= "" end
    return tostring(row.label or "") ~= ""
end

local function IsEnabled(row)
    return type(row) == "table" and row.enabled ~= false
end

local function ResolveTarget(row)
    row = type(row) == "table" and row or {}
    local unit = tostring(row.unit or "")
    local auraType = tostring(row.auraType or "")
    if unit ~= "player" and unit ~= "party" and unit ~= "enemy" then return nil, nil end
    if auraType ~= "buff" and auraType ~= "debuff" then return nil, nil end
    return unit, auraType
end

-- Runtime consumes the same ID/action View contract as the settings page.
-- Do not reconstruct or retain a complete resolved auraSounds root here.
local function GetAuraSoundActionRows(dungeonKey)
    local bossCfg = ExBoss.BossConfig
    if not (bossCfg and type(bossCfg.GetMplusDungeonAuraSoundView) == "function"
        and type(bossCfg.GetMplusDungeonAuraSoundActionView) == "function"
        and type(bossCfg.GetRuntimeSlotForScene) == "function") then
        return nil
    end
    local slotKey = bossCfg:GetRuntimeSlotForScene("mplus")
    local view = bossCfg:GetMplusDungeonAuraSoundView(dungeonKey, slotKey)
    if type(view) ~= "table" or type(view.actionIDs) ~= "table" then return nil end

    local rows = {}
    for _, actionID in ipairs(view.actionIDs) do
        if type(actionID) ~= "string" or actionID == "" then return nil end
        local row = bossCfg:GetMplusDungeonAuraSoundActionView(dungeonKey, actionID, slotKey)
        if type(row) ~= "table" then return nil end
        rows[actionID] = row
    end
    return rows
end

local function AddDesired(desired, actionID, unitToken, row, soundInfo)
    local trigger = TRIGGERS[tostring(row.trigger or "")]
    local spellID = tonumber(row.spellID)
    if not trigger or not spellID or spellID <= 0 or type(soundInfo.file) ~= "string" or soundInfo.file == "" then return end
    local channel = tostring(row.outputChannel or soundInfo.channel or "Master")
    local runtimeKey = tostring(actionID) .. "\31" .. tostring(unitToken)
    desired[runtimeKey] = {
        actionID = tostring(actionID),
        unitToken = unitToken,
        trigger = trigger,
        spellID = spellID,
        soundFileName = soundInfo.file,
        outputChannel = channel,
        fingerprint = table.concat({ tostring(trigger), tostring(spellID), soundInfo.file, channel }, "\31"),
    }
end

local function AddDesiredForRow(desired, actionID, row, engine)
    if not (IsEnabled(row) and HasSoundConfig(row)) then return end
    local trigger = TRIGGERS[tostring(row.trigger or "")]
    local spellID = tonumber(row.spellID)
    if not (trigger and spellID and spellID > 0) then return end

    local ok, soundInfo = pcall(engine.ResolveStandaloneSound, engine, row, { triggerIndex = 0 })
    if not (ok and type(soundInfo) == "table" and type(soundInfo.file) == "string" and soundInfo.file ~= "") then
        return
    end
    local unit = ResolveTarget(row)
    if unit == "player" then
        AddDesired(desired, actionID, "player", row, soundInfo)
    elseif unit == "party" then
        for i = 1, #PARTY_UNIT_TOKENS do
            AddDesired(desired, actionID, PARTY_UNIT_TOKENS[i], row, soundInfo)
        end
    elseif unit == "enemy" then
        for i = 1, #ENEMY_UNIT_TOKENS do
            AddDesired(desired, actionID, ENEMY_UNIT_TOKENS[i], row, soundInfo)
        end
    end
end

local function BuildDesired(items, engine)
    local desired = {}
    for actionID, row in pairs(items) do
        if type(actionID) == "string" and actionID ~= "" and type(row) == "table" then
            AddDesiredForRow(desired, actionID, row, engine)
        end
    end
    return desired
end

local function AddRegistration(runtimeKey, wanted)
    local add = C_UnitAuras and C_UnitAuras.AddAuraSound
    if type(add) ~= "function" then
        lastError = "C_UnitAuras.AddAuraSound unavailable"
        return false
    end
    -- See RemoveRegistration: this must surface an unexpected restricted-API
    -- failure rather than pretending the registration was merely unavailable.
    local auraSoundID = add(wanted.trigger, {
        unitToken = wanted.unitToken,
        spellID = wanted.spellID,
        soundFileName = wanted.soundFileName,
        outputChannel = wanted.outputChannel,
    })
    if auraSoundID then
        active[runtimeKey] = { auraSoundID = auraSoundID, fingerprint = wanted.fingerprint }
        return true
    end
    lastError = string.format("register failed: %s:%s", wanted.unitToken, wanted.spellID)
    return false
end

local function ApplyDesired(desired)
    local complete = true
    -- Remove stale registrations and entries whose rendered audio/config changed.
    for runtimeKey, registration in pairs(active) do
        local wanted = desired[runtimeKey]
        if not wanted or wanted.fingerprint ~= registration.fingerprint then
            if not RemoveRegistration(runtimeKey, registration) then complete = false end
        end
    end
    -- Only new/missing registrations reach the official API.
    for runtimeKey, wanted in pairs(desired) do
        if not active[runtimeKey] and not AddRegistration(runtimeKey, wanted) then complete = false end
    end
    return complete
end

function AuraSound:RefreshActiveRegistrations()
    -- Leaving an instance must remove rules immediately, even if another refresh is queued.
    if GetState("InInstance") ~= true then
        local cleared = ClearActive()
        refreshPending = not cleared
        if cleared then lastError = nil end
        return cleared
    end

    local allowed = CanRegisterNow()
    if not allowed then
        refreshPending = true
        return false
    end
    if not (C_UnitAuras and type(C_UnitAuras.AddAuraSound) == "function" and type(C_UnitAuras.RemoveAuraSound) == "function") then
        lastError = "C_UnitAuras aura sound API unavailable"
        refreshPending = true
        return false
    end

    local dungeonKey = GetDungeonKey()
    if not dungeonKey then
        local cleared = ClearActive()
        refreshPending = not cleared
        if cleared then lastError = nil end
        return cleared
    end

    local actionRows = GetAuraSoundActionRows(dungeonKey)
    if type(actionRows) ~= "table" then
        lastError = "invalid mplus aura sound schema"
        local cleared = ClearActive()
        refreshPending = not cleared
        return false
    end
    local engine = ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and type(engine.ResolveStandaloneSound) == "function") then
        lastError = "voice engine unavailable"
        refreshPending = true
        return false
    end

    lastError = nil
    local desired = BuildDesired(actionRows, engine)
    local complete = ApplyDesired(desired)
    refreshPending = not complete
    return complete
end

function AuraSound:ClearActiveRegistrations()
    local cleared = ClearActive()
    refreshPending = not cleared
    return cleared
end

function AuraSound:GetRuntimeStatus()
    return { activeCount = ActiveCount(), pending = refreshPending, error = lastError }
end

local function RequestRefresh()
    AuraSound:RefreshActiveRegistrations()
end

-- AuraSound writes publish their exact leaf path.  Other M+ paths do not
-- affect these registrations.
local function ClassifyMplusConfigChange(info)
    if type(info) ~= "table" then return "other" end
    if info.kind == "auraSounds" then return "aura" end

    local payload = type(info.path) == "table" and info.path or info
    local paths = payload.batch == true and payload.paths or nil
    if paths == nil then
        if type(payload[1]) ~= "string" then return "other" end
        paths = { payload }
    end
    if type(paths) ~= "table" or #paths == 0 then return "other" end

    local hasAura = false
    for i = 1, #paths do
        local path = paths[i]
        if type(path) ~= "table" or path[1] ~= "dungeonOptions" or path[2] == nil then
            return "other"
        elseif path[3] == "auraSounds" then
            hasAura = true
        else
            return "other"
        end
    end
    if hasAura then return "aura" end
    return "other"
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_AuraSound_PEW", function()
    C_Timer.After(0.25, RequestRefresh)
end)
ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", "ExBoss_AuraSound_Regen", function()
    if refreshPending then RequestRefresh() end
end)
ExwindTools:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "ExBoss_AuraSound_Restriction", function()
    if refreshPending then RequestRefresh() end
end)
for _, stateKey in ipairs({ "InInstance", "InstanceID", "MapID", "InMythicPlus", "RoleKey", "SpecID" }) do
    ExwindTools:WatchState(stateKey, "ExBoss_AuraSound_" .. stateKey, RequestRefresh)
end
ExwindTools:WatchState("ExBossData.MplusConfigChanged", "ExBoss_AuraSound_MplusConfig", function(info)
    local kind = ClassifyMplusConfigChange(info)
    if kind == "other" then return end
    RequestRefresh()
end)
