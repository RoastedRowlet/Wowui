-- 玩家护盾量：模块声明自己的 DB / GUI / 锚点，业务只提交标准 Icon presentation。
-- 中央不识别本模块名称、字段或业务规则。

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.PlayerShield"
local RUNTIME_ITEM_ID = "player-shield:runtime"
local REFRESH_THROTTLE = 0.2
local ICON_HIDE_DELAY = 10
local RefreshActiveSurfaces


-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 1,
    features = { icon = true, labelText = true, enabled = true },
    textSlots = { label = L["护盾文字样式"] },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    anchor = {
        dbPath = "$root",
        bindRoot = true,
        xKey = "xOffset",
        yKey = "yOffset",
        defaultX = 0,
        defaultY = -120,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 40,
        initialHeight = 40,
        clampedToScreen = true,
    },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    preview = {
        positionGuiKeys = { "font_text" },
        elements = {
            ["core.label"] = {
                guiKey = "font_text",
                movable = true,
                textRole = "label",
                tooltip = L["护盾文字样式"],
                position = { x = "font_text.x", y = "font_text.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
        },
    },
    -- =========================================================
    -- 二、默认配置与配置访问 | Defaults and Configuration Access
    -- =========================================================
    defaults = {
        font_text = {
            a = 1,
            autoWidth = false,
            b = 1,
            font = "默认",
            g = 0.91372555494308,
            justifyH = "CENTER",
            justifyV = "MIDDLE",
            outline = "OUTLINE",
            r = 0.24705883860588,
            shadow = true,
            shadowX = 1,
            shadowY = -1,
            size = 18,
            x = 0,
            y = -6,
        },
        icon = {
            alpha = 1,
            blendMode = "BLEND",
            borderColorA = 1,
            borderColorB = 0,
            borderColorG = 0,
            borderColorR = 0,
            borderPadding = 0.6,
            borderSize = 0,
            borderTexture = "EX_Default",
            colorA = 1,
            colorB = 1,
            colorG = 1,
            colorR = 1,
            cooldown = { edgeAlpha = 0.75, showBling = false, showEdge = true, showSwipe = true, swipeAlpha = 0.55000001192093, },
            cropBottom = 0.92,
            cropLeft = 0.08,
            cropRight = 0.92,
            cropTop = 0.08,
            desaturated = false,
            enableCrop = true,
            height = 45,
            iconID = 135940,
            reverse = false,
            showBorder = true,
            showCooldown = true,
            showIcon = true,
            width = 45,
            x = 0,
            y = 0,
        },
        root = {
            abbreviateNumber = true,
            attachToCustom = false,
            customAttachTarget = "",
            enabled = true,
            hideWhenZero = true,
            layout = { direction = "DOWN", maxVisible = 1, spacing = 0, },
            xOffset = -48,
            yOffset = -330,
        },
    },
    samples = {
        panel = { itemID = "player-shield:sample", icon = 135940, text = string.format(L["%d万"], 125) },
        world = { itemID = "player-shield:sample", icon = 135940, text = string.format(L["%d万"], 125) },
    },
    -- [卡片迁移边界：设置页] 仅可按统一规范调整下列 gui.static/gui.fields 的 x/y/w/h 与卡片分组。
    -- key/type/opts、DB path、anchor/preview/defaults 及刷新回调均属绑定或业务合同，禁止修改；复合控件必须整体引用，header 本身不等于卡片容器。
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
                        fields = {
                            { column = 1, label = L["启用"], path = "enabled", presentation = "switch", row = 1, type = "checkbox", },
                            { column = 2, label = L["数值为零时隐藏"], path = "hideWhenZero", presentation = "switch", row = 1, type = "checkbox", },
                            { column = 3, label = L["数字缩写"], path = "abbreviateNumber", presentation = "switch", row = 1, type = "checkbox", },
                        },
                        fixedLayout = {
                            controlH = 6,
                            controlW = 46,
                            firstY = 0,
                            logicalWidth = 200,
                            rowStep = 14,
                            slotX = { 3, 53, 103, 153, },
                        },
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
                id = "icon",
                title = L["护盾图标样式"],
                component = "icongroup",
                key = "icon",
            },
            {
                kind = "composite",
                id = "font_text",
                title = L["护盾文字样式"],
                component = "fontgroup",
                key = "font_text",
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

local function MakeTextBounds(style)
    return {
        width = 200,
        height = math.max(18, tonumber(style.size) or 18),
        anchor = { point = "CENTER", relativePoint = "CENTER", x = tonumber(style.x) or 0, y = tonumber(style.y) or 0 },
    }
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function BuildEntry(itemID, icon, text)
    local db = DB
    local iconStyle = db.icon or {}
    local width = math.max(1, tonumber(iconStyle.width) or 40)
    local height = math.max(1, tonumber(iconStyle.height) or 40)
    return {
        itemID = itemID,
        presentation = {
            style = { icon = iconStyle, text = { label = db.font_text or {} } },
            icon = { value = icon },
            label = text,
            bodySize = { width = width, height = height },
            declaredBounds = { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 },
            semanticBounds = { ["core.label"] = MakeTextBounds(db.font_text or {}) },
            interaction = EXUI:BuildStandardPreviewInteraction("Icon", db, MODULE_SPEC.preview.elements),
        },
    }
end

central:SetPreview(
    { BuildEntry(MODULE_SPEC.samples.panel.itemID, MODULE_SPEC.samples.panel.icon, MODULE_SPEC.samples.panel.text) },
    LAYOUT
)

-- 护盾事件与 Secret-safe 文本：只生成业务状态，绝不创建显示对象。
local GetTime = _G.GetTime
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers
local AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers
local AbbreviateNumbers = _G.AbbreviateNumbers
local C_StringUtil = _G.C_StringUtil
local C_Timer = _G.C_Timer
local math_abs, math_floor, math_max = math.abs, math.floor, math.max
local refreshTimer, iconHideTimer, lastAbsorbEventTime

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function IsSecretValue(value)
    return type(_G.issecretvalue) == "function" and _G.issecretvalue(value)
end

local function GetPlayerShieldAmount()
    local amount = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("player") or nil
    if IsSecretValue(amount) then return amount, true end
    return math_max(0, tonumber(amount) or 0), false
end

local function FormatSecretLargeNumberCN(value)
    if not AbbreviateNumbers then
        return AbbreviateLargeNumbers and AbbreviateLargeNumbers(value) or
            string.format("%s", value)
    end
    return AbbreviateNumbers(value, {
        breakpointData = {
            { breakpoint = 100000000, abbreviation = "亿", significandDivisor = 100000000, fractionDivisor = 1, abbreviationIsGlobal = false },
            { breakpoint = 10000, abbreviation = "万", significandDivisor = 10000, fractionDivisor = 1, abbreviationIsGlobal = false },
        }
    })
end

local function FormatShieldValue(amount)
    if DB.abbreviateNumber then
        -- Native formatting follows the active game locale (e.g. 万/亿 or K/M)
        -- and can safely format protected numeric values.
        if AbbreviateLargeNumbers then return AbbreviateLargeNumbers(amount) end
        if IsSecretValue(amount) then return FormatSecretLargeNumberCN(amount) end
        if amount >= 100000000 then return string.format(L["%.2f亿"], amount / 100000000) end
        if amount >= 10000 then return string.format(L["%d万"], math_floor(amount / 10000)) end
    elseif IsSecretValue(amount) then
        return string.format("%.0f", amount)
    end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(math_floor(amount + 0.5)) or tostring(math_floor(amount + 0.5))
end

local function BuildSecretZeroSafeValueText(amount)
    return C_StringUtil and type(C_StringUtil.TruncateWhenZero) == "function" and C_StringUtil.TruncateWhenZero(amount) or
        nil
end

local function IsIconEventActive()
    return lastAbsorbEventTime ~= nil and (GetTime() - lastAbsorbEventTime) < ICON_HIDE_DELAY
end

local function PublishRuntimeState()
    local db = DB
    if db.enabled ~= true then
        central:Clear(); return
    end
    if db.icon and db.icon.showIcon ~= false and not IsIconEventActive() then
        central:Clear(); return
    end
    local amount, isSecret = GetPlayerShieldAmount()
    if db.hideWhenZero and not isSecret and math_abs(tonumber(amount) or 0) <= 0.0001 then
        central:Clear(); return
    end
    local text = isSecret and db.hideWhenZero and not db.abbreviateNumber and BuildSecretZeroSafeValueText(amount) or
        FormatShieldValue(amount)
    central:SetRuntime({ BuildEntry(RUNTIME_ITEM_ID, (db.icon or {}).iconID, text) }, LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        local sample = MODULE_SPEC.samples.panel
        controller.previewEntries[1].presentation = BuildEntry(sample.itemID, sample.icon, sample.text).presentation
    end
    if not (controller.runtimeEntries and controller.runtimeEntries[1]) then return end
    local db = DB
    if db.enabled ~= true or (db.icon and db.icon.showIcon ~= false and not IsIconEventActive()) then return end
    local amount, isSecret = GetPlayerShieldAmount()
    if db.hideWhenZero and not isSecret and math_abs(tonumber(amount) or 0) <= 0.0001 then return end
    local text = isSecret and db.hideWhenZero and not db.abbreviateNumber and BuildSecretZeroSafeValueText(amount) or
        FormatShieldValue(amount)
    controller.runtimeEntries[1].presentation = BuildEntry(RUNTIME_ITEM_ID, (db.icon or {}).iconID, text).presentation
end

local function ScheduleRefresh()
    if refreshTimer then return end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        refreshTimer = C_Timer.NewTimer(REFRESH_THROTTLE, function()
            refreshTimer = nil; PublishRuntimeState()
        end)
    elseif C_Timer and type(C_Timer.After) == "function" then
        refreshTimer = true
        C_Timer.After(REFRESH_THROTTLE, function()
            refreshTimer = nil; PublishRuntimeState()
        end)
    else
        PublishRuntimeState()
    end
end

local function MarkAbsorbEventActive()
    lastAbsorbEventTime = GetTime()
    if iconHideTimer and type(iconHideTimer.Cancel) == "function" then iconHideTimer:Cancel() end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        iconHideTimer = C_Timer.NewTimer(ICON_HIDE_DELAY, function()
            iconHideTimer = nil; PublishRuntimeState()
        end)
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", MODULE_KEY, function(_, unit)
    if unit == "player" then
        MarkAbsorbEventActive(); ScheduleRefresh()
    end
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, ScheduleRefresh)
-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ScheduleRefresh()
ExwindTools:ReportReady(MODULE_KEY)
