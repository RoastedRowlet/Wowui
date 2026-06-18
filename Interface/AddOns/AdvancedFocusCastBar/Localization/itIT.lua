---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("Le impostazioni sono disponibili esclusivamente tramite Esc > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Carica nel contenuto"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Mondo aperto",
	[Private.Enum.ContentType.Delve] = "Anfratti",
	[Private.Enum.ContentType.Dungeon] = "Spedizione",
	[Private.Enum.ContentType.Raid] = "Incursione",
	[Private.Enum.ContentType.Arena] = "Arena",
	[Private.Enum.ContentType.Battleground] = "Campo di battaglia",
}

L.Settings.LoadConditionRoleLabel = "Carica in base al ruolo"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Guaritore",
	[Private.Enum.Role.Tank] = "Tank",
	[Private.Enum.Role.Damager] = "DPS",
}

L.Settings.FontFlagsLabel = "Opzioni del carattere"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Contorno",
	[Private.Enum.FontFlags.SHADOW] = "Ombra",
}

L.Settings.SecondaryFontScaleLabel = "Scala carattere secondario"
L.Settings.SecondaryFontScaleTooltip =
	"Controlla il rapporto del testo del bersaglio del lancio e della fonte di interruzione rispetto alla dimensione generale del carattere."

L.Settings.FrameWidthLabel = "Larghezza"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Altezza"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Opacità"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Scostamento X"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Scostamento Y"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Importa"
L.Settings.Export = "Esporta"

L.Settings.ColorUninterruptibleLabel = "Non interrompibile"

L.Settings.ColorInterruptibleCanInterruptLabel = "Interrompibile e puoi interrompere"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Interrompibile e non puoi interrompere"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"Quando non puoi interrompere perché la tua specializzazione non ha un'interruzione, non l'hai scelta come talento o il tuo livello è troppo basso."

L.Settings.ColorInterruptTickLabel = "Colore del segno"

L.Settings.ColorGlowLabel = "Colore del bagliore"

L.Settings.FontSizeLabel = "Dimensione carattere"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Larghezza del segno"
L.Settings.TickWidthTooltip = "0 nasconde il segno."

L.Settings.FontLabel = "Carattere"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Trama"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Posizione del testo"
L.Settings.CustomTextPositionTooltip =
	"Controlla la posizione del nome del bersaglio e del testo della fonte di interruzione."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "In basso al centro",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "In basso a sinistra",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "In basso a destra",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "In alto a sinistra",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "In alto a destra",
}

L.Settings.IgnoreFriendliesTooltip =
	"Impedisce di mostrare la barra di lancio se il bersaglio del focus è amichevole o non attaccabile. Disabilita per i test."

L.Settings.BackgroundOpacityLabel = "Opacità dello sfondo"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Opacità fuori portata"
L.Settings.OutOfRangeOpacityTooltip = "100% per disabilitare."

L.Settings.PointLabel = "Punto"
L.Settings.PointTooltip =
	"Insieme a Scostamento X / Scostamento Y, permette un controllo del posizionamento più preciso rispetto al trascinamento."

L.Settings.InterruptSourceText = "Interrotto [%s]"

L.Settings.UnitLabel = "Unità"
L.Settings.UnitTooltip =
	"Quale unità usare. Sì, questo è un addon per la barra di lancio del focus, eppure eccoci qui."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Focus",
	[Private.Enum.Unit.Target] = "Bersaglio",
}

L.Settings.FeatureFlagLabel = "Funzionalità"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Mostra icona",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Mostra tempo di lancio",
	[Private.Enum.FeatureFlag.ShowBorder] = "Mostra bordo",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Evidenzia incantesimi importanti",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Mostra indicatore del bersaglio",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Mostra nome del giocatore bersaglio",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Usa colore di classe del bersaglio",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Mostra fonte di interruzione",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Usa colore della fonte di interruzione",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Riproduci promemoria TTS di bersaglio",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Ignora unità amichevoli",
	[Private.Enum.FeatureFlag.UnfillChannels] = "(S)riempi le canalizzazioni",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Mostra solo quando è interrompibile e puoi interrompere",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Riproduci TTS all'inizio del lancio",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Per maggiori info, passa il mouse su «Funzionalità» a sinistra",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Impostazioni del bersaglio del lancio",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Impostazioni della fonte di interruzione",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Impostazioni audio",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Altro",
}
L.Settings.CastStartText = "Lancio"
L.Settings.CustomizeTTSOnCastStartButtonText = "Personalizza il testo TTS all'inizio del lancio"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"Cosa è importante e cosa no è deciso dal gioco."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"Può avere problemi di contrasto a seconda dello sfondo e del colore della barra."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Riproduce il testo vocale «focus» (o «bersaglio») quando l'unità osservata scompare, come promemoria per sceglierne una nuova. Solo nelle spedizioni!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Riproduce «%s» come testo vocale quando l'unità osservata inizia a lanciare. Incondizionato, non può verificare se puoi interrompere o se è interrompibile. Solo nelle spedizioni!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Svuota la barra di lancio quando attiva; la riempie quando inattiva."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Avviso per i guaritori: questo di fatto disabilita l'addon a meno che tu non sia uno Sciamano Ripristino."
		),
	}, "\n\n")
end
