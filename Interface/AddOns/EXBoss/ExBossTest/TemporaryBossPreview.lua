---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- 临时 Boss 显示测试
--
-- 这是设置页专用的短期预览工具。它不进入真实 Scheduler 生命周期，
-- 不伪造 ENCOUNTER_START/END，也不写入任何配置。
-- 删除本文件、TOC 加载行和设置页按钮调用即可完整移除。
-- =============================================================

ExBoss.TemporaryBossPreview = ExBoss.TemporaryBossPreview or {}
local Preview = ExBoss.TemporaryBossPreview

local OWNER = "ExBoss.TemporaryBossPreview"
local EVENT_SPACING = 5
local CAST_CLEANUP_DELAY = 0.50

Preview._running = Preview._running == true
Preview._generation = tonumber(Preview._generation) or 0
Preview._sequence = tonumber(Preview._sequence) or 0
Preview._handles = Preview._handles or {}
Preview._events = Preview._events or {}
Preview._activeTimers = Preview._activeTimers or {}

local function NotifyStateChanged()
    local page = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
    if page and type(page.RefreshTemporaryBossPreviewButton) == "function" then
        pcall(page.RefreshTemporaryBossPreviewButton, page)
    end
end

local function CancelHandles()
    for handle in pairs(Preview._handles) do
        if type(handle) == "table" and type(handle.Cancel) == "function" then
            pcall(handle.Cancel, handle)
        end
    end
    wipe(Preview._handles)
end

local function Schedule(delay, generation, callback)
    local handle
    handle = C_Timer.NewTimer(math.max(0, tonumber(delay) or 0), function()
        Preview._handles[handle] = nil
        if Preview._running ~= true or Preview._generation ~= generation then
            return
        end
        callback()
    end)
    Preview._handles[handle] = true
    return handle
end

local function StopBars(timer)
    if type(timer) ~= "table" or timer.id == nil then return end
    local timerBar = ExBoss and ExBoss.UI and ExBoss.UI.TimerBar
    local bunBar = ExBoss and ExBoss.UI and ExBoss.UI.BunBar
    if timerBar and type(timerBar.StopExternalTimer) == "function" then
        pcall(timerBar.StopExternalTimer, timerBar, timer.id)
    end
    if bunBar and type(bunBar.StopExternalTimer) == "function" then
        pcall(bunBar.StopExternalTimer, bunBar, timer.id)
    end
end

local function CopyEvents(boss)
    local out = {}
    for _, event in ipairs(type(boss) == "table" and type(boss.events) == "table" and boss.events or {}) do
        if type(event) == "table" then
            local eventID = tonumber(event.eventID)
            local spellID = tonumber(event.evenSpellID or event.spellID)
            if eventID or spellID then
                local copy = {}
                for key, value in pairs(event) do copy[key] = value end
                out[#out + 1] = copy
            end
        end
    end
    return out
end

local function ResolveSpellInfo(spellID)
    if not spellID then return nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info end
    end
    return nil
end

local function BuildTimer(event, encounterID, duration)
    local eventID = tonumber(event and event.eventID)
    local spellIdentifier = tonumber(event and (event.evenSpellID or event.spellID))
    if not eventID and not spellIdentifier then return nil end

    local spellInfo = ResolveSpellInfo(spellIdentifier)
    local displayName = tostring(event.name or event.eventName or (spellInfo and spellInfo.name) or
        (eventID and ("事件 " .. tostring(eventID))) or ("技能 " .. tostring(spellIdentifier)))
    local iconFileID = tonumber(event.iconFileID) or (spellInfo and tonumber(spellInfo.iconID)) or 136243
    local now = GetTime()

    Preview._sequence = Preview._sequence + 1
    local timer = {
        id = "exboss-temp-preview:" .. tostring(Preview._sequence),
        spellID = tonumber(event.spellID) or spellIdentifier,
        spellIdentifier = spellIdentifier,
        iconFileID = iconFileID,
        baseDisplayName = displayName,
        displayName = displayName,
        occurrenceCount = 1,
        baseCastTime = now + duration,
        castTime = now + duration,
        duration = duration,
        timerBarDuration = duration,
        preAlertTime = now,
        barPriority = tonumber(event.barPriority) or 2,
        showBunBar = event.showBunBar ~= false,
        showTimerBar = event.showTimerBar ~= false,
        headAlert = false,
        screenAlert = event.screenAlert == true,
        preAlertText = event.preAlertText,
        screenText = event.centralText,
        centralLead = tonumber(event.centralLead) or 0,
        voiceLabel = event.voiceLabel,
        source = "fixed",
        displaySource = "boss",
        encounterID = tonumber(encounterID),
        eventID = eventID,
        eventColor = event.eventColor,
        iconFlags = tonumber(event.iconFlags) or 0,
        timerBarSchedulePolicy = "SCHEDULED",
        preAlertFired = false,
        castFired = false,
        centralFired = false,
        timelineManaged = false,
        skillDef = event,
        __temporaryBossPreview = true,
    }

    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if not (scheduler and type(scheduler._ApplySkillOverride) == "function") then
        return nil
    end
    local ok, enabled = pcall(scheduler._ApplySkillOverride, scheduler, timer)
    if not ok or enabled ~= true or timer.disabled == true then
        return nil
    end
    return timer
end

local function GetBarDisplayMode()
    local root = _G.EXBOSS12S2
    local general = type(root) == "table" and type(root.ui) == "table" and
        type(root.ui.general) == "table" and root.ui.general or nil
    local mode = tostring(type(general) == "table" and general.barDisplayMode or "bun"):lower()
    if mode ~= "bun" and mode ~= "timer" and mode ~= "both" and mode ~= "none" then
        return "bun"
    end
    return mode
end

local function ShowBars(timer)
    local mode = GetBarDisplayMode()
    if timer.showBunBar == true and (mode == "bun" or mode == "both") then
        local bunBar = ExBoss and ExBoss.UI and ExBoss.UI.BunBar
        if bunBar and type(bunBar.StartExternalTimer) == "function" then
            pcall(bunBar.StartExternalTimer, bunBar, timer)
        end
    end
    if timer.showTimerBar == true and (mode == "timer" or mode == "both") then
        local timerBar = ExBoss and ExBoss.UI and ExBoss.UI.TimerBar
        if timerBar and type(timerBar.StartExternalTimer) == "function" then
            pcall(timerBar.StartExternalTimer, timerBar, timer)
        end
    end
end

local function PlayVoice(timer, trigger)
    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if engine and type(engine.TryPlayForTimer) == "function" then
        pcall(engine.TryPlayForTimer, engine, timer, trigger)
    end
end

local function GetVoiceDelay(timer, trigger, now)
    if timer["fixedVoiceTrigger" .. tostring(trigger) .. "Enabled"] ~= true then return nil end
    local baseTime = trigger == 2 and tonumber(timer.preAlertTime) or tonumber(timer.castTime)
    if not baseTime then return nil end
    if trigger == 2 and timer.countdownPlayName == true then baseTime = baseTime - 1 end
    local mode = tostring(timer["fixedVoiceTrigger" .. tostring(trigger) .. "Mode"] or "delay")
    local offset = math.max(0, tonumber(timer["fixedVoiceTrigger" .. tostring(trigger) .. "Offset"]) or 0)
    local fireAt = mode == "early" and (baseTime - offset) or (baseTime + offset)
    return math.max(0, fireAt - now)
end

function Preview:_ArmTimer(event, timer, generation)
    self._activeTimers[timer.id] = timer
    ShowBars(timer)
    local now = GetTime()
    local dispatcher = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Dispatcher

    if timer.countdownMode == "own" and timer.preAlertEnabled == true and timer.preAlertTime then
        Schedule(math.max(0, timer.preAlertTime - now), generation, function()
            timer.preAlertFired = true
            timer.preAlertCountdownDuration = math.max(0.1, timer.castTime - GetTime())
            if dispatcher and type(dispatcher.OnPreAlert) == "function" then
                pcall(dispatcher.OnPreAlert, dispatcher, timer)
            end
        end)
    end

    if timer.centralMode == "own" and timer.centralEnabled == true and (tonumber(timer.centralLead) or 0) > 0 then
        Schedule(math.max(0, timer.castTime - timer.centralLead - now), generation, function()
            timer.centralFired = true
            if dispatcher and type(dispatcher.OnCentral) == "function" then
                pcall(dispatcher.OnCentral, dispatcher, timer)
            end
        end)
    end

    for trigger = 1, 2 do
        local triggerIndex = trigger
        local delay = GetVoiceDelay(timer, triggerIndex, now)
        if delay then
            Schedule(delay, generation, function()
                timer["fixedVoiceTrigger" .. tostring(triggerIndex) .. "Fired"] = true
                PlayVoice(timer, triggerIndex)
            end)
        end
    end

    Schedule(math.max(0, timer.castTime - now), generation, function()
        timer.castFired = true
        if dispatcher and type(dispatcher.OnCast) == "function" then
            pcall(dispatcher.OnCast, dispatcher, timer)
        end

        -- 当前技能完成后，立即把同一技能的下一轮补到队尾。
        -- 例如五个技能始终保持 5/10/15/20/25 秒的滚动间距。
        local nextTimer = BuildTimer(event, self._encounterID, self._cycleDuration)
        if nextTimer then
            self:_ArmTimer(event, nextTimer, generation)
        end

        Schedule(CAST_CLEANUP_DELAY, generation, function()
            StopBars(timer)
            self._activeTimers[timer.id] = nil
        end)
    end)
    return true
end

function Preview:IsRunning()
    return self._running == true
end

function Preview:Start(boss)
    self:Stop("restart")
    local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if (ExwindTools and ExwindTools.State and ExwindTools.State.IsBossEncounter == true)
        or (scheduler and scheduler._running == true) then
        return false, "真实首领战进行中"
    end
    local encounterID = type(boss) == "table" and tonumber(boss.encounterID) or nil
    local events = CopyEvents(boss)
    if not encounterID or #events == 0 then
        return false, "当前首领没有可测试技能"
    end

    self._generation = self._generation + 1
    self._running = true
    self._encounterID = encounterID
    self._events = events

    local prepared = {}
    for _, event in ipairs(events) do
        local delay = (#prepared + 1) * EVENT_SPACING
        local timer = BuildTimer(event, encounterID, delay)
        if timer then
            prepared[#prepared + 1] = { event = event, timer = timer }
        end
    end
    if #prepared == 0 then
        self:Stop("no-enabled-events")
        return false, "当前配置没有启用的测试技能"
    end

    self._cycleDuration = #prepared * EVENT_SPACING
    NotifyStateChanged()
    for _, item in ipairs(prepared) do
        self:_ArmTimer(item.event, item.timer, self._generation)
    end
    return true
end

function Preview:Stop(reason)
    local wasRunning = self._running == true
    self._generation = self._generation + 1
    self._running = false
    CancelHandles()
    for _, timer in pairs(self._activeTimers) do StopBars(timer) end
    wipe(self._activeTimers)
    self._events = {}
    self._cycleDuration = nil
    self._encounterID = nil
    self._stopReason = reason
    if wasRunning then NotifyStateChanged() end
    return wasRunning
end

if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent("ENCOUNTER_START", OWNER, function()
        Preview:Stop("real-encounter")
    end)
end
