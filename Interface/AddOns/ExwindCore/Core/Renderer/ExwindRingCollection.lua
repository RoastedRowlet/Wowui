-- ExwindRingCollection.lua
-- 圆环唯一 Item/Collection 渲染入口：12.x 径向 StatusBar（StatusBarRenderMode.Radial）。
--
-- 进度来源（按顺序取第一个）：
--   time     { mode = "DURATION"|"SECRET", duration, direction = 0 已过 / 1 剩余, interpolation }
--            Duration 对象原样交给 StatusBar:SetTimerDuration，由原生逐帧驱动，不建 Lua 计时
--   progress { value, minimum, maximum }；秘密数值写 mode = "SECRET"，value 原样交给 StatusBar:SetValue
--   都没有时圆环为空
-- 秘密值（计时、数值、文字）只原样交给原生 StatusBar 与文字绑定，不读取、不比较、不运算。
--
-- presentation：
--   size            圆环边长（普通数字）
--   texture         圆环材质路径（填充与底圈共用，由调用方提供）
--   fillColor       {r,g,b,a}；hasFillColorComponents + fillColorComponents 走原生分量通道
--   backgroundColor {r,g,b,a}；backgroundShown = false 时不画底圈
--   clockwise       true 顺时针填充
--   localOffset     {x,y} 圆环相对 ItemRoot 的位置
--   textSlots       { [语义 ID] = 文字槽 }，写法与 MaterialCollection 相同；锚点相对圆环
--   regionElements / elementContent / regionConfigContextID 交给 RegionElements
-- 排列、群组几何与 TimerBarCollection 同一套 WidgetLayout；圆环没有面板局部拖动层。

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local ITEM_ROOT_POOL = "RuntimeRingCollectionItemRoot"
local RING_WIDGET_POOL = "RuntimeRingCollectionWidget"

local function NumberOr(value, fallback)
    local number = tonumber(value)
    if number == nil then return fallback end
    return number
end

local function Clamp(value, minimum, maximum, fallback)
    return math.max(minimum, math.min(maximum, NumberOr(value, fallback)))
end

EXFactory:InitPool(ITEM_ROOT_POOL, "Frame", nil, function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
end)

-- 圆环本体：底圈材质 + 普通 StatusBar + 秘密 StatusBar + 文字层。普通与秘密数据各用一条
-- StatusBar（与 TimerBarWidget 同一做法），离开计时或秘密通道时把那一条恢复默认。
EXFactory:InitPool(RING_WIDGET_POOL, "Frame", nil, function(widget)
    widget:EnableMouse(false)
    widget:SetSize(1, 1)
    widget.background = EXUI:CreateVisualTexture(widget, _G.EXBACKGROUNDFRAME)
    widget.background:SetAllPoints(widget)
    widget.bar = CreateFrame("StatusBar", nil, widget)
    widget.bar:EnableMouse(false)
    widget.secretBar = CreateFrame("StatusBar", nil, widget)
    widget.secretBar:EnableMouse(false)
    widget.secretBar:Hide()
    widget.textLayer = CreateFrame("Frame", nil, widget)
    widget.textLayer:SetAllPoints(widget)
    widget.textLayer:EnableMouse(false)
end)

local function AcquireItemRoot(parent)
    local root = EXFactory:Acquire(ITEM_ROOT_POOL, parent)
    root:EnableMouse(false)
    root:SetSize(1, 1)
    root:ClearAllPoints()
    root:Hide()
    return root
end

local function ReleaseItemRoot(root)
    if not root then return end
    root:SetScript("OnUpdate", nil)
    root:EnableMouse(false)
    root:Hide()
    root:ClearAllPoints()
    root:SetSize(1, 1)
    root:SetParent(UIParent)
    EXFactory:Release(ITEM_ROOT_POOL, root)
end

local function AcquireRingWidget(parent)
    local widget = EXFactory:Acquire(RING_WIDGET_POOL, parent)
    widget:ClearAllPoints()
    widget:SetSize(1, 1)
    widget._ringMode = nil
    widget:Show()
    return widget
end

local function ResetRingBars(widget)
    if widget._ringMode == "SECRET" then widget.secretBar:SetToDefaults()
    elseif widget._ringMode == "DURATION" or widget._ringMode == "NUMERIC" then widget.bar:SetToDefaults() end
    widget._ringMode = nil
end

local function ReleaseRingWidget(widget)
    if not widget then return end
    ResetRingBars(widget)
    widget.bar:Hide()
    widget.secretBar:Hide()
    widget._textWidgets = nil
    widget:ClearAllPoints()
    widget:SetSize(1, 1)
    EXFactory:Release(RING_WIDGET_POOL, widget)
end

-- 颜色分量表只检查键；分量值（可能是秘密值）原样交给原生 setter。
local function ApplyColorComponents(region, setter, components)
    if type(components) ~= "table" or (type(issecretvalue) == "function" and issecretvalue(components))
        or getmetatable(components) ~= nil then
        error("RingCollection color components require a plain table", 3)
    end
    local hasR, hasG, hasB, hasA = false, false, false, false
    for key in pairs(components) do
        if key == "r" then hasR = true
        elseif key == "g" then hasG = true
        elseif key == "b" then hasB = true
        elseif key == "a" then hasA = true
        else error("RingCollection color components allow only r, g, b, a", 3) end
    end
    if not hasR or not hasG or not hasB then error("RingCollection color components require r, g, b", 3) end
    if hasA then setter(region, components.r, components.g, components.b, components.a)
    else setter(region, components.r, components.g, components.b, 1) end
end

local function ConfigureBar(widget, bar, presentation)
    bar:ClearAllPoints()
    bar:SetAllPoints(widget)
    EXUI:ApplyVisualLayer(bar, _G.EXFILLFRAME, widget)
    bar:SetStatusBarTexture(presentation.texture)
    bar:SetRenderMode(Enum.StatusBarRenderMode.Radial)
    local fill = bar:GetStatusBarTexture()
    fill:SetRadialProgressBarReverse(presentation.clockwise == false)
    fill:SetRadialProgressBarStartOffset(.5)
    fill:SetRadialProgressBarFeather(0)
    local color = type(presentation.fillColor) == "table" and presentation.fillColor or {}
    bar:SetStatusBarColor(Clamp(color.r, 0, 1, 1), Clamp(color.g, 0, 1, .7),
        Clamp(color.b, 0, 1, 0), Clamp(color.a, 0, 1, 1))
    if presentation.hasFillColorComponents == true then
        ApplyColorComponents(bar, bar.SetStatusBarColor, presentation.fillColorComponents)
    end
end

local function ApplyRingProgress(widget, presentation)
    local time, progress = presentation.time, presentation.progress
    if type(time) == "table" and (time.mode == "DURATION" or time.mode == "SECRET") then
        local bar = time.mode == "SECRET" and widget.secretBar or widget.bar
        local other = time.mode == "SECRET" and widget.bar or widget.secretBar
        other:Hide()
        bar:Show()
        bar:SetTimerDuration(time.duration, time.interpolation or Enum.StatusBarInterpolation.Immediate,
            time.direction == nil and Enum.StatusBarTimerDirection.RemainingTime or time.direction)
        -- 复用的 StatusBar 可能停在上一次的值；对齐到原生目标值一次，之后每帧由原生驱动。
        bar:SetToTargetValue()
        widget._ringMode = time.mode
        return
    end
    if type(progress) == "table" and progress.mode == "SECRET" then
        widget.bar:Hide()
        widget.secretBar:Show()
        local minimum, maximum = NumberOr(progress.minimum, 0), NumberOr(progress.maximum, 1)
        if maximum <= minimum then maximum = minimum + 1 end
        widget.secretBar:SetMinMaxValues(minimum, maximum)
        widget.secretBar:SetValue(progress.value)
        widget._ringMode = "SECRET"
        return
    end
    widget.secretBar:Hide()
    widget.bar:Show()
    local minimum = NumberOr(type(progress) == "table" and progress.minimum, 0)
    local maximum = NumberOr(type(progress) == "table" and progress.maximum, minimum + 1)
    if maximum <= minimum then maximum = minimum + 1 end
    local value = type(progress) == "table" and progress.value or progress
    widget.bar:SetMinMaxValues(minimum, maximum)
    widget.bar:SetValue(math.max(minimum, math.min(maximum, NumberOr(value, minimum))))
    widget._ringMode = "NUMERIC"
end

local function ApplyRingWidget(widget, presentation, size)
    if type(presentation.texture) ~= "string" or presentation.texture == "" then
        error("RingCollection presentation requires texture", 3)
    end
    ResetRingBars(widget)
    widget:SetSize(size, size)
    widget.textLayer:SetAllPoints(widget)
    EXUI:ApplyVisualLayer(widget.textLayer, _G.EXFONTFRAME, widget)
    local background = widget.background
    background:SetTexture(presentation.texture)
    local color = type(presentation.backgroundColor) == "table" and presentation.backgroundColor or {}
    background:SetVertexColor(Clamp(color.r, 0, 1, 0), Clamp(color.g, 0, 1, 0),
        Clamp(color.b, 0, 1, 0), Clamp(color.a, 0, 1, .35))
    background:SetShown(presentation.backgroundShown ~= false)
    ConfigureBar(widget, widget.bar, presentation)
    ConfigureBar(widget, widget.secretBar, presentation)
    ApplyRingProgress(widget, presentation)
end

local function CopyLayout(layout, contentCenter)
    local copy = {}
    for key, value in pairs(type(layout) == "table" and layout or {}) do copy[key] = value end
    if contentCenter then copy.contentCenter = true end
    return copy
end

local function ResolveLocalOffset(presentation)
    local offset = presentation.localOffset
    if offset ~= nil and type(offset) ~= "table" then error("RingCollection presentation localOffset must be table", 3) end
    return { x = NumberOr(offset and offset.x, 0), y = NumberOr(offset and offset.y, 0) }
end

local function CombineOffsets(first, second)
    return {
        x = NumberOr(first and first.x, 0) + NumberOr(second and second.x, 0),
        y = NumberOr(first and first.y, 0) + NumberOr(second and second.y, 0),
    }
end

local function UnionBounds(acc, bounds, offset)
    if type(bounds) ~= "table" then return acc end
    local x, y = offset and offset.x or 0, offset and offset.y or 0
    local left, right, bottom, top = bounds.left + x, bounds.right + x, bounds.bottom + y, bounds.top + y
    if not acc then return { left = left, right = right, bottom = bottom, top = top } end
    acc.left, acc.right = math.min(acc.left, left), math.max(acc.right, right)
    acc.bottom, acc.top = math.min(acc.bottom, bottom), math.max(acc.top, top)
    return acc
end

-- 文字槽：与 MaterialCollection 同一份声明写法，锚点相对圆环本体。
local function ResetTextSlot(item, slotID)
    local widget = item.textWidgets and item.textWidgets[slotID]
    if widget then
        widget:Release()
        item.textWidgets[slotID] = nil
    end
end

local function TextSlotBounds(slot)
    local bounds = type(slot) == "table" and slot.declaredBounds or nil
    if type(bounds) ~= "table" then return nil end
    local left, right, bottom, top = tonumber(bounds.left), tonumber(bounds.right), tonumber(bounds.bottom), tonumber(bounds.top)
    if not left or not right or not bottom or not top or right <= left or top <= bottom then return nil end
    return { left = left, right = right, bottom = bottom, top = top }
end

local function ApplyTextSlot(item, slotID, slot)
    if type(slot) ~= "table" or slot.shown == false then
        ResetTextSlot(item, slotID)
        return nil
    end
    local bounds = TextSlotBounds(slot)
    if not bounds then error("RingCollection text slot requires declaredBounds", 3) end
    local widget = item.textWidgets[slotID]
    if not widget then
        widget = EXUI:CreateTextWidget(item.widget.textLayer, "ring:" .. tostring(slotID))
        item.textWidgets[slotID] = widget
    end
    if type(slot.style) ~= "table" then error("RingCollection text slot requires direct style table", 3) end
    widget:SetStylePositionOverride(0, 0)
    widget:ResetSecretText()
    widget:ApplyStyle(slot.style)
    if slot.durationObject ~= nil then
        widget:SetDurationBinding(slot.durationObject, slot.durationOptions)
    elseif slot.secretDuration ~= nil then
        widget:SetDurationBinding(slot.secretDuration, slot.durationOptions)
    elseif slot.secretText == true then
        widget:SetSecretText(slot.text)
    else
        widget:SetText(slot.text or "")
    end
    if type(slot.color) == "table" then widget:SetColor(slot.color) end
    if slot.hasColorComponents == true then widget:SetColorComponents(slot.colorComponents) end
    widget:SetBounds(bounds.right - bounds.left, bounds.top - bounds.bottom)
    local anchor = type(slot.anchor) == "table" and slot.anchor or {}
    local point = anchor.point or "CENTER"
    local resolved = { point = point, relativePoint = anchor.relativePoint or point,
        x = NumberOr(anchor.x, 0), y = NumberOr(anchor.y, 0) }
    widget:SetAnchor(resolved.point, item.widget, resolved.relativePoint, resolved.x, resolved.y)
    return { bounds = bounds, anchor = resolved }
end

local function ApplyTextSlots(item, presentation)
    local slots = type(presentation.textSlots) == "table" and presentation.textSlots or {}
    local wanted = {}
    item.textSlotBounds, item.textSlotAnchors = {}, {}
    for slotID, slot in pairs(slots) do
        if type(slotID) == "string" then
            wanted[slotID] = true
            local applied = ApplyTextSlot(item, slotID, slot)
            if applied then item.textSlotBounds[slotID], item.textSlotAnchors[slotID] = applied.bounds, applied.anchor end
        end
    end
    for slotID in pairs(item.textWidgets) do if not wanted[slotID] then ResetTextSlot(item, slotID) end end
end

local function NewItem(collection, itemID)
    local root = AcquireItemRoot(collection.layout)
    local widget = AcquireRingWidget(root)
    widget:SetPoint("CENTER", root, "CENTER")
    local item = { id = itemID, root = root, widget = widget, collection = collection,
        textWidgets = {}, textSlotBounds = {}, textSlotAnchors = {} }
    widget._textWidgets = item.textWidgets
    -- 条件效果按语义 ID 取圆环或文字槽；没有的元素返回 nil。
    function widget:ResolveDeclaredElement(elementID)
        if elementID == "core.ring" or elementID == "core.root" then return self end
        return self._textWidgets and self._textWidgets[elementID] or nil
    end
    function item:GetRoot() return self.root end
    item.regions = EXUI:CreateRegionElements({
        ownerRoot = root,
        moduleKey = collection.moduleKey,
        interactionMode = collection.interactionMode,
        resolveCore = function(elementID)
            local bounds = item.declaredBounds or { left = -.5, right = .5, bottom = -.5, top = .5 }
            if elementID == "core.root" then return root, bounds end
            if elementID == "core.ring" then return item.widget, bounds end
            error("RingCollection unknown RegionElements core anchor: " .. tostring(elementID), 3)
        end,
        emitIntent = function(intent)
            local callback = collection.callbacks and collection.callbacks.onIntent
            if type(callback) == "function" then callback(intent) end
        end,
    })
    return item
end

function EXUI:CreateRingCollection(parent, interactionMode, moduleKey, callbacks)
    if interactionMode ~= "runtime" and interactionMode ~= "world" and interactionMode ~= "panel" then
        error("CreateRingCollection interactionMode must be runtime, world, or panel", 2)
    end
    local collection = {
        host = parent, moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateRingCollection"),
        interactionMode = interactionMode, callbacks = callbacks,
        contentCenter = type(callbacks) == "table" and callbacks.contentCenter == true,
        itemsByID = {}, currentItems = {}, currentLayout = {}, itemWidth = 1, itemHeight = 1, released = false,
    }
    collection.layout = EXUI:CreateWidgetLayout(parent, {})
    EXUI:InitializeCollectionVisualAnimations(collection)

    function collection:AcquireItem(itemID)
        if type(itemID) ~= "string" or itemID == "" then error("RingCollection itemID must be non-empty string", 2) end
        local item = self.itemsByID[itemID]
        if item then
            if self:IsItemVisualRetiring(itemID) then self:StopItemVisualAnimation(itemID) end
            return item
        end
        item = NewItem(self, itemID)
        self.itemsByID[itemID] = item
        self.geometryRevision = (self.geometryRevision or 0) + 1
        return item
    end

    function collection:ApplyItem(item, presentation)
        if not item or not item.widget then error("RingCollection ApplyItem requires an acquired item", 2) end
        if type(presentation) ~= "table" then error("RingCollection presentation must be table", 2) end
        if self:IsItemVisualRetiring(item.id) then self:StopItemVisualAnimation(item.id) end
        self.geometryRevision = (self.geometryRevision or 0) + 1
        item.presentation = presentation
        local size = math.max(1, NumberOr(presentation.size, 64))
        ApplyRingWidget(item.widget, presentation, size)
        item.declaredBounds = { left = -size * .5, right = size * .5, bottom = -size * .5, top = size * .5 }
        item.localOffset = ResolveLocalOffset(presentation)
        item.bodyWidth, item.bodyHeight = size, size
        self.itemWidth, self.itemHeight = size, size
        item.root:SetSize(size, size)
        item.widget:ClearAllPoints()
        item.widget:SetPoint("CENTER", item.root, "CENTER", item.localOffset.x, item.localOffset.y)
        ApplyTextSlots(item, presentation)
        item.regions:SetConfigContextID(presentation.regionConfigContextID)
        item.regions:Apply(presentation.regionElements, presentation.elementContent)
        if item.visualEffects then
            EXUI:ApplyCollectionItemVisualEffects(item.root, item.visualEffects, size, size)
        end
        if item._collectionClickSpec then EXUI:ApplyCollectionItemClick(item, item._collectionClickSpec) end
        if presentation.shown == false then item.root:Hide() else item.root:Show() end
        return item
    end

    function collection:SetItems(items, layout, geometryOnly)
        local contentItems = items or {}
        items, layout = self.layout:ResolveGeometryItems(self, items or {}, layout)
        if not geometryOnly then
            self.contentItems = {}
            for index, item in ipairs(contentItems) do self.contentItems[index] = item end
        end
        local wanted = {}
        for _, item in ipairs(items or {}) do
            if not item or not item.bodyWidth then error("RingCollection SetItems requires every item to be applied", 2) end
            wanted[item.id] = true
        end
        for itemID, item in pairs(self.itemsByID) do
            if not wanted[itemID] and item.root and not self:IsItemVisualRetiring(itemID) then item.root:Hide() end
        end
        local layoutStyle = CopyLayout(layout, self.contentCenter)
        self.geometryRevision = (self.geometryRevision or 0) + 1
        self.layout:ApplyStyle(layoutStyle, true)
        self.layout:SetSemanticItems(items or {}, self.itemWidth, self.itemHeight)
        self.currentItems = items or {}
        self.currentLayout = layoutStyle
        return self
    end

    function collection:ReapplyCurrentItems(mutatePresentation)
        if self.released then return false end
        for _, item in ipairs(self.currentItems or {}) do
            if item and item.widget and item.presentation then
                if type(mutatePresentation) == "function" then mutatePresentation(item.presentation, item) end
                self:ApplyItem(item, item.presentation)
            end
        end
        self:SetItems(self.currentItems or {}, self.currentLayout, true)
        return true
    end

    function collection:ReapplyCurrentLayout(layout)
        if self.released then return false end
        self:SetItems(self.contentItems or self.currentItems or {}, layout or self.currentLayout, true)
        return true
    end

    function collection:PrepareCurrentGeometry(geometryByItemID, layout)
        if self.released then return nil, "COLLECTION_RELEASED" end
        return self.layout:PrepareItemGeometry(self, geometryByItemID, layout)
    end

    function collection:ApplyPreparedGeometry(plan)
        if self.released then return false, "COLLECTION_RELEASED" end
        return self.layout:ApplyItemGeometry(self, plan)
    end

    function collection:GetWorldBounds()
        local bounds, offsets = nil, self.layout:GetSemanticItemOffsets()
        for _, item in ipairs(self.currentItems or {}) do
            local offset = offsets[item]
            if offset and item.declaredBounds then
                local body = CombineOffsets(offset, item.localOffset)
                bounds = UnionBounds(bounds, item.declaredBounds, body)
                for slotID, slotBounds in pairs(item.textSlotBounds or {}) do
                    bounds = UnionBounds(bounds, slotBounds, CombineOffsets(body, item.textSlotAnchors[slotID]))
                end
                if item.regions then bounds = UnionBounds(bounds, item.regions:GetDeclaredBounds(), offset) end
            end
        end
        if not bounds then return nil end
        return { anchor = self.layout, left = bounds.left, right = bounds.right, bottom = bounds.bottom, top = bounds.top,
            width = math.max(1, bounds.right - bounds.left), height = math.max(1, bounds.top - bounds.bottom),
            anchorOffsetX = (bounds.left + bounds.right) * 0.5, anchorOffsetY = (bounds.bottom + bounds.top) * 0.5 }
    end

    function collection:GetBounds()
        return self.layout:GetBounds()
    end

    function collection:GetItems()
        return self.itemsByID
    end

    function collection:SetItemClickAction(itemID, spec)
        local item = self.itemsByID[itemID]
        if not item or not item.root then return false end
        if self:IsItemVisualRetiring(itemID) then return false end
        return EXUI:ApplyCollectionItemClick(item, spec)
    end

    function collection:SetItemVisualEffects(itemID, effects)
        local item = self.itemsByID[itemID]
        if not item or not item.root then return false end
        item.visualEffects = type(effects) == "table" and effects or nil
        EXUI:ApplyCollectionItemVisualEffects(item.root, item.visualEffects, item.bodyWidth, item.bodyHeight)
        return true
    end

    function collection:ReleaseItem(itemID)
        local item = self.itemsByID[itemID]
        if not item then return end
        self:StopItemVisualAnimation(itemID)
        self.itemsByID[itemID] = nil
        self.geometryRevision = (self.geometryRevision or 0) + 1
        EXUI:ReleaseCollectionItemClick(item)
        EXUI:ReleaseCollectionItemVisualEffects(item.root)
        if item.regions then item.regions:Release() end
        for slotID in pairs(item.textWidgets or {}) do ResetTextSlot(item, slotID) end
        ReleaseRingWidget(item.widget)
        ReleaseItemRoot(item.root)
        item.widget, item.root, item.presentation, item.declaredBounds, item.localOffset = nil, nil, nil, nil, nil
        item.visualEffects, item.regions, item.textWidgets, item.textSlotBounds, item.textSlotAnchors = nil, nil, nil, nil, nil
        item.bodyWidth, item.bodyHeight = nil, nil
    end

    function collection:Release()
        self.released = true
        for itemID in pairs(self.itemsByID) do self:ReleaseItem(itemID) end
        self.layout:Release()
        self.layout, self.currentItems, self.contentItems, self.currentLayout = nil, nil, nil, nil
        self.host, self.callbacks = nil, nil
    end
    return collection
end
