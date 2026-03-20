-- ===================================================================
-- ArcUI_FreeTrialPrank.lua
-- One-time "Free Trial Expired" prank per account
-- Shows once EVER, then never again. Just for laughs.
-- ===================================================================

local ADDON_NAME, ns = ...

-- ===================================================================
-- RICKROLL SOUND
-- Drop your .ogg file at: Interface/AddOns/ArcUI/Sounds/rickroll.ogg
-- A 5-10 second clip works best. Must be .ogg format.
-- ===================================================================
local RICKROLL_SOUND = "Interface\\AddOns\\ArcUI\\Sounds\\Voicy_Rick-Astley-Never-Gonna-Give-You-Up-_Video_.ogg"

-- ===================================================================
-- PRANK STATE
-- ===================================================================
local prankFrame = nil
local PRANK_DELAY = 1.5 -- seconds after login before showing

-- ===================================================================
-- CREATE THE FAKE "TRIAL EXPIRED" POPUP
-- ===================================================================
local function CreatePrankFrame()
    if prankFrame then return prankFrame end

    local f = CreateFrame("Frame", "ArcUI_FreeTrialAlert", UIParent, "BackdropTemplate")
    f:SetSize(420, 220)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(900)
    f:EnableMouse(true)
    f:Hide()

    -- Serious-looking dark backdrop
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 12, bottom = 10 },
    })

    -- Icon (padlock - "locked out" vibe)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(42, 50)
    icon:SetPoint("TOP", 0, -14)
    -- Try atlas first, fall back to texture+texcoord if atlas unavailable
    if not pcall(function() icon:SetAtlas("UI-CharacterCreate-PadLock") end) or icon:GetAtlas() == "" then
        icon:SetTexture("Interface\\Glues\\CharacterCreate\\CharacterCreateClassTrial")
        icon:SetTexCoord(0.23046875, 0.4765625, 0.3984375, 0.9921875)
    end
    f.icon = icon

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -4)
    title:SetText("|cffff3333Trial Expired|r")
    title:SetTextColor(1, 0.3, 0.3)
    f.title = title

    -- Body text
    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOP", title, "BOTTOM", 0, -8)
    body:SetWidth(360)
    body:SetJustifyH("CENTER")
    body:SetText("Your free trial of |cff00ccffArcUI|r has expired.\n\nTo continue using ArcUI, please click below\nto complete the next steps.")
    f.body = body

    -- "Next Steps" button (the bait)
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(180, 30)
    btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
    btn:SetText("Click Here for Next Steps")
    f.actionBtn = btn

    -- ===============================================================
    -- PHASE 2: The reveal
    -- ===============================================================
    local confettiColors = {
        { 1, 0.84, 0 },    -- gold
        { 0, 0.8, 1 },     -- cyan
        { 1, 0.4, 0.7 },   -- pink
        { 0.4, 1, 0.4 },   -- green
        { 1, 0.6, 0.2 },   -- orange
        { 0.7, 0.4, 1 },   -- purple
        { 1, 1, 0.3 },     -- yellow
        { 1, 0.2, 0.2 },   -- red
    }

    local function SpawnConfetti(parent, count)
        count = count or 20
        for i = 1, count do
            C_Timer.After(i * 0.04, function()
                if not parent:IsShown() then return end
                local spark = parent:CreateTexture(nil, "OVERLAY")
                spark:SetSize(math.random(6, 16), math.random(6, 16))
                spark:SetTexture("Interface\\Cooldown\\star4")
                local c = confettiColors[math.random(#confettiColors)]
                spark:SetVertexColor(c[1], c[2], c[3], 1)

                local startX = math.random(-200, 200)
                local startY = math.random(30, 100)
                spark:SetPoint("CENTER", parent, "CENTER", startX, startY)

                -- Float down and fade
                local ag = spark:CreateAnimationGroup()
                local move = ag:CreateAnimation("Translation")
                move:SetOffset(math.random(-60, 60), math.random(-140, -70))
                move:SetDuration(math.random(12, 22) / 10) -- 1.2 to 2.2 seconds
                move:SetSmoothing("OUT")

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(1)
                fade:SetToAlpha(0)
                fade:SetStartDelay(0.6)
                fade:SetDuration(1.0)

                ag:SetScript("OnFinished", function()
                    spark:Hide()
                    spark:ClearAllPoints()
                end)
                ag:Play()
            end)
        end
    end

    local rickrollSoundHandle = nil

    local function StopRickroll()
        if rickrollSoundHandle then
            StopSound(rickrollSoundHandle)
            rickrollSoundHandle = nil
        end
    end

    local revealed = false

    local function ShowReveal()
        if revealed then return end
        revealed = true

        -- Play rickroll (store handle to stop later)
        local _, handle = PlaySoundFile(RICKROLL_SOUND, "Master")
        rickrollSoundHandle = handle

        -- Hide the icon to make room for text
        icon:Hide()

        -- Center text in the frame
        title:ClearAllPoints()
        title:SetPoint("CENTER", f, "CENTER", 0, 55)

        -- Update text
        title:SetText("|cff00ff00Just Kidding!|r")
        title:SetTextColor(0, 1, 0.5)

        body:SetText("|cff00ccffArcUI|r is and always will be |cff00ff00100% free|r.\n\nThank you for downloading the addon!\n\nHope you enjoy |cffcc80ffMidnight|r!")

        -- Resize frame a bit
        f:SetSize(420, 200)

        -- Change button to dismiss
        btn:SetText("Thanks")
        btn:SetScript("OnClick", function()
            StopRickroll()
            f:Hide()
        end)

        -- Confetti party! Multiple waves over several seconds
        SpawnConfetti(f, 25)
        C_Timer.After(0.5, function() SpawnConfetti(f, 20) end)
        C_Timer.After(1.2, function() SpawnConfetti(f, 25) end)
        C_Timer.After(2.0, function() SpawnConfetti(f, 20) end)
        C_Timer.After(3.0, function() SpawnConfetti(f, 25) end)
        C_Timer.After(4.2, function() SpawnConfetti(f, 20) end)
        C_Timer.After(5.5, function() SpawnConfetti(f, 15) end)
        C_Timer.After(6.8, function() SpawnConfetti(f, 15) end)
        C_Timer.After(8.0, function() SpawnConfetti(f, 10) end)
    end

    btn:SetScript("OnClick", function()
        ShowReveal()
    end)

    -- Track reveal state for ESC behavior

    -- ESC: first press triggers reveal, second press dismisses
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if not revealed then
                ShowReveal()
            else
                StopRickroll()
                self:Hide()
            end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    prankFrame = f
    return f
end

-- ===================================================================
-- TRIGGER LOGIC - ONCE PER ACCOUNT, EVER
-- ===================================================================
local function TryShowPrank()
    -- Safety: need db
    if not ns.db or not ns.db.global then return end

    -- Already shown? Never again.
    if ns.db.global.freeTrialPrankShown then return end

    -- Mark as shown IMMEDIATELY (even if they /reload before clicking)
    ns.db.global.freeTrialPrankShown = true

    -- Small delay so it feels like it "detected" something after login
    C_Timer.After(PRANK_DELAY, function()
        if InCombatLockdown() then
            -- If in combat, wait for combat to end
            local combatWaiter = CreateFrame("Frame")
            combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            combatWaiter:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                C_Timer.After(1, function()
                    local frame = CreatePrankFrame()
                    frame:Show()
                end)
            end)
        else
            local frame = CreatePrankFrame()
            frame:Show()
        end
    end)
end

-- ===================================================================
-- INITIALIZATION
-- Hook into ArcUI's load sequence
-- ===================================================================

-- Method 1: If ArcUI fires a callback after db is ready
if ns.RegisterCallback then
    -- Try hooking ArcUI's init
    C_Timer.After(0, function()
        if ns.db and ns.db.global then
            TryShowPrank()
        end
    end)
end

-- Method 2: Fallback event-based init
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Give AceDB a moment to initialize
    C_Timer.After(1, function()
        TryShowPrank()
    end)
end)

-- ===================================================================
-- SLASH COMMAND: Reset the prank (for testing)
-- /arcprankreset
-- ===================================================================
SLASH_ARCUIPRANKRESET1 = "/arcprankreset"
SlashCmdList["ARCUIPRANKRESET"] = function()
    if ns.db and ns.db.global then
        ns.db.global.freeTrialPrankShown = nil
        print("|cff00ccff[ArcUI]|r Prank reset. It will show again on next login/reload.")
    else
        print("|cff00ccff[ArcUI]|r DB not ready yet.")
    end
end