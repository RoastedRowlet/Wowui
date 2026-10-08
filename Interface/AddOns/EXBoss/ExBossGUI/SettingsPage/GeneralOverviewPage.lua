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
local refreshingTimelineBars = false

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

-- [卡片/Grid 迁移边界：通用设置]
-- 允许：只按共享规范调整下列声明的 x/y/w/h 与自然卡片分组。
-- 禁止：修改 key/type/parentKey/subKey、字段业务次序、CVar/Store 写回与即时刷新回调。
-- header/背景类声明不自动拥有相邻控件；迁移后仍须让原 DB 路径与回调负责保存。
local LAYOUT = {
    version = 1,
    title = L["通用设置"],
    sections = {
        { kind = "settings", id = "general", title = L["通用设置"],
            items = {
                { key = "timelineBars", type = "select", multiple = true, label = L["时间轴样式选择"], options = { { value = "bun", label = L["束状条"] }, { value = "timer", label = L["计时条"] } }, parentKey = "ui.general" },
                { key = "bunBarSources", type = "select", multiple = true, label = L["束状条显示"], options = { { value = "boss", label = L["Boss 技能"] }, { value = "trash", label = L["小怪技能"] } }, parentKey = "ui.general" },
                { key = "timerBarSources", type = "select", multiple = true, label = L["计时条显示"], options = { { value = "boss", label = L["Boss 技能"] }, { value = "trash", label = L["小怪技能"] } }, parentKey = "ui.general" },
                { key = "disableBlizzardEncounterTimeline", type = "switch", label = L["关闭暴雪原生计时条"], parentKey = "ui.general" },
                { key = "disableEXBossInRaid", type = "switch", label = L["团本中禁用 EXBoss"], parentKey = "ui.general" },
                { key = "disableAuraSoundRegistration", type = "switch", label = L["关闭光环语音注册（重载后生效）"], parentKey = "voice.global" },
                { key = "hideTankBossAlertsForDps", type = "switch", label = L["DPS职责下不提示坦克技能"], parentKey = "ui.general" },
                { key = "hideTankBossAlertsForHeal", type = "switch", label = L["治疗职责下不提示坦克技能"], parentKey = "ui.general" },
                { key = "showSpellOccurrenceCount", type = "switch", label = L["法术名称显示次数"], parentKey = "ui.general" },
                { key = "encounterWarningsEnabled", type = "switch", label = L["开启暴雪中央文字预警（注意：如果关闭会导致语音不工作）"], parentKey = "ui.general" },
                { key = "encounterWarningSoundsEnabled", type = "switch", label = L["开启中央文字预警提示音（预设叮一声）"], parentKey = "ui.general" },
                { key = "enableBlizzardHintCountdown", type = "switch", label = L["暴雪时间轴模式启用5秒倒数"], parentKey = "ui.general" },
                { key = "enableBlizzardTimelineInRaid", type = "switch", label = L["团本中仍开启暴雪原生计时条"], parentKey = "ui.general" },
            } },
        { kind = "settings", id = "auto-gossip", title = L["自动对话"],
            items = {
                { key = "autoGossipEnabled", type = "switch", label = L["启用自动对话"], parentKey = "autoGossip", subKey = "enabled" },
                { key = "autoGossipAcademyBuff", type = "switch", label = L["[大秘境] 自动对话学院(AA)BUFF"], parentKey = "autoGossip", subKey = "academyBuff" },
                { key = "autoGossipCaveCauldron", type = "switch", label = L["[大秘境] 自动对话洞窟(MC)大锅BUFF"], parentKey = "autoGossip", subKey = "caveCauldron" },
                { key = "autoGossipPosRescue", type = "switch", label = L["[大秘境] 自动对话萨隆矿坑救人(POS)"], parentKey = "autoGossip", subKey = "posRescue" },
                { key = "autoGossipNpxBuff", type = "switch", label = L["[大秘境] 自动对话节点(NPX)BUFF"], parentKey = "autoGossip", subKey = "npxBuff" },
            } },
    },
}

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
    -- 团本例外是独立的新选择；没有旧叶可以推断，默认保持原有行为（不例外）。
    if general.enableBlizzardTimelineInRaid == nil then
        general.enableBlizzardTimelineInRaid = false
    else
        general.enableBlizzardTimelineInRaid = (general.enableBlizzardTimelineInRaid == true)
    end

    local voice = EXBOSS12S2.voice.global
    voice.channel = tostring(voice.channel or "Master")
    voice.volume = tonumber(voice.volume) or 1.0
    voice.disableAuraSoundRegistration = (voice.disableAuraSoundRegistration == true)
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

local function ApplyBarModeChange()
    local sched = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
    sched:RefreshTimelineBars()
end

local function RefreshTimelineBarControls()
    local dropdown = Page._cardSession and Page._cardSession:GetWidget("general", "timelineBars")
    if dropdown then
        dropdown._selections = ExBoss.DisplayPolicy.GetTimelineBars()
        dropdown:RefreshSelectionDisplay()
    end
    for _, key in ipairs({ "TimerBarPage", "BunBarPage", "GlobalSettingsPage" }) do
        local page = ExBoss.UI.Panel[key]
        if page and page.RefreshTimelineBarControls then page:RefreshTimelineBarControls() end
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

local function RefreshActiveSurfaces(_, changedPath, phase)
    if changedPath == "ui.general.timelineBars"
        or changedPath == "ui.general.timelineBars.bun"
        or changedPath == "ui.general.timelineBars.timer" then
        if refreshingTimelineBars then return end
        refreshingTimelineBars = true
        -- The shared multi-select's Clear action removes selection keys.
        -- Persist both off states explicitly so reload remains idempotent.
        local bars = ExBoss.DisplayPolicy.GetTimelineBars()
        bars.bun = bars.bun == true
        bars.timer = bars.timer == true
        ApplyBarModeChange()
        RefreshTimelineBarControls()
        refreshingTimelineBars = false
        return
    end
    local rootDB = EnsureRootDB()
    if changedPath == "voice.global.disableAuraSoundRegistration" then
        -- 这个开关只保存下次加载要采用的值；当前会话不刷新或移除注册。
        return
    end
    if changedPath == "ui.general.bunBarSources" or changedPath == "ui.general.timerBarSources" then
        -- Scheduler 在每个既有分发点读取该选择；不需要也不能重启当前 Boss 时间轴。
        return
    end
    local general = rootDB.ui and rootDB.ui.general or {}
    WriteCVarValue("encounterWarningsEnabled", general.encounterWarningsEnabled == true and "1" or "0")
    WriteCVarValue("Sound_EnableEncounterWarningsSounds", general.encounterWarningSoundsEnabled == true and "1" or "2")
    WriteCVarValue("encounterTimelineEnabled",
        ExBoss.DisplayPolicy.ShouldEnableBlizzardEncounterTimeline(general) and "1" or "0")
    ApplySpellCountDisplayChange()
    ApplyBlizzardHintCountdownChange()
    ApplyBarModeChange()
    ApplyBossSceneToggleChange()
    local mod = ExBoss and ExBoss.AutoGossip
    if mod and type(mod.NotifySettingsChanged) == "function" then mod.NotifySettingsChanged() end
    ApplyVoiceOverrides()
end

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

-- [混合函数边界] Page:Render 内只可调整 sf/sc 的锚点、宽高与布局挂载；rootDB、ActivePage、延迟 guard 和 Grid:Render 绑定禁止修改。
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
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
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
        if Page._cardSession and type(Page._cardSession.Release) == "function" then
            Page._cardSession:Release()
            Page._cardSession = nil
        end
        Page._cardSession = Grid:MountCards(sc, LAYOUT, {
            pageId = MODULE_KEY,
            regionId = "general-overview",
            config = rootDB,
            moduleKey = MODULE_KEY,
            scrollFrame = sf,
        })
    end)
end
