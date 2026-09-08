---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/TimelineAddedBuffer.lua
-- 暴雪原生时间轴 ENCOUNTER_TIMELINE_EVENT_ADDED 事件的缓冲/去重/状态查询层。
-- 只负责：入队候选事件、按 duration 去重过滤、查询暴雪 timeline API 状态。
-- 不负责创建/挂接 timer（那是 Scheduler:_AttachTimelineEventByID 的职责）。
-- 迁移自 Scheduler.lua，见 Scheduler重构计划.md §3.3。
-- =============================================================

ExBoss.Timeline.TimelineAddedBuffer = ExBoss.Timeline.TimelineAddedBuffer or {}
local Buffer = ExBoss.Timeline.TimelineAddedBuffer

local TIMELINE_ADDED_CONFIRM_DELAY           = 0.20
local TIMELINE_MAX_EVENT_DURATION            = 120
local TIMELINE_DURATION_KEY_SCALE            = 10
local FIXED_DRIVER_AI                        = "ai"
local TIMELINE_SOURCE_ENCOUNTER              = Enum and Enum.EncounterTimelineEventSource and
    Enum.EncounterTimelineEventSource.Encounter or 0
local STATE_ACTIVE                           = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState.Active or 0
local STATE_PAUSED                           = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState.Paused or 1
local FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS = {
    [3073] = true,
}

Buffer._timelineAddedPending           = {}
Buffer._acceptedTimelineEventIDs       = {}
Buffer._timelineCountdownSpecByEventID = {}

local function SafeToNumber(v)
    local ok, n = pcall(tonumber, v)
    if ok then
        return n
    end
    return nil
end

local function IsEncounterTimelineSource(source)
    if source == nil then
        return true
    end
    local src = SafeToNumber(source)
    return src == nil or src == TIMELINE_SOURCE_ENCOUNTER
end

local function IsTimelineDurationAllowed(duration)
    local d = SafeToNumber(duration)
    return d ~= nil and d >= 0 and d <= TIMELINE_MAX_EVENT_DURATION
end

local function IsTimelineTestMode()
    return ExwindTools and type(ExwindTools.State) == "table"
        and ExwindTools.State.TimelineTestMode == true
end

local function BuildTimelineDurationKey(duration)
    local d = SafeToNumber(duration) or 0
    return tostring(math.floor((d * TIMELINE_DURATION_KEY_SCALE) + 0.5))
end

local function ExtractColorRGB(colorObj)
    if type(colorObj) ~= "table" then
        return nil
    end
    local r = tonumber(colorObj.r)
    local g = tonumber(colorObj.g)
    local b = tonumber(colorObj.b)
    local a = tonumber(colorObj.a) or 1
    if r and g and b then
        return { r = r, g = g, b = b, a = a }
    end
    if type(colorObj.GetRGB) == "function" then
        local ok, rr, gg, bb = pcall(colorObj.GetRGB, colorObj)
        if ok and tonumber(rr) and tonumber(gg) and tonumber(bb) then
            return { r = tonumber(rr), g = tonumber(gg), b = tonumber(bb), a = a }
        end
    end
    return nil
end

function Buffer:_GetTimelineRemaining(eventID, fallback)
    if C_EncounterTimeline and C_EncounterTimeline.GetEventTimeRemaining then
        local ok, r = pcall(C_EncounterTimeline.GetEventTimeRemaining, eventID)
        if ok and type(r) == "number" then
            return r
        end
    end
    return fallback
end

function Buffer:_GetTimelineState(eventID)
    if C_EncounterTimeline and C_EncounterTimeline.GetEventState then
        local ok, s = pcall(C_EncounterTimeline.GetEventState, eventID)
        if ok then return s end
    end
    return nil
end

function Buffer:_ClearTimelineAddedPending(eventID)
    local pending = self._timelineAddedPending
    local timelineEventID = SafeToNumber(eventID)
    if type(pending) == "table" and timelineEventID then
        pending[timelineEventID] = nil
    end
end

function Buffer:_QueueTimelineEventAdded(eventInfo)
    if type(eventInfo) ~= "table" then return end
    local eventID = SafeToNumber(eventInfo.id)
    local duration = SafeToNumber(eventInfo.duration)
    if not eventID or not IsTimelineDurationAllowed(duration) then
        return
    end
    if not IsEncounterTimelineSource(eventInfo.source) then
        return
    end

    local now = GetTime()
    self._timelineAddedPending = type(self._timelineAddedPending) == "table" and self._timelineAddedPending or {}
    self._timelineAddedPending[eventID] = {
        timelineEventID = eventID,
        duration = duration,
        receivedAt = now,
        readyAt = now + TIMELINE_ADDED_CONFIRM_DELAY,
        spellIdentifier = eventInfo.spellID,
        spellName = eventInfo.spellName,
        iconFileID = SafeToNumber(eventInfo.iconFileID),
        eventColor = ExtractColorRGB(eventInfo.color),
        source = SafeToNumber(eventInfo.source),
    }
    self._acceptedTimelineEventIDs[eventID] = true
end

-- mode/fixedDriver/encounterID 由调用方（Scheduler）显式传入，Buffer 自身不持有
-- 这三个字段——它们是 Scheduler 的核心驱动状态，不属于"时间轴缓冲"职责。
function Buffer:_FilterTimelineAddedBatch(batch, now, mode, fixedDriver, encounterID)
    if type(batch) ~= "table" or #batch == 0 then
        return nil
    end
    local chosenByDuration = {}
    local orderByDuration = {}
    local acceptPausedSync = mode == "fixed"
        and fixedDriver == FIXED_DRIVER_AI
        and FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS[SafeToNumber(encounterID) or 0] == true

    for _, queued in ipairs(batch) do
        local eventID = SafeToNumber(queued and queued.timelineEventID)
        local duration = SafeToNumber(queued and queued.duration)
        if eventID and IsTimelineDurationAllowed(duration) then
            local state = self:_GetTimelineState(eventID)
            local pausedSyncAccepted = acceptPausedSync and state == STATE_PAUSED and
                ExBoss.Timeline.FixedAIResolver:_IsFixedAISyncDuration(duration)
            -- 离线回放没有真实的 C_EncounterTimeline runtime event，无法通过原生状态查询。
            -- 测试模式只跳过这一项校验；时长、来源、批次和去重仍走同一条生产解析链。
            if IsTimelineTestMode() or state == STATE_ACTIVE or pausedSyncAccepted then
                queued.pausedSyncAccepted = pausedSyncAccepted or nil
                local key = BuildTimelineDurationKey(duration)
                if chosenByDuration[key] == nil then
                    orderByDuration[#orderByDuration + 1] = key
                else
                    local oldEventID = SafeToNumber(chosenByDuration[key] and chosenByDuration[key].timelineEventID)
                    if oldEventID and oldEventID ~= eventID then
                        self._acceptedTimelineEventIDs[oldEventID] = nil
                        self._timelineCountdownSpecByEventID[oldEventID] = nil
                    end
                end
                chosenByDuration[key] = queued
            else
                self._acceptedTimelineEventIDs[eventID] = nil
                self._timelineCountdownSpecByEventID[eventID] = nil
            end
        end
    end

    if #orderByDuration == 0 then
        return nil
    end

    table.sort(orderByDuration, function(a, b)
        local left = chosenByDuration[a]
        local right = chosenByDuration[b]
        return (SafeToNumber(left and left.receivedAt) or now or 0) <
            (SafeToNumber(right and right.receivedAt) or now or 0)
    end)

    local filtered = {}
    for _, key in ipairs(orderByDuration) do
        filtered[#filtered + 1] = chosenByDuration[key]
    end
    return filtered
end

-- 供 Scheduler 生命周期入口（StartBoss/EndBoss/StartBlizzardFallback）统一调用。
function Buffer:Reset()
    self._timelineAddedPending           = {}
    self._acceptedTimelineEventIDs       = {}
    self._timelineCountdownSpecByEventID = {}
end
