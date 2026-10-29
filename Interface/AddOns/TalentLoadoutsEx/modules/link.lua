local _, Addon = ...;

local TALENT_BUILD_CHAT_LINK_TEXT = _G["TALENT_BUILD_CHAT_LINK_TEXT"];

function Addon:PostLink()
	local data = Addon:GetData();
	if data and data.text then
		if data.isLegacy then
			Addon:Print(Addon.LegacyWarningMessage);
		elseif TALENT_BUILD_CHAT_LINK_TEXT then
			local specID = PlayerUtil.GetCurrentSpecID();
			local specName = select(2, GetSpecializationInfoByID(specID));
			local viewText = ("[%s]"):format(TALENT_BUILD_CHAT_LINK_TEXT:format(specName, Addon.playerClassName));
			local linkText = LinkUtil.FormatLink("talentbuild", viewText, specID, UnitLevel("player"), data.text);
			local chatLink = Addon.playerClassColor:WrapTextInColorCode(linkText);
			if not _G["ChatEdit_InsertLink"](chatLink) then
				_G["ChatFrame_OpenChat"](chatLink);
			end
		end
	end
end

function Addon:CopyLink()
	local data = Addon:GetData();
	if data and data.text then
		if data.isLegacy then
			Addon:Print(Addon.LegacyWarningMessage);
		else
			Addon:ShowCopyPopup(data.text);
		end
	end
end
