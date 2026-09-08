---@diagnostic disable: undefined-global

do
    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
    local ENCOUNTER_ID = 3456
    local EVENT_DEVOUR = 795
    local EVENT_SPELL_ID = 1296216
    local SHIELD_BASE_AMOUNT = 1311783.429
    local WATCH_THROTTLE = 0.1
    local FORCE_TARGET_TEST = false
    local FORCE_TARGET_UNIT = "target"

    ExBoss = ExBoss or {}
    ExBoss.Modules = ExBoss.Modules or {}
    ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

    local Mod = ExBoss.Modules.Boss.RaviShieldBar or {}
    ExBoss.Modules.Boss.RaviShieldBar = Mod

    local shieldWatchFrame = nil
    local watchedBossUnit = nil
    local watchedCastGUID = nil
    local watchActive = false
    local refreshTimer = nil
    local startWatchTimer = nil
    local armChannelTimer = nil
    local shieldMaxValue = nil
    local waitingForShieldChannelStart = false
    local shieldName = nil
    local shieldIconTexture = nil
    local StartShieldWatch = nil
    local RefreshShieldBar = nil
    local function GetExtraShieldBar()
        return ExBoss and ExBoss.UI and ExBoss.UI.ExtraShieldBar or nil
    end

    local function IsRaviActive()
        local state = ExwindTools and ExwindTools.State or nil
        if type(state) == "table" and state.IsBossEncounter == true and tonumber(state.EncounterID) == ENCOUNTER_ID then
            return true
        end
        local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler or nil
        return type(scheduler) == "table"
            and scheduler._running == true
            and tonumber(scheduler._encounterID) == ENCOUNTER_ID
    end

    local function CancelTimer(timer)
        if timer and type(timer.Cancel) == "function" then
            pcall(timer.Cancel, timer)
        end
    end

    local function GetShieldLevelMultiplier()
        local state = ExwindTools and ExwindTools.State or nil
        if not state or state.InMythicPlus ~= true then
            return 1
        end
        local level = tonumber(state and state.MythicPlusLevel) or 0
        local db = _G.EXDB
        local multipliers = db and db.MythicDamageData and db.MythicDamageData.LevelMultipliers or nil
        local multiplier = multipliers and multipliers[level] or nil
        return tonumber(multiplier) or 1
    end

    local function GetConfiguredShieldMaxValue()
        return SHIELD_BASE_AMOUNT * GetShieldLevelMultiplier()
    end

    local function GetSpellName()
        if type(shieldName) == "string" and shieldName ~= "" then
            return shieldName
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(EVENT_SPELL_ID)
            if info and info.name then
                shieldName = info.name
                return shieldName
            end
        end
        shieldName = L["嘶嘶食腐"]
        return shieldName
    end

    local function GetSpellIcon()
        if shieldIconTexture then
            return shieldIconTexture
        end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, EVENT_SPELL_ID)
            if ok and tex then
                shieldIconTexture = tex
                return tex
            end
        end
        shieldIconTexture = 136197
        return shieldIconTexture
    end

    local function HideShieldBar()
        watchActive = false
        watchedBossUnit = nil
        watchedCastGUID = nil
        shieldMaxValue = nil
        CancelTimer(refreshTimer)
        CancelTimer(startWatchTimer)
        CancelTimer(armChannelTimer)
        refreshTimer = nil
        startWatchTimer = nil
        armChannelTimer = nil
        waitingForShieldChannelStart = false
        if shieldWatchFrame then
            shieldWatchFrame:UnregisterAllEvents()
        end
        local bar = GetExtraShieldBar()
        if bar and bar.Hide then
            bar:Hide("Ravi")
        end
    end

    local function ResolveBossUnit()
        if FORCE_TARGET_TEST == true then
            if UnitExists and UnitExists(FORCE_TARGET_UNIT) then
                watchedBossUnit = FORCE_TARGET_UNIT
                return FORCE_TARGET_UNIT
            end
            return nil
        end
        if type(watchedBossUnit) == "string" and UnitExists and UnitExists(watchedBossUnit) then
            return watchedBossUnit
        end
        for i = 1, 5 do
            local unit = "boss" .. tostring(i)
            if UnitExists and UnitExists(unit) then
                watchedBossUnit = unit
                return unit
            end
        end
        return nil
    end

    RefreshShieldBar = function()
        refreshTimer = nil
        local bar = GetExtraShieldBar()
        if not watchActive or (FORCE_TARGET_TEST ~= true and not IsRaviActive()) then
            HideShieldBar()
            return
        end

        local unit = ResolveBossUnit()
        if not unit or not UnitExists or not UnitExists(unit) then
            return
        end

        local absorbAmount = nil
        if UnitGetTotalAbsorbs then
            absorbAmount = UnitGetTotalAbsorbs(unit)
        end

        if not shieldMaxValue then
            shieldMaxValue = GetConfiguredShieldMaxValue()
        end

        if bar and bar.Update then
            bar:Update("Ravi", {
                name = GetSpellName(),
                icon = GetSpellIcon(),
                value = absorbAmount,
                maxValue = shieldMaxValue,
                progressMode = "SECRET_DIRECT_PROGRESS",
            })
        end
    end

    local function ScheduleRefresh()
        if refreshTimer then
            return
        end
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            refreshTimer = C_Timer.NewTimer(WATCH_THROTTLE, RefreshShieldBar)
        elseif C_Timer and type(C_Timer.After) == "function" then
            refreshTimer = true
            C_Timer.After(WATCH_THROTTLE, function()
                refreshTimer = nil
                RefreshShieldBar()
            end)
        else
            RefreshShieldBar()
        end
    end

    local function EnsureWatchFrame()
        if shieldWatchFrame then
            return shieldWatchFrame
        end
        shieldWatchFrame = CreateFrame("Frame")
        shieldWatchFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
            if event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "PLAYER_TARGET_CHANGED" then
                if event == "PLAYER_TARGET_CHANGED" then
                    watchedBossUnit = nil
                    shieldMaxValue = nil
                end
                if watchActive then
                    ScheduleRefresh()
                end
            elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
                if waitingForShieldChannelStart == true
                    and type(unit) == "string"
                    and unit:match("^boss%d$") then
                    waitingForShieldChannelStart = false
                    watchedBossUnit = unit
                    watchedCastGUID = castGUID
                    CancelTimer(startWatchTimer)
                    startWatchTimer = nil
                    if C_Timer and type(C_Timer.NewTimer) == "function" then
                        startWatchTimer = C_Timer.NewTimer(0.1, function()
                            startWatchTimer = nil
                            if IsRaviActive() then
                                StartShieldWatch(unit, castGUID)
                            end
                        end)
                    elseif C_Timer and type(C_Timer.After) == "function" then
                        startWatchTimer = true
                        C_Timer.After(0.1, function()
                            startWatchTimer = nil
                            if IsRaviActive() then
                                StartShieldWatch(unit, castGUID)
                            end
                        end)
                    else
                        StartShieldWatch(unit, castGUID)
                    end
                end
            elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                if watchActive
                    and type(unit) == "string"
                    and unit == watchedBossUnit
                    and (watchedCastGUID == nil or castGUID == watchedCastGUID) then
                    HideShieldBar()
                end
            elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
                if FORCE_TARGET_TEST == true and event == "PLAYER_ENTERING_WORLD" then
                    watchActive = true
                    ScheduleRefresh()
                else
                    HideShieldBar()
                end
            end
        end)
        return shieldWatchFrame
    end

    StartShieldWatch = function(unit, castGUID)
        HideShieldBar()
        watchActive = true
        watchedBossUnit = unit or watchedBossUnit
        watchedCastGUID = castGUID or watchedCastGUID
        shieldMaxValue = nil
        EnsureWatchFrame():RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
        EnsureWatchFrame():RegisterEvent("PLAYER_TARGET_CHANGED")
        EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
        EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "boss1", "boss2", "boss3", "boss4", "boss5")
        EnsureWatchFrame():RegisterEvent("ENCOUNTER_END")
        EnsureWatchFrame():RegisterEvent("PLAYER_ENTERING_WORLD")
        if FORCE_TARGET_TEST == true or watchedBossUnit then
            ScheduleRefresh()
        end
    end

    local function ArmShieldChannelWatch(delay)
        CancelTimer(armChannelTimer)
        armChannelTimer = nil

        local wait = math.max(0, tonumber(delay) or 0)
        if wait <= 0.05 then
            waitingForShieldChannelStart = true
            EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
            return
        end

        if C_Timer and type(C_Timer.NewTimer) == "function" then
            armChannelTimer = C_Timer.NewTimer(wait, function()
                armChannelTimer = nil
                if IsRaviActive() then
                    waitingForShieldChannelStart = true
                    EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
                end
            end)
        elseif C_Timer and type(C_Timer.After) == "function" then
            armChannelTimer = true
            C_Timer.After(wait, function()
                armChannelTimer = nil
                if IsRaviActive() then
                    waitingForShieldChannelStart = true
                    EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
                end
            end)
        else
            waitingForShieldChannelStart = true
            EnsureWatchFrame():RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "boss1", "boss2", "boss3", "boss4", "boss5")
        end
    end

    local function OnFixedAIEventScheduled(_, payload)
        if tonumber(type(payload) == "table" and payload.encounterID or nil) ~= ENCOUNTER_ID then
            return
        end
        if tonumber(type(payload) == "table" and payload.eventID or nil) ~= EVENT_DEVOUR then
            return
        end
        if not IsRaviActive() then
            return
        end
        ArmShieldChannelWatch(math.max(0, (tonumber(payload and payload.remaining) or 0) - 1))
    end

    function Mod:RefreshVisuals()
        local bar = GetExtraShieldBar()
        if bar and bar.RefreshVisuals then
            bar:RefreshVisuals()
        end
        if watchActive then
            RefreshShieldBar()
        end
    end

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_SCHEDULED", "ExBoss_Ravi_ShieldWatch_Scheduled", OnFixedAIEventScheduled)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_Ravi_ShieldWatch_Reset", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then
                HideShieldBar()
                if FORCE_TARGET_TEST == true then
                    StartShieldWatch()
                end
            end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_Ravi_ShieldWatch_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID or IsRaviActive() then
                HideShieldBar()
            end
        end)
        ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss_Ravi_ShieldWatch_PEW", function()
            if FORCE_TARGET_TEST == true then
                StartShieldWatch()
            else
                HideShieldBar()
            end
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3456,
    dungeon = { key = "altar_of_fangs", name = "Altar of Fangs", zhCN = "毒牙祭坛" },
    boss = { key = "rav_i", name = "Rav'i", zhCN = "拉维" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
