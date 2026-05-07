local _, Addon = ...;

local function ConvertToImportLoadoutEntryInfo(specID, configID, treeID, loadoutContent)
	local loadoutEntryInfo = Addon.TalentsFrame:ConvertToImportLoadoutEntryInfo(configID, treeID, loadoutContent);
	local nodeOrder = Addon:GetNodeOrder(specID, configID, treeID);

	for _, node in pairs(loadoutEntryInfo) do
		if not nodeOrder[node.nodeID] then
			return false;
		end
	end

	table.sort(
		loadoutEntryInfo,
		function(a, b)
			return nodeOrder[a.nodeID] < nodeOrder[b.nodeID];
		end
	);

	return loadoutEntryInfo;
end

local function CommitTalent(configID)
	if configID and Addon.ApplyButton.isShown and Addon.ApplyButton.isEnabled then
		-- When applying Talent from an addon, a taint error may occur.
		-- If there are too many reports of this occurring, I will discontinue this feature.
		-- Addon.TalentsFrame:CommitConfig();

		-- It looks a little worse than it is, but this one does not cause taint error.
		C_Traits.CommitConfig(configID);
	end
end

local loadoutEntryInfoCache = {};
local starterBuildDeactiveFrame = CreateFrame("Frame");
function Addon:GetLoadoutEntryInfo(importText, configID)
	local loadoutEntryInfo = loadoutEntryInfoCache[importText];
	if loadoutEntryInfo then
		return loadoutEntryInfo;
	end

	local talentsFrame = Addon.TalentsFrame;
	local specID = PlayerUtil.GetCurrentSpecID();
	local treeID = C_ClassTalents.GetTraitTreeForSpec(specID);
	if not treeID then
		Addon:Print("Error: C_ClassTalents.GetTraitTreeForSpec() = nil");
		return false;
	end

	local importStream = ExportUtil.MakeImportDataStream(importText);
	if not importStream or not importStream.currentRemainingValue then
		return false;
	end

	local errorMessage = Addon:GetValidationError(treeID, importStream);
	if errorMessage then
		return false;
	end

	if C_ClassTalents.GetStarterBuildActive() then
		local eventName = "TRAIT_CONFIG_UPDATED";
		starterBuildDeactiveFrame:RegisterEvent(eventName);
		starterBuildDeactiveFrame:SetScript(
			"OnEvent",
			function(_, event, ...)
				if event == eventName and (...) == configID then
					starterBuildDeactiveFrame:UnregisterAllEvents();
					Addon:ImportTextAsync(importText);
				end
			end
		);

		C_ClassTalents.SetStarterBuildActive(false);
		return false;
	end

	local success, loadoutContent = pcall(talentsFrame.ReadLoadoutContent, talentsFrame, importStream, treeID);
	if not success then
		return false;
	end

	loadoutEntryInfo = ConvertToImportLoadoutEntryInfo(specID, configID, treeID, loadoutContent);
	if not loadoutEntryInfo then
		return false;
	end

	loadoutEntryInfoCache[importText] = loadoutEntryInfo;
	return loadoutEntryInfo;
end

local function PrintImportError(configID, entry, ranksPurchased)
	local entryInfo = entry.selectionEntryID and C_Traits.GetEntryInfo(configID, entry.selectionEntryID);
	local definitionInfo = entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo(entryInfo.definitionID);

	if not definitionInfo then
		Addon:Print("Error: Loadout entry cannot use. (definitionInfo is nil)");
		return;
	end

	local name = definitionInfo.overrideName;
	if not name then
		local spellInfo = definitionInfo.spellID and C_Spell.GetSpellInfo(definitionInfo.spellID);
		name = spellInfo and spellInfo.name;
	end

	if not name then
		Addon:Print("Error: Loadout entry cannot use. (spellInfo is nil)");
	elseif ranksPurchased then
		Addon:Print(string.format("Cannot Learn: %s(Rank: %d).", name, ranksPurchased));
	else
		Addon:Print(string.format("Cannot Learn: %s.", name));
	end
end

local RankTraitNodeTypes = {
	[Enum.TraitNodeType.Single] = true,
	[Enum.TraitNodeType.Tiered] = true,
}

local function TryPurchaseNode(configID, entry, apexRank)
	local nodeID = entry.nodeID;
	local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);

	if RankTraitNodeTypes[nodeInfo.type] then
		-- Rank
		local specID = PlayerUtil.GetCurrentSpecID();
		local isApex = (nodeID == Addon.ApexNodeIDs[specID]);
		local ranksPurchased = isApex and apexRank or entry.ranksPurchased;
		if nodeInfo.activeRank == ranksPurchased then
			return true; -- Skip
		end

		local hasError = false;
		for _ = 1, ranksPurchased do
			if not C_Traits.PurchaseRank(configID, nodeID) then
				hasError = true;
			end
		end

		if hasError then
			local newRank = C_Traits.GetNodeInfo(configID, nodeID).activeRank;
			if newRank ~= ranksPurchased then
				PrintImportError(configID, entry, ranksPurchased);
				return false;
			end
		end
	else
		-- Selection
		local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID;
		if activeEntryID == entry.selectionEntryID then
			return true; -- Skip
		end

		if not C_Traits.SetSelection(configID, nodeID, entry.selectionEntryID, false) then
			PrintImportError(configID, entry);
			return false;
		end
	end

	return true;
end

local function RefundRank(configID, nodeInfo)
	if nodeInfo.ranksPurchased == 0 then
		return; -- Skip
	end

	local nodeID = nodeInfo.ID;
	C_Traits.RefundAllRanks(configID, nodeID);
	for _ = 1, nodeInfo.maxRanks do
		C_Traits.RefundRank(configID, nodeID);
	end
end

local function ImportTextByNodeType(configID, loadoutEntryInfo, nodeType)
	local specID = PlayerUtil.GetCurrentSpecID();
	local treeID = C_ClassTalents.GetTraitTreeForSpec(specID);
	if not treeID then
		Addon:Print("Error: C_ClassTalents.GetTraitTreeForSpec() = nil");
		return false;
	end

	local apexNodeID = Addon.ApexNodeIDs[specID];
	local apexRank = 0;

	local targetNodeIDs = {};
	for _, entry in ipairs(loadoutEntryInfo) do
		local nodeID = entry.nodeID;
		if nodeType == Addon.NodeTypeDictionary[nodeID] then
			targetNodeIDs[nodeID] = entry;
			if nodeID == apexNodeID then
				apexRank = apexRank + entry.ranksPurchased;
			end
		end
	end

	local isHeroResetted = false;
	if nodeType == Addon.NodeType.Hero then
		for _, subTreeID in ipairs(Addon.SubTreeIDs[specID]) do
			local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID);
			for _, nodeID in ipairs(subTreeInfo.subTreeSelectionNodeIDs) do
				local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
				local activeEntryID = nodeInfo and nodeInfo.activeEntry and nodeInfo.activeEntry.entryID;
				if activeEntryID then
					local entry = targetNodeIDs[nodeID];
					local selectionEntryID = entry and entry.selectionEntryID;
					if activeEntryID ~= selectionEntryID then
						isHeroResetted = true;
						C_Traits.RefundRank(configID, nodeID);
						break;
					end
				end
			end

			if isHeroResetted then
				break;
			end
		end
	end

	if isHeroResetted then
		for _, traitCurrencyID in ipairs(Addon.SubTreeTraitCurrencyIDs[specID]) do
			C_Traits.ResetTreeByCurrency(configID, treeID, traitCurrencyID);
		end
	else
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
			if nodeType == Addon.NodeTypeDictionary[nodeID] then
				local entry = targetNodeIDs[nodeID];
				local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);

				if nodeInfo.activeRank > nodeInfo.ranksPurchased then
					-- Skip
				elseif not entry then
					RefundRank(configID, nodeInfo);
				elseif nodeID == apexNodeID then
					-- Apex Talents
					if apexRank == nodeInfo.ranksPurchased then
						-- Skip
					else
						RefundRank(configID, nodeInfo);
					end
				elseif RankTraitNodeTypes[nodeInfo.type] then
					-- Rank
					if nodeInfo.ranksPurchased == entry.ranksPurchased then
						-- Skip
					elseif nodeInfo.ranksPurchased > 0 then
						RefundRank(configID, nodeInfo);
					end
				else
					-- Selection
					local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID;
					if activeEntryID == entry.selectionEntryID then
						-- Skip
					elseif entry.selectionEntryID == 0 then
						RefundRank(configID, nodeInfo);
					end
				end
			end
		end
	end

	for _, entry in ipairs(loadoutEntryInfo) do
		local nodeID = entry.nodeID;
		if nodeType == Addon.NodeTypeDictionary[nodeID] then
			if not TryPurchaseNode(configID, entry, apexRank) then
				return UnitLevel("player") < GetMaxPlayerLevel();
			end
		end
	end

	return true;
end

local function ImportTextPcall(configID, loadoutEntryInfo)
	return
		ImportTextByNodeType(configID, loadoutEntryInfo, Addon.NodeType.Class) and
		ImportTextByNodeType(configID, loadoutEntryInfo, Addon.NodeType.Spec) and
		ImportTextByNodeType(configID, loadoutEntryInfo, Addon.NodeType.Hero);
end

function Addon:ImportText(importText)
	local configID = C_ClassTalents.GetActiveConfigID();
	if not configID then
		Addon:Print("Error: C_ClassTalents.GetActiveConfigID() = nil");
		return false;
	end

	if Addon:IsTextLoaded(importText, Addon:GetExportText()) then
		CommitTalent(configID);
		return false;
	end

	local loadoutEntryInfo = Addon:GetLoadoutEntryInfo(importText, configID);
	if not loadoutEntryInfo then
		return;
	end

	Addon.isLocked = true;
	Addon:SetTrackNode(false);

	local pcallResult, result = pcall(ImportTextPcall, configID, loadoutEntryInfo);

	Addon.isLocked = false;
	Addon:SetTrackNode(true);

	if not pcallResult then
		error(result);
	end

	return result;
end

function Addon:ImportTextAsync(importText)
	C_Timer.After(
		0,
		function()
			Addon:ImportText(importText);
			Addon:UpdateScrollBox(true);
		end
	);
end
