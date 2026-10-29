-- 材质选取（V2 节点 kind = "texturepreview" / "texturegrid"）：材质选择器的大预览区和缩略图网格。
-- 白色材质在游戏里染色：预览和格子都按 owner 给的颜色画，颜色、透明度就是元素自己的设置（同一份数据），
-- 改颜色的行用标准设置行写在同一页里，Core 这里只负责画。
--
-- texturepreview：{ id, kind = "texturepreview", source = sources 引用名 }。sources[source](scope) 返回
--   { texture = 材质文件 ID 或路径, tint = { r, g, b, a }（可选，默认白）, name = 左上角灰字（可选）,
--     layout = "around"（围着中间的示意图标：括号、法术触发材质）| "ring"（套在图标外）| "single"（只画材质）,
--     axis = "H"（放左边，成对时右边翻转）| "V"（放上边，成对时下边翻转），pair = true（成对）,
--     aspect = 宽 / 高（可选，默认 1）, offset = 两张中心离中心的距离按材质边长的倍数（可选，around 用，
--     不写时贴在图标外侧）, icon = 中间示意图标的材质文件 ID（around / ring 用，可选） }
-- texturegrid：{ id, kind = "texturegrid", source = sources 引用名, select = actions 引用名 }。sources[source](scope) 返回
--   { tint = { r, g, b, a }（可选）, items = { { texture, name, tip（悬停说明，"\n" 分行，第一行是标题，可选）,
--     aspect（可选）, selected = true（可选） }, ... } }；点格子调用 actions[select](context, 项)，owner 写好后
--   context:RefreshPage()。格子按宽度自动排列数。
-- 尺寸全在 GM.settings.parts.texturePick*（页面样式预设可覆盖），颜色只用 GUIColors。
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local GM = _G.ExwindTools.GUIMetrics
local PREVIEW_POOL, GRID_POOL = "EXUI.SettingsV2.TexturePreview", "EXUI.SettingsV2.TextureGrid"
Factory:InitCompositePool(PREVIEW_POOL)
Factory:InitCompositePool(GRID_POOL)
local Layouts = { around = true, ring = true, single = true }

local function Colors() return _G.ExwindTools.GUIColors end
local function Tint(texture, tint)
    tint = type(tint) == "table" and tint or {}
    texture:SetVertexColor(tint.r or tint[1] or 1, tint.g or tint[2] or 1, tint.b or tint[3] or 1, tint.a or tint[4] or 1)
end
-- 在 size × size 的方框里按宽高比放下材质，返回宽、高。
local function Fit(size, aspect)
    aspect = tonumber(aspect) or 1
    if aspect >= 1 then return size, size / aspect end
    return size * aspect, size
end
-- 样式页卡片正文没有内距，标准行自带 rowPaddingX / rowPaddingY；这里留同样的内距，和同卡的行对齐。
local function Padding(style)
    return style and (style.rowPaddingX or GM.settings.rowPaddingX) or 0, style and (style.rowPaddingY or 0) or 0
end

local function PreviewAdapter(node, kit)
    local spec, session = node.spec, node.session
    local style = session.style
    local Check = kit.Check
    local function part(key) return kit.Part(style, key) end
    local states = {}
    local adapter = {}
    local function Read()
        local record = session.owner.sources[spec.source](node.scope)
        Check(type(record) == "table", spec.id .. ": texturepreview source must return a table")
        Check(record.layout == nil or Layouts[record.layout], spec.id .. ": texturepreview layout must be around, ring or single")
        Check(record.axis == nil or record.axis == "H" or record.axis == "V", spec.id .. ": texturepreview axis must be H or V")
        return record
    end
    local function Paint(widget)
        local state = states[widget]
        local record, width = state.record, state.width or widget:GetWidth()
        local padX, padY = Padding(style)
        local face = widget._tpFace
        face:ClearAllPoints()
        face:SetPoint("TOPLEFT", widget, "TOPLEFT", padX, -padY)
        face:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -padX, padY)
        UI:SetControlSurface(face, GM.radius.card, Colors().page, Colors().cardBorder)
        widget._tpName:SetText(record.name or "")
        local layout, axis = record.layout or "single", record.axis or "H"
        local size, iconSize = part("texturePickPreviewSize"), part("texturePickPreviewIcon")
        local icon, first, second = widget._tpIcon, widget._tpFirst, widget._tpSecond
        icon:SetShown(layout ~= "single" and record.icon ~= nil)
        if record.icon ~= nil then icon:SetTexture(record.icon) end
        icon:SetSize(iconSize, iconSize)
        for _, texture in ipairs({ first, second }) do
            texture:SetTexture(record.texture)
            Tint(texture, record.tint)
            texture:ClearAllPoints()
        end
        local w, h
        if layout == "ring" then
            w, h = Fit(size * 1.22, record.aspect)
        elseif layout == "single" then
            w, h = Fit(size * 0.9, record.aspect)
        else
            w, h = Fit(size, record.aspect)
        end
        first:SetSize(w, h)
        second:SetSize(w, h)
        first:SetTexCoord(0, 1, 0, 1)
        if layout ~= "around" then
            first:SetPoint("CENTER", face, "CENTER", 0, 0)
            second:Hide()
        else
            local along = axis == "H" and w or h
            local distance = record.offset and record.offset * along or (iconSize / 2 + part("texturePickGap") + along / 2)
            if axis == "H" then
                first:SetPoint("CENTER", face, "CENTER", -distance, 0)
                second:SetPoint("CENTER", face, "CENTER", distance, 0)
                second:SetTexCoord(1, 0, 0, 1)
            else
                first:SetPoint("CENTER", face, "CENTER", 0, distance)
                second:SetPoint("CENTER", face, "CENTER", 0, -distance)
                second:SetTexCoord(0, 1, 1, 0)
            end
            second:SetShown(record.pair == true)
        end
        first:Show()
        widget:SetAlpha(state.enabled and 1 or 0.6)
        return width
    end
    local function Rebuild(widget)
        states[widget].record = Read()
        Paint(widget)
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(PREVIEW_POOL, host)
        if isNew then
            widget._tpFace = CreateFrame("Frame", nil, widget)
            widget._tpFace:EnableMouse(false)
            widget._tpIcon = widget._tpFace:CreateTexture(nil, "ARTWORK")
            widget._tpIcon:SetPoint("CENTER", widget._tpFace, "CENTER", 0, 0)
            widget._tpIcon:SetTexCoord(.08, .92, .08, .92)
            widget._tpFirst = widget._tpFace:CreateTexture(nil, "OVERLAY")
            widget._tpSecond = widget._tpFace:CreateTexture(nil, "OVERLAY")
            widget._tpName = UI:CreateVisualFontString(widget._tpFace, _G.EXFONTFRAME, "GameFontHighlightSmall")
            widget._tpName:SetPoint("TOPLEFT", widget._tpFace, "TOPLEFT", 8, -6)
            widget._tpName:SetJustifyH("LEFT")
            widget._tpName:SetWordWrap(false)
        end
        UI.ControlAppearance.Font(widget._tpName, part("iconPickTitleFont"), Colors().textPlaceholder, "", "GameFontHighlightSmall")
        widget:EnableMouse(false)
        states[widget] = { host = host, enabled = true }
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        Rebuild(widget)
        return widget
    end
    function adapter.update(widget) Rebuild(widget) end
    function adapter.measure()
        local _, padY = Padding(style)
        return part("texturePickPreviewHeight") + padY * 2
    end
    function adapter.layout(widget, context, width, height)
        kit.Place(widget, states[widget].host, 0, 0, width, height)
        states[widget].width = width
        Paint(widget)
    end
    function adapter.setEnabled(widget, context, enabled)
        states[widget].enabled = enabled
        Paint(widget)
    end
    function adapter.setVisible(widget, context, visible) widget:SetShown(visible) end
    function adapter.release(widget)
        states[widget] = nil
        widget._tpFirst:SetTexture(nil)
        widget._tpSecond:SetTexture(nil)
        widget._tpIcon:SetTexture(nil)
        widget._tpName:SetText("")
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

local function PaintCell(cell)
    local GC, state = Colors(), cell._tp
    if not state then return end
    local hover = state.enabled and cell:IsMouseOver()
    local on = state.item.selected == true
    UI:SetControlSurface(cell, 4, GC.input, on and GC.transparent or (hover and GC.inputHoverBorder or GC.inputBorder))
    UI:PaintSelectCell(cell, on, 4)
    cell:SetAlpha(state.enabled and 1 or 0.6)
end

local function ShowCellTip(cell)
    local tip = cell._tp and (cell._tp.item.tip or cell._tp.item.name)
    if not tip or tip == "" then return end
    local GC = Colors()
    GameTooltip:SetOwner(cell, "ANCHOR_TOP")
    local first = true
    for line in tostring(tip):gmatch("[^\n]+") do
        local color = first and GC.text or GC.textDim
        GameTooltip:AddLine(line, color[1], color[2], color[3], true)
        first = false
    end
    GameTooltip:Show()
end

local function NewCell(widget)
    local cell = CreateFrame("Button", nil, widget)
    cell:RegisterForClicks("LeftButtonUp")
    cell.image = cell:CreateTexture(nil, "ARTWORK")
    cell:SetScript("OnEnter", function(self) PaintCell(self); ShowCellTip(self) end)
    cell:SetScript("OnLeave", function(self)
        PaintCell(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    cell:SetScript("OnClick", function(self)
        local state = self._tp
        if state and state.enabled and state.onClick then state.onClick(state.item) end
    end)
    return cell
end

local function GridAdapter(node, kit)
    local spec, session = node.spec, node.session
    local style = session.style
    local Check = kit.Check
    local function part(key) return kit.Part(style, key) end
    local states = {}
    local adapter = {}
    local function Read()
        local record = session.owner.sources[spec.source](node.scope)
        Check(type(record) == "table" and type(record.items) == "table", spec.id .. ": texturegrid source must return { items }")
        for _, item in ipairs(record.items) do
            Check(type(item) == "table" and item.texture ~= nil, spec.id .. ": texturegrid item needs texture")
        end
        return record
    end
    local function Columns(width)
        local padX = Padding(style)
        local cell, gap = part("texturePickCell"), part("texturePickGap")
        return math.max(1, math.floor((width - padX * 2 + gap) / (cell + gap)))
    end
    local function Height(widget, width)
        local _, padY = Padding(style)
        local count = #states[widget].record.items
        if count == 0 then return padY * 2 end
        local cell, gap = part("texturePickCell"), part("texturePickGap")
        local rows = math.ceil(count / Columns(width))
        return rows * cell + (rows - 1) * gap + padY * 2
    end
    local function Rebuild(widget, context)
        local state = states[widget]
        local record = Read()
        state.record = record
        local cells = widget._tpCells
        local inset = part("texturePickInset")
        local size = part("texturePickCell") - inset * 2
        local function Click(item) session.owner.actions[spec.select](context, item) end
        for index, item in ipairs(record.items) do
            local cell = cells[index]
            if not cell then cell = NewCell(widget); cells[index] = cell end
            cell._tp = { item = item, enabled = state.enabled, onClick = Click }
            cell.image:SetTexture(item.texture)
            cell.image:SetTexCoord(0, 1, 0, 1)
            Tint(cell.image, record.tint)
            cell.image:SetSize(Fit(size, item.aspect))
            cell.image:ClearAllPoints()
            cell.image:SetPoint("CENTER", cell, "CENTER", 0, 0)
            PaintCell(cell)
            cell:Show()
        end
        for index = #record.items + 1, #cells do
            cells[index]._tp = nil
            cells[index].image:SetTexture(nil)
            cells[index]:Hide()
        end
    end
    local function Arrange(widget, width)
        local padX, padY = Padding(style)
        local cell, gap = part("texturePickCell"), part("texturePickGap")
        local columns = Columns(width)
        for index = 1, #states[widget].record.items do
            local column, line = (index - 1) % columns, math.floor((index - 1) / columns)
            kit.Place(widget._tpCells[index], widget, padX + column * (cell + gap), padY + line * (cell + gap), cell, cell)
        end
    end
    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(GRID_POOL, host)
        if isNew then widget._tpCells = {} end
        widget:EnableMouse(false)
        states[widget] = { host = host, enabled = true }
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        Rebuild(widget, context)
        return widget
    end
    function adapter.update(widget, context) Rebuild(widget, context) end
    function adapter.measure(widget, context, width) return Height(widget, width) end
    function adapter.layout(widget, context, width, height)
        kit.Place(widget, states[widget].host, 0, 0, width, height)
        Arrange(widget, width)
    end
    function adapter.setEnabled(widget, context, enabled)
        states[widget].enabled = enabled
        for _, cell in ipairs(widget._tpCells) do
            if cell._tp then cell._tp.enabled = enabled; PaintCell(cell) end
        end
    end
    function adapter.setVisible(widget, context, visible) widget:SetShown(visible) end
    function adapter.release(widget)
        states[widget] = nil
        for _, cell in ipairs(widget._tpCells) do
            if GameTooltip:GetOwner() == cell then GameTooltip:Hide() end
            cell._tp = nil
            cell.image:SetTexture(nil)
            cell:Hide()
        end
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

UI._SettingsV2TexturePreviewAdapter = PreviewAdapter
UI._SettingsV2TextureGridAdapter = GridAdapter
