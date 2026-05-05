local addonName, addonTable = ...

-- UI Reference Store for Standard Options
local ui = {
    markerSection = nil,
    controls = {}
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function CreateStyledCheckbox(parent, labelText, relativeTo, yOffset, getter, setter)
    local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    if relativeTo == parent then btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    else btn:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset) end
    btn:SetSize(26, 26) -- Slightly smaller button
    local text = btn.Text
    text:SetText(labelText); text:SetFontObject("GameFontNormal"); text:SetTextColor(1, 0.82, 0)
    text:ClearAllPoints(); text:SetPoint("LEFT", btn, "RIGHT", 4, 0) -- Reduced padding
    btn:SetChecked(getter())
    btn:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    btn:SetScript("OnEnter", nil); btn:SetScript("OnLeave", nil)
    return btn
end

local function CreateDropdownRow(parent, labelText, relativeTo, yOffset, width, getOptions, getVal, setVal)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(560, 32) -- Reduced height
    if relativeTo == parent then frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    else frame:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset) end

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", 0, 0); label:SetText(labelText); label:SetTextColor(1, 0.82, 0)

    local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    btn:SetSize(width or 180, 26); btn:SetPoint("RIGHT", frame, "RIGHT", -10, 0) -- Reduced width slightly
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    btn:SetBackdropColor(0, 0, 0, 0.8); btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Dropdown Arrow
    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -10, 0)

    local btnText = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", 10, 0); btnText:SetPoint("RIGHT", -25, 0); btnText:SetJustifyH("LEFT")

    local list = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, 0); list:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    list:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    list:SetBackdropColor(0.1, 0.1, 0.1, 1); list:Hide(); list:SetFrameStrata("DIALOG")

    btn:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else 
            if not list.buttons then list.buttons = {} end
            for _, b in ipairs(list.buttons) do b:Hide() end
            local options = getOptions(); local height = 0
            for i, opt in ipairs(options) do
                local b = list.buttons[i]
                if not b then
                    b = CreateFrame("Button", nil, list); b:SetHeight(20)
                    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
                    local t = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); t:SetPoint("LEFT", 5, 0); b.text = t; list.buttons[i] = b
                end
                b:SetPoint("TOPLEFT", 0, -((i-1)*20)); b:SetPoint("TOPRIGHT", 0, -((i-1)*20))
                b:Show(); b.text:SetText(opt.label)
                b:SetScript("OnClick", function() setVal(opt.value); btnText:SetText(opt.label); list:Hide() end)
                height = height + 20
            end
            list:SetHeight(height + 10); list:Show()
        end
    end)
    frame.UpdateDisplay = function()
        local val = getVal(); local options = getOptions(); local labelFound = tostring(val)
        for _, opt in ipairs(options) do if opt.value == val then labelFound = opt.label; break end end
        btnText:SetText(labelFound)
    end
    frame.UpdateDisplay()
    return frame
end

local function CreateSectionFrame(parent, title, relativeTo, yOffset, height)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(600, height or 120) -- Default height slightly reduced
    if relativeTo then f:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset)
    else f:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset) end
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.5); f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 12, 14); fs:SetText(title); fs:SetTextColor(0.2, 0.8, 1)
    return f
end

local function CreateOptions()
    local panel = CreateFrame("Frame")
    panel.name = "FocusMarker" 
    ui.panel = panel
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FocusMarker")
    addonTable.CategoryID = category.ID 
    Settings.RegisterAddOnCategory(category)
    
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    header:SetPoint("TOPLEFT", 16, -16); header:SetText("FocusMarker Suite")

    -- Removed ScrollFrame to remove scrollbar
    local content = CreateFrame("Frame", nil, panel); 
    content:SetPoint("TOPLEFT", 5, -50); 
    content:SetPoint("BOTTOMRIGHT", -28, 10) 

    -- MARKER SETTINGS (Reduced height and spacing)
    local markSec = CreateSectionFrame(content, "Marker Settings", nil, -20, 190)
    local cbShow = CreateStyledCheckbox(markSec, "Show Icon Bar", markSec, -20, function() return FocusMarkerDB.barVisible end, function(val) FocusMarkerDB.barVisible = val; addonTable.UpdateLayout() end)
    ui.controls.cbShow = cbShow
    local cbLock = CreateStyledCheckbox(markSec, "Lock Icon Bar", cbShow, -2, function() return FocusMarkerDB.isLocked end, function(val) FocusMarkerDB.isLocked = val; addonTable.UpdateLayout() end)
    ui.controls.cbLock = cbLock
    local cbNoMouseover = CreateStyledCheckbox(markSec, "Focus Target (No Mouseover)", cbLock, -2, function() return FocusMarkerDB.noMouseover end, function(val) FocusMarkerDB.noMouseover = val; addonTable.UpdateLayout() end)
    ui.controls.cbNoMouseover = cbNoMouseover
    local rowOrient = CreateDropdownRow(markSec, "Bar Orientation", cbNoMouseover, -2, 200, function() return { {label="Horizontal", value="HORIZONTAL"}, {label="Vertical", value="VERTICAL"} } end, function() return FocusMarkerDB.orientation end, function(val) FocusMarkerDB.orientation = val; addonTable.UpdateLayout() end)
    ui.controls.rowOrient = rowOrient
    local rowSize = CreateDropdownRow(markSec, "Icon Size", rowOrient, -2, 200, function() return { {label="16 (Tiny)", value=16}, {label="24 (Small)", value=24}, {label="32 (Normal)", value=32}, {label="40 (Large)", value=40}, {label="48 (X-Large)", value=48}, {label="64 (Huge)", value=64} } end, function() return FocusMarkerDB.iconSize end, function(val) FocusMarkerDB.iconSize = val; addonTable.UpdateLayout() end)
    ui.controls.rowSize = rowSize

    local helpSec = CreateSectionFrame(content, "Instructions & Commands", markSec, -30, 200) -- Reduced spacing and height
    local helpText = helpSec:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    helpText:SetPoint("TOPLEFT", 16, -20) -- Increased top spacing to -30
    helpText:SetWidth(560) -- Ensure wrapping
    helpText:SetJustifyH("LEFT")
    helpText:SetSpacing(2) -- Slightly tighter line spacing
    
    local instructions = [[|cFF33DDFFMACRO SETUP:|r
1. Type |cFFFFD100/macro|r
2. Create macro |cFFFFD100FocusMark|r
3. Leave body EMPTY.
4. Drag to bar.

|cFF33DDFFCHAT COMMANDS:|r
  |cFFFFD100/fm lock|r - Toggle lock
  |cFFFFD100/fm show|r - Show bar
  |cFFFFD100/fm hide|r - Hide bar
  |cFFFFD100/fm reset|r - Defaults]]
    
    helpText:SetText(instructions)
    
    addonTable.OpenConfig = function() 
        if InCombatLockdown() then print("|cffff0000FocusMarker:|r Cannot open settings in combat.") return end
        Settings.OpenToCategory(addonTable.CategoryID)
    end
end

function addonTable.UpdateConfigUI()
    if not ui.panel then return end
    local c = ui.controls
    if c.cbShow then c.cbShow:SetChecked(FocusMarkerDB.barVisible) end
    if c.cbLock then c.cbLock:SetChecked(FocusMarkerDB.isLocked) end
    if c.cbNoMouseover then c.cbNoMouseover:SetChecked(FocusMarkerDB.noMouseover) end
    if c.rowOrient then c.rowOrient.UpdateDisplay() end
    if c.rowSize then c.rowSize.UpdateDisplay() end

    if addonTable.SyncEditModeConfig then addonTable.SyncEditModeConfig() end
end

function addonTable.InitConfig()
    CreateOptions()
end

SLASH_FOCUSMARKER1 = "/fm"
SlashCmdList["FOCUSMARKER"] = function(msg)
    local cmd = msg and msg:lower() or ""
    if InCombatLockdown() and (cmd == "" or cmd == nil) then print("|cffff0000FocusMarker:|r Cannot open settings in combat."); return end
    if cmd == "lock" then 
        FocusMarkerDB.isLocked = not FocusMarkerDB.isLocked
        addonTable.UpdateLayout()
        addonTable.UpdateConfigUI()
        print("FocusMarker: " .. (FocusMarkerDB.isLocked and "Locked" or "Unlocked"))
    elseif cmd == "show" then 
        FocusMarkerDB.barVisible = true
        addonTable.UpdateLayout()
        addonTable.UpdateConfigUI()
    elseif cmd == "hide" then 
        FocusMarkerDB.barVisible = false
        addonTable.UpdateLayout()
        addonTable.UpdateConfigUI()
    elseif cmd == "reset" then 
        FocusMarkerDB.position = { "CENTER", "UIParent", "CENTER", 0, 0 }; 
        FocusMarkerDB.iconSize = 32; 
        FocusMarkerDB.isLocked = true; 
        FocusMarkerDB.orientation = "HORIZONTAL"; 
        FocusMarkerDB.noMouseover = false;
        if addonTable.ApplyPosition then addonTable.ApplyPosition() end
        addonTable.UpdateLayout(); 
        addonTable.UpdateConfigUI(); 
        print("FocusMarker: Settings reset.")
    else 
        if addonTable.OpenConfig then addonTable.OpenConfig() end 
    end
end