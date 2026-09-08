---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/GlobalTrashCDPage.lua
-- 小怪CD 全局设置页（ExwindGrid 渲染）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end
local L                           = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GlobalTrashCDPage = ExBoss.UI.Panel.GlobalTrashCDPage or {}
local Page                        = ExBoss.UI.Panel.GlobalTrashCDPage

-- 仅用于 Grid 的页面事件；TrashCD 设置的唯一持久 owner 是 Store 的
-- Factory -> Author -> User 链路，不能再把页面草稿放进 ModuleDB。
local EDITOR_KEY                  = "ExBoss.TrashCD.Settings.Editor"
local BASE_GRID_COLS              = 200
local TARGET_CELL_PX              = 18
local LAYOUT_CACHE                = {}
local standardPreview             = nil
local ToggleScreenNameplatePreview
local StopScreenNameplatePreview

Page._editorDraft                 = Page._editorDraft or nil
Page._editorActive                = false
Page._editorRevision              = Page._editorRevision or 0

-- =============================================================
-- 默认值
-- =============================================================
local DEFAULTS                    = {
    hideLongTimerBarEnabled       = false,
    hideLongTimerBarSeconds       = 0,
    hideNameplateIconAboveSeconds = 0,
    keepTimerBarAfterReadyEnabled = true,
    keepTimerBarAfterReadySeconds = 10,
    nameplateGrowthSide           = "left",
    nameplateIcon                 = {
        borderColorA       = 1,
        borderColorB       = 0,
        borderColorG       = 0,
        borderColorR       = 0,
        borderPadding      = 0,
        borderSize         = 1,
        borderTexture      = "EX_WhiteBorder",
        height             = 26,
        reverse            = false,
        showBorder         = true,
        showIcon           = true,
        spacing            = 2,
        readyBorderEnabled = true,
        readyBorderColorR  = 0.20,
        readyBorderColorG  = 0.85,
        readyBorderColorB  = 0.20,
        readyBorderColorA  = 1,
        width              = 26,
        x                  = 6,
        y                  = 0,
    },
    nameplateIconStrata           = "DIALOG",
    nameplateIconText             = {
        a       = 1,
        b       = 1,
        font    = "",
        g       = 1,
        outline = "OUTLINE",
        r       = 1,
        shadow  = true,
        shadowX = 1,
        shadowY = -1,
        size    = 18,
        x       = 0,
        y       = 0,
    },
}

-- 与 TrashCD.Store.GetNameplateIconStrata 完全同一份合法 strata 集合。
-- 这是姓名版图标相对其他姓名版元素的显示层级，不是世界锚点层级。
local NAMEPLATE_GROWTH_SIDE_ITEMS = {
    { L["左侧"], "left" },
    { L["右侧"], "right" },
}

local NAMEPLATE_ICON_STRATA_ITEMS = {
    { "BACKGROUND",        "BACKGROUND" },
    { "LOW",               "LOW" },
    { "MEDIUM",            "MEDIUM" },
    { "HIGH",              "HIGH" },
    { "DIALOG",            "DIALOG" },
    { "FULLSCREEN",        "FULLSCREEN" },
    { "FULLSCREEN_DIALOG", "FULLSCREEN_DIALOG" },
    { "TOOLTIP",           "TOOLTIP" },
}

-- =============================================================
-- 布局
-- =============================================================
local LAYOUT                      = {
    { key = "header_main", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["小怪内置CD姓名版图标"], labelSize = 22 },
    {
        key = "nameplateIcon",
        type = "icongroup",
        x = 1,
        y = 11,
        w = 200,
        h = 50,
        label = L["图标位置与外观"],
        opts = { enableOffset = true, hideIconID = true }
    },

    -- IconGroup never implemented enableSpacing.  Keep this as a real field
    -- under nameplateIcon, with its own lifecycle below, so the value reaches
    -- the same runtime and panel positioning formula.
    {
        key = "nameplateIconSpacing",
        subKey = "spacing",
        parentKey = "nameplateIcon",
        type = "slider",
        x = 1,
        y = 65,
        w = 96,
        h = 5, -- 调整 y：63 → 65
        min = 0,
        max = 50,
        step = 1,
        label = L["图标间距"],
        labelPos = "top"
    },
    { key = "nameplateGrowthSide", type = "dropdown", x = 103, y = 65, w = 96, h = 5, label = L["图标增长方向"], items = NAMEPLATE_GROWTH_SIDE_ITEMS, labelPos = "top" }, -- 调整 y：63 → 65
    { key = "nameplateIconStrata", type = "dropdown", x = 1, y = 75, w = 96, h = 5, label = L["图标层级"], items = NAMEPLATE_ICON_STRATA_ITEMS, labelPos = "top" }, -- 调整 y：69 → 75
    {
        key = "hideNameplateIconAboveSeconds",
        type = "input",
        x = 103,
        y = 75,
        w = 96,
        h = 5, -- 调整 y：69 → 75
        label = L["隐藏剩余超过 X 秒的图标（0=关闭）"],
        labelPos = "top"
    },
    {
        key = "screenNameplatePreview",
        type = "button",
        x = 1,
        y = 84,
        w = 200,
        h = 5, -- 调整 y：75 → 84
        label = L["屏幕敌方姓名版预览 开/关"],
        func = function() ToggleScreenNameplatePreview() end
    },

    { key = "nameplateIconText", type = "fontgroup", x = 1, y = 91, w = 200, h = 50, label = L["倒数时间文本"] }, -- 调整 y：82 → 91
}

-- =============================================================
-- 工具函数
-- =============================================================
local function ApplyDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for key, value in pairs(src) do
        out[key] = DeepCopy(value)
    end
    return out
end

local function ReplaceTable(dst, src)
    for key in pairs(dst) do
        dst[key] = nil
    end
    for key, value in pairs(src) do
        dst[key] = DeepCopy(value)
    end
    return dst
end

-- The settings page never owns a second TrashCD database.  It reads the
-- current Factory -> Author -> User Entity resolution and writes only through
-- Store's M+ DIFF patch API below.
local function GetRuntimeTrashSettings()
    local Store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store
    if Store and type(Store.GetRuntimeSettings) == "function" then
        return Store.GetRuntimeSettings()
    end
    return nil
end

-- Grid 必须始终持有同一个页面草稿表，故重载 resolved 时原地替换内容。
-- 这样不会出现旧 ModuleDB 的跨页面残留，也不会让复合控件持有过期表。
local function LoadRuntimeSettingsToDraft()
    local runtime = GetRuntimeTrashSettings()
    local nextDraft = type(runtime) == "table" and DeepCopy(runtime) or {}
    ApplyDefaults(nextDraft, DEFAULTS)
    if type(Page._editorDraft) == "table" then
        return ReplaceTable(Page._editorDraft, nextDraft)
    end
    Page._editorDraft = nextDraft
    return nextDraft
end

local function GetNameplateMarker()
    local marker = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.NameplateMarker
    if not marker or type(marker.BuildPreview) ~= "function" or type(marker.ApplyPreviewLayoutIntent) ~= "function"
        or type(marker.ApplyLiveVisual) ~= "function" then
        error("GlobalTrashCDPage requires TrashCD NameplateMarker standard preview", 2)
    end
    return marker
end

ToggleScreenNameplatePreview = function()
    local marker = GetNameplateMarker()
    local active = type(marker.IsScreenNameplatePreviewEnabled) == "function"
        and marker:IsScreenNameplatePreviewEnabled() == true
    if type(marker.SetScreenNameplatePreview) ~= "function" then
        error("GlobalTrashCDPage requires TrashCD screen nameplate preview", 2)
    end
    local shown = marker:SetScreenNameplatePreview(not active)
    if _G.UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function" then
        local message = active and L["已关闭屏幕敌方姓名版预览"]
            or ((tonumber(shown) or 0) > 0
                and string.format(L["已在 %d 个敌方姓名版显示测试图标"], tonumber(shown) or 0)
                or L["未找到当前屏幕内的敌方姓名版"])
        UIErrorsFrame:AddMessage(message, 0.3, 0.9, 1.0, 1.0)
    end
end

StopScreenNameplatePreview = function()
    local marker = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.NameplateMarker
    if marker and type(marker.SetScreenNameplatePreview) == "function" then
        marker:SetScreenNameplatePreview(false)
    end
end

local function RefreshVisibleControls()
    local Grid = _G.ExwindGrid
    if Grid and Page._scrollChild and type(Grid.RefreshContainerControlsFromDB) == "function" then
        Grid:RefreshContainerControlsFromDB(Page._scrollChild)
    end
end

local function FocusPreviewGUI(guiTarget)
    local target = tostring(guiTarget or "")
    if target ~= "nameplateIcon" and target ~= "nameplateIconText" then
        error("TrashCD nameplate preview has no GUI target for " .. target, 2)
    end
    if not EXUI:FocusModuleGridKey(EDITOR_KEY, target, Page._scrollFrame, Page._scrollChild) then
        error("TrashCD nameplate preview GUI target is not rendered: " .. target, 2)
    end
end

local function RefreshPanelPreview()
    local dock = Page._previewDock
    if not dock or not dock:IsShown() then return end
    local marker = GetNameplateMarker()
    if not standardPreview then
        standardPreview = EXUI:CreateStandardPreview(dock, {
            interactionMode = "panel",
            autoSizeHost = true,
            minHostHeight = 160,
            hostPadding = 14,
            onIntent = function(intent)
                if intent.type == "elementRightClicked" then
                    FocusPreviewGUI(intent.guiTarget)
                    return
                end
                marker:ApplyPreviewLayoutIntent(intent)
                LoadRuntimeSettingsToDraft()
                RefreshVisibleControls()
                RefreshPanelPreview()
            end,
        })
    end
    local preview = marker:BuildPreview()
    -- 一次正式 materialize 后，下一轮 Slider live 必须从这份新快照开始。
    -- live 自己绝不 Materialize，也不会把临时视觉状态带到下一次 commit。
    standardPreview._trashCDLiveSettings = nil
    standardPreview:Materialize(preview.definition, preview.model)
end

-- IconGroup / FontGroup 目前是历史复合控件：它们的旧 onValueChanged 会在
-- Slider 每一格调用 CompositeEmitUpdate。只在本页把经过审计的纯视觉 Slider
-- 改接生命周期；其余字段继续走原有 commit 路径，不能把会影响真实姓名版
-- 业务/结构的字段误当作 panel 的轻量视觉更新。
local LIVE_SLIDER_FIELDS = {
    nameplateIcon = {
        width = true,
        height = true,
        x = true,
        y = true,
        borderSize = true,
        borderPadding = true,
        spacing = true,
    },
    nameplateIconText = {
        size = true,
        x = true,
        y = true,
        shadowX = true,
        shadowY = true,
    },
}

local CommitCurrentField

local function InstallLiveSliders(group, section, draft)
    if not (group and type(group._exCompositeControls) == "table") then return end
    local supported = LIVE_SLIDER_FIELDS[section]
    if not supported then return end
    local marker = GetNameplateMarker()

    for _, entry in ipairs(group._exCompositeControls) do
        local field, slider = tostring(entry.path or ""), entry.control
        if entry.kind == "slider" and supported[field] and slider and type(slider.SetLifecycleCallbacks) == "function" then
            -- 禁用复合控件旧的每格 EmitUpdate；它会走已废弃状态总线，随后
            -- 写 User Delta 并 Materialize。live 只写当前页面草稿。
            slider._onValueChanged = nil
            slider:SetLifecycleCallbacks({
                onLive = function(value)
                    group._exCompositeDb[field] = value
                    marker:ApplyLiveVisual(standardPreview, section .. "." .. field, value, draft)
                end,
                onCommit = function(value)
                    group._exCompositeDb[field] = value
                    -- 唯一正式出口：Store patch 的验证/持久化与 preview rebuild
                    -- 都只在 release、回车或输入框失焦发生一次。
                    CommitCurrentField({ fullPath = section .. "." .. field })
                    EXUI:NotifyModuleValueChanged(EDITOR_KEY, section .. "." .. field, "committed")
                end,
            })
        end
    end
end

local function InstallPageLiveSliders(draft)
    local Grid = _G.ExwindGrid
    if not (Grid and type(Grid.Widgets) == "table") then return end
    InstallLiveSliders(Grid.Widgets.nameplateIcon, "nameplateIcon", draft)
    InstallLiveSliders(Grid.Widgets.nameplateIconText, "nameplateIconText", draft)
    local spacing = Grid.Widgets.nameplateIconSpacing
    if spacing and type(spacing.SetLifecycleCallbacks) == "function" then
        spacing._onValueChanged = nil
        spacing:SetLifecycleCallbacks({
            onLive = function(value)
                draft.nameplateIcon = type(draft.nameplateIcon) == "table" and draft.nameplateIcon or {}
                draft.nameplateIcon.spacing = value
                GetNameplateMarker():ApplyLiveVisual(standardPreview, "nameplateIcon.spacing", value, draft)
            end,
            onCommit = function(value)
                draft.nameplateIcon = type(draft.nameplateIcon) == "table" and draft.nameplateIcon or {}
                draft.nameplateIcon.spacing = value
                CommitCurrentField({ fullPath = "nameplateIcon.spacing" })
                EXUI:NotifyModuleValueChanged(EDITOR_KEY, "nameplateIcon.spacing", "committed")
            end,
        })
    end
end

CommitCurrentField = function(info)
    local gridDB = Page._editorDraft
    local Store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store
    if not (gridDB and Store and type(Store.SetConfigValue) == "function") then return end
    local fullPath = tostring(info.fullPath or info.key or "")
    local path, value = { "settings" }, gridDB
    for key in fullPath:gmatch("[^%.]+") do
        path[#path + 1] = key
        value = type(value) == "table" and value[key] or nil
    end
    if #path <= 1 or value == nil then return end
    Store.SetConfigValue(path, value)
end

local function CommitActiveDraft()
    local gridDB = Page._editorDraft
    local Store = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store
    if not (type(gridDB) == "table" and Store and type(Store.SetConfigValue) == "function") then return end
    local function CommitLeaves(value, path)
        if type(value) == "table" then
            for key, child in pairs(value) do
                path[#path + 1] = key
                CommitLeaves(child, path)
                path[#path] = nil
            end
            return
        end
        local target = { "settings" }
        for index = 1, #path do target[#target + 1] = path[index] end
        Store.SetConfigValue(target, value)
    end
    CommitLeaves(gridDB, {})
end

local function ResolveGridCols(contentWidth)
    local w = tonumber(contentWidth) or 0
    if w < 100 then return BASE_GRID_COLS end
    local cols = math.floor(((w - 20) / TARGET_CELL_PX) + 0.5)
    if cols < BASE_GRID_COLS then cols = BASE_GRID_COLS end
    if cols > BASE_GRID_COLS then cols = BASE_GRID_COLS end
    return cols
end

local function ScaleLayout(items, toCols)
    if toCols == BASE_GRID_COLS then return LAYOUT end
    local cached = LAYOUT_CACHE[toCols]
    if cached then return cached end
    local scale = toCols / BASE_GRID_COLS
    local function ScaleItems(src)
        local out = {}
        for _, item in ipairs(src) do
            local row = {}
            for k, v in pairs(item) do
                if k ~= "children" then row[k] = v end
            end
            if type(item.x) == "number" and type(item.w) == "number" then
                local nx = math.floor(((item.x - 1) * scale) + 1 + 0.5)
                local nw = math.max(1, math.floor(item.w * scale + 0.5))
                if nx < 1 then nx = 1 end
                if nx > toCols then nx = toCols end
                if nx + nw - 1 > toCols then nw = math.max(1, toCols - nx + 1) end
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

-- =============================================================
-- Grid commit → 写入当前 User DIFF + 刷新显示
-- =============================================================
ExwindTools:RegisterModuleLayout(EDITOR_KEY, LAYOUT)

local function RefreshActiveSurfaces(_, phase)
    if Page._editorActive ~= true or type(Page._editorDraft) ~= "table" then return end
    -- The generic composite controls write their page draft during a Slider
    -- drag.  Persisting and Materializing here would rebuild this entire page
    -- on every tick.  Fields with a safe in-place path install it above;
    -- everything else commits once when the mouse is released.
    if phase == "changing" then return false end
    CommitActiveDraft()
    RefreshPanelPreview()
    local marker = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.NameplateMarker
    if marker and type(marker.IsScreenNameplatePreviewEnabled) == "function"
        and marker:IsScreenNameplatePreviewEnabled() == true
        and type(marker.SetScreenNameplatePreview) == "function" then
        marker:SetScreenNameplatePreview(true)
    end
end

EXUI:RegisterModuleValueController(EDITOR_KEY, {
    RefreshActiveSurfaces = RefreshActiveSurfaces,
})

-- =============================================================
-- Render
-- =============================================================
function Page:Render(contentFrame)
    local Grid = _G.ExwindGrid
    if not Grid then return end
    Page._renderGeneration = (Page._renderGeneration or 0) + 1
    local renderGeneration = Page._renderGeneration
    Page._editorRevision = (Page._editorRevision or 0) + 1
    local editorRevision = Page._editorRevision
    Page._editorActive = true

    -- 每次 Render 均从 Factory -> Author -> User 的 resolved 设置重建页面草稿。
    local gridDB = LoadRuntimeSettingsToDraft()

    if not Page._scrollFrame then
        local sf = CreateFrame("ScrollFrame", "ExBoss_GlobalTrashCDScroll",
            contentFrame, "ScrollFrameTemplate")
        if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
            ExBoss.UI.ApplyModernScrollBarSkin(sf)
        end
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        Page._scrollFrame = sf
        Page._scrollChild = sc

        local dock        = CreateFrame("Frame", "ExBoss_TrashCDNameplatePreviewDock", contentFrame, "BackdropTemplate")
        dock:SetHeight(160)
        dock:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        dock:SetBackdropBorderColor(0.20, 0.62, 0.90, 0.45)
        dock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1)
        Page._previewDock = dock

        sf:HookScript("OnHide", function()
            Page._renderGeneration = (Page._renderGeneration or 0) + 1
            Page._editorRevision = (Page._editorRevision or 0) + 1
            Page._editorActive = false
            Page._editorDraft = nil
            if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == Page._scrollChild then
                ExwindTools.UI.ActivePageFrame = nil
                ExwindTools.UI.CurrentModule = nil
            end
            if standardPreview then standardPreview:Release() end
            StopScreenNameplatePreview()
            if Page._previewDock then Page._previewDock:Hide() end
        end)
    end

    local sf = Page._scrollFrame
    local sc = Page._scrollChild
    local dock = Page._previewDock
    dock:SetParent(contentFrame)
    dock:ClearAllPoints()
    dock:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    dock:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -24, -4)
    dock:SetHeight(160)
    dock:Show()

    sf:SetParent(contentFrame)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", dock, "BOTTOMLEFT", 0, -6)
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
    sf:SetVerticalScroll(0)
    sf:Show()

    C_Timer.After(0, function()
        if Page._renderGeneration ~= renderGeneration
            or Page._editorRevision ~= editorRevision
            or Page._editorActive ~= true
            or not sf:IsShown()
            or sf:GetParent() ~= contentFrame then
            return
        end
        local w = contentFrame:GetWidth()
        if w < 100 then w = 820 end
        sc:SetWidth(w - 16)
        sc:SetParent(sf)
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", 0, 0)
        sc:Show()
        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = sc
            ExwindTools.UI.CurrentModule   = EDITOR_KEY
        end
        RefreshPanelPreview()
        local cols = ResolveGridCols(sc:GetWidth())
        if Grid.SetContainerCols then
            Grid:SetContainerCols(sc, cols)
        end
        Grid:Render(sc, ScaleLayout(LAYOUT, cols), gridDB, EDITOR_KEY)
        InstallPageLiveSliders(gridDB)
    end)
end

function Page:Hide()
    Page._renderGeneration = (Page._renderGeneration or 0) + 1
    Page._editorRevision = (Page._editorRevision or 0) + 1
    Page._editorActive = false
    Page._editorDraft = nil
    StopScreenNameplatePreview()
    if ExwindTools.UI and ExwindTools.UI.ActivePageFrame == Page._scrollChild then
        ExwindTools.UI.ActivePageFrame = nil
        ExwindTools.UI.CurrentModule = nil
    end
    local Grid = _G.ExwindGrid
    if Grid and Grid.ReleaseContainerWidgets and Page._scrollChild then
        Grid:ReleaseContainerWidgets(Page._scrollChild)
    end
    if Page._scrollFrame then Page._scrollFrame:Hide() end
end
