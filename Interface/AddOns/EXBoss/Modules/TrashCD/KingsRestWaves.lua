---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.KingsRestWaves or {}
ExBoss.TrashCD.KingsRestWaves = Mod
ExBoss.Trash.KingsRestWaves = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local State = ExBoss.TrashCD and ExBoss.TrashCD.State or nil
local ExwindTools = _G.ExwindTools

local KINGS_REST_MAP_ID = 249
local DAHAZI_SEPULCHER_AREA_ID = 94539
local JOIN_WINDOW = 0.20
local READY_DELAY = 0.50
local MIN_BATCH_MEMBERS = 2

local ROOM_AREA_SET = { [DAHAZI_SEPULCHER_AREA_ID] = true }

Mod._unitBatches = type(Mod._unitBatches) == "table" and Mod._unitBatches or {}
Mod._releasedUnits = type(Mod._releasedUnits) == "table" and Mod._releasedUnits or {}
Mod._nextBatchID = tonumber(Mod._nextBatchID) or 0
Mod._generation = tonumber(Mod._generation) or 0
Mod._currentBatch = type(Mod._currentBatch) == "table" and Mod._currentBatch or nil

local function WipeTable(t)
    if type(t) ~= "table" then
        return {}
    end
    for key in pairs(t) do
        t[key] = nil
    end
    return t
end

local function NormalizeNameplateUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local index = unit:match("^nameplate(%d+)$")
    return index and "nameplate" .. index or nil
end

local function GetCurrentMapID()
    local state = ExwindTools and ExwindTools.State or nil
    local mapID = tonumber(state and state.MapID) or 0
    return mapID > 0 and mapID or nil
end

function Mod.IsActive(mapID)
    local currentMapID = tonumber(mapID) or GetCurrentMapID()
    if currentMapID ~= KINGS_REST_MAP_ID then
        return false
    end
    return Data and type(Data.IsCurrentWMOAreaSetAllowed) == "function"
        and Data.IsCurrentWMOAreaSetAllowed(ROOM_AREA_SET) == true
end

local function SnapshotSummary(summary)
    if type(summary) ~= "table" then
        return nil
    end
    return {
        hasLevel90 = summary.hasLevel90 == true,
        hasCreatureFamily = summary.hasCreatureFamily == true,
        hasLevel90Power0 = summary.hasLevel90Power0 == true,
        level91Count = math.max(0, tonumber(summary.level91Count) or 0),
    }
end

function Mod.SetRefreshCallback(callback)
    Mod._refreshCallback = type(callback) == "function" and callback or nil
end

function Mod.Reset()
    Mod._generation = (tonumber(Mod._generation) or 0) + 1
    Mod._nextBatchID = 0
    Mod._currentBatch = nil
    WipeTable(Mod._unitBatches)
    WipeTable(Mod._releasedUnits)
end

local function GetBatchActiveL1Members(batch)
    local count = 0
    local units = {}
    for unit in pairs(type(batch) == "table" and batch.units or {}) do
        local row = State and type(State.GetUnit) == "function" and State.GetUnit(unit) or nil
        if type(row) == "table" and row.active == true and row.l1Observed == true then
            count = count + 1
            units[unit] = true
        end
    end
    return count, units
end

local function RequestRefresh(units, reason)
    local callback = Mod._refreshCallback
    if type(callback) == "function" and type(units) == "table" and next(units) ~= nil then
        callback(units, reason)
    end
end

local function ReleaseBatch(batch, reason)
    if type(batch) ~= "table" or batch.released == true or batch.ready == true then
        return
    end
    batch.released = true
    local units = {}
    for unit in pairs(batch.units) do
        if Mod._unitBatches[unit] == batch then
            Mod._unitBatches[unit] = nil
            Mod._releasedUnits[unit] = true
            units[unit] = true
        end
    end
    RequestRefresh(units, reason or "kings-rest-batch-release")
end

local function FinalizeBatch(batch, generation)
    if generation ~= Mod._generation or type(batch) ~= "table" or batch.released == true or batch.ready == true then
        return
    end
    local memberCount, units = GetBatchActiveL1Members(batch)
    if memberCount < MIN_BATCH_MEMBERS then
        ReleaseBatch(batch, "kings-rest-batch-too-small")
        return
    end
    local summary = State and type(State.GetActiveL1Summary) == "function" and State.GetActiveL1Summary() or nil
    batch.summary = SnapshotSummary(summary)
    if not batch.summary then
        ReleaseBatch(batch, "kings-rest-wave-no-summary")
        return
    end
    batch.ready = true
    batch.summaryRevision = summary
    RequestRefresh(units, "kings-rest-wave-ready")
end

local function ScheduleReady(batch)
    if type(batch) ~= "table" or batch.ready == true or batch.released == true or batch.readyScheduled == true then
        return
    end
    batch.readyScheduled = true
    local generation = Mod._generation
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(READY_DELAY, function()
            FinalizeBatch(batch, generation)
        end)
    else
        FinalizeBatch(batch, generation)
    end
end

local function ScheduleSingleMemberRelease(batch)
    if type(batch) ~= "table" or batch.releaseScheduled == true then
        return
    end
    batch.releaseScheduled = true
    local generation = Mod._generation
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(JOIN_WINDOW, function()
            if generation ~= Mod._generation or batch.ready == true or batch.released == true then
                return
            end
            if tonumber(batch.memberCount) < MIN_BATCH_MEMBERS then
                ReleaseBatch(batch, "kings-rest-single-release")
            else
                ScheduleReady(batch)
            end
        end)
    end
end

local function NewBatch(now)
    Mod._nextBatchID = (tonumber(Mod._nextBatchID) or 0) + 1
    local batch = {
        id = Mod._nextBatchID,
        startedAt = tonumber(now) or GetTime(),
        units = {},
        memberCount = 0,
    }
    Mod._currentBatch = batch
    ScheduleSingleMemberRelease(batch)
    return batch
end

local function EnrollUnit(unit, now)
    local batch = Mod._unitBatches[unit]
    if type(batch) == "table" then
        return batch
    end
    if Mod._releasedUnits[unit] == true then
        return nil
    end

    batch = Mod._currentBatch
    if type(batch) ~= "table" or batch.ready == true or batch.released == true
        or (tonumber(now) or GetTime()) - (tonumber(batch.startedAt) or 0) > JOIN_WINDOW then
        batch = NewBatch(now)
    end

    batch.units[unit] = true
    batch.memberCount = (tonumber(batch.memberCount) or 0) + 1
    Mod._unitBatches[unit] = batch
    if batch.memberCount >= MIN_BATCH_MEMBERS then
        ScheduleReady(batch)
    end
    return batch
end

-- 姓名板加入时先建立批次，避免第一个姓名板在其余同波成员加入前被正式锁定。
function Mod.OnNameplateAdded(unit, mapID)
    unit = NormalizeNameplateUnit(unit)
    if not unit or Mod.IsActive(mapID) ~= true then
        return false
    end
    Mod._releasedUnits[unit] = nil
    return EnrollUnit(unit, GetTime()) ~= nil
end

function Mod.OnL1Snapshot(unit, mapID)
    unit = NormalizeNameplateUnit(unit)
    if not unit or Mod.IsActive(mapID) ~= true then
        return false
    end
    if Mod._releasedUnits[unit] == true then
        return false
    end
    return EnrollUnit(unit, GetTime()) ~= nil
end

function Mod.OnNameplateRemoved(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    local batch = Mod._unitBatches[unit]
    if type(batch) == "table" and batch.units[unit] == true then
        batch.units[unit] = nil
        batch.memberCount = math.max(0, (tonumber(batch.memberCount) or 1) - 1)
    end
    Mod._unitBatches[unit] = nil
    Mod._releasedUnits[unit] = nil
end

local function IsRoomScopedRow(row)
    return type(row) == "table"
        and type(row.wmoAreaIDs) == "table"
        and row.wmoAreaIDs[DAHAZI_SEPULCHER_AREA_ID] == true
end

local function HasBatchCondition(row)
    return type(row) == "table"
        and type(row.groupHasLevel90) == "boolean"
        and type(row.groupHasCreatureFamily) == "boolean"
        and type(row.groupHasLevel90Power0) == "boolean"
end

local function SameBatchCondition(left, right)
    return HasBatchCondition(left)
        and HasBatchCondition(right)
        and left.groupHasLevel90 == right.groupHasLevel90
        and left.groupHasCreatureFamily == right.groupHasCreatureFamily
        and left.groupHasLevel90Power0 == right.groupHasLevel90Power0
end

-- 波次的正常 91 级数量直接由已导入的同组资料计算；不另写死，也不改 Excel。
local function GetExpectedLevel91Count(anchorRow)
    if not HasBatchCondition(anchorRow) then
        return nil
    end
    local traitsRoot = Data and type(Data.GetTrashMobTraitsRoot) == "function" and Data.GetTrashMobTraitsRoot() or nil
    local rows = type(traitsRoot) == "table" and traitsRoot.rows or nil
    if type(rows) ~= "table" then
        return nil
    end
    local count = 0
    for i = 1, #rows do
        local row = rows[i]
        if IsRoomScopedRow(row) and SameBatchCondition(row, anchorRow) and tonumber(row.level) == 91 then
            count = count + 1
        end
    end
    return count > 0 and count or nil
end

local function MatchesBatchCondition(row, summary)
    return HasBatchCondition(row)
        and type(summary) == "table"
        and row.groupHasLevel90 == summary.hasLevel90
        and row.groupHasCreatureFamily == summary.hasCreatureFamily
        and row.groupHasLevel90Power0 == summary.hasLevel90Power0
end

-- 先由本波内可唯一 L1 锁定的怪物充当锚点，再冻结“这波正常应有几只 91 级”。
-- 活化守卫若已被提前带入，会出现在全场活跃 L1 表内，从而使实际数多于正常数。
function Mod.OnIdentityLocked(unit, candidate, mapID)
    unit = NormalizeNameplateUnit(unit)
    if not unit or Mod.IsActive(mapID) ~= true then
        return false
    end
    local batch = Mod._unitBatches[unit]
    local row = type(candidate) == "table" and candidate.row or nil
    if type(batch) ~= "table" or batch.ready ~= true
        or batch.waveAnchorNPCID ~= nil
        or IsRoomScopedRow(row) ~= true
        or MatchesBatchCondition(row, batch.summary) ~= true then
        return false
    end

    local expectedLevel91 = GetExpectedLevel91Count(row)
    local activeSummary = State and type(State.GetActiveL1Summary) == "function" and State.GetActiveL1Summary() or nil
    local actualLevel91 = tonumber(type(activeSummary) == "table" and activeSummary.level91Count) or 0
    if not expectedLevel91 or actualLevel91 < expectedLevel91 then
        return false
    end

    batch.waveAnchorNPCID = tonumber(candidate.npcID)
    batch.expectedLevel91Count = expectedLevel91
    batch.actualLevel91Count = actualLevel91
    batch.hasExtraLevel91 = actualLevel91 > expectedLevel91
    RequestRefresh(batch.units, "kings-rest-wave-anchor")
    return true
end

-- 该过滤只作用于刚生成且已完成 0.5 秒窗口的那一批姓名板。
-- 三项批次条件与 NPC 归属完全来自 Excel 导出的行；本模块只保留房间与时序。
function Mod.FilterCandidates(candidates, obs, mapID)
    if type(candidates) ~= "table" or type(obs) ~= "table" or Mod.IsActive(mapID) ~= true then
        return candidates, false, nil
    end
    local unit = NormalizeNameplateUnit(obs.unit)
    local batch = unit and Mod._unitBatches[unit] or nil
    if type(batch) ~= "table" then
        return candidates, false, nil
    end
    if batch.ready ~= true then
        return {}, true, "waiting"
    end

    if type(batch.summary) ~= "table" then
        return candidates, false, nil
    end
    local out = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local row = type(candidate) == "table" and candidate.row or nil
        if IsRoomScopedRow(row) then
            if MatchesBatchCondition(row, batch.summary) then
                out[#out + 1] = candidate
            -- 未填写波次条件的房间行目前只有可带入的活化守卫。
            -- 锚点锁定且 91 级数未超额时，证明守卫不在场，不得保留其候选制造二选一。
            elseif HasBatchCondition(row) ~= true and batch.waveAnchorNPCID == nil then
                out[#out + 1] = candidate
            elseif HasBatchCondition(row) ~= true and batch.hasExtraLevel91 == true then
                out[#out + 1] = candidate
            end
        end
    end
    return out, true, "ready"
end

function Mod.GetUnitWaveState(unit)
    unit = NormalizeNameplateUnit(unit)
    local batch = unit and Mod._unitBatches[unit] or nil
    if type(batch) ~= "table" then
        return nil
    end
    return {
        ready = batch.ready == true,
        summary = batch.summary,
        memberCount = tonumber(batch.memberCount) or 0,
        startedAt = batch.startedAt,
        waveAnchorNPCID = batch.waveAnchorNPCID,
        expectedLevel91Count = batch.expectedLevel91Count,
        actualLevel91Count = batch.actualLevel91Count,
        hasExtraLevel91 = batch.hasExtraLevel91 == true,
    }
end
