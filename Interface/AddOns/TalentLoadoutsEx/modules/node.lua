local _, Addon = ...;

-- [specID] = { nodeID, nodeID, ...}
local nodesList = {};
function Addon:GetNodes(specID, configID, treeID)
	if nodesList[specID] then
		return nodesList[specID];
	end

	local nodeOrder = {};
	for _, nodeID in pairs(C_Traits.GetTreeNodes(treeID)) do
		local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
		if nodeInfo.isVisible then
			table.insert(nodeOrder, {nodeInfo.posY, nodeInfo.posX, nodeID});
		end
	end

	table.sort(
		nodeOrder,
		function(a, b)
			if a[1] ~= b[1] then
				return a[1] < b[1];
			else
				return a[2] < b[2];
			end
		end
	);

	local nodeIDs = {};
	for _, node in ipairs(nodeOrder) do
		table.insert(nodeIDs, node[3]);
	end

	nodesList[specID] = nodeIDs;
	return nodeIDs;
end

-- https://warcraft.wiki.gg/wiki/API_C_Traits.GetTraitCurrencyInfo
-- Enum.TraitCurrencyFlag
Addon.NodeType = {
	Class = 4,
	Spec  = 8,
	Hero  = 0,
};

-- [nodeID] = Addon.NodeType
Addon.NodeTypeDictionary = {};

-- [specID] = nodeID
Addon.ApexNodeIDs = {};

-- [specID] = { subTreeID, subTreeID }
Addon.SubTreeIDs = {};

-- [specID] = { traitCurrencyID, traitCurrencyID }
Addon.SubTreeTraitCurrencyIDs = {};

-- [nodeID] = Order
local nodeOrderList = {};
function Addon:GetNodeOrder(specID, configID, treeID)
	if nodeOrderList[specID] then
		return nodeOrderList[specID];
	end

	local order = {};
	for index, nodeID in ipairs(Addon:GetNodes(specID, configID, treeID)) do
		order[nodeID] = index;

		local nodeCosts = C_Traits.GetNodeCost(configID, nodeID);
		local traitCurrencyID = nodeCosts and nodeCosts[1] and nodeCosts[1].ID;
		Addon.NodeTypeDictionary[nodeID] = traitCurrencyID and C_Traits.GetTraitCurrencyInfo(traitCurrencyID);

		local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID);
		if nodeInfo.maxRanks >= 4 then
			Addon.ApexNodeIDs[specID] = nodeID;
		end
	end

	local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec();
	Addon.SubTreeIDs[specID] = subTreeIDs;
	local SubTreeTraitCurrencyIDs = {};
	for _, subTreeID in ipairs(subTreeIDs) do
		local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID);
		table.insert(SubTreeTraitCurrencyIDs, subTreeInfo.traitCurrencyID);
		for _, nodeID in ipairs(subTreeInfo.subTreeSelectionNodeIDs) do
			Addon.NodeTypeDictionary[nodeID] = Addon.NodeType.Hero;
		end
	end

	Addon.SubTreeTraitCurrencyIDs[specID] = SubTreeTraitCurrencyIDs;

	nodeOrderList[specID] = order;
	return order;
end
