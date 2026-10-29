---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossGUI/SettingsPage/GlobalTrashCDPage.lua
-- 小怪CD 全局设置页（V2 声明）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI
if not EXUI then return end
local L                           = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

ExBoss.UI.Panel.GlobalTrashCDPage = ExBoss.UI.Panel.GlobalTrashCDPage or {}
local Page                        = ExBoss.UI.Panel.GlobalTrashCDPage

-- 仅用于页面事件；TrashCD 设置的唯一持久 owner 是 Store 的
-- Factory -> Author -> User 链路，不能再把页面草稿放进 ModuleDB。
local EDITOR_KEY                  = "ExBoss.TrashCD.Settings.Editor"
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

-- =============================================================
-- 布局
-- =============================================================
-- 图标组/字体组整体复用；面板预览和屏幕姓名版预览独立管理。
local LAYOUT = {
    version = 2,
    layout = "stack",
    cards = {
        { kind = "card", id = "placement", title = L["通用"],
            children = {
                { kind = "control", id = "nameplateIconSpacing", path = "nameplateIcon.spacing", controlType = "slider", min = 0, max = 50, step = 1, label = L["图标间距"] },
                { kind = "control", id = "nameplateGrowthSide", path = "nameplateGrowthSide", controlType = "select", label = L["图标增长方向"], options = { { value = "left", label = L["左侧"] }, { value = "right", label = L["右侧"] } } },
                { kind = "control", id = "nameplateIconStrata", path = "nameplateIconStrata", controlType = "select", label = L["图标层级"], options = { { value = "BACKGROUND", label = "BACKGROUND" }, { value = "LOW", label = "LOW" }, { value = "MEDIUM", label = "MEDIUM" }, { value = "HIGH", label = "HIGH" }, { value = "DIALOG", label = "DIALOG" }, { value = "FULLSCREEN", label = "FULLSCREEN" }, { value = "FULLSCREEN_DIALOG", label = "FULLSCREEN_DIALOG" }, { value = "TOOLTIP", label = "TOOLTIP" } } },
                { kind = "control", id = "hideNameplateIconAboveSeconds", path = "hideNameplateIconAboveSeconds", controlType = "input", label = L["隐藏剩余超过 X 秒的图标（0=关闭）"] },
                { kind = "setting", id = "previewRow", label = L["屏幕敌方姓名版预览 开/关"], children = {
                    { kind = "button", id = "screenNameplatePreview", text = L["预览"], action = "screenNameplatePreview" },
                } },
            } },
        { kind = "card", id = "icon", title = L["外观"], children = {
            { kind = "component", id = "nameplateIcon", component = "icongroup", path = "nameplateIcon", opts = { enableOffset = true, hideIconID = true } },
        } },
        { kind = "card", id = "text", title = L["倒数时间文本"], children = {
            { kind = "component", id = "nameplateIconText", component = "fontgroup", path = "nameplateIconText" },
        } },
    },
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
        if src[key] == nil then dst[key] = nil end
    end
    for key, value in pairs(src) do
        if type(value) == "table" and type(dst[key]) == "table" then
            ReplaceTable(dst[key], value)
        else
            dst[key] = DeepCopy(value)
        end
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

-- 页面和复合控件始终持有同一份草稿及子表，重载 resolved 时原地替换内容。
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
    local page = EXUI:GetModulePage(EDITOR_KEY, Page._scrollChild)
    if page then page:Refresh() end
end

local function FocusPreviewGUI(guiTarget)
    local target = tostring(guiTarget or "")
    if target ~= "nameplateIcon" and target ~= "nameplateIconText" then
        error("TrashCD nameplate preview has no GUI target for " .. target, 2)
    end
    local page = EXUI:GetModulePage(EDITOR_KEY, Page._scrollChild)
    if not page or not page:Focus(target, Page._scrollFrame) then
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

-- 只将这些纯视觉 Slider 接到姓名版的轻量预览；其余字段保留标准提交。
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

local function IsDraftCurrent(draft)
    return Page._editorActive == true and Page._editorDraft == draft
        and Page._v2Session ~= nil and Page._v2Session.alive == true
end

local function InstallLiveSliders(group, section, draft)
    if not (group and type(group._exCompositeControls) == "table") then return end
    local supported = LIVE_SLIDER_FIELDS[section]
    if not supported then return end
    local marker = GetNameplateMarker()

    for _, entry in ipairs(group._exCompositeControls) do
        local field, slider = tostring(entry.path or ""), entry.control
        if entry.kind == "slider" and supported[field] and slider and type(slider.SetLifecycleCallbacks) == "function" then
            -- live 只写当前页面草稿并更新面板视觉，提交才刷新正式表面。
            slider._onValueChanged = nil
            slider:SetLifecycleCallbacks({
                onLive = function(value)
                    if not IsDraftCurrent(draft) then return end
                    group._exCompositeDb[field] = value
                    marker:ApplyLiveVisual(standardPreview, section .. "." .. field, value, draft)
                end,
                onCommit = function(value)
                    if not IsDraftCurrent(draft) then return end
                    group._exCompositeDb[field] = value
                    -- 正式出口由唯一 ValueController 提交 Store 并刷新预览。
                    EXUI:NotifyModuleValueChanged(EDITOR_KEY, section .. "." .. field, "committed")
                end,
            })
        end
    end
end

local function InstallPageLiveSliders(draft)
    local page = EXUI:GetModulePage(EDITOR_KEY, Page._scrollChild)
    if not page then return end
    InstallLiveSliders(page:Find("nameplateIcon"), "nameplateIcon", draft)
    InstallLiveSliders(page:Find("nameplateIconText"), "nameplateIconText", draft)
    local spacing = page:Find("nameplateIconSpacing")
    if spacing and type(spacing.SetLifecycleCallbacks) == "function" then
        spacing._onValueChanged = nil
        spacing:SetLifecycleCallbacks({
            onLive = function(value)
                if not IsDraftCurrent(draft) then return end
                draft.nameplateIcon = type(draft.nameplateIcon) == "table" and draft.nameplateIcon or {}
                draft.nameplateIcon.spacing = value
                GetNameplateMarker():ApplyLiveVisual(standardPreview, "nameplateIcon.spacing", value, draft)
            end,
            onCommit = function(value)
                if not IsDraftCurrent(draft) then return end
                draft.nameplateIcon = type(draft.nameplateIcon) == "table" and draft.nameplateIcon or {}
                draft.nameplateIcon.spacing = value
                EXUI:NotifyModuleValueChanged(EDITOR_KEY, "nameplateIcon.spacing", "committed")
            end,
        })
    end
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

-- =============================================================
-- V2 commit → 写入当前 User DIFF + 刷新显示
-- =============================================================
EXUI:RegisterSettingsPageV2(EDITOR_KEY, LAYOUT)

local function RefreshActiveSurfaces(_, changedPath, phase)
    if Page._editorActive ~= true or type(Page._editorDraft) ~= "table" then return end
    -- The generic composite controls write their page draft during a Slider
    -- drag.  Persisting and Materializing here would rebuild this entire page
    -- on every tick.  Fields with a safe in-place path install it above;
    -- everything else commits once when the mouse is released.
    if phase == "changing" then return false end
    CommitActiveDraft()
    RefreshVisibleControls()
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
-- 目录切换隐藏 ScrollFrame、再次 Render 或显式 Hide 都释放设置会话。
local function ReleaseSettingsSession()
    Page._v2Session = nil
    if Page._scrollChild then
        EXUI:ReleaseModuleSettingsPage(Page._scrollChild)
    end
end

function Page:Render(contentFrame)
    Page._editorActive = false
    ReleaseSettingsSession()
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
        EXUI:ApplyStandardPreviewShellStyle(dock, true)
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
            ReleaseSettingsSession()
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
    sf:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
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
        local owner = {
            binding = { moduleKey = EDITOR_KEY, config = gridDB },
            actions = {
                screenNameplatePreview = function(context)
                    if context:IsCurrent() and IsDraftCurrent(gridDB) then ToggleScreenNameplatePreview() end
                end,
            },
        }
        Page._v2Session = EXUI:MountModuleSettingsDeclarationV2(
            sc, EDITOR_KEY, owner, L["小怪内置CD姓名版图标"], nil, sf)
        InstallPageLiveSliders(gridDB)
    end)
end

-- 显式 Hide 与目录隐藏同样释放设置会话。
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
    ReleaseSettingsSession()
    if Page._scrollFrame then Page._scrollFrame:Hide() end
end
