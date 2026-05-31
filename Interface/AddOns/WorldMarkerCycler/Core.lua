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
    -- Validate orderList: must be exactly 8 numbers in range 1-8
    local function isValidOrderList(tbl)
        if type(tbl) ~= "table" or #tbl ~= 8 then return false end
        for i = 1, 8 do
            if type(tbl[i]) ~= "number" or tbl[i] < 1 or tbl[i] > 8 then return false end
        end
        return true
    end
    if not isValidOrderList(sv.orderList) then
        sv.orderList = {6,4,3,7,1,2,5,8}
    end
    -- Custom cycle mode: use a subset of markers instead of the full orderList
    if sv.customCycleEnabled == nil then sv.customCycleEnabled = false end
    sv.customCycleMarkers = sv.customCycleMarkers or {8, 4, 3, 2} -- default: skull, cross, diamond, triangle
    -- Click edge: nil = auto-detect from key name. true = force AnyDown. false = force AnyUp.
    -- Auto-detect: BUTTON* keys use AnyDown, keyboard keys use AnyUp.
    -- Only set this if sv.useClickDown is explicitly true/false from a prior /wmcclickedge command.
    -- Leave nil to keep auto mode.
end

-- Secure world marker cycler button



local cycleBtn = CreateFrame("Button", "WorldMarkerCyclerButton", UIParent, "SecureActionButtonTemplate")
cycleBtn:SetAttribute("type", "macro")
-- Default: AnyUp for keyboard bindings. Call ApplyCycleClickEdge() after SV loads
-- to switch to AnyDown for mouse button binding users.
cycleBtn:RegisterForClicks("AnyUp")

local function ApplyCycleClickEdge()
    local sv = SV()
    -- Manual override (explicitly forced by user via /wmcclickedge up|down) wins.
    -- nil means "auto" — detect from the bound key name.
    if sv and sv.useClickDown == true then
        cycleBtn:RegisterForClicks("AnyDown")
        return
    elseif sv and sv.useClickDown == false then
        cycleBtn:RegisterForClicks("AnyUp")
        return
    end
    -- Auto-detect: WoW mouse buttons (BUTTON1, BUTTON4, BUTTON6, etc.) bound via
    -- SetOverrideBindingClick fire AnyDown. Keyboard keys (including keys sent by
    -- MMO mouse software like Numpad1-12) fire AnyUp.
    if sv then
        local key = (sv.placeKey or ""):upper()
        if key:find("^BUTTON%d") then
            cycleBtn:RegisterForClicks("AnyDown")
            return
        end
    end
    cycleBtn:RegisterForClicks("AnyUp")
end

SecureHandlerWrapScript(cycleBtn, "PreClick", cycleBtn, [=[
    if not order or type(order) ~= "table" or #order == 0 then
        self:SetAttribute("macrotext", "")
        return
    end
    i = (i % #order) + 1
    local marker = order[i] or 1
    self:SetAttribute("macrotext", "/wm [@cursor] " .. marker)
]=])

-- Restore dedicated clear button

local clearBtn = CreateFrame("Button", "WorldMarkerClearButton", UIParent, "SecureActionButtonTemplate")
clearBtn:SetAttribute("type", "macro")
clearBtn:RegisterForClicks("AnyUp", "AnyDown")
SecureHandlerWrapScript(clearBtn, "PreClick", clearBtn, [=[
    self:SetAttribute("macrotext", "/cwm 9")
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
    if sv then
        -- Use custom cycle markers when enabled, otherwise use full orderList
        local list = (sv.customCycleEnabled and sv.customCycleMarkers) or sv.orderList
        if list then
            for _, id in ipairs(list) do
                body = body .. string.format("tinsert(order,%d) ", id)
            end
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
    -- Re-apply click edge in case the newly bound key is/isn't a mouse button
    ApplyCycleClickEdge()
end

-- Event bootstrap
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        InitSaved()
        ApplyCycleClickEdge()
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
    if type(list) == "table" and #list == 8 then
        SV().orderList = list
        BuildOrderTable()
    end
end

-- Custom cycle mode API
function WorldMarkerCyclerAPI.SetCustomCycleEnabled(enabled)
    EnsureSV()
    SV().customCycleEnabled = enabled and true or false
    BuildOrderTable()
end

function WorldMarkerCyclerAPI.GetCustomCycleEnabled()
    local sv = SV()
    return sv and sv.customCycleEnabled or false
end

function WorldMarkerCyclerAPI.SetCustomCycleMarkers(list)
    EnsureSV()
    if type(list) == "table" and #list > 0 then
        SV().customCycleMarkers = list
        BuildOrderTable()
    end
end

function WorldMarkerCyclerAPI.GetCustomCycleMarkers()
    local sv = SV()
    return sv and sv.customCycleMarkers or {}
end

-- Toggle click edge for users who bind to a mouse button (AnyDown) vs keyboard (AnyUp)
function WorldMarkerCyclerAPI.SetUseClickDown(enabled)
    EnsureSV()
    -- nil = auto-detect, true = force AnyDown, false = force AnyUp
    if enabled == nil then
        SV().useClickDown = nil
    else
        SV().useClickDown = enabled and true or false
    end
    ApplyCycleClickEdge()
end

function WorldMarkerCyclerAPI.GetUseClickDown()
    local sv = SV()
    return sv and sv.useClickDown or false
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


SLASH_WMCCLICKEDGE1 = "/wmcclickedge"
SlashCmdList["WMCCLICKEDGE"] = function(msg)
    local mode = msg and msg:lower():match("^%s*(%S+)")
    local sv = SV()
    local boundKey = sv and (sv.placeKey or ""):upper() or ""
    local keyIsMouseBtn = boundKey:find("^BUTTON%d") ~= nil

    if mode == "down" then
        WorldMarkerCyclerAPI.SetUseClickDown(true)
        print("WorldMarkerCycler: click edge FORCED to DOWN.")
        if not keyIsMouseBtn and boundKey ~= "" then
            print("|cffff4444Warning: your bound key '" .. boundKey .. "' is a keyboard key. Forcing DOWN will break it. Type /wmcclickedge up to restore.|r")
        end
    elseif mode == "up" then
        WorldMarkerCyclerAPI.SetUseClickDown(false)
        print("WorldMarkerCycler: click edge FORCED to UP.")
        if keyIsMouseBtn and boundKey ~= "" then
            print("|cffff4444Warning: your bound key '" .. boundKey .. "' is a mouse button. Forcing UP will break it. Type /wmcclickedge auto to restore.|r")
        end
    elseif mode == "auto" then
        -- Clear the manual override and let auto-detect take over
        EnsureSV()
        SV().useClickDown = nil
        ApplyCycleClickEdge()
        local edge = keyIsMouseBtn and "DOWN" or "UP"
        print("WorldMarkerCycler: click edge reset to AUTO (currently " .. edge .. " for key '" .. boundKey .. "').")
    else
        local forced = sv and sv.useClickDown
        local autoEdge = keyIsMouseBtn and "DOWN" or "UP"
        local status
        if forced == nil then
            status = "AUTO (" .. autoEdge .. ") — key '" .. boundKey .. "'"
        elseif forced then
            status = "FORCED DOWN (manual override)"
        else
            status = "FORCED UP (manual override)"
        end
        print("WorldMarkerCycler: click edge = " .. status)
        print("  Usage: /wmcclickedge auto|up|down")
        print("  'auto' is recommended — detects keyboard vs mouse button automatically.")
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

-- One-line status report — easy to copy and paste when reporting issues
SLASH_WMCSTATUS1 = "/wmcstatus"
SlashCmdList["WMCSTATUS"] = function()
    local sv = SV()
    local cycleKey  = sv and ((sv.placeModifier or "") .. (sv.placeKey or "")) or "(none)"
    local clearKey  = sv and ((sv.clearModifier or "") .. (sv.clearKey or "")) or "(none)"
    local rawKey    = sv and (sv.placeKey or ""):upper() or ""
    local isBtn     = rawKey:find("^BUTTON%d") ~= nil
    local forced    = sv and sv.useClickDown
    local edgeMode
    if forced == true then
        edgeMode = "FORCED-DOWN"
    elseif forced == false then
        edgeMode = "FORCED-UP"
    else
        edgeMode = "AUTO(" .. (isBtn and "AnyDown" or "AnyUp") .. ")"
    end
    local orderStr = ""
    if sv and sv.orderList then
        orderStr = table.concat(sv.orderList, ",")
    end
    local customStr = ""
    if sv and sv.customCycleEnabled and sv.customCycleMarkers then
        customStr = " CUSTOM={" .. table.concat(sv.customCycleMarkers, ",") .. "}"
    end
    local line = string.format(
        "[WMC] WoW=%s Locale=%s | CycleKey=%s | ClearKey=%s | Edge=%s | Order=%s%s",
        select(4, GetBuildInfo()), GetLocale(), cycleKey, clearKey, edgeMode, orderStr, customStr
    )
    print(line)
    print("|cffaaaaaa(Copy the line above and send it when reporting an issue)|r")
end

-- Debug: dump saved values and active binding state
SLASH_WMCDEBUG1 = "/wmcdebug"
SlashCmdList["WMCDEBUG"] = function()
    print("=== WMC Debug ===")
    print("Locale:", GetLocale())

    -- World marker saved values
    local sv = _G.WMC_Saved
    if sv then
        local pk = sv.placeKey or "(nil)"
        local pm = sv.placeModifier or "(nil)"
        local ck = sv.clearKey or "(nil)"
        local cm = sv.clearModifier or "(nil)"
        print("World placeKey=[" .. tostring(pk) .. "] mod=[" .. tostring(pm) .. "]")
        print("World clearKey=[" .. tostring(ck) .. "] mod=[" .. tostring(cm) .. "]")
        -- Check byte values to detect non-ASCII garbage
        print("  placeKey bytes: " .. (pk and pk:gsub(".", function(c) return string.format("%02X ", c:byte()) end) or "nil"))
        print("  clearKey bytes: " .. (ck and ck:gsub(".", function(c) return string.format("%02X ", c:byte()) end) or "nil"))
        -- Check if binding is actually registered
        local fullCycle = (pm or "") .. (pk or "")
        local fullClear = (cm or "") .. (ck or "")
        if fullCycle ~= "" then
            local action = GetBindingAction(fullCycle)
            print("  Binding for [" .. fullCycle .. "] -> action=[" .. tostring(action) .. "]")
        end
        if fullClear ~= "" then
            local action = GetBindingAction(fullClear)
            print("  Binding for [" .. fullClear .. "] -> action=[" .. tostring(action) .. "]")
        end
    else
        print("WMC_Saved is nil!")
    end

    -- Target marker saved values
    local tsv = _G.WMC_TargetSaved
    if tsv then
        print("Target placeKey=[" .. tostring(tsv.placeKey) .. "] mod=[" .. tostring(tsv.placeModifier) .. "]")
        print("Target clearKey=[" .. tostring(tsv.clearKey) .. "] mod=[" .. tostring(tsv.clearModifier) .. "]")
        print("  placeKey bytes: " .. ((tsv.placeKey or ""):gsub(".", function(c) return string.format("%02X ", c:byte()) end)))
    else
        print("WMC_TargetSaved is nil!")
    end

    -- Mouseover marker saved values
    local msv = _G.WMC_MouseoverSaved
    if msv then
        print("Mouse placeKey=[" .. tostring(msv.placeKey) .. "] mod=[" .. tostring(msv.placeModifier) .. "]")
        print("Mouse clearKey=[" .. tostring(msv.clearKey) .. "] mod=[" .. tostring(msv.clearModifier) .. "]")
    else
        print("WMC_MouseoverSaved is nil!")
    end

    -- Raid picker saved values
    local rsv = _G.WMC_RaidPickerSaved
    if rsv then
        print("Raid openKey=[" .. tostring(rsv.openKey) .. "] mod=[" .. tostring(rsv.openModifier) .. "]")
    else
        print("WMC_RaidPickerSaved is nil!")
    end

    print("=== End WMC Debug ===")
end

-- Test: manually try placing a world marker with different commands
SLASH_WMCTEST1 = "/wmctest"
SlashCmdList["WMCTEST"] = function(msg)
    local idx = tonumber(msg) or 1
    print("|cff00ff00[WMC Test] Trying to place world marker " .. idx .. " via different methods...|r")

    -- Method 1: Direct API call
    local ok1, err1 = pcall(PlaceRaidMarker, idx)
    print("  PlaceRaidMarker(" .. idx .. "): " .. (ok1 and "OK" or ("FAIL: " .. tostring(err1))))

    -- Method 2: Direct API call with 0 args (at player)
    local ok2, err2 = pcall(ClearRaidMarker, idx)
    print("  ClearRaidMarker(" .. idx .. "): " .. (ok2 and "OK" or ("FAIL: " .. tostring(err2))))

    -- Check button state
    local mt = cycleBtn:GetAttribute("macrotext") or "(nil)"
    print("  cycleBtn macrotext: " .. mt)
    print("  cycleBtn name: " .. (cycleBtn:GetName() or "nil"))
    print("  cycleBtn shown: " .. tostring(cycleBtn:IsShown()))
    print("  cycleBtn visible: " .. tostring(cycleBtn:IsVisible()))

    -- Check bindings
    local sv = _G.WMC_Saved
    if sv then
        local fullKey = (sv.placeModifier or "") .. (sv.placeKey or "")
        if fullKey ~= "" then
            local action = GetBindingAction(fullKey, true)
            print("  GetBindingAction('" .. fullKey .. "'): " .. tostring(action))
        end
    end
end