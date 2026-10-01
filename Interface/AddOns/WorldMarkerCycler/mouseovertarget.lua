-- ======================================================
-- WorldMarkerCycler - Mouseover Target Marker Cycler
-- File: mouseovertarget.lua
-- Places icons on your mouseover (living enemy) or else your target, using the
-- secure "raidtarget" button action (no slash text, so client language and
-- keyboard layout don't matter). /wmcmarkmode macro restores the old /tm macro.
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

    -- Feature toggle: when false, mouseover marker keybinds are disabled entirely
    if sv.enabled == nil then sv.enabled = true end

    -- "action" = secure raid-target action (locale/keyboard independent, default)
    -- "macro"  = old /tm macro text (fallback, /wmcmarkmode macro)
    if sv.markMode ~= "macro" then sv.markMode = "action" end

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
cycleBtn:SetAttribute("type", "raidtarget")
cycleBtn:SetAttribute("action", "set")
cycleBtn:SetAttribute("unit", "mouseover")
cycleBtn:SetAttribute("wmc-mode", "action")
-- IMPORTANT: register only ONE click edge.
-- Registering both "AnyUp" and "AnyDown" makes a single keypress fire the
-- PreClick snippet TWICE, so the cycle index advances by 2 and you only ever
-- see half the markers (4 of 8). Core.lua does the same single-edge dance.
cycleBtn:RegisterForClicks("AnyUp")

local function ApplyCycleClickEdge()
    if InCombatLockdown() then return end
    local sv = SV()
    -- This module's own setting wins. If it has none, follow the ground
    -- cycler's "Click edge" setting (/wmcclickedge), so one setting fixes all.
    local forced = sv and sv.useClickDown
    if forced == nil and type(_G.WMC_Saved) == "table" then
        forced = _G.WMC_Saved.useClickDown
    end
    if forced == true then
        cycleBtn:RegisterForClicks("AnyDown")
        return
    elseif forced == false then
        cycleBtn:RegisterForClicks("AnyUp")
        return
    end
    -- Auto: mouse buttons bound via SetOverrideBindingClick fire on DOWN,
    -- keyboard keys fire on UP.
    if sv then
        local key = (sv.placeKey or ""):upper()
        if key:find("^BUTTON%d") then
            cycleBtn:RegisterForClicks("AnyDown")
            return
        end
    end
    cycleBtn:RegisterForClicks("AnyUp")
end

-- Clear mouseover marker
local clearBtn = CreateFrame(
    "Button",
    "WMC_MouseoverMarkerClearButton",
    UIParent,
    "SecureActionButtonTemplate"
)
clearBtn:SetAttribute("type", "raidtarget")
clearBtn:SetAttribute("action", "clear")
clearBtn:SetAttribute("unit", "mouseover")
clearBtn:SetAttribute("wmc-mode", "action")
clearBtn:RegisterForClicks("AnyUp", "AnyDown")
-- Clearing restarts the cycle at the first marker in the order (matches Core.lua)
clearBtn:SetScript("PostClick", function()
    if not InCombatLockdown() then SecureHandlerExecute(cycleBtn, "i=0") end
end)

-- =========================
-- Secure Order Table
-- =========================
-- =========================
-- Shared cycle order
-- =========================
-- Follow the SAME order as the ground markers (Core.lua / the "Marker Cycle
-- Order" box in the options window). There is no separate order editor for
-- this cycler, so mirroring is what keeps all three consistent - previously
-- this module silently kept its own hardcoded 8,7,6,5,4,3,2,1 list.
-- World marker number (/wm) -> raid target icon number (/tm)
-- 1 Square->6, 2 Triangle->4, 3 Diamond->3, 4 Cross->7, 5 Star->1, 6 Circle->2, 7 Moon->5, 8 Skull->8
local WORLD_TO_RAID_TARGET = { 6, 4, 3, 7, 1, 2, 5, 8 }

local function SyncOrderFromWorld()
    local w = _G.WMC_Saved
    if type(w) ~= "table" then return false end
    -- honour Core.lua's custom-subset mode too
    local list = (w.customCycleEnabled and w.customCycleMarkers) or w.orderList
    if type(list) ~= "table" or #list == 0 then return false end
    local copy = {}
    for i, id in ipairs(list) do
        -- WMC_Saved uses WORLD marker numbers (/wm: 1 Square .. 8 Skull) but /tm and the
        -- "raidtarget" action use RAID TARGET numbers (1 Star .. 8 Skull). Convert so the
        -- target/mouseover cycle places the same icons, in the same order, as the menu shows.
        if type(id) == "number" then copy[#copy + 1] = WORLD_TO_RAID_TARGET[id] or id end
    end
    if #copy == 0 then return false end
    EnsureSV()
    SV().orderList = copy
    return true
end

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
    local marker = 1
    if type(order) == "table" and #order > 0 then
        i = (i % #order) + 1
        marker = order[i] or 1
    end
    if self:GetAttribute("wmc-mode") == "macro" then
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", "/tm [@mouseover,harm,nodead][] " .. marker)
    else
        -- Same rule as the old macro: living enemy under the cursor, else your target
        local unit = SecureCmdOptionParse("[@mouseover,harm,nodead] mouseover; target")
        self:SetAttribute("type", "raidtarget")
        self:SetAttribute("action", "set")
        self:SetAttribute("unit", unit or "target")
        self:SetAttribute("marker", marker)
    end
]=])

SecureHandlerWrapScript(clearBtn, "PreClick", clearBtn, [=[
    if self:GetAttribute("wmc-mode") == "macro" then
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", "/tm [@mouseover,harm,nodead][] 0")
    else
        local unit = SecureCmdOptionParse("[@mouseover,harm,nodead] mouseover; target")
        self:SetAttribute("type", "raidtarget")
        self:SetAttribute("action", "clear")
        self:SetAttribute("unit", unit or "target")
    end
]=])

-- =========================
-- Key Bindings
-- =========================
local bindingsFrame = CreateFrame("Frame", "WMC_MouseoverMarkerBindings")

local function ApplyMarkMode()
    if InCombatLockdown() then return end
    local sv = SV()
    local mode = (sv and sv.markMode == "macro") and "macro" or "action"
    cycleBtn:SetAttribute("wmc-mode", mode)
    clearBtn:SetAttribute("wmc-mode", mode)
end

local function UpdateBindings()
    ApplyCycleClickEdge()  -- keep the click edge matched to the bound key
    ApplyMarkMode()
    ClearOverrideBindings(bindingsFrame)

    local sv = SV()
    if not sv then return end

    -- If mouseover markers are disabled, leave bindings cleared
    if sv.enabled == false then return end

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

-- When the ground cycler's click edge changes (options window or
-- /wmcclickedge), re-apply ours too since we follow it by default.
local HookGroundClickEdge_done = false
local function HookGroundClickEdge()
    if HookGroundClickEdge_done then return end
    HookGroundClickEdge_done = true
    local function reapply() ApplyCycleClickEdge() end
    if SlashCmdList and SlashCmdList["WMCCLICKEDGE"] then
        hooksecurefunc(SlashCmdList, "WMCCLICKEDGE", reapply)
    end
    local core = _G.WorldMarkerCyclerAPI
    if core and core.SetUseClickDown then
        hooksecurefunc(core, "SetUseClickDown", reapply)
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
        HookGroundClickEdge()
        SyncOrderFromWorld()
        BuildOrderTable()
        UpdateBindings()
    elseif event == "PLAYER_LOGIN" then
        -- Core.lua validates WMC_Saved on its own ADDON_LOADED pass;
        -- re-sync here so we pick up the final validated list.
        SyncOrderFromWorld()
        BuildOrderTable()
        UpdateBindings()
    end
end)

-- =========================
-- Public API
-- =========================
WorldMarkerCyclerMouseoverAPI = WorldMarkerCyclerMouseoverAPI or {}

function WorldMarkerCyclerMouseoverAPI.SetEnabled(enabled)
    EnsureSV()
    SV().enabled = enabled and true or false
    UpdateBindings()
end

function WorldMarkerCyclerMouseoverAPI.GetEnabled()
    local sv = SV()
    return sv and sv.enabled ~= false
end

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
    local mods, key = rest:match("^([%w%-]+)%s+(%S+)$")
    if not key then
        -- Try to parse as just key (no modifier)
        key = rest:match("^%s*(%S+)%s*$")
        mods = ""
    end
    mods = mods or ""
    key = key or ""
    -- Locale-agnostic modifier parsing
    local upmods = mods:upper()
    local modstr = ""
    if upmods:find("CTRL%-") or upmods:find("CTR%-") then modstr = modstr.."CTRL-"; mods = mods:gsub("[Cc][Tt][Rr][Ll]?%-", "") end
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

function WorldMarkerCyclerMouseoverAPI.SetMarkMode(mode)
    EnsureSV()
    SV().markMode = (mode == "macro") and "macro" or "action"
    ApplyMarkMode()
end

function WorldMarkerCyclerMouseoverAPI.GetMarkMode()
    local sv = SV()
    return (sv and sv.markMode == "macro") and "macro" or "action"
end

-- Re-read the shared order (called by the options window when you edit it)
WorldMarkerCyclerMouseoverAPI.SyncOrderFromWorld = function()
    if SyncOrderFromWorld() then BuildOrderTable() end
end

