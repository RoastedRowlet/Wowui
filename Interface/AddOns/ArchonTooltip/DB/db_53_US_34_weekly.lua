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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Protection','Warrior-Arms','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Rogue-Outlaw','Rogue-Subtlety','Priest-Holy','Mage-Frost','DeathKnight-Frost','Druid-Guardian','Druid-Restoration','Druid-Feral','DeathKnight-Unholy','Monk-Mistweaver','Priest-Shadow','Monk-Brewmaster','Warrior-Fury','Warlock-Affliction','DemonHunter-Vengeance','Paladin-Holy',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-10-20',data={Ae='Aelarion:BAAANQADCgQIBQAAAA==.',
Al='Alaponia:BAAANQADCgEIAQAAAA==.Alba:BAABNQAECn80AAIBAAoKlhysHwBFAwABAAoKlhysHwBFAwAAAA==.',
Am='Amádeus:BAAANQAECgEIAQABNQAECgoKJAACAHgdAA==.',
An='Andezard:BAABNQAECn8eAAIDAAcKnhJzlgDbAQADAAcKnhJzlgDbAQAAAA==.Angelys:BAAANQADCgYJCgAAAA==.',
Ap='Aphrobitey:BAAANQAECgMIBAABNQAECggIIgAEAP4MAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggJEQAAAA==.',
At='Athenaowl:BAAANQAECgQIBAAAAA==.',
Ay='Ayanoriko:BAACNQAFFH8GAAIFAAMKHg/GAgDvAAAFAAMKHg/GAgDvAAA1AAQKfy4AAgUACgrZIQwJAEgDAAUACgrZIQwJAEgDAAAA.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQADCgYICQAAAA==.Babynick:BAAANQAECgcICAAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFH8JAAMGAAMKTh4CHwD9AAAGAAMK6hwCHwD9AAAHAAEKARZzGwBPAAA1AAQKfzcAAwYACgq7IOwLAO8BAAYACQpxIOwLAO8BAAcABwr1GlsSAOIBAAE1AAUUBggUAAgAkR8A.',
Bi='Bigsharder:BAAANQAECgMIBgABNQAFFAcIGgAJAIslAA==.Bigstones:BAACNQAFFH8FAAIKAAIK0wE4FgBiAAAKAAIK0wE4FgBiAAA1AAQKfyYAAgoACgowCxCeANEBAAoACgowCxCeANEBAAAA.',
Bl='Blacksavior:BAABNQAECn8iAAILAAoKpBdKFABiAgALAAoKpBdKFABiAgAAAA==.Blindbone:BAAANQADCggICAABNQAECgoKKgAEAPMdAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgUICAAAAA==.Bluehydra:BAAANQADCggICAAAAA==.Bluepocalyps:BAAANQADCgYIGgAAAA==.',
Bo='Bobbydigital:BAABNQAECn8iAAIIAAgKPhDRFgAxAQAIAAgKPhDRFgAxAQAAAA==.Bolas:BAABNQAECn8UAAQMAAcKpw/dGgCVAAANAAQKfA5xLgCqAAAMAAQKtgXdGgCVAAAOAAIKpgG4TQA4AAAAAA==.Bopchop:BAAANQAECgIIAgABNQAECgUIBwAPAAAAAA==.Bowookie:BAAANQAECggICAAAAA==.',
Br='Bracynn:BAAANQAECgYIDAAAAA==.',
Bu='Bunnah:BAAANQADCgEIAQAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.',
Ce='Cealia:BAABNQAECn8vAAIQAAoKXQ88KwBuAQAQAAoKXQ88KwBuAQAAAA==.Cephalo:BAAANQADCggIFQAAAA==.',
Ch='Chakuneeai:BAAANQAECgUIBQAAAA==.Chancleta:BAAANQAECgQIBAAAAA==.Christae:BAAANQAECgYIDQAAAA==.Chronuwu:BAAANQADCgYIBwAAAA==.',
Cl='Clydè:BAAANQADCgYIDAAAAA==.Cláncey:BAABNQAECn8kAAICAAoKeB1KHgDyAgACAAoKeB1KHgDyAgAAAA==.',
Co='Compromised:BAABNQAECn8xAAMRAAoKPx7oAQC8AgARAAoKPx7oAQC8AgASAAYKqxDoOQB2AQAAAA==.Connalious:BAAANQAECgEIAQAAAA==.',
Cr='Crwth:BAABNQAECn8VAAIBAAUKUAHjdwFkAAABAAUKUAHjdwFkAAAAAA==.',
Cu='Curendae:BAABNQAECn8aAAIDAAYKDhjnQwAtAQADAAYKDhjnQwAtAQAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Dabaldzombie:BAAANQABCgIIAgABNQAFFAQIDgARACMSAA==.Danika:BAAANQAECgEIAQABNQAECgoKLwATALAhAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUIDgAAAA==.Daxzazi:BAAANQAECgQIBwAAAA==.',
De='Decillian:BAAANQAECgYIEgAAAA==.Delicious:BAEANQAECggIDwABNQAFFAUICgAKADYSAA==.Dern:BAABNQAECn8VAAICAAcKrA/sOAADAQACAAcKrA/sOAADAQAAAA==.Desolit:BAABNQAECn8aAAISAAkKKRm6IQA9AgASAAkKKRm6IQA9AgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAABNQAECn8cAAMUAAoKIBUxBgBzAgAUAAoKIBUxBgBzAgAVAAIK3g9xRgCEAAAAAA==.',
Do='Docvader:BAAANQAECgUIBgAAAA==.',
Dr='Drunkenhealz:BAABNQAECn8XAAIWAAcKhQ7JSQDpAAAWAAcKhQ7JSQDpAAAAAA==.Drunks:BAAANQAECgIJAgAAAA==.Drvargas:BAAANQAECgEIAQAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAABNQAECn8WAAIQAAYK4Q4jXQADAQAQAAYK4Q4jXQADAQAAAA==.',
Em='Emryssa:BAAANQADCgIIAgAAAA==.',
Er='Erosis:BAACNQAFFH8GAAIQAAMK5RqgCgAGAQAQAAMK5RqgCgAGAQA1AAQKfyoAAxAACgriI3ILAKgDABAACgriI3ILAKgDABcAAQoCEE1LAC8AAAAA.',
Es='Esidh:BAAANQAECgcIBAABNQAECggIFAAYACwJAA==.Esidk:BAABNQAECn8UAAIYAAgKLAkBSgCTAQAYAAgKLAkBSgCTAQAAAA==.Esimage:BAAANQAECgMIAwABNQAECggIFAAYACwJAA==.',
Ex='Exgirlfriend:BAAANQADCggIDAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECggIFwAXAGAPAA==.Ezrin:BAAANQAECgQIBwAAAA==.',
Fe='Fear:BAABNQAECn8bAAMGAAoKqB1eUABkAgAGAAkKIx5eUABkAgAHAAEKTBr0cAA+AAAAAA==.Felysria:BAAANQADCgYIBgAAAA==.',
Fr='Frequency:BAEANQAECgUIBwABNQAECgUIDAAPAAAAAA==.Frizzer:BAAANQAECgEIAgAAAA==.',
Ga='Gakopozy:BAAANQADCggIGwAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grimlokke:BAAANQAECgEIAQABNQAECggIFwAXAGAPAA==.',
['Gé']='Géne:BAAANQAECgUIBQABNQAECgoKJAACAHgdAA==.',
Ha='Harbard:BAAANQAECgQICAAAAA==.Havrin:BAABNQAECn8/AAQZAAgKBRolEABeAgAZAAgKBRolEABeAgAaAAIKJQXYNwBSAAAbAAEKAACSQQA3AAAAAA==.',
He='Headhûnter:BAAANQAECgYICQAAAA==.Headshots:BAAANQADCgQIBQABNQAECgoKNAABAJYcAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hew:BAAANQAECgQIBQABNQAECgoKHAAUACAVAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFH8UAAQIAAYKkR/7DwBVAQAIAAQKwB77DwBVAQAcAAQKwyBODwAWAQAYAAIKnxxICACdAAA1AAQKfz0ABAgACQqwJgsJAHEDAAgACAp6JgsJAHEDABwACApVI44aAO0CABgABgoRJP4sADgCAAAA.',
Hu='Huamulan:BAABNQAECn8iAAIBAAgKHgQJCgEOAQABAAgKHgQJCgEOAQAAAA==.',
Ib='Ibchilling:BAABNQAECn8eAAIQAAkK0xDixgD3AQAQAAkK0xDixgD3AQAAAA==.Ibcleaving:BAAANQADCggIDwAAAA==.',
Ic='Icarrus:BAABNQAECn88AAMdAAoKRSEgBABoAwAdAAoKRSEgBABoAwATAAEKAABdcwAmAAABNQAECgUIBwAPAAAAAA==.Iccarus:BAABNQAECn8pAAMCAAkK/x9FDgBPAwACAAkK/x9FDgBPAwAEAAEKAACCMgE2AAABNQAECgUIBwAPAAAAAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQADCgUICQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAAANQAECggIEQABNQAECgoKKgAEAPMdAA==.Jaskim:BAABNQAECn8fAAIYAAcKyAaQYAAjAQAYAAcKyAaQYAAjAQAAAA==.Jaszy:BAAANQADCgMIBAABNQAECgcIHwAYAMgGAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgEIAwAAAA==.',
Ka='Kaffee:BAAANQADCgUIBQAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAABNQAECn8oAAMWAAkKtCO3CAB+AwAWAAkKtCO3CAB+AwAeAAUKURTLFgDRAAAAAA==.Karasan:BAAANQADCgQICAAAAA==.Karenas:BAABNQAECn8gAAIQAAgKZxvphwBvAgAQAAgKZxvphwBvAgAAAA==.Katbeans:BAABNQAECn8rAAMfAAgKGSFCBwDKAgAfAAcKPSJCBwDKAgATAAMKKBUHWgB+AAAAAA==.Kathrynne:BAAANQAECgUJDAAAAA==.Katpaws:BAAANQADCgYIBwAAAA==.Katpuffs:BAAANQADCgEIAQAAAA==.Katscratch:BAAANQADCgIIAgABNQAECggIKgAaAMgdAA==.Kaykoh:BAABNQAECn8hAAMcAAoKqyGnBwCHAwAcAAoKqyGnBwCHAwAIAAIKoB+oSQBlAAAAAA==.',
Ke='Kelicemoon:BAABNQAECn8jAAMGAAkKFAualQCwAQAGAAkKFAualQCwAQAHAAMKXAGvawBJAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIBAABNQAECgUIDgAPAAAAAA==.',
Ki='Kiara:BAAANQAECgIIAQAAAA==.Kitawyn:BAAANQADCgEIAQAAAA==.',
Kl='Kloner:BAAANQADCgIIAQAAAA==.Klord:BAAANQADCgEIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgUIFgAAAA==.',
['Kû']='Kûrr:BAAANQAECgQIBAABNQAECgoKJAACAHgdAA==.',
La='Ladielayne:BAAANQADCgEIAQAAAA==.Lahrnaon:BAAANQADCgYICQAAAA==.Laxeron:BAABNQAECn8WAAIgAAYKlyMFDAD+AQAgAAYKlyMFDAD+AQAAAA==.',
Le='Leotherassy:BAAANQAECgEIAQAAAA==.',
Lo='Lodehavoc:BAAANQADCgcIJgAAAA==.Longboneman:BAAANQAECgUICQABNQAECgoKKgAEAPMdAA==.',
Lu='Lunala:BAAANQADCgEIAQABNQADCggICAAPAAAAAA==.Lusariah:BAAANQADCgYICwAAAA==.',
Ly='Lyat:BAABNQAECn83AAIBAAkK+B0UDgANAgABAAkK+B0UDgANAgAAAA==.Lynthirae:BAABNQAECn8xAAIFAAgKTRhEBQDNAQAFAAgKTRhEBQDNAQAAAA==.',
Ma='Madpearl:BAABNQAECn8iAAIEAAgK/gyVIAA5AQAEAAgK/gyVIAA5AQAAAA==.Mal:BAAANQADCgEIAQABNQAECgYIEAAPAAAAAA==.',
Mc='Mcbodhran:BAABNQAECn8WAAIBAAgKEATUDQEIAQABAAgKEATUDQEIAQAAAA==.Mcfeast:BAABNQAECn8aAAIeAAgKnBgvHABjAgAeAAgKnBgvHABjAgAAAA==.',
Me='Medra:BAABNQAECn8WAAMKAAYKTwYw6QASAQAKAAYKTwYw6QASAQAJAAIKAwM0QQA6AAAAAA==.Melidoria:BAAANQADCggIFQABNQAECgoKKwANAGwSAA==.Meowdi:BAAANQADCgcIJAAAAA==.',
Mi='Milou:BAABNQAECn8XAAMXAAgKYA/TEgB7AQAQAAgKLw2U4ADHAQAXAAcKxw3TEgB7AQAAAA==.Minibone:BAABNQAECn8hAAIKAAoK0BXRWACBAgAKAAoK0BXRWACBAgABNQAECgoKKgAEAPMdAA==.Mixr:BAAANQADCgEIAQAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Momobelfas:BAAANQADCgEIAQAAAA==.Monana:BAAANQADCgYIJQAAAA==.Moonwolf:BAAANQAECgQIBAAAAA==.',
Mu='Mummrak:BAAANQADCggICQAAAA==.',
My='Mysticwood:BAABNQAECn8qAAIEAAoK8x1BIQAFAwAEAAoK8x1BIQAFAwAAAA==.',
Na='Nadjá:BAABNQAECn8VAAIRAAkKrw45DQCFAQARAAkKrw45DQCFAQAAAA==.Nanija:BAAANQADCgcIKAAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAABNQAECn8WAAMCAAkKfRLiMQAcAQACAAkKfRLiMQAcAQAEAAEKjAWnlwAxAAAAAA==.',
Ni='Nightcat:BAABNQAECn8qAAIaAAgKyB0rBAA2AgAaAAgKyB0rBAA2AgAAAA==.Nitestorm:BAABNQAECn8bAAIEAAoKJxoKSwBKAgAEAAoKJxoKSwBKAgAAAA==.Nixstyn:BAAANQADCgEIAQAAAA==.',
No='Noala:BAAANQADCgEIAQAAAA==.Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAAANQAECggIEgAAAA==.',
Og='Ogwarshock:BAACNQAFFH8GAAMHAAMK9hkaAgCsAAAHAAIK4xwaAgCsAAAGAAEKHRSJGwBOAAA1AAQKfygABAcACgobI4YNACACAAcABQpXJYYNACACAAYABgoXHHM6ABwBACEAAQp8H0gNAF8AAAAA.',
Ok='Okote:BAAANQADCgEIAQAAAA==.',
Ol='Oliiver:BAABNQAECn8yAAIDAAoKxx1uBQB5AgADAAoKxx1uBQB5AgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAAANQAECggIEAABNQAECggIFwAXAGAPAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Panaceus:BAABNQAECn8wAAIOAAoK5B1SAwDfAQAOAAoK5B1SAwDfAQAAAA==.Patron:BAAANQADCgUIBQAAAA==.',
Pe='Perpetrator:BAAANQADCgEIAQABNQAECgYICwAPAAAAAA==.',
Ph='Phrequency:BAEANQAECgUIDAAAAA==.',
Pl='Plazmaglaive:BAAANQAECgUIDQAAAA==.',
Po='Poisonóus:BAABNQAECn8WAAIIAAgKDxoMRwDdAQAIAAgKDxoMRwDdAQAAAA==.Polywóg:BAAANQADCgUICQAAAA==.Polyxo:BAAANQAECgYIEwAAAA==.Pon:BAAANQADCgEIAQAAAA==.Pookins:BAAANQADCgEIAQAAAA==.',
Pr='Pricker:BAAANQAECgUIBQABNQAECgoKKgAEAPMdAA==.Prépared:BAACNQAFFH8OAAIRAAQKIxJGEgDQAAARAAQKIxJGEgDQAAA1AAQKfx4AAxEACQqHGiczABICABEACAqHGiczABICACIAAQoAAJE0ACoAAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
['Pö']='Pöncho:BAAANQADCgEIAQAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radicchio:BAAANQADCgYIHwAAAA==.Radkeem:BAABNQAECn8VAAIIAAgKxh4+JACXAgAIAAgKxh4+JACXAgAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECggIFQAIAMYeAA==.Ravenstone:BAAANQADCgcIDAAAAA==.Raya:BAAANQAECgQICgABNQAECgUICwAPAAAAAA==.',
Re='Reluanne:BAAANQADCggICQAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAgAAAA==.Reznor:BAABNQAECn8iAAMjAAoKZRECRABVAgAjAAoKZRECRABVAgABAAQKKgpGPAHAAAAAAA==.',
Ro='Roejawb:BAABNQAECn8aAAIEAAcKoAYRsQAxAQAEAAcKoAYRsQAxAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgUIBgAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQAPAAAAAA==.',
Sa='Sableanne:BAAANQAECgIIAwAAAA==.Sacon:BAAANQADCgYIDgABNQAECgYIEAAPAAAAAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECn8kAAMjAAkKHhmSRQBPAgAjAAkKHhmSRQBPAgALAAIKlRJrVwCCAAAAAA==.Salorll:BAAANQAECgMIAwAAAA==.Savia:BAAANQADCgQIBAABNQADCggIDAAPAAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECn8mAAMeAAkKXCGtCQBFAwAeAAkKXCGtCQBFAwAWAAUKShV3kgBfAQABNQAFFAYIFAAIAJEfAA==.',
Se='Senza:BAAANQAECgYIDQAAAA==.Senzyri:BAABNQAECn8pAAIDAAkKPA1GhQABAgADAAkKPA1GhQABAgAAAA==.',
Sh='Shadyscales:BAACNQAFFH8IAAIUAAMKaQwEAgDjAAAUAAMKaQwEAgDjAAA1AAQKfy8AAhQACQprF3kGAGcCABQACQprF3kGAGcCAAAA.Shenro:BAABNQAECn8fAAIBAAgKpgtlTQApAQABAAgKpgtlTQApAQAAAA==.Shierà:BAAANQADCgcICAABNQAECgYICwAPAAAAAA==.Shockybalboa:BAAANQADCgEIAgAAAA==.',
Si='Simic:BAAANQAECgQIBAAAAA==.Sinnori:BAAANQADCgEIAQAAAA==.',
Sm='Smiddy:BAABNQAECn8YAAMIAAgK0hTROQAfAgAIAAgKvBPROQAfAgAYAAQKUhUJcwDUAAAAAA==.',
So='Souldrains:BAAANQADCggIEgAAAA==.Soyjak:BAABNQAECn8iAAMWAAkKwxJpFgC+AQAWAAkKwxJpFgC+AQAeAAEKAACljgAcAAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.Spinner:BAAANQADCgMIAwAAAA==.Spudpal:BAAANQADCggICAABNQAECgkJKAAWALQjAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAAANQAECgUIEQAAAA==.',
Su='Suraisu:BAABNQAECn8tAAMgAAgKeSGoAwAWAwAgAAgKeSGoAwAWAwAKAAIK8A10MAFzAAAAAA==.',
Sv='Sveela:BAABNQAECn8yAAIZAAoK6SFaAgCoAwAZAAoK6SFaAgCoAwAAAA==.Sveelaa:BAABNQAECn8sAAIDAAkKpCE2DwBpAwADAAkKpCE2DwBpAwABNQAECgoKMgAZAOkhAA==.Sveella:BAAANQAECgcIEAABNQAECgoKMgAZAOkhAA==.',
Sy='Syda:BAAANQADCgYIBwAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECn8tAAIWAAkKuh1UMwCbAgAWAAkKuh1UMwCbAgAAAA==.',
Te='Temlock:BAABNQAECn8gAAIGAAgKmBH3GwCAAQAGAAgKmBH3GwCAAQAAAA==.Temtank:BAAANQAECgYICQABNQAECggIIAAGAJgRAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.',
To='Toes:BAAANQAECgUIDAAAAA==.',
Tr='Traiya:BAAANQADCgEIAQAAAA==.Tralyn:BAAANQABCgQIBAAAAA==.Trukarak:BAABNQAECn8XAAIBAAYKNg8l4gBXAQABAAYKNg8l4gBXAQAAAA==.Trusturheals:BAAANQAECgQIBAAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
Ve='Veliann:BAAANQADCgEIAQAAAA==.',
Vy='Vyktr:BAAANQAECgEIAQAAAA==.',
['Và']='Vàlor:BAAANQAECggIEQAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAABNQAECn8ZAAIaAAYKHRC3FQAVAQAaAAYKHRC3FQAVAQAAAA==.Windle:BAAANQADCggICgAAAA==.Windseer:BAAANQADCgYIDAABNQAECgoKNAABAJYcAA==.',
Xa='Xarríøn:BAAANQAECgQIBAABNQAFFAQIDAABAF0SAA==.',
Xh='Xhadowz:BAAANQAECgcIDQAAAA==.',
Xi='Xiao:BAABNQAECn8xAAMdAAoKpBCuAwDsAQAdAAoKpBCuAwDsAQATAAYKugh3SQDYAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.Xingferat:BAAANQAECgQIBAAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAFFAQIDAABAF0SAA==.',
Ya='Yahargul:BAABNQAECn8nAAIeAAcKWg7fDgAeAQAeAAcKWg7fDgAeAQAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCgYIHAAAAA==.Zaradin:BAAANQAECgQIBAABNQAECgUIDgAPAAAAAA==.Zariest:BAAANQABCgIIAgABNQAECgUIDgAPAAAAAA==.',
Ze='Zeik:BAABNQAECn8zAAILAAoKAiAKAQC3AgALAAoKAiAKAQC3AgAAAA==.Zellspell:BAAANQADCggICgABNQAFFAUIDwAEACEcAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Àl']='Àlcàrà:BAAANQAECgYICwAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgUICwAAAA==.',
['Ÿa']='Ÿamar:BAAANQAECgMIBAAAAA==.',
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
