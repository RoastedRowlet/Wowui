-- UI.lua


local api = WorldMarkerCyclerAPI
local targetApi = WorldMarkerCyclerTargetAPI
local mouseoverApi = WorldMarkerCyclerMouseoverAPI
local f -- forward declare frame

-- Locale table for UI strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["World Marker Key Editor"] = "Éditeur de raccourcis de marqueurs"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TOUS LES RACCOURCIS PEUVENT ÊTRE DÉFINIS ICI"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Utilisez les champs ci-dessous pour définir les raccourcis pour les marqueurs mondiaux, de cible et de survol."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordre de cycle des marqueurs (séparé par des virgules):\nex. 1CARRÉ,2TRIANGLE,3DIAMANT,4CROIX,\n5ÉTOILE,6CERCLE,7LUNE,8CRÂNE"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Remarque : Les raccourcis définis ici remplaceront ceux définis via les commandes ou autres interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this is only made for the cycle raid markers on the ground not for target or mouseovertarget."] = "Tous les marqueurs et les numéros ci-dessus représentent l'ordre qui sera utilisé lorsque vous appuierez sur les raccourcis pour la première fois. Par exemple, si vous mettez 8, le marqueur crâne sera toujours placé en premier après avoir tout effacé. Ceci concerne uniquement les marqueurs de raid au sol, pas ceux de cible ou de survol."
    L["World Cycle Key:"] = "Raccourci cycle mondial :"
    L["World Clear Key:"] = "Raccourci effacer mondial :"
    L["Target Cycle Key:"] = "Raccourci cycle cible :"
    L["Target Clear Key:"] = "Raccourci effacer cible :"
    L["Mouseover Cycle Key:"] = "Raccourci cycle survol :"
    L["Mouseover Clear Key:"] = "Raccourci effacer survol :"
end


local editBoxes = {}
local function CreateKeyEditBoxes(label, x, y, getBind, handler)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)

    local bindBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    bindBox:SetSize(160, 22)
    bindBox:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    bindBox:SetAutoFocus(false)
    bindBox:SetText(getBind())

    local function apply()
        local bind = bindBox:GetText():upper()
        -- Parse modifier and key
        local mod, key = "", bind
        if bind:find("CTRL%-") then mod = mod .. "CTRL-"; key = key:gsub("CTRL%-", "") end
        if bind:find("ALT%-") then mod = mod .. "ALT-"; key = key:gsub("ALT%-", "") end
        if bind:find("SHIFT%-") then mod = mod .. "SHIFT-"; key = key:gsub("SHIFT%-", "") end
        key = key:gsub("^%s+", "")
        local fullBind = mod .. key
        if handler then handler(mod, key, fullBind) end
        bindBox:SetText(fullBind)
        if targetApi and targetApi.UpdateBindings then targetApi.UpdateBindings() end
        if api and api.UpdateBindings then api.UpdateBindings() end
        if mouseoverApi and mouseoverApi.UpdateBindings then mouseoverApi.UpdateBindings() end
    end

    bindBox:SetScript("OnEnterPressed", apply)
    bindBox:SetScript("OnEditFocusLost", apply)

    table.insert(editBoxes, {bindBox = bindBox, getBind = getBind})
end

local function BuildUI()
        -- ...existing code...
    f = CreateFrame("Frame", "WorldMarkerCyclerUI", InterfaceOptionsFramePanelContainer)
    f.name = "World Marker Cycler"
    if SettingsPanel and SettingsPanel.AddCategory then
        SettingsPanel.AddCategory(f)
    elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category, layout = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(f)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(L["World Marker Key Editor"])
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -29)
    title:SetText(L["ALL KEYBIND CAN BE SET IN THIS PAGE"])
    title:SetTextColor(0, 1, 0)
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetTextColor(1, 1, 1, 0.8)
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText(L["Use the input boxes below to set keybindings for world, target, and mouseover markers."])

    -- Marker Order Input Box
local orderLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
orderLabel:SetPoint("TOPLEFT", 16, -400)
orderLabel:SetWidth(400)
orderLabel:SetWordWrap(true)
orderLabel:SetText(L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"])
orderLabel:SetTextColor(1, 1, 1, 1)
orderLabel:SetFontObject("SystemFont_Outline")
-- Add number labels for 1-8 under the example
local numberLabels = {}
for i = 1, 8 do
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
    lbl:SetFontObject("GameFontNormalOutline")
    lbl:SetFont(lbl:GetFont(), 18, "OUTLINE")
    lbl:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", (i-1)*28+6, -2)
    lbl:SetText(tostring(i))
    numberLabels[i] = lbl
end

-- Move icon row below the number label
local function ShowOrderIcons()
    if f._orderIcons then
        for _, t in ipairs(f._orderIcons) do t:Hide() end
    end
    f._orderIcons = f._orderIcons or {}
    local order = (WMC_Saved and WMC_Saved.orderList) or {1,2,3,4,5,6,7,8}
    for i = 1, 8 do
        local marker = order[i]
        local icon = f._orderIcons[i]
        if not icon then
            icon = f:CreateTexture(nil, "ARTWORK")
            f._orderIcons[i] = icon
        end
        icon:SetTexture(markerIcons[marker] or markerIcons[1])
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", numberLabels[i], "BOTTOMLEFT", -4, -2)
        icon:Show()
    end
end

-- Marker icon textures for 1-8 (Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star)
-- WoW marker order: 1=Square, 2=Triangle, 3=Diamond, 4=Cross, 5=Star, 6=Circle, 7=Moon, 8=Skull
local markerIcons = {
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", -- Square
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", -- Triangle (green)
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", -- Diamond (purple)
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", -- Cross (red X)
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", -- Star (yellow)
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", -- Circle (orange)
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", -- Moon (blue)
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", -- Skull
}

local function ShowOrderIcons()
    if f._orderIcons then
        for _, t in ipairs(f._orderIcons) do t:Hide() end
    end
    f._orderIcons = f._orderIcons or {}
    local order = (WMC_Saved and WMC_Saved.orderList) or {1,2,3,4,5,6,7,8}
    for i = 1, 8 do
        local marker = order[i]
        local icon = f._orderIcons[i]
        if not icon then
            icon = f:CreateTexture(nil, "ARTWORK")
            f._orderIcons[i] = icon
        end
        icon:SetTexture(markerIcons[marker] or markerIcons[1])
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", orderLabel, "BOTTOMLEFT", (i-1)*28, -4)
        icon:Show()
    end
end

ShowOrderIcons()

local orderBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
orderBox:SetSize(160, 22)
orderBox:SetPoint("LEFT", orderLabel, "RIGHT", 10, 0)
orderBox:SetAutoFocus(false)
orderBox:SetText(table.concat((WMC_Saved and WMC_Saved.orderList) or {1,2,3,4,5,6,7,8}, ","))

local function applyOrder()
    local text = orderBox:GetText()
    local t = {}
    for num in string.gmatch(text, "%d") do
        table.insert(t, tonumber(num))
    end
    if #t == 8 then
        WMC_Saved.orderList = t
        if api and api.SetOrder then api.SetOrder(t) end
    end
    orderBox:SetText(table.concat(WMC_Saved.orderList, ","))
    ShowOrderIcons()
end

orderBox:SetScript("OnEnterPressed", applyOrder)
orderBox:SetScript("OnEditFocusLost", applyOrder)

        -- ...existing code...

    -- World Marker Cycler
    -- Replace World Cycle Key input box with button
    -- local worldCycleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    -- worldCycleBtn:SetSize(160, 28)
    -- worldCycleBtn:SetPoint("TOPLEFT", 16, -40)
    -- worldCycleBtn:SetText("World Cycle Key Command")
    -- worldCycleBtn:SetScript("OnClick", function()
    --     if SlashCmdList and SlashCmdList["WMCBIND"] then
    --         SlashCmdList["WMCBIND"]("place")
    --     end
    --     if api and api.UpdateBindings then api.UpdateBindings() end
    -- end)

    -- Replace World Clear Key input box with button
    -- local worldClearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    -- worldClearBtn:SetSize(160, 28)
    -- worldClearBtn:SetPoint("TOPLEFT", 16, -80)
    -- worldClearBtn:SetText("World Clear Key Command")
    -- worldClearBtn:SetScript("OnClick", function()
    --     if SlashCmdList and SlashCmdList["WMCCLEAR"] then
    --         SlashCmdList["WMCCLEAR"]()
    --     end
    --     if api and api.UpdateBindings then api.UpdateBindings() end
    -- end)

    CreateKeyEditBoxes(L["World Cycle Key:"], 16, -70,
        function() return ((WMC_Saved and WMC_Saved.placeModifier) or "") .. ((WMC_Saved and WMC_Saved.placeKey) or "") end,
        function(mod, key)
            if api and api.SetPlaceKey then api.SetPlaceKey(mod, key) end
            if api and api.UpdateBindings then api.UpdateBindings() end
        end
    )
    CreateKeyEditBoxes(L["World Clear Key:"], 16, -100,
        function() return ((WMC_Saved and WMC_Saved.clearModifier) or "") .. ((WMC_Saved and WMC_Saved.clearKey) or "") end,
        function(mod, key)
            if api and api.SetClearKey then api.SetClearKey(mod, key) end
            if api and api.UpdateBindings then api.UpdateBindings() end
        end
    )

    -- Target Marker Cycler (target markers) - now with edit boxes
    local missingLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    missingLabel:SetPoint("TOPLEFT", 16, -110)
    missingLabel:SetTextColor(1, 0.2, 0.2)
    missingLabel:SetText("")

    CreateKeyEditBoxes(L["Target Cycle Key:"], 16, -140,
        function() return ((WMC_TargetSaved and WMC_TargetSaved.placeModifier) or "") .. ((WMC_TargetSaved and WMC_TargetSaved.placeKey) or "") end,
        function(mod, key, fullBind)
            if SlashCmdList and SlashCmdList["WMCTARGETADD"] then
                SlashCmdList["WMCTARGETADD"]("cycle " .. (mod or "") .. (mod ~= "" and " " or "") .. (key or ""))
            end
            if targetApi and targetApi.UpdateBindings then targetApi.UpdateBindings() end
        end
    )
    CreateKeyEditBoxes(L["Target Clear Key:"], 16, -190,
        function() return ((WMC_TargetSaved and WMC_TargetSaved.clearModifier) or "") .. ((WMC_TargetSaved and WMC_TargetSaved.clearKey) or "") end,
        function(mod, key, fullBind)
            if SlashCmdList and SlashCmdList["WMCTARGETADD"] then
                SlashCmdList["WMCTARGETADD"]("clear " .. (mod or "") .. (mod ~= "" and " " or "") .. (key or ""))
            end
            if targetApi and targetApi.UpdateBindings then targetApi.UpdateBindings() end
        end
    )

    -- Mouseover Marker Cycler (mouseover markers) - now with edit boxes
    CreateKeyEditBoxes(L["Mouseover Cycle Key:"], 16, -220,
        function() return ((WMC_MouseoverSaved and WMC_MouseoverSaved.placeModifier) or "") .. ((WMC_MouseoverSaved and WMC_MouseoverSaved.placeKey) or "") end,
        function(mod, key, fullBind)
            if SlashCmdList and SlashCmdList["WMCMOUSEOVERADD"] then
                SlashCmdList["WMCMOUSEOVERADD"]("cycle " .. (mod or "") .. (mod ~= "" and " " or "") .. (key or ""))
            end
            if mouseoverApi and mouseoverApi.UpdateBindings then mouseoverApi.UpdateBindings() end
        end
    )
    CreateKeyEditBoxes(L["Mouseover Clear Key:"], 16, -250,
        function() return ((WMC_MouseoverSaved and WMC_MouseoverSaved.clearModifier) or "") .. ((WMC_MouseoverSaved and WMC_MouseoverSaved.clearKey) or "") end,
        function(mod, key, fullBind)
            if SlashCmdList and SlashCmdList["WMCMOUSEOVERADD"] then
                SlashCmdList["WMCMOUSEOVERADD"]("clear " .. (mod or "") .. (mod ~= "" and " " or "") .. (key or ""))
            end
            if mouseoverApi and mouseoverApi.UpdateBindings then mouseoverApi.UpdateBindings() end
        end
    )

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 16, -300)
    label:SetText(L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."])
    label:SetWidth(400)
    label:SetWordWrap(true)
    label:SetTextColor(1, 1, 1, 1)
    label:SetFontObject("SystemFont_Outline")
     local label2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local label2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label2:SetPoint("TOPLEFT", 16, -480)
    label2:SetText(L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this is only made for the cycle raid markers on the ground not for target or mouseovertarget."])
    label2:SetWidth(400)
    label2:SetWordWrap(true)
    label2:SetTextColor(1, 1, 1, 1)
    label2:SetFontObject("SystemFont_Outline")

    -- Slash to toggle UI
    SLASH_WMCEDITOR1 = "/wmckey"
    SlashCmdList["WMCEDITOR"] = function()
        if f:IsShown() then f:Hide() else f:Show() end
    end

    -- Refresh all edit boxes when panel is shown (for slash command changes)
    f:HookScript("OnShow", function()
        -- No refresh logic
    end)

    f:Hide()
end

function WorldMarkerCyclerUI_OnReady()
    if not f then
        BuildUI()
    end
end

-- Sample Keybind Page
local samplePage
local function ShowSampleKeybindPage()
    if not samplePage then
        -- Attach to main UI page (f)
        samplePage = CreateFrame("Frame", "WorldMarkerCyclerSampleKeybindPage", f, "BackdropTemplate")
        samplePage:SetSize(420, 340)
        samplePage:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -40)
        samplePage:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
        samplePage:SetBackdropColor(0, 0, 0, 0.85)
        samplePage:Hide()

        -- Make draggable
        samplePage:SetMovable(true)
        samplePage:EnableMouse(true)
        samplePage:RegisterForDrag("LeftButton")
        samplePage:SetScript("OnDragStart", function(self) self:StartMoving() end)
        samplePage:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        local title = samplePage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("Sample Mouse Keybinds")

        -- ScrollFrame for list
        local scrollFrame = CreateFrame("ScrollFrame", nil, samplePage, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 16, -48)
        scrollFrame:SetPoint("BOTTOMRIGHT", -16, 48)

        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(380, 260)
        scrollFrame:SetScrollChild(content)

        local mouseKeys = {
            { key = "MOUSEWHEELUP", desc = "Mouse Wheel Up" },
            { key = "MOUSEWHEELDOWN", desc = "Mouse Wheel Down" },
            { key = "BUTTON1", desc = "Left Click" },
            { key = "BUTTON2", desc = "Right Click" },
            { key = "BUTTON3", desc = "Middle Button" },
            { key = "BUTTON4", desc = "Extra Mouse Button 4" },
            { key = "BUTTON5", desc = "Extra Mouse Button 5" },
            { key = "BUTTON6", desc = "Extra Mouse Button 6 (if available)" },
            { key = "BUTTON7", desc = "Extra Mouse Button 7 (if available)" },
        }

        local y = -8
        for i, info in ipairs(mouseKeys) do
            local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", 0, y)
            line:SetWidth(360)
            line:SetText("|cffffff00"..info.key.."|r - "..info.desc)
            y = y - 22
        end

        local modLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        modLine:SetPoint("TOPLEFT", 0, y)
        modLine:SetWidth(360)
        modLine:SetText("\nYou can combine with modifiers: |cffffff00CTRL-|r, |cffffff00ALT-|r, |cffffff00SHIFT-|r")
        y = y - 32

        local exampleLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        exampleLine:SetPoint("TOPLEFT", 0, y)
        exampleLine:SetWidth(360)
        exampleLine:SetText("Example: |cffffff00CTRL-MOUSEWHEELDOWN|r")
        y = y - 22

        local noteLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        noteLine:SetPoint("TOPLEFT", 0, y)
        noteLine:SetWidth(360)
        noteLine:SetText("\nNote: Key names must be uppercase and match WoW's internal names.")

        local closeBtn = CreateFrame("Button", nil, samplePage, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 24)
        closeBtn:SetPoint("BOTTOM", 0, 16)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() samplePage:Hide() end)
    end
    samplePage:Show()
end

-- Add toggle button to main UI
local function AddSampleKeybindToggle()
    if not f then return end
    local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    toggleBtn:SetSize(180, 28)
    toggleBtn:SetPoint("TOPLEFT", 16, -340)
    toggleBtn:SetText("Show Sample Mouse Keybinds")
    toggleBtn:SetScript("OnClick", ShowSampleKeybindPage)
end

-- Hook into BuildUI to add the toggle button
local oldBuildUI = BuildUI
function BuildUI()
    oldBuildUI()
    AddSampleKeybindToggle()
end