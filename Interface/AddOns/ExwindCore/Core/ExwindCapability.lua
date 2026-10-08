local _, ExwindTools = ...

-- Runtime-only API feature checks. No SavedVariables or secret game values enter this table.
local Capability = { probes = {}, cache = {}, Diagnostics = {} }
ExwindTools.Capability = Capability

local loggedIn = IsLoggedIn and IsLoggedIn() or false
local probeFrame, probeFontString, probeStatusBar, probeTexture
local auraProbeParent, auraProbeContainer, auraProbeButton, auraProbePending

local function hasMethods(object, ...)
    if not object then return false end
    for i = 1, select("#", ...) do
        if type(object[select(i, ...)]) ~= "function" then return false end
    end
    return true
end

local function hasValues(object, ...)
    if not object then return false end
    for i = 1, select("#", ...) do
        if object[select(i, ...)] == nil then return false end
    end
    return true
end

local function regions()
    if not probeFrame then
        probeFrame = CreateFrame("Frame")
        probeFrame:Hide()
        probeFontString = probeFrame:CreateFontString()
        probeStatusBar = CreateFrame("StatusBar", nil, probeFrame)
        probeTexture = probeFrame:CreateTexture()
    end
    return probeFontString, probeStatusBar, probeTexture
end

local function auraContainer()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        return nil, "Blizzard_AuraContainer is not loaded"
    end
    if auraProbeContainer then return auraProbeContainer end
    if InCombatLockdown and InCombatLockdown() then
        auraProbePending = true
        return nil, "AuraContainer template probe deferred in combat"
    end
    if not UIParent then return nil, "UIParent is unavailable" end
    if not auraProbeParent then
        auraProbeParent = CreateFrame("Frame", nil, UIParent)
        auraProbeParent:Hide()
    end
    local container = CreateFrame("AuraContainer", nil, auraProbeParent, "CustomAuraContainerTemplate")
    if not container then return nil, "CustomAuraContainerTemplate is unavailable" end
    container:Hide()
    auraProbeContainer = container
    auraProbePending = nil
    return container
end

local function auraButton()
    local container, reason = auraContainer()
    if not container then return nil, reason end
    if auraProbeButton then return auraProbeButton end
    if InCombatLockdown and InCombatLockdown() then
        auraProbePending = true
        return nil, "AuraButton template probe deferred in combat"
    end
    local button = CreateFrame("AuraButton", nil, container, "CustomAuraButtonTemplate")
    if not button then return nil, "CustomAuraButtonTemplate is unavailable" end
    button:Hide()
    auraProbeButton = button
    auraProbePending = nil
    return button
end

function Capability:Register(name, probe)
    assert(type(name) == "string" and name ~= "" and type(probe) == "function", "invalid capability registration")
    assert(not self.probes[name], "duplicate capability: " .. name)
    self.probes[name] = probe
    if loggedIn then self:RefreshAll() end
end

function Capability:RefreshAll()
    if not loggedIn then return end
    for name, probe in pairs(self.probes) do
        local ok, available, reason = pcall(probe)
        self.cache[name] = ok and available == true or false
        if self.cache[name] then
            self.Diagnostics[name] = nil
        else
            self.Diagnostics[name] = ok and (reason or "required API or enum is unavailable") or tostring(available)
        end
    end
end

function Capability:Has(name)
    return self.cache[name] == true
end

Capability:Register("Duration.Basic", function()
    if not hasMethods(C_DurationUtil, "CreateDuration") then return false end
    local duration = C_DurationUtil.CreateDuration()
    return hasMethods(duration, "HasSecretValues", "GetRemainingDuration", "GetTotalDuration", "SetTimeFromStart")
end)

Capability:Register("Duration.Text", function()
    if not hasMethods(C_DurationUtil, "CreateDurationTextBinding")
        or not hasMethods(C_StringUtil, "CreateSecondsFormatter", "CreateNumericRuleFormatter")
        or not hasValues(Enum and Enum.DurationTextBindingProperty, "RemainingDuration", "RemainingPercent", "ElapsedDuration", "ElapsedPercent", "TotalDuration")
        or not hasValues(Enum and Enum.SecondsFormatterInterval, "Seconds", "Minutes", "Hours", "Days")
        or not hasValues(Enum and Enum.SecondsFormatterAbbreviation, "None", "Truncate", "OneLetter")
        or not hasValues(Enum and Enum.SecondsFormatterRounding, "RoundUp", "Truncate")
        or not hasValues(Enum and Enum.NumericRuleFormatRounding, "Nearest", "Up", "Down") then return false end
    local binding = C_DurationUtil.CreateDurationTextBinding()
    local available = hasMethods(binding, "SetDuration", "SetFontString", "SetEnabled", "SetTextFormat")
    -- The binding has no FontString attached; reset is only needed after use.
    return available
end)

Capability:Register("Duration.TextColor", function()
    if not hasMethods(C_DurationUtil, "CreateDurationTextBinding")
        or not hasMethods(C_CurveUtil, "CreateColorCurve")
        or not hasValues(Enum and Enum.DurationTextBindingProperty, "RemainingDuration", "RemainingPercent", "ElapsedDuration", "ElapsedPercent", "TotalDuration")
        or not hasValues(Enum and Enum.LuaCurveType, "Step") then return false end
    local binding = C_DurationUtil.CreateDurationTextBinding()
    return hasMethods(binding, "SetTextColorCurve", "ClearTextColorCurve")
end)

Capability:Register("Duration.TextInterval", function()
    if not hasMethods(C_DurationUtil, "CreateDurationTextBinding") then return false end
    local binding = C_DurationUtil.CreateDurationTextBinding()
    return hasMethods(binding, "SetUpdateInterval")
end)

Capability:Register("Aura.Container", function()
    local container, reason = auraContainer()
    if not container then return false, reason end
    return hasMethods(container, "SetUnit", "SetEnabled", "AddAuraGroup", "AddAuraSlot", "SetAuraProcessingPolicy")
        and hasValues(CustomAuraContainerAuraProcessingPolicy, "None", "ProcessAura")
end)

Capability:Register("Aura.GroupGate", function()
    local container, reason = auraContainer()
    if not container then return false, reason end
    return hasMethods(container, "SetAuraGroupMaxFrameCount")
end)

Capability:Register("Aura.Flow", function()
    local container, reason = auraContainer()
    if not container then return false, reason end
    return hasMethods(container, "SetFlowLayoutAxis", "SetFlowLayoutAnchorPoint", "SetFlowLayoutGrowthDirection", "SetFlowLayoutPadding", "SetFlowLayoutMaximumLineSize")
        and hasValues(AnchorUtil and AnchorUtil.FlowLayoutAxis, "Horizontal", "Vertical")
        and hasValues(AnchorUtil and AnchorUtil.FlowDirection, "Left", "Right", "Up", "Down")
end)

Capability:Register("Aura.Duration", function()
    local button, reason = auraButton()
    if not button then return false, reason end
    return hasMethods(button, "SetDurationText", "ClearDurationText", "SetDurationBar", "ClearDurationBar", "SetDurationCooldown", "ClearDurationCooldown")
end)

Capability:Register("Aura.Application", function()
    local button, reason = auraButton()
    if not button then return false, reason end
    return hasMethods(button, "SetApplicationBar", "ClearApplicationBar")
        and hasValues(Enum and Enum.StatusBarInterpolation, "Immediate", "ExponentialEaseOut")
end)

Capability:Register("Aura.Pandemic", function()
    local button, reason = auraButton()
    if not button then return false, reason end
    return hasMethods(button, "AddPandemicRegion", "RemovePandemicRegion")
end)

Capability:Register("Aura.Dispel", function()
    local button, reason = auraButton()
    if not button then return false, reason end
    return hasMethods(button, "AddDispelTypeTexture", "RemoveDispelTypeTexture")
        and hasMethods(C_UnitAuras, "GetAuraDispelTypeColor")
end)

Capability:Register("Aura.Sound", function()
    return hasMethods(C_UnitAuras, "AddAuraSound", "RemoveAuraSound")
        and hasValues(Enum and Enum.UnitAuraSoundTrigger, "Added", "ApplicationsIncreased", "Removed")
end)

Capability:Register("Font.Gradient", function()
    local fontString = regions()
    return hasMethods(fontString, "SetAlphaGradient", "ClearAlphaGradient")
end)

Capability:Register("StatusBar.Timer", function()
    local _, statusBar = regions()
    return hasMethods(statusBar, "SetTimerDuration")
        and hasValues(Enum and Enum.StatusBarTimerDirection, "ElapsedTime", "RemainingTime")
        and hasValues(Enum and Enum.StatusBarInterpolation, "Immediate", "ExponentialEaseOut")
        and hasMethods(C_DurationUtil, "CreateDuration")
end)

Capability:Register("StatusBar.Radial", function()
    local _, statusBar, texture = regions()
    return hasMethods(statusBar, "SetRenderMode")
        and hasValues(Enum and Enum.StatusBarRenderMode, "Radial")
        and hasMethods(texture, "SetRadialProgressBarReverse", "SetRadialProgressBarStartOffset", "SetRadialProgressBarFeather")
end)

Capability:Register("Spell.CooldownFlags", function()
    return hasMethods(C_Spell, "GetSpellCooldown")
end)

Capability:Register("Spell.CooldownDuration", function()
    return hasMethods(C_Spell, "GetSpellCooldownDuration")
end)

Capability:Register("Spell.ChargeDisplay", function()
    return hasMethods(C_Spell, "GetSpellChargeDuration", "GetSpellCharges")
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        loggedIn = true
        watcher:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_REGEN_ENABLED" then
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if not auraProbePending then return end
    end
    if loggedIn then Capability:RefreshAll() end
    if auraProbePending then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
end)

if loggedIn then Capability:RefreshAll() end
if auraProbePending then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
