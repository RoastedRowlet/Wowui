---@type string, AdvancedFocusCastBar
local addonName, Private = ...

---@class AdvancedFocusCastBarSettings
Private.Settings = {}

---@return SavedVariables
function Private.Settings.GetDefaultSettings()
	return {
		Width = 300,
		Height = 45,
		LoadConditionContentType = {
			[Private.Enum.ContentType.OpenWorld] = true,
			[Private.Enum.ContentType.Delve] = true,
			[Private.Enum.ContentType.Dungeon] = true,
			[Private.Enum.ContentType.Raid] = true,
			[Private.Enum.ContentType.Arena] = true,
			[Private.Enum.ContentType.Battleground] = false,
		},
		LoadConditionRole = {
			[Private.Enum.Role.Healer] = true,
			[Private.Enum.Role.Tank] = true,
			[Private.Enum.Role.Damager] = true,
		},
		Opacity = 1,
		Texture = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
		Point = Private.Enum.Point.CENTER,
		OffsetX = 0,
		OffsetY = 200,
		ColorUninterruptible = "FFBFC7C0",
		ColorInterruptibleCanInterrupt = "FF00FF00",
		ColorInterruptibleCannotInterrupt = "FFFFA800",
		ColorInterruptTick = "FFFDFFF7",
		ColorGlow = "FFF2F252",
		Font = "Fonts\\FRIZQT__.TTF",
		FontSize = 17,
		FontFlags = {
			[Private.Enum.FontFlags.OUTLINE] = true,
			[Private.Enum.FontFlags.SHADOW] = false,
		},
		SecondaryFontScale = 0.66,
		BackgroundOpacity = 0.35,
		CustomTextsPosition = Private.Enum.CustomTextsPosition.BOTTOMRIGHT,
		TickWidth = 3,
		OutOfRangeOpacity = 0.55,
		Unit = Private.Enum.Unit.Focus,
		FeatureFlags = {
			[Private.Enum.FeatureFlag.ShowIcon] = true,
			[Private.Enum.FeatureFlag.ShowCastTime] = true,
			[Private.Enum.FeatureFlag.ShowBorder] = true,
			[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] = true,
			[Private.Enum.FeatureFlag.ShowTargetMarker] = true,
			[Private.Enum.FeatureFlag.ShowTargetName] = true,
			[Private.Enum.FeatureFlag.UseTargetClassColor] = true,
			[Private.Enum.FeatureFlag.ShowInterruptSource] = true,
			[Private.Enum.FeatureFlag.UseInterruptSourceClassColor] = true,
			[Private.Enum.FeatureFlag.PlayTargetingTTSReminder] = false,
			[Private.Enum.FeatureFlag.IgnoreFriendlies] = true,
			[Private.Enum.FeatureFlag.UnfillChannels] = true,
			[Private.Enum.FeatureFlag.HideWhenUninterruptible] = false,
			[Private.Enum.FeatureFlag.PlayTTSOnCastStart] = false,
		},
		CustomTTSOnCastStartText = "",
	}
end

local function DecodeProfileString(string)
	-- return C_EncodingUtil.DeserializeJSON(string)
	return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(string))
end

function Private.Settings.Import(string)
	local ok, result = pcall(DecodeProfileString, string)

	if not ok then
		if result ~= nil then
			print(result)
		end

		return false
	end

	-- just a type check
	if result == nil then
		return false
	end

	local hasAnyChange = false
	local defaults = Private.Settings.GetDefaultSettings()

	for key, defaultValue in pairs(defaults) do
		local newValue = result[key]
		local expectedType = type(defaultValue)

		if newValue ~= nil and type(newValue) == expectedType then
			local eventKey = Private.Enum.Setting[key]
			local event = Private.Enum.Events.SETTING_CHANGED

			if
				eventKey == Private.Enum.Setting.Point
				or eventKey == Private.Enum.Setting.OffsetX
				or eventKey == Private.Enum.Setting.OffsetY
			then
				event = Private.Enum.Events.EDIT_MODE_POSITION_CHANGED
			end

			local hasChanges = false

			if expectedType == "table" then
				local enumToCompareAgainst = nil
				if key == "LoadConditionContentType" then
					enumToCompareAgainst = Private.Enum.ContentType
				elseif key == "LoadConditionRole" then
					enumToCompareAgainst = Private.Enum.Role
				elseif key == "FontFlags" then
					enumToCompareAgainst = Private.Enum.FontFlags
				elseif key == "FeatureFlags" then
					enumToCompareAgainst = Private.Enum.FeatureFlag
				end

				if enumToCompareAgainst then
					local newTable = {}

					for _, id in pairs(enumToCompareAgainst) do
						if newValue[id] == nil then
							newTable[id] = AdvancedFocusCastBarSaved.Settings[key][id]
						else
							newTable[id] = newValue[id]

							if newValue[id] ~= AdvancedFocusCastBarSaved.Settings[key][id] then
								hasChanges = true
							end
						end
					end

					if hasChanges then
						AdvancedFocusCastBarSaved.Settings[key] = newTable
						Private.EventRegistry:TriggerEvent(event, eventKey, newTable)
					end
				end
			elseif newValue ~= AdvancedFocusCastBarSaved.Settings[key] then
				AdvancedFocusCastBarSaved.Settings[key] = newValue
				hasChanges = true

				if eventKey and hasChanges then
					Private.EventRegistry:TriggerEvent(event, eventKey, newValue)
				end
			end

			if hasChanges then
				hasAnyChange = true
			end
		end
	end

	return true, hasAnyChange
end

function Private.Settings.Export()
	-- local exportString = C_EncodingUtil.SerializeJSON(AdvancedFocusCastBarSaved.Settings)
	return C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(AdvancedFocusCastBarSaved.Settings))
end

table.insert(Private.LoginFnQueue, function()
	local L = Private.L
	local settingsName = C_AddOns.GetAddOnMetadata(addonName, "Title")
	local category, layout = Settings.RegisterVerticalLayoutCategory(settingsName)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.Settings.EditModeReminder))

	Settings.RegisterAddOnCategory(category)
end)

do
	local function noop() end

	_G.AdvancedFocusCastBarAPI = {
		ImportProfile = Private.Settings.Import,
		ExportProfile = Private.Settings.Export,
		DecodeProfileString = DecodeProfileString,
		SetProfile = noop,
		GetProfileKeys = function()
			return { "Global" }
		end,
		GetCurrentProfileKey = function()
			return "Global"
		end,
		OpenConfig = noop,
		CloseConfig = noop,
	}
end
