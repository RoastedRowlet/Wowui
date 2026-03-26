-- Core.lua

local ADDON_NAME = "WorldMarkerCycler"

-- Locale table for user-facing strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["World Marker Cycler: cleared override bindings and reset cycle index."] = "World Marker Cycler : raccourcis supprimés et index du cycle réinitialisé."
    L["Usage: /wmcbind place [key] OR /wmcbind clear [key]"] = "Utilisation : /wmcbind place [touche] OU /wmcbind clear [touche]"
    L["Press the key you want to bind for '"] = "Appuyez sur la touche à assigner pour '"
    L["'. Press ESC to cancel."] = "'. Appuyez sur ÉCHAP pour annuler."
    L["World Marker Cycler: binding cancelled."] = "World Marker Cycler : assignation annulée."
    L["World Marker Cycler: 'place' bound to "] = "World Marker Cycler : 'placer' assigné à "
    L["World Marker Cycler: 'clear' bound to "] = "World Marker Cycler : 'effacer' assigné à "
end

-- Safe SV accessor
local function SV()
    return _G.WMC_Saved
end

local function EnsureSV()
    if not SV() then
        _G.WMC_Saved = {}
    end
end

local function InitSaved()
    EnsureSV()
    local sv = SV()
    sv.placeKey      = sv.placeKey      or "B"
    sv.placeModifier = sv.placeModifier or ""
    sv.clearKey      = sv.clearKey      or "B"
    sv.clearModifier = sv.clearModifier or "CTRL-"
    sv.orderList     = sv.orderList     or {6,4,3,7,1,2,5,8}
end

-- Secure world marker cycler button



local cycleBtn = CreateFrame("Button", "WorldMarkerCyclerButton", nil, "SecureActionButtonTemplate")
cycleBtn:SetAttribute("type", "macro")
cycleBtn:RegisterForClicks("AnyUp", "AnyDown")
SecureHandlerWrapScript(cycleBtn, "PreClick", cycleBtn, [=[
    if not down or not next(order) then return end
    i = (i % #order) + 1
    local marker = order[i] or 1
    self:SetAttribute("macrotext", "/worldmarker [@cursor] " .. marker)
]=])

-- Restore dedicated clear button

local clearBtn = CreateFrame("Button", "WorldMarkerClearButton", UIParent, "SecureActionButtonTemplate")
clearBtn:SetAttribute("type", "macro")
clearBtn:RegisterForClicks("AnyUp", "AnyDown")
SecureHandlerWrapScript(clearBtn, "PreClick", clearBtn, [=[
    self:SetAttribute("macrotext", "/clearworldmarker 9")
]=])
clearBtn:SetScript("PostClick", function()
    if WorldMarkerCyclerAPI and WorldMarkerCyclerAPI.ResetCycleIndex then
        WorldMarkerCyclerAPI.ResetCycleIndex()
    end
end)

-- Secure world marker clear button
-- No longer needed: clearBtn and its handler removed

-- Binding frame holder
local bindingsFrame = CreateFrame("Frame", "WorldMarkerCyclerBindings")

local function BuildOrderTable()
    local sv = SV()
    local body = "i=0;order=newtable() "
    if sv and sv.orderList then
        for _, id in ipairs(sv.orderList) do
            body = body .. string.format("tinsert(order,%d) ", id)
        end
    end
    SecureHandlerExecute(cycleBtn, body)
end

-- (removed duplicate handler)

local function UpdateBindings()
    ClearOverrideBindings(bindingsFrame)

    local sv = SV()
    local cycleFullKey = ""
    local clearFullKey = ""

    if sv then
        cycleFullKey = (sv.placeModifier or "") .. (sv.placeKey or "")
        clearFullKey = (sv.clearModifier or "") .. (sv.clearKey or "")
    end

    if cycleFullKey ~= "" then
        SetOverrideBindingClick(bindingsFrame, true, cycleFullKey, cycleBtn:GetName())
    end
    if clearFullKey ~= "" then
        SetOverrideBindingClick(bindingsFrame, true, clearFullKey, clearBtn:GetName())
    end
end

-- Event bootstrap
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        InitSaved()
        BuildOrderTable()
        UpdateBindings()
        -- Notify UI.lua that SVs are ready
        if WorldMarkerCyclerUI_OnReady then
            WorldMarkerCyclerUI_OnReady()
        end
    elseif event == "PLAYER_LOGIN" then
        UpdateBindings()
    end
end)

-- Public API (safe when SV is nil)
WorldMarkerCyclerAPI = WorldMarkerCyclerAPI or {}

function WorldMarkerCyclerAPI.SetPlaceKey(mod, key)
    EnsureSV()
    local sv = SV()
    sv.placeModifier = mod or ""
    sv.placeKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerAPI.SetClearKey(mod, key)
    EnsureSV()
    local sv = SV()
    sv.clearModifier = mod or ""
    sv.clearKey = key or ""
    UpdateBindings()
end

function WorldMarkerCyclerAPI.GetPlaceKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.placeModifier or "") .. (sv.placeKey or "")
end

function WorldMarkerCyclerAPI.GetClearKey()
    local sv = SV()
    if not sv then return "" end
    return (sv.clearModifier or "") .. (sv.clearKey or "")
end

function WorldMarkerCyclerAPI.SetOrder(list)
    EnsureSV()
    if type(list) == "table" then
        SV().orderList = list
        BuildOrderTable()
    end
end

-- Reset the cycling index so the next cycle starts from the top
function WorldMarkerCyclerAPI.ResetCycleIndex()
    if not InCombatLockdown() then
        SecureHandlerExecute(cycleBtn, "i=0")
    else
        -- Optionally, queue for after combat or notify user
        print("WorldMarkerCycler: Cannot reset cycle index during combat.")
    end
end


SLASH_WMCCLEAR1 = "/wmcclear"
SlashCmdList["WMCCLEAR"] = function()
    ClearOverrideBindings(bindingsFrame)
    if WorldMarkerCyclerAPI and WorldMarkerCyclerAPI.ResetCycleIndex then
        WorldMarkerCyclerAPI.ResetCycleIndex()
    end
    print(L["World Marker Cycler: cleared override bindings and reset cycle index."])
end


SLASH_WMCBIND1 = "/wmcbind"
SlashCmdList["WMCBIND"] = function(msg)
    local which, keyarg = msg and msg:match("^(%S+)%s*(.*)$")
    which = which and which:lower() or nil
    if not which or (which ~= "place" and which ~= "clear") then
        print(L["Usage: /wmcbind place [key] OR /wmcbind clear [key]"])
        return
    end
    if keyarg and keyarg ~= "" then
        -- Use WoW's GetBindingFromClick to parse the key and modifiers in a locale-agnostic way
        local mod, key = "", keyarg
        -- Try to extract modifiers using GetBindingText for each possible modifier
        local upkeyarg = keyarg:upper()
        -- These are always "CTRL-", "ALT-", "SHIFT-" in the API, but user input may be localized, so we check both
        local ctrlLoc = (locale == "frFR") and "CTRL-" or "CTRL-"
        local altLoc = (locale == "frFR") and "ALT-" or "ALT-"
        local shiftLoc = (locale == "frFR") and "MAJ-" or "SHIFT-"
        if upkeyarg:find("CTRL%-") or upkeyarg:find("CTR%-%") then mod = mod.."CTRL-"; key = key:gsub("[Cc][Tt][Rr][Ll]?%-", "") end
        if upkeyarg:find("ALT%-") then mod = mod.."ALT-"; key = key:gsub("[Aa][Ll][Tt]%-", "") end
        if upkeyarg:find("SHIFT%-") or upkeyarg:find("MAJ%-") then mod = mod.."SHIFT-"; key = key:gsub("[Ss][Hh][Ii][Ff][Tt]%-", ""):gsub("[Mm][Aa][Jj]%-", "") end
        -- Store raw key name (always English) for binding API; use GetBindingText only for display
        local rawKey = key:upper()
        local displayKey = GetBindingText(rawKey, "KEY_", 1) or rawKey
        if which == "place" then
            WorldMarkerCyclerAPI.SetPlaceKey(mod, rawKey)
            print(L["World Marker Cycler: 'place' bound to "]..mod..displayKey)
        else
            WorldMarkerCyclerAPI.SetClearKey(mod, rawKey)
            print(L["World Marker Cycler: 'clear' bound to "]..mod..displayKey)
        end
        return
    end
    print(L["Press the key you want to bind for '"]..which..L["'. Press ESC to cancel."])
    local f = CreateFrame("Frame", nil, UIParent)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            print(L["World Marker Cycler: binding cancelled."])
            self:Hide()
            self:SetScript("OnKeyDown", nil)
            return
        end
        local mod = ""
        if IsControlKeyDown() then mod = mod.."CTRL-" end
        if IsAltKeyDown() then mod = mod.."ALT-" end
        if IsShiftKeyDown() then mod = mod.."SHIFT-" end
        -- key from OnKeyDown is already the internal (English) name; use GetBindingText only for display
        local displayKey = GetBindingText(key, "KEY_", 1) or key
        if which == "place" then
            WorldMarkerCyclerAPI.SetPlaceKey(mod, key)
            print(L["World Marker Cycler: 'place' bound to "]..mod..displayKey)
        else
            WorldMarkerCyclerAPI.SetClearKey(mod, key)
            print(L["World Marker Cycler: 'clear' bound to "]..mod..displayKey)
        end
        self:Hide()
        self:SetScript("OnKeyDown", nil)
    end)
    f:SetScript("OnHide", function(self)
        self:SetScript("OnKeyDown", nil)
    end)
    f:Show()
end