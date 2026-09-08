---@diagnostic disable: undefined-global

do
    local ExwindTools = _G.ExwindTools
    local ENCOUNTER_ID = 3457
    local EVENT_ID = 938
    local PRIMARY_BOSS_UNIT = "boss1"
    local INTERRUPT_STATE_KEY = "3457interrupt"
    local WINDOW_CLEAR_SECONDS = 5
    local encounterActive = false
    local windowActive = false
    local clearTimer = nil
    local armTimer = nil
    local clearToken = 0
    local armToken = 0
    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

    local function CancelTimer(timer)
        if timer and type(timer.Cancel) == "function" then
            pcall(timer.Cancel, timer)
        end
    end

    local function SetInterruptState(count)
        if not (ExwindTools and type(ExwindTools.UpdateState) == "function") then
            return
        end
        ExwindTools:UpdateState(INTERRUPT_STATE_KEY, tonumber(count) or 0)
    end

    local function ClearInterruptState()
        clearToken = clearToken + 1
        CancelTimer(clearTimer)
        clearTimer = nil
        windowActive = false
        SetInterruptState(0)
        if ExwindTools and type(ExwindTools.UpdateState) == "function" then
            ExwindTools:UpdateState("3457interrupt1name", "")
            ExwindTools:UpdateState("3457interrupt2name", "")
            ExwindTools:UpdateState("3457interrupt3name", "")
        end
    end

    local function ShowInterruptText(index)
        local medium = ExBoss and ExBoss.UI and ExBoss.UI.FlashTextMedium
        if medium and type(medium.Show) == "function" then
            medium:Show({
                text = string.format(L["%s断"], tostring(index)),
                duration = 1.5,
                noAnimation = true,
            })
        end
    end

    local function CompleteWindowAfterDelay()
        clearToken = clearToken + 1
        local token = clearToken
        CancelTimer(clearTimer)
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            clearTimer = C_Timer.NewTimer(WINDOW_CLEAR_SECONDS, function()
                if token ~= clearToken then return end
                clearTimer = nil
                ClearInterruptState()
            end)
        elseif C_Timer and type(C_Timer.After) == "function" then
            clearTimer = true
            C_Timer.After(WINDOW_CLEAR_SECONDS, function()
                if token ~= clearToken then return end
                clearTimer = nil
                ClearInterruptState()
            end)
        else
            ClearInterruptState()
        end
    end

    local function BeginInterruptWindow()
        if not encounterActive then
            return
        end
        -- 新一轮 938 窗口覆盖尚未到期的上一轮清理，保证下一次仍从第 1 断开始。
        CancelTimer(clearTimer)
        clearTimer = nil
        ClearInterruptState()
        windowActive = true
    end

    local function ArmInterruptWindow(delay)
        armToken = armToken + 1
        local token = armToken
        CancelTimer(armTimer)
        armTimer = nil
        local wait = math.max(0, tonumber(delay) or 0)
        if wait <= 0.05 then
            BeginInterruptWindow()
            return
        end
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            armTimer = C_Timer.NewTimer(wait, function()
                if token ~= armToken then return end
                armTimer = nil
                BeginInterruptWindow()
            end)
        elseif C_Timer and type(C_Timer.After) == "function" then
            armTimer = true
            C_Timer.After(wait, function()
                if token ~= armToken then return end
                armTimer = nil
                BeginInterruptWindow()
            end)
        else
            BeginInterruptWindow()
        end
    end

    local function OnFixedAIEventScheduled(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if tonumber(type(payload) == "table" and payload.eventID or nil) ~= EVENT_ID then
            return
        end
        if not encounterActive then
            return
        end
        ArmInterruptWindow(math.max(0, (tonumber(payload and payload.remaining) or 0) - 1))
    end

    local function OnUnitSpellcastStart(_, unitTarget)
        -- 此事件只读取 unitTarget；castGUID、spellID、castBarID 均不访问。
        if windowActive ~= true or unitTarget ~= PRIMARY_BOSS_UNIT then
            return
        end
        local state = ExwindTools and ExwindTools.State or nil
        local current = tonumber(state and state[INTERRUPT_STATE_KEY]) or 0
        if current >= 3 then
            return
        end
        local index = current + 1
        SetInterruptState(index)
        ShowInterruptText(index)
        if index == 3 then
            windowActive = false
            CompleteWindowAfterDelay()
        end
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_SCHEDULED", "ExBoss_3457_Interrupt_Window", OnFixedAIEventScheduled)
        ExwindTools:RegisterEvent("UNIT_SPELLCAST_START", "ExBoss_3457_Interrupt_Cast", OnUnitSpellcastStart)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_3457_Interrupt_Start", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                encounterActive = true
                ClearInterruptState()
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_3457_Interrupt_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID then
                encounterActive = false
                armToken = armToken + 1
                CancelTimer(armTimer)
                armTimer = nil
                ClearInterruptState()
            end
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3457,
    dungeon = { key = "altar_of_fangs", name = "Altar of Fangs", zhCN = "毒牙祭坛" },
    boss = { key = "the_writhing_coil", name = "The Writhing Coil", zhCN = "扭缠盘蛇" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
