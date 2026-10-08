---@diagnostic disable: undefined-global

do
    local ExwindTools = _G.ExwindTools
    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
    local ENCOUNTER_ID = 3103
    local EVENT_ID = 32
    local VULNERABILITY_PERCENT = 30
    local VULNERABILITY_KEY = "exboss:3103:32:vulnerability"
    local EXTRA_KEY = "vulnerability"

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
        local config = ExBoss.BossConfig:GetExtraConfig("mplus", ENCOUNTER_ID, EXTRA_KEY)
        if not config or config.enabled ~= true then return end
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
    local R = ExBoss and ExBoss.BossEncounters
    if not R then return end

    R:Register({
        encounterID = 3103,
        dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
        boss = { key = "xathuux_the_annihilator", name = "Xathuux the Annihilator", zhCN = "歼灭者萨祖克斯" },
        phaseAlerts = {},
        vulnerability = {},
        -- [卡片/Grid 迁移边界：3103 encounter extra]
        -- 仅 layout 的 x/y/w/h 与外层卡片呈现可按共享规范迁移；key/defaults/onChanged 及上方事件业务禁止修改。
        -- enabled 控件由统一 SettingsCard body 挂载并回收。
        extras = {
            {
                key = EXTRA_KEY,
                label = L["易伤提示"],
                icon = 135860,
                description = L["提前 4 秒提示易伤，随后显示持续 15 秒的 30% 易伤阶段倒数。"],
                defaults = { enabled = true },
                layout = {
                    version = 1,
                    title = L["易伤提示"],
                    cards = {
                        { id = "vulnerability", title = L["易伤提示"], collapsible = true,
                            placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT" },
                            content = { kind = "grid", items = {
                                { key = "enabled", type = "checkbox", x = 1, y = 1, w = 70, h = 6,
                                    label = L["启用易伤提示"] },
                            } } },
                    },
                },
                onChanged = function(config)
                    if config and config.enabled ~= true then StopVulnerability() end
                end,
            },
        },
    })
end
