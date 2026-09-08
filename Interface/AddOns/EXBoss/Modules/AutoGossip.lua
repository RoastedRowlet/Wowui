---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.AutoGossip = ExBoss.AutoGossip or {}

local Mod = ExBoss.AutoGossip
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, k) return k end })

local C_GossipInfo = _G.C_GossipInfo
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local hooksecurefunc = _G.hooksecurefunc

local DEFAULTS = {
    enabled = true,
    academyBuff = true,
    caveCauldron = true,
    posRescue = true,
    npxBuff = true,
}

local PRESETS = {
    {
        key = "academyBuff",
        ids = { 107065, 107081, 107082, 107083, 107088 },
    },
    {
        key = "caveCauldron",
        ids = { 107387, 107428, 137387 },
    },
    {
        key = "posRescue",
        ids = { 138618, 136301, 136271, 136316, 136280, 136624 },
    },
    {
        key = "npxBuff",
        ids = { 137133 },
    },
}

local PRESET_BY_ID = {}
for _, preset in ipairs(PRESETS) do
    for _, optionID in ipairs(preset.ids) do
        PRESET_BY_ID[optionID] = preset.key
    end
end

local optionHookInstalled = false
local autoSelectScheduled = false
local lastHandledSignature = nil

local function EnsureDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.autoGossip = EXBOSS12S2.autoGossip or {}
    local db = EXBOSS12S2.autoGossip
    if db.enabled == nil then db.enabled = DEFAULTS.enabled end
    if db.academyBuff == nil then db.academyBuff = DEFAULTS.academyBuff end
    if db.caveCauldron == nil then db.caveCauldron = DEFAULTS.caveCauldron end
    if db.posRescue == nil then db.posRescue = DEFAULTS.posRescue end
    if db.npxBuff == nil then db.npxBuff = DEFAULTS.npxBuff end
    return db
end

local function IsEnabled()
    return EnsureDB().enabled == true
end

local function IsOptionEnabled(optionID)
    local presetKey = PRESET_BY_ID[tonumber(optionID) or 0]
    if not presetKey then
        return false
    end
    return EnsureDB()[presetKey] == true
end

local function GetStableOptionID(optionInfo)
    local optionID = optionInfo and tonumber(optionInfo.gossipOptionID)
    if optionID and optionID > 0 then
        return optionID
    end
    return nil
end

local function BuildOptionSignature(options)
    if type(options) ~= "table" or #options == 0 then
        return nil
    end

    local parts = {}
    for index, optionInfo in ipairs(options) do
        local orderIndex = optionInfo and tonumber(optionInfo.orderIndex) or index
        local optionID = GetStableOptionID(optionInfo) or 0
        local optionName = optionInfo and tostring(optionInfo.name or "") or ""
        parts[#parts + 1] = string.format("%d:%d:%s", orderIndex or index, optionID, optionName)
    end

    return table.concat(parts, "|")
end

local function TryAutoSelectCurrentOption()
    if not IsEnabled() then
        return
    end
    if not C_GossipInfo or type(C_GossipInfo.GetOptions) ~= "function" then
        return
    end

    local options = C_GossipInfo.GetOptions()
    if type(options) ~= "table" or #options == 0 then
        return
    end

    local signature = BuildOptionSignature(options)
    if not signature or signature == lastHandledSignature then
        return
    end

    for _, optionInfo in ipairs(options) do
        local optionID = GetStableOptionID(optionInfo)
        if optionID and IsOptionEnabled(optionID) then
            lastHandledSignature = signature
            if type(C_GossipInfo.SelectOption) == "function" then
                C_GossipInfo.SelectOption(optionID)
            elseif type(C_GossipInfo.SelectOptionByIndex) == "function" and optionInfo.orderIndex then
                C_GossipInfo.SelectOptionByIndex(optionInfo.orderIndex)
            end
            return
        end
    end
end

local function ScheduleAutoSelect()
    if autoSelectScheduled then
        return
    end

    autoSelectScheduled = true
    local function Runner()
        autoSelectScheduled = false
        TryAutoSelectCurrentOption()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Runner)
    else
        Runner()
    end
end

function Mod.NotifySettingsChanged()
    lastHandledSignature = nil
    ScheduleAutoSelect()
end

local function InstallOptionHook()
    if optionHookInstalled or type(_G.GossipOptionButtonMixin) ~= "table" then
        return
    end

    hooksecurefunc(_G.GossipOptionButtonMixin, "Setup", function()
        if IsEnabled() then
            ScheduleAutoSelect()
        end
    end)

    optionHookInstalled = true
end

local function TryInstallHooks()
    InstallOptionHook()
    return optionHookInstalled == true
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("GOSSIP_SHOW")
driver:RegisterEvent("GOSSIP_CLOSED")
driver:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_UIPanels_Game" then
        return
    end

    local installedNow = TryInstallHooks()
    if installedNow and (event == "ADDON_LOADED" or event == "PLAYER_LOGIN") then
        driver:UnregisterEvent("ADDON_LOADED")
        driver:UnregisterEvent("PLAYER_LOGIN")
    end

    if event == "GOSSIP_SHOW" then
        lastHandledSignature = nil
        ScheduleAutoSelect()
    elseif event == "GOSSIP_CLOSED" then
        lastHandledSignature = nil
    end
end)

if TryInstallHooks() then
    driver:UnregisterEvent("ADDON_LOADED")
    driver:UnregisterEvent("PLAYER_LOGIN")
end
