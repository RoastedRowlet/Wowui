-- ======================================================
-- WorldMarkerCycler - Raid Marker Picker
-- File: raidmarker_picker.lua
-- Opens a horizontal marker picker and places world marker at cursor.
-- ======================================================

local ADDON_NAME = "WorldMarkerCycler"

-- Locale table for user-facing strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["WorldMarkerCycler: raid picker keybind cleared."] = "WorldMarkerCycler : raccourci du sélecteur de marqueurs effacé."
    L["Usage: /wmcrbind [key]"] = "Utilisation : /wmcrbind [touche]"
    L["Press the key you want to bind for raid marker picker. Press ESC to cancel."] = "Appuyez sur la touche à assigner pour le sélecteur de marqueurs. ÉCHAP pour annuler."
    L["WorldMarkerCycler: raid picker binding cancelled."] = "WorldMarkerCycler : assignation du sélecteur annulée."
    L["WorldMarkerCycler: raid picker bound to "] = "WorldMarkerCycler : sélecteur assigné à "
    L["WorldMarkerCycler: raid picker requires group leader or assistant."] = "WorldMarkerCycler : le sélecteur nécessite d'être chef de groupe/raid ou assistant."
    L["WorldMarkerCycler: cannot open raid picker during combat."] = "WorldMarkerCycler : impossible d'ouvrir le sélecteur en combat."
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

    -- No default keybind; user can bind via /wmcrbind or options UI integrations.
    if sv.openKey == nil then sv.openKey = "" end
    if sv.openModifier == nil then sv.openModifier = "" end
end

-- =========================
-- Picker UI
-- =========================
local picker = CreateFrame("Frame", "WMC_RaidMarkerPickerFrame", UIParent, "BackdropTemplate")
picker:SetSize(360, 40)
picker:SetFrameStrata("TOOLTIP")
picker:SetClampedToScreen(true)
picker:EnableMouse(true)
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

local function PositionPicker()
    picker:ClearAllPoints()

    local scale = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x = x / scale
    y = y / scale

    -- Anchor by cursor, centered horizontally, and clamp to screen bounds.
    local w, h = picker:GetWidth(), picker:GetHeight()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local px = x - (w * 0.5)
    local py = y + 20

    if px < 0 then px = 0 end
    if py < 0 then py = 0 end
    if px + w > screenW then px = screenW - w end
    if py + h > screenH then py = screenH - h end

    picker:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", px, py)
end

local function CanUseRaidMarkerPicker()
    if not IsInGroup() then
        return false
    end
    if UnitIsGroupLeader("player") then
        return true
    end
    if IsInRaid() and UnitIsGroupAssistant("player") then
        return true
    end
    return false
end

local function TogglePicker()
    if InCombatLockdown() then
        print(L["WorldMarkerCycler: cannot open raid picker during combat."])
        return
    end

    if not CanUseRaidMarkerPicker() then
        print(L["WorldMarkerCycler: raid picker requires group leader or assistant."])
        return
    end

    if picker:IsShown() then
        picker:Hide()
        return
    end

    PositionPicker()
    picker:Show()
end

local function CreateMarkerButton(id, index)
    local btn = CreateFrame("Button", "WMC_RaidMarkerPickerButton" .. id, picker, "SecureActionButtonTemplate")
    btn:SetSize(32, 32)
    btn:SetPoint("LEFT", picker, "LEFT", 8 + ((index - 1) * 37), 0)
    btn:RegisterForClicks("AnyDown")
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", "/wm [@cursor] " .. id)
    btn:SetAttribute("type2", "macro")
    btn:SetAttribute("macrotext2", "/cwm " .. id)

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

    btn:SetScript("PostClick", function()
        if not InCombatLockdown() then
            picker:Hide()
        end
    end)

    return btn
end

for i = 1, 8 do
    CreateMarkerButton(i, i)
end

local clearAllBtn = CreateFrame("Button", "WMC_RaidMarkerPickerClearAllButton", picker, "SecureActionButtonTemplate")
clearAllBtn:SetSize(50, 24)
clearAllBtn:SetPoint("LEFT", picker, "LEFT", 304, 0)
clearAllBtn:RegisterForClicks("AnyDown")
clearAllBtn:SetAttribute("type", "macro")
clearAllBtn:SetAttribute("macrotext", "/cwm 9")

clearAllBtn.bg = clearAllBtn:CreateTexture(nil, "BACKGROUND")
clearAllBtn.bg:SetAllPoints()
clearAllBtn.bg:SetColorTexture(0.2, 0.05, 0.05, 0.9)

clearAllBtn.text = clearAllBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
clearAllBtn.text:SetPoint("CENTER")
clearAllBtn.text:SetText("CLEAR")

local clearHL = clearAllBtn:CreateTexture(nil, "HIGHLIGHT")
clearHL:SetAllPoints()
clearHL:SetColorTexture(1, 1, 1, 0.15)

clearAllBtn:SetScript("PostClick", function()
    if not InCombatLockdown() then
        picker:Hide()
    end
end)

picker:SetScript("OnHide", function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end)

-- =========================
-- Key Bindings
-- =========================
local openBtn = CreateFrame("Button", "WMC_RaidMarkerPickerToggleButton", UIParent)
openBtn:RegisterForClicks("AnyDown")
openBtn:SetScript("OnClick", function()
    TogglePicker()
end)

local bindingsFrame = CreateFrame("Frame", "WMC_RaidMarkerPickerBindings")

local function UpdateBindings()
    ClearOverrideBindings(bindingsFrame)

    local sv = SV()
    if not sv then return end

    local openFullKey = (sv.openModifier or "") .. (sv.openKey or "")
    if openFullKey ~= "" then
        SetOverrideBindingClick(bindingsFrame, true, openFullKey, openBtn:GetName())
    end
end

local function ParseBindingString(raw)
    local text = (raw or ""):upper()
    local mod = ""
    local key = text

    if text:find("CTRL%-") or text:find("CTR%-%") then
        mod = mod .. "CTRL-"
        key = key:gsub("CTRL%-", "")
        key = key:gsub("CTR%-", "")
    end
    if text:find("ALT%-") then
        mod = mod .. "ALT-"
        key = key:gsub("ALT%-", "")
    end
    if text:find("SHIFT%-") or text:find("MAJ%-") then
        mod = mod .. "SHIFT-"
        key = key:gsub("SHIFT%-", "")
        key = key:gsub("MAJ%-", "")
    end

    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    return mod, key
end

-- =========================
-- Public API
-- =========================
WorldMarkerCyclerRaidPickerAPI = WorldMarkerCyclerRaidPickerAPI or {}

function WorldMarkerCyclerRaidPickerAPI.SetOpenKey(mod, key)
    EnsureSV()
    SV().openModifier = mod or ""
    SV().openKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerRaidPickerAPI.GetOpenKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.openModifier or "") .. (sv.openKey or "")
end

function WorldMarkerCyclerRaidPickerAPI.TogglePicker()
    TogglePicker()
end

function WorldMarkerCyclerRaidPickerAPI.UpdateBindings()
    UpdateBindings()
end

-- =========================
-- Slash commands
-- =========================
SLASH_WMCRBIND1 = "/wmcrbind"
SlashCmdList["WMCRBIND"] = function(msg)
    EnsureSV()

    local keyarg = (msg or ""):match("^%s*(.-)%s*$")
    if keyarg and keyarg ~= "" then
        local mod, key = ParseBindingString(keyarg)
        local rawKey = (key or ""):upper()
        WorldMarkerCyclerRaidPickerAPI.SetOpenKey(mod, rawKey)
        local displayKey = GetBindingText(rawKey, "KEY_", true) or rawKey
        print(L["WorldMarkerCycler: raid picker bound to "] .. mod .. displayKey)
        return
    end

    print(L["Press the key you want to bind for raid marker picker. Press ESC to cancel."])
    local capture = CreateFrame("Frame", nil, UIParent)
    capture:EnableKeyboard(true)
    capture:SetPropagateKeyboardInput(true)
    capture:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            print(L["WorldMarkerCycler: raid picker binding cancelled."])
            self:Hide()
            self:SetScript("OnKeyDown", nil)
            return
        end

        local mod = ""
        if IsControlKeyDown() then mod = mod .. "CTRL-" end
        if IsAltKeyDown() then mod = mod .. "ALT-" end
        if IsShiftKeyDown() then mod = mod .. "SHIFT-" end

        local rawKey = (key or ""):upper()
        WorldMarkerCyclerRaidPickerAPI.SetOpenKey(mod, rawKey)
        local displayKey = GetBindingText(rawKey, "KEY_", true) or rawKey
        print(L["WorldMarkerCycler: raid picker bound to "] .. mod .. displayKey)

        self:Hide()
        self:SetScript("OnKeyDown", nil)
    end)
    capture:SetScript("OnHide", function(self)
        self:SetScript("OnKeyDown", nil)
    end)
    capture:Show()
end

SLASH_WMCRCLEAR1 = "/wmcrclear"
SlashCmdList["WMCRCLEAR"] = function()
    EnsureSV()
    local sv = SV()
    sv.openKey = ""
    sv.openModifier = ""
    UpdateBindings()
    print(L["WorldMarkerCycler: raid picker keybind cleared."])
end

SLASH_WMCRSHOW1 = "/wmcrshow"
SlashCmdList["WMCRSHOW"] = function()
    TogglePicker()
end

-- =========================
-- Event loader
-- =========================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        InitSaved()
        UpdateBindings()
    elseif event == "PLAYER_LOGIN" then
        UpdateBindings()
    end
end)
