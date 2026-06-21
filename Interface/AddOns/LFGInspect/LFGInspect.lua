local varFrame = CreateFrame("frame", nil, UIParent)
varFrame:RegisterEvent("ADDON_LOADED")
varFrame:SetScript("OnEvent", function(self, event, arg1)
if event == "ADDON_LOADED" and arg1 == "LFGInspect" then
varFrame:UnregisterEvent("ADDON_LOADED")

----------
local default =
{
	classColor = true,
	groupAge = true,
	showIgnore = true,
	alwaysShowRaidComp = false,
	showArmor = true,
	-- showTier = true,
}

local index =
{
	[1] = "classColor",
	[2] = "groupAge",
	[3] = "showIgnore",
	[4] = "alwaysShowRaidComp",
	[5] = "showArmor",
	-- [6] = "showTier",
}

if TwicksLFGInspect_SavedVariables == nil then
	TwicksLFGInspect_SavedVariables = default
else
	for key, value in pairs(default) do
		if TwicksLFGInspect_SavedVariables[key] == nil then
			TwicksLFGInspect_SavedVariables[key] = value
		end
	end
end

TwicksLFGInspect = {}
TwicksLFGInspect.panel = CreateFrame("Frame", "TwicksLFGInspect_Panel", UIParent)
TwicksLFGInspect.panel.name = "LFG Inspect"
local category = Settings.RegisterCanvasLayoutCategory(TwicksLFGInspect.panel, "LFG Inspect")
Settings.RegisterAddOnCategory(category)
TwicksLFGInspect.panel.categoryID = category:GetID() 

local buttonList = {}

local title = TwicksLFGInspect.panel:CreateFontString("ARTWORK", nil, "GameFontNormalLarge")
title:SetPoint("TOPLEFT")
title:SetText("Dungeons")
local title2 = TwicksLFGInspect.panel:CreateFontString("ARTWORK", nil, "GameFontNormalLarge")
title2:SetPoint("TOPLEFT", 0, -128)
title2:SetText("Raids")
local author = TwicksLFGInspect.panel:CreateFontString("ARTWORK", nil, "GameFontNormalLarge")
author:SetPoint("BOTTOMRIGHT")
author:SetText("Made by Twicks")


function createCheckButton(i, x, y)
	local list = 
	{
		" Display player names using class colors",
		" Show time since group was created",
		" Alert when a listed player is on your ignore list",
		" Show raid comp without holding Shift",
		" Display count of each armor type",
		-- " Display count of each tier token",
	}
	
	local checkButton = CreateFrame("CheckButton", "TwicksLFGInspect_CheckButton" .. i, TwicksLFGInspect.panel, "UICheckButtonTemplate")
	buttonList[i] = checkButton
	checkButton:ClearAllPoints()
	checkButton:SetPoint("TOPLEFT", x * 32, y * -32)
	checkButton:SetSize(32, 32)
	_G[checkButton:GetName() .. "Text"]:SetText(list[i])
	_G[checkButton:GetName() .. "Text"]:SetFont(GameFontNormal:GetFont(), 14, "") -- changed from "NONE"
	buttonList[i]:SetScript("OnClick", function()
		if buttonList[i]:GetChecked() then
			TwicksLFGInspect_SavedVariables[index[i]] = true
		else
			TwicksLFGInspect_SavedVariables[index[i]] = false
		end
		setupButtons()
	end)
end

createCheckButton(1, 1, 1)
createCheckButton(2, 1, 2)
createCheckButton(3, 1, 3)
createCheckButton(4, 1, 5)
createCheckButton(5, 1, 6)
-- createCheckButton(6, 1, 7) -- tier token count

local function setupButtons(i)
	for i = 1, 5 do -- 1, #index
		if TwicksLFGInspect_SavedVariables[index[i]] then
			buttonList[i]:SetChecked(true)
		else
			buttonList[i]:SetChecked(false)
		end
	end
end

local tempSettings = CopyTable(TwicksLFGInspect_SavedVariables)

local function settingsChanged()
	for _, key in ipairs(index) do
		if TwicksLFGInspect_SavedVariables[key] ~= tempSettings[key] then
			return true
		end
	end
	return false
end

local function updateSaveButtonState()
	if settingsChanged() then
		TwicksLFGInspect.saveButton:Enable()
	else
		TwicksLFGInspect.saveButton:Disable()
	end
end

local function updateAllChangedIndicators()
	local hasChanges = false
	for i = 1, #index do
		local key = index[i]
		local modified = tempSettings[key] ~= TwicksLFGInspect_SavedVariables[key]

		if modified then
			buttonList[i].modifiedLabel:SetText("|cffff4444Requires reload|r")
			hasChanges = true
		else
			buttonList[i].modifiedLabel:SetText("")
		end
	end

	if hasChanges then
		TwicksLFGInspect.saveButton:Enable()
	else
		TwicksLFGInspect.saveButton:Disable()
	end
end

for i = 1, #index do
	local key = index[i]
	local checkbox = buttonList[i]

	if not checkbox.modifiedLabel then
		local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("LEFT", checkbox.Text, "RIGHT", 8, 0)
		label:SetTextColor(1, 0.7, 0.1) -- orange-ish
		checkbox.modifiedLabel = label
	end

	checkbox:SetScript("OnClick", function(self)
		tempSettings[key] = self:GetChecked() or false
		updateAllChangedIndicators()
	end)
end


TwicksLFGInspect.saveButton = CreateFrame("Button", nil, TwicksLFGInspect.panel, "UIPanelButtonTemplate")
TwicksLFGInspect.saveButton:SetSize(160, 24)
TwicksLFGInspect.saveButton:SetPoint("LEFT", 16, 16)
TwicksLFGInspect.saveButton:SetText("Save & Reload UI")
TwicksLFGInspect.saveButton:Disable()

TwicksLFGInspect.saveButton:SetScript("OnClick", function()
	for _, key in ipairs(index) do
		TwicksLFGInspect_SavedVariables[key] = tempSettings[key]
	end
	ReloadUI()
end)

TwicksLFGInspect.panel:SetScript("OnShow", function()
	for i = 1, #index do
		buttonList[i]:SetChecked(tempSettings[index[i]])
	end
	updateSaveButtonState()
end)

TwicksLFGInspect.panel:SetScript("OnHide", function()
	if settingsChanged() then
		tempSettings = CopyTable(TwicksLFGInspect_SavedVariables)
		print("|cffff4444LFG Inspect|r: Changes reverted")

		for i = 1, #index do
			buttonList[i]:SetChecked(tempSettings[index[i]])
		end
	end

	updateAllChangedIndicators()
end)

SLASH_TWICKSLFGINSPECT1 = '/lfgi'
function SlashCmdList.TWICKSLFGINSPECT(msg, editbox)
	if msg == "" then
		Settings.OpenToCategory(TwicksLFGInspect.panel.categoryID)
	end
end

if LFGListFrame.ApplicationViewer.UnempoweredCover then
	LFGListFrame.ApplicationViewer.UnempoweredCover:EnableMouse(false)
end

local classColor, groupAge, showIgnore = TwicksLFGInspect_SavedVariables[index[1]], TwicksLFGInspect_SavedVariables[index[2]], TwicksLFGInspect_SavedVariables[index[3]]
-- local alwaysShowRaidComp, showArmor, showTier = TwicksLFGInspect_SavedVariables[index[4]], TwicksLFGInspect_SavedVariables[index[5]], TwicksLFGInspect_SavedVariables[index[6]]
local alwaysShowRaidComp, showArmor = TwicksLFGInspect_SavedVariables[index[4]], TwicksLFGInspect_SavedVariables[index[5]]

local classToArmor, classToTier = {}, {}

local function buildClassLookup(map, target)
    for key, classes in pairs(map) do
        for _, class in ipairs(classes) do
            target[class] = key
        end
    end
end

if showArmor then
    buildClassLookup({
            CLOTH = { "MAGE", "PRIEST", "WARLOCK" },
            LEATHER = { "DRUID", "ROGUE", "MONK", "DEMONHUNTER" },
            MAIL = { "HUNTER", "SHAMAN", "EVOKER" },
            PLATE = { "WARRIOR", "PALADIN", "DEATHKNIGHT" },
    }, classToArmor)
end

-- if showTier then
    -- buildClassLookup({
            -- DREADFUL = { "DEATHKNIGHT", "WARLOCK", "DEMONHUNTER" },
            -- MYSTIC = { "HUNTER", "MAGE", "DRUID" },
            -- VENERATED = { "PALADIN", "PRIEST", "SHAMAN" },
            -- ZENITH = { "WARRIOR", "ROGUE", "MONK", "EVOKER" },
    -- }, classToTier)
-- end

local function colorize(class, text, useColor)
    if not useColor then return "|cffffffff" .. (text or class) .. "|r" end
    local c = RAID_CLASS_COLORS[class]
    return c and ("|cff%02x%02x%02x%s|r"):format(c.r*255, c.g*255, c.b*255, text or class) or (text or class)
end

local function addCountsLine(tooltip, data, highlight)
    local out = {}
    for k, v in pairs(data) do
        if v >= 0 then
            local color = (k == highlight) and "|cff00ff00" or "|cffff5555"
            table.insert(out, color .. k .. ":" .. v .. "|r" .. " ")
        end
    end
    tooltip:AddLine(table.concat(out, " "))
end

local function AppendTooltipContent(tooltip, resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    local activity = info and C_LFGList.GetActivityInfoTable(info.activityIDs[1])
    if not activity then return end
    
    local shortName, isRaid = activity.shortName, activity.isCurrentRaidActivity
    
    if groupAge and info.age then
        local min, sec = math.floor(info.age / 60), info.age % 60
        tooltip:AddLine(" ")
        tooltip:AddLine("Group Created: " .. (min > 0 and ("%dmin %02ds ago"):format(min, sec) or ("%ds ago"):format(sec)), 1, 1, 1)
    end
    
    local isDungeon = not isRaid and (shortName == "Mythic+" or shortName == "Mythic" or shortName == "Heroic" or shortName == "Normal")
    if isDungeon then
        local members = {}
        for i = 1, info.numMembers do
            local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
            if p and p.name and p.className and p.specName then
                table.insert(members, { name = p.name, class = p.className, spec = p.specName, file = p.classFilename })
            end
        end
        
        local ignored = {}
        if showIgnore then
            for i = 1, C_FriendList.GetNumIgnores() do
                local full = C_FriendList.GetIgnoreName(i)
                if full then
                    local name = full:match("^[^%-]+")
                    if name then ignored[name:lower()] = true end
                end
            end
        end
        
        local memberMap = {}
        for _, m in ipairs(members) do
            local key = m.class .. " - " .. m.spec
            memberMap[key] = memberMap[key] or {}
            table.insert(memberMap[key], m)
        end
        
        for i = 1, tooltip:NumLines() do
            local line = _G["GameTooltipTextLeft" .. i]
            local text = line and line:GetText()
            if not text then break end
			if issecretvalue(text) then break end
            
            for key, list in pairs(memberMap) do
                if #list > 0 and text:find(key, 1, true) then
                    local m = table.remove(list, 1)
                    local nameText = colorize(m.file, m.name, classColor)
                    if showIgnore and ignored[m.name:lower()] then
                        local icon = CreateAtlasMarkup("Ping_Chat_Warning", 16, 16)
                        nameText = nameText .. ") " .. icon .. " |cffff4444IGNORED|r " .. icon
                    else
                        nameText = nameText .. ")"
                    end
                    line:SetText(("%s (%s"):format(text, nameText))
                    break
                end
            end
        end
    end
    
    if isRaid and (shortName == "Mythic" or shortName == "Heroic" or shortName == "Normal") then
        local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
        if not (counts and counts.classesByRole) then return end
        
        local playerClass = select(2, UnitClass("player"))
        local playerArmor = showArmor and (classToArmor[playerClass] or "UNKNOWN") or nil
        local playerTier = showTier and (classToTier[playerClass] or "UNKNOWN") or nil
        
        local function showComp()
            for _, role in ipairs({ "DAMAGER", "HEALER", "TANK" }) do
                local roleClasses = counts.classesByRole[role]
                if roleClasses then
                    local list = {}
                    for className, n in pairs(roleClasses) do
                        if n > 0 then
                            local label = colorize(className, nil, true)
                            table.insert(list, { text = (n > 1 and label .. " x" .. n or label), count = n })
                        end
                    end
                    table.sort(list, function(a, b) return a.count > b.count end)
                    if #list > 0 then
                        tooltip:AddLine(role .. "S:")
                        for _, entry in ipairs(list) do
                            tooltip:AddLine("  " .. entry.text)
                        end
                        tooltip:AddLine(" ")
                    end
                end
            end
        end
        
        if alwaysShowRaidComp or IsShiftKeyDown() then
            showComp()
        else
            tooltip:AddLine(" ")
            tooltip:AddLine("<Hold Shift for more information>", 0.6, 0.6, 0.6)
            tooltip:AddLine(" ")
        end
        
        if showArmor or showTier then
            local armorCounts, tierCounts = {}, {}
            for _, a in ipairs({ "CLOTH", "LEATHER", "MAIL", "PLATE" }) do armorCounts[a] = 0 end
            for _, t in ipairs({ "DREADFUL", "MYSTIC", "VENERATED", "ZENITH" }) do tierCounts[t] = 0 end
            
            for className, n in pairs(counts) do
                if type(n) == "number" and not className:find("REMAINING") then
                    if showArmor and classToArmor[className] then
                        armorCounts[classToArmor[className]] = armorCounts[classToArmor[className]] + n
                    end
                    if showTier and classToTier[className] then
                        tierCounts[classToTier[className]] = tierCounts[classToTier[className]] + n
                    end
                end
            end
            
            if showArmor then addCountsLine(tooltip, armorCounts, playerArmor) end
            if showTier then addCountsLine(tooltip, tierCounts, playerTier) end
        end
    end
    
    tooltip:Show()
end

local frame, currentTooltip, currentResultID = CreateFrame("Frame"), nil, nil
frame:RegisterEvent("MODIFIER_STATE_CHANGED")
frame:SetScript("OnEvent", function(_, _, key, state)
        if key == "LSHIFT" or key == "RSHIFT" then
            if currentTooltip and currentResultID and currentTooltip:IsVisible() then
                local owner = currentTooltip:GetOwner()
                if owner and owner.resultID == currentResultID then
                    currentTooltip:ClearLines()
                    LFGListUtil_SetSearchEntryTooltip(currentTooltip, currentResultID)
                else
                    currentTooltip, currentResultID = nil, nil
                end
            end
        end
end)

hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID)
        if not resultID or not tooltip:IsVisible() then
            currentTooltip, currentResultID = nil, nil
            return
        end
        currentTooltip, currentResultID = tooltip, resultID
        AppendTooltipContent(tooltip, resultID)
end)

GameTooltip:HookScript("OnHide", function(self)
        if currentTooltip == self then
            currentTooltip, currentResultID = nil, nil
        end
end)


local func1 = CreateFrame("Frame")
func1:RegisterEvent("ADDON_LOADED")
func1:SetScript("OnEvent", setupButtons)

----------

end
end)