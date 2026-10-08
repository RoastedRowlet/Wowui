-- =============================================================
-- DK 血沸监控：保留 EXDK 的冷却更新触发语义，显示由标准 IconCollection 接管。
-- 不创建独立 Frame、SavedVariables、OnUpdate 或第二套拖拽逻辑。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExClass.DKBloodBoilSmart"
local DEATH_KNIGHT_CLASS_ID = 6
local HIGHLIGHT_SPELL_ID = 1265968
local USE_SPELL_ID = 1265982
local ICON_SPELL_ID = 50842
local USE_LOCKOUT_SECONDS = 3
local HIGHLIGHT_TIMEOUT_SECONDS = 15
local SHOW_CONFIRM_SECONDS = .1
local RUNTIME_ITEM_ID = "dk-blood-boil-smart:runtime"
local RefreshActiveSurfaces

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 2,
    features = { cooldown = true, timeText = true, enabled = true },
    textSlots = { time = L["倒数文字"] },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    anchor = {
        dbPath = "$root",
        bindRoot = true,
        xKey = "x",
        yKey = "y",
        defaultX = 4,
        defaultY = -49,
        initialWidth = 45,
        initialHeight = 45,
        clampedToScreen = true,
    },
    -- =========================================================
    -- 二、默认配置与配置访问 | Defaults and Configuration Access
    -- =========================================================
    defaults = {
        font_time = {
            a = 1,
            autoWidth = false,
            b = 0,
            enabled = true,
            fixedWidth = 200,
            font = "默认",
            g = 0.88235300779343,
            gradientEnabled = false,
            gradientLength = 0,
            gradientStart = 0,
            justifyH = "CENTER",
            justifyV = "MIDDLE",
            maxWidth = 0,
            outline = "THINOUTLINE",
            r = 1,
            rotation = 0,
            shadow = true,
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
            blendMode = "BLEND",
            borderColorA = 1,
            borderColorB = 0,
            borderColorG = 0,
            borderColorR = 0,
            borderPadding = 0.19999980926514,
            borderSize = 0.10000038146973,
            borderTexture = "EX_Default",
            colorA = 1,
            colorB = 1,
            colorG = 1,
            colorR = 1,
            cooldown = {
                edgeAlpha = 0,
                showBling = false,
                showEdge = true,
                showSwipe = true,
                swipeAlpha = 0.65,
            },
            cropBottom = 0.92,
            cropLeft = 0.08,
            cropRight = 0.92,
            cropTop = 0.08,
            desaturated = false,
            enableCrop = true,
            height = 45,
            reverse = true,
            rotation = 0,
            showBorder = true,
            showCooldown = true,
            showIcon = true,
            width = 45,
        },
        root = {
            enabled = true,
            layout = {
                direction = "RIGHT",
                maxVisible = 1,
                spacing = 0,
            },
            x = 4,
            y = -49,
        },
    },
    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    preview = {
        positionGuiKeys = { "font_time" },
        elements = {
            ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["DK血沸图标"] },
            ["core.time"] = {
                guiKey = "font_time",
                movable = true,
                textRole = "time",
                tooltip = L["倒数文字"],
                position = { x = "font_time.x", y = "font_time.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
        },
        sample = { itemID = "dk-blood-boil:preview", remaining = 3, duration = 3 },
    },
    -- [卡片迁移边界：设置页] 仅可按统一规范调整下列 gui.static/gui.fields 的 x/y/w/h 与卡片分组。
    -- key/type/opts、DB path、anchor/preview/defaults 及刷新回调均属绑定或业务合同，禁止修改；复合控件必须整体引用，header 本身不等于卡片容器。
    -- =========================================================
    -- 三、GUI 声明 | GUI Declarations
    -- =========================================================
    gui = {
        version = 1,
        description = L["仅在需要手动施放高亮血沸时显示图标。"],
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
                kind = "composite",
                id = "anchor",
                title = L["锚点设置"],
                component = "anchorgroup",
                key = "anchor",
            },
            {
                kind = "composite",
                id = "icon",
                title = L["DK血沸图标"],
                component = "icongroup",
                key = "icon",
            },
            {
                kind = "composite",
                id = "font_time",
                title = L["倒数文字"],
                component = "fontgroup",
                key = "font_time",
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

-- 1265968 开启高亮资格；1265982 取消资格并启动 3 秒抑制。
-- useGeneration 保证连续使用时，只有最后一次使用对应的延迟回调可以解除抑制。
-- showGeneration 保证短暂满足条件的旧显示确认不会在稍后错误显示图标。
-- highlightGeneration 保证资格开启 15 秒内没有被使用时自动取消显示，只有当次资格对应的超时回调能生效。
-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local highlightActive, useLockoutActive, displayActive = false, false, false
local useGeneration, showGeneration, highlightGeneration = 0, 0, 0

local function IsEligible()
    return ExwindTools.State and ExwindTools.State.ClassID == DEATH_KNIGHT_CLASS_ID
end

local function GetTimerIcon()
    return _G.C_Spell and _G.C_Spell.GetSpellTexture and _G.C_Spell.GetSpellTexture(ICON_SPELL_ID) or 134400
end

local function IsRuntimeQualified()
    return DB.enabled == true and highlightActive and not useLockoutActive and IsEligible()
end

local function ShouldShowRuntime()
    return displayActive and IsRuntimeQualified()
end

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

-- 与噬灭变身计时保持同一份标准 Icon presentation 结构；只替换业务数据。
-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function BuildEntry(itemID, cooldown, isPreview)
    local icon = DB.icon or {}
    local width = math.max(1, tonumber(icon.width) or 45)
    local height = math.max(1, tonumber(icon.height) or 45)
    return {
        itemID = itemID,
        presentation = {
            style = { icon = icon, text = { countdown = DB.font_time or {} } },
            icon = { value = GetTimerIcon() },
            cooldown = cooldown,
            bodySize = { width = width, height = height },
            declaredBounds = { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 },
            semanticBounds = { ["core.time"] = MakeTextBounds(DB.font_time or {}) },
            interaction = isPreview and EXUI:BuildStandardPreviewInteraction("Icon", DB, MODULE_SPEC.preview.elements) or nil,
        },
    }
end

local function BuildPreviewEntry()
    local sample = MODULE_SPEC.preview.sample
    return BuildEntry(sample.itemID, { static = true, remaining = sample.remaining, duration = sample.duration }, true)
end

local function RefreshPreview()
    central:SetPreview({ BuildPreviewEntry() }, LAYOUT)
end

RefreshPreview()

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function ClearRuntimeState()
    useGeneration, showGeneration = useGeneration + 1, showGeneration + 1
    highlightGeneration = highlightGeneration + 1
    highlightActive, useLockoutActive, displayActive = false, false, false
    central:Clear()
end

local function PublishRuntime()
    if not ShouldShowRuntime() then
        central:Clear()
        return
    end

    central:SetRuntime({
        BuildEntry(RUNTIME_ITEM_ID, nil, false),
    }, LAYOUT)
end

local function ReconcileRuntime()
    showGeneration = showGeneration + 1
    if not IsRuntimeQualified() then
        displayActive = false
        central:Clear()
        return
    end

    if displayActive then return end

    local generation = showGeneration
    C_Timer.After(SHOW_CONFIRM_SECONDS, function()
        if showGeneration ~= generation or not IsRuntimeQualified() then return end
        displayActive = true
        PublishRuntime()
    end)
end

local function SetHighlightActive()
    if not IsEligible() or DB.enabled ~= true then
        ClearRuntimeState()
        return
    end

    if highlightActive then return end

    highlightActive = true
    highlightGeneration = highlightGeneration + 1
    local generation = highlightGeneration
    ReconcileRuntime()
    C_Timer.After(HIGHLIGHT_TIMEOUT_SECONDS, function()
        if highlightGeneration ~= generation or not highlightActive then return end
        highlightActive = false
        ReconcileRuntime()
    end)
end

local function StartUseLockout()
    if not IsEligible() or DB.enabled ~= true then
        ClearRuntimeState()
        return
    end

    highlightActive = false
    highlightGeneration = highlightGeneration + 1
    useLockoutActive = true
    useGeneration = useGeneration + 1
    local generation = useGeneration
    ReconcileRuntime()
    C_Timer.After(USE_LOCKOUT_SECONDS, function()
        if useGeneration == generation then
            useLockoutActive = false
            ReconcileRuntime()
        end
    end)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildPreviewEntry().presentation
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and ShouldShowRuntime() then
        controller.runtimeEntries[1].presentation = BuildEntry(
            RUNTIME_ITEM_ID,
            nil,
            false
        ).presentation
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("SPELL_UPDATE_COOLDOWN", MODULE_KEY, function(_, spellID, baseSpellID)
    if spellID == HIGHLIGHT_SPELL_ID or baseSpellID == HIGHLIGHT_SPELL_ID then
        SetHighlightActive()
    elseif spellID == USE_SPELL_ID or baseSpellID == USE_SPELL_ID then
        StartUseLockout()
    end
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, ClearRuntimeState)
ExwindTools:WatchState("ClassID", MODULE_KEY, function()
    if not IsEligible() then ClearRuntimeState() end
end)
-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ExwindTools:ReportReady(MODULE_KEY)
