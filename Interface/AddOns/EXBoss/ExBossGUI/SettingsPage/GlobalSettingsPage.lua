---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local GC = ExwindTools.GUIColors

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
local encounterWarningsEnabledCheck
local encounterTimelineDisabledCheck
local colorSettingsPage
local resetSettingsPage
local embedPlaceholder
local activeButtons = {}
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

local fixedColorButtons = {}
local fixedColorLabels = {}
local customNameInput
local customColorButton
local extraCustomEnableChecks = {}
local extraCustomNameInputs = {}
local extraCustomColorButtons = {}
local ResetDisplayStylesOnly
local ResetAllConfigExceptAppearance
local ResetAllConfigIncludingAppearance

-- titleKey/descKey are locale keys resolved at render time via GetTitle/GetDesc,
-- avoiding the load-time capture bug where L["..."] would always return zhCN
-- because EXBOSS12S2 (and the saved locale mode) is not yet available at file load.
-- [卡片/Grid 迁移边界：设置目录]
-- ITEMS 顺序、key/mode/moduleKey/appearanceRoots 是路由与导出业务合同，禁止因视觉迁移改名、重排或补入不可达旧页。
-- 允许迁移的是左侧目录项外观和各真实右侧页面自己的内容布局；目录项不是大型内容卡。
local ITEMS = {
    { key = "overview",           category = "general", titleKey = "通用设置",         descKey = "全局显示模式与语音输出。",                                                                                                          mode = "embedded", moduleKey = "ExBoss.GeneralOverview", appearanceRoots = { "ui.general", "voice.global", "autoGossip" } },
    { key = "countdownvoice",     category = "general", titleKey = "语音设置",          descKey = "开怪倒数与数字语音。",                                                                                                               mode = "embedded", moduleKey = "ExBoss.CountdownVoiceSettings", appearanceRoots = { "voice.countdown" } },
    { key = "batchedit",          category = "general", titleKey = "批量修改",          descKey = "批量启用/禁用事件功能，并真实写入 override。",                                                                                        mode = "embedded", moduleKey = "ExBoss.BatchEdit" },
    { key = "color",              category = "general", titleKey = "通用颜色方案",      descKey = "4个固定颜色方案 + 1个自定义方案 + 最多3个额外方案。Boss技能页可直接选择方案或自定义颜色。",                                             mode = "embedded", moduleKey = "ExBoss.GeneralColor", appearanceRoots = { "voice.colorSchemes", "voice.customColors", "voice.extraCustomColors" } },
    { key = "timerbar",           category = "display", titleKey = "计时条",            descKey = "计时条外观、文字、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.TimerBar" },
    { key = "bunbar",             category = "display", titleKey = "束状条",            descKey = "束状条外观、轨道、位置。",                                                                                                           mode = "embedded", moduleKey = "ExBoss.BunBar" },
    { key = "countdown",          category = "display", titleKey = "[文本]5秒倒数",     descKey = "中央倒数文字与字体、位置。",                                                                                                         mode = "embedded", moduleKey = "ExBoss.Countdown" },
    { key = "flashtextmedium",    category = "display", titleKey = "[文本]文字公告(中)", descKey = "中等尺寸中央提示，供血量转阶段、易伤、站位等功能模块复用。",                                                                         mode = "embedded", moduleKey = "ExBoss.FlashTextMedium" },
    { key = "ringprogress",       category = "display", titleKey = "中央圆环",          descKey = "屏幕中央圆环进度样式、大小、位置。",                                                                                                 mode = "embedded", moduleKey = "ExBoss.RingProgress" },
    { key = "iconalert",          category = "display", titleKey = "图标",              descKey = "通用图标容器，支持 API 推入、可选发光与多图标四向增长。",                                                                             mode = "embedded", moduleKey = "ExBoss.IconAlert" },
    { key = "castprogressbar",    category = "display", titleKey = "施法进度条",        descKey = "与中央圆环同源的施法/引导进度条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.CastProgressBar" },
    { key = "extrashieldbar",     category = "display", titleKey = "护盾条",            descKey = "供首领机制复用的单体护盾监控条。",                                                                                                   mode = "embedded", moduleKey = "ExBoss.ExtraShieldBar" },
    { key = "trashcd",            category = "trash",   titleKey = "小怪内置CD姓名版图标", descKey = "小怪内置CD姓名版图标的外观与相对姓名版位置。",                                                                                              mode = "embedded", moduleKey  = "ExBoss.TrashCD.Settings" },
    { key = "reset",              category = "other",   titleKey = "重置设置",          descKey = "提供三种重置方式：重置外观、重置配置、重置外观加配置。",                                                                                  mode = "embedded" },
    { key = "dungeonextras", category = "general", titleKey = "副本额外设置", descKey = "统一副本额外提示的位置与开关；血量条共用下方外观设置，风火图保留原有样式。", mode = "embedded", moduleKey = "ExBoss.DungeonExtras" },
}

local CATEGORIES = {
    { key = "general", titleKey = "通用" },
    { key = "display", titleKey = "显示" },
    { key = "trash",   titleKey = "小怪" },
    { key = "other",   titleKey = "其他" },
}

local SIDEBAR_ICONS = {
    overview = "settings", countdownvoice = "headphones", batchedit = "pencil-line", color = "palette",
    timerbar = "timer", bunbar = "list", countdown = "hourglass", flashtextmedium = "message-square",
    ringprogress = "crosshair", iconalert = "image", castprogressbar = "wand-sparkles", extrashieldbar = "shield",
    trashcd = "castle", reset = "refresh-cw", dungeonextras = "map",
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

local function GetBarModeOptions()
    return {
        { L["束状条"], "bun" },
        { L["计时条"], "timer" },
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

local function RefreshGeneralControls()
    local g = EnsureGeneralDB()
    if barModeDropdown then
        barModeDropdown._selections = ExBoss.DisplayPolicy.GetTimelineBars()
        barModeDropdown:RefreshSelectionDisplay()
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

-- [排除边界] 这是未由当前 ITEMS 选择的旧 builtin overview；真实通用页是 GeneralOverviewPage，禁止为卡片迁移恢复此区。
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
    overviewSection:SetBackdropColor(unpack(GC.panel))
    overviewSection:SetBackdropBorderColor(unpack(GC.panelBorder))

    local overviewTitle = EXUI:CreateVisualFontString(overviewSection, EXFONTFRAME, "GameFontNormal")
    overviewTitle:SetPoint("TOPLEFT", 10, -8)
    overviewTitle:SetText(L["全局条显示模式"])
    overviewTitle:SetTextColor(unpack(GC.accent))

    if exui and exui.CreateMultiSelectDropdown then
        barModeDropdown = exui:CreateMultiSelectDropdown(
            overviewSection,
            220,
            L["显示模式"],
            GetBarModeOptions(),
            ExBoss.DisplayPolicy.GetTimelineBars(),
            function()
                EXUI:NotifyModuleValueChanged("ExBoss.GeneralOverview", "ui.general.timelineBars", "committed")
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
    overviewDesc:SetTextColor(unpack(GC.textDim))
    overviewDesc:SetText(L["控制全局显示：仅计时条 / 仅束状条 / 两者都启用 / 两者都隐藏。\n可分别关闭大秘境或团本首领提示；关闭后将整体禁用对应场景的 Boss 计时、中央文字、语音与颜色覆盖。\n可按当前职责过滤坦克类 Boss 技能提示。\n可选：首领战中自动将战斗音频预警分类音量静音（0），脱战恢复原值。"])
    overviewSection:Hide()
end

-- [标准设置页边界：通用颜色 / 重置]
-- 两页只提供原有控件与回调；页标题、说明、section、card、宽度、间距和流式高度全部由 typed sections 公共层负责。
local COLOR_PAGE_ID = "ExBoss.GeneralColor"
local RESET_PAGE_ID = "ExBoss.ResetSettings"
local COLOR_FIXED_RENDERER = "ExBoss.GeneralColor.FixedRows"
local COLOR_CUSTOM_RENDERER = "ExBoss.GeneralColor.CustomRows"
local COLOR_EXTRA_RENDERER = "ExBoss.GeneralColor.ExtraRows"
local RESET_ACTION_RENDERER = "ExBoss.ResetSettings.ActionRows"
local standardGlobalPagesRegistered = false

local function ReleaseFactoryControls(host)
    local controls = host and host._exBossOwnedControls
    host._exBossOwnedControls = nil
    local factory = _G.ExwindFactory
    for _, control in ipairs(controls or {}) do
        if control and control._fromPool and factory then
            factory:Release(control._fromPool, control)
        elseif control then
            control:Hide()
            control:ClearAllPoints()
            control:SetParent(nil)
        end
    end
end

local function TrackFactoryControl(host, control)
    host._exBossOwnedControls = host._exBossOwnedControls or {}
    host._exBossOwnedControls[#host._exBossOwnedControls + 1] = control
    return control
end

local function AddGlobalSettingsRow(host, label, isLast, fullWidth)
    local row = EXUI:CreateSettingsRow(host, {
        label = label, isLast = isLast, fullWidth = fullWidth,
    })
    host._exBossRows = host._exBossRows or {}
    local state = { row = row, fullWidth = fullWidth }
    host._exBossRows[#host._exBossRows + 1] = state
    return row, state
end

local function RegisterGlobalRowsRenderer(Grid, key, count, rowHeight, mount, update, release)
    Grid:RegisterCustomRenderer(key, {
        measure = function()
            return count * rowHeight
        end,
        mount = mount,
        update = update,
        layout = function(host, ctx, width)
            width = math.max(1, tonumber(width) or ctx:GetContentWidth())
            local y = 0
            for _, state in ipairs(host._exBossRows or {}) do
                local row = state.row
                local height, controlX, controlY, controlWidth =
                    EXUI:UpdateSettingsRowLayout(row, width, state.controlHeight or 30)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
                if state.fullWidth then
                    local available = math.max(1, width - 40)
                    local checkboxWidth = math.min(110, available * 0.23)
                    local colorWidth = math.min(145, available * 0.27)
                    local inputWidth = math.max(1, available - checkboxWidth - colorWidth - 24)
                    state.checkbox:SetSize(checkboxWidth, 28)
                    state.checkbox:ClearAllPoints()
                    state.checkbox:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -controlY)
                    state.input:SetSize(inputWidth, 28)
                    state.input:ClearAllPoints()
                    state.input:SetPoint("TOPLEFT", state.checkbox, "TOPRIGHT", 12, 0)
                    state.color:SetSize(colorWidth, 28)
                    state.color:ClearAllPoints()
                    state.color:SetPoint("TOPRIGHT", row, "TOPRIGHT", -20, -controlY)
                else
                    local control = state.control
                    local selectedWidth = math.min(controlWidth, state.maxWidth or controlWidth)
                    control:SetSize(selectedWidth, state.controlHeight or 30)
                    control:ClearAllPoints()
                    control:SetPoint("TOPLEFT", row, "TOPLEFT",
                        controlX + controlWidth - selectedWidth, -controlY)
                end
                y = y + height
            end
            ctx:SetContentHeight(y)
            return y
        end,
        release = function(host, ctx)
            release(host, ctx)
            for _, state in ipairs(host._exBossRows or {}) do
                state.row:Release()
            end
            host._exBossRows = nil
        end,
    })
end

local function CreateRegisteredGlobalPage(pageId, regionId)
    local registeredPage = { _renderGeneration = 0 }

    local function SyncScrollChildWidth()
        local sf = registeredPage._scrollFrame
        local sc = registeredPage._scrollChild
        if not sf or not sc then return end
        local width = tonumber(sf:GetWidth()) or 0
        if width < 100 then
            local contentWidth = registeredPage._contentFrame
                and tonumber(registeredPage._contentFrame:GetWidth()) or 0
            width = contentWidth >= 100 and (contentWidth - 24) or 804
        end
        width = math.max(1, width)
        if math.abs((sc:GetWidth() or 0) - width) < 0.5 then return end
        sc:SetWidth(width)
        local session = registeredPage._cardSession
        local Grid = _G.ExwindGrid
        if session and not session.released and Grid and type(Grid.RequestReflow) == "function" then
            Grid:RequestReflow(sc)
        end
    end

    local function ReleaseSession()
        registeredPage._renderGeneration = registeredPage._renderGeneration + 1
        if registeredPage._cardSession and type(registeredPage._cardSession.Release) == "function" then
            registeredPage._cardSession:Release()
        end
        registeredPage._cardSession = nil
        if EXUI.ActivePageFrame == registeredPage._scrollChild then
            EXUI.ActivePageFrame = nil
        end
        if EXUI.ActivePageScrollFrame == registeredPage._scrollFrame then
            EXUI.ActivePageScrollFrame = nil
        end
        if EXUI.CurrentModule == pageId then
            EXUI.CurrentModule = nil
        end
    end

    function registeredPage:Render(contentFrame)
        local Grid = _G.ExwindGrid
        if not Grid or not contentFrame then return end

        if not self._scrollFrame then
            local sf = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
            if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
                ExBoss.UI.ApplyModernScrollBarSkin(sf)
            end
            local sc = CreateFrame("Frame", nil, sf)
            sc:SetHeight(1)
            sf:SetScrollChild(sc)
            sf:HookScript("OnHide", ReleaseSession)
            sf:HookScript("OnSizeChanged", SyncScrollChildWidth)
            self._scrollFrame = sf
            self._scrollChild = sc
        end

        local sf = self._scrollFrame
        local sc = self._scrollChild
        self._contentFrame = contentFrame
        ReleaseSession()
        local generation = self._renderGeneration

        sf:SetParent(contentFrame)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
        sf:SetVerticalScroll(0)
        sf:Show()

        C_Timer.After(0, function()
            if registeredPage._renderGeneration ~= generation
                or not sf:IsShown()
                or sf:GetParent() ~= contentFrame then
                return
            end
            local config = _G.EXBOSS12S2
            if type(config) ~= "table" then
                error(pageId .. " requires the existing EXBOSS12S2 configuration", 0)
            end
            SyncScrollChildWidth()
            sc:SetParent(sf)
            sc:ClearAllPoints()
            sc:SetPoint("TOPLEFT", 0, 0)
            sc:Show()
            EXUI.ActivePageFrame = sc
            EXUI.ActivePageScrollFrame = sf
            EXUI.CurrentModule = pageId
            local declaration = EXUI:GetSettingsPage(pageId)
            if type(declaration) ~= "table" then
                error(pageId .. " is not registered as a settings page", 0)
            end
            registeredPage._cardSession = Grid:MountSettingsDeclaration(sc, declaration, {
                pageId = pageId,
                regionId = regionId,
                config = config,
                moduleKey = pageId,
                scrollFrame = sf,
            })
        end)
    end

    function registeredPage:Hide()
        ReleaseSession()
        if self._scrollFrame then self._scrollFrame:Hide() end
    end

    return registeredPage
end

local function RegisterStandardGlobalPages()
    if standardGlobalPagesRegistered then return end
    local Grid = _G.ExwindGrid
    if not Grid or type(Grid.RegisterCustomRenderer) ~= "function"
        or type(Grid.MountSettingsDeclaration) ~= "function"
        or type(EXUI.RegisterSettingsPage) ~= "function" then
        error("Global settings pages require the typed settings page APIs", 2)
    end

    RegisterGlobalRowsRenderer(Grid, COLOR_FIXED_RENDERER, 4, 48,
        function(host)
            local _, schemes = EnsureColorDB()
            local order = GetSchemeOrder()
            for index, key in ipairs(order) do
                local settingsRow, state = AddGlobalSettingsRow(
                    host, GetSchemeDisplayName(key), index == #order)
                local colorDB = schemes and schemes[key]
                local button = TrackFactoryControl(host, EXUI:CreateColorButton(
                    settingsRow, L["颜色"], colorDB or { r = 1, g = 1, b = 1 }, "", false,
                    function() ApplyVoiceOverrides() end))
                state.control, state.controlHeight, state.maxWidth = button, 30, 180
                fixedColorLabels[key] = settingsRow._exSettingsRowTitle
                fixedColorButtons[key] = button
            end
            RefreshColorControls()
        end,
        function()
            RefreshColorControls()
        end,
        function(host)
            for _, key in ipairs(GetSchemeOrder()) do
                fixedColorLabels[key] = nil
                fixedColorButtons[key] = nil
            end
            ReleaseFactoryControls(host)
        end)

    RegisterGlobalRowsRenderer(Grid, COLOR_CUSTOM_RENDERER, 2, 48,
        function(host)
            local _, _, custom = EnsureColorDB()
            local nameRow, nameState = AddGlobalSettingsRow(host, L["名称"], false)
            customNameInput = TrackFactoryControl(host, EXUI:CreateEditBox(
                nameRow,
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
                }))
            nameState.control, nameState.controlHeight, nameState.maxWidth =
                customNameInput, 30, 260
            local colorRow, colorState = AddGlobalSettingsRow(host, L["颜色"], true)
            customColorButton = TrackFactoryControl(host, EXUI:CreateColorButton(
                colorRow, L["自定义方案颜色"], custom or { r = 1, g = 0.82, b = 0.25 }, "", false,
                function() ApplyVoiceOverrides() end))
            colorState.control, colorState.controlHeight, colorState.maxWidth =
                customColorButton, 30, 180
            RefreshColorControls()
        end,
        function()
            RefreshColorControls()
        end,
        function(host)
            customNameInput = nil
            customColorButton = nil
            ReleaseFactoryControls(host)
        end)

    RegisterGlobalRowsRenderer(Grid, COLOR_EXTRA_RENDERER, 3, 72,
        function(host)
            local _, _, _, extraSlots = EnsureColorDB()
            local count = GetExtraCustomCount()
            for i = 1, count do
                local slot = type(extraSlots) == "table" and extraSlots[i] or nil
                if type(slot) ~= "table" then
                    slot = { enabled = false, name = L["额外方案"] .. tostring(i), r = 1, g = 0.82, b = 0.25 }
                end
                local settingsRow, state = AddGlobalSettingsRow(
                    host, L["额外方案"] .. tostring(i), i == count, true)
                state.controlHeight = 30
                local checkbox = TrackFactoryControl(host, EXUI:CreateCheckbox(settingsRow, L["启用"], slot.enabled == true, function(checked)
                    local _, _, _, slots = EnsureColorDB()
                    if type(slots) ~= "table" then return end
                    local row = slots[i]
                    if type(row) ~= "table" then
                        row = { name = L["额外方案"] .. tostring(i), r = 1, g = 0.82, b = 0.25, enabled = false }
                        slots[i] = row
                    end
                    row.enabled = (checked == true)
                    RefreshColorControls()
                    ApplyVoiceOverrides()
                end))
                local nameInput = TrackFactoryControl(host, EXUI:CreateEditBox(
                    settingsRow,
                    slot.name or (L["额外方案"] .. tostring(i)),
                    190,
                    28,
                    "",
                    {
                        onEditFocusLost = function(text)
                            local _, _, _, slots = EnsureColorDB()
                            if type(slots) ~= "table" then return end
                            local row = slots[i]
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
                            local row = slots[i]
                            if type(row) ~= "table" then
                                row = { enabled = false, r = 1, g = 0.82, b = 0.25 }
                                slots[i] = row
                            end
                            row.name = TrimOptionalText(text)
                            RefreshColorControls()
                        end,
                    }))
                local colorButton = TrackFactoryControl(host, EXUI:CreateColorButton(
                    settingsRow, L["颜色"], slot, "", false, function() ApplyVoiceOverrides() end))
                state.checkbox, state.input, state.color = checkbox, nameInput, colorButton
                extraCustomEnableChecks[i] = checkbox
                extraCustomNameInputs[i] = nameInput
                extraCustomColorButtons[i] = colorButton
            end
            RefreshColorControls()
        end,
        function()
            RefreshColorControls()
        end,
        function(host)
            for i = 1, GetExtraCustomCount() do
                extraCustomEnableChecks[i] = nil
                extraCustomNameInputs[i] = nil
                extraCustomColorButtons[i] = nil
            end
            ReleaseFactoryControls(host)
        end)

    RegisterGlobalRowsRenderer(Grid, RESET_ACTION_RENDERER, 3, 48,
        function(host)
            local styleRow, styleState = AddGlobalSettingsRow(host, L["重置外观"], false)
            local resetStyleBtn = TrackFactoryControl(host, EXUI:CreateButton(styleRow, 120, 32, L["确认"], function()
                EXUI:ShowDialog({
                    sourceAddon = "EXBoss", sourceModule = L["设置"],
                    text = L["仅重置计时条/束状条/倒计时/文字公告的外观样式，不删除法术配置。是否继续？"],
                    danger = true,
                    buttons = {
                        { id = "cancel", text = L["取消"], variant = "secondary" },
                        { id = "confirm", text = L["确定"], variant = "dangerSolid", onClick = function()
                            ResetDisplayStylesOnly()
                            ReloadUI()
                        end },
                    },
                    cancelButton = "cancel",
                })
            end))
            styleState.control, styleState.controlHeight, styleState.maxWidth =
                resetStyleBtn, 32, 120
            local configRow, configState = AddGlobalSettingsRow(host, L["重置配置"], false)
            local resetConfigBtn = TrackFactoryControl(host, EXUI:CreateButton(configRow, 120, 32, L["确认"], function()
                EXUI:ShowDialog({
                    sourceAddon = "EXBoss", sourceModule = L["设置"],
                    text = L["|cffffcc00将清空 EXBoss 的通用设置、语音配置、技能配置与时间轴设置，但保留外观样式。|r\n确认继续？"],
                    danger = true,
                    buttons = {
                        { id = "cancel", text = L["取消"], variant = "secondary" },
                        { id = "confirm", text = L["确定重置"], variant = "dangerSolid", onClick = function()
                            ResetAllConfigExceptAppearance()
                            ReloadUI()
                        end },
                    },
                    cancelButton = "cancel",
                })
            end))
            configState.control, configState.controlHeight, configState.maxWidth =
                resetConfigBtn, 32, 120
            local allRow, allState = AddGlobalSettingsRow(host, L["重置外观加配置"], true)
            local resetAllBtn = TrackFactoryControl(host, EXUI:CreateButton(allRow, 120, 32, L["确认"], function()
                EXUI:ShowDialog({
                    sourceAddon = "EXBoss", sourceModule = L["设置"],
                    text = L["|cffff4444危险：将清空 EXBoss 的全部设置（包含外观）并重载。此操作不可撤销。|r\n确认继续？"],
                    danger = true,
                    buttons = {
                        { id = "cancel", text = L["取消"], variant = "secondary" },
                        { id = "confirm", text = L["确定清空"], variant = "dangerSolid", onClick = function()
                            ResetAllConfigIncludingAppearance()
                            ReloadUI()
                        end },
                    },
                    cancelButton = "cancel",
                })
            end))
            allState.control, allState.controlHeight, allState.maxWidth =
                resetAllBtn, 32, 120
        end,
        function() end,
        ReleaseFactoryControls)

    EXUI:RegisterSettingsPage(COLOR_PAGE_ID, {
        version = 1,
        title = L["通用颜色方案"],
        description = L["4个固定颜色方案 + 1个自定义方案 + 最多3个额外方案。Boss技能页可直接选择方案或自定义颜色。"],
        sections = {
            {
                kind = "custom", id = "fixed-colors", title = L["固定方案"],
                description = L["Boss技能页面可选择下列方案；选择“自定义颜色”时使用“自定义方案”。勾选启用的额外方案会出现在技能页下拉。"],
                renderer = COLOR_FIXED_RENDERER, key = "fixedColors",
            },
            {
                kind = "custom", id = "custom-color", title = L["自定义方案"],
                renderer = COLOR_CUSTOM_RENDERER, key = "customColor",
            },
            {
                kind = "custom", id = "extra-colors", title = L["额外方案（最多3个）"],
                renderer = COLOR_EXTRA_RENDERER, key = "extraColors",
            },
        },
    })

    EXUI:RegisterSettingsPage(RESET_PAGE_ID, {
        version = 1,
        title = L["重置设置"],
        description = L["提供三种重置方式：重置外观、重置配置、重置外观加配置。"],
        sections = {
            {
                kind = "custom", id = "reset-actions", title = L["重置操作"],
                description = L["“重置外观”保留配置数据；“重置配置”保留外观；“重置外观加配置”恢复全部设置。每项操作仍会先显示原有确认提示。"],
                renderer = RESET_ACTION_RENDERER, key = "resetActions",
            },
        },
    })

    colorSettingsPage = CreateRegisteredGlobalPage(COLOR_PAGE_ID, "global-color-settings")
    resetSettingsPage = CreateRegisteredGlobalPage(RESET_PAGE_ID, "global-reset-settings")
    standardGlobalPagesRegistered = true
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
    "ExBoss.DungeonExtras",
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
    "ExBoss.DungeonExtras",
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
    ["ExBoss.DungeonExtras"] = true,
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
        if ExBoss.UI.DungeonExtras then ExBoss.UI.DungeonExtras:RefreshVisuals() end
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
        if b.IsObjectType and b:IsObjectType("Button") then
            b:SetScript("OnClick", nil)
        end
        if b._sidebarKind == "header" then
            headerPool[#headerPool + 1] = b
        else
            EXUI:ReleaseSidebarNavigationButton(b)
        end
    end
    wipe(activeButtons)
end

-- 本列表的选中态按用户选定的方案 C：底色不动、不画左侧指示条，只加一圈主色描边。
-- 只在本调用点选 "outline"，公共默认值与其他侧栏（含 ExwindTools 左树）保持现状。
local SIDEBAR_SELECTED_PRESENTATION = "outline"

local function AcquireListButton()
    local b
    if ExBoss.UI and ExBoss.UI.CreateSidebarModuleButton then
        b = ExBoss.UI.CreateSidebarModuleButton(listChild, {
            selectedPresentation = SIDEBAR_SELECTED_PRESENTATION,
        })
    elseif EXUI and EXUI.CreateSidebarNavigationButton then
        b = EXUI:CreateSidebarNavigationButton(listChild, "", nil, {
            level = 1, height = 28,
            selectedPresentation = SIDEBAR_SELECTED_PRESENTATION,
        })
    else
        error("GlobalSettings sidebar requires the shared navigation button API", 2)
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
    elseif EXUI and EXUI.CreateSidebarNavigationHeader then
        b = EXUI:CreateSidebarNavigationHeader(listChild, "", { height = 26 })
    else
        error("GlobalSettings sidebar requires the shared navigation header API", 2)
    end
    b._sidebarKind = "header"
    return b
end

local function SetupListButton(button, height, leftInset)
    button:SetHeight(height)
    local label = button.label or button.fs
    if button._exButtonPresentation ~= "sidebar" then
        label:ClearAllPoints()
        label:SetPoint("LEFT", leftInset or 14, 0)
        label:SetPoint("RIGHT", -8, 0)
    end
    label:SetJustifyH("LEFT")
    if button.Enable then button:Enable() end
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
    -- 目录切换只直接隐藏各页 _scrollFrame 并在下方清 ActivePageFrame/CurrentModule，不调用 page:Hide()。
    -- StandardModulePage 依靠 ScrollFrame OnHide 进入 teardown；非标准页只执行各自已有的 OnHide。迁移不得把预期的完整释放写成现状或另造第二条释放链。
    local pages = {
        colorSettingsPage,
        resetSettingsPage,
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
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.DungeonExtrasPage,
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
            color = colorSettingsPage,
            reset = resetSettingsPage,
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
            dungeonextras       = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.DungeonExtrasPage,
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
        titleText:ClearAllPoints()
        titleText:SetPoint("TOPLEFT", rightRoot, "TOPLEFT", 14, -14)
        titleText:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -14, -14)
    end
    if descText then
        descText:SetText(item and GetDesc(item) or "")
    end
    if titleSep and descText then
        titleSep:ClearAllPoints()
        titleSep:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
        descText:ClearAllPoints()
        descText:SetPoint("TOPLEFT", titleSep, "BOTTOMLEFT", 0, -10)
        titleSep:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -12, -8)
        descText:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    end

    if key == "overview" then
        if overviewSection then overviewSection:Show() end
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
            activeButtons[#activeButtons + 1] = header
            header:Show()
            y = y - 30
            shown = shown + 1

            for _, row in ipairs(matchedItems) do
                local i = row.index
                local item = row.item
                local b = AcquireListButton()
                SetupListButton(b, 30, 34)
                EXUI:SetSidebarNavigationButtonIcon(b, EXUI:GetIcon(SIDEBAR_ICONS[item.key]))
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
            label:SetTextColor(unpack(GC.textDisabled))
        end
        empty:Show()
        activeButtons[#activeButtons + 1] = empty
        y = y - 32
    end

    listChild:SetHeight(math.max(1, -y + 8))
end

-- [混合函数边界] EnsureUI 内只可调整目录/宿主/内置区的几何与外观；搜索、ITEMS 顺序、embedded host、回调和释放链禁止修改。
local function EnsureUI(leftFrame, contentFrame)
    RegisterStandardGlobalPages()
    if leftRoot and rightRoot then return end

    leftRoot = CreateFrame("Frame", nil, leftFrame)
    leftRoot:SetAllPoints(leftFrame)

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
        searchBox:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 10, -5)
        searchBox:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -22, -5)
    end

    listScroll = CreateFrame("ScrollFrame", nil, leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(listScroll)
    end
    listScroll:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -40)
    listScroll:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -18, 5)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(340, 1)
    listScroll:SetScrollChild(listChild)
    listScroll:HookScript("OnSizeChanged", function(_, width)
        listChild:SetWidth(math.max(1, width))
    end)

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
    titleText:SetTextColor(unpack(GC.text))

    local sep = EXUI:CreateVisualTexture(rightRoot, EXBORDERFRAME)
    sep:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -8)
    sep:SetPoint("TOPRIGHT", rightRoot, "TOPRIGHT", -12, -8)
    sep:SetHeight(1)
    sep:SetColorTexture(unpack(GC.headerDivider))
    titleSep = sep

    descText = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontHighlight")
    descText:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
    descText:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetWordWrap(true)
    descText:SetTextColor(unpack(GC.textDim))

    embedPlaceholder = EXUI:CreateVisualFontString(rightRoot, EXFONTFRAME, "GameFontHighlight")
    embedPlaceholder:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -14)
    embedPlaceholder:SetPoint("RIGHT", rightRoot, "RIGHT", -14, 0)
    embedPlaceholder:SetJustifyH("LEFT")
    embedPlaceholder:SetTextColor(unpack(GC.textPlaceholder))
    embedPlaceholder:Hide()

    local EXUI = ExwindTools.UI

    CreateOverviewSection(rightRoot, descText, EXUI)
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
    listChild:SetWidth(math.max(1, listScroll:GetWidth()))

    rightScrollFrame:SetParent(contentFrame)
    rightScrollFrame:ClearAllPoints()
    rightScrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    rightScrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 0)
    rightRoot:SetWidth(math.max((contentFrame:GetWidth() or 0) - 28, 760))
    RefreshList()
    RefreshGeneralControls()
    RefreshColorControls()
    RefreshRight()
end

function Page:Hide()
    HideEmbeddedPages()
    if leftRoot then leftRoot:Hide() end
    if rightRoot then rightRoot:Hide() end
    if rightScrollFrame then rightScrollFrame:Hide() end
end

function Page:RefreshTimelineBarControls()
    if barModeDropdown then
        barModeDropdown._selections = ExBoss.DisplayPolicy.GetTimelineBars()
        barModeDropdown:RefreshSelectionDisplay()
    end
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
        RefreshColorControls()
        RefreshRight()
    end
end
