---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI

ExBoss.UI.Panel.GlobalSettingsPage = ExBoss.UI.Panel.GlobalSettingsPage or {}
local Page = ExBoss.UI.Panel.GlobalSettingsPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

local leftRoot
local embeddedHostFrame
local rightScrollFrame
local rightRoot
local listScroll
local listChild
local titleText
local titleSep
local descText
local overviewSection
local barModeDropdown
local bossAlertsEnabledMplusCheck
local bossAlertsEnabledRaidCheck
local autoDisableCAAInBossCheck
local encounterWarningsEnabledCheck
local encounterTimelineDisabledCheck
local voiceSection
local voiceChannelDrop
local voiceVolumeSlider
local colorSection
local embedPlaceholder
local activeButtons = {}
local buttonPool = {}
local headerPool = {}
local selectedIndex = 1
local categoryExpanded = {
    general = true,
    display = true,
    trash = true,
    tools = true,
    other = true,
}
local searchBox
local searchText = ""
local sidebarDivider

local fixedColorButtons = {}
local fixedColorLabels = {}
local customNameInput
local customColorButton
local extraCustomEnableChecks = {}
local extraCustomNameInputs = {}
local extraCustomColorButtons = {}
local resetSection

local ResetDisplayStylesOnly
local ResetAllConfigExceptAppearance
local ResetAllConfigIncludingAppearance

-- titleKey/descKey are locale keys resolved at render time via GetTitle/GetDesc,
-- avoiding the load-time capture bug where L["..."] would always return zhCN
-- because EXBOSS12S2 (and the saved locale mode) is not yet available at file load.
local ITEMS = {
    { key = "overview",           category = "general", titleKey = "通用设置",         descKey = "全局显示模式与语音输出。",                                                                                                          mode = "embedded", moduleKey = "ExBoss.GeneralOverview", appearanceRoots = { "ui.general", "voice.global", "autoGossip" } },
    { key = "countdownvoice",     category = "general", titleKey = "语音设置",          descKey = "开怪倒数与数字语音。",                                                                                                               mode = "embedded", moduleKey = "ExBoss.CountdownVoiceSettings", appearanceRoots = { "voice.countdown" } },
    { key = "batchedit",          category = "general", titleKey = "批量修改",          descKey = "批量启用/禁用事件功能，并真实写入 override。",                                                                                        mode = "embedded", moduleKey = "ExBoss.BatchEdit" },
    { key = "color",              category = "general", titleKey = "通用颜色方案",      descKey = "4个固定颜色方案 + 1个自定义方案 + 最多3个额外方案。Boss技能页可直接选择方案或自定义颜色。",                                             mode = "builtin",  moduleKey = "ExBoss.GeneralColor", appearanceRoots = { "voice.colorSchemes", "voice.customColors", "voice.extraCustomColors" } },
    { key = "timerbar",           category = "display", titleKey = "计时条",            descKey = "计时条外观、文字、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.TimerBar" },
    { key = "bunbar",             category = "display", titleKey = "束状条",            descKey = "束状条外观、轨道、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.BunBar" },
    { key = "countdown",          category = "display", titleKey = "[文本]5秒倒数",     descKey = "中央倒数文字与字体、位置。",                                                                                                         mode = "embedded", moduleKey = "ExBoss.Countdown" },
    { key = "flashtextmedium",    category = "display", titleKey = "[文本]文字公告(中)", descKey = "中等尺寸中央提示，供血量转阶段、易伤、站位等功能模块复用。",                                                                         mode = "embedded", moduleKey = "ExBoss.FlashTextMedium" },
    { key = "ringprogress",       category = "display", titleKey = "中央圆环",          descKey = "屏幕中央圆环进度样式、大小、位置。",                                                                                                 mode = "embedded", moduleKey = "ExBoss.RingProgress" },
    { key = "iconalert",          category = "display", titleKey = "图标",              descKey = "通用图标容器，支持 API 推入、可选发光与多图标四向增长。",                                                                             mode = "embedded", moduleKey = "ExBoss.IconAlert" },
    { key = "castprogressbar",    category = "display", titleKey = "施法进度条",        descKey = "与中央圆环同源的施法/引导进度条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.CastProgressBar" },
    { key = "extrashieldbar",     category = "display", titleKey = "护盾条",            descKey = "供首领机制复用的单体护盾监控条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.ExtraShieldBar" },
    { key = "trashcd",            category = "trash",   titleKey = "小怪内置CD姓名版图标", descKey = "小怪内置CD姓名版图标的外观与相对姓名版位置。",                                                                                              mode = "embedded", moduleKey  = "ExBoss.TrashCD.Settings" },
    { key = "reset",              category = "other",   titleKey = "重置设置",          descKey = "提供四种重置方式：\n1) 仅重置外观设置\n2) 仅重置小怪内置CD设置\n3) 重置所有配置（不包含外观）\n4) 清除全部设置（包含外观）",           mode = "builtin"  },
}

local CATEGORIES = {
    { key = "general", titleKey = "通用" },
    { key = "display", titleKey = "显示" },
    { key = "trash",   titleKey = "小怪" },
    { key = "other",   titleKey = "其他" },
}

function Page:GetExportModuleKeys()
    local out = {}
    local seen = {}
    local function add(key)
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    for _, item in ipairs(ITEMS) do
        add(item.moduleKey)
        if type(item.moduleKeys) == "table" then
            for _, key in ipairs(item.moduleKeys) do
                add(key)
            end
        end
    end
    return out
end

-- 外观导出唯一从设置路由取范围：新增非 Boss／小怪设置页时，模块配置会
-- 自动纳入；只有直接写根 SavedVariables 的页面才需要在同一项声明其根路径。
function Page:GetAppearanceProfileSpec()
    local modules, roots, seenModules, seenRoots = {}, {}, {}, {}
    local function add(out, seen, value)
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    for _, item in ipairs(ITEMS) do
        if item.category ~= "trash" and item.key ~= "reset" then
            add(modules, seenModules, item.moduleKey)
            if type(item.moduleKeys) == "table" then
                for _, key in ipairs(item.moduleKeys) do add(modules, seenModules, key) end
            end
            if type(item.appearanceRoots) == "table" then
                for _, path in ipairs(item.appearanceRoots) do add(roots, seenRoots, path) end
            end
        end
    end
    -- Tools 模块拥有独立模块页；注册到 ExBoss.ModuleList 即自动随外观走。
    for _, module in ipairs((ExBoss and ExBoss.ModuleList) or {}) do
        add(modules, seenModules, module.Key)
    end
    return { modules = modules, roots = roots }
end
local function GetTitle(t) return L[t.titleKey or ""] end
local function GetDesc(t)  return L[t.descKey  or ""] end

local function FindItemIndexByKey(key)
    for i, item in ipairs(ITEMS) do
        if item.key == key then
            return i
        end
    end
    return nil
end

local function EnsureSelectedCategoryExpanded()
    local item = ITEMS[selectedIndex]
    if item and item.category then
        categoryExpanded[item.category] = true
    end
end

local CHANNEL_OPTIONS = {
    { "Master", "Master" },
    { "SFX", "SFX" },
    { "Dialog", "Dialog" },
    { "Music", "Music" },
    { "Ambience", "Ambience" },
}

local function GetBarModeOptions()
    return {
        { L["仅束状条"],   "bun"  },
        { L["两者都启用"], "both" },
        { L["仅计时条"],   "timer"},
        { L["两者都隐藏"], "none" },
    }
end

local FALLBACK_SCHEME_ORDER = { "tank", "heal", "target", "cooldown", "mechanic" }
local FALLBACK_SCHEME_KEYS = {
    tank     = "坦克方案",
    heal     = "治疗方案",
    target   = "点名方案",
    cooldown = "减伤方案",
    mechanic = "机制方案",
}
local function GetFallbackSchemeName(key)
    local k = FALLBACK_SCHEME_KEYS[key]
    return k and L[k] or tostring(key or "")
end
local EXTRA_CUSTOM_COUNT_FALLBACK = 3
local EnsureColorDB
local GetSchemeOrder
local GetSchemeDisplayName
local GetExtraCustomCount
local ApplyVoiceOverrides
local RefreshColorControls

local function TrimOptionalText(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetColorModule()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ColorSchemes
end

local function EnsureVoiceDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    EXBOSS12S2.voice.global = EXBOSS12S2.voice.global or {}

    local CS = GetColorModule()
    if CS and CS.EnsureDB then
        CS.EnsureDB()
    end

    local g = EXBOSS12S2.voice.global
    g.channel = g.channel or "Master"
    g.volume = tonumber(g.volume) or 1.0
    return g
end

local function NormalizeBarDisplayMode(mode)
    local m = tostring(mode or ""):lower()
    if m == "timer" or m == "bun" or m == "both" or m == "none" then
        return m
    end
    return "bun"
end

local function EnsureGeneralDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ui = EXBOSS12S2.ui or {}
    EXBOSS12S2.ui.general = EXBOSS12S2.ui.general or {}
    local g = EXBOSS12S2.ui.general
    if g.bossAlertsEnabledMplus == nil then
        g.bossAlertsEnabledMplus = true
    else
        g.bossAlertsEnabledMplus = (g.bossAlertsEnabledMplus == true)
    end
    if g.bossAlertsEnabledRaid == nil then
        g.bossAlertsEnabledRaid = false
    else
        g.bossAlertsEnabledRaid = (g.bossAlertsEnabledRaid == true)
    end
    g.barDisplayMode = NormalizeBarDisplayMode(g.barDisplayMode)
    if g.autoDisableCAAInBoss == nil then
        g.autoDisableCAAInBoss = false
    else
        g.autoDisableCAAInBoss = (g.autoDisableCAAInBoss == true)
    end
    if g.hideTankBossAlertsForDps == nil then
        g.hideTankBossAlertsForDps = true
    else
        g.hideTankBossAlertsForDps = (g.hideTankBossAlertsForDps == true)
    end
    if g.hideTankBossAlertsForHeal == nil then
        g.hideTankBossAlertsForHeal = false
    else
        g.hideTankBossAlertsForHeal = (g.hideTankBossAlertsForHeal == true)
    end
    return g
end

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
    if key == "" then
        return false
    end
    local s = tostring(value or "")
    if s == "" then
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

local function SetEncounterWarningsEnabled(enabled)
    -- 舊 Overview 控件與設定路由共用 ui.general；CVar 只是立即生效的
    -- 遊戲端結果，SavedVariables 才是外觀配置導出／導入的來源。
    local g = EnsureGeneralDB()
    g.encounterWarningsEnabled = (enabled == true)
    WriteCVarValue("encounterWarningsEnabled", enabled and "1" or "0")
end

local function SetEncounterTimelineEnabled(enabled)
    -- 外观配置读取 ui.general；旧 Overview 控件过去只改 CVar，导致
    -- 「关闭暴雪原生计时条」的实际选择没有进入导出包。
    local g = EnsureGeneralDB()
    g.disableBlizzardEncounterTimeline = (enabled ~= true)
    WriteCVarValue("encounterTimelineEnabled", enabled and "1" or "0")
end

local function SetEncounterWarningSoundsEnabled(enabled)
    local g = EnsureGeneralDB()
    g.encounterWarningSoundsEnabled = (enabled == true)
    WriteCVarValue("Sound_EnableEncounterWarningsSounds", enabled and "1" or "2")
end

local function IsTimerBarEnabledByGlobal()
    local g = EnsureGeneralDB()
    local mode = NormalizeBarDisplayMode(g.barDisplayMode)
    return mode == "both" or mode == "timer"
end

local function IsBunBarEnabledByGlobal()
    local g = EnsureGeneralDB()
    local mode = NormalizeBarDisplayMode(g.barDisplayMode)
    return mode == "both" or mode == "bun"
end

local function RefreshGeneralControls()
    local g = EnsureGeneralDB()
    if barModeDropdown then
        local mode = NormalizeBarDisplayMode(g.barDisplayMode)
        barModeDropdown._currentValue = mode
        local label = L["仅束状条"]
        for _, item in ipairs(GetBarModeOptions()) do
            if item[2] == mode then
                label = item[1]
                break
            end
        end
        barModeDropdown:SetText(label)
    end
    if bossAlertsEnabledMplusCheck and bossAlertsEnabledMplusCheck.SetChecked then
        bossAlertsEnabledMplusCheck:SetChecked(g.bossAlertsEnabledMplus == true)
    end
    if bossAlertsEnabledRaidCheck and bossAlertsEnabledRaidCheck.SetChecked then
        bossAlertsEnabledRaidCheck:SetChecked(g.bossAlertsEnabledRaid == true)
    end
    if Page.hideTankBossAlertsForDpsCheck and Page.hideTankBossAlertsForDpsCheck.SetChecked then
        Page.hideTankBossAlertsForDpsCheck:SetChecked(g.hideTankBossAlertsForDps == true)
    end
    if Page.hideTankBossAlertsForHealCheck and Page.hideTankBossAlertsForHealCheck.SetChecked then
        Page.hideTankBossAlertsForHealCheck:SetChecked(g.hideTankBossAlertsForHeal == true)
    end
    if autoDisableCAAInBossCheck and autoDisableCAAInBossCheck.SetChecked then
        autoDisableCAAInBossCheck:SetChecked(g.autoDisableCAAInBoss == true)
    end
    if encounterWarningsEnabledCheck and encounterWarningsEnabledCheck.SetChecked then
        encounterWarningsEnabledCheck:SetChecked(IsEncounterWarningsEnabled())
    end
    if Page.encounterWarningSoundsEnabledCheck and Page.encounterWarningSoundsEnabledCheck.SetChecked then
        Page.encounterWarningSoundsEnabledCheck:SetChecked(IsEncounterWarningSoundsEnabled())
    end
    if encounterTimelineDisabledCheck and encounterTimelineDisabledCheck.SetChecked then
        encounterTimelineDisabledCheck:SetChecked(not IsEncounterTimelineEnabled())
    end
end

local function CreateBossTankFilterChecks(parent, exui)
    if not (exui and exui.CreateCheckbox and parent) then
        return
    end

    Page.hideTankBossAlertsForDpsCheck = exui:CreateCheckbox(
        parent,
        L["DPS职责下不提示坦克技能"],
        EnsureGeneralDB().hideTankBossAlertsForDps == true,
        function(checked)
            local g = EnsureGeneralDB()
            g.hideTankBossAlertsForDps = (checked == true)
            RefreshGeneralControls()
        end
    )
    Page.hideTankBossAlertsForDpsCheck:SetPoint("TOPLEFT", 10, -174)

    Page.hideTankBossAlertsForHealCheck = exui:CreateCheckbox(
        parent,
        L["治疗职责下不提示坦克技能"],
        EnsureGeneralDB().hideTankBossAlertsForHeal == true,
        function(checked)
            local g = EnsureGeneralDB()
            g.hideTankBossAlertsForHeal = (checked == true)
            RefreshGeneralControls()
        end
    )
    Page.hideTankBossAlertsForHealCheck:SetPoint("TOPLEFT", 10, -208)
end

local function CreateOverviewSection(parent, anchor, exui)
    overviewSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    overviewSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    overviewSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    overviewSection:SetHeight(442)
    overviewSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overviewSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    overviewSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local overviewTitle = EXUI:CreateVisualFontString(overviewSection, EXFONTFRAME, "GameFontNormal")
    overviewTitle:SetPoint("TOPLEFT", 10, -8)
    overviewTitle:SetText(L["全局条显示模式"])
    overviewTitle:SetTextColor(1, 0.82, 0.45)

    if exui and exui.CreateDropdown then
        barModeDropdown = exui:CreateDropdown(
            overviewSection,
            220,
            L["显示模式"],
            GetBarModeOptions(),
            EnsureGeneralDB().barDisplayMode,
            function(val)
                local g = EnsureGeneralDB()
                g.barDisplayMode = NormalizeBarDisplayMode(val)
                RefreshGeneralControls()
                ApplyBarModeChange()
            end,
            true
        )
        barModeDropdown:SetPoint("TOPLEFT", 10, -36)
    end

    if exui and exui.CreateCheckbox then
        bossAlertsEnabledMplusCheck = exui:CreateCheckbox(
            overviewSection,
            L["启用大秘境首领提示"],
            EnsureGeneralDB().bossAlertsEnabledMplus == true,
            function(checked)
                local g = EnsureGeneralDB()
                g.bossAlertsEnabledMplus = (checked == true)
                RefreshGeneralControls()
                ApplyBossSceneToggleChange()
            end
        )
        bossAlertsEnabledMplusCheck:SetPoint("TOPLEFT", 10, -72)
    end

    if exui and exui.CreateCheckbox then
        bossAlertsEnabledRaidCheck = exui:CreateCheckbox(
            overviewSection,
            L["启用团本首领提示"],
            EnsureGeneralDB().bossAlertsEnabledRaid == true,
            function(checked)
                local g = EnsureGeneralDB()
                g.bossAlertsEnabledRaid = (checked == true)
                RefreshGeneralControls()
                ApplyBossSceneToggleChange()
            end
        )
        bossAlertsEnabledRaidCheck:SetPoint("TOPLEFT", 10, -106)
    end

    if exui and exui.CreateCheckbox then
        autoDisableCAAInBossCheck = exui:CreateCheckbox(
            overviewSection,
            L["首领战时自动关闭战斗音频预警"],
            EnsureGeneralDB().autoDisableCAAInBoss == true,
            function(checked)
                local g = EnsureGeneralDB()
                g.autoDisableCAAInBoss = (checked == true)
                RefreshGeneralControls()
                if ExBoss and ExBoss.ApplyBossAutoCAASetting then
                    ExBoss.ApplyBossAutoCAASetting()
                end
            end
        )
        autoDisableCAAInBossCheck:SetPoint("TOPLEFT", 10, -140)
    end

    CreateBossTankFilterChecks(overviewSection, exui)

    if exui and exui.CreateCheckbox then
        encounterWarningsEnabledCheck = exui:CreateCheckbox(
            overviewSection,
            L["开启中央文字预警（注意：如果关闭会导致语音不工作）"],
            IsEncounterWarningsEnabled(),
            function(checked)
                SetEncounterWarningsEnabled(checked == true)
                RefreshGeneralControls()
            end
        )
        encounterWarningsEnabledCheck:SetPoint("TOPLEFT", 10, -242)
    end

    if exui and exui.CreateCheckbox then
        Page.encounterWarningSoundsEnabledCheck = exui:CreateCheckbox(
            overviewSection,
            L["开启中央文字预警提示音（预设叮一声）"],
            IsEncounterWarningSoundsEnabled(),
            function(checked)
                SetEncounterWarningSoundsEnabled(checked == true)
                RefreshGeneralControls()
            end
        )
        Page.encounterWarningSoundsEnabledCheck:SetPoint("TOPLEFT", 10, -276)
    end

    if exui and exui.CreateCheckbox then
        encounterTimelineDisabledCheck = exui:CreateCheckbox(
            overviewSection,
            L["关闭暴雪原生计时条"],
            not IsEncounterTimelineEnabled(),
            function(checked)
                SetEncounterTimelineEnabled(not (checked == true))
                RefreshGeneralControls()
            end
        )
        encounterTimelineDisabledCheck:SetPoint("TOPLEFT", 10, -310)
    end

    local overviewDesc = EXUI:CreateVisualFontString(overviewSection, EXFONTFRAME, "GameFontHighlightSmall")
    overviewDesc:SetPoint("TOPLEFT", 10, -346)
    overviewDesc:SetPoint("RIGHT", overviewSection, "RIGHT", -10, 0)
    overviewDesc:SetJustifyH("LEFT")
    overviewDesc:SetTextColor(0.85, 0.85, 0.9)
    overviewDesc:SetText(L["控制全局显示：仅计时条 / 仅束状条 / 两者都启用 / 两者都隐藏。\n可分别关闭大秘境或团本首领提示；关闭后将整体禁用对应场景的 Boss 计时、中央文字、语音与颜色覆盖。\n可按当前职责过滤坦克类 Boss 技能提示。\n可选：首领战中自动将战斗音频预警分类音量静音（0），脱战恢复原值。"])
    overviewSection:Hide()
end

local function CreateVoiceSection(parent, anchor, exui)
    voiceSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    voiceSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    voiceSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    voiceSection:SetHeight(120)
    voiceSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    voiceSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    voiceSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local voiceTitle = EXUI:CreateVisualFontString(voiceSection, EXFONTFRAME, "GameFontNormal")
    voiceTitle:SetPoint("TOPLEFT", 10, -8)
    voiceTitle:SetText(L["全局语音输出"])
    voiceTitle:SetTextColor(1, 0.82, 0.45)

    if exui and exui.CreateDropdown then
        voiceChannelDrop = exui:CreateDropdown(
            voiceSection,
            180,
            L["输出通道"],
            CHANNEL_OPTIONS,
            EnsureVoiceDB().channel,
            function(val)
                local g = EnsureVoiceDB()
                g.channel = tostring(val or "Master")
                ApplyVoiceOverrides()
            end,
            true
        )
        voiceChannelDrop:SetPoint("TOPLEFT", 10, -34)
    end

    if exui and exui.CreateSlider then
        voiceVolumeSlider = exui:CreateSlider(
            voiceSection,
            300,
            L["全局音量"],
            0,
            1,
            EnsureVoiceDB().volume,
            0.01,
            function(v) return string.format("%.2f", v) end,
            function(v)
                local g = EnsureVoiceDB()
                g.volume = tonumber(string.format("%.2f", v)) or 1.0
                ApplyVoiceOverrides()
            end
        )
        voiceVolumeSlider:SetPoint("TOPLEFT", 10, -78)
    end
    voiceSection:Hide()
end

local function CreateColorSection(parent, anchor, exui)
    colorSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    colorSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    colorSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    colorSection:SetHeight(430)
    colorSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    colorSection:SetBackdropColor(0.03, 0.04, 0.06, 0.82)
    colorSection:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)

    local colorTitle = EXUI:CreateVisualFontString(colorSection, EXFONTFRAME, "GameFontNormal")
    colorTitle:SetPoint("TOPLEFT", 10, -8)
    colorTitle:SetText(L["通用颜色方案"])
    colorTitle:SetTextColor(1, 0.82, 0.45)

    local colorDesc = EXUI:CreateVisualFontString(colorSection, EXFONTFRAME, "GameFontHighlightSmall")
    colorDesc:SetPoint("TOPLEFT", 10, -28)
    colorDesc:SetPoint("RIGHT", colorSection, "RIGHT", -10, 0)
    colorDesc:SetText(L["Boss技能页面可选择下列方案；选择“自定义颜色”时使用“自定义方案”。勾选启用的额外方案会出现在技能页下拉。"])
    colorDesc:SetTextColor(0.85, 0.85, 0.9)
    colorDesc:SetJustifyH("LEFT")

    local _, schemes, custom, extraSlots = EnsureColorDB()
    local rowY = -52
    for _, key in ipairs(GetSchemeOrder()) do
        local row = schemes and schemes[key]

        local nameFS = EXUI:CreateVisualFontString(colorSection, EXFONTFRAME, "GameFontHighlight")
        nameFS:SetPoint("TOPLEFT", 12, rowY)
        nameFS:SetText(GetSchemeDisplayName(key))
        nameFS:SetTextColor(0.95, 0.95, 0.95)
        fixedColorLabels[key] = nameFS

        if exui and exui.CreateColorButton then
            local btn = exui:CreateColorButton(colorSection, L["颜色"], row or { r = 1, g = 1, b = 1 }, "", false, function()
                ApplyVoiceOverrides()
            end)
            btn:SetPoint("TOPLEFT", 180, rowY + 8)
            btn:SetSize(220, 30)
            fixedColorButtons[key] = btn
        end
        rowY = rowY - 38
    end

    if exui and exui.CreateEditBox then
        customNameInput = exui:CreateEditBox(
            colorSection,
            (custom and custom.name) or L["自定义方案"],
            160,
            28,
            L["自定义方案名"],
            {
                onEditFocusLost = function(text)
                    local _, _, c = EnsureColorDB()
                    c.name = TrimOptionalText(text)
                    RefreshColorControls()
                end,
                onEnter = function(text)
                    local _, _, c = EnsureColorDB()
                    c.name = TrimOptionalText(text)
                    RefreshColorControls()
                end,
            }
        )
        customNameInput:SetPoint("TOPLEFT", 12, rowY - 2)
    end

    if exui and exui.CreateColorButton then
        customColorButton = exui:CreateColorButton(colorSection, L["自定义方案颜色"], custom or { r = 1, g = 0.82, b = 0.25 }, "", false,
            function()
                ApplyVoiceOverrides()
            end
        )
        customColorButton:SetPoint("TOPLEFT", 180, rowY + 6)
        customColorButton:SetSize(220, 30)
    end

    rowY = rowY - 42
    local extraTitle = EXUI:CreateVisualFontString(colorSection, EXFONTFRAME, "GameFontHighlight")
    extraTitle:SetPoint("TOPLEFT", 12, rowY)
    extraTitle:SetText(L["额外方案（最多3个）"])
    extraTitle:SetTextColor(0.95, 0.95, 0.95)

    rowY = rowY - 24
    for i = 1, GetExtraCustomCount() do
        local slot = type(extraSlots) == "table" and extraSlots[i] or nil
        if type(slot) ~= "table" then
            slot = { enabled = false, name = L["额外方案"] .. tostring(i), r = 1, g = 0.82, b = 0.25 }
        end

        if exui and exui.CreateCheckbox then
            local cb = exui:CreateCheckbox(colorSection, L["启用"], slot.enabled == true, function(checked)
                local _, _, _, slots = EnsureColorDB()
                if type(slots) ~= "table" then return end
                local row = slots and slots[i]
                if type(row) ~= "table" then
                    row = { name = L["额外方案"] .. tostring(i), r = 1, g = 0.82, b = 0.25, enabled = false }
                    slots[i] = row
                end
                row.enabled = (checked == true)
                RefreshColorControls()
                ApplyVoiceOverrides()
            end)
            cb:SetPoint("TOPLEFT", 12, rowY + 4)
            extraCustomEnableChecks[i] = cb
        end

        if exui and exui.CreateEditBox then
            local nameInput = exui:CreateEditBox(
                colorSection,
                slot.name or (L["额外方案"] .. tostring(i)),
                190,
                28,
                "",
                {
                    onEditFocusLost = function(text)
                        local _, _, _, slots = EnsureColorDB()
                        if type(slots) ~= "table" then return end
                        local row = slots and slots[i]
                        if type(row) ~= "table" then
                            row = { enabled = false, r = 1, g = 0.82, b = 0.25 }
                            slots[i] = row
                        end
                        row.name = TrimOptionalText(text)
                        RefreshColorControls()
                    end,
                    onEnter = function(text)
                        local _, _, _, slots = EnsureColorDB()
                        if type(slots) ~= "table" then return end
                        local row = slots and slots[i]
                        if type(row) ~= "table" then
                            row = { enabled = false, r = 1, g = 0.82, b = 0.25 }
                            slots[i] = row
                        end
                        row.name = TrimOptionalText(text)
                        RefreshColorControls()
                    end,
                }
            )
            nameInput:SetPoint("TOPLEFT", 88, rowY + 2)
            extraCustomNameInputs[i] = nameInput
        end

        if exui and exui.CreateColorButton then
            local colorBtn = exui:CreateColorButton(colorSection, L["颜色"], slot, "", false, function()
                ApplyVoiceOverrides()
            end)
            colorBtn:SetPoint("TOPLEFT", 290, rowY + 6)
            colorBtn:SetSize(220, 30)
            extraCustomColorButtons[i] = colorBtn
        end

        rowY = rowY - 38
    end
    colorSection:Hide()
end

local function CreateResetSection(parent, anchor)
    resetSection = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    resetSection:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    resetSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
    resetSection:SetHeight(204)
    resetSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    resetSection:SetBackdropColor(0.12, 0.03, 0.03, 0.85)
    resetSection:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.95)

    local resetTitle = EXUI:CreateVisualFontString(resetSection, EXFONTFRAME, "GameFontNormal")
    resetTitle:SetPoint("TOPLEFT", 10, -10)
    resetTitle:SetText("|cffff4444" .. L["重置设置"] .. "|r")

    local resetDesc = EXUI:CreateVisualFontString(resetSection, EXFONTFRAME, "GameFontHighlightSmall")
    resetDesc:SetPoint("TOPLEFT", 10, -30)
    resetDesc:SetPoint("RIGHT", resetSection, "RIGHT", -10, 0)
    resetDesc:SetJustifyH("LEFT")
    resetDesc:SetText(L["推荐先使用针对性重置：外观问题用“仅重置外观设置”，小怪CD异常用“重置小怪内置CD设置”。\n“重置所有配置（不包含外观）”会清空通用设置、语音配置、技能配置与时间轴设置，但保留外观。\n“清除全部设置”会把 EXBoss 的全部配置都恢复到初始状态。"])
    resetDesc:SetTextColor(0.9, 0.7, 0.7)

    local resetStyleBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetStyleBtn:SetSize(220, 28)
    resetStyleBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 118)
    resetStyleBtn:SetText(L["仅重置外观设置"])
    resetStyleBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_STYLE_ONLY_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["仅重置计时条/束状条/倒计时/文字公告的外观样式，不删除法术配置。是否继续？"],
                button1 = L["确定"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetDisplayStylesOnly()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)

    local resetConfigBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetConfigBtn:SetSize(220, 28)
    resetConfigBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 46)
    resetConfigBtn:SetText(L["重置所有配置（不包含外观）"])
    resetConfigBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_CONFIG_ONLY_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["|cffffcc00将清空 EXBoss 的通用设置、语音配置、技能配置与时间轴设置，但保留外观样式。|r\n确认继续？"],
                button1 = L["确定重置"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetAllConfigExceptAppearance()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)

    local resetAllBtn = CreateFrame("Button", nil, resetSection, "UIPanelButtonTemplate")
    resetAllBtn:SetSize(220, 28)
    resetAllBtn:SetPoint("BOTTOMLEFT", resetSection, "BOTTOMLEFT", 10, 10)
    resetAllBtn:SetText(L["清除全部设置（包含外观）"])
    resetAllBtn:SetScript("OnClick", function()
        local popupID = "EXBOSS_RESET_ALL_CONFIRM"
        if not StaticPopupDialogs[popupID] then
            StaticPopupDialogs[popupID] = {
                text = L["|cffff4444危险：将清空 EXBoss 的全部设置（包含外观）并重载。此操作不可撤销。|r\n确认继续？"],
                button1 = L["确定清空"],
                button2 = L["取消"],
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = function()
                    ResetAllConfigIncludingAppearance()
                    ReloadUI()
                end,
            }
        end
        StaticPopup_Show(popupID)
    end)
    resetSection:Hide()
end

local function GetVordazaShieldModule()
    return ExBoss and ExBoss.Modules and ExBoss.Modules.Boss and ExBoss.Modules.Boss.VordazaShieldBar or nil
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

EnsureColorDB = function()
    local CS = GetColorModule()
    if CS and CS.EnsureDB then
        local db = CS.EnsureDB()
        local custom = (db.customColors and db.customColors[1]) or {}
        return db, db.colorSchemes or {}, custom, db.extraCustomColors or {}
    end

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    EXBOSS12S2.voice.colorSchemes = EXBOSS12S2.voice.colorSchemes or {}
    EXBOSS12S2.voice.customColors = EXBOSS12S2.voice.customColors or {}
    EXBOSS12S2.voice.extraCustomColors = EXBOSS12S2.voice.extraCustomColors or {}
    EXBOSS12S2.voice.customColors[1] = EXBOSS12S2.voice.customColors[1] or { name = L["自定义方案"], r = 1, g = 0.82, b = 0.25 }

    for i = 1, EXTRA_CUSTOM_COUNT_FALLBACK do
        local row = EXBOSS12S2.voice.extraCustomColors[i]
        if type(row) ~= "table" then
            EXBOSS12S2.voice.extraCustomColors[i] = {
                enabled = false,
                name = L["额外方案"] .. tostring(i),
                r = 1,
                g = 0.82,
                b = 0.25,
            }
        else
            if row.enabled == nil then row.enabled = false end
            if type(row.name) ~= "string" then
                row.name = L["额外方案"] .. tostring(i)
            end
            row.r = tonumber(row.r) or 1
            row.g = tonumber(row.g) or 0.82
            row.b = tonumber(row.b) or 0.25
        end
    end

    for _, key in ipairs(FALLBACK_SCHEME_ORDER) do
        local row = EXBOSS12S2.voice.colorSchemes[key]
        if type(row) ~= "table" then
            EXBOSS12S2.voice.colorSchemes[key] = {
                name = GetFallbackSchemeName(key),
                r = 1,
                g = 1,
                b = 1,
            }
        end
    end

    return EXBOSS12S2.voice, EXBOSS12S2.voice.colorSchemes, EXBOSS12S2.voice.customColors[1], EXBOSS12S2.voice.extraCustomColors
end

GetSchemeOrder = function()
    local CS = GetColorModule()
    if CS and CS.GetFixedOrder then
        return CS.GetFixedOrder()
    end
    return FALLBACK_SCHEME_ORDER
end

GetSchemeDisplayName = function(key)
    local CS = GetColorModule()
    if CS and CS.GetSchemeDisplayName then
        return CS.GetSchemeDisplayName(key)
    end
    return GetFallbackSchemeName(key)
end

GetExtraCustomCount = function()
    local CS = GetColorModule()
    if CS and CS.GetExtraCustomCount then
        return tonumber(CS.GetExtraCustomCount()) or EXTRA_CUSTOM_COUNT_FALLBACK
    end
    return EXTRA_CUSTOM_COUNT_FALLBACK
end

ApplyVoiceOverrides = function()
    if ExBoss and ExBoss.Voice and ExBoss.Voice.Engine and ExBoss.Voice.Engine.ApplyEventOverridesToAPI then
        ExBoss.Voice.Engine:ApplyEventOverridesToAPI()
    end
end

local STYLE_MODULE_KEYS = {
    "ExBoss.TimerBar",
    "ExBoss.BunBar",
    "ExBoss.Countdown",
    "ExBoss.FlashTextMedium",
    "ExBoss.RingProgress",
    "ExBoss.IconAlert",
    "ExBoss.CastProgressBar",
    -- ExtraShieldBar owns only display configuration in its ModuleDB, so its
    -- complete DB is part of the appearance snapshot/reset contract.
    "ExBoss.ExtraShieldBar",
}

local EXBOSS_MODULE_KEYS = {
    "ExBoss.TimerBar",
    "ExBoss.BunBar",
    "ExBoss.Countdown",
    "ExBoss.FlashTextMedium",
    "ExBoss.RingProgress",
    "ExBoss.IconAlert",
    "ExBoss.CastProgressBar",
    "ExBoss.ExtraShieldBar",
    "ExBoss.BossSpellOptions",
    "ExBoss.TrashCD.Settings",
}

local STYLE_MODULE_KEY_SET = {
    ["ExBoss.TimerBar"] = true,
    ["ExBoss.BunBar"] = true,
    ["ExBoss.Countdown"] = true,
    ["ExBoss.FlashTextMedium"] = true,
    ["ExBoss.RingProgress"] = true,
    ["ExBoss.IconAlert"] = true,
    ["ExBoss.CastProgressBar"] = true,
    ["ExBoss.ExtraShieldBar"] = true,
}

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[DeepCopy(k)] = DeepCopy(v)
    end
    return out
end

local function CaptureAppearanceSnapshot()
    local snap = {
        timer = {},
        voice = {},
        moduleDB = {},
    }

    if type(EXBOSS12S2) == "table" then
        local timer = type(EXBOSS12S2.timer) == "table" and EXBOSS12S2.timer or nil
        if timer then
            if timer.bunBar ~= nil then snap.timer.bunBar = DeepCopy(timer.bunBar) end
            if timer.countdown ~= nil then snap.timer.countdown = DeepCopy(timer.countdown) end
            if timer.flashTextMedium ~= nil then snap.timer.flashTextMedium = DeepCopy(timer.flashTextMedium) end
            if timer.ringProgress ~= nil then snap.timer.ringProgress = DeepCopy(timer.ringProgress) end
        end

        local voice = type(EXBOSS12S2.voice) == "table" and EXBOSS12S2.voice or nil
        if voice then
            if voice.colorSchemes ~= nil then snap.voice.colorSchemes = DeepCopy(voice.colorSchemes) end
            if voice.customColors ~= nil then snap.voice.customColors = DeepCopy(voice.customColors) end
            if voice.extraCustomColors ~= nil then snap.voice.extraCustomColors = DeepCopy(voice.extraCustomColors) end
        end
    end

    if type(EXBOSS12S2) == "table" and type(EXBOSS12S2.ModuleDB) == "table" then
        for _, key in ipairs(STYLE_MODULE_KEYS) do
            if EXBOSS12S2.ModuleDB[key] ~= nil then
                snap.moduleDB[key] = DeepCopy(EXBOSS12S2.ModuleDB[key])
            end
        end
    end

    return snap
end

local function RestoreAppearanceSnapshot(snap)
    if type(snap) ~= "table" then
        return
    end

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.timer = EXBOSS12S2.timer or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}

    EXBOSS12S2.timer.bunBar = DeepCopy(snap.timer and snap.timer.bunBar)
    EXBOSS12S2.timer.countdown = DeepCopy(snap.timer and snap.timer.countdown)
    EXBOSS12S2.timer.flashTextMedium = DeepCopy(snap.timer and snap.timer.flashTextMedium)
    EXBOSS12S2.timer.ringProgress = DeepCopy(snap.timer and snap.timer.ringProgress)
    EXBOSS12S2.voice.colorSchemes = DeepCopy(snap.voice and snap.voice.colorSchemes)
    EXBOSS12S2.voice.customColors = DeepCopy(snap.voice and snap.voice.customColors)
    EXBOSS12S2.voice.extraCustomColors = DeepCopy(snap.voice and snap.voice.extraCustomColors)

    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.ModuleDB = EXBOSS12S2.ModuleDB or {}
    for _, key in ipairs(STYLE_MODULE_KEYS) do
        EXBOSS12S2.ModuleDB[key] = nil
    end
    if type(snap.moduleDB) == "table" then
        for key, value in pairs(snap.moduleDB) do
            EXBOSS12S2.ModuleDB[key] = DeepCopy(value)
        end
    end
end

local function ClearExBossModuleDB(preserveAppearanceModules)
    if type(EXBOSS12S2) ~= "table" or type(EXBOSS12S2.ModuleDB) ~= "table" then
        return
    end
    for _, key in ipairs(EXBOSS_MODULE_KEYS) do
        if not (preserveAppearanceModules and STYLE_MODULE_KEY_SET[key]) then
            EXBOSS12S2.ModuleDB[key] = nil
        end
    end
end

ResetDisplayStylesOnly = function()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.timer = EXBOSS12S2.timer or {}
    EXBOSS12S2.timer.bunBar = nil
    EXBOSS12S2.timer.countdown = nil
    EXBOSS12S2.timer.flashTextMedium = nil
    EXBOSS12S2.timer.ringProgress = nil

    if EXBOSS12S2 and type(EXBOSS12S2.ModuleDB) == "table" then
        for _, key in ipairs(STYLE_MODULE_KEYS) do
            EXBOSS12S2.ModuleDB[key] = nil
        end
    end

    if ExBoss and ExBoss.UI then
        if ExBoss.UI.TimerBar and ExBoss.UI.TimerBar.RefreshVisuals then
            ExBoss.UI.TimerBar:RefreshVisuals()
        end
        if ExBoss.UI.BunBar and ExBoss.UI.BunBar.RefreshVisuals then
            ExBoss.UI.BunBar:RefreshVisuals()
        end
        if ExBoss.UI.Countdown and ExBoss.UI.Countdown.RefreshVisuals then
            ExBoss.UI.Countdown:RefreshVisuals()
        end
        if ExBoss.UI.FlashTextMedium and ExBoss.UI.FlashTextMedium.RefreshVisuals then
            ExBoss.UI.FlashTextMedium:RefreshVisuals()
        end
        if ExBoss.UI.RingProgress and ExBoss.UI.RingProgress.RefreshVisuals then
            ExBoss.UI.RingProgress:RefreshVisuals()
        end
        if ExBoss.UI.IconAlert and ExBoss.UI.IconAlert.RefreshVisuals then
            ExBoss.UI.IconAlert:RefreshVisuals()
        end
        if ExBoss.UI.CastProgressBar and ExBoss.UI.CastProgressBar.RefreshVisuals then
            ExBoss.UI.CastProgressBar:RefreshVisuals()
        end
        if ExBoss.UI.ExtraShieldBar and ExBoss.UI.ExtraShieldBar.RefreshVisuals then
            ExBoss.UI.ExtraShieldBar:RefreshVisuals()
        end
        local VordazaShield = GetVordazaShieldModule()
        if VordazaShield and VordazaShield.RefreshVisuals then
            VordazaShield:RefreshVisuals()
        end
    end
end

ResetAllConfigExceptAppearance = function()
    local appearance = CaptureAppearanceSnapshot()

    ExwindTools:ResetAddonModuleStorage("EXBOSS")
    EXBossDataDB = nil

    RestoreAppearanceSnapshot(appearance)
end

ResetAllConfigIncludingAppearance = function()
    ExwindTools:ResetAddonModuleStorage("EXBOSS")
    EXBossDataDB = nil
end

local function RefreshVoiceControls()
    local g = EnsureVoiceDB()
    if voiceChannelDrop then
        voiceChannelDrop._currentValue = g.channel
        local label = g.channel
        for _, item in ipairs(CHANNEL_OPTIONS) do
            if item[2] == g.channel then
                label = item[1]
                break
            end
        end
        voiceChannelDrop:SetText(label or "Master")
    end
    if voiceVolumeSlider then
        if voiceVolumeSlider.Init then
            voiceVolumeSlider:Init(g.volume, 0, 1, 100)
        else
            voiceVolumeSlider:SetValue(g.volume)
        end
    end
end

RefreshColorControls = function()
    local _, schemes, custom, extraSlots = EnsureColorDB()
    for _, key in ipairs(GetSchemeOrder()) do
        local btn = fixedColorButtons[key]
        local nameFS = fixedColorLabels[key]
        local row = schemes and schemes[key]
        if btn and type(row) == "table" then
            btn._currentDb = row
            if btn.UpdateColor then
                btn:UpdateColor(row.r, row.g, row.b, 1)
            end
        end
        if nameFS then
            nameFS:SetText(GetSchemeDisplayName(key))
        end
    end

    if customNameInput and type(custom) == "table" then
        if not customNameInput:HasFocus() then
            customNameInput:SetText(custom.name or L["自定义方案"])
        end
    end
    if customColorButton and type(custom) == "table" then
        customColorButton._currentDb = custom
        if customColorButton.UpdateColor then
            customColorButton:UpdateColor(custom.r, custom.g, custom.b, 1)
        end
    end

    for i = 1, GetExtraCustomCount() do
        local row = type(extraSlots) == "table" and extraSlots[i] or nil
        local cb = extraCustomEnableChecks[i]
        local nameInput = extraCustomNameInputs[i]
        local colorBtn = extraCustomColorButtons[i]
        if cb and cb.SetChecked then
            cb:SetChecked(row and row.enabled == true)
        end
        if nameInput and type(row) == "table" then
            if not nameInput:HasFocus() then
                nameInput:SetText(row.name or (L["额外方案"] .. tostring(i)))
            end
        end
        if colorBtn and type(row) == "table" then
            colorBtn._currentDb = row
            if colorBtn.UpdateColor then
                colorBtn:UpdateColor(row.r, row.g, row.b, 1)
            end
        end
    end
end

local function ClearButtons()
    for _, b in ipairs(activeButtons) do
        b:Hide()
        b:ClearAllPoints()
        b:SetScript("OnClick", nil)
        if b._sidebarKind == "header" then
            headerPool[#headerPool + 1] = b
        else
            buttonPool[#buttonPool + 1] = b
        end
    end
    wipe(activeButtons)
end

local function AcquireListButton()
    local b = table.remove(buttonPool)
    if b then
        b:SetParent(listChild)
        return b
    end

    if ExBoss.UI and ExBoss.UI.CreateSidebarModuleButton then
        b = ExBoss.UI.CreateSidebarModuleButton(listChild)
    else
        b = CreateFrame("Button", nil, listChild)
        b.fs = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontHighlightSmall")
        b.fs:SetPoint("LEFT", 14, 0)
        b.fs:SetPoint("RIGHT", -8, 0)
        b.fs:SetJustifyH("LEFT")
        b.label = b.fs
    end
    b._sidebarKind = "item"
    return b
end

local function AcquireHeaderButton()
    local b = table.remove(headerPool)
    if b then
        b:SetParent(listChild)
        return b
    end
    if ExBoss.UI and ExBoss.UI.CreateSidebarCategoryHeader then
        b = ExBoss.UI.CreateSidebarCategoryHeader(listChild)
    else
        b = CreateFrame("Button", nil, listChild)
        b.label = EXUI:CreateVisualFontString(b, EXFONTFRAME, "GameFontNormal")
        b.label:SetAllPoints()
        b.label:SetJustifyH("LEFT")
    end
    b._sidebarKind = "header"
    return b
end

local function SetupListButton(button, height, leftInset)
    button:SetHeight(height)
    local label = button.label or button.fs
    label:ClearAllPoints()
    label:SetPoint("LEFT", leftInset or 14, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    button:Enable()
end

local function ItemMatchesSearch(item)
    if searchText == "" then
        return true
    end
    if not ExBoss.UI or not ExBoss.UI.SidebarTextContains then
        return true
    end
    return ExBoss.UI.SidebarTextContains(GetTitle(item), searchText)
        or ExBoss.UI.SidebarTextContains(GetDesc(item), searchText)
        or ExBoss.UI.SidebarTextContains(item.key, searchText)
        or ExBoss.UI.SidebarTextContains(item.moduleKey, searchText)
end

local function HideEmbeddedPages()
    local pages = {
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GeneralOverviewPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownVoicePage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BatchEditPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TimerBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BunBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextMediumPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.RingProgressPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.IconAlertPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CastProgressBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ExtraShieldBarPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ImportExportPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalTrashCDPage,
    }
    for _, page in ipairs(pages) do
        if page and page._scrollFrame then
            page._scrollFrame:Hide()
            if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == page._scrollChild then
                ExwindTools.UI.ActivePageFrame = nil
                ExwindTools.UI.CurrentModule = nil
            end
        end
    end
end

local function ShowBuiltinLayout(show)
    if titleText then
        if show then titleText:Show() else titleText:Hide() end
    end
    if titleSep then
        if show then titleSep:Show() else titleSep:Hide() end
    end
    if descText then
        if show then descText:Show() else descText:Hide() end
    end
end

local function RefreshRight()
    local item = ITEMS[selectedIndex] or ITEMS[1]
    local key = item and item.key or "overview"

    HideEmbeddedPages()
    if overviewSection then overviewSection:Hide() end
    if voiceSection then voiceSection:Hide() end
    if colorSection then colorSection:Hide() end
    if resetSection then resetSection:Hide() end
    if embedPlaceholder then embedPlaceholder:Hide() end

    if item and item.mode == "embedded" then
        if rightScrollFrame then
            rightScrollFrame:Hide()
        end
        if rightRoot then
            rightRoot:Hide()
        end
        ShowBuiltinLayout(false)

        local pageMap = {
            overview = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GeneralOverviewPage,
            countdownvoice = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownVoicePage,
            batchedit = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BatchEditPage,
            timerbar = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.TimerBarPage,
            bunbar = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BunBarPage,
            countdown = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CountdownPage,
            flashtextmedium = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.FlashTextMediumPage,
            ringprogress         = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.RingProgressPage,
            iconalert            = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.IconAlertPage,
            castprogressbar      = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.CastProgressBarPage,
            extrashieldbar       = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.ExtraShieldBarPage,
            trashcd              = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalTrashCDPage,
        }
        local page = pageMap[key]
        if page and page.Render then
            page:Render(embeddedHostFrame)
        elseif embedPlaceholder then
            embedPlaceholder:SetText((GetTitle(item) or L["设置页"]) .. L[" 未就绪"])
            embedPlaceholder:Show()
        end
        return
    end

    if rightScrollFrame then
        rightScrollFrame:SetVerticalScroll(0)
        rightScrollFrame:Show()
    end
    if rightRoot then
        rightRoot:Show()
    end
    ShowBuiltinLayout(true)
    if titleText then
        titleText:SetText(item and GetTitle(item) or L["通用设置"])
    end
    if descText then
        descText:SetText(item and GetDesc(item) or "")
    end

    if key == "overview" then
        if overviewSection then overviewSection:Show() end
    elseif key == "voice" then
        if voiceSection then voiceSection:Show() end
    elseif key == "color" then
        if colorSection then colorSection:Show() end
    elseif key == "reset" then
        if resetSection then resetSection:Show() end
    end
end

local function RefreshList()
    if not listChild then return end
    ClearButtons()

    local y = -6
    local shown = 0
    for _, category in ipairs(CATEGORIES) do
        local matchedItems = {}
        for i, item in ipairs(ITEMS) do
            if item.category == category.key and ItemMatchesSearch(item) then
                matchedItems[#matchedItems + 1] = { index = i, item = item }
            end
        end

        if #matchedItems > 0 then
            local header = AcquireHeaderButton()
            SetupListButton(header, 26, 0)
            header:SetPoint("TOPLEFT", 10, y)
            header:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
            header.label:SetText(GetTitle(category))
            header:SetScript("OnClick", nil)
            activeButtons[#activeButtons + 1] = header
            header:Show()
            y = y - 30
            shown = shown + 1

            for _, row in ipairs(matchedItems) do
                local i = row.index
                local item = row.item
                local b = AcquireListButton()
                SetupListButton(b, 30, 34)
                b:SetPoint("TOPLEFT", 10, y)
                b:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)

                local label = b.label or b.fs
                label:SetText(GetTitle(item) or (L["条目 "] .. tostring(i)))
                if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and b.label then
                    ExBoss.UI.ApplySidebarModuleButtonState(b, selectedIndex == i, true)
                end

                b:SetScript("OnClick", function()
                    selectedIndex = i
                    EnsureSelectedCategoryExpanded()
                    RefreshList()
                    RefreshRight()
                end)

                activeButtons[#activeButtons + 1] = b
                b:Show()
                y = y - 34
                shown = shown + 1
            end
            y = y - 6
        end
    end

    if shown == 0 then
        local empty = AcquireListButton()
        SetupListButton(empty, 30, 34)
        empty:SetPoint("TOPLEFT", 10, y)
        empty:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
        local label = empty.label or empty.fs
        label:SetText(L["没有匹配项"])
        if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and empty.label then
            ExBoss.UI.ApplySidebarModuleButtonState(empty, false, false)
        else
            label:SetTextColor(0.45, 0.48, 0.55, 1)
        end
        empty:Show()
        activeButtons[#activeButtons + 1] = empty
        y = y - 32
    end

    listChild:SetHeight(math.max(1, -y + 8))
end

local function EnsureUI(leftFrame, contentFrame)
    if leftRoot and rightRoot then return end

    leftRoot = CreateFrame("Frame", nil, leftFrame)
    leftRoot:SetAllPoints(leftFrame)

    sidebarDivider = EXUI:CreateVisualTexture(leftRoot, EXBORDERFRAME)
    sidebarDivider:SetWidth(1)
    sidebarDivider:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -2, -2)
    sidebarDivider:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -2, 2)
    sidebarDivider:SetColorTexture(0.12, 0.15, 0.20, 0.9)

    if ExBoss.UI and ExBoss.UI.CreateSidebarSearchBox then
        searchBox = ExBoss.UI.CreateSidebarSearchBox(leftRoot, searchText, {
            placeholder = L["搜索设置..."],
            onChanged = function(text)
                local normalized = ExBoss.UI.NormalizeSidebarSearchText and ExBoss.UI.NormalizeSidebarSearchText(text) or tostring(text or "")
                if normalized == searchText then
                    return
                end
                searchText = normalized
                if listScroll and listScroll.SetVerticalScroll then
                    listScroll:SetVerticalScroll(0)
                end
                RefreshList()
            end,
        })
        searchBox:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -5)
        searchBox:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -22, -5)
    end

    listScroll = CreateFrame("ScrollFrame", nil, leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(listScroll)
    end
    listScroll:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -40)
    listScroll:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -22, 5)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(340, 1)
    listScroll:SetScrollChild(listChild)

    rightScrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(rightScrollFrame)
    end
    rightRoot = CreateFrame("Frame", nil, rightScrollFrame)
    rightRoot:SetPoint("TOPLEFT", 0, 0)
    rightRoot:SetSize(math.max((contentFrame:GetWidth() or 0) - 28, 760), 1600)
    rightScrollFrame:SetScrollChild(rightRoot)

    titleText = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 14, -14)
    titleText:SetTextColor(1, 0.82, 0.45)

    local sep = EXUI:CreateVisualTexture(rightRoot, EXBORDERFRAME)
    sep:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
    sep:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -12, -8)
    sep:SetHeight(1)
    sep:SetColorTexture(1, 1, 1, 0.18)
    titleSep = sep

    descText = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontHighlight")
    descText:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
    descText:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetWordWrap(true)
    descText:SetTextColor(0.88, 0.88, 0.9)

    embedPlaceholder = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontHighlight")
    embedPlaceholder:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -14)
    embedPlaceholder:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    embedPlaceholder:SetJustifyH("LEFT")
    embedPlaceholder:SetTextColor(0.75, 0.75, 0.8, 1)
    embedPlaceholder:Hide()

    local EXUI = ExwindTools.UI

    CreateOverviewSection(rightRoot, descText, EXUI)
    CreateVoiceSection(rightRoot, descText, EXUI)
    CreateColorSection(rightRoot, descText, EXUI)
    CreateResetSection(rightRoot, descText)
end

function Page:Render(leftFrame, contentFrame)
    if not leftFrame or not contentFrame then return end
    embeddedHostFrame = contentFrame
    EnsureUI(leftFrame, contentFrame)
    if selectedIndex < 1 or selectedIndex > #ITEMS then
        selectedIndex = 1
    end
    EnsureSelectedCategoryExpanded()

    leftRoot:SetParent(leftFrame)
    leftRoot:ClearAllPoints()
    leftRoot:SetAllPoints(leftFrame)
    leftRoot:Show()

    rightScrollFrame:SetParent(contentFrame)
    rightScrollFrame:ClearAllPoints()
    rightScrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    rightScrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 0)
    rightRoot:SetWidth(math.max((contentFrame:GetWidth() or 0) - 28, 760))

    RefreshList()
    RefreshGeneralControls()
    RefreshVoiceControls()
    RefreshColorControls()
    RefreshRight()
end

function Page:Hide()
    HideEmbeddedPages()
    if leftRoot then leftRoot:Hide() end
    if rightRoot then rightRoot:Hide() end
    if rightScrollFrame then rightScrollFrame:Hide() end
end

function Page:SetSelectedKey(key)
    if type(key) ~= "string" or key == "" then return end
    local index = FindItemIndexByKey(key)
    if index then
        selectedIndex = index
        EnsureSelectedCategoryExpanded()
    end

    if leftRoot and embeddedHostFrame and leftRoot:IsShown() then
        RefreshList()
        RefreshGeneralControls()
        RefreshVoiceControls()
        RefreshColorControls()
        RefreshRight()
    end
end
