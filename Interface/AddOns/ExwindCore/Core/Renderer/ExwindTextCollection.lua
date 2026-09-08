-- =========================================================
-- ExwindTextCollection.lua
--
-- 单文字唯一 Item/Collection 渲染入口。runtime、world、panel 各自拥有
-- collection 实例，但只能消费同一份 TextPresentation。它不读取模块 DB、
-- 不读取或推导 Secret 值，也不暴露 FontString。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local ITEM_ROOT_POOL = "RuntimeTextCollectionItemRoot"

EXFactory:InitPool(ITEM_ROOT_POOL, "Frame", nil, function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
end)

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    return copy
end

local function RequireDeclaredBounds(presentation)
    local bounds = presentation and presentation.declaredBounds
    if type(bounds) ~= "table" then error("TextCollection presentation requires declaredBounds", 3) end
    local left, right, bottom, top = tonumber(bounds.left), tonumber(bounds.right), tonumber(bounds.bottom), tonumber(bounds.top)
    if not left or not right or not bottom or not top or right <= left or top <= bottom then
        error("TextCollection declaredBounds must define left < right and bottom < top", 3)
    end
    return { left = left, right = right, bottom = bottom, top = top }
end

-- presentationScale is visual-only runtime geometry.  It never writes to, or
-- clones, the ModuleDB style table: the producer still passes that table by
-- reference.  A scaled root keeps text and every RegionElements child together.
local function RequirePresentationScale(presentation)
    local scale = presentation and presentation.presentationScale
    if scale == nil then return 1 end
    if type(scale) ~= "number" or scale ~= scale or scale <= 0 then
        error("TextCollection presentationScale must be a positive ordinary number", 3)
    end
    return scale
end

local function ResolveAnchor(presentation)
    local anchor = type(presentation and presentation.anchor) == "table" and presentation.anchor or {}
    return {
        point = anchor.point or "CENTER", relativePoint = anchor.relativePoint or anchor.point or "CENTER",
        x = tonumber(anchor.x) or 0, y = tonumber(anchor.y) or 0,
    }
end

local function ResolveSlot(presentation)
    local slot = presentation and (presentation.semanticSlot or presentation.slotID)
    if type(slot) ~= "string" or slot == "" then slot = "core.text" end
    return slot
end

-- 活动倒数文字的唯一合同是 DUR。普通与 Secret Duration 都只原样交给
-- TextWidget 的原生 DurationTextBinding；Collection 不读取、换算或格式化它。
local function ApplyDurationText(collection, widget, presentation)
    if presentation.durationObject ~= nil then
        widget:SetDurationBinding(presentation.durationObject, presentation.durationOptions)
        return true
    end
    if presentation.secretDuration ~= nil then
        widget:SetDurationBinding(presentation.secretDuration, presentation.durationOptions)
        return true
    end
    if presentation.start ~= nil and presentation.duration ~= nil then
        EXUI:ReportDurationViolation(collection.moduleKey, "TextCollection legacy start/duration")
    end
    widget:ClearDurationBinding()
    return false
end

local function ApplyTextPresentation(item, presentation)
    local widget = item.widget
    local style = presentation.style
    if type(style) ~= "table" then error("TextCollection presentation requires direct style table", 3) end
    if presentation.font ~= nil then error("TextCollection font override is removed; declare it in the direct style table", 3) end
    -- Anchor is the collection-level semantic position.  Suppress only the
    -- second visual offset; style remains the original ModuleDB table.
    widget:SetStylePositionOverride(0, 0)
    widget:ResetSecretText()
    widget:ApplyStyle(style)
    -- A producer may pass Secret text straight through, but the collection does
    -- not inspect, compare, convert, or measure it.
    if not ApplyDurationText(item.collection, widget, presentation) then
        if presentation.secretText == true then widget:SetSecretText(presentation.text) else widget:SetText(presentation.text or "") end
    end
    if type(presentation.color) == "table" then widget:SetColor(presentation.color) end
    local bounds = item.declaredBounds
    if presentation.unboundedWidth == true then
        -- 无界公告仍保留 producer 的固定 declaredBounds：TextCollection 的多行
        -- collection 要求每项拥有相同的语义尺寸。视觉 FontString 不设 Bounds，
        -- 因而普通、Secret 与 Duration 文本都不会被固定宽度或宿主容器截断。
        widget:ClearBounds()
    else
        widget:SetBounds(bounds.right - bounds.left, bounds.top - bounds.bottom)
    end
    item.anchor = ResolveAnchor(presentation)
    -- 设置页 Panel 是固定预览 dock，不是世界主 Region 的第二个位置。
    -- 因而主文字的 anchor XY 只作用于 World / Runtime；Panel 永远居中预览。
    if item.collection and item.collection.interactionMode == "panel" and presentation.panelAnchorLocked ~= false then
        item.anchor.x, item.anchor.y = 0, 0
    end
    widget:ClearAllPoints()
    widget:SetAnchor(item.anchor.point, item.root, item.anchor.relativePoint, item.anchor.x, item.anchor.y)
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
    overlay._textCollectionDrag = nil
    if detach then overlay:SetParent(nil) end
end

-- Text is positioned by an explicit semantic rectangle.  The panel border is
-- a child of that rectangle's input overlay, keeping the visual affordance,
-- hit target, drag feedback and pool cleanup in one Core-owned object.
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

local function EmitIntent(collection, intent)
    local callback = collection.callbacks and collection.callbacks.onIntent
    if type(callback) == "function" then callback(intent) end
end

local function ApplyOverlayBounds(item, position)
    local bounds = item.declaredBounds
    local overlay = item.interactionOverlay
    local x = tonumber(position and position.x) or 0
    local y = tonumber(position and position.y) or 0
    overlay:ClearAllPoints()
    overlay:SetSize(bounds.right - bounds.left, bounds.top - bounds.bottom)
    overlay:SetPoint("CENTER", item.root, "CENTER", (bounds.left + bounds.right) * 0.5 + x, (bounds.bottom + bounds.top) * 0.5 + y)
end

-- A Text collection may have several preview rows (for example health curve
-- notices) that all consume one font_text X/Y setting.  Panel dragging must
-- transiently project that one position to every materialized row, while the
-- standard intent handler remains the only DB writer on mouse-up.
local function ApplyTransientTextPosition(collection, position)
    for _, candidate in ipairs(collection.currentItems or {}) do
        if candidate and candidate.presentation and candidate.widget then
            local anchor = ResolveAnchor(candidate.presentation)
            anchor.x, anchor.y = position.x, position.y
            candidate.anchor = anchor
            candidate.widget:ClearAllPoints()
            candidate.widget:SetAnchor(anchor.point, candidate.root, anchor.relativePoint, anchor.x, anchor.y)
            if candidate.interactionOverlay and candidate.interactionOverlay:IsShown() then
                ApplyOverlayBounds(candidate, position)
            end
        end
    end
end

local function ConfigurePanelInteraction(collection, item, interaction)
    local overlay = item.interactionOverlay
    if collection.interactionMode ~= "panel" or type(interaction) ~= "table" then
        ResetOverlay(overlay, false)
        return
    end
    if not overlay then
        overlay = CreateFrame("Button", nil, item.root)
        item.interactionOverlay = overlay
    end
    EnsureInteractionHighlight(overlay)
    if overlay:GetParent() ~= item.root then overlay:SetParent(item.root) end
    ApplyOverlayBounds(item, item.anchor)
    overlay:SetFrameStrata(item.widget:GetFrameStrata() or "MEDIUM")
    overlay:SetFrameLevel((item.widget:GetFrameLevel() or 0) + 50)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    overlay:SetScript("OnMouseDown", function(self, button)
        local elementID = interaction.elementID or item.semanticSlot
        if button == "RightButton" then
            EmitIntent(collection, { type = "elementRightClicked", elementID = elementID, guiTarget = interaction.guiTarget or elementID })
            return
        end
        -- TextCollection is shared.  Only an explicit presentation opt-in may
        -- use its panel text as a movable, free-positioned element; legacy
        -- text collections still own their locked semantic layout.
        if button ~= "LeftButton" or interaction.movable ~= true
            or item.presentation.panelAnchorLocked ~= false then return end
        local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local cursorX, cursorY = GetCursorPosition()
        local anchor = item.anchor or ResolveAnchor(item.presentation)
        self._textCollectionDrag = {
            scale = scale, cursorX = cursorX / scale, cursorY = cursorY / scale,
            baseX = tonumber(anchor.x) or 0, baseY = tonumber(anchor.y) or 0,
            position = { x = tonumber(anchor.x) or 0, y = tonumber(anchor.y) or 0 }, moved = false,
        }
        self:SetScript("OnUpdate", function(buttonFrame)
            local drag = buttonFrame._textCollectionDrag
            if not drag then return end
            if not IsMouseButtonDown("LeftButton") then
                buttonFrame:SetScript("OnUpdate", nil)
                buttonFrame._textCollectionDrag = nil
                return
            end
            local x, y = GetCursorPosition()
            local dx, dy = x / drag.scale - drag.cursorX, y / drag.scale - drag.cursorY
            if not drag.moved and math.abs(dx) < 2 and math.abs(dy) < 2 then return end
            drag.moved = true
            drag.position.x, drag.position.y = drag.baseX + dx, drag.baseY + dy
            ApplyTransientTextPosition(collection, drag.position)
        end)
    end)
    overlay:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local drag = self._textCollectionDrag
        self:SetScript("OnUpdate", nil)
        self._textCollectionDrag = nil
        if drag and drag.moved then
            EmitIntent(collection, { type = "elementMoved", elementID = interaction.elementID or item.semanticSlot,
                position = { x = drag.position.x, y = drag.position.y } })
        end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(interaction.tooltip or (L["可编辑元素："] .. item.semanticSlot), 0.72, 0.94, 1.00)
        GameTooltip:AddLine(interaction.movable == true and L["左键拖动位置；右键定位设置"] or L["右键定位设置"], 0.78, 0.88, 1.00)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function(self)
        if self.highlight then self.highlight:Hide() end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    overlay:Show()
end

local function AcquireItemRoot(parent)
    local root = EXFactory:Acquire(ITEM_ROOT_POOL, parent)
    root:EnableMouse(false)
    root:SetSize(1, 1)
    root:ClearAllPoints()
    root:SetAlpha(1)
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
    root:SetAlpha(1)
    root:SetParent(UIParent)
    EXFactory:Release(ITEM_ROOT_POOL, root)
end

local function NewItem(collection, itemID)
    local root = AcquireItemRoot(collection.layout)
    local item = { id = itemID, root = root, widget = EXUI:CreateTextWidget(root, "collectionText") }
    function item:GetRoot() return self.root end
    item.regions = EXUI:CreateRegionElements({
        ownerRoot = root,
        moduleKey = collection.moduleKey,
        interactionMode = collection.interactionMode,
        resolveCore = function(elementID)
            local bounds = item.declaredBounds or { left = -.5, right = .5, bottom = -.5, top = .5 }
            if elementID == "core.root" then return root, bounds end
            if elementID == "core.text" then return item.widget, bounds end
            error("TextCollection unknown RegionElements core anchor: " .. tostring(elementID), 3)
        end,
        emitIntent = function(intent)
            local callback = collection.callbacks and collection.callbacks.onIntent
            if type(callback) == "function" then callback(intent) end
        end,
    })
    return item
end

local function CopyLayout(layout, contentCenter)
    local copy = CopyTable(layout)
    copy.mode, copy.contentCenter = "SEMANTIC", contentCenter == true
    return copy
end

local function UnionBounds(acc, bounds, offset)
    local x, y = tonumber(offset and offset.x) or 0, tonumber(offset and offset.y) or 0
    local left, right, bottom, top = bounds.left + x, bounds.right + x, bounds.bottom + y, bounds.top + y
    if not acc then return { left = left, right = right, bottom = bottom, top = top } end
    acc.left, acc.right = math.min(acc.left, left), math.max(acc.right, right)
    acc.bottom, acc.top = math.min(acc.bottom, bottom), math.max(acc.top, top)
    return acc
end

local function ScaleBounds(bounds, scale)
    if not bounds then return nil end
    scale = tonumber(scale) or 1
    return {
        left = bounds.left * scale, right = bounds.right * scale,
        bottom = bounds.bottom * scale, top = bounds.top * scale,
    }
end

function EXUI:CreateTextCollection(parent, interactionMode, moduleKey, callbacks)
    if interactionMode ~= "runtime" and interactionMode ~= "world" and interactionMode ~= "panel" then
        error("CreateTextCollection interactionMode must be runtime, world, or panel", 2)
    end
    local collection = { host = parent, moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateTextCollection"), interactionMode = interactionMode, callbacks = callbacks,
        contentCenter = type(callbacks) == "table" and callbacks.contentCenter == true,
        itemsByID = {}, currentItems = {}, itemWidth = 1, itemHeight = 1 }
    collection.layout = EXUI:CreateWidgetLayout(parent, {})

    function collection:AcquireItem(itemID)
        if type(itemID) ~= "string" or itemID == "" then error("TextCollection itemID must be non-empty string", 2) end
        local item = self.itemsByID[itemID]
        if item then return item end
        item = NewItem(self, itemID)
        self.itemsByID[itemID] = item
        return item
    end

    function collection:ApplyItem(item, presentation)
        if not item or not item.widget then error("TextCollection ApplyItem requires an acquired item", 2) end
        if type(presentation) ~= "table" then error("TextCollection presentation must be table", 2) end
        item.presentation, item.declaredBounds, item.semanticSlot = presentation, RequireDeclaredBounds(presentation), ResolveSlot(presentation)
        item.presentationScale = RequirePresentationScale(presentation)
        item.collection = self
        ApplyTextPresentation(item, presentation)
        local baseWidth, baseHeight = item.declaredBounds.right - item.declaredBounds.left, item.declaredBounds.top - item.declaredBounds.bottom
        item.bodyWidth, item.bodyHeight = baseWidth * item.presentationScale, baseHeight * item.presentationScale
        item.root:SetScale(item.presentationScale)
        item.root:SetSize(baseWidth, baseHeight)
        item.root:Show()
        ConfigurePanelInteraction(self, item, presentation.interaction)
        item.regions:SetConfigContextID(presentation.regionConfigContextID)
        item.regions:Apply(presentation.regionElements)
        return item
    end

    function collection:SetItems(items, layout)
        local width, height
        for _, item in ipairs(items or {}) do
            if not item or not item.bodyWidth then error("TextCollection SetItems requires every item to be applied", 2) end
            if not width then width, height = item.bodyWidth, item.bodyHeight
            elseif width ~= item.bodyWidth or height ~= item.bodyHeight then error("TextCollection requires one uniform declared bounds size per collection", 2) end
        end
        if width then self.itemWidth, self.itemHeight = width, height end
        local wanted = {}
        for _, item in ipairs(items or {}) do wanted[item.id] = true end
        for id, item in pairs(self.itemsByID) do if not wanted[id] then item.root:Hide() end end
        self.layout:ApplyStyle(CopyLayout(layout, self.contentCenter))
        self.layout:SetSemanticItems(items or {}, self.itemWidth, self.itemHeight)
        self.currentItems = items or {}
        self.currentLayout = layout
        return self
    end

    -- 与 Icon/TimerBar Collection 相同：GUI Slider 的 live 阶段只能重套已经
    -- 物化的 presentation；不得 Acquire/Release item。完整 Render 仍属于
    -- 模块 commit 刷新。
    function collection:ReapplyCurrentItems(mutatePresentation)
        for _, item in ipairs(self.currentItems or {}) do
            if item and item.widget and item.presentation then
                if type(mutatePresentation) == "function" then
                    mutatePresentation(item.presentation, item)
                end
                self:ApplyItem(item, item.presentation)
            end
        end
        self:SetItems(self.currentItems, self.currentLayout or {
            mode = "SEMANTIC", direction = "UP", spacing = 0, maxVisible = 1,
        })
        return true
    end

    function collection:GetWorldBounds()
        local bounds, offsets = nil, self.layout:GetSemanticItemOffsets()
        for _, item in ipairs(self.currentItems or {}) do
            if item.declaredBounds then bounds = UnionBounds(bounds, ScaleBounds(item.declaredBounds, item.presentationScale), offsets[item]) end
            if item.regions then
                local regionBounds = item.regions:GetDeclaredBounds()
                if regionBounds then bounds = UnionBounds(bounds, ScaleBounds(regionBounds, item.presentationScale), offsets[item]) end
            end
        end
        if not bounds then return nil end
        return { anchor = self.layout, left = bounds.left, right = bounds.right, bottom = bounds.bottom, top = bounds.top,
            width = math.max(1, bounds.right - bounds.left), height = math.max(1, bounds.top - bounds.bottom),
            anchorOffsetX = (bounds.left + bounds.right) * 0.5, anchorOffsetY = (bounds.bottom + bounds.top) * 0.5 }
    end
    function collection:GetBounds() return self.layout:GetBounds() end
    function collection:GetItems() return self.itemsByID end
    -- Runtime animations (for example a fading announcement) may adjust the
    -- item's root alpha without reaching through the collection into a private
    -- TextWidget/FontString tree.  The value is visual-only and never changes
    -- presentation, layout, declared bounds, or module state.
    function collection:SetItemAlpha(itemID, alpha)
        local item = self.itemsByID[itemID]
        if not item or not item.widget then return false end
        alpha = math.max(0, math.min(1, tonumber(alpha) or 1))
        item.widget:SetAlpha(alpha)
        return true
    end
    -- 动画由 Collection 拥有 ItemRoot；模块只能交纯数值阶段，不能取得或操作 Frame。
    function collection:PlayItemAlphaSequence(itemID, phases, onFinished)
        local item = self.itemsByID[itemID]
        if not item or not item.root or type(phases) ~= "table" or #phases == 0 then return false end
        if item.alphaAnimation then
            item.alphaAnimation:SetScript("OnFinished", nil)
            item.alphaAnimation:Stop()
            item.alphaAnimation = nil
        end
        local animation = item.root:CreateAnimationGroup()
        for index, phase in ipairs(phases) do
            if type(phase) ~= "table" then error("TextCollection alpha phase must be table", 2) end
            local fromAlpha, toAlpha, duration = tonumber(phase.from), tonumber(phase.to), tonumber(phase.duration)
            if not fromAlpha or not toAlpha or not duration or duration < 0 then
                error("TextCollection alpha phase requires numeric from/to and non-negative duration", 2)
            end
            local alpha = animation:CreateAnimation("Alpha")
            alpha:SetOrder(index)
            alpha:SetFromAlpha(math.max(0, math.min(1, fromAlpha)))
            alpha:SetToAlpha(math.max(0, math.min(1, toAlpha)))
            alpha:SetDuration(duration)
        end
        animation:SetScript("OnFinished", function()
            if item.alphaAnimation ~= animation then return end
            item.alphaAnimation = nil
            if type(onFinished) == "function" then onFinished() end
        end)
        item.alphaAnimation = animation
        animation:Play()
        return true
    end
    function collection:ReleaseItem(itemID)
        local item = self.itemsByID[itemID]
        if not item then return end
        if item.alphaAnimation then
            item.alphaAnimation:SetScript("OnFinished", nil)
            item.alphaAnimation:Stop()
            item.alphaAnimation = nil
        end
        self.itemsByID[itemID] = nil
        ResetOverlay(item.interactionOverlay, true)
        if item.regions then item.regions:Release() end
        item.root:SetScale(1)
        item.widget:Release()
        ReleaseItemRoot(item.root)
        item.widget, item.root, item.presentation, item.declaredBounds, item.anchor, item.interactionOverlay, item.regions, item.presentationScale = nil, nil, nil, nil, nil, nil, nil, nil
    end
    function collection:Release()
        for id in pairs(self.itemsByID) do self:ReleaseItem(id) end
        self.layout:Release()
        self.layout, self.itemsByID, self.currentItems, self.currentLayout, self.callbacks, self.host = nil, nil, nil, nil, nil, nil
    end
    return collection
end
