-- ======================================================
-- WorldMarkerCycler - Target Marker Cycler
-- File: target.lua
-- Places icons with the secure "raidtarget" button action, which does not
-- depend on slash-command text or client language. /wmcmarkmode macro
-- switches back to the old /tm macro if ever needed.
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

    -- Feature toggle: when false, target marker keybinds are disabled entirely
    if sv.enabled == nil then sv.enabled = true end

    -- "action" = secure raid-target action (locale/keyboard independent, default)
    -- "macro"  = old /tm macro text (fallback, /wmcmarkmode macro)
    if sv.markMode ~= "macro" then sv.markMode = "action" end
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
cycleBtn:SetAttribute("type", "raidtarget")
cycleBtn:SetAttribute("action", "set")
cycleBtn:SetAttribute("unit", "target")
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

-- Clear target marker
local clearBtn = CreateFrame(
    "Button",
    "WMC_TargetMarkerClearButton",
    UIParent,
    "SecureActionButtonTemplate"
)
clearBtn:SetAttribute("type", "raidtarget")
clearBtn:SetAttribute("action", "clear")
clearBtn:SetAttribute("unit", "target")
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
    if not order or #order == 0 then
        self:SetAttribute("type", nil)  -- nothing to place
        return
    end
    i = (i % #order) + 1
    local marker = order[i] or 1
    if self:GetAttribute("wmc-mode") == "macro" then
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", "/tm " .. marker)
    else
        self:SetAttribute("type", "raidtarget")
        self:SetAttribute("action", "set")
        self:SetAttribute("unit", "target")
        self:SetAttribute("marker", marker)
    end
]=])

SecureHandlerWrapScript(clearBtn, "PreClick", clearBtn, [=[
    if self:GetAttribute("wmc-mode") == "macro" then
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", "/tm 0")
    else
        self:SetAttribute("type", "raidtarget")
        self:SetAttribute("action", "clear")
        self:SetAttribute("unit", "target")
    end
]=])

-- =========================
-- Key Bindings
-- =========================
local bindingsFrame = CreateFrame("Frame", "WMC_TargetMarkerBindings")

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

    -- If target markers are disabled, leave bindings cleared
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
WorldMarkerCyclerTargetAPI = WorldMarkerCyclerTargetAPI or {}

function WorldMarkerCyclerTargetAPI.SetEnabled(enabled)
    EnsureSV()
    SV().enabled = enabled and true or false
    UpdateBindings()
end

function WorldMarkerCyclerTargetAPI.GetEnabled()
    local sv = SV()
    return sv and sv.enabled ~= false
end

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
    local mods, key = rest:match("^([%w%-]+)%s+(%S+)$")
    if not key then
        -- Try to parse as just key (no modifier)
        key = rest:match("^%s*(%S+)%s*$")
        mods = ""
    end
    mods = mods or ""
    key = key or ""
    -- Ensure mods and key are strings
    if type(mods) ~= "string" then mods = tostring(mods or "") end
    if type(key) ~= "string" then key = tostring(key or "") end
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
WorldMarkerCyclerTargetAPI.UpdateBindings = UpdateBindings

function WorldMarkerCyclerTargetAPI.SetMarkMode(mode)
    EnsureSV()
    SV().markMode = (mode == "macro") and "macro" or "action"
    ApplyMarkMode()
end

function WorldMarkerCyclerTargetAPI.GetMarkMode()
    local sv = SV()
    return (sv and sv.markMode == "macro") and "macro" or "action"
end

-- Re-read the shared order (called by the options window when you edit it)
WorldMarkerCyclerTargetAPI.SyncOrderFromWorld = function()
    if SyncOrderFromWorld() then BuildOrderTable() end
end


-- /wmcmarkmode action|macro : how target AND mouseover markers are placed
--   action (default) = secure raid-target action, independent of language/slash text
--   macro            = old "/tm" macro behaviour
SLASH_WMCMARKMODE1 = "/wmcmarkmode"
SlashCmdList["WMCMARKMODE"] = function(msg)
    local arg = ((msg or ""):lower()):match("^%s*(%S*)") or ""
    local t = WorldMarkerCyclerTargetAPI
    local m = _G.WorldMarkerCyclerMouseoverAPI
    if arg == "action" or arg == "macro" then
        if InCombatLockdown() then
            print("WorldMarkerCycler: can't change mark mode in combat.")
            return
        end
        t.SetMarkMode(arg)
        if m and m.SetMarkMode then m.SetMarkMode(arg) end
        print("WorldMarkerCycler: target & mouseover markers now use " ..
            (arg == "action" and "the secure raid-target action (default)." or "the /tm macro."))
    else
        print("WorldMarkerCycler: mark mode is '" .. t.GetMarkMode() .. "'.")
        print("Usage: /wmcmarkmode action|macro")
    end
end
