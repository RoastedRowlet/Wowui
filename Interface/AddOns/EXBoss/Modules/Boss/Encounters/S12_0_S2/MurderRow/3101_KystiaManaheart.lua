---@diagnostic disable: undefined-global

do
    local ExwindTools = _G.ExwindTools
    local ENCOUNTER_ID = 3101
    local VULNERABILITY_SEVERITY = 1
    local MAX_VULNERABILITY_TIMES = 4
    local INITIAL_DAMAGE_REDUCTION = 80
    local DAMAGE_REDUCTION_PER_LAYER = 20
    local VULNERABILITY_KEY = "exboss:3101:vulnerability"
    local encounterActive = false

    local function SetVulnerabilityState(times, damageTaken)
        if not (ExwindTools and type(ExwindTools.UpdateState) == "function") then
            return
        end
        ExwindTools:UpdateState("3101dmgtimes", tonumber(times) or 0)
        ExwindTools:UpdateState("3101dmgtaken", tonumber(damageTaken) or 0)
    end

    local function StopVulnerability()
        if ExBoss and type(ExBoss.StopVulnerability) == "function" then
            ExBoss:StopVulnerability(VULNERABILITY_KEY)
        end
    end

    local function EnterVulnerability()
        if not encounterActive then
            return
        end

        local state = ExwindTools and ExwindTools.State or nil
        local currentTimes = tonumber(state and state["3101dmgtimes"]) or 0
        if currentTimes >= MAX_VULNERABILITY_TIMES then
            return
        end

        local nextTimes = currentTimes + 1
        local nextDamageTaken = math.max(0, INITIAL_DAMAGE_REDUCTION - nextTimes * DAMAGE_REDUCTION_PER_LAYER)
        SetVulnerabilityState(nextTimes, nextDamageTaken)

        if ExBoss and type(ExBoss.ShowVulnerability) == "function" then
            ExBoss:ShowVulnerability(100, 1.7, 20, {
                key = VULNERABILITY_KEY,
                channel = "central_medium",
            })
        end
    end

    local function OnEncounterWarning(_, encounterWarningInfo)
        -- 此处只允许读取 severity；不访问 encounterWarningInfo 的任何其他字段。
        local severity = encounterWarningInfo and encounterWarningInfo.severity
        if severity == VULNERABILITY_SEVERITY then
            EnterVulnerability()
        end
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_3101_Vulnerability_Start", function(_, encounterID)
            if tonumber(encounterID) ~= ENCOUNTER_ID then
                return
            end
            encounterActive = true
            StopVulnerability()
            SetVulnerabilityState(0, INITIAL_DAMAGE_REDUCTION)
        end)

        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_3101_Vulnerability_End", function(_, encounterID)
            if tonumber(encounterID) ~= ENCOUNTER_ID then
                return
            end
            encounterActive = false
            StopVulnerability()
            SetVulnerabilityState(0, 0)
        end)

        ExwindTools:RegisterEvent("ENCOUNTER_WARNING", "ExBoss_3101_Vulnerability_Warning", OnEncounterWarning)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3101,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "kystia_manaheart", name = "Kystia Manaheart", zhCN = "凯斯媞亚·魔力之心" },
    healthThresholds = {
        -- 此战的阶段目标是 boss2（咬咬），不是主首领 boss1。
        { unit = "boss2", threshold = 20, preset = "phase_transition" },
    },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
