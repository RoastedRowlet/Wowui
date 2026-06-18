---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("As configurações estão disponíveis exclusivamente via Esc > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Carregar no conteúdo"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Mundo aberto",
	[Private.Enum.ContentType.Delve] = "Vãos",
	[Private.Enum.ContentType.Dungeon] = "Masmorra",
	[Private.Enum.ContentType.Raid] = "Raide",
	[Private.Enum.ContentType.Arena] = "Arena",
	[Private.Enum.ContentType.Battleground] = "Campo de batalha",
}

L.Settings.LoadConditionRoleLabel = "Carregar por função"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Curandeiro",
	[Private.Enum.Role.Tank] = "Tanque",
	[Private.Enum.Role.Damager] = "DPS",
}

L.Settings.FontFlagsLabel = "Opções de fonte"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Contorno",
	[Private.Enum.FontFlags.SHADOW] = "Sombra",
}

L.Settings.SecondaryFontScaleLabel = "Escala de fonte secundária"
L.Settings.SecondaryFontScaleTooltip =
	"Controla a proporção do texto do alvo de conjuração e da fonte de interrupção em relação ao tamanho de fonte geral."

L.Settings.FrameWidthLabel = "Largura"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Altura"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Opacidade"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Deslocamento X"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Deslocamento Y"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Importar"
L.Settings.Export = "Exportar"

L.Settings.ColorUninterruptibleLabel = "Não interrompível"

L.Settings.ColorInterruptibleCanInterruptLabel = "Interrompível e pode interromper"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Interrompível e não pode interromper"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"Quando você não pode interromper porque sua especialização não tem interrupção, você não a escolheu como talento ou seu nível é muito baixo."

L.Settings.ColorInterruptTickLabel = "Cor do marcador"

L.Settings.ColorGlowLabel = "Cor do brilho"

L.Settings.FontSizeLabel = "Tamanho da fonte"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Largura do marcador"
L.Settings.TickWidthTooltip = "0 oculta o marcador."

L.Settings.FontLabel = "Fonte"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Textura"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Posição do texto"
L.Settings.CustomTextPositionTooltip =
	"Controla a posição do nome do alvo bem como do texto da fonte de interrupção."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "Abaixo ao centro",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "Abaixo à esquerda",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "Abaixo à direita",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "Acima à esquerda",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "Acima à direita",
}

L.Settings.IgnoreFriendliesTooltip =
	"Impede a exibição da barra de conjuração se o alvo de foco for amigável ou não atacável. Desative para fins de teste."

L.Settings.BackgroundOpacityLabel = "Opacidade do fundo"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Opacidade fora de alcance"
L.Settings.OutOfRangeOpacityTooltip = "100% para desativar."

L.Settings.PointLabel = "Ponto"
L.Settings.PointTooltip =
	"Junto com Deslocamento X / Deslocamento Y, permite um controle de posicionamento mais preciso do que arrastar e soltar."

L.Settings.InterruptSourceText = "Interrompido [%s]"

L.Settings.UnitLabel = "Unidade"
L.Settings.UnitTooltip = "Qual unidade usar. Sim, este é um addon de barra de conjuração de foco, e mesmo assim aqui estamos."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Foco",
	[Private.Enum.Unit.Target] = "Alvo",
}

L.Settings.FeatureFlagLabel = "Recursos"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Mostrar ícone",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Mostrar tempo de conjuração",
	[Private.Enum.FeatureFlag.ShowBorder] = "Mostrar borda",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Destacar magias importantes",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Mostrar marcador de alvo",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Mostrar nome do jogador alvo",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Usar cor de classe do alvo",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Mostrar fonte de interrupção",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Usar cor da fonte de interrupção",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Reproduzir lembrete de TTS de alvo",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Ignorar unidades amigáveis",
	[Private.Enum.FeatureFlag.UnfillChannels] = "(Des)preencher canalizações",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Mostrar apenas quando for interrompível e puder interromper",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Reproduzir TTS no início da conjuração",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Para mais informações, passe o mouse sobre «Recursos» à esquerda",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Configurações do alvo de conjuração",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Configurações da fonte de interrupção",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Configurações de som",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Outros",
}
L.Settings.CastStartText = "Conjurando"
L.Settings.CustomizeTTSOnCastStartButtonText = "Personalizar o texto de TTS no início da conjuração"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"O que é importante e o que não é, é definido pelo jogo."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"Pode ter problemas de contraste dependendo do fundo e da cor da barra."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Reproduz o texto «foco» (ou «alvo») em texto para voz quando a unidade observada desaparece, como lembrete para escolher uma nova. Apenas em masmorras!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Reproduz «%s» em texto para voz quando a unidade observada começa a conjurar. Incondicional, não pode verificar se você pode interromper ou se é interrompível. Apenas em masmorras!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Esvazia a barra de conjuração quando ativa; preenche quando inativa."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Aviso para curandeiros: isso efetivamente desativa o addon a menos que você seja um Xamã Restauração."
		),
	}, "\n\n")
end
