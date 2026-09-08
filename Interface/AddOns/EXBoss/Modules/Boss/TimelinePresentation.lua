---@diagnostic disable: undefined-global

ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local Presentation = {}
ExBoss.Modules.Boss.TimelinePresentation = Presentation

local ModeRules = ExBoss.Modules.Boss.TimelineModeRules
local SPECIAL_CAST_OBSERVE_ORDINALS = {
    [106] = 3,
}
local SPECIAL_CAST_OBSERVE_WINDOW_AFTER = {
    [106] = 10,
    [296] = 3,
    [308] = 3,
    -- 2623: 两只 Boss 的实际施法可能较预测时间延后，延长后半段观察窗口。
    [889] = 5,
    [890] = 5,
    [894] = 5,
}

local function NormalizeText(v)
    if type(v) ~= "string" then
        return ""
    end
    local s = v:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function LocalizeDynamicText(v)
    if ExBoss and ExBoss.Locale and type(ExBoss.Locale.TranslateBossDynamicText) == "function" then
        return tostring(ExBoss.Locale.TranslateBossDynamicText(v) or "")
    end
    return tostring(v or "")
end

local _encounterEventIndexCache = nil
local _encounterEventIndexSource = nil

local function BuildEncounterEventIndex()
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if _encounterEventIndexCache and _encounterEventIndexSource == data then
        return _encounterEventIndexCache
    end
    local out = {}
    if type(data) == "table" and type(data.maps) == "table" then
        for _, mapRow in pairs(data.maps) do
            if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
                for _, bossRow in pairs(mapRow.bosses) do
                    if type(bossRow) == "table" and type(bossRow.events) == "table" then
                        for rawEventID, eventRow in pairs(bossRow.events) do
                            local eid = tonumber(rawEventID) or
                            (type(eventRow) == "table" and tonumber(eventRow.eventID))
                            if eid and type(eventRow) == "table" then
                                out[eid] = eventRow
                            end
                        end
                    end
                end
            end
        end
    end
    _encounterEventIndexCache = out
    _encounterEventIndexSource = data
    return out
end

local function GetEncounterEventRow(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    return BuildEncounterEventIndex()[eid]
end

local function GetRuntimeEvent(eventID)
    local eid = tonumber(eventID)
    if not eid then
        return nil
    end
    local _, instanceType = GetInstanceInfo()
    local runtime = ExBoss and (instanceType == "raid" and ExBoss.RuntimeRaid or ExBoss.RuntimeMplus)
    if type(runtime) ~= "table" or type(runtime.events) ~= "table" then
        return nil
    end
    -- Existing profiles can contain either numeric event IDs or string event
    -- IDs after import.  The runtime reader must accept both representations.
    return runtime.events[eid] or runtime.events[tostring(eid)]
end

local function ResolveTimerEventID(timer)
    if type(timer) ~= "table" then
        return nil
    end
    return tonumber(timer.eventID) or tonumber(timer.timelineEventID)
end

function Presentation:GetRuntimeVoiceConfig(timer)
    local row = GetRuntimeEvent(ResolveTimerEventID(timer))
    return type(row) == "table" and type(row.triggers) == "table" and row or nil
end

function Presentation:GetRuntimeColorConfig(timer)
    local eventID = ResolveTimerEventID(timer)
    local row = GetRuntimeEvent(eventID)
    local color = type(row) == "table" and type(row.color) == "table" and row.color or nil
    local trace = ExBoss and ExBoss.ColorTrace
    if trace and type(trace.Record) == "function" then
        local _, instanceType = GetInstanceInfo()
        local note = "scene=" .. tostring(instanceType)
            .. " row=" .. tostring(type(row) == "table")
            .. " color=" .. tostring(type(color) == "table")
        if type(color) == "table" then
            note = note .. " enabled=" .. tostring(color.enabled ~= false)
                .. " scheme=" .. tostring(color.scheme or "")
                .. " custom=" .. tostring(color.useCustom == true)
        end
        trace:Record("Timeline.ColorConfig", { id = timer and timer.id, eventID = eventID }, color, note)
    end
    return color
end

function Presentation:GetRuntimeCastObserveUnitFilter(timer)
    local row = GetRuntimeEvent(ResolveTimerEventID(timer))
    local rules = type(row) == "table" and row.rules or nil
    local castWindow = type(rules) == "table" and rules.castWindow or nil
    if type(castWindow) ~= "table" then return nil end
    return castWindow.observeUnit or castWindow.observeUnits
end

local function ResolveLinkedTextFields(row)
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.ResolveLinkedTextFields) == "function" then
        local ok, resolved = pcall(cfg.ResolveLinkedTextFields, cfg, row)
        if ok and type(resolved) == "table" then
            return resolved
        end
    end
    return {
        preAlertText = "",
        timerBarRenameText = "",
    }
end

local function ResolveDefaultCentralText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    local text = NormalizeText(timer.screenText)
    if text ~= "" then
        return LocalizeDynamicText(text)
    end
    text = NormalizeText(timer.displayName)
    if text ~= "" then
        return LocalizeDynamicText(text)
    end
    return ""
end

local function ResolveDefaultPreAlertLead(timer)
    if type(timer) ~= "table" then
        return 0
    end
    local castTime = tonumber(timer.castTime)
    local preAlertTime = tonumber(timer.preAlertTime)
    if castTime and preAlertTime then
        return math.max(0, castTime - preAlertTime)
    end
    return tonumber(timer.timelinePreAlertLead) or 0
end

local function IsBlizzardHintCountdownEnabledByGlobal()
    local db = _G.EXBOSS12S2
    local general = db and db.ui and db.ui.general
    if type(general) ~= "table" then
        return true
    end
    if general.enableBlizzardHintCountdown == nil then
        return true
    end
    return general.enableBlizzardHintCountdown == true
end

-- This is deliberately a display-time rule, not an event configuration
-- change.  Tank, DPS, and healer slots may all point at one Author/User
-- configuration, so setting row.enabled = false here would also disable the
-- event when the player later changes back to tank.  TrashCD calls this same
-- predicate for its Excel-backed eventType; do not create a second role rule.
function Presentation.ShouldSuppressTankEventForCurrentRole(eventRow)
    if type(eventRow) ~= "table" or eventRow.eventType ~= "坦克" then
        return false
    end

    local state = _G.ExwindTools and _G.ExwindTools.State
    local role = tostring(state and state.RoleKey or ""):lower()
    local general = _G.EXBOSS12S2 and _G.EXBOSS12S2.ui and _G.EXBOSS12S2.ui.general
    if type(general) ~= "table" then
        return false
    end

    if role == "dps" then
        return general.hideTankBossAlertsForDps == true
    end
    if role == "heal" or role == "healer" then
        return general.hideTankBossAlertsForHeal == true
    end
    return false
end

function Presentation:Resolve(timer, explicitMode)
    local mode = (ModeRules and ModeRules:ResolveMode(timer, explicitMode)) or "fixed"
    local rules = (ModeRules and ModeRules:Get(mode)) or {}
    local capabilities = type(rules.capabilities) == "table" and rules.capabilities or {}
    local sources = type(rules.sources) == "table" and rules.sources or {}
    local resolvedEventID = ResolveTimerEventID(timer)
    local row = GetRuntimeEvent(resolvedEventID)
    local encounterRow = GetEncounterEventRow(resolvedEventID)

    local perEventCentralEnabled = false
    if type(row) == "table" then
        perEventCentralEnabled = (row.centralEnabled == true)
    elseif type(timer) == "table" then
        perEventCentralEnabled = (timer.centralEnabled == true)
    end

    local out = {
        mode = mode,
        usePerEventEnabled = capabilities.perEventEnabled ~= false,
        eventEnabled = true,
        useEventColor = capabilities.eventColor ~= false,
        useCentralText = capabilities.centralText == true,
        usePreAlertText = capabilities.preAlertText == true,
        useTimerBarRename = capabilities.timerBarRename == true,
        useRingProgress = capabilities.ringProgress == true,
        useOccurrenceCount = capabilities.occurrenceCount ~= false,
        useBlizzardHintCountdown = false,
        useBlizzardHintCentral = false,
        eventColorSource = tostring(sources.eventColor or "own"),
        countdownSource = tostring(sources.countdown or "own"),
        centralSource = tostring(sources.central or "own"),
        castVoiceSource = tostring(sources.castVoice or "own"),
        preAlertVoiceSource = tostring(sources.preAlertVoice or "own"),
        occurrenceDisplayMode = tostring(rules.occurrenceDisplayMode or "inline"),
        blizzardHintCountdownLead = tonumber(rules.blizzardHintCountdownLead) or 5,
        blizzardHintCentralLead = tonumber(rules.blizzardHintCentralLead) or 2,
        blizzardHintCentralDuration = tonumber(rules.blizzardHintCentralDuration) or 2,
        countdownMode = "none",
        centralMode = "none",
        showBunBar = type(timer) == "table" and timer.showBunBar ~= false or true,
        showTimerBar = type(timer) == "table" and timer.showTimerBar ~= false or true,
        screenAlert = type(timer) == "table" and timer.screenAlert == true or false,
        ringEnabled = false,
        castProgressBarEnabled = false,
        ringCastCheckEnabled = false,
        ringWindowBefore = 1,
        ringWindowAfter = 2,
        ringCastDuration = nil,
        ringChannelDuration = nil,
        iconFlags = 0,
        timerTextColor = nil,
        voiceTriggers = nil,
        voiceLabel = nil,
        countdownVoiceEnabled = false,
        countdownPlayName = false,
        preAlertEnabled = false,
        preAlertLead = 0,
        preAlertText = nil,
        centralEnabled = false,
        centralLead = 0,
        centralText = nil,
        timerBarRenameEnabled = false,
        timerBarRenameText = nil,
    }

    if out.usePerEventEnabled and type(row) == "table" and row.enabled == false then
        out.eventEnabled = false
    end

    -- Only suppress the current display.  Do not write to `row`: the active
    -- profile can be shared by all three roles.
    if Presentation.ShouldSuppressTankEventForCurrentRole(encounterRow) then
        out.eventEnabled = false
    end

    if out.usePerEventEnabled and type(row) == "table" then
        if row.showBunBar ~= nil then
            out.showBunBar = (row.showBunBar == true)
        end
        if row.showTimerBar ~= nil then
            out.showTimerBar = (row.showTimerBar == true)
        end
        if row.screenAlert ~= nil then
            out.screenAlert = (row.screenAlert == true)
        end
    end

    local blizzardHintSessionEnabled = (type(timer) == "table" and timer.blizzardHintSessionEnabled == true)
    out.useBlizzardHintCountdown = (capabilities.blizzardHintCountdown == true and
        IsBlizzardHintCountdownEnabledByGlobal() and blizzardHintSessionEnabled)
    out.useBlizzardHintCentral = (capabilities.blizzardHintCentral == true and
        perEventCentralEnabled == true and blizzardHintSessionEnabled)

    if out.useRingProgress and type(row) == "table" and type(row.rules) == "table" and type(row.rules.castWindow) == "table" then
        local cw = row.rules.castWindow
        out.ringEnabled = (cw.enabled == true and cw.ringEnabled ~= false)
        out.castProgressBarEnabled = (cw.enabled == true and cw.castBarEnabled == true)
        out.castObserveLead = tonumber(cw.observeLead)
        out.castObserveOrdinal = tonumber(cw.observeOrdinal)
        if SPECIAL_CAST_OBSERVE_ORDINALS[tonumber(resolvedEventID)] then
            out.castObserveOrdinal = SPECIAL_CAST_OBSERVE_ORDINALS[tonumber(resolvedEventID)]
        end
        out.castObserveExpectedKind = NormalizeText(cw.observeExpectedKind)
        out.castProgressBarRenameEnabled = (cw.castBarRenameEnabled == true)
        if out.castProgressBarRenameEnabled then
            local rename = NormalizeText(cw.castBarRenameText)
            if rename ~= "" then
                out.castProgressBarRenameText = rename
            end
        end
        out.ringCastCheckEnabled = (cw.castCheckEnabled == true or cw.ringCastCheckEnabled == true)
        out.ringWindowBefore = tonumber(cw.windowBefore) or 1
        out.ringWindowAfter = tonumber(cw.windowAfter) or 2
        if SPECIAL_CAST_OBSERVE_WINDOW_AFTER[tonumber(resolvedEventID)] then
            out.ringWindowAfter = SPECIAL_CAST_OBSERVE_WINDOW_AFTER[tonumber(resolvedEventID)]
        end
    end

    if type(encounterRow) == "table" then
        out.ringCastDuration = tonumber(encounterRow.castDuration)
        out.ringChannelDuration = tonumber(encounterRow.channelDuration)
        out.iconFlags = tonumber(encounterRow.iconFlags) or 0
        local rawVoiceLabel = NormalizeText(encounterRow.voiceLabel)
        if rawVoiceLabel ~= "" then
            out.voiceLabel = rawVoiceLabel
        end
    end

    if out.usePerEventEnabled and type(row) == "table" and row.timerTextColorEnabled == true then
        local r = tonumber(row.timerTextColorR)
        local g = tonumber(row.timerTextColorG)
        local b = tonumber(row.timerTextColorB)
        local a = tonumber(row.timerTextColorA) or 1
        if r and g and b then
            out.timerTextColor = { r = r, g = g, b = b, a = a }
        end
    end


    if out.usePreAlertText then
        local enabled = true
        if type(row) == "table" and row.countdownEnabled ~= nil then
            enabled = (row.countdownEnabled == true)
        elseif type(row) == "table" and row.preAlertEnabled == false then
            enabled = false
        elseif type(timer) == "table" and timer.preAlertEnabled == false then
            enabled = false
        end
        out.preAlertEnabled = enabled
        if enabled then
            local lead = type(row) == "table" and tonumber(row.countdownLead) or nil
            if lead == nil then
                lead = type(row) == "table" and tonumber(row.preAlert) or nil
            end
            if lead == nil then
                lead = ResolveDefaultPreAlertLead(timer)
            end
            out.preAlertLead = math.min(30, math.max(0, tonumber(lead) or 0))
            local linked = ResolveLinkedTextFields(row)
            local txt = type(linked) == "table" and NormalizeText(linked.preAlertText) or ""
            if txt == "" and type(timer) == "table" then
                txt = NormalizeText(timer.preAlertText)
            end
            if txt ~= "" then
                out.preAlertText = LocalizeDynamicText(txt)
            end
        end
        if type(row) == "table" and row.countdownVoiceEnabled ~= nil then
            out.countdownVoiceEnabled = (row.countdownVoiceEnabled == true)
        elseif type(row) == "table" and row.countdownPlayName == true then
            out.countdownVoiceEnabled = true
        end
        if type(row) == "table" and row.countdownPlayName == true then
            out.countdownPlayName = true
        end
    end

    if out.useCentralText then
        local enabled = perEventCentralEnabled
        out.centralEnabled = enabled
        if enabled then
            out.centralLead = math.max(0,
                tonumber(type(row) == "table" and row.centralLead or (type(timer) == "table" and timer.centralLead)) or 0)
            local txt = type(row) == "table" and NormalizeText(row.centralText) or ""
            if txt == "" then
                txt = ResolveDefaultCentralText(timer)
            end
            if txt ~= "" then
                out.centralText = LocalizeDynamicText(txt)
            end
        end
    end

    if out.useTimerBarRename then
        local enabled = type(row) == "table" and row.timerBarRenameEnabled == true
        out.timerBarRenameEnabled = enabled
        if enabled then
            local linked = ResolveLinkedTextFields(row)
            local txt = type(linked) == "table" and NormalizeText(linked.timerBarRenameText) or ""
            if txt ~= "" then
                out.timerBarRenameText = LocalizeDynamicText(txt)
            end
        end
    end

    if out.useBlizzardHintCountdown == true then
        out.countdownMode = "blizzard_hint"
    elseif out.preAlertEnabled == true and out.preAlertLead > 0 and NormalizeText(out.preAlertText) ~= "" then
        out.countdownMode = "own"
    end

    if out.useBlizzardHintCentral == true then
        out.centralMode = "blizzard_hint"
    elseif out.centralEnabled == true and NormalizeText(out.centralText) ~= "" then
        out.centralMode = "own"
    end

    return out
end
