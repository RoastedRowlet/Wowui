-- =========================================================
-- ExwindWidgetLayout.lua
-- 图标 / 计时条等同尺寸 Widget 的通用单轴排列器。
-- 只负责子项的视觉排列；模块 anchorFrame 的位置、拖拽、编辑模式和保存仍由
-- AnchorController 负责，布局器绝不读取或修改整体 X/Y。
-- =========================================================

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local WIDGET_LAYOUT_POOL = "RuntimeWidgetLayout"

local DEFAULT_LAYOUT_STYLE = {
    mode = "FLOW",
    direction = "RIGHT",
    spacing = 8,
    maxVisible = 5,
    itemWidth = 40,
    itemHeight = 40,
}

local function NormalizeMode(value)
    local mode = tostring(value or DEFAULT_LAYOUT_STYLE.mode):upper()
    if mode == "FLOW" or mode == "ABSOLUTE" then return mode end
    return DEFAULT_LAYOUT_STYLE.mode
end

local function NumberOr(value, fallback)
    local number = tonumber(value)
    return number or fallback
end

local function NormalizeDirection(value, allowedDirections)
    local direction = tostring(value or DEFAULT_LAYOUT_STYLE.direction):upper()
    local aliases = {
        ["向右"] = "RIGHT",
        ["向左"] = "LEFT",
        ["向上"] = "UP",
        ["向下"] = "DOWN",
        ["HORIZONTAL_RIGHT"] = "RIGHT",
        ["HORIZONTAL_LEFT"] = "LEFT",
        ["VERTICAL_UP"] = "UP",
        ["VERTICAL_DOWN"] = "DOWN",
        ["左右居中"] = "CENTER_HORIZONTAL",
        ["居中左右"] = "CENTER_HORIZONTAL",
        ["HORIZONTAL_CENTER"] = "CENTER_HORIZONTAL",
        ["CENTER_X"] = "CENTER_HORIZONTAL",
        ["上下居中"] = "CENTER_VERTICAL",
        ["居中上下"] = "CENTER_VERTICAL",
        ["VERTICAL_CENTER"] = "CENTER_VERTICAL",
        ["CENTER_Y"] = "CENTER_VERTICAL",
    }
    direction = aliases[direction] or direction
    local valid = direction == "LEFT" or direction == "RIGHT" or direction == "UP" or direction == "DOWN"
        or direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL" or direction == "OVERLAY"
    if valid then
        if type(allowedDirections) ~= "table" then return direction end
        for _, allowed in ipairs(allowedDirections) do
            if direction == allowed then return direction end
        end
    end
    if type(allowedDirections) == "table" then
        for _, allowed in ipairs(allowedDirections) do
            local candidate = NormalizeDirection(allowed)
            if candidate == allowed then return candidate end
        end
    end
    return DEFAULT_LAYOUT_STYLE.direction
end

local function StyleValue(style, key)
    local value = style and style[key]
    if value == nil then value = DEFAULT_LAYOUT_STYLE[key] end
    return value
end

local function ResolveRoot(item)
    if not item then return nil end
    if item.GetRoot then
        local root = item:GetRoot()
        if root then return root end
    end
    return item.root or item
end

local function HideTrackedItems(widget)
    for _, item in ipairs(widget.items or {}) do
        local root = ResolveRoot(item)
        if root and root.ClearAllPoints then
            root:ClearAllPoints()
            root:Hide()
        end
    end
end

local function AnchorAbsoluteOrigin(widget)
    -- ABSOLUTE 的 item.position 永远以 layout widget 的中心为原点。
    -- layout widget 的尺寸是内容包络，不得反过来把包络中心当作语义原点。
    local parent = widget:GetParent() or UIParent
    widget:ClearAllPoints()
    widget:SetPoint("CENTER", parent, "CENTER", 0, 0)
end

local function ApplyWidgetLayout(widget)
    HideTrackedItems(widget)

    local style = widget.style or DEFAULT_LAYOUT_STYLE
    local mode = NormalizeMode(StyleValue(style, "mode"))
    local direction = NormalizeDirection(StyleValue(style, "direction"), style.allowedDirections)
    local spacing = NumberOr(StyleValue(style, "spacing"), DEFAULT_LAYOUT_STYLE.spacing)
    local maxVisible = math.max(1, math.floor(NumberOr(StyleValue(style, "maxVisible"), DEFAULT_LAYOUT_STYLE.maxVisible)))
    local itemWidth = math.max(1, NumberOr(widget.itemWidth or StyleValue(style, "itemWidth"), DEFAULT_LAYOUT_STYLE.itemWidth))
    local itemHeight = math.max(1, NumberOr(widget.itemHeight or StyleValue(style, "itemHeight"), DEFAULT_LAYOUT_STYLE.itemHeight))
    local visibleCount = 0
    if mode == "ABSOLUTE" then
        local minX, maxX, minY, maxY
        for _, item in ipairs(widget.items or {}) do
            local root = ResolveRoot(item)
            local position = root and root.__EXUIStandardPreviewPosition
            if root and root.SetPoint and root.ClearAllPoints and type(position) == "table" then
                visibleCount = visibleCount + 1
                local x, y = NumberOr(position.x, 0), NumberOr(position.y, 0)
                local width, height = math.max(1, root:GetWidth() or 1), math.max(1, root:GetHeight() or 1)
                root:ClearAllPoints()
                root:SetPoint("CENTER", widget, "CENTER", x, y)
                root:Show()
                minX = minX and math.min(minX, x - width * 0.5) or x - width * 0.5
                maxX = maxX and math.max(maxX, x + width * 0.5) or x + width * 0.5
                minY = minY and math.min(minY, y - height * 0.5) or y - height * 0.5
                maxY = maxY and math.max(maxY, y + height * 0.5) or y + height * 0.5
            end
        end
        local layoutWidth = math.max(1, (maxX or 0) - (minX or 0))
        local layoutHeight = math.max(1, (maxY or 0) - (minY or 0))
        widget:SetSize(layoutWidth, layoutHeight)
        AnchorAbsoluteOrigin(widget)
        widget.direction, widget.mode = nil, mode
        widget.visibleCount, widget.layoutWidth, widget.layoutHeight = visibleCount, layoutWidth, layoutHeight
        widget.effectiveSpacing = nil
        return widget
    end
    local overlay = direction == "OVERLAY"
    local horizontal = not overlay and (direction == "LEFT" or direction == "RIGHT" or direction == "CENTER_HORIZONTAL")
    local centered = direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL"
    local axisExtent = horizontal and itemWidth or itemHeight
    -- 负间距是正式语义：本体可重叠。唯一不能允许的是步距 <= 0，否则后续
    -- item 会反向穿过前一项，且 collection 尺寸与摆放坐标不再一致。这里的
    -- 下限仍然是负数，保留最大可用重叠（相邻项至少相差 1px），绝不把它钳回 0。
    local effectiveSpacing = overlay and 0 or math.max(-(axisExtent - 1), spacing)
    local step = overlay and 0 or axisExtent + effectiveSpacing

    local plannedVisible = 0
    for _, item in ipairs(widget.items or {}) do
        if plannedVisible >= maxVisible then break end
        local root = ResolveRoot(item)
        if root and root.SetPoint and root.ClearAllPoints then
            plannedVisible = plannedVisible + 1
        end
    end

    for _, item in ipairs(widget.items or {}) do
        local root = ResolveRoot(item)
        if root and root.SetPoint and root.ClearAllPoints then
            if visibleCount < maxVisible then
                visibleCount = visibleCount + 1
                local offset = centered
                    and (visibleCount - (plannedVisible + 1) * 0.5) * step
                    or (visibleCount - 1) * step
                root:ClearAllPoints()
                if overlay then
                    root:SetPoint("CENTER", widget, "CENTER", 0, 0)
                elseif direction == "RIGHT" then
                    root:SetPoint("LEFT", widget, "LEFT", offset, 0)
                elseif direction == "LEFT" then
                    root:SetPoint("RIGHT", widget, "RIGHT", -offset, 0)
                elseif direction == "CENTER_HORIZONTAL" then
                    root:SetPoint("CENTER", widget, "CENTER", offset, 0)
                elseif direction == "UP" then
                    root:SetPoint("BOTTOM", widget, "BOTTOM", 0, offset)
                elseif direction == "CENTER_VERTICAL" then
                    root:SetPoint("CENTER", widget, "CENTER", 0, offset)
                else
                    root:SetPoint("TOP", widget, "TOP", 0, -offset)
                end
                root:Show()
            else
                root:Hide()
            end
        end
    end

    local layoutWidth = overlay and itemWidth or (horizontal and math.max(itemWidth, itemWidth + math.max(0, visibleCount - 1) * step) or itemWidth)
    local layoutHeight = overlay and itemHeight or (horizontal and itemHeight or math.max(itemHeight, itemHeight + math.max(0, visibleCount - 1) * step))
    widget:SetSize(layoutWidth, layoutHeight)

    widget:ClearAllPoints()
    local parent = widget:GetParent() or UIParent
    if overlay or direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL" then
        widget:SetPoint("CENTER", parent, "CENTER")
    elseif direction == "RIGHT" then
        widget:SetPoint("LEFT", parent, "CENTER")
    elseif direction == "LEFT" then
        widget:SetPoint("RIGHT", parent, "CENTER")
    elseif direction == "UP" then
        widget:SetPoint("BOTTOM", parent, "CENTER")
    else
        widget:SetPoint("TOP", parent, "CENTER")
    end

    widget.direction, widget.mode = direction, mode
    widget.visibleCount = visibleCount
    widget.layoutWidth = layoutWidth
    widget.layoutHeight = layoutHeight
    widget.effectiveSpacing = effectiveSpacing
    return widget
end

-- 语义集合布局：非居中方向的首项中心是 collection 的语义原点；居中方向
-- 的整组中心才是语义原点。后续项仅由 direction / spacing 单点计算。布局尺寸
-- 只用于宿主命中范围和查询，绝不能由模块复制公式或反推整体位置。
--
-- 这与旧 FLOW 的区别是明确的：FLOW 从布局边缘摆放首项，适合一般列表；
-- SEMANTIC 供计时条、图标等“用户保存的是第一个本体位置”的运行时集合使用。
local function ApplySemanticItems(widget)
    HideTrackedItems(widget)
    widget.semanticItemOffsets = {}

    local style = widget.style or DEFAULT_LAYOUT_STYLE
    local direction = NormalizeDirection(StyleValue(style, "direction"), style.allowedDirections)
    local spacing = NumberOr(StyleValue(style, "spacing"), DEFAULT_LAYOUT_STYLE.spacing)
    local maxVisible = math.max(1, math.floor(NumberOr(StyleValue(style, "maxVisible"), DEFAULT_LAYOUT_STYLE.maxVisible)))
    local itemWidth = math.max(1, NumberOr(widget.itemWidth or StyleValue(style, "itemWidth"), DEFAULT_LAYOUT_STYLE.itemWidth))
    local itemHeight = math.max(1, NumberOr(widget.itemHeight or StyleValue(style, "itemHeight"), DEFAULT_LAYOUT_STYLE.itemHeight))
    local overlay = direction == "OVERLAY"
    local horizontal = not overlay and (direction == "LEFT" or direction == "RIGHT" or direction == "CENTER_HORIZONTAL")
    local centered = direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL"
    local axisExtent = horizontal and itemWidth or itemHeight
    local effectiveSpacing = overlay and 0 or math.max(-(axisExtent - 1), spacing)
    local step = overlay and 0 or axisExtent + effectiveSpacing
    local visibleCount = 0
    local plannedVisible = 0
    for _, item in ipairs(widget.items or {}) do
        if plannedVisible >= maxVisible then break end
        local root = ResolveRoot(item)
        if root and root.SetPoint and root.ClearAllPoints then
            plannedVisible = plannedVisible + 1
        end
    end
    local minX, maxX, minY, maxY

    for _, item in ipairs(widget.items or {}) do
        local root = ResolveRoot(item)
        if root and root.SetPoint and root.ClearAllPoints then
            if visibleCount < maxVisible then
                visibleCount = visibleCount + 1
                local offset = centered
                    and (visibleCount - (plannedVisible + 1) * 0.5) * step
                    or (visibleCount - 1) * step
                local x, y = 0, 0
                if overlay then
                    x, y = 0, 0
                elseif direction == "RIGHT" then
                    x = offset
                elseif direction == "LEFT" then
                    x = -offset
                elseif direction == "CENTER_HORIZONTAL" then
                    x = offset
                elseif direction == "UP" then
                    y = offset
                elseif direction == "CENTER_VERTICAL" then
                    y = offset
                else
                    y = -offset
                end
                root:ClearAllPoints()
                root:SetPoint("CENTER", widget, "CENTER", x, y)
                root:Show()
                -- 声明式选择框必须复用布局器本次实际采用的偏移，不能在外部
                -- 再复制 direction/spacing 公式或读取屏幕坐标。
                widget.semanticItemOffsets[item] = { x = x, y = y }
                minX = minX and math.min(minX, x - itemWidth * 0.5) or x - itemWidth * 0.5
                maxX = maxX and math.max(maxX, x + itemWidth * 0.5) or x + itemWidth * 0.5
                minY = minY and math.min(minY, y - itemHeight * 0.5) or y - itemHeight * 0.5
                maxY = maxY and math.max(maxY, y + itemHeight * 0.5) or y + itemHeight * 0.5
            else
                root:Hide()
            end
        end
    end

    local layoutWidth = math.max(1, (maxX or 0) - (minX or 0))
    local layoutHeight = math.max(1, (maxY or 0) - (minY or 0))
    local semanticBounds = {
        width = layoutWidth,
        height = layoutHeight,
        anchorOffsetX = ((minX or 0) + (maxX or 0)) * 0.5,
        anchorOffsetY = ((minY or 0) + (maxY or 0)) * 0.5,
    }
    widget:SetSize(layoutWidth, layoutHeight)
    widget:ClearAllPoints()
    local parent = widget:GetParent() or UIParent
    -- 非居中方向保存的是首项语义原点；CENTER_* 保存的是整组语义中心，二者
    -- 均保持 0,0。设置面板没有世界 XY 概念，非居中方向仅在显式 contentCenter
    -- 时才把完整样本组居中在 preview dock。
    local contentCenter = StyleValue(style, "contentCenter") == true
    widget:SetPoint("CENTER", parent, "CENTER",
        contentCenter and -semanticBounds.anchorOffsetX or 0,
        contentCenter and -semanticBounds.anchorOffsetY or 0)
    widget.direction, widget.mode = direction, "SEMANTIC"
    widget.visibleCount = visibleCount
    widget.layoutWidth, widget.layoutHeight = layoutWidth, layoutHeight
    widget.effectiveSpacing = effectiveSpacing
    -- 语义集合的可见本体范围。只供编辑覆盖层/命中框读取；它不参与
    -- layout 自身、ItemRoot 或保存锚点的定位，更不会读取文字/Atlas 的 visual union。
    widget.semanticBounds = semanticBounds
    return widget
end

local function WidgetLayoutApplyStyle(widget, style)
    widget.style = style or DEFAULT_LAYOUT_STYLE
    return ApplyWidgetLayout(widget)
end

local function WidgetLayoutSetItems(widget, items, itemWidth, itemHeight)
    HideTrackedItems(widget)
    widget.items = type(items) == "table" and items or {}
    widget.itemWidth = itemWidth
    widget.itemHeight = itemHeight
    return ApplyWidgetLayout(widget)
end

local function WidgetLayoutSetSemanticItems(widget, items, itemWidth, itemHeight)
    HideTrackedItems(widget)
    widget.items = type(items) == "table" and items or {}
    widget.itemWidth = itemWidth
    widget.itemHeight = itemHeight
    return ApplySemanticItems(widget)
end

local function WidgetLayoutClear(widget)
    HideTrackedItems(widget)
    widget.items = {}
    widget.visibleCount = 0
    widget.semanticItemOffsets = {}
    widget:SetSize(1, 1)
    return widget
end

local function WidgetLayoutGetBounds(widget)
    return widget.layoutWidth or 1, widget.layoutHeight or 1, widget.visibleCount or 0
end

local function WidgetLayoutGetSemanticBounds(widget)
    local bounds = widget.semanticBounds
    if type(bounds) == "table" then return bounds end
    return { width = 1, height = 1, anchorOffsetX = 0, anchorOffsetY = 0 }
end

local function WidgetLayoutGetSemanticItemOffsets(widget)
    return widget.semanticItemOffsets or {}
end

local function WidgetLayoutRelease(widget)
    if not widget or widget._released then return end
    widget._released = true
    WidgetLayoutClear(widget)
    widget.style = nil
    widget.itemWidth = nil
    widget.itemHeight = nil
    widget:Hide()
    widget:ClearAllPoints()
    EXFactory:Release(WIDGET_LAYOUT_POOL, widget)
end

EXFactory:InitPool(WIDGET_LAYOUT_POOL, "Frame", nil, function(widget)
    widget.root = widget
    widget:SetSize(1, 1)
    widget:EnableMouse(false)
    widget.items = {}
    widget.ApplyStyle = WidgetLayoutApplyStyle
    widget.SetItems = WidgetLayoutSetItems
    widget.SetSemanticItems = WidgetLayoutSetSemanticItems
    widget.Clear = WidgetLayoutClear
    widget.GetBounds = WidgetLayoutGetBounds
    widget.GetSemanticBounds = WidgetLayoutGetSemanticBounds
    widget.GetSemanticItemOffsets = WidgetLayoutGetSemanticItemOffsets
    widget.Release = WidgetLayoutRelease
end)

function EXUI:CreateWidgetLayout(parent, style)
    local widget = EXFactory:Acquire(WIDGET_LAYOUT_POOL, parent)
    widget._released = false
    widget.items = {}
    widget.itemWidth = nil
    widget.itemHeight = nil
    widget.semanticBounds = nil
    widget:ApplyStyle(style or DEFAULT_LAYOUT_STYLE)
    return widget
end

function EXUI:BuildWidgetLayoutStyle(db, key, itemWidth, itemHeight)
    db = type(db) == "table" and db or {}
    local source = key and type(db[key]) == "table" and db[key] or db
    return {
        mode = source.mode or DEFAULT_LAYOUT_STYLE.mode,
        direction = source.direction or source.growDirection or DEFAULT_LAYOUT_STYLE.direction,
        allowedDirections = source.allowedDirections,
        spacing = source.spacing ~= nil and source.spacing or DEFAULT_LAYOUT_STYLE.spacing,
        maxVisible = source.maxVisible or source.maxBars or DEFAULT_LAYOUT_STYLE.maxVisible,
        itemWidth = itemWidth or source.itemWidth or DEFAULT_LAYOUT_STYLE.itemWidth,
        itemHeight = itemHeight or source.itemHeight or DEFAULT_LAYOUT_STYLE.itemHeight,
    }
end
