--[[--------------------------------------------------------------------------
--  TomTom by Cladhaire <cladhaire@gmail.com>
--
--  All Rights Reserved
----------------------------------------------------------------------------]]

-- Player and cursor coordinates on the world map.

local addonName, addon = ...
local TomTom = addon
local L = addon.L
addon.private = addon.private or {}
local private = addon.private
local RoundCoords = private.RoundCoords
local module = {
    settingsKey = "mapcoords",
    defaults = {
        playerenable = true,
        playeraccuracy = 2,
        playeroffset = 0,
        cursorenable = true,
        cursoraccuracy = 2,
        cursoroffset = 0,
        throttle = 0.1,
    },
}
private.AddModule(module, "MapCoords")

local GetCurrentCursorPosition
local WorldMap_OnUpdate

private.AddSettingsSection{
    page = "worldmap", pageName = L["World Map"], pageOrder = 30, order = 30,
    settingsKey = "mapcoords",
    header = L["Player Coordinates"],
    feature = {name = L["Enable showing player coordinates"], path = "mapcoords.playerenable"},
    rows = {
        {type = "range", key = "playeraccuracy", name = L["Player coordinate accuracy"],
         tooltip = L["Coordinates can be displayed as simple XX, YY coordinate, or as more precise XX.XX, YY.YY.  This setting allows you to control that precision"],
         min = 0, max = 2, step = 1},
        {type = "range", key = "playeroffset", name = L["Player coordinate offset"],
         tooltip = L["Coordinates can be moved from the default location, this setting allows you to control that offset"],
         min = -16, max = 256, step = 1},
    },
}

private.AddSettingsSection{
    page = "worldmap", pageName = L["World Map"], pageOrder = 30, order = 40,
    settingsKey = "mapcoords",
    header = L["Cursor Coordinates"],
    feature = {name = L["Enable showing cursor coordinates"], path = "mapcoords.cursorenable"},
    rows = {
        {type = "range", key = "cursoraccuracy", name = L["Cursor coordinate accuracy"],
         tooltip = L["Coordinates can be displayed as simple XX, YY coordinate, or as more precise XX.XX, YY.YY.  This setting allows you to control that precision"],
         min = 0, max = 2, step = 1},
        {type = "range", key = "cursoroffset", name = L["Cursor coordinate offset"],
         tooltip = L["Coordinates can be moved from the default location, this setting allows you to control that offset"],
         min = -32, max = 128, step = 1},
    },
}

function TomTom:ShowHideWorldCoords()
    -- Bail out if we're not supposed to be showing this frame
    if self.profile.mapcoords.playerenable or self.db.profile.mapcoords.cursorenable then
        -- Create the frame if it doesn't exist
        -- Not on WorldMapFrame.BorderFrame: the small map of the classic
        -- clients hides it. BorderFrame covers WorldMapFrame on every
        -- client, so the anchors stay the same.
        -- No fixed strata: the maximized map of the classic clients goes to
        -- FULLSCREEN with a full-screen BlackoutFrame, which would cover a
        -- HIGH frame. The frame must follow the strata of the map.
        if not TomTomWorldFrame then
            TomTomWorldFrame = CreateFrame("Frame", "TomTomWorldFrame", WorldMapFrame)
            TomTomWorldFrame:SetFrameLevel(9000)
            TomTomWorldFrame:SetAllPoints(true)
            TomTomWorldFrame.Player = TomTomWorldFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            TomTomWorldFrame.Cursor = TomTomWorldFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            TomTomWorldFrame:SetScript("OnUpdate", WorldMap_OnUpdate)
        end

        TomTomWorldFrame.Player:ClearAllPoints()
        TomTomWorldFrame.Cursor:ClearAllPoints()
        TomTomWorldFrame.Player:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT",
                                         self.db.profile.mapcoords.playeroffset + 100, -6)
        TomTomWorldFrame.Cursor:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT",
                                         - self.db.profile.mapcoords.cursoroffset + -170, -6)

        TomTomWorldFrame.Player:Hide()
        TomTomWorldFrame.Cursor:Hide()

        if self.profile.mapcoords.playerenable then
            TomTomWorldFrame.Player:Show()
        end

        if self.profile.mapcoords.cursorenable then
            TomTomWorldFrame.Cursor:Show()
        end

        -- Show the frame
        TomTomWorldFrame:Show()
    elseif TomTomWorldFrame then
        TomTomWorldFrame:Hide()
    end
end

-- The module has two features (player and cursor), and no "enable" setting.
function module:IsEnabledInSettings()
    local settings = TomTom.db.profile.mapcoords
    return settings.playerenable or settings.cursorenable
end

function module:OnEnable()
    TomTom:ShowHideWorldCoords()
end

function module:OnDisable()
    if TomTomWorldFrame then
        TomTomWorldFrame:Hide()
    end
end

function module:OnSettingChanged()
    TomTom:ShowHideWorldCoords()
end

function module:OnProfileChanged()
    TomTom:ShowHideWorldCoords()
end

-- Original Code courtesy ckknight, modified for BFA by Ludovicus
function GetCurrentCursorPosition()
    if TomTom:IsGamepadUI() and WorldMapFrame.GetNormalizedGamepadCursorPosition then
        -- The gamepad function gives a clamped 0, 0, not nil, when the soft
        -- cursor does not show.
        if not (SoftCursor and SoftCursor:IsShown()) then
            return nil, nil
        end
        return WorldMapFrame:GetNormalizedGamepadCursorPosition()
    end

    -- GetNormalizedCursorPosition clamps to the map edge, so a mouse outside
    -- the map would show 0 or 100.
    local container = WorldMapFrame.ScrollContainer
    if container and not container:IsMouseOver() then
        return nil, nil
    end

    local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()

    if cx < 0 or cx > 1 or cy < 0 or cy > 1 then
        return nil, nil
    end

    return cx, cy
end
private.GetCurrentCursorPosition = GetCurrentCursorPosition

local coord_throttle = 0
function WorldMap_OnUpdate(self, elapsed)
	coord_throttle = coord_throttle + elapsed
	if coord_throttle <= TomTom.profile.mapcoords.throttle then
		return
	end

	coord_throttle = 0
    local x,y = TomTom:GetCurrentCoords()
    local opt = TomTom.db.profile

    if not x or not y then
        self.Player:SetText(L["Player: ---"])
    else
        self.Player:SetFormattedText(L["Player: %s"], RoundCoords(x, y, opt.mapcoords.playeraccuracy))
    end

    local cX, cY = GetCurrentCursorPosition()

    if not cX or not cY then
        self.Cursor:SetText(L["Cursor: ---"])
    else
        self.Cursor:SetFormattedText(L["Cursor: %s"], RoundCoords(cX, cY, opt.mapcoords.cursoraccuracy))
    end
end
