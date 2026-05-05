---@type string, AdvancedFocusCastBar
local addonName, Private = ...

Private.L = {}

Private.EventRegistry = CreateFromMixins(CallbackRegistryMixin)
Private.EventRegistry:OnLoad()

do
	local tbl = {}

	for _, value in pairs(Private.Enum.Events) do
		table.insert(tbl, value)
	end

	Private.EventRegistry:GenerateCallbackEvents(tbl)
end

Private.LoginFnQueue = {}

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	---@type SavedVariables
	AdvancedFocusCastBarSaved = AdvancedFocusCastBarSaved or {}

	---@type AdvancedFocusCastBarSettings
	AdvancedFocusCastBarSaved.Settings = AdvancedFocusCastBarSaved.Settings or {}

	for key, value in pairs(Private.Settings.GetDefaultSettings()) do
		if
			AdvancedFocusCastBarSaved.Settings[key] == nil
			or type(value) ~= type(AdvancedFocusCastBarSaved.Settings[key])
		then
			AdvancedFocusCastBarSaved.Settings[key] = value
		end
	end

	for i = 1, #Private.LoginFnQueue do
		local fn = Private.LoginFnQueue[i]
		fn()
	end

	table.wipe(Private.LoginFnQueue)
end)
