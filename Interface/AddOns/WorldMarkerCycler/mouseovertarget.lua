-- ======================================================
-- WorldMarkerCycler - Mouseover Target Marker Cycler
-- File: mouseovertarget.lua
-- Uses Blizzard secure /tm command for @mouseover
-- ======================================================


local ADDON_NAME = "WorldMarkerCycler"

-- Locale table for user-facing strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["WorldMarkerCycler: mouseover marker keybinds cleared."] = "WorldMarkerCycler : raccourcis de survol effacés."
    L["Usage: /wmcmadd <cycle|clear> <modifiers> <key>"] = "Utilisation : /wmcmadd <cycle|clear> <modificateurs> <touche>"
    L["Example: /wmcmadd cycle CTRL- SHIFT- F1"] = "Exemple : /wmcmadd cycle CTRL- SHIFT- F1"
    L["WorldMarkerCycler: set "] = "WorldMarkerCycler : raccourci "
    L[" keybind to "] = " assigné à "
end

-- =========================
-- SavedVariables helpers
-- =========================
local function SV()
    return _G.WMC_MouseoverSaved
end

local function EnsureSV()
    if not SV() then
        _G.WMC_MouseoverSaved = {}
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

    -- Robust orderList initialization: must be a table of 8 numbers
    local function isValidOrderList(tbl)
        if type(tbl) ~= "table" or #tbl ~= 8 then return false end
        for i = 1, 8 do
            if type(tbl[i]) ~= "number" then return false end
        end
        return true
    end
    if not isValidOrderList(sv.orderList) then
        sv.orderList = { 8, 7, 6, 5, 4, 3, 2, 1 }
    end
end

-- =========================
-- Secure Buttons
-- =========================

-- Cycle mouseover marker
local cycleBtn = CreateFrame(
    "Button",
    "WMC_MouseoverMarkerCycleButton",
    UIParent,
    "SecureActionButtonTemplate"
)
cycleBtn:SetAttribute("type", "macro")
cycleBtn:SetAttribute("macrotext", "")
cycleBtn:RegisterForClicks("AnyDown")

-- Clear mouseover marker
local clearBtn = CreateFrame(
    "Button",
    "WMC_MouseoverMarkerClearButton",
    UIParent,
    "SecureActionButtonTemplate"
)
clearBtn:SetAttribute("type", "macro")
clearBtn:SetAttribute("macrotext", "")
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
    if not down then return end
    local marker = 1
    if type(order) == "table" and #order > 0 then
        i = (i % #order) + 1
        marker = order[i] or 1
    end
    self:SetAttribute(
        "macrotext",
        "/tm [@mouseover,harm,nodead][] " .. marker
    )
]=])

-- Clear mouseover marker
clearBtn:SetAttribute("macrotext", "/tm [@mouseover,harm,nodead][] 0")

-- =========================
-- Key Bindings
-- =========================
local bindingsFrame = CreateFrame("Frame", "WMC_MouseoverMarkerBindings")

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
WorldMarkerCyclerMouseoverAPI = WorldMarkerCyclerMouseoverAPI or {}

function WorldMarkerCyclerMouseoverAPI.SetPlaceKey(mod, key)
    EnsureSV()
    SV().placeModifier = mod or ""
    SV().placeKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerMouseoverAPI.SetClearKey(mod, key)
    EnsureSV()
    SV().clearModifier = mod or ""
    SV().clearKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerMouseoverAPI.SetOrder(list)
    EnsureSV()
    if type(list) == "table" then
        SV().orderList = list
        BuildOrderTable()
    end
end

function WorldMarkerCyclerMouseoverAPI.GetPlaceKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.placeModifier or "") .. (sv.placeKey or "")
end

function WorldMarkerCyclerMouseoverAPI.GetClearKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.clearModifier or "") .. (sv.clearKey or "")
end

-- /wmcmclear: Clear all keybinds for mouseover marker cycler

SLASH_WMCMOUSEOVERCLEAR1 = "/wmcmclear"
SlashCmdList["WMCMOUSEOVERCLEAR"] = function()
    EnsureSV()
    local sv = SV()
    sv.placeKey = ""
    sv.placeModifier = ""
    sv.clearKey = ""
    sv.clearModifier = ""
    UpdateBindings()
    print(L["WorldMarkerCycler: mouseover marker keybinds cleared."])
end


-- /wmcmadd <cycle|clear> <modifiers> <key>: Add a keybind for cycle or clear
SLASH_WMCMOUSEOVERADD1 = "/wmcmadd"
SlashCmdList["WMCMOUSEOVERADD"] = function(msg)
    EnsureSV()
    local sv = SV()
    -- Accepts: "cycle SHIFT- F1" or "cycle F1" or "cycle SHIFT-F1" or "cycle BUTTON4"
    local which, rest = msg:match("^(%w+)%s+(.+)$")
    if not which or (which ~= "cycle" and which ~= "clear") then
        print(L["Usage: /wmcmadd <cycle|clear> <modifiers> <key>"])
        print(L["Example: /wmcmadd cycle CTRL- SHIFT- F1"])
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
    -- Locale-agnostic modifier parsing
    local upmods = mods:upper()
    local modstr = ""
    if upmods:find("CTRL%-") or upmods:find("CTR%-%") then modstr = modstr.."CTRL-"; mods = mods:gsub("[Cc][Tt][Rr][Ll]?%-", "") end
    if upmods:find("ALT%-") then modstr = modstr.."ALT-"; mods = mods:gsub("[Aa][Ll][Tt]%-", "") end
    if upmods:find("SHIFT%-") or upmods:find("MAJ%-") then modstr = modstr.."SHIFT-"; mods = mods:gsub("[Ss][Hh][Ii][Ff][Tt]%-", ""):gsub("[Mm][Aa][Jj]%-", "") end
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
WorldMarkerCyclerMouseoverAPI.UpdateBindings = UpdateBindings
