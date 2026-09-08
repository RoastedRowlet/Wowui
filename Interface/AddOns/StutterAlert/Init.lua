local _, ns = ...
local L = ns.L
local format = string.format

local Detector = ns.Detector
local Overlay  = ns.Overlay
local DB       = ns.DB

local combatStart = 0

local function applyEnabledState()
    if DB.settings.enabled then
        Detector:Enable()
    else
        Detector:Disable()
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "StutterAlert" then
            DB:Init()
        elseif DB.data then
            -- A load-on-demand addon appeared after we started; refresh the list
            -- so it can be attributed.
            Detector:RebuildAddonList()
        end

    elseif event == "PLAYER_LOGIN" then
        Overlay:Create()
        Detector:RebuildAddonList()
        applyEnabledState()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Loading screens spike for reasons that aren't anyone's addon.
        Detector:StartGrace()
        Detector:RebuildAddonList()

        -- Per-addon memory costs ~50 ms to read, so it is sampled HERE and
        -- nowhere else: we are inside the grace window we just started, where a
        -- long frame is expected and already excluded from detection. The
        -- sampler self-throttles, so rapid zoning will not pay the cost twice.
        Detector:SampleAddonMemory()

    elseif event == "PLAYER_REGEN_DISABLED" then
        combatStart = time()
        Overlay:SetCombat(true)

    elseif event == "PLAYER_REGEN_ENABLED" then
        Overlay:SetCombat(false)
        Overlay:ShowPullSummary(combatStart)
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local function printMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. L.ADDON_TITLE .. "|r: " .. msg)
end

-- Slash spelling -> stored value, and the stored value -> the line we print back.
local BANNER_ARG = { all = "ALL", summary = "SUMMARY", summaries = "SUMMARY", off = "OFF" }
local BANNER_DESC = {
    ALL     = "SLASH_BANNERS_ALL",
    SUMMARY = "SLASH_BANNERS_SUMMARY",
    OFF     = "SLASH_BANNERS_OFF",
}

local function handleSlash(input)
    input = input or ""
    local cmd, arg = input:lower():match("^%s*(%S*)%s*(%S*)")

    if cmd == "banners" then
        local mode = BANNER_ARG[arg]
        if mode then
            DB.settings.bannerMode = mode
            if mode ~= "ALL" then Overlay:ClearToasts() end
        end
        -- With no argument (or an unrecognised one) this just reports the
        -- current setting, which is also how the player discovers it.
        printMsg(format(L.SLASH_BANNERS, L[BANNER_DESC[DB.settings.bannerMode] or "SLASH_BANNERS_ALL"]))
        return
    end

    if cmd == "lock" then
        Overlay:SetLocked(true)
        printMsg(L.SLASH_LOCKED)
    elseif cmd == "unlock" then
        Overlay:SetLocked(false)
        printMsg(L.SLASH_UNLOCKED)
    elseif cmd == "reset" then
        Overlay:ResetPosition()
        Overlay:ResetExportPosition()
        printMsg(L.SLASH_RESET)
    elseif cmd == "report" then
        -- Unconditional way in, for when the button itself is the problem.
        Overlay:ShowExport()
    elseif cmd == "toggle" then
        DB.settings.enabled = not DB.settings.enabled
        applyEnabledState()
        printMsg(DB.settings.enabled and L.SLASH_ENABLED or L.SLASH_DISABLED)
    else
        printMsg(L.SLASH_USAGE_HEADER)
        printMsg(L.SLASH_USAGE_LOCK)
        printMsg(L.SLASH_USAGE_UNLOCK)
        printMsg(L.SLASH_USAGE_RESET)
        printMsg(L.SLASH_USAGE_REPORT)
        printMsg(L.SLASH_USAGE_BANNERS)
        printMsg(L.SLASH_USAGE_TOGGLE)
    end
end

SLASH_STUTTERALERT1 = "/sa"
SLASH_STUTTERALERT2 = "/stutteralert"
SlashCmdList["STUTTERALERT"] = handleSlash
