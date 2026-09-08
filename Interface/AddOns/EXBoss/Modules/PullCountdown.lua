---@diagnostic disable: undefined-global, undefined-field

ExBoss = ExBoss or {}
ExBoss.PullCountdown = ExBoss.PullCountdown or {}

local Mod = ExBoss.PullCountdown
local PULL_ICON_FILE_ID = 132337
local DEFAULT_PULL_SECONDS = 10

local activePullTimerID = nil

local function L()
    return ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
end

local function PrintMessage(text)
    if ExBoss and ExBoss.Print and type(ExBoss.Print.Say) == "function" then
        ExBoss.Print.Say(text)
        return
    end
    print("|cff00ffff<EXBOSS>|r " .. tostring(text or ""))
end

local function IsSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function GetScheduler()
    return ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
end

local function GetCountdownVoiceRuntime()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.Countdown or nil
end

local function RemoveActivePullTimer(_reason)
    local sched = GetScheduler()
    local timerID = tonumber(activePullTimerID)
    if not (sched and timerID and type(sched._RemoveActiveTimerByID) == "function") then
        activePullTimerID = nil
        return
    end
    sched:_RemoveActiveTimerByID(timerID)
    activePullTimerID = nil
end

local function CancelPullVoiceCountdown()
    local runtime = GetCountdownVoiceRuntime()
    if runtime and type(runtime.Cancel) == "function" then
        runtime:Cancel("pull")
    end
end

local function BuildPullTimer(timerID, seconds)
    local now = GetTime()
    local text = tostring(L()["倒数"])
    return {
        id = timerID,
        baseDisplayName = text,
        displayName = text,
        timerBarName = text,
        iconFileID = PULL_ICON_FILE_ID,
        castTime = now + seconds,
        baseCastTime = now + seconds,
        duration = seconds,
        timerBarDuration = seconds,
        occurrenceCount = nil,
        useOccurrenceCount = false,
        occurrenceDisplayMode = "none",
        barPriority = 1,
        showBunBar = true,
        showTimerBar = true,
        showNameplate = false,
        nameplateSide = "right",
        ringEnabled = false,
        castProgressBarEnabled = false,
        headAlert = false,
        screenAlert = false,
        centralEnabled = false,
        centralMode = "none",
        centralLead = 0,
        preAlertEnabled = false,
        preAlertFired = true,
        countdownMode = "none",
        countdownVoiceEnabled = false,
        countdownPlayName = false,
        preAlertTime = nil,
        preAlertText = nil,
        screenText = nil,
        voiceLabel = nil,
        source = "pull",
        eventID = nil,
        eventColor = nil,
        preAlertCountdownDuration = 0,
        timelineManaged = false,
        timelineEventID = nil,
        hintCountdownFired = false,
        hintCentralFired = false,
        mechanicPreAlertFired = false,
        castFired = false,
        bunBarShown = false,
        timerBarShown = false,
        fiveSecBroadcastFired = false,
        centralFired = false,
        fixedVoiceTrigger1Enabled = false,
        fixedVoiceTrigger1Fired = true,
        fixedVoiceTrigger2Enabled = false,
        fixedVoiceTrigger2Fired = true,
        _isPullCountdown = true,
    }
end

function Mod:ShowPullBar(seconds)
    if IsSecretValue(seconds) == true then
        return false, "secret-time"
    end

    local duration = tonumber(seconds)
    if not duration or duration <= 0 then
        RemoveActivePullTimer("pull-zero")
        return false, "invalid-time"
    end

    local sched = GetScheduler()
    if not (sched and type(sched.EnsureTrashLocalRuntime) == "function" and type(sched._RemoveActiveTimerByID) == "function") then
        return false, "scheduler-unavailable"
    end

    RemoveActivePullTimer("pull-replace")
    sched:EnsureTrashLocalRuntime()
    sched._active = sched._active or {}
    sched._nextTimerID = tonumber(sched._nextTimerID) or 1

    local timerID = sched._nextTimerID
    sched._nextTimerID = timerID + 1
    sched._active[timerID] = BuildPullTimer(timerID, duration)
    activePullTimerID = timerID
    return true
end

function Mod:CancelPullBar()
    RemoveActivePullTimer("pull-cancel")
    CancelPullVoiceCountdown()
end

function Mod:HandleStartPlayerCountdown(_, initiatedBy, timeRemaining, totalTime)
    local voiceRuntime = GetCountdownVoiceRuntime()
    if voiceRuntime and type(voiceRuntime.IsPullCountdownEnabled) == "function"
        and voiceRuntime:IsPullCountdownEnabled() == false then
        return
    end
    if IsSecretValue(initiatedBy) == true or IsSecretValue(timeRemaining) == true or IsSecretValue(totalTime) == true then
        return
    end

    local total = tonumber(totalTime)
    local remaining = tonumber(timeRemaining)
    local seconds = total
    if not seconds or seconds <= 0 then
        seconds = remaining
    end
    if not seconds or seconds <= 0 then
        return
    end

    self:ShowPullBar(seconds)

    voiceRuntime = GetCountdownVoiceRuntime()
    if voiceRuntime and type(voiceRuntime.Start) == "function"
        and type(voiceRuntime.IsPullCountdownVoiceEnabled) == "function"
        and voiceRuntime:IsPullCountdownVoiceEnabled() == true then
        local now = GetTime()
        local startFrom = math.max(1, math.min(voiceRuntime.GetMaxCountdownDigit and voiceRuntime:GetMaxCountdownDigit() or 5,
            math.floor(seconds + 0.0001)))
        voiceRuntime:Start({
            key = "pull",
            scope = "global",
            endAt = now + seconds,
            startFrom = startFrom,
            minDigit = 1,
        })
    end
end

function Mod:HandleCancelPlayerCountdown()
    self:CancelPullBar()
end

function Mod:StartPullCountdown(seconds)
    if IsSecretValue(seconds) == true then
        return false, "secret-time"
    end

    local duration = tonumber(seconds)
    if not duration then
        duration = DEFAULT_PULL_SECONDS
    end
    duration = math.floor(duration + 0.0001)

    if duration < 0 then
        return false, "invalid-time"
    end

    if not (C_PartyInfo and type(C_PartyInfo.DoCountdown) == "function") then
        return false, "countdown-api-missing"
    end

    C_PartyInfo.DoCountdown(duration)
    return true
end

function Mod:HandleSlash(rest)
    local text = tostring(rest or ""):match("^%s*(.-)%s*$")
    if text == "" then
        local ok, err = self:StartPullCountdown(DEFAULT_PULL_SECONDS)
        if ok == true then
            return true
        end
        if err == "countdown-api-missing" then
            PrintMessage(L()["当前客户端不支持团队倒数。"])
        else
            PrintMessage(L()["开怪倒数功能未就绪"])
        end
        return true
    end

    local lowered = string.lower(text)
    if lowered == "stop" or lowered == "cancel" then
        self:StartPullCountdown(0)
        return true
    end

    local seconds = tonumber(text)
    if not seconds then
        PrintMessage(L()["用法：/exb pull [秒数]"])
        return true
    end

    local ok, err = self:StartPullCountdown(seconds)
    if ok == true then
        return true
    end
    if err == "countdown-api-missing" then
        PrintMessage(L()["当前客户端不支持团队倒数。"])
    else
        PrintMessage(L()["开怪倒数功能未就绪"])
    end
    return true
end

function Mod:TryRegisterPullSlashAlias()
    if self._pullSlashRegistered == true then
        return
    end
    if type(SlashCmdList) ~= "table" then
        return
    end
    if _G.BigWigs or _G.DBM or SlashCmdList.pull or SlashCmdList.PULL or SlashCmdList["DEADLYBOSSMODSPULL"] then
        return
    end
    SLASH_EXBOSS_PULL1 = "/pull"
    SlashCmdList["EXBOSS_PULL"] = function(input)
        Mod:HandleSlash(input)
    end
    self._pullSlashRegistered = true
end

if ExwindTools and Mod._eventsRegistered ~= true then
    ExwindTools:RegisterEvent("START_PLAYER_COUNTDOWN", "ExBoss.PullCountdown.Start", function(...)
        Mod:HandleStartPlayerCountdown(...)
    end)
    ExwindTools:RegisterEvent("CANCEL_PLAYER_COUNTDOWN", "ExBoss.PullCountdown.Cancel", function(...)
        Mod:HandleCancelPlayerCountdown(...)
    end)
    ExwindTools:RegisterEvent("STOP_PLAYER_COUNTDOWN", "ExBoss.PullCountdown.Stop", function(...)
        Mod:HandleCancelPlayerCountdown(...)
    end)
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss.PullCountdown.World", function()
        Mod:HandleCancelPlayerCountdown()
        Mod:TryRegisterPullSlashAlias()
    end)
    Mod._eventsRegistered = true
end

Mod:TryRegisterPullSlashAlias()
