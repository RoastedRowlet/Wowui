-- =========================================================
-- ExwindVirtualTable.lua: 暴雪官方表格 / 网格的薄封装 EXUI:CreateVirtualTable / EXUI:CreateVirtualGrid。
-- 官方组合：WowScrollBoxList + CreateScrollBoxListLinearView（或 GridView）+ CreateDataProvider
-- + ScrollUtil.InitScrollBoxListWithScrollBar + CreateTableBuilder / ScrollUtil.RegisterTableBuilder。
-- 滚动、行池、单元格池全归官方；这里只做连接、列定义转官方约束、表头、Core 外观、数据和释放回调。
-- 新增文件理由：ExwindVirtualList 是自写滚动的旧列表（EXBoss 在用，不动）；本组件依赖
-- ExwindGUI.lua（选中外观、滚动条）与 ExwindGUISettingsList.lua（表头、表格行分隔线），在 TOC 中排在它们后面。
-- 单元格模板 ExwindVirtualTableCellTemplate 定义在同名 xml：官方列单元格池只认 xml 模板。
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local GC = ExwindTools.GUIColors
local GM = ExwindTools.GUIMetrics
local SCROLL_BAR_INSET = EXUI._GUIInternal.SCROLL_BAR_INSET

-- 列间距、单元格内缩与 Core 设置表格（ResolveSettingsTableColumns / UpdateSettingsTableRowLayout）一致，
-- 表头文字和单元格因此落在同一列线上。
local COLUMN_GAP = 12
local CELL_INSET = 4

local function Check(condition, message)
    if not condition then error("ExwindVirtualTable: " .. message, 3) end
end

-- ---------------------------------------------------------
-- 共用：根框 + 官方 ScrollBox + Core 原生滚动条（有滚动才占位）
-- ---------------------------------------------------------
local function CreateScrollParts(owner, parent, top)
    local root = CreateFrame("Frame", nil, parent)
    owner.frame = root
    owner.scrollBox = CreateFrame("Frame", nil, root, "WowScrollBoxList")
    owner.scrollBar = EXUI:CreateScrollBar(root)
    owner.scrollBar:SetPoint("TOPLEFT", owner.scrollBox, "TOPRIGHT", SCROLL_BAR_INSET - owner.scrollBar:GetWidth(), 0)
    owner.scrollBar:SetPoint("BOTTOMLEFT", owner.scrollBox, "BOTTOMRIGHT", SCROLL_BAR_INSET - owner.scrollBar:GetWidth(), 0)
    owner.anchorsWithBar = {
        CreateAnchor("TOPLEFT", root, "TOPLEFT", 0, -top),
        CreateAnchor("BOTTOMRIGHT", root, "BOTTOMRIGHT", -SCROLL_BAR_INSET, 0),
    }
    owner.anchorsWithoutBar = {
        CreateAnchor("TOPLEFT", root, "TOPLEFT", 0, -top),
        CreateAnchor("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0),
    }
    owner.scrollBox:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top)
    owner.scrollBox:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    return root
end

local function ConnectView(owner, view)
    ScrollUtil.InitScrollBoxListWithScrollBar(owner.scrollBox, owner.scrollBar, view)
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(owner.scrollBox, owner.scrollBar,
        owner.anchorsWithBar, owner.anchorsWithoutBar)
end

local function SetData(owner, items, options)
    Check(not owner.released, "used after Release")
    owner.items = type(items) == "table" and items or {}
    local retain = type(options) == "table" and options.retainScroll == true
    owner.scrollBox:SetDataProvider(CreateDataProvider(owner.items),
        retain and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition)
end

-- 悬停底同树行（GC.menuHover，透明边）；选中外框走公共选中外观。
local function PaintHover(frame)
    if frame._exVTHover then
        EXUI:SetControlSurface(frame, GM.radius.control, GC.menuHover, GC.transparent)
    else
        EXUI:ClearControlSurface(frame)
    end
end

local function InstallHover(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self) self._exVTHover = true; PaintHover(self) end)
    frame:SetScript("OnLeave", function(self) self._exVTHover = nil; PaintHover(self) end)
end

-- =========================================================
-- 表格
-- =========================================================
local Table = {}
Table.__index = Table

ExwindVirtualTableCellMixin = {}

-- 官方列单元格池按模板共用：同一个格子可能先后落到不同表、不同列。
-- 每列的内容建在格子上的独立子框里，按列切换显隐；换列前先释放上一列的业务绑定。
function ExwindVirtualTableCellMixin:Init(owner, columnIndex)
    owner:_InitCell(self, columnIndex)
end

function ExwindVirtualTableCellMixin:Populate(rowData)
    self._exVTOwner:_BindCell(self, rowData)
end

function Table:_ReleaseCell(cell)
    local column = cell._exVTBoundColumn
    if not column then return end
    cell._exVTBoundColumn = nil
    if column.release then column.release(cell._exVTContents[column], self) end
end

function Table:_InitCell(cell, columnIndex)
    if cell._exVTBoundColumn then cell._exVTBoundOwner:_ReleaseCell(cell) end
    local column = self.columns[columnIndex]
    cell._exVTOwner, cell._exVTColumn = self, column
    cell._exVTContents = cell._exVTContents or {}
    for key, content in pairs(cell._exVTContents) do content:SetShown(key == column) end
    local content = cell._exVTContents[column]
    if not content then
        content = CreateFrame("Frame", nil, cell)
        content:SetAllPoints(cell)
        cell._exVTContents[column] = content
        if column.create then column.create(content, self) end
    end
    content:Show()
end

function Table:_BindCell(cell, data)
    local column = cell._exVTColumn
    cell._exVTBoundColumn, cell._exVTBoundOwner = column, self
    if column.bind then column.bind(cell._exVTContents[column], data, self) end
end

function Table:_PaintRow(row, data)
    EXUI:SetSettingsRowLast(row._exVTSurface, data == self.items[#self.items])
    EXUI:PaintSelectRow(row, self.isSelected ~= nil and self.isSelected(data) == true)
end

function Table:_InitRow(row, data)
    if not row._exVTSurface then
        -- 行外观同 Core 设置表格行：底部分隔线（最后一行不画）。
        local surface = EXUI:CreateSettingsTableRow(row, {})
        EXUI:UpdateSettingsTableRowLayout(surface, 1, {}, {})
        surface:ClearAllPoints()
        surface:SetAllPoints(row)
        row._exVTSurface = surface
        self.rowFrames[row] = true
        InstallHover(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(frame, button)
            if self.onRowClick and self.enabled then self.onRowClick(frame, frame:GetElementData(), button, self) end
        end)
        if self.createRow then self.createRow(row, self) end
    end
    row:EnableMouse(self.enabled)
    if self.bindRow then self.bindRow(row, data, row:GetElementDataIndex(), self) end
    self:_PaintRow(row, data)
end

function Table:_ResetRow(row, data)
    for _, cell in ipairs(row.cells or {}) do self:_ReleaseCell(cell) end
    if self.releaseRow then self.releaseRow(row, data, self) end
    row._exVTHover = nil
    PaintHover(row)
    EXUI:PaintSelectRow(row, false)
end

function Table:_Arrange()
    local width = self.scrollBox:GetWidth()
    if not width or width <= 1 then return end
    EXUI:UpdateSettingsTableHeaderLayout(self.header, width)
    self.builder:SetTableWidth(width)
    -- Arrange 会把可视行的格子全部还池再重建；先释放业务绑定，重建时再 bind。
    self.scrollBox:ForEachFrame(function(row)
        for _, cell in ipairs(row.cells or {}) do self:_ReleaseCell(cell) end
    end)
    self.builder:Arrange()
end

function Table:SetData(items, options) SetData(self, items, options) end

-- 数据内容或选中变了、条数没变时用：可视行和格子原地重新 bind，不动滚动位置。
function Table:Refresh()
    Check(not self.released, "used after Release")
    self.scrollBox:ForEachFrame(function(row)
        local data = row:GetElementData()
        row:EnableMouse(self.enabled)
        if self.bindRow then self.bindRow(row, data, row:GetElementDataIndex(), self) end
        self:_PaintRow(row, data)
        for _, cell in ipairs(row.cells or {}) do self:_BindCell(cell, data) end
    end)
end

function Table:SetEnabled(enabled)
    self.enabled = enabled ~= false
    self:Refresh()
end

function Table:IsEnabled() return self.enabled end

-- 表头 + visibleRows 行的高度（固定行高时）。
function Table:MeasureHeight(visibleRows)
    return self.headerHeight + math.max(1, tonumber(visibleRows) or 1) * (self.rowHeight or 0)
end

function Table:Release()
    if self.released then return end
    self.scrollBox:RemoveDataProvider()
    for row in pairs(self.rowFrames) do
        row._exVTSurface:Release()
        row._exVTSurface = nil
    end
    self.rowFrames = {}
    self.header:Release()
    self.frame:Hide()
    self.released = true
end

-- opts:
--   columns    = { { title, width = 固定宽 | weight = 填充权重（缺省 1）,
--                    create(content, table)、bind(content, data, table)、release(content, table) }, ... }
--   rowHeight  = 固定行高；或 rowHeightFor(data) 逐行算
--   createRow(row, table)、bindRow(row, data, index, table)、releaseRow(row, data, table)：行级业务绑定
--   isSelected(data) → 选中画公共选中外观；onRowClick(row, data, button, table)
-- 返回对象：frame（根框，调用方定位和定尺寸）、scrollBox、scrollBar、header、
--   SetData(items, { retainScroll = true })、Refresh()、SetEnabled(bool)、MeasureHeight(n)、Release()。
function EXUI:CreateVirtualTable(parent, opts)
    Check(type(opts) == "table" and type(opts.columns) == "table" and #opts.columns > 0, "opts.columns required")
    Check(tonumber(opts.rowHeight) or type(opts.rowHeightFor) == "function", "opts.rowHeight or opts.rowHeightFor required")
    local t = setmetatable({
        columns = opts.columns, rowHeight = tonumber(opts.rowHeight), items = {}, rowFrames = {}, enabled = true,
        createRow = opts.createRow, bindRow = opts.bindRow, releaseRow = opts.releaseRow,
        isSelected = opts.isSelected, onRowClick = opts.onRowClick,
    }, Table)

    local headerColumns = {}
    for index, column in ipairs(opts.columns) do
        headerColumns[index] = { title = column.title or "", width = column.width, weight = column.weight }
    end
    -- 表头用 Core 设置表格表头，固定在滚动区上方。
    t.header = EXUI:CreateSettingsTableHeader(parent, { columns = headerColumns })
    t.headerHeight = EXUI:UpdateSettingsTableHeaderLayout(t.header, 1)
    local root = CreateScrollParts(t, parent, t.headerHeight)
    t.header:SetParent(root)
    t.header:ClearAllPoints()
    t.header:SetPoint("TOPLEFT", root, "TOPLEFT")

    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("Button", function(row, data) t:_InitRow(row, data) end)
    view:SetElementResetter(function(row, data) t:_ResetRow(row, data) end)
    if t.rowHeight then
        view:SetElementExtent(t.rowHeight)
    else
        view:SetElementExtentCalculator(function(_, data) return opts.rowHeightFor(data) end)
    end
    ConnectView(t, view)

    t.builder = CreateTableBuilder()
    t.builder:SetTableMargins(GM.settings.rowPaddingX)
    t.builder:SetDataProvider(function(data) return data end)
    for index, column in ipairs(opts.columns) do
        local builderColumn = t.builder:AddColumn()
        local gap = index > 1 and COLUMN_GAP or 0
        if tonumber(column.width) and column.width > 0 then
            builderColumn:SetFixedConstraints(column.width, gap)
        else
            builderColumn:SetFillConstraints(math.max(0.01, tonumber(column.weight) or 1), gap)
        end
        builderColumn:SetCellPadding(CELL_INSET, CELL_INSET)
        builderColumn:ConstructCells("Frame", "ExwindVirtualTableCellTemplate", t, index)
    end
    ScrollUtil.RegisterTableBuilder(t.scrollBox, t.builder, function(data) return data end)
    t.scrollBox:HookScript("OnSizeChanged", function()
        if not t.released then t:_Arrange() end
    end)
    return t
end

-- =========================================================
-- 网格（官方 GridView；留给材质选择这类等宽格子用）
-- =========================================================
local Grid = {}
Grid.__index = Grid

function Grid:_InitItem(frame, data)
    if not frame._exVTGrid then
        frame._exVTGrid = true
        InstallHover(frame)
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        frame:SetScript("OnClick", function(item, button)
            if self.onItemClick and self.enabled then self.onItemClick(item, item:GetElementData(), button, self) end
        end)
        if self.createItem then self.createItem(frame, self) end
    end
    frame:EnableMouse(self.enabled)
    if self.bindItem then self.bindItem(frame, data, frame:GetElementDataIndex(), self) end
    EXUI:PaintSelectCell(frame, self.isSelected ~= nil and self.isSelected(data) == true, self.radius)
end

function Grid:_ResetItem(frame, data)
    if self.releaseItem then self.releaseItem(frame, data, self) end
    frame._exVTHover = nil
    PaintHover(frame)
    EXUI:PaintSelectCell(frame, false)
end

function Grid:SetData(items, options) SetData(self, items, options) end

function Grid:Refresh()
    Check(not self.released, "used after Release")
    self.scrollBox:ForEachFrame(function(frame) self:_InitItem(frame, frame:GetElementData()) end)
end

function Grid:SetEnabled(enabled)
    self.enabled = enabled ~= false
    self:Refresh()
end

function Grid:IsEnabled() return self.enabled end

-- visibleRows 行格子的高度（含上下留白和行距）。
function Grid:MeasureHeight(visibleRows)
    local rows = math.max(1, tonumber(visibleRows) or 1)
    return self.padding * 2 + rows * self.itemHeight + (rows - 1) * self.spacing
end

function Grid:Release()
    if self.released then return end
    self.scrollBox:RemoveDataProvider()
    self.frame:Hide()
    self.released = true
end

-- opts:
--   itemWidth、itemHeight = 格子尺寸；stride = 固定每行个数（缺省按宽度自动算）
--   spacing = 格距（缺省 GM.space.specTileGap）；padding = 四周留白（缺省选中柔光外扩 GM.settings.parts.iconPickGlow）
--   radius = 选中描边圆角（缺省 GM.radius.control）
--   createItem(frame, grid)、bindItem(frame, data, index, grid)、releaseItem(frame, data, grid)
--   isSelected(data)、onItemClick(frame, data, button, grid)
-- 返回对象方法同表格（没有表头）。
function EXUI:CreateVirtualGrid(parent, opts)
    Check(type(opts) == "table" and tonumber(opts.itemWidth) and tonumber(opts.itemHeight), "opts.itemWidth / itemHeight required")
    local g = setmetatable({
        items = {}, enabled = true, itemHeight = opts.itemHeight,
        spacing = tonumber(opts.spacing) or GM.space.specTileGap,
        padding = tonumber(opts.padding) or GM.settings.parts.iconPickGlow,
        radius = opts.radius or GM.radius.control,
        createItem = opts.createItem, bindItem = opts.bindItem, releaseItem = opts.releaseItem,
        isSelected = opts.isSelected, onItemClick = opts.onItemClick,
    }, Grid)
    CreateScrollParts(g, parent, 0)
    local pad, spacing = g.padding, g.spacing
    local view = CreateScrollBoxListGridView(tonumber(opts.stride) or 1, pad, pad, pad, pad, spacing, spacing)
    if not tonumber(opts.stride) then view:SetStrideExtent(opts.itemWidth) end
    view:SetElementSize(opts.itemWidth, opts.itemHeight)
    view:SetElementInitializer("Button", function(frame, data) g:_InitItem(frame, data) end)
    view:SetElementResetter(function(frame, data) g:_ResetItem(frame, data) end)
    ConnectView(g, view)
    return g
end

-- =========================================================
-- V2 自定义 component 适配：owner.components[ref] = EXUI:CreateVirtualTableComponent(spec)
-- spec:
--   kind = "table"（缺省）| "grid"；opts = 同 CreateVirtualTable / CreateVirtualGrid 的 opts
--   data(context) → items：mount、update 时取数据（update 保留滚动位置）
--   visibleRows = 视口行数（measure 按它给高度）；或 height = 固定高
-- onRowClick / onItemClick 每次挂载套当次 context:Guard；格子里业务按钮的回调由调用方用 table.context:Guard 包
-- （create 只跑一次，按钮回调里现取 table.context，不要在 create 里捕获 context）。
-- =========================================================
function EXUI:CreateVirtualTableComponent(spec)
    Check(type(spec) == "table" and type(spec.opts) == "table" and type(spec.data) == "function", "spec.opts / spec.data required")
    -- 页面每次重挂都会 mount / release；框体不能销毁，释放后的整套表格留给同一 component 下次挂载复用。
    local parked = {}
    local adapter = {}
    function adapter.mount(host, context)
        local widget = table.remove(parked)
        if widget then
            widget.frame:SetParent(host)
            widget.frame:Show()
            widget.enabled = true
        else
            local opts = CopyTable(spec.opts, true)
            widget = spec.kind == "grid" and EXUI:CreateVirtualGrid(host, opts) or EXUI:CreateVirtualTable(host, opts)
            widget.frame._exVirtualTable = widget
        end
        widget.context = context
        if spec.opts.onRowClick then widget.onRowClick = context:Guard(spec.opts.onRowClick) end
        if spec.opts.onItemClick then widget.onItemClick = context:Guard(spec.opts.onItemClick) end
        widget:SetData(spec.data(context))
        return widget.frame
    end
    function adapter.update(frame, context)
        local widget = frame._exVirtualTable
        widget.context = context
        widget:SetData(spec.data(context), { retainScroll = true })
    end
    function adapter.measure(frame)
        return tonumber(spec.height) or frame._exVirtualTable:MeasureHeight(spec.visibleRows)
    end
    function adapter.layout(frame, context, width, height)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT")
        frame:SetSize(width, height)
    end
    function adapter.setEnabled(frame, context, enabled)
        frame._exVirtualTable:SetEnabled(enabled)
    end
    function adapter.setVisible(frame, context, visible)
        frame:SetShown(visible)
    end
    function adapter.release(frame)
        local widget = frame._exVirtualTable
        -- 清空数据：可视行全部走 releaseRow / 列 release，业务状态在这里解绑。
        widget:SetData({})
        widget.context, widget.onRowClick, widget.onItemClick = nil, nil, nil
        frame:Hide()
        frame:ClearAllPoints()
        parked[#parked + 1] = widget
    end
    return adapter
end
