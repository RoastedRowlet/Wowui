local addonName, addonTable = ...

-- ============================================================================
-- EDIT MODE NATIVE INTEGRATION
-- ============================================================================

local editModeActive = false
local overlay = nil
local floatConfig = nil
local callbackHandles = {} -- Track registered callbacks for proper cleanup

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

function addonTable.IsEditModeActive()
    return editModeActive
end

-- ============================================================================
-- GRID RENDERING
-- ============================================================================

local function UpdateGridTexture(gridTex, width, height)
    if not gridTex then return end
    
    local texCoordWidth = width / 16
    local texCoordHeight = height / 16
    
    gridTex:SetTexCoord(0, texCoordWidth, 0, texCoordHeight)
end

function addonTable.UpdateEditModeOverlay()
    if not overlay or not editModeActive then return end
    
    local bar = addonTable.BarFrame
    if not bar then return end
    
    overlay:SetAllPoints(bar)
    
    if overlay.grid then
        local width, height = bar:GetSize()
        UpdateGridTexture(overlay.grid, width, height)
    end
end

-- ============================================================================
-- FLOATING CONFIG PANEL
-- ============================================================================

local function CreateFloatingConfig()
    if floatConfig then return floatConfig end
    
    local f = CreateFrame("Frame", "FocusMarkerEditModeConfig", UIParent, "BackdropTemplate")
    f:SetSize(260, 170)
    f:SetPoint("CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(1000)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)
    
    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetWidth(256)
    header:SetHeight(64)
    header:SetPoint("TOP", 0, 12)
    
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("FocusMarker Settings")
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        f:Hide()
    end)
    
    local btnOrient = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnOrient:SetSize(180, 30)
    btnOrient:SetPoint("TOP", f, "TOP", 0, -40)
    btnOrient:SetText("Toggle Orientation")
    btnOrient:SetScript("OnClick", function()
        if not FocusMarkerDB then return end
        FocusMarkerDB.orientation = (FocusMarkerDB.orientation == "HORIZONTAL") and "VERTICAL" or "HORIZONTAL"
        if addonTable.UpdateLayout then addonTable.UpdateLayout() end
        if addonTable.UpdateEditModeOverlay then addonTable.UpdateEditModeOverlay() end
        if addonTable.UpdateConfigUI then addonTable.UpdateConfigUI() end
    end)
    
    local sizeLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sizeLabel:SetPoint("TOP", btnOrient, "BOTTOM", 0, -15)
    sizeLabel:SetText("Icon Size Selector")

    local sizeOptions = {
        {label="16 (Tiny)", value=16}, 
        {label="24 (Small)", value=24}, 
        {label="32 (Normal)", value=32}, 
        {label="40 (Large)", value=40}, 
        {label="48 (X-Large)", value=48}, 
        {label="64 (Huge)", value=64}
    }
    
    local btnSize = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnSize:SetSize(180, 24)
    btnSize:SetPoint("TOP", sizeLabel, "BOTTOM", 0, -5)
    
    local function UpdateSizeButtonText()
        if not FocusMarkerDB then return end
        local current = FocusMarkerDB.iconSize
        for _, opt in ipairs(sizeOptions) do
            if opt.value == current then
                btnSize:SetText("Size: " .. opt.label)
                return
            end
        end
        btnSize:SetText("Size: " .. current)
    end
    
    local sizeList = CreateFrame("Frame", nil, btnSize, "BackdropTemplate")
    sizeList:SetPoint("TOP", btnSize, "BOTTOM", 0, 0)
    sizeList:SetSize(180, #sizeOptions * 20 + 10)
    sizeList:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    sizeList:SetFrameStrata("DIALOG")
    sizeList:SetFrameLevel(f:GetFrameLevel() + 10) 
    sizeList:Hide()
    
    for i, opt in ipairs(sizeOptions) do
        local b = CreateFrame("Button", nil, sizeList)
        b:SetSize(170, 20)
        b:SetPoint("TOP", 0, -((i-1)*20) - 5)
        
        local t = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("CENTER")
        t:SetText(opt.label)
        
        b:SetScript("OnEnter", function() t:SetTextColor(1, 1, 0) end)
        b:SetScript("OnLeave", function() t:SetTextColor(1, 1, 1) end)
        
        b:SetScript("OnClick", function()
            if not FocusMarkerDB then return end
            FocusMarkerDB.iconSize = opt.value
            UpdateSizeButtonText()
            if addonTable.UpdateLayout then addonTable.UpdateLayout() end
            if addonTable.UpdateEditModeOverlay then addonTable.UpdateEditModeOverlay() end
            if addonTable.UpdateConfigUI then addonTable.UpdateConfigUI() end
            sizeList:Hide()
        end)
    end
    
    btnSize:SetScript("OnClick", function()
        if sizeList:IsShown() then sizeList:Hide() else sizeList:Show() end
    end)
    
    addonTable.SyncEditModeConfig = function()
        if not f:IsShown() then return end
        UpdateSizeButtonText()
        sizeList:Hide()
    end
    
    f:Hide()
    floatConfig = f
    return f
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function addonTable.ToggleEditModeConfig(anchorFrame)
    if not floatConfig then CreateFloatingConfig() end
    
    if floatConfig:IsShown() then 
        floatConfig:Hide() 
    else 
        floatConfig:Show()
        if addonTable.SyncEditModeConfig then addonTable.SyncEditModeConfig() end
        if anchorFrame then
            floatConfig:ClearAllPoints()
            local barTop = anchorFrame:GetTop() or 0
            local screenHeight = UIParent:GetHeight()
            if (screenHeight - barTop) > 200 then
                floatConfig:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 20)
            else
                floatConfig:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -20)
            end
        end
    end
end

function addonTable.CloseEditModeConfig()
    if floatConfig then floatConfig:Hide() end
end

-- ============================================================================
-- OVERLAY CREATION
-- ============================================================================

local function CreateNativeOverlay()
    local bar = addonTable.BarFrame
    if not bar then return end

    overlay = CreateFrame("Button", nil, bar, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(bar:GetFrameLevel() + 10) 
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    
    overlay:SetBackdrop({
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", 
        edgeSize = 2,
    })
    overlay:SetBackdropBorderColor(0, 0.7, 1, 1)

    overlay.grid = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.grid:SetTexture("Interface\\EditMode\\Patterns\\Grid16x16")
    overlay.grid:SetHorizTile(true)
    overlay.grid:SetVertTile(true)
    overlay.grid:SetAllPoints()
    overlay.grid:SetAlpha(0.3)
    overlay.grid:SetBlendMode("ADD")

    overlay.center = overlay:CreateTexture(nil, "OVERLAY")
    overlay.center:SetTexture("Interface\\EditMode\\Selection\\CenterPoint")
    overlay.center:SetSize(32, 32)
    overlay.center:SetPoint("CENTER")
    overlay.center:SetVertexColor(0, 0.7, 1, 0.8)

    overlay.labelParams = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.labelParams:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
    overlay.labelParams:SetText("FocusMarker")
    
    local bg = overlay:CreateTexture(nil, "ARTWORK")
    bg:SetColorTexture(0, 0.1, 0.2, 0.8)
    bg:SetPoint("TOPLEFT", overlay.labelParams, "TOPLEFT", -4, 2)
    bg:SetPoint("BOTTOMRIGHT", overlay.labelParams, "BOTTOMRIGHT", 4, -2)
    
    overlay.clickLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    overlay.clickLabel:SetPoint("CENTER", 0, 0)
    overlay.clickLabel:SetText("Click To Edit")
    overlay.clickLabel:Hide()
    
    overlay:SetScript("OnDragStart", function() 
        if bar:IsMovable() then bar:StartMoving() end
    end)
    
    overlay:SetScript("OnDragStop", function() 
        bar:StopMovingOrSizing()
        local script = bar:GetScript("OnDragStop")
        if script then script(bar) end
    end)
    
    overlay:SetScript("OnClick", function()
        if addonTable.ToggleEditModeConfig then addonTable.ToggleEditModeConfig(bar) end
    end)
    
    overlay:SetScript("OnEnter", function() 
        overlay:SetBackdropBorderColor(0.5, 0.9, 1, 1) 
        overlay.clickLabel:Show()
        GameTooltip:SetOwner(overlay, "ANCHOR_CURSOR")
        GameTooltip:SetText("FocusMarker", 1, 1, 1)
        GameTooltip:AddLine("Click to edit settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to reposition", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    
    overlay:SetScript("OnLeave", function()
        overlay:SetBackdropBorderColor(0, 0.7, 1, 1) 
        overlay.clickLabel:Hide()
        GameTooltip:Hide()
    end)
end

-- ============================================================================
-- EDIT MODE INITIALIZATION
-- ============================================================================

function addonTable.InitEditMode()
    if not EventRegistry then return end
    
    local function OnEnter()
        editModeActive = true
        if not overlay then CreateNativeOverlay() end
        if overlay then overlay:Show() end
        if addonTable.UpdateLayout then addonTable.UpdateLayout() end
    end
    
    local function OnExit()
        editModeActive = false
        if overlay then overlay:Hide() end
        if addonTable.CloseEditModeConfig then addonTable.CloseEditModeConfig() end
        if addonTable.UpdateLayout then addonTable.UpdateLayout() end
    end
    
    -- API 10.0+ EventRegistry usage
    local enterHandle = EventRegistry:RegisterCallback("EditMode.Enter", OnEnter, addonName)
    local exitHandle = EventRegistry:RegisterCallback("EditMode.Exit", OnExit, addonName)
    
    callbackHandles.enter = enterHandle
    callbackHandles.exit = exitHandle
end

function addonTable.CleanupEditMode()
    if EventRegistry and callbackHandles then
        if callbackHandles.enter then EventRegistry:UnregisterCallback("EditMode.Enter", addonName) end
        if callbackHandles.exit then EventRegistry:UnregisterCallback("EditMode.Exit", addonName) end
    end
    if overlay then overlay:Hide(); overlay = nil end
    if floatConfig then floatConfig:Hide(); floatConfig = nil end
    editModeActive = false
end