---@diagnostic disable: undefined-global
-- =============================================================
-- ExBossEngine/Dispatcher.lua
-- 技能触发调度：Scheduler → UI 层 + 语音
-- 分发时机：
-- 1. 预警触发（施放前 preAlert 秒）→   倒计时数字（预警文本作为倒计时标签，不走中央文本通道）
-- =============================================================

ExBoss.Timeline.Dispatcher = ExBoss.Timeline.Dispatcher or {}
local Dispatcher = ExBoss.Timeline.Dispatcher
local function TraceColor(stage, timer, color, note)
    local trace = ExBoss and ExBoss.ColorTrace
    if trace and type(trace.Record) == "function" then trace:Record(stage, timer, color, note) end
end
local TIMELINE_HINT_EVENT = "EXBOSS_TIMELINE_HINT"
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

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

local function ResolveSafeTimerName(timer)
    if type(timer) ~= "table" then
        return L["未知技能"]
    end

    local spellID = tonumber(timer.spellID)
    local eventID = tonumber(timer.timelineEventID)
    local isBlizzardStyle = (timer.countdownMode == "blizzard_hint") or (timer.centralMode == "blizzard_hint")

    if isBlizzardStyle then
        if type(timer.displayName) == "string" then
            return timer.displayName
        end
        if spellID then
            return L["技能 "] .. tostring(spellID)
        end
        if eventID then
            return L["时间轴事件 "] .. tostring(eventID)
        end
        return L["时间轴事件"]
    end

    if type(timer.timerBarName) == "string" and timer.timerBarName ~= "" then
        return timer.timerBarName
    end
    if type(timer.displayName) == "string" then
        return timer.displayName
    end
    if spellID then
        return L["技能 "] .. tostring(spellID)
    end
    if eventID then
        return L["时间轴事件 "] .. tostring(eventID)
    end
    return L["未知技能"]
end

local function ResolveTimerEventID(timer)
    if type(timer) ~= "table" then
        return nil
    end
    local eventID = tonumber(timer.eventID)
    if eventID then
        return eventID
    end
    return tonumber(timer.timelineEventID)
end

local function BuildTimelineHintPayload(timer, thresholdSecs)
    local now = GetTime()
    local scheduledAt = tonumber(timer and timer.castTime) or now
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
    local encounterID = scheduler and scheduler._encounterID or nil
    return {
        hintType = "remaining_threshold",
        threshold = tonumber(thresholdSecs) or 0,
        remaining = math.max(0, scheduledAt - now),
        fireAt = now,
        scheduledAt = scheduledAt,
        timerID = tonumber(timer and timer.id),
        encounterID = tonumber(encounterID) or encounterID,
        eventID = ResolveTimerEventID(timer),
        spellID = tonumber(timer and timer.spellID) or nil,
        source = timer and timer.source or nil,
        displayName = ResolveSafeTimerName(timer),
    }
end

local function FormatText(template, timer)
    if template == nil then return nil end

    local isTimeline = timer and ((timer.countdownMode == "blizzard_hint") or (timer.centralMode == "blizzard_hint"))
    if isTimeline then
        -- 时间轴名字可能是 secret 值；直接透传，禁止做任何字符串检查或替换。
        return template
    end

    if type(template) ~= "string" then
        template = tostring(template)
    end

    local hasNameToken = template:find("{name}", 1, true) ~= nil
    local out = template
    if hasNameToken then
        out = out:gsub("{name}", ResolveSafeTimerName(timer))
    end

    local remaining = (timer and timer.castTime) and math.max(0, timer.castTime - GetTime()) or 0
    if out:find("{time}", 1, true) then
        out = out:gsub("{time}", string.format("%.1f", remaining))
    end
    return out
end

local function ResolveCountdownColor(timer)
    if type(timer) ~= "table" then
        return nil
    end
    if type(timer.flashTextColor) == "table" then
        return timer.flashTextColor
    end
    if type(timer.eventColor) == "table" then
        return timer.eventColor
    end
    return nil
end

local function BuildPreAlertCountdownSpec(timer)
    if type(timer) ~= "table" then
        return nil
    end
    if timer.countdownMode ~= "own" then
        return nil
    end

    local txt = FormatText(timer.preAlertText, timer)
    if type(txt) ~= "string" then
        return nil
    end

    local spec = {
        displayName = txt,
        iconFileID = timer.iconFileID or 136197,
        duration = tonumber(timer.preAlertCountdownDuration) or 5,
        color = ResolveCountdownColor(timer),
        traceTimerID = timer.id,
        traceEventID = timer.eventID or timer.timelineEventID,
    }
    TraceColor("Dispatcher.Countdown", timer, spec.color, "mode=" .. tostring(timer.countdownMode))
    return spec
end

local function BuildTimelineCountdownSpec(timer)
    return {
        displayName = timer.displayName,
        iconFileID = timer.iconFileID,
        duration = 5,
        color = nil,
        rawText = true,
        disableIconBorder = true,
    }
end

local function ResolveCentralDisplayText(timer)
    if type(timer) ~= "table" then
        return nil
    end
    local text = timer.screenText
    if type(text) == "string" then
        return text
    end
    text = ResolveSafeTimerName(timer)
    if type(text) == "string" then
        return text
    end
    return nil
end

function Dispatcher:OnMechanicPreAlert(timer)
    if not timer or timer.disabled then return end
end

-- 预警触发（施放前 preAlert 秒）→ 倒计时数字
function Dispatcher:OnPreAlert(timer)
    if not timer or timer.disabled then return end
    self:OnMechanicPreAlert(timer)
    if timer.countdownMode ~= "own" or timer.preAlertEnabled ~= true then return end
    -- 束状条改由 Scheduler 在 30s 进入窗口时挂载，预警阶段不重复添加。
    -- 计时条也由 Scheduler 在进入窗口时挂载，预警阶段不重复添加。
    -- 倒计时数字（预警文本作为倒计时标签，不走中央文本通道）。
    if ExBoss.UI.Countdown and ExBoss.UI.Countdown.Show then
        local spec = BuildPreAlertCountdownSpec(timer)
        if spec then
            ExBoss.UI.Countdown:Show(spec)
        end
    end
    local cd = ExBoss.Voice and ExBoss.Voice.Countdown
    if not (cd and type(cd.Start) == "function") then
        return
    end
    if timer.countdownVoiceEnabled ~= true then
        return
    end
    if timer.countdownMode == "blizzard_hint" then
        return
    end
    local isTrash = (tostring(timer.source or "") == "trash")
    if isTrash and not (type(timer.trashRuntime) == "table" and tonumber(timer.trashRuntime.identityLockedNPCID)) then
        return
    end
    local countdownLead = math.floor(tonumber(timer.timelinePreAlertLead) or tonumber(timer.preAlertCountdownDuration) or 5)
    if countdownLead < 1 then
        return
    end
    cd:Start({
        key = "prealert:" .. tostring(timer.id),
        scope = isTrash and "trash" or "boss",
        endAt = tonumber(timer.castTime) or 0,
        startFrom = countdownLead,
        minDigit = 1,
    })
end

function Dispatcher:OnCentral(timer)
    if not timer or timer.disabled then return end
    if timer.centralMode ~= "own" or timer.centralEnabled ~= true then return end
    local text = ResolveCentralDisplayText(timer)
    if not text then return end
    if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.Show then
        ExBoss.UI.FlashTextMedium:Show(timer, FormatText(text, timer), 1.5)
    end
end

-- 施放触发（技能到时）→ 文字公告
function Dispatcher:OnCast(timer)
    if not timer or timer.disabled then return end
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
    if scheduler and type(scheduler.ShowBossProgressFromTimer) == "function" then
        scheduler:ShowBossProgressFromTimer(timer)
    end
    if timer.showBunBar and IsBunBarEnabledByGlobal() and ExBoss.UI.BunBar and ExBoss.UI.BunBar.OnCast then
        ExBoss.UI.BunBar:OnCast(timer)
    end
    if timer.showTimerBar and IsTimerBarEnabledByGlobal() and ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.OnCast then
        ExBoss.UI.TimerBar:OnCast(timer)
    end
    local text = ResolveCentralDisplayText(timer)
    if timer.centralMode == "own" and timer.centralEnabled == true and timer.centralFired ~= true and text and ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.Show then
        ExBoss.UI.FlashTextMedium:Show(timer, FormatText(text, timer), 1.5)
    end
end

function Dispatcher:OnTimelineHint(timer, thresholdSecs)
    if not timer or timer.disabled then return end
    local threshold = tonumber(thresholdSecs) or 0
    local isBlizzardHintCountdown = (timer.countdownMode == "blizzard_hint")
    local isBlizzardHintCentral = (timer.centralMode == "blizzard_hint")
    if isBlizzardHintCountdown and timer.useBlizzardHintCountdown == true and threshold == (tonumber(timer.blizzardHintCountdownLead) or 5) then
        if timer.blizzardCountdownShown ~= true then
            timer.blizzardCountdownShown = true
            if ExBoss.UI.Countdown and ExBoss.UI.Countdown.Show then
                local spec = BuildTimelineCountdownSpec(timer)
                pcall(function()
                    ExBoss.UI.Countdown:Show(spec)
                end)
            end
        end
    end
    if isBlizzardHintCentral and timer.useBlizzardHintCentral == true and threshold == (tonumber(timer.blizzardHintCentralLead) or 2) then
        if timer.blizzardCentralShown ~= true then
            timer.blizzardCentralShown = true
            if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.Show then
                ExBoss.UI.FlashTextMedium:Show(timer, ResolveSafeTimerName(timer), tonumber(timer.blizzardHintCentralDuration) or 2)
            end
        end
    end
    if not ExwindTools or type(ExwindTools.SendEvent) ~= "function" then return end
    local payload = BuildTimelineHintPayload(timer, thresholdSecs)
    --     "|cff33ff99[EXBoss Hint]|r eventID=%s spellID=%s threshold=%s remaining=%.2f name=%s",
    --     tostring(payload.eventID or "nil"),
    --     tostring(payload.spellID or "nil"),
    --     tostring(payload.threshold or "nil"),
    --     tonumber(payload.remaining) or 0,
    --     tostring(payload.displayName or "未知技能")
    -- ))
    ExwindTools:SendEvent(TIMELINE_HINT_EVENT, payload)
end
