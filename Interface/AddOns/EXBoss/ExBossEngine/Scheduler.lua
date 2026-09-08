---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/Scheduler.lua
-- 战斗计时引擎（auto + fixed + blizzard）
-- 调度器，负责根据当前战斗和配置调度计时事件的创建、更新和销毁。
-- =============================================================

ExBoss.Timeline.Scheduler = ExBoss.Timeline.Scheduler or {}
local Scheduler           = ExBoss.Timeline.Scheduler
local function TraceColor(stage, timer, color, note)
    local trace = ExBoss and ExBoss.ColorTrace
    if trace and type(trace.Record) == "function" then trace:Record(stage, timer, color, note) end
end
local FixedAIResolver                              = ExBoss.Timeline.FixedAIResolver
local TimelineAddedBuffer                          = ExBoss.Timeline.TimelineAddedBuffer
local TimerEventEmitter                            = ExBoss.Timeline.TimerEventEmitter
local TimelinePresentation                         = ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and
    ExBoss.Modules.Boss.TimelinePresentation
local TrashRuntimeConfig                           = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.RuntimeConfig or nil

local ONUPDATE_INTERVAL                            = 0.05
local MAX_ENCOUNTER_DURATION                       = 600
local BUNBAR_LEAD_TIME                             = 30
local TIMERBAR_LEAD_TIME                           = 30
-- 与 TimerBar 的 DeclareModuleDefaults 保持一致：ModuleDB 尚未初始化时只能采用
-- 正式默认值，而不是把 nil 误解释为“显示全部”。
local TIMERBAR_DEFAULT_HIDE_LONG_ENABLED           = true
local DEFAULT_PREALERT_SECS                        = 5
local VIRTUAL_HINT_REMAINING_SECS                  = 5
local FIXED_DRIVER_TIME                            = "time"
local FIXED_DRIVER_AI                              = "ai"
local FIXED_AI_MATCH_TOLERANCE                     = 0.75
local FIXED_AI_SYNC_WINDOW                         = 0.1
local FIXED_AI_CANCELED_RESUME_WINDOW              = 5
local FIXED_AI_CANCELED_RESUME_TOLERANCE           = 0.35
local FIXED_AI_FINISHED_TRIGGER_GRACE              = 0.5
local FIXED_AI_TIMELINE_FINISH_TIMEOUT             = 8
local FIXED_TIME_MATCH_TOLERANCE                   = 2.0
local FIXED_TIME_OFFSET_EPSILON                    = 0.02
local FIXED_TIME_OFFSET_CALIBRATION_ENABLED        = false
local TIMELINE_ADDED_CONFIRM_DELAY                 = 0.20
local TIMELINE_MAX_EVENT_DURATION                  = 120
local TIMELINE_DURATION_KEY_SCALE                  = 10
local FIXED_AI_EVENT_SCHEDULED_EVENT               = "EXBOSS_FIXED_AI_EVENT_SCHEDULED"
local FIXED_AI_EVENT_FINISHED_EVENT                = "EXBOSS_FIXED_AI_EVENT_FINISHED"
local BOSS_TRANSITION_EVENT                        = "EXBOSS_BOSS_TRANSITION"
local TIMER_FIVE_SEC_REMAINING_EVENT               = "EXBOSS_TIMER_FIVE_SEC_REMAINING"
local TRASH_CASTBAR_STOP_EVENT                     = "EXBOSS_TRASH_CASTBAR_STOP"
local TRASH_OBSERVED_CAST_START_EVENT              = "EXBOSS_TRASH_OBSERVED_CAST_START"
local TRASH_CAST_START_VOICE_TRIGGERED_EVENT       = "EXBOSS_TRASH_CAST_START_VOICE_TRIGGERED"
local BOSS_OBSERVED_CAST_START_EVENT               = "EXBOSS_BOSS_OBSERVED_CAST_START"
local BOSS_OBSERVED_CAST_STOP_EVENT                = "EXBOSS_BOSS_OBSERVED_CAST_STOP"
local TIMER_FIVE_SEC_REMAINING_THRESHOLD           = 5
local BOSS_CAST_OBSERVE_LEAD                       = 0.10
local BOSS_CAST_OBSERVE_RECENT_KEEP                = 0.35
local BOSS_CAST_OBSERVE_MIN_WINDOW_AFTER           = 0.25

-- 此段在通用 NormalizeText 的局部作用域之前执行；不能调用后定义的 local。
local function NormalizeBossObserveExpectedKind(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

-- Boss 施法观察不保留运行时诊断输出；观察/匹配只走正式逻辑。
local function BossProgressDebugPrint() end
-- 施法条对应BOSS
local SPECIAL_BOSS_OBSERVE_UNIT_FILTERS            = {
    -- S2
    [2143] = {
        [831] = "boss1",
        [832] = "boss1",
        [833] = "boss1",
        [834] = "boss1",
        [835] = "boss2",
        [836] = "boss2",
        [837] = "boss2",
    },
    [2124] = {
        [689] = "boss1",
        [690] = "boss1",
        [720] = "boss1",

        [691] = "boss2",
        [692] = "boss2",
        [713] = "boss2",
        [718] = "boss2",
    },

    [2623] = {
        [889] = "boss2",
        [890] = "boss2",
        [894] = "boss2",

        [885] = "boss1",
        [887] = "boss1",
        [888] = "boss1",
    },

    [3101] = {
        [120] = "boss1",
        [202] = "boss1",

        [122] = "boss2",
        [610] = "boss2",
    },

    [3199] = {
        [173] = "boss1",
        [174] = "boss3",

        [175] = "boss3",
        [176] = "boss3",
        [177] = "boss2",
    },

}
local SPECIAL_BOSS_STOP_EVENT_BY_UNIT_KIND         = {
    [3057] = {
        boss1 = {
            cast = 27,
            channel = 27,
        },
        boss2 = {
            cast = 29,
            channel = 29,
        },
    },
}
local BuildBossObservedCastEventPayload
local DispatchBossObservedCastEvent
local FIXED_AI_KEEP_AFTER_PAUSE_REMOVED_ENCOUNTERS = {
    [3073] = true,
}
local FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS       = {
    [3073] = true,
}
local TRIGGER_TIME                                 = "TIME"
local TRIGGER_AI                                   = "AI"
local TRIGGER_BLZ                                  = "BLZ"

local STATE_ACTIVE                                 = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState.Active or
    0
local STATE_PAUSED                                 = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState.Paused or
    1
local STATE_FINISHED                               = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState
    .Finished or 2
local STATE_CANCELED                               = Enum and Enum.EncounterTimelineEventState and
    Enum.EncounterTimelineEventState
    .Canceled or 3
local TIMELINE_SOURCE_ENCOUNTER                    = Enum and Enum.EncounterTimelineEventSource and
    Enum.EncounterTimelineEventSource.Encounter or 0

Scheduler._active                                  = {}
Scheduler._nextTimerID                             = 1
Scheduler._elapsed                                 = 0
Scheduler._running                                 = false
Scheduler._frame                                   = nil
Scheduler._encounterID                             = nil
Scheduler._mode                                    = "fixed"
Scheduler._timelineEventToTimer                    = {}
Scheduler._fixedDriver                             = FIXED_DRIVER_TIME
Scheduler._fixedAIEventToTimer                     = {}
Scheduler._fixedAIPendingEvents                    = {}
Scheduler._fixedAI176InjectTimers                  = {}
Scheduler._occurrenceCounts                        = {}
Scheduler._fixedTimeOffset                         = 0
Scheduler._fixedTimeEventToTimer                   = {}
Scheduler._lastEncounterStartAt                    = 0
Scheduler._lastEncounterStartID                    = nil
Scheduler._lastEncounterEndAt                      = 0
Scheduler._suppressBlizzardTimeline                = false
Scheduler._ignoreTimelineRecoveryUntil             = 0
Scheduler._sessionToken                            = 0
Scheduler._blizzardHintSessionEnabled              = false
Scheduler._bossCastObservePending                  = {}
Scheduler._bossCastObservePendingByTimerID         = {}
Scheduler._bossCastObserveNextID                   = 1
Scheduler._bossCastObserveRecentStarts             = {}
Scheduler._bossCastObserveNextStartID              = 1
Scheduler._bossObservedRuntimes                    = {}
Scheduler._bossObservedRuntimeNextID               = 1
local _colorResolveErrorLogged                     = false

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = DeepCopy(x)
    end
    return out
end

local function SafeToNumber(v)
    local ok, n = pcall(tonumber, v)
    if ok then
        return n
    end
    return nil
end

local function NormalizeUnitToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    unit = tostring(unit):lower()
    if unit == "" then
        return nil
    end
    return unit
end

local function NormalizeCastBarID(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return id
end

local function IsBossUnitToken(unit)
    unit = NormalizeUnitToken(unit)
    return unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5"
end

local function IsBossCastObserveUnit(unit)
    return IsBossUnitToken(unit)
end

local function GetBossCastObserveUnitPriority(unit)
    if IsBossUnitToken(unit) then
        return 1
    end
    return 0
end

local function NormalizeObserveUnitText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function NormalizeObserveUnitFilter(value)
    if type(value) == "table" then
        local out = {}
        for i = 1, #value do
            local item = NormalizeObserveUnitText(value[i])
            if item then
                out[#out + 1] = item
            end
        end
        return (#out > 0) and out or nil
    end
    local text = NormalizeObserveUnitText(value)
    if not text then
        return nil
    end
    if not text:find("[,|/;]") then
        return { text }
    end
    local out = {}
    for item in text:gmatch("[^,|/;]+") do
        local normalized = NormalizeObserveUnitText(item)
        if normalized then
            out[#out + 1] = normalized
        end
    end
    return (#out > 0) and out or nil
end

local function BossObserveUnitFilterMatches(filterValue, entry)
    local filters = NormalizeObserveUnitFilter(filterValue)
    if not filters or type(entry) ~= "table" then
        return true
    end
    local unitToken = NormalizeUnitToken(entry.unit)
    for i = 1, #filters do
        local raw = filters[i]
        local token = NormalizeUnitToken(raw)
        local lowered = tostring(raw):lower()
        if token and unitToken == token then
            return true
        end
        if lowered == "boss" and IsBossUnitToken(unitToken) then
            return true
        end
    end
    return false
end

local function GetSpecialBossObserveUnitFilter(encounterID, eventID)
    local encounterRow = SPECIAL_BOSS_OBSERVE_UNIT_FILTERS[tonumber(encounterID or 0)]
    if type(encounterRow) ~= "table" then
        return nil
    end
    local value = encounterRow[tonumber(eventID or 0)]
    if value == nil then
        return nil
    end
    if type(value) == "table" then
        return DeepCopy(value)
    end
    return tostring(value)
end

local function GetSpecialBossStopEventID(encounterID, unit, castKind)
    local encounterRow = SPECIAL_BOSS_STOP_EVENT_BY_UNIT_KIND[tonumber(encounterID or 0)]
    if type(encounterRow) ~= "table" then
        return nil
    end
    local unitRow = encounterRow[NormalizeUnitToken(unit) or ""]
    if type(unitRow) ~= "table" then
        return nil
    end
    local eventID = unitRow[tostring(castKind or "")]
    return tonumber(eventID)
end

local function ComputeProgressPlanTotalDuration(plan)
    if type(plan) ~= "table" then
        return 0
    end
    local total = 0
    for i = 1, #plan do
        total = total + math.max(0.1, tonumber(type(plan[i]) == "table" and plan[i].duration or nil) or 0.1)
    end
    return total
end

local function IsEncounterTimelineSource(source)
    if source == nil then
        return true
    end
    local src = SafeToNumber(source)
    return src == nil or src == TIMELINE_SOURCE_ENCOUNTER
end

local function IsFixedTimeTestOverride(encounterID)
    local test = ExBoss and ExBoss.TestTimelineForceFixedTime
    if type(test) ~= "table" or test.active ~= true then
        return false
    end
    local expected = SafeToNumber(test.encounterID)
    local actual = SafeToNumber(encounterID)
    return expected ~= nil and actual ~= nil and expected == actual
end

local function IsTimelineDurationAllowed(duration)
    local d = SafeToNumber(duration)
    return d ~= nil and d >= 0 and d <= TIMELINE_MAX_EVENT_DURATION
end

local function BuildTimelineDurationKey(duration)
    local d = SafeToNumber(duration) or 0
    return tostring(math.floor((d * TIMELINE_DURATION_KEY_SCALE) + 0.5))
end

local function SafeNum(v, def)
    local n = SafeToNumber(v)
    if not n then return def end
    return n
end

local function LocalizeDynamicText(v)
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        return tostring(ExBoss.Locale.TranslateBossDynamicText(v) or "")
    end
    return tostring(v or "")
end

-- PublishFixedAIEventScheduled / PublishFixedAIEventFinished 已迁移到
-- ExBossEngine/TimerEventEmitter.lua，此处改用 TimerEventEmitter.xxx(...) 调用。

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

local function ResolveTimelineDisplayName(passthroughSpellName, eventID)
    if passthroughSpellName ~= nil then
        return passthroughSpellName
    end
    return "时间轴事件 " .. tostring(eventID)
end

local function BuildTimelineCountdownSpec(displayName, iconFileID, color)
    return {
        displayName = displayName,
        iconFileID = iconFileID,
        color = color,
        duration = 5,
        rawText = true,
        disableIconBorder = true,
    }
end

local function ApplyTrashTimelineMeta(timer, meta)
    if type(timer) ~= "table" or type(meta) ~= "table" then
        return
    end

    timer.trashMeta = meta
    timer.colorConfig = type(meta.colorConfig) == "table" and DeepCopy(meta.colorConfig) or timer.colorConfig
    timer.voicePlan = type(meta.voicePlan) == "table" and DeepCopy(meta.voicePlan) or timer.voicePlan
    local voiceLabel = type(meta.voiceLabel) == "string" and meta.voiceLabel or ""
    voiceLabel = voiceLabel:gsub("^%s+", ""):gsub("%s+$", "")
    if voiceLabel ~= "" then
        timer.voiceLabel = voiceLabel
    end

    local displayName = LocalizeDynamicText(meta.displayName or "")
    if displayName ~= "" then
        timer.baseDisplayName = displayName
        timer.displayName = displayName
        timer.timelineSpellName = displayName
    end

    local iconFileID = tonumber(meta.iconFileID)
    if iconFileID and iconFileID > 0 then
        timer.iconFileID = iconFileID
    end

    if type(meta.eventColor) == "table" then
        timer.eventColor = DeepCopy(meta.eventColor)
        timer.flashTextColor = DeepCopy(meta.eventColor)
    end

    local timerBarName = LocalizeDynamicText(meta.timerBarName or "")
    if timerBarName ~= "" then
        timer.timerBarName = timerBarName
    end

    timer.showBunBar = (meta.showBunBar ~= false)
    timer.showTimerBar = (meta.showTimerBar ~= false)
    timer.showNameplate = (meta.showNameplate == true)
    timer.nameplateSide = (tostring(meta.nameplateSide or "right") == "left") and "left" or "right"
    timer.progressDisplayName = LocalizeDynamicText(meta.progressDisplayName or "")
    timer.preferProgressSpellName = (meta.preferProgressSpellName == true)
    timer.ringEnabled = (meta.ringEnabled == true)
    timer.ringRenameEnabled = (meta.ringRenameEnabled == true)
    timer.ringRenameText = LocalizeDynamicText(meta.ringRenameText or "")
    timer.castProgressBarEnabled = (meta.castProgressBarEnabled == true)
    timer.castProgressBarRenameEnabled = (meta.castProgressBarRenameEnabled == true)
    timer.castProgressBarRenameText = LocalizeDynamicText(meta.castProgressBarRenameText or "")
    timer.ringCastCheckEnabled = (meta.ringCastCheckEnabled == true)
    timer.ringPlan = type(meta.ringPlan) == "table" and DeepCopy(meta.ringPlan) or nil

    timer.trashTimerBarHideAboveEnabled = meta.timerBarHideAboveEnabled == true
    timer.trashTimerBarHideAboveSeconds = math.max(0, tonumber(meta.timerBarHideAboveSeconds) or 0)
    if timer.trashTimerBarHideAboveEnabled == true then
        timer.timerBarDuration = timer.trashTimerBarHideAboveSeconds
    end
    timer.trashKeepTimerBarAfterReadyEnabled = meta.keepTimerBarAfterReadyEnabled == true
    timer.trashKeepTimerBarAfterReadySeconds = math.max(0, tonumber(meta.keepTimerBarAfterReadySeconds) or 0)
    timer.trashReadyAt = nil
    timer.countdownVoiceEnabled = (meta.countdownVoiceEnabled == true)
    timer.countdownPlayName = (meta.countdownPlayName == true)

    if meta.countdownEnabled == true then
        timer.countdownMode = "own"
        timer.useBlizzardHintCountdown = false
        timer.preAlertEnabled = true
        timer.preAlertFired = false
        timer.timelinePreAlertLead = tonumber(meta.countdownLead) or VIRTUAL_HINT_REMAINING_SECS
        timer.preAlertText = LocalizeDynamicText(meta.countdownText or displayName)
    else
        timer.useBlizzardHintCountdown = false
        timer.preAlertEnabled = false
        timer.preAlertText = nil
        timer.preAlertFired = true
        timer.timelinePreAlertLead = 0
        timer.countdownMode = "none"
    end

    if meta.centralEnabled == true then
        timer.centralMode = "own"
        timer.useBlizzardHintCentral = false
        timer.centralEnabled = true
        timer.centralFired = false
        timer.centralLead = tonumber(meta.centralLead) or 0
        timer.screenText = LocalizeDynamicText(meta.centralText or displayName)
    else
        timer.useBlizzardHintCentral = false
        timer.centralEnabled = false
        timer.centralFired = true
        timer.centralLead = 0
        timer.screenText = nil
        timer.centralMode = "none"
    end
end

local function IsRingProgressGloballyEnabled()
    local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    if not (Ring and type(Ring.ShowSequence) == "function" and type(Ring.ShowEntry) == "function") then
        return false
    end
    local db = nil
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, mdb = pcall(ExwindTools.GetModuleDB, ExwindTools, "ExBoss.RingProgress", { enabled = true })
        if ok and type(mdb) == "table" then
            db = mdb
        end
    end
    if type(db) ~= "table" then
        db = EXBOSS12S2 and EXBOSS12S2.timer and EXBOSS12S2.timer.ringProgress or nil
    end
    return type(db) == "table" and db.enabled == true
end

local function IsCastProgressBarGloballyEnabled()
    local CastBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
    if not (CastBar and type(CastBar.ShowSequence) == "function" and type(CastBar.ShowEntry) == "function") then
        return false
    end
    -- 旧配置没有 enabled 时保持旧行为（启用）；只有用户明确关闭才停用。
    local db = nil
    if ExwindTools and type(ExwindTools.GetModuleDB) == "function" then
        local ok, moduleDB = pcall(ExwindTools.GetModuleDB, ExwindTools, "ExBoss.CastProgressBar", { enabled = true })
        if ok and type(moduleDB) == "table" then
            db = moduleDB
        end
    end
    return type(db) ~= "table" or db.enabled ~= false
end

local function EnrichProgressPlan(plan, timer)
    if type(plan) ~= "table" or type(timer) ~= "table" then
        return plan
    end
    for i = 1, #plan do
        local phase = plan[i]
        if type(phase) == "table" then
            phase.displayName = phase.displayName or timer.displayName or timer.baseDisplayName
            phase.progressDisplayName = phase.progressDisplayName or timer.progressDisplayName
            phase.preferSpellName = timer.preferProgressSpellName == true
            phase.spellID = phase.spellID or timer.spellID or timer.spellIdentifier
            phase.iconFileID = phase.iconFileID or timer.iconFileID
            phase.ringRenameEnabled = timer.ringRenameEnabled == true
            phase.ringRenameText = tostring(timer.ringRenameText or "")
            phase.castBarRenameEnabled = timer.castProgressBarRenameEnabled == true
            phase.castBarRenameText = tostring(timer.castProgressBarRenameText or "")
        end
    end
    return plan
end

local function ShowProgressDisplays(plan, opts)
    opts = type(opts) == "table" and opts or {}
    if type(plan) ~= "table" or #plan == 0 then
        return false
    end

    local shown = false
    if opts.ringEnabled ~= false and IsRingProgressGloballyEnabled() then
        local Ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        if #plan > 1 and Ring and type(Ring.ShowSequence) == "function" then
            Ring:ShowSequence(plan, {
                castCheckEnabled = opts.castCheckEnabled == true,
                owner = type(opts.owner) == "table" and opts.owner or nil,
            })
            shown = true
        elseif Ring and type(Ring.ShowEntry) == "function" then
            local row = DeepCopy(plan[1])
            row.owner = type(opts.owner) == "table" and opts.owner or nil
            Ring:ShowEntry(row)
            shown = true
        end
    end

    if opts.castProgressBarEnabled == true and IsCastProgressBarGloballyEnabled() then
        local CastBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        if #plan > 1 and CastBar and type(CastBar.ShowSequence) == "function" then
            CastBar:ShowSequence(plan, {
                castCheckEnabled = opts.castCheckEnabled == true,
                owner = type(opts.owner) == "table" and opts.owner or nil,
            })
            shown = true
        elseif CastBar and type(CastBar.ShowEntry) == "function" then
            local row = DeepCopy(plan[1])
            row.owner = type(opts.owner) == "table" and opts.owner or nil
            CastBar:ShowEntry(row)
            shown = true
        end
    end

    return shown
end

local function BuildTrashRingPlanForCurrentStart(timer, runtime)
    local rawPlan = type(timer) == "table" and type(timer.ringPlan) == "table" and timer.ringPlan or nil
    if not rawPlan or #rawPlan == 0 then
        return nil
    end
    local elapsed = 0
    if type(runtime) == "table" then
        local startAt = tonumber(runtime.activeCastStartAt)
        if startAt then
            elapsed = math.max(0, GetTime() - startAt)
        end
    end

    local out = {}
    for i = 1, #rawPlan do
        local phase = rawPlan[i]
        local duration = tonumber(phase and phase.duration) or 0
        if duration > 0 then
            if elapsed >= duration then
                elapsed = elapsed - duration
            else
                local row = DeepCopy(phase)
                row.duration = math.max(0.1, duration - elapsed)
                out[#out + 1] = row
                elapsed = 0
            end
        end
    end
    if #out == 0 then
        return nil
    end
    return out
end

local function BuildBossProgressPlanForCast(timer)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.useRingProgress ~= true then
        return nil
    end
    if timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true then
        return nil
    end

    local plan = {}
    local castDuration = tonumber(timer.ringCastDuration)
    local channelDuration = tonumber(timer.ringChannelDuration)
    if castDuration and castDuration > 0 then
        plan[#plan + 1] = { duration = castDuration, castKind = "cast" }
    end
    if channelDuration and channelDuration > 0 then
        plan[#plan + 1] = { duration = channelDuration, castKind = "channel" }
    end

    if #plan == 0 then
        return nil
    end

    EnrichProgressPlan(plan, timer)
    local castCheckEnabled = (timer.ringCastCheckEnabled == true)
    if castCheckEnabled then
        for i = 1, #plan do
            if type(plan[i]) == "table" then
                plan[i].castCheckEnabled = true
            end
        end
    end
    return plan, castCheckEnabled
end

local function BuildBossProgressPlanForSpecificKind(timer, wantedKind)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.useRingProgress ~= true then
        return nil
    end
    if timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true then
        return nil
    end

    local kind = tostring(wantedKind or "")
    local plan = {}
    local duration = kind == "cast" and tonumber(timer.ringCastDuration) or tonumber(timer.ringChannelDuration)
    if duration and duration > 0 then
        plan[1] = { duration = duration, castKind = kind }
    end

    if #plan == 0 then
        return nil
    end

    EnrichProgressPlan(plan, timer)
    local castCheckEnabled = (timer.ringCastCheckEnabled == true)
    if castCheckEnabled then
        for i = 1, #plan do
            if type(plan[i]) == "table" then
                plan[i].castCheckEnabled = true
            end
        end
    end
    return plan, castCheckEnabled
end

local function BuildBossProgressPlanForObservedStart(timer, castKind)
    local kind = tostring(castKind or "")
    if kind == "channel" then
        return BuildBossProgressPlanForSpecificKind(timer, "channel")
    end

    local plan, castCheckEnabled = BuildBossProgressPlanForSpecificKind(timer, "cast")
    if type(plan) == "table" and #plan > 0 then
        return plan, castCheckEnabled
    end
    if kind == "cast" then
        local fullPlan, fullCastCheckEnabled = BuildBossProgressPlanForCast(timer)
        if type(fullPlan) == "table" and #fullPlan > 0 then
            return fullPlan, fullCastCheckEnabled
        end
    end
    return nil
end

local function PlayTrashObservedCastStartRing(runtime, timer, spellID)
    if type(runtime) ~= "table" or type(timer) ~= "table" then
        return false
    end
    if timer.ringEnabled ~= true and timer.castProgressBarEnabled ~= true then
        return false
    end
    if type(timer.ringPlan) ~= "table" or #timer.ringPlan == 0 then
        return false
    end
    if not IsRingProgressGloballyEnabled() and not IsCastProgressBarGloballyEnabled() then
        return false
    end

    runtime._trashCastStartRingKeys = runtime._trashCastStartRingKeys or {}
    local key = tostring(math.floor(tonumber(spellID) or 0)) ..
        ":" .. string.format("%.3f", tonumber(runtime.activeCastStartAt) or 0)
    if runtime._trashCastStartRingKeys[key] == true then
        return false
    end
    runtime._trashCastStartRingKeys[key] = true

    local plan = BuildTrashRingPlanForCurrentStart(timer, runtime)
    if not plan then
        return false
    end
    EnrichProgressPlan(plan, timer)
    local castCheckEnabled = (timer.ringCastCheckEnabled == true)
    if castCheckEnabled then
        for i = 1, #plan do
            if type(plan[i]) == "table" then
                plan[i].castCheckEnabled = castCheckEnabled
            end
        end
    end
    return ShowProgressDisplays(plan, {
        castCheckEnabled = castCheckEnabled,
        ringEnabled = timer.ringEnabled == true,
        castProgressBarEnabled = timer.castProgressBarEnabled == true,
        owner = {
            source = "trash",
            runtime = runtime,
            castKind = tostring(runtime.activeCastKind or ""),
            castBarID = NormalizeCastBarID(runtime.activeCastBarID),
            earlyStopEnabled = true,
        },
    })
end

function Scheduler:ShowBossProgressFromTimer(timer)
    if type(timer) ~= "table" or timer.disabled then
        return false
    end
    if timer.trashMeta ~= nil or timer.trashRuntime ~= nil or timer.trashSpellData ~= nil then
        return false
    end
    local plan, castCheckEnabled = BuildBossProgressPlanForCast(timer)
    if type(plan) ~= "table" or #plan == 0 then
        return false
    end

    local useBossObserve = self:_ShouldUseBossCastObserve(timer)
    return ShowProgressDisplays(plan, {
        castCheckEnabled = castCheckEnabled == true,
        ringEnabled = timer.ringEnabled == true and not useBossObserve,
        castProgressBarEnabled = timer.castProgressBarEnabled == true and not useBossObserve,
    })
end

function Scheduler:ShowBossProgressFromObservedStart(timer, castKind, unit, _unitGUID, castBarID)
    if type(timer) ~= "table" or timer.disabled then
        BossProgressDebugPrint("show skipped: invalid-or-disabled timer")
        return false
    end
    local ringEnabled = timer.ringEnabled == true and IsRingProgressGloballyEnabled()
    local castProgressBarEnabled = timer.castProgressBarEnabled == true and IsCastProgressBarGloballyEnabled()
    if ringEnabled ~= true and castProgressBarEnabled ~= true then
        BossProgressDebugPrint(string.format(
            "show skipped event=%s unit=%s: all displays disabled",
            tostring(timer.eventID), tostring(NormalizeUnitToken(unit) or unit)
        ))
        return false
    end

    local plan, castCheckEnabled = BuildBossProgressPlanForObservedStart(timer, castKind)
    if type(plan) ~= "table" or #plan == 0 then
        BossProgressDebugPrint(string.format(
            "show skipped event=%s unit=%s kind=%s: no progress plan",
            tostring(timer.eventID), tostring(NormalizeUnitToken(unit) or unit), tostring(castKind)
        ))
        return false
    end

    if tostring(castKind or "") == "channel" then
        self:_HandleBossObservedChannelTransition(timer, unit, castBarID)
    end

    local observedDuration = (type(plan) == "table" and #plan > 0) and ComputeProgressPlanTotalDuration(plan) or 0
    if observedDuration <= 0.05 and type(timer) == "table" and tonumber(timer.castTime) then
        observedDuration = math.max(0, tonumber(timer.castTime) - GetTime())
    end

    local runtime = self:_CreateBossObservedRuntime(
        timer,
        castKind,
        unit,
        castBarID,
        observedDuration
    )

    local owner = {
        source = "boss",
        unit = NormalizeUnitToken(unit),
        castKind = tostring(castKind or ""),
        castBarID = NormalizeCastBarID(castBarID),
        encounterID = tonumber(timer.encounterID),
        eventID = tonumber(timer.eventID),
        runtime = runtime and runtime.id or nil,
        earlyStopEnabled = true,
    }

    local shown = false
    if type(plan) == "table" and #plan > 0 then
        shown = ShowProgressDisplays(plan, {
            castCheckEnabled = castCheckEnabled == true,
            ringEnabled = ringEnabled == true,
            castProgressBarEnabled = castProgressBarEnabled == true,
            owner = owner,
        })
    end
    DispatchBossObservedCastEvent(BOSS_OBSERVED_CAST_START_EVENT, runtime)
    if shown ~= true and runtime and runtime.id then
        self._bossObservedRuntimes[runtime.id] = nil
    end
    BossProgressDebugPrint(string.format(
        "show event=%s unit=%s kind=%s castBarID=%s phases=%d ring=%s castBar=%s check=%s shown=%s",
        tostring(timer.eventID), tostring(NormalizeUnitToken(unit) or unit), tostring(castKind),
        tostring(NormalizeCastBarID(castBarID)), type(plan) == "table" and #plan or 0,
        tostring(ringEnabled), tostring(castProgressBarEnabled), tostring(castCheckEnabled == true), tostring(shown)
    ))
    return shown == true
end

function Scheduler:_ShouldUseBossCastObserve(timer)
    return type(timer) == "table"
        and timer.disabled ~= true
        and timer.source ~= "trash"
        and timer.useRingProgress == true
        and (timer.ringEnabled == true or timer.castProgressBarEnabled == true)
end

local function BuildBossCastObserveSnapshot(timer)
    if type(timer) ~= "table" then
        return nil
    end
    return DeepCopy(timer)
end

function Scheduler:_PruneBossObservedRuntimes(now)
    now = tonumber(now) or GetTime()
    for runtimeID, runtime in pairs(self._bossObservedRuntimes or {}) do
        if type(runtime) ~= "table" then
            self._bossObservedRuntimes[runtimeID] = nil
        else
            local expiresAt = tonumber(runtime.expiresAt) or 0
            if runtime.active ~= true or (expiresAt > 0 and now > expiresAt) then
                self._bossObservedRuntimes[runtimeID] = nil
            end
        end
    end
end

function Scheduler:_CreateBossObservedRuntime(timer, castKind, unit, castBarID, totalDuration)
    local runtimeID = tonumber(self._bossObservedRuntimeNextID) or 1
    self._bossObservedRuntimeNextID = runtimeID + 1

    local now = GetTime()
    local runtime = {
        id = runtimeID,
        encounterID = tonumber(timer and timer.encounterID) or tonumber(self._encounterID),
        eventID = tonumber(timer and timer.eventID),
        timerID = tonumber(timer and timer.id),
        castKind = tostring(castKind or ""),
        castBarID = NormalizeCastBarID(castBarID),
        units = {},
        active = true,
        startedAt = now,
        totalDuration = math.max(0, tonumber(totalDuration) or 0),
        expiresAt = now + math.max(1.0, tonumber(totalDuration) or 0) + 2.0,
        timerSnapshot = BuildBossCastObserveSnapshot(timer),
    }

    local unitToken = NormalizeUnitToken(unit)
    if unitToken then
        runtime.units[unitToken] = true
        runtime.primaryUnit = unitToken
    end

    self._bossObservedRuntimes[runtimeID] = runtime
    return runtime
end

BuildBossObservedCastEventPayload = function(runtime)
    if type(runtime) ~= "table" then
        return nil
    end
    local timer = type(runtime.timerSnapshot) == "table" and runtime.timerSnapshot or nil
    local totalDuration = math.max(0, tonumber(runtime.totalDuration) or 0)
    if totalDuration <= 0.05 and type(timer) == "table" and tonumber(timer.castTime) and tonumber(runtime.startedAt) then
        totalDuration = math.max(0, tonumber(timer.castTime) - tonumber(runtime.startedAt))
    end
    return {
        runtimeID = tonumber(runtime.id),
        encounterID = tonumber(runtime.encounterID),
        eventID = tonumber(runtime.eventID),
        timerID = tonumber(runtime.timerID),
        spellID = tonumber(timer and (timer.spellID or timer.spellIdentifier) or nil),
        displayName = tostring(timer and (timer.displayName or timer.baseDisplayName) or ""),
        progressDisplayName = tostring(timer and timer.progressDisplayName or ""),
        source = "boss",
        unit = NormalizeUnitToken(runtime.primaryUnit),
        castKind = tostring(runtime.castKind or ""),
        castBarID = NormalizeCastBarID(runtime.castBarID),
        startedAt = tonumber(runtime.startedAt) or 0,
        stoppedAt = tonumber(runtime.stoppedAt) or 0,
        totalDuration = totalDuration,
    }
end

DispatchBossObservedCastEvent = function(eventName, runtime)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    local payload = BuildBossObservedCastEventPayload(runtime)
    if type(payload) ~= "table" then
        return
    end
    ExwindTools:SendEvent(eventName, payload)
end

local function ResolveTrashObservedCastDuration(runtime, timer)
    local castKind = tostring(type(runtime) == "table" and runtime.activeCastKind or "")
    if type(timer) == "table" and type(timer.ringPlan) == "table" then
        for i = 1, #timer.ringPlan do
            local item = timer.ringPlan[i]
            if type(item) == "table" and tonumber(item.duration) and tonumber(item.duration) > 0 then
                local itemKind = tostring(item.castKind or "")
                if itemKind == castKind then
                    return math.max(0, tonumber(item.duration) or 0)
                end
            end
        end
    end
    if type(timer) == "table" and tonumber(timer.castTime) and type(runtime) == "table" and tonumber(runtime.activeCastStartAt) then
        local remaining = tonumber(timer.castTime) - tonumber(runtime.activeCastStartAt)
        if remaining > 0.05 then
            return remaining
        end
    end
    return nil
end

local function DispatchTrashObservedCastStartEvent(runtime, spellID, timer)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID) or tonumber(runtime.activeSpellID) or tonumber(runtime.activeObservedSpellID)
    if not sid then
        return
    end
    ExwindTools:SendEvent(TRASH_OBSERVED_CAST_START_EVENT, {
        source = "trash",
        runtime = runtime,
        runtimeKey = tostring(runtime),
        mapID = tonumber(runtime.matchedMapID),
        npcID = tonumber(runtime.matchedNPCID),
        spellID = sid,
        displayName = tostring(type(timer) == "table" and
            (timer.progressDisplayName or timer.displayName or timer.baseDisplayName) or sid),
        progressDisplayName = tostring(type(timer) == "table" and timer.progressDisplayName or ""),
        unit = tostring(runtime._nameplateUnit or ""),
        castKind = tostring(runtime.activeCastKind or ""),
        castBarID = NormalizeCastBarID(runtime.activeCastBarID),
        startedAt = tonumber(runtime.activeCastStartAt) or 0,
        totalDuration = ResolveTrashObservedCastDuration(runtime, timer),
    })
end

local function DispatchTrashCastStartVoiceTriggeredEvent(runtime, spellID, timer)
    if not (ExwindTools and type(ExwindTools.SendEvent) == "function") then
        return
    end
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID) or tonumber(runtime.activeSpellID) or tonumber(runtime.activeObservedSpellID)
    if not sid then
        return
    end
    local seq = tonumber(runtime.activeCastSeq)
    local dedupeKey = tostring(seq or "nil") .. ":" .. tostring(sid)
    if runtime._targetAlertStartEventDedupeKey == dedupeKey then
        return
    end
    runtime._targetAlertStartEventDedupeKey = dedupeKey
    ExwindTools:SendEvent(TRASH_CAST_START_VOICE_TRIGGERED_EVENT, {
        source = "trash_voice_start",
        runtime = runtime,
        runtimeKey = tostring(runtime),
        mapID = tonumber(runtime.matchedMapID),
        npcID = tonumber(runtime.matchedNPCID),
        spellID = sid,
        displayName = tostring(type(timer) == "table" and
            (timer.progressDisplayName or timer.displayName or timer.baseDisplayName) or sid),
        progressDisplayName = tostring(type(timer) == "table" and timer.progressDisplayName or ""),
        unit = tostring(runtime._nameplateUnit or ""),
        castKind = tostring(runtime.activeCastKind or ""),
        castBarID = NormalizeCastBarID(runtime.activeCastBarID),
        startedAt = tonumber(runtime.activeCastStartAt) or 0,
        totalDuration = ResolveTrashObservedCastDuration(runtime, timer),
    })
end

function Scheduler:_FindBossObservedTransitionSource(timer, unit, nextCastBarID)
    local encounterID = tonumber(timer and timer.encounterID) or tonumber(self._encounterID)
    local eventID = tonumber(timer and timer.eventID)
    local unitToken = NormalizeUnitToken(unit)
    local normalizedNextCastBarID = NormalizeCastBarID(nextCastBarID)
    if not encounterID or not normalizedNextCastBarID then
        return nil
    end

    self:_PruneBossObservedRuntimes()

    local wantedPreviousCastBarID = normalizedNextCastBarID - 1
    local bestRuntime, bestScore = nil, nil
    for _, runtime in pairs(self._bossObservedRuntimes or {}) do
        if type(runtime) == "table"
            and runtime.active == true
            and tonumber(runtime.encounterID) == encounterID
            and tostring(runtime.castKind or "") == "cast"
            and NormalizeCastBarID(runtime.castBarID) == wantedPreviousCastBarID then
            local score = 0
            if eventID and tonumber(runtime.eventID) == eventID then
                score = score + 1000
            end
            if unitToken and type(runtime.units) == "table" and runtime.units[unitToken] == true then
                score = score + 100
            end
            if not bestScore or score > bestScore then
                bestScore = score
                bestRuntime = runtime
            end
        end
    end

    return bestRuntime
end

function Scheduler:_FindBossObservedRuntimeForStop(unit, castKind, castBarID, specialEventID)
    local encounterID = tonumber(self._encounterID)
    if not encounterID then
        return nil
    end

    self:_PruneBossObservedRuntimes()

    local unitToken = NormalizeUnitToken(unit)
    local normalizedCastBarID = NormalizeCastBarID(castBarID)
    local wantedKind = tostring(castKind or "")
    local wantedEventID = tonumber(specialEventID)

    local bestRuntime, bestScore = nil, nil
    for _, runtime in pairs(self._bossObservedRuntimes or {}) do
        if type(runtime) == "table"
            and runtime.active == true
            and tonumber(runtime.encounterID) == encounterID
            and tostring(runtime.castKind or "") == wantedKind then
            local matches = true
            local score = 0
            if wantedEventID then
                if tonumber(runtime.eventID) ~= wantedEventID then
                    matches = false
                else
                    score = score + 1000
                end
            end

            if matches and normalizedCastBarID ~= nil then
                if NormalizeCastBarID(runtime.castBarID) == normalizedCastBarID then
                    score = score + 100
                elseif not wantedEventID then
                    matches = false
                end
            end

            if matches and unitToken and type(runtime.units) == "table" and runtime.units[unitToken] == true then
                score = score + 10
            end

            if matches and score > 0 and (not bestScore or score > bestScore) then
                bestScore = score
                bestRuntime = runtime
            end
        end
    end

    return bestRuntime
end

function Scheduler:_StopBossObservedRuntime(runtime)
    if type(runtime) ~= "table" or runtime.active ~= true then
        return false
    end
    runtime.active = false
    runtime.stoppedAt = GetTime()
    DispatchBossObservedCastEvent(BOSS_OBSERVED_CAST_STOP_EVENT, runtime)

    local owner = {
        source = "boss",
        runtime = runtime.id,
    }
    local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
    if castBar and type(castBar.StopByOwner) == "function" then
        castBar:StopByOwner(owner)
    end
    local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
    if ring and type(ring.StopByOwner) == "function" then
        ring:StopByOwner(owner)
    end
    self._bossObservedRuntimes[runtime.id] = nil
    return true
end

function Scheduler:_AttachBossObservedRuntimeUnitAlias(unit, castKind, castBarID)
    local unitToken = NormalizeUnitToken(unit)
    if not unitToken then
        return
    end
    local runtime = self:_FindBossObservedRuntimeForStop(unit, castKind, castBarID, nil)
    if type(runtime) ~= "table" then
        return
    end
    runtime.units = type(runtime.units) == "table" and runtime.units or {}
    runtime.units[unitToken] = true
end

function Scheduler:_ResolveAndStopBossObservedRuntime(unit, castKind, castBarID, specialEventID)
    local runtime = self:_FindBossObservedRuntimeForStop(unit, castKind, castBarID, specialEventID)
    if not runtime then
        BossProgressDebugPrint(string.format(
            "stop no-match unit=%s kind=%s castBarID=%s specialEvent=%s",
            tostring(NormalizeUnitToken(unit) or unit), tostring(castKind), tostring(NormalizeCastBarID(castBarID)),
            tostring(specialEventID)
        ))
        return false
    end
    BossProgressDebugPrint(string.format(
        "stop match runtime=%s event=%s unit=%s kind=%s castBarID=%s",
        tostring(runtime.id), tostring(runtime.eventID), tostring(NormalizeUnitToken(unit) or unit), tostring(castKind),
        tostring(NormalizeCastBarID(castBarID))
    ))
    return self:_StopBossObservedRuntime(runtime)
end

function Scheduler:_HandleBossObservedChannelTransition(timer, unit, castBarID)
    local runtime = self:_FindBossObservedTransitionSource(timer, unit, castBarID)
    if not runtime then
        return false
    end
    return self:_StopBossObservedRuntime(runtime)
end

function Scheduler:_TryShowBossObservedChannelFromStart(unit, castBarID)
    local runtime = self:_FindBossObservedTransitionSource(nil, unit, castBarID)
    if type(runtime) ~= "table" then
        return false
    end
    local timer = (type(self._active) == "table" and self._active[tonumber(runtime.timerID)]) or runtime.timerSnapshot
    if type(timer) ~= "table" then
        return false
    end
    return self:ShowBossProgressFromObservedStart(timer, "channel", unit, nil, castBarID) == true
end

function Scheduler:_DropBossCastObservePending(pendingID)
    local id = tonumber(pendingID)
    if not id then
        return
    end
    local pending = self._bossCastObservePending and self._bossCastObservePending[id] or nil
    if not pending then
        return
    end
    BossProgressDebugPrint(string.format(
        "drop pending=%s event=%s status=%s",
        tostring(pending.id), tostring(pending.eventID), tostring(pending.status)
    ))
    self._bossCastObservePending[id] = nil
    local timerID = tonumber(pending.timerID)
    if timerID and self._bossCastObservePendingByTimerID[timerID] == id then
        self._bossCastObservePendingByTimerID[timerID] = nil
    end
end

function Scheduler:_DropBossCastObservePendingByTimerID(timerID)
    local id = tonumber(timerID)
    if not id then
        return
    end
    local pendingID = self._bossCastObservePendingByTimerID and self._bossCastObservePendingByTimerID[id] or nil
    if pendingID then
        self:_DropBossCastObservePending(pendingID)
    end
end

function Scheduler:_QueueBossCastObserveForTimer(timer, now)
    if not self:_ShouldUseBossCastObserve(timer) then
        return nil
    end
    local timerID = tonumber(timer and timer.id)
    local castTime = tonumber(timer and timer.castTime)
    if not timerID or not castTime then
        return nil
    end
    BossProgressDebugPrint(string.format(
        "queue begin timer=%s event=%s pendingTable=%s byTimerTable=%s",
        tostring(timerID), tostring(timer.eventID), tostring(type(self._bossCastObservePending)),
        tostring(type(self._bossCastObservePendingByTimerID))
    ))
    if self._bossCastObservePendingByTimerID[timerID] then
        return self._bossCastObservePendingByTimerID[timerID]
    end

    now = tonumber(now) or GetTime()
    local observeLead = math.max(0, tonumber(timer.castObserveLead) or BOSS_CAST_OBSERVE_LEAD)
    local windowAfter = math.max(BOSS_CAST_OBSERVE_MIN_WINDOW_AFTER, tonumber(timer.ringWindowAfter) or 2)
    local expectedKind = NormalizeBossObserveExpectedKind(timer.castObserveExpectedKind)
    if expectedKind == "" then
        local hasCast = (tonumber(timer.ringCastDuration) or 0) > 0
        local hasChannel = (tonumber(timer.ringChannelDuration) or 0) > 0
        if hasCast and not hasChannel then
            expectedKind = "cast"
        elseif hasChannel and not hasCast then
            expectedKind = "channel"
        else
            expectedKind = "any"
        end
    end
    local pendingID = tonumber(self._bossCastObserveNextID) or 1
    self._bossCastObserveNextID = pendingID + 1
    BossProgressDebugPrint(string.format("queue snapshot begin timer=%s event=%s", tostring(timerID), tostring(timer.eventID)))
    local timerSnapshot = BuildBossCastObserveSnapshot(timer)
    BossProgressDebugPrint(string.format("queue snapshot done timer=%s event=%s", tostring(timerID), tostring(timer.eventID)))
    local pending = {
        id = pendingID,
        timerID = timerID,
        eventID = SafeToNumber(timer.eventID),
        expectedAt = castTime,
        observeStartAt = castTime - observeLead,
        observeEndAt = castTime + windowAfter,
        expectedKind = expectedKind,
        unitFilter = type(timer.castObserveUnitFilter) == "table" and DeepCopy(timer.castObserveUnitFilter)
            or timer.castObserveUnitFilter,
        matchOrdinal = math.max(1, math.floor(tonumber(timer.castObserveOrdinal) or 1)),
        matchedCount = 0,
        sessionToken = tonumber(self._sessionToken) or 0,
        status = ((castTime - observeLead) <= now) and "active" or "queued",
        timerSnapshot = timerSnapshot,
    }
    self._bossCastObservePending[pendingID] = pending
    self._bossCastObservePendingByTimerID[timerID] = pendingID
    BossProgressDebugPrint(string.format(
        "queue pending=%s event=%s encounter=%s kind=%s unit=%s start=%.3f end=%.3f",
        tostring(pendingID), tostring(pending.eventID), tostring(timer.encounterID or self._encounterID),
        tostring(pending.expectedKind), tostring(pending.unitFilter),
        tonumber(pending.observeStartAt) or 0, tonumber(pending.observeEndAt) or 0
    ))

    return pendingID
end

function Scheduler:_PruneBossCastObserveRecentStarts(now)
    now = tonumber(now) or GetTime()
    local keep = BOSS_CAST_OBSERVE_RECENT_KEEP
    for i = #self._bossCastObserveRecentStarts, 1, -1 do
        local entry = self._bossCastObserveRecentStarts[i]
        if type(entry) ~= "table" or (now - (tonumber(entry.at) or 0)) > keep then
            table.remove(self._bossCastObserveRecentStarts, i)
        end
    end
end

function Scheduler:_PendingAcceptsBossCastStart(pending, entry)
    if type(pending) ~= "table" or type(entry) ~= "table" then
        return false
    end
    if pending.status ~= "active" then
        return false
    end
    if (tonumber(pending.sessionToken) or 0) ~= (tonumber(self._sessionToken) or 0) then
        return false
    end
    local at = tonumber(entry.at) or 0
    if at < (tonumber(pending.observeStartAt) or 0) or at > (tonumber(pending.observeEndAt) or 0) then
        return false
    end
    local expectedKind = tostring(pending.expectedKind or "any")
    local actualKind = tostring(entry.kind or "")
    if expectedKind ~= "any" and expectedKind ~= "" and expectedKind ~= actualKind then
        BossProgressDebugPrint(string.format(
            "reject pending=%s event=%s expectedKind=%s actualKind=%s unit=%s",
            tostring(pending.id), tostring(pending.eventID), expectedKind, actualKind, tostring(entry.unit)
        ))
        return false
    end
    if not BossObserveUnitFilterMatches(pending.unitFilter, entry) then
        BossProgressDebugPrint(string.format(
            "reject pending=%s event=%s expectedUnit=%s actualUnit=%s kind=%s",
            tostring(pending.id), tostring(pending.eventID), tostring(pending.unitFilter),
            tostring(entry.unit), tostring(entry.kind)
        ))
        return false
    end
    return true
end

function Scheduler:_FindBestBossCastObservePending(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local bestPending = nil
    local bestDistance = math.huge
    for _, pending in pairs(self._bossCastObservePending or {}) do
        if self:_PendingAcceptsBossCastStart(pending, entry) then
            local distance = math.abs((tonumber(pending.expectedAt) or 0) - (tonumber(entry.at) or 0))
            if distance < bestDistance then
                bestDistance = distance
                bestPending = pending
            end
        end
    end
    return bestPending
end

function Scheduler:_MatchBossCastObservePending(pending, entry)
    if type(pending) ~= "table" or type(entry) ~= "table" then
        return false
    end
    local timer = (type(self._active) == "table" and self._active[tonumber(pending.timerID)]) or pending.timerSnapshot
    if type(timer) ~= "table" then
        self:_DropBossCastObservePending(pending.id)
        return false
    end

    pending.status = "matched"
    BossProgressDebugPrint(string.format(
        "match pending=%s event=%s unit=%s kind=%s castBarID=%s",
        tostring(pending.id), tostring(timer.eventID), tostring(entry.unit),
        tostring(entry.kind), tostring(entry.castBarID)
    ))

    self:ShowBossProgressFromObservedStart(
        timer,
        entry.kind,
        entry.unit,
        nil,
        entry.castBarID
    )
    self:_DropBossCastObservePending(pending.id)
    return true
end

function Scheduler:_ConsumeBossCastObserveStart(pending, entry)
    if type(pending) ~= "table" or type(entry) ~= "table" then
        return false
    end
    if entry.assignedPendingID == pending.id then
        return false
    end
    if entry.assignedPendingID and entry.assignedPendingID ~= pending.id then
        return false
    end
    entry.assignedPendingID = pending.id
    pending.matchedCount = (tonumber(pending.matchedCount) or 0) + 1
    if pending.matchedCount >= (tonumber(pending.matchOrdinal) or 1) then
        return self:_MatchBossCastObservePending(pending, entry)
    end

    return true
end

function Scheduler:_ReplayBossCastObserveRecentStarts(pending, now)
    if type(pending) ~= "table" or pending.status ~= "active" then
        return
    end
    now = tonumber(now) or GetTime()
    for i = 1, #self._bossCastObserveRecentStarts do
        local entry = self._bossCastObserveRecentStarts[i]
        if type(entry) == "table"
            and not entry.assignedPendingID
            and (tonumber(entry.at) or 0) <= now
            and self:_PendingAcceptsBossCastStart(pending, entry) then
            if self:_ConsumeBossCastObserveStart(pending, entry) and pending.status == "matched" then
                return
            end
        end
    end
end

function Scheduler:_TickBossCastObserve(now)
    now = tonumber(now) or GetTime()
    self:_PruneBossCastObserveRecentStarts(now)
    self:_PruneBossObservedRuntimes(now)
    for pendingID, pending in pairs(self._bossCastObservePending or {}) do
        if type(pending) ~= "table" then
            self._bossCastObservePending[pendingID] = nil
        elseif (tonumber(pending.sessionToken) or 0) ~= (tonumber(self._sessionToken) or 0) then
            self:_DropBossCastObservePending(pendingID)
        elseif now > (tonumber(pending.observeEndAt) or 0) then
            BossProgressDebugPrint(string.format(
                "expire pending=%s event=%s kind=%s unit=%s end=%.3f now=%.3f",
                tostring(pending.id), tostring(pending.eventID), tostring(pending.expectedKind),
                tostring(pending.unitFilter), tonumber(pending.observeEndAt) or 0, now
            ))
            self:_DropBossCastObservePending(pendingID)
        elseif pending.status == "queued" and now >= (tonumber(pending.observeStartAt) or 0) then
            pending.status = "active"
            BossProgressDebugPrint(string.format(
                "activate pending=%s event=%s kind=%s unit=%s",
                tostring(pending.id), tostring(pending.eventID), tostring(pending.expectedKind),
                tostring(pending.unitFilter)
            ))

            self:_ReplayBossCastObserveRecentStarts(pending, now)
        elseif pending.status == "active" then
            self:_ReplayBossCastObserveRecentStarts(pending, now)
        end
    end
end

function Scheduler:_RecordBossCastObserveStart(unit, kind, castBarID)
    if not (self._running and IsBossCastObserveUnit(unit)) then
        return
    end
    local unitToken = NormalizeUnitToken(unit)
    local now = GetTime()
    BossProgressDebugPrint(string.format(
        "observe start unit=%s kind=%s castBarID=%s",
        tostring(unitToken), tostring(kind), tostring(NormalizeCastBarID(castBarID))
    ))
    self:_PruneBossCastObserveRecentStarts(now)

    local entry = {
        id = tonumber(self._bossCastObserveNextStartID) or 1,
        unit = unitToken,
        kind = tostring(kind or ""),
        castBarID = NormalizeCastBarID(castBarID),
        at = now,
        priority = GetBossCastObserveUnitPriority(unitToken),
        assignedPendingID = nil,
    }
    self._bossCastObserveNextStartID = entry.id + 1

    for i = #self._bossCastObserveRecentStarts, 1, -1 do
        local old = self._bossCastObserveRecentStarts[i]
        if type(old) == "table"
            and old.kind == entry.kind
            and old.castBarID ~= nil
            and entry.castBarID ~= nil
            and old.castBarID == entry.castBarID
            and math.abs((tonumber(old.at) or 0) - now) <= 0.05 then
            if entry.priority > (tonumber(old.priority) or 0) then
                old.unit = entry.unit
                old.priority = entry.priority
            end
            entry = old
            break
        end
    end

    if entry.id == (tonumber(self._bossCastObserveNextStartID) or 0) - 1 then
        self._bossCastObserveRecentStarts[#self._bossCastObserveRecentStarts + 1] = entry
    end

    local pending = self:_FindBestBossCastObservePending(entry)
    if pending then
        self:_ConsumeBossCastObserveStart(pending, entry)
    else
        local candidates = {}
        for _, candidate in pairs(self._bossCastObservePending or {}) do
            if type(candidate) == "table" then
                candidates[#candidates + 1] = string.format(
                    "#%s:e%s:%s:%s:%.3f-%.3f",
                    tostring(candidate.id), tostring(candidate.eventID), tostring(candidate.status),
                    tostring(candidate.expectedKind), tonumber(candidate.observeStartAt) or 0,
                    tonumber(candidate.observeEndAt) or 0
                )
            end
        end
        BossProgressDebugPrint(string.format(
            "observe no-match unit=%s kind=%s castBarID=%s pending=%s",
            tostring(unitToken), tostring(kind), tostring(entry.castBarID),
            #candidates > 0 and table.concat(candidates, ",") or "none"
        ))
    end
    if tostring(kind or "") == "channel" and not entry.assignedPendingID then
        self:_TryShowBossObservedChannelFromStart(unitToken, castBarID)
    end
    self:_AttachBossObservedRuntimeUnitAlias(unitToken, kind, castBarID)
end

local function ResolveTimerBarDisplaySettings()
    local timerBar = ExBoss and ExBoss.UI and ExBoss.UI.TimerBar
    local display = timerBar and type(timerBar.GetDB) == "function" and timerBar:GetDB() or nil
    if type(display) ~= "table" then
        return TIMERBAR_DEFAULT_HIDE_LONG_ENABLED, TIMERBAR_LEAD_TIME
    end
    local hideLongEnabled = display.hideLongTimersEnabled
    if hideLongEnabled == nil then hideLongEnabled = TIMERBAR_DEFAULT_HIDE_LONG_ENABLED end
    return hideLongEnabled == true, math.max(0, tonumber(display.hideLongTimersSeconds) or TIMERBAR_LEAD_TIME)
end

-- _AddTimer 标记的固定/AI 事件属于普通“已调度”计时器。此 metadata 是显示全部
-- 的显式资格；trash 的独立 per-timer hide-above 策略不借用全局关闭语义。
local function IsOrdinaryScheduledTimer(timer)
    return type(timer) == "table" and timer.timerBarSchedulePolicy == "SCHEDULED"
end

local function IsTimerBarShowAllScheduled(timer)
    if type(timer) == "table" and timer.trashTimerBarHideAboveEnabled == true then return false end
    if not IsOrdinaryScheduledTimer(timer) then return false end
    local hideLongEnabled = ResolveTimerBarDisplaySettings()
    return hideLongEnabled == false
end

local function ResolveTimerBarLeadTime(timer)
    if type(timer) == "table" and timer.trashTimerBarHideAboveEnabled == true then
        return math.max(0, tonumber(timer.trashTimerBarHideAboveSeconds) or 0)
    end
    local _, hideLongSeconds = ResolveTimerBarDisplaySettings()
    return hideLongSeconds
end

local function ResolveTimerBarDisplayDuration(timer, now)
    local baseDuration = TIMERBAR_LEAD_TIME
    if type(timer) == "table" then
        baseDuration = math.max(1, tonumber(timer.timerBarDuration) or tonumber(timer.duration) or TIMERBAR_LEAD_TIME)
    end
    local remaining = math.max(1, tonumber(type(timer) == "table" and timer.castTime or 0) - tonumber(now or GetTime()))
    if IsTimerBarShowAllScheduled(timer) then
        -- 显示全部从当前调度帧开始计时，不能沿用 30 秒的旧 duration。
        return remaining
    end
    local leadTime = math.max(0, ResolveTimerBarLeadTime(timer))
    if leadTime <= 0 then
        return baseDuration
    end
    return math.max(1, math.min(baseDuration, leadTime, remaining))
end

local function ShouldShowTimerBarNow(timer, now)
    -- per-timer trash override 永远先于全局 show-all/threshold；这条路径与 View
    -- 的 IsRuntimeTimerVisible 使用同一 seconds 优先级。
    if type(timer) == "table" and timer.trashTimerBarHideAboveEnabled == true then
        return now >= (timer.castTime - math.max(0, tonumber(timer.trashTimerBarHideAboveSeconds) or 0))
    end
    if IsTimerBarShowAllScheduled(timer) then return true end
    return now >= (timer.castTime - ResolveTimerBarLeadTime(timer))
end

local function ResolveBunBarLeadTime()
    local tools = rawget(_G, "ExwindTools")
    local display = tools and tools.GetModuleDB and tools:GetModuleDB("ExBoss.BunBar") or nil
    local seconds = type(display) == "table" and display.hideLongTimersSeconds or nil
    if type(seconds) == "number" then
        return math.max(0, seconds)
    end
    return BUNBAR_LEAD_TIME
end

local function ResolveSpellIconFileID(spellIdentifier, fallbackSpellID, explicitIconFileID)
    local iconFileID = tonumber(explicitIconFileID)
    if iconFileID and iconFileID > 0 then
        return iconFileID
    end

    local sid = tonumber(spellIdentifier) or tonumber(fallbackSpellID)
    if not sid then
        return nil
    end

    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, icon = pcall(C_Spell.GetSpellTexture, sid)
        if ok and tonumber(icon) and tonumber(icon) > 0 then
            return tonumber(icon)
        end
    end

    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, sid)
        local icon = ok and type(info) == "table" and tonumber(info.iconID) or nil
        if icon and icon > 0 then
            return icon
        end
    end

    return nil
end

local function TimerDB()
    local tdb = nil
    if _G.EXBossData and _G.EXBossData.GetTimelineModeDB then
        tdb = _G.EXBossData.GetTimelineModeDB()
    else
        -- 兜底
        EXBOSS12S2 = EXBOSS12S2 or {}
        EXBOSS12S2.timer = EXBOSS12S2.timer or {}
        EXBOSS12S2.timer.timelineMode = EXBOSS12S2.timer.timelineMode or {}
        tdb = EXBOSS12S2.timer.timelineMode
    end

    if type(tdb) ~= "table" then
        tdb = {}
    end
    if type(tdb.byEncounter) ~= "table" then tdb.byEncounter = {} end
    if type(tdb.default) ~= "string" or tdb.default == "" then tdb.default = "auto" end
    if type(tdb.fixedDriverByEncounter) ~= "table" then tdb.fixedDriverByEncounter = {} end
    if type(tdb.fixedDriverDefault) ~= "string" or tdb.fixedDriverDefault == "" then
        tdb.fixedDriverDefault = FIXED_DRIVER_TIME
    end
    return tdb
end

local function NormalizeBarDisplayMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "timer" or m == "bun" or m == "both" or m == "none" then
        return m
    end
    return "bun"
end

local function GetBarDisplayMode()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ui = EXBOSS12S2.ui or {}
    EXBOSS12S2.ui.general = EXBOSS12S2.ui.general or {}
    local g = EXBOSS12S2.ui.general
    g.barDisplayMode = NormalizeBarDisplayMode(g.barDisplayMode)
    return g.barDisplayMode
end

local function IsTimerBarEnabledByGlobal()
    local mode = GetBarDisplayMode()
    return mode == "both" or mode == "timer"
end

local function IsBunBarEnabledByGlobal()
    local mode = GetBarDisplayMode()
    return mode == "both" or mode == "bun"
end

local function IsTimerAllowedOnBarBySource(timer, barKind)
    local policy = ExBoss and ExBoss.DisplayPolicy
    if policy and type(policy.ShouldShowTimerOnBar) == "function" then
        return policy.ShouldShowTimerOnBar(timer, barKind) == true
    end
    return true
end

local function IsBossSceneEnabledForCurrentInstance()
    local bossCfg = ExBoss and ExBoss.BossConfig
    if bossCfg and type(bossCfg.IsCurrentSceneEnabled) == "function" then
        local ok, enabled = pcall(bossCfg.IsCurrentSceneEnabled, bossCfg)
        if ok then
            return enabled ~= false
        end
    end

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ui = EXBOSS12S2.ui or {}
    EXBOSS12S2.ui.general = EXBOSS12S2.ui.general or {}
    local g = EXBOSS12S2.ui.general
    if g.bossAlertsEnabledRaid == nil then g.bossAlertsEnabledRaid = false end
    if g.disableEXBossInRaid == nil then
        g.disableEXBossInRaid = (g.bossAlertsEnabledRaid ~= true)
    else
        g.disableEXBossInRaid = (g.disableEXBossInRaid == true)
    end
    if g.bossAlertsEnabledMplus == nil then g.bossAlertsEnabledMplus = true end

    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then
        return g.disableEXBossInRaid ~= true
    end
    if instanceType == "party" then
        return g.bossAlertsEnabledMplus ~= false
    end
    return true
end

local function IsTimelineTestMode()
    return ExwindTools and type(ExwindTools.State) == "table"
        and ExwindTools.State.TimelineTestMode == true
end

-- [DISABLED] ClearEncounterWarningsUI 已注释掉。
-- 原因：在 ENCOUNTER_START 等事件处理链路中调用此函数，会导致 Blizzard 受保护框架
-- (CriticalEncounterWarnings 等) 的 OnHide → ResetWarning → ScaleTextToFit 在
-- tainted 执行上下文中对秘密宽度值做算术运算，产生
-- "attempt to perform arithmetic on a secret number value (execution tainted by 'EXBoss')" 报错。
-- pcall 无法拦截此类 WoW 安全系统上报的 taint 违规。
-- 暴雪警告框有自己的生命周期，EXBoss 无需主动清除。
-- 如需恢复：将下方整块取消注释，并同步恢复两处 ClearEncounterWarningsUI() 调用。
--
-- local function ClearEncounterWarningsUI()
--     local frames = {
--         _G.CriticalEncounterWarnings,
--         _G.MediumEncounterWarnings,
--         _G.MinorEncounterWarnings,
--     }
--     for i = 1, #frames do
--         local frame = frames[i]
--         if type(frame) == "table" then
--             if type(frame.ClearWarning) == "function" then
--                 pcall(frame.ClearWarning, frame)
--             elseif type(frame.HideWarning) == "function" then
--                 pcall(frame.HideWarning, frame)
--             end
--         end
--     end
--     local tooltip = _G.GameTooltip
--     if tooltip and type(tooltip.Hide) == "function" then
--         pcall(tooltip.Hide, tooltip)
--     end
-- end

local function ResolveEncounterID(encounterID)
    local n = tonumber(encounterID)
    if n then
        return n
    end
    return encounterID
end

local function ResolveBossDef(encounterID)
    local bosses = ExBoss.Timeline and ExBoss.Timeline._bosses
    if type(bosses) ~= "table" then
        return nil, ResolveEncounterID(encounterID)
    end
    local id = ResolveEncounterID(encounterID)
    local def = bosses[id]
    if not def and type(id) == "number" then
        def = bosses[tostring(id)]
    end
    return def, id
end

local _encounterEventRowsCache = {}

local function GetEncounterEventRows(encounterID)
    local id = tonumber(encounterID)
    if not id then return nil end
    local cached = _encounterEventRowsCache[id]
    if cached ~= nil then
        return cached or nil
    end

    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) ~= "table" or type(data.maps) ~= "table" then
        _encounterEventRowsCache[id] = false
        return nil
    end

    for _, map in pairs(data.maps) do
        if type(map) == "table" and type(map.bosses) == "table" then
            for _, boss in pairs(map.bosses) do
                if type(boss) == "table" and tonumber(boss.encounterID) == id and type(boss.events) == "table" then
                    _encounterEventRowsCache[id] = boss.events
                    return boss.events
                end
            end
        end
    end

    _encounterEventRowsCache[id] = false
    return nil
end

-- 跨战斗持久缓存：key 为 eventID（全局唯一）。value.pendingName == true 表示
-- 技能名解析时 C_Spell 本地数据尚未就绪，允许后续被 RetryRuntimeSkillSpellName 覆盖更新。
local _runtimeSkillFromEventCache = {}
local _runtimeSkillSpellNamePending = {}
local RUNTIME_SKILL_SPELLNAME_MAX_RETRY = 3
local RUNTIME_SKILL_SPELLNAME_RETRY_DELAY = 1

local function IsSpellDataReadyForRuntimeSkill(spellIdentifier)
    if not spellIdentifier then return true end
    if C_Spell and type(C_Spell.IsSpellDataCached) == "function" then
        local ok, cached = pcall(C_Spell.IsSpellDataCached, spellIdentifier)
        if ok then return cached and true or false end
    end
    return true
end

local function RetryRuntimeSkillSpellName(eventID, spellIdentifier, attempt)
    local cached = _runtimeSkillFromEventCache[eventID]
    if type(cached) ~= "table" or cached.pendingName ~= true then
        _runtimeSkillSpellNamePending[spellIdentifier] = nil
        return
    end
    if IsSpellDataReadyForRuntimeSkill(spellIdentifier) and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, apiName = pcall(C_Spell.GetSpellName, spellIdentifier)
        if ok and type(apiName) == "string" and apiName ~= "" then
            cached.displayName = LocalizeDynamicText(apiName)
            cached.voiceLabel = apiName
            cached.pendingName = nil
            _runtimeSkillSpellNamePending[spellIdentifier] = nil
            return
        end
    end
    if attempt >= RUNTIME_SKILL_SPELLNAME_MAX_RETRY then
        _runtimeSkillSpellNamePending[spellIdentifier] = nil
        return
    end
    if C_Spell and type(C_Spell.RequestLoadSpellData) == "function" then
        pcall(C_Spell.RequestLoadSpellData, spellIdentifier)
    end
    C_Timer.After(RUNTIME_SKILL_SPELLNAME_RETRY_DELAY, function()
        RetryRuntimeSkillSpellName(eventID, spellIdentifier, attempt + 1)
    end)
end

local function BuildRuntimeSkillFromEvent(eventID, event)
    if type(event) ~= "table" then return nil end
    local eid = tonumber(eventID)
    if eid then
        local cached = _runtimeSkillFromEventCache[eid]
        if cached ~= nil then
            return cached
        end
    end

    local evenSpellID = tonumber(event.evenSpellID)
    local spellID = tonumber(event.spellID) or evenSpellID
    local name = nil
    local spellIdentifier = evenSpellID or spellID
    local pendingName = false
    if spellIdentifier and C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, apiName = pcall(C_Spell.GetSpellName, spellIdentifier)
        if ok and type(apiName) == "string" and apiName ~= "" then
            name = apiName
        elseif eid and not _runtimeSkillSpellNamePending[spellIdentifier] then
            pendingName = true
        end
    end
    local rawFallbackName = name
    if not rawFallbackName then
        rawFallbackName = event.eventName or event.name
    end
    if type(rawFallbackName) ~= "string" or rawFallbackName == "" then
        rawFallbackName = spellID and ("技能 " .. tostring(spellID)) or ("事件 " .. tostring(eventID))
    end
    local rawName = tostring(name or rawFallbackName or "")
    local displayName = LocalizeDynamicText(name or rawFallbackName)
    local skill = {
        eventID = tonumber(event.eventID) or eid,
        spellID = spellID,
        evenSpellID = evenSpellID,
        spellIdentifier = evenSpellID or spellID,
        iconFileID = ResolveSpellIconFileID(evenSpellID or spellID, spellID, event.iconFileID),
        displayName = displayName,
        source = "duration_map",
        preAlert = 5,
        castDuration = 1.5,
        barPriority = 2,
        showBunBar = true,
        showTimerBar = true,
        screenAlert = false,
        preAlertText = "{name}",
        screenText = nil,
        voiceLabel = rawName,
        pendingName = pendingName or nil,
    }

    if eid then
        _runtimeSkillFromEventCache[eid] = skill
        if pendingName and spellIdentifier then
            _runtimeSkillSpellNamePending[spellIdentifier] = true
            if C_Spell and type(C_Spell.RequestLoadSpellData) == "function" then
                pcall(C_Spell.RequestLoadSpellData, spellIdentifier)
            end
            C_Timer.After(RUNTIME_SKILL_SPELLNAME_RETRY_DELAY, function()
                RetryRuntimeSkillSpellName(eid, spellIdentifier, 1)
            end)
        end
    end
    return skill
end

local function NormalizeMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "fixed" or m == "blizzard" or m == "auto" then
        return m
    end
    return "auto"
end

local function NormalizeFixedDriver(driver)
    local v = tostring(driver or ""):lower()
    if v == FIXED_DRIVER_AI then
        return FIXED_DRIVER_AI
    end
    return FIXED_DRIVER_TIME
end

local function NormalizeEncounterTrigger(trigger)
    local t = tostring(trigger or ""):upper()
    if t == TRIGGER_TIME or t == TRIGGER_AI or t == TRIGGER_BLZ then
        return t
    end
    return nil
end

local function GetEncounterTriggerPreset(encounterID)
    local id = tonumber(encounterID) or encounterID

    if _G.EXBossData and type(_G.EXBossData.GetEncounterTrigger) == "function" then
        local ok, trigger = pcall(_G.EXBossData.GetEncounterTrigger, id)
        if ok then
            local normalized = NormalizeEncounterTrigger(trigger)
            if normalized then
                return normalized
            end
        end
    end

    local all = _G.EXBOSS_ENCOUNTER_TRIGGERS
    if type(all) ~= "table" then
        return nil
    end
    local row = all[id]
    if row == nil then
        row = all[tostring(id)]
    end
    if type(row) == "table" then
        return NormalizeEncounterTrigger(row.trigger)
    end
    return NormalizeEncounterTrigger(row)
end

-- GetEncounterTriggerRow / GetEncounterAIStateMachine / EncounterAIStateMachineHasRules /
-- BuildEncounterEventActions / BuildEncounterFixedAISyncCycleLimits /
-- GetDurationRulesForEncounter / HasDurationRulesForEncounter 已迁移到
-- ExBossEngine/FixedAIResolver.lua，此处改用 FixedAIResolver.xxx(...) 调用。

local function GetFixedDriverOverride(encounterID)
    local tdb = TimerDB()
    local byID = tdb.fixedDriverByEncounter
    local v = byID[encounterID]
    if v == nil then
        v = byID[tostring(encounterID)]
    end
    if v == nil or v == "" then
        v = tdb.fixedDriverDefault or FIXED_DRIVER_TIME
    end
    return NormalizeFixedDriver(v)
end

local function ModeUsesFixed(mode)
    return mode == "fixed"
end

local function ModeUsesTimeline(mode)
    return mode == "blizzard"
end

local function CanUseFixedForEncounter(encounterID, bossDef)
    local id = tonumber(encounterID)
    if not id then return false end
    local set = _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS
    if type(set) ~= "table" or set[id] ~= true then
        return false
    end
    local def = bossDef
    if type(def) ~= "table" then
        def = ExBoss.Timeline and ExBoss.Timeline._bosses and ExBoss.Timeline._bosses[id]
    end
    return type(def) == "table" and type(def.skills) == "table" and #def.skills > 0
end

local function CanUseDurationMapForEncounter(encounterID)
    return FixedAIResolver.HasDurationRulesForEncounter(encounterID)
end

local function CanUseTimelineAPI()
    if not C_EncounterTimeline then return false end
    if C_EncounterTimeline.IsFeatureAvailable then
        local ok, available = pcall(C_EncounterTimeline.IsFeatureAvailable)
        if ok and not available then
            return false
        end
    end
    return true
end

local function NormalizeText(v)
    if type(v) ~= "string" then return "" end
    local t = v:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

local function ResolveOccurrenceKey(skill, source)
    if type(skill) ~= "table" then
        return nil
    end
    local prefix = tostring(source or "timer")
    local eventID = tonumber(skill.eventID)
    if eventID then
        return prefix .. ":event:" .. tostring(eventID)
    end
    local spellID = tonumber(skill.evenSpellID) or tonumber(skill.spellIdentifier) or tonumber(skill.spellID)
    if spellID then
        return prefix .. ":spell:" .. tostring(spellID)
    end
    local name = NormalizeText(skill.displayName or skill.name)
    if name ~= "" then
        return prefix .. ":name:" .. name
    end
    return nil
end

local function ResolveDefaultCentralText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    local text = NormalizeText(timer.screenText)
    if text ~= "" then
        return text
    end
    text = NormalizeText(timer.displayName)
    if text ~= "" then
        return text
    end
    return ""
end

local function NormalizeLeadSeconds(v, fallback)
    local n = tonumber(v)
    if not n then
        n = tonumber(fallback) or 0
    end
    if n < 0 then n = 0 end
    if n > 30 then n = 30 end
    return n
end

local function NormalizeTriggerOffsetMode(v)
    local s = tostring(v or ""):lower()
    if s == "early" then
        return "early"
    end
    return "delay"
end

local function NormalizeTriggerOffsetSeconds(v)
    local n = tonumber(v)
    if not n then
        n = 0
    end
    if n < 0 then n = 0 end
    if n > 30 then n = 30 end
    return n
end

local function ResolveVoiceEventConfig(timer)
    local row = TimelinePresentation and TimelinePresentation.GetRuntimeVoiceConfig and
        TimelinePresentation:GetRuntimeVoiceConfig(timer) or nil
    if type(row) == "table" and timer.castVoiceSource == "own" and type(row.triggers) == "table" then
        return {
            enabled = (row.enabled ~= false),
            triggers = row.triggers,
        }
    end
    return nil
end

local function ResolveEventColorFromVoiceEvents(timer)
    local cfg = TimelinePresentation and TimelinePresentation.GetRuntimeColorConfig and
        TimelinePresentation:GetRuntimeColorConfig(timer) or nil
    if type(cfg) == "table" then
        local CS = ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
        if CS and CS.ResolveEventColor then
            local r, g, b = CS.ResolveEventColor(cfg)
            if r ~= nil and g ~= nil and b ~= nil then
                return { r = r, g = g, b = b, a = 1 }
            end
        end
        if cfg.r ~= nil and cfg.g ~= nil and cfg.b ~= nil then
            return {
                r = tonumber(cfg.r) or 1,
                g = tonumber(cfg.g) or 0.82,
                b = tonumber(cfg.b) or 0.25,
                a = tonumber(cfg.a) or 1,
            }
        end
    end
    return nil
end

local function ResolveBlizzardEventColor(timer)
    if type(timer) ~= "table" or not (C_EncounterEvents and C_EncounterEvents.GetEventColor) then
        return nil
    end
    local eventID = tonumber(timer.timelineEventID) or tonumber(timer.eventID)
    if not eventID then
        return nil
    end
    local ok, colorObj = pcall(C_EncounterEvents.GetEventColor, eventID)
    if not ok then
        return nil
    end
    return ExtractColorRGB(colorObj)
end

local function SafeResolveEventColorFromVoiceEvents(timer)
    local ok, color = pcall(ResolveEventColorFromVoiceEvents, timer)
    if ok and type(color) == "table" then
        return color
    end
    if not ok and not _colorResolveErrorLogged then
        _colorResolveErrorLogged = true
    end
    return nil
end

local function ResolveSkillEventID(skill, encounterID)
    if type(skill) ~= "table" then return nil end
    local eventID = tonumber(skill.eventID)
    if eventID then
        return eventID
    end

    local spellID = tonumber(skill.evenSpellID) or tonumber(skill.spellIdentifier) or tonumber(skill.spellID)
    if not spellID then
        return nil
    end

    local rows = GetEncounterEventRows(encounterID)
    if type(rows) ~= "table" then
        return nil
    end

    for rawEventID, row in pairs(rows) do
        if type(row) == "table" then
            local rowEventID = tonumber(row.eventID) or tonumber(rawEventID)
            local rowSpellID = tonumber(row.evenSpellID) or tonumber(row.spellID)
            if rowEventID and rowSpellID and rowSpellID == spellID then
                return rowEventID
            end
        end
    end

    return nil
end

local function ResetFixedVoiceTriggerState(timer, trigger)
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] = false
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"] = "delay"
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"] = 0
    timer["fixedVoiceTrigger" .. tostring(trigger) .. "Fired"] = false
end

local function ResolveTimerVoiceLabel(timer)
    if type(timer) ~= "table" then
        return ""
    end
    return NormalizeText(timer.voiceLabel)
end

local function ApplyFixedVoiceTriggerConfig(timer)
    ResetFixedVoiceTriggerState(timer, 1)
    ResetFixedVoiceTriggerState(timer, 2)

    if type(timer) ~= "table" then return end
    if timer.castVoiceSource ~= nil and timer.castVoiceSource ~= "own" then
        return
    end

    local cfg = ResolveVoiceEventConfig(timer)
    if type(cfg) ~= "table" then
        if ResolveTimerVoiceLabel(timer) ~= "" then
            timer.fixedVoiceTrigger1Enabled = true
        end
        return
    end
    if cfg.enabled == false then
        return
    end

    local triggers = cfg.triggers
    if type(triggers) ~= "table" then
        if ResolveTimerVoiceLabel(timer) ~= "" then
            timer.fixedVoiceTrigger1Enabled = true
        end
        return
    end

    local hasExplicitFixedVoice = false
    for trigger = 1, 2 do
        local triggerCfg = triggers[trigger]
        local allowTrigger = not (trigger == 2 and timer.source ~= "trash" and timer.countdownPlayName ~= true)
        if allowTrigger and type(triggerCfg) == "table" and triggerCfg.enabled == true then
            hasExplicitFixedVoice = true
            timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] = true
            timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"] = NormalizeTriggerOffsetMode(triggerCfg
                .fixedOffsetMode)
            timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"] = NormalizeTriggerOffsetSeconds(triggerCfg
                .fixedOffsetSeconds)
        end
    end

    if not hasExplicitFixedVoice and ResolveTimerVoiceLabel(timer) ~= "" then
        timer.fixedVoiceTrigger1Enabled = true
    end
end

local function GetFixedVoiceTriggerBaseTime(timer, trigger)
    if type(timer) ~= "table" then return nil end
    trigger = tonumber(trigger)
    if trigger == 1 then
        return tonumber(timer.castTime)
    end
    if trigger == 2 then
        if timer.preAlertEnabled == false then
            return nil
        end
        return tonumber(timer.preAlertTime)
    end
    return nil
end

local function GetFixedVoiceTriggerFireTime(timer, trigger)
    local baseTime = GetFixedVoiceTriggerBaseTime(timer, trigger)
    if not baseTime then
        return nil
    end

    if tonumber(trigger) == 2 and type(timer) == "table" and timer.countdownPlayName == true then
        return baseTime - 1
    end

    local mode = NormalizeTriggerOffsetMode(timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"])
    local offset = NormalizeTriggerOffsetSeconds(timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"])
    if mode == "early" then
        return baseTime - offset
    end
    return baseTime + offset
end

local function HasPendingFixedVoiceTriggers(timer)
    if type(timer) ~= "table" then return false end
    for trigger = 1, 2 do
        if timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] == true
            and timer["fixedVoiceTrigger" .. tostring(trigger) .. "Fired"] ~= true
            and GetFixedVoiceTriggerFireTime(timer, trigger) ~= nil then
            return true
        end
    end
    return false
end

local function HasAnyFixedVoiceTriggerEnabled(timer)
    if type(timer) ~= "table" then
        return false
    end
    return timer.fixedVoiceTrigger1Enabled == true or timer.fixedVoiceTrigger2Enabled == true
end

local function TryFireFixedVoiceTriggers(timer, now)
    if type(timer) ~= "table" then return end
    if timer.source == "trash"
        and not (type(timer.trashRuntime) == "table" and tonumber(timer.trashRuntime.identityLockedNPCID)) then
        return
    end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        return
    end

    for trigger = 1, 2 do
        local allowTrigger = not (timer.source == "fixed_ai"
            and trigger == 1
            and timer.fixedAICompletingFromFinished ~= true)
        if allowTrigger then
            local enabled = (timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] == true)
            local firedKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Fired"
            if enabled and timer[firedKey] ~= true then
                local fireAt = GetFixedVoiceTriggerFireTime(timer, trigger)
                if fireAt and now >= fireAt then
                    if timer.source == "trash" then

                    end
                    timer[firedKey] = true
                    local ok, err = Engine:TryPlayForTimer(timer, trigger)

                    if timer.source == "trash" then

                    end
                end
            end
        end
    end
end

local function ScheduleFixedVoiceTriggerPlayback(timer, trigger, delay)
    if type(timer) ~= "table" then
        return false
    end
    local wait = tonumber(delay)
    if not wait or wait <= 0 then
        return false
    end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        return false
    end

    local firedKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Fired"
    local scheduledKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Scheduled"
    if timer[scheduledKey] == true then
        return true
    end

    timer[scheduledKey] = true
    local snapshot = DeepCopy(timer)
    snapshot[firedKey] = true
    C_Timer.After(wait, function()
        timer[scheduledKey] = nil
        if timer[firedKey] == true then
            return
        end
        if snapshot.source == "trash"
            and not (type(snapshot.trashRuntime) == "table" and tonumber(snapshot.trashRuntime.identityLockedNPCID)) then
            return
        end
        timer[firedKey] = true
        local ok, err = Engine:TryPlayForTimer(snapshot, trigger)
    end)
    return true
end

local function EnsureFixedVoiceAtCast(timer)
    if type(timer) ~= "table" then
        return
    end
    if timer.source == "trash"
        and not (type(timer.trashRuntime) == "table" and tonumber(timer.trashRuntime.identityLockedNPCID)) then
        return
    end
    if timer.castVoiceSource ~= nil and timer.castVoiceSource ~= "own" then
        return
    end
    if timer.fixedVoiceCastFallbackTried == true then
        return
    end
    timer.fixedVoiceCastFallbackTried = true

    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayForTimer) then
        return
    end

    if not HasAnyFixedVoiceTriggerEnabled(timer) then
        local label = ResolveTimerVoiceLabel(timer)
        if label == "" then
            return
        end
    end

    if timer.fixedVoiceTrigger1Enabled == true and timer.fixedVoiceTrigger1Fired ~= true then
        local now = GetTime()
        local fireAt = GetFixedVoiceTriggerFireTime(timer, 1)
        if fireAt and fireAt > now then
            local delay = fireAt - now
            if ScheduleFixedVoiceTriggerPlayback(timer, 1, delay) then
                return
            end
        end
    end

    if timer.fixedVoiceTrigger1Fired == true then
        return
    end

    local ok, err = Engine:TryPlayForTimer(timer, 1)
end

local IsFixedAICastStartFinishMode

local function ReleaseFixedAIVoiceAtCastTime(timer, now)
    if type(timer) ~= "table" then
        return
    end
    if timer.source ~= "fixed_ai" then
        return
    end
    if not IsFixedAICastStartFinishMode(timer) then
        return
    end
    if timer.fixedAIVoiceReleased == true then
        return
    end
    timer.fixedAIVoiceReleased = true
    timer.fixedAIVoicePendingByFinish = nil

    timer.fixedAICompletingFromFinished = true
    TryFireFixedVoiceTriggers(timer, tonumber(now) or GetTime())
    if timer.fixedVoiceTrigger1Fired == true then
        timer.fixedVoiceCastFallbackTried = true
    end
    EnsureFixedVoiceAtCast(timer)
    timer.fixedAICompletingFromFinished = false
end

function Scheduler:_ApplySkillOverride(timer)
    if type(timer) ~= "table" then return true end
    timer.disabled = false
    local runtimeMode = (timer.timelineManaged or timer.source == "blizzard") and "blizzard" or "fixed"
    local presentation = TimelinePresentation and TimelinePresentation.Resolve and
        TimelinePresentation:Resolve(timer, runtimeMode) or nil
    if type(presentation) ~= "table" then
        timer.disabled = true
        return false
    end
    local mode = tostring(presentation.mode or runtimeMode)
    timer._mode = mode
    timer.usePerEventEnabled = (presentation.usePerEventEnabled == true)
    timer.useEventColor = (presentation.useEventColor == true)
    timer.useCentralText = (presentation.useCentralText == true)
    timer.usePreAlertText = (presentation.usePreAlertText == true)
    timer.useTimerBarRename = (presentation.useTimerBarRename == true)
    timer.useRingProgress = (presentation.useRingProgress == true)
    timer.useOccurrenceCount = (presentation.useOccurrenceCount == true)
    timer.occurrenceDisplayMode = tostring(presentation.occurrenceDisplayMode or "inline")
    timer.useBlizzardHintCountdown = (presentation.useBlizzardHintCountdown == true)
    timer.useBlizzardHintCentral = (presentation.useBlizzardHintCentral == true)
    timer.blizzardHintCountdownLead = tonumber(presentation.blizzardHintCountdownLead) or VIRTUAL_HINT_REMAINING_SECS
    timer.blizzardHintCentralLead = tonumber(presentation.blizzardHintCentralLead) or 2
    timer.blizzardHintCentralDuration = tonumber(presentation.blizzardHintCentralDuration) or 2
    timer.eventColorSource = tostring(presentation.eventColorSource or "own")
    timer.countdownSource = tostring(presentation.countdownSource or "own")
    timer.centralSource = tostring(presentation.centralSource or "none")
    timer.castVoiceSource = tostring(presentation.castVoiceSource or "own")
    timer.preAlertVoiceSource = tostring(presentation.preAlertVoiceSource or "own")
    timer.countdownMode = tostring(presentation.countdownMode or "none")
    timer.centralMode = tostring(presentation.centralMode or "none")
    timer.voiceLabel = NormalizeText(presentation.voiceLabel)
    if timer.voiceLabel == "" then
        timer.voiceLabel = nil
    end
    timer.iconFlags = tonumber(presentation.iconFlags) or 0
    timer.ringEnabled = (presentation.ringEnabled == true)
    timer.castProgressBarEnabled = (presentation.castProgressBarEnabled == true)
    timer.castProgressBarRenameEnabled = (presentation.castProgressBarRenameEnabled == true)
    timer.castProgressBarRenameText = NormalizeText(presentation.castProgressBarRenameText)
    timer.ringCastCheckEnabled = (presentation.ringCastCheckEnabled == true)
    timer.ringWindowBefore = tonumber(presentation.ringWindowBefore) or 1
    timer.ringWindowAfter = tonumber(presentation.ringWindowAfter) or 2
    timer.castObserveLead = tonumber(presentation.castObserveLead) or nil
    timer.castObserveOrdinal = tonumber(presentation.castObserveOrdinal) or nil
    timer.castObserveExpectedKind = NormalizeText(presentation.castObserveExpectedKind)
    local observeUnitFilter = TimelinePresentation and TimelinePresentation.GetRuntimeCastObserveUnitFilter and
        TimelinePresentation:GetRuntimeCastObserveUnitFilter(timer) or nil
    if type(observeUnitFilter) == "table" then
        timer.castObserveUnitFilter = DeepCopy(observeUnitFilter)
    elseif type(observeUnitFilter) == "string" then
        local normalizedFilter = NormalizeText(observeUnitFilter)
        timer.castObserveUnitFilter = normalizedFilter ~= "" and normalizedFilter or nil
    else
        timer.castObserveUnitFilter = nil
    end
    if timer.castObserveUnitFilter == nil then
        timer.castObserveUnitFilter = GetSpecialBossObserveUnitFilter(
            tonumber(timer.encounterID) or tonumber(self._encounterID),
            timer.eventID or timer.timelineEventID
        )
    end
    timer.ringCastDuration = tonumber(presentation.ringCastDuration) or nil
    timer.ringChannelDuration = tonumber(presentation.ringChannelDuration) or nil
    timer.countdownVoiceEnabled = (presentation.countdownVoiceEnabled == true)
    timer.countdownPlayName = (presentation.countdownPlayName == true)

    timer.preAlertEnabled = false
    timer.preAlertTime = nil
    timer.preAlertText = nil
    timer.preAlertFired = true
    timer.screenAlert = false
    if timer.timelineManaged then
        timer.timelinePreAlertLead = 0
    end

    timer.centralEnabled = false
    timer.centralLead = 0
    timer.centralFired = true
    timer.screenText = nil
    timer.timerBarName = nil

    -- 固定时间轴：事件颜色覆盖不依赖 skill override 是否存在。
    -- 这样可避免“中央文本有色、但部分计时条未染色”的不一致。
    if timer.eventColorSource == "own" then
        local eventColor = SafeResolveEventColorFromVoiceEvents(timer)
        if type(eventColor) == "table" then
            local resolved = {
                r = tonumber(eventColor.r) or 1,
                g = tonumber(eventColor.g) or 1,
                b = tonumber(eventColor.b) or 1,
                a = tonumber(eventColor.a) or 1,
            }
            timer.flashTextColor = resolved
            -- 条体与中央文本保持同色，避免依赖 C_EncounterEvents 命中。
            timer.eventColor = {
                r = resolved.r,
                g = resolved.g,
                b = resolved.b,
                a = resolved.a,
            }
        else
            timer.flashTextColor = nil
        end
    else
        timer.flashTextColor = nil
        local blizzardColor = ResolveBlizzardEventColor(timer)
        if type(blizzardColor) == "table" then
            timer.eventColor = blizzardColor
        end
    end

    if presentation.eventEnabled == false then
        timer.disabled = true
        return false
    end

    timer.showBunBar = (presentation.showBunBar ~= false)
    timer.showTimerBar = (presentation.showTimerBar ~= false)

    if presentation.countdownMode == "own" then
        timer.preAlertEnabled = true
        timer.screenAlert = true
        timer.preAlertText = presentation.preAlertText
        local lead = math.min(30, math.max(0, tonumber(presentation.preAlertLead) or 0))
        if lead > 0 then
            timer.preAlertTime = (timer.castTime or GetTime()) - lead
            timer.preAlertFired = false
            if timer.timelineManaged then
                timer.timelinePreAlertLead = lead
            end
        end
    end

    if presentation.centralMode == "own" then
        timer.centralEnabled = true
        timer.centralLead = NormalizeLeadSeconds(presentation.centralLead, 0)
        timer.centralFired = false
        timer.screenText = presentation.centralText
    end

    if presentation.timerBarRenameEnabled == true then
        local rename = NormalizeText(presentation.timerBarRenameText)
        if rename ~= "" then
            timer.timerBarName = rename
        end
    end

    local timerTextCfg = presentation.timerTextColor
    timer.timerTextColor = nil
    if type(timerTextCfg) == "table" then
        local r = tonumber(timerTextCfg.r)
        local g = tonumber(timerTextCfg.g)
        local b = tonumber(timerTextCfg.b)
        local a = tonumber(timerTextCfg.a) or 1
        if r and g and b then
            timer.timerTextColor = { r = r, g = g, b = b, a = a }
        end
    end

    local trace = ExBoss and ExBoss.ColorTrace
    local flash = trace and type(trace.Describe) == "function" and trace:Describe(timer.flashTextColor) or "?"
    local text = trace and type(trace.Describe) == "function" and trace:Describe(timer.timerTextColor) or "?"
    TraceColor("Scheduler.Final", timer, timer.eventColor,
        "source=" .. tostring(timer.eventColorSource) .. " flash=" .. flash .. " timerText=" .. text)

    ApplyFixedVoiceTriggerConfig(timer)

    return true
end

function Scheduler:RefreshActiveEventConfig(eventID)
    local eid = tonumber(eventID)
    if not eid or type(self._active) ~= "table" then
        return 0
    end

    local refreshed = 0
    for _, timer in pairs(self._active) do
        if type(timer) == "table" and tonumber(timer.eventID) == nil and type(timer.skillDef) == "table" then
            timer.eventID = ResolveSkillEventID(timer.skillDef, self._encounterID)
        end
        if type(timer) == "table"
            and timer.timelineManaged ~= true
            and tonumber(timer.eventID) == eid then
            self:_ApplyTimerDisplayName(timer)
            if self:_ApplySkillOverride(timer) then
                refreshed = refreshed + 1
                if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshTimer then
                    ExBoss.UI.TimerBar:RefreshTimer(timer)
                end
                if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshTimer then
                    ExBoss.UI.BunBar:RefreshTimer(timer)
                end
            end
        end
    end

    return refreshed
end

function Scheduler:_GetModeOverride(encounterID)
    local tdb = TimerDB()
    local byID = tdb.byEncounter
    local v = byID[encounterID]
    if v == nil then
        v = byID[tostring(encounterID)]
    end
    if v == nil or v == "" then
        v = tdb.default or "auto"
    end
    return NormalizeMode(v)
end

function Scheduler:GetMode(encounterID)
    local bossDef, resolvedID = ResolveBossDef(encounterID)
    if IsFixedTimeTestOverride(resolvedID)
        and type(bossDef) == "table"
        and type(bossDef.skills) == "table"
        and #bossDef.skills > 0 then
        return "fixed"
    end
    local canFixedTime = CanUseFixedForEncounter(resolvedID, bossDef)
    local canDurationMap = CanUseDurationMapForEncounter(resolvedID)
    local canFixed = canFixedTime or canDurationMap
    local triggerPreset = GetEncounterTriggerPreset(resolvedID)
    local override = self:_GetModeOverride(resolvedID)

    if not bossDef and not canDurationMap then
        return "blizzard"
    end

    if override ~= "auto" then
        if override == "fixed" then
            if not canFixed then
                return "blizzard"
            end
            return "fixed"
        end
        if override == "blizzard" and not CanUseTimelineAPI() and canFixed then
            return "fixed"
        end
        return "blizzard"
    end

    if triggerPreset == TRIGGER_BLZ then
        return "blizzard"
    end
    if triggerPreset == TRIGGER_TIME then
        if canFixedTime then
            return "fixed"
        end
        if canDurationMap then
            return "fixed"
        end
        return "blizzard"
    end
    if triggerPreset == TRIGGER_AI then
        if canDurationMap then
            return "fixed"
        end
        if canFixedTime then
            return "fixed"
        end
        return "blizzard"
    end

    if canFixed then
        return "fixed"
    end
    return "blizzard"
end

-- ── 进本预热缓存 ──────────────────────────────────────────────
-- 玩家进入副本时，把该副本下所有 boss 的静态配置（触发预设/事件动作/duration
-- 规则/AI状态机/duration_map技能名解析）提前算好存入各自的模块级缓存，避免每次
-- 进战斗都对同一批静态数据重复计算。见 Scheduler重构计划.md §7。

function Scheduler:PrewarmEncounterConfigs(instanceID)
    local id = tonumber(instanceID)
    if not id then return 0 end

    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) ~= "table" or type(data.maps) ~= "table" then
        return 0
    end

    local mapRow = data.maps[id]
    if type(mapRow) ~= "table" then
        for _, row in pairs(data.maps) do
            if type(row) == "table" and tonumber(row.mapID) == id then
                mapRow = row
                break
            end
        end
    end
    if type(mapRow) ~= "table" or type(mapRow.bosses) ~= "table" then
        return 0
    end

    local warmed = 0
    for _, boss in pairs(mapRow.bosses) do
        if type(boss) == "table" and tonumber(boss.encounterID) then
            local encounterID = tonumber(boss.encounterID)
            FixedAIResolver.BuildEncounterEventActions(encounterID)
            FixedAIResolver.BuildEncounterFixedAISyncCycleLimits(encounterID)
            FixedAIResolver.GetEncounterAIStateMachine(encounterID)
            FixedAIResolver.GetDurationRulesForEncounter(encounterID)
            local eventRows = GetEncounterEventRows(encounterID)
            if type(eventRows) == "table" then
                for eventID, event in pairs(eventRows) do
                    BuildRuntimeSkillFromEvent(eventID, event)
                end
            end
            warmed = warmed + 1
        end
    end
    return warmed
end

-- ── 生命周期 ────────────────────────────────────────────────

function Scheduler:StartBoss(encounterID)
    if not IsBossSceneEnabledForCurrentInstance() and not IsTimelineTestMode() then
        self:EndBoss()
        return false
    end
    self:EndBoss()

    local bossDef, resolvedID = ResolveBossDef(encounterID)
    if not bossDef then
        local count = 0
        if ExBoss.Timeline and ExBoss.Timeline._bosses then
            for _ in pairs(ExBoss.Timeline._bosses) do
                count = count + 1
            end
        end
        --             .. " type=" .. tostring(type(encounterID))
        --             .. " bosses=" .. tostring(count))
        -- 无本地固定轴定义时，仍允许暴雪原生轴工作。
        bossDef = { axisType = "blizzard", skills = {} }
        resolvedID = ResolveEncounterID(encounterID)
    end

    self._encounterID = resolvedID
    self._mode = self:GetMode(resolvedID)
    self._running = true
    self._blizzardHintSessionEnabled = true
    self._sessionToken = (tonumber(self._sessionToken) or 0) + 1
    TimelineAddedBuffer._acceptedTimelineEventIDs = {}
    TimelineAddedBuffer._timelineAddedPending = {}
    TimelineAddedBuffer._timelineCountdownSpecByEventID = {}
    FixedAIResolver._eventActionsByEventID = FixedAIResolver.BuildEncounterEventActions(resolvedID)
    FixedAIResolver._fixedAISyncCycleLimits = FixedAIResolver.BuildEncounterFixedAISyncCycleLimits(resolvedID)
    FixedAIResolver._fixedAISyncCycleCounts = {}
    FixedAIResolver._fixedAIStateMachine = nil
    FixedAIResolver._fixedAIPhase = nil
    FixedAIResolver._fixedAIStrictDurationMatch = false
    self._bossCastObservePending = {}
    self._bossCastObservePendingByTimerID = {}
    self._bossCastObserveNextID = 1
    self._bossCastObserveRecentStarts = {}
    self._bossCastObserveNextStartID = 1
    self._bossObservedRuntimes = {}
    self._bossObservedRuntimeNextID = 1

    local now = GetTime()
    if ModeUsesFixed(self._mode) then
        self:_SetupFixedDriver(resolvedID, bossDef)
        if self._fixedDriver == FIXED_DRIVER_TIME then
            for _, skill in ipairs(bossDef.skills or {}) do
                local src = tostring(skill.source or bossDef.axisType or "fixed"):lower()
                if src == "fixed" and skill.first then
                    self:_ExpandAndSchedule(skill, now)
                end
            end
        end
    else
        self._fixedDriver = FIXED_DRIVER_TIME
        FixedAIResolver._fixedAIDurationRules = nil
        FixedAIResolver._fixedAIStateMachine = nil
        FixedAIResolver._fixedAIPhase = nil
        FixedAIResolver._fixedAISkillByEventID = {}
        self._fixedAIEventToTimer = {}
        self._fixedAIPendingEvents = {}
        FixedAIResolver._fixedAICanceledResumeSnapshot = nil
        FixedAIResolver._fixedAISequenceCounters = {}
        FixedAIResolver._fixedAIPreEventLimitCounts = {}
        FixedAIResolver._fixedAISyncCycleLimits = {}
        FixedAIResolver._fixedAISyncCycleCounts = {}
    end

    if self._mode == "blizzard" then
        self._ignoreTimelineRecoveryUntil = now + 2.0
    else
        self._ignoreTimelineRecoveryUntil = 0
    end

    if ModeUsesTimeline(self._mode) and CanUseTimelineAPI() and self._ignoreTimelineRecoveryUntil <= now then
        self:_RecoverTimelineEvents()
    end

    self._frame:Show()
    return true
end

function Scheduler:HandleEncounterStart(encounterID, source)
    local now = GetTime and GetTime() or 0
    local resolvedID = ResolveEncounterID(encounterID)
    if self._running and self._encounterID == resolvedID and (now - (tonumber(self._lastEncounterStartAt) or 0)) <= 1.0 then
        return
    end
    if self._lastEncounterStartID == resolvedID and (now - (tonumber(self._lastEncounterStartAt) or 0)) <= 1.0 then
        return
    end
    self._lastEncounterStartAt = now
    self._lastEncounterStartID = resolvedID
    self._suppressBlizzardTimeline = false
    -- ClearEncounterWarningsUI() -- [DISABLED] 见函数定义处注释
    self:StartBoss(encounterID)
end

function Scheduler:EndBoss()
    self:_CancelFixedAI176InjectTimers()
    if ExBoss.UI.BunBar and ExBoss.UI.BunBar.ReleaseAll then
        ExBoss.UI.BunBar:ReleaseAll()
    end
    if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.ReleaseAll then
        ExBoss.UI.TimerBar:ReleaseAll()
    end
    if ExBoss.UI.Countdown and ExBoss.UI.Countdown.Stop then
        ExBoss.UI.Countdown:Stop()
    end
    if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.Stop then
        ExBoss.UI.FlashTextMedium:Stop()
    end
    if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.Hide then
        ExBoss.UI.CastProgressBar:Hide()
    end
    if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.Hide then
        ExBoss.UI.RingProgress:Hide()
    end
    self._active                                        = {}
    self._nextTimerID                                   = 1
    self._running                                       = false
    self._blizzardHintSessionEnabled                    = false
    self._encounterID                                   = nil
    self._mode                                          = "fixed"
    self._timelineEventToTimer                          = {}
    TimelineAddedBuffer._timelineCountdownSpecByEventID = {}
    self._fixedDriver                                   = FIXED_DRIVER_TIME
    FixedAIResolver._fixedAIDurationRules               = nil
    FixedAIResolver._fixedAIStateMachine                = nil
    FixedAIResolver._fixedAIPhase                       = nil
    FixedAIResolver._fixedAISkillByEventID              = {}
    self._fixedAIEventToTimer                           = {}
    self._fixedAIPendingEvents                          = {}
    FixedAIResolver._fixedAICanceledResumeSnapshot      = nil
    FixedAIResolver._fixedAISequenceCounters            = {}
    FixedAIResolver._fixedAIPreEventLimitCounts         = {}
    self._occurrenceCounts                              = {}
    self._fixedTimeOffset                               = 0
    self._fixedTimeEventToTimer                         = {}
    TimelineAddedBuffer._acceptedTimelineEventIDs       = {}
    TimelineAddedBuffer._timelineAddedPending           = {}
    FixedAIResolver._eventActionsByEventID              = {}
    FixedAIResolver._fixedAISyncCycleLimits             = {}
    FixedAIResolver._fixedAISyncCycleCounts             = {}
    self._bossCastObservePending                        = {}
    self._bossCastObservePendingByTimerID               = {}
    self._bossCastObserveNextID                         = 1
    self._bossCastObserveRecentStarts                   = {}
    self._bossCastObserveNextStartID                    = 1
    self._bossObservedRuntimes                          = {}
    self._bossObservedRuntimeNextID                     = 1
    self._sessionToken                                  = (tonumber(self._sessionToken) or 0) + 1
    self._ignoreTimelineRecoveryUntil                   = 0
    -- ClearEncounterWarningsUI() -- [DISABLED] 见函数定义处注释
    if self._frame then self._frame:Hide() end
end

function Scheduler:HandleEncounterEnd(source)
    local now = GetTime and GetTime() or 0
    if (now - (tonumber(self._lastEncounterEndAt) or 0)) <= 1.0 then
        return
    end
    self._lastEncounterEndAt = now
    self._suppressBlizzardTimeline = true
    self:EndBoss()
end

function Scheduler:StartBlizzardFallback()
    if self._suppressBlizzardTimeline == true then
        return false
    end
    local now = GetTime and GetTime() or 0
    if (now - (tonumber(self._lastEncounterEndAt) or 0)) <= 6.0 then
        return false
    end
    if not IsBossSceneEnabledForCurrentInstance() then
        self:EndBoss()
        return false
    end
    if self._running then
        return false
    end
    if not CanUseTimelineAPI() then
        return false
    end
    self._active                                        = {}
    self._nextTimerID                                   = 1
    self._encounterID                                   = nil
    self._mode                                          = "blizzard"
    self._running                                       = true
    self._blizzardHintSessionEnabled                    = false
    self._timelineEventToTimer                          = {}
    TimelineAddedBuffer._timelineCountdownSpecByEventID = {}
    self._fixedDriver                                   = FIXED_DRIVER_TIME
    FixedAIResolver._fixedAIDurationRules               = nil
    FixedAIResolver._fixedAIStateMachine                = nil
    FixedAIResolver._fixedAIPhase                       = nil
    FixedAIResolver._fixedAISkillByEventID              = {}
    self._fixedAIEventToTimer                           = {}
    self._fixedAIPendingEvents                          = {}
    FixedAIResolver._fixedAICanceledResumeSnapshot      = nil
    FixedAIResolver._fixedAISequenceCounters            = {}
    FixedAIResolver._fixedAIPreEventLimitCounts         = {}
    self._occurrenceCounts                              = {}
    self._fixedTimeOffset                               = 0
    self._fixedTimeEventToTimer                         = {}
    TimelineAddedBuffer._acceptedTimelineEventIDs       = {}
    TimelineAddedBuffer._timelineAddedPending           = {}
    FixedAIResolver._eventActionsByEventID              = {}
    FixedAIResolver._fixedAISyncCycleLimits             = {}
    FixedAIResolver._fixedAISyncCycleCounts             = {}
    self._bossObservedRuntimes                          = {}
    self._bossObservedRuntimeNextID                     = 1
    self._sessionToken                                  = (tonumber(self._sessionToken) or 0) + 1
    self._ignoreTimelineRecoveryUntil                   = 0
    if self._frame then
        self._frame:Show()
    end
    self:_RecoverTimelineEvents()
    return true
end

-- ── fixed 轴展开 ─────────────────────────────────────────────

function Scheduler:_SetupFixedDriver(encounterID, bossDef)
    self._fixedDriver = FIXED_DRIVER_TIME
    FixedAIResolver._fixedAIDurationRules = nil
    FixedAIResolver._fixedAIStateMachine = nil
    FixedAIResolver._fixedAIPhase = nil
    FixedAIResolver._fixedAISkillByEventID = {}
    self._fixedAIEventToTimer = {}
    self._fixedAIPendingEvents = {}
    FixedAIResolver._fixedAICanceledResumeSnapshot = nil
    FixedAIResolver._fixedAISequenceCounters = {}
    FixedAIResolver._fixedAIPreEventLimitCounts = {}
    FixedAIResolver._fixedAISyncCycleCounts = {}
    self._occurrenceCounts = {}
    self._fixedTimeOffset = 0
    self._fixedTimeEventToTimer = {}
    TimelineAddedBuffer._timelineAddedPending = {}

    local testFixedTime = IsFixedTimeTestOverride(encounterID)
        and type(bossDef) == "table"
        and type(bossDef.skills) == "table"
        and #bossDef.skills > 0
    local canFixedTime = CanUseFixedForEncounter(encounterID, bossDef) or testFixedTime
    local durationRules = FixedAIResolver.GetDurationRulesForEncounter(encounterID)
    local aiStateMachine = FixedAIResolver.GetEncounterAIStateMachine(encounterID)
    local hasDurationRules = (type(durationRules) == "table" and #durationRules > 0)
        or FixedAIResolver.EncounterAIStateMachineHasRules(aiStateMachine)
    local triggerPreset = GetEncounterTriggerPreset(encounterID)
    local requestedDriver = GetFixedDriverOverride(encounterID)
    if testFixedTime then
        requestedDriver = FIXED_DRIVER_TIME
    elseif triggerPreset == TRIGGER_AI then
        requestedDriver = FIXED_DRIVER_AI
    elseif triggerPreset == TRIGGER_TIME then
        requestedDriver = FIXED_DRIVER_TIME
    end

    local resolvedDriver = requestedDriver
    if resolvedDriver == FIXED_DRIVER_AI and not hasDurationRules then
        resolvedDriver = canFixedTime and FIXED_DRIVER_TIME or FIXED_DRIVER_TIME
    elseif resolvedDriver == FIXED_DRIVER_TIME and not canFixedTime and hasDurationRules then
        resolvedDriver = FIXED_DRIVER_AI
    elseif not canFixedTime and hasDurationRules then
        resolvedDriver = FIXED_DRIVER_AI
    elseif canFixedTime then
        resolvedDriver = FIXED_DRIVER_TIME
    end

    self._fixedDriver = resolvedDriver
    if resolvedDriver == FIXED_DRIVER_AI then
        FixedAIResolver._fixedAIStateMachine = aiStateMachine
        FixedAIResolver._fixedAIStrictDurationMatch = FixedAIResolver.IsEncounterStrictDurationMatch(encounterID)
        if type(aiStateMachine) == "table" then
            local initialPhase = NormalizeText(aiStateMachine.initialPhase)
            if initialPhase ~= "" and initialPhase:upper() ~= "NONE" then
                FixedAIResolver._fixedAIPhase = initialPhase
                local phaseRow = type(aiStateMachine.phases) == "table" and aiStateMachine.phases[initialPhase] or nil
                FixedAIResolver._fixedAIDurationRules = type(phaseRow) == "table" and phaseRow.rules or nil
                FixedAIResolver._eventActionsByEventID = FixedAIResolver.BuildEncounterEventActions(encounterID,
                    initialPhase)
            end
        else
            FixedAIResolver._fixedAIDurationRules = durationRules
        end
    end

    if type(bossDef) == "table" and type(bossDef.skills) == "table" then
        for _, skill in ipairs(bossDef.skills) do
            local eventID = tonumber(skill and skill.eventID)
            if eventID then
                FixedAIResolver._fixedAISkillByEventID[eventID] = skill
            end
        end
    end

    local eventRows = GetEncounterEventRows(encounterID)
    if type(eventRows) == "table" then
        for eventID, event in pairs(eventRows) do
            local eid = tonumber(eventID)
            if eid and not FixedAIResolver._fixedAISkillByEventID[eid] then
                local skill = BuildRuntimeSkillFromEvent(eid, event)
                if skill then
                    FixedAIResolver._fixedAISkillByEventID[eid] = skill
                end
            end
        end
    end
end

function Scheduler:_ProcessFixedAIPendingBatch(batch, syncMode)
    if type(batch) ~= "table" or #batch == 0 then return end
    if syncMode == true then
        FixedAIResolver._fixedAISequenceCounters = {}
        FixedAIResolver:_ResetAllFixedAIPreEventLimits()
        FixedAIResolver:_ResetFixedAISyncCycleLimits()
    end

    local canceledResumeSnapshotMap = FixedAIResolver:_BuildFixedAICanceledResumeSnapshotMap(batch, syncMode)
    local usedCanceledResumeSnapshot = false
    for _, queued in ipairs(batch) do
        local timelineEventID = SafeToNumber(queued.timelineEventID)
        local duration = SafeToNumber(queued.duration)
        local observedAt = SafeToNumber(queued.receivedAt) or GetTime()
        if timelineEventID and duration then
            local inferredEventID = canceledResumeSnapshotMap and canceledResumeSnapshotMap[queued] or nil
            if inferredEventID then
                usedCanceledResumeSnapshot = true
            end
            if not inferredEventID then
                inferredEventID = FixedAIResolver:_ResolveFixedAIEventIDForMode(duration, timelineEventID, syncMode)
            end
            if not inferredEventID and syncMode then
                inferredEventID = FixedAIResolver:_ResolveFixedAIEventID(duration)
            end

            if inferredEventID then
                local skill = FixedAIResolver._fixedAISkillByEventID[inferredEventID]
                local hasSkill = type(skill) == "table"
                local acceptedSync = hasSkill and FixedAIResolver:_AcceptFixedAISyncCycleLimit(inferredEventID) or false
                local acceptedPre = acceptedSync and FixedAIResolver:_AcceptFixedAIPreEventLimit(inferredEventID) or
                    false

                if hasSkill and acceptedSync and acceptedPre then
                    local oldTimerID = self._fixedAIEventToTimer[timelineEventID]
                    if oldTimerID then
                        local oldTimer = self._active[oldTimerID]

                        self:_RemoveActiveTimerByID(oldTimerID)
                        self._fixedAIEventToTimer[timelineEventID] = nil
                    end

                    local castTime = observedAt + math.max(0, duration)
                    local timerID = self:_AddTimer(skill, castTime, "fixed_ai")
                    if timerID then
                        local timer = self._active[timerID]
                        if timer then
                            timer.fixedAITimelineEventID = timelineEventID
                        end
                        self._fixedAIEventToTimer[timelineEventID] = timerID

                        TimerEventEmitter.PublishFixedAIEventScheduled(self, timer, inferredEventID, duration,
                            observedAt, castTime, syncMode)
                    else

                    end
                else

                end
            else

            end
        end
    end
    if usedCanceledResumeSnapshot then
        FixedAIResolver._fixedAICanceledResumeSnapshot = nil
    end
end

function Scheduler:_ApplyEncounterEventActions(timer)
    if type(timer) ~= "table" then
        return
    end
    local actions = FixedAIResolver._eventActionsByEventID
    if type(actions) ~= "table" then
        timer.clearActiveSnapshotAfter = nil
        return
    end
    local eventID = tonumber(timer.eventID) or tonumber(timer.timelineEventID)
    local row = eventID and actions[eventID] or nil
    timer.clearActiveSnapshotAfter = tonumber(row and row.clearActiveSnapshotAfter)
    if row and row.waitTimelineFinish ~= nil then
        timer.waitTimelineFinish = row.waitTimelineFinish == true
    end
    if row and row.timelineFinishTimeout ~= nil then
        timer.timelineFinishTimeout = tonumber(row.timelineFinishTimeout)
    end
    if row and row.finishMode ~= nil then
        timer.finishMode = tostring(row.finishMode or ""):lower()
    end
    timer.timerFinishIgnoreStateWindow = tonumber(row and row.timerFinishIgnoreStateWindow)
    timer.castStartUnit = type(row) == "table" and tostring(row.castStartUnit or ""):lower() or nil
    if timer.castStartUnit == "" then
        timer.castStartUnit = nil
    end
    timer.castStartWindow = tonumber(row and row.castStartWindow)
    timer.castStartEvent = type(row) == "table" and tostring(row.castStartEvent or ""):lower() or nil
    if timer.castStartEvent == "" then
        timer.castStartEvent = nil
    end
    if row and row.resumeFromCanceledSnapshot == true then
        timer.resumeFromCanceledSnapshot = true
        timer.resumeSnapshotTolerance = tonumber(row.resumeSnapshotTolerance)
        timer.resumeSnapshotWindow = tonumber(row.resumeSnapshotWindow)
        timer.canceledSnapshotEvents = row.canceledSnapshotEvents
    else
        timer.resumeFromCanceledSnapshot = nil
        timer.canceledSnapshotEvents = nil
    end
end

function Scheduler:_RemoveActiveTimerByID(timerID)
    local id = tonumber(timerID)
    if not id then
        return
    end
    local timer = self._active[id]
    if not timer then
        return
    end
    if timer.timelineEventID then
        self._timelineEventToTimer[timer.timelineEventID] = nil
    end
    if timer.fixedAITimelineEventID then
        self._fixedAIEventToTimer[timer.fixedAITimelineEventID] = nil
    end
    if timer.fixedTimeTimelineEventID then
        self._fixedTimeEventToTimer[timer.fixedTimeTimelineEventID] = nil
    end
    local countdownRuntime = ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown
    if countdownRuntime and type(countdownRuntime.Cancel) == "function" then
        countdownRuntime:Cancel("prealert:" .. tostring(id))
    end

    if timer.source == "trash" and type(timer.trashRuntime) == "table" and tonumber(timer.spellID) then
        local bySpell = type(timer.trashRuntime.localTimerIDsBySpellID) == "table" and
            timer.trashRuntime.localTimerIDsBySpellID or nil
        if bySpell then
            bySpell[tonumber(timer.spellID)] = nil
        end
    end
    self._active[id] = nil
end

function Scheduler:CancelTrashLocalTimer(runtime, spellID)
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID)
    if not sid then
        return
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    local timerID = bySpell and tonumber(bySpell[sid]) or nil
    if timerID then
        self:_RemoveActiveTimerByID(timerID)
    end
end

function Scheduler:CancelTrashLocalTimers(runtime)
    if type(runtime) ~= "table" then
        return
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    if type(bySpell) ~= "table" then
        return
    end
    local ids = {}
    for _, timerID in pairs(bySpell) do
        if tonumber(timerID) then
            ids[#ids + 1] = tonumber(timerID)
        end
    end
    for i = 1, #ids do
        self:_RemoveActiveTimerByID(ids[i])
    end
    wipe(bySpell)
end

function Scheduler:HandleTrashObservedCastSuccess(runtime, spellID)
    if type(runtime) ~= "table" then
        return
    end
    local sid = tonumber(spellID)
    if not sid then
        return
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    local timerID = bySpell and tonumber(bySpell[sid]) or nil
    local timer = timerID and self._active and self._active[timerID] or nil
    if type(timer) ~= "table" then
        return
    end
    timer.castFired = true
    if ExBoss.Timeline.Dispatcher then
        ExBoss.Timeline.Dispatcher:OnCast(timer)
    end
    self:_RemoveActiveTimerByID(timerID)
end

function Scheduler:GetTrashLocalTimer(runtime, spellID)
    if type(runtime) ~= "table" then
        return nil
    end
    if type(spellID) ~= "number" then
        return nil
    end
    local sid = math.floor(spellID)
    if not sid then
        return nil
    end
    local bySpell = type(runtime.localTimerIDsBySpellID) == "table" and runtime.localTimerIDsBySpellID or nil
    local timerID = bySpell and tonumber(bySpell[sid]) or nil
    return timerID and self._active and self._active[timerID] or nil
end

local function BuildTrashObservedCastStartTrigger(runtime, spellID)
    local store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
    if not (store and type(store.GetRuntimeSpellEntry) == "function") then
        return nil, "no store"
    end
    local mapID = tonumber(runtime and runtime.matchedMapID)
    local npcID = tonumber(runtime and runtime.matchedNPCID)
    local sid = tonumber(spellID)
    if not (mapID and npcID and sid) then
        return nil, "bad ids"
    end

    local cfg = store.GetRuntimeSpellEntry(mapID, npcID, sid)
    if type(cfg) ~= "table" then
        return nil, "no cfg"
    end
    if cfg.enabled ~= true then
        return nil, "cfg disabled"
    end
    if cfg.voice1Enabled ~= true then
        return nil, "trigger1 disabled"
    end

    return {
        enabled = true,
        sourceType = tostring(cfg.voice1Source or "pack"),
        label = tostring(cfg.voice1Label or ""),
        customLSM = tostring(cfg.voice1LSM or ""),
        customPath = tostring(cfg.voice1Path or ""),
        fixedOffsetMode = tostring(cfg.voice1OffsetMode or "delay"),
        fixedOffsetSeconds = tonumber(cfg.voice1OffsetSeconds) or 0,
    }, nil
end

local function BuildTrashObservedCastStartDisplayTimer(runtime, spellID)
    local data = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
    if not (data and type(data.GetTrashCDDataRoot) == "function") then
        return nil, "no data"
    end
    if not (TrashRuntimeConfig and type(TrashRuntimeConfig.BuildResolvedMeta) == "function") then
        return nil, "no runtime-config"
    end

    local mapID = tonumber(runtime and runtime.matchedMapID)
    local npcID = tonumber(runtime and runtime.matchedNPCID)
    local sid = tonumber(spellID)
    if not (mapID and npcID and sid) then
        return nil, "bad ids"
    end

    local root = data.GetTrashCDDataRoot()
    local mapRow = type(root) == "table" and type(root[mapID]) == "table" and root[mapID] or nil
    local mobData = mapRow and type(mapRow.mobs) == "table" and mapRow.mobs[npcID] or nil
    local spellData = mobData and type(mobData.spells) == "table" and mobData.spells[sid] or nil
    if type(mobData) ~= "table" or type(spellData) ~= "table" then
        return nil, "no spell-data"
    end

    local fallbackIcon = tonumber(spellData.iconFileID)
        or (type(data.GetSpellIconSafe) == "function" and tonumber(data.GetSpellIconSafe(sid)))
        or 136243
    local meta = TrashRuntimeConfig.BuildResolvedMeta(runtime, mobData, spellData, fallbackIcon)
    if type(meta) ~= "table" then
        return nil, "no meta"
    end

    local timer = {
        spellID = sid,
        spellIdentifier = sid,
        trashRuntime = runtime,
        trashNPCID = npcID,
        trashSpellData = spellData,
        baseDisplayName = tostring(meta.displayName or spellData.name or sid),
        displayName = tostring(meta.displayName or spellData.name or sid),
        iconFileID = tonumber(meta.iconFileID) or tonumber(spellData.iconFileID) or fallbackIcon,
    }
    ApplyTrashTimelineMeta(timer, meta)
    return timer, nil
end

local function NormalizeTrashCastStartVoiceCooldownMuteWindow(value)
    if value == nil or value == false then
        return nil
    end
    if value == true then
        return 0
    end
    if type(value) == "number" then
        if value <= 0 then
            return nil
        end
        return value
    end
    if type(value) ~= "string" then
        return nil
    end

    local text = value:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end

    local lowered = string.lower(text)
    if lowered == "true" or text == "是" then
        return 0
    end
    if lowered == "false" or text == "否" then
        return nil
    end

    local suffixSeconds = text:match("^([%d%.]+)%s*[sS]$")
    if suffixSeconds then
        local numeric = tonumber(suffixSeconds)
        return (numeric and numeric > 0) and numeric or nil
    end

    local chineseSeconds = text:match("^([%d%.]+)%s*秒$")
    if chineseSeconds then
        local numeric = tonumber(chineseSeconds)
        return (numeric and numeric > 0) and numeric or nil
    end

    local numeric = tonumber(text)
    if not numeric or numeric <= 0 then
        return nil
    end
    return numeric
end

local function ShouldSuppressTrashCastStartVoiceByCooldown(timer)
    if type(timer) ~= "table" then
        return false, nil, nil
    end
    local spellData = type(timer.trashSpellData) == "table" and timer.trashSpellData or nil
    local muteWindow = NormalizeTrashCastStartVoiceCooldownMuteWindow(
        spellData and spellData.muteCastStartVoiceDuringCooldown
    )
    if muteWindow == nil then
        return false, nil, nil
    end

    local now = GetTime()
    local remaining = math.max(0, tonumber(timer.castTime or now) - now)
    if remaining > muteWindow then
        return true, remaining, muteWindow
    end
    return false, remaining, muteWindow
end

local function IsTrashObservedSpellAllowedForCurrentRole(runtime, spellID)
    if not (TrashRuntimeConfig and type(TrashRuntimeConfig.IsRuntimeSpellAllowedForCurrentRole) == "function") then
        return true
    end
    return TrashRuntimeConfig.IsRuntimeSpellAllowedForCurrentRole(runtime, spellID) ~= false
end

-- 预判语音的诊断沿用 TrashCD Runtime Debug；不开 Debug 时完全无输出。
local function DebugPriorityPreviewVoice(runtime, stage, detail)
    local controller = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Runtime or nil
    if not (controller and type(controller.AppendExternalDebug) == "function") then
        return
    end
    if type(controller.IsDebug) == "function" and controller.IsDebug() ~= true then
        return
    end
    local seq = tonumber(type(runtime) == "table" and runtime.activeCastSeq or nil) or 0
    local key = "scheduler:" .. tostring(stage or "?") .. ":" .. tostring(seq)
    if type(runtime) == "table" and runtime._debugPriorityPreviewVoiceKey == key then
        return
    end
    if type(runtime) == "table" then
        runtime._debugPriorityPreviewVoiceKey = key
    end
    controller.AppendExternalDebug("TrashCD PreviewVoice", string.format(
        "%s seq=%s spell=%s preview=%s %s", tostring(stage or "?"), tostring(seq),
        tostring(type(runtime) == "table" and runtime.activeSpellID or "nil"),
        tostring(type(runtime) == "table" and runtime.priorityPreviewVoiceNPCID or "nil"),
        tostring(detail or "")), true)
end

function Scheduler:PlayTrashObservedCastStartVoice(runtime, spellID, options)
    if type(runtime) == "table" and runtime.activeSpellAmbiguous == true then
        DebugPriorityPreviewVoice(runtime, "deny-ambiguous", "spell=" .. tostring(spellID))
        return false
    end

    if type(runtime) ~= "table" then
        return false
    end
    if not IsTrashObservedSpellAllowedForCurrentRole(runtime, spellID) then
        return false
    end
    local priorityPreviewVoice = type(options) == "table" and options.priorityPreviewVoice == true
    local priorityPreviewNPCID = priorityPreviewVoice and tonumber(options.priorityPreviewNPCID) or nil
    if not tonumber(runtime.identityLockedNPCID) and not priorityPreviewNPCID then
        return false
    end
    runtime._trashCastStartVoiceKeys = runtime._trashCastStartVoiceKeys or {}
    local dedupeKey = tostring(math.floor(tonumber(spellID) or 0)) ..
        ":" .. string.format("%.3f", tonumber(runtime.activeCastStartAt) or 0)
    if runtime._trashCastStartVoiceKeys[dedupeKey] == true then
        return false
    end

    local timer = self:GetTrashLocalTimer(runtime, spellID)
    if type(timer) ~= "table" then
        -- 预判语音必须已有来自同一优先级候选的本地 CD 计时；不允许走
        -- fallback，否则没有充分的排程归因，也会绕开 CD 内静音判断。
        if priorityPreviewNPCID then
            DebugPriorityPreviewVoice(runtime, "deny-no-local-timer", "spell=" .. tostring(spellID))
            return false
        end
        local fallbackTimer, fallbackErr = BuildTrashObservedCastStartDisplayTimer(runtime, spellID)
        DispatchTrashObservedCastStartEvent(runtime, spellID, fallbackTimer)
        local progressShown = false
        if type(fallbackTimer) == "table" then
            progressShown = PlayTrashObservedCastStartRing(runtime, fallbackTimer, spellID) == true
        else

        end

        local bySpell = type(runtime) == "table" and type(runtime.localTimerIDsBySpellID) == "table" and
            runtime.localTimerIDsBySpellID or nil
        local sid = tonumber(spellID)
        local mappedTimerID = sid and bySpell and tonumber(bySpell[sid]) or nil
        local mappedTimer = mappedTimerID and self._active and self._active[mappedTimerID] or nil
        local keys = {}
        if type(bySpell) == "table" then
            for k in pairs(bySpell) do
                keys[#keys + 1] = tostring(k)
            end
            table.sort(keys)
        end

        local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
        if not (Engine and Engine.TryPlayStandaloneSound) then
            return false
        end
        local triggerCfg, triggerErr = BuildTrashObservedCastStartTrigger(runtime, spellID)
        if type(triggerCfg) ~= "table" then
            return false
        end

        local ok, err = Engine:TryPlayStandaloneSound(triggerCfg,
            "trash-cast:" .. tostring(runtime) .. ":" .. tostring(dedupeKey), {
                triggerIndex = 1,
                throttle = false,
            })

        if ok == true then
            runtime._trashCastStartVoiceKeys[dedupeKey] = true
            DispatchTrashCastStartVoiceTriggeredEvent(runtime, spellID, fallbackTimer)
        end
        return (ok == true), err
    end
    if priorityPreviewNPCID then
        if timer.source ~= "trash"
            or timer.trashRuntime ~= runtime
            or tonumber(timer.trashNPCID) ~= priorityPreviewNPCID
            or type(timer.trashSpellData) ~= "table"
            or timer.trashSpellData.allowPriorityPreviewCastStartVoice ~= true then
            DebugPriorityPreviewVoice(runtime, "deny-timer-mismatch", "spell=" .. tostring(spellID))
            return false
        end
    end
    DispatchTrashObservedCastStartEvent(runtime, spellID, timer)
    PlayTrashObservedCastStartRing(runtime, timer, spellID)

    local voicePlan = type(timer.voicePlan) == "table" and timer.voicePlan or nil
    local triggerCfg = voicePlan and type(voicePlan.triggers) == "table" and voicePlan.triggers[1] or nil
    if not (type(triggerCfg) == "table" and triggerCfg.enabled == true) then
        if priorityPreviewNPCID then
            DebugPriorityPreviewVoice(runtime, "deny-trigger", "spell=" .. tostring(spellID))
        end
        return false
    end
    local Engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if not (Engine and Engine.TryPlayStandaloneSound) then
        if priorityPreviewNPCID then
            DebugPriorityPreviewVoice(runtime, "deny-voice-engine", "spell=" .. tostring(spellID))
        end
        return false
    end

    local suppressByCooldown, cooldownRemaining, muteWindow = ShouldSuppressTrashCastStartVoiceByCooldown(timer)
    if suppressByCooldown == true then
        runtime._trashCastStartVoiceKeys[dedupeKey] = true
        timer.fixedVoiceTrigger1Fired = true
        timer.fixedVoiceTrigger1Enabled = false
        if priorityPreviewNPCID then
            DebugPriorityPreviewVoice(runtime, "deny-cooldown", "spell=" .. tostring(spellID)
                .. " remaining=" .. tostring(cooldownRemaining)
                .. " mute=" .. tostring(muteWindow))
        end

        return false
    end

    -- Trash trigger sources are per-skill (LSM/file/TTS/pack).  Do not use
    -- TryPlayForTimer here: it resolves the generic voice label and would
    -- fall back to the selected voice pack even when this trigger chose LSM.
    local ok, err = Engine:TryPlayStandaloneSound(triggerCfg,
        "trash-cast:" .. tostring(runtime) .. ":" .. tostring(dedupeKey), {
            triggerIndex = 1,
            throttle = false,
        })

    if ok == true then
        runtime._trashCastStartVoiceKeys[dedupeKey] = true
        timer.fixedVoiceTrigger1Fired = true
        timer.fixedVoiceTrigger1Enabled = false
        DispatchTrashCastStartVoiceTriggeredEvent(runtime, spellID, timer)
    end
    if priorityPreviewNPCID then
        DebugPriorityPreviewVoice(runtime, ok and "played" or "deny-engine-result",
            "spell=" .. tostring(spellID) .. " err=" .. tostring(err or "nil"))
    end
    return ok, err
end

function Scheduler:EnsureTrashLocalRuntime()
    if self._running ~= true then
        self._running = true
        self._mode = "fixed"
        self._elapsed = ONUPDATE_INTERVAL
    end
    if self._frame then
        self._frame:Show()
    end
end

local function IsTrashFixedCombatTimelineSpell(spellData)
    return type(spellData) == "table" and spellData.fixedCombatTimeline == true
end

local function GetTrashFixedCombatTimelineStep(spellData)
    local seq = type(spellData) == "table" and type(spellData.cd) == "table" and spellData.cd or nil
    local step = seq and tonumber(seq[1]) or nil
    if step and step > 0 then
        return step
    end
    return nil
end

local function ResetTrashTimerForNextFixedCombatTimeline(timer, nextAt, now)
    local delay = math.max(0.1, nextAt - now)
    timer.baseCastTime = nextAt
    timer.castTime = nextAt
    timer.duration = math.max(delay, 30)
    timer.trashIconStartTime = now
    timer.trashIconDuration = delay
    timer.timerBarDuration = TIMERBAR_LEAD_TIME
    timer.preAlertFired = false
    timer.hintCountdownFired = false
    timer.hintCentralFired = false
    timer.castFired = false
    timer.centralFired = false
    timer.trashReadyAt = nil
    timer.bunBarShown = false
    timer.timerBarShown = false
    timer.fiveSecBroadcastFired = false
    if timer.countdownMode == "own" and timer.preAlertEnabled == true then
        timer.preAlertTime = nextAt - SafeNum(timer.timelinePreAlertLead, DEFAULT_PREALERT_SECS)
    else
        timer.preAlertTime = nil
    end
    ApplyFixedVoiceTriggerConfig(timer)
    timer.fixedVoiceTrigger1Enabled = false
    timer.fixedVoiceTrigger1Fired = true
end

function Scheduler:_AdvanceTrashFixedCombatTimeline(timer, now)
    if type(timer) ~= "table" or timer.trashFixedCombatTimeline ~= true then
        return false
    end
    local spellData = timer.trashSpellData
    local step = GetTrashFixedCombatTimelineStep(spellData)
    if not step then
        return false
    end
    local spellID = tonumber(timer.spellID)
    local scheduledAt = tonumber(timer.castTime) or now
    local nextAt = scheduledAt + step
    while nextAt <= now + 0.20 do
        nextAt = nextAt + step
    end

    if ExBoss.Timeline.Dispatcher then
        ExBoss.Timeline.Dispatcher:OnCast(timer)
    end
    ResetTrashTimerForNextFixedCombatTimeline(timer, nextAt, now)

    local runtime = type(timer.trashRuntime) == "table" and timer.trashRuntime or nil
    if runtime and spellID then
        runtime.nextSpellStartAt = runtime.nextSpellStartAt or {}
        runtime.nextSpellAnchorAt = runtime.nextSpellAnchorAt or {}
        runtime.nextSpellStartAt[spellID] = nextAt
        runtime.nextSpellAnchorAt[spellID] = tonumber(runtime.defaultAnchorAt) or tonumber(runtime.engagedAt) or now
    end
    return true
end

function Scheduler:RegisterTrashLocalTimer(runtime, mobData, spellData, remaining, meta)
    if type(runtime) ~= "table" or type(mobData) ~= "table" or type(spellData) ~= "table" or type(meta) ~= "table" then
        return nil
    end
    if TrashRuntimeConfig then
        if type(TrashRuntimeConfig.IsDisabledInCurrentEncounter) == "function"
            and TrashRuntimeConfig.IsDisabledInCurrentEncounter() == true then
            return nil
        end
        if type(TrashRuntimeConfig.IsDisabledInBossEncounter) == "function"
            and TrashRuntimeConfig.IsDisabledInBossEncounter(self._encounterID) == true then
            return nil
        end
    end
    local delay = tonumber(remaining)
    local spellID = tonumber(spellData.spellID)
    if not delay or delay <= 0 or not spellID then
        return nil
    end

    self:EnsureTrashLocalRuntime()

    runtime.localTimerIDsBySpellID = runtime.localTimerIDsBySpellID or {}
    local now = GetTime()
    local timerID = tonumber(runtime.localTimerIDsBySpellID[spellID])
    local timer = timerID and self._active and self._active[timerID] or nil
    local isNewTimer = type(timer) ~= "table"

    if isNewTimer then
        timerID = self._nextTimerID
        self._nextTimerID = timerID + 1
        timer = {
            id = timerID,
            spellID = spellID,
            spellIdentifier = spellID,
            baseDisplayName = tostring(meta.displayName or spellData.name or spellID),
            displayName = tostring(meta.displayName or spellData.name or spellID),
            occurrenceCount = nil,
            baseCastTime = now + delay,
            castTime = now + delay,
            duration = math.max(delay, 30),
            trashIconDuration = delay,
            trashIconStartTime = now,
            timerBarDuration = TIMERBAR_LEAD_TIME,
            preAlertTime = nil,
            barPriority = 2,
            showBunBar = true,
            showTimerBar = true,
            showNameplate = false,
            nameplateSide = "right",
            headAlert = false,
            screenAlert = false,
            preAlertText = nil,
            screenText = nil,
            centralLead = 0,
            voiceLabel = nil,
            source = "trash",
            eventID = nil,
            eventColor = nil,
            preAlertFired = false,
            hintCountdownFired = false,
            hintCentralFired = false,
            castFired = false,
            bunBarShown = false,
            timerBarShown = false,
            fiveSecBroadcastFired = false,
            timelineManaged = false,
            timelineEventID = nil,
            timelinePreAlertLead = DEFAULT_PREALERT_SECS,
            centralFired = false,
            trashRuntime = runtime,
            trashNPCID = tonumber(mobData.npcID),
            trashSpellData = spellData,
            trashFixedCombatTimeline = IsTrashFixedCombatTimelineSpell(spellData),
        }
        self._active[timerID] = timer
        runtime.localTimerIDsBySpellID[spellID] = timerID
    end

    timer.spellID = spellID
    timer.spellIdentifier = spellID
    timer.iconFileID = tonumber(meta.iconFileID) or tonumber(spellData.iconFileID)
    timer.baseDisplayName = tostring(meta.displayName or spellData.name or spellID)
    timer.displayName = timer.baseDisplayName
    local newCastTime = now + delay
    local oldCastTime = tonumber(timer.castTime)
    local oldIconStartTime = tonumber(timer.trashIconStartTime)
    local resetIconCooldown = isNewTimer
        or oldIconStartTime == nil
        or timer.castFired == true
        or timer.trashReadyAt ~= nil
        or oldCastTime == nil
        or math.abs(newCastTime - oldCastTime) > 0.75

    timer.baseCastTime = newCastTime
    timer.castTime = newCastTime
    timer.duration = math.max(delay, 30)
    if resetIconCooldown then
        timer.trashIconStartTime = now
        timer.trashIconDuration = delay
    else
        timer.trashIconDuration = math.max(0.1, newCastTime - oldIconStartTime)
    end
    timer.timerBarDuration = TIMERBAR_LEAD_TIME
    timer.preAlertTime = nil
    timer.preAlertFired = false
    timer.hintCountdownFired = false
    timer.hintCentralFired = false
    timer.castFired = false
    timer.centralFired = false
    timer.trashReadyAt = nil
    timer.trashRuntime = runtime
    timer.trashNPCID = tonumber(mobData.npcID)
    timer.trashSpellData = spellData
    timer.trashFixedCombatTimeline = IsTrashFixedCombatTimelineSpell(spellData)

    ApplyTrashTimelineMeta(timer, meta)
    if timer.countdownMode == "own" and timer.preAlertEnabled == true then
        timer.preAlertTime = (now + delay) - SafeNum(timer.timelinePreAlertLead, DEFAULT_PREALERT_SECS)
    end
    ApplyFixedVoiceTriggerConfig(timer)
    -- 小怪“施法开始”语音必须由真实 UNIT_SPELLCAST_START / CHANNEL_START 触发；
    -- 本地 CD 计时到点只表示技能可用，不代表怪物已经开始施法。
    timer.fixedVoiceTrigger1Enabled = false
    timer.fixedVoiceTrigger1Fired = true

    return timerID
end

function Scheduler:GetTrashNameplateTimers(runtime, now)
    if type(runtime) ~= "table" then
        return {}
    end
    now = tonumber(now) or GetTime()
    local out = {}
    for _, timer in pairs(self._active or {}) do
        if type(timer) == "table"
            and timer.source == "trash"
            and timer.trashRuntime == runtime
            and timer.showNameplate == true
            and (timer.castFired ~= true or timer.trashReadyAt ~= nil) then
            out[#out + 1] = {
                spellID = tonumber(timer.spellID),
                iconFileID = tonumber(timer.iconFileID),
                displayName = tostring(timer.displayName or timer.baseDisplayName or ""),
                remaining = math.max(0, tonumber(timer.castTime or now) - now),
                duration = math.max(0, tonumber(timer.trashIconDuration) or tonumber(timer.duration) or 0),
                startTime = tonumber(timer.trashIconStartTime),
                ready = (timer.trashReadyAt ~= nil),
                side = (tostring(timer.nameplateSide or "right") == "left") and "left" or "right",
            }
        end
    end
    table.sort(out, function(a, b)
        local ar = tonumber(a and a.remaining) or 0
        local br = tonumber(b and b.remaining) or 0
        if ar == br then
            return (tonumber(a and a.spellID) or 0) < (tonumber(b and b.spellID) or 0)
        end
        return ar < br
    end)
    return out
end

local function ShouldIgnoreFixedAIStateChangeNearDeadline(timer, now)
    if type(timer) ~= "table" or timer.source ~= "fixed_ai" then
        return false
    end
    if tostring(timer.finishMode or ""):lower() ~= "timer" then
        return false
    end
    local window = tonumber(timer.timerFinishIgnoreStateWindow)
    if not window or window <= 0 then
        return false
    end
    now = tonumber(now) or GetTime()
    local castTime = SafeToNumber(timer.castTime)
    if not castTime then
        return false
    end
    return (castTime - now) <= window
end

local function ShouldPauseFixedAITimer(timer)
    if type(timer) ~= "table" or timer.source ~= "fixed_ai" then
        return false
    end
    return FIXED_AI_SYNC_ACCEPT_PAUSED_ENCOUNTERS[SafeToNumber(Scheduler._encounterID) or 0] == true
end

local function ShiftFixedAITimerForPause(timer, delta)
    if type(timer) ~= "table" then
        return
    end
    delta = tonumber(delta)
    if not delta or delta <= 0 then
        return
    end

    if timer.castTime then
        timer.castTime = tonumber(timer.castTime) + delta
    end
    if timer.preAlertTime then
        timer.preAlertTime = tonumber(timer.preAlertTime) + delta
    end
    if timer.fixedAICastStartListenAt then
        timer.fixedAICastStartListenAt = tonumber(timer.fixedAICastStartListenAt) + delta
    end
    if timer.fixedAICastStartDeadline then
        timer.fixedAICastStartDeadline = tonumber(timer.fixedAICastStartDeadline) + delta
    end
end

local function ApplyFixedAIPausedState(timer, now)
    if not ShouldPauseFixedAITimer(timer) or timer.castFired == true then
        return false
    end
    if timer.fixedAIPausedAt then
        timer.fixedAIPausedTick = tonumber(now) or GetTime()
        return true
    end
    timer.fixedAIPausedAt = tonumber(now) or GetTime()
    timer.fixedAIPausedTick = timer.fixedAIPausedAt
    timer.fixedAIPaused = true
    timer.fixedAIWasPaused = true
    return true
end

local function ResumeFixedAIPausedState(timer, now)
    if type(timer) ~= "table" or timer.fixedAIPausedAt == nil then
        return false
    end
    timer.fixedAIPausedAt = nil
    timer.fixedAIPausedTick = nil
    timer.fixedAIPaused = nil
    return true
end

local function ShouldKeepFixedAIAfterPauseRemoved(encounterID, timer)
    return type(timer) == "table"
        and timer.source == "fixed_ai"
        and FIXED_AI_KEEP_AFTER_PAUSE_REMOVED_ENCOUNTERS[SafeToNumber(encounterID) or 0] == true
        and (timer.fixedAIWasPaused == true or timer.fixedAIPaused == true)
end

local function DetachFixedAITimelineKeepLocal(scheduler, timer, timelineEventID, reason)
    if type(timer) ~= "table" then
        return false
    end
    ResumeFixedAIPausedState(timer, GetTime())
    timer.fixedAITimelineEventID = nil
    timer.fixedAIKeepAfterPauseRemoved = true
    if type(scheduler) == "table" and type(scheduler._fixedAIEventToTimer) == "table" then
        scheduler._fixedAIEventToTimer[timelineEventID] = nil
    end

    return true
end

IsFixedAICastStartFinishMode = function(timer)
    return type(timer) == "table"
        and timer.source == "fixed_ai"
        and tostring(timer.finishMode or ""):lower() == "cast_start"
end

local function GetFixedAICastStartListenLead(_timer)
    return 0.1
end

local function GetFixedAICastStartDeadlineOffset(_timer)
    return 2.0
end

local function TryEnterFixedAICastStartWait(timer, now)
    if not IsFixedAICastStartFinishMode(timer) or timer.castFired == true then
        return false
    end
    now = tonumber(now) or GetTime()
    local castTime = SafeToNumber(timer.castTime)
    if not castTime then
        return false
    end
    local listenLead = GetFixedAICastStartListenLead(timer)
    local deadlineOffset = GetFixedAICastStartDeadlineOffset(timer)
    local listenAt = castTime - listenLead
    local deadline = castTime + deadlineOffset
    if now < listenAt or now > deadline then
        return false
    end
    timer.fixedAIWaitingCastStart = true
    timer.fixedAICastStartListenAt = listenAt
    timer.fixedAICastStartDeadline = deadline
    return true
end

local function UnitAllowedForFixedAICastStart(timer, unit)
    local allowedUnit = tostring(type(timer) == "table" and timer.castStartUnit or "")
    if allowedUnit == "" or allowedUnit == "boss" then
        return IsBossCastObserveUnit(unit)
    end
    return allowedUnit == tostring(NormalizeUnitToken(unit) or "")
end

function Scheduler:RebindTrashRuntime(oldRuntime, newRuntime)
    if type(oldRuntime) ~= "table" or type(newRuntime) ~= "table" or oldRuntime == newRuntime then
        return 0
    end
    local rebound = 0
    for _, timer in pairs(self._active or {}) do
        if type(timer) == "table" and timer.source == "trash" and timer.trashRuntime == oldRuntime then
            timer.trashRuntime = newRuntime
            rebound = rebound + 1
        end
    end
    return rebound
end

function Scheduler:_ScheduleClearActiveSnapshot(triggerTimer)
    local delay = tonumber(triggerTimer and triggerTimer.clearActiveSnapshotAfter)
    if not delay or delay <= 0 then
        return
    end

    local triggerID = tonumber(triggerTimer and triggerTimer.id)
    FixedAIResolver:_ResetFixedAIPreEventLimits(tonumber(triggerTimer and triggerTimer.eventID) or
        tonumber(triggerTimer and triggerTimer.timelineEventID))
    local snapshot = {}
    for timerID, timer in pairs(self._active) do
        if timerID ~= triggerID and type(timer) == "table" and timer.castFired ~= true then
            snapshot[#snapshot + 1] = timerID
        end
    end
    if #snapshot == 0 then
        return
    end

    local sessionToken = tonumber(self._sessionToken) or 0
    local encounterID = self._encounterID
    C_Timer.After(delay, function()
        if sessionToken ~= (tonumber(Scheduler._sessionToken) or 0) then
            return
        end
        if Scheduler._running ~= true or Scheduler._encounterID ~= encounterID then
            return
        end
        for i = 1, #snapshot do
            Scheduler:_RemoveActiveTimerByID(snapshot[i])
        end
    end)
end

function Scheduler:_FlushFixedAIPendingEvents(now)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then return end
    local pending = self._fixedAIPendingEvents
    if type(pending) ~= "table" or #pending == 0 then return end
    now = tonumber(now) or GetTime()

    while #pending > 0 do
        local first = pending[1]
        local firstAt = tonumber(first and first.receivedAt)
        if not firstAt then
            table.remove(pending, 1)
        elseif (now - firstAt) < FIXED_AI_SYNC_WINDOW then
            break
        else
            local batch = {}
            local windowEnd = firstAt + FIXED_AI_SYNC_WINDOW
            while #pending > 0 do
                local row = pending[1]
                local rowAt = tonumber(row and row.receivedAt)
                if not rowAt or rowAt <= windowEnd then
                    table.insert(batch, row)
                    table.remove(pending, 1)
                else
                    break
                end
            end
            local filtered = TimelineAddedBuffer:_FilterTimelineAddedBatch(batch, now, self._mode, self._fixedDriver,
                self._encounterID)
            if filtered and #filtered > 0 then
                FixedAIResolver:_UpdateFixedAIPhaseFromBatch(filtered, self._encounterID)
                local syncMode = FixedAIResolver:_CountFixedAISyncRuleMatches(filtered) >= 2
                    or FixedAIResolver:_HasFixedAIPausedSyncAccepted(filtered)
                    or FixedAIResolver:_HasFixedAICanceledResumeSnapshotReady(filtered)
                self:_ProcessFixedAIPendingBatch(filtered, syncMode)
            end
        end
    end
end

function Scheduler:_OnFixedTimeTimelineEventAdded(eventInfo)
    if not FIXED_TIME_OFFSET_CALIBRATION_ENABLED then return end
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_TIME) then return end
    if type(eventInfo) ~= "table" then return end

    local timelineEventID = SafeToNumber(eventInfo.id)
    local duration = SafeToNumber(eventInfo.duration)
    if not timelineEventID or not duration then return end
    if not IsEncounterTimelineSource(eventInfo.source) or not IsTimelineDurationAllowed(duration) then return end

    local oldTimerID = self._fixedTimeEventToTimer[timelineEventID]
    if oldTimerID then
        self._active[oldTimerID] = nil
        self._fixedTimeEventToTimer[timelineEventID] = nil
    end

    local observedCastAt = GetTime() + math.max(0, duration)
    local timerID = self:_FindBestFixedTimeTimer(observedCastAt)
    if not timerID then
        return
    end

    local timer = self._active[timerID]
    if not timer then
        return
    end

    local baseCast = tonumber(timer.baseCastTime) or tonumber(timer.castTime)
    if baseCast then
        self:_ApplyFixedTimeOffset(observedCastAt - baseCast)
        timer = self._active[timerID] or timer
    end

    timer.fixedTimelineMatched = true
    timer.fixedTimeTimelineEventID = timelineEventID
    self._fixedTimeEventToTimer[timelineEventID] = timerID
end

function Scheduler:_TryHoldFixedAIForTimelineFinish(timer, now)
    if type(timer) ~= "table"
        or timer.source ~= "fixed_ai"
        or timer.finishMode == "timer"
        or timer.castFired == true then
        return false
    end

    local timelineEventID = SafeToNumber(timer.fixedAITimelineEventID)
    if not timelineEventID then
        return false
    end

    local state = TimelineAddedBuffer:_GetTimelineState(timelineEventID)
    if state ~= STATE_ACTIVE and state ~= STATE_PAUSED then
        return false
    end

    now = tonumber(now) or GetTime()
    local startedAt = tonumber(timer.fixedAITimelineFinishWaitStartedAt)
    if not startedAt then
        startedAt = now
        timer.fixedAITimelineFinishWaitStartedAt = startedAt
    end

    local timeout = tonumber(timer.timelineFinishTimeout)
    if not timeout and timer.waitTimelineFinish == true then
        timeout = FIXED_AI_TIMELINE_FINISH_TIMEOUT
    end
    if timeout and timeout > 0 and (now - startedAt) >= timeout then
        timer.fixedAIWaitingTimelineFinish = false
        timer.fixedAITimelineFinishTimedOut = true

        return false
    end

    if timer.fixedAIWaitingTimelineFinish ~= true then

    end
    timer.fixedAIWaitingTimelineFinish = true
    if timer.fixedVoiceTrigger1Fired == true or timer.fixedVoiceTrigger2Fired == true then
        timer.fixedVoiceCastFallbackTried = true
    end
    timer.castTime = now
    return true
end

function Scheduler:_OnFixedAITimelineEventAdded(eventInfo)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then return end
    if type(eventInfo) ~= "table" then return end

    local timelineEventID = SafeToNumber(eventInfo.id)
    local duration = SafeToNumber(eventInfo.duration)
    if not timelineEventID or not duration then return end
    if not IsEncounterTimelineSource(eventInfo.source) or not IsTimelineDurationAllowed(duration) then return end

    table.insert(self._fixedAIPendingEvents, {
        timelineEventID = timelineEventID,
        duration = duration,
        receivedAt = GetTime(),
    })
end

function Scheduler:_RemoveFixedAIPendingTimelineEvent(timelineEventID)
    local id = SafeToNumber(timelineEventID)
    local pending = self._fixedAIPendingEvents
    if not id or type(pending) ~= "table" then
        return false
    end
    local removed = false
    for i = #pending, 1, -1 do
        local row = pending[i]
        if SafeToNumber(row and row.timelineEventID) == id then
            table.remove(pending, i)
            removed = true
        end
    end
    return removed
end

function Scheduler:_CancelFixedAI176InjectTimers()
    local pendingTimers = self._fixedAI176InjectTimers
    if type(pendingTimers) ~= "table" then
        self._fixedAI176InjectTimers = {}
        return
    end
    for _, pendingTimer in pairs(pendingTimers) do
        if type(pendingTimer) == "table" and type(pendingTimer.Cancel) == "function" then
            pendingTimer:Cancel()
        end
    end
    self._fixedAI176InjectTimers = {}
end

-- 176 施放后等 1 秒，注入一个 44 秒条目。3199 的 normalize 会将
-- 44 秒归一为 45 秒，因此该条目会通过真正的 sequenceGroup 解析并在完成点后
-- 约 45 秒施放。不能改用 ScheduleFixedAIVirtualEvent，否则不会推进 sequenceGroup。
function Scheduler:_Inject3199Loop44After176Finished(timer, timelineEventID)
    if SafeToNumber(self._encounterID) ~= 3199
        or type(timer) ~= "table"
        or SafeToNumber(timer.eventID) ~= 176
        or timer.fixedAIInjected44AfterFinish == true then
        return false
    end

    timer.fixedAIInjected44AfterFinish = true
    local sessionToken = SafeToNumber(self._sessionToken)
    local injectKey = tostring(timer.id)
    self._fixedAI176InjectTimers = type(self._fixedAI176InjectTimers) == "table"
        and self._fixedAI176InjectTimers or {}
    local pendingTimer = nil
    pendingTimer = C_Timer.NewTimer(1, function()
        if self._fixedAI176InjectTimers[injectKey] == pendingTimer then
            self._fixedAI176InjectTimers[injectKey] = nil
        end
        if SafeToNumber(self._sessionToken) ~= sessionToken
            or not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI)
            or SafeToNumber(self._encounterID) ~= 3199 then
            return
        end

        local syntheticTimelineEventID = SafeToNumber(self._fixedAIVirtualTimelineEventID) or -1
        self._fixedAIVirtualTimelineEventID = syntheticTimelineEventID - 1
        self:_ProcessFixedAIPendingBatch({
            {
                timelineEventID = syntheticTimelineEventID,
                duration = 44,
                receivedAt = GetTime(),
            },
        }, false)
    end)
    self._fixedAI176InjectTimers[injectKey] = pendingTimer
    return true
end

function Scheduler:_TriggerFixedAITimerCast(timer, now, _reason, suppressVoice)
    if type(timer) ~= "table" or timer.castFired == true then
        return false
    end
    now = tonumber(now) or GetTime()

    timer.fixedAIPausedAt = nil
    timer.fixedAIPausedTick = nil
    timer.fixedAIPaused = nil
    timer.fixedAIWaitingTimelineFinish = false
    timer.fixedAIWaitingCastStart = false
    timer.fixedAICastStartListenAt = nil
    timer.fixedAICastStartDeadline = nil
    timer.fixedAICastStartNextPollAt = nil
    timer.castTime = now
    timer.fixedAICompletingFromFinished = true

    if suppressVoice ~= true then
        TryFireFixedVoiceTriggers(timer, now)
        if timer.fixedVoiceTrigger1Fired == true then
            timer.fixedVoiceCastFallbackTried = true
        end
    end
    timer.castFired = true
    self:_Inject3199Loop44After176Finished(timer, timer.fixedAITimelineEventID)
    if ExBoss.Timeline.Dispatcher then
        ExBoss.Timeline.Dispatcher:OnCast(timer)
    end
    TimerEventEmitter.PublishFixedAIEventFinished(self, timer)
    if timer.clearActiveSnapshotAfter then
        self:_ScheduleClearActiveSnapshot(timer)
    end
    if suppressVoice ~= true then
        EnsureFixedVoiceAtCast(timer)
    end
    timer.fixedAICompletingFromFinished = false
    return true
end

function Scheduler:_CompleteFixedAITimerFromFinished(timerID)
    local id = SafeToNumber(timerID)
    local timer = id and self._active and self._active[id] or nil
    if type(timer) ~= "table" then
        return
    end

    local now = GetTime()
    local castTime = SafeToNumber(timer.castTime) or now
    local remaining = castTime - now
    if timer.castFired ~= true and (timer.source == "fixed_ai"
            or timer.waitTimelineFinish == true
            or timer.fixedAIWaitingTimelineFinish == true
            or remaining <= FIXED_AI_FINISHED_TRIGGER_GRACE) then
        self:_TriggerFixedAITimerCast(timer, now, "state-finished-complete")
    end

    self:_RemoveActiveTimerByID(id)
end

function Scheduler:_FindFixedAICastStartTimer(unit, _eventKind, now)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return nil
    end
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    now = tonumber(now) or GetTime()
    local bestTimer = nil
    local bestDelta = math.huge
    for _, timer in pairs(self._active or {}) do
        if TryEnterFixedAICastStartWait(timer, now) then
            if UnitAllowedForFixedAICastStart(timer, unit) then
                local deadline = tonumber(timer.fixedAICastStartDeadline) or now
                if now <= deadline then
                    local delta = math.abs((tonumber(timer.castTime) or now) - now)
                    if delta < bestDelta then
                        bestDelta = delta
                        bestTimer = timer
                    end
                end
            end
        end
    end
    return bestTimer
end

function Scheduler:_OnBossSpellcastBoundary(unit, eventKind)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return
    end
    local now = GetTime()
    local timer = self:_FindFixedAICastStartTimer(unit, eventKind, now)
    if not timer then
        return
    end
    local suppressVoice = (timer.source == "fixed_ai" and IsFixedAICastStartFinishMode(timer))
    if suppressVoice then
        timer.fixedAIVoicePendingByFinish = true
    end
    if self:_TriggerFixedAITimerCast(timer, now, "boss-" .. tostring(eventKind) .. "-start", suppressVoice) then
        if suppressVoice ~= true then
            self:_RemoveActiveTimerByID(timer.id)
        end
    end
end

function Scheduler:_OnFixedTimeTimelineEventRemoved(eventID)
    if not FIXED_TIME_OFFSET_CALIBRATION_ENABLED then return end
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_TIME) then return end
    local timelineEventID = SafeToNumber(eventID)
    if not timelineEventID then return end

    local timerID = self._fixedTimeEventToTimer[timelineEventID]
    if not timerID then return end

    self._fixedTimeEventToTimer[timelineEventID] = nil
    self._active[timerID] = nil
end

function Scheduler:_OnFixedAITimelineEventRemoved(eventID)
    local timelineEventID = SafeToNumber(eventID)
    if not timelineEventID then return end

    local timerID = self._fixedAIEventToTimer[timelineEventID]
    local timer = timerID and self._active[timerID] or nil
    if ShouldIgnoreFixedAIStateChangeNearDeadline(timer, GetTime()) then
        return
    end
    if type(timer) == "table" and timer.finishMode == "timer" then
        return
    end
    if type(timer) == "table" and timer.fixedAIVoicePendingByFinish == true and timer.fixedAIVoiceReleased ~= true then
        ReleaseFixedAIVoiceAtCastTime(timer, GetTime())
    end
    if TryEnterFixedAICastStartWait(timer, GetTime()) then
        ReleaseFixedAIVoiceAtCastTime(timer, GetTime())
        return
    end
    local syncEnabled = (type(timer) == "table" and timer.source == "fixed_ai")
        or (type(timer) == "table" and timer.waitTimelineFinish == true)
    if not syncEnabled then
        return
    end

    local pendingRemoved = self:_RemoveFixedAIPendingTimelineEvent(timelineEventID)

    if not timerID then
        return
    end

    if ShouldKeepFixedAIAfterPauseRemoved(self._encounterID, timer) then
        DetachFixedAITimelineKeepLocal(self, timer, timelineEventID, "timeline removed keep-after-pause")
        return
    end

    self:_RemoveActiveTimerByID(timerID)
end

function Scheduler:_OnFixedAITimelineEventStateChanged(eventID)
    local timelineEventID = SafeToNumber(eventID)
    if not timelineEventID then return end

    local timerID = self._fixedAIEventToTimer[timelineEventID]
    local timer = timerID and self._active[timerID] or nil
    local state = TimelineAddedBuffer:_GetTimelineState(timelineEventID)
    local now = GetTime()
    if state == STATE_CANCELED then
        local remainBefore = timer and ((SafeToNumber(timer.castTime) or now) - now) or nil
        FixedAIResolver:_CaptureFixedAICanceledResumeSnapshot(timer, timelineEventID, remainBefore, now)
    end
    local syncEnabled = (type(timer) == "table" and timer.source == "fixed_ai")
    if not syncEnabled then
        return
    end

    if ShouldIgnoreFixedAIStateChangeNearDeadline(timer, now) then
        return
    end
    if state == STATE_PAUSED then
        ApplyFixedAIPausedState(timer, now)

        return
    end
    if state == STATE_ACTIVE then
        ResumeFixedAIPausedState(timer, now)

        return
    end
    if type(timer) == "table" and timer.fixedAIVoicePendingByFinish == true and timer.fixedAIVoiceReleased ~= true then
        ReleaseFixedAIVoiceAtCastTime(timer, now)
    end
    if TryEnterFixedAICastStartWait(timer, now) then
        ReleaseFixedAIVoiceAtCastTime(timer, now)
        return
    end

    local pendingRemoved = self:_RemoveFixedAIPendingTimelineEvent(timelineEventID)

    if not timerID then
        return
    end

    if state == STATE_CANCELED and ShouldKeepFixedAIAfterPauseRemoved(self._encounterID, timer) then
        DetachFixedAITimelineKeepLocal(self, timer, timelineEventID, "timeline canceled keep-after-pause")
        return
    end

    if state == STATE_FINISHED then
        self:_CompleteFixedAITimerFromFinished(timerID)
        return
    end

    if timer then
        timer.fixedAIPausedAt = nil
        timer.fixedAIPausedTick = nil
        timer.fixedAIPaused = nil
    end
    self:_RemoveActiveTimerByID(timerID)
end

function Scheduler:ScheduleFixedAIVirtualEvent(eventID, duration, key, options)
    if not (self._running and self._mode == "fixed" and self._fixedDriver == FIXED_DRIVER_AI) then
        return nil
    end

    local eid = SafeToNumber(eventID)
    local dur = SafeToNumber(duration)
    if not eid or not dur then
        return nil
    end

    if type(options) == "table" then
        local expectedEncounterID = SafeToNumber(options.encounterID)
        if expectedEncounterID and expectedEncounterID ~= SafeToNumber(self._encounterID) then
            return nil
        end
    end

    local skill = type(FixedAIResolver._fixedAISkillByEventID) == "table" and FixedAIResolver._fixedAISkillByEventID
        [eid] or nil
    if type(skill) ~= "table" then
        local rows = GetEncounterEventRows(self._encounterID)
        local row = type(rows) == "table" and rows[eid] or nil
        skill = BuildRuntimeSkillFromEvent(eid, row)
        if type(skill) == "table" then
            FixedAIResolver._fixedAISkillByEventID = type(FixedAIResolver._fixedAISkillByEventID) == "table" and
                FixedAIResolver._fixedAISkillByEventID or {}
            FixedAIResolver._fixedAISkillByEventID[eid] = skill
        end
    end
    if type(skill) ~= "table" then
        return nil
    end

    local observedAt = type(options) == "table" and SafeToNumber(options.observedAt) or nil
    observedAt = observedAt or GetTime()
    local castTime = observedAt + math.max(0, dur)
    local timerID = self:_AddTimer(skill, castTime, "fixed_ai")
    local timer = timerID and self._active[timerID] or nil
    if not timer then
        return nil
    end

    timer.fixedAIVirtual = true
    timer.fixedAIVirtualKey = tostring(key or eid)
    timer.fixedAIVirtualEventID = eid

    TimerEventEmitter.PublishFixedAIEventScheduled(self, timer, eid, dur, observedAt, castTime, false)
    return timerID
end

function Scheduler:CancelFixedAIVirtualEvents(key)
    local expectedKey = key ~= nil and tostring(key) or nil
    local removed = 0
    if type(self._active) ~= "table" then
        return removed
    end

    for timerID, timer in pairs(self._active) do
        if type(timer) == "table"
            and timer.fixedAIVirtual == true
            and (not expectedKey or timer.fixedAIVirtualKey == expectedKey) then
            self:_RemoveActiveTimerByID(timerID)
            removed = removed + 1
        end
    end

    return removed
end

function Scheduler:_ExpandAndSchedule(skill, battleStart)
    local first = tonumber(skill and skill.first)
    if not first then
        return nil
    end
    local castTime = battleStart + first
    local limit = battleStart + MAX_ENCOUNTER_DURATION
    if castTime > limit then
        return nil
    end

    local timerID = self:_AddTimer(skill, castTime, "fixed")
    local timer = timerID and self._active[timerID] or nil
    if timer then
        timer.fixedBattleStart = battleStart
        timer.fixedIntervalIndex = 1
    end
    return timerID
end

function Scheduler:_ScheduleNextFixedOccurrence(timer)
    if type(timer) ~= "table" or timer.source ~= "fixed" then
        return nil
    end

    local skill = timer.skillDef
    if type(skill) ~= "table" or skill.interval == nil then
        return nil
    end

    local interval = skill.interval
    local index = tonumber(timer.fixedIntervalIndex) or 1
    local delay = type(interval) == "table" and tonumber(interval[index]) or tonumber(interval)
    if not delay or delay <= 0 then
        return nil
    end

    local currentCast = tonumber(timer.castTime)
    local battleStart = tonumber(timer.fixedBattleStart)
    if not currentCast or not battleStart then
        return nil
    end

    local nextCast = currentCast + delay
    if nextCast > (battleStart + MAX_ENCOUNTER_DURATION) then
        return nil
    end

    local nextTimerID = self:_AddTimer(skill, nextCast, "fixed")
    local nextTimer = nextTimerID and self._active[nextTimerID] or nil
    if nextTimer then
        nextTimer.fixedBattleStart = battleStart
        nextTimer.fixedIntervalIndex = type(interval) == "table" and ((index % #interval) + 1) or 1
    end
    return nextTimerID
end

function Scheduler:_NextOccurrenceCount(skill, source)
    local key = ResolveOccurrenceKey(skill, source)
    if not key then
        return nil
    end
    self._occurrenceCounts = type(self._occurrenceCounts) == "table" and self._occurrenceCounts or {}
    local nextCount = (tonumber(self._occurrenceCounts[key]) or 0) + 1
    self._occurrenceCounts[key] = nextCount
    return nextCount
end

function Scheduler:_ApplyTimerDisplayName(timer)
    if type(timer) ~= "table" then
        return
    end
    local baseName = timer.baseDisplayName or timer.displayName
    timer.baseDisplayName = baseName
    timer.displayName = baseName
end

function Scheduler:_AddTimer(skill, castTime, source)
    local id = self._nextTimerID
    self._nextTimerID = id + 1
    local occurrenceCount = self:_NextOccurrenceCount(skill, source)

    local timer = {
        id                     = id,
        spellID                = skill.spellID,
        spellIdentifier        = skill.evenSpellID or skill.spellIdentifier or skill.spellID,
        iconFileID             = ResolveSpellIconFileID(skill.evenSpellID or skill.spellIdentifier or skill.spellID,
            skill.spellID, skill.iconFileID),
        baseDisplayName        = skill.displayName,
        displayName            = skill.displayName,
        occurrenceCount        = occurrenceCount,
        baseCastTime           = castTime,
        castTime               = castTime,
        duration               = skill.preAlert and (skill.preAlert + (skill.castDuration or 0)) or 30,
        timerBarDuration       = TIMERBAR_LEAD_TIME,
        preAlertTime           = skill.preAlert and (castTime - skill.preAlert) or nil,
        barPriority            = skill.barPriority or 2,
        showBunBar             = skill.showBunBar ~= false,
        showTimerBar           = skill.showTimerBar ~= false,
        headAlert              = skill.headAlert or false,
        screenAlert            = skill.screenAlert or false,
        preAlertText           = skill.preAlertText,
        screenText             = skill.screenText,
        centralLead            = NormalizeLeadSeconds(skill.centralLead, 0),
        voiceLabel             = skill.voiceLabel,
        source                 = source,
        encounterID            = tonumber(self._encounterID),
        timerBarSchedulePolicy = "SCHEDULED",
        eventID                = ResolveSkillEventID(skill, self._encounterID),
        eventColor             = skill.eventColor,
        preAlertFired          = false,
        hintCountdownFired     = false,
        hintCentralFired       = false,
        castFired              = false,
        bunBarShown            = false,
        fiveSecBroadcastFired  = false,
        timerBarShown          = false,
        timelineManaged        = false,
        timelineEventID        = nil,
        timelinePreAlertLead   = DEFAULT_PREALERT_SECS,
        fixedTimelineMatched   = false,
        waitTimelineFinish     = skill.waitTimelineFinish == true,
        timelineFinishTimeout  = tonumber(skill.timelineFinishTimeout),
        centralFired           = false,
        skillDef               = skill,
    }

    self:_ApplyTimerDisplayName(timer)
    self:_ApplyEncounterEventActions(timer)

    if not self:_ApplySkillOverride(timer) then
        return nil
    end

    self._active[id] = timer

    return id
end

-- ── blizzard 原生轴桥接 ──────────────────────────────────────


function Scheduler:_FlushTimelineAddedPending(now)
    if not (self._running and self._mode == "blizzard" and ModeUsesTimeline(self._mode)) then
        return
    end
    local pending = TimelineAddedBuffer._timelineAddedPending
    if type(pending) ~= "table" then
        return
    end

    now = SafeToNumber(now) or GetTime()
    local batch = nil
    for eventID, queued in pairs(pending) do
        if type(queued) ~= "table" or now >= (SafeToNumber(queued.readyAt) or 0) then
            pending[eventID] = nil
            batch = batch or {}
            batch[#batch + 1] = queued
        end
    end

    local filtered = TimelineAddedBuffer:_FilterTimelineAddedBatch(batch, now, self._mode, self._fixedDriver,
        self._encounterID)
    if not filtered then
        return
    end

    for _, queued in ipairs(filtered) do
        local eventID = SafeToNumber(queued.timelineEventID)
        if eventID then
            TimelineAddedBuffer._timelineCountdownSpecByEventID[eventID] = BuildTimelineCountdownSpec(
                queued.spellName,
                queued.iconFileID,
                queued.eventColor
            )
            self:_AttachTimelineEventByID(
                eventID,
                TimelineAddedBuffer:_GetTimelineRemaining(eventID, queued.duration),
                queued.spellIdentifier,
                queued.spellName,
                queued.iconFileID,
                queued.eventColor,
                queued.source
            )
        end
    end
end

function Scheduler:_BuildTimelineTimer(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
                                       passthroughIconFileID, passthroughEventColor, passthroughSource)
    eventID = SafeToNumber(eventID)
    if not eventID then return nil end

    local now = GetTime()
    remaining = SafeNum(remaining, TimelineAddedBuffer:_GetTimelineRemaining(eventID, 0))
    if remaining < 0 then remaining = 0 end

    -- 12.0 secret 规则：显示名只透传事件载荷 spellName，不调用外部法术名 API。
    local name = ResolveTimelineDisplayName(passthroughSpellName, eventID)
    local priority = 2
    local screenAlert = false
    local occurrenceCount = self:_NextOccurrenceCount({
        eventID = eventID,
        spellIdentifier = passthroughSpellIdentifier,
        displayName = name,
    }, "blizzard")

    local timer = {
        -- secret 值只做透传，不在本模块做比较/运算。
        spellID                    = nil,
        spellIdentifier            = passthroughSpellIdentifier,
        timelineSpellName          = passthroughSpellName,
        iconFileID                 = passthroughIconFileID,
        baseDisplayName            = name,
        displayName                = name,
        occurrenceCount            = occurrenceCount,
        castTime                   = now + remaining,
        duration                   = math.max(5, remaining),
        timerBarDuration           = TIMERBAR_LEAD_TIME,
        preAlertTime               = nil,
        barPriority                = priority,
        showBunBar                 = true,
        showTimerBar               = true,
        headAlert                  = false,
        screenAlert                = screenAlert,
        preAlertText               = nil,
        screenText                 = nil,
        centralLead                = 0,
        voiceLabel                 = nil,
        source                     = "blizzard",
        encounterID                = tonumber(self._encounterID),
        timerBarSchedulePolicy     = "SCHEDULED",
        eventID                    = nil,
        eventColor                 = passthroughEventColor,
        preAlertFired              = false,
        hintCountdownFired         = false,
        hintCentralFired           = false,
        castFired                  = false,
        bunBarShown                = false,
        fiveSecBroadcastFired      = false,
        timerBarShown              = false,
        timelineManaged            = true,
        timelineEventID            = eventID,
        timelineSourceType         = tonumber(passthroughSource),
        blizzardHintSessionEnabled = (self._blizzardHintSessionEnabled == true),
        timelinePreAlertLead       = 0,
        centralFired               = false,
    }
    self:_ApplyTimerDisplayName(timer)
    self:_ApplyEncounterEventActions(timer)
    if not self:_ApplySkillOverride(timer) then
        return nil
    end
    local trashMeta = TrashRuntimeConfig and type(TrashRuntimeConfig.GetTimelineEventMeta) == "function"
        and TrashRuntimeConfig.GetTimelineEventMeta(eventID) or nil
    if type(trashMeta) == "table" then
        ApplyTrashTimelineMeta(timer, trashMeta)
    end
    return timer
end

function Scheduler:_AttachTimelineEventByID(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
                                            passthroughIconFileID, passthroughEventColor, passthroughSource)
    eventID = SafeToNumber(eventID)
    if not eventID then return end

    local exists = self._timelineEventToTimer[eventID]
    if exists and self._active[exists] then
        local timer = self._active[exists]
        if timer then
            if passthroughSpellIdentifier ~= nil then
                timer.spellIdentifier = passthroughSpellIdentifier
            end
            if passthroughSpellName ~= nil then
                timer.timelineSpellName = passthroughSpellName
            end
            if passthroughIconFileID ~= nil then
                timer.iconFileID = passthroughIconFileID
            end
            if type(passthroughEventColor) == "table" then
                timer.eventColor = passthroughEventColor
            end
            timer.timelineSourceType = tonumber(passthroughSource) or timer.timelineSourceType
            timer.blizzardHintSessionEnabled = (self._blizzardHintSessionEnabled == true)
            timer.spellID = nil
            timer.baseDisplayName = ResolveTimelineDisplayName(timer.timelineSpellName, eventID)
            self:_ApplyTimerDisplayName(timer)
        end
        local now = GetTime()
        remaining = SafeNum(remaining, TimelineAddedBuffer:_GetTimelineRemaining(eventID, timer.castTime - now))
        if remaining and remaining >= 0 then
            timer.castTime = now + remaining
            if timer.countdownMode == "own" then
                timer.timelinePreAlertLead = math.min(DEFAULT_PREALERT_SECS, math.max(0, remaining))
            else
                timer.timelinePreAlertLead = 0
            end
        end
        if not self:_ApplySkillOverride(timer) then
            self:_DetachTimelineEvent(eventID)
        end
        local trashMeta = TrashRuntimeConfig and type(TrashRuntimeConfig.GetTimelineEventMeta) == "function"
            and TrashRuntimeConfig.GetTimelineEventMeta(eventID) or nil
        if type(trashMeta) == "table" then
            ApplyTrashTimelineMeta(timer, trashMeta)
        end
        self:_ApplyEncounterEventActions(timer)
        return
    end

    local timer = self:_BuildTimelineTimer(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
        passthroughIconFileID, passthroughEventColor, passthroughSource)
    if not timer then return end

    local id = self._nextTimerID
    self._nextTimerID = id + 1
    timer.id = id
    self._active[id] = timer
    self._timelineEventToTimer[eventID] = id
end

function Scheduler:_DetachTimelineEvent(eventID)
    local timerID = self._timelineEventToTimer[eventID]
    if not timerID then return end
    self._timelineEventToTimer[eventID] = nil
    self._active[timerID] = nil
end

function Scheduler:_RecoverTimelineEvents()
    if not (self._running and ModeUsesTimeline(self._mode) and CanUseTimelineAPI()) then
        return
    end
    local now = GetTime and GetTime() or 0
    if self._mode == "blizzard" and now < (tonumber(self._ignoreTimelineRecoveryUntil) or 0) then
        return
    end
    if self._mode == "blizzard" and self._encounterID ~= nil then
        return
    end
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventList) then
        return
    end
    local ok, events = pcall(C_EncounterTimeline.GetEventList)
    if not ok or type(events) ~= "table" then return end

    for _, eventID in ipairs(events) do
        if TimelineAddedBuffer:_GetTimelineState(eventID) ~= STATE_ACTIVE then
            TimelineAddedBuffer._acceptedTimelineEventIDs[SafeToNumber(eventID) or 0] = nil
            TimelineAddedBuffer._timelineCountdownSpecByEventID[SafeToNumber(eventID) or 0] = nil
        else
            local remaining = TimelineAddedBuffer:_GetTimelineRemaining(eventID, 0)
            if IsTimelineDurationAllowed(remaining) then
                local passthroughSpellIdentifier = nil
                local passthroughSpellName = nil
                local passthroughIconFileID = nil
                local passthroughEventColor = nil
                if C_EncounterTimeline and C_EncounterTimeline.GetEventInfo then
                    local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
                    if okInfo and info then
                        passthroughSpellIdentifier = info.spellID
                        passthroughSpellName = info.spellName
                        passthroughIconFileID = SafeToNumber(info.iconFileID)
                        passthroughEventColor = ExtractColorRGB(info.color)
                        TimelineAddedBuffer._timelineCountdownSpecByEventID[eventID] = BuildTimelineCountdownSpec(
                            info.spellName,
                            info.iconFileID,
                            passthroughEventColor
                        )
                    end
                end
                TimelineAddedBuffer._acceptedTimelineEventIDs[SafeToNumber(eventID) or 0] = true
                self:_AttachTimelineEventByID(eventID, remaining, passthroughSpellIdentifier, passthroughSpellName,
                    passthroughIconFileID, passthroughEventColor)
            end
        end
    end
end

function Scheduler:_OnTimelineEventAdded(eventInfo)
    if not (self._running and ModeUsesTimeline(self._mode)) then return end
    -- 优先使用 ADDED 事件透传的信息（与原生时间轴同源）。
    if type(eventInfo) == "table" and SafeToNumber(eventInfo.id) then
        TimelineAddedBuffer:_QueueTimelineEventAdded(eventInfo)
        return
    end
    if self._mode ~= "blizzard" then
        self:_RecoverTimelineEvents()
    end
end

function Scheduler:_OnTimelineEventStateChanged(eventID)
    if not (self._running and ModeUsesTimeline(self._mode)) then return end
    local timelineEventID = SafeToNumber(eventID)
    local timerID = self._timelineEventToTimer[timelineEventID or eventID]
    local timer = timerID and self._active[timerID] or nil
    local state = TimelineAddedBuffer:_GetTimelineState(eventID)
    if self._mode == "blizzard" and TimelineAddedBuffer._acceptedTimelineEventIDs[timelineEventID or 0] ~= true then
        return
    end
    if self._mode == "blizzard"
        and timelineEventID
        and type(TimelineAddedBuffer._timelineAddedPending) == "table"
        and TimelineAddedBuffer._timelineAddedPending[timelineEventID] then
        if state ~= STATE_ACTIVE then
            TimelineAddedBuffer:_ClearTimelineAddedPending(timelineEventID)
            TimelineAddedBuffer._acceptedTimelineEventIDs[timelineEventID] = nil
            TimelineAddedBuffer._timelineCountdownSpecByEventID[timelineEventID] = nil
        end
        return
    end

    if not timerID then
        if self._mode == "blizzard" then
            return
        end
        local passthroughSpellIdentifier = nil
        local passthroughSpellName = nil
        local passthroughIconFileID = nil
        local passthroughEventColor = nil
        if C_EncounterTimeline and C_EncounterTimeline.GetEventInfo then
            local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
            if okInfo and info then
                passthroughSpellIdentifier = info.spellID
                passthroughSpellName = info.spellName
                passthroughIconFileID = SafeToNumber(info.iconFileID)
                passthroughEventColor = ExtractColorRGB(info.color)
                TimelineAddedBuffer._timelineCountdownSpecByEventID[eventID] = BuildTimelineCountdownSpec(
                    info.spellName,
                    info.iconFileID,
                    passthroughEventColor
                )
            end
        end
        self:_AttachTimelineEventByID(eventID, TimelineAddedBuffer:_GetTimelineRemaining(eventID, 0),
            passthroughSpellIdentifier,
            passthroughSpellName, passthroughIconFileID, passthroughEventColor, nil)
        return
    end

    timer = self._active[timerID]
    if not timer then
        self._timelineEventToTimer[eventID] = nil
        return
    end

    if state == STATE_FINISHED then
        if timer.trashKeepTimerBarAfterReadyEnabled == true then
            timer.trashReadyAt = tonumber(timer.trashReadyAt) or GetTime()
            timer.castTime = GetTime()
            timer.timelineManaged = false
            timer.timelineEventID = nil
            self._timelineEventToTimer[eventID] = nil
            return
        end
        timer.castFired = true
        if ExBoss.Timeline.Dispatcher then
            ExBoss.Timeline.Dispatcher:OnCast(timer)
        end
        self:_DetachTimelineEvent(eventID)
    elseif state == STATE_CANCELED then
        self:_DetachTimelineEvent(eventID)
    end
end

function Scheduler:_OnTimelineEventRemoved(eventID)
    if not (self._running and ModeUsesTimeline(self._mode)) then return end
    local timelineEventID = SafeToNumber(eventID) or 0
    TimelineAddedBuffer:_ClearTimelineAddedPending(timelineEventID)
    TimelineAddedBuffer._acceptedTimelineEventIDs[timelineEventID] = nil
    TimelineAddedBuffer._timelineCountdownSpecByEventID[timelineEventID] = nil
    self:_DetachTimelineEvent(eventID)
end

function Scheduler:_UpdateTimelineManagedTimer(timer, now)
    local eventID = timer.timelineEventID
    if not eventID then
        if timer.trashKeepTimerBarAfterReadyEnabled == true and timer.trashReadyAt ~= nil then
            local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
            if hideAfter > 0 and (now - tonumber(timer.trashReadyAt)) >= hideAfter then
                return "remove"
            end
            timer.castTime = now
            return "keep"
        end
        return "remove"
    end

    local state = TimelineAddedBuffer:_GetTimelineState(eventID)
    if state == nil then
        return "remove"
    end

    local remaining = TimelineAddedBuffer:_GetTimelineRemaining(eventID, timer.castTime - now)
    if type(remaining) == "number" and remaining >= 0 then
        timer.castTime = now + remaining
    else
        remaining = math.max(0, timer.castTime - now)
    end

    local blizzardCentralLead = tonumber(timer.blizzardHintCentralLead) or 2
    if timer.useBlizzardHintCentral == true and timer.centralMode == "blizzard_hint" and timer.hintCentralFired ~= true and remaining <= blizzardCentralLead then
        timer.hintCentralFired = true
        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnTimelineHint then
            ExBoss.Timeline.Dispatcher:OnTimelineHint(timer, blizzardCentralLead)
        end
    end

    local lead = SafeNum(timer.timelinePreAlertLead, DEFAULT_PREALERT_SECS)
    if timer.countdownMode == "own" and timer.preAlertEnabled == true and not timer.preAlertFired and remaining <= lead then
        timer.preAlertFired = true
        if ExBoss.Timeline.Dispatcher then
            ExBoss.Timeline.Dispatcher:OnPreAlert(timer)
        end
    end

    local centralLead = NormalizeLeadSeconds(timer.centralLead, 0)
    if timer.centralMode == "own" and centralLead > 0 and timer.centralEnabled == true and not timer.centralFired and remaining <= centralLead then
        timer.centralFired = true
        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnCentral then
            ExBoss.Timeline.Dispatcher:OnCentral(timer)
        end
    end

    if state == STATE_FINISHED or remaining <= 0 then
        if timer.trashKeepTimerBarAfterReadyEnabled == true then
            timer.trashReadyAt = tonumber(timer.trashReadyAt) or now
            timer.castTime = now
            local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
            if hideAfter > 0 and (now - timer.trashReadyAt) >= hideAfter then
                return "remove"
            end
            return "keep"
        end
        if not timer.castFired then
            timer.castFired = true
            if ExBoss.Timeline.Dispatcher then
                ExBoss.Timeline.Dispatcher:OnCast(timer)
            end
            if timer.clearActiveSnapshotAfter then
                self:_ScheduleClearActiveSnapshot(timer)
            end
        end
        return "remove"
    end
    if state == STATE_CANCELED then
        return "remove"
    end
    return "keep"
end

-- ── HIGHLIGHT 事件 ───────────────────────────────────────────
-- ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT 在某个技能剩余约5秒时触发（无参数）。

local HIGHLIGHT_TARGET_SECS = 5 -- Blizzard 触发时提前量（秒）

function Scheduler:_OnTimelineHighlight(eventID)
    if not self._running then return end

    local timelineEventID = eventID
    if timelineEventID then
        if self._mode == "blizzard" and TimelineAddedBuffer._acceptedTimelineEventIDs[timelineEventID] ~= true then
            return
        end
        local timerID = self._timelineEventToTimer and self._timelineEventToTimer[timelineEventID] or nil
        local timer = timerID and self._active and self._active[timerID] or nil
        local isBlizzardManaged = type(timer) == "table"
            and (timer.timelineManaged == true
                or timer.countdownMode == "blizzard_hint"
                or timer.centralMode == "blizzard_hint")
        if isBlizzardManaged then
            local blizzardCountdownLead = timer.blizzardHintCountdownLead or HIGHLIGHT_TARGET_SECS
            if timer.useBlizzardHintCountdown == true and timer.countdownMode == "blizzard_hint" and blizzardCountdownLead == HIGHLIGHT_TARGET_SECS and timer.hintCountdownFired ~= true then
                timer.blizzardHighlightCountdownFired = true
                timer.hintCountdownFired = true
                timer.blizzardCountdownShown = true
                local spec = TimelineAddedBuffer._timelineCountdownSpecByEventID[timelineEventID]
                if spec and ExBoss.UI.Countdown and ExBoss.UI.Countdown.Show then
                    ExBoss.UI.Countdown:Show(spec)
                end
            end
            return
        end
    end
end

-- ── OnUpdate 驱动 ────────────────────────────────────────────

function Scheduler:_OnUpdate(elapsed)
    if not self._running then return end
    self._elapsed = self._elapsed + elapsed
    if self._elapsed < ONUPDATE_INTERVAL then return end
    self._elapsed  = 0

    local now      = GetTime()
    local toRemove = nil

    self:_FlushTimelineAddedPending(now)
    self:_FlushFixedAIPendingEvents(now)
    self:_TickBossCastObserve(now)

    for id, timer in pairs(self._active) do
        local action = nil
        if timer.timelineManaged then
            action = self:_UpdateTimelineManagedTimer(timer, now)
        end

        -- ENCOUNTER_WARNING 声明式提示以 Boss event 的预计结束时刻为窗口中心。
        -- 即使本 tick 随后回收 timer，Runtime 已保存的 windowAfter 仍可继续匹配。
        local encounterWarningAlert = ExBoss and ExBoss.TargetAlert or nil
        if encounterWarningAlert and type(encounterWarningAlert.ObserveBossTimer) == "function" then
            encounterWarningAlert:ObserveBossTimer(timer, self._encounterID, now)
        end

        if action ~= "remove" then
            if not timer.bunBarShown and timer.showBunBar and IsBunBarEnabledByGlobal()
                and IsTimerAllowedOnBarBySource(timer, "bun")
                and now >= (timer.castTime - ResolveBunBarLeadTime()) then
                timer.bunBarShown = true
                if ExBoss.UI.BunBar and ExBoss.UI.BunBar.AddTimer then
                    ExBoss.UI.BunBar:AddTimer(timer)
                end
            end

            if not timer.timerBarShown and timer.showTimerBar and IsTimerBarEnabledByGlobal()
                and IsTimerAllowedOnBarBySource(timer, "timer")
                and ShouldShowTimerBarNow(timer, now) then
                timer.timerBarShown = true
                timer.timerBarDuration = ResolveTimerBarDisplayDuration(timer, now)
                if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.AddTimer then
                    ExBoss.UI.TimerBar:AddTimer(timer)
                end
            end

            if not timer.fiveSecBroadcastFired and not timer.castFired then
                local remaining = timer.castTime - now
                if remaining <= TIMER_FIVE_SEC_REMAINING_THRESHOLD and remaining > 0 then
                    timer.fiveSecBroadcastFired = true
                    BossProgressDebugPrint(string.format(
                        "five-sec timer=%s event=%s source=%s mode=%s remaining=%.3f disabled=%s useRing=%s ring=%s castBar=%s observe=%s",
                        tostring(timer.id), tostring(timer.eventID), tostring(timer.source), tostring(timer._mode),
                        tonumber(remaining) or 0, tostring(timer.disabled == true), tostring(timer.useRingProgress == true),
                        tostring(timer.ringEnabled == true), tostring(timer.castProgressBarEnabled == true),
                        tostring(self:_ShouldUseBossCastObserve(timer))
                    ))
                    TimerEventEmitter.PublishTimerFiveSecRemaining(timer, self._encounterID, remaining)
                    self:_QueueBossCastObserveForTimer(timer, now)
                end
            end

            if not timer.timelineManaged then
                if timer.trashKeepTimerBarAfterReadyEnabled == true and timer.trashReadyAt ~= nil then
                    local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
                    if hideAfter > 0 and (now - tonumber(timer.trashReadyAt)) >= hideAfter then
                        action = "remove"
                    else
                        timer.castTime = now
                        action = "keep"
                    end
                end
            end

            if not timer.timelineManaged and action ~= "remove" and timer.source == "trash" then
                local remaining = math.max(0, timer.castTime - now)
                if timer.countdownMode == "own" and timer.preAlertEnabled == true and not timer.preAlertFired and timer.preAlertTime and now >= timer.preAlertTime then
                    timer.preAlertFired = true
                    local lead = math.max(0, tonumber(timer.castTime or now) - tonumber(timer.preAlertTime or now))
                    timer.preAlertCountdownDuration = math.max(0.1,
                        math.min(lead > 0 and lead or DEFAULT_PREALERT_SECS, remaining))
                    if timer.preAlertCountdownDuration > 0.15 and ExBoss.Timeline.Dispatcher then
                        ExBoss.Timeline.Dispatcher:OnPreAlert(timer)
                    end
                end
                local centralLead = NormalizeLeadSeconds(timer.centralLead, 0)
                if timer.centralMode == "own" and centralLead > 0 and timer.centralEnabled == true and not timer.centralFired and remaining <= centralLead then
                    timer.centralFired = true
                    if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnCentral then
                        ExBoss.Timeline.Dispatcher:OnCentral(timer)
                    end
                end
                TryFireFixedVoiceTriggers(timer, now)
                if now >= timer.castTime then
                    if not timer.castFired then
                        timer.castFired = true
                    end
                    if self:_AdvanceTrashFixedCombatTimeline(timer, now) then
                        action = "keep"
                    else
                        timer.trashReadyAt = tonumber(timer.trashReadyAt) or now
                        timer.castTime = now
                        if timer.trashKeepTimerBarAfterReadyEnabled == true then
                            local hideAfter = math.max(0, tonumber(timer.trashKeepTimerBarAfterReadySeconds) or 0)
                            if hideAfter > 0 and (now - timer.trashReadyAt) >= hideAfter then
                                action = "remove"
                            else
                                action = "keep"
                            end
                        else
                            action = "remove"
                        end
                    end
                end
            end

            if not timer.timelineManaged and action ~= "remove" and timer.source ~= "trash" and not (timer.trashKeepTimerBarAfterReadyEnabled == true and timer.trashReadyAt ~= nil) then
                if timer.source == "fixed_ai" and timer.fixedAIPaused == true then
                    local lastTick = tonumber(timer.fixedAIPausedTick) or tonumber(timer.fixedAIPausedAt) or now
                    local pauseDelta = math.max(0, now - lastTick)
                    if pauseDelta > 0 then
                        ShiftFixedAITimerForPause(timer, pauseDelta)
                    end
                    timer.fixedAIPausedTick = now
                    action = "keep"
                else
                    local blizzardCountdownLead = tonumber(timer.blizzardHintCountdownLead) or
                        VIRTUAL_HINT_REMAINING_SECS
                    if timer.useBlizzardHintCountdown == true and timer.countdownMode == "blizzard_hint" and timer.hintCountdownFired ~= true and now >= (timer.castTime - blizzardCountdownLead) then
                        timer.hintCountdownFired = true
                        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnTimelineHint then
                            ExBoss.Timeline.Dispatcher:OnTimelineHint(timer, blizzardCountdownLead)
                        end
                    end
                    local blizzardCentralLead = tonumber(timer.blizzardHintCentralLead) or 2
                    if timer.useBlizzardHintCentral == true and timer.centralMode == "blizzard_hint" and timer.hintCentralFired ~= true and now >= (timer.castTime - blizzardCentralLead) then
                        timer.hintCentralFired = true
                        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnTimelineHint then
                            ExBoss.Timeline.Dispatcher:OnTimelineHint(timer, blizzardCentralLead)
                        end
                    end
                    if timer.countdownMode == "own" and timer.preAlertEnabled == true and not timer.preAlertFired and timer.preAlertTime and now >= timer.preAlertTime then
                        timer.preAlertFired = true
                        local remaining = math.max(0, tonumber(timer.castTime or now) - now)
                        local lead = math.max(0, tonumber(timer.castTime or now) - tonumber(timer.preAlertTime or now))
                        timer.preAlertCountdownDuration = math.max(0.1,
                            math.min(lead > 0 and lead or DEFAULT_PREALERT_SECS, remaining))
                        if timer.preAlertCountdownDuration > 0.15 and ExBoss.Timeline.Dispatcher then
                            ExBoss.Timeline.Dispatcher:OnPreAlert(timer)
                        end
                    end
                    local centralLead = NormalizeLeadSeconds(timer.centralLead, 0)
                    if timer.centralMode == "own" and centralLead > 0 and timer.centralEnabled == true and not timer.centralFired and now >= (timer.castTime - centralLead) then
                        timer.centralFired = true
                        if ExBoss.Timeline.Dispatcher and ExBoss.Timeline.Dispatcher.OnCentral then
                            ExBoss.Timeline.Dispatcher:OnCentral(timer)
                        end
                    end
                    local castNow = false
                    if not timer.castFired and now >= timer.castTime and timer.source == "fixed_ai" then
                        if TryEnterFixedAICastStartWait(timer, now) then
                            local deadline = tonumber(timer.fixedAICastStartDeadline) or now
                            if now >= deadline then
                                castNow = true
                            else
                                action = "keep"
                            end
                        elseif self:_TryHoldFixedAIForTimelineFinish(timer, now) then
                            action = "keep"
                        else
                            castNow = true
                        end
                    elseif not timer.castFired and timer.source == "fixed_ai" and IsFixedAICastStartFinishMode(timer) and TryEnterFixedAICastStartWait(timer, now) then
                        local deadline = tonumber(timer.fixedAICastStartDeadline) or now
                        if now >= deadline then
                            castNow = true
                        else
                            action = "keep"
                        end
                    else
                        TryFireFixedVoiceTriggers(timer, now)
                        castNow = not timer.castFired and now >= timer.castTime
                    end
                    if castNow then
                        if timer.source == "fixed_ai" then
                            self:_TriggerFixedAITimerCast(timer, now, "cast-timeout-fallback")
                            for trigger = 1, 2 do
                                local enabledKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"
                                local firedKey = "fixedVoiceTrigger" .. tostring(trigger) .. "Fired"
                                local fireAt = GetFixedVoiceTriggerFireTime(timer, trigger)
                                local keepPending = (timer[enabledKey] == true)
                                    and (timer[firedKey] ~= true)
                                    and fireAt
                                    and fireAt > now
                                if not keepPending then
                                    timer[firedKey] = true
                                end
                            end
                        else
                            timer.fixedAIWaitingTimelineFinish = false
                            timer.castFired = true
                            if ExBoss.Timeline.Dispatcher then
                                ExBoss.Timeline.Dispatcher:OnCast(timer)
                            end
                            if timer.clearActiveSnapshotAfter then
                                self:_ScheduleClearActiveSnapshot(timer)
                            end
                            EnsureFixedVoiceAtCast(timer)
                        end
                        if timer.source == "fixed" then
                            self:_ScheduleNextFixedOccurrence(timer)
                        end
                    end
                end
                if timer.castFired and not HasPendingFixedVoiceTriggers(timer) then
                    action = "remove"
                end
            end
        end

        if action == "remove" then
            if not toRemove then toRemove = {} end
            toRemove[id] = true
        end
    end

    if toRemove then
        for id in pairs(toRemove) do
            self:_RemoveActiveTimerByID(id)
        end
    end
end

function Scheduler:GetActiveTimers()
    return self._active
end

function Scheduler:GetCurrentEncounterID()
    return self._encounterID
end

-- ── 帧初始化 ─────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:Hide()
frame:SetScript("OnUpdate", function(_, elapsed)
    Scheduler:_OnUpdate(elapsed)
end)
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
Scheduler._handlesEncounterEvents = false
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_START" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        Scheduler:_RecordBossCastObserveStart(unit, "cast", castBarID)
        Scheduler:_OnBossSpellcastBoundary(unit, "cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        Scheduler:_RecordBossCastObserveStart(unit, "channel", castBarID)
        Scheduler:_OnBossSpellcastBoundary(unit, "channel")
    elseif event == "UNIT_SPELLCAST_STOP" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        local specialEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "cast")
        if IsBossCastObserveUnit(unit) then
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "cast", castBarID, specialEventID)
        end
        if castBar and type(castBar.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            castBar:StopByUnitCastBar(unit, castBarID, "cast")
        end
        if ring and type(ring.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            ring:StopByUnitCastBar(unit, castBarID, "cast")
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        local specialEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "channel")
        if IsBossCastObserveUnit(unit) then
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "channel", castBarID, specialEventID)
        end
        if castBar and type(castBar.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            castBar:StopByUnitCastBar(unit, castBarID, "channel")
        end
        if ring and type(ring.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialEventID,
                })
            end
            ring:StopByUnitCastBar(unit, castBarID, "channel")
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        local unit = ...
        local castBarID = select(select("#", ...), ...)
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        local specialCastEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "cast")
        local specialChannelEventID = GetSpecialBossStopEventID(Scheduler._encounterID, unit, "channel")
        if IsBossCastObserveUnit(unit) then
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "cast", castBarID, specialCastEventID)
            Scheduler:_ResolveAndStopBossObservedRuntime(unit, "channel", castBarID, specialChannelEventID)
        end
        if castBar and type(castBar.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialCastEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialCastEventID,
                })
            end
            if specialChannelEventID and type(castBar.StopByOwner) == "function" then
                castBar:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialChannelEventID,
                })
            end
            castBar:StopByUnitCastBar(unit, castBarID, "cast")
            castBar:StopByUnitCastBar(unit, castBarID, "channel")
        end
        if ring and type(ring.StopByUnitCastBar) == "function" and IsBossCastObserveUnit(unit) then
            if specialCastEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "cast",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialCastEventID,
                })
            end
            if specialChannelEventID and type(ring.StopByOwner) == "function" then
                ring:StopByOwner({
                    source = "boss",
                    unit = NormalizeUnitToken(unit),
                    castKind = "channel",
                    encounterID = tonumber(Scheduler._encounterID),
                    eventID = specialChannelEventID,
                })
            end
            ring:StopByUnitCastBar(unit, castBarID, "cast")
            ring:StopByUnitCastBar(unit, castBarID, "channel")
        end
    elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        if Scheduler._running and Scheduler._mode == "fixed" then
            if Scheduler._fixedDriver == FIXED_DRIVER_AI then
                Scheduler:_OnFixedAITimelineEventAdded(arg1)
                return
            end
            if Scheduler._fixedDriver == FIXED_DRIVER_TIME then
                Scheduler:_OnFixedTimeTimelineEventAdded(arg1)
                return
            end
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_OnTimelineEventAdded(arg1)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        if Scheduler._running and Scheduler._mode == "fixed" then
            if Scheduler._fixedDriver == FIXED_DRIVER_AI then
                Scheduler:_OnFixedAITimelineEventStateChanged(arg1)
            end
            return
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_OnTimelineEventStateChanged(arg1)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        if Scheduler._running and Scheduler._mode == "fixed" then
            if Scheduler._fixedDriver == FIXED_DRIVER_AI then
                Scheduler:_OnFixedAITimelineEventRemoved(arg1)
                return
            end
            if Scheduler._fixedDriver == FIXED_DRIVER_TIME then
                Scheduler:_OnFixedTimeTimelineEventRemoved(arg1)
                return
            end
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_OnTimelineEventRemoved(arg1)
    elseif event == "ENCOUNTER_TIMELINE_STATE_UPDATED" then
        if Scheduler._suppressBlizzardTimeline == true then
            return
        end
        local now = GetTime and GetTime() or 0
        if Scheduler._mode == "blizzard" and now < (tonumber(Scheduler._ignoreTimelineRecoveryUntil) or 0) then
            return
        end
        if not Scheduler._running then
            Scheduler:StartBlizzardFallback()
        end
        Scheduler:_RecoverTimelineEvents()
    elseif event == "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT" then
        local arg1 = ...
        if Scheduler._suppressBlizzardTimeline == true and not (Scheduler._running and Scheduler._mode == "fixed") then
            return
        end
        Scheduler:_OnTimelineHighlight(arg1)
    end
end)
Scheduler._frame   = frame
Scheduler._elapsed = 0

-- 时间轴事件统一经过 ExwindTools 分发：原生事件与 ExwindDev 的离线虚拟事件共用同一入口。
-- UNIT_SPELLCAST_* 仍由 Scheduler 自己的 frame 监听，因为它们不属于时间轴回放输入。
if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    local timelineEvents = {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT",
        "ENCOUNTER_TIMELINE_STATE_UPDATED",
    }
    for _, timelineEvent in ipairs(timelineEvents) do
        ExwindTools:RegisterEvent(timelineEvent, "ExBoss.Scheduler.Timeline", function(event, ...)
            local handler = frame:GetScript("OnEvent")
            if handler then
                handler(frame, event, ...)
            end
        end)
    end
end

if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent(TRASH_CASTBAR_STOP_EVENT, "ExBoss.Scheduler.TrashCastBarStop", function(_, payload)
        if type(payload) ~= "table" then
            return
        end
        local owner = {
            source = "trash",
            runtime = payload.runtime,
            castKind = tostring(payload.castKind or ""),
            castBarID = NormalizeCastBarID(payload.castBarID),
        }
        local castBar = ExBoss and ExBoss.UI and ExBoss.UI.CastProgressBar or nil
        if castBar and type(castBar.StopByOwner) == "function" then
            castBar:StopByOwner(owner)
        end
        local ring = ExBoss and ExBoss.UI and ExBoss.UI.RingProgress or nil
        if ring and type(ring.StopByOwner) == "function" then
            ring:StopByOwner(owner)
        end
    end)
end

-- BOSS 注册表（由 EXBOSS12S2/Bosses/*.lua 填入）
ExBoss.Timeline._bosses = ExBoss.Timeline._bosses or {}

function ExBoss.Timeline:RegisterBoss(encounterID, def)
    self._bosses[encounterID] = def
end
