---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- Modules/Boss/Mechanics/HealthThreshold.lua
-- 血量阈值 / 转阶段提示通用模块
--
-- 本模块只解释声明字段，不写具体 Boss 特判。
-- Boss 规则来源：ExBoss.BossEncounters:Get(encounterID).healthThresholds
-- 旧全局血量表已退场，避免 Boss 声明与数据表双来源叠加。
-- 显示输出：默认中央文字公告(中)。
-- 固定转阶段预设：{ threshold = 66, preset = "phase_transition", unit = "boss1" }
-- 自动输出 5/4/3/2/1.5/1/0.8/0.6/0.4/0.2% 倒数，随后显示阶段转换。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}
ExBoss.Modules.Boss.HealthThreshold = ExBoss.Modules.Boss.HealthThreshold or {}

local Mod = ExBoss.Modules.Boss.HealthThreshold
local MODULE_KEY = "ExBoss.Boss.HealthThreshold"

local TICK_SECONDS = 0.50
local DEFAULT_BOSS_UNIT = "boss1"
-- 所有首领共用的转阶段倒数点；按血量由高至低依次显示。
local PHASE_TRANSITION_LEAD_STEPS = { 5, 4, 3, 2, 1.5, 1, 0.8, 0.6, 0.4, 0.2 }
local PHASE_TRANSITION_PRESET = "phase_transition"
local PHASE_TRANSITION_LEAD_TEXT = "转阶段 {lead}%"
local PHASE_TRANSITION_TEXT = "阶段转换"

local activeBossEncounterID = nil
local activeTrashUnits = {}
local ticker = nil
local runtimeRules = { boss = {}, trash = {} }

local function LText(key)
    local L = ExBoss and ExBoss.L
    if L then
        return L[key]
    end
    return key
end

local function NormalizeText(v)
    if v == nil then return "" end
    return tostring(v)
end

local function FormatRuleText(rule, lead)
    local text = NormalizeText(rule and rule.text)
    if text == "" then
        text = "{lead}%"
    else
        text = LText(text)
    end
    if lead then
        if text:find("{lead}", 1, true) then
            text = text:gsub("{lead}", tostring(lead))
        elseif text:find("%d", 1, true) then
            text = string.format(text, lead)
        else
            text = text .. " > " .. tostring(lead) .. "%"
        end
    end
    return text
end

local function ExpandPhaseTransitionPreset(rule, out, defaultOutput)
    local threshold = tonumber(rule.threshold or rule.at)
    if not threshold then
        return
    end

    local unit = tostring(rule.unit or DEFAULT_BOSS_UNIT)
    local output = tostring(rule.output or defaultOutput or "central_medium")
    local leadText = NormalizeText(rule.text)
    if leadText == "" then
        leadText = PHASE_TRANSITION_LEAD_TEXT
    end

    for index, lead in ipairs(PHASE_TRANSITION_LEAD_STEPS) do
        local nextLead = tonumber(PHASE_TRANSITION_LEAD_STEPS[index + 1]) or 0
        out[#out + 1] = {
            unit = unit,
            min = threshold + nextLead,
            max = threshold + lead,
            text = FormatRuleText({ text = leadText }, lead),
            output = output,
        }
    end

    local transitionText = NormalizeText(rule.transitionText or rule.endText)
    if transitionText == "" then
        transitionText = PHASE_TRANSITION_TEXT
    end
    local transitionWindow = tonumber(rule.transitionWindow or rule.endWindow) or 1
    if transitionWindow > 0 then
        out[#out + 1] = {
            unit = unit,
            min = threshold - transitionWindow,
            max = threshold,
            text = LText(transitionText),
            output = output,
        }
    end
end

local function ExpandRule(rule, out, defaultOutput)
    if type(rule) ~= "table" then
        return
    end
    if rule[3] ~= nil and rule[4] ~= nil then
        local tupleRule = {
            min = rule[3],
            max = rule[4],
            text = rule[5],
            unit = rule.unit or rule[6],
            output = rule.output,
        }
        return ExpandRule(tupleRule, out, defaultOutput)
    end

    if tostring(rule.preset or "") == PHASE_TRANSITION_PRESET then
        return ExpandPhaseTransitionPreset(rule, out, defaultOutput)
    end

    local minPct = tonumber(rule.min or rule.minPct)
    local maxPct = tonumber(rule.max or rule.maxPct)
    if minPct and maxPct and maxPct > minPct then
        out[#out + 1] = {
            unit = tostring(rule.unit or DEFAULT_BOSS_UNIT),
            min = minPct,
            max = maxPct,
            text = NormalizeText(rule.text),
            output = tostring(rule.output or defaultOutput or "central_medium"),
        }
        return
    end

    local threshold = tonumber(rule.threshold or rule.at)
    local leadMax = tonumber(rule.lead or rule.leadPct)
    if not threshold or not leadMax or leadMax <= 0 then
        return
    end
    for lead = math.floor(leadMax), 1, -1 do
        out[#out + 1] = {
            unit = tostring(rule.unit or DEFAULT_BOSS_UNIT),
            min = threshold + lead - 1,
            max = threshold + lead,
            text = FormatRuleText(rule, lead),
            output = tostring(rule.output or defaultOutput or "central_medium"),
        }
    end

    local transitionText = NormalizeText(rule.transitionText or rule.endText)
    if transitionText ~= "" then
        transitionText = LText(transitionText)
        local transitionWindow = tonumber(rule.transitionWindow or rule.endWindow) or 1
        if transitionWindow > 0 then
            out[#out + 1] = {
                unit = tostring(rule.unit or DEFAULT_BOSS_UNIT),
                min = threshold - transitionWindow,
                max = threshold,
                text = transitionText,
                output = tostring(rule.output or defaultOutput or "central_medium"),
            }
        end
    end
end

local function AddRuntimeRules(kind, id, out)
    local bucket = runtimeRules[kind]
    local rules = type(bucket) == "table" and bucket[id] or nil
    if type(rules) == "table" then
        for _, rule in ipairs(rules) do
            ExpandRule(rule, out, "central_medium")
        end
    end
end

local function AddEncounterRules(encounterID, out)
    local registry = ExBoss and ExBoss.BossEncounters
    local def = registry and registry.Get and registry:Get(encounterID)
    local rules = def and def.healthThresholds
    if type(rules) ~= "table" then
        return
    end
    for _, rule in ipairs(rules) do
        ExpandRule(rule, out, "central_medium")
    end
end

local function GetRules(kind, id)
    id = tonumber(id)
    if not id then
        return {}
    end
    kind = string.lower(kind or "")

    local out = {}
    if kind == "boss" then
        AddEncounterRules(id, out)
    end
    AddRuntimeRules(kind, id, out)
    return out
end

local function HasActiveRules()
    if activeBossEncounterID and #GetRules("boss", activeBossEncounterID) > 0 then
        return true
    end
    for _, row in pairs(activeTrashUnits) do
        if row and #GetRules("trash", row.npcID) > 0 then
            return true
        end
    end
    return false
end

local function BuildActiveEntries()
    local entries = {}
    if activeBossEncounterID then
        local rules = GetRules("boss", activeBossEncounterID)
        for i = 1, #rules do
            local rule = rules[i]
            if rule.output == "central_medium" then
                entries[#entries + 1] = {
                    unit = rule.unit or DEFAULT_BOSS_UNIT,
                    min = rule.min,
                    max = rule.max,
                    text = rule.text,
                }
            end
        end
    end
    for unit, row in pairs(activeTrashUnits) do
        if row and row.npcID and UnitExists(unit) and not UnitIsDead(unit) then
            local rules = GetRules("trash", row.npcID)
            for i = 1, #rules do
                local rule = rules[i]
                if rule.output == "central_medium" then
                    entries[#entries + 1] = {
                        unit = unit,
                        min = rule.min,
                        max = rule.max,
                        text = rule.text,
                    }
                end
            end
        else
            activeTrashUnits[unit] = nil
        end
    end
    return entries
end

local function ClearOutput()
    local medium = ExBoss and ExBoss.UI and ExBoss.UI.FlashTextMedium
    if medium and medium.ClearHealthEntries then
        medium:ClearHealthEntries()
    end
end

local function Refresh()
    local medium = ExBoss and ExBoss.UI and ExBoss.UI.FlashTextMedium
    if not medium or not medium.ShowHealthEntries then
        return
    end
    medium:ShowHealthEntries(BuildActiveEntries())
end

local function StopTickerIfIdle()
    if HasActiveRules() then
        return
    end
    if ticker and ticker.Cancel then
        ticker:Cancel()
    end
    ticker = nil
    ClearOutput()
end

local function EnsureTicker()
    if ticker then
        return
    end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end
    ticker = C_Timer.NewTicker(TICK_SECONDS, function()
        if HasActiveRules() then
            Refresh()
        else
            StopTickerIfIdle()
        end
    end)
    Refresh()
end

function Mod:ActivateBoss(encounterID)
    activeBossEncounterID = tonumber(encounterID)
    if HasActiveRules() then
        EnsureTicker()
    else
        StopTickerIfIdle()
    end
end

function Mod:DeactivateBoss()
    activeBossEncounterID = nil
    StopTickerIfIdle()
end

function Mod:ActivateTrashUnit(unit, mapID, npcID)
    if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then
        return
    end
    npcID = tonumber(npcID)
    if not npcID or #GetRules("trash", npcID) == 0 then
        activeTrashUnits[unit] = nil
        StopTickerIfIdle()
        return
    end
    activeTrashUnits[unit] = {
        mapID = tonumber(mapID),
        npcID = npcID,
    }
    EnsureTicker()
end

function Mod:DeactivateTrashUnit(unit)
    if type(unit) == "string" then
        activeTrashUnits[unit] = nil
    end
    StopTickerIfIdle()
end

function Mod:DeactivateAllTrashUnits()
    for unit in pairs(activeTrashUnits) do
        activeTrashUnits[unit] = nil
    end
    StopTickerIfIdle()
end

function Mod:RegisterRule(kind, id, minPct, maxPct, text, unit)
    kind = tostring(kind or ""):lower()
    id = tonumber(id)
    if kind ~= "boss" and kind ~= "trash" then
        return false
    end
    if not id or not tonumber(minPct) or not tonumber(maxPct) then
        return false
    end
    runtimeRules[kind][id] = runtimeRules[kind][id] or {}
    runtimeRules[kind][id][#runtimeRules[kind][id] + 1] = {
        min = tonumber(minPct),
        max = tonumber(maxPct),
        text = tostring(text or ""),
        unit = unit,
        output = "central_medium",
    }
    if HasActiveRules() then
        EnsureTicker()
    end
    return true
end

function Mod:RegisterLeadRule(kind, id, threshold, lead, text, unit)
    kind = tostring(kind or ""):lower()
    id = tonumber(id)
    if kind ~= "boss" and kind ~= "trash" then
        return false
    end
    if not id or not tonumber(threshold) or not tonumber(lead) then
        return false
    end
    runtimeRules[kind][id] = runtimeRules[kind][id] or {}
    runtimeRules[kind][id][#runtimeRules[kind][id] + 1] = {
        threshold = tonumber(threshold),
        lead = tonumber(lead),
        text = tostring(text or ""),
        unit = unit,
        output = "central_medium",
    }
    if HasActiveRules() then
        EnsureTicker()
    end
    return true
end

function Mod:RefreshVisuals()
    Refresh()
end

local function Register(event, owner, func)
    if ExwindTools.RegisterEvent then
        ExwindTools:RegisterEvent(event, owner, func)
    end
end

Register("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.7, function()
        StopTickerIfIdle()
    end)
end)

Register("ENCOUNTER_START", MODULE_KEY .. "_boss", function(_, encounterID)
    Mod:ActivateBoss(encounterID)
end)

Register("ENCOUNTER_END", MODULE_KEY .. "_boss", function()
    Mod:DeactivateBoss()
end)

Register("NAME_PLATE_UNIT_REMOVED", MODULE_KEY .. "_trash", function(_, unit)
    Mod:DeactivateTrashUnit(unit)
end)
