-- =========================================================
-- ExwindUnifiedPanel.lua
-- Core 原生拥有的三合一面板外壳。
--
-- Phase 1 只建立 Shell、Provider Registry、持久化和 Core-only 空状态。
-- 本文件不注册 Tools/EXBoss/EXAura Provider，不读取它们的数据，也不嵌入旧窗口。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L

local Theme = ExwindTools.PanelTheme
if not Theme then
    error(L["[ExwindUnifiedPanel] ExwindPanelTheme.lua 必须先加载"])
end

local Layout = Theme.Layout
local Color = Theme.Color
local Backdrop = Theme.Backdrop
local Panel = ExwindTools.UnifiedPanel or {}
ExwindTools.UnifiedPanel = Panel

Panel.Providers = Panel.Providers or {}
Panel.ProviderOrder = Panel.ProviderOrder or { "tools", "boss", "aura" }
Panel.ProviderMeta = Panel.ProviderMeta or {
    tools = { title = "EXWINDTOOLS", short = "T", accent = "cyan" },
    boss = { title = "EXBOSS", short = "B", accent = "gold" },
    aura = { title = "EXAURA", short = "A", accent = "violet" },
    -- "settings" 不在 ProviderOrder 里，不会被 RebuildAppRail 生成圆形图标；
    -- 只用于 UpdateHeader 在设置页显示正确标题。
    settings = { title = "SETTINGS", short = "S", accent = "cyan" },
}
Panel.LayoutMode = Panel.LayoutMode or "tabs_full"

local function CopyColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function GetFont()
    return ExwindTools.MAIN_FONT or STANDARD_TEXT_FONT
end

local function SetText(fontString, text, size, color, flags)
    fontString:SetFont(GetFont(), size or 12, flags or "")
    fontString:SetText(text or "")
    if color then
        fontString:SetTextColor(CopyColor(color))
    end
end

local function MakeSolidFrame(parent, color, borderColor)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop(Backdrop)
    frame:SetBackdropColor(CopyColor(color or Color.card))
    frame:SetBackdropBorderColor(CopyColor(borderColor or Color.border))
    return frame
end

-- 标题栏与 Tab 处于同一个连续背景内；这里刻意不建立边框，避免顶部出现
-- 多余分隔线或让 Tab 看起来像一排按钮。
local function MakeFlatFrame(parent, color)
    local frame = CreateFrame("Frame", nil, parent)
    local background = EXUI:CreateVisualTexture(frame, EXBACKGROUNDFRAME)
    background:SetAllPoints()
    background:SetColorTexture(CopyColor(color or Color.header))
    frame.Background = background
    return frame
end

local function MakeText(parent, _, size, color, flags)
    local text = EXUI:CreateVisualFontString(parent, EXFONTFRAME)
    SetText(text, "", size, color, flags)
    return text
end

local function GetSavedState()
    _G.EXCORE12S2 = _G.EXCORE12S2 or {}
    _G.EXCORE12S2.UnifiedPanel = _G.EXCORE12S2.UnifiedPanel or {}
    return _G.EXCORE12S2.UnifiedPanel
end

-- Shell 只持久化 route 的轻量标量（tab/page/moduleKey 等），绝不把 Provider
-- 的业务 table、规则或 Boss 数据写进 Core SavedVariables。
local function CopyRoute(route)
    if type(route) == "string" then return route end
    if type(route) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(route) do
        local valueType = type(value)
        if (type(key) == "string" or type(key) == "number")
            and (valueType == "string" or valueType == "number" or valueType == "boolean")
        then
            copy[key] = value
        end
    end
    return next(copy) and copy or nil
end

function Panel:GetSavedRoute(id)
    local state = GetSavedState()
    local routes = state.routes
    return routes and CopyRoute(routes[id]) or nil
end

function Panel:SaveActiveRoute(id, route)
    if not id then return end
    -- "settings" 是固定齿轮按钮打开的伪 Provider，不参与"记住上次打开的
    -- Provider"这套记忆逻辑，否则下次开面板会卡在设置页而不是业务页。
    if id == "settings" then return end
    local state = GetSavedState()
    state.lastProvider = id
    local copied = CopyRoute(route)
    if copied ~= nil then
        state.routes = state.routes or {}
        state.routes[id] = copied
    end
end

function Panel:GetMetrics()
    local frame = self.Frame
    local width = frame and frame:GetWidth() or Layout.DEFAULT_WIDTH
    local height = frame and frame:GetHeight() or Layout.DEFAULT_HEIGHT
    local workspaceWidth = math.max(1, width - Layout.APP_RAIL_WIDTH)
    -- Shell 默认 B:C=25:75；Provider 可显式声明唯一的页面级比例例外。
    local navRatio = tonumber(self.ActiveNavRatio) or Layout.NAV_RATIO
    local navWidth = math.floor(workspaceWidth * navRatio + 0.5)
    local tabVisible = self.TopTabHost and self.TopTabHost:IsShown()
    local workspaceHeight = math.max(1, height - Layout.HEADER_HEIGHT - (tabVisible and Layout.TOP_TAB_HEIGHT or 0))

    return {
        panelWidth = width,
        panelHeight = height,
        appRailWidth = Layout.APP_RAIL_WIDTH,
        headerHeight = Layout.HEADER_HEIGHT,
        tabHeight = tabVisible and Layout.TOP_TAB_HEIGHT or 0,
        workspaceWidth = workspaceWidth,
        workspaceHeight = workspaceHeight,
        navWidth = navWidth,
        navRatio = navRatio,
        contentWidth = math.max(1, workspaceWidth - navWidth),
        spacing = Layout.CONTENT_GUTTER,
        splitGridCols = Layout.SPLIT_CONTENT_GRID_COLS,
        fullGridCols = Layout.FULL_CONTENT_GRID_COLS,
    }
end

function Panel:SaveGeometry()
    if not self.Frame then return end
    local state = GetSavedState()
    local point, _, relativePoint, x, y = self.Frame:GetPoint(1)
    state.point = point or "CENTER"
    state.relativePoint = relativePoint or "CENTER"
    state.x = tonumber(x) or 0
    state.y = tonumber(y) or 0
end

function Panel:RestoreGeometry()
    local state = GetSavedState()
    -- Shell 尺寸是统一面板的固定视觉规格；旧版本保存过的 width/height
    -- 只作为遗留数据保留，不再读取，避免曾经拖拽过的尺寸持续影响布局比例。
    self.Frame:SetSize(Layout.DEFAULT_WIDTH, Layout.DEFAULT_HEIGHT)
    self.Frame:ClearAllPoints()
    self.Frame:SetPoint(state.point or "CENTER", UIParent, state.relativePoint or "CENTER", tonumber(state.x) or 0, tonumber(state.y) or 0)
    self.Frame:SetScale(tonumber(state.scale) or 1)
end

-- scalePercent 是整数百分比（60~110），只做 SetScale；不改 Point/Size，
-- 因此不影响拖拽或 Grid 的像素计算——两者都读取的是缩放前的逻辑尺寸。
function Panel:SetScale(scalePercent)
    local scale = Clamp((tonumber(scalePercent) or 100) / 100, 0.6, 1.1)
    local state = GetSavedState()
    state.scale = scale
    if self.Frame then
        self.Frame:SetScale(scale)
    end
end

function Panel:GetScale()
    local state = GetSavedState()
    return math.floor((tonumber(state.scale) or 1) * 100 + 0.5)
end

function Panel:HideAllHosts()
    if self.NavHost then self.NavHost:Hide() end
    if self.ContentHost then self.ContentHost:Hide() end
    if self.FullContentHost then self.FullContentHost:Hide() end
    if self.PreviewDock then self.PreviewDock:Hide() end
end

function Panel:ApplyLayout(mode, options)
    if not self.Frame then return end
    options = options or {}
    mode = mode or "tabs_full"
    if mode ~= "split" and mode ~= "tabs_split" and mode ~= "tabs_full" then
        error(L["[ExwindUnifiedPanel] 未知布局模式: "] .. tostring(mode))
    end

    self.LayoutMode = mode
    local hasTabs = (mode ~= "split") and options.showTabs ~= false
    local hasNav = mode ~= "tabs_full"
    local requestedRatio = tonumber(options.navRatio)
    self.ActiveNavRatio = (requestedRatio and requestedRatio > 0 and requestedRatio < 1) and requestedRatio or nil
    self.TopTabHost:SetShown(hasTabs)
    self:HideAllHosts()

    local metrics = self:GetMetrics()
    self.NavHost:ClearAllPoints()
    self.ContentHost:ClearAllPoints()
    self.FullContentHost:ClearAllPoints()

    if hasNav then
        self.NavHost:SetWidth(metrics.navWidth)
        self.NavHost:SetPoint("TOPLEFT", self.Frame, "TOPLEFT", Layout.APP_RAIL_WIDTH, -(Layout.HEADER_HEIGHT + (hasTabs and Layout.TOP_TAB_HEIGHT or 0)))
        self.NavHost:SetPoint("BOTTOMLEFT", self.Frame, "BOTTOMLEFT", Layout.APP_RAIL_WIDTH, 0)
        self.ContentHost:SetPoint("TOPLEFT", self.NavHost, "TOPRIGHT", 0, 0)
        self.ContentHost:SetPoint("BOTTOMRIGHT", self.Frame, "BOTTOMRIGHT", 0, 0)
        self.NavHost:Show()
        self.ContentHost:Show()
    else
        self.FullContentHost:SetPoint("TOPLEFT", self.Frame, "TOPLEFT", Layout.APP_RAIL_WIDTH, -(Layout.HEADER_HEIGHT + (hasTabs and Layout.TOP_TAB_HEIGHT or 0)))
        self.FullContentHost:SetPoint("BOTTOMRIGHT", self.Frame, "BOTTOMRIGHT", 0, 0)
        self.FullContentHost:Show()
    end

    -- ContentBody 是所有需要 B+C 的 Provider 的实际业务画布。预览/辅助栏改变
    -- 时必须收缩它，而不是只把一个新 Frame 叠在上面；否则 C 区会被遮住。
    self:UpdateContentBodyBounds()

    if self.ActiveProvider then
        local provider = self.Providers[self.ActiveProvider]
        if provider and type(provider.Relayout) == "function" then
            provider:Relayout(self:GetMetrics())
        end
    else
        self:ShowCoreStatus()
    end
end

function Panel:UpdateContentBodyBounds()
    local host = self.ContentHost
    local body = self.ContentBodyHost
    if not host or not body then return end

    body:ClearAllPoints()
    local topHost = self.PreviewDock and self.PreviewDock:IsShown() and self.PreviewDock or host
    local topPoint = topHost == host and "TOP" or "BOTTOM"
    body:SetPoint("TOPLEFT", topHost, topPoint .. "LEFT", 0, 0)
    body:SetPoint("TOPRIGHT", topHost, topPoint .. "RIGHT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    body:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
end

function Panel:SetPreviewDockVisible(visible, height)
    if not self.PreviewDock then return end
    height = Clamp(tonumber(height) or Layout.PREVIEW_DOCK_HEIGHT, 1, Layout.PREVIEW_DOCK_HEIGHT)
    self.PreviewDock:SetHeight(visible and height or 1)
    self.PreviewDock:SetShown(visible == true)

    self:UpdateContentBodyBounds()
end

function Panel:CreateWelcomeContent()
    if self.CoreStatusRoot then return end
    local root = CreateFrame("Frame", nil, self.FullContentHost)
    root:SetAllPoints()
    self.CoreStatusRoot = root

    local card = MakeSolidFrame(root, Color.card, Color.border)
    card:SetSize(520, 254)
    card:SetPoint("CENTER", 0, 2)
    self.CoreStatusCard = card

    local accent = EXUI:CreateVisualTexture(card, EXBASEFRAME)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(CopyColor(Color.cyan))

    local eyebrow = MakeText(card, "OVERLAY", 10, Color.cyan, "OUTLINE")
    eyebrow:SetPoint("TOPLEFT", 22, -22)
    eyebrow:SetText("EXWINDCORE · UNIFIED PANEL")

    local title = MakeText(card, "OVERLAY", 23, Color.text, "")
    title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -9)
    title:SetText(L["核心面板已就绪"])

    local description = MakeText(card, "OVERLAY", 12, Color.muted, "")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    description:SetPoint("RIGHT", card, "RIGHT", -22, 0)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetWordWrap(true)
    description:SetText(L["ExwindCore 可以独立打开此面板。已安装并完成注册的 ExwindTools、EXBoss、EXAura 会出现在最左侧三枚插件入口中。"])

    local line = EXUI:CreateVisualTexture(card, EXBASEFRAME)
    line:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
    line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -22, -125)
    line:SetHeight(1)
    line:SetColorTexture(CopyColor(Color.borderSoft))

    self.CoreStatusRows = {}
    for index, id in ipairs(self.ProviderOrder) do
        local row = CreateFrame("Frame", nil, card)
        row:SetHeight(27)
        row:SetPoint("TOPLEFT", 22, -143 - (index - 1) * 31)
        row:SetPoint("RIGHT", card, "RIGHT", -22, 0)

        local dot = EXUI:CreateVisualTexture(row, EXBASEFRAME)
        dot:SetSize(7, 7)
        dot:SetPoint("LEFT", 0, 0)
        row.dot = dot

        local label = MakeText(row, "OVERLAY", 12, Color.text, "")
        label:SetPoint("LEFT", dot, "RIGHT", 9, 0)
        row.label = label

        local status = MakeText(row, "OVERLAY", 10, Color.muted, "OUTLINE")
        status:SetPoint("RIGHT", 0, 0)
        row.status = status
        self.CoreStatusRows[id] = row
    end
end

function Panel:ShowCoreStatus()
    if not self.FullContentHost then return end
    self:CreateWelcomeContent()
    self.CoreStatusRoot:SetParent(self.FullContentHost)
    self.CoreStatusRoot:SetAllPoints(self.FullContentHost)
    self.CoreStatusRoot:Show()

    for _, id in ipairs(self.ProviderOrder) do
        local row = self.CoreStatusRows[id]
        local meta = self.ProviderMeta[id]
        local provider = self.Providers[id]
        if row and meta then
            row.label:SetText(meta.title)
            if provider then
                row.dot:SetColorTexture(CopyColor(Color.success))
                row.status:SetText(L["已注册 · 可打开"])
                row.status:SetTextColor(CopyColor(Color.success))
            else
                row.dot:SetColorTexture(CopyColor(Color.quiet))
                local router = ExwindTools.PanelRouter
                local availability = router and router.GetProviderStatus and router:GetProviderStatus(id) or nil
                if availability and not availability.installed then
                    row.status:SetText(L["未安装"])
                elseif availability and not availability.enabled then
                    row.status:SetText(L["已安装 · 未启用"])
                elseif availability and not availability.loaded then
                    row.status:SetText(L["已安装 · 未加载"])
                else
                    row.status:SetText(L["已加载 · 尚未注册"])
                end
                row.status:SetTextColor(CopyColor(Color.muted))
            end
        end
    end
end

function Panel:HideCoreStatus()
    if self.CoreStatusRoot then self.CoreStatusRoot:Hide() end
end

function Panel:UpdateHeader(providerID)
    if not self.HeaderTitle or not self.HeaderSubtitle then return end
    local meta = providerID and self.ProviderMeta[providerID] or nil
    if not meta then
        self.HeaderTitle:SetText("EXWIND CORE")
        self.HeaderTitle:SetTextColor(CopyColor(Color.cyan))
        self.HeaderSubtitle:SetText("/ UNIFIED PANEL")
        return
    end
    local accent = Color[meta.accent or "cyan"] or Color.cyan
    self.HeaderTitle:SetText(meta.title or "EXWIND")
    self.HeaderTitle:SetTextColor(CopyColor(accent))
    self.HeaderSubtitle:SetText("/ CONFIGURATION")
end

-- Provider 顶端 Tab 的稳定宿主。Shell 只负责按钮与选中视觉；route、页面状态、
-- Renderer 调用仍由 Provider 自己拥有。Tools 不使用此 API；EXBoss/EXAura 可复用。
function Panel:ClearTopTabs()
    if self.TopChoiceGroup then
        self.TopChoiceGroup:Release()
        self.TopChoiceGroup = nil
    end
    for _, button in ipairs(self.TopTabButtons or {}) do
        button:Hide()
        button:SetScript("OnClick", nil)
    end
    self.TopTabOwner = nil
    self.TopTabButtons = self.TopTabButtons or {}
end

function Panel:SetTopTabs(providerID, tabs, activeKey, onSelect, options)
    if not self.TopTabHost then return false end
    self:ClearTopTabs()
    self.TopTabOwner = providerID
    if options and options.choiceGroup then
        local items = {}
        for _, tab in ipairs(tabs or {}) do
            items[#items + 1] = { id = tab.key, label = tab.label, disabled = tab.disabled }
        end
        local group = EXUI:CreateTabGroup(self.TopTabHost, {
            items = items, value = activeKey, sizing = "content", itemHeight = Layout.TOP_TAB_HEIGHT - 2,
            width = math.max(1, self.TopTabHost:GetWidth() - 28),
            onChange = function(key)
                if self.TopTabOwner ~= providerID then return false end
                if onSelect then return onSelect(key) end
            end,
        })
        group:SetPoint("TOPLEFT", 14, -1)
        group:SetPoint("TOPRIGHT", -14, -1)
        self.TopChoiceGroup = group
        return true
    end
    local previous

    for index, tab in ipairs(tabs or {}) do
        if type(tab) == "table" and tab.key and tab.label then
            local button = self.TopTabButtons[index]
            if not button then
                button = CreateFrame("Button", nil, self.TopTabHost)
                button:SetHeight(Layout.TOP_TAB_HEIGHT - 2)
                button.hover = EXUI:CreateVisualTexture(button, EXBACKGROUNDFRAME)
                button.hover:SetAllPoints()
                button.hover:SetColorTexture(Color.cyan[1], Color.cyan[2], Color.cyan[3], 0.055)
                button.hover:Hide()
                button.label = MakeText(button, "OVERLAY", Layout.TOP_TAB_FONT_SIZE or 14, Color.muted, "OUTLINE")
                button.label:SetPoint("CENTER", 0, 0)
                button.accent = EXUI:CreateVisualTexture(button, EXBASEFRAME)
                button.accent:SetPoint("BOTTOMLEFT", 8, 0)
                button.accent:SetPoint("BOTTOMRIGHT", -8, 0)
                button.accent:SetHeight(2)
                self.TopTabButtons[index] = button
            end

            button._tabKey = tab.key
            button.label:SetText(tab.label)
            button:ClearAllPoints()
            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 5, 0)
            else
                button:SetPoint("LEFT", self.TopTabHost, "LEFT", 14, 0)
            end
            button:SetWidth(math.max(68, button.label:GetStringWidth() + 26))
            local active = tab.key == activeKey
            local provider = self.Providers and self.Providers[providerID]
            local accent = Color[provider and provider.accent or "cyan"] or Color.cyan
            button.label:SetTextColor(CopyColor(active and Color.text or Color.muted))
            button.accent:SetColorTexture(CopyColor(accent))
            button.accent:SetShown(active)
            button.hover:SetShown(active)
            button:SetScript("OnEnter", function(self)
                if not self._tabActive then self.hover:Show() end
            end)
            button:SetScript("OnLeave", function(self)
                if not self._tabActive then self.hover:Hide() end
            end)
            button._tabActive = active
            button:SetScript("OnClick", function(self)
                if type(onSelect) == "function" then onSelect(self._tabKey) end
            end)
            button:Show()
            previous = button
        end
    end
    return true
end

local function SetRailButtonState(button, active)
    if not button then return end
    local meta = button._providerMeta or {}
    local accent = Color[meta.accent or "cyan"] or Color.cyan
    button._active = active == true
    button:SetBackdropColor(active and 0.075 or 0.03, active and 0.12 or 0.04, active and 0.17 or 0.06, active and 0.96 or 0)
    button:SetBackdropBorderColor(active and accent[1] or Color.borderSoft[1], active and accent[2] or Color.borderSoft[2], active and accent[3] or Color.borderSoft[3], active and 0.65 or 0)
    button.accent:SetShown(active == true)
    button.label:SetTextColor(CopyColor(active and Color.text or Color.muted))
end

function Panel:RebuildAppRail()
    if not self.AppRail then return end
    local offset = -70
    for _, button in ipairs(self.RailButtons or {}) do
        button:Hide()
    end

    for _, id in ipairs(self.ProviderOrder) do
        local provider = self.Providers[id]
        if provider then
            local button = self.RailButtonByID[id]
            if not button then
                button = CreateFrame("Button", nil, self.AppRail, "BackdropTemplate")
                button:SetSize(42, 42)
                button:SetBackdrop(Backdrop)
                button._providerID = id
                button._providerMeta = self.ProviderMeta[id] or {}
                button.label = MakeText(button, "OVERLAY", 15, Color.muted, "OUTLINE")
                button.label:SetPoint("CENTER")
                button.accent = EXUI:CreateVisualTexture(button, EXBASEFRAME)
                button.accent:SetPoint("LEFT", -9, 0)
                button.accent:SetSize(2, 23)
                button.accent:SetColorTexture(CopyColor(Color.cyan))
                button:SetScript("OnClick", function(self)
                    Panel:SelectProvider(self._providerID)
                end)
                button:SetScript("OnEnter", function(self)
                    if not self._active then
                        self:SetBackdropColor(0.10, 0.13, 0.18, 0.78)
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText((self._providerMeta and self._providerMeta.title) or self._providerID, 0.86, 0.92, 1)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function(self)
                    SetRailButtonState(self, self._active)
                    GameTooltip:Hide()
                end)
                self.RailButtons[#self.RailButtons + 1] = button
                self.RailButtonByID[id] = button
            end

            button.label:SetText((self.ProviderMeta[id] and self.ProviderMeta[id].short) or id:sub(1, 1):upper())
            button:ClearAllPoints()
            button:SetPoint("TOP", self.AppRail, "TOP", 0, offset)
            button:Show()
            SetRailButtonState(button, self.ActiveProvider == id)
            offset = offset - 51
        end
    end
end

-- 通用设置伪 Provider：不放进 ProviderOrder，因此不会出现在应用栏的圆形
-- Provider 图标列表里，只能从下方固定的齿轮按钮进入。用来承载不属于任何
-- 单一插件的全局开关，例如统一小地图按钮的隐藏开关。
--
-- 内容和其它设置页一样，统一走 ExwindGrid + EXUI 标准控件渲染，不手写
-- Frame/CheckButton；不属于任何 moduleKey，因此 config 用一个 __index/
-- __newindex 代理表把 Grid 的标准读写路径实时转发到 Is/SetMinimapButtonHidden，
-- 而不是另建一份镜像 DB。
local SettingsProvider = { id = "settings", accent = "cyan", hasTopTabs = false, layoutMode = "tabs_full" }

local SettingsConfigProxy = setmetatable({}, {
    __index = function(_, key)
        if key == "minimapHidden" then
            return ExwindTools.IsMinimapButtonHidden and ExwindTools:IsMinimapButtonHidden() or false
        elseif key == "panelScale" then
            return Panel:GetScale()
        end
        return nil
    end,
    __newindex = function(_, key, value)
        if key == "minimapHidden" and ExwindTools.SetMinimapButtonHidden then
            ExwindTools:SetMinimapButtonHidden(value == true)
        elseif key == "panelScale" then
            Panel:SetScale(value)
        end
    end,
})

local PANEL_SCALE_OPTIONS = {
    { "60%", 60 }, { "65%", 65 }, { "70%", 70 }, { "75%", 75 }, { "80%", 80 },
    { "85%", 85 }, { "90%", 90 }, { "95%", 95 }, { "100%", 100 },
    { "105%", 105 }, { "110%", 110 },
}

-- 200 列密度和 HomePage.lua 等其它标准设置页保持一致，让 y 坐标差对应
-- 合理的像素间距；默认 50 列会让每格过宽，内容被拉得离标题很远。
local SETTINGS_GRID_COLS = 200

local function BuildSettingsLayout()
    return {
        { key = "header_settings", type = "header", x = 1, y = 3, w = 190, h = 4, label = L["通用设置"], labelSize = 20 },
        { key = "minimapHidden", type = "checkbox", x = 3, y = 11, w = 60, h = 4, label = L["隐藏小地图按钮"] },
        { key = "panelScale", type = "dropdown", x = 3, y = 19, w = 30, h = 4, label = L["面板缩放"], items = PANEL_SCALE_OPTIONS },
    }
end

function SettingsProvider:Mount(hosts)
    local root = CreateFrame("Frame", nil, hosts.fullContentHost)
    root:SetAllPoints()
    self.Root = root

    local scrollFrame = CreateFrame("ScrollFrame", nil, root, "ScrollFrameTemplate")
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -24, 4)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    self.ScrollFrame = scrollFrame
    self.ScrollChild = scrollChild
end

function SettingsProvider:Render()
    local Grid = _G.ExwindGrid
    if not (Grid and self.ScrollFrame and self.ScrollChild) then return end
    local width = self.ScrollFrame:GetWidth()
    if width < 100 then width = 800 end
    self.ScrollChild:SetWidth(width - 16)
    self.ScrollChild:SetHeight(1)
    if Grid.SetContainerCols then
        Grid:SetContainerCols(self.ScrollChild, SETTINGS_GRID_COLS)
    end
    Grid:Render(self.ScrollChild, BuildSettingsLayout(), SettingsConfigProxy, nil)
end

function SettingsProvider:ApplyRoute()
    if self.Root then self.Root:Show() end
    C_Timer.After(0, function()
        if self.Root and self.Root:IsShown() then self:Render() end
    end)
end

function SettingsProvider:Relayout()
    if self.Root and self.Root:IsShown() then self:Render() end
end

function SettingsProvider:Hide()
    if self.Root then self.Root:Hide() end
end

Panel.Providers.settings = SettingsProvider

function Panel:EnterEditMode()
    local frame = self:CreateFrame()
    local providerID = self.ActiveProvider
    local route = providerID and self:GetSavedRoute(providerID) or nil

    EXUI:EnterEditModeWithExitCallback(function()
        Panel:Show(providerID, route)
    end)
    frame:Hide()
end

function Panel:RegisterProvider(id, provider)
    if type(id) ~= "string" or id == "" then
        error(L["[ExwindUnifiedPanel] Provider id 必须是非空字符串"], 2)
    end
    if type(provider) ~= "table" then
        error(L["[ExwindUnifiedPanel] Provider 必须是 table: "] .. id, 2)
    end

    self.Providers[id] = provider
    provider.id = id
    self:RebuildAppRail()
    if not self.ActiveProvider and self.Frame and self.Frame:IsShown() then
        self:ShowCoreStatus()
    end
    return true
end

function Panel:UnregisterProvider(id)
    if self.ActiveProvider == id then
        self:SelectProvider(nil)
    end
    self.Providers[id] = nil
    self:RebuildAppRail()
end

function Panel:SelectProvider(id, route)
    if not id then
        if self.ActiveProvider then
            local oldProvider = self.Providers[self.ActiveProvider]
            if oldProvider and type(oldProvider.Hide) == "function" then oldProvider:Hide() end
        end
        self.ActiveProvider = nil
        self:ClearTopTabs()
        self:UpdateHeader(nil)
        self:ApplyLayout("tabs_full", { showTabs = false })
        self:RebuildAppRail()
        if self.SettingsRailButton then SetRailButtonState(self.SettingsRailButton, false) end
        return true
    end

    local provider = self.Providers[id]
    if not provider then return false end
    if route == nil then
        route = self:GetSavedRoute(id)
    end
    local previous = self.ActiveProvider
    if previous and previous ~= id then
        local oldProvider = self.Providers[previous]
        if oldProvider and type(oldProvider.Hide) == "function" then oldProvider:Hide() end
    end

    self.ActiveProvider = id
    self:SaveActiveRoute(id, route)
    self:ClearTopTabs()
    self:UpdateHeader(id)
    self:HideCoreStatus()
    -- 首次 Mount 只建 Provider 自己的稳定 root；它还没有可 Relayout 的业务内容。
    -- 因此必须发生在 ApplyLayout 之前，避免 Shell 把第一次 Relayout 送进未初始化树。
    if not provider._shellMounted and type(provider.Mount) == "function" then
        provider:Mount(self.Hosts, self:GetMetrics())
        provider._shellMounted = true
    end
    local mode = provider.layoutMode or "tabs_full"
    if type(provider.GetLayoutMode) == "function" then
        mode = provider:GetLayoutMode(route) or mode
    end
    self:ApplyLayout(mode, {
        showTabs = provider.hasTopTabs == true,
        navRatio = provider.navRatio,
    })
    if type(provider.ApplyRoute) == "function" then
        provider:ApplyRoute(route, previous)
    end
    self:RebuildAppRail()
    if self.SettingsRailButton then SetRailButtonState(self.SettingsRailButton, id == "settings") end
    return true
end

function Panel:CreateFrame()
    if self.Frame then return self.Frame end

    local frame = CreateFrame("Frame", "ExwindUnifiedPanelFrame", UIParent, "BackdropTemplate")
    frame:SetBackdrop(Backdrop)
    frame:SetBackdropColor(CopyColor(Color.panel))
    frame:SetBackdropBorderColor(CopyColor(Color.border))
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(false)
    frame:SetClampedToScreen(false)
    frame:EnableMouse(true)

    -- Shell 是 EXBoss/Tools/Aura 共用的真正窗口。空白区的鼠标抬起有时会被
    -- Scroll/内容子 Frame 接收；因此由 GLOBAL_MOUSE_UP 统一清理手动拖动状态。
    local function PrepareShellDrag(self, source)
        local scale = UIParent:GetEffectiveScale() or 1
        local cursorX, cursorY = GetCursorPosition()
        self._exShellDragOrigin = {
            cursorX = (cursorX or 0) / scale,
            cursorY = (cursorY or 0) / scale,
            left = self:GetLeft() or 0,
            top = self:GetTop() or 0,
            source = source,
        }
    end
    local function StopShellDrag(self)
        if not self._exShellDragging then
            self._exShellDragOrigin = nil
            return
        end
        self:SetScript("OnUpdate", nil)
        self._exShellDragging = nil
        self._exShellDragOrigin = nil
        Panel:SaveGeometry()
    end
    local function StartShellDrag(self, source)
        -- 不使用 StartMoving：它会把已保存的 RIGHT / CENTER 锚点转换为 TOPLEFT，
        -- 在部分 UI 缩放与子 Frame 事件序列下会产生可见跳跃。手动按鼠标增量移动，
        -- 起点恒为按下瞬间的实际屏幕坐标。
        local origin = self._exShellDragOrigin
        if not origin then
            PrepareShellDrag(self, source)
            origin = self._exShellDragOrigin
        end
        self._exShellDragging = true
        self:SetScript("OnUpdate", function(frame)
            local drag = frame._exShellDragOrigin
            if not drag then return end
            if _G.IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                StopShellDrag(frame)
                return
            end
            local scale = UIParent:GetEffectiveScale() or 1
            local cursorX, cursorY = GetCursorPosition()
            local left = drag.left + ((cursorX or 0) / scale - drag.cursorX)
            local top = drag.top + ((cursorY or 0) / scale - drag.cursorY)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end)
    end
    frame._exStartShellDrag = StartShellDrag
    frame._exStopShellDrag = StopShellDrag

    -- 鼠标落在 Button、Slider、EditBox 等启用鼠标的子控件时，由子控件先接收事件，
    -- 不会破坏正常点击或输入；只有未被控件占用的空白区会落到 Shell。
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        StartShellDrag(self, "root")
    end)
    frame:SetScript("OnDragStop", function(self)
        StopShellDrag(self)
    end)
    -- 这是关键兜底：GLOBAL_MOUSE_UP 无论鼠标最终落在哪个子 Frame 都会触发。
    frame:RegisterEvent("GLOBAL_MOUSE_UP")
    frame:SetScript("OnEvent", function(self, event, button)
        if event == "GLOBAL_MOUSE_UP" and button == "LeftButton" then
            StopShellDrag(self)
        end
    end)
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            PrepareShellDrag(frame, "root")
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            StopShellDrag(self)
        end
    end)
    frame:SetScript("OnSizeChanged", function()
        if Panel.ActiveProvider then
            local provider = Panel.Providers[Panel.ActiveProvider]
            if provider and type(provider.Relayout) == "function" then provider:Relayout(Panel:GetMetrics()) end
        end
    end)
    frame:SetScript("OnHide", function()
        StopShellDrag(frame)
        if Panel.ActiveProvider then
            local provider = Panel.Providers[Panel.ActiveProvider]
            if provider and type(provider.Hide) == "function" then provider:Hide() end
        end
    end)
    self.Frame = frame
    self:RestoreGeometry()

    local rail = MakeSolidFrame(frame, Color.rail, Color.border)
    rail:SetPoint("TOPLEFT")
    rail:SetPoint("BOTTOMLEFT")
    rail:SetWidth(Layout.APP_RAIL_WIDTH)
    self.AppRail = rail

    local brand = MakeText(rail, "OVERLAY", 14, Color.violet, "OUTLINE")
    brand:SetPoint("TOP", 0, -22)
    brand:SetText("EX")
    local brandLine = EXUI:CreateVisualTexture(rail, EXBASEFRAME)
    brandLine:SetPoint("TOP", brand, "BOTTOM", 0, -12)
    brandLine:SetSize(22, 1)
    brandLine:SetColorTexture(CopyColor(Color.borderSoft))

    local coreMark = MakeText(rail, "OVERLAY", 8, Color.quiet, "OUTLINE")
    coreMark:SetPoint("BOTTOM", 0, 13)
    coreMark:SetText("CORE")

    -- 固定在应用栏底部的通用设置入口。不属于任何 Provider，承载不属于
    -- 单一插件的全局开关（例如统一小地图按钮的隐藏开关）。
    local settingsBtn = CreateFrame("Button", nil, rail, "BackdropTemplate")
    settingsBtn:SetSize(42, 42)
    settingsBtn:SetPoint("BOTTOM", rail, "BOTTOM", 0, 188)
    settingsBtn:SetBackdrop(Backdrop)
    settingsBtn:SetBackdropColor(0.03, 0.04, 0.06, 0)
    settingsBtn:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
    settingsBtn._providerMeta = { accent = "cyan" }
    settingsBtn.accent = EXUI:CreateVisualTexture(settingsBtn, EXBASEFRAME)
    settingsBtn.accent:SetPoint("LEFT", -9, 0)
    settingsBtn.accent:SetSize(2, 23)
    settingsBtn.accent:SetColorTexture(CopyColor(Color.cyan))
    settingsBtn.accent:Hide()
    -- SetRailButtonState 是圆形 Provider 按钮和这几个固定功能按钮共用的高亮
    -- 函数，会无条件访问 button.label；这里不显示文字，只为满足该访问。
    settingsBtn.label = MakeText(settingsBtn, "OVERLAY", 15, Color.muted, "OUTLINE")
    settingsBtn.label:SetPoint("CENTER")
    settingsBtn.icon = EXUI:CreateVisualTexture(settingsBtn, EXBASEFRAME)
    settingsBtn.icon:SetPoint("CENTER")
    settingsBtn.icon:SetSize(24, 24)
    settingsBtn.icon:SetTexture("Interface\\AddOns\\ExwindCore\\Textures\\setting.png")
    settingsBtn:SetScript("OnClick", function() Panel:SelectProvider("settings") end)
    settingsBtn:SetScript("OnEnter", function(self)
        if not self._active then
            self:SetBackdropColor(0.10, 0.13, 0.18, 0.78)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["通用设置"], 0.86, 0.92, 1)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        SetRailButtonState(self, self._active)
        GameTooltip:Hide()
    end)
    self.SettingsRailButton = settingsBtn

    -- 唯一的更新日志入口：正文仍由各插件注册，Core 只打开统一 TAB 窗口。
    local changelog = CreateFrame("Button", nil, rail, "BackdropTemplate")
    changelog:SetSize(42, 42)
    changelog:SetPoint("BOTTOM", rail, "BOTTOM", 0, 137)
    changelog:SetBackdrop(Backdrop)
    changelog:SetBackdropColor(0.03, 0.04, 0.06, 0)
    changelog:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
    changelog.label = MakeText(changelog, "OVERLAY", 15, Color.muted, "OUTLINE")
    changelog.label:SetPoint("CENTER")
    changelog.label:SetText("≡")
    changelog:SetScript("OnClick", function()
        local viewer = ExwindTools.ChangelogViewer
        if viewer and viewer.ShowManual then
            viewer:ShowManual()
        end
    end)
    changelog:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.13, 0.18, 0.78)
        self:SetBackdropBorderColor(Color.cyan[1], Color.cyan[2], Color.cyan[3], 0.55)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["更新日志"], 0.86, 0.92, 1)
        GameTooltip:Show()
    end)
    changelog:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.03, 0.04, 0.06, 0)
        self:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
        GameTooltip:Hide()
    end)
    self.ChangelogRailButton = changelog

    -- 固定在应用栏底部的全局编辑模式入口。它不属于任何 Provider，因此
    -- Tools / EXBoss / EXAura 任一页面都复用同一个 Core 编辑会话。
    local editMode = CreateFrame("Button", nil, rail, "BackdropTemplate")
    editMode:SetSize(42, 42)
    editMode:SetPoint("BOTTOM", rail, "BOTTOM", 0, 86)
    editMode:SetBackdrop(Backdrop)
    editMode:SetBackdropColor(0.03, 0.04, 0.06, 0)
    editMode:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
    editMode.icon = EXUI:CreateVisualTexture(editMode, EXBASEFRAME)
    editMode.icon:SetPoint("CENTER")
    editMode.icon:SetSize(26.4, 26.4)
    -- 该资源是 PNG；必须保留扩展名。省略扩展名时客户端只会按传统
    -- BLP/TGA 候选解析，因此按钮命中区存在但图标会保持透明。
    editMode.icon:SetTexture("Interface\\AddOns\\ExwindCore\\Textures\\grid.png")
    editMode:SetScript("OnClick", function() Panel:EnterEditMode() end)
    editMode:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.13, 0.18, 0.78)
        self:SetBackdropBorderColor(Color.cyan[1], Color.cyan[2], Color.cyan[3], 0.55)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["编辑模式"], 0.86, 0.92, 1)
        GameTooltip:Show()
    end)
    editMode:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.03, 0.04, 0.06, 0)
        self:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
        GameTooltip:Hide()
    end)
    self.EditModeRailButton = editMode

    local reload = CreateFrame("Button", nil, rail, "BackdropTemplate")
    reload:SetSize(42, 42)
    reload:SetPoint("BOTTOM", rail, "BOTTOM", 0, 35)
    reload:SetBackdrop(Backdrop)
    reload:SetBackdropColor(0.03, 0.04, 0.06, 0)
    reload:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
    reload.icon = EXUI:CreateVisualTexture(reload, EXBASEFRAME)
    reload.icon:SetPoint("CENTER")
    reload.icon:SetSize(24, 24)
    reload.icon:SetTexture("Interface\\AddOns\\ExwindCore\\Textures\\reload.png")
    reload:SetScript("OnClick", function() ReloadUI() end)
    reload:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.13, 0.18, 0.78)
        self:SetBackdropBorderColor(Color.cyan[1], Color.cyan[2], Color.cyan[3], 0.55)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["重新加载界面"], 0.86, 0.92, 1)
        GameTooltip:Show()
    end)
    reload:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.03, 0.04, 0.06, 0)
        self:SetBackdropBorderColor(Color.borderSoft[1], Color.borderSoft[2], Color.borderSoft[3], 0)
        GameTooltip:Hide()
    end)
    self.ReloadRailButton = reload
    self.RailButtons = {}
    self.RailButtonByID = {}

    local header = MakeFlatFrame(frame, Color.header)
    header:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(Layout.HEADER_HEIGHT)
    self.Header = header

    local title = MakeText(header, "OVERLAY", 17, Color.cyan, "OUTLINE")
    title:SetPoint("TOPLEFT", 18, -3)
    title:SetText("EXWIND")
    local titleSub = MakeText(header, "OVERLAY", 10, Color.muted, "OUTLINE")
    titleSub:SetPoint("LEFT", title, "RIGHT", 7, 0)
    titleSub:SetText("/ UNIFIED PANEL")
    self.HeaderTitle = title
    self.HeaderSubtitle = titleSub

    -- 关闭键属于整个 Shell，而非 Header 中线；始终贴齐窗口右上角。
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() frame:Hide() end)

    local drag = CreateFrame("Button", nil, header)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -38, 0)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            PrepareShellDrag(frame, "header")
        end
    end)
    drag:SetScript("OnDragStart", function() StartShellDrag(frame, "header") end)
    drag:SetScript("OnDragStop", function()
        StopShellDrag(frame)
    end)

    local tabHost = MakeFlatFrame(frame, Color.header)
    tabHost:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    tabHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tabHost:SetHeight(Layout.TOP_TAB_HEIGHT)
    self.TopTabHost = tabHost

    local navHost = MakeSolidFrame(frame, Color.nav, Color.border)
    self.NavHost = navHost

    local contentHost = CreateFrame("Frame", nil, frame)
    self.ContentHost = contentHost
    local contentBg = EXUI:CreateVisualTexture(contentHost, EXBACKGROUNDFRAME)
    contentBg:SetAllPoints()
    contentBg:SetColorTexture(CopyColor(Color.content))

    local previewDock = MakeSolidFrame(contentHost, Color.cardAlt, Color.border)
    previewDock:SetPoint("TOPLEFT")
    previewDock:SetPoint("TOPRIGHT")
    previewDock:SetHeight(1)
    -- PreviewDock 是 Shell 提供给 Provider 的有界画布，而不是一块装饰背景。
    -- 标准预览允许元素按配置偏移；没有裁切时，偏移后的图标/文字会越过
    -- Dock 画到下面的 ContentBody/Grid。边界应在 Core 的宿主契约收口，
    -- 不能要求每个 Provider 自己猜测或截断其投影模型。
    previewDock:SetClipsChildren(true)
    -- ContentBody 和 PreviewDock 是同一个 ContentHost 的 sibling。显式把 Dock
    -- 放在业务画布前景，保证它在自己的有界区域内始终可见；裁切保证这不
    -- 会变成覆盖下方页面的浮层。
    previewDock:SetFrameLevel((contentHost:GetFrameLevel() or 0) + 10)
    self.PreviewDock = previewDock

    local contentBody = CreateFrame("Frame", nil, contentHost)
    contentBody:SetAllPoints(contentHost)
    self.ContentBodyHost = contentBody

    local fullContentHost = CreateFrame("Frame", nil, frame)
    self.FullContentHost = fullContentHost
    local fullBg = EXUI:CreateVisualTexture(fullContentHost, EXBACKGROUNDFRAME)
    fullBg:SetAllPoints()
    fullBg:SetColorTexture(CopyColor(Color.content))

    local modalLayer = CreateFrame("Frame", nil, frame)
    modalLayer:SetAllPoints(frame)
    modalLayer:SetFrameStrata("DIALOG")
    modalLayer:SetFrameLevel(frame:GetFrameLevel() + 100)
    self.ModalLayer = modalLayer

    self.Hosts = {
        appRail = rail,
        header = header,
        tabHost = tabHost,
        navHost = navHost,
        contentHost = contentHost,
        contentBodyHost = contentBody,
        fullContentHost = fullContentHost,
        previewDock = previewDock,
        modalHost = modalLayer,
    }

    if _G.UISpecialFrames then
        local found = false
        for _, name in ipairs(_G.UISpecialFrames) do
            if name == "ExwindUnifiedPanelFrame" then found = true break end
        end
        if not found then
            table.insert(_G.UISpecialFrames, "ExwindUnifiedPanelFrame")
        end
    end

    self:RebuildAppRail()
    self:ApplyLayout("tabs_full", { showTabs = false })
    frame:Hide()
    return frame
end

function Panel:Show(providerID, route)
    local frame = self:CreateFrame()
    frame:Show()
    if providerID and self.Providers[providerID] then
        self:SelectProvider(providerID, route)
    elseif self.ActiveProvider and self.Providers[self.ActiveProvider] then
        -- 关闭 Shell 时 Provider:Hide() 已收起其 root；重开必须重新走 route，
        -- 不能只 Raise 外壳而留下空白内容区。
        self:SelectProvider(self.ActiveProvider, route)
    elseif not self.ActiveProvider then
        local restored = GetSavedState().lastProvider
        if restored and self.Providers[restored] then
            self:SelectProvider(restored, route)
        else
            self:SelectProvider(nil)
        end
    end
    frame:Raise()
end

function Panel:Hide()
    if self.Frame then self.Frame:Hide() end
end

function Panel:Toggle()
    local frame = self:CreateFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        self:Show()
    end
end
