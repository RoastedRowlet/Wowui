-- ExwindMaterialCollection.lua
-- 单材质唯一 Item/Collection 渲染入口。
--
-- runtime、world、panel 各自拥有 collection，但都只能消费同一 presentation。
-- 它不读取任何模块 DB，也不暴露内部 Texture。实际位置由 WidgetLayout，局部
-- panel 拖动只通过 intent 回写声明位置。

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local ITEM_ROOT_POOL = "RuntimeMaterialCollectionItemRoot"
EXFactory:InitPool(ITEM_ROOT_POOL, "Frame", nil, function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
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

local function CopyLayout(layout, contentCenter)
    local copy = {}
    for key, value in pairs(type(layout) == "table" and layout or {}) do copy[key] = value end
    copy.mode = "SEMANTIC"
    copy.contentCenter = contentCenter == true
    return copy
end

local function RequireDeclaredBounds(presentation)
    local bounds = presentation and presentation.declaredBounds
    if type(bounds) ~= "table" then
        error("MaterialCollection presentation requires declaredBounds", 3)
    end
    local left, right = tonumber(bounds.left), tonumber(bounds.right)
    local bottom, top = tonumber(bounds.bottom), tonumber(bounds.top)
    if not left or not right or not bottom or not top or right <= left or top <= bottom then
        error("MaterialCollection declaredBounds must be a non-empty semantic rectangle", 3)
    end
    return { left = left, right = right, bottom = bottom, top = top }
end

-- 局部位置是 presentation 的语义部分，而不是 panel 交互的临时状态。
-- localOffset 是新声明的明确名称；已有 producer 的 anchor.x/y 可作为同一
-- 语义的兼容输入。二者只在这里归一化一次，三个宿主随后消费完全相同的值。
-- 这段代码不检查任何运行时 Aura/Secret 状态。
local function ResolveLocalOffset(presentation)
    local offset = presentation and presentation.localOffset
    if offset == nil then
        offset = presentation and presentation.anchor
    end
    if offset ~= nil and type(offset) ~= "table" then
        error("MaterialCollection presentation localOffset must be table", 3)
    end
    return {
        x = tonumber(offset and offset.x) or 0,
        y = tonumber(offset and offset.y) or 0,
    }
end

local function CombineOffsets(first, second)
    return {
        x = (tonumber(first and first.x) or 0) + (tonumber(second and second.x) or 0),
        y = (tonumber(first and first.y) or 0) + (tonumber(second and second.y) or 0),
    }
end

local function ApplyLocalOffset(item, offset)
    item.widget:ClearAllPoints()
    item.widget:SetPoint("CENTER", item.root, "CENTER", offset.x, offset.y)
end

local function UnionBounds(acc, bounds, offset)
    -- RegionElementCollection is optional for a material item.  A valid
    -- collection with no declared child region returns nil here; do not let a
    -- selection/world-bounds refresh turn that absence into an editor error.
    if type(bounds) ~= "table" then return acc end
    local x, y = offset and offset.x or 0, offset and offset.y or 0
    local left, right, bottom, top = bounds.left + x, bounds.right + x, bounds.bottom + y, bounds.top + y
    if not acc then return { left = left, right = right, bottom = bottom, top = top } end
    acc.left, acc.right = math.min(acc.left, left), math.max(acc.right, right)
    acc.bottom, acc.top = math.min(acc.bottom, bottom), math.max(acc.top, top)
    return acc
end

local function ResetOverlay(overlay, detach)
    if not overlay then return end
    overlay:SetScript("OnUpdate", nil)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
    if overlay.highlight then
        overlay.highlight:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        overlay.highlight:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
        overlay.highlight:Hide()
    end
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay._materialDrag = nil
    if detach then overlay:SetParent(nil) end
end

-- The panel selection frame is part of the generic interaction layer.  It is
-- bound to the overlay's declared bounds, never to a Material visual region,
-- so changing/pooled textures cannot leave a stale mouse or border rectangle.
local function EnsureInteractionHighlight(overlay)
    if overlay.highlight then return overlay.highlight end
    local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    highlight:SetAllPoints(overlay)
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    highlight:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
    highlight:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
    highlight:Hide()
    overlay.highlight = highlight
    return highlight
end

local function SetInteractionHighlightPressed(overlay, pressed)
    local highlight = overlay and overlay.highlight
    if not highlight then return end
    if pressed then
        highlight:SetBackdropBorderColor(1.00, 0.82, 0.20, 1.00)
        highlight:SetBackdropColor(1.00, 0.72, 0.12, 0.18)
        highlight:Show()
    else
        highlight:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        highlight:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
        highlight:Hide()
    end
end

local function EmitIntent(collection, intent)
    local callback = collection.callbacks and collection.callbacks.onIntent
    if type(callback) == "function" then callback(intent) end
end

local function ConfigurePanelInteraction(collection, item, interaction)
    local overlay = item.interactionOverlay
    if collection.interactionMode ~= "panel" or type(interaction) ~= "table" then
        ResetOverlay(overlay, false)
        return
    end
    if not overlay then
        overlay = CreateFrame("Button", nil, item.widget)
        item.interactionOverlay = overlay
    end
    EnsureInteractionHighlight(overlay)
    if overlay:GetParent() ~= item.widget then overlay:SetParent(item.widget) end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(item.widget)
    overlay:SetFrameStrata(item.widget:GetFrameStrata() or "MEDIUM")
    overlay:SetFrameLevel((item.widget:GetFrameLevel() or 0) + 50)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    overlay:SetScript("OnMouseDown", function(self, button)
        local elementID = interaction.elementID or "core.material"
        if button == "RightButton" then
            EmitIntent(collection, { type = "elementRightClicked", elementID = elementID,
                guiTarget = interaction.guiTarget or elementID })
            return
        end
        if button ~= "LeftButton" or interaction.movable ~= true then return end
        local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local x, y = GetCursorPosition()
        -- Drag 的基准必须是当前 presentation 已应用的局部位置；interaction
        -- 只是输入权限声明，不能拥有另一份 position 真源。
        local position = item.localOffset or {}
        self._materialDrag = { scale = scale, x = x / scale, y = y / scale,
            baseX = tonumber(position.x) or 0, baseY = tonumber(position.y) or 0, moved = false }
        SetInteractionHighlightPressed(self, true)
        self:SetScript("OnUpdate", function(buttonFrame)
            local drag = buttonFrame._materialDrag
            if not drag then return end
            if not IsMouseButtonDown("LeftButton") then
                buttonFrame:GetScript("OnMouseUp")(buttonFrame, "LeftButton")
                return
            end
            local cursorX, cursorY = GetCursorPosition()
            local dx, dy = cursorX / drag.scale - drag.x, cursorY / drag.scale - drag.y
            if not drag.moved and math.abs(dx) < 2 and math.abs(dy) < 2 then return end
            drag.moved = true
            item.widget:ClearAllPoints()
            item.widget:SetPoint("CENTER", item.root, "CENTER", drag.baseX + dx, drag.baseY + dy)
        end)
    end)
    overlay:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local drag = self._materialDrag
        self:SetScript("OnUpdate", nil)
        self._materialDrag = nil
        SetInteractionHighlightPressed(self, false)
        if drag and drag.moved then
            local cursorX, cursorY = GetCursorPosition()
            EmitIntent(collection, { type = "elementMoved", elementID = interaction.elementID or "core.material",
                position = { x = drag.baseX + cursorX / drag.scale - drag.x, y = drag.baseY + cursorY / drag.scale - drag.y } })
        end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(interaction.tooltip or L["可编辑元素：材质"], 0.72, 0.94, 1.00)
        GameTooltip:AddLine(interaction.movable == true and L["左键拖动位置；右键定位设置"] or L["右键定位设置"], 0.78, 0.88, 1.00)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function(self)
        if self.highlight and not self._materialDrag then self.highlight:Hide() end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    overlay:Show()
end

-- A material scene may declare text slots (for example Aura texture's name,
-- time and stacks).  They are part of the same presentation, not a second
-- preview-only tree.  Their positions are relative to ItemRoot, just like
-- native Aura text regions are relative to their AuraButton.
local function ResetTextSlot(item, slotID, detach)
    local widget = item.textWidgets and item.textWidgets[slotID]
    if widget then
        widget:Release()
        item.textWidgets[slotID] = nil
    end
    local overlay = item.textInteractionOverlays and item.textInteractionOverlays[slotID]
    if overlay then
        ResetOverlay(overlay, detach)
        if detach then item.textInteractionOverlays[slotID] = nil end
    end
end

local function TextSlotBounds(slot)
    local bounds = type(slot) == "table" and slot.declaredBounds or nil
    if type(bounds) ~= "table" then return nil end
    local left, right, bottom, top = tonumber(bounds.left), tonumber(bounds.right), tonumber(bounds.bottom), tonumber(bounds.top)
    if not left or not right or not bottom or not top or right <= left or top <= bottom then return nil end
    return { left = left, right = right, bottom = bottom, top = top }
end

local function ResolveTextSlotAnchor(slot)
    local anchor = type(slot and slot.anchor) == "table" and slot.anchor or {}
    return {
        point = anchor.point or "CENTER", relativePoint = anchor.relativePoint or anchor.point or "CENTER",
        x = tonumber(anchor.x) or 0, y = tonumber(anchor.y) or 0,
    }
end

local function ApplyTextSlot(item, slotID, slot)
    if type(slot) ~= "table" or slot.shown == false then
        ResetTextSlot(item, slotID, false)
        return nil
    end
    local bounds = TextSlotBounds(slot)
    if not bounds then error("MaterialCollection text slot requires declaredBounds", 3) end
    local widget = item.textWidgets[slotID]
    if not widget then
        widget = EXUI:CreateTextWidget(item.root, "material:" .. tostring(slotID))
        item.textWidgets[slotID] = widget
    end
    local style = slot.style
    if type(style) ~= "table" then error("MaterialCollection text slot requires direct style table", 3) end
    -- `anchor` is the semantic position.  Suppress only the second visual
    -- offset; never copy or mutate the DB style object.
    widget:SetStylePositionOverride(0, 0)
    widget:ResetSecretText()
    widget:ApplyStyle(style)
    widget:SetText(slot.text or "")
    widget:SetBounds(bounds.right - bounds.left, bounds.top - bounds.bottom)
    local anchor = ResolveTextSlotAnchor(slot)
    widget:SetAnchor(anchor.point, item.root, anchor.relativePoint, anchor.x, anchor.y)
    return { bounds = bounds, anchor = anchor }
end

local function ConfigureTextSlotInteraction(collection, item, slotID, slot, applied, interaction)
    local overlay = item.textInteractionOverlays[slotID]
    if collection.interactionMode ~= "panel" or not applied or type(interaction) ~= "table" then
        if overlay then ResetOverlay(overlay, false) end
        return
    end
    if not overlay then
        overlay = CreateFrame("Button", nil, item.root)
        item.textInteractionOverlays[slotID] = overlay
    elseif overlay:GetParent() ~= item.root then
        overlay:SetParent(item.root)
    end
    EnsureInteractionHighlight(overlay)
    local bounds, anchor = applied.bounds, applied.anchor
    overlay:ClearAllPoints()
    overlay:SetSize(bounds.right - bounds.left, bounds.top - bounds.bottom)
    overlay:SetPoint("CENTER", item.root, "CENTER", anchor.x + (bounds.left + bounds.right) * .5,
        anchor.y + (bounds.bottom + bounds.top) * .5)
    overlay:SetFrameStrata(item.root:GetFrameStrata() or "MEDIUM")
    overlay:SetFrameLevel((item.root:GetFrameLevel() or 0) + 60)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            EmitIntent(collection, { type = "elementRightClicked", elementID = slotID, guiTarget = interaction.guiTarget or slotID })
            return
        end
        if button ~= "LeftButton" or interaction.movable ~= true then return end
        local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local x, y = GetCursorPosition()
        self._materialTextDrag = { scale = scale, x = x / scale, y = y / scale, baseX = anchor.x, baseY = anchor.y, moved = false }
        SetInteractionHighlightPressed(self, true)
        self:SetScript("OnUpdate", function(buttonFrame)
            local drag = buttonFrame._materialTextDrag
            if not drag then return end
            if not IsMouseButtonDown("LeftButton") then buttonFrame:GetScript("OnMouseUp")(buttonFrame, "LeftButton"); return end
            local cursorX, cursorY = GetCursorPosition()
            local dx, dy = cursorX / drag.scale - drag.x, cursorY / drag.scale - drag.y
            if not drag.moved and math.abs(dx) < 2 and math.abs(dy) < 2 then return end
            drag.moved = true
            local nextX, nextY = drag.baseX + dx, drag.baseY + dy
            local text = item.textWidgets[slotID]
            if text then text:SetAnchor(anchor.point, item.root, anchor.relativePoint, nextX, nextY) end
            self:ClearAllPoints()
            self:SetPoint("CENTER", item.root, "CENTER", nextX + (bounds.left + bounds.right) * .5,
                nextY + (bounds.bottom + bounds.top) * .5)
        end)
    end)
    overlay:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local drag = self._materialTextDrag
        self:SetScript("OnUpdate", nil)
        self._materialTextDrag = nil
        SetInteractionHighlightPressed(self, false)
        if drag and drag.moved then
            local cursorX, cursorY = GetCursorPosition()
            EmitIntent(collection, { type = "elementMoved", elementID = slotID,
                position = { x = drag.baseX + cursorX / drag.scale - drag.x, y = drag.baseY + cursorY / drag.scale - drag.y } })
        end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(interaction.tooltip or (L["可编辑元素："] .. tostring(slotID)), 0.72, 0.94, 1.00)
        GameTooltip:AddLine(interaction.movable == true and L["左键拖动位置；右键定位设置"] or L["右键定位设置"], 0.78, 0.88, 1.00)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function(self)
        if self.highlight and not self._materialTextDrag then self.highlight:Hide() end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    overlay:Show()
end

local function ApplyTextSlots(collection, item, presentation)
    local slots = type(presentation.textSlots) == "table" and presentation.textSlots or {}
    local interactions = type(presentation.interaction) == "table" and presentation.interaction.slots or {}
    local wanted = {}
    item.textSlotBounds, item.textSlotAnchors = {}, {}
    for slotID, slot in pairs(slots) do
        if type(slotID) == "string" then
            wanted[slotID] = true
            local applied = ApplyTextSlot(item, slotID, slot)
            if applied then
                item.textSlotBounds[slotID], item.textSlotAnchors[slotID] = applied.bounds, applied.anchor
                ConfigureTextSlotInteraction(collection, item, slotID, slot, applied, interactions[slotID])
            else
                ConfigureTextSlotInteraction(collection, item, slotID, slot, nil, nil)
            end
        end
    end
    for slotID in pairs(item.textWidgets) do if not wanted[slotID] then ResetTextSlot(item, slotID, false) end end
    for slotID, overlay in pairs(item.textInteractionOverlays) do
        if not wanted[slotID] then ResetOverlay(overlay, false) end
    end
end

local function NewItem(collection, itemID)
    local root = AcquireItemRoot(collection.layout)
    local widget = EXUI:CreateExtraTextureWidget(root)
    widget:ClearAllPoints()
    widget:SetPoint("CENTER", root, "CENTER")
    local item = { id = itemID, widget = widget, root = root, textWidgets = {}, textInteractionOverlays = {}, textSlotBounds = {}, textSlotAnchors = {} }
    function item:GetRoot() return self.root end
    item.regions = EXUI:CreateRegionElements({
        ownerRoot = root,
        moduleKey = collection.moduleKey,
        interactionMode = collection.interactionMode,
        resolveCore = function(elementID)
            local bounds = item.declaredBounds or { left = -.5, right = .5, bottom = -.5, top = .5 }
            if elementID == "core.root" then return root, bounds end
            if elementID == "core.material" then return item.widget, bounds end
            error("MaterialCollection unknown RegionElements core anchor: " .. tostring(elementID), 3)
        end,
        emitIntent = function(intent)
            local callback = collection.callbacks and collection.callbacks.onIntent
            if type(callback) == "function" then callback(intent) end
        end,
    })
    return item
end

function EXUI:CreateMaterialCollection(parent, interactionMode, moduleKey, callbacks)
    if interactionMode ~= "runtime" and interactionMode ~= "world" and interactionMode ~= "panel" then
        error("CreateMaterialCollection interactionMode must be runtime, world, or panel", 2)
    end
    local collection = {
        host = parent, moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateMaterialCollection"), interactionMode = interactionMode, callbacks = callbacks,
        contentCenter = type(callbacks) == "table" and callbacks.contentCenter == true,
        itemsByID = {}, currentItems = {}, currentLayout = nil, itemWidth = 1, itemHeight = 1, released = false,
    }
    collection.layout = EXUI:CreateWidgetLayout(parent, {})

    function collection:AcquireItem(itemID)
        if type(itemID) ~= "string" or itemID == "" then error("MaterialCollection itemID must be non-empty string", 2) end
        local item = self.itemsByID[itemID]
        if item then return item end
        item = NewItem(self, itemID)
        self.itemsByID[itemID] = item
        return item
    end

    function collection:ApplyItem(item, presentation)
        if not item or not item.widget then error("MaterialCollection ApplyItem requires an acquired item", 2) end
        if type(presentation) ~= "table" then error("MaterialCollection presentation must be table", 2) end
        item.presentation = presentation
        item.declaredBounds = RequireDeclaredBounds(presentation)
        item.localOffset = ResolveLocalOffset(presentation)
        item.widget:ApplyPresentation(presentation)
        item.bodyWidth, item.bodyHeight = math.max(1, item.widget:GetWidth() or 1), math.max(1, item.widget:GetHeight() or 1)
        item.root:SetSize(item.bodyWidth, item.bodyHeight)
        ApplyLocalOffset(item, item.localOffset)
        ConfigurePanelInteraction(self, item, presentation.interaction)
        ApplyTextSlots(self, item, presentation)
        item.regions:SetConfigContextID(presentation.regionConfigContextID)
        item.regions:Apply(presentation.regionElements)
        return item
    end

    function collection:SetItems(items, layout)
        local width, height
        for _, item in ipairs(items or {}) do
            if not item or not item.bodyWidth then error("MaterialCollection SetItems requires every item to be applied", 2) end
            if not width then width, height = item.bodyWidth, item.bodyHeight
            elseif width ~= item.bodyWidth or height ~= item.bodyHeight then
                error("MaterialCollection requires one uniform body size per collection", 2)
            end
        end
        if width then self.itemWidth, self.itemHeight = width, height end
        local wanted = {}
        for _, item in ipairs(items or {}) do wanted[item.id] = true end
        for id, item in pairs(self.itemsByID) do if not wanted[id] then item.root:Hide() end end
        local layoutStyle = CopyLayout(layout, self.contentCenter)
        self.layout:ApplyStyle(layoutStyle)
        self.layout:SetSemanticItems(items or {}, self.itemWidth, self.itemHeight)
        self.currentItems = items or {}
        self.currentLayout = layoutStyle
        return self
    end

    -- Public existing-item refresh contract.  Callers may only mutate the
    -- persisted presentation table; this collection keeps Region/Widget
    -- ownership private, never acquires/releases items, then reapplies the
    -- same semantic layout so body changes also recalculate collection bounds.
    function collection:ReapplyCurrentItems(mutatePresentation)
        if self.released then return false end
        for _, item in ipairs(self.currentItems or {}) do
            if item and item.widget and item.presentation then
                if type(mutatePresentation) == "function" then
                    mutatePresentation(item.presentation)
                end
                self:ApplyItem(item, item.presentation)
            end
        end
        self:SetItems(self.currentItems or {}, self.currentLayout)
        return true
    end

    function collection:GetWorldBounds()
        local bounds, offsets = nil, self.layout:GetSemanticItemOffsets()
        for _, item in ipairs(self.currentItems or {}) do
            if item.declaredBounds then
                bounds = UnionBounds(bounds, item.declaredBounds, CombineOffsets(offsets[item], item.localOffset))
            end
            for slotID, slotBounds in pairs(item.textSlotBounds or {}) do
                local slotAnchor = item.textSlotAnchors and item.textSlotAnchors[slotID] or nil
                bounds = UnionBounds(bounds, slotBounds, CombineOffsets(offsets[item], slotAnchor))
            end
            if item.regions then
                local regionBounds = item.regions:GetDeclaredBounds()
                if regionBounds then
                    bounds = UnionBounds(bounds, regionBounds, CombineOffsets(offsets[item], item.localOffset))
                end
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

    function collection:ReleaseItem(itemID)
        local item = self.itemsByID[itemID]
        if not item then return end
        self.itemsByID[itemID] = nil
        ResetOverlay(item.interactionOverlay, true)
        if item.regions then item.regions:Release() end
        for slotID in pairs(item.textWidgets or {}) do ResetTextSlot(item, slotID, true) end
        for slotID, overlay in pairs(item.textInteractionOverlays or {}) do
            if not (item.textWidgets and item.textWidgets[slotID]) then ResetOverlay(overlay, true) end
        end
        item.widget:Release()
        ReleaseItemRoot(item.root)
        item.widget, item.root, item.presentation, item.declaredBounds, item.localOffset, item.interactionOverlay = nil, nil, nil, nil, nil, nil
        item.textWidgets, item.textInteractionOverlays, item.textSlotBounds, item.textSlotAnchors, item.regions = nil, nil, nil, nil, nil
    end
    function collection:Release()
        for id in pairs(self.itemsByID) do self:ReleaseItem(id) end
        self.layout:Release()
        self.layout, self.itemsByID, self.currentItems, self.currentLayout, self.callbacks, self.host = nil, nil, nil, nil, nil, nil
        self.released = true
    end
    return collection
end
