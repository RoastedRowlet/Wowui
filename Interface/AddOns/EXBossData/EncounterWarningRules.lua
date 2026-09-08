---@diagnostic disable: undefined-global
-- =============================================================
-- EXBossData/EncounterWarningRules.lua
-- ENCOUNTER_WARNING 图标提示的静态声明真源。
-- 这里只放规则数据；窗口、事件监听、测试命令和显示输出属于 EXBoss Runtime。
-- =============================================================

_G.EXBossData = _G.EXBossData or {}

-- 是否启用不属于声明表；由 Boss 页当前角色/职责的勾选决定。
-- severity：0 = Low、1 = Medium、2 = High（Blizzard EncounterEventSeverity）。
-- windowBefore/windowAfter：相对 event 预计结束时刻的秒数，区间两端均包含。
-- 图标与文字不写入声明；显示时由 spellID 通过客户端法术 API 取得。
local Rules = {
    {
        -- encounterID = 1234, -- 可选；省略时匹配所有首领战。
        eventID = 867,
        severity = 1,
        windowBefore = 1,
        windowAfter = 3,
        spellID = 372851,
        duration = 4.5,
    },
}

_G.EXBossData.EncounterWarningRules = Rules

function _G.EXBossData.GetEncounterWarningRules()
    return Rules
end

function _G.EXBossData.HasEncounterWarningRule(encounterID, eventID)
    local eid = tonumber(eventID)
    local encounter = encounterID ~= nil and tonumber(encounterID) or nil
    if not eid then
        return false
    end
    for _, rule in ipairs(Rules) do
        if type(rule) == "table" and tonumber(rule.eventID) == eid then
            local ruleEncounter = rule.encounterID ~= nil and tonumber(rule.encounterID) or nil
            if ruleEncounter == nil or ruleEncounter == encounter then
                return true
            end
        end
    end
    return false
end
