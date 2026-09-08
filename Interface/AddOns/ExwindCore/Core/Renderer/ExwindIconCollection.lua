-- =========================================================
-- ExwindIconCollection.lua
-- Icon 唯一 Item/Collection 渲染入口。
--
-- runtime、世界编辑与 GUI 预览各自持有一个 collection 实例，但只能向
-- ApplyItem / SetItems 提供同一份 presentation 与 layout。Collection 不读
-- DB、不保留业务状态，也不会从子 Frame 反推编辑边界。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local EXUI = ExwindTools and ExwindTools.UI
local EXFactory = _G.ExwindFactory
if not EXUI or not EXFactory then return end

local ITEM_ROOT_POOL = "RuntimeIconCollectionItemRoot"

EXFactory:InitPool(ITEM_ROOT_POOL, "Frame", nil, function(root)
    root:EnableMouse(false)
    root:SetSize(1, 1)
end)

local function ApplyIcon(widget, icon)
    if type(icon) == "table" and icon.mode == "SECRET" then
        widget:SetSecretIcon(icon.value)
    elseif type(icon) == "table" and icon.mode == "ATLAS" then
        widget:SetAtlas(icon.value)
    elseif type(icon) == "table" and icon.mode == "PORTRAIT" then
        widget:SetUnitPortrait(icon.unit)
    else
        widget:SetIcon(type(icon) == "table" and icon.value or icon)
    end
end

local function ApplyStacks(widget, stacks)
    if type(stacks) == "table" and stacks.mode == "SECRET" then
        widget:SetSecretStacks(stacks.value)
    else
        widget:SetStacks(type(stacks) == "table" and stacks.value or stacks)
    end
end

-- Icon 的固定 core 槽位也必须是纯数据布局。这里专门处理已经由
-- IconWidget 建立的 core.icon/core.label/core.time/core.stacks；它不创建任何
-- 子 Region，也不接受模块回调或裸 Frame。可扩展子 Region 一律走
-- presentation.regionElements。
local CORE_LAYOUT_SLOT_IDS = {
    icon = "core.icon",
    label = "core.label",
    time = "core.time",
    stacks = "core.stacks",
}

-- 名称是 Countdown 等复合行的锚点源，必须先解除它对 IconWidget.textLayer
-- 的默认依赖；之后图标／时间才可安全锚定名称内容区域。
local CORE_LAYOUT_ORDER = { "label", "icon", "time", "stacks" }

local function AssertPureCoreLayout(value, label, seen)
    local valueType = type(value)
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        error(label .. " cannot contain " .. valueType, 3)
    end
    if valueType ~= "table" then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        AssertPureCoreLayout(key, label, seen)
        AssertPureCoreLayout(child, label, seen)
    end
end

local function ResolveCoreLayoutSlot(item, elementID)
    local widget = item.widget
    if elementID == "core.root" then return item.root end
    if elementID == "core.icon" or elementID == "core.cooldown" then return widget end
    if elementID == "core.label" or elementID == "core.spellName" then return widget.labelText end
    if elementID == "core.label.content" then return widget.labelText:GetContentRegion() end
    if elementID == "core.time" then return widget.countdownText end
    if elementID == "core.stacks" or elementID == "icon.stacks" then return widget.stackText end
    error("IconCollection coreLayout references unknown core slot " .. tostring(elementID), 3)
end

-- IconWidget normally owns its text slots below its own textLayer.  A compound
-- row may explicitly promote a slot to ItemRoot so icon, name and time become
-- siblings.  This is required when the icon must follow the *actual* name
-- FontString width: anchoring an IconWidget parent to its own label child is a
-- forbidden dependency cycle.
local function ApplyDetachedCoreSlots(item, presentation)
    local detached = type(presentation) == "table" and presentation.detachedCoreSlots or nil
    local widget = item.widget
    local function Place(slotID, child)
        local parent = type(detached) == "table" and detached[slotID] == true and item.root or widget.textLayer
        if child and child:GetParent() ~= parent then child:SetParent(parent) end
    end
    Place("label", widget.labelText)
    Place("time", widget.countdownText)
end

local function CoreRectPoint(rect, point)
    point = tostring(point or "CENTER"):upper()
    local x, y = (rect.left + rect.right) * .5, (rect.bottom + rect.top) * .5
    if point:find("LEFT", 1, true) then x = rect.left elseif point:find("RIGHT", 1, true) then x = rect.right end
    if point:find("TOP", 1, true) then y = rect.top elseif point:find("BOTTOM", 1, true) then y = rect.bottom end
    return x, y
end

local function CoreAnchoredRect(relativeRect, anchor, width, height)
    local x, y = CoreRectPoint(relativeRect, anchor.relativePoint or anchor.point or "CENTER")
    x, y = x + (tonumber(anchor.x) or 0), y + (tonumber(anchor.y) or 0)
    local point = tostring(anchor.point or "CENTER"):upper()
    local left, right = x - width * .5, x + width * .5
    local bottom, top = y - height * .5, y + height * .5
    if point:find("LEFT", 1, true) then left, right = x, x + width
    elseif point:find("RIGHT", 1, true) then left, right = x - width, x end
    if point:find("TOP", 1, true) then bottom, top = y - height, y
    elseif point:find("BOTTOM", 1, true) then bottom, top = y, y + height end
    return { left = left, right = right, bottom = bottom, top = top }
end

local function SetCoreLayoutRect(item, elementID, rect)
    item.coreLayoutRects[elementID] = rect
    if elementID == "core.label" then item.coreLayoutRects["core.spellName"] = rect end
    if elementID == "core.stacks" then item.coreLayoutRects["icon.stacks"] = rect end
end

local function ResetCoreLayoutRects(item, presentation)
    local iconWidth, iconHeight = math.max(1, item.widget:GetWidth() or 1), math.max(1, item.widget:GetHeight() or 1)
    local declared = type(presentation) == "table" and presentation.bodySize or nil
    local width = math.max(1, tonumber(declared and declared.width) or iconWidth)
    local height = math.max(1, tonumber(declared and declared.height) or iconHeight)
    -- Core semantic rectangles are relative to ItemRoot.  When a collection
    -- consumes a local body offset, both the real IconWidget and its declared
    -- interaction/bounds geometry must move together.
    local offset = item.localOffset or {}
    local x, y = tonumber(offset.x) or 0, tonumber(offset.y) or 0
    local body = { left = -width * .5 + x, right = width * .5 + x, bottom = -height * .5 + y, top = height * .5 + y }
    local icon = { left = -iconWidth * .5 + x, right = iconWidth * .5 + x, bottom = -iconHeight * .5 + y, top = iconHeight * .5 + y }
    item.coreLayoutRects = {
        ["core.root"] = body, ["core.icon"] = icon, ["core.cooldown"] = icon,
        ["core.label"] = body, ["core.spellName"] = body,
        ["core.time"] = body, ["core.stacks"] = body, ["icon.stacks"] = body,
    }
end

local function ApplyCoreLayout(item, presentation)
    local layout = presentation.coreLayout
    ResetCoreLayoutRects(item, presentation)
    if layout == nil then return end
    if type(layout) ~= "table" then error("IconCollection coreLayout must be table", 3) end
    AssertPureCoreLayout(layout, "IconCollection coreLayout")

    for _, key in ipairs(CORE_LAYOUT_ORDER) do
        local spec = layout[key]
        if spec ~= nil then
            if type(spec) ~= "table" then error("IconCollection coreLayout." .. key .. " must be table", 3) end
            local target = ResolveCoreLayoutSlot(item, CORE_LAYOUT_SLOT_IDS[key])
            local elementID = CORE_LAYOUT_SLOT_IDS[key]
            local bounds = spec.bounds
            local width, height = nil, nil
            if spec.clearBounds == true and type(target.ClearBounds) == "function" then
                target:ClearBounds()
            end
            if bounds ~= nil then
                if type(bounds) ~= "table" then error("IconCollection coreLayout." .. key .. ".bounds must be table", 3) end
                width, height = tonumber(bounds.width), tonumber(bounds.height)
                if not width or not height or width <= 0 or height <= 0 then
                    error("IconCollection coreLayout." .. key .. ".bounds requires positive width/height", 3)
                end
                if type(target.SetBounds) == "function" then
                    target:SetBounds(width, height)
                elseif type(target.SetSize) == "function" then
                    target:SetSize(width, height)
                else
                    error("IconCollection coreLayout." .. key .. " target cannot set bounds", 3)
                end
            end
            local anchor = spec.anchor
            if anchor ~= nil then
                if type(anchor) ~= "table" then error("IconCollection coreLayout." .. key .. ".anchor must be table", 3) end
                local relativeElement = anchor.relativeElement or "core.root"
                if type(relativeElement) ~= "string" or relativeElement == "" then
                    error("IconCollection coreLayout." .. key .. ".anchor.relativeElement must be semantic ID", 3)
                end
                local relative = ResolveCoreLayoutSlot(item, relativeElement)
                local point = anchor.point or "CENTER"
                local relativePoint = anchor.relativePoint or point
                local x, y = tonumber(anchor.x) or 0, tonumber(anchor.y) or 0
                if type(target.SetAnchor) == "function" then
                    target:SetAnchor(point, relative, relativePoint, x, y)
                elseif type(target.SetPoint) == "function" then
                    target:ClearAllPoints()
                    target:SetPoint(point, relative, relativePoint, x, y)
                else
                    error("IconCollection coreLayout." .. key .. " target cannot set anchor", 3)
                end
                local base = item.coreLayoutRects[relativeElement] or item.coreLayoutRects["core.root"]
                local prior = item.coreLayoutRects[elementID] or item.coreLayoutRects["core.root"]
                SetCoreLayoutRect(item, elementID, CoreAnchoredRect(base, anchor,
                    width or (prior.right - prior.left), height or (prior.top - prior.bottom)))
            end
            if anchor == nil and width and height then
                local prior = item.coreLayoutRects[elementID] or item.coreLayoutRects["core.root"]
                SetCoreLayoutRect(item, elementID, CoreAnchoredRect(prior, { point = "CENTER", relativePoint = "CENTER" }, width, height))
            end
        end
    end
end

-- Glow is a fixed Icon core visual, not a module-owned child tree.  Modules
-- provide only a pure option table; the collection owns the external library
-- lifecycle and always releases it with the pooled item.
local function GetGlowLibrary()
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibCustomGlow-1.0", true)
    return ok and lib or nil
end

local function StopCoreGlow(item)
    local glow = item.coreGlow
    if not glow then return end
    local target, lib = item.widget, GetGlowLibrary()
    if glow.mode == "pixel" and lib and type(lib.PixelGlow_Stop) == "function" then lib.PixelGlow_Stop(target, glow.key)
    elseif glow.mode == "autocast" and lib and type(lib.AutoCastGlow_Stop) == "function" then lib.AutoCastGlow_Stop(target, glow.key)
    elseif glow.mode == "proc" and lib and type(lib.ProcGlow_Stop) == "function" then lib.ProcGlow_Stop(target, glow.key)
    elseif glow.mode == "action" and lib and type(lib.ButtonGlow_Stop) == "function" then lib.ButtonGlow_Stop(target)
    elseif glow.fallback then glow.fallback:Hide() end
    item.coreGlow = nil
end

local function ApplyCoreGlow(item, presentation)
    StopCoreGlow(item)
    local spec = type(presentation.coreLayout) == "table" and presentation.coreLayout.glow or nil
    if type(spec) ~= "table" or spec.enabled ~= true then return end
    local color = type(spec.color) == "table" and spec.color or { 1, 1, 1, 1 }
    local r, g, b, a = tonumber(color.r or color[1]) or 1, tonumber(color.g or color[2]) or 1,
        tonumber(color.b or color[3]) or 1, tonumber(color.a or color[4]) or 1
    local lines, frequency = math.max(1, math.floor(tonumber(spec.lines) or 8)), tonumber(spec.frequency) or .25
    local scale, offset = tonumber(spec.scale) or 1, tonumber(spec.offset) or 0
    local key = "coreGlow:" .. tostring(item.collection.moduleKey) .. ":" .. tostring(item.id)
    local target, lib, style = item.widget, GetGlowLibrary(), tostring(spec.style or "Pixel Glow")
    local mode
    if lib then
        if style == "Action Button Glow" and type(lib.ButtonGlow_Start) == "function" then
            lib.ButtonGlow_Start(target, { r, g, b, a }, frequency, 20); mode = "action"
        elseif style == "Autocast Shine" and type(lib.AutoCastGlow_Start) == "function" then
            lib.AutoCastGlow_Start(target, { r, g, b, a }, lines, frequency, scale, offset, offset, key, 20); mode = "autocast"
        elseif style == "Proc Glow" and type(lib.ProcGlow_Start) == "function" then
            lib.ProcGlow_Start(target, { key = key, color = { r, g, b, a }, frameLevel = 20, xOffset = offset, yOffset = offset, duration = 1 }); mode = "proc"
        elseif type(lib.PixelGlow_Start) == "function" then
            lib.PixelGlow_Start(target, { r, g, b, a }, lines, frequency, nil, scale, offset, offset, false, key, 20); mode = "pixel"
        end
    end
    if mode then item.coreGlow = { mode = mode, key = key }; return end
    local fallback = item.coreGlowFallback
    if not fallback then
        fallback = CreateFrame("Frame", nil, target, "BackdropTemplate")
        item.coreGlowFallback = fallback
    end
    fallback:SetFrameStrata(target:GetFrameStrata())
    fallback:SetFrameLevel((target:GetFrameLevel() or 1) + 20)
    fallback:ClearAllPoints()
    fallback:SetPoint("TOPLEFT", target, "TOPLEFT", -3 - offset, 3 + offset)
    fallback:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3 + offset, -3 - offset)
    fallback:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = math.max(1, scale) })
    fallback:SetBackdropBorderColor(r, g, b, a)
    fallback:Show()
    item.coreGlow = { mode = "fallback", fallback = fallback }
end

local function ApplyCooldown(collection, widget, cooldown)
    if type(cooldown) ~= "table" then
        widget:ClearCooldown()
        return
    end
    if cooldown.mode == "SECRET" then
        widget:SetSecretCooldown(cooldown.duration, cooldown.clearIfZero)
    elseif cooldown.mode == "DURATION" then
        widget:SetDurationObject(cooldown.duration, cooldown.clearIfZero, cooldown.durationTextProperty,
            cooldown.durationTextOptions)
    elseif cooldown.static == true then
        widget:SetStaticCooldown(cooldown.remaining, cooldown.duration, cooldown.format)
        -- Static editor/world samples have a known ordinary display string.
        -- Apply it after the numeric snapshot so a presentation may expose one
        -- combined label instead of a second visual time field.
        if type(cooldown.text) == "string" then widget:SetCountdownText(cooldown.text) end
    elseif cooldown.start ~= nil and cooldown.duration ~= nil then
        widget:SetCooldown(collection.moduleKey, cooldown.start, cooldown.duration, cooldown.modRate, cooldown.format)
    else
        widget:SetCountdownText(cooldown.text)
    end
end

-- Cooldown completion belongs to the collection presentation contract, not to
-- a consumer reaching through an item for IconWidget's private Cooldown frame.
-- Only a runtime presentation that explicitly opts in may notify the owning
-- collection callback.  The generation guard makes a pooled/re-applied item
-- incapable of delivering an obsolete native Cooldown notification.
local function ConfigureCooldownDoneCallback(collection, item, presentation)
    item.cooldownDoneGeneration = (item.cooldownDoneGeneration or 0) + 1
    local generation = item.cooldownDoneGeneration
    local callback = type(collection.callbacks) == "table" and collection.callbacks.onCooldownDone or nil
    if collection.interactionMode ~= "runtime" or presentation.cooldownDone ~= true or type(callback) ~= "function" then
        item.widget:SetCooldownDoneCallback(nil)
        return
    end
    item.widget:SetCooldownDoneCallback(function()
        if collection.released or collection.itemsByID[item.id] ~= item or item.cooldownDoneGeneration ~= generation then return end
        callback({ itemID = item.id })
    end)
end

-- 额外子元素的 Host 由 IconWidget 建立且固定在 Item Body；Collection 只负责
-- 声明、render/release 生命周期。业务模块绝不能取得或创建裸 Texture/Frame。
local function ConfigureExtraChildHosts(item, specs)
    local wanted, hosts = {}, {}
    for id, spec in pairs(type(specs) == "table" and specs or {}) do
        if type(id) == "string" and id ~= "" and type(spec) == "table" then
            wanted[id] = true
            hosts[id] = item.widget:ConfigureExtraChildHost(id, spec)
        end
    end
    for id in pairs(item.extraChildHostIDs or {}) do
        if not wanted[id] then
            local host = item.widget:GetExtraChildHost(id)
            if host then host:Hide() end
        end
    end
    item.extraChildHostIDs = wanted
    return hosts
end

local function ResetRuntimeTooltip(item)
    local overlay = item.runtimeTooltipOverlay
    if not overlay then return end
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:ClearAllPoints()
end

-- 这是图标唯一的 runtime 法术 tooltip 通道。world / panel 不会有鼠标所有权，
-- 模块只传 spellID，Core 不读取任何模块业务表。
local function ConfigureRuntimeTooltip(collection, item, spec)
    ResetRuntimeTooltip(item)
    if collection.interactionMode ~= "runtime" or type(spec) ~= "table" or not spec.spellID then return end
    local overlay = item.runtimeTooltipOverlay
    if not overlay then
        overlay = CreateFrame("Button", nil, item.root)
        overlay:SetFrameStrata(item.widget:GetFrameStrata() or "MEDIUM")
        overlay:SetFrameLevel((item.widget:GetFrameLevel() or 0) + 40)
        item.runtimeTooltipOverlay = overlay
    end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(item.widget)
    overlay:EnableMouse(true)
    overlay:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spec.spellID)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    overlay:Show()
end

local function ResetRuntimeAction(item)
    local overlay = item.runtimeActionOverlay
    if not overlay then return end
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:ClearAllPoints()
end

-- runtime item action 是交互型 Icon Body 的唯一正式通道（聊天频道栏等）。
-- 它严格不在 world/panel 创建，故不会争夺 AnchorController 或 Panel 的输入。
local function ConfigureRuntimeAction(collection, item, spec)
    ResetRuntimeAction(item)
    if collection.interactionMode ~= "runtime" or type(spec) ~= "table" or type(spec.onClick) ~= "function" then return end
    local overlay = item.runtimeActionOverlay
    if not overlay then
        overlay = CreateFrame("Button", nil, item.root)
        overlay:SetFrameStrata(item.widget:GetFrameStrata() or "MEDIUM")
        overlay:SetFrameLevel((item.widget:GetFrameLevel() or 0) + 45)
        item.runtimeActionOverlay = overlay
    end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(item.widget)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonUp")
    overlay:SetScript("OnEnter", function(self) if type(spec.onEnter) == "function" then spec.onEnter(item, self) end end)
    overlay:SetScript("OnLeave", function(self) if type(spec.onLeave) == "function" then spec.onLeave(item, self) end end)
    overlay:SetScript("OnMouseDown", function(self, button) if type(spec.onDown) == "function" then spec.onDown(item, self, button) end end)
    overlay:SetScript("OnMouseUp", function(self, button) if type(spec.onUp) == "function" then spec.onUp(item, self, button) end end)
    overlay:SetScript("OnClick", function(self, button) spec.onClick(item, self, button) end)
    overlay:Show()
end

local function CopyLayout(layout, contentCenter)
    local copy = {}
    for key, value in pairs(type(layout) == "table" and layout or {}) do copy[key] = value end
    if contentCenter then copy.contentCenter = true end
    return copy
end

-- 选择范围不是视觉树的扫描结果。每个 presentation 必须声明相对 ItemRoot
-- CENTER 的四边；这样文字、边框等超出 Icon Body 的元素也能与世界编辑、
-- GUI 预览和实际渲染使用同一份几何定义。
local function RequireDeclaredBounds(presentation)
    local bounds = type(presentation) == "table" and presentation.declaredBounds or nil
    if type(bounds) ~= "table" then
        error("IconCollection presentation requires declaredBounds", 3)
    end
    local left, right = tonumber(bounds.left), tonumber(bounds.right)
    local bottom, top = tonumber(bounds.bottom), tonumber(bounds.top)
    if not left or not right or not bottom or not top or right <= left or top <= bottom then
        error("IconCollection declaredBounds must define left < right and bottom < top", 3)
    end
    return { left = left, right = right, bottom = bottom, top = top }
end

-- FLOW collection 的 Body 尺寸同样是 presentation 的声明，而不是从已经
-- 应用过 Pixel/Font/子层后的 Frame 反推。这样同一组图标会有一个明确的
-- 布局尺寸来源；模块仍须让 icon style 使用同一尺寸，visual 与 semantic
-- body 才会完全一致。旧 consumer 未声明时维持既有 Widget 尺寸路径。
local function ResolveDeclaredBodySize(presentation, widget)
    local bodySize = type(presentation) == "table" and presentation.bodySize or nil
    if bodySize == nil then
        return math.max(1, widget:GetWidth() or 1), math.max(1, widget:GetHeight() or 1)
    end
    if type(bodySize) ~= "table" then
        error("IconCollection presentation bodySize must be table", 3)
    end
    local width, height = tonumber(bodySize.width), tonumber(bodySize.height)
    if not width or not height or width <= 0 or height <= 0 then
        error("IconCollection presentation bodySize must define positive width and height", 3)
    end
    return width, height
end

-- Match TimerBarCollection's public policy: settings-panel composition stays
-- centered, while World and Runtime consume the presentation's one local
-- offset.  A1 and A5 can therefore share the same AuraPresentation contract.
local function ResolveLocalOffset(collection, presentation)
    if collection and collection.interactionMode == "panel" then return { x = 0, y = 0 } end
    local offset = presentation and presentation.localOffset
    if offset ~= nil and type(offset) ~= "table" then
        error("IconCollection presentation localOffset must be table", 3)
    end
    return { x = tonumber(offset and offset.x) or 0, y = tonumber(offset and offset.y) or 0 }
end

local function CombineOffsets(first, second)
    return {
        x = (tonumber(first and first.x) or 0) + (tonumber(second and second.x) or 0),
        y = (tonumber(first and first.y) or 0) + (tonumber(second and second.y) or 0),
    }
end

local function UnionDeclaredBounds(bounds, rect, offset)
    offset = offset or {}
    local x, y = tonumber(offset.x) or 0, tonumber(offset.y) or 0
    local left, right = rect.left + x, rect.right + x
    local bottom, top = rect.bottom + y, rect.top + y
    if not bounds then return { left = left, right = right, bottom = bottom, top = top } end
    bounds.left, bounds.right = math.min(bounds.left, left), math.max(bounds.right, right)
    bounds.bottom, bounds.top = math.min(bounds.bottom, bottom), math.max(bounds.top, top)
    return bounds
end

local function EmitIntent(collection, intent)
    local callbacks = collection.callbacks
    if type(callbacks) == "table" and type(callbacks.onIntent) == "function" then
        callbacks.onIntent(intent)
    end
end

-- Icon 的局部文字也必须以稳定的语义暴露。Collection consumer 只声明这些
-- semantic ID，不能读取 IconWidget 的私有 FontString/TextWidget。
local ICON_TEXT_ROLE_BY_SEMANTIC_ID = {
    ["core.time"] = "time",
    ["icon.stacks"] = "stacks",
    ["core.stacks"] = "stacks",
    ["core.label"] = "label",
    ["core.spellName"] = "label",
}

local function ResolveTextRole(slotID, requestedRole)
    local role = requestedRole or ICON_TEXT_ROLE_BY_SEMANTIC_ID[slotID]
    if role == "icon.stacks" or role == "core.stacks" then return "stacks" end
    return role
end

local function CanonicalSemanticID(slotID)
    return slotID == "core.stacks" and "icon.stacks" or slotID
end

-- bounds 是纯声明的布局信息，绝不从 Secret Text 或其 Region 反推。Secret
-- Countdown 同样没有可供 Lua 安全测量的文字 metrics，故两种情况都走这里。
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

local function GetTextSlot(item, slotID, spec)
    local widget = item.widget
    local role = ResolveTextRole(slotID, spec and spec.textRole)
    if role == "label" then return widget.labelText, role end
    if role == "stacks" then return widget.stackText, role end
    if role == "time" then
        local cooldown = item.presentation and item.presentation.cooldown
        -- 只读取公开的 mode 声明，不检查 Secret duration 本身。
        if type(cooldown) == "table" and cooldown.mode == "SECRET" then
            return widget.secretCountdown, role
        end
        return widget.countdownText, role
    end
    return nil, role
end

local function StopOverlayDrag(overlay, emitMove)
    local drag = overlay._iconCollectionDrag
    if not drag then return end
    overlay:SetScript("OnUpdate", nil)
    overlay._iconCollectionDrag = nil
    if overlay.highlight then
        overlay.highlight:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        overlay.highlight:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
        overlay.highlight:Hide()
    end
    if GameTooltip and GameTooltip:GetOwner() == overlay then GameTooltip:Hide() end
    if emitMove and drag.dragging then
        EmitIntent(drag.collection, {
            type = "elementMoved",
            elementID = drag.elementID,
            position = { x = drag.position.x, y = drag.position.y },
        })
    end
end

-- Panel interaction owns its own visual affordance.  It is deliberately a
-- child of the mouse overlay rather than the IconWidget: runtime/world never
-- receive it, and the exact same declared/metric bounds drive hit testing and
-- the blue/orange editing frame.
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

local function ResetInteractionOverlay(overlay, detach)
    if not overlay then return end
    StopOverlayDrag(overlay, false)
    overlay:SetScript("OnClick", nil)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
    if overlay.highlight and overlay.highlight.Hide then overlay.highlight:Hide() end
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay._iconCollectionSlotID = nil
    if detach then overlay:SetParent(nil) end
end

local function ResolveInteractionAnchor(spec, semanticBounds)
    if type(semanticBounds) == "table" then
        return type(semanticBounds.anchor) == "table" and semanticBounds.anchor or semanticBounds
    end
    return type(spec) == "table" and type(spec.anchor) == "table" and spec.anchor or {}
end

-- 少数复合 Icon 呈现（例如“名称 → 时间/图标”的倒数行）把模块坐标定义在
-- TextWidget root 的 anchor，而非 FontString style。显式 positionMode="anchor"
-- 时，拖动必须保持这条正式相对锚点链，不能把位置叠加到 style.x/y。
local function ResolveTransientAnchorParent(item, relativeSlot)
    if relativeSlot == "core.root" then return item.root end
    if relativeSlot == "core.label.content" then return item.widget.labelText:GetContentRegion() end
    if type(relativeSlot) == "string" and relativeSlot ~= "" then
        local target = GetTextSlot(item, relativeSlot, nil)
        if target then return target end
        error("IconCollection transient anchor references unknown text slot " .. relativeSlot, 3)
    end
    return item.widget.textLayer
end

local function ApplyTextMetricsAnchor(overlay, textWidget)
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
    overlay:ClearAllPoints()
    overlay:SetSize(math.max(24, (tonumber(metrics.width) or 1) + 12), math.max(22, (tonumber(metrics.height) or 1) + 8))
    overlay:SetPoint("CENTER", textWidget, "CENTER", offsetX + (tonumber(metrics.offsetX) or 0),
        offsetY + (tonumber(metrics.offsetY) or 0))
    return true
end

local function ApplyDeclaredSemanticBounds(overlay, parent, bounds, position)
    if type(bounds) ~= "table" then return false end
    local width, height = tonumber(bounds.width), tonumber(bounds.height)
    if not width or not height or width <= 0 or height <= 0 then return false end
    local anchor = ResolveInteractionAnchor(nil, bounds)
    local point = anchor.point or "CENTER"
    overlay:ClearAllPoints()
    overlay:SetSize(width, height)
    overlay:SetPoint(point, parent, anchor.relativePoint or point,
        position and position.x or anchor.x or 0, position and position.y or anchor.y or 0)
    return true
end

local function ApplyInteractionAnchor(overlay, item, slotID, spec, semanticBounds, position)
    local textWidget, role = GetTextSlot(item, slotID, spec)
    if textWidget then
        if ApplyTextMetricsAnchor(overlay, textWidget) then return true, textWidget, nil end
        local applied = ApplyDeclaredSemanticBounds(overlay, textWidget, semanticBounds, position)
        return applied, textWidget, applied and semanticBounds or nil
    end
    -- core.icon 是唯一的 Body slot；它保留完整 icon hitbox 的兼容行为。
    overlay:ClearAllPoints()
    overlay:SetAllPoints(item.widget)
    return true, item.widget, nil
end

local function ShallowCopy(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    return copy
end

-- GUI 面板中同一 collection 的预览样本是同一份配置的多个实例。拖动其中
-- 一个文字槽位时，所有已物化样本必须同步投影该临时位置；这里只改现有
-- Widget，松手后仍由 elementMoved 的正常重套写回，绝不 Acquire/Release。
local function ApplyTransientPositionToItem(item, slotID, spec, position)
    local textWidget, role = GetTextSlot(item, slotID, spec)
    if slotID == "core.icon" and spec.positionMode == "anchor" and item.widget and item.widget.SetAnchor then
        local anchor = ResolveInteractionAnchor(spec, ResolveSemanticBounds(item.presentation, slotID, spec))
        item.widget:SetAnchor(anchor.point or "CENTER", ResolveTransientAnchorParent(item, spec.relativeSlot),
            anchor.relativePoint or anchor.point or "CENTER", position.x, position.y)
        return
    end
    if role == "time" and textWidget == item.widget.secretCountdown and textWidget.SetAnchor then
        local anchor = ResolveInteractionAnchor(spec, ResolveSemanticBounds(item.presentation, slotID, spec))
        textWidget:SetAnchor(anchor.point or "CENTER", item.widget.textLayer, anchor.relativePoint or anchor.point or "CENTER",
            position.x, position.y)
        return
    end
    if spec.positionMode == "anchor" and textWidget and textWidget.SetAnchor then
        local anchor = ResolveInteractionAnchor(spec, ResolveSemanticBounds(item.presentation, slotID, spec))
        textWidget:SetAnchor(anchor.point or "CENTER", ResolveTransientAnchorParent(item, spec.relativeSlot),
            anchor.relativePoint or anchor.point or "CENTER", position.x, position.y)
        return
    end
    if textWidget and textWidget.ApplyStyle and type(textWidget.style) == "table" then
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
        if type(candidateSpec) == "table" then
            ApplyTransientPositionToItem(candidate, slotID, candidateSpec, position)
            -- 每个样本都要让命中层跟着已经移动的可见文字；否则画面虽同步，
            -- 其余样本的下一次点击仍会落在旧位置。
            local overlay = candidate.interactionOverlays and candidate.interactionOverlays[slotID]
            if overlay and overlay.IsShown and overlay:IsShown() then
                ApplyInteractionAnchor(overlay, candidate, slotID, candidateSpec,
                    ResolveSemanticBounds(candidate.presentation, slotID, candidateSpec), position)
            end
            applied = true
        end
    end
    if not applied then ApplyTransientPositionToItem(item, slotID, spec, position) end
end

-- 普通文字的位置真源是 TextWidget 的当前 visual metrics。若拖动从 0,0
-- 开始，会在第一次 OnUpdate 抹掉既有 style.x/style.y，表现为图标页文字
-- "飘" 到鼠标外；TimerBarCollection 使用同一规则。
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
    local textWidget, role = GetTextSlot(item, slotID, spec)
    -- core.icon 也可以声明为局部可移动（例如 Countdown 的图标相对行根
    -- 偏移）；它移动的是已物化 Item 内的 IconWidget，不会移动 collection
    -- 的语义布局或模块总锚点。
    local movable = spec.movable == true
    -- 文字是否显示由 Widget 的视觉状态决定；特别是 stacks 可为 Secret，绝不读取
    -- 或比较其内容。没有 metrics 的可见 Secret 文字必须声明 semanticBounds。
    if textWidget and textWidget.IsShown and not textWidget:IsShown() then return false end
    local semanticBounds = ResolveSemanticBounds(item.presentation, slotID, spec)
    local overlay = item.interactionOverlays[slotID]
    if not overlay then
        overlay = CreateFrame("Button", nil, item.root)
        overlay:SetFrameStrata(item.widget:GetFrameStrata() or "MEDIUM")
        overlay:SetFrameLevel((item.widget:GetFrameLevel() or 0) + 50)
        item.interactionOverlays[slotID] = overlay
        item.root._iconCollectionInteractionOverlays = item.interactionOverlays
        -- 旧版单一图标命中框的只读兼容引用；新逻辑只使用上面的 slot map。
        if slotID == "core.icon" then item.root._iconCollectionInteractionOverlay = overlay end
    end
    EnsureInteractionHighlight(overlay)
    local anchored, parent, activeSemanticBounds = ApplyInteractionAnchor(overlay, item, slotID, spec, semanticBounds)
    if not anchored then
        ResetInteractionOverlay(overlay, false)
        return false
    end
    if overlay:GetParent() ~= parent then overlay:SetParent(parent) end
    -- SetParent clears anchors on native Frames; establish the final parent before
    -- applying the hitbox geometry.
    anchored, parent, activeSemanticBounds = ApplyInteractionAnchor(overlay, item, slotID, spec, semanticBounds)
    if not anchored then ResetInteractionOverlay(overlay, false); return false end
    overlay._iconCollectionSlotID = slotID
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    overlay:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and not movable then
            EmitIntent(collection, { type = "elementClicked", elementID = self._iconCollectionSlotID })
        end
    end)
    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            EmitIntent(collection, { type = "elementRightClicked", elementID = self._iconCollectionSlotID,
                guiTarget = spec.guiTarget or self._iconCollectionSlotID })
            return
        end
        -- Body positioning normally belongs to collection layout.  A composite
        -- presentation may explicitly declare core.icon's own relative anchor;
        -- that moves the IconWidget inside its ItemRoot without moving layout.
        local movableTarget = textWidget or (slotID == "core.icon" and item.widget)
        if button ~= "LeftButton" or not movable or not movableTarget then return end
        local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local cursorX, cursorY = GetCursorPosition()
        local anchor = ResolveInteractionAnchor(spec, activeSemanticBounds)
        local basePosition = textWidget and not activeSemanticBounds
            and ResolveTextInteractionPosition(textWidget, anchor)
            or { x = anchor.x or 0, y = anchor.y or 0 }
        self._iconCollectionDrag = { collection = collection, elementID = self._iconCollectionSlotID, scale = scale,
            cursorX = cursorX / scale, cursorY = cursorY / scale, baseX = basePosition.x, baseY = basePosition.y,
            position = { x = basePosition.x, y = basePosition.y }, dragging = false }
        if self.highlight then
            self.highlight:SetBackdropBorderColor(1.00, 0.82, 0.20, 1.00)
            self.highlight:SetBackdropColor(1.00, 0.72, 0.12, 0.18)
            self.highlight:Show()
        end
        self:SetScript("OnUpdate", function(buttonFrame)
            local drag = buttonFrame._iconCollectionDrag
            if not drag then return end
            if not IsMouseButtonDown("LeftButton") then StopOverlayDrag(buttonFrame, true); return end
            local x, y = GetCursorPosition()
            local deltaX, deltaY = x / drag.scale - drag.cursorX, y / drag.scale - drag.cursorY
            if not drag.dragging and math.abs(deltaX) < 2 and math.abs(deltaY) < 2 then return end
            drag.dragging = true
            drag.position.x, drag.position.y = drag.baseX + deltaX, drag.baseY + deltaY
            ApplyTransientPosition(drag.collection, item, buttonFrame._iconCollectionSlotID, spec, drag.position)
            ApplyInteractionAnchor(buttonFrame, item, buttonFrame._iconCollectionSlotID, spec, semanticBounds, drag.position)
        end)
    end)
    overlay:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then StopOverlayDrag(self, true) end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.highlight then self.highlight:Show() end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(spec.tooltip or (L["可编辑元素："] .. self._iconCollectionSlotID), 0.72, 0.94, 1.00)
            GameTooltip:AddLine(movable and L["左键拖动位置；右键定位设置"] or L["右键定位设置"], 0.78, 0.88, 1.00)
            GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        if self.highlight and not self._iconCollectionDrag then self.highlight:Hide() end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    overlay:Show()
    return true
end

-- 局部交互只在 panel 宿主生成。world 的唯一鼠标所有者是 AnchorController，
-- runtime 永远没有鼠标输入；overlay 不参与 Body 尺寸和世界选择 bounds。
local function ConfigureInteractionOverlays(collection, item, interaction)
    local overlays = item.interactionOverlays
    if collection.interactionMode ~= "panel" then
        for _, overlay in pairs(overlays) do ResetInteractionOverlay(overlay, false) end
        item.interactionOverlay = nil
        return
    end
    local slots = type(interaction) == "table" and interaction.slots or nil
    -- 兼容旧的 interaction = { elementID = ... }，但新声明一律使用 slots。
    if type(slots) ~= "table" and type(interaction) == "table" then slots = { [interaction.elementID or "core.icon"] = interaction } end
    local wanted = {}
    for slotID, spec in pairs(type(slots) == "table" and slots or {}) do
        if type(slotID) == "string" and slotID ~= "" and type(spec) == "table" then
            if ConfigureInteractionOverlay(collection, item, slotID, spec) then
                wanted[slotID] = true
                if slotID == "core.icon" then item.interactionOverlay = item.interactionOverlays[slotID] end
            end
        end
    end
    for slotID, overlay in pairs(overlays) do
        if not wanted[slotID] then ResetInteractionOverlay(overlay, false) end
    end
    if not wanted["core.icon"] then item.interactionOverlay = nil end
end

local function ReleaseInteractionOverlays(item)
    for _, overlay in pairs(item.interactionOverlays or {}) do ResetInteractionOverlay(overlay, true) end
    item.interactionOverlay = nil
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
    for _, overlay in pairs(root._iconCollectionInteractionOverlays or {}) do
        ResetInteractionOverlay(overlay, false)
    end
    -- ItemRoot 本身从不拥有业务脚本；仍在归还前显式清空，避免未来扩展把
    -- world/panel 闭包遗留在 pool 中。Factory 随后会执行同样的通用 reset。
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
        interactionOverlay = nil,
        interactionOverlays = root._iconCollectionInteractionOverlays or {},
        extraChildHostIDs = {},
    }
    function item:GetRoot() return self.root end
    item.widget = EXUI:CreateIconWidget(root)
    item.widget:ClearAllPoints()
    item.widget:SetPoint("CENTER", root, "CENTER")
    item.regions = EXUI:CreateRegionElements({
        ownerRoot = root,
        moduleKey = collection.moduleKey,
        interactionMode = collection.interactionMode,
        resolveCore = function(elementID)
            local widget = item.widget
            local width, height = math.max(1, widget:GetWidth() or 1), math.max(1, widget:GetHeight() or 1)
            local rect = item.coreLayoutRects and item.coreLayoutRects[elementID]
                or { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 }
            return widget:ResolveDeclaredElement(elementID), rect
        end,
        emitIntent = function(intent)
            local callback = collection.callbacks and collection.callbacks.onIntent
            if type(callback) == "function" then callback(intent) end
        end,
    })
    return item
end

local function CreateCollection(parent, interactionMode, moduleKey, callbacks)
    if interactionMode ~= "runtime" and interactionMode ~= "world" and interactionMode ~= "panel" then
        error("CreateIconCollection interactionMode must be runtime, world, or panel", 2)
    end
    local collection = {
        host = parent,
        moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateIconCollection"),
        interactionMode = interactionMode,
        callbacks = callbacks,
        contentCenter = type(callbacks) == "table" and callbacks.contentCenter == true,
        itemsByID = {},
        currentItems = {},
        itemWidth = 1,
        itemHeight = 1,
    }
    collection.layout = EXUI:CreateWidgetLayout(parent, {})

    function collection:AcquireItem(itemID)
        if type(itemID) ~= "string" or itemID == "" then error("IconCollection itemID must be non-empty string", 2) end
        local item = self.itemsByID[itemID]
        if item then return item end
        item = NewItem(self, itemID)
        self.itemsByID[itemID] = item
        return item
    end

    function collection:ApplyItem(item, presentation)
        if not item or not item.widget then error("IconCollection ApplyItem requires an acquired item", 2) end
        if type(presentation) ~= "table" then error("IconCollection presentation must be table", 2) end
        item.presentation = presentation
        item.declaredBounds = RequireDeclaredBounds(presentation)
        item.localOffset = ResolveLocalOffset(self, presentation)
        local widget = item.widget
        if type(widget.SetSuppressBorderGeometry) == "function" then
            widget:SetSuppressBorderGeometry(presentation.suppressIconBorderGeometry == true)
        end
        -- A previous Secret content anchor can make this Frame's current
        -- geometry protected.  Restore the normal ItemRoot relation before
        -- applying any visual style that reads the fixed icon size.
        widget:ClearAllPoints()
        widget:SetPoint("CENTER", item.root, "CENTER", item.localOffset.x, item.localOffset.y)
        -- Detach before IconWidget reapplies its own text-slot anchors.  The
        -- subsequent core layout then establishes the only final anchors.
        ApplyDetachedCoreSlots(item, presentation)
        widget:ApplyStyle(presentation.style or {})
        ApplyIcon(widget, presentation.icon)
        ApplyStacks(widget, presentation.stacks)
        if type(widget.SetCountdownTextPrefix) == "function" then
            widget:SetCountdownTextPrefix(presentation.countdownTextPrefix)
        end
        widget:SetLabel(presentation.label)
        if type(widget.SetCountdownTextVisibleOverride) == "function" then
            widget:SetCountdownTextVisibleOverride(presentation.countdownTextVisible)
        end
        if type(widget.SetCooldownVisualVisibleOverride) == "function" then
            widget:SetCooldownVisualVisibleOverride(presentation.cooldownVisualVisible)
        end
        -- Cooldown completion is edge-triggered.  The callback has to exist
        -- before a new native Duration is applied; installing it afterward can
        -- miss a completion that the client resolves during SetDurationObject.
        ConfigureCooldownDoneCallback(self, item, presentation)
        ApplyCooldown(self, widget, presentation.cooldown)
        if presentation.usable ~= nil then widget:SetUsable(presentation.usable) else widget:SetUsable(nil) end
        if presentation.desaturated ~= nil then widget:SetDesaturated(presentation.desaturated) else widget:SetDesaturated(nil) end
        -- 先把 IconWidget 放到 ItemRoot。core.icon 就是这个 IconWidget 本体，
        -- 因而固定 core 布局必须在此之后应用；否则其 SetAnchor 会被下面的
        -- 默认居中锚点立刻覆盖，图标永远留在行中央。
        item.bodyWidth, item.bodyHeight = ResolveDeclaredBodySize(presentation, widget)
        item.root:SetSize(item.bodyWidth, item.bodyHeight)
        widget:ClearAllPoints()
        widget:SetPoint("CENTER", item.root, "CENTER", item.localOffset.x, item.localOffset.y)
        -- 固定 core 槽位布局必须在 Panel hitbox 建立前完成；之后才轮到
        -- RegionElements 的独立子 Region 与交互覆盖层。
        ApplyCoreLayout(item, presentation)
        ApplyCoreGlow(item, presentation)
        local hosts = ConfigureExtraChildHosts(item, presentation.extraHosts)
        if type(presentation.renderExtraChildren) == "function" then
            presentation.renderExtraChildren(widget, hosts, presentation.extraChildren or {}, self.interactionMode, item)
        end
        item.regions:SetConfigContextID(presentation.regionConfigContextID)
        item.regions:Apply(presentation.regionElements)
        ConfigureRuntimeTooltip(self, item, presentation.runtimeTooltip)
        ConfigureRuntimeAction(self, item, presentation.runtimeAction)
        ConfigureInteractionOverlays(self, item, presentation.interaction)
        item.root:Show()
        return item
    end

    function collection:SetItems(items, layout)
        -- WidgetLayout 的语义 FLOW 是等尺寸 Body contract；不能像旧手写页面
        -- 一样用最后一个 item 的尺寸悄悄覆盖前项。每次布局在所有 item 都
        -- Apply 完后校验，因而一次配置刷新可原子地改变整组的统一尺寸。
        local bodyWidth, bodyHeight
        for _, item in ipairs(items or {}) do
            if not item or not item.bodyWidth or not item.bodyHeight then
                error("IconCollection SetItems requires every item to be applied", 2)
            end
            if not bodyWidth then
                bodyWidth, bodyHeight = item.bodyWidth, item.bodyHeight
            elseif item.bodyWidth ~= bodyWidth or item.bodyHeight ~= bodyHeight then
                error("IconCollection requires one uniform body size per collection", 2)
            end
        end
        if bodyWidth then
            self.itemWidth, self.itemHeight = bodyWidth, bodyHeight
        end
        local wanted = {}
        for _, item in ipairs(items or {}) do
            if item and item.id then wanted[item.id] = true end
        end
        for itemID, item in pairs(self.itemsByID) do
            if not wanted[itemID] and item.root then item.root:Hide() end
        end
        self.layout:ApplyStyle(CopyLayout(layout, self.contentCenter))
        self.layout:SetSemanticItems(items or {}, self.itemWidth, self.itemHeight)
        self.currentItems = items or {}
        self.currentLayout = layout
        return self
    end

    -- GUI Slider 的 live 阶段只能重套已物化 presentation。这个正式入口不
    -- 暴露 Widget/Frame，也绝不 Acquire/Release Item；调用方只可修改同一份
    -- presentation 后由 Collection 统一 ApplyItem，并以既有 layout 更新步距。
    function collection:ReapplyCurrentItems(mutatePresentation, options)
        if self.released then return false end
        options = type(options) == "table" and options or {}
        for _, item in ipairs(self.currentItems or {}) do
            if item and item.widget and item.presentation then
                if type(mutatePresentation) == "function" then
                    mutatePresentation(item.presentation, item)
                end
                self:ApplyItem(item, item.presentation)
            end
        end
        if options.reapplyLayout ~= false then
            self:SetItems(self.currentItems, self.currentLayout)
        end
        return true
    end

    -- 排列 Slider 的 live 阶段只允许重排已物化的同一批 Item。不得借此 Acquire、
    -- Release、重建 Preview session 或重新生成 presentation。
    function collection:ReapplyCurrentLayout(layout)
        if self.released then return false end
        self:SetItems(self.currentItems or {}, layout or self.currentLayout)
        return true
    end

    -- 拓扑型 GUI 字段（例如频道勾选）只能在正常 Render 已物化的 Item
    -- 范围内切换可见集合。这个入口绝不 Acquire/Release，也不让模块读取
    -- itemsByID 私有表。
    function collection:ReapplyExistingItemSet(itemIDs, layout)
        if self.released or type(itemIDs) ~= "table" then return false end
        local items = {}
        for _, itemID in ipairs(itemIDs) do
            local item = self.itemsByID[itemID]
            if item then items[#items + 1] = item end
        end
        self:SetItems(items, layout or self.currentLayout)
        return true
    end

    function collection:SetItemUsable(itemID, usable)
        local item = self.itemsByID[itemID]
        if not item or not item.widget then return false end
        item.widget:SetUsable(usable)
        return true
    end

    function collection:GetBounds()
        return self.layout:GetBounds()
    end

    function collection:GetWorldBounds()
        local bounds
        local offsets = self.layout:GetSemanticItemOffsets()
        for _, item in ipairs(self.currentItems or {}) do
            local offset = offsets[item]
            if offset and item and item.declaredBounds then
                bounds = UnionDeclaredBounds(bounds, item.declaredBounds, CombineOffsets(offset, item.localOffset))
            end
            if offset and item and item.regions then
                local regionBounds = item.regions:GetDeclaredBounds()
                -- A presentation without RegionElements legitimately has no
                -- child bounds. It must not be treated as a rectangle while
                -- computing the parent Icon world-edit extent.
                if type(regionBounds) == "table" then
                    bounds = UnionDeclaredBounds(bounds, regionBounds, offset)
                end
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

    function collection:GetItems() return self.itemsByID end

    function collection:ReleaseItem(itemID)
        local item = self.itemsByID[itemID]
        if not item then return end
        self.itemsByID[itemID] = nil
        StopCoreGlow(item)
        if type(item.presentation) == "table" and type(item.presentation.releaseExtraChildren) == "function" then
            item.presentation.releaseExtraChildren(item.widget, item)
        end
        ResetRuntimeTooltip(item)
        ResetRuntimeAction(item)
        ReleaseInteractionOverlays(item)
        if item.regions then item.regions:Release() end
        item.cooldownDoneGeneration = (item.cooldownDoneGeneration or 0) + 1
        item.widget:SetCooldownDoneCallback(nil)
        item.widget:Release()
        item.widget = nil
        ReleaseItemRoot(item.root)
        item.root = nil
        item.bodyWidth = nil
        item.bodyHeight = nil
        item.declaredBounds = nil
        item.localOffset = nil
        item.coreLayoutRects = nil
        item.presentation = nil
        item.interactionOverlay = nil
        item.interactionOverlays = nil
        item.extraChildHostIDs = nil
        item.regions = nil
    end

    function collection:Release()
        self.released = true
        for itemID in pairs(self.itemsByID) do self:ReleaseItem(itemID) end
        self.layout:Release()
        self.layout = nil
        self.currentItems = nil
        self.currentLayout = nil
        self.itemWidth = nil
        self.itemHeight = nil
        self.host = nil
        self.callbacks = nil
    end

    return collection
end

function EXUI:CreateIconCollection(parent, interactionMode, moduleKey, callbacks)
    return CreateCollection(parent, interactionMode, moduleKey, callbacks)
end
