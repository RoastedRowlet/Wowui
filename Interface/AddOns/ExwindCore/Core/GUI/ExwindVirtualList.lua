-- =========================================================
-- ExwindVirtualList.lua - 事件驱动的可复用虚拟列表
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local VirtualList = {}
ExwindTools.VirtualList = VirtualList
_G.ExwindVirtualList = VirtualList

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function GetSlotCount(list)
    local height = math.max(1, list:GetHeight() or 1)
    local count = math.max(1, math.ceil(height / list.rowHeight) + list.overscan)
    if list.maxRows then
        count = math.min(count, list.maxRows)
    end
    return count
end

function VirtualList:Create(parent, options)
    options = type(options) == "table" and options or {}
    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list.rowHeight = math.max(20, tonumber(options.rowHeight) or 42)
    list.overscan = math.max(0, math.floor(tonumber(options.overscan) or 1))
    list.maxRows = tonumber(options.maxRows)
    if list.maxRows then list.maxRows = math.max(1, math.floor(list.maxRows)) end
    list.createRow = options.createRow
    list.bindRow = options.bindRow
    list.rows = {}
    list.items = {}
    list.offset = 0
    list.context = nil
    list:EnableMouseWheel(true)

    -- A virtual list does not have a ScrollFrame to bind, but its visible
    -- scrollbar should still be the same native thin control as every page.
    list.scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    list.scrollBar:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -4)
    list.scrollBar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 4)
    list.scrollBar:Hide()

    function list:EnsureRows()
        local wanted = GetSlotCount(self)
        while #self.rows < wanted do
            local row = type(self.createRow) == "function" and self.createRow(self) or CreateFrame("Frame", nil, self)
            row:SetParent(self)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -((#self.rows) * self.rowHeight))
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -12, -((#self.rows) * self.rowHeight))
            row:SetHeight(self.rowHeight)
            -- 鼠标落在实际行上时也交给列表滚动，避免子控件吞掉滚轮事件。
            if row.EnableMouseWheel then row:EnableMouseWheel(true) end
            row:SetScript("OnMouseWheel", function(_, delta)
                self:SetOffset(self.offset - (tonumber(delta) or 0))
            end)
            self.rows[#self.rows + 1] = row
        end
    end

    function list:GetMaxOffset()
        return math.max(0, #self.items - GetSlotCount(self))
    end

    function list:UpdateScrollBar(maxOffset)
        maxOffset = maxOffset or self:GetMaxOffset()
        local itemCount = #self.items
        local visibleRows = GetSlotCount(self)
        local percentage = maxOffset > 0 and (self.offset / maxOffset) or 0

        self._syncingScrollBar = true
        self.scrollBar:SetScrollPercentage(percentage, ScrollBoxConstants.NoScrollInterpolation)
        self.scrollBar:SetVisibleExtentPercentage(itemCount > 0 and math.min(1, visibleRows / itemCount) or 1)
        self.scrollBar:SetPanExtentPercentage(maxOffset > 0 and (1 / maxOffset) or 1)
        self._syncingScrollBar = nil
        self.scrollBar:SetShown(maxOffset > 0)
    end

    function list:Refresh()
        -- 在 custom host 完成最终尺寸前，列表会经历若干次 SizeChanged。
        -- 空数据不应预创建行/复合控件，否则首次打开会产生无效分配和闪动。
        if #self.items == 0 then
            self.offset = 0
            self:UpdateScrollBar(0)
            for _, row in ipairs(self.rows) do row:Hide() end
            return
        end

        self:EnsureRows()
        local maxOffset = self:GetMaxOffset()
        self.offset = math.floor(Clamp(self.offset, 0, maxOffset) + 0.5)
        self:UpdateScrollBar(maxOffset)
        for slot, row in ipairs(self.rows) do
            local index = self.offset + slot
            local item = self.items[index]
            if item then
                row:SetShown(true)
                if type(self.bindRow) == "function" then
                    self.bindRow(row, item, index, self.context, self)
                end
            else
                if type(self.bindRow) == "function" then
                    self.bindRow(row, nil, nil, nil, self)
                end
                row:Hide()
            end
        end
    end

    function list:SetData(items, context)
        self.items = type(items) == "table" and items or {}
        self.context = context
        self.offset = 0
        self:Refresh()
    end

    function list:SetOffset(offset)
        self.offset = math.floor(Clamp(offset, 0, self:GetMaxOffset()) + 0.5)
        self:Refresh()
    end

    function list:ReleaseData()
        self:SetData({}, nil)
        self:Hide()
    end

    list.scrollBar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percentage)
        if list._syncingScrollBar then return end
        list:SetOffset((tonumber(percentage) or 0) * list:GetMaxOffset())
    end, list)
    list:SetScript("OnMouseWheel", function(_, delta)
        list:SetOffset(list.offset - (tonumber(delta) or 0))
    end)
    list:SetScript("OnSizeChanged", function()
        list:Refresh()
    end)

    return list
end
