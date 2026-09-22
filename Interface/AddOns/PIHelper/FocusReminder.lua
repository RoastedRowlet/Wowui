--[[
	Popup that reminds you to focus a friendly player in raid and dungeon
	instances. Stays on screen until a friendly player is focused, or
	ignored until the next reload.
]]

local ADDON_NAME, addon = ...

local popup
local queued
local previewing
local hiding
local dismissedThisSession
local ShowPopup
local RefreshTestButton

-- "raid", "dungeon", or nil (outdoors / pvp / unknown). Do not use instance
-- IDs: they can be secret on restricted maps.
local function InstanceKind()
	local instanceType
	if GetInstanceInfo then
		instanceType = select(2, GetInstanceInfo())
	end
	if addon.IsSecret(instanceType) or type(instanceType) ~= "string" then
		instanceType = nil
	end
	if instanceType == "raid" then
		return "raid"
	end
	if instanceType == "party" then
		return "dungeon"
	end
	if not IsInInstance then
		return nil
	end
	local ok, inInstance, instType = pcall(IsInInstance)
	if not ok then
		return nil
	end
	if addon.PlainBool(inInstance) ~= true then
		return nil
	end
	if addon.IsSecret(instType) or type(instType) ~= "string" then
		instType = nil
	end
	if instType == "raid" then
		return "raid"
	end
	if instType == "party" then
		return "dungeon"
	end
	if instType then
		return nil
	end
	if IsInRaid and IsInRaid() then
		return "raid"
	end
	return "dungeon"
end

local function InstanceWantsReminder()
	local db = addon.db
	if not db then
		return false
	end
	local kind = InstanceKind()
	if kind == "raid" then
		return db.focusRemindRaid == true
	end
	if kind == "dungeon" then
		return db.focusRemindDungeon == true
	end
	return false
end

local function HidePopup()
	hiding = true
	if popup then
		popup:Hide()
	end
	hiding = false
end

local function DismissForSession()
	dismissedThisSession = true
	HidePopup()
end

local function ShouldShowReminder()
	if dismissedThisSession then
		return false
	end
	local db = addon.db
	if not db or not db.enabled or not db.focusRemindEnabled then
		return false
	end
	if not (addon.ContextIsWatching and addon.ContextIsWatching("focus")) then
		return false
	end
	if addon.IsActive and not addon.IsActive() then
		return false
	end
	if not addon.ClassAllowed() then
		return false
	end
	if db.healerOnly and not addon.IsHealerSpec() then
		return false
	end
	if addon.HasFriendlyPlayerFocus and addon.HasFriendlyPlayerFocus() then
		return false
	end
	return InstanceWantsReminder()
end

local function EnsurePopup()
	if popup then
		return popup
	end
	local C = addon.C
	local f = CreateFrame("Frame", "PIHelperFocusReminder", UIParent)
	f:SetSize(320, 128)
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 0.98)

	local function edge(point1, point2, w, h)
		local tex = f:CreateTexture(nil, "OVERLAY")
		tex:SetColorTexture(C.windowBorder[1], C.windowBorder[2], C.windowBorder[3], 1)
		tex:SetPoint(point1)
		tex:SetPoint(point2)
		if w then
			tex:SetWidth(w)
		end
		if h then
			tex:SetHeight(h)
		end
		return tex
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 1)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

	local title = f:CreateFontString(nil, "OVERLAY")
	title:SetFont(addon.FONT, 15, "")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Set Focus")
	title:SetTextColor(C.gold[1], C.gold[2], C.gold[3], 1)

	local body = f:CreateFontString(nil, "OVERLAY")
	body:SetFont(addon.FONT, 12, "")
	body:SetPoint("TOPLEFT", 14, -36)
	body:SetPoint("BOTTOMRIGHT", -14, 42)
	body:SetJustifyH("LEFT")
	body:SetWordWrap(true)
	body:SetText("Focus a friendly player to track their cooldowns. Until then, raid and dungeon tracking still apply.")
	body:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	f.body = body

	local dismiss = CreateFrame("Button", nil, f)
	dismiss:SetSize(210, 22)
	dismiss:SetPoint("BOTTOM", 0, 12)
	local dismissBg = dismiss:CreateTexture(nil, "BACKGROUND")
	dismissBg:SetAllPoints()
	dismissBg:SetColorTexture(0.16, 0.18, 0.19, 1)
	local function dismissEdge(point1, point2, w, h)
		local tex = dismiss:CreateTexture(nil, "OVERLAY")
		tex:SetColorTexture(C.windowBorder[1], C.windowBorder[2], C.windowBorder[3], 1)
		tex:SetPoint(point1)
		tex:SetPoint(point2)
		if w then
			tex:SetWidth(w)
		end
		if h then
			tex:SetHeight(h)
		end
	end
	dismissEdge("TOPLEFT", "TOPRIGHT", nil, 1)
	dismissEdge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	dismissEdge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	dismissEdge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
	local dismissLbl = dismiss:CreateFontString(nil, "OVERLAY")
	dismissLbl:SetFont(addon.FONT, 12, "")
	dismissLbl:SetPoint("CENTER", 0, 0.5)
	dismissLbl:SetText("Ignore until next reload")
	dismissLbl:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	dismiss:SetScript("OnEnter", function()
		dismissLbl:SetTextColor(C.gold[1], C.gold[2], C.gold[3], 1)
	end)
	dismiss:SetScript("OnLeave", function()
		dismissLbl:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	end)
	dismiss:SetScript("OnClick", function()
		if previewing then
			addon.HideTestFocusReminder()
			return
		end
		DismissForSession()
	end)
	dismiss:Hide()
	f.dismiss = dismiss

	popup = f
	f:Hide()
	f:SetScript("OnHide", function()
		local wasPreview = previewing
		if hiding then
			previewing = false
			if f.dismiss then
				f.dismiss:Hide()
			end
			if wasPreview then
				RefreshTestButton()
			end
			return
		end
		if previewing then
			previewing = false
			if f.dismiss then
				f.dismiss:Hide()
			end
			RefreshTestButton()
			return
		end
		if ShouldShowReminder() then
			C_Timer.After(0, function()
				if ShouldShowReminder() then
					ShowPopup(false)
				end
			end)
		end
	end)
	return f
end

RefreshTestButton = function()
	if addon.UI and addon.UI.RefreshWidgets then
		addon.UI.RefreshWidgets()
	end
end

ShowPopup = function(isPreview)
	local frame = EnsurePopup()
	previewing = isPreview and true or false
	if frame.dismiss then
		frame.dismiss:Show()
	end
	frame:Show()
	if previewing then
		RefreshTestButton()
	end
end

function addon.IsTestFocusReminderOn()
	return previewing == true and popup and popup:IsShown()
end

function addon.HideTestFocusReminder()
	if not previewing then
		return
	end
	HidePopup()
	if ShouldShowReminder() then
		ShowPopup(false)
	end
end

function addon.ToggleTestFocusReminder()
	if addon.IsTestFocusReminderOn() then
		addon.HideTestFocusReminder()
	else
		ShowPopup(true)
	end
	return addon.IsTestFocusReminderOn()
end

function addon.RefreshFocusReminder()
	if previewing then
		return
	end
	if ShouldShowReminder() then
		ShowPopup(false)
		return
	end
	HidePopup()
end

local function QueueRefresh()
	if not (addon.IsActive and addon.IsActive() and addon.db and addon.db.focusRemindEnabled) then
		HidePopup()
		queued = false
		return
	end
	if queued then
		return
	end
	queued = true
	C_Timer.After(0.5, function()
		queued = false
		addon.RefreshFocusReminder()
	end)
end

addon.On("LOGIN", QueueRefresh)
addon.On("FOCUS", function()
	if previewing then
		return
	end
	if popup and popup:IsShown() and not ShouldShowReminder() then
		HidePopup()
		return
	end
	QueueRefresh()
end)
addon.On("POLICY", QueueRefresh)
addon.On("ACTIVATE", QueueRefresh)

local events
local function SyncReminderEvents()
	local db = addon.db
	local want = addon.IsActive and addon.IsActive() and db and db.focusRemindEnabled
	if want then
		if not events then
			events = CreateFrame("Frame")
			events:SetScript("OnEvent", QueueRefresh)
		end
		events:RegisterEvent("CHALLENGE_MODE_START")
		events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		events:RegisterEvent("PLAYER_ENTERING_WORLD")
	elseif events then
		events:UnregisterAllEvents()
		HidePopup()
	end
end

addon.On("LOGIN", SyncReminderEvents)
addon.On("ACTIVATE", SyncReminderEvents)
addon.On("POLICY", SyncReminderEvents)
addon.On("DEACTIVATE", function()
	if events then
		events:UnregisterAllEvents()
	end
	HidePopup()
end)
