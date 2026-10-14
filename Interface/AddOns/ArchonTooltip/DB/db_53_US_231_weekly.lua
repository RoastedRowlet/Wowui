local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Paladin-Protection','Unknown-Unknown','Paladin-Holy','Priest-Holy','Druid-Guardian','Hunter-BeastMastery','Shaman-Elemental','Hunter-Marksmanship','Mage-Arcane','Shaman-Restoration','DeathKnight-Frost','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Protection','Rogue-Subtlety','Warrior-Arms','Druid-Balance','Priest-Shadow','Priest-Discipline','Warrior-Fury','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Unholy','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Mage-Frost',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aalana:BAABNQAECn8jAAIBAAgKqiJNCQAHAwABAAgKqiJNCQAHAwAAAA==.',
Ab='Abelle:BAAANQADCgcIEwAAAA==.',
Ad='Adrialortial:BAAANQADCgcICgAAAA==.',
Ae='Aegis:BAAANQAECgYIDwAAAA==.',
Al='Aliantha:BAAANQABCgIIAgAAAA==.',
An='Animalstyle:BAAANQAECgQIBAABNQAECgcIEAACAAAAAA==.Antrus:BAAANQAECggIDQAAAA==.',
Ar='Arakhne:BAAANQADCgYIBgABNQAECgkJKQADAKweAA==.',
As='Asthar:BAAANQADCggIDwAAAA==.',
Ba='Babyoda:BAAANQADCgIIAwAAAA==.Babysnatcher:BAAANQADCgYICgAAAA==.Banthos:BAABNQAECn84AAIEAAkKeR5nEgA1AwAEAAkKeR5nEgA1AwAAAA==.',
Be='Bearbearbear:BAABNQAECn8jAAIFAAgK2ApDJQBmAQAFAAgK2ApDJQBmAQABNQAECgkJIgAGAI0TAA==.',
Bi='Bifpowsplat:BAAANQAECgEIAQAAAA==.',
Bo='Bolla:BAABNQAECn8XAAIHAAgKeQKy3ADXAAAHAAgKeQKy3ADXAAAAAA==.Boundless:BAAANQABCgIIAgAAAA==.',
Br='Breadadin:BAAANQADCgQIBAAAAA==.Breadshank:BAAANQADCgUIBQAAAA==.Brtiki:BAAANQABCggIHQAAAA==.',
Bu='Bulldozer:BAAANQAECgEIAQAAAA==.Butchflowers:BAAANQADCgQIBgAAAA==.',
Cf='Cfodder:BAAANQAECgYICwAAAA==.',
Ch='Chiste:BAAANQAECgIIAwAAAA==.',
Co='Condemner:BAAANQABCggICwAAAA==.Covak:BAABNQAECn8XAAMIAAkKZBiWNwCOAQAIAAcKxxSWNwCOAQAGAAMKgyDn7wAcAQABNQAFFAIIBgAJAN4bAA==.',
Cr='Crixis:BAAANQADCgUIBQAAAA==.',
Cu='Cutcutcut:BAAANQAECgYICwAAAA==.',
Da='Daeleth:BAAANQABCgYIBgAAAA==.Dahlia:BAABNQAECn8cAAIKAAkKHRjWOwBuAgAKAAkKHRjWOwBuAgABNQAFFAYIFAAGAF0dAA==.Dalaye:BAAANQADCgcICAAAAA==.Dantedragon:BAAANQAECgIIAgAAAA==.Dargho:BAAANQAECggICQABNQAFFAIIBgAJAN4bAA==.Dastypop:BAAANQADCgUICAAAAA==.',
De='Deadpanda:BAABNQAECn81AAILAAkKXA9nOQDoAQALAAkKXA9nOQDoAQAAAA==.',
Dk='Dkillin:BAABNQAECn8dAAIMAAcKeQkG3gBZAQAMAAcKeQkG3gBZAQAAAA==.',
Dr='Dreadheirark:BAAANQABCgIIAgAAAA==.',
Du='Durlag:BAAANQAECgEIAQAAAA==.',
Eg='Eggosa:BAAANQADCgIIAgAAAA==.',
El='Elizalynn:BAABNQAECn8bAAIEAAgKjx9qKwC4AgAEAAgKjx9qKwC4AgAAAA==.',
Ev='Everli:BAAANQADCgUICAAAAA==.',
Fa='Father:BAAANQAECgMIAwAAAA==.',
Fi='Fidgita:BAAANQAECgMIAwAAAA==.Fishguts:BAACNQAFFH8OAAINAAUKexHmBAB5AQANAAUKexHmBAB5AQA1AAQKf0MABA0ACQo5GW0PAIUCAA0ACQo5GW0PAIUCAA4ACAqBGLEgACMCAA8ABQpaCnsfAOoAAAAA.',
Fo='Focaccia:BAAANQADCggJCQAAAA==.Foxthisup:BAAANQAECgIIBAABNQAECggIDQACAAAAAA==.',
Gl='Glasscannon:BAAANQADCgcIDAAAAA==.',
Go='Goburin:BAAANQADCgUIBQAAAA==.Goldmoorn:BAEANQAECggIDwAAAA==.',
Gr='Granuaile:BAAANQAECgQICQAAAA==.',
Gu='Gula:BAAANQADCgYJBgAAAA==.Guldude:BAAANQADCgUIBQABNQAECgcIEQACAAAAAA==.',
Gw='Gwenianna:BAAANQADCgEIAQABNQAECggIIAAKABIZAA==.Gwenquaya:BAABNQAECn8gAAIKAAgKEhnzRwA/AgAKAAgKEhnzRwA/AgAAAA==.',
Ho='Hockeydruid:BAAANQAECgEIAQABNQAECgcIGgAGABMUAA==.Hockeyhunter:BAABNQAECn8aAAIGAAcKExSfgQAGAgAGAAcKExSfgQAGAgAAAA==.Hoewhrmymoni:BAAANQABCgYIBgAAAA==.Hoistbro:BAAANQAECgUICAAAAA==.Holydps:BAAANQADCgIIAwAAAA==.',
Hu='Huntdrath:BAAANQAECgEIAgAAAA==.Hunthunthunt:BAABNQAECn8iAAIGAAkKjRN5VQBvAgAGAAkKjRN5VQBvAgAAAA==.',
['Hè']='Hèxen:BAAANQABCgcIBwAAAA==.',
Ic='Ichaival:BAAANQAECgUICQABNQAECgkJFQAQACYNAA==.',
Ir='Irox:BAAANQADCgYIAQAAAA==.',
Je='Jedem:BAAANQADCgQIBgAAAA==.',
Ka='Kazu:BAAANQAECgUICAAAAA==.Kazum:BAAANQAECgIIAgAAAA==.',
Ke='Keralan:BAABNQAECn8cAAIRAAkKYCW3AADLAwARAAkKYCW3AADLAwAAAA==.',
Ki='Kimk:BAAANQADCgMIAwAAAA==.',
Kj='Kjevoke:BAAANQAECggIAgAAAA==.',
Kl='Klhank:BAAANQADCgEIAQAAAA==.',
Ko='Kosuke:BAAANQAECgQIBwAAAA==.',
Kr='Kromwel:BAABNQAECn8nAAISAAgKuSF/BQAaAwASAAgKuSF/BQAaAwAAAA==.',
Ky='Ky:BAAANQADCgUIDAAAAA==.',
La='Laizee:BAABNQAECn8oAAIKAAgKbgp9iQBuAQAKAAgKbgp9iQBuAQAAAA==.Latrice:BAAANQAECgMIBQAAAA==.',
Le='Lezal:BAAANQAECgEIAQAAAA==.',
Li='Liquidnitro:BAAANQAECgQIBQAAAA==.Livsfara:BAAANQADCgUIBQABNQAECggIHAASADEbAA==.',
Lo='Lone:BAAANQAECgIIAgABNQAECggIGQATABgfAA==.',
Lu='Lucyreborn:BAAANQAECgUIBwAAAA==.',
Ly='Lyam:BAAANQADCgEIAQAAAA==.Lylboo:BAAANQAECgMIBAAAAA==.',
Ma='Mansamusa:BAAANQAECgIIAgAAAA==.Mawikiea:BAAANQADCgIIAwABNQAECgkJLQAEAC0dAA==.',
Me='Melander:BAABNQAECn8cAAMSAAgKMRtqDQBZAgASAAgKMRtqDQBZAgAUAAYKMw08xgBnAQAAAA==.Meltman:BAAANQAECgEIAQAAAA==.',
Mh='Mhoram:BAAANQABCgYIBgAAAA==.',
Mi='Micur:BAAANQAECgYICwAAAA==.Mightborne:BAAANQAECggIDQAAAA==.Mike:BAAANQADCgEIAQAAAA==.',
Mo='Morbus:BAAANQAECgIIAgAAAA==.Mordracon:BAAANQAECgcIEQAAAA==.',
My='Myth:BAABNQAECn87AAIJAAkKmxjbYgC4AgAJAAkKmxjbYgC4AgAAAA==.',
Na='Nami:BAAANQAFFAIIAgAAAA==.Nazareths:BAAANQABCgEIAQAAAA==.',
Ne='Nelflander:BAAANQAECgMIAwABNQAECggIHAASADEbAA==.Nemble:BAAANQABCgYIDwAAAA==.',
Og='Ogou:BAAANQAECgcIEQAAAA==.',
Om='Omnimage:BAAANQAECgQICgAAAA==.',
On='Onyxz:BAABNQAECn8jAAIVAAgK1hlCLAB2AgAVAAgK1hlCLAB2AgAAAA==.',
['Où']='Oùtcast:BAAANQABCggICgAAAA==.',
Pa='Panla:BAAANQADCgQIBAAAAA==.Patrickstâr:BAAANQAECgcIDQAAAA==.',
Po='Pollywag:BAAANQADCgMIAwAAAA==.',
Pr='Promethus:BAAANQAECgIIAgAAAA==.',
Ra='Raedaldra:BAABNQAECn8nAAQWAAkKsByOFQCwAgAWAAgKVxyOFQCwAgAEAAQKzRHTrAAKAQAXAAQKcxByEwDvAAAAAA==.Raggnarr:BAACNQAFFH8IAAMUAAQKTxYbGwA1AQAUAAQKsg8bGwA1AQAYAAIKGRRZAwCVAAA1AAQKfyoAAxgACQoaIl0DACMDABgACQoaIl0DACMDABQABAqnHIvLAFkBAAAA.Ragnaroc:BAAANQABCgEIAQAAAA==.Rainesagé:BAACNQAFFH8GAAIEAAMKBQa4IQDNAAAEAAMKBQa4IQDNAAA1AAQKfx8AAgQACQpdF7g/AGgCAAQACQpdF7g/AGgCAAAA.Ranar:BAABNQAECn8VAAIQAAkKJg0zNwDyAQAQAAkKJg0zNwDyAQAAAA==.',
Re='Remiel:BAAANQADCgUIBQAAAA==.Renatnom:BAAANQAECgQIDAAAAA==.Reäper:BAAANQABCgIIBgAAAA==.',
Ri='Rimlin:BAAANQADCgYIDAAAAA==.Rishu:BAAANQABCgUIBQAAAA==.Rizzhashira:BAABNQAECn8bAAIBAAgKAx5LFQBUAgABAAgKAx5LFQBUAgAAAA==.',
Ro='Ronji:BAAANQADCgEIAQAAAA==.Rowge:BAAANQAECggIEwAAAA==.Rox:BAAANQABCgQIDgAAAA==.',
Ry='Rythevia:BAABNQAECn8xAAMZAAkKBRl8CwCuAgAZAAkKBRl8CwCuAgAaAAcK4RQsDACTAQAAAA==.',
Sa='Sadgirls:BAABNQAECn8YAAMLAAgKBSFDDwAUAwALAAgKBSFDDwAUAwAbAAEKAADeygBTAAAAAA==.Satanickk:BAAANQAECgcIEwAAAA==.Satanos:BAAANQAECgEIAQAAAA==.',
Sc='Scora:BAAANQABCgEIAQAAAA==.',
Sh='Shadowraven:BAAANQADCggIBwAAAA==.Shamshamsham:BAABNQAECn8ZAAIHAAgK7Q01cgDGAQAHAAgK7Q01cgDGAQABNQAECgkJIgAGAI0TAA==.',
Sk='Skillz:BAAANQABCgIIAgAAAA==.',
Sl='Slamcheeks:BAAANQADCgYIBgAAAA==.',
Sn='Sneakybeef:BAAANQADCgYIBgABNQAECggIHAASADEbAA==.Snikit:BAAANQAECgQIBAABNQAECggIHAASADEbAA==.',
So='Sojourner:BAAANQAECgcIDwAAAA==.',
Sp='Speedy:BAAANQADCgEIAQABNQAECgcIGgAGABMUAA==.Spellstyle:BAAANQAECgcIEAAAAA==.',
St='Stimpack:BAAANQAECggICAAAAA==.',
Su='Sundaystyle:BAAANQAECgQIBAABNQAECgcIEAACAAAAAA==.Superfire:BAAANQAECgQIBAAAAA==.Superspam:BAABNQAECn8bAAMVAAgKqxQxOQAiAgAVAAgKqxQxOQAiAgAcAAQKoCG8MwB4AQAAAA==.',
Sy='Sylphiett:BAABNQAECn8nAAIJAAgKiRKuwQD/AQAJAAgKiRKuwQD/AQABNQAECgkJJwAZADAUAA==.',
Te='Teinaras:BAABNQAECn8iAAIIAAkKsxl/GACRAgAIAAkKsxl/GACRAgAAAA==.',
Th='Thefloydster:BAAANQAECgEIAQAAAA==.Thistledewit:BAAANQAECggIEAAAAA==.',
Ti='Tinydragon:BAABNQAECn8nAAIZAAkKMBT7EABEAgAZAAkKMBT7EABEAgAAAA==.Tinyvoid:BAAANQAECggIEgABNQAECgkJJwAZADAUAA==.Tirok:BAAANQADCgMIAwAAAA==.',
To='Togdumburz:BAABNQAECn8iAAMdAAkKURqcQgCHAgAdAAgKaBqcQgCHAgAeAAEKxBndaQBMAAAAAA==.Tortillalock:BAAANQADCgEIAQAAAA==.',
Ty='Tyberth:BAAANQABCgIIBAAAAA==.Typhon:BAABNQAECn8aAAMKAAkKwBpCKQC8AgAKAAkKwBpCKQC8AgAHAAEKCwVIOwEuAAAAAA==.',
Ud='Udderlymad:BAAANQADCggIBwABNQAECggIDQACAAAAAA==.',
Un='Undeåd:BAAANQAECgQIBQAAAA==.',
Va='Vaelhyra:BAAANQAECgIIAgABNQAECgkJHAARAGAlAA==.Vameera:BAAANQAECgEIAQAAAA==.',
Ve='Velirine:BAABNQAECn8aAAIfAAcKBRoLCQBEAgAfAAcKBRoLCQBEAgAAAA==.',
Vi='Vietsham:BAAANQAECgYIBgAAAA==.Vilkas:BAACNQAFFH8GAAIIAAYKwgfTDABtAQAIAAYKwgfTDABtAQA1AAQKfxcAAggACQqbGUUXAJwCAAgACQqbGUUXAJwCAAE1AAUUBQgIABYAxh4A.',
Vo='Vokevokevoke:BAAANQADCgYICAABNQAECgkJIgAGAI0TAA==.Vorpalite:BAAANQADCgYIBgAAAA==.',
Wa='Warspite:BAAANQADCgIIAgABNQAECggIIwAVANYZAA==.Warwarwar:BAABNQAECn8ZAAQSAAgK1AlcHwBRAQASAAgKIwhcHwBRAQAYAAQKzwU0IgChAAAUAAUKYQLMHwGTAAABNQAECgkJIgAGAI0TAA==.',
Wo='Wolffangfist:BAAANQADCgEIAQAAAA==.',
['Xä']='Xänthe:BAABNQAECn8tAAMEAAkKLR2qIwDbAgAEAAkKLR2qIwDbAgAWAAEK2gawfQAsAAAAAA==.',
Yo='You:BAAANQADCgUIBgABNQAECgcIGgAGABMUAA==.',
Za='Zarron:BAAANQADCgUIBQAAAA==.',
Zi='Zife:BAACNQAFFH8MAAIOAAQKSyXeBQCyAQAOAAQKSyXeBQCyAQA1AAQKfyYAAg4ACQpHJrYHAFEDAA4ACQpHJrYHAFEDAAAA.',
Zu='Zultarra:BAAANQADCgcIGAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
