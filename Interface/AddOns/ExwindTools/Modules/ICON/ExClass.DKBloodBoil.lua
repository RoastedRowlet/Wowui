-- =============================================================
-- DK 血沸监控：保留 EXDK 的冷却更新触发语义，显示由标准 IconCollection 接管。
-- 不创建独立 Frame、SavedVariables、OnUpdate 或第二套拖拽逻辑。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local C_DurationUtil = _G.C_DurationUtil
local MODULE_KEY = "ExClass.DKBloodBoil"
local DEATH_KNIGHT_CLASS_ID = 6
local TRACKED_COOLDOWN_SPELL_ID = 1265982
local ICON_SPELL_ID = 50842
local DISPLAY_DURATION_SECONDS = 3
local RUNTIME_ITEM_ID = "dk-blood-boil:runtime"
local RefreshActiveSurfaces

-- 模块加载发生在 Tools 存储注册之后，因此可以使用现有入口登记职业分类。
-- 这不会改写冻结的 Core 静态 ModuleList。
ExwindTools:RegisterExternalModule({
    Key = MODULE_KEY,
    Name = L["DK血沸监控"],
    Desc = L["血沸冷却更新时显示 3 秒倒数图标。"],
    Category = 6,
})

local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "icon",
    version = 2,
    features = { cooldown = true, timeText = true, enabled = true },
    textSlots = { time = L["倒数文字"] },
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
    gui = {
        fields = {
            {
                group = "settings",
                h = 18,
                key = "moduleCommon",
                label = L["模块通用设置"],
                measure = true,
                options = {
                    bindRoot = true,
                    fields = { { label = L["启用"], path = "enabled", type = "checkbox" } },
                    fixedLayout = {
                        controlH = 6,
                        controlW = 46,
                        firstY = 0,
                        logicalWidth = 200,
                        rowStep = 14,
                        slotX = { 3, 53, 103, 153 },
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
                measure = true,
                order = 2,
                type = "anchorgroup",
                w = 200,
                x = 1,
                y = 32,
            },
            {
                group = "settings",
                h = 50,
                key = "icon",
                label = L["DK血沸图标"],
                labelSize = 20,
                order = 3,
                type = "icongroup",
                w = 200,
                x = 1,
                y = 55,
            },
            {
                group = "settings",
                h = 50,
                key = "font_time",
                label = L["倒数文字"],
                labelSize = 20,
                order = 4,
                type = "fontgroup",
                w = 200,
                x = 1,
                y = 108,
            },
        },
        groups = { { key = "settings", order = 1 } },
        static = {
            { h = 8, key = "header", label = L["DK血沸监控"], labelSize = 25, type = "header", w = 200, x = 1, y = 1 },
            {
                h = 8,
                key = "description",
                label = L["血沸冷却更新时显示 3 秒倒数图标。"],
                type = "description",
                w = 197,
                x = 1,
                y = 163,
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterIconModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

local runtimeDuration, displayActive, displayGeneration = nil, false, 0

local function IsEligible()
    return ExwindTools.State and ExwindTools.State.ClassID == DEATH_KNIGHT_CLASS_ID
end

local function GetTimerIcon()
    return _G.C_Spell and _G.C_Spell.GetSpellTexture and _G.C_Spell.GetSpellTexture(ICON_SPELL_ID) or 134400
end

local function ShouldShowRuntime()
    return DB.enabled == true and displayActive and IsEligible()
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

local function ClearTimer()
    displayGeneration = displayGeneration + 1
    runtimeDuration, displayActive = nil, false
    central:Clear()
end

local function PublishRuntime()
    if not ShouldShowRuntime() then
        central:Clear()
        return
    end

    central:SetRuntime({
        BuildEntry(RUNTIME_ITEM_ID, { mode = "DURATION", duration = runtimeDuration, clearIfZero = true }, false),
    }, LAYOUT)
end

local function StartTimer()
    if not IsEligible() or DB.enabled ~= true then
        ClearTimer()
        return
    end

    runtimeDuration = C_DurationUtil.CreateDuration()
    runtimeDuration:SetTimeFromStart(GetTime(), DISPLAY_DURATION_SECONDS, 1)
    displayActive = true
    displayGeneration = displayGeneration + 1
    local generation = displayGeneration
    PublishRuntime()
    C_Timer.After(DISPLAY_DURATION_SECONDS, function()
        if displayGeneration == generation then ClearTimer() end
    end)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildPreviewEntry().presentation
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and ShouldShowRuntime() then
        controller.runtimeEntries[1].presentation = BuildEntry(
            RUNTIME_ITEM_ID,
            { mode = "DURATION", duration = runtimeDuration, clearIfZero = true },
            false
        ).presentation
    end
end

ExwindTools:RegisterEvent("SPELL_UPDATE_COOLDOWN", MODULE_KEY, function(_, spellID, baseSpellID)
    if spellID == TRACKED_COOLDOWN_SPELL_ID or baseSpellID == TRACKED_COOLDOWN_SPELL_ID then
        StartTimer()
    end
end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, ClearTimer)
ExwindTools:WatchState("ClassID", MODULE_KEY, function()
    if not IsEligible() then ClearTimer() end
end)
ExwindTools:ReportReady(MODULE_KEY)
