---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("Einstellungen ausschließlich via Bearbeitungsmodus: Escape > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Ladebedingung: Spielbereich"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Offene Welt",
	[Private.Enum.ContentType.Delve] = "Tiefen",
	[Private.Enum.ContentType.Dungeon] = "Instanz",
	[Private.Enum.ContentType.Raid] = "Schlachtzug",
	[Private.Enum.ContentType.Arena] = "Arena",
	[Private.Enum.ContentType.Battleground] = "Schlachtfeld",
}

L.Settings.LoadConditionRoleLabel = "Load on Role"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Heiler",
	[Private.Enum.Role.Tank] = "Panzer",
	[Private.Enum.Role.Damager] = "Schadensverursacher",
}

L.Settings.FontFlagsLabel = "Schriftoptionen"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Umriss",
	[Private.Enum.FontFlags.SHADOW] = "Schatten",
}

L.Settings.SecondaryFontScaleLabel = "Sekundärtextskalierung"
L.Settings.SecondaryFontScaleTooltip =
	"Kontrolliert die Schriftgröße des anvisierten Spielers & unterbrechenden Spielernamen in Relation zur allgemeinen Schriftgröße."

L.Settings.FrameWidthLabel = "Breite"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Höhe"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Deckkraft"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Versatz X-Achse"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Versatz Y-Achse"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Importieren"
L.Settings.Export = "Exportieren"

L.Settings.ColorUninterruptibleLabel = "Ununterbrechbar"

L.Settings.ColorInterruptibleCanInterruptLabel = "Unterbrechbar & Kann unterbrechen"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Ununterbrechbar & Kann nicht unterbrechen"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"Wenn deine Spezialisierung keinen Unterbrechungszauber hat, du ihn nicht talentiert hast oder deine Stufe zu niedrig ist."

L.Settings.ColorInterruptTickLabel = "Indikatorfarbe"

L.Settings.ColorGlowLabel = "Hervorhebungsanimationsfarbe"

L.Settings.FontSizeLabel = "Schriftgröße"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Indikatorbreite"
L.Settings.TickWidthTooltip = "0 verbirgt den Indikator."

L.Settings.FontLabel = "Schrift"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Textur"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Textpositionierung"
L.Settings.CustomTextPositionTooltip = "Kontrolliert die Position des Zielnamens und der Unterbrechungsquelle."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOMCENTER] = "Unten Mitte",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "Unten Links",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "Unten Rechts",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "Oben Links",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "Rechts",
}

L.Settings.IgnoreFriendliesTooltip =
	"Verhindert die Leiste einzublenden falls das Ziel freundlich oder unangreifbar ist. Deaktivieren für Testzwecke."

L.Settings.BackgroundOpacityLabel = "Hintergrunddeckkraft"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Außer-Reichweite Deckkraft"
L.Settings.OutOfRangeOpacityTooltip = "100% zum Deaktivieren."

L.Settings.PointLabel = "Punkt"
L.Settings.PointTooltip =
	"Erlaubt zusammen mit Versatz X-/Y-Achse granularere Positionierung im Gegensatz zu Drag & Drop."

L.Settings.InterruptSourceText = "Unterbrochen [%s]"

L.Settings.UnitLabel = "Einheit"
L.Settings.UnitTooltip =
	"Welche Einheit benutzt werden soll. Ja, dies ist ein Addon speziell für Fokuszauber.. und dennoch sind wir hier."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Fokus",
	[Private.Enum.Unit.Target] = "Ziel",
}

L.Settings.FeatureFlagLabel = "Features"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Zeige Symbol",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Zeige Zauberdauer",
	[Private.Enum.FeatureFlag.ShowBorder] = "Zeige Rahmen",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Wichtige Zauber hervorheben",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Zeige Zielmarkierung",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Zeige anvisierten Spielernamen",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Färbe Namen in Klassenfarbe ein",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Zeige unterbrechenden Spielernamen",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Färbe Namen in Klassenfarbe ein",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Text-zu-Sprache Erinnerung abspielen",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Freundliche Ziele ignorieren",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Kanalisierungszauberanimation leert statt füllt",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Nur anzeigen wenn unterbrechbar & kann unterbrechen",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Text-zu-Sprache bei Beginn eines Zaubers abspielen",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "'Features' links hat weitere Infos im Tooltip",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Anvisiertes Ziel",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Unterbrechungsquelle",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Toneinstellungen",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Weiteres",
}
L.Settings.CastStartText = "Wirkt"
L.Settings.CustomizeTTSOnCastStartButtonText = "Text-zu-Sprache bei Beginn eines Zaubers anpassen"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"Was wichtig und was nicht wichtig ist wird ausschließlich vom Spiel selbst kommuniziert."
		),
		CreateFeatureFlagTooltip(Private.Enum.FeatureFlag.UseTargetClassColor, "Kann Kontrastprobleme haben."),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Spielt 'Fokus' (oder 'Ziel') Text-zu-Sprache ab wenn die derzeitg beobachtete Einheit verschwindet, bspw. weil sie getötet wurde, zur Erinnerung ein neues Ziel zu wählen. Nur in Instanzen aktiv!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Spielt '%s' Text-zu-Sprache ab wenn die beobachtete Einheit anfängt zu wirken. Bedingungslos, kann nicht prüfen ob du unterbrechen kannst oder ob der Zauber unterbrechbar ist. Nur in Instanzen!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Leert die Leiste bei Kanalisierungszaubern wenn aktiv; füllt wenn inaktiv."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Achtung Heiler: effektiv deaktiviert diese Einstellung das Addon für alle Heiler bis auf Wiederherstellungsschamanen"
		),
	}, "\n\n")
end
