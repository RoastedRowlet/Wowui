-- Addon:	     GroupfinderFlags
-- Author:	     Spielstein@Curse
-- Contributor:  Turtle919@Curse (Data and flag pictures of the american/oceanic region)


----------------------------------------------------------------------------
----------------------------------------------------------------------------
--------  Variables, databases and constants  ------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------

-- Creating MainFrame
GroupfinderFlags = {}
GroupfinderFlags.mainFrame = CreateFrame("Frame", "GroupfinderFlagsFrame", UIParent)
GroupfinderFlags.FIRST_SLASH_START = 0

-- own realm
GroupfinderFlags.OWN_REALM = GetRealmName()

-- locale code
GroupfinderFlags.LOCALE_CODE = "enUS"
local locale = GetLocale()

-- german localization
if locale == "deDE" then
	GroupfinderFlags.LOCALE_CODE = "deDE"
-- french localization
elseif locale == "frFR" then
	GroupfinderFlags.LOCALE_CODE = "frFR"
-- italian localization
elseif locale == "itIT" then
	GroupfinderFlags.LOCALE_CODE = "itIT"
-- russian localization
elseif locale == "ruRU" then
	GroupfinderFlags.LOCALE_CODE = "ruRU"
-- spanish localization
elseif locale == "esES" then
	GroupfinderFlags.LOCALE_CODE = "esES"
-- (mexican) spanish localization
elseif locale == "esMX" then
	GroupfinderFlags.LOCALE_CODE = "esMX"
-- portuguese localization
elseif locale == "ptBR" then
	GroupfinderFlags.LOCALE_CODE = "ptBR"
end


-- flage files
GroupfinderFlags.TEXT_IMAGE_PATH = "|TInterface\\AddOns\\GroupfinderFlags\\flag_icons\\"
GroupfinderFlags.TEXTURE_IMAGE_PATH = "Interface\\AddOns\\GroupfinderFlags\\flag_textures\\"
GroupfinderFlags.SIZE = ":9:15|t"
GroupfinderFlags.FLAGS = {
	-- europe
	["german"] = "german"..GroupfinderFlags.SIZE,
	["british"] = "british"..GroupfinderFlags.SIZE,
	["portuguese"] = "portuguese"..GroupfinderFlags.SIZE,
	["russian"] = "russian"..GroupfinderFlags.SIZE,
	["french"] = "french"..GroupfinderFlags.SIZE,
	["spanish"] = "spanish"..GroupfinderFlags.SIZE,
	["italian"] = "italian"..GroupfinderFlags.SIZE,
	-- american/oceanic
	["american"] = "american"..GroupfinderFlags.SIZE,
	["brazilian"] = "brazilian"..GroupfinderFlags.SIZE,
	["oceanic"] = "oceanic"..GroupfinderFlags.SIZE,
	["mexican"] = "mexican"..GroupfinderFlags.SIZE,
}

GroupfinderFlags.TEXTURES = {
	-- europe
	["german"] = "german.tga",
	["british"] = "british.tga",
	["portuguese"] = "portuguese.tga",
	["russian"] = "russian.tga",
	["french"] = "french.tga",
	["spanish"] = "spanish.tga",
	["italian"] = "italian.tga",
	-- american/oceanic
	["american"] = "american.tga",
	["brazilian"] = "brazilian.tga",
	["oceanic"] = "oceanic.tga",
	["mexican"] = "mexican.tga",
}

-- continent maps
GroupfinderFlags.MAPS = {
	["america"] = "Interface\\Addons\\GroupfinderFlags\\misc_images\\map_america_oceania.tga",
	["europe"] = "Interface\\Addons\\GroupfinderFlags\\misc_images\\map_europe.tga",
	["america_sw"] = "Interface\\Addons\\GroupfinderFlags\\misc_images\\map_america_oceania_sw.tga",
	["europe_sw"] = "Interface\\Addons\\GroupfinderFlags\\misc_images\\map_europe_sw.tga",
}
GroupfinderFlags.BUTTON_OVERLAY = "Interface\\Addons\\GroupfinderFlags\\misc_images\\button_overlay.tga"

local function GFF_ManipulateTextureColors(btn)
	if btn.Top         then btn.Top:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.TopLeft     then btn.TopLeft:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.TopRight    then btn.TopRight:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.Bottom      then btn.Bottom:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.BottomLeft  then btn.BottomLeft:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.BottomRight then btn.BottomRight:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.Left        then btn.Left:SetVertexColor(0.6157, 0.4627, 0.0902) end
	if btn.Right       then btn.Right:SetVertexColor(0.6157, 0.4627, 0.0902) end
end

local function NormalizeRealmname(realmname)
	if realmname then
		return realmname:gsub("[%s%-]", "")
	else
		return nil
	end
end

local function Local_InterfaceOptions_AddCategory(panel)
    local categoryId = nil
	if InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	elseif Settings and Settings.RegisterAddOnCategory and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		categoryId = category.ID
		Settings.RegisterAddOnCategory(category);
	end
	return categoryId
end


----------------------------------------------------------------------------
----------------------------------------------------------------------------
--------  Options panel  ---------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------

-- option panel

local opanel = CreateFrame("Frame", "GroupfinderFlagsOptionsPanel", UIParent)

-- main titles
opanel.title = opanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
opanel.title:SetPoint("TOPLEFT", 16, -16)
opanel.title:SetText("GroupfinderFlags")
opanel.title:SetJustifyH("LEFT")

opanel.title2 = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.title2:SetPoint("TOPLEFT", 16, -35)
opanel.title2:SetText("Author: Spielstein@Curse\nVersion: " .. C_AddOns.GetAddOnMetadata("GroupfinderFlags", "Version"))
opanel.title2:SetJustifyH("LEFT")


-- region selection title
opanel.regionTitle = opanel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
opanel.regionTitle:SetPoint("TOPLEFT",  opanel.title2, "BOTTOMLEFT", 0, -20)
opanel.regionTitle:SetText("Region selection")
opanel.regionTitle:SetJustifyH("LEFT")

-- region selection
opanel.us_button = CreateFrame("Button", "GFF_US_Button", opanel, "ThinBorderTemplate")
opanel.us_button:SetPoint("TOPLEFT", opanel.regionTitle, "BOTTOMLEFT", 16, -10)
opanel.us_button:SetSize(64, 64)
opanel.us_button:SetNormalTexture(GroupfinderFlags.MAPS.america_sw)
opanel.us_button:SetPushedTexture(GroupfinderFlags.MAPS.america)
opanel.us_button:SetDisabledTexture(GroupfinderFlags.MAPS.america)
opanel.us_button:SetHighlightTexture(GroupfinderFlags.BUTTON_OVERLAY)
opanel.us_button:SetScript("OnClick", function (self)
	GroupfinderFlagsDB.region = "america"
	self:Disable()
	self:GetParent().eu_button:Enable()
end)
GFF_ManipulateTextureColors(opanel.us_button)
opanel.us_button:Disable()

opanel.us_text = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.us_text:SetText("America\nOceania")
opanel.us_text:SetPoint("TOP", opanel.us_button, "BOTTOM", 0, 0)

opanel.eu_button = CreateFrame("Button", "GFF_EU_Button", opanel, "ThinBorderTemplate")
opanel.eu_button:SetPoint("LEFT", opanel.us_button, "RIGHT", 32, 0)
opanel.eu_button:SetSize(64, 64)
opanel.eu_button:SetNormalTexture(GroupfinderFlags.MAPS.europe_sw)
opanel.eu_button:SetPushedTexture(GroupfinderFlags.MAPS.europe)
opanel.eu_button:SetDisabledTexture(GroupfinderFlags.MAPS.europe)
opanel.eu_button:SetHighlightTexture(GroupfinderFlags.BUTTON_OVERLAY)
opanel.eu_button:SetScript("OnClick", function (self)
	GroupfinderFlagsDB.region = "europe"
	self:Disable()
	self:GetParent().us_button:Enable()
end)
GFF_ManipulateTextureColors(opanel.eu_button)
opanel.eu_button:Disable()

opanel.eu_text = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.eu_text:SetText("Europe")
opanel.eu_text:SetPoint("TOP", opanel.eu_button, "BOTTOM", 0, -(opanel.eu_text:GetStringHeight()/2))


-- option title
opanel.optionTitle = opanel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
opanel.optionTitle:SetPoint("TOPLEFT",  opanel.regionTitle, "BOTTOMLEFT", 0, -110)
opanel.optionTitle:SetText("Options")
opanel.optionTitle:SetJustifyH("LEFT")

-- option for disabling flags in the groupfinder
opanel.boxForGrpFinder = CreateFrame("CheckButton", "GFF_ShowGrpFinderFlagCheckbox", opanel, "OptionsBaseCheckButtonTemplate")
opanel.boxForGrpFinder:SetPoint("TOPLEFT", opanel.optionTitle, "BOTTOMLEFT", 0, -5)
opanel.boxForGrpFinder:SetScript("OnClick", function()
	GroupfinderFlagsDB.showFlagInGrpFinder = not GroupfinderFlagsDB.showFlagInGrpFinder
	opanel.boxForGrpFinder:SetChecked(GroupfinderFlagsDB.showFlagInGrpFinder)
end)
opanel.boxtextForGrpFinder = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.boxtextForGrpFinder:SetPoint("LEFT", opanel.boxForGrpFinder, "RIGHT", 10, 1)
opanel.boxtextForGrpFinder:SetJustifyH("LEFT")
opanel.boxtextForGrpFinder:SetText("Show the country's flag for applicants in the Groupfinder UI")

-- option for disabling flags in the groupfinder
opanel.boxForLeaderGrpFinder = CreateFrame("CheckButton", "GFF_ShowGrpFinderFlagCheckbox", opanel, "OptionsBaseCheckButtonTemplate")
opanel.boxForLeaderGrpFinder:SetPoint("TOPLEFT", opanel.boxForGrpFinder, "BOTTOMLEFT", 0, -1)
opanel.boxForLeaderGrpFinder:SetScript("OnClick", function()
	GroupfinderFlagsDB.showLeaderFlagInGrpFinder = not GroupfinderFlagsDB.showLeaderFlagInGrpFinder
	opanel.boxForLeaderGrpFinder:SetChecked(GroupfinderFlagsDB.showLeaderFlagInGrpFinder)
end)
opanel.boxtextForLeaderGrpFinder = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.boxtextForLeaderGrpFinder:SetPoint("LEFT", opanel.boxForLeaderGrpFinder, "RIGHT", 10, 1)
opanel.boxtextForLeaderGrpFinder:SetJustifyH("LEFT")
opanel.boxtextForLeaderGrpFinder:SetText("Show the country's flag of the group leader in the Groupfinder UI")

-- option for disabling flags in tooltip
opanel.boxForTooltipFlag = CreateFrame("CheckButton", "GFF_ShowTooltipFlagCheckbox", opanel, "OptionsBaseCheckButtonTemplate")
opanel.boxForTooltipFlag:SetPoint("TOPLEFT", opanel.boxForLeaderGrpFinder, "BOTTOMLEFT", 0, -1)
opanel.boxForTooltipFlag:SetScript("OnClick", function()
	GroupfinderFlagsDB.showFlagInTooltip = not GroupfinderFlagsDB.showFlagInTooltip
	opanel.boxForTooltipFlag:SetChecked(GroupfinderFlagsDB.showFlagInTooltip)
end)
opanel.boxtextForTooltipFlag = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.boxtextForTooltipFlag:SetPoint("LEFT", opanel.boxForTooltipFlag, "RIGHT", 10, 1)
opanel.boxtextForTooltipFlag:SetJustifyH("LEFT")
opanel.boxtextForTooltipFlag:SetText("Show the country's flag in the tooltips")

-- option for disabling country name next to flag
opanel.boxForTooltipCountryNames = CreateFrame("CheckButton", "GFF_ShowTooltipCountryNameCheckbox", opanel, "OptionsBaseCheckButtonTemplate")
opanel.boxForTooltipCountryNames:SetPoint("TOPLEFT", opanel.boxForTooltipFlag, "BOTTOMLEFT", 0, -1)
opanel.boxForTooltipCountryNames:SetScript("OnClick", function()
	GroupfinderFlagsDB.showCountrynameInTooltip = not GroupfinderFlagsDB.showCountrynameInTooltip
	opanel.boxForTooltipCountryNames:SetChecked(GroupfinderFlagsDB.showCountrynameInTooltip)
end)
opanel.boxtextForTooltipCountryNames = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.boxtextForTooltipCountryNames:SetPoint("LEFT", opanel.boxForTooltipCountryNames, "RIGHT", 10, 1)
opanel.boxtextForTooltipCountryNames:SetJustifyH("LEFT")
opanel.boxtextForTooltipCountryNames:SetText("Show the country's name next to the flag in tooltips")

-----------------------

-- option for disabling country name next to flag
opanel.boxForTimezonesOnUSandOceania = CreateFrame("CheckButton", "GFF_ShowTooltipTimezoneCheckbox", opanel, "OptionsBaseCheckButtonTemplate")
opanel.boxForTimezonesOnUSandOceania:SetPoint("TOPLEFT", opanel.boxForTooltipCountryNames, "BOTTOMLEFT", 0, -1)
opanel.boxForTimezonesOnUSandOceania:SetScript("OnClick", function()
	GroupfinderFlagsDB.showTimezoneOnUSandOceania = not GroupfinderFlagsDB.showTimezoneOnUSandOceania
	opanel.boxForTimezonesOnUSandOceania:SetChecked(GroupfinderFlagsDB.showTimezoneOnUSandOceania)
end)
opanel.boxtextForTimezonesOnUSandOceania = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.boxtextForTimezonesOnUSandOceania:SetPoint("LEFT", opanel.boxForTimezonesOnUSandOceania, "RIGHT", 10, 1)
opanel.boxtextForTimezonesOnUSandOceania:SetJustifyH("LEFT")
opanel.boxtextForTimezonesOnUSandOceania:SetText("Show the country's timezone next to the flag in tooltips (US & Oceania only)")

----------------

-- option for showing the information only if realm languages are different
opanel.boxForOnlyShowingIfLanguagesDiff = CreateFrame("CheckButton", "GFF_ShowFlagOnlyIfLangDiffCheckbox", opanel, "OptionsBaseCheckButtonTemplate")
opanel.boxForOnlyShowingIfLanguagesDiff:SetPoint("TOPLEFT", opanel.boxForTimezonesOnUSandOceania, "BOTTOMLEFT", 0, -1)
opanel.boxForOnlyShowingIfLanguagesDiff:SetScript("OnClick", function()
	GroupfinderFlagsDB.showFlagOnlyIfOtherCountry = not GroupfinderFlagsDB.showFlagOnlyIfOtherCountry
	opanel.boxForOnlyShowingIfLanguagesDiff:SetChecked(GroupfinderFlagsDB.showFlagOnlyIfOtherCountry)
end)
opanel.boxtextForOnlyShowingIfLanguagesDiff = opanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
opanel.boxtextForOnlyShowingIfLanguagesDiff:SetPoint("LEFT", opanel.boxForOnlyShowingIfLanguagesDiff, "RIGHT", 10, 1)
opanel.boxtextForOnlyShowingIfLanguagesDiff:SetJustifyH("LEFT")
opanel.boxtextForOnlyShowingIfLanguagesDiff:SetText("Only show the flag/county name if my and their language is different.")


GroupfinderFlags.opanel = opanel
GroupfinderFlags.opanel.name = "GroupfinderFlags";
GroupfinderFlags.categoryID = Local_InterfaceOptions_AddCategory(GroupfinderFlags.opanel)
--InterfaceOptions_AddCategory(GroupfinderFlags.opanel);


----------------------------------------------------------------------------
----------------------------------------------------------------------------
--------  Hooking functions  -----------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------

-- hooking the gametooltip
local function HookfunctionForGametooltip(...)

	if not (GroupfinderFlagsDB.showFlagInTooltip or GroupfinderFlagsDB.showCountrynameInTooltip) then
		return
	end

	-- variables
	local _
	local unit, realm, languageList, unitPlayerLocation

	-- get unit infos from the game tooltip
	_, unit = GameTooltip:GetUnit()

	if not issecretvalue(unit) then
		-- only proceed if unit is not nil
		if unit ~= nil then

			-- gets name and realm of the player
			_, realm = UnitName(unit)

			-- if realm is nil check if player is from user's own realm
			unitPlayerLocation = PlayerLocation:CreateFromUnit(unit)
			if (realm == nil or realm == "") and C_PlayerInfo.UnitIsSameServer(unitPlayerLocation) then
				realm = GroupfinderFlags.OWN_REALM
			end

			realm = NormalizeRealmname(realm)

			-- check whether region is selected
			if GroupfinderFlagsDB.region ~= nil and (GroupfinderFlagsDB.region == "europe" or GroupfinderFlagsDB.region == "america") then

				-- get region specific realm language list
				if GroupfinderFlagsDB.region == "europe" then
					languageList = GroupfinderFlags.EU_REALM_LANGUAGES
				elseif GroupfinderFlagsDB.region == "america" then
					languageList = GroupfinderFlags.US_REALM_LANGUAGES
				end


				-- only proceed if player's realm is in database
				if languageList[realm] ~= nil then

					-- if option "showFlagOnlyIfOtherCountry" is active, only proceed with different languages
					if not GroupfinderFlagsDB.showFlagOnlyIfOtherCountry or languageList[realm] ~= languageList[GroupfinderFlags.OWN_REALM] then

						-- adding the flag by :AddLine()
						local flag = GroupfinderFlags.TEXT_IMAGE_PATH..GroupfinderFlags.FLAGS[languageList[realm]]
						local country_name = "|cFFFFFFFF" .. GroupfinderFlags.COUNTRYNAMES[GroupfinderFlags.LOCALE_CODE][languageList[realm]] .. "|r"
						local timezone = (GroupfinderFlagsDB.showTimezoneOnUSandOceania and GroupfinderFlagsDB.region == "america" and GroupfinderFlags.US_REALM_TIMEZONES[realm]) and "|cFFFFFFFF (" .. GroupfinderFlags.US_REALM_TIMEZONES[realm] .. ")|r" or ""
						local both_activated = GroupfinderFlagsDB.showFlagInTooltip and GroupfinderFlagsDB.showCountrynameInTooltip
						GameTooltip:AddLine((GroupfinderFlagsDB.showFlagInTooltip and flag or "") .. (both_activated and "|cFFFFFFFF - |r" or "") .. (GroupfinderFlagsDB.showCountrynameInTooltip and country_name or "") .. timezone)
						--  and readjusting the height and the width of the tooltip by :Show()
						GameTooltip:Show()
					end
				end
			end
		end
	end
end


--
local function HookfunctionForGroupFinderSearchTooltip(tooltip, resultID)

	if not (GroupfinderFlagsDB.showFlagInTooltip or GroupfinderFlagsDB.showCountrynameInTooltip) then
		return
	end

	-- check whether region is selected
	if GroupfinderFlagsDB.region == nil or (GroupfinderFlagsDB.region ~= "europe" and GroupfinderFlagsDB.region ~= "america") then
		return
	end

	local _
	local leaderName, shortname, fullname, realm, languageList

	leaderName = C_LFGList.GetSearchResultInfo(resultID)["leaderName"];

	if leaderName == nil then
		return
	end

	-- extract name+realm and (only) name
	shortname = Ambiguate(leaderName, "short")
	fullname = Ambiguate(leaderName, "mail")

	-- if:     shortname and fullname are equal -> applicant is from user's own realm
	-- else:   extract realm from fullname
	if shortname == fullname then
		realm = GroupfinderFlags.OWN_REALM
	else
		realm = string.sub(fullname, string.len(shortname)+2)
	end

	realm = NormalizeRealmname(realm)

	-- get region specific realm language list
	if GroupfinderFlagsDB.region == "europe" then
		languageList = GroupfinderFlags.EU_REALM_LANGUAGES
	elseif GroupfinderFlagsDB.region == "america" then
		languageList = GroupfinderFlags.US_REALM_LANGUAGES
	end

	-- only proceed if player's realm is in database
	if languageList[realm] ~= nil then

		-- if option "showFlagOnlyIfOtherCountry" is active, only proceed with different languages
		if not GroupfinderFlagsDB.showFlagOnlyIfOtherCountry or languageList[realm] ~= languageList[GroupfinderFlags.OWN_REALM] then

			-- adding the flag by :AddLine()
			local flag = GroupfinderFlags.TEXT_IMAGE_PATH..GroupfinderFlags.FLAGS[languageList[realm]]
			local country_name = "|cFFFFFFFF" .. GroupfinderFlags.COUNTRYNAMES[GroupfinderFlags.LOCALE_CODE][languageList[realm]] .. "|r"
			local timezone = (GroupfinderFlagsDB.showTimezoneOnUSandOceania and GroupfinderFlagsDB.region == "america" and GroupfinderFlags.US_REALM_TIMEZONES[realm]) and "|cFFFFFFFF (" .. GroupfinderFlags.US_REALM_TIMEZONES[realm] .. ")|r" or ""
			local both_activated = GroupfinderFlagsDB.showFlagInTooltip and GroupfinderFlagsDB.showCountrynameInTooltip
			tooltip:AddLine(" ")
			tooltip:AddLine((GroupfinderFlagsDB.showFlagInTooltip and flag or "") .. (both_activated and "|cFFFFFFFF - |r" or "") .. (GroupfinderFlagsDB.showCountrynameInTooltip and country_name or "") .. timezone)
			--  and readjusting the height and the width of the tooltip by :Show()
			tooltip:Show()
		end
	end

end


-- hooking function for the applicantviewer
local function HookfunctionForGroupFinderApplicants(member, appID, memberIdx)

	-- reset flag
	if member.GFF_text_flag then
		member.GFF_text_flag:SetText("")
	end

	if not GroupfinderFlagsDB.showFlagInGrpFinder then
		return
	end

	-- check whether region is selected
	if GroupfinderFlagsDB.region == nil or (GroupfinderFlagsDB.region ~= "europe" and GroupfinderFlagsDB.region ~= "america") then
		return
	end

	-- variables
	local realm, shortname, fullname, languageList

	-- getting applicant's name
	local name, _, _, _, _, _, _, _, _, _, relationship, _, _, _, _, _, isLeaver = C_LFGList.GetApplicantMemberInfo(appID, memberIdx);

	-- extract name+realm and (only) name
	shortname = Ambiguate(name, "short")
	fullname = Ambiguate(name, "mail")

	-- if:     shortname and fullname are equal -> applicant is from user's own realm
	-- else:   extract realm from fullname
	if shortname == fullname then
		realm = GroupfinderFlags.OWN_REALM
	else
		realm = string.sub(fullname, string.len(shortname)+2)
	end

	realm = NormalizeRealmname(realm)

	-- get region specific realm language list
	if GroupfinderFlagsDB.region == "europe" then
		languageList = GroupfinderFlags.EU_REALM_LANGUAGES
	elseif GroupfinderFlagsDB.region == "america" then
		languageList = GroupfinderFlags.US_REALM_LANGUAGES
	end

	-- if option "showFlagOnlyIfOtherCountry" is active, only proceed with different languages
	if GroupfinderFlagsDB.showFlagOnlyIfOtherCountry and languageList[realm] == languageList[GroupfinderFlags.OWN_REALM] then
		return
	end

	-- add a font string for displaying the flag if needed
	if not member.GFF_text_flag then
		member.GFF_text_flag = member:CreateFontString("$parentFlag", "ARTWORK", "GameFontNormalSmall")
		member.GFF_text_flag:SetPoint("LEFT", member.Name, "RIGHT", -10, 0)
	end
	-- set the appropiate flag
	member.GFF_text_flag:SetText(languageList[realm] ~= nil and GroupfinderFlags.TEXT_IMAGE_PATH..GroupfinderFlags.FLAGS[languageList[realm]] or "")

	-- recalculate the name column's width (taken from blizz code and modified)
	-- local nameLength = 100 - 15
	-- if relationship then
	-- 	member.FriendIcon:SetPoint("LEFT", member.GFF_text_flag, "RIGHT", -3, 0)
	-- 	nameLength = nameLength - 22
	-- end
  	-- if ( member.Name:GetWidth() > nameLength ) then
    -- 	member.Name:SetWidth(nameLength)
  	-- end
	-- member.Name:SetWidth(member.Name:GetWidth() - 30)

end


-- hook for the search result view (group leader flag)
local function HookfunctionForGroupFinderSearchLeaderFlag(self)

	-- reset flag
	if self.GFF_text_flag then
		self.GFF_text_flag:SetText("")
	end
	if self.GFF_background_flag then
		self.GFF_background_flag:Hide()
	end

	if not GroupfinderFlagsDB.showLeaderFlagInGrpFinder then
		return
	end

	-- check whether region is selected
	if GroupfinderFlagsDB.region == nil or (GroupfinderFlagsDB.region ~= "europe" and GroupfinderFlagsDB.region ~= "america") then
		return
	end
	
	local resultID = self.resultID

	if not C_LFGList.HasSearchResultInfo(resultID) then
		return
	end

	local searchResultInfo = C_LFGList.GetSearchResultInfo(self.resultID)

	if not searchResultInfo.leaderName then
		return
	end

	-- variables
	local realm, shortname, fullname, languageList

	-- extract name+realm and (only) name
	shortname = Ambiguate(searchResultInfo.leaderName, "short")
	fullname = Ambiguate(searchResultInfo.leaderName, "mail")

	-- if:     shortname and fullname are equal -> applicant is from user's own realm
	-- else:   extract realm from fullname
	if shortname == fullname then
		realm = GroupfinderFlags.OWN_REALM
	else
		realm = string.sub(fullname, string.len(shortname)+2)
	end

	-- get region specific realm language list
	if GroupfinderFlagsDB.region == "europe" then
		languageList = GroupfinderFlags.EU_REALM_LANGUAGES
	elseif GroupfinderFlagsDB.region == "america" then
		languageList = GroupfinderFlags.US_REALM_LANGUAGES
	end

	-- if option "showFlagOnlyIfOtherCountry" is active, only proceed with different languages
	if GroupfinderFlagsDB.showFlagOnlyIfOtherCountry and languageList[realm] == languageList[GroupfinderFlags.OWN_REALM] then
		return
	end

	-- add a font string for displaying the flag if needed
	if not self.GFF_text_flag then
		self.GFF_text_flag = self:CreateFontString("$parentFlag", "ARTWORK", "GameFontNormalSmall")
		if GroupfinderFlags.PGF_LOADED then
			self.GFF_text_flag:SetPoint("LEFT", self.Name, "RIGHT", -10, 1.5)
		else
			self.GFF_text_flag:SetPoint("LEFT", self.Name, "RIGHT", 2, 0)
		end
	end

	---- EXPERIMENTAL ----

	if GroupfinderFlagsDB.experimentalFeaturesEnabled then

		if not self.GFF_background_flag then
			self.GFF_background_flag = self:CreateTexture(nil, "ARTWORK")
			self.GFF_background_flag:SetAllPoints(self.DataDisplay)
			--self.GFF_background_flag:SetPoint("TOPRIGHT", self.DataDisplay, "TOPRIGHT", 0, 0)
			--self.GFF_background_flag:SetPoint("BOTTOMRIGHT", self.DataDisplay, "BOTTOMRIGHT", 0, 0)
			--self.GFF_background_flag:SetPoint("TOPLEFT", self.DataDisplay, "TOPRIGHT", -5, 0)
			--self.GFF_background_flag:SetPoint("BOTTOMLEFT", self.DataDisplay, "BOTTOMRIGHT", -5, 0)
			self.GFF_background_flag:SetAlpha(0.25)
		end

	end

	---- EXPERIMENTAL ----

	-- set the appropiate flag
	self.GFF_text_flag:SetText(languageList[realm] ~= nil and GroupfinderFlags.TEXT_IMAGE_PATH..GroupfinderFlags.FLAGS[languageList[realm]] or "")

	---- EXPERIMENTAL ----

		if GroupfinderFlagsDB.experimentalFeaturesEnabled then

		if languageList[realm] ~= nil then
			self.GFF_background_flag:Show()
			self.GFF_background_flag:SetTexture(GroupfinderFlags.TEXTURE_IMAGE_PATH..GroupfinderFlags.TEXTURES[languageList[realm]])
		end
	end

	---- EXPERIMENTAL ----

	if not GroupfinderFlags.PGF_LOADED then
		-- recalculate the name column's width (taken from blizz code and modified)
		local nameLength = 176 - 17
		if searchResultInfo.voiceChat ~= "" then
			self.VoiceChat:SetPoint("LEFT", self.GFF_text_flag, "RIGHT", 2, 0)
			nameLength = nameLength - 24
		end
		if ( self.Name:GetWidth() > nameLength ) then
			self.Name:SetWidth(nameLength)
		end
	end

end


local function AddFlagToPlayernameInChat(self, event, msg, author, ...)

	--print(author)
	-- gets name and realm of the player
	name, realm = string.split(author, "-")

	-- if realm is nil then player is from user's own realm
	if realm == nil or realm == "" then
		realm = GroupfinderFlags.OWN_REALM
	end

	realm = NormalizeRealmname(realm)

	-- check whether region is selected
	if GroupfinderFlagsDB.region ~= nil and (GroupfinderFlagsDB.region == "europe" or GroupfinderFlagsDB.region == "america") then

		-- get region specific realm language list
		if GroupfinderFlagsDB.region == "europe" then
			languageList = GroupfinderFlags.EU_REALM_LANGUAGES
		elseif GroupfinderFlagsDB.region == "america" then
			languageList = GroupfinderFlags.US_REALM_LANGUAGES
		end

		-- only proceed if player's realm is in database
		if languageList[realm] ~= nil then
			-- adding the flag by :AddLine()
			local flag = GroupfinderFlags.TEXT_IMAGE_PATH..GroupfinderFlags.FLAGS[languageList[realm]]
		    msg = string.format("%s %s", flag, msg)
		end
	end

    return false, msg, author, ...
end


local CHAT_EVENTS = {
	-- "CHAT_MSG_SAY",
	-- "CHAT_MSG_GUILD",
	-- "CHAT_MSG_PARTY",
	-- "CHAT_MSG_RAID",
	-- "CHAT_MSG_WHISPER",
	-- "CHAT_MSG_CHANNEL",
}
for i = 1, #CHAT_EVENTS do ChatFrame_AddMessageEventFilter(CHAT_EVENTS[i], AddFlagToPlayernameInChat) end



----------------------------------------------------------------------------
----------------------------------------------------------------------------
--------  OnEvent Handler  -------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------

-- OnEvent handler
local function OnEvent(self, event, arg1, arg2, ...)
	if event == "ADDON_LOADED" and arg1 == "GroupfinderFlags" then

		-- creating the saved variables' array if needed
		if GroupfinderFlagsDB == nil then
			GroupfinderFlagsDB = {}
    	end

    	-- set the saved variables' default value if needed
    	if GroupfinderFlagsDB.showFlagInGrpFinder == nil then
    		GroupfinderFlagsDB.showFlagInGrpFinder = true
    	end
		if GroupfinderFlagsDB.showFlagInTooltip == nil then
			GroupfinderFlagsDB.showFlagInTooltip = true
		end
		if GroupfinderFlagsDB.showCountrynameInTooltip == nil then
			GroupfinderFlagsDB.showCountrynameInTooltip = true
		end
		if GroupfinderFlagsDB.showFlagOnlyIfOtherCountry == nil then
			GroupfinderFlagsDB.showFlagOnlyIfOtherCountry = false
		end
		if GroupfinderFlagsDB.showLeaderFlagInGrpFinder == nil then
			GroupfinderFlagsDB.showLeaderFlagInGrpFinder = true
		end
		if GroupfinderFlagsDB.showTimezoneOnUSandOceania == nil then
			GroupfinderFlagsDB.showTimezoneOnUSandOceania = true
		end

		if GroupfinderFlagsDB.experimentalFeaturesEnabled == nil then
			GroupfinderFlagsDB.experimentalFeaturesEnabled = false
		end

		-- unregister PLAYER_LOGIN after retrieving saved variables
    	--GroupfinderFlags.mainFrame:UnregisterEvent("PLAYER_LOGIN")
    	GroupfinderFlags.mainFrame:UnregisterEvent("ADDON_LOADED")

    	-- set up the option panel
    	GroupfinderFlags.opanel.boxForGrpFinder:SetChecked(GroupfinderFlagsDB.showFlagInGrpFinder)
		GroupfinderFlags.opanel.boxForLeaderGrpFinder:SetChecked(GroupfinderFlagsDB.showLeaderFlagInGrpFinder)
    	GroupfinderFlags.opanel.boxForTooltipFlag:SetChecked(GroupfinderFlagsDB.showFlagInTooltip)
    	GroupfinderFlags.opanel.boxForTooltipCountryNames:SetChecked(GroupfinderFlagsDB.showCountrynameInTooltip)
    	GroupfinderFlags.opanel.boxForOnlyShowingIfLanguagesDiff:SetChecked(GroupfinderFlagsDB.showFlagOnlyIfOtherCountry)
    	GroupfinderFlags.opanel.boxForTimezonesOnUSandOceania:SetChecked(GroupfinderFlagsDB.showTimezoneOnUSandOceania)
    	--TODO boxForTimezonesOnUSandOceania

    	if GroupfinderFlagsDB.region ~= nil then
    		if GroupfinderFlagsDB.region == "europe" then
    			GroupfinderFlags.opanel.us_button:Enable()
    		elseif GroupfinderFlagsDB.region == "america" then
    			GroupfinderFlags.opanel.eu_button:Enable()
    		end
    	end

    	-- if no region is selected build and show selection dialog
    	if GroupfinderFlagsDB.region == nil then

    		local selectionFrame = CreateFrame("Frame", "GroupfinderFlagsRegionSelection", UIParent, "GlowBoxTemplate")--"ThinBorderTemplate") --GlowBoxTemplate
			selectionFrame:SetSize(300,200)

    		local top_text1 = selectionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    		top_text1:SetText("GroupfinderFlags")
    		top_text1:SetPoint("TOP", selectionFrame, "TOP", 0, -20)

    		local top_text2 = selectionFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    		top_text2:SetText("Choose your Region")
    		top_text2:SetPoint("TOP", top_text1, "BOTTOM", 0, 0)

			local eu_button = CreateFrame("Button", "GFF_EU_RegionButton", selectionFrame, "ThinBorderTemplate")
			eu_button:SetPoint("CENTER", selectionFrame, "CENTER", 48, -10)
			eu_button:SetSize(64, 64)
			eu_button:SetNormalTexture(GroupfinderFlags.MAPS.europe_sw)
			eu_button:SetPushedTexture(GroupfinderFlags.MAPS.europe)
			eu_button:SetHighlightTexture(GroupfinderFlags.BUTTON_OVERLAY)
			eu_button:SetScript("OnClick", function (self)
				GroupfinderFlagsDB.region = "europe"
				GroupfinderFlags.opanel.us_button:Enable()
				self:GetParent():Hide()
			end)
			GFF_ManipulateTextureColors(eu_button)

			local eu_text = selectionFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			eu_text:SetText("Europe")
			eu_text:SetPoint("TOP", eu_button, "BOTTOM", 0, -(eu_text:GetStringHeight()/2))

			local us_button = CreateFrame("Button", "GFF_US_RegionButton", selectionFrame, "ThinBorderTemplate")
			us_button:SetPoint("CENTER", selectionFrame, "CENTER", -48, -10)
			us_button:SetSize(64, 64)
			us_button:SetNormalTexture(GroupfinderFlags.MAPS.america_sw)
			us_button:SetPushedTexture(GroupfinderFlags.MAPS.america)
			us_button:SetHighlightTexture(GroupfinderFlags.BUTTON_OVERLAY)
			us_button:SetScript("OnClick", function (self)
				GroupfinderFlagsDB.region = "america"
				GroupfinderFlags.opanel.eu_button:Enable()
				self:GetParent():Hide()
			end)
			GFF_ManipulateTextureColors(us_button)

			local us_text = selectionFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			us_text:SetText("America\nOceania")
			us_text:SetPoint("TOP", us_button, "BOTTOM", 0, 0)


			selectionFrame:SetPoint("CENTER",0,0)
			selectionFrame:Show()

			selectionFrame.top_text1 = top_text1
			selectionFrame.top_text2 = top_text2

    		selectionFrame.eu_button = eu_button
    		selectionFrame.eu_text = eu_text

    		selectionFrame.us_button = us_button
    		selectionFrame.us_text = us_text

    		GroupfinderFlags.regionSelectionFrame = selectionFrame
    	end
	end
	if event == "PLAYER_LOGIN" then
		GroupfinderFlags.mainFrame:UnregisterEvent("PLAYER_LOGIN")
		local loaded, _ = C_AddOns.IsAddOnLoaded("PremadeGroupsFilter")
		GroupfinderFlags.PGF_LOADED = loaded
	end
end


----------------------------------------------------------------------------
----------------------------------------------------------------------------
--------  Script startup  --------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------

-- hooking blizz's code: --
-- hook for the applicantviewer
hooksecurefunc("LFGListApplicationViewer_UpdateApplicantMember", HookfunctionForGroupFinderApplicants)
-- hook for the search result view tooltip
hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", HookfunctionForGroupFinderSearchTooltip)
-- hook for the search result view (group leader flag)
hooksecurefunc("LFGListSearchEntry_Update", HookfunctionForGroupFinderSearchLeaderFlag)
-- hook for the gametooltip
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)

	--DevTools_Dump(data)

	-- check if called tooltip is blizz's game tooltip and not a third party copy
	if tooltip ~= _G.GameTooltip then
		return
	end

	HookfunctionForGametooltip()
end)

-- loading saved settings
GroupfinderFlags.mainFrame:RegisterEvent("ADDON_LOADED")
GroupfinderFlags.mainFrame:RegisterEvent("PLAYER_LOGIN")
GroupfinderFlags.mainFrame:SetScript("OnEvent", OnEvent)


-- slash commands
SLASH_GROUPFINDERFLAGS1 = "/gff"
SLASH_GROUPFINDERFLAGS2 = "/groupfinderflags"
SlashCmdList["GROUPFINDERFLAGS"] = function(msg)

	if msg == "exp" then
		GroupfinderFlagsDB.experimentalFeaturesEnabled = not GroupfinderFlagsDB.experimentalFeaturesEnabled
	else
		if InterfaceOptionsFrame_OpenToCategory then
		    InterfaceOptionsFrame_OpenToCategory(GroupfinderFlags.opanel)
		    InterfaceOptionsFrame_OpenToCategory(GroupfinderFlags.opanel)
		elseif GroupfinderFlags.categoryID then
		    Settings.OpenToCategory(GroupfinderFlags.categoryID)
		end
	end
end
