-- =========================================================
-- ExwindToolsPanelProvider.lua
-- ExwindTools 业务工作区接入 Unified Shell。
--
-- 此 Provider 只在独立 ExwindTools AddOn 已加载时注册；Core-only 安装
-- 仍只显示 Shell 状态页。它调用 EXUI:MountUnifiedWorkspace() 创建新的稳定
-- 工作区，而非重父级化 ExwindToolsMainFrame。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools then return end

local Panel = ExwindTools.UnifiedPanel
local EXUI = ExwindTools.UI
if not Panel or not EXUI then
    error(L["[ExwindToolsPanelProvider] Unified Shell 与 ExwindTools UI 必须先加载"])
end

local Provider = {
    id = "tools",
    layoutMode = "split",
    hasTopTabs = false,
    navRatio = 0.22,
}

local function UpdateEditModeButton()
    local button = Provider.EditModeButton
    if not button then return end
    local label = EXUI:IsEditModeActive() and L["关闭编辑模式"] or L["启用编辑模式"]
    button:SetText(label)
end

function Provider:CreateHeaderActions(header)
    if self.HeaderActions then return end

    local holder = CreateFrame("Frame", nil, header)
    holder:SetHeight(30)
    holder:SetPoint("RIGHT", header, "RIGHT", -46, 0)
    self.HeaderActions = holder

    local reload = EXUI:CreateSmallButton(holder, L["立即重载界面"], function()
        C_UI.Reload()
    end)
    reload:SetSize(118, 24)
    reload:SetPoint("RIGHT", 0, 0)
    self.ReloadButton = reload

    local edit = EXUI:CreateSmallButton(holder, "", function()
        EXUI:ToggleEditMode()
        UpdateEditModeButton()
        -- 保留旧行为：开启全局编辑时收起总面板，给世界中的锚点操作让出空间。
        if EXUI:IsEditModeActive() then
            Panel:Hide()
        end
    end)
    edit:SetSize(118, 24)
    edit:SetPoint("RIGHT", reload, "LEFT", -7, 0)
    self.EditModeButton = edit
    EXUI.EditModeToggleButton = edit

    local changelog = EXUI:CreateSmallButton(holder, L["更新日志"], function()
        if ExwindTools.ShowChangelog then
            ExwindTools:ShowChangelog({ markShown = true })
        end
    end)
    changelog:SetSize(84, 24)
    changelog:SetPoint("RIGHT", edit, "LEFT", -7, 0)
    self.ChangelogButton = changelog
    EXUI.ChangelogButton = changelog

    UpdateEditModeButton()
end

function Provider:Mount(hosts, metrics)
    self.Hosts = hosts
    EXUI:MountUnifiedWorkspace(hosts, Panel)
    self:CreateHeaderActions(hosts.header)
    self:Relayout(metrics)
end

function Provider:Relayout(metrics)
    self.Metrics = metrics or Panel:GetMetrics()
    EXUI:RelayoutUnifiedWorkspace(self.Metrics)
    if self.HeaderActions then
        self.HeaderActions:Show()
    end

    -- 只有模块 Grid 的可用宽度真的变化时才重绘。Shell 的 OnSizeChanged 在拖动
    -- 期间会连续触发；这里以 generation 去抖，最终只执行一次“布局变更”全量 Render，
    -- 不会把普通数据点击误升级成全页刷新。
    local scrollFrame = EXUI.ModuleScrollFrame
    if EXUI.CurrentPage == "ModuleSettings" and scrollFrame and scrollFrame:IsShown() then
        local width = math.floor((scrollFrame:GetWidth() or 0) + 0.5)
        if width > 1 and self.LastModuleGridWidth ~= width then
            self.LastModuleGridWidth = width
            self.RelayoutGeneration = (self.RelayoutGeneration or 0) + 1
            local generation = self.RelayoutGeneration
            C_Timer.After(0.12, function()
                if generation ~= Provider.RelayoutGeneration then return end
                if not Panel.Frame or not Panel.Frame:IsShown() or Panel.ActiveProvider ~= "tools" then return end
                if EXUI.CurrentPage ~= "ModuleSettings" or not EXUI.ModuleScrollFrame or not EXUI.ModuleScrollFrame:IsShown() then return end
                EXUI:RefreshContentKeepModuleScroll()
            end)
        end
    end
end

function Provider:ApplyRoute(route)
    if type(route) == "table" then
        if route.moduleKey then
            EXUI.CurrentPage = "ModuleSettings"
            EXUI.CurrentModule = route.moduleKey
        elseif route.page then
            EXUI.CurrentPage = route.page
            if route.moduleKey == nil and route.page ~= "ModuleSettings" then
                EXUI.CurrentModule = nil
            end
        end
    elseif type(route) == "string" and route ~= "" then
        EXUI.CurrentPage = route
        if route ~= "ModuleSettings" then
            EXUI.CurrentModule = nil
        end
    end

    EXUI:ShowUnifiedWorkspace()
    EXUI:RefreshContent()
    Panel:SaveActiveRoute("tools", {
        page = EXUI.CurrentPage,
        moduleKey = EXUI.CurrentModule,
    })
    UpdateEditModeButton()

    if ExwindTools.HandleChangelogPopupOnUIOpen then
        C_Timer.After(0.05, function()
            if Panel.Frame and Panel.Frame:IsShown() and Panel.ActiveProvider == "tools" then
                ExwindTools:HandleChangelogPopupOnUIOpen()
            end
        end)
    end
end

function Provider:Hide()
    if self.HeaderActions then self.HeaderActions:Hide() end
    Panel:SaveActiveRoute("tools", {
        page = EXUI.CurrentPage,
        moduleKey = EXUI.CurrentModule,
    })
    EXUI:HideUnifiedWorkspace()
end

function Provider:Toggle()
    if Panel.Frame and Panel.Frame:IsShown() and Panel.ActiveProvider == "tools" then
        Panel:Hide()
    else
        Panel:Show("tools")
    end
end

local function IsToolsAddonLoaded()
    if _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded then
        return _G.C_AddOns.IsAddOnLoaded("ExwindTools") == true
    end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded("ExwindTools") == true
end

local function RegisterProvider()
    if Panel.Providers.tools == Provider then return end
    Panel:RegisterProvider("tools", Provider)
end

-- ExwindTools 的世界编辑模块统一通过现有模块设置页路由回同一个
-- Unified Tools Provider。模块不得各自注册或维护第二套右键跳转逻辑。
EXUI:RegisterModuleSettingsRouter("ExwindTools", function(moduleKey)
    ExwindTools:OpenConfig(moduleKey)
end)

if IsToolsAddonLoaded() then
    RegisterProvider()
else
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, _, addonName)
        if addonName ~= "ExwindTools" then return end
        self:UnregisterEvent("ADDON_LOADED")
        RegisterProvider()
    end)
end
