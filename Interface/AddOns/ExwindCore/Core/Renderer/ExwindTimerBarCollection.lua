-- =========================================================
-- ExwindTimerBarCollection.lua
-- TimerBar 唯一 Item/Collection 渲染入口。
--
-- 这个文件只服务 TimerBar：每个 ItemRoot 只持有一个 TimerBarWidget。
-- Runtime、世界编辑和 GUI 预览分别拥有自己的 collection 实例，但必须向
-- ApplyItem / SetItems 传入相同结构的 presentation 与 layout。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local ITEM_ROOT_POOL = "RuntimeTimerBarCollectionItemRoot"

EXFactory:InitPool(ITEM_ROOT_POOL, "Frame", nil, function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
end)

local function ApplyIcon(widget, icon)
    if type(icon) == "table" and icon.mode == "SECRET" then
        widget:SetSecretIcon(icon.value)
    else
        widget:SetIcon(type(icon) == "table" and icon.value or icon)
    end
end

-- 层数有三种显式 presentation 语义：
--   NORMAL：stacks 是 Lua 可读的普通值；nil/false/0 都交给 Widget 清空或隐藏。
--   SECRET：secretStacks 是 12.x 受保护值，只能原样透传给 SetSecretStacks。
--   HIDDEN：强制清理前一项（包括 pool 重用留下的 Secret 文本），不读取任何 Secret。
-- 旧的 { mode = "SECRET", value = ... } 包装仍属于同一公开 stacks 契约；新调用方
-- 可用 stacksMode + secretStacks 避免把受保护值塞进普通字段。
local function ApplyStacks(widget, presentation)
    local mode = presentation.stacksMode
    if mode == "SECRET" then
        widget:SetSecretStacks(presentation.secretStacks)
        return
    end
    if mode == "HIDDEN" then
        widget:SetStacks(nil)
        return
    end

    local stacks = presentation.stacks
    if type(stacks) == "table" and stacks.mode == "SECRET" then
        widget:SetSecretStacks(stacks.value)
    else
        local value = type(stacks) == "table" and stacks.value or stacks
        -- 0 仅在普通 Lua 层数契约中等同于“无层数”。Secret 值不会走到这里，
        -- 因而没有读取、比较或转换任何受保护对象。
        if value == 0 then value = nil end
        widget:SetStacks(value)
    end
end

local function ApplyProgress(widget, progress)
    if progress == nil then return end
    if type(progress) == "table" and progress.mode == "SECRET" then
        widget:SetSecretProgress(progress.value, progress.maximum, progress.minimum)
        return
    end
    local value = type(progress) == "table" and progress.value or progress
    local maximum = type(progress) == "table" and (progress.maximum or progress.max) or 1
    local minimum = type(progress) == "table" and progress.minimum or nil
    widget:SetProgress(value or 0, maximum or 1, minimum)
end

-- 主 TimerBar 的局部 XY 属于世界 / Runtime 主 Region。Panel 是固定 preview
-- dock：它不得使用这对 XY，否则设置页会出现本体和预览分别位于左右两侧。
local function ResolveLocalOffset(collection, presentation, standardSchema)
    if collection and collection.interactionMode == "panel" then return { x = 0, y = 0 } end
    -- Standard TimerBar 的主条局部位置只来自模块自己声明的
    -- timerGroup.x/y。模块不得再手写 presentation.localOffset 形成第二条
    -- 位置链；Panel、World、Runtime 都从这同一张 DB 读取。
    if type(standardSchema) == "table" then
        local db = type(presentation) == "table" and presentation.db or nil
        local timerBar = type(db) == "table" and db[standardSchema.timerBarKey] or nil
        if type(timerBar) ~= "table" then
            error("StandardTimerBar presentation requires declared timerBar DB", 3)
        end
        return { x = tonumber(timerBar.x) or 0, y = tonumber(timerBar.y) or 0 }
    end
    local offset = presentation and presentation.localOffset
    if offset ~= nil and type(offset) ~= "table" then
        error("TimerBarCollection presentation localOffset must be table", 3)
    end
    return { x = tonumber(offset and offset.x) or 0, y = tonumber(offset and offset.y) or 0 }
end

local function CombineOffsets(first, second)
    return {
        x = (tonumber(first and first.x) or 0) + (tonumber(second and second.x) or 0),
        y = (tonumber(first and first.y) or 0) + (tonumber(second and second.y) or 0),
    }
end

local function ApplyTime(collection, widget, time)
    if type(time) == "table" and time.mode == "SECRET" then
        widget:SetSecretTime(time.duration, time.interpolation, time.direction)
        return true
    end
    if type(time) == "table" and time.mode == "DURATION" then
        -- An ordinary Duration Object has its own explicit path.  It is not
        -- Secret data and must not fall through to the legacy start/duration
        -- timer, which owns a Lua OnUpdate.
        widget:SetDurationObject(time.duration, time.interpolation, time.direction, time.textOptions)
        return true
    end
    if type(time) == "table" and time.start ~= nil and time.duration ~= nil then
        widget:SetTime(collection.moduleKey, time.start, time.duration, time.modRate, time.countdownFormat)
        return true
    end

    widget:ClearTime()
    local text = type(time) == "table" and time.text or time
    if text ~= nil then
        widget.timeText:SetText(text)
        if not (type(time) == "table" and time.shown == false) then
            widget.timeText:Show()
        end
    end
    return false
end

-- TimerBar 的文本槽必须以稳定语义暴露给 interaction declaration，而不是让
-- collection consumer 读取 widget 的私有 text child。项目可声明自己的非保留
-- semantic，只要显式映射至标准 TimerBar 的 stacks 文字角色。
local TIMERBAR_TEXT_ROLE_BY_SEMANTIC_ID = {
    ["core.spellName"] = "label",
    ["core.targetName"] = "target",
    ["core.time"] = "time",
    ["core.stacks"] = "stacks",
    ["barStacks"] = "stacks",
    ["exaura.barStacks"] = "stacks",
}

local function ResolveTextRole(slotID, requestedRole)
    local role = requestedRole or TIMERBAR_TEXT_ROLE_BY_SEMANTIC_ID[slotID]
    if role == "D" or role == "barStacks" or role == "core.stacks" or role == "exaura.barStacks" then return "stacks" end
    return role
end

local function CanonicalSemanticID(slotID)
    return slotID == "barStacks" and "core.stacks" or slotID
end

-- 当文字来自 Secret 值时，TextWidget 可能没有可测的 glyph metrics。bounds 是
-- 纯布局声明，不含文字值；调用方可放在 interaction slot，或放在 presentation
-- 的 semanticBounds[canonicalID]。没有有效 bounds 时必须禁用局部命中，绝不
-- 用 1x1 或扫描实际 Region 兜底。
local function ResolveSemanticBounds(presentation, slotID, spec)
    local bounds = type(spec) == "table" and spec.semanticBounds or nil
    if type(bounds) ~= "table" then
        local allBounds = type(presentation) == "table" and presentation.semanticBounds or nil
        if type(allBounds) == "table" then
            bounds = allBounds[CanonicalSemanticID(slotID)] or allBounds[slotID]
        end
    end
    if type(bounds) ~= "table" then return nil end
    local width, height = tonumber(bounds.width), tonumber(bounds.height)
    if not width or not height or width <= 0 or height <= 0 then return nil end
    return bounds
end

local function GetTextWidget(widget, role)
    if role == "A" or role == "label" or role == "spellName" then return widget.textA or widget.labelText end
    if role == "B" or role == "target" or role == "targetName" then return widget.textB end
    if role == "C" or role == "time" then return widget.textC or widget.timeText end
    if role == "D" or role == "stacks" or role == "barStacks" or role == "core.stacks" or role == "exaura.barStacks" then return widget.stackText end
    return nil
end

local function ApplyStandardPresentation(collection, item, presentation)
    local widget = item.widget
    local schema = presentation.schema or collection.standardSchema
    local db = presentation.db
    if not schema or type(db) ~= "table" then
        error("StandardTimerBarCollection presentation requires schema and DB", 2)
    end
    EXUI:ApplyStandardTimerBarStyle(widget, db, schema, presentation.styleOverrides)
    EXUI:SetStandardTimerBarContent(widget, collection.moduleKey, presentation.content or {})
    for slot, color in pairs(type(presentation.textColors) == "table" and presentation.textColors or {}) do
        EXUI:SetStandardTimerBarTextColor(widget, slot, color)
    end
    for slot, shown in pairs(type(presentation.textShownFromBoolean) == "table" and presentation.textShownFromBoolean or {}) do
        EXUI:SetStandardTimerBarTextShownFromBoolean(widget, slot, shown)
    end
    local fill = presentation.fillFromBoolean
    if type(fill) == "table" then
        local function color(value)
            if type(value) == "table" and value.r ~= nil then return CreateColor(value.r, value.g, value.b, value.a == nil and 1 or value.a) end
            return value
        end
        widget:SetFillColorFromBoolean(fill.value, color(fill.trueColor), color(fill.falseColor))
    elseif presentation.fillColor then
        widget:SetFillColor(presentation.fillColor)
    end
    local alpha = presentation.alphaFromBoolean
    if type(alpha) == "table" and type(widget.SetAlphaFromBoolean) == "function" then
        widget:SetAlphaFromBoolean(alpha.value, alpha.trueAlpha, alpha.falseAlpha)
    elseif presentation.alpha ~= nil then
        widget:SetAlpha(presentation.alpha)
    end
end

local function GetInteractionTextWidget(item, slotID, spec)
    return item and item.widget and GetTextWidget(item.widget, ResolveTextRole(slotID, spec and spec.textRole))
end

-- 交互层不是 TimerBar 的视觉树：它只存在于编辑宿主，且永远不参与
-- ItemRoot 尺寸、Body 锚点或 collection 的语义布局。这样面板/世界编辑
-- 能把用户意图送回模块，而实际显示仍只有 TimerBarWidget 一个来源。
local function EmitInteractionIntent(collection, intent)
    local callbacks = collection and collection.callbacks
    if type(callbacks) == "table" and type(callbacks.onIntent) == "function" then
        callbacks.onIntent(intent)
    end
end

local function StopOverlayDrag(overlay, emitMove)
    local drag = overlay._timerBarDrag
    if not drag then return end
    overlay:SetScript("OnUpdate", nil)
    overlay._timerBarDrag = nil
    if overlay.highlight then
        overlay.highlight:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        overlay.highlight:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
    end
    if GameTooltip and GameTooltip:GetOwner() == overlay then GameTooltip:Hide() end
    if emitMove and drag.dragging then
        EmitInteractionIntent(drag.collection, {
            type = "elementMoved",
            elementID = drag.elementID,
            position = { x = drag.position.x, y = drag.position.y },
        })
    end
end

local function ResetInteractionOverlay(overlay, detach)
    if not overlay then return end
    StopOverlayDrag(overlay, false)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
    if overlay.highlight then overlay.highlight:Hide() end
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay._timerBarSlotID = nil
    if detach then overlay:SetParent(nil) end
end

local function ShallowCopy(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    return copy
end

-- 面板拖动的 transient 投影：同一 collection 的同一文字槽位必须一起跟随。
-- 这只改已物化的 Widget 样式，绝不创建预览替身或写 DB；松手的 intent 才会
-- 触发正常 ApplyItem 持久刷新。
local function ApplyTransientPositionToItem(item, slotID, spec, position)
    local widget = item and item.widget
    if not widget or type(position) ~= "table" then return end
    local textWidget = GetInteractionTextWidget(item, slotID, spec)
    if textWidget and type(textWidget.ApplyStyle) == "function" and type(textWidget.style) == "table" then
        local transient = ShallowCopy(textWidget.style)
        transient.x, transient.y = position.x, position.y
        textWidget:ApplyStyle(transient)
    end
end

local function ApplyTransientPosition(collection, item, slotID, spec, position)
    local applied = false
    for _, candidate in ipairs(collection.currentItems or {}) do
        local candidateSpec = candidate == item and spec
            or candidate and candidate.presentation and candidate.presentation.interaction
                and candidate.presentation.interaction.slots and candidate.presentation.interaction.slots[slotID]
        if type(candidateSpec) == "table" and ResolveTextRole(slotID, candidateSpec.textRole) then
            ApplyTransientPositionToItem(candidate, slotID, candidateSpec, position)
            applied = true
        end
    end
    if not applied then ApplyTransientPositionToItem(item, slotID, spec, position) end
end

local function ResolveInteractionParent(item, slotID, spec)
    if type(spec.fixedElement) == "string" and type(item.widget.GetFixedElementRoot) == "function" then
        local root = item.widget:GetFixedElementRoot(spec.fixedElement)
        if root then return root end
    end
    local textWidget = GetInteractionTextWidget(item, slotID, spec)
    if textWidget then return textWidget end
    return item.root
end

-- 可拖文字的视觉、命中与提交必须共享同一份局部 position。普通 TimerBar
-- 文本的 root 固定覆盖 bar；真实字形位置来自 style.x/y。因此不得让命中框
-- 在拖动时暗中读取另一份 style 值而提交却使用 slot anchor。
local function ApplyTextInteractionAnchor(overlay, textWidget, position)
    local metrics = textWidget and textWidget.GetVisualMetrics and textWidget:GetVisualMetrics()
    if type(metrics) ~= "table" then return false end
    local rootWidth = math.max(1, textWidget:GetWidth() or 1)
    local rootHeight = math.max(1, textWidget:GetHeight() or 1)
    local justifyH = tostring(metrics.justifyH or "LEFT"):upper()
    local justifyV = tostring(metrics.justifyV or "MIDDLE"):upper()
    local offsetX, offsetY = 0, 0
    if justifyH == "LEFT" then offsetX = -rootWidth * 0.5 + metrics.width * 0.5
    elseif justifyH == "RIGHT" then offsetX = rootWidth * 0.5 - metrics.width * 0.5 end
    if justifyV == "TOP" then offsetY = rootHeight * 0.5 - metrics.height * 0.5
    elseif justifyV == "BOTTOM" then offsetY = -rootHeight * 0.5 + metrics.height * 0.5 end
    local styleX = tonumber(metrics.offsetX) or 0
    local styleY = tonumber(metrics.offsetY) or 0
    local visualX = type(position) == "table" and tonumber(position.x) or styleX
    local visualY = type(position) == "table" and tonumber(position.y) or styleY
    offsetX = offsetX + visualX
    offsetY = offsetY + visualY
    overlay:ClearAllPoints()
    -- 点击范围应紧贴文字但不能薄到难点；这是交互 padding，不影响文本本身。
    overlay:SetSize(math.max(24, (tonumber(metrics.width) or 1) + 12), math.max(22, (tonumber(metrics.height) or 1) + 8))
    overlay:SetPoint("CENTER", textWidget, "CENTER", offsetX, offsetY)
    return true
end

-- Hitbox 与拖动意图必须采用同一锚点声明。对无 metrics 的 Secret 文本，
-- semanticBounds.anchor 是唯一视觉/交互基准；不能命中框按 bounds、提交却按
-- 空 spec.anchor，否则首次拖动会产生跳位。
local function ResolveInteractionAnchor(spec, semanticBounds)
    if type(semanticBounds) == "table" then
        return type(semanticBounds.anchor) == "table" and semanticBounds.anchor or semanticBounds
    end
    return type(spec) == "table" and type(spec.anchor) == "table" and spec.anchor or {}
end

local function ApplyDeclaredSemanticBounds(overlay, parent, bounds, position)
    if type(bounds) ~= "table" then return false end
    local width, height = tonumber(bounds.width), tonumber(bounds.height)
    if not width or not height or width <= 0 or height <= 0 then return false end
    local anchor = ResolveInteractionAnchor(nil, bounds)
    local point = anchor.point or "CENTER"
    local relativePoint = anchor.relativePoint or point
    local x = position and position.x or anchor.x or 0
    local y = position and position.y or anchor.y or 0
    overlay:ClearAllPoints()
    overlay:SetSize(width, height)
    overlay:SetPoint(point, parent, relativePoint, x, y)
    return true
end

local function ApplyInteractionAnchor(overlay, parent, slotID, spec, semanticBounds, position)
    if ResolveTextRole(slotID, spec.textRole) then
        if ApplyTextInteractionAnchor(overlay, parent, position) then return true, nil end
        local applied = ApplyDeclaredSemanticBounds(overlay, parent, semanticBounds, position)
        return applied, applied and semanticBounds or nil
    end
    local anchor = ResolveInteractionAnchor(spec, nil)
    local point = anchor.point or "CENTER"
    local relativePoint = anchor.relativePoint or point
    overlay:ClearAllPoints()
    overlay:SetPoint(point, parent, relativePoint,
        position and position.x or anchor.x or 0,
        position and position.y or anchor.y or 0)
    overlay:SetSize(math.max(1, spec.width or 1), math.max(1, spec.height or 1))
    return true, nil
end

local function ResolveTextInteractionPosition(textWidget, fallback)
    local metrics = textWidget and textWidget.GetVisualMetrics and textWidget:GetVisualMetrics()
    if type(metrics) == "table" then
        return {
            x = tonumber(metrics.offsetX) or 0,
            y = tonumber(metrics.offsetY) or 0,
        }
    end
    local anchor = ResolveInteractionAnchor(fallback, nil)
    return {
        x = tonumber(anchor.x) or 0,
        y = tonumber(anchor.y) or 0,
    }
end

local function ConfigureInteractionOverlay(collection, item, slotID, spec)
    local textRole = ResolveTextRole(slotID, spec.textRole)
    local isText = textRole ~= nil
    -- 条体与条体图标同属主本体；Panel 中只能作为固定预览，绝不能拖动。
    local movable = spec.movable == true and slotID ~= "core.bar" and slotID ~= "core.icon"
    local textWidget = GetInteractionTextWidget(item, slotID, spec)
    local semanticBounds = ResolveSemanticBounds(item.presentation, slotID, spec)
    -- stackText 的内容可以来自 Secret 值，不能读取/比较/转换它。可见性是
    -- Widget 已经决定的纯视觉状态：没有层数或样式禁用时不创建命中框。
    if textRole == "stacks" and (not textWidget or not textWidget:IsShown()) then
        local existing = item.interactionOverlays[slotID]
        if existing then ResetInteractionOverlay(existing, false) end
        return false
    end

    local overlay = item.interactionOverlays[slotID]
    if not overlay then
        overlay = CreateFrame("Button", nil, item.root)
        overlay:SetFrameStrata(item.root:GetFrameStrata() or "MEDIUM")
        overlay:SetFrameLevel((item.root:GetFrameLevel() or 0) + 50)
        local highlight = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
        highlight:SetAllPoints(overlay)
        highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        highlight:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        highlight:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
        highlight:Hide()
        overlay.highlight = highlight
        item.interactionOverlays[slotID] = overlay
    end

    local parent = ResolveInteractionParent(item, slotID, spec)
    if overlay:GetParent() ~= parent then overlay:SetParent(parent) end
    -- 声明 semanticBounds 的文字（尤其 Secret 文本）以 bounds.anchor 为唯一
    -- 位置真源；普通可测文字才从 style.x/y 取得初始局部位置。
    local initialPosition = isText and not semanticBounds and ResolveTextInteractionPosition(textWidget, spec) or nil
    local anchored, activeSemanticBounds = ApplyInteractionAnchor(overlay, parent, slotID, spec, semanticBounds, initialPosition)
    if not anchored then
        ResetInteractionOverlay(overlay, false)
        return false
    end
    overlay._timerBarSlotID = slotID
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    overlay:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(spec.tooltip or (L["可编辑元素："] .. self._timerBarSlotID), 0.72, 0.94, 1.00)
            GameTooltip:AddLine(movable and L["左键拖动位置；右键定位设置"] or L["右键定位设置"], 0.78, 0.88, 1.00)
            GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        if self.highlight and not self._timerBarDrag then self.highlight:Hide() end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            EmitInteractionIntent(collection, {
                type = "elementRightClicked",
                elementID = self._timerBarSlotID,
                guiTarget = spec.guiTarget or self._timerBarSlotID,
            })
            return
        end
        if button ~= "LeftButton" or not movable then return end

        StopOverlayDrag(self, false)
        -- 鼠标坐标必须用稳定 UI scale 换算；overlay 的 parent 可能是缩放的
        -- ExtraChildHost，绝不能在拖动中拿它自己的 effective scale。
        local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local cursorX, cursorY = GetCursorPosition()
        local anchor = ResolveInteractionAnchor(spec, activeSemanticBounds)
        local basePosition = isText and not activeSemanticBounds and ResolveTextInteractionPosition(textWidget, anchor) or {
            x = anchor.x or 0,
            y = anchor.y or 0,
        }
        local baseX, baseY = basePosition.x, basePosition.y
        self._timerBarDrag = {
            collection = collection,
            elementID = self._timerBarSlotID,
            scale = scale,
            cursorX = cursorX / scale,
            cursorY = cursorY / scale,
            baseX = baseX,
            baseY = baseY,
            position = { x = baseX, y = baseY },
            dragging = false,
        }
        if self.highlight then
            self.highlight:SetBackdropBorderColor(1.00, 0.82, 0.20, 1.00)
            self.highlight:SetBackdropColor(1.00, 0.72, 0.12, 0.18)
        end
        self:SetScript("OnUpdate", function(buttonFrame)
            local drag = buttonFrame._timerBarDrag
            if not drag then return end
            if not IsMouseButtonDown("LeftButton") then
                StopOverlayDrag(buttonFrame, true)
                return
            end
            local x, y = GetCursorPosition()
            local deltaX = x / drag.scale - drag.cursorX
            local deltaY = y / drag.scale - drag.cursorY
            if not drag.dragging and math.abs(deltaX) < 2 and math.abs(deltaY) < 2 then return end
            drag.dragging = true
            drag.position.x = drag.baseX + deltaX
            drag.position.y = drag.baseY + deltaY
            ApplyTransientPosition(drag.collection, item, buttonFrame._timerBarSlotID, spec, drag.position)
            ApplyInteractionAnchor(buttonFrame, ResolveInteractionParent(item, buttonFrame._timerBarSlotID, spec),
                buttonFrame._timerBarSlotID, spec, semanticBounds, drag.position)
        end)
    end)
    overlay:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then StopOverlayDrag(self, true) end
    end)
    overlay:Show()
    return true
end

local function ConfigureInteractionOverlays(collection, item, interaction)
    local overlays = item.interactionOverlays
    -- 局部元素移动只属于 GUI 面板预览。世界编辑的唯一鼠标所有者是
    -- AnchorController，它只能拖动模块整体；以后新增宿主也默认禁止局部交互。
    if collection.interactionMode ~= "panel" then
        for _, overlay in pairs(overlays) do ResetInteractionOverlay(overlay, false) end
        return
    end

    local wanted = {}
    local slots = type(interaction) == "table" and interaction.slots or nil
    for slotID, spec in pairs(type(slots) == "table" and slots or {}) do
        if type(slotID) == "string" and slotID ~= "" and type(spec) == "table" then
            if ConfigureInteractionOverlay(collection, item, slotID, spec) then
                wanted[slotID] = true
            end
        end
    end
    for slotID, overlay in pairs(overlays) do
        if not wanted[slotID] then ResetInteractionOverlay(overlay, false) end
    end
end

local function ReleaseInteractionOverlays(item)
    for _, overlay in pairs(item.interactionOverlays or {}) do
        ResetInteractionOverlay(overlay, true)
    end
    item.interactionOverlays = {}
end

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
    root:SetScript("OnShow", nil)
    root:SetScript("OnHide", nil)
    root:EnableMouse(false)
    root:Hide()
    root:ClearAllPoints()
    root:SetSize(1, 1)
    root:SetParent(UIParent)
    EXFactory:Release(ITEM_ROOT_POOL, root)
end

local function NewItem(collection, itemID)
    local root = AcquireItemRoot(collection.layout)

    local item = {
        id = itemID,
        root = root,
        collection = collection,
        interactionOverlays = {},
    }
    function item:GetRoot()
        return self.root
    end

    if collection.standardSchema then
        item.widget = EXUI:CreateStandardTimerBarWidget(root, collection.standardSchema)
        item.isStandard = true
    else
        item.widget = EXUI:CreateTimerBarWidget(root)
    end
    item.widget:ClearAllPoints()
    item.widget:SetPoint("CENTER", root, "CENTER")
    item.regions = EXUI:CreateRegionElements({
        ownerRoot = root,
        moduleKey = collection.moduleKey,
        interactionMode = collection.interactionMode,
        resolveCore = function(elementID)
            return item.widget:ResolveDeclaredElement(elementID)
        end,
        emitIntent = function(intent)
            local callback = collection.callbacks and collection.callbacks.onIntent
            if type(callback) == "function" then callback(intent) end
        end,
        syncTransientPosition = function(entryID, position)
            for _, candidate in ipairs(collection.currentItems or {}) do
                if candidate and candidate.regions then
                    candidate.regions:ApplyTransientPosition(entryID, position)
                end
            end
        end,
    })
    return item
end

local function UnionDeclaredBounds(bounds, rect, offset)
    if type(rect) ~= "table" then return bounds end
    offset = offset or {}
    local x, y = tonumber(offset.x) or 0, tonumber(offset.y) or 0
    local left, right = rect.left + x, rect.right + x
    local bottom, top = rect.bottom + y, rect.top + y
    if not bounds then return { left = left, right = right, bottom = bottom, top = top } end
    bounds.left, bounds.right = math.min(bounds.left, left), math.max(bounds.right, right)
    bounds.bottom, bounds.top = math.min(bounds.bottom, bottom), math.max(bounds.top, top)
    return bounds
end

local function CreateCollection(parent, interactionMode, moduleKey, callbacks, standardSchema)
    local collection = {
        host = parent,
        moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateTimerBarCollection"),
        interactionMode = interactionMode,
        callbacks = callbacks,
        contentCenter = type(callbacks) == "table" and callbacks.contentCenter == true,
        itemsByID = {},
        currentItems = {},
        currentLayout = {},
        itemWidth = 1,
        itemHeight = 1,
        standardSchema = standardSchema,
    }
    collection.layout = EXUI:CreateWidgetLayout(parent, {})

    function collection:AcquireItem(itemID)
        local item = self.itemsByID[itemID]
        if item then return item end
        item = NewItem(self, itemID)
        self.itemsByID[itemID] = item
        return item
    end

    function collection:ApplyItem(item, presentation)
        if not item or not item.widget then return item end
        presentation = type(presentation) == "table" and presentation or {}
        item.presentation = presentation
        local widget = item.widget
        -- Panel resize may temporarily drive only the existing widget geometry.
        -- Every normal Apply returns ownership to the one persistent style/DB.
        if type(widget.SetGeometryOverride) == "function" then
            widget:SetGeometryOverride(nil)
        end
        if type(widget.SetTimerDoneCallback) == "function" then
            widget:SetTimerDoneCallback(presentation.onTimerDone)
        end

        if self.standardSchema then
            ApplyStandardPresentation(self, item, presentation)
        else
            widget:ApplyStyle(presentation.style or {})
            ApplyIcon(widget, presentation.icon)
            ApplyStacks(widget, presentation)
            widget:SetLabel(presentation.label)
            local ownsProgress = ApplyTime(self, widget, presentation.time)
            if not ownsProgress then ApplyProgress(widget, presentation.progress) end
            if presentation.fillColor then
                widget:SetFillColor(presentation.fillColor)
            end
        end
        if type(widget.RefreshDeclaredTextSelections) == "function" then
            widget:RefreshDeclaredTextSelections()
        end
        if type(widget.SetFillVisible) == "function" then widget:SetFillVisible(presentation.fillVisible ~= false) end
        if presentation.extraHosts ~= nil or presentation.extraElements ~= nil or presentation.extraTextures ~= nil
            or presentation.extraChildren ~= nil or presentation.renderExtraChildren ~= nil then
            error("TimerBarCollection legacy extension presentation is removed; declare ordered regionElements instead", 2)
        end
        item.regions:SetConfigContextID(presentation.regionConfigContextID)
        item.regions:Apply(presentation.regionElements)
        ConfigureInteractionOverlays(self, item, presentation.interaction)

        -- ItemRoot 尺寸只来自固定 Body 的真实宽高。文字与 ExtraChildHost 不得
        -- 参与 collection 步距，也不得通过 visual union 移动语义原点。
        self.itemWidth = math.max(1, widget:GetWidth() or 1)
        self.itemHeight = math.max(1, widget:GetHeight() or 1)
        item.root:SetSize(self.itemWidth, self.itemHeight)
        item.localOffset = ResolveLocalOffset(self, presentation, self.standardSchema)
        widget:ClearAllPoints()
        widget:SetPoint("CENTER", item.root, "CENTER", item.localOffset.x, item.localOffset.y)
        if presentation.shown == false then item.root:Hide() else item.root:Show() end
        return item
    end

    -- Runtime timer corrections must not pay the cost of a complete presentation
    -- projection.  This narrow path only rebinds the time owner on an existing
    -- widget; style, icon, regions, interaction overlays, geometry and layout are
    -- deliberately untouched.
    function collection:UpdateItemTime(item, time)
        if self.released or not item or not item.widget then return false end
        if type(item.presentation) == "table" then
            item.presentation.time = time
        end
        ApplyTime(self, item.widget, time)
        return true
    end

    function collection:SetItems(items, layout)
        local wanted = {}
        for _, item in ipairs(items or {}) do
            if item and item.id then wanted[item.id] = true end
        end
        -- 样本数量减少时，旧 Item 不能残留在屏幕上；这里只隐藏未参与本轮
        -- collection 的 Item，不回写任何 Body/ExtraChild 的坐标。
        for itemID, item in pairs(self.itemsByID) do
            if not wanted[itemID] and item.root then item.root:Hide() end
        end
        local layoutStyle = {}
        for key, value in pairs(type(layout) == "table" and layout or {}) do layoutStyle[key] = value end
        -- Panel 没有模块世界 XY；只在这个宿主把完整样本组居中。runtime/world
        -- 仍是语义首项固定，绝不受此 preview-only 行为影响。
        if self.contentCenter then layoutStyle.contentCenter = true end
        self.layout:ApplyStyle(layoutStyle)
        self.layout:SetSemanticItems(items or {}, self.itemWidth, self.itemHeight)
        self.currentItems = items or {}
        self.currentLayout = layoutStyle
        return self
    end

    -- GUI slider 的 live 阶段只能重套已物化 presentation。这个正式入口不
    -- 暴露 Widget/Frame，也绝不 Acquire/Release Item；调用方只可修改同一份
    -- presentation 后由 Collection 统一 ApplyItem。完整 layout/生命周期仍由
    -- commit 阶段的模块 Refresh 负责。
    function collection:ReapplyCurrentItems(mutatePresentation, options)
        if self.released then return false end
        options = type(options) == "table" and options or {}
        local maxItems = tonumber(options.maxItems)
        if maxItems then maxItems = math.max(0, math.floor(maxItems)) end
        local applied = 0
        for _, item in ipairs(self.currentItems or {}) do
            if item and item.widget and item.presentation and (not maxItems or applied < maxItems) then
                if type(mutatePresentation) == "function" then
                    mutatePresentation(item.presentation, item)
                end
                self:ApplyItem(item, item.presentation)
                applied = applied + 1
            end
        end
        -- 拖动期可以只更新代表样本而不重排整组；松手阶段由完整 Render 统一
        -- 同步当前预览数量与布局。
        if options.reapplyLayout ~= false then
            self:SetItems(self.currentItems, self.currentLayout)
        end
        return true
    end

    -- Panel resize is geometry-only while the mouse is held.  Reapplying the
    -- complete presentation here would also reset native timer/content state
    -- every frame.  The committed notification performs the normal Apply once.
    function collection:ResizeCurrentItems(width, height)
        if self.released then return false end
        width, height = math.max(1, tonumber(width) or 1), math.max(1, tonumber(height) or 1)
        local itemWidth, itemHeight
        for _, item in ipairs(self.currentItems or {}) do
            local widget = item and item.widget
            if widget and type(widget.SetGeometryOverride) == "function" then
                widget:SetGeometryOverride({ width = width, height = height })
                local currentWidth = math.max(1, widget:GetWidth() or 1)
                local currentHeight = math.max(1, widget:GetHeight() or 1)
                item.root:SetSize(currentWidth, currentHeight)
                itemWidth, itemHeight = currentWidth, currentHeight
            end
        end
        if itemWidth then
            self.itemWidth, self.itemHeight = itemWidth, itemHeight
            self.layout:SetSemanticItems(self.currentItems or {}, itemWidth, itemHeight)
        end
        return itemWidth ~= nil
    end

    -- 排列 Slider 的 live 阶段只允许重排已物化的同一批 Item。不得借此 Acquire、
    -- Release、重建 Preview session 或重新生成 presentation。
    function collection:ReapplyCurrentLayout(layout)
        if self.released then return false end
        self:SetItems(self.currentItems or {}, layout or self.currentLayout)
        return true
    end

    function collection:ReleaseItem(itemID)
        local item = self.itemsByID[itemID]
        if not item then return end
        self.itemsByID[itemID] = nil
        ReleaseInteractionOverlays(item)
        if item.regions then item.regions:Release() end
        if item.isStandard then
            EXUI:ReleaseStandardTimerBarWidget(item.widget)
        else
            item.widget:Release()
        end
        item.widget = nil
        ReleaseItemRoot(item.root)
        item.root = nil
        item.regions = nil
        item.interactionOverlays = nil
        item.presentation = nil
        item.localOffset = nil
    end

    function collection:GetBounds()
        return self.layout:GetBounds()
    end

    -- 暴雪式 Selection Bounds：局部控件矩形 + WidgetLayout 已实际使用的 Item
    -- 偏移，直接给出相对 layout.CENTER 的四边。绝不读取屏幕坐标/子 Frame。
    function collection:GetWorldBounds()
        local bounds = nil
        local offsets = self.layout:GetSemanticItemOffsets()
        for _, item in ipairs(self.currentItems or {}) do
            local offset = offsets[item]
            if offset and item and item.widget and type(item.widget.GetDeclaredSelectionBounds) == "function" then
                bounds = UnionDeclaredBounds(bounds, item.widget:GetDeclaredSelectionBounds(), CombineOffsets(offset, item.localOffset))
            end
            if offset and item and item.regions then
                bounds = UnionDeclaredBounds(bounds, item.regions:GetDeclaredBounds(), CombineOffsets(offset, item.localOffset))
            end
        end
        if not bounds then return nil end
        return {
            anchor = self.layout,
            left = bounds.left,
            right = bounds.right,
            bottom = bounds.bottom,
            top = bounds.top,
            width = math.max(1, bounds.right - bounds.left),
            height = math.max(1, bounds.top - bounds.bottom),
            anchorOffsetX = (bounds.left + bounds.right) * 0.5,
            anchorOffsetY = (bounds.bottom + bounds.top) * 0.5,
        }
    end

    function collection:GetItems()
        return self.itemsByID
    end

    function collection:Release()
        for itemID in pairs(self.itemsByID) do
            self:ReleaseItem(itemID)
        end
        self.layout:Release()
        self.layout = nil
        self.currentItems = nil
        self.currentLayout = nil
        self.host = nil
        self.callbacks = nil
        self.released = true
    end

    return collection
end

function EXUI:CreateTimerBarCollection(parent, interactionMode, moduleKey, callbacks)
    return CreateCollection(parent, interactionMode, moduleKey, callbacks, nil)
end

-- 三文字 StandardTimerBar 的明确集合入口：与普通 TimerBarCollection 共享
-- 同一固定 Body/语义布局/交互规则，但不会把 Secret 文本塞进普通 label 契约。
function EXUI:CreateStandardTimerBarCollection(parent, interactionMode, moduleKey, callbacks)
    EXUI:RequireModuleKey(moduleKey, "CreateStandardTimerBarCollection")
    callbacks = type(callbacks) == "table" and callbacks or {}
    if type(callbacks.schema) ~= "table" then
        error("CreateStandardTimerBarCollection requires callbacks.schema", 2)
    end
    return CreateCollection(parent, interactionMode, moduleKey, callbacks, callbacks.schema)
end
