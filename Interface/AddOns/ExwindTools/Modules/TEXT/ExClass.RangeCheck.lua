-- 距离监视：模块只声明唯一 DB / GUI / Text presentation，并提交中央 Text owner。
-- Anchor、Runtime、World、Panel、EditMode 与输入事务全部由中央持有。

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local MODULE_KEY = "ExClass.RangeCheck"
local LRC = LibStub("LibRangeCheck-3.0", true)
local SAMPLE_RANGE = { min = 15, max = 20 }
local TEXT_BOUNDS_WIDTH = 240
local RefreshActiveSurfaces

local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "text",
    version = 1,
    anchor = {
        dbPath = "$root", bindRoot = true,
        xKey = "xOffset", yKey = "yOffset", defaultX = 0, defaultY = -85,
        attachEnabledKey = "attachToCustom", attachTargetKey = "customAttachTarget",
        initialWidth = 240, initialHeight = 48, clampedToScreen = false,
    },
    preview = {
        positionGuiKeys = { "font_text" },
        elements = {
            ["rangecheck.body"] = {
                guiKey = "font_text", movable = true, tooltip = L["距离监视"],
                position = { x = "font_text.x", y = "font_text.y" },
                anchor = { point = "CENTER", relativePoint = "CENTER" },
            },
        },
    },
    defaults = {
        root = {
            enabled = true, showText = true, frameScale = 1.0, hideThreshold = 60,
            xOffset = 0, yOffset = -85, attachToCustom = false, customAttachTarget = "",
            rangeFormat = "", minOnlyFormat = "",
            layout = { direction = "DOWN", spacing = 0, maxVisible = 1 },
            crColorR = 0.9, crColorG = 0.9, crColorB = 0.9,
            srColorR = 0.063, srColorG = 1, srColorB = 0.941,
            s10ColorR = 0.063, s10ColorG = 1, s10ColorB = 0.941,
            s15ColorR = 0.063, s15ColorG = 1, s15ColorB = 0.941,
            mrColorR = 0.039, mrColorG = 1, mrColorB = 0,
            lrColorR = 1, lrColorG = 1, lrColorB = 0,
            oorColorR = 1, oorColorG = 0, oorColorB = 0,
        },
        font_text = {
            font = "默认", size = 18, r = 1, g = 1, b = 1, a = 1,
            outline = "OUTLINE", shadow = true, shadowX = 1, shadowY = -1,
            justifyH = "CENTER", justifyV = "MIDDLE", x = 0, y = 0,
        },
    },
    gui = {
        static = {
            { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["距离监视"], labelSize = 25 },
            { key = "desc", type = "description", x = 1, y = 7, w = 200, h = 8, label = L["实时显示目标距离范围，根据与目标的最小距离自动变色。"] },
            { key = "sub_general", type = "subheader", x = 1, y = 15, w = 200, h = 8, label = L["基础设置"], labelSize = 20 },
            { key = "desc_format", type = "description", x = 1, y = 137, w = 200, h = 6, label = L["范围格式需要两个 %d (最小/最大，如%d - %d)，仅最小值格式需要一个 %d+。留空使用默认格式。"] },
            { key = "sub_colors", type = "subheader", x = 1, y = 144, w = 200, h = 8, label = L["距离颜色设置"], labelSize = 20 },
        },
        fields = {
            { key = "enabled", type = "checkbox", x = 1, y = 24, w = 46, h = 6, label = L["启用"] },
            { key = "showText", type = "checkbox", x = 51, y = 24, w = 46, h = 6, label = L["显示距离范围"] },
            { key = "frameScale", type = "slider", x = 1, y = 37, w = 46, h = 6, label = L["缩放"], min = 0.5, max = 3, labelPos = "top" },
            { key = "hideThreshold", type = "slider", x = 51, y = 37, w = 46, h = 6, label = L["隐藏距离阈值"], min = 5, max = 100, labelPos = "top" },
            { key = "anchorGroup", type = "anchorgroup", x = 1, y = 47, w = 200, h = 18, label = L["锚点设置"] },
            { key = "font_text", type = "fontgroup", x = 1, y = 68, w = 200, h = 50, label = L["距离文本"], labelSize = 20 },
            { key = "rangeFormat", type = "input", x = 1, y = 127, w = 46, h = 6, label = L["范围格式"], labelPos = "top" },
            { key = "minOnlyFormat", type = "input", x = 51, y = 127, w = 46, h = 6, label = L["仅最小值格式"], labelPos = "top" },
            { key = "crColor", type = "color", x = 1, y = 157, w = 46, h = 6, label = L["< 5 码"] },
            { key = "srColor", type = "color", x = 51, y = 157, w = 46, h = 6, label = L[">= 5 码"] },
            { key = "s10Color", type = "color", x = 101, y = 157, w = 46, h = 6, label = L[">= 10 码"] },
            { key = "s15Color", type = "color", x = 151, y = 157, w = 46, h = 6, label = L[">= 15 码"] },
            { key = "mrColor", type = "color", x = 1, y = 168, w = 46, h = 6, label = L[">= 20 码"] },
            { key = "lrColor", type = "color", x = 51, y = 168, w = 46, h = 6, label = L[">= 30 码"] },
            { key = "oorColor", type = "color", x = 101, y = 168, w = 46, h = 6, label = L[">= 40 码"] },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterTextModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end
if not LRC then
    print(string.format("|cffff0000[%s]|r %s", L["距离监控"], L["LibRangeCheck-3.0 未找到，模块无法工作。"]))
    return
end

local function Num(value, fallback) value = tonumber(value); return value or fallback end

local function GetRangeColor(minRange)
    local db = DB
    if not minRange then return Num(db.crColorR, .9), Num(db.crColorG, .9), Num(db.crColorB, .9) end
    if minRange >= 40 then return Num(db.oorColorR, 1), Num(db.oorColorG, 0), Num(db.oorColorB, 0) end
    if minRange >= 30 then return Num(db.lrColorR, 1), Num(db.lrColorG, 1), Num(db.lrColorB, 0) end
    if minRange >= 20 then return Num(db.mrColorR, .039), Num(db.mrColorG, 1), Num(db.mrColorB, 0) end
    if minRange >= 15 then return Num(db.s15ColorR, .063), Num(db.s15ColorG, 1), Num(db.s15ColorB, .941) end
    if minRange >= 10 then return Num(db.s10ColorR, .063), Num(db.s10ColorG, 1), Num(db.s10ColorB, .941) end
    if minRange >= 5 then return Num(db.srColorR, .063), Num(db.srColorG, 1), Num(db.srColorB, .941) end
    return Num(db.crColorR, .9), Num(db.crColorG, .9), Num(db.crColorB, .9)
end

local function FormatRangeText(minRange, maxRange)
    if not minRange then return "" end
    local db = DB
    if not maxRange then return string.format((db.minOnlyFormat ~= "" and db.minOnlyFormat) or "%d+", minRange) end
    return string.format((db.rangeFormat ~= "" and db.rangeFormat) or "%d - %d", minRange, maxRange)
end

local function GetFrameScale() return math.max(.5, math.min(3, Num(DB.frameScale, 1))) end

-- The direct DB style is deliberately never copied or rewritten. x/y are
-- consumed exactly once by presentation.anchor; TextCollection suppresses only
-- the second style-position application.
local function BuildPresentation(minRange, maxRange, sample)
    local db = DB
    local shown = sample == true or (db.enabled ~= false and db.showText ~= false and minRange ~= nil)
    local r, g, b = GetRangeColor(minRange)
    local style = db.font_text
    local textX = Num(style and style.x, 0)
    local textY = Num(style and style.y, 0)
    local height = math.max(24, Num(style and style.size, 18) * 1.5)
    return {
        shown = shown, text = shown and FormatRangeText(minRange, maxRange) or "",
        color = { r = r, g = g, b = b, a = 1 }, style = style,
        presentationScale = GetFrameScale(), presentationScalePath = "frameScale",
        declaredBounds = { left = -TEXT_BOUNDS_WIDTH * .5, right = TEXT_BOUNDS_WIDTH * .5, bottom = -height * .5, top = height * .5 },
        anchor = { point = "CENTER", relativePoint = "CENTER", x = textX, y = textY },
        semanticSlot = "rangecheck.body",
        interaction = EXUI:BuildStandardPreviewInteraction("Text", db, MODULE_SPEC.preview.elements),
    }
end

local function BuildEntry(itemID, minRange, maxRange, sample)
    return { itemID = itemID, presentation = BuildPresentation(minRange, maxRange, sample) }
end

local function PublishPreview()
    central:SetPreview({ BuildEntry("rangecheck:sample", SAMPLE_RANGE.min, SAMPLE_RANGE.max, true) }, LAYOUT)
end

local function PublishRuntime()
    local db = DB
    if db.enabled == false or db.showText == false or not UnitExists("target") then central:Clear(); return end
    local minRange, maxRange = LRC:GetRange("target")
    if Num(db.hideThreshold, 60) < 100 and minRange and minRange > Num(db.hideThreshold, 60) then central:Clear(); return end
    if minRange == nil then central:Clear(); return end
    central:SetRuntime({ BuildEntry("rangecheck:runtime", minRange, maxRange, false) }, LAYOUT)
end

local function RefreshPresentations()
    PublishPreview()
    PublishRuntime()
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildEntry("rangecheck:sample", SAMPLE_RANGE.min, SAMPLE_RANGE.max, true).presentation
    end
    if not (controller.runtimeEntries and controller.runtimeEntries[1]) then return end
    if DB.enabled == false or DB.showText == false or not UnitExists("target") then return end
    local minRange, maxRange = LRC:GetRange("target")
    if minRange == nil or (Num(DB.hideThreshold, 60) < 100 and minRange > Num(DB.hideThreshold, 60)) then return end
    controller.runtimeEntries[1].presentation = BuildEntry("rangecheck:runtime", minRange, maxRange, false).presentation
end

local updater = CreateFrame("Frame", nil, UIParent)
updater:Hide()
local elapsedSinceUpdate = 0
updater:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= 0.3 then elapsedSinceUpdate = 0; PublishRuntime() end
end)

ExwindTools:RegisterEvent("PLAYER_TARGET_CHANGED", MODULE_KEY, PublishRuntime)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    C_Timer.After(0.5, function() RefreshPresentations(); updater:Show() end)
end)

PublishPreview()
C_Timer.After(1, function() RefreshPresentations(); updater:Show() end)
ExwindTools:ReportReady(MODULE_KEY)
