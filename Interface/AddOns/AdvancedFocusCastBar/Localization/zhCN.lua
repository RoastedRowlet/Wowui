---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder = string.format("设置仅可通过 Esc > %s 进行调整。", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "在内容中加载"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "开放世界",
	[Private.Enum.ContentType.Delve] = "地穴",
	[Private.Enum.ContentType.Dungeon] = "地下城",
	[Private.Enum.ContentType.Raid] = "团队副本",
	[Private.Enum.ContentType.Arena] = "竞技场",
	[Private.Enum.ContentType.Battleground] = "战场",
}

L.Settings.LoadConditionRoleLabel = "按职责加载"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "治疗",
	[Private.Enum.Role.Tank] = "坦克",
	[Private.Enum.Role.Damager] = "输出",
}

L.Settings.FontFlagsLabel = "字体选项"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "描边",
	[Private.Enum.FontFlags.SHADOW] = "阴影",
}

L.Settings.SecondaryFontScaleLabel = "次要字体缩放"
L.Settings.SecondaryFontScaleTooltip = "控制施法目标和打断来源文本相对于整体字体大小的比例。"

L.Settings.FrameWidthLabel = "宽度"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "高度"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "不透明度"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "X轴偏移"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Y轴偏移"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "导入"
L.Settings.Export = "导出"

L.Settings.ColorUninterruptibleLabel = "不可打断"

L.Settings.ColorInterruptibleCanInterruptLabel = "可打断且你能打断"

L.Settings.ColorInterruptibleCannotInterruptLabel = "可打断但你无法打断"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"当你无法打断时——因为你的专精没有打断技能、未选择相关天赋，或等级过低。"

L.Settings.ColorInterruptTickLabel = "刻度颜色"

L.Settings.ColorGlowLabel = "发光颜色"

L.Settings.FontSizeLabel = "字体大小"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "刻度宽度"
L.Settings.TickWidthTooltip = "设为 0 可隐藏刻度。"

L.Settings.FontLabel = "字体"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "材质"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "文本位置"
L.Settings.CustomTextPositionTooltip = "控制目标名称文本以及打断来源文本的位置。"
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "底部居中",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "左下",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "右下",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "左上",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "右上",
}

L.Settings.IgnoreFriendliesTooltip = "当焦点目标为友方或不可攻击时不显示施法条。测试时请禁用。"

L.Settings.BackgroundOpacityLabel = "背景不透明度"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "超出距离不透明度"
L.Settings.OutOfRangeOpacityTooltip = "设为 100% 可禁用。"

L.Settings.PointLabel = "锚点"
L.Settings.PointTooltip = "与 X轴偏移 / Y轴偏移 配合使用，相比拖放可实现更精细的定位控制。"

L.Settings.InterruptSourceText = "已打断 [%s]"

L.Settings.UnitLabel = "单位"
L.Settings.UnitTooltip = "使用哪个单位。是的，这是一个焦点施法条插件，但我们还是加了这个选项。"
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "焦点",
	[Private.Enum.Unit.Target] = "目标",
}

L.Settings.FeatureFlagLabel = "功能"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "显示图标",
	[Private.Enum.FeatureFlag.ShowCastTime] = "显示施法时间",
	[Private.Enum.FeatureFlag.ShowBorder] = "显示边框",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "高亮重要法术",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "显示目标标记",
	[Private.Enum.FeatureFlag.ShowTargetName] = "显示目标玩家名称",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "使用目标职业颜色",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "显示打断来源",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "使用打断来源颜色",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "播放选定目标语音提醒",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "忽略友方单位",
	[Private.Enum.FeatureFlag.UnfillChannels] = "引导法术（反向）填充",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "仅在可打断且你能打断时显示",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "施法开始时播放语音",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "更多信息请将鼠标悬停在左侧的“功能”上",
	[Private.Enum.FeatureFlag.ShowTargetName] = "施法目标设置",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "打断来源设置",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "声音设置",
	[Private.Enum.FeatureFlag.UnfillChannels] = "其他",
}
L.Settings.CastStartText = "施法"
L.Settings.CustomizeTTSOnCastStartButtonText = "自定义施法开始时的语音文本"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(Private.Enum.FeatureFlag.ShowImportantSpellsGlow, "哪些重要、哪些不重要由游戏本身决定。"),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"根据背景和条颜色的不同，可能存在对比度问题。"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"当你当前观察的单位消失时，播放“焦点”（或“目标”）语音，提醒你选择新的目标。仅在地下城中生效！"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"当你观察的单位开始施法时播放“%s”语音。无条件触发，无法判断你是否能打断或该法术是否可打断。仅在地下城中生效！",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(Private.Enum.FeatureFlag.UnfillChannels, "引导法术激活时清空施法条；未激活时填充。"),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"治疗者警告：除非你是恢复萨满，否则此设置实际上会使插件失效。"
		),
	}, "\n\n")
end
