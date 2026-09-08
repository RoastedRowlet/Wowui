-- =========================================================
-- ExwindStandardPreview.lua
-- EXUI 唯一标准预览组合层（第一阶段：icon / timerbar）。
--
-- 这不是旧 PreviewController / Workspace 的替代入口，也不读取模块 DB。
-- 模块只传纯 PreviewDefinition + PreviewModel，并接收语义 intent。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local ITEM_POOL = "EXUIStandardPreviewItem"
local REGION_POOL = "EXUIStandardPreviewRegion"
local HITBOX_POOL = "EXUIStandardPreviewHitbox"
local issecretvalue = _G.issecretvalue

local CHILD_KINDS = { text = true, glow = true, texture = true, atlas = true }
local RESERVED_PREFIX = "core."
local COLLECTION_ROOT_ID = "collection"
local COLLECTION_ITEM_ID = "__collection__"

local FIXED = {
    icon = {
        ["core.icon"] = { visual = true, focusable = false, tooltip = L["图标本体（固定在预览中心）"] },
        ["core.cooldown"] = { visual = true, focusable = false, tooltip = L["倒数圈（固定在图标本体上）"] },
        ["core.time"] = { text = true, movable = true, tooltip = L["时间文本"], anchor = { point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER" } },
        ["core.stacks"] = { text = true, movable = true, tooltip = L["层数文本"], anchor = { point = "BOTTOMRIGHT", relativeElement = "core.icon", relativePoint = "BOTTOMRIGHT" } },
    },
    timerbar = {
        ["core.bar"] = { visual = true, focusable = false, tooltip = L["计时条本体（固定在预览中心）"] },
        ["core.icon"] = { visual = true, focusable = false, tooltip = L["计时条图标（固定在计时条本体上）"] },
        ["core.spellName"] = { text = true, movable = true, tooltip = L["法术名称"], anchor = { point = "LEFT", relativeElement = "core.bar", relativePoint = "LEFT", x = 5 } },
        ["core.targetName"] = { text = true, movable = true, tooltip = L["目标名称"], anchor = { point = "CENTER", relativeElement = "core.bar", relativePoint = "CENTER" } },
        ["core.time"] = { text = true, movable = true, tooltip = L["时间文本"], anchor = { point = "RIGHT", relativeElement = "core.bar", relativePoint = "RIGHT", x = -5 } },
    },
    -- Material has no borrowed Icon/TimerBar fixed body.  Its sole declared
    -- texture child is the visual body and owns the only panel hitbox.
    material = {},
}

local DEFAULT_LAYOUT = { mode = "FLOW", direction = "DOWN", spacing = 8, maxVisible = 5 }
-- 所有标准设置页预览宿主的最低可见高度。内容较少时也保留稳定的触控空间；
-- 模块不得各自给 dock 写特例高度。world host 不使用此值。
local DEFAULT_PANEL_MIN_HOST_HEIGHT = 160
-- 世界编辑 host / 输入 / 覆盖层只留一圈极小且四边一致的安全余量。它不能按
-- 模块、元素方向或标题变化；真实可见元素的非对称 union 才是边界真源。
local WORLD_ENVELOPE_PADDING = 2

local function Fail(message)
    error("EXUI StandardPreview: " .. message, 3)
end

local function Number(value, name)
    if type(value) ~= "number" then Fail(name .. " must be number") end
    return value
end

local function Integer(value, name)
    Number(value, name)
    if value % 1 ~= 0 then Fail(name .. " must be integer") end
    return value
end

local function Copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

-- PreviewDefinition / PreviewModel 是模块到 Core 的不可变值边界。这里不仅验证，
-- 还递归复制每一个普通值，确保调用方随后改 DB 或原输入表不会改变已 materialize
-- 的预览，也不能让 Widget 持有模块配置表。回调函数仅存在于 CreateStandardPreview
-- options 边界，永远不进入声明或模型。
local function SnapshotPlain(value, path, seen)
    -- Preview Definition / Model 是普通值边界。12.1 的 issecretvalue 是权威允许的
    -- 唯一探测入口；检测不到时宁可拒绝 materialize，也不能把未知值静默存入 Core。
    if type(issecretvalue) ~= "function" then
        Fail("secret detection API is unavailable; refusing " .. path)
    end
    if issecretvalue(value) then
        Fail(path .. " must not contain Secret Value")
    end
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "number" or valueType == "string" then return value end
    if valueType ~= "table" then Fail(path .. " must contain only plain Lua values") end
    if value.GetObjectType or getmetatable(value) then Fail(path .. " must not contain Frame/object tables") end
    seen = seen or {}
    if seen[value] then Fail(path .. " must not contain cyclic tables") end
    seen[value] = true
    local snapshot = {}
    for key, child in pairs(value) do
        if issecretvalue(key) then Fail(path .. " must not contain Secret Value keys") end
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then Fail(path .. " has invalid key type") end
        snapshot[key] = SnapshotPlain(child, path .. "." .. tostring(key), seen)
    end
    seen[value] = nil
    return snapshot
end

-- 给模块构建自己的 Definition / Model 快照的公开值工具。它不知道模块名、DB、字段路径
-- 或页面；模块必须在返回前就完成自己的快照，Core 的 Materialize 仍会再次隔离。
function EXUI:SnapshotPreviewData(value, path)
    return SnapshotPlain(value, path or "previewData")
end

local function AssertAnchor(anchor, path)
    if anchor == nil then return end
    if type(anchor) ~= "table" then Fail(path .. " must be table") end
    if anchor.point ~= nil and type(anchor.point) ~= "string" then Fail(path .. ".point must be string") end
    if anchor.relativePoint ~= nil and type(anchor.relativePoint) ~= "string" then Fail(path .. ".relativePoint must be string") end
    if anchor.relativeElement ~= nil and type(anchor.relativeElement) ~= "string" then Fail(path .. ".relativeElement must be string") end
    if anchor.x ~= nil then Number(anchor.x, path .. ".x") end
    if anchor.y ~= nil then Number(anchor.y, path .. ".y") end
end

local function ValidateLayout(layout)
    layout = layout or DEFAULT_LAYOUT
    if type(layout) ~= "table" then Fail("definition.layout must be table") end
    local mode = tostring(layout.mode or DEFAULT_LAYOUT.mode):upper()
    if mode ~= "FLOW" and mode ~= "ABSOLUTE" then Fail("definition.layout.mode must be FLOW or ABSOLUTE") end
    local direction = tostring(layout.direction or DEFAULT_LAYOUT.direction):upper()
    if direction ~= "LEFT" and direction ~= "RIGHT" and direction ~= "UP" and direction ~= "DOWN" then
        Fail("definition.layout.direction must be LEFT/RIGHT/UP/DOWN")
    end
    -- 间距是相邻本体之间的有符号空隙：负值表示重叠，不是非法布局。
    -- 之前把负值拒绝在快照验证阶段，会在 Materialize 已清空旧预览后直接报错，
    -- 表现为“滑到 0 以下整个预览消失”。真正的最小步距由 WidgetLayout 按
    -- 本体尺寸保障，不能在这里把用户的负间距重写成 0。
    if layout.spacing ~= nil and type(layout.spacing) ~= "number" then
        Fail("definition.layout.spacing must be number")
    end
    if layout.maxVisible ~= nil and (type(layout.maxVisible) ~= "number" or layout.maxVisible < 1 or layout.maxVisible % 1 ~= 0) then
        Fail("definition.layout.maxVisible must be positive integer")
    end
    if layout.itemWidth ~= nil and (type(layout.itemWidth) ~= "number" or layout.itemWidth <= 0) then
        Fail("definition.layout.itemWidth must be positive number")
    end
    if layout.itemHeight ~= nil and (type(layout.itemHeight) ~= "number" or layout.itemHeight <= 0) then
        Fail("definition.layout.itemHeight must be positive number")
    end
    if layout.semanticFirstItem ~= nil and type(layout.semanticFirstItem) ~= "boolean" then
        Fail("definition.layout.semanticFirstItem must be boolean")
    end
end

local function ValidateSlotOverrides(slots, fixed, path)
    if slots ~= nil and type(slots) ~= "table" then Fail(path .. " must be table") end
    for id, spec in pairs(slots or {}) do
        if not fixed[id] then Fail(path .. " has unknown fixed element " .. tostring(id)) end
        if type(spec) ~= "table" then Fail(path .. "." .. id .. " must be table") end
        if spec.movable ~= nil and type(spec.movable) ~= "boolean" then Fail(path .. "." .. id .. ".movable must be boolean") end
        if spec.focusable ~= nil and type(spec.focusable) ~= "boolean" then Fail(path .. "." .. id .. ".focusable must be boolean") end
        if spec.shown ~= nil and type(spec.shown) ~= "boolean" then Fail(path .. "." .. id .. ".shown must be boolean") end
        if spec.guiTarget ~= nil and type(spec.guiTarget) ~= "string" then Fail(path .. "." .. id .. ".guiTarget must be string") end
        if spec.tooltip ~= nil and type(spec.tooltip) ~= "string" then Fail(path .. "." .. id .. ".tooltip must be string") end
        AssertAnchor(spec.anchor, path .. "." .. id .. ".anchor")
        if spec.style ~= nil and type(spec.style) ~= "table" then Fail(path .. "." .. id .. ".style must be table") end
    end
end

-- ExtraChildHost 只声明几何和交互。payload 永远属于模块；Core 不知道其中是
-- Atlas、团队标记还是任何其它业务视觉。
local function ValidateExtraChildHosts(hosts)
    if hosts == nil then return end
    if type(hosts) ~= "table" then Fail("definition.extraChildHosts must be table") end
    local ids = {}
    for key in pairs(hosts) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #hosts then
            Fail("definition.extraChildHosts must be a dense array")
        end
    end
    for _, host in ipairs(hosts) do
        if type(host) ~= "table" then Fail("definition.extraChildHosts entries must be table") end
        if type(host.id) ~= "string" or host.id == "" then Fail("extra child host id must be non-empty string") end
        if host.id:sub(1, #RESERVED_PREFIX) == RESERVED_PREFIX then Fail("extra child host id uses reserved core.* namespace") end
        if ids[host.id] then Fail("definition has duplicate extra child host " .. host.id) end
        ids[host.id] = true
        if host.movable ~= nil and type(host.movable) ~= "boolean" then Fail("extra child host " .. host.id .. ".movable must be boolean") end
        if host.focusable ~= nil and type(host.focusable) ~= "boolean" then Fail("extra child host " .. host.id .. ".focusable must be boolean") end
        if host.guiTarget ~= nil and type(host.guiTarget) ~= "string" then Fail("extra child host " .. host.id .. ".guiTarget must be string") end
        if host.tooltip ~= nil and type(host.tooltip) ~= "string" then Fail("extra child host " .. host.id .. ".tooltip must be string") end
        AssertAnchor(host.anchor, "extra child host " .. host.id .. ".anchor")
        if type(host.width) ~= "number" or host.width <= 0 then Fail("extra child host " .. host.id .. ".width must be positive number") end
        if type(host.height) ~= "number" or host.height <= 0 then Fail("extra child host " .. host.id .. ".height must be positive number") end
    end
end

local function ValidateDefinition(definition)
    if type(definition) ~= "table" then Fail("definition must be table") end
    if definition.kind ~= "icon" and definition.kind ~= "timerbar" and definition.kind ~= "material" then
        Fail("definition.kind must be icon, timerbar, or material")
    end
    ValidateLayout(definition.layout)
    if definition.appearance ~= nil and type(definition.appearance) ~= "table" then Fail("definition.appearance must be table") end
    local fixed = FIXED[definition.kind]
    ValidateSlotOverrides(definition.slots, fixed, "definition.slots")
    ValidateExtraChildHosts(definition.extraChildHosts)

    for key in pairs(definition.children or {}) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #(definition.children or {}) then
            Fail("definition.children must be a dense array")
        end
    end
    local ids = {}
    for _, child in ipairs(definition.children or {}) do
        if type(child) ~= "table" then Fail("definition.children entries must be table") end
        local id = child.id
        if type(id) ~= "string" or id == "" then Fail("definition child id must be non-empty string") end
        if id:sub(1, #RESERVED_PREFIX) == RESERVED_PREFIX then Fail("definition child id " .. id .. " uses reserved core.* namespace") end
        if ids[id] then Fail("definition has duplicate child id " .. id) end
        ids[id] = true
        if not CHILD_KINDS[child.kind] then Fail("definition child " .. id .. " has unknown kind " .. tostring(child.kind)) end
        if child.movable ~= nil and type(child.movable) ~= "boolean" then Fail("definition child " .. id .. ".movable must be boolean") end
        if child.focusable ~= nil and type(child.focusable) ~= "boolean" then Fail("definition child " .. id .. ".focusable must be boolean") end
        if child.guiTarget ~= nil and type(child.guiTarget) ~= "string" then Fail("definition child " .. id .. ".guiTarget must be string") end
        if child.tooltip ~= nil and type(child.tooltip) ~= "string" then Fail("definition child " .. id .. ".tooltip must be string") end
        if child.layer ~= nil and child.layer ~= "background" and child.layer ~= "child" then
            Fail("definition child " .. id .. ".layer must be background or child")
        end
        AssertAnchor(child.anchor, "definition child " .. id .. ".anchor")
        if child.style ~= nil and type(child.style) ~= "table" then Fail("definition child " .. id .. ".style must be table") end
    end

    for key in pairs(definition.collectionDecorations or {}) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #(definition.collectionDecorations or {}) then
            Fail("definition.collectionDecorations must be a dense array")
        end
    end
    local decorationIDs = { [COLLECTION_ROOT_ID] = true }
    for _, decoration in ipairs(definition.collectionDecorations or {}) do
        if type(decoration) ~= "table" then Fail("definition.collectionDecorations entries must be table") end
        local id = decoration.id
        if type(id) ~= "string" or id == "" then Fail("collection decoration id must be non-empty string") end
        if id == COLLECTION_ROOT_ID or id == COLLECTION_ITEM_ID then Fail("collection decoration id is reserved: " .. id) end
        if id:sub(1, #RESERVED_PREFIX) == RESERVED_PREFIX then Fail("collection decoration id " .. id .. " uses reserved core.* namespace") end
        if decorationIDs[id] then Fail("definition has duplicate collection decoration id " .. id) end
        decorationIDs[id] = true
        if not CHILD_KINDS[decoration.kind] then Fail("collection decoration " .. id .. " has unknown kind " .. tostring(decoration.kind)) end
        if decoration.movable ~= nil and type(decoration.movable) ~= "boolean" then Fail("collection decoration " .. id .. ".movable must be boolean") end
        if decoration.focusable ~= nil and type(decoration.focusable) ~= "boolean" then Fail("collection decoration " .. id .. ".focusable must be boolean") end
        if decoration.guiTarget ~= nil and type(decoration.guiTarget) ~= "string" then Fail("collection decoration " .. id .. ".guiTarget must be string") end
        if decoration.tooltip ~= nil and type(decoration.tooltip) ~= "string" then Fail("collection decoration " .. id .. ".tooltip must be string") end
        if decoration.layer ~= nil and decoration.layer ~= "background" and decoration.layer ~= "child" then
            Fail("collection decoration " .. id .. ".layer must be background or child")
        end
        AssertAnchor(decoration.anchor, "collection decoration " .. id .. ".anchor")
        if decoration.style ~= nil and type(decoration.style) ~= "table" then Fail("collection decoration " .. id .. ".style must be table") end
        if decoration.width ~= nil and (type(decoration.width) ~= "number" or decoration.width <= 0) then Fail("collection decoration " .. id .. ".width must be positive number") end
        if decoration.height ~= nil and (type(decoration.height) ~= "number" or decoration.height <= 0) then Fail("collection decoration " .. id .. ".height must be positive number") end
    end
    for _, decoration in ipairs(definition.collectionDecorations or {}) do
        local relativeID = decoration.anchor and decoration.anchor.relativeElement
        if relativeID ~= nil and not decorationIDs[relativeID] then
            Fail("collection decoration " .. decoration.id .. " anchor references unknown collection element " .. tostring(relativeID))
        end
    end
    if definition.kind == "material" then
        local child = definition.children and definition.children[1]
        if not child or child.kind ~= "texture" then
            Fail("material definition requires a texture body as its first child")
        end
        for index = 2, #(definition.children or {}) do
            local childKind = definition.children[index].kind
            if childKind ~= "text" and childKind ~= "texture" then
                Fail("material definition supports only text or texture children after its texture body")
            end
        end
        if #(definition.extraChildHosts or {}) ~= 0 or #(definition.collectionDecorations or {}) ~= 0 then
            Fail("material definition does not support extra child hosts or collection decorations")
        end
    end
end

local function ValidateMaterialSpec(material, path)
    if type(material) ~= "table" then Fail(path .. ".material must be table") end
    local geometry = material.geometry
    if type(geometry) ~= "table" then Fail(path .. ".material.geometry must be table") end
    if type(geometry.width) ~= "number" or geometry.width <= 0 then Fail(path .. ".material.geometry.width must be positive number") end
    if type(geometry.height) ~= "number" or geometry.height <= 0 then Fail(path .. ".material.geometry.height must be positive number") end
    if material.textureToken == nil then Fail(path .. ".material.textureToken is required") end
    AssertAnchor(material.anchor, path .. ".material.anchor")
    if material.color ~= nil and type(material.color) ~= "table" then Fail(path .. ".material.color must be table") end
    if material.texCoord ~= nil and type(material.texCoord) ~= "table" then Fail(path .. ".material.texCoord must be table") end
    if material.alpha ~= nil and type(material.alpha) ~= "number" then Fail(path .. ".material.alpha must be number") end
    if material.rotation ~= nil and type(material.rotation) ~= "number" then Fail(path .. ".material.rotation must be number") end
    if material.rotationRadians ~= nil and type(material.rotationRadians) ~= "number" then Fail(path .. ".material.rotationRadians must be number") end
    if material.blendMode ~= nil and type(material.blendMode) ~= "string" then Fail(path .. ".material.blendMode must be string") end
    if material.visible ~= nil and type(material.visible) ~= "boolean" then Fail(path .. ".material.visible must be boolean") end
end

local function ValidateItem(item, kind, index, childrenByID, extraHostsByID, layout, materialBodyID)
    local path = "model.items[" .. index .. "]"
    if type(item) ~= "table" then Fail(path .. " must be table") end
    if type(item.itemID) ~= "string" or item.itemID == "" then Fail(path .. ".itemID must be non-empty string") end
    if item.type ~= "spell" and item.type ~= "custom" then Fail(path .. ".type must be spell or custom") end
    Integer(item.order, path .. ".order")
    if tostring(layout.mode or DEFAULT_LAYOUT.mode):upper() == "ABSOLUTE" then
        if type(item.position) ~= "table" then Fail(path .. ".position is required for ABSOLUTE layout") end
        Number(item.position.x, path .. ".position.x")
        Number(item.position.y, path .. ".position.y")
    elseif item.position ~= nil then
        Fail(path .. ".position is only valid for ABSOLUTE layout")
    end
    if item.appearance ~= nil and type(item.appearance) ~= "table" then Fail(path .. ".appearance must be table") end
    ValidateSlotOverrides(item.slots, FIXED[kind], path .. ".slots")
    if item.type == "spell" then
        Integer(item.spellID, path .. ".spellID")
        if item.spellID <= 0 then Fail(path .. ".spellID must be positive") end
        if not C_Spell or not C_Spell.GetSpellInfo or not C_Spell.GetSpellInfo(item.spellID) then
            Fail(path .. ".spellID cannot be resolved")
        end
    else
        if type(item.name) ~= "string" or item.name == "" then Fail(path .. ".name must be non-empty string for custom") end
        if kind ~= "material" and item.icon == nil then Fail(path .. ".icon is required for custom") end
    end
    if item.duration ~= nil then
        if type(item.duration) ~= "number" or item.duration <= 0 then Fail(path .. ".duration must be > 0") end
        if type(item.remaining) ~= "number" or item.remaining < 0 or item.remaining > item.duration then
            Fail(path .. ".remaining must be within [0, duration]")
        end
    elseif item.remaining ~= nil then
        Fail(path .. ".remaining requires duration")
    end
    -- 模块可为固定标准时间槽提供已经格式化好的普通展示文字（例如整数/小数
    -- 开关），但它仍由同一个 core.time TextWidget 与静态 cooldown 快照驱动；
    -- 这不是模块自建第二个倒数 renderer。
    if item.timeText ~= nil and type(item.timeText) ~= "string" then
        Fail(path .. ".timeText must be string")
    end
    if item.progressValue ~= nil and type(item.progressValue) ~= "number" then Fail(path .. ".progressValue must be number") end
    if item.progressMaximum ~= nil and (type(item.progressMaximum) ~= "number" or item.progressMaximum <= 0) then
        Fail(path .. ".progressMaximum must be positive number")
    end
    if item.progressValue ~= nil and item.progressMaximum == nil then
        Fail(path .. ".progressValue requires progressMaximum")
    end
    if item.elements ~= nil and type(item.elements) ~= "table" then Fail(path .. ".elements must be table") end
    for id, data in pairs(item.elements or {}) do
        local declaration = childrenByID[id]
        if not declaration then Fail(path .. ".elements references undeclared child " .. tostring(id)) end
        if type(data) ~= "table" then Fail(path .. ".elements." .. id .. " must be table") end
        if data.shown ~= nil and type(data.shown) ~= "boolean" then Fail(path .. ".elements." .. id .. ".shown must be boolean") end
        if data.style ~= nil and type(data.style) ~= "table" then Fail(path .. ".elements." .. id .. ".style must be table") end
        if data.position ~= nil then
            if type(data.position) ~= "table" then Fail(path .. ".elements." .. id .. ".position must be table") end
            Number(data.position.x, path .. ".elements." .. id .. ".position.x")
            Number(data.position.y, path .. ".elements." .. id .. ".position.y")
        end
        if kind == "material" and id == materialBodyID then
            ValidateMaterialSpec(data.material, path .. ".elements." .. id)
        end
        if data.shown ~= false then
            if declaration.kind == "atlas" and (type(data.atlas) ~= "string" or data.atlas == "") then
                Fail(path .. ".elements." .. id .. " requires non-empty atlas")
            elseif declaration.kind == "texture" then
                if id ~= materialBodyID and data.texture == nil then
                    Fail(path .. ".elements." .. id .. " requires texture")
                end
            elseif declaration.kind == "glow" and type(data.style or declaration.style) ~= "table" then
                Fail(path .. ".elements." .. id .. " requires style")
            end
        end
    end
    for id in pairs(childrenByID) do
        if type(item.elements) ~= "table" or item.elements[id] == nil then
            Fail(path .. ".elements omits declared child " .. id .. "; pass { shown = false } when hidden")
        end
    end
    if item.extraChildren ~= nil and type(item.extraChildren) ~= "table" then Fail(path .. ".extraChildren must be table") end
    for id, data in pairs(item.extraChildren or {}) do
        if not extraHostsByID[id] then Fail(path .. ".extraChildren references undeclared host " .. tostring(id)) end
        if type(data) ~= "table" then Fail(path .. ".extraChildren." .. id .. " must be table") end
        if data.shown ~= nil and type(data.shown) ~= "boolean" then Fail(path .. ".extraChildren." .. id .. ".shown must be boolean") end
        if data.position ~= nil then
            if type(data.position) ~= "table" then Fail(path .. ".extraChildren." .. id .. ".position must be table") end
            Number(data.position.x, path .. ".extraChildren." .. id .. ".position.x")
            Number(data.position.y, path .. ".extraChildren." .. id .. ".position.y")
        end
        if data.payload ~= nil and type(data.payload) ~= "table" then Fail(path .. ".extraChildren." .. id .. ".payload must be table") end
    end
    for id in pairs(extraHostsByID) do
        if type(item.extraChildren) ~= "table" or item.extraChildren[id] == nil then
            Fail(path .. ".extraChildren omits declared host " .. id .. "; pass { shown = false } when hidden")
        end
    end
    if kind == "icon" and item.stacks ~= nil and (type(item.stacks) ~= "number" and type(item.stacks) ~= "string") then
        Fail(path .. ".stacks must be number or string")
    end
    if kind == "timerbar" and item.targetName ~= nil and type(item.targetName) ~= "string" then
        Fail(path .. ".targetName must be string")
    end
end

local function ValidateModel(definition, model)
    if type(model) ~= "table" or type(model.items) ~= "table" then Fail("model.items must be table") end
    local childrenByID, extraHostsByID, itemIDs, orders = {}, {}, {}, {}
    for key in pairs(model.items) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #model.items then Fail("model.items must be a dense array") end
    end
    for _, child in ipairs(definition.children or {}) do childrenByID[child.id] = child end
    for _, host in ipairs(definition.extraChildHosts or {}) do extraHostsByID[host.id] = host end
    local materialBodyID = definition.kind == "material"
        and definition.children and definition.children[1] and definition.children[1].id or nil
    for index, item in ipairs(model.items) do
        ValidateItem(item, definition.kind, index, childrenByID, extraHostsByID,
            definition.layout or DEFAULT_LAYOUT, materialBodyID)
        if itemIDs[item.itemID] then Fail("model has duplicate itemID " .. item.itemID) end
        if orders[item.order] then Fail("model has duplicate order " .. tostring(item.order)) end
        itemIDs[item.itemID], orders[item.order] = true, true
    end
    if itemIDs[COLLECTION_ITEM_ID] then Fail("model itemID uses reserved collection id") end

    if model.decorations ~= nil and type(model.decorations) ~= "table" then Fail("model.decorations must be table") end
    local declared = {}
    for _, decoration in ipairs(definition.collectionDecorations or {}) do declared[decoration.id] = decoration end
    for id, data in pairs(model.decorations or {}) do
        local decoration = declared[id]
        if not decoration then Fail("model.decorations references undeclared collection decoration " .. tostring(id)) end
        if type(data) ~= "table" then Fail("model.decorations." .. id .. " must be table") end
        if data.shown ~= nil and type(data.shown) ~= "boolean" then Fail("model.decorations." .. id .. ".shown must be boolean") end
        if data.width ~= nil and (type(data.width) ~= "number" or data.width <= 0) then Fail("model.decorations." .. id .. ".width must be positive number") end
        if data.height ~= nil and (type(data.height) ~= "number" or data.height <= 0) then Fail("model.decorations." .. id .. ".height must be positive number") end
        if data.position ~= nil then
            if type(data.position) ~= "table" then Fail("model.decorations." .. id .. ".position must be table") end
            Number(data.position.x, "model.decorations." .. id .. ".position.x")
            Number(data.position.y, "model.decorations." .. id .. ".position.y")
        end
        if data.text ~= nil and type(data.text) ~= "string" and type(data.text) ~= "number" then Fail("model.decorations." .. id .. ".text must be string or number") end
        if data.shown ~= false then
            if decoration.kind == "atlas" and (type(data.atlas) ~= "string" or data.atlas == "") then Fail("model.decorations." .. id .. " requires non-empty atlas") end
            if decoration.kind == "texture" and data.texture == nil then Fail("model.decorations." .. id .. " requires texture") end
            if decoration.kind == "glow" and type(data.style or decoration.style) ~= "table" then Fail("model.decorations." .. id .. " requires style") end
        end
    end
    for id in pairs(declared) do
        if type(model.decorations) ~= "table" or model.decorations[id] == nil then
            Fail("model.decorations omits declared collection decoration " .. id .. "; pass { shown = false } when hidden")
        end
    end
end

local function ResolveContent(item)
    if item.type == "custom" then return item.name, item.icon end
    if not C_Spell or not C_Spell.GetSpellInfo then Fail("C_Spell.GetSpellInfo is unavailable") end
    local spell = C_Spell.GetSpellInfo(item.spellID)
    if not spell then Fail("spell item " .. item.itemID .. " has unresolved spellID " .. item.spellID) end
    return spell.name, spell.iconID
end

local function ResetRegion(region)
    region:Hide()
    region:ClearAllPoints()
    region:SetScript("OnUpdate", nil)
    if region._texture then
        region._texture:Hide()
        region._texture:SetTexture(nil)
        region._texture:SetVertexColor(1, 1, 1, 1)
        region._texture:ClearAllPoints()
    end
    region._previewText = nil
    if region._previewGlow then region._previewGlow:Release(); region._previewGlow = nil end
end

local function EnsureRegion(region)
    if not region._texture then
        region._texture = EXUI:CreateVisualTexture(region, _G.EXBORDERFRAME)
    end
    -- ResetRegion 会清除上一次使用的锚点；对象池复用时必须无条件恢复纹理几何。
    region._texture:ClearAllPoints()
    region._texture:SetAllPoints(region)
    EXUI:ApplyVisualLayer(region._texture, _G.EXBORDERFRAME, region)
end

local function ApplyPreviewLayer(region, layer, root)
    EXUI:ApplyVisualLayer(region, layer, root)
    return region
end

local function SetWorldEditState(preview, shown)
    if preview.interactionMode ~= "world" then return end
    -- StandardPreview 只声明“这个 host 正在承载标准世界预览”。唯一编辑视觉的
    -- 创建、显示和模块标题注入只能由 AnchorController / HUD 管理链在 materialize
    -- 之后完成；这里绝不能以 nil title 调用视觉层，否则首次 world materialize 会
    -- 把唯一标题层初始化为空，形成“有框但没有模块名”的时序分叉。
    preview.host.__ExwindStandardWorldPreview = shown == true or nil
    preview.host.__ExwindStandardWorldEditLayer = shown == true or nil
end

local function CenterFixedBody(item)
    -- 本体不是可移动元素。无论布局重排、刷新或子元素临时拖动发生多少次，
    -- 条/图标都只锚在它所属 layout slot 的几何中心。
    if not item.widget then return end
    item.widget:ClearAllPoints()
    item.widget:SetPoint("CENTER", item.root, "CENTER")
end

-- Material is a dedicated StandardPreview body.  The input is the pure
-- MaterialPresentation value produced by a module; Core converts it once to
-- the public ExtraTextureWidget contract, so panel rendering never obtains a
-- raw Texture or drops flip/blend/rotation/local-alpha fields.
local function MaterialWidgetPresentation(material)
    local geometry = material.geometry or {}
    local color = material.color or {}
    local coord = material.texCoord or {}
    return {
        style = {
            width = math.max(1, tonumber(geometry.width) or 1),
            height = math.max(1, tonumber(geometry.height) or 1),
        },
        texture = material.textureToken,
        texCoord = {
            tonumber(coord.left) or 0, tonumber(coord.right) or 1,
            tonumber(coord.top) or 0, tonumber(coord.bottom) or 1,
        },
        color = {
            r = tonumber(color.r) or 1, g = tonumber(color.g) or 1, b = tonumber(color.b) or 1,
            a = (tonumber(color.a) or 1) * (tonumber(material.alpha) or 1),
        },
        blendMode = material.blendMode or "BLEND",
        rotation = tonumber(material.rotation) or 0,
        -- texCoord is already the canonical flipped coordinate rectangle.
        flipH = false, flipV = false,
        shown = material.visible ~= false,
    }
end

local function ApplyMaterialBody(item, declaration, data)
    local material = data and data.material
    ValidateMaterialSpec(material, "material body")
    if not item.widget or type(item.widget.ApplyPresentation) ~= "function" then
        Fail("material preview requires ExtraTextureWidget")
    end
    local presentation = MaterialWidgetPresentation(material)
    if data.shown == false then presentation.shown = false end
    item.widget:ApplyPresentation(presentation)
    local anchor = material.anchor or {}
    item.widget:SetAnchor(anchor.point or "CENTER", item.root, anchor.relativePoint or anchor.point or "CENTER",
        tonumber(anchor.x) or 0, tonumber(anchor.y) or 0)
    local element = item.elements[declaration.id] or { id = declaration.id, root = item.widget }
    element.spec, element.anchor = declaration, declaration.anchor
    element.position = { x = tonumber(anchor.x) or 0, y = tonumber(anchor.y) or 0 }
    item.elements[declaration.id] = element
    return material
end

local function ReleaseHitbox(hitbox)
    if GameTooltip and GameTooltip:GetOwner() == hitbox then GameTooltip:Hide() end
    hitbox:SetScript("OnUpdate", nil)
    hitbox:SetScript("OnEnter", nil)
    hitbox:SetScript("OnLeave", nil)
    hitbox:SetScript("OnMouseDown", nil)
    hitbox:SetScript("OnMouseUp", nil)
    hitbox._preview = nil
    hitbox:SetScale(1)
    hitbox:Hide()
    hitbox:ClearAllPoints()
    EXFactory:Release(HITBOX_POOL, hitbox)
end

local function ReleaseElement(element)
    if element.hitbox then ReleaseHitbox(element.hitbox); element.hitbox = nil end
    if element.text then element.text:Release(); element.text = nil end
    if element.region then ResetRegion(element.region); EXFactory:Release(REGION_POOL, element.region); element.region = nil end
end

local function ReleaseItem(item)
    for _, element in pairs(item.elements or {}) do ReleaseElement(element) end
    item.elements = nil
    if item.widget then item.widget:Release(); item.widget = nil end
    item.roots = nil
    item.root:Hide()
    item.root:ClearAllPoints()
    item.root.__EXUIStandardPreviewPosition = nil
    EXFactory:Release(ITEM_POOL, item.root)
end

local function ReleaseCollectionDecorations(preview)
    local collection = preview.collection
    if not collection then return end
    for _, element in pairs(collection.elements or {}) do ReleaseElement(element) end
    preview.collection = nil
end

local function ElementRoot(element)
    if element.root then return element.root end
    if element.text then return element.text end
    return element.region
end

-- 世界编辑模式的鼠标所有者只能是 AnchorController 的 anchorFrame。标准预览本身
-- 不创建任何世界 hitbox，但必须把所有真实可见 Region（含外置图标、Atlas 和
-- 子元素）纳入 anchorFrame 的尺寸。否则向上/向下排列时，视觉只落在旧锚点的一半，
-- 看得到却点不到。世界 host 使用实际非对称 union；固定本体通过内部反向 offset
-- 保持原有逻辑位置，不能为了“贴紧”而改变条/图标本体的运行时锚点。
local function AccumulateVisibleBounds(bounds, region)
    if not region then return end
    if type(region.GetRoot) == "function" then region = region:GetRoot() end
    if not region or type(region.IsShown) ~= "function" or not region:IsShown() then return end
    if type(region.GetLeft) ~= "function" or type(region.GetRight) ~= "function"
        or type(region.GetTop) ~= "function" or type(region.GetBottom) ~= "function" then
        return
    end
    local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
    if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then return end
    bounds.left = bounds.left and math.min(bounds.left, left) or left
    bounds.right = bounds.right and math.max(bounds.right, right) or right
    bounds.top = bounds.top and math.max(bounds.top, top) or top
    bounds.bottom = bounds.bottom and math.min(bounds.bottom, bottom) or bottom
end

local function ResolveWorldEnvelope(preview)
    local bounds = {}
    for _, item in ipairs(preview.items) do
        AccumulateVisibleBounds(bounds, item.root)
        AccumulateVisibleBounds(bounds, item.widget)
        for _, element in pairs(item.elements) do
            -- ExtraChildHost 的固定 bounds 要覆盖世界编辑的整体命中范围；但
            -- semantic-root 路径只使用这些 bounds 扩大编辑框，绝不将 union
            -- center 回写给 Body、collection 或保存锚点。
            AccumulateVisibleBounds(bounds, ElementRoot(element))
        end
    end
    if preview.collection then
        for _, element in pairs(preview.collection.elements or {}) do
            AccumulateVisibleBounds(bounds, ElementRoot(element))
        end
    end
    if not bounds.left then
        local width, height = preview.layout:GetBounds()
        return {
            width = math.max(1, width + WORLD_ENVELOPE_PADDING * 2),
            height = math.max(1, height + WORLD_ENVELOPE_PADDING * 2),
            anchorOffsetX = 0,
            anchorOffsetY = 0,
            contentOffsetX = 0,
            contentOffsetY = 0,
        }
    end

    local host = preview.host
    local hostLeft, hostRight = host:GetLeft(), host:GetRight()
    local hostTop, hostBottom = host:GetTop(), host:GetBottom()
    if type(hostLeft) ~= "number" or type(hostRight) ~= "number"
        or type(hostTop) ~= "number" or type(hostBottom) ~= "number" then
        local width, height = preview.layout:GetBounds()
        return {
            width = math.max(1, width + WORLD_ENVELOPE_PADDING * 2),
            height = math.max(1, height + WORLD_ENVELOPE_PADDING * 2),
            anchorOffsetX = 0,
            anchorOffsetY = 0,
            contentOffsetX = 0,
            contentOffsetY = 0,
        }
    end
    -- 设置页预览仍保持固定本体居中；世界编辑则必须让 anchorFrame 的鼠标范围、
    -- 覆盖层与真实可见 union 一致。若强行取左右/上下对称包络，左侧 Atlas 会在右边
    -- 制造同等宽度的空白，且空白会跟着条宽移动。这里以实际 union 中心为新的 frame
    -- 中心，同时以反向 contentOffset 保持条/图标在其原有逻辑 world 位置不跳动。
    local hostCenterX, hostCenterY = (hostLeft + hostRight) * 0.5, (hostTop + hostBottom) * 0.5
    local logicalCenterX = hostCenterX + (preview.worldContentOffsetX or 0)
    local logicalCenterY = hostCenterY + (preview.worldContentOffsetY or 0)
    local unionCenterX, unionCenterY = (bounds.left + bounds.right) * 0.5, (bounds.top + bounds.bottom) * 0.5
    local anchorOffsetX, anchorOffsetY = unionCenterX - logicalCenterX, unionCenterY - logicalCenterY
    return {
        width = math.max(1, (bounds.right - bounds.left) + WORLD_ENVELOPE_PADDING * 2),
        height = math.max(1, (bounds.top - bounds.bottom) + WORLD_ENVELOPE_PADDING * 2),
        anchorOffsetX = anchorOffsetX,
        anchorOffsetY = anchorOffsetY,
        contentOffsetX = -anchorOffsetX,
        contentOffsetY = -anchorOffsetY,
    }
end

local function ApplyAnchor(root, anchor, roots, fallback, position)
    anchor = anchor or fallback
    local relative = roots[anchor.relativeElement] or fallback.relative
    if not relative then Fail("anchor references unavailable element " .. tostring(anchor.relativeElement)) end
    root:ClearAllPoints()
    root:SetPoint(anchor.point or fallback.point, relative, anchor.relativePoint or fallback.relativePoint or anchor.point or fallback.point,
        position and position.x or anchor.x or 0, position and position.y or anchor.y or 0)
end

-- 模块的 x/y 是子元素相对本体的空间位置，已经由 slot/child anchor 表达。
-- TextWidget 的 style.x/y 只会把同一位置再平移一次，既让画面偏离正式显示，
-- 也会把命中几何建立在错误坐标上。标准预览保留字体视觉样式，但位置只认 anchor。
-- CenterFixedBody 是 item slot 的默认布局步骤；模块若声明了 fixed element
-- 的自定义 anchor（例如 Countdown 的完整 IconWidget），必须在每次默认居中
-- 之后重新应用。否则初次物化或拖动重建时，custom anchor 会被无条件覆盖，
-- 造成 intent 虽然已经写回，画面却回到中心、X/Y 看起来完全无效。
local function ApplyFixedElementAnchors(item)
    if not item or not item.widget or not item.elements then return end
    local coreIcon = item.elements["core.icon"]
    if coreIcon and coreIcon.anchor then
        ApplyAnchor(ElementRoot(coreIcon), coreIcon.anchor, item.roots, coreIcon.fallback, coreIcon.position)
    end
end

local function PreviewTextStyle(style)
    local result = Copy(style)
    result.x, result.y = 0, 0
    -- 运行时 AuraButton 的 ApplyFontStyle 对缺省配置有明确语义：文字框始终
    -- CENTER/MIDDLE；只有 fixedWidth/关闭 autoWidth 或 maxWidth 才换行。标准
    -- TextWidget 若直接吃稀疏配置，会保留池中旧的对齐/换行状态，造成同一份
    -- durationText/countText 在预览与实际画面中的字框基准不同。
    result.justifyH = result.justifyH or "CENTER"
    result.justifyV = result.justifyV or "MIDDLE"
    result.wordWrap = result.autoWidth == false or (tonumber(result.maxWidth) or 0) > 0
    return result
end

local function AcquireText(parent, style, text)
    local widget = EXUI:CreateTextWidget(parent, "standardPreview")
    widget:ApplyStyle(PreviewTextStyle(style))
    widget:SetText(text or "")
    return widget
end

local function FixedSpec(definition, id, default)
    local override = definition.slots and definition.slots[id] or nil
    local result = Copy(default)
    if override then
        for key, value in pairs(override) do result[key] = value end
    end
    return result
end

-- 多 item 标准预览可为每一项提供纯数据外观/固定槽覆盖；这是一条通用预览契约，
-- 不携带 renderer 或模块逻辑。单体/线性模块未传时完全沿用 definition 默认值。
local function EffectiveDefinition(definition, item)
    if item.appearance == nil and item.slots == nil then return definition end
    local effective = Copy(definition)
    effective.appearance = item.appearance or definition.appearance
    if item.slots then
        effective.slots = {}
        for id, spec in pairs(definition.slots or {}) do effective.slots[id] = Copy(spec) end
        for id, spec in pairs(item.slots) do
            local merged = Copy(effective.slots[id])
            for key, value in pairs(spec) do merged[key] = value end
            effective.slots[id] = merged
        end
    end
    return effective
end

local function StyleForIcon(appearance)
    local style = Copy(appearance)
    style.text = { countdown = { enabled = false }, stacks = { enabled = false }, label = { enabled = false } }
    return style
end

local function StyleForTimer(appearance)
    local style = Copy(appearance)
    if type(appearance and appearance.timerBar) == "table" then
        style.timerBar = Copy(appearance.timerBar)
    end
    style.text = { label = { enabled = false }, time = { enabled = false }, stacks = { enabled = false } }
    return style
end

local function CreateFixedText(item, roots, id, spec, text, shown, width, height, fallback)
    local element = { id = id, spec = spec, anchor = spec.anchor, fallback = fallback }
    element.text = AcquireText(item.root, spec.style, text)
    ApplyPreviewLayer(element.text, _G.EXPREVIEWCHILDFRAME, item.root)
    -- 运行时 Aura 的 FontString 只有在 fixedWidth/autoWidth=false 或 maxWidth>0
    -- 时才拥有固定文字框；默认 autoWidth 是以字形自身宽度锚定。此前一律塞入
    -- 图标宽高，LEFT/RIGHT 对齐就会把时间/层数整体推到图标边缘，和实际不符。
    local style = type(spec.style) == "table" and spec.style or {}
    local fixedWidth = tonumber(style.fixedWidth) or 0
    local fixedWidthEnabled = style.fixedWidthEnabled == true or style.autoWidth == false
    local maxWidth = tonumber(style.maxWidth) or 0
    if fixedWidthEnabled and fixedWidth > 0 then
        element.text:SetBounds(fixedWidth, height)
    elseif maxWidth > 0 then
        element.text:SetBounds(maxWidth, height)
    else
        element.text:ClearBounds()
    end
    ApplyAnchor(element.text, spec.anchor, roots, fallback)
    element.text:SetShown(shown == true)
    roots[id] = element.text
    item.elements[id] = element
end

local AttachHitbox

local function ApplyTextBounds(widget, style, fallbackWidth, fallbackHeight)
    style = type(style) == "table" and style or {}
    local fixedWidth = tonumber(style.fixedWidth) or 0
    local fixedWidthEnabled = style.fixedWidthEnabled == true or style.autoWidth == false
    local maxWidth = tonumber(style.maxWidth) or 0
    if fixedWidthEnabled and fixedWidth > 0 then
        widget:SetBounds(fixedWidth, fallbackHeight)
    elseif maxWidth > 0 then
        widget:SetBounds(maxWidth, fallbackHeight)
    else
        widget:ClearBounds()
    end
end

local function MaterializeChild(item, roots, declaration, data, fallback)
    local style = data and data.style or declaration.style
    -- Child 声明也必须遵守 visual-layer 合同。此前只有 collection decoration
    -- 会读取 declaration.layer，导致圆环这类挂在 icon item 上的背景 child 被
    -- 错当作 previewChild（高于 icon/Cooldown 的子 Frame）。
    local profile = declaration.layer == "background" and _G.EXBACKGROUNDFRAME or _G.EXPREVIEWCHILDFRAME
    -- `data.position` is the actual position passed to ApplyAnchor. Preserve it
    -- for dragging: the drag origin must be the rendered location, not the
    -- declaration's default anchor offset.
    local initialPosition = data and data.position or nil
    local element = {
        id = declaration.id,
        spec = declaration,
        anchor = declaration.anchor,
        fallback = fallback,
        position = {
            x = initialPosition and initialPosition.x or (declaration.anchor and declaration.anchor.x) or 0,
            y = initialPosition and initialPosition.y or (declaration.anchor and declaration.anchor.y) or 0,
        },
    }
    local shown = data == nil or data.shown ~= false
    if declaration.kind == "text" then
        if data and data.text ~= nil and type(data.text) ~= "string" and type(data.text) ~= "number" then
            Fail("child " .. declaration.id .. ".text must be string or number")
        end
        element.text = AcquireText(item.root, style, data and tostring(data.text or "") or "")
        ApplyPreviewLayer(element.text, profile, item.root)
        -- text child 同样是声明式几何：名称等业务文字不能被 Core 强行压成
        -- 本体尺寸，否则纵向图标预览会重叠，也无法与世界编辑同源。
        local width = data and data.width or declaration.width or item.widget:GetWidth()
        local height = data and data.height or declaration.height or item.widget:GetHeight()
        if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
            Fail("text child " .. declaration.id .. " width/height must be positive number")
        end
        ApplyTextBounds(element.text, style, width, height)
        ApplyAnchor(element.text, declaration.anchor, roots, fallback, initialPosition)
        element.text:SetShown(shown)
    else
        local region = EXFactory:Acquire(REGION_POOL, item.root)
        EnsureRegion(region)
        ApplyPreviewLayer(region, profile, item.root)
        -- Region 是 pooled child Frame；其 texture 也要每次重套层级，不能沿用
        -- 上一个借用者留下的 DrawLayer。
        ApplyPreviewLayer(region._texture, profile, region)
        element.region = region
        local width = data and data.width or declaration.width or 16
        local height = data and data.height or declaration.height or 16
        if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
            Fail("child " .. declaration.id .. " width/height must be positive number")
        end
        region:SetSize(width, height)
        ApplyAnchor(region, declaration.anchor, roots, fallback, initialPosition)
        if declaration.kind == "atlas" and shown then
            local atlas = data and data.atlas
            if type(atlas) ~= "string" or atlas == "" then Fail("atlas child " .. declaration.id .. " requires data.atlas") end
            -- 标准尺寸语义：region 的 width/height 来自模型优先、声明其次；
            -- Atlas 只提供图像内容，绝不以其原始尺寸覆写声明式几何。
            region._texture:SetAtlas(atlas, false)
            region._texture:ClearAllPoints()
            region._texture:SetAllPoints(region)
        elseif declaration.kind == "texture" and shown then
            local texture = data and data.texture
            if texture == nil then Fail("texture child " .. declaration.id .. " requires data.texture") end
            region._texture:SetTexture(texture)
        elseif declaration.kind == "glow" and shown then
            local glowStyle = data and data.style or declaration.style
            if type(glowStyle) ~= "table" then Fail("glow child " .. declaration.id .. " requires declaration.style or data.style") end
            region._previewGlow = EXUI:CreateGlowWidget(region, glowStyle)
            region._previewGlow:SetAllPoints(region)
            ApplyPreviewLayer(region._previewGlow, _G.EXPREVIEWCHILDFRAME, item.root)
            if shown then region._previewGlow:ShowGlow() else region._previewGlow:HideGlow() end
            region._texture:Hide()
        end
        local color = data and data.color
        if color ~= nil then
            if type(color) ~= "table" then Fail("child " .. declaration.id .. ".color must be table") end
            region._texture:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, color.a == nil and 1 or color.a)
        end
        region._texture:SetShown(shown and declaration.kind ~= "glow")
        region:SetShown(shown)
    end
    roots[declaration.id] = ElementRoot(element)
    item.elements[declaration.id] = element
end

local function MaterializeExtraChildHost(item, roots, declaration, data, fallback)
    if not item.widget or type(item.widget.ConfigureExtraChildHost) ~= "function" then
        Fail("TimerBarWidget must provide ConfigureExtraChildHost")
    end
    local initialPosition = data and data.position or nil
    local anchor = Copy(declaration.anchor or {})
    anchor.x = initialPosition and initialPosition.x or anchor.x or 0
    anchor.y = initialPosition and initialPosition.y or anchor.y or 0
    local host = item.widget:ConfigureExtraChildHost(declaration.id, {
        anchor = anchor,
        width = declaration.width,
        height = declaration.height,
        shown = data == nil or data.shown ~= false,
    })
    local element = {
        id = declaration.id,
        spec = declaration,
        root = host,
        anchor = declaration.anchor,
        fallback = fallback,
        position = { x = anchor.x, y = anchor.y },
        isExtraChildHost = true,
    }
    roots[declaration.id] = host
    item.elements[declaration.id] = element
    item.extraChildHosts = item.extraChildHosts or {}
    item.extraChildHosts[declaration.id] = host
end

-- collection decoration 是标准预览的根级纯数据元素：它不属于任意 item，因而可以
-- 表达一组图标共用的轨道/背景。它和普通 child 共用 kind、样式、命中和对象池规则，
-- 只把锚点根替换为 collection layout；绝不接受 renderer、Frame 或函数注入。
local function MaterializeCollectionDecorations(preview, definition, model)
    if #(definition.collectionDecorations or {}) == 0 then return end
    local collection = {
        root = preview.layout,
        itemID = COLLECTION_ITEM_ID,
        elements = {},
        roots = { [COLLECTION_ROOT_ID] = preview.layout },
        isCollection = true,
    }
    local fallback = { point = "CENTER", relative = preview.layout, relativePoint = "CENTER" }

    for _, declaration in ipairs(definition.collectionDecorations) do
        local data = model.decorations[declaration.id]
        local element = { id = declaration.id, spec = declaration, anchor = declaration.anchor, fallback = fallback }
        local shown = data.shown ~= false
        local profile = declaration.layer == "background" and _G.EXBACKGROUNDFRAME or _G.EXPREVIEWCHILDFRAME
        if declaration.kind == "text" then
            element.text = AcquireText(preview.layout, declaration.style, tostring(data.text or ""))
            ApplyPreviewLayer(element.text, profile, preview.layout)
            local width = data.width or declaration.width or preview.layout:GetWidth()
            local height = data.height or declaration.height or preview.layout:GetHeight()
            if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
                Fail("collection text decoration " .. declaration.id .. " width/height must be positive number")
            end
            element.text:SetBounds(width, height)
            element.text:SetShown(shown)
        else
            local region = EXFactory:Acquire(REGION_POOL, preview.layout)
            EnsureRegion(region)
            ApplyPreviewLayer(region, profile, preview.layout)
            ApplyPreviewLayer(region._texture, profile, region)
            element.region = region
            local width = data.width or declaration.width or 16
            local height = data.height or declaration.height or 16
            if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
                Fail("collection decoration " .. declaration.id .. " width/height must be positive number")
            end
            region:SetSize(width, height)
            if declaration.kind == "atlas" and shown then
                region._texture:SetAtlas(data.atlas, false)
                region._texture:ClearAllPoints()
                region._texture:SetAllPoints(region)
            elseif declaration.kind == "texture" and shown then
                region._texture:SetTexture(data.texture)
            elseif declaration.kind == "glow" and shown then
                local glowStyle = data.style or declaration.style
                region._previewGlow = EXUI:CreateGlowWidget(region, glowStyle)
                region._previewGlow:SetAllPoints(region)
                ApplyPreviewLayer(region._previewGlow, profile, preview.layout)
                region._previewGlow:ShowGlow()
                region._texture:Hide()
            end
            local color = data.color
            if color ~= nil then
                if type(color) ~= "table" then Fail("collection decoration " .. declaration.id .. ".color must be table") end
                region._texture:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, color.a == nil and 1 or color.a)
            end
            region._texture:SetShown(shown and declaration.kind ~= "glow")
            region:SetShown(shown)
        end
        collection.roots[declaration.id] = ElementRoot(element)
        collection.elements[declaration.id] = element
    end
    for _, declaration in ipairs(definition.collectionDecorations) do
        local element = collection.elements[declaration.id]
        local data = model.decorations[declaration.id]
        ApplyAnchor(ElementRoot(element), element.anchor, collection.roots, fallback, data.position)
    end
    for _, element in pairs(collection.elements) do AttachHitbox(preview, collection, element) end
    preview.collection = collection
end

local function ValidateActual(definition, item)
    local expected, actual = {}, {}
    for id in pairs(FIXED[definition.kind]) do expected[id] = true end
    for _, child in ipairs(definition.children or {}) do expected[child.id] = true end
    for _, host in ipairs(definition.extraChildHosts or {}) do expected[host.id] = true end
    for id in pairs(item.elements) do actual[id] = true end
    for id in pairs(expected) do if not actual[id] then Fail("item " .. item.itemID .. " did not materialize required element " .. id) end end
    for id in pairs(actual) do if not expected[id] then Fail("item " .. item.itemID .. " materialized undeclared element " .. id) end end
end

local function SetHitboxVisual(hitbox, state)
    hitbox:SetScale(state == "pressed" and 0.96 or 1)
    if state == "pressed" or state == "dragging" then
        hitbox:SetBackdropBorderColor(1, 0.82, 0.12, 0.98); hitbox:SetBackdropColor(1, 0.72, 0.08, 0.18)
    elseif state == "selected" then
        hitbox:SetBackdropBorderColor(1, 0.82, 0.12, 0.95); hitbox:SetBackdropColor(1, 0.72, 0.08, 0.10)
    elseif state == "hover" then
        hitbox:SetBackdropBorderColor(0.35, 0.82, 1, 0.90); hitbox:SetBackdropColor(0.20, 0.66, 1, 0.08)
    else
        hitbox:SetBackdropBorderColor(0.35, 0.82, 1, 0); hitbox:SetBackdropColor(0.20, 0.66, 1, 0)
    end
end

local function IsSelected(preview, itemID, elementID)
    local selected = preview.interaction and preview.interaction.selected
    return selected and selected.itemID == itemID and selected.elementID == elementID
end

local function SetPhase(preview, phase)
    preview.interaction.phase = phase
end

local function SetSelection(preview, itemID, elementID)
    preview.interaction.selected = { itemID = itemID, elementID = elementID }
    for _, item in ipairs(preview.items) do
        for _, element in pairs(item.elements) do
            if element.hitbox then
                SetHitboxVisual(element.hitbox, IsSelected(preview, item.itemID, element.id) and "selected" or "idle")
            end
        end
    end
    if preview.collection then
        for _, element in pairs(preview.collection.elements) do
            if element.hitbox then
                SetHitboxVisual(element.hitbox, IsSelected(preview, preview.collection.itemID, element.id) and "selected" or "idle")
            end
        end
    end
end

-- 独立 hitbox 必须匹配最终可见 Region，而不是 TextWidget 为对齐而保留的整条 Bounds。
-- 文字的实际字形矩形由 TextWidget 公开 metrics 提供；Region 则直接双点贴合目标。
local function MatchHitboxToElement(hitbox, element)
    local root = ElementRoot(element)
    if not root then Fail("element " .. element.id .. " has no root for hitbox") end
    hitbox:ClearAllPoints()
    if element.text then
        local metrics = element.text:GetVisualMetrics()
        local rootWidth, rootHeight = math.max(1, root:GetWidth() or 1), math.max(1, root:GetHeight() or 1)
        local justifyH = tostring(metrics.justifyH or "LEFT"):upper()
        local justifyV = tostring(metrics.justifyV or "MIDDLE"):upper()
        local offsetX, offsetY = 0, 0
        if justifyH == "LEFT" then
            offsetX = -rootWidth / 2 + metrics.width / 2
        elseif justifyH == "RIGHT" then
            offsetX = rootWidth / 2 - metrics.width / 2
        end
        if justifyV == "TOP" then
            offsetY = rootHeight / 2 - metrics.height / 2
        elseif justifyV == "BOTTOM" then
            offsetY = -rootHeight / 2 + metrics.height / 2
        end
        hitbox:SetSize(metrics.width, metrics.height)
        hitbox:SetPoint("CENTER", root, "CENTER", offsetX, offsetY)
    else
        hitbox:SetPoint("TOPLEFT", root, "TOPLEFT")
        hitbox:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT")
    end
end

local function RefreshItemHitboxes(item, preview)
    for _, element in pairs(item.elements) do
        local root = ElementRoot(element)
        local shouldHaveHitbox = preview and preview.interactionMode == "panel"
            and (element.spec.movable == true or element.spec.focusable == true)
            and root and (not root.IsShown or root:IsShown())
        if preview and shouldHaveHitbox and not element.hitbox then
            AttachHitbox(preview, item, element)
        elseif preview and not shouldHaveHitbox and element.hitbox then
            ReleaseHitbox(element.hitbox)
            element.hitbox = nil
        elseif element.hitbox then
            MatchHitboxToElement(element.hitbox, element)
        end
    end
end

local function ApplyTransientPosition(item, element, position)
    -- Icon/TimerBar 的本体固定在 slot 中心；材质本体则已经由
    -- MaterialPresentation.anchor 定义局部位置。拖动其文字 child 时若强制
    -- CenterFixedBody，会覆盖材质锚点并造成贴图跟随文字跳动。
    if item.widget and item.kind ~= "material" then
        CenterFixedBody(item)
        ApplyFixedElementAnchors(item)
    end
    local root = ElementRoot(element)
    ApplyAnchor(root, element.anchor, item.roots, element.fallback, position)
    element.position = { x = position.x, y = position.y }
    RefreshItemHitboxes(item)
end

local function CancelActiveInteraction(preview)
    local active = preview.interaction.active
    if not active then return end
    if active.hitbox then
        active.hitbox:SetScript("OnUpdate", nil)
        if GameTooltip and GameTooltip:GetOwner() == active.hitbox then GameTooltip:Hide() end
    end
    preview.interaction.active = nil
    if preview.interaction.selected then
        SetPhase(preview, "selected")
    else
        SetPhase(preview, "idle")
    end
end

local function FinishActiveInteraction(preview, emitMove)
    local active = preview.interaction.active
    if not active then return end
    active.hitbox:SetScript("OnUpdate", nil)
    preview.interaction.active = nil
    if active.dragging and emitMove then
        -- released 是可审计的明确生命周期节点；intent 只在最终位置发一次。
        SetPhase(preview, "released")
        local intent = {
            type = "elementMoved", itemID = active.item.itemID, elementID = active.element.id,
            position = { x = active.position.x, y = active.position.y },
        }
        if active.item.isCollection then intent.scope = "collection" end
        -- onIntent 可以同步刷新整个页面预览；刷新会 Release 并立即复用所有
        -- hitbox。回调之后绝不能再读取或重画 active.hitbox，否则会把旧元素
        -- 的选中状态写到一个新元素上（截图中的“选第三个，最上面也被选中”）。
        local epoch = preview.materializationEpoch
        if GameTooltip and GameTooltip:GetOwner() == active.hitbox then GameTooltip:Hide() end
        preview.onIntent(intent)
        if preview.materializationEpoch ~= epoch then return end
    end
    SetPhase(preview, preview.interaction.selected and "selected" or "idle")
    if active.hitbox and active.hitbox:IsShown() then
        SetHitboxVisual(active.hitbox, IsSelected(preview, active.item.itemID, active.element.id) and "selected" or "idle")
    end
end

local function UpdateActiveInteraction(preview)
    local active = preview.interaction.active
    if not active then return end
    if not IsMouseButtonDown("LeftButton") then
        FinishActiveInteraction(preview, true)
        return
    end
    local cursorX, cursorY = GetCursorPosition()
    -- hitbox 在 pressed / dragging 状态会缩放作视觉反馈；绝不能拿它自己的
    -- EffectiveScale 作为坐标系，否则按下后一帧会把同一个屏幕像素换算成另一个
    -- UI 坐标并制造伪 delta。dragScale 只在按下时由稳定 host 捕获一次。
    cursorX, cursorY = cursorX / active.dragScale, cursorY / active.dragScale
    local deltaX, deltaY = cursorX - active.cursorX, cursorY - active.cursorY
    if not active.dragging then
        if math.abs(deltaX) < preview.dragThreshold and math.abs(deltaY) < preview.dragThreshold then return end
        active.dragging = true
        SetPhase(preview, "dragging")
    end
    active.position.x = active.startX + deltaX
    active.position.y = active.startY + deltaY
    ApplyTransientPosition(active.item, active.element, active.position)
    SetHitboxVisual(active.hitbox, "dragging")
end

AttachHitbox = function(preview, item, element)
    if preview.interactionMode ~= "panel" then return end
    if element.spec.movable ~= true and element.spec.focusable ~= true then return end
    local root = ElementRoot(element)
    if not root then Fail("element " .. element.id .. " has no root for hitbox") end
    if root.IsShown and not root:IsShown() then return end
    local hitbox = EXFactory:Acquire(HITBOX_POOL, item.root)
    ApplyPreviewLayer(hitbox, _G.EXPREVIEWEDITORFRAME, item.root)
    -- FramePool 的通用 Button 复位只保证 LeftButtonUp。标准面板右键是正式
    -- intent，故每次借用都显式注册 Down/Up，不能依赖池的历史状态。
    hitbox:EnableMouse(true)
    hitbox:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    hitbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    MatchHitboxToElement(hitbox, element)
    hitbox._preview = { preview = preview, item = item, element = element }
    hitbox:SetScript("OnEnter", function(self)
        if preview.interaction.active == nil and not IsSelected(preview, item.itemID, element.id) then SetHitboxVisual(self, "hover") end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(element.spec.tooltip or (L["子元素："] .. element.id), 1, 0.82, 0)
            if element.spec.movable == true then
                GameTooltip:AddLine(L["左键拖动位置；右键定位设置"], 0.7, 0.9, 1)
            else
                GameTooltip:AddLine(L["右键定位设置"], 0.7, 0.9, 1)
            end
            GameTooltip:Show()
        end
    end)
    hitbox:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        if preview.interaction.active == nil then
            SetHitboxVisual(self, IsSelected(preview, item.itemID, element.id) and "selected" or "idle")
        end
    end)
    hitbox:SetScript("OnMouseDown", function(self, button)
        local info = self._preview
        SetSelection(preview, info.item.itemID, info.element.id)
        if button == "RightButton" then
            SetPhase(preview, "selected")
            local intent = { type = "elementRightClicked", itemID = info.item.itemID, elementID = info.element.id, guiTarget = element.spec.guiTarget or element.id }
            if info.item.isCollection then intent.scope = "collection" end
            preview.onIntent(intent)
            return
        end
        if button ~= "LeftButton" then return end
        -- focusable-only 元素也完成了选取；它没有拖动生命周期，必须显式进入
        -- selected，不能把已选中的黄色视觉留在 idle 状态。
        if element.spec.movable ~= true then
            SetPhase(preview, "selected")
            return
        end
        CancelActiveInteraction(preview)
        -- 触控屏宿主的 scale 在一次拖动生命周期内是唯一坐标基准。不能读取
        -- hitbox scale：SetHitboxVisual("pressed") 会有意把它缩至 0.96。
        local dragScale = preview.host:GetEffectiveScale() or 1
        if dragScale <= 0 then Fail("preview host effective scale must be positive") end
        local x, y = GetCursorPosition()
        preview.interaction.active = {
            hitbox = self,
            item = item,
            element = element,
            dragScale = dragScale,
            cursorX = x / dragScale,
            cursorY = y / dragScale,
            startX = element.position and element.position.x or (element.anchor and element.anchor.x) or 0,
            startY = element.position and element.position.y or (element.anchor and element.anchor.y) or 0,
            position = {
                x = element.position and element.position.x or (element.anchor and element.anchor.x) or 0,
                y = element.position and element.position.y or (element.anchor and element.anchor.y) or 0,
            },
            dragging = false,
        }
        SetPhase(preview, "pressed")
        SetHitboxVisual(self, "pressed")
        self:SetScript("OnUpdate", function() UpdateActiveInteraction(preview) end)
    end)
    hitbox:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then FinishActiveInteraction(preview, true) end
    end)
    SetHitboxVisual(hitbox, IsSelected(preview, item.itemID, element.id) and "selected" or "idle")
    hitbox:Show()
    element.hitbox = hitbox
end

local function MaterializeItem(preview, definition, modelItem)
    definition = EffectiveDefinition(definition, modelItem)
    local root = EXFactory:Acquire(ITEM_POOL, preview.layout)
    root:EnableMouse(false)
    ApplyPreviewLayer(root, _G.EXPREVIEWBODYFRAME, preview.layout)
    local item = { root = root, itemID = modelItem.itemID, kind = definition.kind, elements = {} }
    root.__EXUIStandardPreviewPosition = modelItem.position
    local name, icon = ResolveContent(modelItem)
    if definition.kind == "icon" then
        item.widget = EXUI:CreateIconWidget(root, StyleForIcon(definition.appearance))
        item.widget:SetIcon(icon)
        if modelItem.duration then item.widget:SetStaticCooldown(modelItem.remaining, modelItem.duration) else item.widget:ClearCooldown() end
    elseif definition.kind == "timerbar" then
        item.widget = EXUI:CreateTimerBarWidget(root, StyleForTimer(definition.appearance))
        item.widget:SetIcon(icon)
        item.widget:SetLabel(nil)
        if modelItem.progressValue ~= nil then
            item.widget:SetProgress(modelItem.progressValue, modelItem.progressMaximum)
        elseif modelItem.duration then
            local timerStyle = definition.appearance and definition.appearance.timerBar or definition.appearance or {}
            local progressMode = tostring(timerStyle.progressMode or "REMAINING"):upper()
            local value = progressMode == "ELAPSED" and (modelItem.duration - modelItem.remaining) or modelItem.remaining
            item.widget:SetProgress(value, modelItem.duration)
        else
            item.widget:SetProgress(1, 1)
        end
    else
        local declaration = definition.children and definition.children[1]
        local data = declaration and modelItem.elements and modelItem.elements[declaration.id]
        if not declaration or not data then Fail("material preview requires declared material body") end
        item.widget = EXUI:CreateExtraTextureWidget(root)
        item.widget:ApplyPresentation(MaterialWidgetPresentation(data.material))
    end
    ApplyPreviewLayer(item.widget, _G.EXPREVIEWBODYFRAME, root)
    CenterFixedBody(item)
    -- 子元素可以越出图标/条本体。布局格的尺寸是声明式模型的一部分；这样多项
    -- 纵向排列和 autoSizeHost 不会忽略名称、材质等真实占用空间。未声明时保持
    -- 旧的“本体尺寸即格尺寸”标准默认值。
    local itemWidth = definition.layout and definition.layout.itemWidth or item.widget:GetWidth()
    local itemHeight = definition.layout and definition.layout.itemHeight or item.widget:GetHeight()
    root:SetSize(itemWidth, itemHeight)

    local roots = {}
    item.roots = roots
    local fallback
    if definition.kind == "icon" then
        roots["core.icon"], roots["core.cooldown"] = item.widget, item.widget
        -- `core.layout` 是 item slot 的声明式布局根，不是一个第二套视觉控件。
        -- 允许模块把完整 IconWidget 作为可移动的 core.icon，同时让名称等
        -- 子元素仍锚在固定的预览中心；默认模块不使用这个别名，行为不变。
        roots["core.layout"] = root
        fallback = { point = "CENTER", relative = item.widget, relativePoint = "CENTER" }
        local timeSpec = FixedSpec(definition, "core.time", FIXED.icon["core.time"])
        local stacksSpec = FixedSpec(definition, "core.stacks", FIXED.icon["core.stacks"])
        CreateFixedText(item, roots, "core.time", timeSpec, modelItem.duration and (modelItem.timeText or EXUI:FormatCountdown(modelItem.remaining)) or "", modelItem.duration ~= nil and timeSpec.shown ~= false, item.widget:GetWidth(), item.widget:GetHeight(), fallback)
        CreateFixedText(item, roots, "core.stacks", stacksSpec, modelItem.stacks and tostring(modelItem.stacks) or "", modelItem.stacks ~= nil and stacksSpec.shown ~= false, item.widget:GetWidth(), item.widget:GetHeight(), fallback)
        local iconSpec = FixedSpec(definition, "core.icon", FIXED.icon["core.icon"])
        local iconAnchor = iconSpec.anchor
        local iconPosition = {
            x = iconAnchor and iconAnchor.x or 0,
            y = iconAnchor and iconAnchor.y or 0,
        }
        item.elements["core.icon"] = {
            id = "core.icon", spec = iconSpec, root = item.widget,
            anchor = iconAnchor, position = iconPosition,
        }
        item.widget:SetShown(iconSpec.shown ~= false)
        item.elements["core.cooldown"] = { id = "core.cooldown", spec = FIXED.icon["core.cooldown"], root = item.widget }
    elseif definition.kind == "timerbar" then
        if type(item.widget.GetFixedElementRoot) ~= "function" then
            Fail("TimerBarWidget must provide GetFixedElementRoot")
        end
        -- 计时条的完整 Widget 是运行时 leftDecorationsLayer 的几何宿主：它包含
        -- 外置图标，因此不能用 core.bar 或 core.icon 代替。这里仅公开标准语义根，
        -- 不暴露 Widget 私有 Region；模块子元素可与运行时使用同一参照物。
        roots["core.layout"] = item.widget
        roots["core.bar"] = item.widget:GetFixedElementRoot("bar")
        roots["core.icon"] = item.widget:GetFixedElementRoot("icon")
        if not roots["core.bar"] or not roots["core.icon"] then
            Fail("TimerBarWidget fixed element root is unavailable")
        end
        fallback = { point = "CENTER", relative = item.widget, relativePoint = "CENTER" }
        local spellNameSpec = FixedSpec(definition, "core.spellName", FIXED.timerbar["core.spellName"])
        local targetNameSpec = FixedSpec(definition, "core.targetName", FIXED.timerbar["core.targetName"])
        local timeSpec = FixedSpec(definition, "core.time", FIXED.timerbar["core.time"])
        local barWidth, barHeight = roots["core.bar"]:GetWidth(), roots["core.bar"]:GetHeight()
        CreateFixedText(item, roots, "core.spellName", spellNameSpec, name, spellNameSpec.shown ~= false, barWidth, barHeight, fallback)
        CreateFixedText(item, roots, "core.targetName", targetNameSpec, modelItem.targetName or "", targetNameSpec.shown ~= false and modelItem.targetName ~= nil and modelItem.targetName ~= "", barWidth, barHeight, fallback)
        CreateFixedText(item, roots, "core.time", timeSpec, modelItem.duration and (modelItem.timeText or EXUI:FormatCountdown(modelItem.remaining)) or "", modelItem.duration ~= nil and timeSpec.shown ~= false, barWidth, barHeight, fallback)
        item.elements["core.bar"] = { id = "core.bar", spec = FIXED.timerbar["core.bar"], root = roots["core.bar"] }
        item.elements["core.icon"] = { id = "core.icon", spec = FIXED.timerbar["core.icon"], root = roots["core.icon"] }
    else
        local declaration = definition.children[1]
        local data = modelItem.elements[declaration.id]
        roots["core.layout"] = root
        roots[declaration.id] = item.widget
        fallback = { point = "CENTER", relative = root, relativePoint = "CENTER" }
        ApplyMaterialBody(item, declaration, data)
    end
    if definition.kind ~= "material" then
        for _, child in ipairs(definition.children or {}) do MaterializeChild(item, roots, child, modelItem.elements and modelItem.elements[child.id], fallback) end
        for _, host in ipairs(definition.extraChildHosts or {}) do
            MaterializeExtraChildHost(item, roots, host, modelItem.extraChildren and modelItem.extraChildren[host.id], fallback)
        end
    else
        -- A material has one public texture body and may declare text or
        -- texture annotation children.  The latter is an edit-safe projection
        -- for attached icon/progress content; actual panel/runtime widgets stay
        -- owned by the business renderer.  Every child still shares the normal
        -- preview path so drag hitboxes and config intents remain Core-owned.
        for index = 2, #(definition.children or {}) do
            local child = definition.children[index]
            MaterializeChild(item, roots, child, modelItem.elements and modelItem.elements[child.id], fallback)
        end
    end
    if #(definition.extraChildHosts or {}) > 0 then
        if type(preview.renderExtraChildren) ~= "function" then
            Fail("definition.extraChildHosts requires renderExtraChildren option")
        end
        preview.renderExtraChildren(item.widget, item.extraChildHosts, modelItem.extraChildren or {}, preview.interactionMode)
    end
    -- core.icon 默认由 CenterFixedBody 放在 item slot 中心；如果模块声明了
    -- 一个依赖文字 child 的正式 anchor，此处在所有 child 已物化后再应用，
    -- 避免为满足顺序而创建第二个图标或手工复制 IconWidget 内部区域。
    local coreIcon = item.elements["core.icon"]
    if definition.kind == "icon" and coreIcon and coreIcon.anchor then
        ApplyFixedElementAnchors(item)
    end
    ValidateActual(definition, item)
    for _, element in pairs(item.elements) do AttachHitbox(preview, item, element) end
    return item
end

local function ClearPreview(preview, keepSelection)
    CancelActiveInteraction(preview)
    preview.materializationEpoch = preview.materializationEpoch + 1
    ReleaseCollectionDecorations(preview)
    for _, item in ipairs(preview.items) do ReleaseItem(item) end
    preview.items = {}
    preview.definition, preview.model = nil, nil
    if not keepSelection then
        preview.interaction.selected = nil
        SetPhase(preview, "idle")
    end
    if preview.layout then preview.layout:Clear() end
end

function EXUI:CreateStandardPreview(host, options)
    -- CreateFrame 是全局构造函数，不是 Frame 实例的方法。标准预览宿主必须是
    -- 真正的基础 Frame；仅有同名 GetObjectType 方法的伪表、Texture、FontString
    -- 或其他 Region 都不能作为对象池、布局与子元素的父级。
    if not host or type(host.GetObjectType) ~= "function" or host:GetObjectType() ~= "Frame" then
        Fail("host must be Frame")
    end
    options = options or {}
    if options.interactionMode ~= nil and options.interactionMode ~= "panel" and options.interactionMode ~= "world" then
        Fail("options.interactionMode must be panel or world")
    end
    if options.worldAnchorMode ~= nil and options.worldAnchorMode ~= "content-center" and options.worldAnchorMode ~= "semantic-root" then
        Fail("options.worldAnchorMode must be content-center or semantic-root")
    end
    if options.worldAnchorMode ~= nil and (options.interactionMode or "world") ~= "world" then
        Fail("options.worldAnchorMode is only valid for world previews")
    end
    if options.interactionMode == "panel" and type(options.onIntent) ~= "function" then Fail("panel preview requires options.onIntent callback") end
    if options.autoSizeHost ~= nil and type(options.autoSizeHost) ~= "boolean" then Fail("options.autoSizeHost must be boolean") end
    if options.autoSizeHostWidth ~= nil and type(options.autoSizeHostWidth) ~= "boolean" then Fail("options.autoSizeHostWidth must be boolean") end
    if options.hostPadding ~= nil and (type(options.hostPadding) ~= "number" or options.hostPadding < 0) then Fail("options.hostPadding must be non-negative number") end
    if options.minHostHeight ~= nil and (type(options.minHostHeight) ~= "number" or options.minHostHeight <= 0) then
        Fail("options.minHostHeight must be positive number")
    end
    if options.minHostHeight ~= nil and (options.interactionMode or "world") ~= "panel" then
        Fail("options.minHostHeight is only valid for panel previews")
    end
    if options.panelContentAlignment ~= nil and options.panelContentAlignment ~= "center" and options.panelContentAlignment ~= "left" then
        Fail("options.panelContentAlignment must be center or left")
    end
    if options.panelContentInset ~= nil and (type(options.panelContentInset) ~= "number" or options.panelContentInset < 0) then
        Fail("options.panelContentInset must be non-negative number")
    end
    if options.dragThreshold ~= nil and (type(options.dragThreshold) ~= "number" or options.dragThreshold < 0) then Fail("options.dragThreshold must be non-negative number") end
    if options.renderExtraChildren ~= nil and type(options.renderExtraChildren) ~= "function" then
        Fail("options.renderExtraChildren must be function")
    end
    local preview = {
        host = host,
        items = {},
        interactionMode = options.interactionMode or "world",
        worldAnchorMode = options.worldAnchorMode or "content-center",
        onIntent = options.onIntent,
        autoSizeHost = options.autoSizeHost == true,
        autoSizeHostWidth = options.autoSizeHostWidth == true,
        hostPadding = options.hostPadding or 0,
        minHostHeight = options.minHostHeight or ((options.interactionMode or "world") == "panel" and DEFAULT_PANEL_MIN_HOST_HEIGHT or 0),
        panelContentAlignment = options.panelContentAlignment or "center",
        panelContentInset = options.panelContentInset or 0,
        dragThreshold = options.dragThreshold or 4,
        renderExtraChildren = options.renderExtraChildren,
        -- 面板是唯一交互状态所有者。hitbox 只保存对当前元素的局部引用，绝不
        -- 维护第二份拖动/选取状态，更不持有模块 DB 或页面状态。
        interaction = { phase = "idle", selected = nil, active = nil },
        materializationEpoch = 0,
        width = 1,
        height = 1,
    }
    preview.layout = EXUI:CreateWidgetLayout(host, DEFAULT_LAYOUT)

    function preview:Materialize(definition, model)
        -- GetLeft/GetRight 只能可靠地反映已显示的世界 Frame。world materialize 的
        -- 语义本来就是“显示编辑样本”，因此先显示宿主以便把实际 Region 包络纳入
        -- AnchorController；panel 宿主的显隐仍完全由页面管理。
        if self.interactionMode == "world" then
            self.host:Show()
            SetWorldEditState(self, true)
        end
        ClearPreview(self, true)
        local definitionSnapshot = SnapshotPlain(definition, "definition")
        local modelSnapshot = SnapshotPlain(model, "model")
        ValidateDefinition(definitionSnapshot)
        ValidateModel(definitionSnapshot, modelSnapshot)
        self.definition, self.model = definitionSnapshot, modelSnapshot
        local ordered = {}
        for _, entry in ipairs(modelSnapshot.items) do ordered[#ordered + 1] = entry end
        table.sort(ordered, function(a, b) return a.order < b.order end)
        for _, entry in ipairs(ordered) do self.items[#self.items + 1] = MaterializeItem(self, definitionSnapshot, entry) end
        if self.interaction.selected then
            local found = false
            for _, item in ipairs(self.items) do
                for _, element in pairs(item.elements) do
                    if element.hitbox and IsSelected(self, item.itemID, element.id) then found = true end
                end
            end
            if not found then
                self.interaction.selected = nil
                SetPhase(self, "idle")
            elseif self.interaction.active == nil then
                -- elementMoved callback 可同步 Materialize；旧 hitbox 已不能在
                -- callback 后访问，故由新 materialize 的有效 selected 统一收口
                -- released → selected，不能把状态永久停在 released。
                SetPhase(self, "selected")
            end
        end
        self.layout:ApplyStyle(definitionSnapshot.layout or DEFAULT_LAYOUT)
        local roots = {}
        for _, item in ipairs(self.items) do roots[#roots + 1] = item.root end
        local width, height = 1, 1
        if #self.items > 0 then width, height = self.items[1].root:GetWidth(), self.items[1].root:GetHeight() end
        if definitionSnapshot.layout and definitionSnapshot.layout.semanticFirstItem == true then
            -- TimerBar 等语义集合保存的是首项本体的位置。增长布局只能移动后续
            -- item，不能依可见包络重算并移动首项。
            self.layout:SetSemanticItems(roots, width, height)
        else
            self.layout:SetItems(roots, width, height)
        end
        -- 预览 collection 在两个宿主都以中心放置。direction 只定义 items 之间
        -- 的排列次序，绝不能让世界编辑模式从 anchor 中点只向一侧长出、造成一半
        -- 内容落在 AnchorController 的可点范围外。每个固定条/图标本体仍在 slot 中心。
        self.layout:SetParent(self.host)
        self.layout:ClearAllPoints()
        self.layout:SetPoint("CENTER", self.host, "CENTER", self.worldContentOffsetX or 0, self.worldContentOffsetY or 0)
        for _, item in ipairs(self.items) do
            CenterFixedBody(item)
            ApplyFixedElementAnchors(item)
            RefreshItemHitboxes(item, self)
        end
        MaterializeCollectionDecorations(self, definitionSnapshot, modelSnapshot)
        -- 同一次 materialize 的内容并集同时供 world 尺寸和 panel 对齐使用。
        -- 不能只在某个分支局部声明，否则 panel 的 left 对齐会读取到 nil。
        local envelope = ResolveWorldEnvelope(self)
        if self.interactionMode == "world" then
            -- 标准世界预览只标记 aggregate host；AnchorController 在本次 materialize
            -- 返回后，以同一个 host 和普通模块标题显示唯一 VisualLayers 前景层。
            -- 唯一鼠标所有者仍是 anchorFrame，自身不创建任何 hitbox。
            SetWorldEditState(self, true)
            self.worldBounds = envelope
            self.width, self.height = self.worldBounds.width, self.worldBounds.height
            if self.worldAnchorMode == "semantic-root" then
                -- 有些声明的根原点不是内容并集中心（AuraContainer 的
                -- TOPLEFT 就锚在群组根 CENTER）。这种世界投影必须保留
                -- Provider 声明的语义原点，不能再被标准渲染器自动居中。
                self.worldContentOffsetX, self.worldContentOffsetY = 0, 0
            else
                self.host:SetSize(self.width, self.height)
                self.worldContentOffsetX = self.worldBounds.contentOffsetX
                self.worldContentOffsetY = self.worldBounds.contentOffsetY
            end
            self.layout:ClearAllPoints()
            self.layout:SetPoint("CENTER", self.host, "CENTER", self.worldContentOffsetX, self.worldContentOffsetY)
        else
            -- panel 也必须把 collection/root decoration 计入实际内容尺寸；否则
            -- 共享轨道材质会在内容少时被 dock 裁切，形成 panel/world 不同源。
            self.width, self.height = envelope.width, envelope.height
        end
        if self.interactionMode ~= "world" then
            -- 所有标准 panel 的真实 dock 都必须保留最低可见高度，而不是只有
            -- autoSizeHost 的页面才生效。autoSizeHost 额外按内容自然扩展；其余
            -- panel 仅在外部 dock 低于标准下限时抬高它。world 永不走此路径。
            local requiredHeight = self.minHostHeight
            if self.autoSizeHost then
                requiredHeight = math.max(requiredHeight, self.height + self.hostPadding * 2)
            end
            if self.host:GetHeight() < requiredHeight then
                self.host:SetHeight(requiredHeight)
            end
            -- panel 预览默认维持本体居中。少数纵向集合的真实内容会因右侧文字
            -- 形成非对称 union；它们可显式请求按 union 左边贴合宿主，而不是靠
            -- 模块猜偏移量。该选项只影响 panel，不参与世界编辑或运行时 anchor。
            if self.autoSizeHostWidth then
                local requiredWidth = self.width + self.panelContentInset * 2
                if self.host:GetWidth() < requiredWidth then self.host:SetWidth(requiredWidth) end
            end
            if self.panelContentAlignment == "left" then
                local hostLeft, hostRight = self.host:GetLeft(), self.host:GetRight()
                if type(hostLeft) == "number" and type(hostRight) == "number" then
                    local hostCenterX = (hostLeft + hostRight) * 0.5
                    local unionCenterX = hostCenterX + (envelope.anchorOffsetX or 0)
                    local targetCenterX = hostLeft + self.panelContentInset + self.width * 0.5
                    self.layout:ClearAllPoints()
                    self.layout:SetPoint("CENTER", self.host, "CENTER", targetCenterX - unionCenterX, 0)
                end
            end
        end
        return self
    end

    function preview:Refresh(model)
        if not self.definition then Fail("Refresh requires prior Materialize") end
        return self:Materialize(self.definition, model)
    end

    -- 单静态样本的 Slider 只触碰已物化的 Region/FontString，不构造或替换
    -- 预览树。Panel 与 Core 拥有的 World 编辑预览共用这条在位重套契约。
    local function ReapplyDeclaredChild(item, declaration, data)
        local element = item.elements and item.elements[declaration.id]
        if not element then return false end
        local shown = data == nil or data.shown ~= false
        element.spec, element.anchor = declaration, declaration.anchor
        element.position = {
            x = data and data.position and data.position.x or (declaration.anchor and declaration.anchor.x) or 0,
            y = data and data.position and data.position.y or (declaration.anchor and declaration.anchor.y) or 0,
        }
        if declaration.kind == "text" then
            if not element.text then return false end
            local style = data and data.style or declaration.style
            local width = data and data.width or declaration.width or item.widget:GetWidth()
            local height = data and data.height or declaration.height or item.widget:GetHeight()
            element.text:ApplyStyle(PreviewTextStyle(style))
            element.text:SetText(data and tostring(data.text or "") or "")
            ApplyTextBounds(element.text, style, width, height)
            ApplyAnchor(element.text, declaration.anchor, item.roots, element.fallback,
                data and data.position or nil)
            element.text:SetShown(shown)
            return true
        end
        if declaration.kind ~= "texture" or not element.region then return false end
        local width = data and data.width or declaration.width or 16
        local height = data and data.height or declaration.height or 16
        element.region:SetSize(width, height)
        ApplyAnchor(element.region, declaration.anchor, item.roots, element.fallback,
            data and data.position or nil)
        element.region._texture:SetTexture(data and data.texture or nil)
        local color = data and data.color or nil
        if color then
            element.region._texture:SetVertexColor(
                color.r or 1, color.g or 1, color.b or 1, color.a == nil and 1 or color.a)
        else
            element.region._texture:SetVertexColor(1, 1, 1, 1)
        end
        element.region._texture:SetShown(shown)
        element.region:SetShown(shown)
        return true
    end

    local function ReapplyFixedText(item, id, spec, text, shown, width, height)
        local element = item.elements and item.elements[id]
        if not element or not element.text then return false end
        element.spec, element.anchor = spec, spec.anchor
        element.position = {
            x = spec.anchor and spec.anchor.x or 0,
            y = spec.anchor and spec.anchor.y or 0,
        }
        element.text:ApplyStyle(PreviewTextStyle(spec.style))
        element.text:SetText(tostring(text or ""))
        ApplyTextBounds(element.text, spec.style, width, height)
        ApplyAnchor(element.text, spec.anchor, item.roots, element.fallback)
        element.text:SetShown(shown == true)
        return true
    end

    local function ApplyReappliedMaterialBounds(target, envelope)
        target.width, target.height = envelope.width, envelope.height
        if target.interactionMode ~= "world" then return end

        SetWorldEditState(target, true)
        target.worldBounds = envelope
        if target.worldAnchorMode == "semantic-root" then
            target.worldContentOffsetX, target.worldContentOffsetY = 0, 0
        else
            target.host:SetSize(target.width, target.height)
            target.worldContentOffsetX = target.worldBounds.contentOffsetX
            target.worldContentOffsetY = target.worldBounds.contentOffsetY
        end
        target.layout:ClearAllPoints()
        target.layout:SetPoint("CENTER", target.host, "CENTER", target.worldContentOffsetX, target.worldContentOffsetY)
    end

    function preview:ReapplyCurrentMaterial(definition, model)
        if (self.interactionMode ~= "panel" and self.interactionMode ~= "world") or not self.definition or not self.model
            or #self.items ~= 1 or self.released then
            return false
        end
        local definitionSnapshot = SnapshotPlain(definition, "definition")
        local modelSnapshot = SnapshotPlain(model, "model")
        ValidateDefinition(definitionSnapshot)
        ValidateModel(definitionSnapshot, modelSnapshot)
        if (definitionSnapshot.kind ~= "icon" and definitionSnapshot.kind ~= "material")
            or self.definition.kind ~= definitionSnapshot.kind
            or #(definitionSnapshot.children or {}) ~= #(self.definition.children or {})
            or #(definitionSnapshot.collectionDecorations or {}) ~= 0
            or #(self.definition.collectionDecorations or {}) ~= 0
            or #(modelSnapshot.items or {}) ~= 1 then
            return false
        end
        local modelItem = modelSnapshot.items[1]
        local item = self.items[1]
        if not item or item.itemID ~= modelItem.itemID or self.model.items[1].itemID ~= modelItem.itemID
            or self.model.items[1].order ~= modelItem.order then
            return false
        end
        if definitionSnapshot.kind == "material" then
            local declaration = definitionSnapshot.children and definitionSnapshot.children[1]
            local previous = self.definition.children and self.definition.children[1]
            local data = declaration and modelItem.elements and modelItem.elements[declaration.id]
            local element = declaration and item.elements and item.elements[declaration.id]
            if not declaration or not previous or previous.id ~= declaration.id or previous.kind ~= "texture"
                or not data or not element then
                return false
            end
            for index = 2, #(definitionSnapshot.children or {}) do
                local child = definitionSnapshot.children[index]
                local oldChild = self.definition.children and self.definition.children[index]
                local childElement = child and item.elements and item.elements[child.id]
                if not oldChild or oldChild.id ~= child.id or oldChild.kind ~= child.kind
                    or not childElement or (child.kind ~= "text" and child.kind ~= "texture") then
                    return false
                end
            end
            ApplyMaterialBody(item, declaration, data)
            for index = 2, #(definitionSnapshot.children or {}) do
                local child = definitionSnapshot.children[index]
                if not ReapplyDeclaredChild(item, child,
                    modelItem.elements and modelItem.elements[child.id] or nil) then
                    return false
                end
            end
            local itemWidth = definitionSnapshot.layout and definitionSnapshot.layout.itemWidth or item.widget:GetWidth()
            local itemHeight = definitionSnapshot.layout and definitionSnapshot.layout.itemHeight or item.widget:GetHeight()
            item.root:SetSize(itemWidth, itemHeight)
            self.definition, self.model = definitionSnapshot, modelSnapshot
            self.layout:ApplyStyle(definitionSnapshot.layout or DEFAULT_LAYOUT)
            self.layout:SetItems({ item.root }, item.root:GetWidth(), item.root:GetHeight())
            self.layout:SetParent(self.host)
            self.layout:ClearAllPoints()
            self.layout:SetPoint("CENTER", self.host, "CENTER", 0, 0)
            RefreshItemHitboxes(item, self)
            local envelope = ResolveWorldEnvelope(self)
            ApplyReappliedMaterialBounds(self, envelope)
            return true
        end
        for index, declaration in ipairs(definitionSnapshot.children or {}) do
            local previous = self.definition.children and self.definition.children[index]
            local element = item.elements and item.elements[declaration.id]
            if not previous or previous.id ~= declaration.id or previous.kind ~= declaration.kind or not element
                or (declaration.kind ~= "text" and declaration.kind ~= "texture") then
                return false
            end
        end

        local name, icon = ResolveContent(modelItem)
        item.widget:ApplyStyle(StyleForIcon(definitionSnapshot.appearance))
        item.widget:SetIcon(icon)
        if modelItem.duration then item.widget:SetStaticCooldown(modelItem.remaining, modelItem.duration) else item.widget:ClearCooldown() end
        local itemWidth = definitionSnapshot.layout and definitionSnapshot.layout.itemWidth or item.widget:GetWidth()
        local itemHeight = definitionSnapshot.layout and definitionSnapshot.layout.itemHeight or item.widget:GetHeight()
        item.root:SetSize(itemWidth, itemHeight)
        CenterFixedBody(item)

        local iconSpec = FixedSpec(definitionSnapshot, "core.icon", FIXED.icon["core.icon"])
        local coreIcon = item.elements and item.elements["core.icon"]
        if not coreIcon then return false end
        coreIcon.spec, coreIcon.anchor = iconSpec, iconSpec.anchor
        coreIcon.position = {
            x = iconSpec.anchor and iconSpec.anchor.x or 0,
            y = iconSpec.anchor and iconSpec.anchor.y or 0,
        }
        item.widget:SetShown(iconSpec.shown ~= false)
        local timeSpec = FixedSpec(definitionSnapshot, "core.time", FIXED.icon["core.time"])
        local stacksSpec = FixedSpec(definitionSnapshot, "core.stacks", FIXED.icon["core.stacks"])
        if not ReapplyFixedText(item, "core.time", timeSpec,
            modelItem.duration and (modelItem.timeText or EXUI:FormatCountdown(modelItem.remaining)) or "",
            modelItem.duration ~= nil and timeSpec.shown ~= false,
            item.widget:GetWidth(), item.widget:GetHeight())
            or not ReapplyFixedText(item, "core.stacks", stacksSpec,
                modelItem.stacks and tostring(modelItem.stacks) or "",
                modelItem.stacks ~= nil and stacksSpec.shown ~= false,
                item.widget:GetWidth(), item.widget:GetHeight()) then
            return false
        end

        for _, declaration in ipairs(definitionSnapshot.children or {}) do
            local data = modelItem.elements and modelItem.elements[declaration.id] or nil
            if not ReapplyDeclaredChild(item, declaration, data) then return false end
        end
        ApplyFixedElementAnchors(item)
        self.definition, self.model = definitionSnapshot, modelSnapshot
        self.layout:ApplyStyle(definitionSnapshot.layout or DEFAULT_LAYOUT)
        self.layout:SetItems({ item.root }, item.root:GetWidth(), item.root:GetHeight())
        self.layout:SetParent(self.host)
        self.layout:ClearAllPoints()
        self.layout:SetPoint("CENTER", self.host, "CENTER", 0, 0)
        RefreshItemHitboxes(item, self)
        local envelope = ResolveWorldEnvelope(self)
        ApplyReappliedMaterialBounds(self, envelope)
        return true
    end

    function preview:Release()
        ClearPreview(self, false)
        SetWorldEditState(self, false)
        self.worldBounds = nil
        self.worldContentOffsetX, self.worldContentOffsetY = 0, 0
        return self
    end

    function preview:GetBounds()
        return self.width, self.height
    end

    function preview:GetWorldBounds()
        if self.interactionMode ~= "world" then Fail("GetWorldBounds is only valid for world previews") end
        if type(self.worldBounds) ~= "table" then Fail("GetWorldBounds requires prior Materialize") end
        return self.worldBounds
    end

    function preview:Unmount()
        self:Release()
        if self.layout then self.layout:Release(); self.layout = nil end
        self.host, self.onIntent, self.renderExtraChildren = nil, nil, nil
    end
    return preview
end

EXFactory:InitPool(ITEM_POOL, "Frame")
EXFactory:InitPool(REGION_POOL, "Frame")
EXFactory:InitPool(HITBOX_POOL, "Button", "BackdropTemplate")
