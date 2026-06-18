---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder = string.format("設定僅可透過 Esc > %s 進行調整。", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "在內容中載入"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "開放世界",
	[Private.Enum.ContentType.Delve] = "洞穴探索",
	[Private.Enum.ContentType.Dungeon] = "地城",
	[Private.Enum.ContentType.Raid] = "團隊副本",
	[Private.Enum.ContentType.Arena] = "競技場",
	[Private.Enum.ContentType.Battleground] = "戰場",
}

L.Settings.LoadConditionRoleLabel = "依職責載入"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "治療",
	[Private.Enum.Role.Tank] = "坦克",
	[Private.Enum.Role.Damager] = "輸出",
}

L.Settings.FontFlagsLabel = "字型選項"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "外框",
	[Private.Enum.FontFlags.SHADOW] = "陰影",
}

L.Settings.SecondaryFontScaleLabel = "次要字型縮放"
L.Settings.SecondaryFontScaleTooltip = "控制施法目標與打斷來源文字相對於整體字型大小的比例。"

L.Settings.FrameWidthLabel = "寬度"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "高度"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "不透明度"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "X軸偏移"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Y軸偏移"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "匯入"
L.Settings.Export = "匯出"

L.Settings.ColorUninterruptibleLabel = "無法打斷"

L.Settings.ColorInterruptibleCanInterruptLabel = "可打斷且你能打斷"

L.Settings.ColorInterruptibleCannotInterruptLabel = "可打斷但你無法打斷"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"當你無法打斷時——因為你的專精沒有打斷技能、未選擇相關天賦，或等級過低。"

L.Settings.ColorInterruptTickLabel = "刻度顏色"

L.Settings.ColorGlowLabel = "發光顏色"

L.Settings.FontSizeLabel = "字型大小"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "刻度寬度"
L.Settings.TickWidthTooltip = "設為 0 可隱藏刻度。"

L.Settings.FontLabel = "字型"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "材質"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "文字位置"
L.Settings.CustomTextPositionTooltip = "控制目標名稱文字以及打斷來源文字的位置。"
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "底部置中",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "左下",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "右下",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "左上",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "右上",
}

L.Settings.IgnoreFriendliesTooltip = "當專注目標為友方或無法攻擊時不顯示施法條。測試時請停用。"

L.Settings.BackgroundOpacityLabel = "背景不透明度"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "超出距離不透明度"
L.Settings.OutOfRangeOpacityTooltip = "設為 100% 可停用。"

L.Settings.PointLabel = "錨點"
L.Settings.PointTooltip = "與 X軸偏移 / Y軸偏移 搭配使用，相比拖放可達成更精細的定位控制。"

L.Settings.InterruptSourceText = "已打斷 [%s]"

L.Settings.UnitLabel = "單位"
L.Settings.UnitTooltip = "要使用哪個單位。是的，這是一個專注施法條插件，但我們還是加了這個選項。"
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "專注目標",
	[Private.Enum.Unit.Target] = "目標",
}

L.Settings.FeatureFlagLabel = "功能"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "顯示圖示",
	[Private.Enum.FeatureFlag.ShowCastTime] = "顯示施法時間",
	[Private.Enum.FeatureFlag.ShowBorder] = "顯示邊框",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "強調重要法術",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "顯示目標標記",
	[Private.Enum.FeatureFlag.ShowTargetName] = "顯示目標玩家名稱",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "使用目標職業顏色",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "顯示打斷來源",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "使用打斷來源顏色",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "播放選定目標語音提醒",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "忽略友方單位",
	[Private.Enum.FeatureFlag.UnfillChannels] = "引導法術（反向）填充",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "僅在可打斷且你能打斷時顯示",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "施法開始時播放語音",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "更多資訊請將滑鼠移至左側的「功能」上",
	[Private.Enum.FeatureFlag.ShowTargetName] = "施法目標設定",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "打斷來源設定",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "聲音設定",
	[Private.Enum.FeatureFlag.UnfillChannels] = "其他",
}
L.Settings.CastStartText = "施法"
L.Settings.CustomizeTTSOnCastStartButtonText = "自訂施法開始時的語音文字"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(Private.Enum.FeatureFlag.ShowImportantSpellsGlow, "哪些重要、哪些不重要由遊戲本身決定。"),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"依背景與條顏色的不同，可能會有對比度問題。"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"當你目前觀察的單位消失時，播放「專注目標」（或「目標」）語音，提醒你選擇新的目標。僅在地城中生效！"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"當你觀察的單位開始施法時播放「%s」語音。無條件觸發，無法判斷你是否能打斷或該法術是否可打斷。僅在地城中生效！",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(Private.Enum.FeatureFlag.UnfillChannels, "引導法術啟用時清空施法條；未啟用時填充。"),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"治療者警告：除非你是恢復薩滿，否則此設定實際上會使插件失效。"
		),
	}, "\n\n")
end
