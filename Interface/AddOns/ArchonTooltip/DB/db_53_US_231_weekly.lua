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

local lookup = {'Paladin-Protection','Mage-Arcane','Paladin-Holy','Priest-Holy','Druid-Guardian','Hunter-BeastMastery','Shaman-Elemental','Hunter-Marksmanship','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Protection','Rogue-Subtlety','Warrior-Arms','Mage-Frost','Rogue-Assassination','Druid-Restoration','Priest-Shadow','Priest-Discipline','Warrior-Fury','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aalana:BAABNQAECn8pAAIBAAoKdB1vCQAGAwABAAoKdB1vCQAGAwAAAA==.',
Ab='Abelle:BAAANQADCgcIGAAAAA==.',
Ad='Adrialortial:BAAANQADCgcICgAAAA==.',
Ae='Aegis:BAAANQAECgYIDwAAAA==.',
Al='Aliantha:BAAANQABCgIIAgAAAA==.',
An='Animalstyle:BAAANQAECgQIBAABNQAECgkJFQACABIWAA==.Antrus:BAAANQAECggIEQAAAA==.',
Ar='Arakhne:BAAANQADCgYIBgABNQAECgkJLAADAAAfAA==.',
As='Asthar:BAAANQADCggIDwAAAA==.',
Ba='Babyoda:BAAANQADCgIIAwAAAA==.Babysnatcher:BAAANQADCgYICgAAAA==.Banthos:BAABNQAECn9BAAIEAAoKOSHtBAC/AgAEAAoKOSHtBAC/AgAAAA==.',
Be='Bearbearbear:BAABNQAECn8lAAIFAAkKigrtJQBnAQAFAAkKigrtJQBnAQABNQAECgoKJwAGAJoRAA==.',
Bi='Bifpowsplat:BAAANQAECgEIAQAAAA==.',
Bo='Bolla:BAABNQAECn8ZAAIHAAgKeQJW3wDXAAAHAAgKeQJW3wDXAAAAAA==.Boundless:BAAANQABCgIIAgAAAA==.',
Br='Breadadin:BAAANQADCgQIBAAAAA==.Breadshank:BAAANQADCgUIBQAAAA==.Brtiki:BAAANQABCggIHQAAAA==.',
Bu='Bulldozer:BAAANQAECgEIAQAAAA==.Butchflowers:BAAANQADCgUICwAAAA==.',
Cf='Cfodder:BAABNQAECn8UAAIGAAcKRhWLiwDzAQAGAAcKRhWLiwDzAQAAAA==.',
Ch='Chiste:BAAANQAECgIIAwAAAA==.',
Co='Condemner:BAAANQABCggICwAAAA==.Covak:BAACNQAFFH8FAAMGAAQKVAg8JACjAAAGAAIKmAs8JACjAAAIAAMKAAJCIABtAAA1AAQKfxgAAwgACgq1FSk4AI4BAAgACArPESk4AI4BAAYAAwqDIJnyABwBAAAA.',
Cr='Crixis:BAAANQADCgUIBQAAAA==.',
Cu='Cutcutcut:BAAANQAECgcIEQAAAA==.',
Da='Daeleth:BAAANQABCgYIBgAAAA==.Dahlia:BAABNQAECn8fAAIJAAkKLRuRPABtAgAJAAkKLRuRPABtAgABNQAFFAYIFgAGAP4dAA==.Dalaye:BAAANQADCgcICAAAAA==.Dantedragon:BAAANQAECgIIAgAAAA==.Dargho:BAAANQAECggIEAABNQAFFAQIBQAGAFQIAA==.Dastypop:BAAANQADCgUICAAAAA==.',
De='Deadpanda:BAABNQAECn86AAMKAAoKNg5tOgDoAQAKAAoKNg5tOgDoAQALAAEKAAChZAAAAAAAAA==.',
Dk='Dkillin:BAABNQAECn8fAAIMAAgKBwlj4QBZAQAMAAgKBwlj4QBZAQAAAA==.',
Dr='Dreadheirark:BAAANQABCgIIAgAAAA==.',
Du='Durlag:BAAANQAECgIIAgAAAA==.',
Eg='Eggosa:BAAANQADCgIIAgAAAA==.',
El='Elizalynn:BAABNQAECn8eAAIEAAkK4R8zLAC4AgAEAAkK4R8zLAC4AgAAAA==.',
Ev='Everli:BAAANQADCgUICAAAAA==.',
Fa='Father:BAAANQAECgQIBwAAAA==.',
Fi='Fidgita:BAAANQAECgMIAwAAAA==.Fishguts:BAACNQAFFH8PAAINAAYKyxAIBQB5AQANAAYKyxAIBQB5AQA1AAQKf0kABA0ACgqTF6YPAIUCAA0ACgqTF6YPAIUCAA4ACAqBGCkhACMCAA8ABgqOCpcNAH4AAAAA.',
Fo='Focaccia:BAAANQADCggJCQAAAA==.Foxthisup:BAAANQAECgMIBgABNQAECggIDwAQAAAAAA==.',
Gl='Glasscannon:BAAANQAECgQIBAAAAA==.',
Go='Goldmoorn:BAEANQAFFAEIAQAAAA==.',
Gr='Granuaile:BAAANQAECgUIDgAAAA==.',
Gu='Gula:BAAANQADCgYJBgAAAA==.Guldude:BAAANQADCgUIBQABNQAECggIHAARAIsTAA==.',
Gw='Gwenianna:BAAANQADCgEIAQABNQAECgkJIwAJAEQYAA==.Gwenquaya:BAABNQAECn8jAAIJAAkKRBjhSAA/AgAJAAkKRBjhSAA/AgAAAA==.',
Ho='Hockeydruid:BAAANQAECgEIAQABNQAECgcIHAAGABMUAA==.Hockeyhunter:BAABNQAECn8cAAIGAAcKExS1gwAFAgAGAAcKExS1gwAFAgAAAA==.Hoewhrmymoni:BAAANQABCgcICAAAAA==.Hoistbro:BAAANQAECgUICAAAAA==.Holydps:BAAANQADCgQIBwAAAA==.',
Hu='Huntdrath:BAAANQAECgEIAgAAAA==.Hunthunthunt:BAABNQAECn8nAAIGAAoKmhGqVQBxAgAGAAoKmhGqVQBxAgAAAA==.',
['Hè']='Hèxen:BAAANQABCgcIBwAAAA==.',
Ic='Ichaival:BAAANQAECgQIDQABNQAECgoKHgASAAsNAA==.',
Ir='Irox:BAAANQADCgYIAQAAAA==.',
Je='Jedem:BAAANQADCgUICwAAAA==.',
Ka='Kazu:BAAANQAECgcIDgAAAA==.Kazum:BAAANQAECgMIBgAAAA==.',
Ke='Keralan:BAABNQAECn8fAAITAAkKniW3AADMAwATAAkKniW3AADMAwAAAA==.',
Ki='Kimk:BAAANQADCgMIAwAAAA==.',
Kj='Kjevoke:BAAANQAECggIAgAAAA==.',
Kl='Klhank:BAAANQADCgEIAQAAAA==.',
Ko='Kosuke:BAAANQAECgQIBwAAAA==.',
Kr='Kromwel:BAABNQAECn8nAAIUAAgKuSGPBQAaAwAUAAgKuSGPBQAaAwAAAA==.',
Ky='Ky:BAAANQADCgUIDAAAAA==.',
La='Laizee:BAABNQAECn8qAAIJAAgKcgroigBuAQAJAAgKcgroigBuAQAAAA==.Latrice:BAAANQAECgMIBQAAAA==.Laveyan:BAEANQADCgcIBwABNQAFFAEIAQAQAAAAAA==.',
Le='Lezal:BAAANQAECggIAgAAAA==.',
Li='Liquidnitro:BAAANQAECgQIBQAAAA==.Livsfara:BAAANQADCgUIBQABNQAECgkJHgAUAMsXAA==.',
Lo='Lone:BAAANQAECgQIBQABNQAECgkJGwAVAKYfAA==.',
Lu='Lucyreborn:BAAANQAECgUIBwAAAA==.',
Ly='Lyam:BAAANQADCgEIAQAAAA==.Lylboo:BAAANQAECgMIBAAAAA==.',
Ma='Mansamusa:BAAANQAECgIIAgAAAA==.Mawikiea:BAAANQADCgIIAwABNQAECgoKLwAEALUbAA==.',
Me='Melander:BAABNQAECn8eAAMUAAkKyxebDQBYAgAUAAgKMRubDQBYAgAWAAgKtQx+yABnAQAAAA==.Meltman:BAAANQAECgEIAQAAAA==.',
Mh='Mhoram:BAAANQABCgYIBgAAAA==.',
Mi='Micur:BAAANQAECgYICwAAAA==.Mightborne:BAAANQAECggIDwAAAA==.Mike:BAAANQADCgEIAQAAAA==.',
Mo='Morbus:BAAANQAECgIIAgAAAA==.Mordracon:BAABNQAECn8WAAIUAAgKUBiHEAAgAgAUAAgKUBiHEAAgAgAAAA==.',
My='Myth:BAABNQAECn9KAAMXAAoKgxgbBQBVAQACAAoKCxcpZQC0AgAXAAUKYRwbBQBVAQAAAA==.',
Na='Nami:BAABNQAFFH8GAAMVAAQKcgboBgDaAAAVAAQKBAToBgDaAAAYAAEK2ApACQBKAAAAAA==.Nazareths:BAAANQABCgEIAQAAAA==.',
Ne='Nelflander:BAAANQAECgMIAwABNQAECgkJHgAUAMsXAA==.Nemble:BAAANQABCgYIFAAAAA==.',
Og='Ogou:BAABNQAECn8cAAQRAAgKixPFPQAKAgARAAgKixPFPQAKAgAZAAUKEQu/WAClAAAFAAIKvAX2ZwAmAAAAAA==.',
Om='Omnimage:BAAANQAECgQIDgAAAA==.',
On='Onyxz:BAABNQAECn8rAAIRAAgK1hnFDAB6AQARAAgK1hnFDAB6AQAAAA==.',
['Où']='Oùtcast:BAAANQABCggICgAAAA==.',
Pa='Panla:BAAANQADCgQIBAAAAA==.Patrickstâr:BAAANQAECggIDgAAAA==.',
Po='Pollywag:BAAANQADCgMIAwAAAA==.',
Pr='Promethus:BAAANQAECgYICgAAAA==.',
Ra='Raedaldra:BAABNQAECn8uAAQaAAoKMxzQFQCvAgAaAAgKkRzQFQCvAgAbAAQKcxCSEwDvAAAEAAUKVxWdZwCeAAAAAA==.Raggnarr:BAACNQAFFH8IAAMWAAQKTxbFGwA1AQAWAAQKsg/FGwA1AQAcAAIKGRRnAwCVAAA1AAQKfy4AAxwACgr3HmIDACMDABwACQoaImIDACMDABYABQrMF8QzAEMBAAAA.Ragnaroc:BAAANQABCgEIAQAAAA==.Rainesagé:BAACNQAFFH8GAAIEAAMKBQZ+IgDNAAAEAAMKBQZ+IgDNAAA1AAQKfyAAAgQACgo5FblAAGgCAAQACgo5FblAAGgCAAAA.Ranar:BAABNQAECn8eAAISAAoKCw0rCQCyAQASAAoKCw0rCQCyAQAAAA==.',
Re='Remiel:BAAANQADCgUIBQAAAA==.Renatnom:BAAANQAECgQIDwAAAA==.Reäper:BAAANQABCgIIBgAAAA==.',
Ri='Rimlin:BAAANQADCgYIDAAAAA==.Rishu:BAAANQABCgUIBQAAAA==.Rizzhashira:BAABNQAECn8eAAIBAAkKAByYFQBTAgABAAkKAByYFQBTAgAAAA==.',
Ro='Ronji:BAAANQADCgEIAQAAAA==.Rowge:BAABNQAECn8bAAIVAAoKIhn8BgAOAwAVAAoKIhn8BgAOAwAAAA==.Rox:BAAANQABCgQIDgAAAA==.',
Ry='Rythevia:BAABNQAECn81AAMdAAoK8hafCwCtAgAdAAoK8hafCwCtAgAeAAcK4RRMDACTAQAAAA==.',
Sa='Sadgirls:BAABNQAECn8kAAMKAAoKvh9NAQDnAgAKAAoKvh9NAQDnAgALAAEKAAAWzQBSAAAAAA==.Sandoriel:BAAANQABCgIIAwAAAA==.Satanickk:BAABNQAECn8VAAMaAAgKrBZUIwAXAgAaAAgKrBZUIwAXAgAbAAEK9gRPKwAuAAAAAA==.Satanos:BAAANQAECgEIAQAAAA==.',
Sc='Scora:BAAANQABCgEIAgAAAA==.',
Sh='Shadowraven:BAAANQADCggIBwAAAA==.Shamshamsham:BAABNQAECn8aAAIHAAkK0wzOcwDGAQAHAAkK0wzOcwDGAQABNQAECgoKJwAGAJoRAA==.',
Sk='Skillz:BAAANQABCgIIAgAAAA==.',
Sl='Slamcheeks:BAAANQAECgQIBAAAAA==.',
Sn='Sneakybeef:BAAANQADCgYIBgABNQAECgkJHgAUAMsXAA==.Snikit:BAAANQAECgQIBAABNQAECgkJHgAUAMsXAA==.',
So='Sojourner:BAAANQAECgcIEgAAAA==.',
Sp='Speedy:BAAANQADCgEIAQABNQAECgcIHAAGABMUAA==.Spellstyle:BAABNQAECn8VAAMCAAkKEhYp5QC/AQACAAgKGxYp5QC/AQAXAAEK3hU1PwBGAAAAAA==.',
St='Stimpack:BAAANQAECggICAAAAA==.',
Su='Sundaystyle:BAAANQAECgQIBgABNQAECgkJFQACABIWAA==.Superfire:BAAANQAECgQIBAAAAA==.Superspam:BAABNQAECn8fAAMZAAgK6yBQNAB4AQAZAAQKoCFQNAB4AQARAAgKBBpDEQBPAQAAAA==.',
Sy='Sylphiett:BAABNQAECn8rAAICAAoKqhC5aQDpAAACAAoKqhC5aQDpAAABNQAFFAMIBQAdAD4EAA==.',
Te='Teinaras:BAABNQAECn8mAAIIAAoKyRjXGACQAgAIAAoKyRjXGACQAgAAAA==.',
Th='Thefloydster:BAAANQAECgEIAQAAAA==.Thistledewit:BAAANQAECggIEgAAAA==.',
Ti='Tinydragon:BAACNQAFFH8FAAIdAAMKPgSYCgCvAAAdAAMKPgSYCgCvAAA1AAQKfycAAh0ACQowFB4RAEMCAB0ACQowFB4RAEMCAAAA.Tinyvoid:BAABNQAECn8XAAIfAAoK/BVTGgCGAgAfAAoK/BVTGgCGAgABNQAFFAMIBQAdAD4EAA==.Tirok:BAAANQADCgMIAwAAAA==.',
To='Togdumburz:BAABNQAECn8iAAMgAAkKURr7QwCGAgAgAAgKaBr7QwCGAgAhAAEKxBl7agBMAAAAAA==.Tortillalock:BAAANQADCgEIAQAAAA==.',
Ty='Tyberth:BAAANQABCgIIBAAAAA==.Typhon:BAABNQAECn8bAAMJAAoK+xnNKQC8AgAJAAoK+xnNKQC8AgAHAAEKCwVlQAEuAAAAAA==.',
Ud='Udderlymad:BAAANQADCggIBwABNQAECggIDwAQAAAAAA==.',
Un='Undeåd:BAAANQAECgQIBgAAAA==.',
Va='Vaelhyra:BAAANQAECgIIAgABNQAECgkJHwATAJ4lAA==.Vameera:BAAANQAECgEIAQAAAA==.',
Ve='Velirine:BAABNQAECn8gAAIXAAcKFxs8CQBDAgAXAAcKFxs8CQBDAgAAAA==.',
Vi='Vietsham:BAAANQAECgYIBgAAAA==.Vilkas:BAACNQAFFH8GAAIIAAYKwgchDQBtAQAIAAYKwgchDQBtAQA1AAQKfxcAAggACQqbGZcXAJwCAAgACQqbGZcXAJwCAAE1AAQKCgobAB8AUB4A.',
Vo='Vokevokevoke:BAAANQADCgYICAABNQAECgoKJwAGAJoRAA==.Vorpalite:BAAANQADCgYIBgAAAA==.',
Wa='Warspite:BAAANQADCgIIAgABNQAECggIKwARANYZAA==.Warwarwar:BAABNQAECn8fAAQUAAgKGgyfEAC2AAAUAAgKGQufEAC2AAAcAAQKzwWZIgChAAAWAAUKYQJCIwGTAAABNQAECgoKJwAGAJoRAA==.',
Wo='Wolffangfist:BAAANQADCgEIAQAAAA==.',
['Xä']='Xänthe:BAABNQAECn8vAAMEAAoKtRtdJADbAgAEAAoKtRtdJADbAgAaAAEK2gZhfwAsAAAAAA==.',
Yo='You:BAAANQADCgUIBgABNQAECgcIHAAGABMUAA==.',
Za='Zarron:BAAANQADCgUIBQAAAA==.',
Zi='Zife:BAACNQAFFH8MAAIOAAQKSyUFBgCyAQAOAAQKSyUFBgCyAQA1AAQKfykAAg4ACgoPJukHAFEDAA4ACgoPJukHAFEDAAAA.',
Zu='Zultarra:BAAANQADCgcIHQAAAA==.',
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
