---@type string, AdvancedFocusCastBar
local addonName, Private = ...
local LibCustomGlow = LibStub("LibCustomGlow-1.0")
local LibEditMode = LibStub("LibEditMode")
local LibSharedMedia = LibStub("LibSharedMedia-3.0")

---@class AdvancedFocusCastBarMixin
AdvancedFocusCastBarMixin = {}

function AdvancedFocusCastBarMixin:OnLoad()
	self:Hide()
	self.elapsed = 0

	self.events = {
		-- start or update events
		"UNIT_SPELLCAST_START",
		"UNIT_SPELLCAST_DELAYED",
		"UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_UPDATE",
		"UNIT_SPELLCAST_EMPOWER_START",
		"UNIT_SPELLCAST_EMPOWER_UPDATE",
		-- end or failed events
		"UNIT_SPELLCAST_STOP",
		"UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_EMPOWER_STOP",
		-- meta events
		"UNIT_SPELLCAST_INTERRUPTIBLE",
		"UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	}

	-- color caching
	self.colors = {
		Uninterruptible = CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorUninterruptible),
		InterruptibleCanInterrupt = CreateColorFromHexString(
			AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCanInterrupt
		),
		InterruptibleCannotInterrupt = CreateColorFromHexString(
			AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCannotInterrupt
		),
		InterruptTick = CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorInterruptTick),
	}

	-- initial layouting
	do
		self.CastBar.InterruptBar.Tick = self.CastBar.InterruptBar:CreateTexture()

		self.CastBar.InterruptBar.Tick:SetColorTexture(
			self.colors.InterruptTick.r,
			self.colors.InterruptTick.g,
			self.colors.InterruptTick.b
		)

		self.CastBar.InterruptBar.Tick:SetSize(2, AdvancedFocusCastBarSaved.Settings.Height)
		self:AdjustDirection(false)
		self.CastBar.InterruptBar.Tick:AddMaskTexture(self.CastBar.Mask)
		self.CastBar:SetStatusBarTexture(AdvancedFocusCastBarSaved.Settings.Texture)

		PixelUtil.SetSize(self, AdvancedFocusCastBarSaved.Settings.Width, AdvancedFocusCastBarSaved.Settings.Height)
		PixelUtil.SetSize(
			self.Icon,
			AdvancedFocusCastBarSaved.Settings.Height,
			AdvancedFocusCastBarSaved.Settings.Height
		)
		self:AdjustIconLayout(AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowIcon])
		self:AdjustSpellNameTextWidth()

		do
			local texture = self.CastBar:GetStatusBarTexture()
			if texture then
				texture:SetDrawLayer("BORDER")
			end
		end

		self.Border:SetBackdrop({
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		self.Border:SetBackdropBorderColor(0.1, 0.1, 0.1, 1)
		self.Border:SetShown(AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowBorder])
		self:SetFontAndFontSize()
		self:ToggleTargetNameVisibility()
		self:AdjustCustomTextsPosition()
		self:AdjustBackgroundOpacity()
	end

	-- edit mode setup
	do
		self.firstFrameTimestamp = 0

		LibEditMode:RegisterCallback("enter", GenerateClosure(self.OnEditModeEnter, self))
		LibEditMode:RegisterCallback("exit", GenerateClosure(self.OnEditModeExit, self))
		LibEditMode:RegisterCallback("layout", GenerateClosure(self.RestoreEditModePosition, self))

		Private.EventRegistry:RegisterCallback(
			Private.Enum.Events.EDIT_MODE_POSITION_CHANGED,
			self.OnEvent,
			self,
			Private.Enum.Events.EDIT_MODE_POSITION_CHANGED
		)

		local defaults = Private.Settings.GetDefaultSettings()

		LibEditMode:AddFrame(self, GenerateClosure(self.OnEditModePositionChange, self), {
			point = defaults.Point,
			x = defaults.OffsetX,
			y = defaults.OffsetY,
		}, Private.L.EditMode.AddonName)

		---@param key Setting
		---@return SliderSettings
		local function GetSliderSettingsForOption(key)
			if key == Private.Enum.Setting.SecondaryFontScale then
				return {
					min = 0.1,
					max = 5,
					step = 0.01,
				}
			end

			if key == Private.Enum.Setting.TickWidth then
				return {
					min = 0,
					max = 16,
					step = 1,
				}
			end

			if key == Private.Enum.Setting.FontSize then
				return {
					min = 8,
					max = 32,
					step = 1,
				}
			end

			if key == Private.Enum.Setting.Opacity then
				return {
					min = 0.2,
					max = 1,
					step = 0.01,
				}
			end

			if key == Private.Enum.Setting.OutOfRangeOpacity then
				return {
					min = 0.2,
					max = 1,
					step = 0.01,
				}
			end

			if key == Private.Enum.Setting.BackgroundOpacity then
				return {
					min = 0,
					max = 1,
					step = 0.01,
				}
			end

			if key == Private.Enum.Setting.Width then
				return {
					min = 10,
					max = 2000,
					step = 1,
				}
			end

			if key == Private.Enum.Setting.Height then
				return {
					min = 10,
					max = 1000,
					step = 1,
				}
			end

			if key == Private.Enum.Setting.OffsetX then
				local width = GetPhysicalScreenSize()

				return {
					min = -(width / 2),
					max = (width / 2),
					step = 1,
				}
			end

			if key == Private.Enum.Setting.OffsetY then
				local width, height = GetPhysicalScreenSize()

				return {
					min = -(height / 2),
					max = height / 2,
					step = 1,
				}
			end

			error(
				string.format(
					"Slider Settings for key '%s' are either not implemented or you're calling this with the wrong key.",
					key
				)
			)
		end

		---@param key Setting
		---@return LibEditModeSetting
		local function CreateSetting(key)
			local L = Private.L.Settings

			if key == Private.Enum.Setting.SecondaryFontScale then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.SecondaryFontScale
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					value = math.floor(value * 100) / 100
					if value ~= AdvancedFocusCastBarSaved.Settings.SecondaryFontScale then
						AdvancedFocusCastBarSaved.Settings.SecondaryFontScale = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.SecondaryFontScaleLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.SecondaryFontScale,
					desc = L.SecondaryFontScaleTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			if key == Private.Enum.Setting.Opacity then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.Opacity
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					value = math.floor(value * 100) / 100
					if value ~= AdvancedFocusCastBarSaved.Settings.Opacity then
						AdvancedFocusCastBarSaved.Settings.Opacity = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.OpacityLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.Opacity,
					desc = L.OpacityTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
					formatter = FormatPercentage,
				}
			end

			if key == Private.Enum.Setting.OutOfRangeOpacity then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.OutOfRangeOpacity
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					value = math.floor(value * 100) / 100
					if value ~= AdvancedFocusCastBarSaved.Settings.OutOfRangeOpacity then
						AdvancedFocusCastBarSaved.Settings.OutOfRangeOpacity = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.OutOfRangeOpacityLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.OutOfRangeOpacity,
					desc = L.OutOfRangeOpacityTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
					formatter = FormatPercentage,
				}
			end

			if key == Private.Enum.Setting.BackgroundOpacity then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.BackgroundOpacity
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					value = math.floor(value * 100) / 100
					if value ~= AdvancedFocusCastBarSaved.Settings.BackgroundOpacity then
						AdvancedFocusCastBarSaved.Settings.BackgroundOpacity = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.BackgroundOpacityLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.BackgroundOpacity,
					desc = L.BackgroundOpacityTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
					formatter = FormatPercentage,
				}
			end

			if key == Private.Enum.Setting.TickWidth then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.TickWidth
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					if value ~= AdvancedFocusCastBarSaved.Settings.TickWidth then
						AdvancedFocusCastBarSaved.Settings.TickWidth = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.TickWidthLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.TickWidth,
					desc = L.TickWidthTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			if key == Private.Enum.Setting.FontSize then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.FontSize
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					if value ~= AdvancedFocusCastBarSaved.Settings.FontSize then
						AdvancedFocusCastBarSaved.Settings.FontSize = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.FontSizeLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.FontSize,
					desc = L.FontSizeTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			if key == Private.Enum.Setting.Font then
				---@param layoutName string
				---@param value string
				local function Set(layoutName, value)
					if AdvancedFocusCastBarSaved.Settings.Font ~= value then
						AdvancedFocusCastBarSaved.Settings.Font = value
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

						---@type CreateFontFamilyMemberInfo[]
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
					local fonts = CopyTable(LibSharedMedia:List(LibSharedMedia.MediaType.FONT))
					table.sort(fonts)
					local byLabel = LibSharedMedia:HashTable(LibSharedMedia.MediaType.FONT)

					for index, label in pairs(fonts) do
						local path = byLabel[label]

						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.Font == path
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

					rootDescription:SetScrollMode(30 * 20)
				end

				---@type LibEditModeDropdown
				return {
					name = L.FontLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					desc = L.FontTooltip,
					default = defaults.Font,
					multiple = false,
					generator = Generator,
					set = Set,
				}
			end

			if key == Private.Enum.Setting.Point then
				---@param layoutName string
				---@param value string
				local function Set(layoutName, value)
					AdvancedFocusCastBarSaved.Settings.Point = value

					Private.EventRegistry:TriggerEvent(Private.Enum.Events.EDIT_MODE_POSITION_CHANGED)
				end

				local function Generator(owner, rootDescription, data)
					for pointKey, value in pairs(Private.Enum.Point) do
						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.Point == value
						end

						local function SetProxy()
							Set(LibEditMode:GetActiveLayoutName(), value)
						end

						rootDescription:CreateRadio(value, IsEnabled, SetProxy)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.PointLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					desc = L.PointTooltip,
					default = defaults.Point,
					multiple = false,
					generator = Generator,
					set = Set,
				}
			end

			if key == Private.Enum.Setting.CustomTextsPosition then
				---@param layoutName string
				---@param value string
				local function Set(layoutName, value)
					AdvancedFocusCastBarSaved.Settings.CustomTextsPosition = value

					Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
				end

				local function Generator(owner, rootDescription, data)
					for customTextsPositionKey, value in pairs(Private.Enum.CustomTextsPosition) do
						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.CustomTextsPosition == value
						end

						local function SetProxy()
							Set(LibEditMode:GetActiveLayoutName(), value)
						end

						rootDescription:CreateRadio(L.CustomTextPositionLabels[value], IsEnabled, SetProxy)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.CustomTextPositionLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					desc = L.CustomTextPositionTooltip,
					default = defaults.CustomTextsPosition,
					multiple = false,
					generator = Generator,
					set = Set,
					disabled = not AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowTargetName]
						and not AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowInterruptSource],
				}
			end

			if key == Private.Enum.Setting.Unit then
				---@param layoutName string
				---@param value string
				local function Set(layoutName, value)
					AdvancedFocusCastBarSaved.Settings.Unit = value

					Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
				end

				local function Generator(owner, rootDescription, data)
					for unitKey, value in pairs(Private.Enum.Unit) do
						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.Unit == value
						end

						local function SetProxy()
							Set(LibEditMode:GetActiveLayoutName(), value)
						end

						rootDescription:CreateRadio(L.UnitLabels[value], IsEnabled, SetProxy)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.UnitLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					desc = L.UnitTooltip,
					default = defaults.Unit,
					multiple = false,
					generator = Generator,
					set = Set,
				}
			end

			if key == Private.Enum.Setting.Texture then
				---@param layoutName string
				---@param value string
				local function Set(layoutName, value)
					if AdvancedFocusCastBarSaved.Settings.Texture ~= value then
						AdvancedFocusCastBarSaved.Settings.Texture = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				local function Generator(owner, rootDescription, data)
					local textures = CopyTable(LibSharedMedia:List(LibSharedMedia.MediaType.STATUSBAR))
					table.sort(textures)
					local byLabel = LibSharedMedia:HashTable(LibSharedMedia.MediaType.STATUSBAR)

					for index, label in pairs(textures) do
						local path = byLabel[label]

						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.Texture == path
						end

						local function SetProxy()
							Set(LibEditMode:GetActiveLayoutName(), path)
						end

						rootDescription:CreateRadio(
							string.format("|T%s:%d:%d|t %s", path, 19, 19, label),
							IsEnabled,
							SetProxy
						)
					end

					rootDescription:SetScrollMode(30 * 20)
				end

				---@type LibEditModeDropdown
				return {
					name = L.TextureLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					desc = L.TextureTooltip,
					default = defaults.Texture,
					multiple = false,
					generator = Generator,
					set = Set,
				}
			end

			if key == Private.Enum.Setting.ColorUninterruptible then
				---@param layoutName string
				---@param value ColorMixin
				local function Set(layoutName, value)
					local color = value:GenerateHexColor()

					if AdvancedFocusCastBarSaved.Settings.ColorUninterruptible ~= color then
						AdvancedFocusCastBarSaved.Settings.ColorUninterruptible = color
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, color)
					end
				end

				---@return colorRGBA
				local function Get()
					return CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorUninterruptible)
				end

				---@type LibEditModeColorPicker
				return {
					name = L.ColorUninterruptibleLabel,
					desc = L.ColorUninterruptibleTooltip,
					default = CreateColorFromHexString(defaults.ColorUninterruptible),
					set = Set,
					get = Get,
					kind = LibEditMode.SettingType.ColorPicker,
				}
			end

			if key == Private.Enum.Setting.ColorInterruptibleCanInterrupt then
				---@param layoutName string
				---@param value ColorMixin
				local function Set(layoutName, value)
					local color = value:GenerateHexColor()

					if AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCanInterrupt ~= color then
						AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCanInterrupt = color
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, color)
					end
				end

				---@return colorRGBA
				local function Get()
					return CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCanInterrupt)
				end

				---@type LibEditModeColorPicker
				return {
					name = L.ColorInterruptibleCanInterruptLabel,
					desc = L.ColorInterruptibleCanInterruptTooltip,
					default = CreateColorFromHexString(defaults.ColorInterruptibleCanInterrupt),
					set = Set,
					get = Get,
					kind = LibEditMode.SettingType.ColorPicker,
				}
			end

			if key == Private.Enum.Setting.ColorInterruptibleCannotInterrupt then
				---@param layoutName string
				---@param value ColorMixin
				local function Set(layoutName, value)
					local color = value:GenerateHexColor()

					if AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCannotInterrupt ~= color then
						AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCannotInterrupt = color
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, color)
					end
				end

				---@return colorRGBA
				local function Get()
					return CreateColorFromHexString(
						AdvancedFocusCastBarSaved.Settings.ColorInterruptibleCannotInterrupt
					)
				end

				---@type LibEditModeColorPicker
				return {
					name = L.ColorInterruptibleCannotInterruptLabel,
					desc = L.ColorInterruptibleCannotInterruptTooltip,
					default = CreateColorFromHexString(defaults.ColorInterruptibleCannotInterrupt),
					set = Set,
					get = Get,
					kind = LibEditMode.SettingType.ColorPicker,
				}
			end

			if key == Private.Enum.Setting.ColorGlow then
				---@param layoutName string
				---@param value ColorMixin
				local function Set(layoutName, value)
					local color = value:GenerateHexColor()

					if AdvancedFocusCastBarSaved.Settings.ColorGlow ~= color then
						AdvancedFocusCastBarSaved.Settings.ColorGlow = color
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, color)
					end
				end

				---@return colorRGBA
				local function Get()
					return CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorGlow)
				end

				---@type LibEditModeColorPicker
				return {
					name = L.ColorGlowLabel,
					desc = L.ColorGlowTooltip,
					default = CreateColorFromHexString(defaults.ColorGlow),
					set = Set,
					get = Get,
					kind = LibEditMode.SettingType.ColorPicker,
				}
			end

			if key == Private.Enum.Setting.ColorInterruptTick then
				---@param layoutName string
				---@param value ColorMixin
				local function Set(layoutName, value)
					local color = value:GenerateHexColor()

					if AdvancedFocusCastBarSaved.Settings.ColorInterruptTick ~= color then
						AdvancedFocusCastBarSaved.Settings.ColorInterruptTick = color
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, color)
					end
				end

				---@return colorRGBA
				local function Get()
					return CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorInterruptTick)
				end

				---@type LibEditModeColorPicker
				return {
					name = L.ColorInterruptTickLabel,
					desc = L.ColorInterruptTickTooltip,
					default = CreateColorFromHexString(defaults.ColorInterruptTick),
					set = Set,
					get = Get,
					kind = LibEditMode.SettingType.ColorPicker,
				}
			end

			if key == Private.Enum.Setting.LoadConditionContentType then
				local function Generator(owner, rootDescription, data)
					for label, id in pairs(Private.Enum.ContentType) do
						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.LoadConditionContentType[id]
						end

						local function Toggle()
							AdvancedFocusCastBarSaved.Settings.LoadConditionContentType[id] =
								not AdvancedFocusCastBarSaved.Settings.LoadConditionContentType[id]

							Private.EventRegistry:TriggerEvent(
								Private.Enum.Events.SETTING_CHANGED,
								key,
								AdvancedFocusCastBarSaved.Settings.LoadConditionContentType
							)
						end

						local translated = L.LoadConditionContentTypeLabels[id]
						rootDescription:CreateCheckbox(translated, IsEnabled, Toggle, {
							value = label,
							multiple = true,
						})
					end
				end

				---@param layoutName string
				---@param values table<FeatureFlag, boolean>
				local function Set(layoutName, values)
					local hasChanges = false

					for id, bool in pairs(values) do
						if AdvancedFocusCastBarSaved.Settings.LoadConditionContentType[id] ~= bool then
							AdvancedFocusCastBarSaved.Settings.LoadConditionContentType[id] = bool
							hasChanges = true
						end
					end

					if hasChanges then
						Private.EventRegistry:TriggerEvent(
							Private.Enum.Events.SETTING_CHANGED,
							key,
							AdvancedFocusCastBarSaved.Settings.LoadConditionContentType
						)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.LoadConditionContentTypeLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					default = defaults.LoadConditionContentType,
					desc = L.LoadConditionContentTypeTooltip,
					generator = Generator,
					-- technically is a reset only
					set = Set,
				}
			end

			if key == Private.Enum.Setting.FeatureFlag then
				local function Generator(owner, rootDescription, data)
					local order = {
						Private.Enum.FeatureFlag.ShowIcon,
						Private.Enum.FeatureFlag.ShowCastTime,
						Private.Enum.FeatureFlag.ShowBorder,
						Private.Enum.FeatureFlag.ShowImportantSpellsGlow,
						Private.Enum.FeatureFlag.ShowTargetMarker,
						Private.Enum.FeatureFlag.ShowTargetName,
						Private.Enum.FeatureFlag.UseTargetClassColor,
						Private.Enum.FeatureFlag.ShowInterruptSource,
						Private.Enum.FeatureFlag.UseInterruptSourceClassColor,
						Private.Enum.FeatureFlag.PlayTTSOnCastStart,
						Private.Enum.FeatureFlag.PlayTargetingTTSReminder,
						Private.Enum.FeatureFlag.UnfillChannels,
						Private.Enum.FeatureFlag.IgnoreFriendlies,
						Private.Enum.FeatureFlag.HideWhenUninterruptible,
					}

					for index, id in ipairs(order) do
						local title = L.FeatureFlagSettingTitles[id]

						if title then
							if index > 0 then
								rootDescription:CreateDivider()
							end

							rootDescription:CreateTitle(title)
						end

						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.FeatureFlags[id]
						end

						local function Toggle()
							AdvancedFocusCastBarSaved.Settings.FeatureFlags[id] =
								not AdvancedFocusCastBarSaved.Settings.FeatureFlags[id]

							Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, { id })

							if
								id == Private.Enum.FeatureFlag.ShowInterruptSource
								or id == Private.Enum.FeatureFlag.ShowTargetName
							then
								local thisState = AdvancedFocusCastBarSaved.Settings.FeatureFlags[id]

								local otherId = id == Private.Enum.FeatureFlag.ShowInterruptSource
										and Private.Enum.FeatureFlag.ShowTargetName
									or Private.Enum.FeatureFlag.ShowInterruptSource
								local otherState = AdvancedFocusCastBarSaved.Settings.FeatureFlags[otherId]

								if not thisState and not otherState then
									LibEditMode:DisableFrameSetting(self, L.CustomTextPositionLabel)
								else
									LibEditMode:EnableFrameSetting(self, L.CustomTextPositionLabel)
								end
							end
						end

						local translated = L.FeatureFlagLabels[id]
						rootDescription:CreateCheckbox(translated, IsEnabled, Toggle, {
							value = id,
							multiple = true,
						})
					end
				end

				---@param layoutName string
				---@param values table<string, boolean>
				local function Set(layoutName, values)
					local hasChanges = false
					local changedIds = {}

					for id, bool in pairs(values) do
						if AdvancedFocusCastBarSaved.Settings.FeatureFlags[id] ~= bool then
							AdvancedFocusCastBarSaved.Settings.FeatureFlags[id] = bool
							hasChanges = true
							table.insert(changedIds, id)
						end
					end

					if hasChanges then
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, changedIds)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.FeatureFlagLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					default = defaults.FeatureFlags,
					desc = L.FeatureFlagTooltip,
					generator = Generator,
					-- technically is a reset only
					set = Set,
				}
			end

			if key == Private.Enum.Setting.LoadConditionRole then
				local function Generator(owner, rootDescription, data)
					for label, id in pairs(Private.Enum.Role) do
						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.LoadConditionRole[id] == true
						end

						local function Toggle()
							AdvancedFocusCastBarSaved.Settings.LoadConditionRole[id] =
								not AdvancedFocusCastBarSaved.Settings.LoadConditionRole[id]

							Private.EventRegistry:TriggerEvent(
								Private.Enum.Events.SETTING_CHANGED,
								key,
								AdvancedFocusCastBarSaved.Settings.LoadConditionRole
							)
						end

						local translated = L.LoadConditionRoleLabels[id]

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
						if AdvancedFocusCastBarSaved.Settings.LoadConditionRole[id] ~= bool then
							AdvancedFocusCastBarSaved.Settings.LoadConditionRole[id] = bool
							hasChanges = true
						end
					end

					if hasChanges then
						Private.EventRegistry:TriggerEvent(
							Private.Enum.Events.SETTING_CHANGED,
							key,
							AdvancedFocusCastBarSaved.Settings.LoadConditionRole
						)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.LoadConditionRoleLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					default = defaults.LoadConditionRole,
					desc = L.LoadConditionRoleTooltip,
					generator = Generator,
					-- technically is a reset only
					set = Set,
				}
			end

			if key == Private.Enum.Setting.FontFlags then
				local function Generator(owner, rootDescription, data)
					for label, id in pairs(Private.Enum.FontFlags) do
						local function IsEnabled()
							return AdvancedFocusCastBarSaved.Settings.FontFlags[id] == true
						end

						local function Toggle()
							AdvancedFocusCastBarSaved.Settings.FontFlags[id] =
								not AdvancedFocusCastBarSaved.Settings.FontFlags[id]

							Private.EventRegistry:TriggerEvent(
								Private.Enum.Events.SETTING_CHANGED,
								key,
								AdvancedFocusCastBarSaved.Settings.FontFlags
							)
						end

						local translated = L.FontFlagsLabels[id]

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
						if AdvancedFocusCastBarSaved.Settings.FontFlags[id] ~= bool then
							AdvancedFocusCastBarSaved.Settings.FontFlags[id] = bool
							hasChanges = true
						end
					end

					if hasChanges then
						Private.EventRegistry:TriggerEvent(
							Private.Enum.Events.SETTING_CHANGED,
							key,
							AdvancedFocusCastBarSaved.Settings.FontFlags
						)

						LibEditMode:RefreshFrameSettings(self)
					end
				end

				---@type LibEditModeDropdown
				return {
					name = L.FontFlagsLabel,
					kind = Enum.EditModeSettingDisplayType.Dropdown,
					default = defaults.FontFlags,
					desc = L.FontFlagsTooltip,
					generator = Generator,
					-- technically is a reset only
					set = Set,
				}
			end

			if key == Private.Enum.Setting.Width then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.Width
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					if value ~= AdvancedFocusCastBarSaved.Settings.Width then
						AdvancedFocusCastBarSaved.Settings.Width = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.FrameWidthLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.Width,
					desc = L.FrameWidthTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			if key == Private.Enum.Setting.Height then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.Height
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					if value ~= AdvancedFocusCastBarSaved.Settings.Height then
						AdvancedFocusCastBarSaved.Settings.Height = value
						Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, key, value)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.FrameHeightLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.Height,
					desc = L.FrameHeightTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			if key == Private.Enum.Setting.OffsetX then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.OffsetX
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					if value ~= AdvancedFocusCastBarSaved.Settings.OffsetX then
						AdvancedFocusCastBarSaved.Settings.OffsetX = value

						Private.EventRegistry:TriggerEvent(Private.Enum.Events.EDIT_MODE_POSITION_CHANGED)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.OffsetXLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.OffsetX,
					desc = L.OffsetXTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			if key == Private.Enum.Setting.OffsetY then
				local sliderSettings = GetSliderSettingsForOption(key)

				---@param layoutName string
				---@return number
				local function Get(layoutName)
					return AdvancedFocusCastBarSaved.Settings.OffsetY
				end

				---@param layoutName string
				---@param value number
				local function Set(layoutName, value)
					if value ~= AdvancedFocusCastBarSaved.Settings.OffsetY then
						AdvancedFocusCastBarSaved.Settings.OffsetY = value

						Private.EventRegistry:TriggerEvent(Private.Enum.Events.EDIT_MODE_POSITION_CHANGED)
					end
				end

				---@type LibEditModeSlider
				return {
					name = L.OffsetYLabel,
					kind = Enum.EditModeSettingDisplayType.Slider,
					default = defaults.OffsetY,
					desc = L.OffsetYTooltip,
					get = Get,
					set = Set,
					minValue = sliderSettings.min,
					maxValue = sliderSettings.max,
					valueStep = sliderSettings.step,
				}
			end

			error(
				string.format(
					"Edit Mode Settings for key '%s' are either not implemented or you're calling this with the wrong key.",
					key or "NO KEY"
				)
			)
		end

		LibEditMode:AddFrameSettings(self, {
			CreateSetting(Private.Enum.Setting.Width),
			CreateSetting(Private.Enum.Setting.Height),
			CreateSetting(Private.Enum.Setting.LoadConditionContentType),
			CreateSetting(Private.Enum.Setting.LoadConditionRole),
			CreateSetting(Private.Enum.Setting.Texture),
			CreateSetting(Private.Enum.Setting.FeatureFlag),
			CreateSetting(Private.Enum.Setting.Opacity),
			CreateSetting(Private.Enum.Setting.OutOfRangeOpacity),
			CreateSetting(Private.Enum.Setting.BackgroundOpacity),
			CreateSetting(Private.Enum.Setting.Font),
			CreateSetting(Private.Enum.Setting.FontSize),
			CreateSetting(Private.Enum.Setting.FontFlags),
			CreateSetting(Private.Enum.Setting.SecondaryFontScale),
			CreateSetting(Private.Enum.Setting.ColorUninterruptible),
			CreateSetting(Private.Enum.Setting.ColorInterruptibleCanInterrupt),
			CreateSetting(Private.Enum.Setting.ColorInterruptibleCannotInterrupt),
			CreateSetting(Private.Enum.Setting.ColorInterruptTick),
			CreateSetting(Private.Enum.Setting.ColorGlow),
			CreateSetting(Private.Enum.Setting.TickWidth),
			CreateSetting(Private.Enum.Setting.CustomTextsPosition),
			CreateSetting(Private.Enum.Setting.Point),
			CreateSetting(Private.Enum.Setting.OffsetX),
			CreateSetting(Private.Enum.Setting.OffsetY),
			CreateSetting(Private.Enum.Setting.Unit),
		})

		---@param title string
		---@param text string
		---@param button1 string
		---@return table
		local function CreateReadOnlyPopup(title, text, button1)
			return {
				id = addonName,
				whileDead = true,
				text = title,
				button1 = button1,
				hasEditBox = true,
				hasWideEditBox = true,
				editBoxWidth = 350,
				hideOnEscape = true,
				OnShow = function(popupSelf)
					local editBox = popupSelf:GetEditBox()
					editBox:SetText(text)
					editBox:HighlightText()

					local ctrlDown = false

					editBox:SetScript("OnKeyDown", function(_, key)
						if key == "LCTRL" or key == "RCTRL" or key == "LMETA" or key == "RMETA" then
							ctrlDown = true
						end
					end)
					editBox:SetScript("OnKeyUp", function(_, key)
						C_Timer.After(0.2, function()
							ctrlDown = false
						end)

						if ctrlDown and (key == "C" or key == "X") then
							StaticPopup_Hide(addonName)
						end
					end)
				end,
				EditBoxOnEscapePressed = function(popupSelf)
					popupSelf:GetParent():Hide()
				end,
				EditBoxOnTextChanged = function(popupSelf)
					-- ctrl + x sets the text to "" but this triggers hiding and shouldn't trigger resetting the text
					local currentText = popupSelf:GetText()

					if currentText == "" or currentText == text then
						return
					end

					popupSelf:SetText(text)
				end,
			}
		end

		---@param title string
		---@param button1 string
		---@param initialText string
		---@param OnAccept fun(text: string)
		---@return table
		local function CreateWritablePopup(title, button1, initialText, OnAccept)
			local dialogInfo = {
				id = addonName,
				whileDead = true,
				text = title,
				button1 = button1,
				button2 = CLOSE,
				hasEditBox = true,
				hasWideEditBox = true,
				editBoxWidth = 350,
				hideOnEscape = true,
				editBoxText = initialText,
				OnAccept = function(popupSelf)
					local editBox = popupSelf:GetEditBox()

					OnAccept(strtrim(editBox:GetText()))
				end,
			}

			if initialText ~= "" then
				dialogInfo.OnShow = function(popupSelf)
					local editBox = popupSelf:GetEditBox()
					editBox:SetText(initialText)
				end
			end

			return dialogInfo
		end

		local function OnImportButtonClick()
			StaticPopupDialogs[addonName] = CreateWritablePopup(
				Private.L.Settings.Import,
				Private.L.Settings.Import,
				"",
				function(importString)
					local success, hasAnyChange = Private.Settings.Import(importString)

					if hasAnyChange and LibEditMode:IsInEditMode() then
						LibEditMode:RefreshFrameSettings(self)
					end
				end
			)

			StaticPopup_Hide(addonName)
			StaticPopup_Show(addonName)
		end

		local function OnExportButtonClick()
			StaticPopupDialogs[addonName] =
				CreateReadOnlyPopup(Private.L.Settings.Export, Private.Settings.Export(), ACCEPT)

			StaticPopup_Hide(addonName)
			StaticPopup_Show(addonName)
		end

		local function OnDiscordLinkClick()
			local link = C_EncodingUtil.DeserializeCBOR(
				C_EncodingUtil.DecodeBase64("oURsaW5rWB1odHRwczovL2Rpc2NvcmQuZ2cvQzVTVGpZUnNDRA==")
			).link

			StaticPopupDialogs[addonName] = CreateReadOnlyPopup("Discord", link, ACCEPT)

			StaticPopup_Hide(addonName)
			StaticPopup_Show(addonName)
		end

		local function OnCustomTTSOnCastStartTextClick()
			StaticPopupDialogs[addonName] = CreateWritablePopup(
				Private.L.Settings.CustomizeTTSOnCastStartButtonText,
				ACCEPT,
				AdvancedFocusCastBarSaved.Settings.CustomTTSOnCastStartText or Private.L.Settings.CastStartText,
				function(newText)
					if newText ~= AdvancedFocusCastBarSaved.Settings.CustomTTSOnCastStartText then
						AdvancedFocusCastBarSaved.Settings.CustomTTSOnCastStartText = newText
					end
				end
			)

			StaticPopup_Hide(addonName)
			StaticPopup_Show(addonName)
		end

		LibEditMode:AddFrameSettingsButtons(self, {
			{
				click = OnCustomTTSOnCastStartTextClick,
				text = Private.L.Settings.CustomizeTTSOnCastStartButtonText,
			},
			{
				click = OnImportButtonClick,
				text = Private.L.Settings.Import,
			},
			{
				click = OnExportButtonClick,
				text = Private.L.Settings.Export,
			},
			{
				click = OnDiscordLinkClick,
				text = "Discord",
			},
		})

		-- dummy cast text is already AdvancedFocusCastBar and the selection label layering
		-- makes it impossible to see some of the options changing in real time
		self.Selection.Label:HookScript("OnShow", function(labelSelf)
			labelSelf:Hide()
		end)
	end

	Private.EventRegistry:RegisterCallback(Private.Enum.Events.SETTING_CHANGED, self.OnSettingsChange, self)

	FrameUtil.RegisterFrameForEvents(self, {
		"ZONE_CHANGED_NEW_AREA",
		"LOADING_SCREEN_DISABLED",
		"UPDATE_INSTANCE_INFO",
		"FIRST_FRAME_RENDERED",
	})

	self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

	self:ToggleTargetMarkerIntegration()
	self:ToggleUnitIntegration()
end

function AdvancedFocusCastBarMixin:ToggleUnitIntegration()
	FrameUtil.UnregisterFrameForEvents(self, self.events)
	FrameUtil.RegisterFrameForUnitEvents(self, self.events, AdvancedFocusCastBarSaved.Settings.Unit)

	if AdvancedFocusCastBarSaved.Settings.Unit == Private.Enum.Unit.Focus then
		self:UnregisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("PLAYER_FOCUS_CHANGED")
	else
		self:UnregisterEvent("PLAYER_FOCUS_CHANGED")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
	end
end

function AdvancedFocusCastBarMixin:AdjustSpellNameTextWidth()
	local iconSize = AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowIcon]
			and AdvancedFocusCastBarSaved.Settings.Height
		or 0
	local castTimeSize = AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowCastTime]
			and 2 * AdvancedFocusCastBarSaved.Settings.Height
		or 0
	local maxWidth = AdvancedFocusCastBarSaved.Settings.Width - 4 - iconSize - castTimeSize

	self.CastBar.SpellNameText:SetWidth(maxWidth)
end

function AdvancedFocusCastBarMixin:AdjustDirection(isChannel)
	self.CastBar.InterruptBar:ClearAllPoints()
	self.CastBar.InterruptBar.Tick:ClearAllPoints()

	if isChannel and AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.UnfillChannels] then
		self.CastBar:SetReverseFill(false)
		self.CastBar.Positioner:SetReverseFill(false)
		self.CastBar.InterruptBar:SetReverseFill(true)

		self.CastBar.InterruptBar:SetPoint("RIGHT", self.CastBar.Positioner:GetStatusBarTexture(), "RIGHT")
		self.CastBar.InterruptBar.Tick:SetPoint("RIGHT", self.CastBar.InterruptBar:GetStatusBarTexture(), "LEFT")
	else
		self.CastBar:SetReverseFill(isChannel)
		self.CastBar.Positioner:SetReverseFill(isChannel)
		self.CastBar.InterruptBar:SetReverseFill(isChannel)

		if isChannel then
			self.CastBar.InterruptBar:SetPoint("RIGHT", self.CastBar.Positioner:GetStatusBarTexture(), "LEFT")
			self.CastBar.InterruptBar.Tick:SetPoint("RIGHT", self.CastBar.InterruptBar:GetStatusBarTexture(), "LEFT")
		else
			self.CastBar.InterruptBar:SetPoint("LEFT", self.CastBar.Positioner:GetStatusBarTexture(), "RIGHT")
			self.CastBar.InterruptBar.Tick:SetPoint("LEFT", self.CastBar.InterruptBar:GetStatusBarTexture(), "RIGHT")
		end
	end
end

function AdvancedFocusCastBarMixin:IsPastLoadingScreen()
	return self.firstFrameTimestamp > 0 and (GetTime() - self.firstFrameTimestamp) > 1
end

function AdvancedFocusCastBarMixin:ToggleTargetMarkerIntegration()
	if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowTargetMarker] then
		self:RegisterEvent("RAID_TARGET_UPDATE")
	else
		self:UnregisterEvent("RAID_TARGET_UPDATE")
	end
end

function AdvancedFocusCastBarMixin:MaybePlayCastStartTTS()
	if
		AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.PlayTTSOnCastStart]
		and self.contentType ~= Private.Enum.ContentType.Raid
	then
		local text = AdvancedFocusCastBarSaved.Settings.CustomTTSOnCastStartText or Private.L.Settings.CastStartText
		self:PlayTTS(text)
	end
end

function AdvancedFocusCastBarMixin:AdjustIconLayout(shown)
	self.CastBar:ClearAllPoints()

	PixelUtil.SetSize(self.Icon, AdvancedFocusCastBarSaved.Settings.Height, AdvancedFocusCastBarSaved.Settings.Height)

	if shown then
		self.Icon:ClearAllPoints()
		self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		self.Icon:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
		self.Icon:Show()

		self.CastBar:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", 0, 0)
		self.CastBar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)

		local adjustedWidth = AdvancedFocusCastBarSaved.Settings.Width - AdvancedFocusCastBarSaved.Settings.Height
		PixelUtil.SetSize(self.CastBar, adjustedWidth, AdvancedFocusCastBarSaved.Settings.Height)
		PixelUtil.SetSize(self.CastBar.Mask, adjustedWidth, AdvancedFocusCastBarSaved.Settings.Height)
		PixelUtil.SetSize(self.CastBar.Positioner, adjustedWidth, AdvancedFocusCastBarSaved.Settings.Height)
		PixelUtil.SetSize(self.CastBar.InterruptBar, adjustedWidth, AdvancedFocusCastBarSaved.Settings.Height)
		PixelUtil.SetSize(
			self.CastBar.InterruptBar.Tick,
			AdvancedFocusCastBarSaved.Settings.TickWidth,
			AdvancedFocusCastBarSaved.Settings.Height
		)
	else
		self.Icon:Hide()

		self.CastBar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		self.CastBar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)

		PixelUtil.SetSize(
			self.CastBar,
			AdvancedFocusCastBarSaved.Settings.Width,
			AdvancedFocusCastBarSaved.Settings.Height
		)

		PixelUtil.SetSize(
			self.CastBar.Mask,
			AdvancedFocusCastBarSaved.Settings.Width,
			AdvancedFocusCastBarSaved.Settings.Height
		)
		PixelUtil.SetSize(
			self.CastBar.Positioner,
			AdvancedFocusCastBarSaved.Settings.Width,
			AdvancedFocusCastBarSaved.Settings.Height
		)
		PixelUtil.SetSize(
			self.CastBar.InterruptBar,
			AdvancedFocusCastBarSaved.Settings.Width,
			AdvancedFocusCastBarSaved.Settings.Height
		)
		PixelUtil.SetSize(
			self.CastBar.InterruptBar.Tick,
			AdvancedFocusCastBarSaved.Settings.TickWidth,
			AdvancedFocusCastBarSaved.Settings.Height
		)
	end
end

function AdvancedFocusCastBarMixin:OnSettingsChange(key, value)
	if key == Private.Enum.Setting.Width then
		self:SetWidth(value)
		self:AdjustIconLayout(AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowIcon])
		self:AdjustSpellNameTextWidth()
		self:HideGlow()
		self:ShowGlow(false)
	elseif key == Private.Enum.Setting.Height then
		self:SetHeight(value)
		self:AdjustIconLayout(AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowIcon])
		self:AdjustSpellNameTextWidth()
		self:HideGlow()
		self:ShowGlow(false)
	elseif key == Private.Enum.Setting.Opacity then
		self:SetAlpha(value)
	elseif key == Private.Enum.Setting.Texture then
		self.CastBar:SetStatusBarTexture(value)
	elseif
		key == Private.Enum.Setting.Font
		or key == Private.Enum.Setting.FontSize
		or key == Private.Enum.Setting.FontFlags
		or key == Private.Enum.Setting.SecondaryFontScale
	then
		self:SetFontAndFontSize()
	elseif key == Private.Enum.Setting.ColorUninterruptible then
		self.colors.Uninterruptible = CreateColorFromHexString(value)
	elseif key == Private.Enum.Setting.ColorInterruptibleCanInterrupt then
		self.colors.InterruptibleCanInterrupt = CreateColorFromHexString(value)
	elseif key == Private.Enum.Setting.ColorInterruptibleCannotInterrupt then
		self.colors.InterruptibleCannotInterrupt = CreateColorFromHexString(value)
	elseif key == Private.Enum.Setting.ColorGlow then
		if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] then
			self:HideGlow()
			self:ShowGlow(false)
		end
	elseif key == Private.Enum.Setting.ColorInterruptTick then
		self.colors.InterruptTick = CreateColorFromHexString(value)
	elseif key == Private.Enum.Setting.BackgroundOpacity then
		self:AdjustBackgroundOpacity()
	elseif key == Private.Enum.Setting.TickWidth then
		self.CastBar.InterruptBar.Tick:SetShown(value > 0)
		self.CastBar.InterruptBar.Tick:SetWidth(value)
	elseif key == Private.Enum.Setting.OutOfRangeOpacity then
		if value == 1 then
			self:SetAlpha(1)
		end
	elseif key == Private.Enum.Setting.CustomTextsPosition then
		self:AdjustCustomTextsPosition()
	elseif key == Private.Enum.Setting.Unit then
		self:ToggleUnitIntegration()
	elseif key == Private.Enum.Setting.FeatureFlag then
		for index, id in ipairs(value) do
			if id == Private.Enum.FeatureFlag.ShowIcon then
				self:AdjustIconLayout(AdvancedFocusCastBarSaved.Settings.FeatureFlags[id])
				self:AdjustSpellNameTextWidth()
			elseif id == Private.Enum.FeatureFlag.ShowCastTime then
				self.CastBar.CastTimeText:SetShown(AdvancedFocusCastBarSaved.Settings.FeatureFlags[id])
				self:AdjustSpellNameTextWidth()
			elseif id == Private.Enum.FeatureFlag.ShowBorder then
				self:HideGlow()
				self.Border:SetShown(AdvancedFocusCastBarSaved.Settings.FeatureFlags[id])
				self:ShowGlow(false)
			elseif id == Private.Enum.FeatureFlag.ShowImportantSpellsGlow then
				if not AdvancedFocusCastBarSaved.Settings.FeatureFlags[id] then
					self:HideGlow()
				end
			elseif id == Private.Enum.FeatureFlag.ShowTargetMarker then
				self.CustomElementsFrame.TargetMarker:SetShown(AdvancedFocusCastBarSaved.Settings.FeatureFlags[id])
				self:ToggleTargetMarkerIntegration()
			elseif id == Private.Enum.FeatureFlag.ShowTargetName then
				self:ToggleTargetNameVisibility()
			elseif id == Private.Enum.FeatureFlag.HideWhenUninterruptible then
				if AdvancedFocusCastBarSaved.Settings.FeatureFlags[id] and self.interruptId == nil then
					for _, event in next, self.events do
						self:UnregisterEvent(event)
					end
				else
					self:ToggleUnitIntegration()
				end
			end
		end
	end
end

function AdvancedFocusCastBarMixin:AdjustCustomTextsPosition()
	local point = AdvancedFocusCastBarSaved.Settings.CustomTextsPosition
				== Private.Enum.CustomTextsPosition.BOTTOMCENTER
			and "BOTTOM"
		or AdvancedFocusCastBarSaved.Settings.CustomTextsPosition

	local factor = (
		point == Private.Enum.CustomTextsPosition.TOPLEFT or point == Private.Enum.CustomTextsPosition.TOPRIGHT
	)
			and 1
		or -1

	for i = 1, 5 do
		local CustomElementsFrame = self.CustomElementsFrame["TargetNameText" .. i]

		CustomElementsFrame:ClearAllPoints()
		CustomElementsFrame:SetPoint(point, self, point, 0, 8 * factor)
	end
end

function AdvancedFocusCastBarMixin:ToggleTargetNameVisibility()
	self:SetTargetNameVisibility(
		AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowTargetName]
	)
end

function AdvancedFocusCastBarMixin:AdjustBackgroundOpacity()
	self.CastBar.Background:SetAlpha(AdvancedFocusCastBarSaved.Settings.BackgroundOpacity)
end

function AdvancedFocusCastBarMixin:SetTargetNameVisibility(bool)
	for i = 1, 5 do
		local targetNameFrame = self.CustomElementsFrame["TargetNameText" .. i]
		targetNameFrame:SetShown(bool)
	end
end

function AdvancedFocusCastBarMixin:SetFontAndFontSize()
	local otherSize = AdvancedFocusCastBarSaved.Settings.SecondaryFontScale
		* AdvancedFocusCastBarSaved.Settings.FontSize

	local fontStrings = {
		[self.CastBar.CastTimeText] = AdvancedFocusCastBarSaved.Settings.FontSize,
		[self.CastBar.SpellNameText] = AdvancedFocusCastBarSaved.Settings.FontSize,
		[self.CustomElementsFrame.TargetNameText1] = otherSize,
		[self.CustomElementsFrame.TargetNameText2] = otherSize,
		[self.CustomElementsFrame.TargetNameText3] = otherSize,
		[self.CustomElementsFrame.TargetNameText4] = otherSize,
		[self.CustomElementsFrame.TargetNameText5] = otherSize,
		[self.CustomElementsFrame.InterruptSourceText] = otherSize,
	}

	local targetYOffset = otherSize * 0.66 * -1

	local flags = AdvancedFocusCastBarSaved.Settings.FontFlags[Private.Enum.FontFlags.OUTLINE] and "OUTLINE" or ""

	for fontString, targetFontSize in pairs(fontStrings) do
		fontString:SetFont(AdvancedFocusCastBarSaved.Settings.Font, targetFontSize, flags)

		if AdvancedFocusCastBarSaved.Settings.FontFlags[Private.Enum.FontFlags.SHADOW] then
			fontString:SetShadowOffset(1, -1)
			fontString:SetShadowColor(0, 0, 0, 1)
		else
			fontString:SetShadowOffset(0, 0)
		end

		if fontString ~= self.CastBar.CastTimeText and fontString ~= self.CastBar.SpellNameText then
			fontString:ClearAllPoints()
			fontString:SetPoint(AdvancedFocusCastBarSaved.Settings.CustomTextsPosition, 0, targetYOffset)
		end
	end
end

function AdvancedFocusCastBarMixin:RestoreEditModePosition()
	self:ClearAllPoints()
	self:SetPoint(
		---@diagnostic disable-next-line: param-type-mismatch
		AdvancedFocusCastBarSaved.Settings.Point,
		AdvancedFocusCastBarSaved.Settings.OffsetX,
		AdvancedFocusCastBarSaved.Settings.OffsetY
	)
end

function AdvancedFocusCastBarMixin:OnEditModePositionChange(frame, layoutName, point, x, y)
	x = math.floor(x)
	y = math.floor(y)

	AdvancedFocusCastBarSaved.Settings.Point = point
	AdvancedFocusCastBarSaved.Settings.OffsetX = x
	AdvancedFocusCastBarSaved.Settings.OffsetY = y

	Private.EventRegistry:TriggerEvent(Private.Enum.Events.EDIT_MODE_POSITION_CHANGED)
end

do
	local PreviewIconDataProvider = nil

	function AdvancedFocusCastBarMixin:GetRandomIcon()
		if PreviewIconDataProvider == nil then
			PreviewIconDataProvider =
				CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook, true)
		end

		return PreviewIconDataProvider:GetRandomIcon()
	end
end

function AdvancedFocusCastBarMixin:LoopPreview()
	if not self:IsPastLoadingScreen() then
		return
	end

	local dummyDuration = C_DurationUtil.CreateDuration()
	dummyDuration:SetTimeFromStart(GetTime(), 3)

	self.castInformation = {
		duration = dummyDuration,
		isChannel = math.random(0, 1) == 1,
		name = addonName,
		notInterruptible = math.random(0, 1) == 1,
		texture = self:GetRandomIcon(),
		isImportant = math.random(0, 1) == 1,
	}

	self:ProcessCastInformation()
	self:Show()
end

-- /run AdvancedFocusCastBarParent:ToggleDemo()
function AdvancedFocusCastBarMixin:ToggleDemo()
	if self.demoInterval == nil then
		self:OnEditModeEnter()
	else
		self:OnEditModeExit()
	end
end

function AdvancedFocusCastBarMixin:OnEditModeEnter()
	if not self:IsPastLoadingScreen() then
		return
	end

	if self.demoInterval ~= nil then
		self.demoInterval:Cancel()
		self.demoInterval = nil
	end

	self.demoInterval = C_Timer.NewTicker(3, GenerateClosure(self.LoopPreview, self))
	self:LoopPreview()
	self:SetScript("OnEvent", nil)
end

function AdvancedFocusCastBarMixin:OnEditModeExit()
	if self.demoInterval ~= nil then
		self.demoInterval:Cancel()
		self.demoInterval = nil
	end

	self:SetScript("OnEvent", self.OnEvent)
	self:Hide()
end
function AdvancedFocusCastBarMixin:GetOpacityWithRangeCheck(theOpacity)
	if AdvancedFocusCastBarSaved.Settings.OutOfRangeOpacity < 1 then
		local inRange = C_Spell.IsSpellInRange(self.interruptId, AdvancedFocusCastBarSaved.Settings.Unit)

		if inRange ~= nil then
			theOpacity = inRange == true and theOpacity or AdvancedFocusCastBarSaved.Settings.OutOfRangeOpacity
		end
	end

	return theOpacity
end
function AdvancedFocusCastBarMixin:SetAlphaFromFeatureFlag(interruptDuration, opacity)
	if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.HideWhenUninterruptible] then
		self:SetAlphaFromBoolean(
			self.castInformation.notInterruptible,
			0,
			C_CurveUtil.EvaluateColorValueFromBoolean(interruptDuration:IsZero(), opacity, 0)
		)
	end
end

function AdvancedFocusCastBarMixin:OnUpdate(elapsed)
	if self.interruptHidingDelayTimer ~= nil then
		return
	end

	if
		self.castInformation.isChannel
		and AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.UnfillChannels]
	then
		self.CastBar:SetValue(self.castInformation.duration:GetRemainingDuration())
	else
		self.CastBar:SetValue(self.castInformation.duration:GetElapsedDuration())
	end

	self.elapsed = self.elapsed + elapsed

	if self.elapsed < 0.1 then
		return
	end

	self.elapsed = self.elapsed - 0.1

	if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowCastTime] then
		self.CastBar.CastTimeText:SetFormattedText("%.1f", self.castInformation.duration:GetRemainingDuration())
	end

	-- ensure the following calls will have the expected opacity since they're all pointing to the same value
	local theOpacity = AdvancedFocusCastBarSaved.Settings.Opacity

	if self.interruptId ~= nil then
		theOpacity = self:GetOpacityWithRangeCheck(theOpacity)
		self:SetAlpha(theOpacity)
		local interruptDuration = C_Spell.GetSpellCooldownDuration(self.interruptId)

		if interruptDuration == nil then
			return
		end

		self:SetAlphaFromFeatureFlag(interruptDuration, theOpacity)
		self:DeriveAndSetNextColor(interruptDuration)

		if
			self.castInformation.isChannel
			and AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.UnfillChannels]
		then
			self.CastBar.Positioner:SetValue(self.castInformation.duration:GetRemainingDuration())
		else
			self.CastBar.Positioner:SetValue(self.castInformation.duration:GetElapsedDuration())
		end

		self.CastBar.InterruptBar:SetValue(interruptDuration:GetRemainingDuration())

		self.CastBar.InterruptBar:SetAlphaFromBoolean(
			interruptDuration:IsZero(),
			0,
			C_CurveUtil.EvaluateColorValueFromBoolean(self.castInformation.notInterruptible, 0, theOpacity)
		)
		-- the soft hide immediately following this would override hiding the bar so return.
		return
	end

	-- soft hides the bar if the ending event is for some reason missing.
	-- needs to be this far down to avoid overlapping with out of range alpha
	self:SetAlphaFromBoolean(self.castInformation.duration:IsZero(), 0, theOpacity)
end

function AdvancedFocusCastBarMixin:ShowGlow(isImportant)
	local frame = AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowBorder] and self.Border
		or self

	if frame._PixelGlow == nil then
		local color = CreateColorFromHexString(AdvancedFocusCastBarSaved.Settings.ColorGlow)

		LibCustomGlow.PixelGlow_Start(
			frame, -- frame
			color, -- color
			nil, -- N
			nil, -- frequency
			nil, -- length
			nil, -- thickness
			nil, -- xOffset
			nil, -- yOffset
			nil, -- border
			nil, -- key
			nil -- frameLevel
		)

		-- needed to layer above the glow
		self.CustomElementsFrame:SetFrameLevel(frame._PixelGlow:GetFrameLevel() + 1)
	end

	frame._PixelGlow:SetAlphaFromBoolean(isImportant)
end

function AdvancedFocusCastBarMixin:HideGlow()
	LibCustomGlow.PixelGlow_Stop(
		AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowBorder] and self.Border or self
	)
end

function AdvancedFocusCastBarMixin:LoadConditionsProhibitExecution()
	if not AdvancedFocusCastBarSaved.Settings.LoadConditionRole[self.role] then
		return true
	end

	if not AdvancedFocusCastBarSaved.Settings.LoadConditionContentType[self.contentType] then
		return true
	end

	return false
end

function AdvancedFocusCastBarMixin:UnitIsIrrelevant()
	if not UnitExists(AdvancedFocusCastBarSaved.Settings.Unit) then
		return true
	end

	if
		AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.IgnoreFriendlies]
		and not UnitCanAttack("player", AdvancedFocusCastBarSaved.Settings.Unit)
	then
		return true
	end

	return false
end

function AdvancedFocusCastBarMixin:DetectInterruptId()
	local playerClass = select(3, UnitClass("player"))

	local classInterruptMap = {
		[Constants.UICharacterClasses.Warrior] = { 6552 },
		[Constants.UICharacterClasses.Paladin] = { 96231, 31935 }, -- Rebuke must come before Avenger's Shield
		[Constants.UICharacterClasses.Hunter] = { 147362, 187707 },
		[Constants.UICharacterClasses.Rogue] = { 1766 },
		[Constants.UICharacterClasses.Priest] = { 15487 },
		[Constants.UICharacterClasses.DeathKnight] = { 47528 },
		[Constants.UICharacterClasses.Shaman] = { 57994 },
		[Constants.UICharacterClasses.Mage] = { 2139 },
		[Constants.UICharacterClasses.Warlock] = { 19647, 89766, 119910, 1276467, 132409 },
		[Constants.UICharacterClasses.Monk] = { 116705 },
		[Constants.UICharacterClasses.Druid] = { 38675, 78675, 106839 },
		[Constants.UICharacterClasses.DemonHunter] = { 183752 },
		[Constants.UICharacterClasses.Evoker] = { 351338 },
	}

	local eligibleInterrupts = classInterruptMap[playerClass]

	for i = 1, #eligibleInterrupts do
		local id = eligibleInterrupts[i]

		if
			C_SpellBook.IsSpellKnownOrInSpellBook(id)
			or C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Pet)
		then
			return id
		end
	end

	return nil
end

function AdvancedFocusCastBarMixin:DeriveAndSetNextColor(interruptDuration)
	if self.interruptId == nil then
		return
	end

	local bool = (interruptDuration or C_Spell.GetSpellCooldownDuration(self.interruptId)):IsZero()

	self.CastBar:GetStatusBarTexture():SetVertexColorFromBoolean(
		self.castInformation.notInterruptible,
		self.colors.Uninterruptible,
		C_CurveUtil.EvaluateColorFromBoolean(
			bool,
			self.colors.InterruptibleCanInterrupt,
			self.colors.InterruptibleCannotInterrupt
		)
	)
end

function AdvancedFocusCastBarMixin:QueryCastInformation()
	local duration = UnitCastingDuration(AdvancedFocusCastBarSaved.Settings.Unit)
	local isChannel = false

	if duration == nil then
		duration = UnitChannelDuration(AdvancedFocusCastBarSaved.Settings.Unit)
		isChannel = true
	end

	if duration == nil then
		return
	end

	local name, texture, notInterruptible, spellId

	if isChannel then
		_, name, texture, _, _, _, notInterruptible, spellId = UnitChannelInfo(AdvancedFocusCastBarSaved.Settings.Unit)
	else
		_, name, texture, _, _, _, _, notInterruptible, spellId =
			UnitCastingInfo(AdvancedFocusCastBarSaved.Settings.Unit)
	end

	return {
		duration = duration,
		isChannel = isChannel,
		name = name,
		texture = texture,
		notInterruptible = notInterruptible,
		isImportant = C_Spell.IsSpellImportant(spellId),
	}
end

function AdvancedFocusCastBarMixin:GetMaybeColoredUnitName(unit)
	local name = UnitName(unit)

	if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.UseTargetClassColor] then
		local class = select(2, UnitClass(unit))

		if class == nil then
			return name
		end

		local color = C_ClassColor.GetClassColor(class)

		return color:WrapTextInColorCode(name)
	end

	return name
end

function AdvancedFocusCastBarMixin:ProcessCastInformation()
	local totalDuration = self.castInformation.duration:GetTotalDuration()
	self.CastBar:SetMinMaxValues(0, totalDuration)
	self.CastBar.Positioner:SetMinMaxValues(0, totalDuration)
	self.CastBar.InterruptBar:SetMinMaxValues(0, totalDuration)

	if
		self.castInformation.isChannel
		and AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.UnfillChannels]
	then
		self.CastBar:SetValue(totalDuration)
		self.CastBar.Positioner:SetValue(totalDuration)
	else
		self.CastBar:SetValue(self.castInformation.duration:GetElapsedDuration())
	end

	self:AdjustDirection(self.castInformation.isChannel)

	self.Icon:SetTexture(self.castInformation.texture)
	self.CastBar.SpellNameText:SetText(self.castInformation.name)
	self:DeriveAndSetNextColor()

	if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] then
		self:ShowGlow(self.castInformation.isImportant)
	else
		-- looks anti intuitive - because it is.
		-- once the glow was enabled once, we just never stop it but only hide it to avoid going through the whole
		-- LibCustomGlow lifecycle again.
		self:ShowGlow(false)
	end

	-- interruptId won't change while the castbar is visible, so its set once outside to prevent spamming this
	if self.interruptId == nil then
		self.CastBar:GetStatusBarTexture():SetVertexColorFromBoolean(
			self.castInformation.notInterruptible,
			self.colors.Uninterruptible,
			self.colors.InterruptibleCannotInterrupt
		)
	end

	-- presence means we're in edit mode
	if self.demoInterval == nil then
		if self.interruptId ~= nil then
			local interruptDuration = C_Spell.GetSpellCooldownDuration(self.interruptId)

			if interruptDuration ~= nil then
				-- ensure initial opacity is correct when out of range.
				local theOpacity = AdvancedFocusCastBarSaved.Settings.Opacity
				theOpacity = self:GetOpacityWithRangeCheck(theOpacity)

				self:SetAlphaFromFeatureFlag(interruptDuration, theOpacity)
			end
		end

		if
			self.contentType ~= Private.Enum.ContentType.Raid
			and AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowTargetName]
		then
			self:SetTargetNameVisibility(true)

			if IsInGroup() then
				local partyMembers = GetNumGroupMembers()

				for i = 1, partyMembers do
					local unit = i == partyMembers and "player" or "party" .. i

					---@type FontString
					local frame = self.CustomElementsFrame["TargetNameText" .. i]
					frame:SetText(self:GetMaybeColoredUnitName(unit))
					frame:SetAlphaFromBoolean(UnitIsSpellTarget(AdvancedFocusCastBarSaved.Settings.Unit, unit), 1, 0)
				end
			else
				self.CustomElementsFrame.TargetNameText1:SetText(self:GetMaybeColoredUnitName("player"))
				self.CustomElementsFrame.TargetNameText1:SetAlphaFromBoolean(
					UnitIsSpellTarget(AdvancedFocusCastBarSaved.Settings.Unit, "player"),
					1,
					0
				)
			end
		else
			self:SetTargetNameVisibility(false)
		end
	else
		if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowTargetMarker] then
			local index = math.random(0, 8)

			self.CustomElementsFrame.TargetMarker:SetShown(index > 0)

			if index > 0 then
				SetRaidTargetIconTexture(self.CustomElementsFrame.TargetMarker, index)
			end
		else
			self.CustomElementsFrame.TargetMarker:Hide()
		end

		self.CustomElementsFrame.TargetNameText1:SetText(self:GetMaybeColoredUnitName("player"))
		self:SetTargetNameVisibility(true)
	end
end

function AdvancedFocusCastBarMixin:PlayTTS(text)
	C_VoiceChat.SpeakText(self:FindAppropriateTTSVoiceID(), text, 3, C_TTSSettings.GetSpeechVolume())
end

function AdvancedFocusCastBarMixin:FindAppropriateTTSVoiceID()
	local expectsAlternateVoice = C_TTSSettings.GetSetting(Enum.TtsBoolSetting.AlternateSystemVoice)
	local voice = TextToSpeech_GetSelectedVoice(
		expectsAlternateVoice and Enum.TtsVoiceType.Alternate or Enum.TtsVoiceType.Standard
	)
	if voice == nil then
		voice = TextToSpeech_GetSelectedVoice(
			expectsAlternateVoice and Enum.TtsVoiceType.Standard or Enum.TtsVoiceType.Alternate
		)
	end

	if voice == nil then
		return C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard)
	end

	return voice.voiceID
end

function AdvancedFocusCastBarMixin:QueueDelayedHide()
	-- for channel interrupts, the state has been cleared so we just use dummy values instead
	self.CastBar:SetMinMaxValues(0, 1)
	self.CastBar:SetValue(1)
	self.CastBar:SetStatusBarColor(
		self.colors.InterruptibleCannotInterrupt.r,
		self.colors.InterruptibleCannotInterrupt.g,
		self.colors.InterruptibleCannotInterrupt.b
	)

	if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowImportantSpellsGlow] then
		self:ShowGlow(false)
	end

	local showCastTime = AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowCastTime]

	if showCastTime then
		self.CastBar.CastTimeText:Hide()
	end

	local showTargetName = AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowTargetName]

	if showTargetName then
		self:SetTargetNameVisibility(false)
	end

	self.interruptHidingDelayTimer = C_Timer.NewTimer(1, function()
		if showCastTime then
			self.CastBar.CastTimeText:Show()
		end

		if showTargetName then
			self:SetTargetNameVisibility(true)
		end

		self.CustomElementsFrame.InterruptSourceText:Hide()
		self.interruptHidingDelayTimer = nil
		self:Hide()
	end)
end

function AdvancedFocusCastBarMixin:OnEvent(event, ...)
	if
		event == "UNIT_SPELLCAST_START"
		or event == "UNIT_SPELLCAST_DELAYED"
		or event == "UNIT_SPELLCAST_CHANNEL_START"
		or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
		or event == "UNIT_SPELLCAST_EMPOWER_START"
		or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
	then
		if self:LoadConditionsProhibitExecution() or self:UnitIsIrrelevant() then
			return
		end

		self.castInformation = self:QueryCastInformation()

		if self.castInformation == nil then
			return
		end

		if self.interruptHidingDelayTimer ~= nil then
			self.interruptHidingDelayTimer:Invoke()
			self.interruptHidingDelayTimer = nil
		end

		if
			event == "UNIT_SPELLCAST_START"
			or event == "UNIT_SPELLCAST_CHANNEL_START"
			or event == "UNIT_SPELLCAST_EMPOWER_START"
		then
			self:MaybePlayCastStartTTS()
		end

		self:ProcessCastInformation()
		self:Show()
	elseif
		event == "UNIT_SPELLCAST_STOP"
		or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_CHANNEL_STOP"
		or event == "UNIT_SPELLCAST_EMPOWER_STOP"
	then
		if
			self:LoadConditionsProhibitExecution()
			or self:UnitIsIrrelevant()
			or not self:IsShown()
			or self.interruptHidingDelayTimer ~= nil
		then
			return
		end

		local interruptedBy = nil

		if AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowInterruptSource] then
			if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
				interruptedBy = select(4, ...)
			elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
				interruptedBy = select(5, ...)
			end
		end

		self.castInformation = self:QueryCastInformation()

		if self.castInformation == nil and interruptedBy == nil then
			self:Hide()

			return
		end

		local delayHiding = false

		if
			AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.ShowInterruptSource]
			and interruptedBy ~= nil
		then
			if interruptedBy ~= nil then
				delayHiding = true

				local interruptName = UnitNameFromGUID(interruptedBy)
				local interruptColor = nil

				if
					AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.UseInterruptSourceClassColor]
					and interruptedBy ~= nil
				then
					local className = select(2, UnitClassFromGUID(interruptedBy))
					if className ~= nil then
						interruptColor = C_ClassColor.GetClassColor(className)
					end
				end

				if interruptColor == nil then
					interruptColor = CreateColor(1, 1, 1)
				end

				self.CustomElementsFrame.InterruptSourceText:SetFormattedText(
					Private.L.Settings.InterruptSourceText,
					interruptColor == nil and interruptName or interruptColor:WrapTextInColorCode(interruptName)
				)

				self.CustomElementsFrame.InterruptSourceText:Show()
			end
		end

		if delayHiding then
			self:QueueDelayedHide()
		else
			-- when testing against yourself, this avoids breakage when the testing spell is in a macro trying to cast other stuff
			if event == "UNIT_SPELLCAST_FAILED" and UnitIsUnit(AdvancedFocusCastBarSaved.Settings.Unit, "player") then
				return
			end

			self:Hide()
		end
	elseif event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_TARGET_CHANGED" then
		if self:LoadConditionsProhibitExecution() then
			return
		end

		if not UnitExists(AdvancedFocusCastBarSaved.Settings.Unit) then
			if self:IsShown() then
				self:Hide()
			end

			if
				AdvancedFocusCastBarSaved.Settings.FeatureFlags[Private.Enum.FeatureFlag.PlayTargetingTTSReminder]
				and self.contentType == Private.Enum.ContentType.Dungeon
			then
				-- delay this as focus target dying may imply leaving combat
				C_Timer.After(1, function()
					if InCombatLockdown() then
						self:PlayTTS(AdvancedFocusCastBarSaved.Settings.Unit)
					end
				end)
			end

			return
		end

		if self:UnitIsIrrelevant() then
			-- hide if focus moved to an irrelevant unit. 
			if self:IsShown() then
				self:Hide()
			end

			return
		end

		self.castInformation = self:QueryCastInformation()

		if self.castInformation == nil then
			if self:IsShown() then
				self:Hide()
			end

			return
		end

		self:MaybePlayCastStartTTS()
		self:ProcessCastInformation()
		self:Show()
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		if self:LoadConditionsProhibitExecution() then
			return
		end

		self.castInformation = self:QueryCastInformation()

		if self.castInformation == nil then
			self:Hide()
			return
		end

		self:DeriveAndSetNextColor()
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if self:LoadConditionsProhibitExecution() then
			return
		end

		self.castInformation = self:QueryCastInformation()

		if self.castInformation == nil then
			self:Hide()
			return
		end

		self:DeriveAndSetNextColor()
	elseif event == "RAID_TARGET_UPDATE" then
		local index = GetRaidTargetIndex(AdvancedFocusCastBarSaved.Settings.Unit)

		if index == nil then
			self.CustomElementsFrame.TargetMarker:Hide()
		else
			SetRaidTargetIconTexture(self.CustomElementsFrame.TargetMarker, index)
			self.CustomElementsFrame.TargetMarker:Show()
		end
	elseif
		event == "ZONE_CHANGED_NEW_AREA"
		or event == "LOADING_SCREEN_DISABLED"
		or event == "PLAYER_SPECIALIZATION_CHANGED"
		or event == "UPDATE_INSTANCE_INFO"
	then
		if
			event == "LOADING_SCREEN_DISABLED"
			and not UnitExists(AdvancedFocusCastBarSaved.Settings.Unit)
			and self:IsShown()
		then
			self:Hide()
		end

		local nextInterruptId = self:DetectInterruptId()

		if nextInterruptId ~= self.interruptId then
			self.interruptId = nextInterruptId

			Private.EventRegistry:TriggerEvent(Private.Enum.Events.SETTING_CHANGED, Private.Enum.Setting.FeatureFlag, {
				Private.Enum.FeatureFlag.HideWhenUninterruptible,
			})
		end

		local _, instanceType, difficultyId = GetInstanceInfo()
		-- equivalent to `instanceType == "none"`
		local nextContentType = Private.Enum.ContentType.OpenWorld

		if instanceType == "raid" then
			nextContentType = Private.Enum.ContentType.Raid
		elseif instanceType == "party" then
			if
				difficultyId == DifficultyUtil.ID.DungeonTimewalker
				or difficultyId == DifficultyUtil.ID.DungeonNormal
				or difficultyId == DifficultyUtil.ID.DungeonHeroic
				or difficultyId == DifficultyUtil.ID.DungeonMythic
				or difficultyId == DifficultyUtil.ID.DungeonChallenge
				or difficultyId == 205 -- follower dungeons
			then
				nextContentType = Private.Enum.ContentType.Dungeon
			end
		elseif instanceType == "pvp" then
			nextContentType = Private.Enum.ContentType.Battleground
		elseif instanceType == "arena" then
			nextContentType = Private.Enum.ContentType.Arena
		elseif instanceType == "scenario" then
			if difficultyId == 208 then
				nextContentType = Private.Enum.ContentType.Delve
			end
		end

		self.contentType = nextContentType

		local specId = PlayerUtil.GetCurrentSpecID()

		if
			specId == 105 -- restoration druid
			or specId == 1468 -- preservation evoker
			or specId == 270 -- mistweaver monk
			or specId == 65 -- holy paladin
			or specId == 256 -- discipline priest
			or specId == 257 -- holy priest
			or specId == 264 -- restoration shaman
		then
			self.role = Private.Enum.Role.Healer
		elseif
			specId == 250 -- blood death knight
			or specId == 581 -- vengeance demon hunter
			or specId == 104 -- guardian druid
			or specId == 268 -- brewmaster monk
			or specId == 66 -- protection paladin
			or specId == 73 -- protection warrior
		then
			self.role = Private.Enum.Role.Tank
		else
			self.role = Private.Enum.Role.Damager
		end
	elseif event == Private.Enum.Events.EDIT_MODE_POSITION_CHANGED then
		self:ClearAllPoints()
		self:SetPoint(
			---@diagnostic disable-next-line: param-type-mismatch
			AdvancedFocusCastBarSaved.Settings.Point,
			AdvancedFocusCastBarSaved.Settings.OffsetX,
			AdvancedFocusCastBarSaved.Settings.OffsetY
		)
	elseif event == "FIRST_FRAME_RENDERED" then
		self.firstFrameTimestamp = GetTime()
		self:UnregisterEvent("FIRST_FRAME_RENDERED")
	end
end

table.insert(Private.LoginFnQueue, function()
	CreateFrame("Frame", "AdvancedFocusCastBarParent", UIParent, "AdvancedFocusCastBarFrameTemplate")
end)
