-- =========================================================
-- ExwindRegionElements.lua
--
-- 唯一通用子 Region 生命周期。它只消费纯 declaration/presentation，绝不读取
-- ModuleDB / Rule DB、绝不接收模块 render/release 函数，也绝不建立第二套配置。
-- =========================================================

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
if not EXUI then return end

local ALLOWED_KINDS = { text = true, icon = true, timerbar = true, texture = true }
local CONFIG_CONTEXT_PROVIDERS = {}

local function SetInteractionOverlayVisual(overlay, visible, dragging)
    if not overlay then return end
    if not visible then
        -- 透明不够可靠：pool / reparent 后必须物理移除 Backdrop，避免额外元素
        -- 在未悬停时留下常住的选中框。
        overlay:SetBackdrop(nil)
        return
    end
    overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    if dragging then
        overlay:SetBackdropBorderColor(1.00, 0.82, 0.20, 1.00)
        overlay:SetBackdropColor(1.00, 0.72, 0.12, 0.18)
    else
        overlay:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        overlay:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
    end
end

-- A RegionElements configuration context is deliberately not a renderer
-- callback.  It resolves the live configuration root from a stable identity
-- at the instant an interaction commits, so a stale panel can never write the
-- rule which happens to be selected now.
function EXUI:RegisterRegionConfigContextProvider(providerID, provider)
    if type(providerID) ~= "string" or providerID == "" then
        error("RegisterRegionConfigContextProvider requires non-empty providerID", 2)
    end
    if type(provider) ~= "table" or type(provider.Resolve) ~= "function" then
        error("RegisterRegionConfigContextProvider requires provider.Resolve", 2)
    end
    if CONFIG_CONTEXT_PROVIDERS[providerID] ~= nil then
        error("Region config context provider already registered: " .. providerID, 2)
    end
    CONFIG_CONTEXT_PROVIDERS[providerID] = provider
end

local function ResolveConfigContext(contextID)
    if type(contextID) ~= "string" or contextID == "" then
        error("RegionElements requires non-empty configContextID", 3)
    end
    local providerID = contextID:match("^([^:]+):")
    local provider = providerID and CONFIG_CONTEXT_PROVIDERS[providerID] or nil
    if not provider then error("RegionElements has no config context provider for " .. contextID, 3) end
    local context = provider.Resolve(contextID)
    if type(context) ~= "table" or type(context.Write) ~= "function" or type(context.Commit) ~= "function" then
        error("RegionElements config context is invalid: " .. contextID, 3)
    end
    return context
end

local function Number(value, fallback)
    value = tonumber(value)
    return value == nil and (fallback or 0) or value
end

local function AssertPure(value, label, seen, allowSecret)
    local valueType = type(value)
    -- 12.x Secret Values are opaque userdata, but are legal only when passed
    -- unchanged to an existing narrow Widget native API (Duration, raid mark,
    -- Secret visibility, icon).  Arbitrary userdata/Frame remains forbidden.
    if valueType == "userdata" and type(issecretvalue) == "function" and issecretvalue(value) and allowSecret == true then return end
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        error(label .. " cannot contain " .. valueType, 3)
    end
    if valueType ~= "table" then return end
    if type(value.GetObjectType) == "function" then error(label .. " cannot contain a Frame/Region object", 3) end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        AssertPure(key, label, seen, allowSecret)
        AssertPure(child, label, seen, allowSecret)
    end
end

local function IsSecret(value)
    return type(value) == "userdata" and type(issecretvalue) == "function" and issecretvalue(value)
end

-- `content` is the only payload channel, but it is not a blanket Secret
-- escape hatch.  A Secret value may occur only under a native Widget input
-- which this manager forwards without inspecting.  All other fields remain
-- ordinary declarative data.
local SECRET_CONTENT_KEYS = {
    text = { text = true, durationObject = true, secretDuration = true },
    icon = { icon = true, stacks = true, cooldown = true },
    timerbar = { icon = true, stacks = true, durationObject = true, secretDuration = true, value = true },
    texture = { raidTargetIndex = true, shownFromBoolean = true },
}

local function AssertNativePayload(value, label, seen)
    if IsSecret(value) then return end
    local valueType = type(value)
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        error(label .. " cannot contain " .. valueType, 3)
    end
    if valueType ~= "table" then return end
    if type(value.GetObjectType) == "function" then error(label .. " cannot contain a Frame/Region object", 3) end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        AssertNativePayload(key, label, seen)
        AssertNativePayload(child, label, seen)
    end
end

local function AssertContent(kind, content, label)
    if content == nil then return end
    if type(content) ~= "table" then error(label .. " must be table", 3) end
    local nativeKeys = SECRET_CONTENT_KEYS[kind] or {}
    for key, value in pairs(content) do
        if nativeKeys[key] then
            AssertNativePayload(value, label .. "." .. key)
        else
            AssertPure(value, label .. "." .. tostring(key), nil, false)
        end
    end
end

local function RequireBounds(spec, label)
    local bounds = type(spec) == "table" and spec.bounds or nil
    local width, height = Number(bounds and bounds.width), Number(bounds and bounds.height)
    if width <= 0 or height <= 0 then error(label .. " requires bounds.width and bounds.height", 3) end
    -- Keep the declaration's direct table identity.  It is presentation
    -- geometry, never a copied configuration/style snapshot.
    return bounds
end

local function NormalizeAnchor(spec)
    local anchor = type(spec.anchor) == "table" and spec.anchor or {}
    local relativeElement = anchor.relativeElement or "core.root"
    if type(relativeElement) ~= "string" or relativeElement == "" then
        error("RegionElements anchor.relativeElement must be a non-empty semantic ID", 3)
    end
    return {
        point = anchor.point or "CENTER",
        relativePoint = anchor.relativePoint or anchor.point or "CENTER",
        relativeElement = relativeElement,
        x = Number(anchor.x),
        y = Number(anchor.y),
    }
end

local function GetStylePosition(entry)
    local position = type(entry.spec.position) == "table" and entry.spec.position or nil
    if position then return Number(position.x), Number(position.y) end
    local style = type(entry.spec.style) == "table" and entry.spec.style or {}
    return Number(style.x), Number(style.y)
end

local function IsText(entry)
    return entry.kind == "text"
end

local function ResolvePoint(rect, point)
    rect = rect or { left = -0.5, right = 0.5, bottom = -0.5, top = 0.5 }
    point = tostring(point or "CENTER"):upper()
    local x = (rect.left + rect.right) * .5
    local y = (rect.bottom + rect.top) * .5
    if point:find("LEFT", 1, true) then x = rect.left elseif point:find("RIGHT", 1, true) then x = rect.right end
    if point:find("TOP", 1, true) then y = rect.top elseif point:find("BOTTOM", 1, true) then y = rect.bottom end
    return x, y
end

local function RectFromAnchor(relativeRect, anchor, width, height, positionX, positionY)
    local x, y = ResolvePoint(relativeRect, anchor.relativePoint)
    x, y = x + anchor.x + positionX, y + anchor.y + positionY
    local localRect = { left = x, right = x, bottom = y, top = y }
    local point = tostring(anchor.point or "CENTER"):upper()
    if point:find("LEFT", 1, true) then localRect.right = localRect.right + width
    elseif point:find("RIGHT", 1, true) then localRect.left = localRect.left - width
    else localRect.left, localRect.right = x - width * .5, x + width * .5 end
    if point:find("TOP", 1, true) then localRect.bottom = localRect.bottom - height
    elseif point:find("BOTTOM", 1, true) then localRect.top = localRect.top + height
    else localRect.bottom, localRect.top = y - height * .5, y + height * .5 end
    return localRect
end

local function Union(acc, rect)
    if not rect then return acc end
    if not acc then return { left = rect.left, right = rect.right, bottom = rect.bottom, top = rect.top } end
    acc.left, acc.right = math.min(acc.left, rect.left), math.max(acc.right, rect.right)
    acc.bottom, acc.top = math.min(acc.bottom, rect.bottom), math.max(acc.top, rect.top)
    return acc
end

local function ApplyText(widget, spec)
    if type(spec.style) ~= "table" then error("RegionElements text requires direct style table", 3) end
    widget:ResetSecretText()
    widget:ApplyStyle(spec.style)
    local content = type(spec.content) == "table" and spec.content or {}
    if content.durationObject ~= nil then
        widget:SetDurationBinding(content.durationObject, content.durationOptions)
    elseif content.secretDuration ~= nil then
        widget:SetDurationBinding(content.secretDuration, content.durationOptions)
    elseif content.secretText == true then
        widget:SetSecretText(content.text)
    else
        widget:SetText(content.text or "")
    end
    if type(content.color) == "table" then widget:SetColor(content.color) end
    if content.shown == false or spec.shown == false or spec.style.enabled == false then widget:Hide() else widget:Show() end
end

local function ApplyIcon(widget, spec, moduleKey)
    if type(spec.style) ~= "table" then error("RegionElements icon requires direct style table", 3) end
    local content = type(spec.content) == "table" and spec.content or {}
    widget:ApplyStyle(spec.style)
    local icon = content.icon
    if type(icon) == "table" and icon.mode == "SECRET" then widget:SetSecretIcon(icon.value)
    elseif type(icon) == "table" and icon.mode == "ATLAS" then widget:SetAtlas(icon.value)
    else widget:SetIcon(type(icon) == "table" and icon.value or icon) end
    local stacks = content.stacks
    if type(stacks) == "table" and stacks.mode == "SECRET" then widget:SetSecretStacks(stacks.value)
    else widget:SetStacks(type(stacks) == "table" and stacks.value or stacks) end
    widget:SetLabel(content.label)
    local cooldown = content.cooldown
    if type(cooldown) ~= "table" then widget:ClearCooldown()
    elseif cooldown.mode == "SECRET" then widget:SetSecretCooldown(cooldown.duration, cooldown.clearIfZero)
    elseif cooldown.mode == "DURATION" then widget:SetDurationObject(cooldown.duration, cooldown.clearIfZero,
        cooldown.durationTextProperty, cooldown.durationTextOptions)
    elseif cooldown.static == true then widget:SetStaticCooldown(cooldown.remaining, cooldown.duration, cooldown.format)
    elseif cooldown.start ~= nil and cooldown.duration ~= nil then widget:SetCooldown(moduleKey, cooldown.start, cooldown.duration, cooldown.modRate, cooldown.format)
    else widget:SetCountdownText(cooldown.text) end
    widget:SetShown(content.shown ~= false and spec.shown ~= false)
end

local function ApplyTimerBar(widget, spec, moduleKey)
    if type(spec.style) ~= "table" then error("RegionElements timerbar requires direct style table", 3) end
    local content = type(spec.content) == "table" and spec.content or {}
    if type(widget.SetGeometryOverride) == "function" then widget:SetGeometryOverride(content.geometry) end
    if type(widget.SetPresentationOptions) == "function" then widget:SetPresentationOptions(content.presentationOptions) end
    if spec.standardSchema then
        EXUI:ApplyStandardTimerBarStyle(widget, spec.style, spec.standardSchema)
        EXUI:SetStandardTimerBarContent(widget, moduleKey, content)
        return
    end
    widget:ApplyStyle(spec.style)
    if content.icon ~= nil then
        if type(content.icon) == "table" and content.icon.mode == "SECRET" then widget:SetSecretIcon(content.icon.value)
        else widget:SetIcon(type(content.icon) == "table" and content.icon.value or content.icon) end
    end
    widget:SetLabel(content.label or content.spellName)
    if widget.textB then widget.textB:SetText(content.targetName or content.textB or "") end
    if content.durationObject ~= nil then widget:SetDurationObject(content.durationObject, content.interpolation, content.direction)
    elseif content.secretDuration ~= nil then widget:SetSecretTime(content.secretDuration, content.interpolation, content.direction)
    -- Secret values must be forwarded unchanged.  Do not use `or` fallback
    -- selection here, because that turns an opaque native value into Lua
    -- control flow.  The declaration contract requires `maximum` for this
    -- channel.
    elseif content.hasSecretProgress == true then widget:SetSecretProgress(content.value, content.maximum, content.minimum)
    else widget:SetProgress(content.progress or 0, content.maximum or content.max or 1) end
    if content.stacks ~= nil then widget:SetStacks(content.stacks) end
    if type(widget.SetFillVisible) == "function" then widget:SetFillVisible(content.fillVisible ~= false) end
    widget:SetShown(content.shown ~= false and spec.shown ~= false)
end

local function ApplyTexture(widget, spec)
    if type(spec.style) ~= "table" then error("RegionElements texture requires direct style table", 3) end
    local content = type(spec.content) == "table" and spec.content or {}
    widget:ResetShownFromBoolean()
    widget:ApplyPresentation({
        style = spec.style,
        width = spec.bounds.width,
        height = spec.bounds.height,
        texture = content.texture or spec.style.texture,
        atlas = content.atlas or spec.style.atlas,
        texCoord = content.texCoord,
        flipH = content.flipH,
        flipV = content.flipV,
        blendMode = content.blendMode or spec.style.blendMode,
        rotation = content.rotation or spec.style.rotation,
        color = content.color or spec.style,
        shown = content.shown ~= false and spec.shown ~= false,
    })
    -- These native channels may carry opaque Secret values.  Call them
    -- unconditionally so Lua never compares/branches on the secret itself.
    if content.hasRaidTargetIndex == true then widget:SetRaidTargetIndex(content.raidTargetIndex) end
    -- The boolean itself is never inspected.  Producer sets this ordinary
    -- declaration flag when it intentionally supplies the native channel.
    if content.hasShownFromBoolean == true then widget:SetShownFromBoolean(content.shownFromBoolean) end
end

local function ReleaseEntry(entry)
    if entry.overlay then
        entry.overlay:SetScript("OnUpdate", nil)
        entry.overlay:SetScript("OnMouseDown", nil)
        entry.overlay:SetScript("OnMouseUp", nil)
        entry.overlay:Hide()
        entry.overlay:SetParent(nil)
        entry.overlay = nil
    end
    if entry.widget then
        if entry.kind == "timerbar" and entry.spec and entry.spec.standardSchema then
            EXUI:ReleaseStandardTimerBarWidget(entry.widget)
        else
            entry.widget:Release()
        end
    end
    entry.widget = nil
    if entry.root then
        entry.root:Hide()
        entry.root:ClearAllPoints()
        entry.root:SetParent(nil)
    end
    entry.root = nil
end

function EXUI:CreateRegionElements(options)
    if type(options) ~= "table" or type(options.ownerRoot) ~= "table" or type(options.resolveCore) ~= "function" then
        error("CreateRegionElements requires ownerRoot and resolveCore", 2)
    end
    local manager = {
        ownerRoot = options.ownerRoot,
        resolveCore = options.resolveCore,
        interactionMode = options.interactionMode,
        moduleKey = options.moduleKey,
        emitIntent = options.emitIntent,
        syncTransientPosition = options.syncTransientPosition,
        configContextID = options.configContextID,
        entriesByID = {},
        order = {},
    }

    local function CommitElementMove(entry, interaction, position)
        local context = ResolveConfigContext(manager.configContextID)
        local mapping = type(interaction.position) == "table" and interaction.position or nil
        if type(mapping and mapping.x) ~= "string" or type(mapping and mapping.y) ~= "string" then
            error("RegionElements " .. entry.id .. " config-context drag requires interaction.position.x/y paths", 3)
        end
        local writtenX, reasonX = context.Write(mapping.x, position.x)
        if writtenX ~= true then error("RegionElements failed to write " .. mapping.x .. ": " .. tostring(reasonX), 3) end
        local writtenY, reasonY = context.Write(mapping.y, position.y)
        if writtenY ~= true then error("RegionElements failed to write " .. mapping.y .. ": " .. tostring(reasonY), 3) end
        local committed, reason = context.Commit({
            type = "elementMoved",
            elementID = interaction.elementID or ("elements." .. entry.id),
            position = { x = position.x, y = position.y },
        })
        if committed ~= true then error("RegionElements failed to commit " .. tostring(manager.configContextID) .. ": " .. tostring(reason), 3) end
        local moduleKey = EXUI:RequireModuleKey(manager.moduleKey, "RegionElements config-context drag")
        EXUI:NotifyModuleValueChanged(moduleKey, mapping.x, "committed")
    end

    local function ResolveTarget(entry)
        local targetID = entry.anchor.relativeElement
        if targetID:sub(1, 5) == "core." then return manager.resolveCore(targetID) end
        local id, childCore = targetID:match("^elements%.([^.]+)%.(core%..+)$")
        if id and childCore then
            local target = manager.entriesByID[id]
            if not target or not target.widget then error("RegionElements " .. entry.id .. " anchors unknown or later element: " .. targetID, 3) end
            if target.kind == "timerbar" or target.kind == "icon" then return target.widget:ResolveDeclaredElement(childCore), target.declaredBounds end
            if target.kind == "text" and childCore == "core.text" then return target.widget, target.declaredBounds end
            if target.kind == "texture" and childCore == "core.material" then return target.widget, target.declaredBounds end
            error("RegionElements " .. entry.id .. " anchors unsupported child core: " .. targetID, 3)
        end
        id = targetID:match("^elements%.(.+)$")
        local target = id and manager.entriesByID[id] or nil
        if not target or not target.root then error("RegionElements " .. entry.id .. " anchors unknown or later element: " .. targetID, 3) end
        return target.root, target.declaredBounds
    end

    local function SetRootAnchor(entry, transientX, transientY)
        local relativeRoot, relativeRect = ResolveTarget(entry)
        if not relativeRoot then error("RegionElements " .. entry.id .. " anchor has no root", 3) end
        local positionX, positionY = GetStylePosition(entry)
        if transientX ~= nil then
            if IsText(entry) then
                positionX, positionY = transientX - positionX, transientY - positionY
            else
                positionX, positionY = transientX, transientY
            end
        elseif IsText(entry) then
            positionX, positionY = 0, 0
        end
        entry.root:ClearAllPoints()
        entry.root:SetSize(entry.bounds.width, entry.bounds.height)
        entry.root:SetPoint(entry.anchor.point, relativeRoot, entry.anchor.relativePoint,
            entry.anchor.x + positionX, entry.anchor.y + positionY)
        local declaredPositionX, declaredPositionY = GetStylePosition(entry)
        entry.declaredBounds = RectFromAnchor(relativeRect, entry.anchor, entry.bounds.width, entry.bounds.height,
            IsText(entry) and declaredPositionX or declaredPositionX, IsText(entry) and declaredPositionY or declaredPositionY)
    end

    local function EnsureWidget(entry)
        if entry.root and entry.widget then return end
        entry.root = CreateFrame("Frame", nil, manager.ownerRoot)
        entry.root:EnableMouse(false)
        if entry.kind == "text" then entry.widget = EXUI:CreateTextWidget(entry.root, "element:" .. entry.id)
        elseif entry.kind == "icon" then entry.widget = EXUI:CreateIconWidget(entry.root)
        elseif entry.kind == "timerbar" then
            entry.widget = entry.spec.standardSchema and EXUI:CreateStandardTimerBarWidget(entry.root, entry.spec.standardSchema)
                or EXUI:CreateTimerBarWidget(entry.root)
        else entry.widget = EXUI:CreateExtraTextureWidget(entry.root) end
    end

    local function ConfigureInteraction(entry)
        local interaction = type(entry.spec.interaction) == "table" and entry.spec.interaction or nil
        if manager.interactionMode ~= "panel" or not interaction or entry.visible ~= true then
            if entry.overlay then entry.overlay:Hide() end
            return
        end
        local overlay = entry.overlay
        if not overlay then
            overlay = CreateFrame("Button", nil, entry.root, "BackdropTemplate")
            entry.overlay = overlay
        end
        overlay:ClearAllPoints(); overlay:SetAllPoints(entry.root)
        overlay:SetFrameStrata(entry.root:GetFrameStrata() or "MEDIUM")
        overlay:SetFrameLevel((entry.root:GetFrameLevel() or 0) + 80)
        overlay:EnableMouse(true)
        overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown")
        SetInteractionOverlayVisual(overlay, overlay:IsMouseOver(), false)
        overlay:SetScript("OnEnter", function(self)
            SetInteractionOverlayVisual(self, true, false)
        end)
        overlay:SetScript("OnLeave", function(self)
            if not self.__regionDrag then SetInteractionOverlayVisual(self, false, false) end
        end)
        overlay:SetScript("OnMouseDown", function(self, button)
            local elementID = interaction.elementID or ("elements." .. entry.id)
            if button == "RightButton" then
                if interaction.rightClickable == false then return end
                if type(manager.emitIntent) == "function" then manager.emitIntent({ type = "elementRightClicked", elementID = elementID, guiTarget = interaction.guiTarget or elementID }) end
                return
            end
            if button ~= "LeftButton" or interaction.movable ~= true then return end
            local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            local x, y = GetCursorPosition()
            local baseX, baseY = GetStylePosition(entry)
            self.__regionDrag = { scale = scale, cursorX = x / scale, cursorY = y / scale, baseX = baseX, baseY = baseY, moved = false }
            SetInteractionOverlayVisual(self, true, true)
            self:SetScript("OnUpdate", function(button)
                local drag = button.__regionDrag
                if not drag then return end
                if not IsMouseButtonDown("LeftButton") then button:GetScript("OnMouseUp")(button, "LeftButton"); return end
                local cursorX, cursorY = GetCursorPosition()
                local dx, dy = cursorX / drag.scale - drag.cursorX, cursorY / drag.scale - drag.cursorY
                if not drag.moved and math.abs(dx) < 2 and math.abs(dy) < 2 then return end
                drag.moved = true
                local position = { x = drag.baseX + dx, y = drag.baseY + dy }
                if type(manager.syncTransientPosition) == "function" then
                    manager.syncTransientPosition(entry.id, position)
                else
                    SetRootAnchor(entry, position.x, position.y)
                end
            end)
        end)
        overlay:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            local drag = self.__regionDrag
            self:SetScript("OnUpdate", nil); self.__regionDrag = nil
            SetInteractionOverlayVisual(self, self:IsMouseOver(), false)
            if drag and drag.moved and type(manager.emitIntent) == "function" then
                local cursorX, cursorY = GetCursorPosition()
                local position = { x = drag.baseX + cursorX / drag.scale - drag.cursorX, y = drag.baseY + cursorY / drag.scale - drag.cursorY }
                if manager.configContextID ~= nil then
                    CommitElementMove(entry, interaction, position)
                else
                    manager.emitIntent({ type = "elementMoved", elementID = interaction.elementID or ("elements." .. entry.id), position = position })
                end
            elseif drag and drag.moved and manager.configContextID ~= nil then
                local cursorX, cursorY = GetCursorPosition()
                CommitElementMove(entry, interaction, { x = drag.baseX + cursorX / drag.scale - drag.cursorX, y = drag.baseY + cursorY / drag.scale - drag.cursorY })
            end
        end)
        overlay:Show()
    end

    local function ApplyEntry(entry)
        EnsureWidget(entry)
        SetRootAnchor(entry)
        if entry.kind == "text" then
            entry.widget:SetBounds(entry.bounds.width, entry.bounds.height)
            entry.widget:SetAnchor("CENTER", entry.root, "CENTER")
            ApplyText(entry.widget, entry.spec)
        elseif entry.kind == "icon" then
            entry.widget:ClearAllPoints(); entry.widget:SetPoint("CENTER", entry.root, "CENTER")
            ApplyIcon(entry.widget, entry.spec, entry.moduleKey)
        elseif entry.kind == "timerbar" then
            local content = type(entry.spec.content) == "table" and entry.spec.content or {}
            entry.root:SetClipsChildren(content.viewport == true)
            entry.widget:ClearAllPoints()
            if content.viewport == true then entry.widget:SetPoint("LEFT", entry.root, "LEFT", 0, 0)
            else entry.widget:SetPoint("CENTER", entry.root, "CENTER") end
            ApplyTimerBar(entry.widget, entry.spec, entry.moduleKey)
        else
            entry.widget:ClearAllPoints(); entry.widget:SetPoint("CENTER", entry.root, "CENTER")
            ApplyTexture(entry.widget, entry.spec)
        end
        local content = type(entry.spec.content) == "table" and entry.spec.content or {}
        entry.visible = entry.spec.shown ~= false and content.shown ~= false
        entry.root:SetShown(entry.visible)
        ConfigureInteraction(entry)
    end

    function manager:Apply(declarations)
        if declarations == nil then declarations = {} end
        if type(declarations) ~= "table" then error("RegionElements presentation must be an ordered array", 2) end
        local count = #declarations
        for key in pairs(declarations) do
            if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then
                error("RegionElements presentation must be a dense ordered array", 2)
            end
        end
        local wanted, nextOrder = {}, {}
        for index, spec in ipairs(declarations) do
            if type(spec) ~= "table" then error("RegionElements[" .. index .. "] must be table", 2) end
            for key, value in pairs(spec) do
                -- Secret data has no place in style/anchor/bounds/interaction.
                -- Even `content` is checked against the narrow native channel
                -- for its specific child kind.
                if key == "content" then
                    AssertContent(spec.kind, value, "RegionElements[" .. index .. "].content")
                else
                    AssertPure(value, "RegionElements[" .. index .. "]." .. tostring(key), nil, false)
                end
            end
            if type(spec.id) ~= "string" or spec.id == "" then error("RegionElements entry requires non-empty id", 2) end
            if not ALLOWED_KINDS[spec.kind] then error("RegionElements." .. spec.id .. " has unsupported kind: " .. tostring(spec.kind), 2) end
            if wanted[spec.id] then error("RegionElements duplicate id: " .. spec.id, 2) end
            local entry = self.entriesByID[spec.id]
            if entry and entry.kind ~= spec.kind then ReleaseEntry(entry); entry = nil end
            entry = entry or { id = spec.id, kind = spec.kind }
            entry.spec, entry.moduleKey, entry.anchor, entry.bounds = spec, self.moduleKey, NormalizeAnchor(spec), RequireBounds(spec, "RegionElements." .. spec.id)
            self.entriesByID[spec.id] = entry
            wanted[spec.id], nextOrder[#nextOrder + 1] = true, spec.id
            ApplyEntry(entry)
        end
        for id, entry in pairs(self.entriesByID) do
            if not wanted[id] then ReleaseEntry(entry); self.entriesByID[id] = nil end
        end
        self.order = nextOrder
        return self
    end

    function manager:SetConfigContextID(contextID)
        if contextID ~= nil and (type(contextID) ~= "string" or contextID == "") then
            error("RegionElements configContextID must be non-empty string or nil", 2)
        end
        self.configContextID = contextID
        return self
    end

    -- 同一 panel collection 中的同 ID extra element 共用一份 ModuleDB 位置。
    -- 拖动时只同步已物化样本的根锚点；正式 DB 写入仍只发生在 mouse-up。
    function manager:ApplyTransientPosition(entryID, position)
        if self.interactionMode ~= "panel" or type(entryID) ~= "string" or type(position) ~= "table" then return false end
        local entry = self.entriesByID[entryID]
        if not entry or entry.visible ~= true then return false end
        SetRootAnchor(entry, position.x, position.y)
        return true
    end

    function manager:GetDeclaredBounds()
        local bounds
        for _, id in ipairs(self.order) do
            local entry = self.entriesByID[id]
            if entry.visible == true then bounds = Union(bounds, entry.declaredBounds) end
        end
        return bounds
    end

    function manager:Release()
        for id, entry in pairs(self.entriesByID) do ReleaseEntry(entry); self.entriesByID[id] = nil end
        self.order, self.ownerRoot, self.resolveCore, self.emitIntent, self.syncTransientPosition, self.configContextID = nil, nil, nil, nil, nil, nil
    end

    return manager
end
