---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("Les réglages sont disponibles exclusivement via Échap > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Charger dans le contenu"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Monde ouvert",
	[Private.Enum.ContentType.Delve] = "Gouffres",
	[Private.Enum.ContentType.Dungeon] = "Donjon",
	[Private.Enum.ContentType.Raid] = "Raid",
	[Private.Enum.ContentType.Arena] = "Arène",
	[Private.Enum.ContentType.Battleground] = "Champ de bataille",
}

L.Settings.LoadConditionRoleLabel = "Charger selon le rôle"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Soigneur",
	[Private.Enum.Role.Tank] = "Tank",
	[Private.Enum.Role.Damager] = "DPS",
}

L.Settings.FontFlagsLabel = "Options de police"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Contour",
	[Private.Enum.FontFlags.SHADOW] = "Ombre",
}

L.Settings.SecondaryFontScaleLabel = "Échelle de police secondaire"
L.Settings.SecondaryFontScaleTooltip =
	"Contrôle le ratio du texte de la cible et de la source d'interruption par rapport à la taille de police générale."

L.Settings.FrameWidthLabel = "Largeur"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Hauteur"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Opacité"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Décalage X"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Décalage Y"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Importer"
L.Settings.Export = "Exporter"

L.Settings.ColorUninterruptibleLabel = "Ininterruptible"

L.Settings.ColorInterruptibleCanInterruptLabel = "Interruptible & Peut interrompre"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Interruptible & Ne peut pas interrompre"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"Lorsque vous ne pouvez pas interrompre parce que votre spécialisation n'a pas d'interruption, que vous ne l'avez pas talentée ou que votre niveau est trop bas."

L.Settings.ColorInterruptTickLabel = "Couleur du repère"

L.Settings.ColorGlowLabel = "Couleur de la lueur"

L.Settings.FontSizeLabel = "Taille de police"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Largeur du repère"
L.Settings.TickWidthTooltip = "0 masque le repère."

L.Settings.FontLabel = "Police"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Texture"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Position du texte"
L.Settings.CustomTextPositionTooltip =
	"Contrôle la position du nom de la cible ainsi que du texte de la source d'interruption."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "En bas au centre",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "En bas à gauche",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "En bas à droite",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "En haut à gauche",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "En haut à droite",
}

L.Settings.IgnoreFriendliesTooltip =
	"Empêche l'affichage de la barre d'incantation si la cible focus est amicale ou inattaquable. Désactivez pour les tests."

L.Settings.BackgroundOpacityLabel = "Opacité de l'arrière-plan"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Opacité hors de portée"
L.Settings.OutOfRangeOpacityTooltip = "100% pour désactiver."

L.Settings.PointLabel = "Point"
L.Settings.PointTooltip =
	"Avec Décalage X / Décalage Y, permet un contrôle de positionnement plus précis qu'avec le glisser-déposer."

L.Settings.InterruptSourceText = "Interrompu [%s]"

L.Settings.UnitLabel = "Unité"
L.Settings.UnitTooltip =
	"Quelle unité utiliser. Oui, c'est un addon de barre d'incantation pour le focus, et pourtant nous voilà."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Focalisation",
	[Private.Enum.Unit.Target] = "Cible",
}

L.Settings.FeatureFlagLabel = "Fonctionnalités"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Afficher l'icône",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Afficher le temps d'incantation",
	[Private.Enum.FeatureFlag.ShowBorder] = "Afficher la bordure",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Mettre en lumière les sorts importants",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Afficher le marqueur de cible",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Afficher le nom du joueur ciblé",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Utiliser la couleur de classe de la cible",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Afficher la source d'interruption",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Utiliser la couleur de la source d'interruption",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Jouer un rappel TTS de ciblage",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Ignorer les unités amicales",
	[Private.Enum.FeatureFlag.UnfillChannels] = "(Dé)remplir les canalisations",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Afficher uniquement si interruptible & peut interrompre",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Jouer le TTS au début de l'incantation",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Pour plus d'infos, survolez « Fonctionnalités » à gauche",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Réglages de la cible d'incantation",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Réglages de la source d'interruption",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Réglages du son",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Autre",
}
L.Settings.CastStartText = "Incantation"
L.Settings.CustomizeTTSOnCastStartButtonText = "Personnaliser le texte TTS au début de l'incantation"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"Ce qui est important ou non est déterminé par le jeu."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"Peut poser des problèmes de contraste selon l'arrière-plan et la couleur de la barre."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Joue le texte « focalisation » (ou « cible ») en synthèse vocale lorsque l'unité observée disparaît, pour rappeler d'en choisir une nouvelle. Uniquement dans les donjons !"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Joue « %s » en synthèse vocale lorsque l'unité observée commence à incanter. Sans condition, ne peut pas vérifier si vous pouvez interrompre ou si c'est interruptible. Uniquement dans les donjons !",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Vide la barre d'incantation lorsqu'elle est active ; la remplit lorsqu'elle est inactive."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Avertissement pour les soigneurs : cela désactive effectivement l'addon sauf si vous êtes Chaman Restauration."
		),
	}, "\n\n")
end
