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
