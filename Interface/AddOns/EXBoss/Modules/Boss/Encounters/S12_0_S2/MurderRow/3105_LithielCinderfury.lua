---@diagnostic disable: undefined-global

do
    local ExwindTools = _G.ExwindTools
    local ENCOUNTER_ID = 3105
    local EVENT_ID = 207
    local COUNTDOWN_KEY = "exboss:3105:207:no_portal"
    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

    local function StopNoPortalCountdown()
        local alert = ExBoss and ExBoss.Alert or nil
        if alert and type(alert.StopFlashCountdown) == "function" then
            alert:StopFlashCountdown(COUNTDOWN_KEY)
        end
    end

    local function OnFixedAIEventFinished(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if tonumber(type(payload) == "table" and payload.eventID or nil) ~= EVENT_ID then
            return
        end

        local alert = ExBoss and ExBoss.Alert or nil
        if alert and type(alert.FlashCountdown) == "function" then
            alert:FlashCountdown(L["不要点门"], 10, {
                key = COUNTDOWN_KEY,
                channel = "central_medium",
                noAnimation = true,
            })
        end
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_FINISHED", "ExBoss_3105_NoPortal_Finished", OnFixedAIEventFinished)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_3105_NoPortal_Start", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                StopNoPortalCountdown()
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_3105_NoPortal_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID then
                StopNoPortalCountdown()
            end
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3105,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "lithiel_cinderfury", name = "Lithiel Cinderfury", zhCN = "利希尔·烬怒" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
