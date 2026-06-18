---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("Los ajustes están disponibles exclusivamente a través de Escape > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Cargar en contenido"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Mundo abierto",
	[Private.Enum.ContentType.Delve] = "Simas",
	[Private.Enum.ContentType.Dungeon] = "Mazmorra",
	[Private.Enum.ContentType.Raid] = "Banda",
	[Private.Enum.ContentType.Arena] = "Arena",
	[Private.Enum.ContentType.Battleground] = "Campo de batalla",
}

L.Settings.LoadConditionRoleLabel = "Cargar según el rol"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Sanador",
	[Private.Enum.Role.Tank] = "Tanque",
	[Private.Enum.Role.Damager] = "DPS",
}

L.Settings.FontFlagsLabel = "Opciones de fuente"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Contorno",
	[Private.Enum.FontFlags.SHADOW] = "Sombra",
}

L.Settings.SecondaryFontScaleLabel = "Escala de fuente secundaria"
L.Settings.SecondaryFontScaleTooltip =
	"Controla la proporción del texto del objetivo de lanzamiento y de la fuente de interrupción en relación con el tamaño de fuente general."

L.Settings.FrameWidthLabel = "Anchura"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Altura"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Opacidad"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Desplazamiento X"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Desplazamiento Y"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Importar"
L.Settings.Export = "Exportar"

L.Settings.ColorUninterruptibleLabel = "No interrumpible"

L.Settings.ColorInterruptibleCanInterruptLabel = "Interrumpible y puedes interrumpir"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Interrumpible y no puedes interrumpir"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"Cuando no puedes interrumpir porque tu especialización no tiene interrupción, no la has aprendido como talento o tu nivel es demasiado bajo."

L.Settings.ColorInterruptTickLabel = "Color de la marca"

L.Settings.ColorGlowLabel = "Color del resplandor"

L.Settings.FontSizeLabel = "Tamaño de fuente"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Anchura de la marca"
L.Settings.TickWidthTooltip = "0 oculta la marca."

L.Settings.FontLabel = "Fuente"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Textura"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Posición del texto"
L.Settings.CustomTextPositionTooltip =
	"Controla la posición del nombre del objetivo así como del texto de la fuente de interrupción."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "Abajo centro",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "Abajo izquierda",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "Abajo derecha",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "Arriba izquierda",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "Arriba derecha",
}

L.Settings.IgnoreFriendliesTooltip =
	"Evita mostrar la barra de lanzamiento si el objetivo de foco es amistoso o no atacable. Desactívalo para hacer pruebas."

L.Settings.BackgroundOpacityLabel = "Opacidad del fondo"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Opacidad fuera de alcance"
L.Settings.OutOfRangeOpacityTooltip = "100% para desactivar."

L.Settings.PointLabel = "Punto"
L.Settings.PointTooltip =
	"Junto con Desplazamiento X / Desplazamiento Y, permite un control de posición más preciso que arrastrar y soltar."

L.Settings.InterruptSourceText = "Interrumpido [%s]"

L.Settings.UnitLabel = "Unidad"
L.Settings.UnitTooltip = "Qué unidad usar. Sí, esto es un addon de barra de lanzamiento de foco, y aun así aquí estamos."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Foco",
	[Private.Enum.Unit.Target] = "Objetivo",
}

L.Settings.FeatureFlagLabel = "Funciones"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Mostrar icono",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Mostrar tiempo de lanzamiento",
	[Private.Enum.FeatureFlag.ShowBorder] = "Mostrar borde",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Resaltar hechizos importantes",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Mostrar marcador de objetivo",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Mostrar nombre del jugador objetivo",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Usar color de clase del objetivo",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Mostrar fuente de interrupción",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Usar color de la fuente de interrupción",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Reproducir recordatorio de TTS de objetivo",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Ignorar unidades amistosas",
	[Private.Enum.FeatureFlag.UnfillChannels] = "(Des)rellenar canalizaciones",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Mostrar solo cuando es interrumpible y puedes interrumpir",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Reproducir TTS al iniciar el lanzamiento",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Para más información, pasa el ratón sobre «Funciones» a la izquierda",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Ajustes del objetivo de lanzamiento",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Ajustes de la fuente de interrupción",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Ajustes de sonido",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Otros",
}
L.Settings.CastStartText = "Lanzando"
L.Settings.CustomizeTTSOnCastStartButtonText = "Personalizar el texto de TTS al iniciar el lanzamiento"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"Lo que es importante y lo que no lo determina el juego."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"Puede tener problemas de contraste según el fondo y el color de la barra."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Reproduce el texto a voz «foco» (u «objetivo») cuando la unidad observada desaparece, como recordatorio para elegir una nueva. ¡Solo en mazmorras!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Reproduce «%s» en texto a voz cuando la unidad observada empieza a lanzar. Incondicional, no puede verificar si puedes interrumpir o si es interrumpible. ¡Solo en mazmorras!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Vacía la barra de lanzamiento cuando está activa; la rellena cuando está inactiva."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Aviso para sanadores: esto desactiva efectivamente el addon a menos que seas Chamán Restauración."
		),
	}, "\n\n")
end
