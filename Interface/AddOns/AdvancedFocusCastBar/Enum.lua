---@type string, AdvancedFocusCastBar
local addonName, Private = ...

---@class AdvancedFocusCastBarEnums
Private.Enum = {}

---@enum CustomEvents
Private.Enum.Events = {
	SETTING_CHANGED = "SETTING_CHANGED",
	EDIT_MODE_POSITION_CHANGED = "EDIT_MODE_POSITION_CHANGED",
}

---@enum ContentType
Private.Enum.ContentType = {
	OpenWorld = 1,
	Delve = 2,
	Dungeon = 3,
	Raid = 4,
	Arena = 5,
	Battleground = 6,
}

---@enum Role
Private.Enum.Role = {
	Healer = 1,
	Tank = 2,
	Damager = 3,
}

---@enum Point
Private.Enum.Point = {
	CENTER = "CENTER",
	TOP = "TOP",
	BOTTOM = "BOTTOM",
	LEFT = "LEFT",
	RIGHT = "RIGHT",
}

---@enum CustomTextsPosition
Private.Enum.CustomTextsPosition = {
	BOTTOMCENTER = "BOTTOMCENTER",
	BOTTOMLEFT = "BOTTOMLEFT",
	BOTTOMRIGHT = "BOTTOMRIGHT",
	TOPLEFT = "TOPLEFT",
	TOPRIGHT = "TOPRIGHT",
}

---@enum Setting
Private.Enum.Setting = {
	Width = 1,
	Height = 2,
	LoadConditionContentType = 3,
	LoadConditionRole = 4,
	Opacity = 5,
	Texture = 6,
	Point = 7,
	OffsetX = 8,
	OffsetY = 9,
	ColorUninterruptible = 10,
	ColorInterruptibleCanInterrupt = 11,
	ColorInterruptibleCannotInterrupt = 12,
	ColorInterruptTick = 13,
	Font = 14,
	FontSize = 15,
	BackgroundOpacity = 16,
	CustomTextsPosition = 17,
	TickWidth = 18,
	OutOfRangeOpacity = 19,
	FontFlags = 20,
	Unit = 21,
	FeatureFlag = 22,
	ColorGlow = 23,
	SecondaryFontScale = 24,
}

---@enum FontFlags
Private.Enum.FontFlags = {
	OUTLINE = "OUTLINE",
	SHADOW = "SHADOW",
}

---@enum Unit
Private.Enum.Unit = {
	Focus = "focus",
	Target = "target",
}

---@enum FeatureFlag
Private.Enum.FeatureFlag = {
	ShowIcon = 1,
	ShowCastTime = 2,
	ShowBorder = 3,
	ShowImportantSpellsGlow = 4,
	ShowTargetMarker = 5,
	ShowTargetName = 6,
	UseTargetClassColor = 7,
	ShowInterruptSource = 8,
	UseInterruptSourceClassColor = 9,
	PlayTargetingTTSReminder = 10,
	IgnoreFriendlies = 11,
	UnfillChannels = 12,
	HideWhenUninterruptible = 13,
	PlayTTSOnCastStart = 14,
}
