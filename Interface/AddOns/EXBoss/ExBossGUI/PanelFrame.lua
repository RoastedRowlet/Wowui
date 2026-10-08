---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/PanelFrame.lua
-- 主面板骨架：窗口 + 顶部 Tab + 左侧导航框架 + 右侧内容区
-- 无任何外部依赖（不需要 ExwindTools / ExwindGrid / ExwindFactory）
-- =============================================================


-- 挂载到 ExBoss.UI.Panel（ExBoss.lua 已预建此表）
local Panel = ExBoss.UI.Panel
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local EXUI = _G.ExwindTools and _G.ExwindTools.UI
local GC = _G.ExwindTools and _G.ExwindTools.GUIColors

-- =============================================================
-- 常量
-- =============================================================
local PANEL_W   = 1560
local PANEL_H   = 980
local TAB_H     = 36
local TAB_BAR_Y = -30
local LEFT_W    = 380
local CONTENT_X = LEFT_W + 10

local OUTER_STRIP_W = 140
local EMBED_TOP_Y    = -36

-- [卡片/Grid 迁移边界：顶级路由]
-- TABS/redirect/dispatch 顺序与 key 是导航业务合同，禁止因卡片外观迁移改名、重排、恢复历史页或改变可达性。
-- 页面内容卡片只在各 Page 内迁移；本文件继续只拥有 Unified/fallback 宿主与切页释放。
local TABS = {
-- icon 传统一图标库的 ID（不是路径）：选项组只对 ID 图标跟随文字色上色（未选中变暗）。
    { key = "home",          label = L["首页"], icon = "house" },
    { key = "voicepack",     label = L["语音/配置"], icon = "headphones" },
    { key = "boss",          label = L["副本(首领)"], icon = "castle" },
    { key = "trash",         label = L["副本(小怪)"], icon = "list" },
    { key = "tools",         label = L["小工具"], icon = "toolbox" },
    { key = "globalsettings",label = L["设置"], icon = "settings" },
    { key = "importexport",  label = L["导入导出"], icon = "download" },
    { key = "about",         label = L["关于插件"], icon = "info" },
}

local EMBED_TABS = {
    { key = "embed:exwindtools", label = "ExwindTools" },
    { key = "embed:exaura",      label = "EXAura" },
}

-- [跨插件嵌入边界] 这是 8 个 EXBoss 内容 Tab 之外的 2 条 route：fallback 才使用下方 embedHost，Unified 必须转发到 tools/aura Provider。
-- key、左侧外挂条顺序、SetEmbedHost/ClearEmbedHost 成对调用与 Provider 转发均禁止因卡片迁移改变；相邻插件内容不归 EXBoss 卡片拥有。

-- =============================================================
-- 运行时状态
-- =============================================================
local mainFrame    = nil
local tabButtons   = {}
local tabIndexByKey = {}
local leftFrame    = nil
local contentFrame = nil
local currentTab   = "home"
local lastOwnTab   = "home"
local outerStrip   = nil
local embedHost    = nil
local embedButtons = {}
local unifiedHosts = nil
local unifiedPanel = nil

local GLOBAL_SETTINGS_REDIRECTS = {
    ["timerbar"] = "timerbar",
    ["bunbar"] = "bunbar",
    ["countdown"] = "countdown",
    ["flashtextmedium"] = "flashtextmedium",
    ["ringprogress"] = "ringprogress",
    ["iconalert"] = "iconalert",
    ["castprogressbar"] = "castprogressbar",
    ["extrashieldbar"] = "extrashieldbar",
    ["dungeonextras"] = "dungeonextras",
    -- ["targetalert"] = "targetalert", -- 临时停用
    ["mythiccast"] = "mythiccast",
    ["interrupttracker"] = "interrupttracker",

    ["ExBoss.TimerBar"] = "timerbar",
    ["ExBoss.BunBar"] = "bunbar",
    ["ExBoss.Countdown"] = "countdown",
    ["ExBoss.FlashTextMedium"] = "flashtextmedium",
    ["ExBoss.RingProgress"] = "ringprogress",
    ["ExBoss.IconAlert"] = "iconalert",
    ["ExBoss.CastProgressBar"] = "castprogressbar",
    ["ExBoss.ExtraShieldBar"] = "extrashieldbar",
    ["ExBoss.DungeonExtras"] = "dungeonextras",
    -- ["ExBoss.TargetAlert"] = "targetalert", -- 临时停用
    ["ExBoss.Tools.MythicCast"] = "mythiccast",
    ["ExBoss.Tools.InterruptTracker"] = "interrupttracker",
}

local function IsMDTEnabled()
    if ExBoss and ExBoss.MDT and type(ExBoss.MDT.IsEnabled) == "function" then
        return ExBoss.MDT.IsEnabled()
    end
    return true
end
local function BuildVisibleTabs()
    local out = {}
    for i = 1, #TABS do
        local tabDef = TABS[i]
        if tabDef.key ~= "mdt" or IsMDTEnabled() then
            out[#out + 1] = tabDef
        end
    end
    return out
end

local function NormalizeTabKey(tabKey)
    local requested = tabKey or "boss"
    if GLOBAL_SETTINGS_REDIRECTS[requested] then
        return GLOBAL_SETTINGS_REDIRECTS[requested]
    end
    if requested == "voice" then
        requested = "voicepack"
    end
    if requested == "timeline" then
        requested = "fixedtimeline"
    end
    if requested == "index" then
        requested = "home"
    end
    if requested == "general" then
        requested = "globalsettings"
    end
    if requested == "import" or requested == "export" or requested == "impexp" then
        requested = "importexport"
    end
    if requested == "trashcd" then
        requested = "trash"
    end
    if requested == "tool" or requested == "widgets" or requested == "widget" then
        requested = "tools"
    end
    return requested
end

local function IsTabVisible(tabKey)
    local key = NormalizeTabKey(tabKey)
    if key == "embed:exwindtools" or key == "embed:exaura" then
        return true
    end
    for i = 1, #TABS do
        local tabDef = TABS[i]
        if tabDef.key == key then
            if key == "mdt" then
                return IsMDTEnabled()
            end
            return true
        end
    end
    return false
end

local function ResolveSafeTab(tabKey)
    local key = NormalizeTabKey(tabKey)
    if IsTabVisible(key) then
        return key
    end
    return "home"
end

local function RefreshEditModeButtonLabel()
    if not mainFrame or not mainFrame._editModeBtn then return end
    local ET = _G.ExwindTools
    local enabled = ET and ET.UI and ET.UI:IsEditModeActive() == true
    mainFrame._editModeBtn:SetText(enabled and L["关闭编辑模式"] or L["开启编辑模式"])
end

local function TryHandleChangelogPopupOnUIOpen()
    if not (C_Timer and C_Timer.After) then
        return
    end
    C_Timer.After(0.05, function()
        if mainFrame and mainFrame:IsShown() and ExBoss and ExBoss.HandleChangelogPopupOnUIOpen then
            ExBoss:HandleChangelogPopupOnUIOpen()
        end
    end)
end

local function ShouldUseLeftNav(tabKey)
    return tabKey == "boss" or tabKey == "trash" or tabKey == "globalsettings" or tabKey == "tools"
end

local function IsEmbedTab(tabKey)
    return tabKey == "embed:exwindtools" or tabKey == "embed:exaura"
end

local function IsUnifiedMode()
    return unifiedHosts ~= nil and unifiedPanel ~= nil
end

local function ApplyModernScrollBarSkin(scrollFrame)
    if not scrollFrame then
        return
    end
    -- ScrollFrameTemplate already owns and binds exactly one native
    -- MinimalScrollBar.  Delegate only its geometry/appearance to Core.
    scrollFrame:EnableMouseWheel(true)
    EXUI:ApplyModernScrollFrame(scrollFrame)
end

ExBoss.UI.ApplyModernScrollBarSkin = ApplyModernScrollBarSkin

local function NormalizeSidebarSearchText(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value:lower()
end

local function SidebarTextContains(haystack, needle)
    local search = NormalizeSidebarSearchText(needle)
    if search == "" then
        return true
    end
    local source = NormalizeSidebarSearchText(haystack)
    return source:find(search, 1, true) ~= nil
end

local function CreateSidebarSearchBox(parent, initialText, opts)
    local config = type(opts) == "table" and opts or {}
    return EXUI:CreateSearchBox(parent, initialText or "", 1, config.height or 30, {
        onChanged = config.onChanged,
    })
end

local function CreateSidebarCategoryHeader(parent)
    return EXUI:CreateSidebarNavigationHeader(parent, "", { height = 26 })
end

-- opts.selectedPresentation 直接转给公共侧栏导航按钮（nil/"rail" = 默认的淡底+左侧指示条，
-- "outline" = 只描边）。按钮来自共享池，呈现选项每次创建都要重新传，所以不在这里写死默认值。
local function CreateSidebarModuleButton(parent, opts)
    local config = type(opts) == "table" and opts or {}
    local btn = EXUI:CreateSidebarNavigationButton(parent, "", nil, {
        level = 1,
        height = 28,
        selectedPresentation = config.selectedPresentation,
    })
    btn:SetHeight(28)
    return btn
end

local function ApplySidebarModuleButtonState(btn, isActive, isEnabled)
    if not btn then
        return
    end
    btn.isActive = isActive == true
    btn.isEnabledState = (isEnabled ~= false)
    EXUI:SetSidebarNavigationButtonState(btn, btn.isActive, btn.isEnabledState)
end

ExBoss.UI.NormalizeSidebarSearchText = NormalizeSidebarSearchText
ExBoss.UI.SidebarTextContains = SidebarTextContains
ExBoss.UI.CreateSidebarSearchBox = CreateSidebarSearchBox
ExBoss.UI.CreateSidebarCategoryHeader = CreateSidebarCategoryHeader
ExBoss.UI.CreateSidebarModuleButton = CreateSidebarModuleButton
ExBoss.UI.ApplySidebarModuleButtonState = ApplySidebarModuleButtonState

-- =============================================================
-- 插件切换嵌入 (左侧外挂标签条 -> EXBoss 画布整体渲染其他插件)
-- =============================================================
-- [嵌入生命周期边界] fallback embedHost 只承载相邻插件已有 UI：两个 embed route 间切换时清另一插件，返回 EXBoss 内容 Tab 时 UnembedActive 清两者；单纯隐藏 fallback 窗口不会清 host。
-- 不能由 EXBoss 卡片接管、复制或另行释放相邻插件内容。
local function SetOwnTopTabBarShown(shown)
    for _, btn in pairs(tabButtons) do
        if shown then btn:Show() else btn:Hide() end
    end
end

local function UpdateStripButtonStates()
    local activeKey = IsEmbedTab(currentTab) and currentTab or "exboss"
    for key, btn in pairs(embedButtons) do
        if key == activeKey then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
end

local function EnsureEmbedHost()
    if embedHost then return end
    embedHost = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    embedHost:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, EMBED_TOP_Y)
    embedHost:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
    embedHost:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    embedHost:SetBackdropColor(unpack(GC.panel))
    embedHost:SetBackdropBorderColor(unpack(GC.panelBorder))

    local placeholder = EXUI:CreateVisualFontString(embedHost, EXFONTFRAME, "GameFontNormal")
    placeholder:SetPoint("CENTER")
    placeholder:SetTextColor(unpack(GC.textDim))
    placeholder:SetJustifyH("CENTER")
    placeholder:SetText("")
    embedHost._placeholder = placeholder

    Panel.embedHost = embedHost
end

local function ClearEmbedExwindTools()
    local ET = _G.ExwindTools
    if ET and ET.UI and ET.UI.ClearEmbedHost then ET.UI:ClearEmbedHost() end
end

local function ClearEmbedEXAura()
    local EA = _G.EXAura
    if EA and EA.Editor and EA.Editor.ClearEmbedHost then EA.Editor.ClearEmbedHost() end
end

local function UnembedActive()
    ClearEmbedExwindTools()
    ClearEmbedEXAura()
end

local function EmbedExwindTools(host)
    ClearEmbedEXAura()
    local ET = _G.ExwindTools
    local ui = ET and ET.UI
    if ui and ui.SetEmbedHost then
        if host._placeholder then host._placeholder:Hide() end
        ui:SetEmbedHost(host)
    elseif host._placeholder then
        host._placeholder:SetText(L["尚未安装 ExwindTools"])
        host._placeholder:Show()
    end
end

local function EmbedEXAura(host)
    ClearEmbedExwindTools()
    local EA = _G.EXAura
    local editor = EA and EA.Editor
    if editor and editor.SetEmbedHost then
        if host._placeholder then host._placeholder:Hide() end
        editor.SetEmbedHost(host)
    elseif host._placeholder then
        host._placeholder:SetText(L["尚未安装 EXAura"])
        host._placeholder:Show()
    end
end

-- =============================================================
-- 内容区刷新
-- =============================================================
-- [混合函数边界] RefreshContent 内仅宿主 frame 的 SetPoint/SetAllPoints 属布局语句；Tab 分派、Hide 顺序、页面 Render/Hide 与嵌入清理全部禁止修改。
-- HTML special pages own only the geometry inside EXBoss's B+C host.
-- Keep navigation reachable at small widths; hiding it would remove real controls.
local function ApplySpecialPageHostGeometry()
    if not (mainFrame and leftFrame and contentFrame) then return end
    local special = currentTab == "boss" or currentTab == "trash"
    if special then
        local host = mainFrame
        -- In split mode FullContentHost is deliberately unanchored by Core.
        -- Use the live B+C body bounds, respecting the existing preview dock.
        local rightHost = IsUnifiedMode() and unifiedHosts.contentBodyHost or mainFrame
        local width = math.max(1, host:GetWidth())
        local navWidth = IsUnifiedMode() and math.max(1, unifiedHosts.navHost:GetWidth() or 0)
            or (width <= 1180 and 220 or math.max(248, math.min(320, width * 0.21)))
        local top = IsUnifiedMode() and 0 or (TAB_BAR_Y - TAB_H - 4)
        if not mainFrame._prototypeHosts then leftFrame:ClearAllPoints() end
        leftFrame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, top)
        leftFrame:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        leftFrame:SetWidth(navWidth)
        if not mainFrame._prototypeHosts then contentFrame:ClearAllPoints() end
        contentFrame:SetPoint("TOPLEFT", host, "TOPLEFT", navWidth, top)
        contentFrame:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMRIGHT", 0, 0)
        leftFrame:SetBackdropColor(unpack(GC.panel))
        contentFrame:SetBackdropColor(unpack(GC.panel))
        leftFrame:SetBackdropBorderColor(unpack(IsUnifiedMode() and GC.transparent or GC.panelBorder))
        contentFrame:SetBackdropBorderColor(unpack(GC.transparent))
        mainFrame._prototypeHosts = true
    elseif mainFrame._prototypeHosts then
        mainFrame._prototypeHosts = nil
        leftFrame:SetBackdropColor(unpack(GC.panel))
        -- Unified Shell 拥有外轮廓与 B/C 分隔线，离开特殊页也不叠加宿主方框。
        local hostBorder = IsUnifiedMode() and GC.transparent or GC.panelBorder
        leftFrame:SetBackdropBorderColor(unpack(hostBorder))
        contentFrame:SetBackdropColor(unpack(GC.panel))
        contentFrame:SetBackdropBorderColor(unpack(hostBorder))
        if not IsUnifiedMode() then
            leftFrame:ClearAllPoints()
            leftFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, TAB_BAR_Y - TAB_H - 4)
            leftFrame:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 4)
            leftFrame:SetWidth(LEFT_W)
            contentFrame:ClearAllPoints()
            contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT",
                ShouldUseLeftNav(currentTab) and CONTENT_X + 4 or 4, TAB_BAR_Y - TAB_H - 4)
            contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
        end
    end
    if not special then
        local border = (IsUnifiedMode() or currentTab == "home") and GC.transparent or GC.panelBorder
        contentFrame:SetBackdropBorderColor(unpack(border))
    end
end

local function RefreshContent()
    if not contentFrame then return end

    -- TrashCD 在 Unified 模式会把既有“副本/法术列表”挂到 Shell B；离开该页
    -- 必须主动收起，不能依赖原 content root 的 Hide（两个 pane 已不再是其 child）。
    if currentTab ~= "trash" and TrashCDPage and TrashCDPage.Hide then
        TrashCDPage:Hide()
    end

    if IsEmbedTab(currentTab) then
        SetOwnTopTabBarShown(false)
        leftFrame:Hide()
        contentFrame:Hide()
    else
        lastOwnTab = currentTab
        SetOwnTopTabBarShown(true)
        contentFrame:Show()
        if embedHost then embedHost:Hide() end
        UnembedActive()
    end

    if mainFrame then
        local useLeft = ShouldUseLeftNav(currentTab)
        local expectFull = not useLeft
        if IsUnifiedMode() and currentTab ~= "boss" and currentTab ~= "trash" then
            leftFrame:ClearAllPoints()
            leftFrame:SetAllPoints(unifiedHosts.navHost)
            contentFrame:ClearAllPoints()
            contentFrame:SetAllPoints(useLeft and unifiedHosts.contentBodyHost or unifiedHosts.fullContentHost)
            contentFrame._fullWidthMode = expectFull
        elseif not IsUnifiedMode() and contentFrame._fullWidthMode ~= expectFull then
            local contentTopY = TAB_BAR_Y - TAB_H - 4
            contentFrame:ClearAllPoints()
            if useLeft then
                contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", CONTENT_X + 4, contentTopY)
            else
                contentFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, contentTopY)
            end
            contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
            contentFrame._fullWidthMode = expectFull
        end
    end

    ApplySpecialPageHostGeometry()
    if not mainFrame._prototypeResizeHooked then
        mainFrame._prototypeResizeHooked = true
        mainFrame:HookScript("OnSizeChanged", function()
            if currentTab == "boss" or currentTab == "trash" then ApplySpecialPageHostGeometry() end
        end)
    end

    -- Blizzard 样式 Tab 高亮
    if not IsUnifiedMode() and mainFrame and PanelTemplates_SetTab then
        local tabIndex = tabIndexByKey[currentTab]
        if tabIndex then
            PanelTemplates_SetTab(mainFrame, tabIndex)
        end
    end

    -- 隐藏占位文字（各 Tab 自己决定是否显示）
    if contentFrame._placeholder then
        contentFrame._placeholder:SetText("")
        contentFrame._placeholder:Hide()
    end

    -- 隐藏各设置页的 scrollFrame（切 Tab 时清理）
    local BossPage       = ExBoss.UI.Panel.BossPage
    local FixedTimelinePage = ExBoss.UI.Panel.FixedTimelinePage
    local HomePage       = ExBoss.UI.Panel.HomePage
    local GlobalSettingsPage = ExBoss.UI.Panel.GlobalSettingsPage
    local ImportExportPage = ExBoss.UI.Panel.ImportExportPage
    local MDTPage = ExBoss.UI.Panel.MDTPage
    local OtherVoicePage = ExBoss.UI.Panel.OtherVoicePage
    local ToolsPage = ExBoss.UI.Panel.ToolsPage
    local TimerBarPage   = ExBoss.UI.Panel.TimerBarPage
    local BunBarPage     = ExBoss.UI.Panel.BunBarPage
    local CountdownPage  = ExBoss.UI.Panel.CountdownPage
    local FlashTextMediumPage = ExBoss.UI.Panel.FlashTextMediumPage
    local RingProgressPage = ExBoss.UI.Panel.RingProgressPage
    local IconAlertPage = ExBoss.UI.Panel.IconAlertPage
    local CastProgressBarPage = ExBoss.UI.Panel.CastProgressBarPage
    local ExtraShieldBarPage = ExBoss.UI.Panel.ExtraShieldBarPage
    local VoicePackPage  = ExBoss.UI.Panel.VoicePackPage
    local TrashCDPage    = ExBoss.UI.Panel.TrashCDPage
    for _, page in ipairs({
        TimerBarPage,
        BunBarPage,
        CountdownPage,
        FlashTextMediumPage,
        RingProgressPage,
        IconAlertPage,
        CastProgressBarPage,
        ExtraShieldBarPage,
        ExBoss.UI.Panel.DungeonExtrasPage,
    }) do
        if page and page._scrollFrame then page._scrollFrame:Hide() end
        if page and page.Hide then page:Hide() end
    end
    if BossPage and BossPage.Hide then BossPage:Hide() end
    if FixedTimelinePage and FixedTimelinePage.Hide then FixedTimelinePage:Hide() end
    if HomePage and HomePage.Hide then HomePage:Hide() end
    if GlobalSettingsPage and GlobalSettingsPage.Hide then GlobalSettingsPage:Hide() end
    if ImportExportPage and ImportExportPage.Hide then ImportExportPage:Hide() end
    if VoicePackPage and VoicePackPage.Hide then VoicePackPage:Hide() end
    if MDTPage and MDTPage.Hide then MDTPage:Hide() end
    if OtherVoicePage and OtherVoicePage.Hide then OtherVoicePage:Hide() end
    if ToolsPage and ToolsPage.Hide then ToolsPage:Hide() end
    if TrashCDPage and TrashCDPage.Hide then TrashCDPage:Hide() end

    -- 分发各 Tab
    if currentTab == "home" then
        leftFrame:Hide()
        if HomePage and HomePage.Render then
            HomePage:Render(contentFrame)
        elseif contentFrame._placeholder then
            contentFrame._placeholder:SetText(L["首页（占位）"])
            contentFrame._placeholder:Show()
        end

    elseif currentTab == "boss" then
        leftFrame:Show()
        if BossPage and BossPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            BossPage:Render(leftFrame, contentFrame)
        else
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Show()
            end
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["BOSS技能页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "fixedtimeline" then
        leftFrame:Hide()
        if FixedTimelinePage and FixedTimelinePage.Render then
            FixedTimelinePage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["固定时间轴预览页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "mdt" then
        leftFrame:Hide()
        if MDTPage and MDTPage.Render then
            MDTPage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["MDT页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "globalsettings" then
        leftFrame:Show()
        if GlobalSettingsPage and GlobalSettingsPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            GlobalSettingsPage:Render(leftFrame, contentFrame)
        else
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Show()
            end
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["通用设置页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "voicepack" then
        leftFrame:Hide()
        if VoicePackPage and VoicePackPage.Render then
            local ok, err = pcall(function()
                VoicePackPage:Render(contentFrame)
            end)
            if not ok and contentFrame._placeholder then
                contentFrame._placeholder:SetText(string.format(L["语音包设置页异常:\n%s"], tostring(err)))
                contentFrame._placeholder:Show()
            end
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["语音包设置页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "othervoice" then
        leftFrame:Hide()
        if OtherVoicePage and OtherVoicePage.Render then
            local ok, err = pcall(function()
                OtherVoicePage:Render(contentFrame)
            end)
            if not ok and contentFrame._placeholder then
                contentFrame._placeholder:SetText(string.format(L["其他语音页异常:\n%s"], tostring(err)))
                contentFrame._placeholder:Show()
            end
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["其他语音页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "importexport" then
        leftFrame:Hide()
        if ImportExportPage and ImportExportPage.Render then
            ImportExportPage:Render(contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["导入导出页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "trash" then
        leftFrame:Show()
        if TrashCDPage and TrashCDPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            TrashCDPage:Render(IsUnifiedMode() and leftFrame or nil, contentFrame)
        else
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(L["小怪CD页未就绪"])
                contentFrame._placeholder:Show()
            end
        end

    elseif currentTab == "tools" then
        leftFrame:Show()
        if ToolsPage and ToolsPage.Render then
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Hide()
            end
            ToolsPage:Render(leftFrame, contentFrame)
        else
            if leftFrame._placeholderLabel then
                leftFrame._placeholderLabel:Show()
            end
            if contentFrame._placeholder then
                contentFrame._placeholder:SetText(string.format(L["设置页 [%s] — 待开发"], L["小工具"]))
                contentFrame._placeholder:Show()
            end
        end

    elseif IsEmbedTab(currentTab) then
        EnsureEmbedHost()
        embedHost:Show()
        if currentTab == "embed:exwindtools" then
            EmbedExwindTools(embedHost)
        else
            EmbedEXAura(embedHost)
        end

    else
        leftFrame:Hide()
        if contentFrame._placeholder then
            contentFrame._placeholder:SetText(string.format(L["设置页 [%s] — 待开发"], currentTab))
            contentFrame._placeholder:Show()
        end
    end

    UpdateStripButtonStates()
end

local function FlushFocusedEditBox()
    local focus = type(GetCurrentKeyBoardFocus) == "function" and GetCurrentKeyBoardFocus() or nil
    if not focus then
        return
    end
    if focus.IsObjectType and focus:IsObjectType("EditBox") and focus.ClearFocus then
        focus:ClearFocus()
    end
end

-- =============================================================
-- 窗口创建（懒加载，只执行一次）
-- =============================================================
-- [宿主边界] 只可按共享外观调整 EXBoss 内容 root/nav/content 的几何与背景；不能在这里替各页面创建卡片或接管其释放。
local function CreateUnifiedPanel()
    if mainFrame then return end
    local shellFrame = unifiedHosts.contentHost:GetParent()
    mainFrame = CreateFrame("Frame", nil, shellFrame, "BackdropTemplate")
    mainFrame:SetPoint("TOPLEFT", unifiedHosts.navHost, "TOPLEFT", 0, 0)
    mainFrame:SetPoint("BOTTOMRIGHT", unifiedHosts.contentHost, "BOTTOMRIGHT", 0, 0)
    mainFrame:SetFrameStrata(shellFrame:GetFrameStrata())
    mainFrame:Hide()

    leftFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    leftFrame:SetAllPoints(unifiedHosts.navHost)
    leftFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    leftFrame:SetBackdropColor(unpack(GC.panel))
    leftFrame:SetBackdropBorderColor(unpack(GC.transparent))
    Panel.leftFrame = leftFrame

    contentFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    contentFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    contentFrame:SetBackdropColor(unpack(GC.panel))
    contentFrame:SetBackdropBorderColor(unpack(GC.transparent))
    local placeholder = EXUI:CreateVisualFontString(contentFrame, EXFONTFRAME, "GameFontNormal")
    placeholder:SetPoint("CENTER")
    placeholder:SetTextColor(unpack(GC.textDim))
    contentFrame._placeholder = placeholder
    Panel.contentFrame = contentFrame
    Panel._frame = mainFrame
end

-- [窗口边界：fallback] 仅可迁移旧独立窗口 chrome 与几何；拖动、ESC、Tab 状态机、路由、焦点提交和 Unified 回退条件禁止修改。
local function CreatePanel()
    if mainFrame then return end

    if IsUnifiedMode() then
        CreateUnifiedPanel()
        return
    end


    -- ── 主窗口 ────────────────────────────────────────────────
    mainFrame = CreateFrame("Frame", "ExBoss_MainPanel", UIParent, "BackdropTemplate")
    mainFrame:SetSize(PANEL_W, PANEL_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    -- 允许用户将窗口拖出屏幕边界（多屏/截图/排版场景）
    mainFrame:SetClampedToScreen(false)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    mainFrame:SetScript("OnHide", function()
        FlushFocusedEditBox()
        local HomePage = ExBoss.UI.Panel.HomePage
        if HomePage then HomePage:Hide() end
    end)
    mainFrame:Hide()

    -- 支持 ESC 关闭
    if not tContains(UISpecialFrames, "ExBoss_MainPanel") then
        table.insert(UISpecialFrames, "ExBoss_MainPanel")
    end

    mainFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    mainFrame:SetBackdropColor(unpack(GC.panel))
    mainFrame:SetBackdropBorderColor(unpack(GC.panelBorder))

    -- ── 标题栏 ────────────────────────────────────────────────
    local titleBar = EXUI:CreateVisualTexture(mainFrame, EXBACKGROUNDFRAME)
    titleBar:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  4, -4)
    titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(28)
    titleBar:SetColorTexture(unpack(GC.header))

    local titleText = EXUI:CreateVisualFontString(mainFrame, EXFONTFRAME, "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cffff4400Ex|r|cff00ccffBoss|r  v" .. ExBoss.VERSION)

    -- ── 面板缩放控件 ──────────────────────────────────────────
    local scaleLabel = EXUI:CreateVisualFontString(mainFrame, EXFONTFRAME, "GameFontNormalSmall")
    scaleLabel:SetPoint("LEFT", titleText, "RIGHT", 16, 0)
    scaleLabel:SetText(L["缩放"])
    scaleLabel:SetTextColor(unpack(GC.textDim))

    local scaleDropdown
    local function ApplyPanelScale(pct)
        if EXBOSS12S2 and EXBOSS12S2.ui and EXBOSS12S2.ui.general then
            EXBOSS12S2.ui.general.panelScale = pct
        end
        mainFrame:SetScale(pct / 100)
        scaleDropdown:SetText(pct .. "%")
        scaleDropdown._currentValue = pct
    end
    mainFrame._applyPanelScale = ApplyPanelScale

    local scaleOptions = { 70, 75, 80, 85, 90, 95, 100, 105, 110 }
    local scaleItems = {}
    for _, pct in ipairs(scaleOptions) do
        scaleItems[#scaleItems + 1] = { pct .. "%", pct }
    end
    scaleDropdown = EXUI:CreateDropdown(mainFrame, 100, "", scaleItems, 100, function(pct)
        ApplyPanelScale(pct)
    end, false)
    scaleDropdown:SetPoint("LEFT", scaleLabel, "RIGHT", 6, 0)
    scaleDropdown:SetFrameLevel(mainFrame:GetFrameLevel() + 30)

    local initPct = (EXBOSS12S2 and EXBOSS12S2.ui and EXBOSS12S2.ui.general and EXBOSS12S2.ui.general.panelScale) or 100
    initPct = math.max(70, math.min(110, initPct))
    scaleDropdown._currentValue = initPct
    scaleDropdown:SetText(initPct .. "%")
    mainFrame:SetScale(initPct / 100)

    -- 标题栏拖拽层：避免内容区控件吞掉鼠标，确保始终可拖动窗口
    local dragHandle = CreateFrame("Frame", nil, mainFrame)
    dragHandle:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        mainFrame:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
    end)

    -- 关闭按钮
    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        FlushFocusedEditBox()
        mainFrame:Hide()
    end)

    -- 标题栏右上角：编辑模式按钮（沿用 ExwindTools 的全局编辑模式逻辑）
    local editModeBtn = EXUI:CreateButton(mainFrame, 120, 22, "", nil, { compact = true })
    editModeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, -1)
    editModeBtn:SetScript("OnClick", function()
        local ET = _G.ExwindTools
        if ET and ET.UI and ET.UI.ToggleEditMode then
            ET.UI:ToggleEditMode()
            RefreshEditModeButtonLabel()
            if ET.UI:IsEditModeActive() and mainFrame:IsShown() then
                FlushFocusedEditBox()
                mainFrame:Hide()
            end
        end
    end)
    mainFrame._editModeBtn = editModeBtn
    RefreshEditModeButtonLabel()

    -- 让拖拽层避开“编辑模式 + 关闭”按钮区域，避免按钮无法点击。
    dragHandle:SetPoint("RIGHT", editModeBtn, "LEFT", -6, 0)

    -- ── 左侧外挂插件切换标签条 ────────────────────────────────
    outerStrip = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    outerStrip:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", 1, 0)
    outerStrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMLEFT", 1, 0)
    outerStrip:SetWidth(OUTER_STRIP_W)
    outerStrip:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    outerStrip:SetBackdropColor(unpack(GC.panel))
    outerStrip:SetBackdropBorderColor(unpack(GC.panelBorder))

    local function MakeStripButton(label, onClick)
        local btn = CreateFrame("Button", nil, outerStrip, "UIPanelButtonTemplate")
        btn:SetSize(OUTER_STRIP_W - 16, 32)
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            FlushFocusedEditBox()
            onClick()
            RefreshContent()
        end)
        return btn
    end

    local ownBtn = MakeStripButton(L["EXBoss"], function()
        currentTab = ResolveSafeTab(lastOwnTab)
    end)
    ownBtn:SetPoint("TOP", outerStrip, "TOP", 0, -12)
    embedButtons["exboss"] = ownBtn

    local prevStripBtn = ownBtn
    for _, def in ipairs(EMBED_TABS) do
        local btn = MakeStripButton(def.label, function()
            currentTab = def.key
        end)
        btn:SetPoint("TOP", prevStripBtn, "BOTTOM", 0, -8)
        embedButtons[def.key] = btn
        prevStripBtn = btn
    end

    -- ── 顶部 Tab 栏 ───────────────────────────────────────────
    local tabBarY = TAB_BAR_Y
    local prevTab = nil
    local visibleTabs = BuildVisibleTabs()
    for i, tabDef in ipairs(visibleTabs) do
        local btn = CreateFrame("Button", "ExBoss_MainPanelTab" .. i, mainFrame, "PanelTopTabButtonTemplate")
        btn:SetID(i)
        if prevTab then
            btn:SetPoint("LEFT", prevTab, "RIGHT", -15, 0)
        else
            btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, tabBarY)
        end
        btn:SetText(tabDef.label)
        if PanelTemplates_TabResize then
            PanelTemplates_TabResize(btn, 0)
        end
        btn._tabKey = tabDef.key

        btn:SetScript("OnClick", function(self)
            FlushFocusedEditBox()
            currentTab = self._tabKey
            RefreshContent()
        end)

        tabButtons[tabDef.key] = btn
        tabIndexByKey[tabDef.key] = i
        prevTab = btn
    end
    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(mainFrame, #visibleTabs)
    end

    -- ── 左侧导航框架 ──────────────────────────────────────────
    local contentTopY = tabBarY - TAB_H - 4
    leftFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    leftFrame:SetPoint("TOPLEFT",    mainFrame, "TOPLEFT",  4, contentTopY)
    leftFrame:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 4)
    leftFrame:SetWidth(LEFT_W)
    leftFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    leftFrame:SetBackdropColor(unpack(GC.panel))
    leftFrame:SetBackdropBorderColor(unpack(GC.panelBorder))

    local leftLabel = EXUI:CreateVisualFontString(leftFrame, EXFONTFRAME, "GameFontNormalSmall")
    leftLabel:SetPoint("TOP", leftFrame, "TOP", 0, -10)
    leftLabel:SetTextColor(unpack(GC.textDim))
    leftLabel:SetText(L["副本 / BOSS 导航\n(待开发)"])
    leftFrame._placeholderLabel = leftLabel

    Panel.leftFrame = leftFrame

    -- ── 右侧内容区 ────────────────────────────────────────────
    contentFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    contentFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",  CONTENT_X + 4, contentTopY)
    contentFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
    contentFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8, edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    contentFrame:SetBackdropColor(unpack(GC.panel))
    contentFrame:SetBackdropBorderColor(unpack(GC.panelBorder))
    Panel.contentFrame = contentFrame

    -- 占位文字
    local placeholder = EXUI:CreateVisualFontString(contentFrame, EXFONTFRAME, "GameFontNormal")
    placeholder:SetPoint("CENTER")
    placeholder:SetTextColor(unpack(GC.textDim))
    placeholder:SetJustifyH("CENTER")
    placeholder:SetText("")
    contentFrame._placeholder = placeholder

    -- ── 底部状态栏 ────────────────────────────────────────────
    local statusText = EXUI:CreateVisualFontString(mainFrame, EXFONTFRAME, "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 12, 8)
    statusText:SetTextColor(unpack(GC.textDim))
    statusText:SetText(L["/exb  打开/关闭    |    /exb edit  编辑模式"])
    Panel.statusText = statusText

    local changelogBtn = EXUI:CreateButton(mainFrame, 88, 22, L["更新日志"], function()
        if ExBoss and ExBoss.ShowChangelog then
            ExBoss:ShowChangelog({ markShown = true })
        end
    end, { compact = true })
    changelogBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -12, 6)
    changelogBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 40)
    Panel.changelogBtn = changelogBtn

    Panel._frame = mainFrame
end

-- =============================================================
-- 公开接口
-- =============================================================
function Panel:GetCurrentTab()
    return currentTab
end

function Panel:MountUnified(hosts, shell)
    if mainFrame and not IsUnifiedMode() then
        error(L["[EXBoss] 旧独立面板已创建；请 /reload 后从 Unified Shell 打开"], 2)
    end
    unifiedHosts, unifiedPanel = hosts, shell
    CreatePanel()
end

function Panel:RelayoutUnified()
    if not IsUnifiedMode() or not mainFrame then return end
    mainFrame:SetPoint("TOPLEFT", unifiedHosts.navHost, "TOPLEFT", 0, 0)
    mainFrame:SetPoint("BOTTOMRIGHT", unifiedHosts.contentHost, "BOTTOMRIGHT", 0, 0)
    ApplySpecialPageHostGeometry()
end

function Panel:RefreshUnifiedTabs()
    if not IsUnifiedMode() then return end
    unifiedPanel:SetTopTabs("boss", BuildVisibleTabs(), currentTab, function(tabKey)
        unifiedPanel:SelectProvider("boss", { tab = tabKey })
    end, { choiceGroup = true })
end

function Panel:Toggle()
    local router = ExwindTools and ExwindTools.PanelRouter
    if router and router.Toggle then
        return router:Toggle("boss")
    end
    if IsUnifiedMode() then
        if unifiedPanel.Frame and unifiedPanel.Frame:IsShown() and unifiedPanel.ActiveProvider == "boss" then
            unifiedPanel:Hide()
        else
            unifiedPanel:Show("boss")
        end
        return
    end
    CreatePanel()
    currentTab = ResolveSafeTab(currentTab)
    RefreshEditModeButtonLabel()
    if mainFrame:IsShown() then
        FlushFocusedEditBox()
        mainFrame:Hide()
    else
        mainFrame:Show()
        local BossPage = ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
        if BossPage and BossPage.OnPanelShown then
            BossPage:OnPanelShown()
        end
        RefreshContent()
        TryHandleChangelogPopupOnUIOpen()
    end
end

function Panel:Show()
    local router = ExwindTools and ExwindTools.PanelRouter
    if router and router.Open then
        return router:Open("boss")
    end
    if IsUnifiedMode() then
        unifiedPanel:Show("boss")
        return
    end
    CreatePanel()
    currentTab = ResolveSafeTab(currentTab)
    RefreshEditModeButtonLabel()
    mainFrame:Show()
    local BossPage = ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
    if BossPage and BossPage.OnPanelShown then
        BossPage:OnPanelShown()
    end
    RefreshContent()
    TryHandleChangelogPopupOnUIOpen()
end

function Panel:Hide()
    FlushFocusedEditBox()
    if IsUnifiedMode() then
        if mainFrame then mainFrame:Hide() end
        return
    end
    if mainFrame then mainFrame:Hide() end
end

function Panel:SetTab(tabKey)
    local requested = NormalizeTabKey(tabKey)
    -- 旧外挂条的两个目标在 Unified 模式不再是 EXBoss 内部 Tab；直接切换
    -- Shell Provider，绝不能落入 RefreshContent() 的旧 SetEmbedHost 路径。
    if IsUnifiedMode() and requested == "embed:exwindtools" then
        unifiedPanel:Show("tools")
        return
    elseif IsUnifiedMode() and requested == "embed:exaura" then
        unifiedPanel:Show("aura")
        return
    end
    if GLOBAL_SETTINGS_REDIRECTS[requested] then
        requested = GLOBAL_SETTINGS_REDIRECTS[requested]
    end
    if requested == "timerbar"
        or requested == "bunbar"
        or requested == "countdown"
        or requested == "flashtextmedium"
        or requested == "ringprogress"
        or requested == "iconalert"
        or requested == "castprogressbar"
        or requested == "extrashieldbar"
        or requested == "dungeonextras"
    then
        local globalPage = ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalSettingsPage
        if globalPage and globalPage.SetSelectedKey then
            globalPage:SetSelectedKey(requested)
        end
        requested = "globalsettings"
    end
    if requested == "mythiccast" or requested == "interrupttracker" then
        local toolsPage = ExBoss.UI.Panel and ExBoss.UI.Panel.ToolsPage
        if toolsPage and toolsPage.SetSelectedKey then
            toolsPage:SetSelectedKey(requested)
        end
        requested = "tools"
    end
    currentTab = ResolveSafeTab(requested)
    if IsUnifiedMode() then
        unifiedPanel:SaveActiveRoute("boss", { tab = currentTab })
        Panel:RefreshUnifiedTabs()
    end
    if mainFrame and mainFrame:IsShown() then
        FlushFocusedEditBox()
        RefreshContent()
    end
end
