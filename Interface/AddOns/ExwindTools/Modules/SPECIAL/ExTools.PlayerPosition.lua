-- =============================================================
-- [[ 玩家角色定位标记 ]]
-- EXUI 唯一 IconCollection Renderer：运行、世界编辑、设置页预览共用。
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExTools.PlayerPosition"

local VIS_SHOW_IN_COMBAT = "show_in_combat"
local VIS_SHOW_OUT_OF_COMBAT = "show_out_of_combat"
local VIS_ONLY_IN_INSTANCE = "only_in_instance"

local VISIBILITY_OPTIONS = {
    { L["战斗中显示"], VIS_SHOW_IN_COMBAT },
    { L["战斗外显示"], VIS_SHOW_OUT_OF_COMBAT },
    { L["仅副本内"], VIS_ONLY_IN_INSTANCE },
}

local SPEC_OPTION_DEFS = {
    { specID = 71, className = "战士", specName = "武器", colorHex = "C79C6E" },
    { specID = 72, className = "战士", specName = "狂怒", colorHex = "C79C6E" },
    { specID = 73, className = "战士", specName = "防护", colorHex = "C79C6E" },
    { specID = 65, className = "圣骑士", specName = "神圣", colorHex = "F48CBA" },
    { specID = 66, className = "圣骑士", specName = "防护", colorHex = "F48CBA" },
    { specID = 70, className = "圣骑士", specName = "惩戒", colorHex = "F48CBA" },
    { specID = 253, className = "猎人", specName = "野兽控制", colorHex = "ABD473" },
    { specID = 254, className = "猎人", specName = "射击", colorHex = "ABD473" },
    { specID = 255, className = "猎人", specName = "生存", colorHex = "ABD473" },
    { specID = 259, className = "潜行者", specName = "奇袭", colorHex = "FFF468" },
    { specID = 260, className = "潜行者", specName = "狂徒", colorHex = "FFF468" },
    { specID = 261, className = "潜行者", specName = "敏锐", colorHex = "FFF468" },
    { specID = 256, className = "牧师", specName = "戒律", colorHex = "FFFFFF" },
    { specID = 257, className = "牧师", specName = "神圣", colorHex = "FFFFFF" },
    { specID = 258, className = "牧师", specName = "暗影", colorHex = "FFFFFF" },
    { specID = 250, className = "死亡骑士", specName = "鲜血", colorHex = "C41E3A" },
    { specID = 251, className = "死亡骑士", specName = "冰霜", colorHex = "C41E3A" },
    { specID = 252, className = "死亡骑士", specName = "邪恶", colorHex = "C41E3A" },
    { specID = 262, className = "萨满祭司", specName = "元素", colorHex = "0070DD" },
    { specID = 263, className = "萨满祭司", specName = "增强", colorHex = "0070DD" },
    { specID = 264, className = "萨满祭司", specName = "恢复", colorHex = "0070DD" },
    { specID = 62, className = "法师", specName = "奥术", colorHex = "3FC7EB" },
    { specID = 63, className = "法师", specName = "火焰", colorHex = "3FC7EB" },
    { specID = 64, className = "法师", specName = "冰霜", colorHex = "3FC7EB" },
    { specID = 265, className = "术士", specName = "痛苦", colorHex = "8788EE" },
    { specID = 266, className = "术士", specName = "恶魔学识", colorHex = "8788EE" },
    { specID = 267, className = "术士", specName = "毁灭", colorHex = "8788EE" },
    { specID = 268, className = "武僧", specName = "酒仙", colorHex = "00FF98" },
    { specID = 269, className = "武僧", specName = "踏风", colorHex = "00FF98" },
    { specID = 270, className = "武僧", specName = "织雾", colorHex = "00FF98" },
    { specID = 102, className = "德鲁伊", specName = "平衡", colorHex = "FF7C0A" },
    { specID = 103, className = "德鲁伊", specName = "野性", colorHex = "FF7C0A" },
    { specID = 104, className = "德鲁伊", specName = "守护", colorHex = "FF7C0A" },
    { specID = 105, className = "德鲁伊", specName = "恢复", colorHex = "FF7C0A" },
    { specID = 577, className = "恶魔猎手", specName = "浩劫", colorHex = "A330C9" },
    { specID = 581, className = "恶魔猎手", specName = "复仇", colorHex = "A330C9" },
    { specID = 1467, className = "唤魔师", specName = "湮灭", colorHex = "33937F" },
    { specID = 1468, className = "唤魔师", specName = "恩护", colorHex = "33937F" },
    { specID = 1473, className = "唤魔师", specName = "增辉", colorHex = "33937F" },
    { specID = 1480, className = "恶魔猎手", specName = "噬灭", colorHex = "A330C9" },
}

local EnsureAnchorController
local PLAYER_POSITION_DEFAULT_OFFSET_X = 0
local PLAYER_POSITION_DEFAULT_OFFSET_Y = 0

-- 锚点组是页面对唯一 AnchorController 的正式入口：位置仍只写 root ModuleDB
-- 的 offsetX/offsetY，依附状态也只写同一个 root，不能再以散装 Slider 伪造。
local function PickPlayerPositionAnchor()
    if type(EnsureAnchorController) ~= "function" then return false end
    local controller = EnsureAnchorController()
    if controller and type(controller.StartFramePicker) == "function" then
        return controller:StartFramePicker()
    end
    return false
end

local PLAYER_POSITION_ANCHOR_OPTS = {
    bindRoot = true,
    offsetXKey = "offsetX",
    offsetYKey = "offsetY",
    defaultOffsetX = PLAYER_POSITION_DEFAULT_OFFSET_X,
    defaultOffsetY = PLAYER_POSITION_DEFAULT_OFFSET_Y,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    onPickFrame = PickPlayerPositionAnchor,
}

-- 距离判定仍是本模块既有业务字段；这里只声明它们应由哪一个标准通用卡承载。
-- 图标的所有视觉尺寸、颜色、裁切、边框等只由后面的 icongroup 写入 DB.icon。
local COMMON_FIELDS = {
    { path = "enabled", type = "checkbox", label = L["启用指示器"], row = 1 },
    { path = "shapeType", type = "dropdown", label = L["图形样式"], row = 1,
        items = { { L["方块 (Square)"], "SQUARE" }, { L["十字 (Cross)"], "CROSS" },
            { L["圆形 (Circle)"], "CIRCLE" }, { L["圆环 (Ring)"], "RING" }, { L["菱形 (Diamond)"], "DIAMOND" } } },
    { path = "rangeSpell", type = "input", label = L["距离判定法术(ID)"], row = 2 },
    { path = "rangeColor", type = "color", label = L["超距颜色"], row = 2 },
}

local COMMON_OPTS = {
    bindRoot = true,
    fixedLayout = {
        logicalWidth = 200,
        controlW = 46,
        controlH = 6,
        slotX = { 3, 53, 103, 153 },
        firstY = 0,
        rowStep = 14,
    },
    fields = COMMON_FIELDS,
}

local function GetSpecOptionValue(specID)
    return tostring(specID)
end

local function BuildSpecOptionLabel(def)
    return string.format("|cff%s%s|r - %s", def.colorHex, L[def.className] or def.className,
        L[def.specName] or def.specName)
end

local function BuildSpecOptions()
    local options = {}

    for _, def in ipairs(SPEC_OPTION_DEFS) do
        local value = GetSpecOptionValue(def.specID)
        options[#options + 1] = { BuildSpecOptionLabel(def), value }
    end

    return options
end

local SPEC_OPTIONS = BuildSpecOptions()

local function BuildDefaultVisibility()
    return {
        [VIS_SHOW_IN_COMBAT] = true,
        [VIS_SHOW_OUT_OF_COMBAT] = true,
        [VIS_ONLY_IN_INSTANCE] = true,
    }
end

local function BuildDefaultEnabledSpecs()
    local enabledSpecs = {}
    for _, def in ipairs(SPEC_OPTION_DEFS) do
        enabledSpecs[GetSpecOptionValue(def.specID)] = true
    end
    return enabledSpecs
end

local function NormalizeVisibilityConfig(source)
    local result = BuildDefaultVisibility()
    if type(source) ~= "table" then
        return result
    end

    for key in pairs(result) do
        if source[key] ~= nil then result[key] = source[key] == true end
    end

    return result
end

local function NormalizeEnabledSpecsConfig(source)
    local result = BuildDefaultEnabledSpecs()
    if type(source) ~= "table" then
        return result
    end

    for key in pairs(result) do
        if source[key] ~= nil then result[key] = source[key] == true end
    end

    return result
end

-- =============================================================
-- 01. 页面：通用设置 → 整体锚点 → 图标本体 → 既有业务筛选
-- =============================================================
local function EX_RegisterLayout()
    local layout = {
        { key = "head", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["玩家角色定位标记"], labelSize = 25 },
        { key = "moduleCommon", type = "modulecommonsettings", x = 1, y = 10, w = 200, h = 42, measure = true,
            label = L["模块通用设置"], opts = COMMON_OPTS },
        { key = "anchorGroup", type = "anchorgroup", x = 1, y = 55, w = 200, h = 25, measure = true,
            label = L["锚点设置"], opts = PLAYER_POSITION_ANCHOR_OPTS },
        { key = "icon", type = "icongroup", x = 1, y = 83, w = 200, h = 50, label = L["图标外观"], labelSize = 20,
            opts = {} },
        { key = "h_visibility", type = "subheader", x = 1, y = 136, w = 200, h = 6, label = L["显示场景"], labelSize = 20 },
        { key = "visibility", type = "multiselect", x = 1, y = 146, w = 96, h = 8, label = L["触发场景"], items = VISIBILITY_OPTIONS },
        { key = "enabledSpecs", type = "multiselect", x = 101, y = 146, w = 96, h = 8, label = L["启用专精"], items = SPEC_OPTIONS },
    }

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end
EX_RegisterLayout()

if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- =============================================================
-- 02. 唯一默认声明与 ModuleDB
-- =============================================================
local EX_DEFAULTS = {
    root = {
        enabled = false,
        shapeType = "CROSS",
        offsetX = PLAYER_POSITION_DEFAULT_OFFSET_X,
        offsetY = PLAYER_POSITION_DEFAULT_OFFSET_Y,
        attachToCustom = false,
        customAttachTarget = "",
        rangeSpell = "",
        rangeColorR = 1,
        rangeColorG = 0,
        rangeColorB = 0,
        rangeColorA = 1,
        visibility = BuildDefaultVisibility(),
        enabledSpecs = BuildDefaultEnabledSpecs(),
    },
    icon = {
        showIcon = true, iconID = nil, reverse = false, width = 32, height = 32, x = 0, y = 0,
        showCooldown = false, showBorder = false, enableCrop = false, alpha = 1,
        colorR = 0.15, colorG = 1, colorB = 0.25, colorA = 1,
        blendMode = "BLEND", rotation = 0, desaturated = false,
        cropLeft = 0, cropRight = 1, cropTop = 0, cropBottom = 1,
        borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1,
        borderTexture = "EX_Default", borderSize = 0, borderPadding = 0.6,
        cooldown = { showSwipe = false, swipeAlpha = .65, showEdge = false, edgeAlpha = 1, showBling = false },
    },
}
local ROOT_FIELDS = {
    "enabled", "shapeType", "offsetX", "offsetY", "attachToCustom", "customAttachTarget", "rangeSpell",
    "rangeColorR", "rangeColorG", "rangeColorB", "rangeColorA", "visibility", "enabledSpecs",
}
local DEFAULT_SCHEMA = {
    { group = "root", root = true, fields = ROOT_FIELDS },
    { group = "icon", fields = {
        "showIcon", "iconID", "reverse", "width", "height", "x", "y", "showCooldown", "showBorder", "enableCrop",
        "alpha", "colorR", "colorG", "colorB", "colorA", "blendMode", "rotation", "desaturated",
        "cropLeft", "cropRight", "cropTop", "cropBottom", "borderColorR", "borderColorG", "borderColorB", "borderColorA",
        "borderTexture", "borderSize", "borderPadding", cooldown = { "showSwipe", "swipeAlpha", "showEdge", "edgeAlpha", "showBling" },
    } },
}
ExwindTools:DeclareModuleDefaults(EXWIND_MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY)
EX_DB.visibility = NormalizeVisibilityConfig(EX_DB.visibility)
EX_DB.enabledSpecs = NormalizeEnabledSpecsConfig(EX_DB.enabledSpecs)

-- =============================================================
-- 03. 既有业务 State：距离、显示场景与专精筛选（不得在此区创建视觉树）
-- =============================================================

local TEXTURE_PATHS = {
    SQUARE = "Interface\\AddOns\\ExwindTools\\Textures\\PlayerPosition\\Square.png",
    CROSS = "Interface\\AddOns\\ExwindTools\\Textures\\PlayerPosition\\Cross.png",
    CIRCLE = "Interface\\AddOns\\ExwindTools\\Textures\\PlayerPosition\\Circle.png",
    RING = "Interface\\AddOns\\ExwindTools\\Textures\\PlayerPosition\\Ring.png",
    DIAMOND = "Interface\\AddOns\\ExwindTools\\Textures\\PlayerPosition\\Diamond.png",
}
local anchorFrame, anchorController, runtimeCollection, worldCollection, panelPreview, panelDock
local worldPreviewActive = false
local updater, updateElapsed = CreateFrame("Frame", nil, UIParent), 0

local function DB() return EX_DB end
local function Num(value, fallback)
    value = tonumber(value); return value or fallback
end

local function GetRangeSpell()
    local userSpell = DB().rangeSpell
    if userSpell and userSpell ~= "" then return tonumber(userSpell) or userSpell end
    local state, staticDB = ExwindTools.State, ExwindTools.DB_Static
    local specID = state and state.SpecID
    local spec = specID and staticDB and staticDB.SpecByID and staticDB.SpecByID[specID]
    return spec and spec.RangeSpell or nil
end

local function IsRuntimeVisible()
    local db, state = DB(), ExwindTools.State or {}
    if db.enabled ~= true then return false end
    if db.visibility[VIS_ONLY_IN_INSTANCE] and not state.InInstance then return false end
    local specID = tonumber(state.SpecID) or 0
    local specKey = specID > 0 and GetSpecOptionValue(specID) or nil
    if specKey and db.enabledSpecs[specKey] == false then return false end
    return state.InCombat and db.visibility[VIS_SHOW_IN_COMBAT] == true or db.visibility[VIS_SHOW_OUT_OF_COMBAT] == true
end

local function ResolveColor()
    local db = DB()
    local icon = db.icon or EX_DEFAULTS.icon
    local r, g, b, a = Num(icon.colorR, 1), Num(icon.colorG, 1), Num(icon.colorB, 1), Num(icon.colorA, 1)
    local spell = GetRangeSpell()
    if spell and UnitExists("target") and C_Spell.IsSpellInRange(spell, "target") == false then
        r, g, b, a = Num(db.rangeColorR, 1), Num(db.rangeColorG, 0), Num(db.rangeColorB, 0), Num(db.rangeColorA, 1)
    end
    return r, g, b, a
end

-- =============================================================
-- 04. 唯一 IconCollection Presentation 与三宿主 Renderer
-- =============================================================
local SINGLE_ICON_LAYOUT = { mode = "FLOW", direction = "RIGHT", spacing = 0, maxVisible = 1 }
local RUNTIME_ITEM_ID, WORLD_ITEM_ID, PANEL_ITEM_ID = "playerposition:runtime", "playerposition:world", "playerposition:panel"

local function CopyIconStyle(texture, r, g, b, a)
    local source = DB().icon or EX_DEFAULTS.icon
    local style = {}
    for key, value in pairs(source) do
        if key == "cooldown" and type(value) == "table" then
            style.cooldown = {}
            for cooldownKey, cooldownValue in pairs(value) do style.cooldown[cooldownKey] = cooldownValue end
        else
            style[key] = value
        end
    end
    style.width = math.max(6, Num(style.width, 32))
    style.height = math.max(6, Num(style.height, 32))
    style.iconID = texture
    style.colorR, style.colorG, style.colorB, style.colorA = r, g, b, a
    return style
end

-- Runtime、world-edit、panel 的 Item 都从这个唯一函数取得 presentation。
-- sample 只决定是否采用静态颜色和强制显示，不会创建另一套预览外观。
local function BuildPresentation(sample, interactive)
    local db = DB()
    local icon = db.icon or EX_DEFAULTS.icon
    local r, g, b, a
    if sample then
        -- panel/world 只取静态 DB 样本，不调用目标距离或实时状态查询。
        r, g, b, a = Num(icon.colorR, 1), Num(icon.colorG, 1), Num(icon.colorB, 1), Num(icon.colorA, 1)
    else
        r, g, b, a = ResolveColor()
    end
    -- 未填自定义图标时保持既有形状选择；IconGroup 填入图标 ID 后则由该正式
    -- 外观字段覆盖，三宿主仍消费同一个 texture。
    local texture = icon.iconID or TEXTURE_PATHS[tostring(db.shapeType or "CROSS"):upper()] or TEXTURE_PATHS.CROSS
    local style = CopyIconStyle(texture, r, g, b, a)
    local presentation = {
        shown = sample == true or IsRuntimeVisible(),
        style = { icon = style },
        icon = texture,
        bodySize = { width = style.width, height = style.height },
        declaredBounds = { left = -style.width * .5, right = style.width * .5, bottom = -style.height * .5, top = style.height * .5 },
    }
    if interactive then
        presentation.interaction = {
            slots = {
                ["core.icon"] = { movable = false, guiTarget = "icon", tooltip = L["玩家角色定位标记"] },
            },
        }
    end
    return presentation
end

local function RenderCollection(collection, itemID, sample, interactive)
    local presentation = BuildPresentation(sample, interactive)
    if not sample and not presentation.shown then
        collection:SetItems({}, SINGLE_ICON_LAYOUT)
        return false
    end
    local item = collection:AcquireItem(itemID)
    collection:ApplyItem(item, presentation)
    collection:SetItems({ item }, SINGLE_ICON_LAYOUT)
    return true
end

local function ApplyPreviewDockColor()
    if panelDock and type(panelDock.SetBackdropColor) == "function" then
        panelDock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1)
    end
end

local function RenderPanelSample()
    if not panelPreview then return end
    ApplyPreviewDockColor()
    panelPreview:Render({ { itemID = PANEL_ITEM_ID, presentation = BuildPresentation(true, true) } }, SINGLE_ICON_LAYOUT)
    if panelDock then
        local _, height = panelPreview:GetBounds()
        panelDock:SetHeight(math.max(160, (height or 0) + 28))
    end
end

local function SyncRuntimeAnchorBounds()
    if not anchorFrame or not runtimeCollection then return end
    local width, height = runtimeCollection:GetBounds()
    anchorFrame:SetSize(math.max(1, width or 1), math.max(1, height or 1))
end

-- =============================================================
-- 05. 整体 Anchor、World 编辑与 Panel 生命周期
-- =============================================================

EnsureAnchorController = function()
    if anchorController then return anchorController end
    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExwindPlayerPositionAnchor",
        title = L["玩家角色定位标记"],
        getDB = DB,
        offsetXKey = "offsetX",
        offsetYKey = "offsetY",
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        syncWidgets = { "offsetX", "offsetY", "attachToCustom", "customAttachTarget" },
        widgetRanges = { offsetX = { min = -500, max = 500, step = 1 }, offsetY = { min = -500, max = 500, step = 1 } },
        initialWidth = 32,
        initialHeight = 32,
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        clampedToScreen = false,
        frameStrata = "DIALOG",
        onCreateFrame = function(_, owner) owner:Hide() end,
        onPositionSaved = function()
            -- 世界拖动已写入本模块 root DB 的 offsetX/offsetY。通过唯一
            -- 正式通知重套已有表面，并让编辑世界样本立即采用该 DB 坐标。
            EXUI:NotifyModuleValueChanged(EXWIND_MODULE_KEY, "offsetX", "committed")
            if EXUI.CurrentModule == EXWIND_MODULE_KEY and EXUI.MainFrame and EXUI.MainFrame:IsShown() then
                EXUI:RefreshContent()
            end
        end,
    })
    return anchorController
end

local function EnsureAnchor()
    if not anchorFrame then anchorFrame = EnsureAnchorController():Ensure() end
    local sample = BuildPresentation(true)
    anchorFrame:SetSize(sample.bodySize.width, sample.bodySize.height)
    EnsureAnchorController():ApplyPosition()
    return anchorFrame
end

local function RenderRuntime()
    local host = EnsureAnchor()
    runtimeCollection = runtimeCollection or EXUI:CreateIconCollection(host, "runtime", EXWIND_MODULE_KEY)
    local shown = RenderCollection(runtimeCollection, RUNTIME_ITEM_ID, false, false)
    SyncRuntimeAnchorBounds()
    if shown and not worldPreviewActive then
        host:Show()
    elseif not worldPreviewActive then
        host:Hide()
    end
end

local function RenderWorld(host)
    EnsureAnchor()
    worldPreviewActive = true
    if runtimeCollection then runtimeCollection:SetItems({}, SINGLE_ICON_LAYOUT) end
    if worldCollection then worldCollection:Release() end
    worldCollection = EXUI:CreateIconCollection(host, "world", EXWIND_MODULE_KEY)
    RenderCollection(worldCollection, WORLD_ITEM_ID, true, false)
    -- host 就是 EditMode 传入的 AnchorController 根；世界固定样本必须显示在
    -- 这一个 host 上，不能把它当作运行时视觉隐藏。
    host:Show()
end

local function ReleaseWorld()
    worldPreviewActive = false
    if worldCollection then
        worldCollection:Release(); worldCollection = nil
    end
    RenderRuntime()
end

local function GetWorldBounds()
    return worldCollection and worldCollection:GetWorldBounds() or nil
end

local function RefreshVisuals()
    EnsureAnchor()
    if worldPreviewActive then
        if worldCollection then RenderCollection(worldCollection, WORLD_ITEM_ID, true, false) end
        if runtimeCollection then runtimeCollection:SetItems({}, SINGLE_ICON_LAYOUT) end
    else
        RenderRuntime()
    end
    RenderPanelSample()
end

-- GUI 值变更只能重套已经存在的三种表面。presentation 每次都从当前 ModuleDB
-- 重建到原表上，Collection 只 Apply 当前 item，绝不创建或释放任何对象。
local function ReplaceCurrentPresentation(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
end

local function ReapplyExistingCollection(collection, sample, interactive)
    if collection and type(collection.ReapplyCurrentItems) == "function" then
        collection:ReapplyCurrentItems(function(presentation)
            ReplaceCurrentPresentation(presentation, BuildPresentation(sample, interactive))
        end)
    end
end

local function RefreshActiveSurfaces(changedPath)
    if changedPath == "offsetX" or changedPath == "offsetY"
        or changedPath == "attachToCustom" or changedPath == "customAttachTarget" then
        EnsureAnchorController():ApplyPosition()
    end
    if panelPreview and type(panelPreview.ReapplyCurrentItems) == "function" then
        panelPreview:ReapplyCurrentItems(function(presentation)
            ReplaceCurrentPresentation(presentation, BuildPresentation(true, true))
        end)
    end
    ReapplyExistingCollection(worldCollection, true, false)
    ReapplyExistingCollection(runtimeCollection, false, false)
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

local function FocusPlayerPositionGUI(guiTarget)
    if guiTarget ~= "icon" then error("PlayerPosition preview has no GUI target for " .. tostring(guiTarget), 2) end
    if not EXUI:FocusModuleGridKey(EXWIND_MODULE_KEY, guiTarget, EXUI.ModuleScrollFrame, EXUI.ActivePageFrame) then
        error("PlayerPosition preview GUI target is not rendered: " .. guiTarget, 2)
    end
end

local function HandlePreviewIntent(intent)
    if type(intent) ~= "table" or intent.type ~= "elementRightClicked" or intent.elementID ~= "core.icon" then
        error("PlayerPosition preview received unsupported intent", 2)
    end
    FocusPlayerPositionGUI(intent.guiTarget)
    return true
end

EXUI:RegisterEditableModule({
    addon = "ExwindTools",
    key = EXWIND_MODULE_KEY,
    name = L["玩家角色定位标记"],
    settingsPage = EXWIND_MODULE_KEY,
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor = EnsureAnchor,
    RenderWorld = RenderWorld,
    ReleaseWorld = ReleaseWorld,
    GetWorldBounds = GetWorldBounds,
})

-- Icon 是固定 Body；本模块没有可局部移动的文字或额外 Host。panel 明确
-- 声明右键语义，世界编辑仍只由 AnchorController 处理模块整体拖动。
ExwindTools:RegisterModulePreview(EXWIND_MODULE_KEY, {
    mount = function(dock)
        if panelPreview then panelPreview:Release() end
        panelDock = dock
        ApplyPreviewDockColor()
        panelPreview = EXUI:CreateIconPanelPreview(dock, EXWIND_MODULE_KEY, { onIntent = HandlePreviewIntent })
        RenderPanelSample()
    end,
    update = RenderPanelSample,
    release = function()
        if panelPreview then
            panelPreview:Release(); panelPreview = nil
        end
        panelDock = nil
    end,
})

-- =============================================================
-- 06. 既有业务 State 更新与提交回读（不改距离/显示判定）
-- =============================================================

updater:Hide()
updater:SetScript("OnUpdate", function(_, elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed >= .1 then
        updateElapsed = 0
        if not worldPreviewActive then RenderRuntime() end
    end
end)

ExwindTools:WatchState("InCombat", EXWIND_MODULE_KEY, function() if not worldPreviewActive then RenderRuntime() end end)
ExwindTools:WatchState("InInstance", EXWIND_MODULE_KEY, function() if not worldPreviewActive then RenderRuntime() end end)
ExwindTools:WatchState("SpecID", EXWIND_MODULE_KEY, function() if not worldPreviewActive then RenderRuntime() end end)
ExwindTools:RegisterEvent("PLAYER_TARGET_CHANGED", EXWIND_MODULE_KEY,
    function() if not worldPreviewActive then RenderRuntime() end end)

C_Timer.After(1, function()
    EnsureAnchor()
    RefreshVisuals()
    updater:Show()
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)
