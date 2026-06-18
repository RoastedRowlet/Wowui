---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("Настройки доступны исключительно через Esc > %s.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "Загружать в контенте"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "Открытый мир",
	[Private.Enum.ContentType.Delve] = "Вылазки",
	[Private.Enum.ContentType.Dungeon] = "Подземелье",
	[Private.Enum.ContentType.Raid] = "Рейд",
	[Private.Enum.ContentType.Arena] = "Арена",
	[Private.Enum.ContentType.Battleground] = "Поле боя",
}

L.Settings.LoadConditionRoleLabel = "Загружать по роли"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "Лекарь",
	[Private.Enum.Role.Tank] = "Танк",
	[Private.Enum.Role.Damager] = "Урон",
}

L.Settings.FontFlagsLabel = "Параметры шрифта"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "Контур",
	[Private.Enum.FontFlags.SHADOW] = "Тень",
}

L.Settings.SecondaryFontScaleLabel = "Масштаб второстепенного шрифта"
L.Settings.SecondaryFontScaleTooltip =
	"Управляет соотношением текста цели заклинания и источника прерывания относительно общего размера шрифта."

L.Settings.FrameWidthLabel = "Ширина"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "Высота"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "Непрозрачность"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "Смещение по X"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Смещение по Y"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "Импорт"
L.Settings.Export = "Экспорт"

L.Settings.ColorUninterruptibleLabel = "Непрерываемое"

L.Settings.ColorInterruptibleCanInterruptLabel = "Прерываемое и можно прервать"

L.Settings.ColorInterruptibleCannotInterruptLabel = "Прерываемое и нельзя прервать"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"Когда вы не можете прервать, потому что у вашей специализации нет прерывания, вы не выбрали его в талантах или ваш уровень слишком низкий."

L.Settings.ColorInterruptTickLabel = "Цвет метки"

L.Settings.ColorGlowLabel = "Цвет свечения"

L.Settings.FontSizeLabel = "Размер шрифта"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "Ширина метки"
L.Settings.TickWidthTooltip = "0 скрывает метку."

L.Settings.FontLabel = "Шрифт"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "Текстура"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "Положение текста"
L.Settings.CustomTextPositionTooltip =
	"Управляет положением имени цели, а также текста источника прерывания."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "Снизу по центру",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "Снизу слева",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "Снизу справа",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "Сверху слева",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "Сверху справа",
}

L.Settings.IgnoreFriendliesTooltip =
	"Не показывает полосу заклинаний, если цель фокуса дружественная или неуязвимая. Отключите для тестирования."

L.Settings.BackgroundOpacityLabel = "Непрозрачность фона"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "Непрозрачность вне досягаемости"
L.Settings.OutOfRangeOpacityTooltip = "100% для отключения."

L.Settings.PointLabel = "Точка"
L.Settings.PointTooltip =
	"Вместе со Смещением по X / Смещением по Y обеспечивает более точное управление позиционированием по сравнению с перетаскиванием."

L.Settings.InterruptSourceText = "Прервано [%s]"

L.Settings.UnitLabel = "Юнит"
L.Settings.UnitTooltip = "Какой юнит использовать. Да, это аддон для полосы заклинаний фокуса, и всё же мы здесь."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "Фокус",
	[Private.Enum.Unit.Target] = "Цель",
}

L.Settings.FeatureFlagLabel = "Возможности"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Показывать значок",
	[Private.Enum.FeatureFlag.ShowCastTime] = "Показывать время произнесения",
	[Private.Enum.FeatureFlag.ShowBorder] = "Показывать рамку",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "Подсвечивать важные заклинания",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "Показывать метку цели",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Показывать имя выбранного игрока",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "Использовать цвет класса цели",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Показывать источник прерывания",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "Использовать цвет источника прерывания",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "Воспроизводить голосовое напоминание о цели",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "Игнорировать дружественных",
	[Private.Enum.FeatureFlag.UnfillChannels] = "(Не)заполнять поддерживаемые заклинания",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "Показывать только когда можно прервать и есть прерывание",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Воспроизводить озвучку в начале произнесения",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "Подробнее — наведите курсор на «Возможности» слева",
	[Private.Enum.FeatureFlag.ShowTargetName] = "Настройки цели заклинания",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "Настройки источника прерывания",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "Настройки звука",
	[Private.Enum.FeatureFlag.UnfillChannels] = "Прочее",
}
L.Settings.CastStartText = "Каст"
L.Settings.CustomizeTTSOnCastStartButtonText = "Настроить текст озвучки в начале произнесения"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"Что важно, а что нет — определяет сама игра."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"Может вызывать проблемы с контрастом в зависимости от фона и цвета полосы."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"Воспроизводит озвучку «фокус» (или «цель»), когда наблюдаемый юнит исчезает, как напоминание выбрать нового. Только в подземельях!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"Воспроизводит озвучку «%s», когда наблюдаемый юнит начинает читать заклинание. Безусловно, не может проверить, можете ли вы прервать или прерываемо ли оно. Только в подземельях!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"Опустошает полосу заклинаний, когда активна; заполняет, когда неактивна."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"Предупреждение для лекарей: по сути это отключает аддон, если вы не шаман-Усмирение стихий."
		),
	}, "\n\n")
end
