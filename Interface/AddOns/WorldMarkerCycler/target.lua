-- ======================================================
-- WorldMarkerCycler - Target Marker Cycler
-- File: target.lua
-- Uses Blizzard secure /tm command (NO SetRaidTarget)
-- ======================================================


local ADDON_NAME = "WorldMarkerCycler"

-- Locale table for user-facing strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["WorldMarkerCycler: target marker keybinds cleared."] = "WorldMarkerCycler : raccourcis de cible effacés."
    L["Usage: /wmctadd <cycle|clear> <modifiers> <key>"] = "Utilisation : /wmctadd <cycle|clear> <modificateurs> <touche>"
    L["Example: /wmctadd cycle CTRL- SHIFT- F1"] = "Exemple : /wmctadd cycle CTRL- SHIFT- F1"
    L["WorldMarkerCycler: set "] = "WorldMarkerCycler : raccourci "
    L[" keybind to "] = " assigné à "
end

-- =========================
-- SavedVariables helpers
-- =========================
local function SV()
    return _G.WMC_TargetSaved
end

local function EnsureSV()
    if not SV() then
        _G.WMC_TargetSaved = {}
    end
end

local function InitSaved()
    EnsureSV()
    local sv = SV()

    -- No default keybinds; user must set in options menu
    if sv.placeKey == nil then sv.placeKey = "" end
    if sv.placeModifier == nil then sv.placeModifier = "" end
    if sv.clearKey == nil then sv.clearKey = "" end
    if sv.clearModifier == nil then sv.clearModifier = "" end

    -- Order:
    -- Skull → Cross → Square → Moon → Triangle → Diamond → Circle → Star
    if sv.orderList == nil then sv.orderList = { 8, 7, 6, 5, 4, 3, 2, 1 } end
end

-- =========================
-- Secure Buttons
-- =========================

-- Cycle target marker
local cycleBtn = CreateFrame(
    "Button",
    "WMC_TargetMarkerCycleButton",
    UIParent,
    "SecureActionButtonTemplate"
)
cycleBtn:SetAttribute("type", "macro")
cycleBtn:RegisterForClicks("AnyDown")

-- Clear target marker
local clearBtn = CreateFrame(
    "Button",
    "WMC_TargetMarkerClearButton",
    UIParent,
    "SecureActionButtonTemplate"
)
clearBtn:SetAttribute("type", "macro")
clearBtn:SetAttribute("macrotext", "/tm 0")
clearBtn:RegisterForClicks("AnyDown")

-- =========================
-- Secure Order Table
-- =========================
local function BuildOrderTable()
    local sv = SV()
    local body = "i=0; order=newtable() "

    if sv and sv.orderList then
        for _, id in ipairs(sv.orderList) do
            body = body .. ("tinsert(order,%d) "):format(id)
        end
    end

    SecureHandlerExecute(cycleBtn, body)
end

-- =========================
-- Secure Click Handler
-- =========================
SecureHandlerWrapScript(cycleBtn, "PreClick", cycleBtn, [=[
    if not down or not order or #order == 0 then return end
    i = (i % #order) + 1
    local marker = order[i] or 1
    self:SetAttribute(
        "macrotext",
        "/tm " .. marker
    )
]=])

-- =========================
-- Key Bindings
-- =========================
local bindingsFrame = CreateFrame("Frame", "WMC_TargetMarkerBindings")

local function UpdateBindings()
    ClearOverrideBindings(bindingsFrame)

    local sv = SV()
    if not sv then return end

    local cycleKey = (sv.placeModifier or "") .. (sv.placeKey or "")
    local clearKey = (sv.clearModifier or "") .. (sv.clearKey or "")

    if cycleKey ~= "" then
        SetOverrideBindingClick(
            bindingsFrame,
            true,
            cycleKey,
            cycleBtn:GetName()
        )
    end

    if clearKey ~= "" then
        SetOverrideBindingClick(
            bindingsFrame,
            true,
            clearKey,
            clearBtn:GetName()
        )
    end
end

-- =========================
-- Event Loader
-- =========================
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

loader:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        InitSaved()
        BuildOrderTable()
        UpdateBindings()
    elseif event == "PLAYER_LOGIN" then
        UpdateBindings()
    end
end)

-- =========================
-- Public API
-- =========================
WorldMarkerCyclerTargetAPI = WorldMarkerCyclerTargetAPI or {}

function WorldMarkerCyclerTargetAPI.SetPlaceKey(mod, key)
    EnsureSV()
    SV().placeModifier = mod or ""
    SV().placeKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerTargetAPI.SetClearKey(mod, key)
    EnsureSV()
    SV().clearModifier = mod or ""
    SV().clearKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerTargetAPI.SetOrder(list)
    EnsureSV()
    if type(list) == "table" then
        SV().orderList = list
        BuildOrderTable()
    end
end

function WorldMarkerCyclerTargetAPI.GetPlaceKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.placeModifier or "") .. (sv.placeKey or "")
end

function WorldMarkerCyclerTargetAPI.GetClearKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.clearModifier or "") .. (sv.clearKey or "")
end


-- /wmctclear: Clear all keybinds for target marker cycler

SLASH_WMCTARGETCLEAR1 = "/wmctclear"
SlashCmdList["WMCTARGETCLEAR"] = function()
    EnsureSV()
    local sv = SV()
    sv.placeKey = ""
    sv.placeModifier = ""
    sv.clearKey = ""
    sv.clearModifier = ""
    UpdateBindings()
    print(L["WorldMarkerCycler: target marker keybinds cleared."])
end


-- /wmctadd <cycle|clear> <modifiers> <key>: Add a keybind for cycle or clear
SLASH_WMCTARGETADD1 = "/wmctadd"
SlashCmdList["WMCTARGETADD"] = function(msg)
    EnsureSV()
    local sv = SV()
    -- Accepts: "cycle SHIFT- F1" or "cycle F1" or "cycle SHIFT-F1"
    local which, rest = msg:match("^(%w+)%s+(.+)$")
    if not which or (which ~= "cycle" and which ~= "clear") then
        print(L["Usage: /wmctadd <cycle|clear> <modifiers> <key>"])
        print(L["Example: /wmctadd cycle CTRL- SHIFT- F1"])
        return
    end
    rest = rest or ""
    local mods, key = rest:match("^([%w%-]+)%s+([%w%p]+)$")
    if not key then
        -- Try to parse as just key (no modifier)
        key = rest:match("^%s*([%w%p]+)%s*$")
        mods = ""
    end
    mods = mods or ""
    key = key or ""
    -- Ensure mods and key are strings
    if type(mods) ~= "string" then mods = tostring(mods or "") end
    if type(key) ~= "string" then key = tostring(key or "") end
    local upmods = mods:upper()
    local modstr = ""
    if upmods:find("CTRL%-") or upmods:find("CTR%-%") then modstr = modstr.."CTRL-"; mods = mods:gsub("[Cc][Tt][Rr][Ll]?%-", "") end
    if upmods:find("ALT%-") then modstr = modstr.."ALT-"; mods = mods:gsub("[Aa][Ll][Tt]%-", "") end
    if upmods:find("SHIFT%-") or upmods:find("MAJ%-%") then modstr = modstr.."SHIFT-"; mods = mods:gsub("[Ss][Hh][Ii][Ff][Tt]%-", ""):gsub("[Mm][Aa][Jj]%-", "") end
    -- Store raw key name for binding API; use GetBindingText only for display
    local rawKey = key:upper()
    local displayKey = GetBindingText(rawKey, "KEY_", 1) or rawKey
    if which == "cycle" then
        sv.placeModifier = modstr
        sv.placeKey = rawKey
    elseif which == "clear" then
        sv.clearModifier = modstr
        sv.clearKey = rawKey
    end
    UpdateBindings()
    print(L["WorldMarkerCycler: set "]..which..L[" keybind to "]..(modstr or "")..(displayKey or ""))
end

-- Expose UpdateBindings for UI
WorldMarkerCyclerTargetAPI.UpdateBindings = UpdateBindings
