---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GeneralOverviewPage = ExBoss.UI.Panel.GeneralOverviewPage or {}
local Page = ExBoss.UI.Panel.GeneralOverviewPage

local MODULE_KEY = "ExBoss.GeneralOverview"
local BASE_GRID_COLS = 200
local MIN_GRID_COLS = 200
local MAX_GRID_COLS = 200
local TARGET_CELL_PX = 18
local LAYOUT_CACHE = {}
local ACTIVE_CONTENT_FRAME

local CHANNEL_OPTIONS = {
    { "Master",   "Master" },
    { "SFX",      "SFX" },
    { "Dialog",   "Dialog" },
    { "Music",    "Music" },
    { "Ambience", "Ambience" },
}

local BAR_MODE_OPTIONS = {
    { L["仅束状条"], "bun" },
    { L["两者都启用"], "both" },
    { L["仅计时条"], "timer" },
    { L["两者都隐藏"], "none" },
}

local BAR_SOURCE_OPTIONS = {
    { L["Boss 技能"], "boss" },
    { L["小怪技能"], "trash" },
}

local function ReadCVarValue(name)
    local key = tostring(name or "")
    if key == "" then
        return nil
    end

    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, key)
    end
    if (not ok or value == nil) and type(GetCVar) == "function" then
        ok, value = pcall(GetCVar, key)
    end
    if not ok or value == nil then
        return nil
    end
    local s = tostring(value)
    if s == "" then
        return nil
    end
    return s
end

local function WriteCVarValue(name, value)
    local key = tostring(name or "")
    local s = tostring(value or "")
    if key == "" or s == "" then
        return false
    end

    local ok = false
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, key, s)
        if ok then
            return true
        end
    end
    if type(SetCVar) == "function" then
        ok = pcall(SetCVar, key, s)
        if ok then
            return true
        end
    end
    return false
end

local function IsEncounterWarningsEnabled()
    local value = ReadCVarValue("encounterWarningsEnabled")
    if value == nil then
        WriteCVarValue("encounterWarningsEnabled", "1")
        return true
    end
    return value ~= "0"
end

local function IsEncounterTimelineEnabled()
    local value = ReadCVarValue("encounterTimelineEnabled")
    if value == nil then
        WriteCVarValue("encounterTimelineEnabled", "1")
        return true
    end
    return value ~= "0"
end

local function IsEncounterWarningSoundsEnabled()
    local value = ReadCVarValue("Sound_EnableEncounterWarningsSounds")
    if value == nil then
        return true
    end
    return value ~= "2"
end

local LAYOUT = {
    { key = "header_8111", type = "header", x = 1, y = 4, w = 200, h = 6, label = L["通用设置"], labelSize = 20 },
    { key = "barDisplayMode", type = "dropdown", x = 1, y = 17, w = 63, h = 6, label = L["时间轴样式选择"], items = BAR_MODE_OPTIONS, parentKey = "ui.general" },
    { key = "bunBarSources", type = "multiselect", x = 68, y = 17, w = 63, h = 6, label = L["束状条显示"], items = BAR_SOURCE_OPTIONS, parentKey = "ui.general" },
    { key = "timerBarSources", type = "multiselect", x = 135, y = 17, w = 63, h = 6, label = L["计时条显示"], items = BAR_SOURCE_OPTIONS, parentKey = "ui.general" },
    { key = "disableBlizzardEncounterTimeline", type = "checkbox", x = 1, y = 23, w = 76, h = 6, label = L["关闭暴雪原生计时条"], parentKey = "ui.general" },
    { key = "disableEXBossInRaid", type = "checkbox", x = 1, y = 30, w = 76, h = 6, label = L["团本中禁用 EXBoss"], parentKey = "ui.general" },
    { key = "autoDisableCAAInBoss", type = "checkbox", x = 1, y = 36, w = 76, h = 6, label = L["首领战时自动关闭战斗音频预警"], parentKey = "ui.general" },
    { key = "hideTankBossAlertsForDps", type = "checkbox", x = 1, y = 43, w = 76, h = 6, label = L["DPS职责下不提示坦克技能"], parentKey = "ui.general" },
    { key = "hideTankBossAlertsForHeal", type = "checkbox", x = 1, y = 50, w = 76, h = 6, label = L["治疗职责下不提示坦克技能"], parentKey = "ui.general" },
    { key = "showSpellOccurrenceCount", type = "checkbox", x = 1, y = 57, w = 73, h = 6, label = L["法术名称显示次数"], parentKey = "ui.general" },
    { key = "encounterWarningsEnabled", type = "checkbox", x = 1, y = 64, w = 86, h = 6, label = L["开启暴雪中央文字预警（注意：如果关闭会导致语音不工作）"], parentKey = "ui.general" },
    { key = "encounterWarningSoundsEnabled", type = "checkbox", x = 1, y = 71, w = 127, h = 6, label = L["开启中央文字预警提示音（预设叮一声）"], parentKey = "ui.general" },
    { key = "enableBlizzardHintCountdown", type = "checkbox", x = 1, y = 78, w = 44, h = 6, label = L["暴雪时间轴模式启用5秒倒数"], parentKey = "ui.general" },
    { key = "header_5292", type = "header", x = 1, y = 89, w = 197, h = 10, label = L["音频输出选项"], labelSize = 20 },
    { key = "channel", type = "dropdown", x = 1, y = 102, w = 48, h = 6, label = L["输出通道"], items = CHANNEL_OPTIONS, parentKey = "voice.global" },
    { key = "volume", type = "slider", x = 55, y = 102, w = 44, h = 6, label = L["全局音量"], min = 0, max = 1, step = 0.01, parentKey = "voice.global" },
    { key = "label_5567", type = "label", x = 1, y = 114, w = 95, h = 6, label = L["注意:声音大小请勿在此修改,若要调整声音大小请在ESC的设置面板修改"] },
    { key = "header_auto_gossip", type = "header", x = 1, y = 121, w = 197, h = 10, label = L["自动对话"], labelSize = 20 },
    { key = "autoGossipEnabled", type = "checkbox", x = 1, y = 127, w = 76, h = 6, label = L["启用自动对话"], parentKey = "autoGossip", subKey = "enabled" },
    { key = "autoGossipAcademyBuff", type = "checkbox", x = 1, y = 134, w = 102, h = 6, label = L["[大秘境] 自动对话学院(AA)BUFF"], parentKey = "autoGossip", subKey = "academyBuff" },
    { key = "autoGossipCaveCauldron", type = "checkbox", x = 1, y = 140, w = 102, h = 6, label = L["[大秘境] 自动对话洞窟(MC)大锅BUFF"], parentKey = "autoGossip", subKey = "caveCauldron" },
    { key = "autoGossipPosRescue", type = "checkbox", x = 1, y = 146, w = 102, h = 6, label = L["[大秘境] 自动对话萨隆矿坑救人(POS)"], parentKey = "autoGossip", subKey = "posRescue" },
    { key = "autoGossipNpxBuff", type = "checkbox", x = 1, y = 152, w = 102, h = 6, label = L["[大秘境] 自动对话节点(NPX)BUFF"], parentKey = "autoGossip", subKey = "npxBuff" },
}

local function NormalizeBarDisplayMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "timer" or m == "bun" or m == "both" or m == "none" then
        return m
    end
    return "bun"
end

local function EnsureBarSourceSelections(selections)
    if type(selections) ~= "table" then
        return { boss = true, trash = true }
    end
    selections.boss = (selections.boss == true)
    selections.trash = (selections.trash == true)
    return selections
end

local function EnsureRootDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ui = EXBOSS12S2.ui or {}
    EXBOSS12S2.ui.general = EXBOSS12S2.ui.general or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    EXBOSS12S2.voice.global = EXBOSS12S2.voice.global or {}
    EXBOSS12S2.autoGossip = EXBOSS12S2.autoGossip or {}

    local general = EXBOSS12S2.ui.general
    general.barDisplayMode = NormalizeBarDisplayMode(general.barDisplayMode)
    general.bunBarSources = EnsureBarSourceSelections(general.bunBarSources)
    general.timerBarSources = EnsureBarSourceSelections(general.timerBarSources)
    if general.bossAlertsEnabledMplus == nil then
        general.bossAlertsEnabledMplus = true
    else
        general.bossAlertsEnabledMplus = (general.bossAlertsEnabledMplus == true)
    end
    -- The visible checkbox is deliberately named as the user's action
    -- (disable in raid).  Preserve the old positive flag for one-time
    -- migration only, without deleting or rewriting it.
    if general.disableEXBossInRaid == nil then
        general.disableEXBossInRaid = (general.bossAlertsEnabledRaid ~= true)
    else
        general.disableEXBossInRaid = (general.disableEXBossInRaid == true)
    end
    if general.autoDisableCAAInBoss == nil then
        general.autoDisableCAAInBoss = false
    else
        general.autoDisableCAAInBoss = (general.autoDisableCAAInBoss == true)
    end
    if general.hideTankBossAlertsForDps == nil then
        general.hideTankBossAlertsForDps = true
    else
        general.hideTankBossAlertsForDps = (general.hideTankBossAlertsForDps == true)
    end
    if general.hideTankBossAlertsForHeal == nil then
        general.hideTankBossAlertsForHeal = false
    else
        general.hideTankBossAlertsForHeal = (general.hideTankBossAlertsForHeal == true)
    end
    if general.showSpellOccurrenceCount == nil then
        general.showSpellOccurrenceCount = true
    else
        general.showSpellOccurrenceCount = (general.showSpellOccurrenceCount == true)
    end
    if general.enableBlizzardHintCountdown == nil then
        general.enableBlizzardHintCountdown = true
    else
        general.enableBlizzardHintCountdown = (general.enableBlizzardHintCountdown == true)
    end
    -- These saved choices are the authority.  Read the live CVar only once
    -- for a brand-new setting; afterwards Init.lua restores this value when
    -- another addon changes the CVar.  Reading it every UI refresh would
    -- overwrite a click with the CVar's old value before we can apply it.
    if general.encounterWarningsEnabled == nil then
        general.encounterWarningsEnabled = IsEncounterWarningsEnabled()
    else
        general.encounterWarningsEnabled = (general.encounterWarningsEnabled == true)
    end
    if general.encounterWarningSoundsEnabled == nil then
        general.encounterWarningSoundsEnabled = IsEncounterWarningSoundsEnabled()
    else
        general.encounterWarningSoundsEnabled = (general.encounterWarningSoundsEnabled == true)
    end
    if general.disableBlizzardEncounterTimeline == nil then
        general.disableBlizzardEncounterTimeline = not IsEncounterTimelineEnabled()
    else
        general.disableBlizzardEncounterTimeline = (general.disableBlizzardEncounterTimeline == true)
    end

    local voice = EXBOSS12S2.voice.global
    voice.channel = tostring(voice.channel or "Master")
    voice.volume = tonumber(voice.volume) or 1.0
    if voice.volume < 0 then voice.volume = 0 end
    if voice.volume > 1 then voice.volume = 1 end

    local autoGossip = EXBOSS12S2.autoGossip
    if autoGossip.enabled == nil then
        autoGossip.enabled = true
    else
        autoGossip.enabled = (autoGossip.enabled == true)
    end
    if autoGossip.academyBuff == nil then
        autoGossip.academyBuff = true
    else
        autoGossip.academyBuff = (autoGossip.academyBuff == true)
    end
    if autoGossip.caveCauldron == nil then
        autoGossip.caveCauldron = true
    else
        autoGossip.caveCauldron = (autoGossip.caveCauldron == true)
    end
    if autoGossip.posRescue == nil then
        autoGossip.posRescue = true
    else
        autoGossip.posRescue = (autoGossip.posRescue == true)
    end
    if autoGossip.npxBuff == nil then
        autoGossip.npxBuff = true
    else
        autoGossip.npxBuff = (autoGossip.npxBuff == true)
    end

    return EXBOSS12S2
end

local function IsTimerBarEnabledByGlobal()
    local root = EnsureRootDB()
    local mode = NormalizeBarDisplayMode(root.ui.general.barDisplayMode)
    return mode == "both" or mode == "timer"
end

local function IsBunBarEnabledByGlobal()
    local root = EnsureRootDB()
    local mode = NormalizeBarDisplayMode(root.ui.general.barDisplayMode)
    return mode == "both" or mode == "bun"
end

local function ApplyBarModeChange()
    if not IsBunBarEnabledByGlobal() and ExBoss and ExBoss.UI and ExBoss.UI.BunBar and ExBoss.UI.BunBar.ReleaseAll then
        ExBoss.UI.BunBar:ReleaseAll()
    end
    if not IsTimerBarEnabledByGlobal() and ExBoss and ExBoss.UI and ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.ReleaseAll then
        ExBoss.UI.TimerBar:ReleaseAll()
    end

    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end
end

local function ApplyVoiceOverrides()
    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local function ApplySpellCountDisplayChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end
end

local function ApplyBlizzardHintCountdownChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    if sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end
end

local function ApplyBossSceneToggleChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    local bossCfg = ExBoss and ExBoss.BossConfig
    local sceneEnabled = true
    if bossCfg and type(bossCfg.IsCurrentSceneEnabled) == "function" then
        local ok, enabled = pcall(bossCfg.IsCurrentSceneEnabled, bossCfg)
        if ok then
            sceneEnabled = (enabled ~= false)
        end
    end

    if sceneEnabled == false then
        if ExBoss and ExBoss.ApplyBossAutoCAASetting then
            ExBoss.ApplyBossAutoCAASetting(false)
        end
        if sched and sched.EndBoss then
            sched:EndBoss()
        end
        if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ClearEventOverridesInMemory then
            ExBoss.Voice.Engine:ClearEventOverridesInMemory("boss scene disabled")
        end
    elseif sched and sched._running and sched.StartBoss and sched._encounterID then
        sched:StartBoss(sched._encounterID)
    end

    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then
        return BASE_GRID_COLS
    end
    local cols = math.floor(((w - 20) / TARGET_CELL_PX) + 0.5)
    if cols < MIN_GRID_COLS then cols = MIN_GRID_COLS end
    if cols > MAX_GRID_COLS then cols = MAX_GRID_COLS end
    return cols
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then
        return LAYOUT
    end
    local cached = LAYOUT_CACHE[toCols]
    if cached then
        return cached
    end

    local scale = toCols / BASE_GRID_COLS
    local function ScaleItems(src)
        local out = {}
        for _, item in ipairs(src) do
            local row = {}
            for k, v in pairs(item) do
                if k ~= "children" then
                    row[k] = v
                end
            end
            if type(item.x) == "number" and type(item.w) == "number" then
                local nx = math.floor(((item.x - 1) * scale) + 1 + 0.5)
                local nw = math.max(1, math.floor(item.w * scale + 0.5))
                if nx < 1 then nx = 1 end
                if nx > toCols then nx = toCols end
                if nx + nw - 1 > toCols then
                    nw = math.max(1, toCols - nx + 1)
                end
                row.x = nx
                row.w = nw
            end
            if type(item.children) == "table" then
                row.children = ScaleItems(item.children)
            end
            out[#out + 1] = row
        end
        return out
    end

    cached = ScaleItems(items)
    LAYOUT_CACHE[toCols] = cached
    return cached
end

ExwindTools:RegisterModuleLayout(MODULE_KEY, LAYOUT)

local function RefreshActiveSurfaces(changedPath)
    local rootDB = EnsureRootDB()
    if changedPath == "ui.general.bunBarSources" or changedPath == "ui.general.timerBarSources" then
        -- Scheduler 在每个既有分发点读取该选择；不需要也不能重启当前 Boss 时间轴。
        return
    end
    local general = rootDB.ui and rootDB.ui.general or {}
    WriteCVarValue("encounterWarningsEnabled", general.encounterWarningsEnabled == true and "1" or "0")
    WriteCVarValue("Sound_EnableEncounterWarningsSounds", general.encounterWarningSoundsEnabled == true and "1" or "2")
    WriteCVarValue("encounterTimelineEnabled", general.disableBlizzardEncounterTimeline == true and "0" or "1")
    ApplySpellCountDisplayChange()
    ApplyBlizzardHintCountdownChange()
    ApplyBarModeChange()
    ApplyBossSceneToggleChange()
    if ExBoss and ExBoss.ApplyBossAutoCAASetting then ExBoss.ApplyBossAutoCAASetting() end
    local mod = ExBoss and ExBoss.AutoGossip
    if mod and type(mod.NotifySettingsChanged) == "function" then mod.NotifySettingsChanged() end
    ApplyVoiceOverrides()
end

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid or not contentFrame then
        return
    end

    ACTIVE_CONTENT_FRAME = contentFrame

    local rootDB = EnsureRootDB()

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_GeneralOverviewScroll", contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end

        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)

        Page._scrollFrame = sf
        Page._scrollChild = sc
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild

    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if not sf:IsShown() then return end
        local w = contentFrame:GetWidth()
        if w < 100 then w = 820 end
        sc:SetWidth(w - 16)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()
        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = sc
            ExwindTools.UI.CurrentModule = MODULE_KEY
        end
        local cols = ResolveGridCols(sc:GetWidth())
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), rootDB, MODULE_KEY)
    end)
end
