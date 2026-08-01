-- ======================================================
-- WorldMarkerCycler - Raid Marker Picker
-- File: raidmarker_picker.lua
-- Persistent, lockable marker toolbar.
-- Click a marker to place it at your cursor. Right-click to toggle lock.
-- Drag to reposition when unlocked. /wmcrshow /wmcrhide /wmcrtoggle /wmcrlock
-- Also hosts ready check, start countdown and stop countdown buttons.
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
    L["Ready Check"] = "Vérification de préparation"
    L["Start Countdown"] = "Démarrer le compte à rebours"
    L["Stop Countdown"] = "Arrêter le compte à rebours"
    L["Asks the group if they are ready."] = "Demande au groupe s'il est prêt."
    L["Starts a pull timer."] = "Démarre un compte à rebours d'engagement."
    L["Cancels a running pull timer."] = "Annule le compte à rebours en cours."
    L["Requires group leader or assistant."] = "Nécessite d'être chef de groupe ou assistant."
    L["Marker bar: two rows"] = "Barre de marqueurs : deux lignes"
    L["Splits the bar so the markers sit above the action buttons."] = "Divise la barre : les marqueurs au-dessus des boutons d'action."
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
    if sv.countdownSeconds == nil then sv.countdownSeconds = 10 end
    if sv.rows == nil then sv.rows = 1 end
end

-- =========================
-- Picker UI
-- =========================
local picker = CreateFrame("Frame", "WMC_RaidMarkerPickerFrame", UIParent, "BackdropTemplate,SecureHandlerStateTemplate")
picker:SetSize(454, 44)
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

local markerButtons = {}
for i = 1, 8 do
    markerButtons[i] = CreateMarkerButton(i, i)
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

-- =========================
-- Ready check / countdown buttons
-- =========================
-- These sit to the right of CLEAR. All three run their action through a secure
-- macro button, which is what lets the protected ready-check / countdown calls
-- go through (and keeps working in combat).
local actionButtons = {}

local function CreateActionButton(suffix, xOffset, atlas, fallbackTexture, title, body)
    local btn = CreateFrame("Button", "WMC_RaidMarkerPicker" .. suffix .. "Button", picker, "SecureActionButtonTemplate")
    btn:SetSize(26, 26)
    btn:SetPoint("LEFT", picker, "LEFT", xOffset, 0)
    -- LEFT-click only, and only one click edge. Registering "AnyDown","AnyUp"
    -- like the marker buttons do would fire the macro TWICE per press - harmless
    -- for placing a marker, but it would send two ready checks or restart the
    -- countdown on release.
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", "")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if not icon:SetAtlas(atlas) then
        icon:SetTexture(fallbackTexture)
    end
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 1, 0)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Requires group leader or assistant."], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    actionButtons[#actionButtons + 1] = btn
    return btn
end

-- CLEAR ends at x=354, so these start at 360 and the frame is 454 wide.
local readyCheckBtn = CreateActionButton("ReadyCheck", 360,
    "common-icon-checkmark-yellow", "Interface\\RaidFrame\\ReadyCheck-Ready",
    L["Ready Check"], L["Asks the group if they are ready."])

local stopCountdownBtn = CreateActionButton("StopCountdown", 390,
    "common-icon-redx", "Interface\\RaidFrame\\ReadyCheck-NotReady",
    L["Stop Countdown"], L["Cancels a running pull timer."])

local countdownBtn = CreateActionButton("Countdown", 420,
    "common-icon-exit", "Interface\\Icons\\INV_Misc_PocketWatch_01",
    L["Start Countdown"], L["Starts a pull timer."])

-- Which countdown command actually exists depends on the client and on whether
-- DBM / BigWigs are loaded, so resolve it once at login rather than assuming
-- "/countdown" is always available.
local function CountdownMacroText(seconds)
    if _G.SLASH_COUNTDOWN1 or (SlashCmdList and SlashCmdList["COUNTDOWN"]) then
        return "/countdown " .. seconds
    elseif SlashCmdList and SlashCmdList["PULL"] then
        return "/pull " .. seconds          -- DBM / BigWigs
    elseif C_PartyInfo and C_PartyInfo.DoCountdown then
        return "/run C_PartyInfo.DoCountdown(" .. seconds .. ")"
    end
    return "/countdown " .. seconds          -- last resort, still the common case
end

local function ApplyActionMacros()
    if InCombatLockdown() then return end   -- SetAttribute on secure buttons
    local sv = SV()
    local seconds = (sv and tonumber(sv.countdownSeconds)) or 10
    readyCheckBtn:SetAttribute("macrotext", "/readycheck")
    countdownBtn:SetAttribute("macrotext", CountdownMacroText(seconds))
    stopCountdownBtn:SetAttribute("macrotext", CountdownMacroText(0))
end

-- Purely cosmetic dimming when you can't use these (the button stays clickable;
-- the game just ignores the command if you lack permission).
local function CanUseRaidTools()
    if not IsInGroup() then return false end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function UpdateActionButtonState()
    local usable = CanUseRaidTools()
    for _, btn in ipairs(actionButtons) do
        btn.icon:SetDesaturated(not usable)
        btn.icon:SetAlpha(usable and 1 or 0.35)
    end
end

-- =========================
-- Bar layout (1 row or 2 rows)
-- =========================
-- Everything on the bar is positioned from here rather than at creation time,
-- so switching between layouts is just a re-anchor pass.
--   1 row : [8 markers][CLEAR][ready][stop][countdown]      454 x 44
--   2 rows: [8 markers]  /  [CLEAR][ready][stop][countdown] 307 x 76
-- NOTE: these are protected frames, so moving them is illegal in combat -
-- the pass is deferred to PLAYER_REGEN_ENABLED if we're locked down.
local LAYOUT = {
    pad        = 8,
    markerSize = 32,
    markerStep = 37,
    clearW     = 50,
    clearH     = 24,
    actionSize = 26,
    actionGap  = 4,
    clearGap   = 6,
}

local layoutPending = false

local function GetRows()
    local sv = SV()
    local rows = sv and tonumber(sv.rows) or 1
    return (rows == 2) and 2 or 1
end

local function ApplyLayout()
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    layoutPending = false

    local Lo = LAYOUT
    local rows = GetRows()
    local markersRight = Lo.pad + (7 * Lo.markerStep) + Lo.markerSize   -- 299
    local actionsW = Lo.clearW + Lo.clearGap
        + (3 * Lo.actionSize) + (2 * Lo.actionGap)                      -- 142

    local function place(btn, x, y, w, h)
        btn:SetSize(w, h)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", picker, "TOPLEFT", x, -y)
    end

    -- markers always form the top row
    for i = 1, 8 do
        place(markerButtons[i],
            Lo.pad + ((i - 1) * Lo.markerStep), Lo.pad - 2,
            Lo.markerSize, Lo.markerSize)
    end

    local rowTop = Lo.pad - 2 + Lo.markerSize + Lo.clearGap   -- top of row 2
    local startX, clearY, actionY, width, height

    if rows == 2 then
        width   = markersRight + Lo.pad
        startX  = math.floor((width - actionsW) / 2)          -- centre row 2
        clearY  = rowTop + math.floor((Lo.actionSize - Lo.clearH) / 2)
        actionY = rowTop
        height  = rowTop + Lo.actionSize + Lo.pad - 2
    else
        width   = markersRight + Lo.clearGap - 1 + actionsW + Lo.pad
        startX  = markersRight + Lo.clearGap - 1
        clearY  = math.floor((44 - Lo.clearH) / 2)
        actionY = math.floor((44 - Lo.actionSize) / 2)
        height  = 44
    end

    place(clearAllBtn, startX, clearY, Lo.clearW, Lo.clearH)
    local ax = startX + Lo.clearW + Lo.clearGap
    for i, btn in ipairs(actionButtons) do
        place(btn, ax, actionY, Lo.actionSize, Lo.actionSize)
        ax = ax + Lo.actionSize + Lo.actionGap
    end

    picker:SetSize(width, height)
end

local actionStateFrame = CreateFrame("Frame")
actionStateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
actionStateFrame:RegisterEvent("PARTY_LEADER_CHANGED")
actionStateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
actionStateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
actionStateFrame:SetScript("OnEvent", function(_, event)
    UpdateActionButtonState()
    if event == "PLAYER_REGEN_ENABLED" then
        ApplyActionMacros()   -- in case login happened while in combat
        if layoutPending then ApplyLayout() end
    end
end)

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

function WorldMarkerCyclerRaidPickerAPI.SetCountdownSeconds(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 1 or seconds > 60 then return false end
    EnsureSV()
    SV().countdownSeconds = math.floor(seconds)
    ApplyActionMacros()
    return true
end

function WorldMarkerCyclerRaidPickerAPI.GetCountdownSeconds()
    local sv = SV()
    return (sv and tonumber(sv.countdownSeconds)) or 10
end

-- Bar layout: 1 = single row, 2 = markers on top / buttons underneath
function WorldMarkerCyclerRaidPickerAPI.SetRows(rows)
    rows = (tonumber(rows) == 2) and 2 or 1
    EnsureSV()
    SV().rows = rows
    ApplyLayout()
    RestorePosition()
    return not InCombatLockdown()   -- false = queued until combat ends
end

function WorldMarkerCyclerRaidPickerAPI.GetRows()
    return GetRows()
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

-- /wmcrrows <1|2>: switch the bar between one row and two rows
SLASH_WMCRROWS1 = "/wmcrrows"
SlashCmdList["WMCRROWS"] = function(msg)
    local n = tonumber((msg or ""):match("%d"))
    if n ~= 1 and n ~= 2 then
        print("WorldMarkerCycler: usage /wmcrrows 1|2  (currently "
            .. WorldMarkerCyclerRaidPickerAPI.GetRows() .. ")")
        return
    end
    if WorldMarkerCyclerRaidPickerAPI.SetRows(n) then
        print("WorldMarkerCycler: marker bar set to " .. n .. " row(s).")
    else
        print("WorldMarkerCycler: layout will change when you leave combat.")
    end
end

-- /wmcpull <seconds>: change what the countdown button starts (default 10)
SLASH_WMCPULL1 = "/wmcpull"
SlashCmdList["WMCPULL"] = function(msg)
    local seconds = tonumber((msg or ""):match("%d+"))
    if InCombatLockdown() then
        print("WorldMarkerCycler: can't change the countdown length in combat.")
        return
    end
    if WorldMarkerCyclerRaidPickerAPI.SetCountdownSeconds(seconds) then
        print("WorldMarkerCycler: countdown button set to " .. seconds .. "s.")
    else
        print("WorldMarkerCycler: usage /wmcpull <1-60>  (currently "
            .. WorldMarkerCyclerRaidPickerAPI.GetCountdownSeconds() .. "s)")
    end
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
        -- resolve /countdown vs /pull vs C_PartyInfo now that other addons loaded
        ApplyActionMacros()
        UpdateActionButtonState()
        ApplyLayout()
        local sv = SV()
        if not sv or sv.shown ~= false then
            picker:SetAttribute("state-shown", "1")
        end
    end
end)
