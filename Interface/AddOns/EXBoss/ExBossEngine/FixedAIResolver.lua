---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/FixedAIResolver.lua
-- AI 轴 duration 推理引擎：给定一批 (timelineEventID, duration)，
-- 判断它们分别对应哪个 eventID，是否应该被接受。
-- 只负责推理判断，不负责 timer 的创建/移除（那是 Scheduler 的职责）。
-- 迁移自 Scheduler.lua，见 Scheduler重构计划.md §3.2。
-- =============================================================

ExBoss.Timeline.FixedAIResolver = ExBoss.Timeline.FixedAIResolver or {}
local Resolver = ExBoss.Timeline.FixedAIResolver

local FIXED_AI_MATCH_TOLERANCE                     = 0.75
local FIXED_AI_CANCELED_RESUME_WINDOW              = 5
local FIXED_AI_CANCELED_RESUME_TOLERANCE           = 0.35
local BOSS_TRANSITION_EVENT                        = "EXBOSS_BOSS_TRANSITION"

Resolver._fixedAIDurationRules          = nil
Resolver._fixedAIStateMachine           = nil
Resolver._fixedAIPhase                  = nil
Resolver._fixedAIStrictDurationMatch    = false
Resolver._fixedAISkillByEventID         = {}
Resolver._fixedAISequenceCounters       = {}
Resolver._fixedAIPreEventLimitCounts    = {}
Resolver._fixedAISyncCycleLimits        = {}
Resolver._fixedAISyncCycleCounts        = {}
Resolver._fixedAICanceledResumeSnapshot = nil
Resolver._eventActionsByEventID         = {}

local function SafeToNumber(v)
    local ok, n = pcall(tonumber, v)
    if ok then
        return n
    end
    return nil
end

local function NormalizeText(v)
    if type(v) ~= "string" then return "" end
    local t = v:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

local function GetEncounterTriggerRow(encounterID)
    local id = tonumber(encounterID) or encounterID
    local all = _G.EXBOSS_ENCOUNTER_TRIGGERS
    if type(all) ~= "table" then
        return nil
    end
    local row = all[id]
    if row == nil then
        row = all[tostring(id)]
    end
    return type(row) == "table" and row or nil
end

local _encounterAIStateMachineCache = {}

function Resolver.GetEncounterAIStateMachine(encounterID)
    local id = tonumber(encounterID)
    if not id then
        local row = GetEncounterTriggerRow(encounterID)
        local machine = row and row.aiStateMachine
        return type(machine) == "table" and machine or nil
    end
    local cached = _encounterAIStateMachineCache[id]
    if cached ~= nil then
        return cached or nil
    end
    local row = GetEncounterTriggerRow(id)
    local machine = row and row.aiStateMachine
    machine = (type(machine) == "table") and machine or nil
    _encounterAIStateMachineCache[id] = machine or false
    return machine
end

function Resolver.IsEncounterStrictDurationMatch(encounterID)
    local row = GetEncounterTriggerRow(encounterID)
    return type(row) == "table" and row.strictDurationMatch == true
end

local function GetFixedAIMatchTolerance(resolver, configuredTolerance)
    if type(resolver) == "table" and resolver._fixedAIStrictDurationMatch == true then
        return 0
    end
    return SafeToNumber(configuredTolerance) or FIXED_AI_MATCH_TOLERANCE
end

function Resolver.EncounterAIStateMachineHasRules(machine)
    if type(machine) ~= "table" or type(machine.phases) ~= "table" then
        return false
    end
    for _, phaseRow in pairs(machine.phases) do
        local rules = type(phaseRow) == "table" and phaseRow.rules or nil
        if type(rules) == "table" and #rules > 0 then
            return true
        end
    end
    return false
end

local _encounterEventActionsCache = {}

function Resolver.BuildEncounterEventActions(encounterID, phaseName)
    local encounterIDKey = tonumber(encounterID)
    local phaseKey = NormalizeText(phaseName)
    local cacheKey = encounterIDKey and (tostring(encounterIDKey) .. ":" .. phaseKey) or nil
    if cacheKey then
        local cached = _encounterEventActionsCache[cacheKey]
        if cached ~= nil then
            return cached
        end
    end

    local function NormalizeCastStartUnit(unit)
        local u = tostring(unit or ""):lower()
        if u == "boss" then
            return "boss"
        end
        if u == "boss1" or u == "boss2" or u == "boss3" or u == "boss4" or u == "boss5" then
            return u
        end
        return nil
    end

    local function NormalizeCastStartEvent(eventName)
        local e = tostring(eventName or ""):lower()
        if e == "cast" or e == "start" or e == "spellcast_start" then
            return "cast"
        end
        if e == "channel" or e == "channel_start" or e == "spellcast_channel_start" then
            return "channel"
        end
        return nil
    end

    local out = {}
    local function AppendActionRows(src)
        if type(src) ~= "table" then
            return
        end
        for rawEventID, actionRow in pairs(src) do
            local eventID = tonumber(rawEventID)
            if eventID and type(actionRow) == "table" then
            local clearDelay = tonumber(actionRow.clearActiveSnapshotAfter)
            local waitTimelineFinish = actionRow.waitTimelineFinish == true
            local timelineFinishTimeout = tonumber(actionRow.timelineFinishTimeout)
            local finishMode = tostring(actionRow.finishMode or ""):lower()
            local timerFinishIgnoreStateWindow = tonumber(actionRow.timerFinishIgnoreStateWindow)
            local castStartUnit = NormalizeCastStartUnit(actionRow.castStartUnit)
            -- Temporary probe: event 296 had a legacy boss-unit override that conflicts with
            -- the rebuilt cast-window matching path. Ignore that single override for now so
            -- we can verify whether it is the only blocker for playback.
            if eventID == 296 then
                castStartUnit = nil
            end
            local castStartWindow = tonumber(actionRow.castStartWindow)
            local castStartEvent = NormalizeCastStartEvent(actionRow.castStartEvent)
            local resumeFromCanceledSnapshot = actionRow.resumeFromCanceledSnapshot == true
            local resumeSnapshotTolerance = tonumber(actionRow.resumeSnapshotTolerance)
            local resumeSnapshotWindow = tonumber(actionRow.resumeSnapshotWindow)
            local canceledSnapshotEvents = nil
            if type(actionRow.canceledSnapshotEvents) == "table" then
                canceledSnapshotEvents = {}
                for key, value in pairs(actionRow.canceledSnapshotEvents) do
                    local eventValue = tonumber(value)
                    local eventKey = tonumber(key)
                    local eventID = eventValue or (value == true and eventKey or nil)
                    if eventID then
                        canceledSnapshotEvents[eventID] = true
                    end
                end
                if next(canceledSnapshotEvents) == nil then
                    canceledSnapshotEvents = nil
                end
            end
            local preEventLimits = nil
            if type(actionRow.preEventLimits) == "table" then
                preEventLimits = {}
                for rawLimitEventID, rawLimitCount in pairs(actionRow.preEventLimits) do
                    local limitEventID = tonumber(rawLimitEventID)
                    local limitCount = tonumber(rawLimitCount)
                    if limitEventID and limitCount and limitCount > 0 then
                        preEventLimits[limitEventID] = limitCount
                    end
                end
                if next(preEventLimits) == nil then
                    preEventLimits = nil
                end
            end
            if (clearDelay and clearDelay > 0)
                or preEventLimits
                or waitTimelineFinish
                or finishMode ~= ""
                or (timerFinishIgnoreStateWindow and timerFinishIgnoreStateWindow > 0)
                or castStartUnit ~= nil
                or (castStartWindow and castStartWindow > 0)
                or castStartEvent ~= nil
                or resumeFromCanceledSnapshot then
                out[eventID] = out[eventID] or {}
                if clearDelay and clearDelay > 0 then
                    out[eventID].clearActiveSnapshotAfter = clearDelay
                end
                if waitTimelineFinish then
                    out[eventID].waitTimelineFinish = true
                    if timelineFinishTimeout and timelineFinishTimeout > 0 then
                        out[eventID].timelineFinishTimeout = timelineFinishTimeout
                    end
                end
                if preEventLimits then
                    out[eventID].preEventLimits = preEventLimits
                end
                if finishMode ~= "" then
                    out[eventID].finishMode = finishMode
                end
                if timerFinishIgnoreStateWindow and timerFinishIgnoreStateWindow > 0 then
                    out[eventID].timerFinishIgnoreStateWindow = timerFinishIgnoreStateWindow
                end
                if castStartUnit then
                    out[eventID].castStartUnit = castStartUnit
                end
                if castStartWindow and castStartWindow > 0 then
                    out[eventID].castStartWindow = castStartWindow
                end
                if castStartEvent then
                    out[eventID].castStartEvent = castStartEvent
                end
                if resumeFromCanceledSnapshot then
                    out[eventID].resumeFromCanceledSnapshot = true
                    out[eventID].resumeSnapshotTolerance = resumeSnapshotTolerance
                    out[eventID].resumeSnapshotWindow = resumeSnapshotWindow
                    out[eventID].canceledSnapshotEvents = canceledSnapshotEvents
                end
            end
        end
    end
    end

    local row = GetEncounterTriggerRow(encounterID)
    AppendActionRows(row and row.eventActions)

    if phaseKey ~= "" then
        local machine = row and row.aiStateMachine
        local phaseRow = type(machine) == "table" and type(machine.phases) == "table"
            and machine.phases[phaseKey] or nil
        AppendActionRows(type(phaseRow) == "table" and phaseRow.eventActions or nil)
    end

    if cacheKey then _encounterEventActionsCache[cacheKey] = out end
    return out
end

local _encounterFixedAISyncCycleLimitsCache = {}

function Resolver.BuildEncounterFixedAISyncCycleLimits(encounterID)
    local cacheKey = tonumber(encounterID)
    if cacheKey then
        local cached = _encounterFixedAISyncCycleLimitsCache[cacheKey]
        if cached ~= nil then
            return cached
        end
    end

    local out = {}
    local row = GetEncounterTriggerRow(encounterID)
    local src = row and row.syncCycleLimits
    if type(src) ~= "table" then
        if cacheKey then _encounterFixedAISyncCycleLimitsCache[cacheKey] = out end
        return out
    end
    for rawEventID, rawLimit in pairs(src) do
        local eventID = tonumber(rawEventID)
        local limit = tonumber(rawLimit)
        if eventID and limit and limit > 0 then
            out[eventID] = limit
        end
    end
    if cacheKey then _encounterFixedAISyncCycleLimitsCache[cacheKey] = out end
    return out
end

local _durationRulesForEncounterCache = {}

function Resolver.GetDurationRulesForEncounter(encounterID)
    local id = tonumber(encounterID)
    if not id then return nil end
    local cached = _durationRulesForEncounterCache[id]
    if cached ~= nil then
        return cached or nil
    end
    local rows = nil
    if type(_G.EXBOSS_DURATION_EVENT_RULES) == "table" then
        rows = _G.EXBOSS_DURATION_EVENT_RULES[id]
        if rows == nil then
            rows = _G.EXBOSS_DURATION_EVENT_RULES[tostring(id)]
        end
    end
    if type(rows) ~= "table" or #rows == 0 then
        _durationRulesForEncounterCache[id] = false
        return nil
    end
    _durationRulesForEncounterCache[id] = rows
    return rows
end

function Resolver.HasDurationRulesForEncounter(encounterID)
    if type(Resolver.GetDurationRulesForEncounter(encounterID)) == "table" then
        return true
    end
    return Resolver.EncounterAIStateMachineHasRules(Resolver.GetEncounterAIStateMachine(encounterID))
end

function Resolver:_GetFixedAIPhaseRow(phaseName)
    local machine = self._fixedAIStateMachine
    if type(machine) ~= "table" or type(machine.phases) ~= "table" then
        return nil
    end
    local key = NormalizeText(phaseName)
    if key == "" then
        return nil
    end
    local row = machine.phases[key]
    return type(row) == "table" and row or nil
end

function Resolver.DispatchBossTransitionEvent(encounterID, phaseName, happenedAt)
    if not ExwindTools or type(ExwindTools.SendEvent) ~= "function" then
        return
    end
    local id = tonumber(encounterID)
    local phase = NormalizeText(phaseName)
    local now = SafeToNumber(happenedAt) or GetTime()
    if not id or phase == "" then
        return
    end
    ExwindTools:SendEvent(BOSS_TRANSITION_EVENT, id, phase, now)
end

function Resolver:_SetFixedAIPhase(phaseName, enterConfig, suppressEvent, transitionTime, encounterID)
    local key = NormalizeText(phaseName)
    local phaseRow = self:_GetFixedAIPhaseRow(key)
    local oldPhase = NormalizeText(self._fixedAIPhase)
    local newPhase = phaseRow and key or nil
    if newPhase and oldPhase == newPhase then
        return false
    end
    self._fixedAIPhase = newPhase
    self._fixedAIDurationRules = phaseRow and phaseRow.rules or nil
    if encounterID ~= nil then
        self._eventActionsByEventID = self.BuildEncounterEventActions(encounterID, newPhase)
    end
    if type(enterConfig) == "table" then
        if enterConfig.resetSequence ~= false then
            self._fixedAISequenceCounters = {}
        end
        if enterConfig.resetPreLimits ~= false then
            self:_ResetAllFixedAIPreEventLimits()
        end
        if enterConfig.resetSyncLimits ~= false then
            self:_ResetFixedAISyncCycleLimits()
        end
    end
    if suppressEvent ~= true and newPhase then
        Resolver.DispatchBossTransitionEvent(encounterID, newPhase, transitionTime)
    end
    return true
end

function Resolver:_NormalizeFixedAIMatchDuration(duration)
    local value = SafeToNumber(duration)
    if not value then
        return nil
    end

    local function ApplyNormalize(rules, current)
        if type(rules) ~= "table" then
            return current
        end
        for _, row in ipairs(rules) do
            if type(row) == "table" then
                local minValue = SafeToNumber(row.min or row.timeMin or row.timemin)
                local maxValue = SafeToNumber(row.max or row.timeMax or row.timemax)
                local snapValue = SafeToNumber(row.snap or row.snapTo or row.time)
                if minValue and maxValue and snapValue and current >= minValue and current <= maxValue then
                    return snapValue
                end
            end
        end
        return current
    end

    local machine = self._fixedAIStateMachine
    if type(machine) ~= "table" then
        return value
    end

    value = ApplyNormalize(machine.globalNormalize, value)
    local phaseRow = self:_GetFixedAIPhaseRow(self._fixedAIPhase)
    value = ApplyNormalize(phaseRow and phaseRow.normalize, value)
    return value
end

function Resolver:_ResolveFixedAIPhaseEnter(batch)
    local machine = self._fixedAIStateMachine
    if type(machine) ~= "table" or type(machine.phases) ~= "table" or type(batch) ~= "table" or #batch == 0 then
        return nil, nil
    end

    local bestPhase, bestEnter, bestPriority = nil, nil, nil
    for phaseName, phaseRow in pairs(machine.phases) do
        local enter = type(phaseRow) == "table" and phaseRow.enter or nil
        if type(enter) == "table" then
            local mode = tostring(enter.mode or ""):lower()
            local tolerance = GetFixedAIMatchTolerance(self, enter.tolerance)
            local matched = false
            if mode == "sync_batch_all" then
                local times = type(enter.times) == "table" and enter.times or nil
                if times and #times > 0 then
                    local used = {}
                    matched = true
                    for _, rawTime in ipairs(times) do
                        local target = SafeToNumber(rawTime)
                        if target then
                            local found = false
                            for index, queued in ipairs(batch) do
                                if not used[index] then
                                    local duration = SafeToNumber(queued and queued.duration)
                                    if duration and math.abs(duration - target) <= tolerance then
                                        used[index] = true
                                        found = true
                                        break
                                    end
                                end
                            end
                            if not found then
                                matched = false
                                break
                            end
                        end
                    end
                end
            elseif mode == "duration_once" then
                local target = SafeToNumber(enter.time)
                if target then
                    for _, queued in ipairs(batch) do
                        local duration = SafeToNumber(queued and queued.duration)
                        if duration and math.abs(duration - target) <= tolerance then
                            matched = true
                            break
                        end
                    end
                end
            end

            if matched then
                local priority = SafeToNumber(enter.priority) or 0
                if bestEnter == nil or priority > (bestPriority or 0) then
                    bestPhase = NormalizeText(phaseName)
                    bestEnter = enter
                    bestPriority = priority
                end
            end
        end
    end

    return bestPhase, bestEnter
end

function Resolver:_UpdateFixedAIPhaseFromBatch(batch, encounterID)
    local phaseName, enter = self:_ResolveFixedAIPhaseEnter(batch)
    if not phaseName then
        return false
    end
    local happenedAt = nil
    if type(batch) == "table" and type(batch[1]) == "table" then
        happenedAt = SafeToNumber(batch[1].receivedAt)
    end
    return self:_SetFixedAIPhase(phaseName, enter, false, happenedAt, encounterID)
end

function Resolver:_ResolveFixedAIEventID(duration)
    local d = self:_NormalizeFixedAIMatchDuration(duration)
    if not d then return nil end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then return nil end

    local bestEventID, bestDelta = nil, nil
    for _, row in ipairs(rules) do
        local t = tonumber(row and row.time)
        local eventID = tonumber(row and row.eventID)
        if t and eventID then
            local delta = math.abs(d - t)
            if not bestDelta or delta < bestDelta then
                bestDelta = delta
                bestEventID = eventID
            end
        end
    end

    if bestDelta and bestDelta <= GetFixedAIMatchTolerance(self) then
        return bestEventID
    end
    return nil
end

function Resolver:_ResolveFixedAIEventIDForMode(duration, timelineEventID, syncMode)
    local d = self:_NormalizeFixedAIMatchDuration(duration)
    if not d then return nil end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then return nil end

    local candidates = {}
    local bestDelta = nil
    local timelineID = tonumber(timelineEventID)

    for _, row in ipairs(rules) do
        if type(row) == "table" then
            local rowSync = (row.sync == true)
            if rowSync == syncMode then
                local t = tonumber(row.time)
                local eventID = tonumber(row.eventID)
                if t and eventID then
                    if (not syncMode) or (timelineID and eventID == timelineID) then
                        local delta = math.abs(d - t)
                        if not bestDelta or delta < bestDelta then
                            bestDelta = delta
                            candidates = { row }
                        elseif delta == bestDelta then
                            candidates[#candidates + 1] = row
                        end
                    end
                end
            end
        end
    end

    if not (bestDelta and bestDelta <= GetFixedAIMatchTolerance(self)) then
        return nil
    end

    if #candidates <= 1 or syncMode == true then
        return tonumber(candidates[1] and candidates[1].eventID)
    end

    local firstGroup = NormalizeText(candidates[1] and candidates[1].sequenceGroup)
    if firstGroup == "" then
        return tonumber(candidates[1] and candidates[1].eventID)
    end

    local grouped = {}
    for _, row in ipairs(candidates) do
        if NormalizeText(row and row.sequenceGroup) == firstGroup then
            grouped[#grouped + 1] = row
        end
    end
    if #grouped == 0 then
        return tonumber(candidates[1] and candidates[1].eventID)
    end

    table.sort(grouped, function(a, b)
        return (tonumber(a and a.sequenceOrder) or 0) < (tonumber(b and b.sequenceOrder) or 0)
    end)

    self._fixedAISequenceCounters = type(self._fixedAISequenceCounters) == "table" and self._fixedAISequenceCounters or
        {}
    local current = tonumber(self._fixedAISequenceCounters[firstGroup]) or 0
    local nextIndex = (current % #grouped) + 1
    self._fixedAISequenceCounters[firstGroup] = current + 1
    local chosen = grouped[nextIndex]
    if chosen then
        return tonumber(chosen.eventID)
    end
    return nil
end

function Resolver:_CountFixedAISyncRuleMatches(batch)
    if type(batch) ~= "table" then
        return 0
    end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then
        return 0
    end
    local count = 0
    for _, queued in ipairs(batch) do
        local d = self:_NormalizeFixedAIMatchDuration(queued and queued.duration)
        if d then
            local matched = false
            for _, row in ipairs(rules) do
                if type(row) == "table" and row.sync == true then
                    local t = SafeToNumber(row.time)
                    if t and math.abs(d - t) <= GetFixedAIMatchTolerance(self) then
                        matched = true
                        break
                    end
                end
            end
            if matched then
                count = count + 1
            end
        end
    end
    return count
end

function Resolver:_HasFixedAIPausedSyncAccepted(batch)
    if type(batch) ~= "table" then
        return false
    end
    for _, queued in ipairs(batch) do
        if type(queued) == "table" and queued.pausedSyncAccepted == true then
            return true
        end
    end
    return false
end

function Resolver:_IsFixedAISyncDuration(duration)
    local d = self:_NormalizeFixedAIMatchDuration(duration)
    if not d then
        return false
    end
    local rules = self._fixedAIDurationRules
    if type(rules) ~= "table" then
        return false
    end
    for _, row in ipairs(rules) do
        if type(row) == "table" and row.sync == true then
            local t = SafeToNumber(row.time)
            if t and math.abs(d - t) <= GetFixedAIMatchTolerance(self) then
                return true
            end
        end
    end
    return false
end

function Resolver:_HasFixedAICanceledResumeSnapshotReady(batch)
    if type(batch) ~= "table" or #batch < 2 then
        return false
    end
    local snapshot = self._fixedAICanceledResumeSnapshot
    if type(snapshot) ~= "table" or type(snapshot.entries) ~= "table" or #snapshot.entries == 0 then
        return false
    end
    local now = GetTime()
    local expiresAt = SafeToNumber(snapshot.expiresAt)
    if expiresAt and now > expiresAt then
        self._fixedAICanceledResumeSnapshot = nil
        return false
    end
    return true
end

function Resolver:_FindFixedAIPreEventLimit(eventID)
    local id = tonumber(eventID)
    if not id then
        return nil, nil
    end
    local actions = self._eventActionsByEventID
    if type(actions) ~= "table" then
        return nil, nil
    end
    for resetEventID, action in pairs(actions) do
        local limits = type(action) == "table" and action.preEventLimits or nil
        local limit = type(limits) == "table" and tonumber(limits[id]) or nil
        if limit and limit > 0 then
            return tonumber(resetEventID), limit
        end
    end
    return nil, nil
end

function Resolver:_AcceptFixedAIPreEventLimit(eventID)
    local resetEventID, limit = self:_FindFixedAIPreEventLimit(eventID)
    if not resetEventID then
        return true
    end
    self._fixedAIPreEventLimitCounts = type(self._fixedAIPreEventLimitCounts) == "table" and
        self._fixedAIPreEventLimitCounts or {}
    local byReset = self._fixedAIPreEventLimitCounts[resetEventID]
    if type(byReset) ~= "table" then
        byReset = {}
        self._fixedAIPreEventLimitCounts[resetEventID] = byReset
    end
    local id = tonumber(eventID)
    local current = tonumber(byReset[id]) or 0
    if current >= limit then
        return false
    end
    byReset[id] = current + 1
    return true
end

function Resolver:_ResetFixedAIPreEventLimits(resetEventID)
    local id = tonumber(resetEventID)
    if not id or type(self._fixedAIPreEventLimitCounts) ~= "table" then
        return
    end
    self._fixedAIPreEventLimitCounts[id] = nil
end

function Resolver:_ResetAllFixedAIPreEventLimits()
    self._fixedAIPreEventLimitCounts = {}
end

function Resolver:_ResetFixedAISyncCycleLimits()
    self._fixedAISyncCycleCounts = {}
end

function Resolver:_AcceptFixedAISyncCycleLimit(eventID)
    local id = tonumber(eventID)
    if not id then
        return true
    end
    local limits = self._fixedAISyncCycleLimits
    local limit = type(limits) == "table" and tonumber(limits[id]) or nil
    if not (limit and limit > 0) then
        return true
    end
    self._fixedAISyncCycleCounts = type(self._fixedAISyncCycleCounts) == "table" and self._fixedAISyncCycleCounts or {}
    local current = tonumber(self._fixedAISyncCycleCounts[id]) or 0
    if current >= limit then
        return false
    end
    self._fixedAISyncCycleCounts[id] = current + 1
    return true
end

function Resolver:_FindFixedAICanceledResumeAction(eventID)
    local id = SafeToNumber(eventID)
    if not id or type(self._eventActionsByEventID) ~= "table" then
        return nil
    end
    for _, action in pairs(self._eventActionsByEventID) do
        if type(action) == "table" and action.resumeFromCanceledSnapshot == true then
            local events = type(action.canceledSnapshotEvents) == "table" and action.canceledSnapshotEvents or nil
            if events and events[id] == true then
                return action
            end
        end
    end
    return nil
end

function Resolver:_CaptureFixedAICanceledResumeSnapshot(timer, timelineEventID, remaining, now)
    if type(timer) ~= "table" then
        return
    end
    local eventID = SafeToNumber(timer.eventID) or SafeToNumber(timer.timelineEventID)
    local action = self:_FindFixedAICanceledResumeAction(eventID)
    if not action then
        return
    end

    now = SafeToNumber(now) or GetTime()
    local remain = SafeToNumber(remaining)
    if not remain then
        local castTime = SafeToNumber(timer.castTime)
        remain = castTime and (castTime - now) or nil
    end
    if not remain or remain <= 0 then
        return
    end

    local window = math.max(1, SafeToNumber(action.resumeSnapshotWindow) or FIXED_AI_CANCELED_RESUME_WINDOW)
    local snapshot = self._fixedAICanceledResumeSnapshot
    if type(snapshot) ~= "table" or (SafeToNumber(snapshot.expiresAt) or 0) < now then
        snapshot = {
            entries = {},
        }
        self._fixedAICanceledResumeSnapshot = snapshot
    end

    snapshot.tolerance = math.max(0.01,
        SafeToNumber(action.resumeSnapshotTolerance) or FIXED_AI_CANCELED_RESUME_TOLERANCE)
    snapshot.expiresAt = now + window

    local entries = snapshot.entries
    local replaced = false
    for _, entry in ipairs(entries) do
        if SafeToNumber(entry.eventID) == eventID then
            entry.remaining = remain
            entry.timelineEventID = SafeToNumber(timelineEventID)
            entry.timerID = SafeToNumber(timer.id)
            replaced = true
            break
        end
    end
    if not replaced then
        entries[#entries + 1] = {
            eventID = eventID,
            remaining = remain,
            timelineEventID = SafeToNumber(timelineEventID),
            timerID = SafeToNumber(timer.id),
        }
    end
end

function Resolver:_BuildFixedAICanceledResumeSnapshotMap(batch, syncMode)
    local snapshot = self._fixedAICanceledResumeSnapshot
    if type(snapshot) ~= "table" or type(batch) ~= "table" then
        return nil
    end

    if syncMode ~= true then
        return nil
    end

    local now = GetTime()
    local expiresAt = SafeToNumber(snapshot.expiresAt)
    if expiresAt and now > expiresAt then
        self._fixedAICanceledResumeSnapshot = nil
        return nil
    end

    local entries = type(snapshot.entries) == "table" and snapshot.entries or nil
    if not entries or #entries == 0 then
        return nil
    end

    local tolerance = SafeToNumber(snapshot.tolerance) or FIXED_AI_CANCELED_RESUME_TOLERANCE
    local usedEntries = {}
    local map = {}
    local matched = false
    for _, queued in ipairs(batch) do
        local duration = SafeToNumber(queued and queued.duration)
        if duration then
            local bestIndex, bestDelta = nil, nil
            for index, entry in ipairs(entries) do
                if not usedEntries[index] then
                    local remaining = SafeToNumber(entry.remaining)
                    local eventID = SafeToNumber(entry.eventID)
                    if remaining and eventID then
                        local delta = math.abs(duration - remaining)
                        if delta <= tolerance and (not bestDelta or delta < bestDelta) then
                            bestIndex = index
                            bestDelta = delta
                        end
                    end
                end
            end
            if bestIndex then
                usedEntries[bestIndex] = true
                map[queued] = SafeToNumber(entries[bestIndex].eventID)
                matched = true
            end
        end
    end

    return matched and map or nil
end

-- 供 Scheduler 生命周期入口（StartBoss/EndBoss/StartBlizzardFallback）统一调用，
-- 替代原本三处手写重置。行为等价于原 Scheduler.lua 里对这10个字段的完整重置。
function Resolver:Reset()
    self._fixedAIDurationRules          = nil
    self._fixedAIStateMachine           = nil
    self._fixedAIPhase                  = nil
    self._fixedAIStrictDurationMatch    = false
    self._fixedAISkillByEventID         = {}
    self._fixedAISequenceCounters       = {}
    self._fixedAIPreEventLimitCounts    = {}
    self._fixedAISyncCycleLimits        = {}
    self._fixedAISyncCycleCounts        = {}
    self._fixedAICanceledResumeSnapshot = nil
    self._eventActionsByEventID         = {}
end
