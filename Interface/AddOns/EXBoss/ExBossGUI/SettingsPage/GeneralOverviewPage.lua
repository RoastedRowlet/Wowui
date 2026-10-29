---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GeneralOverviewPage = ExBoss.UI.Panel.GeneralOverviewPage or {}
local Page = ExBoss.UI.Panel.GeneralOverviewPage

local MODULE_KEY = "ExBoss.GeneralOverview"
local refreshingTimelineBars = false

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

-- 全局设置绑定 EXBOSS12S2 根，所有提交仍交给唯一 GeneralOverview owner。
local LAYOUT = {
    version = 2,
    cards = {
        { kind = "card", id = "general", title = L["通用设置"],
            children = {
                { id = "timelineBars", kind = "control", controlType = "select", multiple = true, label = L["时间轴样式选择"], options = { { value = "bun", label = L["束状条"] }, { value = "timer", label = L["计时条"] } }, path = "ui.general.timelineBars" },
                { id = "bunBarSources", kind = "control", controlType = "select", multiple = true, label = L["束状条显示"], options = { { value = "boss", label = L["Boss 技能"] }, { value = "trash", label = L["小怪技能"] } }, path = "ui.general.bunBarSources" },
                { id = "timerBarSources", kind = "control", controlType = "select", multiple = true, label = L["计时条显示"], options = { { value = "boss", label = L["Boss 技能"] }, { value = "trash", label = L["小怪技能"] } }, path = "ui.general.timerBarSources" },
                { id = "disableBlizzardEncounterTimeline", kind = "control", controlType = "switch", label = L["关闭暴雪原生计时条"], path = "ui.general.disableBlizzardEncounterTimeline" },
                { id = "disableEXBossInRaid", kind = "control", controlType = "switch", label = L["团本中禁用 EXBoss"], path = "ui.general.disableEXBossInRaid" },
                { id = "disableAuraSoundRegistration", kind = "control", controlType = "switch", label = L["关闭光环语音注册（重载后生效）"], path = "voice.global.disableAuraSoundRegistration" },
                { id = "hideTankBossAlertsForDps", kind = "control", controlType = "switch", label = L["DPS职责下不提示坦克技能"], path = "ui.general.hideTankBossAlertsForDps" },
                { id = "hideTankBossAlertsForHeal", kind = "control", controlType = "switch", label = L["治疗职责下不提示坦克技能"], path = "ui.general.hideTankBossAlertsForHeal" },
                { id = "showSpellOccurrenceCount", kind = "control", controlType = "switch", label = L["法术名称显示次数"], path = "ui.general.showSpellOccurrenceCount" },
                { id = "encounterWarningsEnabled", kind = "control", controlType = "switch", label = L["开启暴雪中央文字预警（注意：如果关闭会导致语音不工作）"], path = "ui.general.encounterWarningsEnabled" },
                { id = "encounterWarningSoundsEnabled", kind = "control", controlType = "switch", label = L["开启中央文字预警提示音（预设叮一声）"], path = "ui.general.encounterWarningSoundsEnabled" },
                { id = "enableBlizzardHintCountdown", kind = "control", controlType = "switch", label = L["暴雪时间轴模式启用5秒倒数"], path = "ui.general.enableBlizzardHintCountdown" },
                { id = "enableBlizzardTimelineInRaid", kind = "control", controlType = "switch", label = L["团本中仍开启暴雪原生计时条"], path = "ui.general.enableBlizzardTimelineInRaid" },
            } },
        { kind = "card", id = "auto-gossip", title = L["自动对话"],
            children = {
                { id = "autoGossipEnabled", kind = "control", controlType = "switch", label = L["启用自动对话"], path = "autoGossip.enabled" },
                { id = "autoGossipAcademyBuff", kind = "control", controlType = "switch", label = L["[大秘境] 自动对话学院(AA)BUFF"], path = "autoGossip.academyBuff" },
                { id = "autoGossipCaveCauldron", kind = "control", controlType = "switch", label = L["[大秘境] 自动对话洞窟(MC)大锅BUFF"], path = "autoGossip.caveCauldron" },
                { id = "autoGossipPosRescue", kind = "control", controlType = "switch", label = L["[大秘境] 自动对话萨隆矿坑救人(POS)"], path = "autoGossip.posRescue" },
                { id = "autoGossipNpxBuff", kind = "control", controlType = "switch", label = L["[大秘境] 自动对话节点(NPX)BUFF"], path = "autoGossip.npxBuff" },
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

function Page:RefreshTimelineBarControls()
    local mountedPage = EXUI:GetModulePage(MODULE_KEY, self._scrollChild)
    local dropdown = mountedPage and mountedPage:Find("timelineBars")
    if dropdown then
        dropdown._selections = ExBoss.DisplayPolicy.GetTimelineBars()
        dropdown:RefreshSelectionDisplay()
    end
end

local function RefreshTimelineBarControls()
    Page:RefreshTimelineBarControls()
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

EXUI:RegisterSettingsPageV2(MODULE_KEY, LAYOUT)

local function RefreshPageControls()
    local mountedPage = EXUI:GetModulePage(MODULE_KEY, Page._scrollChild)
    if mountedPage then mountedPage:Refresh() end
end

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
        RefreshPageControls()
        return
    end
    if changedPath == "ui.general.bunBarSources" or changedPath == "ui.general.timerBarSources" then
        -- Scheduler 在每个既有分发点读取该选择；不需要也不能重启当前 Boss 时间轴。
        RefreshPageControls()
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
    RefreshPageControls()
end

EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

local function ReleaseSession()
    Page._renderGeneration = (Page._renderGeneration or 0) + 1
    Page._v2Session = nil
    local sc = Page._scrollChild
    if sc then
        EXUI:ReleaseModuleSettingsPage(sc)
    end
    if sc and EXUI.ActivePageFrame == sc then
        EXUI.ActivePageFrame = nil
    end
    if Page._scrollFrame and EXUI.ActivePageScrollFrame == Page._scrollFrame then
        EXUI.ActivePageScrollFrame = nil
    end
    if EXUI.CurrentModule == MODULE_KEY then
        EXUI.CurrentModule = nil
    end
end

local function SyncScrollChildWidth()
    local sf, sc = Page._scrollFrame, Page._scrollChild
    if not sf or not sc then return end
    local width = sf:GetWidth()
    if width < 100 then
        local contentWidth = Page._contentFrame and Page._contentFrame:GetWidth() or 0
        width = contentWidth >= 100 and (contentWidth - 24) or 804
    end
    sc:SetWidth(math.max(1, width))
    if Page._v2Session then Page._v2Session:Invalidate() end
end

function Page:Render(contentFrame)
    if not contentFrame then return end
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
        sf:HookScript("OnHide", ReleaseSession)
        sf:HookScript("OnSizeChanged", SyncScrollChildWidth)
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild
    Page._contentFrame = contentFrame
    ReleaseSession()
    local generation = Page._renderGeneration

    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if Page._renderGeneration ~= generation or not sf:IsShown()
            or sf:GetParent() ~= contentFrame then return end
        SyncScrollChildWidth()
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()
        EXUI.ActivePageFrame = sc
        EXUI.ActivePageScrollFrame = sf
        EXUI.CurrentModule = MODULE_KEY
        local owner = {
            binding = { moduleKey = MODULE_KEY, config = rootDB },
        }
        Page._v2Session = EXUI:MountModuleSettingsDeclarationV2(sc, MODULE_KEY, owner,
            L["通用设置"], L["全局显示模式与语音输出。"], sf)
    end)
end

function Page:Hide()
    ReleaseSession()
    if self._scrollFrame then self._scrollFrame:Hide() end
end

function Page:Refresh()
    RefreshPageControls()
end
