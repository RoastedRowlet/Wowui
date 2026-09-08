-- git branch test

---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- Core/ExBoss_Alert.lua
-- TEST
-- 统一文字提示 API。
--
-- 只做显示通道路由，不做 Boss / 机制判断。
-- =============================================================

ExBoss = ExBoss or {}
ExBoss.Alert = ExBoss.Alert or {}

local Alert = ExBoss.Alert
local activeCountdowns = {}
local activeVulnerabilityTimers = {}
local StopCountdownDisplays
local VULNERABILITY_DEFAULT_KEY = "boss:vulnerability"
local VULNERABILITY_PREP_COLOR = { r = 1, g = 0.82, b = 0.1, a = 1 }
local VULNERABILITY_ACTIVE_COLOR = { r = 1, g = 0.18, b = 0.12, a = 1 }
local VULNERABILITY_END_COLOR = { r = 1, g = 1, b = 1, a = 1 }

local function LText(key)
    local L = ExBoss and ExBoss.L
    if L then
        return L[key]
    end
    return key
end

local function NormalizeChannel(channel)
    return "central_medium"
end

local function NormalizePayload(textOrPayload, duration, options)
    local payload
    if type(textOrPayload) == "table" then
        payload = textOrPayload
    else
        payload = type(options) == "table" and options or {}
        payload.text = tostring(textOrPayload or "")
        payload.duration = duration
    end

    payload.channel = NormalizeChannel(payload.channel)
    payload.text = tostring(payload.text or "")
    payload.duration = tonumber(payload.duration) or 1.5
    return payload
end

local function ShowMedium(payload)
    local ui = ExBoss and ExBoss.UI and ExBoss.UI.FlashTextMedium
    if not (ui and type(ui.Show) == "function") then
        return false
    end
    ui:Show(payload)
    return true
end

function Alert:FlashText(textOrPayload, duration, options)
    local payload = NormalizePayload(textOrPayload, duration, options)
    if payload.text == "" then
        return false
    end
    return ShowMedium(payload)
end

local function ShowCountdownMedium(payload)
    local ui = ExBoss and ExBoss.UI and ExBoss.UI.FlashTextMedium
    if not (ui and type(ui.ShowCountdown) == "function") then
        return ShowMedium(payload)
    end
    ui:ShowCountdown(payload)
    return true
end

function Alert:FlashCountdownText(payload)
    payload = NormalizePayload(payload)
    return ShowCountdownMedium(payload)
end

local function StopCountdown(key)
    local state = activeCountdowns[key]
    if not state then return end
    if state.stopTimer and type(state.stopTimer.Cancel) == "function" then
        state.stopTimer:Cancel()
    end
    activeCountdowns[key] = nil
    if not next(activeCountdowns) then
        StopCountdownDisplays()
    end
end

StopCountdownDisplays = function()
    local ui = ExBoss and ExBoss.UI or nil
    local medium = ui and ui.FlashTextMedium or nil
    if medium and type(medium.StopCountdown) == "function" then
        medium:StopCountdown()
    end
end

local function ReplaceTemplateText(text, value)
    return tostring(text or ""):gsub("{text}", function()
        return tostring(value or "")
    end)
end

function Alert:StopFlashCountdown(key)
    StopCountdown(tostring(key or "default"))
end

function Alert:FlashCountdown(textOrPayload, seconds, options)
    local payload = NormalizePayload(textOrPayload, 1.05, options)
    local total = tonumber(payload.seconds or seconds) or 0
    if payload.text == "" or total <= 0 then
        return false
    end

    local key = tostring(payload.key or payload.id or payload.text or "default")
    StopCountdown(key)

    local template = tostring(payload.template or "{text} {time}")
    local endAt = tonumber(payload.endAt or payload.endTime) or (GetTime() + total)
    if not (C_DurationUtil and type(C_DurationUtil.CreateDuration) == "function") then
        error("ExBoss.Alert requires C_DurationUtil.CreateDuration for countdown text", 2)
    end
    local durationObject = C_DurationUtil.CreateDuration()
    durationObject:SetTimeFromEnd(endAt, total, tonumber(payload.modRate) or 1)

    local pre, suffix = template:match("^(.-){time}(.*)$")
    if not pre then
        error("ExBoss.Alert countdown template requires exactly one {time} placeholder", 2)
    end
    local labelText = ReplaceTemplateText(pre, payload.text)
    local suffixText = ReplaceTemplateText(suffix, payload.text)
    local state = {
        endAt = endAt,
        payload = payload,
        durationObject = durationObject,
    }
    activeCountdowns[key] = state
    Alert:FlashCountdownText({
        text = payload.text,
        label = labelText,
        suffix = suffixText,
        durationObject = durationObject,
        channel = payload.channel,
        color = payload.color,
        noAnimation = payload.noAnimation ~= false,
    })
    state.stopTimer = C_Timer.NewTimer(math.max(0, endAt - GetTime()), function()
        -- The timer is only an end-of-life notification.  Blizzard owns all
        -- visible countdown updates through the DurationTextBinding.
        if activeCountdowns[key] == state then
            StopCountdown(key)
        end
    end)
    return true
end

local function CopyColor(color)
    if type(color) ~= "table" then
        return nil
    end
    return {
        r = tonumber(color.r) or 1,
        g = tonumber(color.g) or 1,
        b = tonumber(color.b) or 1,
        a = tonumber(color.a) or 1,
    }
end

local function BuildVulnerabilityOptions(options)
    options = type(options) == "table" and options or {}
    local key = tostring(options.key or VULNERABILITY_DEFAULT_KEY)
    return {
        key = key,
        prepKey = tostring(options.prepKey or (key .. ":prep")),
        activeKey = tostring(options.activeKey or key),
        channel = options.channel or "central_medium",
        template = options.template or "{text} {time}",
        noAnimation = options.noAnimation ~= false,
    }
end

local function FormatVulnerabilityText(value, fallback)
    if value == nil or value == "" then
        return fallback
    end
    local n = tonumber(value)
    if n then
        local percentText
        if math.floor(n) == n then
            percentText = tostring(math.floor(n))
        else
            percentText = tostring(n)
        end
        return string.format(LText("%s%%易伤"), percentText)
    end
    return tostring(value)
end

local function FormatVulnerabilityActiveText(value)
    return FormatVulnerabilityText(value, LText("易伤阶段"))
end

local function CancelVulnerabilityTimers(key)
    local timers = activeVulnerabilityTimers[key]
    if type(timers) == "table" then
        for i = 1, #timers do
            local timer = timers[i]
            if timer and type(timer.Cancel) == "function" then
                pcall(timer.Cancel, timer)
            end
        end
    end
    activeVulnerabilityTimers[key] = nil
end

local function AddVulnerabilityTimer(key, timer)
    if not timer then
        return
    end
    activeVulnerabilityTimers[key] = activeVulnerabilityTimers[key] or {}
    local timers = activeVulnerabilityTimers[key]
    timers[#timers + 1] = timer
end

function Alert:ShowVulnerabilityPrepare(seconds, options)
    local cfg = BuildVulnerabilityOptions(options)
    local text = type(options) == "table" and options.text or nil
    StopCountdown(cfg.activeKey)
    return self:FlashCountdown(text or LText("准备易伤"), tonumber(seconds) or 1, {
        channel = cfg.channel,
        template = cfg.template,
        key = cfg.prepKey,
        noAnimation = cfg.noAnimation,
        color = CopyColor(type(options) == "table" and options.color) or VULNERABILITY_PREP_COLOR,
    })
end

function Alert:ShowVulnerabilityActive(labelOrPercent, seconds, options)
    local cfg = BuildVulnerabilityOptions(options)
    local text = FormatVulnerabilityText(labelOrPercent, LText("易伤阶段"))
    StopCountdown(cfg.prepKey)
    return self:FlashCountdown(text, tonumber(seconds) or 1, {
        channel = cfg.channel,
        template = cfg.template,
        key = cfg.activeKey,
        noAnimation = cfg.noAnimation,
        color = CopyColor(type(options) == "table" and options.color) or VULNERABILITY_ACTIVE_COLOR,
    })
end

function Alert:ShowVulnerabilityEnd(options)
    local cfg = BuildVulnerabilityOptions(options)
    StopCountdown(cfg.prepKey)
    StopCountdown(cfg.activeKey)
    local text = type(options) == "table" and options.text or nil
    return self:FlashText(text or LText("易伤结束"), tonumber(type(options) == "table" and options.duration) or 2, {
        channel = cfg.channel,
        noAnimation = cfg.noAnimation,
        color = CopyColor(type(options) == "table" and options.color) or VULNERABILITY_END_COLOR,
    })
end

function Alert:ShowVulnerability(labelOrPercent, prepareSeconds, activeSeconds, options)
    local cfg = BuildVulnerabilityOptions(options)
    local isActive = type(options) == "table" and options.isActive or nil
    local prepSeconds = tonumber(prepareSeconds) or 0
    local vulnSeconds = tonumber(activeSeconds) or 0
    if prepSeconds <= 0 or vulnSeconds <= 0 then
        return false
    end

    CancelVulnerabilityTimers(cfg.key)
    self:StopVulnerability(options or cfg.key)

    self:ShowVulnerabilityPrepare(prepSeconds, {
        key = cfg.key,
        prepKey = cfg.prepKey,
        activeKey = cfg.activeKey,
        channel = cfg.channel,
        template = cfg.template,
        noAnimation = cfg.noAnimation,
        text = type(options) == "table" and options.prepareText or nil,
        color = type(options) == "table" and options.prepareColor or nil,
    })

    local activeTimer = C_Timer.NewTimer(prepSeconds, function()
        if type(isActive) == "function" and not isActive() then
            self:StopVulnerability(options or cfg.key)
            return
        end
        local activeText = type(options) == "table" and options.activeText or nil
        self:ShowVulnerabilityActive(activeText or FormatVulnerabilityActiveText(labelOrPercent), vulnSeconds, {
            key = cfg.key,
            prepKey = cfg.prepKey,
            activeKey = cfg.activeKey,
            channel = cfg.channel,
            template = cfg.template,
            noAnimation = cfg.noAnimation,
            color = type(options) == "table" and options.activeColor or nil,
        })
    end)
    AddVulnerabilityTimer(cfg.key, activeTimer)

    local endTimer = C_Timer.NewTimer(prepSeconds + vulnSeconds, function()
        if type(isActive) == "function" and not isActive() then
            self:StopVulnerability(options or cfg.key)
            return
        end
        local endText = type(options) == "table" and options.endText or nil
        self:ShowVulnerabilityEnd({
            key = cfg.key,
            prepKey = cfg.prepKey,
            activeKey = cfg.activeKey,
            channel = cfg.channel,
            noAnimation = cfg.noAnimation,
            text = endText or LText("易伤结束"),
            duration = type(options) == "table" and options.endDuration or nil,
            color = type(options) == "table" and options.endColor or nil,
        })
        activeVulnerabilityTimers[cfg.key] = nil
    end)
    AddVulnerabilityTimer(cfg.key, endTimer)
    return true
end

function Alert:StopVulnerability(keyOrOptions)
    local cfg
    if type(keyOrOptions) == "table" then
        cfg = BuildVulnerabilityOptions(keyOrOptions)
    else
        cfg = BuildVulnerabilityOptions({ key = keyOrOptions })
    end
    CancelVulnerabilityTimers(cfg.key)
    StopCountdown(cfg.prepKey)
    StopCountdown(cfg.activeKey)
    if not next(activeCountdowns) then
        StopCountdownDisplays()
    end
end

function ExBoss:FlashText(textOrPayload, duration, options)
    return Alert:FlashText(textOrPayload, duration, options)
end

function ExBoss:FlashCountdown(textOrPayload, seconds, options)
    return Alert:FlashCountdown(textOrPayload, seconds, options)
end

function ExBoss:StopFlashCountdown(key)
    return Alert:StopFlashCountdown(key)
end

function ExBoss:ShowVulnerabilityPrepare(seconds, options)
    return Alert:ShowVulnerabilityPrepare(seconds, options)
end

function ExBoss:ShowVulnerability(labelOrPercent, prepareSeconds, activeSeconds, options)
    return Alert:ShowVulnerability(labelOrPercent, prepareSeconds, activeSeconds, options)
end

function ExBoss:ShowVulnerabilityActive(labelOrPercent, seconds, options)
    return Alert:ShowVulnerabilityActive(labelOrPercent, seconds, options)
end

function ExBoss:ShowVulnerabilityEnd(options)
    return Alert:ShowVulnerabilityEnd(options)
end

function ExBoss:StopVulnerability(keyOrOptions)
    return Alert:StopVulnerability(keyOrOptions)
end
