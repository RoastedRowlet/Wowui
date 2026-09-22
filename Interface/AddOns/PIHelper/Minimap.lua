--[[
	PI Helper minimap button
	Created only when the setting is on. Drag uses OnUpdate while moving,
	then clears it. Click opens options.
]]

local _, addon = ...

local BUTTON_SIZE = 31
local ICON_SIZE = 24
local BG_SIZE = 24
local BORDER_SIZE = 50
local RADIUS_PAD = 5
local DEFAULT_ANGLE = 250
local ICON_PATH = "Interface\\Icons\\spell_holy_powerinfusion"

local minimapButton

local function MinimapRadius()
	local width = Minimap and Minimap.GetWidth and Minimap:GetWidth()
	if type(width) ~= "number" then
		return 80
	end
	return (width / 2) + RADIUS_PAD
end

local function UpdatePosition()
	if not minimapButton or not addon.db then
		return
	end
	local angle = addon.db.minimapAngle
	if type(angle) ~= "number" then
		angle = DEFAULT_ANGLE
	end
	angle = math.rad(angle)
	local radius = MinimapRadius()
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragUpdate(self)
	self.dragMoved = true
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	if type(mx) ~= "number" or type(my) ~= "number" or type(scale) ~= "number" then
		return
	end
	if type(px) ~= "number" or type(py) ~= "number" or scale == 0 then
		return
	end
	px, py = px / scale, py / scale
	addon.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
	UpdatePosition()
end

local function StopDrag(self)
	self:SetScript("OnUpdate", nil)
	self:UnlockHighlight()
end

local function EnsureButton()
	if minimapButton or not Minimap then
		return
	end

	local btn = CreateFrame("Button", "PIHelperMinimapButton", Minimap)
	btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = btn:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(BORDER_SIZE, BORDER_SIZE)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = btn:CreateTexture(nil, "BACKGROUND")
	background:SetSize(BG_SIZE, BG_SIZE)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("CENTER")

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetTexture(ICON_PATH)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetPoint("CENTER")

	local mask = btn:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("PI Helper")
		GameTooltip:AddLine("Left-click to open options.", 0.90, 0.91, 0.92, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	btn:SetScript("OnMouseDown", function(self)
		self.dragMoved = false
	end)
	btn:SetScript("OnClick", function(self)
		if self.dragMoved then
			return
		end
		if addon.ToggleOptions then
			addon.ToggleOptions()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", DragUpdate)
	end)
	btn:SetScript("OnDragStop", StopDrag)
	btn:SetScript("OnHide", StopDrag)

	minimapButton = btn
end

function addon.SyncMinimap()
	if not addon.db then
		return
	end
	if addon.db.showMinimap == true and addon.ClassAllowed() then
		EnsureButton()
		if minimapButton then
			UpdatePosition()
			minimapButton:Show()
		end
		return
	end
	if minimapButton then
		minimapButton:Hide()
	end
end
