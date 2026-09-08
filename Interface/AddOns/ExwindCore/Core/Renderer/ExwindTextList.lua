-- =========================================================
-- ExwindTextList.lua
--
-- 只服务「动态双列文字行」：每一行固定为 label + value 两个 TextWidget。
-- Collection 不读 ModuleDB、不订阅 State；模块只交付同一份 presentation，
-- Runtime / World / Panel 均调用 SetItems。Panel 可选地发出纯 GUI 跳转意图。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local LIST_ROOT_POOL = "RuntimeTextListRoot"
local ROW_ROOT_POOL = "RuntimeTextListRowRoot"

EXFactory:InitPool(LIST_ROOT_POOL, "Frame", "BackdropTemplate", function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
end)

EXFactory:InitPool(ROW_ROOT_POOL, "Frame", nil, function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
end)

local function NumberOr(value, fallback)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge and value or fallback
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    return copy
end

local function NormalizeAlign(value, fallback)
    value = tostring(value or fallback or "LEFT"):match("^([^:]+):") or value or fallback or "LEFT"
    if value ~= "LEFT" and value ~= "CENTER" and value ~= "RIGHT" then return fallback or "LEFT" end
    return value
end

local function ApplyText(widget, spec, width, height)
    spec = type(spec) == "table" and spec or {}
    local style = CopyTable(spec.style)
    style.x, style.y = 0, 0
    style.justifyH = NormalizeAlign(style.justifyH or style.align, "LEFT")
    style.justifyV, style.wordWrap = "MIDDLE", false
    -- ResetSecretText removes the FontString style.  This order is mandatory
    -- when an item switches from a secret runtime value to a normal sample.
    widget:ResetSecretText()
    widget:ApplyStyle(style)
    if spec.secretText == true then widget:SetSecretText(spec.text) else widget:SetText(spec.text or "") end
    widget:SetBounds(width, height)
end

local function ReleaseRow(row)
    if not row then return end
    row:SetScript("OnMouseUp", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:EnableMouse(false)
    if row.label then row.label:Release(); row.label = nil end
    if row.value then row.value:Release(); row.value = nil end
    row:Hide()
    row:ClearAllPoints()
    row:SetSize(1, 1)
    EXFactory:Release(ROW_ROOT_POOL, row)
end

local function AcquireRow(collection, id)
    local row = collection.rowsByID[id]
    if row then return row end
    row = EXFactory:Acquire(ROW_ROOT_POOL, collection.root)
    row.id = id
    row.label = EXUI:CreateTextWidget(row, "textListLabel")
    row.value = EXUI:CreateTextWidget(row, "textListValue")
    collection.rowsByID[id] = row
    return row
end

local function ApplyBackdrop(collection, spec)
    spec = type(spec) == "table" and spec or {}
    local root = collection.root
    if spec.shown ~= true then
        root:SetBackdrop(nil)
        return
    end
    root:SetBackdrop({
        bgFile = spec.bgFile,
        edgeFile = spec.edgeFile,
        edgeSize = NumberOr(spec.edgeSize, 1),
        insets = {
            left = NumberOr(spec.insetLeft, 0), right = NumberOr(spec.insetRight, 0),
            top = NumberOr(spec.insetTop, 0), bottom = NumberOr(spec.insetBottom, 0),
        },
    })
    local bg = type(spec.bgColor) == "table" and spec.bgColor or {}
    local border = type(spec.borderColor) == "table" and spec.borderColor or {}
    root:SetBackdropColor(NumberOr(bg.r, 0), NumberOr(bg.g, 0), NumberOr(bg.b, 0), NumberOr(bg.a, 0))
    root:SetBackdropBorderColor(NumberOr(border.r, 1), NumberOr(border.g, 1), NumberOr(border.b, 1), NumberOr(border.a, 1))
end

-- Panel 行只发出模块声明的点击意图；不会参与 runtime/world 输入，也不会修改 DB。
local function ConfigurePanelRowInteraction(collection, row, item)
    row:SetScript("OnMouseUp", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:EnableMouse(false)

    local interaction = item and item.interaction
    local emitIntent = collection.callbacks and collection.callbacks.onIntent
    if collection.interactionMode ~= "panel" or type(interaction) ~= "table" or type(emitIntent) ~= "function" then
        return
    end

    local elementID = interaction.elementID
    if type(elementID) ~= "string" or elementID == "" then return end
    local guiTarget = interaction.guiTarget or elementID
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            emitIntent({ type = "elementClicked", elementID = elementID, guiTarget = guiTarget })
        elseif button == "RightButton" then
            emitIntent({ type = "elementRightClicked", elementID = elementID, guiTarget = guiTarget })
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(interaction.tooltip or L["可编辑元素"], 0.72, 0.94, 1.00)
        GameTooltip:AddLine(L["左键打开设置"], 0.78, 0.88, 1.00)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
end

local function PlaceColumn(widget, row, align, side, width, height, x, y, inset, gap)
    widget:ClearAllPoints()
    widget:SetBounds(width * 0.5 - inset - gap, height)
    if side == "label" then
        if align == "LEFT" then
            widget:SetAnchor("LEFT", row, "LEFT", inset + x, y)
        elseif align == "CENTER" then
            widget:SetAnchor("CENTER", row, "LEFT", width * 0.25 + x, y)
        else
            widget:SetAnchor("RIGHT", row, "CENTER", -gap + x, y)
        end
    elseif align == "RIGHT" then
        widget:SetAnchor("RIGHT", row, "RIGHT", -inset + x, y)
    elseif align == "CENTER" then
        widget:SetAnchor("CENTER", row, "RIGHT", -width * 0.25 + x, y)
    else
        widget:SetAnchor("LEFT", row, "CENTER", gap + x, y)
    end
end

local function SetItems(collection, items, layout)
    layout = type(layout) == "table" and layout or {}
    local width = math.max(1, NumberOr(layout.width, 220))
    local rowHeight = math.max(1, NumberOr(layout.rowHeight, 20))
    local spacing = NumberOr(layout.spacing, 0)
    local inset = math.max(0, NumberOr(layout.inset, 8))
    local gap = math.max(0, NumberOr(layout.gap, 4))
    local paddingTop = math.max(0, NumberOr(layout.paddingTop, 0))
    local paddingBottom = math.max(0, NumberOr(layout.paddingBottom, 0))
    local labelAlign = NormalizeAlign(layout.labelAlign, "LEFT")
    local valueAlign = NormalizeAlign(layout.valueAlign, "RIGHT")
    local labelX, valueX = NumberOr(layout.labelX, 0), NumberOr(layout.valueX, 0)
    local wanted, ordered = {}, {}
    local y = -paddingTop

    for index, item in ipairs(type(items) == "table" and items or {}) do
        local id = tostring(item.id or index)
        wanted[id] = true
        local row = AcquireRow(collection, id)
        row:SetParent(collection.root)
        row:SetSize(width, rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", collection.root, "TOPLEFT", 0, y)

        local labelSpec, valueSpec = item.label or {}, item.value or {}
        ApplyText(row.label, labelSpec, width * 0.5 - inset - gap, rowHeight)
        ApplyText(row.value, valueSpec, width * 0.5 - inset - gap, rowHeight)
        PlaceColumn(row.label, row, labelAlign, "label", width, rowHeight,
            NumberOr((labelSpec.style or {}).x, 0) + labelX, NumberOr((labelSpec.style or {}).y, 0), inset, gap)
        PlaceColumn(row.value, row, valueAlign, "value", width, rowHeight,
            NumberOr((valueSpec.style or {}).x, 0) + valueX, NumberOr((valueSpec.style or {}).y, 0), inset, gap)
        row:Show()
        ConfigurePanelRowInteraction(collection, row, item)
        ordered[#ordered + 1] = row
        y = y - rowHeight - spacing
    end

    for id, row in pairs(collection.rowsByID) do
        if not wanted[id] then
            collection.rowsByID[id] = nil
            ReleaseRow(row)
        end
    end

    local count = #ordered
    local height = paddingTop + paddingBottom
    if count > 0 then height = height + count * rowHeight + math.max(0, count - 1) * spacing end
    collection.root:SetSize(width, math.max(1, height))
    collection.root:Show()
    ApplyBackdrop(collection, layout.backdrop)
    collection.bounds = { width = width, height = math.max(1, height), anchorOffsetX = 0, anchorOffsetY = 0 }
    collection.items = ordered
    collection.currentLayout = layout
    return collection.bounds
end

local function ReleaseCollection(collection)
    if not collection or collection.released then return end
    collection.released = true
    for id, row in pairs(collection.rowsByID) do
        collection.rowsByID[id] = nil
        ReleaseRow(row)
    end
    collection.root:SetBackdrop(nil)
    collection.root:Hide()
    collection.root:ClearAllPoints()
    collection.root:SetSize(1, 1)
    EXFactory:Release(LIST_ROOT_POOL, collection.root)
end

function EXUI:CreateTextList(parent, interactionMode, moduleKey, callbacks)
    if interactionMode ~= "runtime" and interactionMode ~= "world" and interactionMode ~= "panel" then
        error("CreateTextList interactionMode must be runtime, world, or panel", 2)
    end
    if callbacks ~= nil and type(callbacks) ~= "table" then
        error("CreateTextList callbacks must be table or nil", 2)
    end
    local root = EXFactory:Acquire(LIST_ROOT_POOL, parent)
    root._released = false
    root:EnableMouse(false)
    local collection = {
        root = root,
        moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateTextList"),
        interactionMode = interactionMode,
        callbacks = callbacks,
        rowsByID = {},
        items = {},
        bounds = { width = 1, height = 1, anchorOffsetX = 0, anchorOffsetY = 0 },
        released = false,
    }
    collection.SetItems = SetItems
    collection.Release = ReleaseCollection
    -- Resolver only reuses rows that are already materialized.  It deliberately
    -- does not call SetItems/AcquireRow: topology changes remain normal render
    -- lifecycle work, while GUI value changes reapply current DB presentation.
    function collection:ReapplyExistingItems(resolver)
        if self.released then return false end
        if type(resolver) ~= "function" then error("ReapplyExistingItems requires resolver", 2) end
        local layout = self.currentLayout or {}
        local width = math.max(1, NumberOr(layout.width, self.bounds.width))
        local rowHeight = math.max(1, NumberOr(layout.rowHeight, 20))
        local inset, gap = math.max(0, NumberOr(layout.inset, 8)), math.max(0, NumberOr(layout.gap, 4))
        local labelAlign = NormalizeAlign(layout.labelAlign, "LEFT")
        local valueAlign = NormalizeAlign(layout.valueAlign, "RIGHT")
        local labelX, valueX = NumberOr(layout.labelX, 0), NumberOr(layout.valueX, 0)
        for id, row in pairs(self.rowsByID) do
            local item = resolver(id)
            if item then
                row:SetSize(width, rowHeight)
                local labelSpec, valueSpec = item.label or {}, item.value or {}
                ApplyText(row.label, labelSpec, width * 0.5 - inset - gap, rowHeight)
                ApplyText(row.value, valueSpec, width * 0.5 - inset - gap, rowHeight)
                PlaceColumn(row.label, row, labelAlign, "label", width, rowHeight, NumberOr((labelSpec.style or {}).x, 0) + labelX, NumberOr((labelSpec.style or {}).y, 0), inset, gap)
                PlaceColumn(row.value, row, valueAlign, "value", width, rowHeight, NumberOr((valueSpec.style or {}).x, 0) + valueX, NumberOr((valueSpec.style or {}).y, 0), inset, gap)
                ConfigurePanelRowInteraction(self, row, item)
            end
        end
        return true
    end
    return collection
end
