-- =============================================================
--TEST
-- 战斗复活：模块声明自身 DB、GUI、锚点与标准 IconCollection presentation。
-- 中央只管理通用 Collection 宿主，不识别本模块或任何业务名称。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExTools.BattleResurrection"
local SPELL_ID_REBIRTH = 20484
local RUNTIME_ITEM_ID = "battle-resurrection:runtime"
local RefreshActiveSurfaces
local C_StringUtil, Enum = _G.C_StringUtil, _G.Enum

-- 战复充能计时固定显示为 MM:SS。仍由原生 DurationTextBinding 驱动，模块不读取或
-- 计算 Duration Object 的内部时间。
local BATTLE_RES_MINUTES_FORMATTER = C_StringUtil.CreateNumericRuleFormatter()
BATTLE_RES_MINUTES_FORMATTER:SetBreakpoints({ {
    threshold = 0,
    format = "%02.0f",
    components = { { div = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down } },
} })
local BATTLE_RES_SECONDS_FORMATTER = C_StringUtil.CreateNumericRuleFormatter()
BATTLE_RES_SECONDS_FORMATTER:SetBreakpoints({ {
    threshold = 0,
    format = "%02.0f",
    components = { { mod = 60, step = 1, rounding = Enum.NumericRuleFormatRounding.Down } },
} })

local function FormatBattleResTime(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    return string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function BuildBattleResDurationTextOptions()
    return {
        formatString = "{}:{}",
        components = {
            { property = Enum.DurationTextBindingProperty.RemainingDuration, formatter = BATTLE_RES_MINUTES_FORMATTER },
            { property = Enum.DurationTextBindingProperty.RemainingDuration, formatter = BATTLE_RES_SECONDS_FORMATTER },
        },
        expiredText = "00:00",
        zeroDurationText = "00:00",
    }
end


-- 模块自己的默认值与所有 Grid 几何；中央只校验、持久化并渲染本声明。
-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 1,
    features = { cooldown = true, timeText = true, stacksText = true, enabled = true },
    textSlots = { time = L["战复计时文字"], stacks = L["战复次数文字"] },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    anchor = {
        dbPath = "anchor",
        xKey = "x",
        yKey = "y",
        defaultX = -831,
        defaultY = -65,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 50,
        initialHeight = 50,
        clampedToScreen = true,
    },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    preview = {
        positionGuiKeys = { "font_time", "font_stacks" },
        elements = {
            ["core.time"] = {
                guiKey = "font_time",
                movable = true,
                textRole = "time",
                tooltip = L["战复计时文字"],
                position = { x = "font_time.x", y = "font_time.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
            ["icon.stacks"] = {
                guiKey = "font_stacks",
                movable = true,
                textRole = "stacks",
                tooltip = L["战复次数文字"],
                position = { x = "font_stacks.x", y = "font_stacks.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
        },
    },
    -- =========================================================
    -- 二、默认配置与配置访问 | Defaults and Configuration Access
    -- =========================================================
    defaults = {
        root = {
            anchor = {
                attachToCustom = false,
                customAttachTarget = "",
                x = -514,
                y = -108,
            },
            enabled = true,
            font_stacks = {
                a = 1,
                autoWidth = false,
                b = 1,
                enabled = true,
                fixedWidth = 200,
                font = "Friz Quadrata TT",
                g = 1,
                gradientEnabled = false,
                gradientLength = 0,
                gradientStart = 0,
                justifyH = "CENTER",
                justifyV = "MIDDLE",
                maxWidth = 0,
                outline = "OUTLINE",
                r = 1,
                rotation = 0,
                shadow = false,
                shadowColorA = 1,
                shadowColorB = 0,
                shadowColorG = 0,
                shadowColorR = 0,
                shadowX = 1,
                shadowY = -1,
                size = 22,
                x = 90.36622197954,
                y = 0.79973856533599,
            },
            font_time = {
                a = 1,
                autoWidth = false,
                b = 0,
                enabled = true,
                fixedWidth = 200,
                font = "默认",
                g = 0.82,
                gradientEnabled = false,
                gradientLength = 0,
                gradientStart = 0,
                justifyH = "CENTER",
                justifyV = "MIDDLE",
                maxWidth = 0,
                outline = "OUTLINE",
                r = 1,
                rotation = 0,
                shadow = false,
                shadowColorA = 1,
                shadowColorB = 0,
                shadowColorG = 0,
                shadowColorR = 0,
                shadowX = 1,
                shadowY = -1,
                size = 20,
                x = 0,
                y = 0,
            },
            icon = {
                alpha = 1,
                borderColorA = 1,
                borderColorB = 0,
                borderColorG = 0,
                borderColorR = 0,
                borderPadding = 0.30000019073486,
                borderSize = 0,
                borderTexture = "EX_Default",
                cooldown = {
                    edgeAlpha = 0.75,
                    showBling = false,
                    showEdge = true,
                    showSwipe = true,
                    swipeAlpha = 0.55000001192093,
                },
                enableCrop = true,
                height = 60,
                reverse = false,
                showBorder = true,
                showCooldown = true,
                showIcon = true,
                width = 60,
            },
            layout = {
                direction = "DOWN",
                maxVisible = 1,
                spacing = 0,
            },
        },
    },
    -- [卡片迁移边界：设置页] 仅可按统一规范调整下列 gui.static/gui.fields 的 x/y/w/h 与卡片分组。
    -- key/type/opts、DB path、anchor/preview/defaults 及刷新回调均属绑定或业务合同，禁止修改；复合控件必须整体引用，header 本身不等于卡片容器。
    -- =========================================================
    -- 三、GUI 声明 | GUI Declarations
    -- =========================================================
    gui = {
        version = 1,
        description = L["战复次数与充能倒数由中央显示层渲染"],
        sections = {
            {
                kind = "composite", id = "common", title = L["模块通用设置"],
                component = "modulecommonsettings", key = "moduleCommon", opts = {
                    bindRoot = true,
                    presentation = "settings-list",
                    fields = {
                        { label = L["启用战复监控"], path = "enabled", presentation = "switch", type = "checkbox" },
                    },
                    fixedLayout = {
                        controlH = 6, controlW = 46, firstY = 0, logicalWidth = 200,
                        rowStep = 14, slotX = { 3, 53, 103, 153 },
                    },
                },
            },
            {
                kind = "composite", id = "anchor", title = L["锚点设置"],
                component = "anchorgroup", key = "anchor",
            },
            {
                kind = "composite", id = "icon", title = L["战复整体图标与位置"],
                component = "icongroup", key = "icon",
            },
            {
                kind = "composite", id = "font_time", title = L["战复计时文字（中心）"],
                component = "fontgroup", key = "font_time",
            },
            {
                kind = "composite", id = "font_stacks", title = L["战复次数文字（右下）"],
                component = "fontgroup", key = "font_stacks",
            },
        },
    },
    samples = {
        panel = { itemID = "battle-resurrection:sample", icon = 136080, stacks = "2", cooldownSeconds = 55, cooldownDuration = 60 },
        world = { itemID = "battle-resurrection:sample", icon = 136080, stacks = "2", cooldownSeconds = 55, cooldownDuration = 60 },
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
        anchor = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = tonumber(style.x) or 0,
            y = tonumber(style.y) or 0,
        },
    }
end

-- 这是标准 IconCollection presentation；模块只交纯数据显示，中央不接收模块函数。
-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function BuildEntry(itemID, icon, stacks, cooldown)
    local db = DB
    local iconStyle = db.icon or {}
    local width = math.max(1, tonumber(iconStyle.width) or 50)
    local height = math.max(1, tonumber(iconStyle.height) or 50)
    return {
        itemID = itemID,
        presentation = {
            style = { icon = iconStyle, text = { countdown = db.font_time or {}, stacks = db.font_stacks or {} } },
            icon = { value = icon },
            label = "",
            stacks = stacks,
            cooldown = cooldown,
            bodySize = { width = width, height = height },
            declaredBounds = { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 },
            semanticBounds = {
                ["core.time"] = MakeTextBounds(db.font_time or {}),
                ["icon.stacks"] = MakeTextBounds(db.font_stacks or {}),
            },
            interaction = EXUI:BuildStandardPreviewInteraction("Icon", db, MODULE_SPEC.preview.elements),
        },
    }
end

local function BuildSampleEntry(sample)
    return BuildEntry(sample.itemID, sample.icon, sample.stacks, {
        static = true, remaining = sample.cooldownSeconds, duration = sample.cooldownDuration,
        text = FormatBattleResTime(sample.cooldownSeconds),
    })
end

central:SetPreview({ BuildSampleEntry(MODULE_SPEC.samples.panel) }, LAYOUT)

-- =============================================================
-- 战复业务：环境判断、原生充能对象与刷新订阅。
-- 不创建或操作任何显示对象。
-- =============================================================
-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function IsActiveEnvironment()
    local state = ExwindTools.State or {}
    if state.DifficultyID == 8 then return true end
    if state.InstanceType == "party" then return false end
    return state.InstanceType == "raid" and state.IsBossEncounter == true or state.IsBossEncounter == true
end

local function GetChargeState()
    -- Restricted cooldown 字段只能原样交给中央 Icon；业务不读取、比较或换算。
    local current, durationObject = nil, nil
    if C_Spell and C_Spell.GetSpellDisplayCount then current = C_Spell.GetSpellDisplayCount(SPELL_ID_REBIRTH) end
    if C_Spell and C_Spell.GetSpellChargeDuration then durationObject = C_Spell.GetSpellChargeDuration(SPELL_ID_REBIRTH) end
    return current, durationObject
end

local function RefreshBattleResurrection()
    local current, durationObject = GetChargeState()
    if DB.enabled ~= true or not IsActiveEnvironment() then
        central:Clear()
        return
    end
    local cooldown = durationObject ~= nil and {
        mode = "DURATION",
        duration = durationObject,
        clearIfZero = true,
        durationTextOptions = BuildBattleResDurationTextOptions(),
    } or nil
    central:SetRuntime({ BuildEntry(RUNTIME_ITEM_ID, 136080, current, cooldown) }, LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildSampleEntry(MODULE_SPEC.samples.panel).presentation
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and DB.enabled == true and IsActiveEnvironment() then
        local current, durationObject = GetChargeState()
        local cooldown = durationObject and {
            mode = "DURATION",
            duration = durationObject,
            clearIfZero = true,
            durationTextOptions = BuildBattleResDurationTextOptions(),
        } or nil
        controller.runtimeEntries[1].presentation = BuildEntry(RUNTIME_ITEM_ID, 136080, current, cooldown).presentation
    end
end

local retryToken = 0
local function ScheduleChargeRefresh()
    retryToken = retryToken + 1
    local token = retryToken
    for _, delay in ipairs({ 0, 1, 2, 5, 10 }) do
        C_Timer.After(delay, function()
            if token == retryToken then RefreshBattleResurrection() end
        end)
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    RefreshBattleResurrection()
    ScheduleChargeRefresh()
end)
ExwindTools:RegisterEvent("ZONE_CHANGED_NEW_AREA", MODULE_KEY, function()
    RefreshBattleResurrection()
    ScheduleChargeRefresh()
end)
ExwindTools:RegisterEvent("CHALLENGE_MODE_START", MODULE_KEY, function()
    RefreshBattleResurrection()
    ScheduleChargeRefresh()
end)
ExwindTools:RegisterEvent("CHALLENGE_MODE_COMPLETED", MODULE_KEY, function()
    RefreshBattleResurrection()
    ScheduleChargeRefresh()
end)
ExwindTools:RegisterEvent("SPELL_UPDATE_CHARGES", MODULE_KEY, RefreshBattleResurrection)
ExwindTools:WatchState("IsBossEncounter", MODULE_KEY, function()
    RefreshBattleResurrection()
    ScheduleChargeRefresh()
end)
ExwindTools:WatchState("DifficultyID", MODULE_KEY, RefreshBattleResurrection)
ExwindTools:WatchState("InstanceType", MODULE_KEY, RefreshBattleResurrection)
RefreshBattleResurrection()
-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ExwindTools:ReportReady(MODULE_KEY)
