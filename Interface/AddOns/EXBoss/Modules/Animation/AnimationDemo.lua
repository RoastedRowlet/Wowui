-- 动画 API 测试面板：验证 SimpleAnimGroup / Translation 位移动画
-- 使用 /exanim 打开或关闭

local PANEL_SIZE = 250
local ARROW_SIZE = 40
local ARROW_TRAVEL = PANEL_SIZE - ARROW_SIZE
local ARROW_DURATION = 1
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

local PANEL_TEXTURE_PATH = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RubyPanel.png"

-- 起始边 -> {箭头朝向所用的 Atlas, 起始锚点, 位移终点相对起点的偏移}
local ARROWS = {
	Top = { atlas = "NPE_ArrowDown", point = "TOP", offsetX = 0, offsetY = -ARROW_TRAVEL },
	Bottom = { atlas = "NPE_ArrowUp", point = "BOTTOM", offsetX = 0, offsetY = ARROW_TRAVEL },
	Left = { atlas = "NPE_ArrowRight", point = "LEFT", offsetX = ARROW_TRAVEL, offsetY = 0 },
	Right = { atlas = "NPE_ArrowLeft", point = "RIGHT", offsetX = -ARROW_TRAVEL, offsetY = 0 },
}

local FIRE_ATLAS = "dreamsurge_fire-portal-icon"
local FIRE_SIZE = 40
local FIRE_BREATH_DURATION = 0.8

-- 停靠边 -> 图标停靠的锚点（只定位，不位移）
local FIRE_POINTS = {
	Top = "TOP",
	Bottom = "BOTTOM",
	Left = "LEFT",
	Right = "RIGHT",
}

local frame
local animArea
local arrowTexture
local arrowAnimGroup
local arrowTranslate
local fireTexture
local fireAnimGroup

local function EnsureArrow()
	if arrowTexture then
		return
	end

	arrowTexture = animArea:CreateTexture(nil, "OVERLAY")
	arrowTexture:SetSize(ARROW_SIZE, ARROW_SIZE)
	arrowTexture:Hide()

	arrowAnimGroup = arrowTexture:CreateAnimationGroup()
	arrowTranslate = arrowAnimGroup:CreateAnimation("Translation")
	arrowTranslate:SetDuration(ARROW_DURATION)
	arrowTranslate:SetSmoothing("OUT")

	arrowAnimGroup:SetScript("OnFinished", function()
		arrowTexture:Hide()
	end)
end

local function PlayArrow(direction)
	EnsureArrow()

	local config = ARROWS[direction]
	arrowAnimGroup:Stop()
	arrowTexture:SetAtlas(config.atlas, false)
	arrowTexture:ClearAllPoints()
	arrowTexture:SetPoint(config.point, animArea, config.point, 0, 0)
	arrowTranslate:SetOffset(config.offsetX, config.offsetY)
	arrowTexture:Show()
	arrowAnimGroup:Play()
end

local function EnsureFire()
	if fireTexture then
		return
	end

	fireTexture = animArea:CreateTexture(nil, "OVERLAY")
	fireTexture:SetAtlas(FIRE_ATLAS, false)
	fireTexture:SetSize(FIRE_SIZE, FIRE_SIZE)
	fireTexture:Hide()

	fireAnimGroup = fireTexture:CreateAnimationGroup()
	fireAnimGroup:SetLooping("BOUNCE")

	local scaleAnim = fireAnimGroup:CreateAnimation("Scale")
	scaleAnim:SetScaleFrom(1, 1)
	scaleAnim:SetScaleTo(1.15, 1.15)
	scaleAnim:SetDuration(FIRE_BREATH_DURATION)
	scaleAnim:SetSmoothing("IN_OUT")

	local alphaAnim = fireAnimGroup:CreateAnimation("Alpha")
	alphaAnim:SetFromAlpha(0.6)
	alphaAnim:SetToAlpha(1)
	alphaAnim:SetDuration(FIRE_BREATH_DURATION)
	alphaAnim:SetSmoothing("IN_OUT")
end

local function PlayFire(direction)
	EnsureFire()

	local point = FIRE_POINTS[direction]
	fireAnimGroup:Stop()
	fireTexture:ClearAllPoints()
	fireTexture:SetPoint(point, animArea, point, 0, 0)
	fireTexture:Show()
	fireAnimGroup:Play()
end

local function CreateDemoButton(parent, label, x, y, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(50, 22)
	button:SetText(label)
	button:SetPoint("BOTTOM", parent, "BOTTOM", x, y)
	button:SetScript("OnClick", onClick)
	return button
end

local function CreateDemoFrame()
	frame = CreateFrame("Frame", "EXBossAnimationDemoFrame", UIParent, "BackdropTemplate")
	frame:SetSize(PANEL_SIZE + 40, PANEL_SIZE + 140)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetScript("OnHide", function()
		if arrowAnimGroup then
			arrowAnimGroup:Stop()
			arrowTexture:Hide()
		end
		if fireAnimGroup then
			fireAnimGroup:Stop()
			fireTexture:Hide()
		end
	end)

	local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", -4, -4)
	closeButton:SetScript("OnClick", function()
		frame:Hide()
	end)

	animArea = CreateFrame("Frame", nil, frame)
	animArea:SetSize(PANEL_SIZE, PANEL_SIZE)
	animArea:SetPoint("TOP", frame, "TOP", 0, -20)

	local panelTexture = animArea:CreateTexture(nil, "BACKGROUND")
	panelTexture:SetAllPoints(animArea)
	panelTexture:SetTexture(PANEL_TEXTURE_PATH)

	-- 第一排：位移箭头测试
	CreateDemoButton(frame, L["上"], -75, 55, function() PlayArrow("Top") end)
	CreateDemoButton(frame, L["下"], -25, 55, function() PlayArrow("Bottom") end)
	CreateDemoButton(frame, L["左"], 25, 55, function() PlayArrow("Left") end)
	CreateDemoButton(frame, L["右"], 75, 55, function() PlayArrow("Right") end)

	-- 第二排：火焰图标呼吸测试
	CreateDemoButton(frame, L["火上"], -75, 20, function() PlayFire("Top") end)
	CreateDemoButton(frame, L["火下"], -25, 20, function() PlayFire("Bottom") end)
	CreateDemoButton(frame, L["火左"], 25, 20, function() PlayFire("Left") end)
	CreateDemoButton(frame, L["火右"], 75, 20, function() PlayFire("Right") end)

	return frame
end

SLASH_EXBOSSANIMDEMO1 = "/exanim"
SlashCmdList["EXBOSSANIMDEMO"] = function()
	if not frame then
		CreateDemoFrame()
	end

	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end
