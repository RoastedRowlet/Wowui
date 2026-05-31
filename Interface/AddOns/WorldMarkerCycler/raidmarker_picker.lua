-- ======================================================
-- WorldMarkerCycler - Raid Marker Picker
-- File: raidmarker_picker.lua
-- Persistent, lockable marker toolbar.
-- Click a marker to place it at your cursor. Right-click to toggle lock.
-- Drag to reposition when unlocked. /wmcrshow /wmcrhide /wmcrtoggle /wmcrlock
-- ======================================================

local ADDON_NAME = "WorldMarkerCycler"

-- Locale table for user-facing strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["WorldMarkerCycler: marker bar locked."] = "WorldMarkerCycler : barre de marqueurs verrouillée."
    L["WorldMarkerCycler: marker bar unlocked. Drag to move, right-click to lock."] = "WorldMarkerCycler : barre déverrouillée. Glissez pour déplacer, clic-droit pour verrouiller."
    L["WorldMarkerCycler: marker bar shown."] = "WorldMarkerCycler : barre de marqueurs affichée."
    L["WorldMarkerCycler: marker bar hidden."] = "WorldMarkerCycler : barre de marqueurs masquée."
end

-- =========================
-- SavedVariables helpers
-- =========================
local function SV()
    return _G.WMC_RaidPickerSaved
end

local function EnsureSV()
    if not SV() then
        _G.WMC_RaidPickerSaved = {}
    end
end

local function InitSaved()
    EnsureSV()
    local sv = SV()
    if sv.posAnchor == nil then sv.posAnchor = "CENTER" end
    if sv.posX    == nil then sv.posX    = 0   end
    if sv.posY    == nil then sv.posY    = 200 end
    if sv.locked      == nil then sv.locked      = true  end
    if sv.shown        == nil then sv.shown        = false end
    if sv.openKey      == nil then sv.openKey      = "" end
    if sv.openModifier == nil then sv.openModifier = "" end
end

-- =========================
-- Picker UI
-- =========================
local picker = CreateFrame("Frame", "WMC_RaidMarkerPickerFrame", UIParent, "BackdropTemplate,SecureHandlerStateTemplate")
picker:SetSize(360, 44)
picker:SetFrameStrata("MEDIUM")
picker:SetMovable(true)
picker:EnableMouse(true)
picker:SetClampedToScreen(true)
picker:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
picker:SetBackdropColor(0, 0, 0, 0.9)
picker:SetBackdropBorderColor(0.9, 0.82, 0.4, 1)
picker:Hide()
-- Secure visibility: SetAttribute("state-shown", "0"/"1") works from addon code in combat.
-- The handler runs in secure context, allowing Show/Hide on this protected frame.
picker:SetAttribute("state-shown", "0")
picker:SetAttribute("_onstate-shown", [[
    if newstate == "1" then self:Show() else self:Hide() end
]])

-- =========================
-- Lock / position helpers
-- =========================
local function IsLocked()
    local sv = SV()
    return (not sv) or (sv.locked ~= false)
end

local function UpdateLockedVisuals()
    if IsLocked() then
        picker:SetBackdropBorderColor(0.9, 0.82, 0.4, 1)   -- gold = locked
    else
        picker:SetBackdropBorderColor(0.3, 0.8, 1.0, 1)    -- blue = unlocked / draggable
    end
end

local function SavePosition()
    EnsureSV()
    local sv = SV()
    local point, _, _, x, y = picker:GetPoint(1)
    sv.posAnchor = point or "CENTER"
    sv.posX      = x or 0
    sv.posY      = y or 0
end

local function RestorePosition()
    local sv = SV()
    picker:ClearAllPoints()
    if sv and sv.posAnchor then
        picker:SetPoint(sv.posAnchor, UIParent, sv.posAnchor, sv.posX or 0, sv.posY or 0)
    else
        picker:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

local function SetLocked(locked)
    EnsureSV()
    SV().locked = locked
    UpdateLockedVisuals()
end

local function ToggleLock()
    SetLocked(not IsLocked())
    if IsLocked() then
        print(L["WorldMarkerCycler: marker bar locked."])
    else
        print(L["WorldMarkerCycler: marker bar unlocked. Drag to move, right-click to lock."])
    end
end

-- Left-drag to move when unlocked; right-click anywhere to toggle lock
picker:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and not IsLocked() then
        self:StartMoving()
    elseif button == "RightButton" then
        ToggleLock()
    end
end)
picker:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        self:StopMovingOrSizing()
        SavePosition()
    end
end)

-- Tooltip on the frame background
picker:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("World Marker Bar", 1, 1, 0)
    if IsLocked() then
        GameTooltip:AddLine("Right-click to unlock and move", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("Drag to reposition", 0.3, 0.8, 1)
        GameTooltip:AddLine("Right-click to lock", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end)
picker:SetScript("OnLeave", function(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end)

local function GetDisplayMarkerForWorldMarkerID(worldMarkerID)
    ---@diagnostic disable-next-line: undefined-field
    local worldOrder = rawget(_G, "WORLD_RAID_MARKER_ORDER")
    if type(worldOrder) == "table" then
        for displayMarker, mappedWorldMarkerID in pairs(worldOrder) do
            if mappedWorldMarkerID == worldMarkerID then
                return displayMarker
            end
        end
    end

    local fallback = {
        [1] = 3,
        [2] = 5,
        [3] = 6,
        [4] = 2,
        [5] = 8,
        [6] = 7,
        [7] = 4,
        [8] = 1,
    }
    return fallback[worldMarkerID] or worldMarkerID
end

local displayMarkerToRaidTargetTexture = {
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}

local function CreateMarkerButton(id, index)
    local btn = CreateFrame("Button", "WMC_RaidMarkerPickerButton" .. id, picker, "SecureActionButtonTemplate")
    btn:SetSize(32, 32)
    btn:SetPoint("LEFT", picker, "LEFT", 8 + ((index - 1) * 37), 0)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    -- Left-click: place this world marker at cursor's world position
    btn:SetAttribute("type", "worldmarker")
    btn:SetAttribute("action", "set")
    btn:SetAttribute("marker", id)
    -- Right-click: clear only this world marker
    btn:SetAttribute("type2", "worldmarker")
    btn:SetAttribute("action2", "clear")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    local displayMarker = GetDisplayMarkerForWorldMarkerID(id)
    local usedAtlas = icon:SetAtlas("GM-raidMarker" .. displayMarker, true)
    if not usedAtlas then
        icon:SetTexture(displayMarkerToRaidTargetTexture[displayMarker])
    end
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)

    return btn
end

for i = 1, 8 do
    CreateMarkerButton(i, i)
end

local clearAllBtn = CreateFrame("Button", "WMC_RaidMarkerPickerClearAllButton", picker, "SecureActionButtonTemplate")
clearAllBtn:SetSize(50, 24)
clearAllBtn:SetPoint("LEFT", picker, "LEFT", 304, 0)
clearAllBtn:RegisterForClicks("AnyDown", "AnyUp")
-- worldmarker + action=clear + no marker attribute → ClearRaidMarker(nil) → clears all
clearAllBtn:SetAttribute("type", "worldmarker")
clearAllBtn:SetAttribute("action", "clear")

clearAllBtn.bg = clearAllBtn:CreateTexture(nil, "BACKGROUND")
clearAllBtn.bg:SetAllPoints()
clearAllBtn.bg:SetColorTexture(0.2, 0.05, 0.05, 0.9)

clearAllBtn.text = clearAllBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
clearAllBtn.text:SetPoint("CENTER")
clearAllBtn.text:SetText("CLEAR")

local clearHL = clearAllBtn:CreateTexture(nil, "HIGHLIGHT")
clearHL:SetAllPoints()
clearHL:SetColorTexture(1, 1, 1, 0.15)

picker:SetScript("OnHide", function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end)

-- =========================
-- Keybind: toggle bar show/hide
-- =========================
local pickerBindingsFrame = CreateFrame("Frame")

-- Hidden button that receives the synthetic click from SetOverrideBindingClick.
-- SecureHandlerClickTemplate lets _onclick run in secure context so SetAttribute
-- works during combat lockdown. AnyUp matches SetOverrideBindingClick's key-UP delivery.
local pickerToggleBtn = CreateFrame("Button", "WMC_RaidPickerToggleButton", UIParent, "SecureHandlerClickTemplate")
pickerToggleBtn:RegisterForClicks("AnyUp")
pickerToggleBtn:SetFrameRef("picker", picker)
pickerToggleBtn:SetAttribute("_onclick", [[
    local p = self:GetFrameRef("picker")
    local newState = (p:GetAttribute("state-shown") == "1") and "0" or "1"
    p:SetAttribute("state-shown", newState)
]])
-- PostClick runs in normal Lua (after the secure handler), so we can save the new shown state.
-- Without this, pressing the keybind to hide the bar doesn't update sv.shown, so it re-appears on reload.
pickerToggleBtn:SetScript("PostClick", function()
    EnsureSV()
    SV().shown = picker:IsShown()
end)

local function UpdatePickerBindings()
    ClearOverrideBindings(pickerBindingsFrame)
    local sv = SV()
    if sv and sv.openKey and sv.openKey ~= "" then
        local fullKey = (sv.openModifier or "") .. sv.openKey
        SetOverrideBindingClick(pickerBindingsFrame, true, fullKey, "WMC_RaidPickerToggleButton")
    end
end

-- =========================
-- Public API
-- =========================
WorldMarkerCyclerRaidPickerAPI = WorldMarkerCyclerRaidPickerAPI or {}

function WorldMarkerCyclerRaidPickerAPI.Show()
    if InCombatLockdown() then return end
    EnsureSV()
    SV().shown = true
    RestorePosition()
    picker:SetAttribute("state-shown", "1")
end

function WorldMarkerCyclerRaidPickerAPI.Hide()
    if InCombatLockdown() then return end
    EnsureSV()
    SV().shown = false
    picker:SetAttribute("state-shown", "0")
end

function WorldMarkerCyclerRaidPickerAPI.Toggle()
    if InCombatLockdown() then return end
    if picker:IsShown() then
        WorldMarkerCyclerRaidPickerAPI.Hide()
    else
        WorldMarkerCyclerRaidPickerAPI.Show()
    end
end

function WorldMarkerCyclerRaidPickerAPI.SetLocked(locked)
    SetLocked(locked)
end

function WorldMarkerCyclerRaidPickerAPI.IsLocked()
    return IsLocked()
end

function WorldMarkerCyclerRaidPickerAPI.ToggleLock()
    ToggleLock()
end

function WorldMarkerCyclerRaidPickerAPI.SetOpenKey(mod, key)
    EnsureSV()
    local sv = SV()
    sv.openModifier = mod or ""
    sv.openKey      = key or ""
    UpdatePickerBindings()
end

function WorldMarkerCyclerRaidPickerAPI.UpdateBindings()
    UpdatePickerBindings()
end

-- =========================
-- Slash commands
-- =========================
SLASH_WMCRSHOW1 = "/wmcrshow"
SlashCmdList["WMCRSHOW"] = function()
    WorldMarkerCyclerRaidPickerAPI.Show()
    print(L["WorldMarkerCycler: marker bar shown."])
end

SLASH_WMCRHIDE1 = "/wmcrhide"
SlashCmdList["WMCRHIDE"] = function()
    WorldMarkerCyclerRaidPickerAPI.Hide()
    print(L["WorldMarkerCycler: marker bar hidden."])
end

SLASH_WMCRTOGGLE1 = "/wmcrtoggle"
SlashCmdList["WMCRTOGGLE"] = function()
    WorldMarkerCyclerRaidPickerAPI.Toggle()
end

SLASH_WMCRLOCK1 = "/wmcrlock"
SlashCmdList["WMCRLOCK"] = function()
    ToggleLock()
end

-- Sync the shown SavedVariable after combat ends, since the secure toggle button
-- can flip visibility in combat without going through the Lua API.
local postCombatSyncFrame = CreateFrame("Frame")
postCombatSyncFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
postCombatSyncFrame:SetScript("OnEvent", function()
    EnsureSV()
    SV().shown = picker:IsShown()
end)

-- =========================
-- Event loader
-- =========================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        InitSaved()
    elseif event == "PLAYER_LOGIN" then
        RestorePosition()
        UpdateLockedVisuals()
        UpdatePickerBindings()
        local sv = SV()
        if not sv or sv.shown ~= false then
            picker:SetAttribute("state-shown", "1")
        end
    end
end)
