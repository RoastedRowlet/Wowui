---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/TimerEventEmitter.lua
-- 统一收口 Scheduler 对外广播的 timer 相关事件（EXwindTools:SendEvent）。
-- 纯粹的 payload 构造 + 广播，不持有任何状态，不做推理/判断。
-- 迁移自 Scheduler.lua，见 Scheduler重构计划.md §3.5。
-- =============================================================

ExBoss.Timeline.TimerEventEmitter = ExBoss.Timeline.TimerEventEmitter or {}
local Emitter = ExBoss.Timeline.TimerEventEmitter

local FIXED_AI_EVENT_SCHEDULED_EVENT   = "EXBOSS_FIXED_AI_EVENT_SCHEDULED"
local FIXED_AI_EVENT_FINISHED_EVENT    = "EXBOSS_FIXED_AI_EVENT_FINISHED"
local TIMER_FIVE_SEC_REMAINING_EVENT   = "EXBOSS_TIMER_FIVE_SEC_REMAINING"

local function SafeToNumber(v)
    local ok, n = pcall(tonumber, v)
    if ok then
        return n
    end
    return nil
end

function Emitter.PublishFixedAIEventScheduled(scheduler, timer, eventID, duration, observedAt, castTime, syncMode)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    local now = GetTime()
    ExwindTools:SendEvent(FIXED_AI_EVENT_SCHEDULED_EVENT, {
        encounterID = scheduler and scheduler._encounterID or nil,
        eventID = SafeToNumber(eventID),
        timerID = SafeToNumber(timer and timer.id),
        duration = SafeToNumber(duration),
        observedAt = SafeToNumber(observedAt),
        castTime = SafeToNumber(castTime),
        remaining = math.max(0, (SafeToNumber(castTime) or now) - now),
        source = "fixed_ai",
        syncMode = syncMode == true,
        spellID = SafeToNumber(timer and timer.spellID),
        spellIdentifier = SafeToNumber(timer and timer.spellIdentifier),
        displayName = tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
        occurrenceCount = SafeToNumber(timer and timer.occurrenceCount),
    })
end

function Emitter.PublishFixedAIEventFinished(scheduler, timer)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    local now = GetTime()
    ExwindTools:SendEvent(FIXED_AI_EVENT_FINISHED_EVENT, {
        encounterID = scheduler and scheduler._encounterID or nil,
        eventID = SafeToNumber(timer and timer.eventID),
        timerID = SafeToNumber(timer and timer.id),
        timelineEventID = SafeToNumber(timer and timer.fixedAITimelineEventID),
        fireAt = now,
        source = "fixed_ai",
        finishSource = "blizzard_timeline",
        spellID = SafeToNumber(timer and timer.spellID),
        spellIdentifier = SafeToNumber(timer and timer.spellIdentifier),
        displayName = tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
    })
end

-- timer.fiveSecBroadcastFired 的置位由调用方（Scheduler:_OnUpdate）负责，
-- 这里只做纯广播，不碰 timer 的生命周期标志位。
function Emitter.PublishTimerFiveSecRemaining(timer, encounterID, remaining)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    ExwindTools:SendEvent(TIMER_FIVE_SEC_REMAINING_EVENT, {
        timerID     = timer.id,
        eventID     = SafeToNumber(timer.eventID),
        encounterID = encounterID,
        remaining   = remaining,
        castTime    = timer.castTime,
        source      = timer.source,
        spellID     = SafeToNumber(timer.spellID),
        displayName = timer.displayName,
    })
end
