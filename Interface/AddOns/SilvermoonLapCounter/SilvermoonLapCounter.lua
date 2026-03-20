-- Silvermoon Lap Counter
-- Counts laps around Silvermoon City using 4 checkpoints

local ADDON_NAME = "SilvermoonLapCounter"
local SILVERMOON_MAP_ID = 2393

local defaultCheckpoints = {
    [1] = { name = "North", x1 = 0.4565, y1 = 0.6221, x2 = 0.4566, y2 = 0.6608 },
    [2] = { name = "East",  x1 = 0.4811, y1 = 0.7034, x2 = 0.5221, y2 = 0.7034 },
    [3] = { name = "South", x1 = 0.4566, y1 = 0.7474, x2 = 0.4568, y2 = 0.7970 },
    [4] = { name = "West",  x1 = 0.3950, y1 = 0.7034, x2 = 0.4277, y2 = 0.7035 },
}

local cpLabels = { "N", "E", "S", "W" }

local checkpointsVisited = { false, false, false, false }
local insideCheckpoint = { false, false, false, false }
local lapStartTime = nil
local ticker = nil
local frame = nil
local lapCountText = nil
local lastLapText = nil
local bestLapText = nil
local cpIndicators = {}  -- each: { dot = Texture, label = FontString }
local initialized = false
local manualVisibility = nil  -- nil = auto, true = force show, false = force hide
local statsFrame = nil
local statsLines = {}
local HideTracker  -- forward declaration

-- ============================================================
-- Helpers
-- ============================================================

local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function IsInZone(px, py, cp)
    local minX = math.min(cp.x1, cp.x2)
    local maxX = math.max(cp.x1, cp.x2)
    local minY = math.min(cp.y1, cp.y2)
    local maxY = math.max(cp.y1, cp.y2)
    if maxX - minX < 0.02 then
        local mid = (minX + maxX) / 2
        minX = mid - 0.01
        maxX = mid + 0.01
    end
    if maxY - minY < 0.02 then
        local mid = (minY + maxY) / 2
        minY = mid - 0.01
        maxY = mid + 0.01
    end
    return px >= minX and px <= maxX and py >= minY and py <= maxY
end

-- Compute center and radius of the checkpoint circle
local areaCenter = { x = 0, y = 0 }
local areaRadius = 0
do
    local cx, cy = 0, 0
    for i = 1, 4 do
        local cp = defaultCheckpoints[i]
        cx = cx + (cp.x1 + cp.x2) / 2
        cy = cy + (cp.y1 + cp.y2) / 2
    end
    areaCenter.x = cx / 4
    areaCenter.y = cy / 4
    for i = 1, 4 do
        local cp = defaultCheckpoints[i]
        local mx = (cp.x1 + cp.x2) / 2
        local my = (cp.y1 + cp.y2) / 2
        local dx = mx - areaCenter.x
        local dy = my - areaCenter.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > areaRadius then areaRadius = dist end
    end
    areaRadius = areaRadius + 0.05 -- margin
end

local function IsInLapArea(px, py)
    local dx = px - areaCenter.x
    local dy = py - areaCenter.y
    return math.sqrt(dx * dx + dy * dy) <= areaRadius
end

local function IsInSilvermoon()
    local mapID = C_Map.GetBestMapForUnit("player")
    return mapID == SILVERMOON_MAP_ID
end

local function Print(msg)
    print("|cff00ccff[SLC]|r " .. msg)
end

-- chatMode: nil/"best" = only new best times, "all" = everything, "off" = nothing
local function GetChatMode()
    return SilvermoonLapCounterDB and SilvermoonLapCounterDB.chatMode or "best"
end

local function PlaySLC(soundID)
    if SilvermoonLapCounterDB and SilvermoonLapCounterDB.sound ~= false then
        PlaySound(soundID)
    end
end

local function FormatTime(seconds)
    if not seconds then return "--:--" end
    local mins = math.floor(seconds / 60)
    local secs = seconds - mins * 60
    return string.format("%d:%05.2f", mins, secs)
end

local function GetCurrentCharData()
    local key = GetCharKey()
    if not SilvermoonLapCounterDB.characters[key] then
        SilvermoonLapCounterDB.characters[key] = { lapCount = 0 }
    end
    local data = SilvermoonLapCounterDB.characters[key]
    -- Keep class and realm up to date
    local _, classToken = UnitClass("player")
    data.class = classToken
    data.realm = GetRealmName()
    return data
end

-- ============================================================
-- UI
-- ============================================================

local function UpdateIndicator(index)
    local cp = cpIndicators[index]
    if not cp then return end
    if checkpointsVisited[index] then
        cp.dot:SetColorTexture(0, 0.8, 0, 1)
        cp.label:SetTextColor(0, 0.8, 0, 1)
    else
        cp.dot:SetColorTexture(0.3, 0.3, 0.3, 1)
        cp.label:SetTextColor(0.5, 0.5, 0.5, 1)
    end
end

local function UpdateUI()
    if not frame or not initialized then return end
    local data = GetCurrentCharData()
    lapCountText:SetText(tostring(data.lapCount))
    lastLapText:SetText("Last: " .. FormatTime(data.lastLapTime))
    if data.bestLapTime then
        bestLapText:SetText("Best: |cffffd700" .. FormatTime(data.bestLapTime) .. "|r")
    else
        bestLapText:SetText("Best: --:--")
    end
    for i = 1, 4 do
        UpdateIndicator(i)
    end
end

local function UpdateStatsFrame()
    if not statsFrame or not statsFrame:IsShown() then return end
    local sorted = {}
    if SilvermoonLapCounterDB.characters then
        for key, charData in pairs(SilvermoonLapCounterDB.characters) do
            if charData.lapCount and charData.lapCount > 0 then
                table.insert(sorted, { key = key, data = charData })
            end
        end
    end
    table.sort(sorted, function(a, b)
        local aTime = a.data.bestLapTime or 9999
        local bTime = b.data.bestLapTime or 9999
        return aTime < bTime
    end)
    local idx = 1
    for _, entry in ipairs(sorted) do
        if not statsLines[idx] then
            statsLines[idx] = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        end
        local name = entry.key:match("^(.-)%-") or entry.key
        local realm = entry.data.realm or entry.key:match("%-(.+)$") or ""
        local laps = tostring(entry.data.lapCount)
        local best = FormatTime(entry.data.bestLapTime)
        local color = "ffcccccc"
        if entry.data.class and RAID_CLASS_COLORS[entry.data.class] then
            local c = RAID_CLASS_COLORS[entry.data.class]
            color = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        end
        local bestDate = entry.data.bestLapDate and ("  |cff666666" .. entry.data.bestLapDate .. "|r") or ""
        statsLines[idx]:SetText("|c" .. color .. name .. "|r |cff666666" .. realm .. "|r  " .. laps .. " laps  best " .. best .. bestDate)
        statsLines[idx]:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", 12, -28 - (idx - 1) * 15)
        statsLines[idx]:Show()
        idx = idx + 1
    end
    if idx == 1 then
        if not statsLines[1] then
            statsLines[1] = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        end
        statsLines[1]:SetText("|cff888888No laps recorded yet.|r")
        statsLines[1]:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", 12, -28)
        statsLines[1]:Show()
        idx = 2
    end
    for j = idx, #statsLines do
        statsLines[j]:Hide()
    end
    statsFrame:SetHeight(28 + (idx - 1) * 15 + 10)
end

local function ToggleStatsFrame()
    if not statsFrame then
        statsFrame = CreateFrame("Frame", "SilvermoonLapCounterStats", UIParent, "BackdropTemplate")
        statsFrame:SetSize(340, 60)
        statsFrame:SetPoint("LEFT", frame, "RIGHT", 4, 0)
        statsFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        statsFrame:SetBackdropColor(0, 0, 0, 0.85)
        statsFrame:SetMovable(true)
        statsFrame:EnableMouse(true)
        statsFrame:RegisterForDrag("LeftButton")
        statsFrame:SetScript("OnDragStart", statsFrame.StartMoving)
        statsFrame:SetScript("OnDragStop", statsFrame.StopMovingOrSizing)
        statsFrame:SetClampedToScreen(true)

        local title = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOP", 0, -8)
        title:SetText("Leaderboard")
        title:SetTextColor(1, 0.84, 0, 1)

        local closeBtn = CreateFrame("Button", nil, statsFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetSize(20, 20)
        closeBtn:SetScript("OnClick", function() statsFrame:Hide() end)
        statsFrame:Hide()
    end

    if statsFrame:IsShown() then
        statsFrame:Hide()
    else
        statsFrame:Show()
        UpdateStatsFrame()
    end
end

local function CreateMainFrame()
    frame = CreateFrame("Frame", "SilvermoonLapCounterFrame", UIParent, "BackdropTemplate")
    frame:SetSize(160, 95)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, xOfs, yOfs = self:GetPoint()
        SilvermoonLapCounterDB.position = { point = point, relPoint = relPoint, x = xOfs, y = yOfs }
    end)
    frame:SetClampedToScreen(true)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Silvermoon Lap Counter")
    title:SetTextColor(1, 0.84, 0, 1)

    lapCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    lapCountText:SetPoint("TOP", 0, -20)
    lapCountText:SetText("0")

    lastLapText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lastLapText:SetPoint("TOP", 0, -42)
    lastLapText:SetText("Last: --:--")

    bestLapText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bestLapText:SetPoint("TOP", 0, -54)
    bestLapText:SetText("Best: --:--")

    -- Checkpoint indicators: N → E → S → W
    local startX = -48
    for i = 1, 4 do
        local dot = frame:CreateTexture(nil, "OVERLAY")
        dot:SetSize(10, 10)
        dot:SetPoint("TOP", frame, "TOP", startX + (i - 1) * 32, -70)
        dot:SetColorTexture(0.3, 0.3, 0.3, 1)

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", dot, "RIGHT", 2, 0)
        label:SetText(cpLabels[i])
        label:SetTextColor(0.5, 0.5, 0.5, 1)

        cpIndicators[i] = { dot = dot, label = label }
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    closeBtn:SetSize(20, 20)
    closeBtn:SetScript("OnClick", function() HideTracker() end)

    -- Stats button (leaderboard)
    local statsBtn = CreateFrame("Button", nil, frame)
    statsBtn:SetSize(18, 18)
    statsBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    statsBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    statsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    statsBtn:SetScript("OnClick", ToggleStatsFrame)
    statsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Leaderboard")
        GameTooltip:Show()
    end)
    statsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if SilvermoonLapCounterDB.position then
        local p = SilvermoonLapCounterDB.position
        frame:ClearAllPoints()
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    end
end

-- ============================================================
-- Lap logic
-- ============================================================

local function CheckPosition()
    if not IsInSilvermoon() then return end
    if not frame or not frame:IsShown() then return end

    local pos = C_Map.GetPlayerMapPosition(SILVERMOON_MAP_ID, "player")
    if not pos then return end
    local px, py = pos:GetXY()

    -- Reset if player left the lap area
    if not IsInLapArea(px, py) then
        if lapStartTime or checkpointsVisited[1] or checkpointsVisited[2] or checkpointsVisited[3] or checkpointsVisited[4] then
            checkpointsVisited = { false, false, false, false }
            insideCheckpoint = { false, false, false, false }
            lapStartTime = nil
            UpdateUI()
        end
        return
    end

    for i = 1, 4 do
        local cp = defaultCheckpoints[i]
        local inZone = IsInZone(px, py, cp)
        if inZone and not insideCheckpoint[i] and not checkpointsVisited[i] then
            checkpointsVisited[i] = true
            if not lapStartTime then
                lapStartTime = GetTime()
            end
            if GetChatMode() == "all" then
                Print("Checkpoint " .. i .. " (" .. cp.name .. ")")
            end
            UpdateUI()
        end
        insideCheckpoint[i] = inZone
    end

    if checkpointsVisited[1] and checkpointsVisited[2] and checkpointsVisited[3] and checkpointsVisited[4] then
        local data = GetCurrentCharData()
        local lapTime = GetTime() - lapStartTime
        local now = date("%Y-%m-%d %H:%M")
        data.lapCount = data.lapCount + 1
        data.lastLapTime = lapTime
        data.lastLapDate = now
        if not data.firstLapDate then
            data.firstLapDate = now
        end
        if not data.bestLapTime or lapTime < data.bestLapTime then
            data.bestLapTime = lapTime
            data.bestLapDate = now
            PlaySLC(5913903)
            local mode = GetChatMode()
            if mode == "best" or mode == "all" then
                Print("Lap " .. data.lapCount .. "! NEW BEST: " .. FormatTime(lapTime))
            end
            if SilvermoonLapCounterDB.guildAnnounce and data.lapCount > 1 and IsInGuild() then
                SendChatMessage(
                    "New Silvermoon lap record: " .. FormatTime(lapTime) .. " (Lap " .. data.lapCount .. ")",
                    "GUILD"
                )
            end
        else
            PlaySLC(231913)
            if GetChatMode() == "all" then
                Print("Lap " .. data.lapCount .. ": " .. FormatTime(lapTime))
            end
        end
        -- Milestone announcements
        if SilvermoonLapCounterDB.guildAnnounce and IsInGuild() then
            local count = data.lapCount
            if count == 100 or count == 1000 or count == 10000 or count == 100000 then
                SendChatMessage(
                    "Just completed " .. count .. " laps around Silvermoon City!",
                    "GUILD"
                )
            end
        end

        checkpointsVisited = { false, false, false, false }
        -- Don't reset insideCheckpoint here: player is still standing in the
        -- last checkpoint zone. Keeping it true prevents ghost-registration
        -- of that checkpoint on the very next tick for the new lap.
        lapStartTime = nil
        UpdateUI()
        UpdateStatsFrame()
    end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, CheckPosition)
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function OnZoneChanged()
    if IsInSilvermoon() then
        manualVisibility = nil  -- reset auto-visibility on zone enter
        StartTicker()
        if frame then frame:Show() end
    else
        StopTicker()
        if frame and manualVisibility ~= true then frame:Hide() end
    end
end

-- ============================================================
-- Slash commands
-- ============================================================

HideTracker = function()
    manualVisibility = false
    checkpointsVisited = { false, false, false, false }
    insideCheckpoint = { false, false, false, false }
    lapStartTime = nil
    if frame then frame:Hide() end
    UpdateUI()
    Print("Tracker hidden. Type |cff00ff00/slc show|r to re-enable.")
end

local function HandleSlashCommand(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "show" then
        manualVisibility = true
        frame:Show()
    elseif cmd == "hide" then
        HideTracker()
    elseif cmd == "reset" then
        local data = GetCurrentCharData()
        data.lapCount = 0
        data.lastLapTime = nil
        data.bestLapTime = nil
        checkpointsVisited = { false, false, false, false }
        insideCheckpoint = { false, false, false, false }
        lapStartTime = nil
        UpdateUI()
        Print("Lap counter reset.")
    elseif cmd == "chat" then
        local mode = arg ~= "" and arg:lower() or nil
        if mode == "all" then
            SilvermoonLapCounterDB.chatMode = "all"
            Print("Chat: all (checkpoints + laps)")
        elseif mode == "off" then
            SilvermoonLapCounterDB.chatMode = "off"
            Print("Chat: off")
        else
            SilvermoonLapCounterDB.chatMode = "best"
            Print("Chat: best times only (default)")
        end
    elseif cmd == "guild" then
        SilvermoonLapCounterDB.guildAnnounce = not SilvermoonLapCounterDB.guildAnnounce
        Print("Guild announce: " .. (SilvermoonLapCounterDB.guildAnnounce and "ON" or "OFF"))
    elseif cmd == "sound" then
        if SilvermoonLapCounterDB.sound == false then
            SilvermoonLapCounterDB.sound = true
        else
            SilvermoonLapCounterDB.sound = false
        end
        Print("Sounds: " .. (SilvermoonLapCounterDB.sound ~= false and "ON" or "OFF"))
    elseif cmd == "status" then
        local data = GetCurrentCharData()
        Print(GetCharKey() .. ": " .. data.lapCount .. " laps")
        Print("Last: " .. FormatTime(data.lastLapTime) .. (data.lastLapDate and ("  (" .. data.lastLapDate .. ")") or ""))
        Print("Best: " .. FormatTime(data.bestLapTime) .. (data.bestLapDate and ("  (" .. data.bestLapDate .. ")") or ""))
        if data.firstLapDate then
            Print("First lap: " .. data.firstLapDate)
        end
        for i = 1, 4 do
            local cp = defaultCheckpoints[i]
            local visited = checkpointsVisited[i] and "|cff00ff00yes|r" or "|cffff0000no|r"
            Print(string.format("  Checkpoint %d: %s: %s", i, cp.name, visited))
        end
        if SilvermoonLapCounterDB.characters then
            local currentKey = GetCharKey()
            for key, charData in pairs(SilvermoonLapCounterDB.characters) do
                if key ~= currentKey and charData.lapCount > 0 then
                    Print(string.format("  %s: %d laps, best %s", key, charData.lapCount, FormatTime(charData.bestLapTime)))
                end
            end
        end
    else
        Print("|cffffd700Silvermoon Lap Counter|r")
        Print("  /slc |cff00ff00show|r — Show tracker (anywhere)")
        Print("  /slc |cff00ff00hide|r — Hide tracker (anywhere)")
        Print("  /slc |cff00ff00reset|r — Reset laps for current character")
        Print("  /slc |cff00ff00status|r — Show stats in chat")
        Print("  /slc |cff00ff00guild|r — Toggle guild announce on/off")
        Print("  /slc |cff00ff00sound|r — Toggle sounds on/off")
        Print("  /slc |cff00ff00chat|r — Best times only (default)")
        Print("  /slc |cff00ff00chat all|r — Show checkpoints + all laps")
        Print("  /slc |cff00ff00chat off|r — No chat output")
    end
end

SLASH_SLC1 = "/slc"
SLASH_SLC2 = "/lapcounter"
SlashCmdList["SLC"] = HandleSlashCommand

-- ============================================================
-- Events
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if not SilvermoonLapCounterDB then
            SilvermoonLapCounterDB = {}
        end
        if not SilvermoonLapCounterDB.characters then
            SilvermoonLapCounterDB.characters = {}
        end
        CreateMainFrame()

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not initialized then
            initialized = true
            -- Migrate old per-account data to per-character
            if SilvermoonLapCounterDB.lapCount ~= nil then
                local key = GetCharKey()
                if not SilvermoonLapCounterDB.characters[key] then
                    SilvermoonLapCounterDB.characters[key] = {}
                end
                local data = SilvermoonLapCounterDB.characters[key]
                data.lapCount = SilvermoonLapCounterDB.lapCount
                data.lastLapTime = SilvermoonLapCounterDB.lastLapTime
                data.bestLapTime = SilvermoonLapCounterDB.bestLapTime
                SilvermoonLapCounterDB.lapCount = nil
                SilvermoonLapCounterDB.lastLapTime = nil
                SilvermoonLapCounterDB.bestLapTime = nil
            end
            UpdateUI()
        end
        OnZoneChanged()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        OnZoneChanged()
    end
end)
