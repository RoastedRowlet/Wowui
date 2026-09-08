---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.State or {}
ExBoss.TrashCD.State = Mod
ExBoss.Trash.State = Mod

Mod._units = Mod._units or {}
Mod._lastCombatLogUnitDiedAt = tonumber(Mod._lastCombatLogUnitDiedAt) or 0
Mod._pollIndex = tonumber(Mod._pollIndex) or 1
Mod._l1Summary = type(Mod._l1Summary) == "table" and Mod._l1Summary or {}
Mod._l1SummaryDirty = Mod._l1SummaryDirty ~= false

local MAX_NAMEPLATES = 40
local POLL_INTERVAL = 0.10
local POLL_BATCH = 10

local function NormalizeNameplateUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local index = unit:match("^nameplate(%d+)$")
    if not index then
        return nil
    end
    return "nameplate" .. index
end

local function EnsureUnitRow(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    local row = Mod._units[unit]
    if type(row) ~= "table" then
        row = { unit = unit }
        Mod._units[unit] = row
    end
    row.unit = unit
    return row
end

local function ResetUnitRow(row, unit, now)
    for key in pairs(row) do
        row[key] = nil
    end
    row.unit = unit
    row.active = true
    row.addedAt = now
    row.lastSeenAt = now
    row.lastUpdateAt = now
end

local function MarkL1SummaryDirty()
    Mod._l1SummaryDirty = true
end

local function IsEliteClassification(classification)
    return tostring(classification or "") == "elite"
end

local function UnitExistsSafe(unit)
    if type(UnitExists) ~= "function" then
        return false
    end
    return UnitExists(unit) == true
end

local function UnitAffectingCombatSafe(unit)
    if type(UnitAffectingCombat) ~= "function" then
        return false
    end
    return UnitAffectingCombat(unit) == true
end

-- 生命周期追踪只在 Runtime 调试已开启时直接输出；不参与任何判断。
local function DebugTrace(msg)
    local runtime = ExBoss.TrashCD and ExBoss.TrashCD.Runtime or nil
    if runtime and type(runtime.AppendExternalDebug) == "function" then
        runtime.AppendExternalDebug("TrashCD State", msg, true)
    end
end

function Mod.Reset()
    wipe(Mod._units)
    Mod._lastCombatLogUnitDiedAt = 0
    Mod._pollIndex = 1
    MarkL1SummaryDirty()
end

function Mod.GetUnit(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    return Mod._units[unit]
end

function Mod.GetUnits()
    return Mod._units
end

function Mod.OnNameplateAdded(unit)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    local now = GetTime()
    local row = EnsureUnitRow(unit)
    if not row then
        return nil
    end
    if row.active ~= true or row.removedAt ~= nil or row.deadAt ~= nil then
        ResetUnitRow(row, unit, now)
        MarkL1SummaryDirty()
        return row
    end
    row.active = true
    row.lastSeenAt = now
    row.lastUpdateAt = now
    return row
end

function Mod.OnNameplateRemoved(unit)
    local row = EnsureUnitRow(unit)
    if not row then
        return nil
    end
    local now = GetTime()
    local wasInCombat = row.inCombat == true
    row.active = false
    -- 姓名板移除由 Runtime 的缓存流程处理，不把它当作“脱战回调”。
    -- 否则下一次轮询会对已移除的 token 再刷新一次，并可能提前清掉 5 秒恢复缓存。
    row.inCombat = false
    row.removedAt = now
    row.lastUpdateAt = now
    MarkL1SummaryDirty()
    DebugTrace(string.format("removed unit=%s wasCombat=%s (no combat-leave callback)",
        tostring(unit), tostring(wasInCombat)))
    return row
end

-- 仅保存已取得的 L1 快照，不额外调用游戏 API。
function Mod.SyncL1Observation(unit, obs)
    local row = EnsureUnitRow(unit)
    if not row or type(obs) ~= "table" then
        return row
    end

    local level = tonumber(obs.level) or nil
    local power = obs.power
    local family = type(obs.hasCreatureFamily) == "boolean" and obs.hasCreatureFamily or nil
    local firstSeenAt = tonumber(obs.firstSeenAt) or nil
    local changed = row.active ~= true
        or row.level ~= level
        or row.power ~= power
        or row.hasCreatureFamily ~= family
        or row.l1Observed ~= true

    row.active = true
    row.level = level
    row.power = power
    row.hasCreatureFamily = family
    row.l1Observed = true
    row.firstSeenAt = firstSeenAt or row.firstSeenAt
    row.lastSeenAt = GetTime()
    row.lastUpdateAt = row.lastSeenAt

    if changed then
        MarkL1SummaryDirty()
    end
    return row
end

-- 所有副本共用的本地姓名板 L1 汇总。只在表变化后至多扫描 40 个 State 行。
function Mod.GetActiveL1Summary()
    local summary = Mod._l1Summary
    if Mod._l1SummaryDirty ~= true then
        return summary
    end

    summary.hasLevel90 = false
    summary.hasCreatureFamily = false
    summary.hasLevel90Power0 = false
    summary.level91Count = 0
    summary.activeCount = 0
    summary.observedCount = 0

    for _, row in pairs(Mod._units) do
        if type(row) == "table" and row.active == true then
            summary.activeCount = summary.activeCount + 1
            if row.l1Observed == true then
                summary.observedCount = summary.observedCount + 1
                if tonumber(row.level) == 90 then
                    summary.hasLevel90 = true
                    if tonumber(row.power) == 0 then
                        summary.hasLevel90Power0 = true
                    end
                end
                if tonumber(row.level) == 91 then
                    summary.level91Count = summary.level91Count + 1
                end
                if row.hasCreatureFamily == true then
                    summary.hasCreatureFamily = true
                end
            end
        end
    end

    Mod._l1SummaryDirty = false
    return summary
end

-- State 只检测状态变化；实际刷新、计时建立和清理由 Runtime 接手。
function Mod.SetCombatStateCallback(callback)
    Mod._combatStateCallback = type(callback) == "function" and callback or nil
end

local function NotifyCombatStateChanged(unit, inCombat, row)
    local callback = Mod._combatStateCallback
    if type(callback) == "function" then
        callback(unit, inCombat == true, row)
    end
end

function Mod.RefreshUnitCombat(unit, now)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil, nil
    end
    now = tonumber(now) or GetTime()

    local exists = UnitExistsSafe(unit)
    local row = exists and EnsureUnitRow(unit) or Mod._units[unit]
    if type(row) ~= "table" then
        return nil, nil
    end

    local wasActive = row.active == true
    local wasInCombat = row.inCombat == true
    row.unit = unit
    row.exists = exists
    row.lastCombatCheckedAt = now
    row.lastUpdateAt = now

    local combatStateChanged = false
    if exists then
        if row.deadAt ~= nil then
            row.active = false
            row.inCombat = false
            row.lastSeenAt = now
            if wasInCombat == true then
                row.lastCombatLeftAt = now
                combatStateChanged = true
            end
            if combatStateChanged then
                NotifyCombatStateChanged(unit, false, row)
            end
            return false, row
        end
        row.active = true
        row.removedAt = nil
        row.lastSeenAt = now
        if row.addedAt == nil then
            row.addedAt = now
        end
        row.inCombat = UnitAffectingCombatSafe(unit)
        if row.inCombat == true and wasInCombat ~= true then
            row.engagedAt = row.engagedAt or now
            row.lastCombatEnteredAt = now
            combatStateChanged = true
        elseif row.inCombat ~= true and wasInCombat == true then
            row.lastCombatLeftAt = now
            combatStateChanged = true
        end
    else
        row.active = false
        row.inCombat = false
        if wasActive and row.removedAt == nil then
            row.removedAt = now
        end
        if wasInCombat == true then
            row.lastCombatLeftAt = now
            combatStateChanged = true
        end
    end

    if wasActive ~= (row.active == true) then
        MarkL1SummaryDirty()
    end

    if combatStateChanged then
        DebugTrace(string.format("combat-transition unit=%s %s->%s active=%s dead=%s",
            tostring(unit), tostring(wasInCombat), tostring(row.inCombat == true),
            tostring(row.active == true), tostring(row.deadAt ~= nil)))
        NotifyCombatStateChanged(unit, row.inCombat == true, row)
    end

    return row.inCombat == true, row
end

function Mod.IsUnitInCombat(unit, refresh)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return false
    end
    if refresh ~= false then
        local inCombat = Mod.RefreshUnitCombat(unit)
        return inCombat == true
    end
    local row = Mod._units[unit]
    return type(row) == "table" and row.inCombat == true
end

function Mod.PollNameplateCombat(now, batchSize)
    now = tonumber(now) or GetTime()
    batchSize = tonumber(batchSize) or POLL_BATCH
    if batchSize < 1 then
        batchSize = POLL_BATCH
    end
    for _ = 1, batchSize do
        local index = tonumber(Mod._pollIndex) or 1
        if index < 1 or index > MAX_NAMEPLATES then
            index = 1
        end
        Mod.RefreshUnitCombat("nameplate" .. index, now)
        index = index + 1
        if index > MAX_NAMEPLATES then
            index = 1
        end
        Mod._pollIndex = index
    end
end

function Mod.OnUnitDead(unit)
    local row = EnsureUnitRow(unit)
    if not row then
        return nil
    end
    local now = GetTime()
    row.active = false
    row.inCombat = false
    row.deadAt = now
    row.lastUpdateAt = now
    MarkL1SummaryDirty()
    DebugTrace(string.format("unit-dead unit=%s", tostring(unit)))
    return row
end

function Mod.OnCombatLogUnitDied()
    Mod._lastCombatLogUnitDiedAt = GetTime()
    return Mod._lastCombatLogUnitDiedAt
end

function Mod.SyncUnit(unit, runtime, obs, resolved, mapID)
    local row = type(obs) == "table" and Mod.SyncL1Observation(unit, obs) or EnsureUnitRow(unit)
    if not row then
        return nil
    end

    local now = GetTime()
    row.active = true
    row.lastSeenAt = now
    row.lastUpdateAt = now

    if type(obs) == "table" then
        row.unitClassification = obs.unitClassification
        if type(obs.inCombat) == "boolean" then
            row.inCombat = obs.inCombat == true
        else
            row.inCombat = Mod.IsUnitInCombat(unit, false)
        end
        if type(obs.preCombatChanneling) == "boolean" then
            row.preCombatChanneling = obs.preCombatChanneling
        else
            row.preCombatChanneling = nil
        end
        row.firstSeenAt = tonumber(obs.firstSeenAt) or row.firstSeenAt
        row.isElite = IsEliteClassification(obs.unitClassification)
    elseif row.inCombat == nil then
        row.inCombat = Mod.IsUnitInCombat(unit, false)
    end

    local lockedNPCID = tonumber(type(runtime) == "table" and runtime.identityLockedNPCID or nil)
    row.identityLocked = lockedNPCID ~= nil
    row.identityLockedNPCID = lockedNPCID
    row.identityLockedMapID = tonumber(type(runtime) == "table" and runtime.identityLockedMapID or nil)
    row.identityLockedAt = tonumber(type(runtime) == "table" and runtime.identityLockedAt or nil)
    row.identityLockSource = type(runtime) == "table" and runtime.identityLockSource or nil

    local runtimeMapID = tonumber(type(runtime) == "table" and runtime.matchedMapID or nil)
    local resolvedMapID = tonumber(mapID)
    row.matchedMapID = runtimeMapID or resolvedMapID or row.matchedMapID

    local runtimeNPCID = tonumber(type(runtime) == "table" and runtime.matchedNPCID or nil)
    local resolvedNPCID = tonumber(type(resolved) == "table" and resolved.npcID or nil)
    local npcID = lockedNPCID or runtimeNPCID or resolvedNPCID
    if npcID then
        row.npcID = npcID
        row.resolved = true
        row.lastResolvedAt = now
    else
        row.npcID = nil
        row.resolved = false
    end

    if type(runtime) == "table" then
        row.engagedAt = tonumber(runtime.engagedAt) or row.engagedAt
        row.lastResolvedName = tostring(runtime.lastResolvedName or row.lastResolvedName or "")
    end
    if type(resolved) == "table" and resolved.name ~= nil then
        row.lastResolvedName = tostring(resolved.name)
    end
    if row.lastResolvedName == "" then
        row.lastResolvedName = nil
    end

    row.lastCombatLogUnitDiedAt = tonumber(Mod._lastCombatLogUnitDiedAt) or 0
    return row
end

if not Mod._pollFrame and type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (tonumber(self.elapsed) or 0) + (tonumber(elapsed) or 0)
        if self.elapsed < POLL_INTERVAL then
            return
        end
        self.elapsed = 0
        if type(IsInInstance) == "function" and IsInInstance() ~= true then
            return
        end
        Mod.PollNameplateCombat(GetTime(), POLL_BATCH)
    end)
    Mod._pollFrame = frame
end
