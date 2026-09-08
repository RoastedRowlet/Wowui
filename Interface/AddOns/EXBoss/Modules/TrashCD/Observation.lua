---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Observation or {}
ExBoss.TrashCD.Observation = Mod
ExBoss.Trash.Observation = Mod
local TRASH_CASTBAR_STOP_EVENT = "EXBOSS_TRASH_CASTBAR_STOP"

local SNAPSHOT_DELAY = 0.10
local CAST_TARGET_SAMPLE_DELAY = 0.10
local CAST_TARGET_HOSTILE_SAMPLE_DELAY = 0.30
local CAST_TARGET_CLEAR_WINDOW = 0.10
local CAST_TARGET_SWITCH_WINDOW = 0.10
local MAX_NAMEPLATES = 40
local CHANNEL_REFRESH_INTERRUPTIBLE_WINDOW = 1.00


local function IsNameplateInCombat(unit, refresh)
    local state = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.State or nil
    if state and type(state.IsUnitInCombat) == "function" then
        return state.IsUnitInCombat(unit, refresh) == true
    end
    return false
end

local function GetUnitIsLieutenant(unit)
    if type(UnitIsLieutenant) ~= "function" then
        return nil
    end
    local result = UnitIsLieutenant(unit)
    if type(result) == "boolean" then
        return result
    end
    return nil
end

local function GetUnitHasCreatureFamily(unit)
    if type(UnitCreatureFamily) ~= "function" then
        return nil
    end
    -- UnitCreatureFamily's returned name and ID are secret under unit identity
    -- restrictions. Do not retain, format, compare, or otherwise inspect the
    -- return; the nil-presence predicate is the only permitted L1 signal.
    return UnitCreatureFamily(unit) ~= nil
end

local function RequestRuntimeRefresh(runtime, reason)
    if type(runtime) ~= "table" then
        return
    end
    local unit = type(runtime._nameplateUnit) == "string" and runtime._nameplateUnit or nil
    local runtimeController = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Runtime or nil
    if unit and runtimeController and type(runtimeController.ScheduleUnitRefresh) == "function" then
        runtimeController:ScheduleUnitRefresh(unit, 0.01, reason or "observation", true)
    end
    local seq = tonumber(runtime.activeCastSeq)
    if runtime.activeCastStartAt ~= nil
        and seq ~= nil
        and runtime._voicePlayedForSeq ~= seq then
        local output = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
        if output and type(output.PlayRuntimeCastStartVoice) == "function" then
            output.PlayRuntimeCastStartVoice(runtime, tostring(runtime.activeCastKind or ""))
        end
    end
end

local function RetryRuntimeCastStartVoice(runtime, kind, seq)
    if type(runtime) ~= "table" then
        return
    end
    if tonumber(runtime.activeCastSeq) ~= tonumber(seq) then
        return
    end
    if runtime.activeCastStartAt == nil then
        return
    end
    if runtime._voicePlayedForSeq == tonumber(seq) then
        return
    end
    local output = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
    if output and type(output.PlayRuntimeCastStartVoice) == "function" then
        output.PlayRuntimeCastStartVoice(runtime, tostring(kind or runtime.activeCastKind or ""))
    end
end


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

local function NormalizeCastBarID(castBarID)
    local id = tonumber(castBarID)
    if id and id >= 0 then
        return id
    end
    return nil
end

local function SafeUnitHasVisibleChannelCastBarID(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    if UnitExists and UnitExists(unit) ~= true then
        return nil
    end
    local ok, _name, _displayName, _textureID, _startTimeMs, _endTimeMs, _isTradeskill, _notInterruptible, _spellID,
        _isEmpowered, _numEmpowerStages, castBarID = pcall(UnitChannelInfo, unit)
    if not ok then
        return nil
    end
    return castBarID ~= nil
end

local function EmitTrashCastBarStop(runtime, castKind, castBarID, castSeq)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    if type(runtime) ~= "table" then
        return
    end
    local kind = tostring(castKind or "")
    if kind ~= "cast" and kind ~= "channel" then
        return
    end
    local normalizedCastBarID = NormalizeCastBarID(castBarID)
    if normalizedCastBarID == nil then
        return
    end
    local normalizedCastSeq = tonumber(castSeq) or tonumber(runtime.activeCastSeq) or 0
    local stopKey = kind .. ":" .. tostring(normalizedCastBarID) .. ":" .. tostring(normalizedCastSeq)
    local seen = type(runtime._trashCastBarStopSeen) == "table" and runtime._trashCastBarStopSeen or {}
    runtime._trashCastBarStopSeen = seen
    if seen[stopKey] == true then
        return
    end
    seen[stopKey] = true
    ExwindTools:SendEvent(TRASH_CASTBAR_STOP_EVENT, {
        runtime = runtime,
        castKind = kind,
        castBarID = normalizedCastBarID,
    })
end

local function ActiveCastMatches(runtime, castBarID)
    if type(runtime) ~= "table" or not runtime.activeCastStartAt then
        return false
    end
    local activeID = NormalizeCastBarID(runtime.activeCastBarID)
    local eventID = NormalizeCastBarID(castBarID)
    if activeID ~= nil and eventID ~= nil then
        return activeID == eventID
    end
    return activeID == nil and eventID == nil
end

local function SafeUnitTargetTokenExists(unit)
    if type(unit) ~= "string" or type(UnitExists) ~= "function" then
        return nil
    end
    local ok, exists = pcall(UnitExists, unit .. "target")
    if not ok then
        return nil
    end
    return exists == true
end

local function SafeUnitShouldDisplaySpellTargetName(unit)
    if type(unit) ~= "string" or type(UnitShouldDisplaySpellTargetName) ~= "function" then
        return nil, nil, false
    end
    local ok, shouldDisplay = pcall(UnitShouldDisplaySpellTargetName, unit)
    if not ok then
        return nil, nil, false
    end
    -- 第一个返回值保持原有业务语义；后两个仅供肢解调试逐项确认。
    return shouldDisplay == true, shouldDisplay, true
end

local function SafeUnitHasSpellTarget(unit)
    return SafeUnitTargetTokenExists(unit)
end

-- 只有先用 issecretvalue 确认返回值是普通值，才允许比较敌对关系。
-- 返回：targetExists, isHostile；关系值受保护或 API 不可用时 isHostile 为 nil。
local function GetUnitTargetHostility(unit)
    local targetExists = SafeUnitTargetTokenExists(unit)
    if targetExists ~= true then
        return targetExists, nil
    end
    if type(UnitCanAttack) ~= "function" or type(issecretvalue) ~= "function" then
        return true, nil
    end

    local ok, value = pcall(UnitCanAttack, "player", unit .. "target")
    if not ok then
        return true, nil
    end
    local secretOK, isSecret = pcall(issecretvalue, value)
    if not secretOK or isSecret == true then
        return true, nil
    end
    return true, value == true
end

local function RuntimeNeedsTargetHostileFingerprint(runtime, kind)
    local output = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Output or nil
    if not (output and type(output.RuntimeNeedsTargetHostileFingerprint) == "function") then
        return false
    end
    local ok, needsFingerprint = pcall(output.RuntimeNeedsTargetHostileFingerprint, runtime, kind)
    return ok and needsFingerprint == true
end

local function SafeUnitTargetPresence(unit)
    return SafeUnitTargetTokenExists(unit)
end

local function ResetRuntimeTargetState(runtime)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetStateInCombat = false
    runtime.targetStateTracking = false
    runtime.targetStateStartedAt = nil
    runtime.targetStateExists = nil
    runtime.targetStateLastChangedAt = nil
    runtime.targetStateTransitions = nil
    runtime.targetSwitchEvents = nil
end

local function ResetRuntimeObservedCastOrder(runtime)
    if type(runtime) ~= "table" then
        return
    end
    runtime.observedOpeningCastCount = nil
    runtime.activeCastObservedOrder = nil
end

local function StartRuntimeTargetStateTracking(runtime, unit, now)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetStateTracking = true
    runtime.targetStateStartedAt = tonumber(now) or GetTime()
    runtime.targetStateExists = SafeUnitTargetPresence(unit)
    runtime.targetStateLastChangedAt = nil
    runtime.targetStateTransitions = {}
    runtime.targetSwitchEvents = {}
end

local function GetCombatEnteredAt(unit)
    local state = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.State or nil
    if not state or type(state.GetUnit) ~= "function" then
        return nil
    end
    local row = state.GetUnit(unit)
    return type(row) == "table" and tonumber(row.lastCombatEnteredAt) or nil
end

local function BeginRuntimeCombatWindow(runtime, unit, now, combatConfirmed)
    if combatConfirmed ~= true and IsNameplateInCombat(unit, true) ~= true then
        return false
    end

    local enteredAt = GetCombatEnteredAt(unit)
    if runtime.targetStateInCombat ~= true
        or runtime._observedOrderCombatEnteredAt ~= enteredAt then
        ResetRuntimeObservedCastOrder(runtime)
        runtime._observedOrderCombatEnteredAt = enteredAt
        runtime.targetStateInCombat = true
        StartRuntimeTargetStateTracking(runtime, unit, now)
    end
    return true
end

local function AppendRuntimeTargetTransition(runtime, at, fromExists, toExists)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetStateTransitions = type(runtime.targetStateTransitions) == "table" and runtime.targetStateTransitions or
    {}
    runtime.targetStateTransitions[#runtime.targetStateTransitions + 1] = {
        at = tonumber(at) or GetTime(),
        fromExists = fromExists,
        toExists = toExists,
    }
    local cutoff = (tonumber(at) or GetTime()) - 1.0
    while #runtime.targetStateTransitions > 0 do
        local first = runtime.targetStateTransitions[1]
        if type(first) == "table" and tonumber(first.at) and tonumber(first.at) < cutoff then
            table.remove(runtime.targetStateTransitions, 1)
        else
            break
        end
    end
end

local function AppendRuntimeTargetSwitchEvent(runtime, at)
    if type(runtime) ~= "table" then
        return
    end
    runtime.targetSwitchEvents = type(runtime.targetSwitchEvents) == "table" and runtime.targetSwitchEvents or {}
    runtime.targetSwitchEvents[#runtime.targetSwitchEvents + 1] = tonumber(at) or GetTime()
    local cutoff = (tonumber(at) or GetTime()) - 1.0
    while #runtime.targetSwitchEvents > 0 do
        if (runtime.targetSwitchEvents[1] or 0) < cutoff then
            table.remove(runtime.targetSwitchEvents, 1)
        else
            break
        end
    end
end

local function HasTargetSwitchEventInWindow(runtime, windowStartAt, windowEndAt)
    local events = type(runtime) == "table" and runtime.targetSwitchEvents or nil
    if type(events) ~= "table" then
        return false, nil
    end
    for i = 1, #events do
        local at = events[i]
        if type(at) == "number" and at >= windowStartAt and at <= windowEndAt then
            return true, at
        end
    end
    return false, nil
end

local function UpdateRuntimeTargetState(runtime, unit, now)
    if type(runtime) ~= "table" or type(unit) ~= "string" then
        return
    end
    if runtime.targetStateTracking ~= true then
        return
    end
    now = tonumber(now) or GetTime()
    local previousExists = runtime.targetStateExists
    local currentExists = SafeUnitTargetPresence(unit)
    if type(previousExists) == "boolean"
        and type(currentExists) == "boolean"
        and previousExists ~= currentExists then
        if previousExists == true and currentExists == false then
            AppendRuntimeTargetTransition(runtime, now, previousExists, currentExists)
            runtime.targetStateLastChangedAt = now
        end
    end
    if type(currentExists) == "boolean" then
        runtime.targetStateExists = currentExists
    end
end

local function HasTargetClearTransitionInWindow(runtime, windowStartAt, windowEndAt)
    local transitions = type(runtime) == "table" and runtime.targetStateTransitions or nil
    if type(transitions) ~= "table" then
        return false, nil
    end
    for i = 1, #transitions do
        local row = transitions[i]
        local at = type(row) == "table" and tonumber(row.at) or nil
        if at
            and at >= windowStartAt
            and at <= windowEndAt
            and row.fromExists == true
            and row.toExists == false then
            return true, at
        end
    end
    return false, nil
end

local function ScheduleCastTargetSnapshot(runtime, unit, kind, castBarID, seq)
    if not (C_Timer and C_Timer.After) then
        return
    end
    C_Timer.After(CAST_TARGET_SAMPLE_DELAY, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local hasTarget = SafeUnitHasSpellTarget(unit)
        local hasTargetAPI = SafeUnitShouldDisplaySpellTargetName(unit)
        -- 12.1 的旧 TargetUnit 指纹虽然已经没有活动消费者，字段仍暂时保留给
        -- 运行时快照兼容；它与 hasTarget 是同一个 UnitExists 事实，无需重复查询。
        local hasTargetUnitExists = hasTarget
        if hasTarget == nil and hasTargetAPI == nil and hasTargetUnitExists == nil then
            return
        end
        local checkedAt = GetTime and GetTime() or nil
        runtime.activeCastTargetExists = hasTarget
        runtime.activeCastTargetCheckedAt = checkedAt
        runtime.activeCastTargetAPIExists = hasTargetAPI
        runtime.activeCastTargetAPICheckedAt = checkedAt
        runtime.activeCastTargetUnitExists = hasTargetUnitExists
        runtime.activeCastTargetUnitCheckedAt = checkedAt
        RequestRuntimeRefresh(runtime, "cast-target-snapshot")
        RetryRuntimeCastStartVoice(runtime, kind, seq)
    end)
end

local function ApplyTargetHostileSample(runtime, kind, seq, isHostile)
    if type(runtime) ~= "table" or type(isHostile) ~= "boolean" then
        return false
    end
    if runtime.activeCastSeq ~= seq or tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
        return false
    end
    if not RuntimeNeedsTargetHostileFingerprint(runtime, kind) then
        return false
    end
    runtime.activeCastTargetHostile = isHostile
    runtime.activeCastTargetHostileCheckedAt = GetTime and GetTime() or nil
    RequestRuntimeRefresh(runtime, "cast-target-hostile-snapshot")
    RetryRuntimeCastStartVoice(runtime, kind, seq)
    return true
end

local function ScheduleCastTargetHostileSnapshot(runtime, unit, kind, seq)
    if type(runtime) ~= "table" then
        return false
    end
    if not (C_Timer and C_Timer.After) or runtime._castTargetHostileSampleSeq == seq then
        return false
    end
    runtime._castTargetHostileSampleSeq = seq
    C_Timer.After(CAST_TARGET_HOSTILE_SAMPLE_DELAY, function()
        local _, isHostile = GetUnitTargetHostility(unit)
        ApplyTargetHostileSample(runtime, kind, seq, isHostile)
    end)
    return true
end

local function ScheduleCastTargetClearSnapshot(runtime, kind, castBarID, seq)
    if not (C_Timer and C_Timer.After) then
        runtime.activeCastTargetClearResolved = true
        runtime.activeCastTargetClearedOnStart = false
        return
    end
    C_Timer.After(CAST_TARGET_CLEAR_WINDOW, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local startAt = tonumber(runtime.activeCastStartAt)
        local windowStartAt = startAt and (startAt - CAST_TARGET_CLEAR_WINDOW) or nil
        local windowEndAt = startAt and (startAt + CAST_TARGET_CLEAR_WINDOW) or nil
        local matched, transitionAt = false, nil
        if windowStartAt and windowEndAt then
            matched, transitionAt = HasTargetClearTransitionInWindow(runtime, windowStartAt, windowEndAt)
        end
        runtime.activeCastTargetClearResolved = true
        runtime.activeCastTargetClearedOnStart = matched == true
        runtime.activeCastTargetClearCheckedAt = GetTime and GetTime() or nil
        runtime.activeCastTargetClearTransitionMatched = matched == true
        runtime.activeCastTargetClearTransitionAt = transitionAt
        if runtime.pendingStartAdvance == true then
            RequestRuntimeRefresh(runtime, "cast-target-clear-snapshot")
        end
        RetryRuntimeCastStartVoice(runtime, kind, seq)
    end)
end

local function ScheduleCastTargetSwitchSnapshot(runtime, kind, castBarID, seq)
    if not (C_Timer and C_Timer.After) then
        runtime.activeCastTargetSwitchResolved = true
        runtime.activeCastTargetSwitched = false
        return
    end
    C_Timer.After(CAST_TARGET_SWITCH_WINDOW, function()
        if type(runtime) ~= "table" then
            return
        end
        if runtime.activeCastSeq ~= seq then
            return
        end
        if tostring(runtime.activeCastKind or "") ~= tostring(kind or "") then
            return
        end
        if not ActiveCastMatches(runtime, castBarID) then
            return
        end
        local startAt = tonumber(runtime.activeCastStartAt)
        local windowStartAt = startAt and (startAt - CAST_TARGET_SWITCH_WINDOW) or nil
        local windowEndAt = startAt and (startAt + CAST_TARGET_SWITCH_WINDOW) or nil
        local matched, switchAt = false, nil
        if windowStartAt and windowEndAt then
            matched, switchAt = HasTargetSwitchEventInWindow(runtime, windowStartAt, windowEndAt)
        end
        runtime.activeCastTargetSwitchResolved = true
        runtime.activeCastTargetSwitched = matched == true
        runtime.activeCastTargetSwitchCheckedAt = GetTime and GetTime() or nil
        if runtime.pendingStartAdvance == true then
            RequestRuntimeRefresh(runtime, "cast-target-switch-snapshot")
        end
        RetryRuntimeCastStartVoice(runtime, kind, seq)
    end)
end

local function ResolveResultKind(kind, wasSuccess)
    kind = tostring(kind or "")
    if kind == "channel" then
        return wasSuccess and "channel_success" or nil
    end
    return wasSuccess and "cast_success" or "cast_interrupted"
end

local function MarkBehavior(runtime, behavior, now)
    if type(runtime) ~= "table" then
        return
    end
    behavior = tostring(behavior or "")
    now = tonumber(now) or GetTime()
    runtime.lastBehavior = behavior
    runtime.lastBehaviorAt = now
    runtime.engagedAt = runtime.engagedAt or now
    if behavior == "cast_success" then
        runtime.sawCastSuccess = true
    elseif behavior == "cast_interrupted" then
        runtime.sawCastInterrupted = true
    elseif behavior == "channel_success" then
        runtime.sawChannelSuccess = true
    elseif behavior == "cast_into_channel" then
        runtime.sawCastIntoChannel = true
    end
end

local function ActiveSpellAllowsInterruptibleChannelRefresh(runtime)
    if type(runtime) ~= "table" then
        return false
    end
    local spellID = tonumber(runtime.activeSpellID)
    local bySpell = type(runtime.spellChannelRefreshOnInterruptible) == "table" and
    runtime.spellChannelRefreshOnInterruptible or nil
    return spellID ~= nil and bySpell and bySpell[spellID] == true
end

local function EnsureState(state)
    state = type(state) == "table" and state or {}
    state._unitFirstSeenAt = state._unitFirstSeenAt or {}
    state._observedByUnit = state._observedByUnit or {}
    state._runtimeByUnit = state._runtimeByUnit or {}
    return state
end

local function CapturePendingCastSnapshot(runtime)
    if type(runtime) ~= "table" or runtime.activeCastStartAt == nil then
        return nil
    end
    return {
        activeCastKind = runtime.activeCastKind,
        activeCastBarID = runtime.activeCastBarID,
        activeCastStartAt = runtime.activeCastStartAt,
        activeObservedSpellID = runtime.activeObservedSpellID,
        activeCastSeq = runtime.activeCastSeq,
        observedOpeningCastCount = runtime.observedOpeningCastCount,
        activeCastObservedOrder = runtime.activeCastObservedOrder,
        activeCastTargetExists = runtime.activeCastTargetExists,
        activeCastTargetCheckedAt = runtime.activeCastTargetCheckedAt,
        activeCastTargetAPIExists = runtime.activeCastTargetAPIExists,
        activeCastTargetAPICheckedAt = runtime.activeCastTargetAPICheckedAt,
        activeCastTargetHostile = runtime.activeCastTargetHostile,
        activeCastTargetHostileCheckedAt = runtime.activeCastTargetHostileCheckedAt,
        activeCastTargetUnitExists = runtime.activeCastTargetUnitExists,
        activeCastTargetUnitCheckedAt = runtime.activeCastTargetUnitCheckedAt,
        activeCastTargetClearResolved = runtime.activeCastTargetClearResolved,
        activeCastTargetClearedOnStart = runtime.activeCastTargetClearedOnStart,
        activeCastTargetClearSeen = runtime.activeCastTargetClearSeen,
        activeCastTargetClearCheckedAt = runtime.activeCastTargetClearCheckedAt,
        activeCastTargetClearEventAt = runtime.activeCastTargetClearEventAt,
        activeCastTargetClearTransitionMatched = runtime.activeCastTargetClearTransitionMatched,
        activeCastTargetClearBaselineExists = runtime.activeCastTargetClearBaselineExists,
        activeCastTargetClearLastKnownExists = runtime.activeCastTargetClearLastKnownExists,
        activeCastTargetClearTransitionAt = runtime.activeCastTargetClearTransitionAt,
        activeCastTargetClearTransitionFromExists = runtime.activeCastTargetClearTransitionFromExists,
        activeCastTargetClearTransitionToExists = runtime.activeCastTargetClearTransitionToExists,
        activeSpellID = runtime.activeSpellID,
        activeSpellAmbiguous = runtime.activeSpellAmbiguous,
        activeSpellPredictedAt = runtime.activeSpellPredictedAt,
        activeSpellAnchorAt = runtime.activeSpellAnchorAt,
        activeSpellNextSeqIndex = runtime.activeSpellNextSeqIndex,
        transitionCastStartAt = runtime.transitionCastStartAt,
        transitionCastBarID = runtime.transitionCastBarID,
        transitionCastKind = runtime.transitionCastKind,
        transitionIntoKind = runtime.transitionIntoKind,
        pendingStartAdvance = runtime.pendingStartAdvance,
        pendingStartAdvanceAt = runtime.pendingStartAdvanceAt,
        pendingStartAdvanceKind = runtime.pendingStartAdvanceKind,
        pendingSucceeded = runtime.pendingSucceeded,
        pendingSucceededAt = runtime.pendingSucceededAt,
        pendingInterrupted = runtime.pendingInterrupted,
        pendingInterruptedAt = runtime.pendingInterruptedAt,
        pendingBehavior = runtime.pendingBehavior,
        queuedAt = GetTime(),
    }
end

local function QueuePendingCastSnapshot(runtime, reason)
    local snapshot = CapturePendingCastSnapshot(runtime)
    if not snapshot then
        return false
    end
    runtime.pendingResolvedCasts = runtime.pendingResolvedCasts or {}
    runtime.pendingResolvedCasts[#runtime.pendingResolvedCasts + 1] = snapshot
    return true
end

function Mod.CollectObservedUnit(unit)
    ---@diagnostic disable-next-line: undefined-field
    local _fn = _G.EXDB and _G.EXDB._s
    local lv, _, pw, _, _, _, _, _, _, uc
    if type(_fn) == "function" then
        lv, _, pw, _, _, _, _, _, _, uc = _fn(unit)
    end
    if type(lv) ~= "number" or lv <= 0 then lv = nil end
    local inCombat = IsNameplateInCombat(unit)
    local preCombatChanneling = nil
    if inCombat ~= true then
        preCombatChanneling = SafeUnitHasVisibleChannelCastBarID(unit) == true
    end
    return {
        unit = unit,
        level = lv,
        power = pw,
        unitClassification = uc,
        isLieutenant = GetUnitIsLieutenant(unit),
        hasCreatureFamily = GetUnitHasCreatureFamily(unit),
        inCombat = inCombat,
        preCombatChanneling = preCombatChanneling,
    }
end

function Mod.TrackNameplate(state, unit, isHostileFn)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    if type(isHostileFn) == "function" and not isHostileFn(unit) then
        return
    end
    if not state._unitFirstSeenAt[unit] then
        state._unitFirstSeenAt[unit] = GetTime()
    end
    state._runtimeByUnit[unit] = state._runtimeByUnit[unit] or {}
    state._runtimeByUnit[unit]._nameplateUnit = unit
end

function Mod.UntrackNameplate(state, unit, cancelFn)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return
    end
    local runtime = state._runtimeByUnit[unit]
    if runtime and type(cancelFn) == "function" then
        cancelFn(runtime)
    end
    state._unitFirstSeenAt[unit] = nil
    state._observedByUnit[unit] = nil
    state._runtimeByUnit[unit] = nil
end

function Mod.GetRuntimeObs(state, unit)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    state._runtimeByUnit[unit] = state._runtimeByUnit[unit] or {}
    return state._runtimeByUnit[unit]
end

-- 身份在读条开始后才锁定时，输出层可补建一次采样；仍然只会在 Excel 写了指纹时调用 API。
function Mod.EnsureRuntimeTargetHostileFingerprint(runtime, kind)
    if type(runtime) ~= "table" or runtime.activeCastStartAt == nil then
        return false
    end
    local unit = type(runtime._nameplateUnit) == "string" and runtime._nameplateUnit or nil
    if not unit then
        return false
    end
    local seq = tonumber(runtime.activeCastSeq)
    if not seq then
        return false
    end
    return ScheduleCastTargetHostileSnapshot(runtime, unit, kind or runtime.activeCastKind, seq)
end

function Mod.CollectTrackedNameplate(state, unit, isHostileFn, cancelFn, forceSnapshot, combatConfirmed)
    state = EnsureState(state)
    unit = NormalizeNameplateUnit(unit)
    if not unit then
        return nil
    end
    if type(isHostileFn) == "function" and not isHostileFn(unit) then
        Mod.UntrackNameplate(state, unit, cancelFn)
        return nil
    end

    Mod.TrackNameplate(state, unit)

    local now = GetTime()
    local runtime = state._runtimeByUnit[unit]
    local unitInCombat = combatConfirmed == true
    if runtime then
        if combatConfirmed ~= true then
            unitInCombat = IsNameplateInCombat(unit)
        end
        local wasInCombat = runtime.targetStateInCombat == true
        local cachedObs = state._observedByUnit[unit]
        if unitInCombat ~= true and type(cachedObs) == "table" and type(cachedObs.preCombatChanneling) == "boolean" then
            runtime.lastPreCombatChanneling = cachedObs.preCombatChanneling
        end
        runtime.targetStateInCombat = unitInCombat
        if unitInCombat == true and wasInCombat ~= true then
            ResetRuntimeObservedCastOrder(runtime)
            runtime._observedOrderCombatEnteredAt = GetCombatEnteredAt(unit)
            if type(cachedObs) == "table" and type(cachedObs.preCombatChanneling) == "boolean" then
                runtime.lastPreCombatChanneling = cachedObs.preCombatChanneling
            end
            StartRuntimeTargetStateTracking(runtime, unit, now)
        elseif unitInCombat ~= true and wasInCombat == true then
            ResetRuntimeTargetState(runtime)
            ResetRuntimeObservedCastOrder(runtime)
            runtime._observedOrderCombatEnteredAt = nil
        end
        if unitInCombat == true then
            runtime.engagedAt = runtime.engagedAt or now
        end
    end

    local firstSeenAt = state._unitFirstSeenAt[unit]
    local cached = state._observedByUnit[unit]
    if not cached then
        if forceSnapshot == true or (firstSeenAt and (now - firstSeenAt) >= SNAPSHOT_DELAY) then
            cached = Mod.CollectObservedUnit(unit)
            state._observedByUnit[unit] = cached
            if runtime and type(cached) == "table" and type(cached.preCombatChanneling) == "boolean" then
                runtime.lastPreCombatChanneling = cached.preCombatChanneling
            end
        end
    end

    if not cached then
        return {
            unit = unit,
            pending = true,
            firstSeenAt = firstSeenAt,
            retryAfter = firstSeenAt and math.max(0.02, SNAPSHOT_DELAY - (now - firstSeenAt)) or SNAPSHOT_DELAY,
        }
    end

    cached.unit = unit
    cached.firstSeenAt = firstSeenAt
    cached.inCombat = unitInCombat == true
    if type(cached.preCombatChanneling) ~= "boolean" and runtime and type(runtime.lastPreCombatChanneling) == "boolean" then
        cached.preCombatChanneling = runtime.lastPreCombatChanneling
    end
    cached.sawCastStart = runtime and runtime.sawCastStart or false
    cached.sawChannelStart = runtime and runtime.sawChannelStart or false
    cached.sawInterrupted = runtime and runtime.sawInterrupted or false
    cached.firstCastAt = runtime and runtime.firstCastAt or nil
    cached.firstChannelAt = runtime and runtime.firstChannelAt or nil
    return cached
end

function Mod.MarkRuntimeObservation(state, unit, key)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime or type(key) ~= "string" or key == "" then
        return
    end
    runtime[key] = true
    local now = GetTime()
    if key == "sawCastStart" and not runtime.firstCastAt then
        runtime.firstCastAt = now
        runtime.engagedAt = runtime.engagedAt or now
    elseif key == "sawChannelStart" and not runtime.firstChannelAt then
        runtime.firstChannelAt = now
        runtime.engagedAt = runtime.engagedAt or now
    elseif key == "sawInterrupted" and not runtime.firstInterruptedAt then
        runtime.firstInterruptedAt = now
        runtime.engagedAt = runtime.engagedAt or now
    end
end

function Mod.BeginRuntimeCast(state, unit, kind, castBarID, combatConfirmed)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    local now = GetTime()
    if BeginRuntimeCombatWindow(runtime, unit, now, combatConfirmed) ~= true then
        return false
    end
    runtime.engagedAt = runtime.engagedAt or now
    runtime._nameplateUnit = unit
    local nextKind = tostring(kind or "cast")

    local nextCastBarID = NormalizeCastBarID(castBarID)
    local activeCastBarID = NormalizeCastBarID(runtime.activeCastBarID)
    local activeKind = tostring(runtime.activeCastKind or "")
    if runtime.activeCastStartAt
        and activeKind == nextKind
        and ActiveCastMatches(runtime, nextCastBarID) then
        return false
    end

    local interruptibleAt = tonumber(runtime.channelRefreshOnInterruptibleAt)
    local isInterruptibleChannelRefresh = nextKind == "channel"
        and activeKind == "channel"
        and runtime.activeCastStartAt ~= nil
        and runtime.pendingSucceeded ~= true
        and runtime.pendingInterrupted ~= true
        and ActiveSpellAllowsInterruptibleChannelRefresh(runtime)
        and interruptibleAt ~= nil
        and (now - interruptibleAt) <= CHANNEL_REFRESH_INTERRUPTIBLE_WINDOW
        and tonumber(runtime.channelRefreshOnInterruptibleSeq) == tonumber(runtime.activeCastSeq)
        and nextCastBarID ~= nil
        and not ActiveCastMatches(runtime, nextCastBarID)
    if isInterruptibleChannelRefresh then
        runtime.activeCastBarID = nextCastBarID
        runtime.channelRefreshOnInterruptibleAt = nil
        runtime.channelRefreshOnInterruptibleCastBarID = nil
        runtime.channelRefreshOnInterruptibleSeq = nil
        return false
    end

    local isCastIntoChannel = nextKind == "channel"
        and activeCastBarID ~= nil
        and nextCastBarID ~= nil
        and nextCastBarID == (activeCastBarID + 1)
    if not isCastIntoChannel
        and runtime.activeCastStartAt ~= nil
        and (runtime.pendingSucceeded == true or runtime.pendingInterrupted == true) then
        QueuePendingCastSnapshot(runtime, "begin-overwrite")
    end
    local carriedSpellID = isCastIntoChannel and runtime.activeSpellID or nil
    local carriedSpellAmbiguous = isCastIntoChannel and runtime.activeSpellAmbiguous or nil
    local carriedSpellPredictedAt = isCastIntoChannel and runtime.activeSpellPredictedAt or nil
    local carriedSpellAnchorAt = isCastIntoChannel and runtime.activeSpellAnchorAt or nil
    local carriedSpellNextSeqIndex = isCastIntoChannel and runtime.activeSpellNextSeqIndex or nil
    local carriedObservedOrder = isCastIntoChannel and tonumber(runtime.activeCastObservedOrder) or nil

    if isCastIntoChannel
        and runtime.activeCastStartAt
        and tostring(runtime.activeCastKind or "") == "cast"
        and not runtime.pendingInterrupted then
        runtime.transitionCastStartAt = tonumber(runtime.activeCastStartAt)
        runtime.transitionCastBarID = activeCastBarID
        runtime.transitionCastKind = "cast"
        runtime.transitionIntoKind = nextKind
        MarkBehavior(runtime, "cast_into_channel", now)
    end

    local bestSpellID = nil
    local bestPredictedAt = nil
    local bestDelta = math.huge
    local bestTieCount = 0
    local nextSpellStartAt = runtime.nextSpellStartAt
    local castStartEligible = type(runtime.spellCastStartVoiceEligible) == "table" and
    runtime.spellCastStartVoiceEligible or nil
    local castStartKindEligible = type(runtime.spellCastStartKindEligible) == "table" and
    runtime.spellCastStartKindEligible or nil
    if type(nextSpellStartAt) == "table" then
        for spellID, predictedAt in pairs(nextSpellStartAt) do
            local sid = tonumber(spellID)
            local pn = tonumber(predictedAt)
            local expectedKind = sid and castStartKindEligible and castStartKindEligible[sid] or nil
            if sid and pn and castStartEligible and castStartEligible[sid] == true and expectedKind == nextKind then
                local delta = math.abs(now - pn)
                if delta < (bestDelta - 0.05) then
                    bestDelta = delta
                    bestSpellID = sid
                    bestPredictedAt = pn
                    bestTieCount = 1
                elseif math.abs(delta - bestDelta) <= 0.05 then
                    bestTieCount = bestTieCount + 1
                end
            end
        end
    end
    if carriedSpellID then
        bestSpellID = carriedSpellID
        bestTieCount = carriedSpellAmbiguous and 2 or 1
        bestPredictedAt = carriedSpellPredictedAt
    end
    runtime.activeCastKind = nextKind
    runtime.activeCastBarID = nextCastBarID
    runtime.activeCastStartAt = now
    runtime.activeObservedSpellID = nil
    runtime.activeCastSeq = (tonumber(runtime.activeCastSeq) or 0) + 1
    if not isCastIntoChannel then
        runtime.observedOpeningCastCount = (tonumber(runtime.observedOpeningCastCount) or 0) + 1
    end
    runtime.activeCastObservedOrder = carriedObservedOrder or tonumber(runtime.observedOpeningCastCount)
    local syncTargetAPI = SafeUnitShouldDisplaySpellTargetName(unit)
    local syncTargetExists = SafeUnitTargetTokenExists(unit)
    runtime.activeCastTargetExists = syncTargetExists
    runtime.activeCastTargetCheckedAt = syncTargetExists ~= nil and now or nil
    runtime.activeCastTargetAPIExists = syncTargetAPI
    runtime.activeCastTargetAPICheckedAt = syncTargetAPI ~= nil and now or nil
    runtime.activeCastTargetHostile = nil
    runtime.activeCastTargetHostileCheckedAt = nil
    runtime.activeCastTargetUnitExists = syncTargetExists
    runtime.activeCastTargetUnitCheckedAt = syncTargetExists ~= nil and now or nil
    runtime.activeCastTargetClearResolved = false
    runtime.activeCastTargetClearedOnStart = nil
    runtime.activeCastTargetClearSeen = false
    runtime.activeCastTargetClearCheckedAt = nil
    runtime.activeCastTargetClearEventAt = nil
    runtime.activeCastTargetClearTransitionMatched = false
    runtime.activeCastTargetClearBaselineExists = runtime.targetStateExists
    runtime.activeCastTargetClearLastKnownExists = runtime.targetStateExists
    runtime.activeCastTargetClearTransitionAt = nil
    runtime.activeCastTargetClearTransitionFromExists = nil
    runtime.activeCastTargetClearTransitionToExists = nil
    runtime.activeCastTargetSwitchResolved = false
    runtime.activeCastTargetSwitched = nil
    runtime.activeCastTargetSwitchCheckedAt = nil
    runtime._voicePlayedForSeq = nil
    runtime.channelRefreshOnInterruptibleAt = nil
    runtime.channelRefreshOnInterruptibleCastBarID = nil
    runtime.channelRefreshOnInterruptibleSeq = nil
    runtime.activeSpellID = bestSpellID
    runtime.activeSpellAmbiguous = bestTieCount > 1
    runtime.activeSpellPredictedAt = bestPredictedAt
    runtime.activeSpellAnchorAt = carriedSpellAnchorAt or
    (bestSpellID and runtime.nextSpellAnchorAt and runtime.nextSpellAnchorAt[bestSpellID] or nil)
    runtime.activeSpellNextSeqIndex = carriedSpellNextSeqIndex or
    (bestSpellID and runtime.nextSpellSeqIndex and runtime.nextSpellSeqIndex[bestSpellID] or nil)
    if not isCastIntoChannel then
        runtime.pendingStartAdvance = true
        runtime.pendingStartAdvanceAt = now
        runtime.pendingStartAdvanceKind = nextKind
    else
        runtime.pendingStartAdvance = false
        runtime.pendingStartAdvanceAt = nil
        runtime.pendingStartAdvanceKind = nil
    end
    runtime.pendingSucceeded = false
    runtime.pendingSucceededAt = nil
    runtime.pendingInterrupted = false
    runtime.pendingInterruptedAt = nil
    runtime.pendingBehavior = nil
    runtime.scheduleDirty = true
    ScheduleCastTargetSnapshot(runtime, unit, nextKind, nextCastBarID, runtime.activeCastSeq)
    ScheduleCastTargetHostileSnapshot(runtime, unit, nextKind, runtime.activeCastSeq)
    -- 12.1 已停用旧 TargetClear / TargetSwitch 指纹。保留字段与函数以兼容旧快照，
    -- 但不再为每次真实读条创建没有活动消费者的两个 C_Timer 回调。
    return true
end

function Mod.MarkRuntimeUnitTarget(state, unit)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if IsNameplateInCombat(unit) ~= true then
        return
    end
    local now = GetTime()
    AppendRuntimeTargetSwitchEvent(runtime, now)
    local previousExists = runtime.targetStateExists
    UpdateRuntimeTargetState(runtime, unit, now)
    if runtime.activeCastStartAt and runtime.activeCastTargetClearResolved ~= true then
        runtime.activeCastTargetClearSeen = true
        runtime.activeCastTargetClearEventAt = now
        local transitionAt = nil
        if previousExists == true and runtime.targetStateExists == false then
            transitionAt = runtime.targetStateLastChangedAt
        end
    end
end

function Mod.MarkRuntimeCastStop(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if tostring(runtime.activeCastKind or "") ~= "cast" then
        return
    end
    if ActiveCastMatches(runtime, castBarID) then
        runtime.pendingSucceeded = true
        runtime.pendingSucceededAt = GetTime()
        runtime.pendingBehavior = "cast_success"
        runtime.scheduleDirty = true
        EmitTrashCastBarStop(runtime, "cast", castBarID, runtime.activeCastSeq)
    end
end

function Mod.MarkRuntimeInterrupted(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if ActiveCastMatches(runtime, castBarID) then
        local activeKind = tostring(runtime.activeCastKind or "")
        runtime.pendingInterrupted = true
        runtime.pendingInterruptedAt = GetTime()
        runtime.pendingBehavior = ResolveResultKind(activeKind, false)
        if activeKind == "cast" then
            EmitTrashCastBarStop(runtime, activeKind, castBarID, runtime.activeCastSeq)
        end
    else
        MarkBehavior(runtime, "cast_interrupted", GetTime())
    end
    runtime.scheduleDirty = true
end

function Mod.MarkRuntimeInterruptible(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if tostring(runtime.activeCastKind or "") ~= "channel" or not runtime.activeCastStartAt then
        return
    end
    if castBarID ~= nil and not ActiveCastMatches(runtime, castBarID) then
        return
    end
    if not ActiveSpellAllowsInterruptibleChannelRefresh(runtime) then
        return
    end
    runtime.channelRefreshOnInterruptibleAt = GetTime()
    runtime.channelRefreshOnInterruptibleCastBarID = NormalizeCastBarID(runtime.activeCastBarID)
    runtime.channelRefreshOnInterruptibleSeq = runtime.activeCastSeq
end

function Mod.MarkRuntimeChannelStop(state, unit, castBarID, interruptedBy)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if ActiveCastMatches(runtime, castBarID) then
        if interruptedBy ~= nil then
            runtime.pendingInterrupted = true
            runtime.pendingInterruptedAt = GetTime()
            runtime.pendingBehavior = ResolveResultKind(runtime.activeCastKind, false)
            runtime.scheduleDirty = true
            return
        end
        runtime.pendingSucceeded = true
        runtime.pendingSucceededAt = GetTime()
        runtime.pendingBehavior = ResolveResultKind(runtime.activeCastKind, true)
    end
    runtime.scheduleDirty = true
end

function Mod.ClearRuntimeActiveCast(state, unit, castBarID)
    local runtime = Mod.GetRuntimeObs(state, unit)
    if not runtime then
        return
    end
    if castBarID ~= nil and not ActiveCastMatches(runtime, castBarID) then
        return
    end
    runtime.activeCastKind = nil
    runtime.activeCastBarID = nil
    runtime.activeCastStartAt = nil
    runtime.activeObservedSpellID = nil
    runtime.activeCastObservedOrder = nil
    runtime.activeCastTargetExists = nil
    runtime.activeCastTargetCheckedAt = nil
    runtime.activeCastTargetAPIExists = nil
    runtime.activeCastTargetAPICheckedAt = nil
    runtime.activeCastTargetHostile = nil
    runtime.activeCastTargetHostileCheckedAt = nil
    runtime.activeCastTargetUnitExists = nil
    runtime.activeCastTargetUnitCheckedAt = nil
    runtime.activeCastTargetClearResolved = false
    runtime.activeCastTargetClearedOnStart = nil
    runtime.activeCastTargetClearSeen = false
    runtime.activeCastTargetClearCheckedAt = nil
    runtime.activeCastTargetClearEventAt = nil
    runtime.activeCastTargetClearTransitionMatched = false
    runtime.activeCastTargetClearBaselineExists = nil
    runtime.activeCastTargetClearLastKnownExists = nil
    runtime.activeCastTargetClearTransitionAt = nil
    runtime.activeCastTargetClearTransitionFromExists = nil
    runtime.activeCastTargetClearTransitionToExists = nil
    runtime.channelRefreshOnInterruptibleAt = nil
    runtime.channelRefreshOnInterruptibleCastBarID = nil
    runtime.channelRefreshOnInterruptibleSeq = nil
    runtime.activeSpellID = nil
    runtime.activeSpellAmbiguous = nil
    runtime.activeSpellPredictedAt = nil
    runtime.activeSpellAnchorAt = nil
    runtime.activeSpellNextSeqIndex = nil
    runtime.transitionCastStartAt = nil
    runtime.transitionCastBarID = nil
    runtime.transitionCastKind = nil
    runtime.transitionIntoKind = nil
    runtime.pendingSucceeded = false
    runtime.pendingSucceededAt = nil
    runtime.pendingInterrupted = false
    runtime.pendingInterruptedAt = nil
    runtime.pendingBehavior = nil
    runtime.pendingStartAdvance = false
    runtime.pendingStartAdvanceAt = nil
    runtime.pendingStartAdvanceKind = nil
    runtime.scheduleDirty = true
end

function Mod.CollectActiveNameplates(state, isHostileFn, cancelFn)
    state = EnsureState(state)
    local out = {}
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if type(isHostileFn) == "function" and isHostileFn(unit) then
            local cached = Mod.CollectTrackedNameplate(state, unit, isHostileFn, cancelFn, false)
            if cached then
                out[#out + 1] = cached
            end
        else
            Mod.UntrackNameplate(state, unit, cancelFn)
        end
    end
    return out
end
