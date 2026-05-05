---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder = string.format("Settings are exclusively available via Escape > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Load in Content"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Open World",
	[Private.Enum.ContentType.Delve] = "Delves",
	[Private.Enum.ContentType.Dungeon] = "Dungeon",
	[Private.Enum.ContentType.Raid] = "Raid",
	[Private.Enum.ContentType.Arena] = "Arena",
	[Private.Enum.ContentType.Battleground] = "Battleground",
}

L.Settings.LoadConditionRoleLabel = "Load on Role"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Healer",
	[Private.Enum.Role.Tank] = "Tank",
	[Private.Enum.Role.Damager] = "DPS",
}

L.Settings.FontFlagsLabel = "Font Options"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Outline",
	[Private.Enum.FontFlags.SHADOW] = "Shadow",
}

L.Settings.SecondaryFontScaleLabel = "Secondary Font Scale"
L.Settings.SecondaryFontScaleTooltip =
	"Controls the ratio of Cast Target and Interrupt Source text in relation to the general font size."

L.Settings.FrameWidthLabel = "Width"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Height"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Opacity"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Offset X"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Offset Y"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Import"
L.Settings.Export = "Export"

L.Settings.ColorUninterruptibleLabel = "Uninterruptible"

L.Settings.ColorInterruptibleCanInterruptLabel = "Interruptible & Can Interrupt"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Interruptible & Cannot Interrupt"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"When you cannot interrupt because your spec has no interrupt, you haven't talented or it you're too low level."

L.Settings.ColorInterruptTickLabel = "Tick Color"

L.Settings.ColorGlowLabel = "Glow Color"

L.Settings.FontSizeLabel = "Font Size"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Tick Width"
L.Settings.TickWidthTooltip = "0 hides the tick."

L.Settings.FontLabel = "Font"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Texture"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Text Position"
L.Settings.CustomTextPositionTooltip = "Controls position of Target Name text as well as Interrupt Source text."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOMCENTER] = "Bottom Center",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "Bottom Left",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "Bottom Right",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "Top Left",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "Top Right",
}

L.Settings.IgnoreFriendliesTooltip =
	"Prevents showing the cast bar if the focus target is friendly or unattackable. Disable for testing purposes."

L.Settings.BackgroundOpacityLabel = "Background Opacity"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Out of Range Opacity"
L.Settings.OutOfRangeOpacityTooltip = "100% to disable."

L.Settings.PointLabel = "Point"
L.Settings.PointTooltip =
	"Together with Offset X / Offset Y, allows more granular positioning control in contrast to drag & drop."

L.Settings.InterruptSourceText = "Interrupted [%s]"

L.Settings.UnitLabel = "Unit"
L.Settings.UnitTooltip = "Which unit to use. Yes, this is a focus cast bar addon, yet here we are."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Focus",
	[Private.Enum.Unit.Target] = "Target",
}

L.Settings.FeatureFlagLabel = "Features"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Show Icon",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Show Cast Time",
	[Private.Enum.FeatureFlag.ShowBorder] = "Show Border",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Glow Important Spells",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Show Target Marker",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Show Targeted Player Name",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Show Target Class Color",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Show Interrupt Source",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Use Interrupt Source Color",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Play Targeting TTS Reminder",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Ignore Friendlies",
	[Private.Enum.FeatureFlag.UnfillChannels] = "(Un)Fill Channels",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Only show when interruptible & can interrupt",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Play TTS on Cast Start",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "For more info, hover 'Features' on the left",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Cast Target Settings",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Interrupt Source Settings",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Sound Settings",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Other",
}
L.Settings.CastStartText = "Cast"
L.Settings.CustomizeTTSOnCastStartButtonText = "Customize TTS On Cast Start Text"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"What's important and what isn't is declared by the game."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"Can have contrast problems depending on background and bar color."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Plays 'focus' (or 'target') text-to-speech when your current observed unit disappears as a reminder to pick a new one. Only in dungeons!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Plays '%s' text-to-speech when your observed unit starts casting. Unconditional, cannot verify whether you can interrupt or is interruptible. Only in dungeons!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Unfill the cast bar when active; fills it when inactive."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Warning for healers: this effectively disables the addon unless you're a Restoration Shaman."
		),
	}, "\n\n")
end
