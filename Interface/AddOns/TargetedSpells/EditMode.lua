---@type string, TargetedSpells
local addonName, Private = ...
local LibEditMode = LibStub("LibEditMode")

---@class TargetedSpellsEditModeMixin
local TargetedSpellsEditModeMixin = {}

function TargetedSpellsEditModeMixin:Init(displayName, frameKind)
	self.frameKind = frameKind
	self.demoPlaying = false
	self.frames = {}
	self.demoTimers = {
		tickers = {},
		timers = {},
	}
	self.editModeFrame = CreateFrame("Frame", displayName, UIParent)
	self.editModeFrame:SetClampedToScreen(true)
	-- some addons such as BetterCooldownManager toggle the edit mode briefly on login/loading screen end
	-- which would toggle demos on our end. by flipping this bool, we can avoid that entirely, speeding up load time
	self.editModeFrame.firstFrameTimestamp = 0

	self.editModeFrame:RegisterEvent("FIRST_FRAME_RENDERED")
	self.editModeFrame:SetScript("OnEvent", function(self, event)
		self.firstFrameTimestamp = GetTime()
		self:SetScript("OnEvent", nil)
		self:UnregisterAllEvents()
	end)

	Private.Utils.RegisterEditModeFrame(frameKind, self.editModeFrame)
	Private.EventRegistry:RegisterCallback(Private.Enum.Events.SETTING_CHANGED, self.OnSettingsChanged, self)

	do
		local cb = GenerateClosure(self.StartDemo, self)

		LibEditMode:RegisterCallback("enter", QUI == nil and cb or function()
			C_Timer.After(0.25, cb)
		end)
	end

	LibEditMode:RegisterCallback("exit", GenerateClosure(self.EndDemo, self))

	self:AppendSettings()
end

function TargetedSpellsEditModeMixin:IsPastLoadingScreen()
	return (GetTime() - self.editModeFrame.firstFrameTimestamp) > 1
end

function TargetedSpellsEditModeMixin:OnSettingsChanged(key, flagIdOrValue, newBool)
	if
		-- self
		key == Private.Settings.Keys.Self.Gap
		or key == Private.Settings.Keys.Self.Direction
		or key == Private.Settings.Keys.Self.Width
		or key == Private.Settings.Keys.Self.Height
		or key == Private.Settings.Keys.Self.SortOrder
		or key == Private.Settings.Keys.Self.Grow
		or key == Private.Settings.Keys.Self.GlowType
		-- party
		or key == Private.Settings.Keys.Party.Gap
		or key == Private.Settings.Keys.Party.Direction
		or key == Private.Settings.Keys.Party.Width
		or key == Private.Settings.Keys.Party.Height
		or key == Private.Settings.Keys.Party.OffsetX
		or key == Private.Settings.Keys.Party.OffsetY
		or key == Private.Settings.Keys.Party.SourceAnchor
		or key == Private.Settings.Keys.Party.TargetAnchor
		or key == Private.Settings.Keys.Party.SortOrder
		or key == Private.Settings.Keys.Party.Grow
		or key == Private.Settings.Keys.Party.GlowType
	then
		self:OnLayoutSettingChanged(key, flagIdOrValue)
	elseif key == Private.Settings.Keys.Self.Enabled or key == Private.Settings.Keys.Party.Enabled then
		if not LibEditMode:IsInEditMode() then
			return
		end

		if
			(key == Private.Settings.Keys.Self.Enabled and self.frameKind == Private.Enum.FrameKind.Self)
			or (key == Private.Settings.Keys.Party.Enabled and self.frameKind == Private.Enum.FrameKind.Party)
		then
			if flagIdOrValue then
				self:StartDemo()
			else
				self:EndDemo()
			end
		end
	elseif key == Private.Settings.Keys.Self.FeatureFlags or key == Private.Settings.Keys.Party.FeatureFlags then
		local flagId = flagIdOrValue

		if flagId == Private.Enum.FeatureFlag.GlowImportant then
			self:OnLayoutSettingChanged(key, flagId, newBool)
		elseif flagId == Private.Enum.FeatureFlag.OnlyImportant then
			if not LibEditMode:IsInEditMode() then
				return
			end

			local isSelf = key == Private.Settings.Keys.Self.FeatureFlags

			if
				(isSelf and self.frameKind == Private.Enum.FrameKind.Self)
				or (not isSelf and self.frameKind == Private.Enum.FrameKind.Party)
			then
				self:EndDemo()
				self:StartDemo()
			end
		elseif flagId == Private.Enum.FeatureFlag.IncludeSelfInParty then
			if self.frameKind ~= Private.Enum.FrameKind.Party or not LibEditMode:IsInEditMode() then
				return
			end

			self:EndDemo()
			self:StartDemo()
		end
	end
end

function TargetedSpellsEditModeMixin:CreateImportExportButtons()
	return {
		{
			click = function()
				self:OnImportButtonClick()
			end,
			text = Private.L.Settings.Import,
		},
		{
			click = function()
				self:OnExportButtonClick()
			end,
			text = Private.L.Settings.Export,
		},
		{
			click = function()
				self:OnDiscordButtonClick()
			end,
			text = "Discord",
		},
	}
end

function TargetedSpellsEditModeMixin:OnDiscordButtonClick()
	local link = C_EncodingUtil.DeserializeCBOR(
		C_EncodingUtil.DecodeBase64("oURsaW5rWB1odHRwczovL2Rpc2NvcmQuZ2cvQzVTVGpZUnNDRA==")
	).link

	Private.Utils.ShowStaticPopup(Private.Utils.CreateEditablePopup("Discord", link, ACCEPT))
end

function TargetedSpellsEditModeMixin:OnExportButtonClick()
	Private.Utils.ShowStaticPopup(
		Private.Utils.CreateEditablePopup(Private.L.Settings.Export, Private.Utils.Export(), ACCEPT)
	)
end

function TargetedSpellsEditModeMixin:OnImportButtonClick()
	Private.Utils.ShowStaticPopup({
		text = Private.L.Settings.Import,
		button1 = Private.L.Settings.Import,
		button2 = CLOSE,
		hasEditBox = true,
		hasWideEditBox = true,
		editBoxWidth = 350,
		hideOnEscape = true,
		OnAccept = function(popupSelf)
			local editBox = popupSelf:GetEditBox()
			self:OnImportConfirmation(editBox:GetText())
		end,
	})
end

function TargetedSpellsEditModeMixin:OnImportConfirmation(encodedString)
	local hasAnyChange = Private.Utils.Import(encodedString)

	if hasAnyChange then
		LibEditMode:RefreshFrameSettings(self.editModeFrame)
	end
end

function TargetedSpellsEditModeMixin:OnImportCancellation()
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:CreateSetting(key, defaults)
	local L = Private.L

	if key == Private.Settings.Keys.Self.FontFlags or key == Private.Settings.Keys.Party.FontFlags then
		local tableRef = key == Private.Settings.Keys.Self.FontFlags and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.FontFlags) do
				local function IsEnabled()
					return tableRef.FontFlags[id] == true
				end

				local function Toggle()
					tableRef.FontFlags[id] = not tableRef.FontFlags[id]

					Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, tableRef.FontFlags)
				end

				local translated = L.Settings.FontFlagsLabels[id]

				rootDescription:CreateCheckbox(translated, IsEnabled, Toggle, {
					value = label,
					multiple = true,
				})
			end
		end

		---@param layoutName string
		---@param values table<string, boolean>
		local function Set(layoutName, values)
			local hasChanges = false

			for id, bool in pairs(values) do
				if tableRef.FontFlags[id] ~= bool then
					tableRef.FontFlags[id] = bool
					hasChanges = true
				end
			end

			if hasChanges then
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, tableRef.FontFlags)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FontFlagsLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.FontFlags,
			desc = L.Settings.FontFlagsTooltip,
			generator = Generator,
			-- technically is a reset only
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.Font or key == Private.Settings.Keys.Party.Font then
		local tableRef = key == Private.Settings.Keys.Self.Font and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		---@param value string
		local function Set(layoutName, value)
			if tableRef.Font ~= value then
				tableRef.Font = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@param path string
		---@param label string
		---@return string globalName
		local function CreateAndGetFontIfNeeded(path, label)
			local sanitizedName = string.gsub(label, " ", "")
			local globalName = addonName .. "_" .. sanitizedName

			if _G[globalName] == nil then
				local locale = GAME_LOCALE or GetLocale()
				local overrideAlphabet = "roman"
				if locale == "koKR" then
					overrideAlphabet = "korean"
				elseif locale == "zhCN" then
					overrideAlphabet = "simplifiedchinese"
				elseif locale == "zhTW" then
					overrideAlphabet = "traditionalchinese"
				elseif locale == "ruRU" then
					overrideAlphabet = "russian"
				end

				local members = {}
				local coreFont = GameFontNormal
				local alphabets = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }
				for _, alphabet in ipairs(alphabets) do
					local forAlphabet = coreFont:GetFontObjectForAlphabet(alphabet)
					local file, size, _ = forAlphabet:GetFont()
					if alphabet == overrideAlphabet then
						table.insert(members, {
							alphabet = alphabet,
							file = path,
							height = size,
							flags = "",
						})
					else
						table.insert(members, {
							alphabet = alphabet,
							file = file,
							height = size,
							flags = "",
						})
					end
				end

				local font = CreateFontFamily(globalName, members)
				font:SetTextColor(1, 1, 1)
				_G[globalName] = font
			end

			return globalName
		end

		local function Generator(owner, rootDescription, data)
			local fontInfo = Private.Settings.GetFontOptions()

			for index, label in pairs(fontInfo.fonts) do
				local path = fontInfo.byLabel[label]

				local function IsEnabled()
					return tableRef.Font == path
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), path)
				end

				local radio = rootDescription:CreateRadio(label, IsEnabled, SetProxy)

				radio:AddInitializer(function(button, elementDescription, menu)
					local globalName = CreateAndGetFontIfNeeded(path, label)
					button.fontString:SetFontObject(globalName)
				end)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FontLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			desc = L.Settings.FontTooltip,
			default = defaults.Font,
			multiple = false,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.Opacity or key == Private.Settings.Keys.Party.Opacity then
		local tableRef = key == Private.Settings.Keys.Self.Opacity and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.Opacity
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= tableRef.Opacity then
				tableRef.Opacity = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.OpacityLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.Opacity,
			desc = L.Settings.OpacityTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
			formatter = FormatPercentage,
		}
	end

	if key == Private.Settings.Keys.Self.IconZoom or key == Private.Settings.Keys.Party.IconZoom then
		local tableRef = key == Private.Settings.Keys.Self.IconZoom and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.IconZoom
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= tableRef.IconZoom then
				tableRef.IconZoom = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.IconZoomLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.IconZoom,
			desc = L.Settings.IconZoomTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
			formatter = FormatPercentage,
		}
	end

	if key == Private.Settings.Keys.Self.FeatureFlags or key == Private.Settings.Keys.Party.FeatureFlags then
		local kind = key == Private.Settings.Keys.Self.FeatureFlags and Private.Enum.FrameKind.Self
			or Private.Enum.FrameKind.Party
		local tableRef = kind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		local function Generator(owner, rootDescription, data)
			for _, id in ipairs(Private.Settings.GetFeatureFlagsForKind(kind)) do
				local title = L.Settings.FeatureFlagSettingTitles[id]

				if title then
					rootDescription:CreateTitle(title)
				end

				local function IsEnabled()
					return tableRef.FeatureFlags[id] == true
				end

				local function Toggle()
					tableRef.FeatureFlags[id] = not tableRef.FeatureFlags[id]
					Private.EventRegistry:TriggerEvent(
						Private.Enum.Events.SETTING_CHANGED,
						key,
						id,
						tableRef.FeatureFlags[id]
					)
				end

				rootDescription:CreateCheckbox(L.Settings.FeatureFlagLabels[id], IsEnabled, Toggle, {
					value = id,
					multiple = true,
				})
			end
		end

		---@param layoutName string
		---@param values table<number, boolean>
		local function Set(layoutName, values)
			for id, bool in pairs(values) do
				if tableRef.FeatureFlags[id] ~= bool then
					tableRef.FeatureFlags[id] = bool
					Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, id, bool)
				end
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FeatureFlagsLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.FeatureFlags,
			desc = L.Settings.FeatureFlagsTooltip,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.GlowType or key == Private.Settings.Keys.Party.GlowType then
		local tableRef = key == Private.Settings.Keys.Self.GlowType and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if tableRef.GlowType ~= value then
				tableRef.GlowType = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.GlowType) do
				local function IsEnabled()
					return tableRef.GlowType == id
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), id)
				end

				local translated = L.Settings.GlowTypeLabels[id]

				rootDescription:CreateRadio(translated, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.GlowTypeLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			desc = L.Settings.GlowTypeTooltip,
			default = defaults.GlowType,
			multiple = false,
			generator = Generator,
			set = Set,
			disabled = not tableRef.FeatureFlags[Private.Enum.FeatureFlag.GlowImportant],
		}
	end

	if key == Private.Settings.Keys.Self.Enabled or key == Private.Settings.Keys.Party.Enabled then
		local tableRef = key == Private.Settings.Keys.Self.Enabled and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.Enabled
		end

		---@param layoutName string
		---@param value boolean
		local function Set(layoutName, value)
			if value ~= tableRef.Enabled then
				tableRef.Enabled = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeCheckbox
		return {
			name = L.Settings.EnabledLabel,
			kind = Enum.EditModeSettingDisplayType.Checkbox,
			default = defaults.Enabled,
			desc = L.Settings.EnabledTooltip,
			get = Get,
			set = Set,
		}
	end

	if
		key == Private.Settings.Keys.Self.LoadConditionContentType
		or key == Private.Settings.Keys.Party.LoadConditionContentType
	then
		local isSelf = key == Private.Settings.Keys.Self.LoadConditionContentType
		local kindTableRef = isSelf and TargetedSpellsSaved.Settings.Self or TargetedSpellsSaved.Settings.Party

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.ContentType) do
				if
					Private.Settings.IsContentTypeAvailableForKind(
						isSelf and Private.Enum.FrameKind.Self or Private.Enum.FrameKind.Party,
						id
					)
				then
					local function IsEnabled()
						return kindTableRef.LoadConditionContentType[id]
					end

					local function Toggle()
						kindTableRef.LoadConditionContentType[id] = not kindTableRef.LoadConditionContentType[id]

						Private.EventRegistry:TriggerEvent(
							Private.Enum.Events.SETTING_CHANGED,
							key,
							kindTableRef.LoadConditionContentType
						)

						local anyEnabled = false
						for role, loadCondition in pairs(kindTableRef.LoadConditionContentType) do
							if loadCondition then
								anyEnabled = true
								break
							end
						end

						local kindTableRef = isSelf and TargetedSpellsSaved.Settings.Self
							or TargetedSpellsSaved.Settings.Party

						if anyEnabled ~= kindTableRef.Enabled then
							kindTableRef.Enabled = anyEnabled
							local enabledKey = isSelf and Private.Settings.Keys.Self.Enabled
								or Private.Settings.Keys.Party.Enabled
							Private.EventRegistry:TriggerEvent(
								Private.Enum.Events.SETTING_CHANGED,
								enabledKey,
								anyEnabled
							)

							LibEditMode:RefreshFrameSettings(self.editModeFrame)
						end
					end

					local translated = L.Settings.LoadConditionContentTypeLabels[id]
					rootDescription:CreateCheckbox(translated, IsEnabled, Toggle, {
						value = label,
						multiple = true,
					})
				end
			end
		end

		---@param layoutName string
		---@param values table<string, boolean>
		local function Set(layoutName, values)
			local hasChanges = false

			for id, bool in pairs(values) do
				if kindTableRef.LoadConditionContentType[id] ~= bool then
					kindTableRef.LoadConditionContentType[id] = bool
					hasChanges = true
				end
			end

			if hasChanges then
				Private.EventRegistry:TriggerEvent(
					Private.Enum.Events.SETTING_CHANGED,
					key,
					kindTableRef.LoadConditionContentType
				)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.LoadConditionContentTypeLabelAbbreviated,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.LoadConditionContentType,
			desc = L.Settings.LoadConditionContentTypeTooltip,
			generator = Generator,
			-- technically is a reset only
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.LoadConditionRole or key == Private.Settings.Keys.Party.LoadConditionRole then
		local isSelf = key == Private.Settings.Keys.Self.LoadConditionRole
		local kindTableRef = isSelf and TargetedSpellsSaved.Settings.Self or TargetedSpellsSaved.Settings.Party

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.Role) do
				local function IsEnabled()
					return kindTableRef.LoadConditionRole[id] == true
				end

				local function Toggle()
					kindTableRef.LoadConditionRole[id] = not kindTableRef.LoadConditionRole[id]

					Private.EventRegistry:TriggerEvent(
						Private.Enum.Events.SETTING_CHANGED,
						key,
						kindTableRef.LoadConditionRole
					)

					local anyEnabled = false
					for role, loadCondition in pairs(kindTableRef.LoadConditionRole) do
						if loadCondition then
							anyEnabled = true
							break
						end
					end

					if anyEnabled ~= kindTableRef.Enabled then
						kindTableRef.Enabled = anyEnabled
						local enabledKey = isSelf and Private.Settings.Keys.Self.Enabled
							or Private.Settings.Keys.Party.Enabled
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, enabledKey, anyEnabled)

						LibEditMode:RefreshFrameSettings(self.editModeFrame)
					end
				end

				local translated = L.Settings.LoadConditionRoleLabels[id]

				rootDescription:CreateCheckbox(translated, IsEnabled, Toggle, {
					value = label,
					multiple = true,
				})
			end
		end

		---@param layoutName string
		---@param values table<string, boolean>
		local function Set(layoutName, values)
			local hasChanges = false

			for id, bool in pairs(values) do
				if kindTableRef.LoadConditionRole[id] ~= bool then
					kindTableRef.LoadConditionRole[id] = bool
					hasChanges = true
				end
			end

			if hasChanges then
				Private.EventRegistry:TriggerEvent(
					Private.Enum.Events.SETTING_CHANGED,
					key,
					kindTableRef.LoadConditionRole
				)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.LoadConditionRoleLabelAbbreviated,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.LoadConditionRole,
			desc = L.Settings.LoadConditionRoleTooltip,
			generator = Generator,
			-- technically is a reset only
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Party.RoleFilter then
		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.Role) do
				local function IsEnabled()
					return TargetedSpellsSaved.Settings.Party.RoleFilter[id] == true
				end

				local function Toggle()
					TargetedSpellsSaved.Settings.Party.RoleFilter[id] =
						not TargetedSpellsSaved.Settings.Party.RoleFilter[id]

					Private.EventRegistry:TriggerEvent(
						Private.Enum.Events.SETTING_CHANGED,
						key,
						TargetedSpellsSaved.Settings.Party.RoleFilter
					)
				end

				local translated = L.Settings.RoleFilterLabels[id]

				rootDescription:CreateCheckbox(translated, IsEnabled, Toggle, {
					value = label,
					multiple = true,
				})
			end
		end

		---@param layoutName string
		---@param values table<string, boolean>
		local function Set(layoutName, values)
			local hasChanges = false

			for id, bool in pairs(values) do
				if TargetedSpellsSaved.Settings.Party.RoleFilter[id] ~= bool then
					TargetedSpellsSaved.Settings.Party.RoleFilter[id] = bool
					hasChanges = true
				end
			end

			if hasChanges then
				Private.EventRegistry:TriggerEvent(
					Private.Enum.Events.SETTING_CHANGED,
					key,
					TargetedSpellsSaved.Settings.Party.RoleFilter
				)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.RoleFilterLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.RoleFilter,
			desc = L.Settings.RoleFilterTooltip,
			generator = Generator,
			-- technically is a reset only
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.FontSize or key == Private.Settings.Keys.Party.FontSize then
		local tableRef = key == Private.Settings.Keys.Self.FontSize and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.FontSize
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= tableRef.FontSize then
				tableRef.FontSize = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.FontSizeLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.FontSize,
			desc = L.Settings.FontSizeTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
			disabled = not tableRef.FeatureFlags[Private.Enum.FeatureFlag.ShowDuration],
		}
	end

	if key == Private.Settings.Keys.Self.Width or key == Private.Settings.Keys.Party.Width then
		local tableRef = key == Private.Settings.Keys.Self.Width and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.Width
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= tableRef.Width then
				tableRef.Width = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.FrameWidthLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.Width,
			desc = L.Settings.FrameWidthTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
		}
	end

	if key == Private.Settings.Keys.Self.Height or key == Private.Settings.Keys.Party.Height then
		local tableRef = key == Private.Settings.Keys.Self.Height and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.Height
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= tableRef.Height then
				tableRef.Height = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.FrameHeightLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.Height,
			desc = L.Settings.FrameHeightTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
		}
	end

	if key == Private.Settings.Keys.Self.Gap or key == Private.Settings.Keys.Party.Gap then
		local tableRef = key == Private.Settings.Keys.Self.Gap and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return tableRef.Gap
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= tableRef.Gap then
				tableRef.Gap = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.FrameGapLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.Gap,
			desc = L.Settings.FrameGapTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
		}
	end

	if key == Private.Settings.Keys.Self.Direction or key == Private.Settings.Keys.Party.Direction then
		local tableRef = key == Private.Settings.Keys.Self.Direction and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if tableRef.Direction ~= value then
				tableRef.Direction = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.Direction) do
				local function IsEnabled()
					return tableRef.Direction == id
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), id)
				end

				local translated = id == Private.Enum.Direction.Horizontal and L.Settings.FrameDirectionHorizontal
					or L.Settings.FrameDirectionVertical

				rootDescription:CreateRadio(translated, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FrameDirectionLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.Direction,
			desc = L.Settings.FrameDirectionTooltip,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Party.OffsetX then
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return TargetedSpellsSaved.Settings.Party.OffsetX
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= TargetedSpellsSaved.Settings.Party.OffsetX then
				TargetedSpellsSaved.Settings.Party.OffsetX = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.FrameOffsetXLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.OffsetX,
			desc = L.Settings.FrameOffsetXTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
		}
	end

	if key == Private.Settings.Keys.Party.OffsetY then
		local sliderSettings = Private.Settings.GetSliderSettingsForOption(key)

		---@param layoutName string
		local function Get(layoutName)
			return TargetedSpellsSaved.Settings.Party.OffsetY
		end

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if value ~= TargetedSpellsSaved.Settings.Party.OffsetY then
				TargetedSpellsSaved.Settings.Party.OffsetY = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		---@type LibEditModeSlider
		return {
			name = L.Settings.FrameOffsetYLabel,
			kind = Enum.EditModeSettingDisplayType.Slider,
			default = defaults.OffsetY,
			desc = L.Settings.FrameOffsetYTooltip,
			get = Get,
			set = Set,
			minValue = sliderSettings.min,
			maxValue = sliderSettings.max,
			valueStep = sliderSettings.step,
		}
	end

	if key == Private.Settings.Keys.Party.SourceAnchor then
		---@param layoutName string
		---@param value string
		local function Set(layoutName, value)
			if TargetedSpellsSaved.Settings.Party.SourceAnchor ~= value then
				TargetedSpellsSaved.Settings.Party.SourceAnchor = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for label, enumValue in pairs(Private.Enum.Anchor) do
				local function IsEnabled()
					return TargetedSpellsSaved.Settings.Party.SourceAnchor == enumValue
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), enumValue)
				end

				rootDescription:CreateRadio(label, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FrameSourceAnchorLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.SourceAnchor,
			desc = L.Settings.FrameSourceAnchorTooltip,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Party.TargetAnchor then
		---@param layoutName string
		---@param value string
		local function Set(layoutName, value)
			if TargetedSpellsSaved.Settings.Party.TargetAnchor ~= value then
				TargetedSpellsSaved.Settings.Party.TargetAnchor = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for label, enumValue in pairs(Private.Enum.Anchor) do
				local function IsEnabled()
					return TargetedSpellsSaved.Settings.Party.TargetAnchor == enumValue
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), enumValue)
				end

				rootDescription:CreateRadio(label, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FrameTargetAnchorLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.TargetAnchor,
			desc = L.Settings.FrameTargetAnchorTooltip,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.SortOrder or key == Private.Settings.Keys.Party.SortOrder then
		local tableRef = key == Private.Settings.Keys.Self.SortOrder and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if tableRef.SortOrder ~= value then
				tableRef.SortOrder = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.SortOrder) do
				local function IsEnabled()
					return tableRef.SortOrder == id
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), id)
				end

				local translated = id == Private.Enum.SortOrder.Ascending and L.Settings.FrameSortOrderAscending
					or L.Settings.FrameSortOrderDescending

				rootDescription:CreateRadio(translated, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FrameSortOrderLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.SortOrder,
			desc = L.Settings.FrameSortOrderTooltip,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.Grow or key == Private.Settings.Keys.Party.Grow then
		local tableRef = key == Private.Settings.Keys.Self.Grow and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		---@param value number
		local function Set(layoutName, value)
			if tableRef.Grow ~= value then
				tableRef.Grow = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for label, id in pairs(Private.Enum.Grow) do
				local function IsEnabled()
					return tableRef.Grow == id
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), id)
				end

				local translated = L.Settings.FrameGrowLabels[id]

				rootDescription:CreateRadio(translated, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.FrameGrowLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.Grow,
			desc = L.Settings.FrameGrowTooltip,
			generator = Generator,
			set = Set,
		}
	end

	if key == Private.Settings.Keys.Self.BorderStyle or key == Private.Settings.Keys.Party.BorderStyle then
		local tableRef = key == Private.Settings.Keys.Self.BorderStyle and TargetedSpellsSaved.Settings.Self
			or TargetedSpellsSaved.Settings.Party

		---@param layoutName string
		---@param value string
		local function Set(layoutName, value)
			if tableRef.BorderStyle ~= value then
				tableRef.BorderStyle = value
				Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
			end
		end

		local function Generator(owner, rootDescription, data)
			for _, label in ipairs(Private.Settings.GetBorderOptions()) do
				local function IsEnabled()
					return tableRef.BorderStyle == label
				end

				local function SetProxy()
					Set(LibEditMode:GetActiveLayoutName(), label)
				end

				rootDescription:CreateRadio(label, IsEnabled, SetProxy)
			end
		end

		---@type LibEditModeDropdown
		return {
			name = L.Settings.BorderStyleLabel,
			kind = Enum.EditModeSettingDisplayType.Dropdown,
			default = defaults.BorderStyle,
			desc = L.Settings.BorderStyleTooltip,
			generator = Generator,
			set = Set,
		}
	end

	error(
		string.format(
			"Edit Mode Settings for key '%s' are either not implemented or you're calling this with the wrong key.",
			key or "NO KEY"
		)
	)
end

function TargetedSpellsEditModeMixin:OnLayoutSettingChanged(key, value)
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:AppendSettings()
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:AcquireFrame()
	local frame = Private.Utils.Pool:Acquire()

	frame:PostCreate("preview", self.frameKind, nil)

	return frame
end

function TargetedSpellsEditModeMixin:OnEditModePositionChanged(frame, layoutName, point, x, y)
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:RepositionPreviewFrames()
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:LoopFrame(frame, index)
	frame:SetSpellId()
	frame:SetStartTime()
	local castTime = 4 + index / 2
	local duration = C_DurationUtil.CreateDuration()
	duration:SetTimeFromStart(GetTime(), castTime)
	frame:SetDuration(duration)
	frame:Show()
	frame:SetAlpha(secretwrap(1))

	local tableRef = self.frameKind == Private.Enum.FrameKind.Self and TargetedSpellsSaved.Settings.Self
		or TargetedSpellsSaved.Settings.Party

	if tableRef.FeatureFlags[Private.Enum.FeatureFlag.GlowImportant] and Private.Utils.RollDice() then
		frame:ShowGlow(secretwrap(true))

		if tableRef.FeatureFlags[Private.Enum.FeatureFlag.OnlyImportant] then
			frame:SetAlpha(secretwrap(1))
		end
	else
		frame:HideGlow()

		if tableRef.FeatureFlags[Private.Enum.FeatureFlag.OnlyImportant] then
			frame:SetAlpha(secretwrap(0))
		end
	end

	self:RepositionPreviewFrames()

	table.insert(
		self.demoTimers.timers,
		C_Timer.NewTimer(castTime, function()
			frame:ClearStartTime()
			frame:Hide()
			self:RepositionPreviewFrames()
		end)
	)
end

function TargetedSpellsEditModeMixin:StartDemo()
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:ReleaseAllFrames()
	-- Implement in your derived mixin.
end

function TargetedSpellsEditModeMixin:EndDemo()
	if not self.demoPlaying then
		return
	end

	for _, ticker in pairs(self.demoTimers.tickers) do
		ticker:Cancel()
	end

	for _, timer in pairs(self.demoTimers.timers) do
		timer:Cancel()
	end

	table.wipe(self.demoTimers.tickers)
	table.wipe(self.demoTimers.timers)

	self:ReleaseAllFrames()

	self.demoPlaying = false
end

---@class TargetedSpellsSelfEditMode
local SelfEditModeMixin = CreateFromMixins(TargetedSpellsEditModeMixin)

function SelfEditModeMixin:Init()
	TargetedSpellsEditModeMixin.Init(self, Private.L.EditMode.TargetedSpellsSelfLabel, Private.Enum.FrameKind.Self)
	self.maxFrames = 5

	PixelUtil.SetPoint(self.editModeFrame, "CENTER", UIParent, "CENTER", 0, 0)
	self:ResizeEditModeFrame()
end

function SelfEditModeMixin:ResizeEditModeFrame()
	local width, gap, height, direction =
		TargetedSpellsSaved.Settings.Self.Width,
		TargetedSpellsSaved.Settings.Self.Gap,
		TargetedSpellsSaved.Settings.Self.Height,
		TargetedSpellsSaved.Settings.Self.Direction

	if direction == Private.Enum.Direction.Horizontal then
		local totalWidth = (self.maxFrames * width) + (self.maxFrames - 1) * gap
		PixelUtil.SetSize(self.editModeFrame, totalWidth, height)
	else
		local totalHeight = (self.maxFrames * height) + (self.maxFrames - 1) * gap
		PixelUtil.SetSize(self.editModeFrame, width, totalHeight)
	end
end

function SelfEditModeMixin:ReleaseAllFrames()
	for index, frame in ipairs(self.frames) do
		Private.Utils.Pool:Release(frame)
	end

	table.wipe(self.frames)
end

function SelfEditModeMixin:AppendSettings()
	LibEditMode:AddFrame(
		self.editModeFrame,
		GenerateClosure(self.OnEditModePositionChanged, self),
		Private.Settings.GetDefaultEditModeFramePosition(),
		Private.L.EditMode.TargetedSpellsSelfLabel
	)

	LibEditMode:RegisterCallback("layout", GenerateClosure(self.RestoreEditModePosition, self))

	local settingsOrder = Private.Settings.GetSettingsDisplayOrder(Private.Enum.FrameKind.Self)
	local settings = {}
	local defaults = Private.Settings.GetSelfDefaultSettings()

	for i, key in ipairs(settingsOrder) do
		table.insert(settings, self:CreateSetting(key, defaults))
	end

	LibEditMode:AddFrameSettings(self.editModeFrame, settings)
	LibEditMode:AddFrameSettingsButtons(self.editModeFrame, self:CreateImportExportButtons())
end

function SelfEditModeMixin:RestoreEditModePosition()
	self.editModeFrame:ClearAllPoints()
	PixelUtil.SetPoint(
		self.editModeFrame,
		"CENTER",
		UIParent,
		TargetedSpellsSaved.Settings.Self.Position.point,
		TargetedSpellsSaved.Settings.Self.Position.x,
		TargetedSpellsSaved.Settings.Self.Position.y
	)
end

function SelfEditModeMixin:OnEditModePositionChanged(frame, layoutName, point, x, y)
	TargetedSpellsSaved.Settings.Self.Position.point = point
	TargetedSpellsSaved.Settings.Self.Position.x = x
	TargetedSpellsSaved.Settings.Self.Position.y = y

	Private.EventRegistry:TriggerEvent(Private.Enum.Events.EDIT_MODE_POSITION_CHANGED, point, x, y)
end

function SelfEditModeMixin:RepositionPreviewFrames()
	if not self.demoPlaying then
		return
	end

	---@type TargetedSpellsMixin[]
	local activeFrames = {}

	for index = 1, self.maxFrames do
		if self.frames[index] == nil then
			self.frames[index] = self:AcquireFrame()

			table.insert(
				self.demoTimers.tickers,
				C_Timer.NewTicker(5 + index, GenerateClosure(self.LoopFrame, self, self.frames[index], index))
			)

			self:LoopFrame(self.frames[index], index)
		end

		local frame = self.frames[index]

		if frame:ShouldBeShown() then
			table.insert(activeFrames, frame)
		end
	end

	if #activeFrames == 0 then
		return
	end

	local tableRef = TargetedSpellsSaved.Settings.Self

	Private.Utils.SortFrames(activeFrames, tableRef.SortOrder)

	local layouting = Private.Utils.CollectLayoutingArguments(
		tableRef.Direction,
		tableRef.Grow,
		tableRef.Width,
		tableRef.Height,
		tableRef.Gap
	)

	local parentDimension = layouting.isHorizontal and self.editModeFrame:GetWidth() or self.editModeFrame:GetHeight()
	local offset = layouting.isGrowEnd and (parentDimension / 2 - tableRef.Gap) or (-parentDimension / 2)

	Private.Utils.AdjustLayout(
		activeFrames,
		layouting,
		self.editModeFrame,
		"CENTER",
		layouting.isHorizontal and offset or 0,
		(not layouting.isHorizontal) and offset or 0,
		true
	)
end

function SelfEditModeMixin:StartDemo()
	if self.demoPlaying or not TargetedSpellsSaved.Settings.Self.Enabled or not self:IsPastLoadingScreen() then
		return
	end

	self.demoPlaying = true

	self:RepositionPreviewFrames()
end

function SelfEditModeMixin:OnLayoutSettingChanged(key, value)
	if
		key == Private.Settings.Keys.Self.Gap
		or key == Private.Settings.Keys.Self.Direction
		or key == Private.Settings.Keys.Self.Width
		or key == Private.Settings.Keys.Self.Height
		or key == Private.Settings.Keys.Self.SortOrder
		or key == Private.Settings.Keys.Self.Grow
	then
		if
			key == Private.Settings.Keys.Self.Width
			or key == Private.Settings.Keys.Self.Height
			or key == Private.Settings.Keys.Self.Gap
			or key == Private.Settings.Keys.Self.Direction
		then
			self:ResizeEditModeFrame()
		end

		self:RepositionPreviewFrames()
	elseif key == Private.Settings.Keys.Self.GlowImportant then
		local glowEnabled = value

		for _, frame in pairs(self.frames) do
			if glowEnabled and frame:IsVisible() and Private.Utils.RollDice() then
				frame:ShowGlow(true)
			else
				frame:HideGlow()
			end
		end
	elseif key == Private.Settings.Keys.Self.GlowType then
		if not TargetedSpellsSaved.Settings.Self.FeatureFlags[Private.Enum.FeatureFlag.GlowImportant] then
			return
		end

		for _, frame in pairs(self.frames) do
			if frame:IsVisible() and Private.Utils.RollDice() then
				frame:ShowGlow(true)
			else
				frame:HideGlow()
			end
		end
	end
end

table.insert(Private.LoginFnQueue, GenerateClosure(SelfEditModeMixin.Init, SelfEditModeMixin))

---@class TargetedSpellsPartyEditMode
local PartyEditModeMixin = CreateFromMixins(TargetedSpellsEditModeMixin)

function PartyEditModeMixin:Init()
	TargetedSpellsEditModeMixin.Init(self, Private.L.EditMode.TargetedSpellsPartyLabel, Private.Enum.FrameKind.Party)
	self.maxUnitCount = 5
	self.amountOfPreviewFramesPerUnit = 3
	self.useRaidStylePartyFrames = self.useRaidStylePartyFrames or EditModeManagerFrame:UseRaidStylePartyFrames()
	self:RepositionEditModeFrame()

	-- when this executes, layouts aren't loaded yet
	hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", function(editModeManagerSelf)
		if TargetedSpellsSaved.Settings.Party.Enabled then
			local accountSettings = C_EditMode.GetAccountSettings()

			for i, setting in pairs(accountSettings) do
				if setting.setting == Enum.EditModeAccountSetting.ShowPartyFrames and setting.value == 0 then
					C_EditMode.SetAccountSetting(Enum.EditModeAccountSetting.ShowPartyFrames, 1)
					break
				end
			end
		end

		local useRaidStylePartyFrames = EditModeManagerFrame:UseRaidStylePartyFrames()

		if useRaidStylePartyFrames == self.useRaidStylePartyFrames then
			return
		end

		self.useRaidStylePartyFrames = useRaidStylePartyFrames
		self:RepositionEditModeFrame()
	end)

	-- dirtying checkboxes while edit mode is opened doesn't fire any events
	hooksecurefunc(EditModeManagerFrame, "OnAccountSettingChanged", function(editModeManagerSelf, accountSetting, value)
		if
			not TargetedSpellsSaved.Settings.Party.Enabled
			or accountSetting ~= Enum.EditModeAccountSetting.ShowPartyFrames
		then
			return
		end

		if value then
			self:StartDemo()
			self:RepositionEditModeFrame()
			self.editModeFrame:Show()
		else
			self:EndDemo()
			self.editModeFrame:Hide()
		end
	end)

	-- dirtying settings while edit mode is opened doesn't fire any events eitehr
	hooksecurefunc(EditModeSystemSettingsDialog, "OnSettingValueChanged", function(settingsSelf, setting, checked)
		if
			not TargetedSpellsSaved.Settings.Party.Enabled
			or setting ~= Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames
		then
			return
		end

		local useRaidStylePartyFrames = checked == 1

		if useRaidStylePartyFrames == self.useRaidStylePartyFrames then
			return
		end

		self.useRaidStylePartyFrames = useRaidStylePartyFrames
		self:RepositionEditModeFrame()

		if TargetedSpellsSaved.Settings.Party.Enabled then
			self:EndDemo()
			self:StartDemo()
		end
	end)
end

function PartyEditModeMixin:AppendSettings()
	LibEditMode:AddFrame(
		self.editModeFrame,
		GenerateClosure(self.OnEditModePositionChanged, self),
		Private.Settings.GetDefaultEditModeFramePosition(),
		"Targeted Spells - Party"
	)
	self.editModeFrame:SetScript("OnDragStart", nil)
	self.editModeFrame:SetScript("OnDragStop", nil)

	do
		local cb = GenerateClosure(self.RepositionEditModeFrame, self)

		LibEditMode:RegisterCallback("enter", QUI == nil and cb or function()
			C_Timer.After(0.25, cb)
		end)
	end

	local settingsOrder = Private.Settings.GetSettingsDisplayOrder(Private.Enum.FrameKind.Party)
	local settings = {}
	local defaults = Private.Settings.GetPartyDefaultSettings()

	for i, key in ipairs(settingsOrder) do
		table.insert(settings, self:CreateSetting(key, defaults))
	end

	LibEditMode:AddFrameSettings(self.editModeFrame, settings)
	LibEditMode:AddFrameSettingsButtons(self.editModeFrame, self:CreateImportExportButtons())
end

---@param useRaidStylePartyFrames boolean
---@return Frame, number
local function GetEditModePartyParentFrame(useRaidStylePartyFrames)
	if Vd1 ~= nil then
		return Vd1, Vd1:GetWidth()
	end

	if ShadowUF ~= nil and SUFHeaderparty ~= nil then
		return SUFHeaderparty, SUFHeaderparty:GetWidth()
	end

	if EnhanceQoL ~= nil and EQOLUFPartyHeader ~= nil then
		return EQOLUFPartyHeader, EQOLUFPartyHeader:GetWidth()
	end

	if
		ElvUI ~= nil
		and ElvUI[1].db ~= nil
		and ElvUI[1].db.unitframe.units.party.enable ~= nil
		and ElvUF_Party ~= nil
		and ElvUF_Party:IsShown()
	then
		return ElvUF_Party, ElvUF_Party:GetWidth()
	end

	if QUI ~= nil then
		if QUI_PartyHeader ~= nil and QUI_PartyHeader:IsShown() then
			return QUI_PartyHeader, QUI_PartyHeader:GetWidth()
		end

		if QUI_GroupFramesMover ~= nil then
			return QUI_GroupFramesMover, QUI_GroupFramesMover:GetWidth()
		end
	end

	if Cell ~= nil and CellPartyFrameHeader ~= nil then
		return CellPartyFrameHeader, CellPartyFrameHeader:GetWidth()
	end

	if Private.Utils.HasThirdPartyCandidates() or Grid2 ~= nil or DandersFrames ~= nil then
		local maybeFrame = Private.Utils.FindThirdPartyGroupFrameForUnit("player")

		if maybeFrame then
			local maybeParent = maybeFrame:GetParent()

			if maybeParent then
				return maybeParent, maybeParent:GetWidth()
			end
		end
	end

	if useRaidStylePartyFrames then
		return CompactPartyFrame, CompactPartyFrame.memberUnitFrames[1]:GetWidth()
	end

	return PartyFrame, 125
end

function PartyEditModeMixin:RepositionEditModeFrame()
	local parent, width = GetEditModePartyParentFrame(self.useRaidStylePartyFrames)
	PixelUtil.SetSize(self.editModeFrame, width, 16)
	self.editModeFrame:ClearAllPoints()
	PixelUtil.SetPoint(self.editModeFrame, "CENTER", parent, "TOP", 0, 16)
end

function PartyEditModeMixin:OnEditModePositionChanged()
	self:RepositionEditModeFrame()
end

function PartyEditModeMixin:OnLayoutSettingChanged(key, value)
	if
		key == Private.Settings.Keys.Party.Gap
		or key == Private.Settings.Keys.Party.Direction
		or key == Private.Settings.Keys.Party.Width
		or key == Private.Settings.Keys.Party.Height
		or key == Private.Settings.Keys.Party.OffsetX
		or key == Private.Settings.Keys.Party.OffsetY
		or key == Private.Settings.Keys.Party.SourceAnchor
		or key == Private.Settings.Keys.Party.TargetAnchor
		or key == Private.Settings.Keys.Party.SortOrder
		or key == Private.Settings.Keys.Party.Grow
	then
		self:RepositionPreviewFrames()
	elseif key == Private.Settings.Keys.Party.GlowImportant then
		local glowEnabled = value

		for i, frames in pairs(self.frames) do
			for j, frame in ipairs(frames) do
				if frame:IsVisible() and glowEnabled and Private.Utils.RollDice() then
					frame:ShowGlow(true)
				else
					frame:HideGlow()
				end
			end
		end
	elseif key == Private.Settings.Keys.Party.GlowType then
		if not TargetedSpellsSaved.Settings.Party.FeatureFlags[Private.Enum.FeatureFlag.GlowImportant] then
			return
		end

		for i, frames in pairs(self.frames) do
			for j, frame in ipairs(frames) do
				if frame:IsVisible() and Private.Utils.RollDice() then
					frame:ShowGlow(true)
				else
					frame:HideGlow()
				end
			end
		end
	end
end

function PartyEditModeMixin:RepositionPreviewFrames()
	if not self.demoPlaying then
		return
	end

	local tableRef = TargetedSpellsSaved.Settings.Party

	local offsetX, offsetY, sortOrder, targetAnchor =
		tableRef.OffsetX, tableRef.OffsetY, tableRef.SortOrder, tableRef.TargetAnchor

	local layouting = Private.Utils.CollectLayoutingArguments(
		tableRef.Direction,
		tableRef.Grow,
		tableRef.Width,
		tableRef.Height,
		tableRef.Gap
	)

	for i = 1, self.maxUnitCount do
		if
			i < 5
			or (i == 5 and TargetedSpellsSaved.Settings.Party.FeatureFlags[Private.Enum.FeatureFlag.IncludeSelfInParty])
		then
			local token = i == 5 and "player" or string.format("party%d", i)
			local parentFrame = Private.Utils.FindThirdPartyGroupFrameForUnit(token)

			if parentFrame == nil then
				if self.useRaidStylePartyFrames then
					-- some addons like Danders set alpha to 0
					if CompactPartyFrame:GetAlpha() > 0 then
						---@type Frame
						parentFrame = CompactPartyFrame.memberUnitFrames[i]
					end
				else
					-- same as above
					if PartyFrame:GetAlpha() > 0 then
						for memberFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
							if memberFrame.layoutIndex == i then
								---@type Frame
								parentFrame = memberFrame
								break
							end
						end
					end
				end
			end

			if parentFrame ~= nil then
				if self.frames[i] == nil then
					self.frames[i] = {}
				end

				---@type TargetedSpellsMixin[]
				local activeFrames = {}

				for j = 1, self.amountOfPreviewFramesPerUnit do
					if self.frames[i][j] == nil then
						self.frames[i][j] = self:AcquireFrame()

						table.insert(
							self.demoTimers.tickers,
							C_Timer.NewTicker(
								5 + j + i,
								GenerateClosure(self.LoopFrame, self, self.frames[i][j], j + i)
							)
						)

						self:LoopFrame(self.frames[i][j], j + i)
					end

					local frame = self.frames[i][j]

					if frame:ShouldBeShown() then
						table.insert(activeFrames, frame)
					end
				end

				if #activeFrames > 0 then
					Private.Utils.SortFrames(activeFrames, sortOrder)

					Private.Utils.AdjustLayout(
						activeFrames,
						layouting,
						parentFrame,
						targetAnchor,
						offsetX,
						offsetY,
						true
					)
				end
			end
		end
	end
end

function PartyEditModeMixin:StartDemo()
	if self.demoPlaying or not TargetedSpellsSaved.Settings.Party.Enabled or not self:IsPastLoadingScreen() then
		return
	end

	self.demoPlaying = true

	self:RepositionPreviewFrames()
end

function PartyEditModeMixin:ReleaseAllFrames()
	for unit = 1, self.maxUnitCount do
		local frames = self.frames[unit]

		if frames ~= nil then
			for index = 1, self.amountOfPreviewFramesPerUnit do
				local frame = frames[index]

				if frame then
					Private.Utils.Pool:Release(frame)
					frames[index] = nil
				end
			end
		end
	end
end

table.insert(Private.LoginFnQueue, GenerateClosure(PartyEditModeMixin.Init, PartyEditModeMixin))
