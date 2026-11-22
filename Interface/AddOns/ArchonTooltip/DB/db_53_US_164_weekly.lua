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

local lookup = {'DeathKnight-Unholy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Evoker-Preservation','Shaman-Restoration','Paladin-Holy','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Devastation','Priest-Holy','Unknown-Unknown','Warrior-Protection','Druid-Guardian','Mage-Arcane','Mage-Frost','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','Shaman-Elemental','Paladin-Protection','Warrior-Fury','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adicia:BAABNQAECn8nAAIBAAcKbgnqQwD8AAABAAcKbgnqQwD8AAAAAA==.',
Ae='Aedercy:BAAANQABCggIHwAAAA==.Aestel:BAAANQABCgYIBQAAAA==.',
Al='Alarus:BAAANQAECgUICwAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAABNQAECn82AAICAAoKVx8gDwAAAwACAAoKVx8gDwAAAwAAAA==.Alynara:BAAANQADCgcIBwABNQAECgoKIwADALgMAA==.',
Am='Ambrozyn:BAAANQAECgUICwAAAA==.',
An='Anarariellea:BAAANQADCggJDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIJAgABNQAECgcIJgAEAOwIAA==.',
Aq='Aqari:BAABNQAECn8aAAIFAAgKdhyoCQCiAgAFAAgKdhyoCQCiAgAAAA==.',
Ar='Araxiie:BAAANQADCgIIAgAAAA==.Ardrelar:BAAANQAECgYIDAAAAA==.',
As='Asila:BAAANQAECgMIBAAAAA==.Astar:BAAANQAECgUIBQABNQAECgoKNgAFALchAA==.Astraea:BAAANQADCggIGwABNQAECgoKUgAGAL4hAA==.',
At='Athika:BAAANQADCggIDAAAAA==.',
Au='Auria:BAAANQAECgIIAwABNQAECggIGgAFAHYcAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAABNQAECn8XAAIHAAcKVBhLYgDxAQAHAAcKVBhLYgDxAQAAAA==.',
Ba='Baddock:BAAANQAECgUICQAAAA==.Banzamakeher:BAAANQAECgQIBwAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Bella:BAAANQAECggICAAAAA==.Benjamin:BAABNQAECn8uAAIIAAoK/hIEbQC6AQAIAAoK/hIEbQC6AQAAAA==.Bernixanders:BAAANQAECgEIAQAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECggIAwAAAA==.Blazinember:BAABNQAECn8yAAIJAAoKYRGJAgDZAQAJAAoKYRGJAgDZAQAAAA==.Blockhead:BAAANQAECgIIAgAAAA==.',
Bo='Bolonmixto:BAACNQAFFH8LAAMKAAYKRQ0ADgAqAQAKAAYKRQ0ADgAqAQALAAEK0wu9IABHAAA1AAQKfz8AAwoACgpdIqgPAPkCAAoACgpdIqgPAPkCAAsAAgrgHeCHAJMAAAAA.Boop:BAABNQAECn8rAAIMAAoKCRWDBwDwAQAMAAoKCRWDBwDwAQABNQAECgoKTAANANkhAA==.Borghamer:BAAANQAECgIIAgAAAA==.Borimor:BAAANQAECggICAABNQAECgoKLQAOAIsSAA==.',
Br='Brendee:BAAANQADCgcIFgAAAA==.Bromkin:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëorn:BAAANQAECggIDgABNQAECgoKLQAOAIsSAA==.',
Ca='Calinor:BAAANQAECgEIAgAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAABNQAECn8dAAIPAAkKbwwVQQAzAQAPAAkKbwwVQQAzAQAAAA==.Cereus:BAABNQAECn82AAMFAAoKtyHRBAA8AwAFAAoKtyHRBAA8AwAQAAUK8xIsGwCSAAAAAA==.',
Ch='Chaelenge:BAAANQAECggIEQAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAABNQAECn8dAAINAAgKCAMyMwGgAAANAAgKCAMyMwGgAAAAAA==.',
Co='Coldncrispy:BAAANQAECgMIAwAAAA==.Coloratura:BAABNQAECn82AAIRAAoK1RyNMQB8AgARAAoK1RyNMQB8AgAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQAECgoKTAANANkhAA==.Crylessia:BAAANQAECgMIAwAAAA==.',
Da='Dagethon:BAAANQADCgUIEAAAAA==.Dandon:BAAANQADCgYIBgABNQAECgUIBQASAAAAAA==.Danfortesque:BAAANQADCgcIBwAAAA==.Danyah:BAAANQADCgUJBQABNQAECgoKOwATACoeAA==.Darkshådow:BAAANQAECgcIDAAAAA==.Daromiciah:BAAANQADCgYIBgAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Deftdirk:BAAANQADCgcIBwAAAA==.Delve:BAAANQADCgEIAQAAAA==.Denvoker:BAAANQAECgEIAQAAAA==.Desdeanna:BAAANQABCgIIAgAAAA==.',
Di='Dissension:BAAANQAECgYIAwAAAA==.',
Do='Donpablo:BAAANQADCgcICgAAAA==.Doubtfire:BAABNQAECn8mAAMEAAcK7AhjYgCbAAAEAAcKbQNjYgCbAAAUAAMK/A9dWgBfAAAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgcIDgABNQAECgkJPwARANsgAA==.',
Eg='Egroeg:BAAANQADCgQIBAABNQAECgUIBQASAAAAAA==.',
Ei='Einar:BAAANQAECgQIBAAAAA==.',
Er='Eraessyr:BAAANQADCgQJBAAAAA==.Eragön:BAAANQADCgUIBQAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBQAAAA==.Fangz:BAABNQAECn8vAAIIAAgKWAfjsAAYAQAIAAgKWAfjsAAYAQAAAA==.',
Fl='Flarebeard:BAAANQADCgQIBAAAAA==.',
Fo='Forsëti:BAAANQAECggIDgAAAA==.',
Fr='Freakadeëk:BAAANQAECgIIBQAAAA==.Frierenn:BAABNQAECn8hAAMVAAgK8g8uwgAAAgAVAAgK8g8uwgAAAgAWAAEKAAC7RwA0AAAAAA==.Frosh:BAAANQAECgEIAQAAAA==.',
Ga='Gadodagaps:BAAANQADCgcIBwAAAA==.',
Gh='Ghouldottie:BAAANQAECgQIBAAAAA==.',
Gi='Gilidar:BAABNQAECn87AAIIAAoK/yJfHQDRAgAIAAoK/yJfHQDRAgAAAA==.Gillarria:BAAANQADCgcIDAAAAA==.',
Gl='Glori:BAAANQADCgYIEAABNQAECgcIEAASAAAAAA==.',
Gn='Gnomerdenis:BAAANQAECgYICAAAAA==.',
Go='Goochiemon:BAAANQAECgMIAwAAAA==.',
Gr='Greenspawn:BAAANQAECggICQAAAA==.Grimmberly:BAAANQAECgUIEQABNQAECgoKHwAUAMIiAA==.Grimoire:BAABNQAECn8fAAMUAAoKwiJNCwC4AgAUAAoKwiJNCwC4AgAXAAEKDQaegQAdAAAAAA==.Gronna:BAAANQADCgYIBgABNQAECgoKNgACAFcfAA==.',
Gu='Guthunnel:BAAANQAECgUIBQAAAA==.Gutshadra:BAAANQAECgMICgAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgoKHwAUAMIiAA==.Helpmee:BAAANQAECgYIBAAAAA==.',
Ho='Hoawatt:BAAANQAECgQICgAAAA==.Holynova:BAAANQAECgEIAQABNQAECgcIHAAHAMQXAA==.Honkky:BAAANQAECgMIAgAAAA==.Hoofkick:BAAANQADCgQIBAAAAA==.Horaz:BAAANQADCgcIBwAAAA==.',
Hu='Huuch:BAABNQAECn8aAAIOAAgKEwdepgC5AQAOAAgKEwdepgC5AQAAAA==.',
Ig='Ignee:BAABNQAECn87AAMTAAoKKh6OBgCYAgATAAoKKh6OBgCYAgAIAAMKUwwDJQGOAAAAAA==.Ignia:BAAANQAECggIEQAAAA==.Igris:BAAANQADCggICAAAAA==.',
Ir='Iremoon:BAABNQAECn8oAAQBAAgKBwvlPwAQAQABAAgKBwvlPwAQAQAYAAMKjATekwB3AAAZAAMKFgThqwB3AAAAAA==.',
Je='Jestyr:BAABNQAECn8ZAAMaAAgK9CKgBAD4AgAaAAgK9CKgBAD4AgAbAAIKEgmASgBpAAAAAA==.',
Ji='Jimba:BAAANQADCgQIBAAAAA==.Jimbah:BAAANQADCgMIAwAAAA==.Jiyao:BAABNQAECn8yAAMcAAoKnxlnGwDOAQAcAAoKnxlnGwDOAQAdAAMKVwWHQQBtAAAAAA==.',
Jo='Jojinn:BAAANQAECgEIAQAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Kainarasa:BAAANQAECgYIBgABNQAECgoKTAANANkhAA==.Katarinea:BAABNQAECn8YAAIEAAkK4AaKYwBAAQAEAAkK4AaKYwBAAQAAAA==.Kaylle:BAABNQAECn8ZAAINAAoKQRPnbAD2AQANAAoKQRPnbAD2AQAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECggIEQASAAAAAA==.',
Kh='Khala:BAABNQAECn8cAAIeAAkKLgUnmwAiAQAeAAkKLgUnmwAiAQAAAA==.Khalessie:BAABNQAECn81AAIfAAoK3hP6BADYAQAfAAoK3hP6BADYAQAAAA==.',
Ki='Killa:BAAANQAECgIIAgABNQAECgoKMAAIABkjAA==.Killerfire:BAAANQAECgIIAgAAAA==.Killim:BAAANQAECgYICQAAAA==.Kirsi:BAAANQAECgEIAQAAAA==.Kiselle:BAAANQADCgQIBAABNQAECggIGgAFAHYcAA==.',
Kl='Klorick:BAABNQAECn8UAAIgAAoKOgRkfgAVAQAgAAoKOgRkfgAVAQABNQAECgoKLQAOAIsSAA==.',
Kr='Krillian:BAAANQADCggICAAAAA==.Krissa:BAAANQADCgcIBwAAAA==.',
Ku='Kungfudru:BAAANQAECgMIAwAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgoKLQAOAIsSAA==.',
Ky='Kyla:BAAANQAECgUICwAAAA==.Kyomu:BAAANQADCggICAABNQAECgoKTAANANkhAA==.',
La='Lazzarus:BAAANQAECgcICgAAAA==.',
Le='Legio:BAAANQADCgQICAAAAA==.',
Li='Lineofsight:BAABNQAECn84AAIIAAkKaw8CewCVAQAIAAkKaw8CewCVAQAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAABNQAECn8nAAIaAAgKtxCfEwBzAQAaAAgKtxCfEwBzAQAAAA==.',
Lo='Loading:BAAANQAECgEIAQABNQAECgoKLgAgAN8XAA==.Lockdarkly:BAAANQAECgYIBwAAAA==.Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQAECgQICwAAAA==.',
['Lí']='Lív:BAAANQAECgMIAwAAAA==.',
Ma='Machrona:BAAANQAECgQIBAAAAA==.Madelyn:BAAANQADCgUJBQAAAA==.Magecat:BAAANQAECgEIAQABNQAECggIEQASAAAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malena:BAEBNQAECn8VAAIeAAkKrAlTjABEAQAeAAkKrAlTjABEAQAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAABNQAECn8ZAAMWAAoKsBMNDgC1AQAWAAgKNxENDgC1AQAVAAcKvxSGhwCZAQAAAA==.Marksmann:BAAANQADCgYIBQAAAA==.',
Mc='Mcdavé:BAABNQAECn8nAAIgAAgKog4abABDAQAgAAgKog4abABDAQAAAA==.',
Me='Meerclar:BAAANQAECgUICwAAAA==.Melaila:BAABNQAECn9SAAIGAAoKviFVBwCjAwAGAAoKviFVBwCjAwAAAA==.Melysithea:BAABNQAECn8gAAIXAAoKMBK9HAAgAgAXAAoKMBK9HAAgAgABNQAECgoKUgAGAL4hAA==.',
Mi='Micheal:BAAANQAECggICAAAAA==.Midir:BAAANQAECgYIBgAAAA==.Mistymay:BAAANQADCgYJCwAAAA==.Miñitañk:BAAANQAECgUIDwAAAA==.',
Mo='Moldthinur:BAABNQAECn8sAAIhAAgK7hwTGAC4AQAhAAgK7hwTGAC4AQAAAA==.Mongrol:BAAANQAECgQIDQAAAA==.Monôpolyguy:BAABNQAECn8gAAIWAAcKbBVPFABMAQAWAAcKbBVPFABMAQAAAA==.Moonowl:BAAANQAECgQIDgAAAA==.',
Mu='Mummrakhan:BAABNQAECn8YAAIeAAcK2AMj1ACpAAAeAAcK2AMj1ACpAAAAAA==.Murraya:BAAANQAECgIIAgAAAA==.',
My='Mythdalkurim:BAAANQADCgUICgAAAA==.',
Na='Naniel:BAABNQAECn80AAMTAAoK4CIhBABNAwATAAoK4CIhBABNAwAiAAEKRg2xNAA4AAAAAA==.Nazgrefry:BAAANQAECgcIDwAAAA==.',
Ne='Neb:BAABNQAECn85AAIeAAoK9BQdRQAFAgAeAAoK9BQdRQAFAgAAAA==.Necroy:BAAANQAECggIEAAAAA==.',
Ni='Niccee:BAABNQAECn8ZAAIEAAoKxgcGYwBCAQAEAAoKxgcGYwBCAQAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgoKHAAgAEcgAA==.Noodles:BAABNQAECn8UAAINAAYKdRWUzACCAQANAAYKdRWUzACCAQAAAA==.Nosebleeds:BAAANQAECgcICwAAAA==.',
Nu='Numerotres:BAAANQADCgQIBAAAAA==.Numerouno:BAABNQAECn8cAAMHAAcKxBe0hACMAQAHAAYKLxa0hACMAQANAAYKaQWkHQG9AAAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Om='Omegasupreme:BAAANQABCgIJAgAAAA==.',
Oo='Ookthron:BAABNQAECn8mAAMIAAoK1BZ8dQCjAQAIAAoK1BZ8dQCjAQATAAMKuxILNQCNAAAAAA==.Ootred:BAAANQAECgIIAgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBwAAAA==.',
Pa='Palakin:BAAANQAECgIIAgAAAA==.Papasmurff:BAAANQAECgIIAgAAAA==.Parachute:BAAANQAECgUIDAAAAA==.Parky:BAAANQADCgUICAAAAA==.Pathald:BAAANQADCgQIBAAAAA==.',
Pe='Percival:BAABNQAECn8YAAINAAoKGxEwrwDBAQANAAoKGxEwrwDBAQAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgcIGgAjAHETAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAABNQAECn9MAAINAAoK2SEwHADwAgANAAoK2SEwHADwAgAAAA==.',
Po='Pokimane:BAAANQAECgcIBwAAAA==.',
Pr='Praxiscannon:BAABNQAECn8XAAIeAAkKkgWjowAPAQAeAAkKkgWjowAPAQAAAA==.',
Pu='Pumpshire:BAABNQAECn8mAAIQAAoK/gjGEQAcAQAQAAoK/gjGEQAcAQAAAA==.',
Pw='Pwongo:BAABNQAECn9kAAIXAAoKvSNgAgD0AwAXAAoKvSNgAgD0AwAAAA==.',
Qt='Qt:BAACNQAFFH8XAAIgAAYK2Bu5CABaAQAgAAYK2Bu5CABaAQA1AAQKfzAAAiAACgqCIn8SANcCACAACgqCIn8SANcCAAAA.',
Qu='Queue:BAAANQAECgYIEQAAAA==.Quilten:BAAANQAECgUIDgAAAA==.',
Ra='Raenii:BAABNQAECn8fAAIeAAkKLBROTQDsAQAeAAkKLBROTQDsAQABNQAECgkJPwARANsgAA==.Ramoth:BAAANQAECgcIEAAAAA==.Razelda:BAAANQAECggIDQAAAA==.',
Re='Reveya:BAAANQADCgEIAQABNQAECgoKIwADALgMAA==.',
Rh='Rhodas:BAAANQAECggIDgABNQAECgkJMQAIANIiAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQAECgUICwASAAAAAA==.Riannen:BAAANQADCgEIAQAAAA==.',
Ro='Roadwanderer:BAAANQAECgQIBwAAAA==.Robbiedrake:BAAANQAECgIIAgABNQAECgoKRQAMACIcAA==.Robbiemonk:BAABNQAECn9FAAIMAAoKIhw3BACFAgAMAAoKIhw3BACFAgAAAA==.Rodric:BAABNQAECn8ZAAINAAoKLgjNrgByAQANAAoKLgjNrgByAQABNQAECgoKLQAOAIsSAA==.',
Ru='Runetottem:BAAANQAECggIEgAAAA==.',
Rx='Rxeight:BAAANQADCgYIDAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQAECgQIDgABNQAECgUIBQASAAAAAA==.Sannith:BAABNQAECn8hAAMVAAcK5RdfywDvAQAVAAcKqxVfywDvAQAWAAEKlh5pQwA9AAAAAA==.',
Sc='Scyllia:BAABNQAECn8mAAICAAkKwBgrFwCfAgACAAkKwBgrFwCfAgAAAA==.Scârlett:BAEANQADCgUICAABNQAECgkJFQAeAKwJAA==.',
Sh='Shadowklaw:BAAANQAECgQIBwAAAA==.Shadowlich:BAAANQAECggICQAAAA==.Shamanoodles:BAABNQAECn8eAAIGAAkKjRKfUQDMAQAGAAkKjRKfUQDMAQABNQAECgoKUgAGAL4hAA==.Shespawn:BAABNQAECn8VAAMBAAoK9RBuIgDMAQABAAoK9RBuIgDMAQAZAAEKAADkyAA3AAAAAA==.Shurie:BAABNQAECn8tAAIOAAoKixKTVgAeAgAOAAoKixKTVgAeAgAAAA==.Shâdê:BAAANQAECgMJBAAAAA==.Shânk:BAAANQAECgIIAgAAAA==.',
Si='Sinae:BAAANQADCggICAAAAA==.Sindrak:BAAANQABCgYICAAAAA==.',
Sl='Slipperybop:BAABNQAECn80AAINAAkKjyHDLAAVAwANAAkKjyHDLAAVAwABNQAECgQICQASAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snakeshadow:BAAANQADCggICAAAAA==.Snazzlehorn:BAAANQAECgQIBQAAAA==.Snifflenips:BAAANQAECgUIBQAAAA==.Snoroll:BAAANQAECgEIAQAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQAECgcICwAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAABNQAECn8ZAAIVAAkKaASnrgBHAQAVAAkKaASnrgBHAQABNQAECgoKLQAOAIsSAA==.',
Sr='Srhubbabubba:BAAANQAECgQICAABNQAECggIHgARACYcAA==.',
St='Sternn:BAAANQAECgQIEgAAAA==.Straif:BAABNQAECn8fAAINAAUKDwa/OQHDAAANAAUKDwa/OQHDAAAAAA==.Strawberrÿ:BAABNQAECn8bAAINAAkKSQm00gB2AQANAAkKSQm00gB2AQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Sydonai:BAAANQAECggIDQAAAA==.Syreithada:BAAANQADCgcICQAAAA==.',
['Sì']='Sìnn:BAAANQADCgIIAwAAAA==.',
Ta='Talathra:BAABNQAECn8jAAMDAAoKuAyDJQA9AQADAAkKBAmDJQA9AQAOAAQKeg0q2wD8AAAAAA==.',
Td='Tddaddy:BAAANQADCgEIAQAAAA==.',
Te='Teddy:BAABNQAECn8bAAIUAAoKDxSEHQC1AQAUAAoKDxSEHQC1AQAAAA==.Tellah:BAEANQADCgQIBAABNQAFFAQIBgAGAGYiAA==.',
Th='Thegodofwar:BAABNQAECn8xAAIIAAkK0iJ0IQC+AgAIAAkK0iJ0IQC+AgAAAA==.Thân:BAABNQAECn8cAAMkAAkKMA6gEwD8AAAeAAgKdAy6eQBxAQAkAAUK/g+gEwD8AAAAAA==.',
Ti='Tivon:BAAANQAECgEJAQAAAA==.',
To='Tonksie:BAAANQAECgUICQAAAA==.',
Tt='Ttonkkalos:BAAANQAECgUICwAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Um:BAAANQADCgIIAgABNQAECgoKLgAgAN8XAA==.Umi:BAAANQAECggIEgAAAA==.Umzingeli:BAAANQADCggIEAAAAA==.',
Va='Varkbyte:BAAANQAECgMIAwAAAA==.Varock:BAAANQAECgIIAgABNQAECgoKTAANANkhAA==.',
Vi='Vindication:BAABNQAECn8ZAAMHAAcKyyGcJAChAgAHAAcKyyGcJAChAgANAAEKYQNOwAEoAAAAAA==.Viz:BAAANQAECgIIAwAAAA==.',
Vr='Vraul:BAABNQAECn8eAAIIAAoKrhAJqgC0AQAIAAoKrhAJqgC0AQAAAA==.',
Vu='Vulpain:BAAANQADCggIDgABNQAECgoKTAANANkhAA==.',
Vv='Vvnth:BAAANQAECgMIAwAAAA==.',
Wa='Washer:BAAANQAECgYIDwAAAA==.',
Wh='Whiteangel:BAAANQAECgEIAQAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.Willywallace:BAAANQABCgMIAwAAAA==.',
Wo='Wolfowl:BAAANQAECgEIAQAAAA==.Wolfrunner:BAAANQADCgEIAQABNQAECgoKNAATAKghAA==.Wormon:BAAANQADCggICAAAAA==.',
Xa='Xaela:BAABNQAECn8cAAIbAAkK2A0uMwCoAQAbAAkK2A0uMwCoAQAAAA==.Xannyphantom:BAAANQADCggICAAAAA==.Xarous:BAAANQAECggIDgABNQAECgoKTAANANkhAA==.',
Xi='Xiabal:BAABNQAECn8pAAMXAAoKDBkUNQByAQAXAAcKSBQUNQByAQAEAAkKARTsQgAbAQAAAA==.',
Xw='Xweakling:BAAANQADCgYICAABNQAECgoKKgAiAMQYAA==.Xweekling:BAABNQAECn8qAAIiAAoKxBgGCQBNAgAiAAoKxBgGCQBNAgAAAA==.',
Yo='Yonnà:BAAANQAECgMIAwAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAABNQAECn8ZAAIZAAcKjAk3XgDKAAAZAAcKjAk3XgDKAAAAAA==.',
Yu='Yuxiong:BAAANQAECgIIAwAAAA==.',
Ze='Zedra:BAEANQADCggIGAABNQAECgkJFQAeAKwJAA==.Zedrâ:BAEANQADCggIDAABNQAECgkJFQAeAKwJAA==.Zerostar:BAABNQAECn8gAAMOAAkKFxQ+SQA+AgAOAAkKFxQ+SQA+AgAjAAIKIAaeEABrAAAAAA==.Zevon:BAAANQAECgQIBAABNQAECgUICwASAAAAAA==.',
['Ña']='Ñaman:BAAANQAECgEIAQAAAA==.',
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
