---@type string, AdvancedFocusCastBar
local addonName, Private = ...

local L = Private.L

L.EditMode = {}

L.EditMode.AddonName = "Advanced Focus Cast Bar"

L.Settings = {}

L.Settings.EditModeReminder =
	string.format("설정은 Esc > %s 를 통해서만 이용할 수 있습니다.", HUD_EDIT_MODE_MENU)

L.Settings.LoadConditionContentTypeLabel = "콘텐츠에서 불러오기"
L.Settings.LoadConditionContentTypeTooltip = nil
L.Settings.LoadConditionContentTypeLabels = {
	[Private.Enum.ContentType.OpenWorld] = "열린 공간",
	[Private.Enum.ContentType.Delve] = "구렁",
	[Private.Enum.ContentType.Dungeon] = "던전",
	[Private.Enum.ContentType.Raid] = "공격대",
	[Private.Enum.ContentType.Arena] = "투기장",
	[Private.Enum.ContentType.Battleground] = "전장",
}

L.Settings.LoadConditionRoleLabel = "역할에 따라 불러오기"
L.Settings.LoadConditionRoleTooltip = nil
L.Settings.LoadConditionRoleLabels = {
	[Private.Enum.Role.Healer] = "치유 전담",
	[Private.Enum.Role.Tank] = "방어 전담",
	[Private.Enum.Role.Damager] = "공격 전담",
}

L.Settings.FontFlagsLabel = "글꼴 옵션"
L.Settings.FontFlagsTooltip = nil
L.Settings.FontFlagsLabels = {
	[Private.Enum.FontFlags.OUTLINE] = "외곽선",
	[Private.Enum.FontFlags.SHADOW] = "그림자",
}

L.Settings.SecondaryFontScaleLabel = "보조 글꼴 크기 비율"
L.Settings.SecondaryFontScaleTooltip =
	"전체 글꼴 크기에 대한 시전 대상 및 차단자 텍스트의 비율을 조절합니다."

L.Settings.FrameWidthLabel = "너비"
L.Settings.FrameWidthTooltip = nil

L.Settings.FrameHeightLabel = "높이"
L.Settings.FrameHeightTooltip = nil

L.Settings.OpacityLabel = "투명도"
L.Settings.OpacityTooltip = nil

L.Settings.OffsetXLabel = "X축 간격"
L.Settings.OffsetXTooltip = nil

L.Settings.OffsetYLabel = "Y축 간격"
L.Settings.OffsetYTooltip = nil

L.Settings.Import = "가져오기"
L.Settings.Export = "내보내기"

L.Settings.ColorUninterruptibleLabel = "차단 불가"

L.Settings.ColorInterruptibleCanInterruptLabel = "차단 가능 & 차단할 수 있음"

L.Settings.ColorInterruptibleCannotInterruptLabel = "차단 가능 & 차단할 수 없음"
L.Settings.ColorInterruptibleCannotInterruptTooltip =
	"전문화에 차단 기술이 없거나, 특성으로 선택하지 않았거나, 레벨이 너무 낮아 차단할 수 없을 때 적용됩니다."

L.Settings.ColorInterruptTickLabel = "눈금 색상"

L.Settings.ColorGlowLabel = "발광 색상"

L.Settings.FontSizeLabel = "글꼴 크기"
L.Settings.FontSizeTooltip = nil

L.Settings.TickWidthLabel = "눈금 너비"
L.Settings.TickWidthTooltip = "0이면 눈금을 숨깁니다."

L.Settings.FontLabel = "글꼴"
L.Settings.FontTooltip = nil

L.Settings.TextureLabel = "텍스처"
L.Settings.TextureTooltip = nil

L.Settings.ShowTargetNameTooltip = nil

L.Settings.CustomTextPositionLabel = "텍스트 위치"
L.Settings.CustomTextPositionTooltip = "대상 이름 텍스트와 차단자 텍스트의 위치를 조절합니다."
L.Settings.CustomTextPositionLabels = {
	[Private.Enum.CustomTextsPosition.BOTTOM] = "아래 가운데",
	[Private.Enum.CustomTextsPosition.BOTTOMLEFT] = "아래 왼쪽",
	[Private.Enum.CustomTextsPosition.BOTTOMRIGHT] = "아래 오른쪽",
	[Private.Enum.CustomTextsPosition.TOPLEFT] = "위 왼쪽",
	[Private.Enum.CustomTextsPosition.TOPRIGHT] = "위 오른쪽",
}

L.Settings.IgnoreFriendliesTooltip =
	"주시 대상이 아군이거나 공격할 수 없는 경우 시전 막대를 표시하지 않습니다. 테스트할 때는 비활성화하세요."

L.Settings.BackgroundOpacityLabel = "배경 투명도"
L.Settings.BackgroundOpacityTooltip = nil

L.Settings.OutOfRangeOpacityLabel = "사정거리 밖 투명도"
L.Settings.OutOfRangeOpacityTooltip = "100%이면 비활성화됩니다."

L.Settings.PointLabel = "기준점"
L.Settings.PointTooltip =
	"X축 간격 / Y축 간격과 함께 사용하면 드래그 앤 드롭보다 더 세밀하게 위치를 조절할 수 있습니다."

L.Settings.InterruptSourceText = "차단됨 [%s]"

L.Settings.UnitLabel = "대상"
L.Settings.UnitTooltip = "사용할 대상을 선택합니다. 네, 이건 주시 대상 시전 막대 애드온인데도 말이죠."
L.Settings.UnitLabels = {
	[Private.Enum.Unit.Focus] = "주시 대상",
	[Private.Enum.Unit.Target] = "대상",
}

L.Settings.FeatureFlagLabel = "기능"
L.Settings.FeatureFlagLabels = {
	[Private.Enum.FeatureFlag.ShowIcon] = "아이콘 표시",
	[Private.Enum.FeatureFlag.ShowCastTime] = "시전 시간 표시",
	[Private.Enum.FeatureFlag.ShowBorder] = "테두리 표시",
	[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = "중요한 주문 강조",
	[Private.Enum.FeatureFlag.ShowTargetMarker] = "대상 표식 표시",
	[Private.Enum.FeatureFlag.ShowTargetName] = "대상으로 지정한 플레이어 이름 표시",
	[Private.Enum.FeatureFlag.UseTargetClassColor] = "대상 직업 색상 사용",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "차단자 표시",
	[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = "차단자 직업 색상 사용",
	[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = "대상 지정 음성 알림 재생",
	[Private.Enum.FeatureFlag.IgnoreFriendlies] = "아군 무시",
	[Private.Enum.FeatureFlag.UnfillChannels] = "정신집중 막대 (비)채우기",
	[Private.Enum.FeatureFlag.HideWhenUninterruptible] = "차단 가능하고 차단할 수 있을 때만 표시",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "시전 시작 시 음성 재생",
}
L.Settings.FeatureFlagSettingTitles = {
	[Private.Enum.FeatureFlag.ShowIcon] = "자세한 내용은 왼쪽의 '기능'에 마우스를 올려보세요",
	[Private.Enum.FeatureFlag.ShowTargetName] = "시전 대상 설정",
	[Private.Enum.FeatureFlag.ShowInterruptSource] = "차단자 설정",
	[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = "소리 설정",
	[Private.Enum.FeatureFlag.UnfillChannels] = "기타",
}
L.Settings.CastStartText = "시전"
L.Settings.CustomizeTTSOnCastStartButtonText = "시전 시작 시 음성 텍스트 사용자 지정"

do
	local function CreateFeatureFlagTooltip(id, tooltip)
		return string.format("%s - %s", L.Settings.FeatureFlagLabels[id], tooltip)
	end

	L.Settings.FeatureFlagTooltip = table.concat({
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
			"무엇이 중요하고 중요하지 않은지는 게임이 결정합니다."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UseTargetClassColor,
			"배경 및 막대 색상에 따라 대비 문제가 생길 수 있습니다."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
			"관찰 중인 대상이 사라지면 새 대상을 선택하라는 알림으로 '주시 대상'(또는 '대상') 음성을 재생합니다. 던전에서만 작동합니다!"
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.PlayTTSOnCastStart,
			string.format(
				"관찰 중인 대상이 시전을 시작하면 '%s' 음성을 재생합니다. 조건 없이 작동하며, 차단할 수 있는지 또는 차단 가능한지 확인할 수 없습니다. 던전에서만 작동합니다!",
				L.Settings.CastStartText
			)
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.UnfillChannels,
			"정신집중 시전이 활성화되면 막대를 비우고, 비활성화되면 채웁니다."
		),
		CreateFeatureFlagTooltip(
			Private.Enum.FeatureFlag.HideWhenUninterruptible,
			"치유사 주의: 복원 주술사가 아니라면 사실상 애드온이 비활성화됩니다."
		),
	}, "\n\n")
end
