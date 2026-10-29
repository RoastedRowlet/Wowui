-- Two finite visual presets for ordinary Collection items. Layout and business
-- state stay with their owners; native AnimationGroup performs interpolation.
local Core = _G.ExwindTools
local UI = Core and Core.UI
if not UI then return end

local function RestoreBase(item)
    local effects = item.visualEffects or {}
    item.root:SetAlpha(effects.alpha and effects.alpha.value or 1)
    item.root:SetScale((item.presentationScale or 1) * (effects.scale and effects.scale.value or 1))
end

local function Stop(collection, itemID)
    local item = collection.itemsByID and collection.itemsByID[itemID]
    if not item or not item.root then return false end
    local root, state = item.root, item.visualAnimation
    if state then
        item.visualAnimation = nil
        root._exCollectionVisualAnimation = nil
        root._exCollectionVisualRetiring = nil
        root:SetScript("OnHide", state.previousOnHide)
        state.group:SetScript("OnFinished", nil)
        state.group:Stop()
        RestoreBase(item)
    end
    return state ~= nil
end

local function Preset(root, effect)
    local presets = root._exCollectionVisualPresets
    if not presets then presets = {}; root._exCollectionVisualPresets = presets end
    if presets[effect] then return presets[effect] end
    local preset = { group = root:CreateAnimationGroup(), scales = {} }
    preset.group:SetLooping("NONE")
    preset.group:SetToFinalAlpha(false)
    local count = effect == "bounceIn" and 3 or 2
    for order = 1, count do
        local scale = preset.group:CreateAnimation("Scale")
        scale:SetOrder(order)
        scale:SetOrigin("CENTER", 0, 0)
        scale:SetSmoothing(order == 1 and "OUT" or "IN_OUT")
        preset.scales[order] = scale
    end
    if effect == "bounceOut" then
        preset.fade = preset.group:CreateAnimation("Alpha")
        preset.fade:SetOrder(2)
        preset.fade:SetSmoothing("IN")
    end
    presets[effect] = preset
    return preset
end

local function Configure(preset, effect, speed, amount, alpha)
    local scales = preset.scales
    local overshoot = 1 + amount * .4
    local small = 1 - amount
    if effect == "bounceIn" then
        local settle = 1 - amount * .1
        scales[1]:SetScaleFrom(small, small)
        scales[1]:SetScaleTo(overshoot, overshoot)
        scales[1]:SetDuration(.18 / speed)
        scales[2]:SetScaleFrom(1, 1)
        scales[2]:SetScaleTo(settle / overshoot, settle / overshoot)
        scales[2]:SetDuration(.09 / speed)
        scales[3]:SetScaleFrom(1, 1)
        scales[3]:SetScaleTo(1 / settle, 1 / settle)
        scales[3]:SetDuration(.08 / speed)
    else
        scales[1]:SetScaleFrom(1, 1)
        scales[1]:SetScaleTo(overshoot, overshoot)
        scales[1]:SetDuration(.09 / speed)
        scales[2]:SetScaleFrom(1, 1)
        scales[2]:SetScaleTo(small / overshoot, small / overshoot)
        scales[2]:SetDuration(.18 / speed)
        preset.fade:SetFromAlpha(alpha)
        preset.fade:SetToAlpha(0)
        preset.fade:SetDuration(.18 / speed)
    end
end

local function Play(collection, itemID, phase, config, onFinished)
    if phase ~= "enter" and phase ~= "exit" then error("visual animation phase must be enter or exit", 2) end
    if onFinished ~= nil and type(onFinished) ~= "function" then error("visual animation completion must be a function", 2) end
    local item = collection.itemsByID and collection.itemsByID[itemID]
    if collection.released or not item or not item.root then return false end
    config = config or {}
    local effect = config.effect or "none"
    if effect ~= "none" and effect ~= (phase == "enter" and "bounceIn" or "bounceOut") then
        error("visual animation effect does not match phase", 2)
    end
    if effect ~= "none" and phase == "exit" and item.root._exCollectionVisualRetiring then return true end
    Stop(collection, itemID)
    if effect == "none" or not item.root:IsShown() then return false end
    -- The existing Text alpha sequence and this preset share ItemRoot Alpha.
    if item.alphaAnimation then
        item.alphaAnimation:SetScript("OnFinished", nil)
        item.alphaAnimation:Stop()
        item.alphaAnimation = nil
    end
    local speed = math.max(.25, math.min(3, tonumber(config.speed) or 1))
    local amount = math.max(.05, math.min(.5, tonumber(config.amount) or .25))
    local root = item.root
    local preset = Preset(root, effect)
    local effects = item.visualEffects or {}
    Configure(preset, effect, speed, amount, effects.alpha and effects.alpha.value or 1)
    local state = { group = preset.group, previousOnHide = root:GetScript("OnHide") }
    item.visualAnimation = state
    root._exCollectionVisualAnimation = state
    root._exCollectionVisualRetiring = phase == "exit" or nil
    if phase == "exit" then
        UI:ReleaseCollectionItemClick(item)
        -- Freeze the last declared semantic position before active items are
        -- relaid out. Never read screen geometry or Secret content anchors.
        local layout = collection.layout
        local offset = layout:GetSemanticItemOffsets()[item]
        if offset then
            local bounds = layout:GetSemanticBounds()
            local centered = layout.style.contentCenter == true and layout.style.mode ~= "ABSOLUTE"
            root:ClearAllPoints()
            root:SetPoint("CENTER", collection.host, "CENTER",
                offset.x - (centered and bounds.anchorOffsetX or 0),
                offset.y - (centered and bounds.anchorOffsetY or 0))
        end
    end
    root:SetScript("OnHide", function(hidden)
        local previous = state.previousOnHide
        Stop(collection, itemID)
        if previous then previous(hidden) end
    end)
    preset.group:SetScript("OnFinished", function()
        if not collection.itemsByID or collection.itemsByID[itemID] ~= item or item.visualAnimation ~= state then return end
        item.visualAnimation = nil
        root._exCollectionVisualAnimation = nil
        root._exCollectionVisualRetiring = nil
        root:SetScript("OnHide", state.previousOnHide)
        preset.group:SetScript("OnFinished", nil)
        RestoreBase(item)
        if phase == "exit" then collection:ReleaseItem(itemID) end
        if onFinished then onFinished() end
    end)
    preset.group:Play()
    return true
end

local function IsRetiring(collection, itemID)
    local item = collection.itemsByID and collection.itemsByID[itemID]
    return item ~= nil and item.root ~= nil and item.root._exCollectionVisualRetiring == true
end

local function HasRetiring(collection)
    for _, item in pairs(collection.itemsByID or {}) do
        if item.root and item.root._exCollectionVisualRetiring then return true end
    end
    return false
end

function UI:InitializeCollectionVisualAnimations(collection)
    -- Play enter after SetItems/host show. Play exit before omitting the item
    -- from SetItems; completion releases it, then calls the owner notification.
    -- false means no animation was started: the owner hides/releases normally.
    -- Keep the host shown while HasRetiringVisualItems is true. Forced teardown
    -- uses ReleaseItem/Release and never runs a canceled completion callback.
    collection.PlayItemVisualAnimation = Play
    collection.StopItemVisualAnimation = Stop
    collection.IsItemVisualRetiring = IsRetiring
    collection.HasRetiringVisualItems = HasRetiring
end
