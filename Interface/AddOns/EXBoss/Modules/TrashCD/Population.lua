---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Population or {}
ExBoss.TrashCD.Population = Mod
ExBoss.Trash.Population = Mod

local ExwindTools = _G.ExwindTools

Mod._remainingByMapAndStage = Mod._remainingByMapAndStage or {}
Mod._context = Mod._context or nil
Mod._reservationRevision = tonumber(Mod._reservationRevision) or 0

local function WipeTable(t)
    if type(t) ~= "table" then
        return {}
    end
    for key in pairs(t) do
        t[key] = nil
    end
    return t
end

local function GetState()
    return ExwindTools and ExwindTools.State or nil
end

-- 仅供排查预占名额生命周期；Runtime 未开调试时 AppendExternalDebug 不会输出。
local function DebugTrace(msg)
    local runtime = ExBoss.TrashCD and ExBoss.TrashCD.Runtime or nil
    if runtime and type(runtime.AppendExternalDebug) == "function" then
        runtime.AppendExternalDebug("TrashCD Population", msg, true)
    end
end

local function RuntimeLabel(runtime)
    return string.format("unit=%s npc=%s", tostring(type(runtime) == "table" and runtime._debugUnit or "?"),
        tostring(type(runtime) == "table" and runtime._populationNPCID or "?"))
end

local function GetCurrentMapID(explicitMapID)
    local mapID = tonumber(explicitMapID)
    if mapID and mapID > 0 then
        return mapID
    end
    local state = GetState()
    mapID = tonumber(state and state.MapID) or 0
    return mapID > 0 and mapID or nil
end

local function GetCurrentBossStage()
    local state = GetState()
    local stage = tonumber(state and state.DungeonBossProgressIndex) or 0
    -- Scenario criteria may still be loading on the first pull; that is 1号首领前。
    return stage > 0 and stage or 1
end

local function GetConfiguredCount(row, stage)
    local counts = type(row) == "table" and row.bossCounts or nil
    local count = type(counts) == "table" and tonumber(counts[stage]) or nil
    if count == nil then
        return nil
    end
    return math.max(0, math.floor(count))
end

local function GetConfiguredPriority(row, stage)
    local priorities = type(row) == "table" and row.bossPriorities or nil
    if type(priorities) == "table" then
        return tonumber(priorities[stage])
    end
    -- 兼容旧资料中的单个 priority 值；新表请填写 bossPriorities。
    return tonumber(type(row) == "table" and row.priority)
end

local function GetStagePool(mapID, stage)
    if not mapID or not stage then
        return nil
    end
    local byMap = Mod._remainingByMapAndStage[mapID]
    if type(byMap) ~= "table" then
        byMap = {}
        Mod._remainingByMapAndStage[mapID] = byMap
    end
    local pool = byMap[stage]
    if type(pool) ~= "table" then
        pool = {}
        byMap[stage] = pool
    end
    return pool
end

local function GetRemaining(row, mapID, stage)
    local initial = GetConfiguredCount(row, stage)
    if initial == nil or not mapID then
        return nil
    end
    local npcID = tonumber(type(row) == "table" and row.npcID)
    if not npcID then
        return nil
    end
    local pool = GetStagePool(mapID, stage)
    if pool[npcID] == nil then
        pool[npcID] = initial
    end
    return tonumber(pool[npcID]) or 0
end

function Mod.Reset()
    WipeTable(Mod._remainingByMapAndStage)
    Mod._reservationRevision = (tonumber(Mod._reservationRevision) or 0) + 1
end

function Mod.IsRowEligible(row, explicitMapID, options)
    if type(row) ~= "table" then
        return true
    end

    options = type(options) == "table" and options or {}

    local state = GetState()
    if type(row.bossEncounter) == "boolean"
        and row.bossEncounter ~= (state and state.IsBossEncounter == true) then
        return false, "boss-encounter"
    end

    if options.ignoreBossCounts ~= true then
        local mapID = GetCurrentMapID(explicitMapID)
        local stage = GetCurrentBossStage()
        local remaining = GetRemaining(row, mapID, stage)
        if remaining ~= nil and remaining <= 0 then
            return false, "boss-count-exhausted"
        end
    end
    return true
end

local function ClearRuntimeReservation(runtime, source)
    runtime._populationMapID = nil
    runtime._populationStage = nil
    runtime._populationNPCID = nil
    runtime._populationInitialCount = nil
    runtime._populationReserved = nil
    runtime._populationRevision = nil
    runtime._populationDeathConsumed = nil
    runtime._populationResolutionSource = source
end

local function ReleaseRuntimeReservation(runtime)
    if type(runtime) ~= "table" or runtime._populationReserved ~= true then
        return false
    end

    local revision = tonumber(runtime._populationRevision)
    local mapID = tonumber(runtime._populationMapID)
    local stage = tonumber(runtime._populationStage)
    local npcID = tonumber(runtime._populationNPCID)
    local initial = tonumber(runtime._populationInitialCount)
    if revision == tonumber(Mod._reservationRevision)
        and mapID and stage and npcID and initial then
        local pool = GetStagePool(mapID, stage)
        local remaining = tonumber(pool[npcID])
        if remaining ~= nil then
            pool[npcID] = math.min(math.max(0, math.floor(initial)), math.max(0, remaining) + 1)
            DebugTrace(string.format("release %s map=%s stage=%s remaining=%s->%s",
                RuntimeLabel(runtime), tostring(mapID), tostring(stage), tostring(remaining), tostring(pool[npcID])))
        end
    else
        DebugTrace(string.format("release-skipped %s revision=%s currentRevision=%s map=%s stage=%s",
            RuntimeLabel(runtime), tostring(revision), tostring(Mod._reservationRevision), tostring(mapID), tostring(stage)))
    end
    return true
end

local function ReserveRuntime(runtime, row, mapID, stage, npcID, initial, source)
    local remaining = GetRemaining(row, mapID, stage)
    if remaining == nil or remaining <= 0 then
        DebugTrace(string.format("reserve-refused unit=%s npc=%s map=%s stage=%s remaining=%s",
            tostring(runtime and runtime._debugUnit or "?"), tostring(npcID), tostring(mapID), tostring(stage), tostring(remaining)))
        ClearRuntimeReservation(runtime, source)
        return false
    end

    local pool = GetStagePool(mapID, stage)
    pool[npcID] = math.max(0, remaining - 1)
    runtime._populationMapID = mapID
    runtime._populationStage = stage
    runtime._populationNPCID = npcID
    runtime._populationInitialCount = initial
    runtime._populationReserved = true
    runtime._populationRevision = Mod._reservationRevision
    runtime._populationDeathConsumed = nil
    runtime._populationResolutionSource = source
    DebugTrace(string.format("reserve %s map=%s stage=%s remaining=%s->%s source=%s",
        RuntimeLabel(runtime), tostring(mapID), tostring(stage), tostring(remaining), tostring(pool[npcID]), tostring(source)))
    return true
end

function Mod.MarkResolved(runtime, candidate, explicitMapID, source, inCombat)
    if type(runtime) ~= "table" or type(candidate) ~= "table" then
        return
    end
    local row = type(candidate.row) == "table" and candidate.row or candidate
    local mapID = GetCurrentMapID(explicitMapID)
    local stage = GetCurrentBossStage()
    local npcID = tonumber(candidate.npcID or row.npcID)
    local initial = GetConfiguredCount(row, stage)

    if runtime._populationReserved == true
        and tonumber(runtime._populationRevision) == tonumber(Mod._reservationRevision)
        and tonumber(runtime._populationMapID) == mapID
        and tonumber(runtime._populationStage) == stage
        and tonumber(runtime._populationNPCID) == npcID then
        runtime._populationResolutionSource = source
        return
    end

    ReleaseRuntimeReservation(runtime)
    if inCombat ~= true or not (mapID and stage and npcID and initial ~= nil) then
        ClearRuntimeReservation(runtime, source)
        return
    end
    ReserveRuntime(runtime, row, mapID, stage, npcID, initial, source)
end

-- 姓名板失联后的临时预留必须归还；已确认死亡的预留则转为正式消耗，不能归还。
function Mod.ReleaseRuntimeReservation(runtime, source)
    if type(runtime) ~= "table" then
        return false
    end
    local released = false
    if runtime._populationReserved == true and runtime._populationDeathConsumed ~= true then
        released = ReleaseRuntimeReservation(runtime) == true
    end
    ClearRuntimeReservation(runtime, source or "runtime-released")
    return released
end

function Mod.SelectPriority(candidates, obs, runtime, explicitMapID)
    if type(candidates) ~= "table" or #candidates <= 1 or type(obs) ~= "table" or obs.inCombat ~= true then
        return nil
    end

    local best = nil
    local bestPriority = nil
    local tied = false
    local stage = GetCurrentBossStage()
    for i = 1, #candidates do
        local candidate = candidates[i]
        local priority = GetConfiguredPriority(type(candidate) == "table" and candidate.row or nil, stage)
        if priority ~= nil then
            if bestPriority == nil or priority > bestPriority then
                best = candidate
                bestPriority = priority
                tied = false
            elseif priority == bestPriority then
                tied = true
            end
        end
    end
    if not best or tied then
        return nil
    end
    return best
end

function Mod.OnUnitDead(runtime)
    if type(runtime) ~= "table" or runtime._populationReserved ~= true or runtime._populationDeathConsumed == true then
        return false
    end
    -- 名额已在成功识别时预占；死亡只消费 runtime，不能再次扣减。
    runtime._populationDeathConsumed = true
    DebugTrace(string.format("death-consumed %s map=%s stage=%s",
        RuntimeLabel(runtime), tostring(runtime._populationMapID), tostring(runtime._populationStage)))
    return true
end

function Mod.SyncStateContext()
    local state = GetState()
    if type(state) ~= "table" or state.InInstance ~= true then
        return
    end
    Mod._context = Mod._context or {}
    Mod._context.inMythicPlus = state.InMythicPlus == true
    Mod._context.mapID = GetCurrentMapID()
end

local function RegisterStateCallbacks()
    if Mod._stateCallbacksRegistered == true or not (ExwindTools and type(ExwindTools.WatchState) == "function") then
        return
    end
    Mod._stateCallbacksRegistered = true

    ExwindTools:WatchState("InInstance", "ExBoss.TrashCD.Population.Instance", function(inInstance, oldInstance)
        if inInstance == true then
            Mod.SyncStateContext()
            return
        end
        if oldInstance == true and type(Mod._context) == "table" and Mod._context.inMythicPlus ~= true then
            Mod.Reset()
        end
        if inInstance ~= true then
            Mod._context = nil
        end
    end)

    ExwindTools:WatchState("InMythicPlus", "ExBoss.TrashCD.Population.MythicPlus", function(inMythicPlus)
        if inMythicPlus == true then
            Mod.SyncStateContext()
        end
    end)

    ExwindTools:WatchState("MythicPlusRunStartRevision", "ExBoss.TrashCD.Population.MythicPlusStart", function()
        local state = GetState()
        if state and state.InMythicPlus == true then
            Mod.Reset()
            Mod.SyncStateContext()
        end
    end)
end

RegisterStateCallbacks()
Mod.SyncStateContext()
