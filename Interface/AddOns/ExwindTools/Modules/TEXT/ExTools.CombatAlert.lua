-- =============================================================
-- 进出战斗提示：独立中央 Text 模块。
-- 业务只提交文字和状态颜色；中央唯一拥有 Anchor、Panel、World、Runtime。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.CombatAlert"
local RUNTIME_ITEM_ID = "combat-alert:runtime"
local PREVIEW_ITEM_ID = "combat-alert:preview"
local LAYOUT_DEFAULTS = { direction = "DOWN", spacing = 0, maxVisible = 1 }
local DISPLAY_WIDTH, DISPLAY_HEIGHT = 400, 100
local RefreshActiveSurfaces


local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "text",
    version = 1,
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    anchor = {
        dbPath = "$root",
        xKey = "x",
        yKey = "y",
        defaultX = 0,
        defaultY = 200,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = DISPLAY_WIDTH,
        initialHeight = DISPLAY_HEIGHT,
        clampedToScreen = true,
        bindRoot = true,
    },
    -- =========================================================
    -- 二、默认配置与配置访问 | Defaults and Configuration Access
    -- =========================================================
    defaults = {
        font_text = {
            a = 1,
            b = 1,
            font = "默认",
            g = 1,
            outline = "THICKOUTLINE",
            r = 1,
            shadow = true,
            shadowX = 2,
            shadowY = -2,
            size = 35,
            x = 0,
            y = 0,
        },
        root = {
            attachToCustom = false,
            customAttachTarget = "",
            enabled = true,
            enterColorA = 1,
            enterColorB = 0.2,
            enterColorG = 0.2,
            enterColorR = 1,
            enterMessage = L["进入战斗"],
            layout = {
                direction = "DOWN",
                maxVisible = 1,
                spacing = 0,
            },
            leaveColorA = 1,
            leaveColorB = 0.2,
            leaveColorG = 1,
            leaveColorR = 0.2,
            leaveMessage = L["离开战斗"],
            x = 7,
            y = 333,
        },
    },
    preview = {
        positionGuiKeys = {},
        elements = {
            ["core.text"] = { guiKey = "font_text", movable = false, tooltip = L["战斗提示文字"] },
        },
    },

    -- =========================================================
    -- 三、GUI 声明 | GUI Declarations
    -- =========================================================
    gui = {
        version = 1,
        sections = {
            {
                kind = "composite",
                id = "common",
                title = L["模块通用设置"],
                component = "modulecommonsettings",
                key = "moduleCommon",
                opts = {
                    bindRoot = true,
                    presentation = "settings-list",
                    fields = { { label = L["启用"], path = "enabled", presentation = "switch", type = "checkbox" } },
                    fixedLayout = {
                        controlH = 6,
                        controlW = 46,
                        firstY = 0,
                        logicalWidth = 200,
                        rowStep = 14,
                        slotX = { 3, 53, 103, 153 },
                    },
                },
            },
            {
                kind = "settings",
                id = "messages",
                title = L["提示内容"],
                items = {
                    { key = "enterMessage", label = L["进入战斗文本"], type = "input" },
                    { key = "leaveMessage", label = L["离开战斗文本"], type = "input" },
                    { key = "enterColor", label = L["进入战斗颜色"], type = "color" },
                    { key = "leaveColor", label = L["离开战斗颜色"], type = "color" },
                },
            },
            {
                kind = "composite",
                id = "anchor",
                title = L["锚点设置"],
                component = "anchorgroup",
                key = "anchor",
            },
            {
                kind = "composite",
                id = "font_text",
                title = L["文字样式"],
                component = "fontgroup",
                key = "font_text",
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterTextModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function ColorFor(kind)
    local prefix = kind == "enter" and "enterColor" or "leaveColor"
    return {
        r = DB[prefix .. "R"] or 1,
        g = DB[prefix .. "G"] or 1,
        b = DB[prefix .. "B"] or 1,
        a = DB[prefix .. "A"] or 1,
    }
end

local function BuildPresentation(kind)
    local text = kind == "enter" and DB.enterMessage or DB.leaveMessage
    if text == nil or text == "" then text = kind == "enter" and L["进入战斗"] or L["离开战斗"] end
    return {
        text = L[text] or text,
        style = DB.font_text,
        color = ColorFor(kind),
        declaredBounds = { left = -DISPLAY_WIDTH * .5, right = DISPLAY_WIDTH * .5, bottom = -DISPLAY_HEIGHT * .5, top = DISPLAY_HEIGHT * .5 },
        anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        semanticSlot = "combat-alert.message",
        interaction = EXUI:BuildStandardPreviewInteraction("Text", DB, MODULE_SPEC.preview.elements),
    }
end

local function RefreshPreview()
    central:SetPreview({ { itemID = PREVIEW_ITEM_ID, presentation = BuildPresentation("enter") } }, LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildPresentation("enter")
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] then
        controller.runtimeEntries[1].presentation = BuildPresentation("enter")
    end
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function Play(kind)
    if DB.enabled ~= true then
        central:Clear()
        return
    end
    central:SetRuntime({ { itemID = RUNTIME_ITEM_ID, presentation = BuildPresentation(kind) } }, LAYOUT)
    central:PlayRuntimeAlphaSequence(RUNTIME_ITEM_ID, {
        { from = 0, to = 1, duration = .3 },
        { from = 1, to = 1, duration = 1 },
        { from = 1, to = 0, duration = .5 },
    }, true)
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("PLAYER_REGEN_DISABLED", MODULE_KEY, function() Play("enter") end)
ExwindTools:RegisterEvent("PLAYER_REGEN_ENABLED", MODULE_KEY, function() Play("leave") end)
-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
RefreshPreview()
ExwindTools:ReportReady(MODULE_KEY)
