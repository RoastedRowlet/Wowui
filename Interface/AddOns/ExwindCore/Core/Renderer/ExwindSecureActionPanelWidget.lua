-- =============================================================
-- SecureActionPanelWidget
-- 固定安全 slot 的最小容器；不解释任何 raid/world/action 业务。
-- Runtime 才创建 SecureActionButtonTemplate，World/Panel 永远是不可点击同构视觉。
-- =============================================================
-- EXUI is owned by ExwindTools.  It is not published as _G.EXUI, so looking
-- it up there made this file return during load and left the formal factory
-- nil for RaidMarkerPanel.
local EXUI = ExwindTools and ExwindTools.UI
if not EXUI then return end

local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown

local function IsLocked() return InCombatLockdown and InCombatLockdown() end
local function ApplyVisual(slot, spec)
    local visual = spec.visual or {}
    local contentScale = tonumber(visual.contentScale) or 1
    slot.widget:ApplyStyle({ icon = {
        width = (visual.width or 28) * contentScale, height = (visual.height or 28) * contentScale,
        showIcon = visual.shown ~= false, enableCrop = visual.enableCrop,
        colorR = visual.colorR, colorG = visual.colorG, colorB = visual.colorB, colorA = visual.colorA,
        showBorder = false, showCooldown = false,
    } })
    slot.widget:SetIcon(visual.iconID)
    if visual.atlas then slot.widget:SetAtlas(visual.atlas) end
    if visual.raidTargetIndex then
        slot.extra:SetSize(visual.width or 28, visual.height or 28)
        slot.extra:SetAnchor("CENTER", slot.visualRoot, "CENTER", 0, 0)
        slot.extra:SetRaidTargetIndex(visual.raidTargetIndex)
    else
        slot.extra:SetVisible(false)
    end
    slot.widget:SetDesaturated(visual.desaturated == true)
    slot.widget:SetAlpha(visual.alpha or 1)
    -- IconWidget 不暴露内部 Texture；颜色是后续若确实需要的明确 style 字段，
    -- 这个安全容器不越过 Widget 边界取得裸 Texture。
    slot.widget:SetShown(visual.shown ~= false)
end
local function ApplyAttributes(slot, attributes)
    if slot.mode ~= "runtime" then return true end
    if IsLocked() then slot.pendingAttributes = attributes; return false end
    for key in pairs(slot.appliedAttributes) do if not attributes or attributes[key] == nil then slot.button:SetAttribute(key, nil) end end
    for key, value in pairs(attributes or {}) do slot.button:SetAttribute(key, value) end
    slot.appliedAttributes, slot.pendingAttributes = attributes or {}, nil
    return true
end
local function CreateSlot(panel, id)
    local button = CreateFrame("Button", nil, panel.root, panel.mode == "runtime" and "SecureActionButtonTemplate" or nil)
    button:SetSize(28, 28); button:EnableMouse(panel.mode == "runtime")
    if panel.mode == "runtime" then button:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown") end
    local slot = { panel = panel, id = id, mode = panel.mode, button = button, appliedAttributes = {} }
    slot.visualRoot = CreateFrame("Frame", nil, button)
    slot.visualRoot:SetSize(28, 28)
    slot.visualRoot:SetPoint("CENTER", button, "CENTER", 0, 0)
    slot.visualRoot:EnableMouse(false)
    slot.widget = EXUI:CreateIconWidget(slot.visualRoot)
    slot.extra = EXUI:CreateExtraTextureWidget(slot.visualRoot)
    slot.widget:SetAnchor("CENTER", slot.visualRoot, "CENTER", 0, 0)
    function slot:Apply(spec)
        spec = spec or {}; self.spec = spec; self.button:SetSize((spec.visual and spec.visual.width) or 28, (spec.visual and spec.visual.height) or 28)
        self.visualRoot:SetSize((spec.visual and spec.visual.width) or 28, (spec.visual and spec.visual.height) or 28)
        ApplyVisual(self, spec); ApplyAttributes(self, spec.attributes)
    end
    function slot:SetVisualScale(scale) self.visualRoot:SetScale(tonumber(scale) or 1) end
    function slot:SetShown(shown) if self.mode == "runtime" and IsLocked() then self.pendingShown = shown; return false end; self.button:SetShown(shown == true); self.pendingShown = nil; return true end
    function slot:Release() if self.widget then self.widget:Release(); self.widget = nil end; if self.extra then self.extra:Release(); self.extra = nil end; if self.visualRoot then self.visualRoot:Hide(); self.visualRoot:SetParent(nil); self.visualRoot = nil end; self.button:Hide(); self.button:SetParent(nil) end
    panel.slots[id] = slot; return slot
end
function EXUI:CreateSecureActionPanelWidget(parent, mode)
    assert(mode == "runtime" or mode == "world" or mode == "panel", "SecureActionPanelWidget mode")
    local root = CreateFrame("Frame", nil, parent); root:EnableMouse(false)
    local panel = { root = root, mode = mode, slots = {} }
    function panel:AcquireSlot(id) return self.slots[id] or CreateSlot(self, id) end
    -- GUI 刷新只能重套已经存在的 slot。resolver 不得要求缺失 slot；缺失
    -- presentation 由正常 Render/Mount 生命周期处理，绝不在这里创建。
    function panel:ReapplyExistingSlots(resolver)
        if type(resolver) ~= "function" then error("ReapplyExistingSlots requires resolver", 2) end
        for id, slot in pairs(self.slots) do
            local spec = resolver(id, slot.spec, slot)
            if spec ~= nil then slot:Apply(spec) end
        end
        return true
    end
    function panel:FlushSecure()
        if self.mode ~= "runtime" or IsLocked() then return false end
        for _, slot in pairs(self.slots) do if slot.pendingAttributes then ApplyAttributes(slot, slot.pendingAttributes) end; if slot.pendingShown ~= nil then slot:SetShown(slot.pendingShown) end end
        return true
    end
    function panel:Release() for _, slot in pairs(self.slots) do slot:Release() end; self.slots = {}; self.root:Hide(); self.root:SetParent(nil) end
    return panel
end

-- Runtime Collection item clicks.  Secure buttons stay outside the Collection
-- ItemRoot parent chain so B's visual layout may continue to move in combat.
local pendingItems, retiredMacros, activeMacros = {}, {}, {}
local function Locked() return InCombatLockdown and InCombatLockdown() end
local function DestroyMacro(macro)
    if not macro then return end
    if Locked() then retiredMacros[macro] = true; return end
    if UnregisterStateDriver then UnregisterStateDriver(macro.handler, "exauracombat") end
    macro.button:SetAttribute("type1", nil)
    macro.button:SetAttribute("macrotext1", nil)
    macro.button:Hide()
    macro.button:ClearAllPoints()
    macro.button:SetParent(nil)
    macro.handler:Hide()
    macro.handler:SetParent(nil)
    retiredMacros[macro] = nil
    activeMacros[macro] = nil
end
local function CreateMacro(item)
    local button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    local handler = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    handler:SetFrameRef("action", button)
    handler:SetAttribute("_onstate-exauracombat", [[
        if newstate == "combat" then
            local action = self:GetFrameRef("action")
            action:SetAttribute("type1", nil)
            action:SetAttribute("macrotext1", nil)
            action:Hide()
        end
    ]])
    RegisterStateDriver(handler, "exauracombat", "[combat] combat; ready")
    local macro = { button = button, handler = handler }
    item._collectionMacro = macro
    activeMacros[macro] = item
    return macro
end
local function MeasureItem(item)
    local root = item.root
    if not root or type(root.GetScaledRect) ~= "function" then return nil end
    local ok, x, y, width, height = pcall(root.GetScaledRect, root)
    if not ok then return nil end
    local secret = type(issecretvalue) == "function" and issecretvalue
    if secret and (secret(x) or secret(y) or secret(width) or secret(height)) then return nil end
    if type(x) ~= "number" or type(y) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number"
        or width <= 0 or height <= 0 then return nil end
    local scale = UIParent:GetEffectiveScale()
    if secret and secret(scale) then return nil end
    if type(scale) ~= "number" or scale <= 0 then return nil end
    return (x + width / 2) / scale, (y + height / 2) / scale,
        width / scale, height / scale
end
local function ItemVisible(item)
    local root = item.root
    if not root or type(root.IsVisible) ~= "function" then return false end
    local ok, visible = pcall(root.IsVisible, root)
    if not ok or type(issecretvalue) == "function" and issecretvalue(visible) then return false end
    return visible == true
end
local function ApplyClick(item)
    if not item.root then return false end
    local spec = item._collectionClickSpec or {}
    if spec.mode ~= "code" and item._collectionCodeButton then
        item._collectionCodeButton:Hide()
        item._collectionCodeButton:SetScript("OnClick", nil)
    end
    if spec.mode == "code" and type(spec.onClick) == "function" then
        local button = item._collectionCodeButton
        if not button then
            button = CreateFrame("Button", nil, item.root)
            item._collectionCodeButton = button
            button:EnableMouse(true)
            button:RegisterForClicks("AnyUp")
        end
        button:ClearAllPoints()
        button:SetAllPoints(item.root)
        button:SetScript("OnClick", function(_, mouseButton) spec.onClick(mouseButton) end)
        button:Show()
    end
    if Locked() then pendingItems[item] = true; return false end
    pendingItems[item] = nil
    if spec.mode ~= "macro" or type(spec.macro) ~= "string" or spec.macro == "" then
        DestroyMacro(item._collectionMacro)
        item._collectionMacro = nil
        return true
    end
    if not ItemVisible(item) then
        local macro = item._collectionMacro
        if macro then
            macro.button:SetAttribute("type1", nil)
            macro.button:SetAttribute("macrotext1", nil)
            macro.button:Hide()
        end
        return false
    end
    local x, y, width, height = MeasureItem(item)
    if not x then
        DestroyMacro(item._collectionMacro)
        item._collectionMacro = nil
        return false
    end
    local macro = item._collectionMacro or CreateMacro(item)
    local button = macro.button
    button:Hide()
    button:ClearAllPoints()
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    button:SetSize(width, height)
    button:SetFrameStrata(item.root:GetFrameStrata())
    button:SetFrameLevel((item.root:GetFrameLevel() or 0) + 20)
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", spec.macro)
    button:Show()
    return true
end
local flushFrame = CreateFrame("Frame")
flushFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
flushFrame:SetScript("OnEvent", function()
    if Locked() then return end
    for macro in pairs(retiredMacros) do DestroyMacro(macro) end
    for item in pairs(pendingItems) do
        pendingItems[item] = nil
        if item.root then ApplyClick(item) end
    end
    for macro, item in pairs(activeMacros) do
        if item.root and item._collectionMacro == macro then ApplyClick(item) end
    end
end)
function EXUI:ApplyCollectionItemClick(item, spec)
    if not item or not item.root then return false end
    item._collectionClickSpec = type(spec) == "table" and spec or nil
    return ApplyClick(item)
end
function EXUI:ReleaseCollectionItemClick(item)
    if not item then return end
    pendingItems[item] = nil
    local code = item._collectionCodeButton
    if code then
        code:SetScript("OnClick", nil)
        code:Hide()
        code:SetParent(nil)
    end
    item._collectionCodeButton = nil
    DestroyMacro(item._collectionMacro)
    item._collectionMacro, item._collectionClickSpec = nil, nil
end
