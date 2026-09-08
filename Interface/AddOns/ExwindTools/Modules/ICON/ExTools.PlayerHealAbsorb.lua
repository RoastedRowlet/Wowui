-- =============================================================
-- 玩家治疗吸收：业务状态 + 标准 IconCollection presentation。
-- 中央只管理通用 Collection、Anchor、Panel 与 World 生命周期。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.PlayerHealAbsorb"
local RUNTIME_ITEM_ID = "player-heal-absorb:runtime"
local REFRESH_THROTTLE = 0.2
local ICON_HIDE_DELAY = 10
local DEFAULT_ICON_SPELL_ID = 6788
local RefreshActiveSurfaces


-- 默认值、锚点、预览语义与每一个 Grid 坐标均由模块声明；中央没有模块分支。
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 1,
    features = { icon = true, labelText = true, secretLabelText = true },
    textSlots = { label = L["治疗吸收文字样式"] },
    anchor = {
        dbPath = "$root",
        xKey = "xOffset",
        yKey = "yOffset",
        defaultX = 0,
        defaultY = -160,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 96,
        initialHeight = 36,
        clampedToScreen = true,
        bindRoot = true,
    },
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
            borderColorA = 1,
            borderColorB = 0,
            borderColorG = 0,
            borderColorR = 0,
            borderPadding = 0.6,
            borderSize = 0,
            borderTexture = "EX_Default",
            height = 45,
            iconID = 135871,
            reverse = false,
            showBorder = true,
            showIcon = true,
            width = 45,
            x = 0,
            y = 0,
        },
        root = {
            abbreviateNumber = true,
            attachToCustom = false,
            customAttachTarget = "",
            enabled = false,
            hideWhenZero = true,
            layout = {
                direction = "RIGHT",
                maxVisible = 1,
                mode = "FLOW",
                spacing = 0,
            },
            xOffset = 15,
            yOffset = -329,
        },
    },
    preview = {
        positionGuiKeys = { "font_text" },
        elements = {
            ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["治疗吸收图标样式"] },
            ["core.label"] = {
                guiKey = "font_text",
                movable = true,
                textRole = "label",
                tooltip = L["治疗吸收文字样式"],
                position = { x = "font_text.x", y = "font_text.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
        },
        sample = { amount = 360000, itemID = "player-heal-absorb:preview" },
    },
    gui = {
        fields = {
            {
                group = "settings",
                h = 26,
                key = "moduleCommon",
                label = L["模块通用设置"],
                options = {
                    bindRoot = true,
                    fields = {
                        {
                            column = 1,
                            label = L["启用"],
                            path = "enabled",
                            row = 1,
                            type = "checkbox",
                        },
                        {
                            column = 2,
                            label = L["数值为零时隐藏"],
                            path = "hideWhenZero",
                            row = 1,
                            type = "checkbox",
                        },
                        {
                            column = 3,
                            label = L["数字缩写"],
                            path = "abbreviateNumber",
                            row = 1,
                            type = "checkbox",
                        },
                    },
                    fixedLayout = {
                        controlH = 6,
                        controlW = 46,
                        firstY = 0,
                        logicalWidth = 200,
                        rowStep = 14,
                        slotX = {
                            3,
                            53,
                            103,
                            153,
                        },
                    },
                },
                order = 1,
                type = "modulecommonsettings",
                w = 200,
                x = 1,
                y = 10,
            },
            {
                group = "settings",
                h = 20,
                key = "anchor",
                label = L["锚点设置"],
                order = 2,
                type = "anchorgroup",
                w = 200,
                x = 1,
                y = 39,
            },
            {
                group = "settings",
                h = 50,
                key = "icon",
                label = L["治疗吸收图标样式"],
                labelSize = 20,
                order = 3,
                type = "icongroup",
                w = 200,
                x = 1,
                y = 62,
            },
            {
                group = "settings",
                h = 50,
                key = "font_text",
                label = L["治疗吸收文字样式"],
                labelSize = 20,
                order = 4,
                type = "fontgroup",
                w = 200,
                x = 1,
                y = 115,
            },
        },
        groups = {
            {
                key = "settings",
                order = 1,
            },
        },
        static = {
            {
                h = 6,
                key = "header",
                label = L["玩家治疗吸收盾"],
                labelSize = 25,
                type = "header",
                w = 200,
                x = 1,
                y = 1,
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

local GetTime = _G.GetTime
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers
local AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers
local AbbreviateNumbers = _G.AbbreviateNumbers
local C_StringUtil = _G.C_StringUtil
local C_Timer = _G.C_Timer
local math_abs, math_floor, math_max = math.abs, math.floor, math.max
local refreshTimer, iconHideTimer, lastHealAbsorbEventTime

local function IsSecretValue(value)
    return type(_G.issecretvalue) == "function" and _G.issecretvalue(value)
end

local function ReadPlayerHealAbsorb()
    local amount = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs("player") or nil
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

local function FormatHealAbsorbValue(amount)
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

local function ResolveIcon()
    local configured = DB.icon and DB.icon.iconID
    if configured then return configured end
    if _G.C_Spell and type(_G.C_Spell.GetSpellTexture) == "function" then
        return _G.C_Spell.GetSpellTexture(
            DEFAULT_ICON_SPELL_ID)
    end
    return _G.GetSpellTexture and _G.GetSpellTexture(DEFAULT_ICON_SPELL_ID) or nil
end

local function BuildPresentation(text, iconShown)
    local db, icon, font = DB, DB.icon or {}, DB.font_text or {}
    local width = math_max(1, tonumber(icon.width) or 36)
    local height = math_max(1, tonumber(icon.height) or 36)
    return {
        style = { icon = icon, text = { label = font } },
        icon = ResolveIcon(),
        label = text,
        bodySize = { width = width, height = height },
        declaredBounds = { left = -width / 2, right = width / 2, bottom = -height / 2, top = height / 2 },
        interaction = EXUI:BuildStandardPreviewInteraction("Icon", db, MODULE_SPEC.preview.elements),
    }
end

local function SetStandardPreview()
    local text = FormatHealAbsorbValue(MODULE_SPEC.preview.sample.amount)
    local entry = { itemID = MODULE_SPEC.preview.sample.itemID, presentation = BuildPresentation(text, true) }
    central:SetPreview({ entry }, LAYOUT)
end

local function IsIconEventActive()
    return lastHealAbsorbEventTime ~= nil and (GetTime() - lastHealAbsorbEventTime) < ICON_HIDE_DELAY
end

local function PublishRuntimeState()
    local db = DB
    if db.enabled ~= true then
        central:Clear(); return
    end
    local iconShown = IsIconEventActive()
    if db.icon and db.icon.showIcon ~= false and not iconShown then
        central:Clear(); return
    end
    local amount, isSecret = ReadPlayerHealAbsorb()
    if db.hideWhenZero and not isSecret and math_abs(tonumber(amount) or 0) <= 0.0001 then
        central:Clear(); return
    end
    local text = isSecret and db.hideWhenZero and not db.abbreviateNumber and C_StringUtil
        and type(C_StringUtil.TruncateWhenZero) == "function" and C_StringUtil.TruncateWhenZero(amount)
        or FormatHealAbsorbValue(amount)
    central:SetRuntime({ { itemID = RUNTIME_ITEM_ID, presentation = BuildPresentation(text or "", iconShown) } },
        LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildPresentation(FormatHealAbsorbValue(MODULE_SPEC.preview.sample.amount), true)
    end
    if not (controller.runtimeEntries and controller.runtimeEntries[1]) then return end
    local db, iconShown = DB, IsIconEventActive()
    if db.enabled ~= true or (db.icon and db.icon.showIcon ~= false and not iconShown) then return end
    local amount, isSecret = ReadPlayerHealAbsorb()
    if db.hideWhenZero and not isSecret and math_abs(tonumber(amount) or 0) <= 0.0001 then return end
    local text = isSecret and db.hideWhenZero and not db.abbreviateNumber and C_StringUtil
        and type(C_StringUtil.TruncateWhenZero) == "function" and C_StringUtil.TruncateWhenZero(amount)
        or FormatHealAbsorbValue(amount)
    controller.runtimeEntries[1].presentation = BuildPresentation(text or "", iconShown)
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

local function MarkHealAbsorbEventActive()
    lastHealAbsorbEventTime = GetTime()
    if iconHideTimer and type(iconHideTimer.Cancel) == "function" then iconHideTimer:Cancel() end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        iconHideTimer = C_Timer.NewTimer(ICON_HIDE_DELAY, function()
            iconHideTimer = nil; PublishRuntimeState()
        end)
    end
end

ExwindTools:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", MODULE_KEY, function(_, unit)
    if unit == "player" then
        MarkHealAbsorbEventActive(); ScheduleRefresh()
    end
end)
ExwindTools:RegisterEvent("UNIT_HEAL_PREDICTION", MODULE_KEY, function(_, unit)
    if unit == "player" then ScheduleRefresh() end
end)
ExwindTools:RegisterEvent("UNIT_MAXHEALTH", MODULE_KEY, function(_, unit)
    if unit == "player" then ScheduleRefresh() end
end)
ExwindTools:RegisterEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", MODULE_KEY, function(_, unit)
    if unit == "player" then ScheduleRefresh() end
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, ScheduleRefresh)
SetStandardPreview()
ScheduleRefresh()
ExwindTools:ReportReady(MODULE_KEY)
