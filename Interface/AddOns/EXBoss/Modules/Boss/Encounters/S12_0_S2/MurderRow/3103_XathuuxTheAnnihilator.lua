---@diagnostic disable: undefined-global

do
    local ExwindTools = _G.ExwindTools
    local ENCOUNTER_ID = 3103
    local EVENT_ID = 32
    local VULNERABILITY_PERCENT = 30
    local VULNERABILITY_KEY = "exboss:3103:32:vulnerability"

    local function StopVulnerability()
        if ExBoss and type(ExBoss.StopVulnerability) == "function" then
            ExBoss:StopVulnerability(VULNERABILITY_KEY)
        end
    end

    local function OnFixedAIEventFinished(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if tonumber(type(payload) == "table" and payload.eventID or nil) ~= EVENT_ID then
            return
        end
        if not (ExBoss and type(ExBoss.ShowVulnerability) == "function") then
            return
        end

        ExBoss:ShowVulnerability(VULNERABILITY_PERCENT, 4, 15, {
            key = VULNERABILITY_KEY,
            channel = "central_medium",
        })
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_FINISHED", "ExBoss_3103_Vulnerability_Finished", OnFixedAIEventFinished)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_3103_Vulnerability_Start", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                StopVulnerability()
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_3103_Vulnerability_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID then
                StopVulnerability()
            end
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3103,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "xathuux_the_annihilator", name = "Xathuux the Annihilator", zhCN = "歼灭者萨祖克斯" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
