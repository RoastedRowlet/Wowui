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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Protection','Warrior-Arms','Paladin-Protection','Unknown-Unknown','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Rogue-Outlaw','Rogue-Subtlety','Mage-Frost','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Priest-Holy','Monk-Brewmaster','Priest-Shadow','Evoker-Devastation','Druid-Restoration','Evoker-Preservation','DemonHunter-Vengeance','Paladin-Holy','Warrior-Fury',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-10-13',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAABNQAECn8wAAIBAAkKgCDjHgBGAwABAAkKgCDjHgBGAwAAAA==.',
Am='Amádeus:BAAANQAECgEIAQABNQAECgkJIAACAMAdAA==.',
An='Andezard:BAABNQAECn8YAAIDAAcKnhJQlADcAQADAAcKnhJQlADcAQAAAA==.Angelys:BAAANQADCgYJCQAAAA==.',
Ap='Aphrobitey:BAAANQAECgMIBAABNQAECggIGwAEAO4KAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggJEAAAAA==.',
At='Athenaowl:BAAANQADCggIEQAAAA==.',
Ay='Ayanoriko:BAABNQAECn8qAAIFAAkKsSLfCABIAwAFAAkKsSLfCABIAwAAAA==.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQADCgYICQAAAA==.Babynick:BAAANQADCggICAAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFH8JAAMGAAMKTh7lHQAFAQAGAAMK6hzlHQAFAQAHAAEKARaoGwBPAAA1AAQKfzEAAwYACQqQI/kcAA4DAAYACAqzI/kcAA4DAAcABwr1Gi0SAOIBAAE1AAUUBQgOAAgAxCAA.',
Bi='Bigsharder:BAAANQAECgMIBgABNQAFFAcIEwAJABslAA==.Bigstones:BAABNQAECn8iAAIKAAkKPww5nADRAQAKAAkKPww5nADRAQAAAA==.',
Bl='Blacksavior:BAABNQAECn8gAAILAAkKphgJFABiAgALAAkKphgJFABiAgAAAA==.Blindbone:BAAANQADCggICAABNQAECgkJJgAEAEEdAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgUICAAAAA==.Bluehydra:BAAANQADCggICAAAAA==.Bluepocalyps:BAAANQADCgYIFAAAAA==.',
Bo='Bobbydigital:BAABNQAECn8bAAIIAAgKPhCbVgCWAQAIAAgKPhCbVgCWAQAAAA==.Bolas:BAAANQAECgYIEAAAAA==.Bopchop:BAAANQADCggICAABNQAECgEIAQAMAAAAAA==.Bowookie:BAAANQAECggICAAAAA==.',
Br='Bracynn:BAAANQAECgQIBwAAAA==.',
Bu='Bunnah:BAAANQABCgIIAgAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.',
Ce='Cealia:BAABNQAECn8nAAINAAgKthHEwQD/AQANAAgKthHEwQD/AQAAAA==.Cephalo:BAAANQADCggJEwAAAA==.',
Ch='Chakuneeai:BAAANQAECgUIBQAAAA==.Chancleta:BAAANQAECgQIBAAAAA==.Christae:BAAANQAECgUICwAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAABNQAECn8gAAICAAkKwB3ZHQDzAgACAAkKwB3ZHQDzAgAAAA==.',
Co='Compromised:BAABNQAECn8nAAMOAAkK+BqhGgDCAgAOAAkK+BqhGgDCAgAPAAYKqxAsOQB2AQAAAA==.Connalious:BAAANQAECgEIAQAAAA==.',
Cr='Crwth:BAAANQAECgQIEAAAAA==.',
Cu='Curendae:BAAANQAECgUIEQAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Dabaldzombie:BAAANQABCgIIAgABNQAFFAMICwAOACMSAA==.Danika:BAAANQAECgEIAQABNQAECgkJJgAQADwhAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUIDgAAAA==.Daxzazi:BAAANQAECgQIBwAAAA==.',
De='Decillian:BAAANQAECgYIEgAAAA==.Delicious:BAEANQAECggIDwABNQAFFAUICgAKADYSAA==.Dern:BAAANQAECgUIDwAAAA==.Desolit:BAABNQAECn8YAAIPAAcKKR1aIQA+AgAPAAcKKR1aIQA+AgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAABNQAECn8XAAMRAAkKYhYrBgBzAgARAAkKYhYrBgBzAgASAAIK3g9+RQCEAAAAAA==.',
Do='Docvader:BAAANQAECgEIAQAAAA==.',
Dr='Drunkenhealz:BAAANQAECgUIEwAAAA==.Drunks:BAAANQAECgIJAgAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAAANQAECgUIDgAAAA==.',
Er='Erosis:BAABNQAECn8mAAMNAAkKVyUYCwCqAwANAAkKVyUYCwCqAwATAAEKAhBnSgAvAAAAAA==.',
Es='Esidh:BAAANQAECgcIBAABNQAECggIDwAMAAAAAA==.Esidk:BAAANQAECggIDwAAAA==.Esimage:BAAANQAECgMIAwABNQAECggIDwAMAAAAAA==.',
Ex='Exgirlfriend:BAAANQADCggIDAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECggIFwATAGAPAA==.Ezrin:BAAANQAECgQIBwAAAA==.',
Fe='Fear:BAABNQAECn8ZAAMGAAkK3R30TgBkAgAGAAgKdR70TgBkAgAHAAEKTBpecAA+AAAAAA==.Felysria:BAAANQADCgYIBgAAAA==.',
Fr='Frequency:BAEANQAECgUIBwABNQAECgUICwAMAAAAAA==.Frizzer:BAAANQADCggIDQAAAA==.',
Ga='Gakopozy:BAAANQADCggIFwAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grimlokke:BAAANQAECgEIAQABNQAECggIFwATAGAPAA==.',
['Gé']='Géne:BAAANQAECgUIBQABNQAECgkJIAACAMAdAA==.',
Ha='Harbard:BAAANQAECgQICAAAAA==.Havrin:BAABNQAECn89AAMUAAgKBRrmDwBdAgAUAAgKBRrmDwBdAgAVAAEKAADsPwA3AAAAAA==.',
He='Headhûnter:BAAANQAECgMIAwAAAA==.Headshots:BAAANQADCgQIBAABNQAECgkJMAABAIAgAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hew:BAAANQAECgQIBQABNQAECgkJFwARAGIWAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFH8OAAQIAAUKxCCTDwBWAQAIAAQKwB6TDwBWAQAWAAMKiyUUDwAWAQAXAAEKFiEQGgBdAAA1AAQKfz0ABAgACQqwJvMIAHEDAAgACAp6JvMIAHEDABYACApVI0EaAO0CABcABgoRJBEsADgCAAAA.',
Hu='Huamulan:BAABNQAECn8gAAIBAAcK3gMjBgEOAQABAAcK3gMjBgEOAQAAAA==.',
Ib='Ibchilling:BAABNQAECn8cAAINAAgKohFLxQD4AQANAAgKohFLxQD4AQAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAABNQAECn85AAMYAAkKAyITBABpAwAYAAkKAyITBABpAwAQAAEKAAB6cQAmAAABNQAECgUIBwAMAAAAAA==.Iccarus:BAABNQAECn8pAAMCAAkK/x8BDgBQAwACAAkK/x8BDgBQAwAEAAEKAAAbLgE3AAABNQAECgUIBwAMAAAAAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQADCgUICQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAAANQAECggIEAABNQAECgkJJgAEAEEdAA==.Jaskim:BAABNQAECn8bAAIXAAcKyAavXgAjAQAXAAcKyAavXgAjAQAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgcIGwAXAMgGAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgEIAwAAAA==.',
Ka='Kaffee:BAAANQADCgUIBQAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAABNQAECn8iAAIZAAkKMyN5CAB+AwAZAAkKMyN5CAB+AwAAAA==.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAABNQAECn8eAAINAAgKZxv1hgBwAgANAAgKZxv1hgBwAgAAAA==.Katbeans:BAABNQAECn8kAAMaAAcKPSIsBwDKAgAaAAcKPSIsBwDKAgAQAAIKCBK/WAB+AAAAAA==.Kathrynne:BAAANQAECgUJDAAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Katpuffs:BAAANQADCgEIAQAAAA==.Kaykoh:BAABNQAECn8ZAAMWAAkKjiKZBwCGAwAWAAkKjiKZBwCGAwAIAAIKxRnDpwB+AAAAAA==.',
Ke='Kelicemoon:BAABNQAECn8iAAMGAAgKsQuGkwCwAQAGAAgKsQuGkwCwAQAHAAMKXAEhawBJAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIAwABNQAECgUIDgAMAAAAAA==.',
Ki='Kiara:BAAANQAECgIIAQAAAA==.',
Kl='Kloner:BAAANQADCgIIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgUIEwAAAA==.',
['Kû']='Kûrr:BAAANQAECgQIAwABNQAECgkJIAACAMAdAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgYICAAAAA==.Laxeron:BAAANQAECgUIDgAAAA==.',
Le='Leotherassy:BAAANQADCggIDQAAAA==.',
Lo='Lodehavoc:BAAANQADCgcIHgAAAA==.Longboneman:BAAANQAECgUICQABNQAECgkJJgAEAEEdAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAABNQAECn8wAAIBAAkK3h3XKAAhAwABAAkK3h3XKAAhAwAAAA==.Lynthirae:BAABNQAECn8qAAIFAAgKTRgdJABjAgAFAAgKTRgdJABjAgAAAA==.',
Ma='Madpearl:BAABNQAECn8bAAIEAAgK7goEfQCpAQAEAAgK7goEfQCpAQAAAA==.',
Mc='Mcbodhran:BAAANQAECgYIEAAAAA==.Mcfeast:BAABNQAECn8aAAIbAAgKnBjgGwBkAgAbAAgKnBjgGwBkAgAAAA==.',
Me='Medra:BAAANQAECgUIDwAAAA==.Melidoria:BAAANQADCggIDQABNQAECgkJIwAcACkTAA==.Meowdi:BAAANQADCgcIIAAAAA==.',
Mi='Milou:BAABNQAECn8XAAMTAAgKYA+eEgB7AQANAAgKLw1W3gDIAQATAAcKxw2eEgB7AQAAAA==.Minibone:BAABNQAECn8fAAIKAAkK2xWkVwCBAgAKAAkK2xWkVwCBAgABNQAECgkJJgAEAEEdAA==.Mixr:BAAANQADCgEIAQAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Monana:BAAANQADCgYIHQAAAA==.Moonwolf:BAAANQADCgMIAwAAAA==.',
Mu='Mummrak:BAAANQADCgEIAQAAAA==.',
My='Mysticwood:BAABNQAECn8mAAIEAAkKQR3cIAAFAwAEAAkKQR3cIAAFAwAAAA==.',
Na='Nadjá:BAAANQAECgYICwAAAA==.Nanija:BAAANQADCgcIIAAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAAANQAECgcIDQAAAA==.',
Ni='Nightcat:BAABNQAECn8jAAIdAAgK7hrpFgCGAgAdAAgK7hrpFgCGAgAAAA==.Nitestorm:BAABNQAECn8XAAIEAAcK5h/rSQBLAgAEAAcK5h/rSQBLAgAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAAANQAECgcICgAAAA==.',
Og='Ogwarshock:BAABNQAECn8kAAMHAAkKLSNvDQAhAgAHAAUKVyVvDQAhAgAGAAYKyhrCgADgAQAAAA==.',
Ol='Oliiver:BAABNQAECn8oAAIDAAgKyR44MQDXAgADAAgKyR44MQDXAgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAAANQAECgcIDgABNQAECggIFwATAGAPAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Panaceus:BAABNQAECn8qAAIeAAkKYBygCgD4AgAeAAkKYBygCgD4AgAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgcICwAMAAAAAA==.',
Ph='Phrequency:BAEANQAECgUICwAAAA==.',
Pl='Plazmaglaive:BAAANQAECgQICAAAAA==.',
Po='Poisonóus:BAABNQAECn8WAAIIAAgKDxo5RgDeAQAIAAgKDxo5RgDeAQAAAA==.Polywóg:BAAANQADCgUICQAAAA==.Polyxo:BAAANQAECgQIDQAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Pricker:BAAANQAECgUIBQABNQAECgkJJgAEAEEdAA==.Prépared:BAACNQAFFH8LAAIOAAMKIxLdEQDQAAAOAAMKIxLdEQDQAAA1AAQKfx4AAw4ACQqHGo4yABICAA4ACAqHGo4yABICAB8AAQoAAN4zACkAAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radicchio:BAAANQADCgYIGAAAAA==.Radkeem:BAAANQAECgcIEwAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECgcIEwAMAAAAAA==.Raya:BAAANQAECgMIBwABNQAECgQIBgAMAAAAAA==.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAABNQAECn8eAAMgAAkK6xIOQwBWAgAgAAkK6xIOQwBWAgABAAQKKgrGNwHAAAAAAA==.',
Ro='Roejawb:BAABNQAECn8aAAIEAAcKoAbXrgAxAQAEAAcKoAbXrgAxAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgMIBAAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQAMAAAAAA==.',
Sa='Sableanne:BAAANQADCgYICgAAAA==.Sacon:BAAANQADCgYICgABNQAECgQIBAAMAAAAAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECn8iAAMgAAgKMhnmRABPAgAgAAgKMhnmRABPAgALAAIKlRJjVgCDAAAAAA==.Salorll:BAAANQAECgMIAwAAAA==.Savia:BAAANQADCgQIBAABNQADCggIDAAMAAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECn8mAAMbAAkKXCGCCQBFAwAbAAkKXCGCCQBFAwAZAAUKShXIkABfAQABNQAFFAUIDgAIAMQgAA==.',
Se='Senza:BAAANQAECgQICAAAAA==.Senzyri:BAABNQAECn8oAAIDAAgKIQ5XgwACAgADAAgKIQ5XgwACAgAAAA==.',
Sh='Shadyscales:BAACNQAFFH8IAAIRAAMKaQz+AQDjAAARAAMKaQz+AQDjAAA1AAQKfy8AAhEACQprF3YGAGYCABEACQprF3YGAGYCAAAA.Shenro:BAABNQAECn8XAAIBAAcKGwxt1gBoAQABAAcKGwxt1gBoAQAAAA==.Shierà:BAAANQADCgcIBwABNQAECgQIBgAMAAAAAA==.',
Si='Simic:BAAANQADCgcIEwAAAA==.Sinnori:BAAANQABCggICwAAAA==.',
Sm='Smiddy:BAAANQAECgcIEwAAAA==.',
So='Souldrains:BAAANQADCgYICQAAAA==.Soyjak:BAABNQAECn8bAAMZAAgK1Q+fbQDQAQAZAAgK1Q+fbQDQAQAbAAEKAADIjAAcAAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.Spinner:BAAANQADCgMIAwAAAA==.Spudpal:BAAANQADCggICAABNQAECgkJIgAZADMjAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAAANQAECgUIDAAAAA==.',
Su='Suraisu:BAABNQAECn8pAAMhAAgKeSGkAwAWAwAhAAgKeSGkAwAWAwAKAAIK8A23LAFzAAAAAA==.',
Sv='Sveela:BAABNQAECn8vAAIUAAkKHiRSAgCoAwAUAAkKHiRSAgCoAwAAAA==.Sveelaa:BAABNQAECn8sAAIDAAkKpCHiDgBqAwADAAkKpCHiDgBqAwABNQAECgkJLwAUAB4kAA==.Sveella:BAAANQAECgYIEAABNQAECgkJLwAUAB4kAA==.',
Sy='Syda:BAAANQADCgYIBgAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECn8qAAIZAAgKTx1zMgCbAgAZAAgKTx1zMgCbAgAAAA==.',
Te='Temlock:BAABNQAECn8YAAIGAAgKhxESeQD0AQAGAAgKhxESeQD0AQAAAA==.Temtank:BAAANQAECgQIBwABNQAECggIGAAGAIcRAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.',
To='Toes:BAAANQAECgUICQAAAA==.',
Tr='Tralyn:BAAANQABCgQIBAAAAA==.Trukarak:BAAANQAECgUIDwAAAA==.Trusturheals:BAAANQADCgQIBAAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
Ve='Veepwakeup:BAAANQAECggIBwABNQAFFAgIBAAMAAAAAA==.',
['Và']='Vàlor:BAAANQAECgYIDwAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAAANQAECgUIEQAAAA==.Wildtail:BAAANQADCgcIDAAAAA==.Windle:BAAANQADCggICgAAAA==.Windseer:BAAANQADCgYICwABNQAECgkJMAABAIAgAA==.',
Xa='Xarríøn:BAAANQADCgUIBwABNQAFFAMICAABALAVAA==.',
Xh='Xhadowz:BAAANQAECgcIDAAAAA==.',
Xi='Xiao:BAABNQAECn8nAAMYAAgK1A15HwCQAQAYAAgK1A15HwCQAQAQAAUKugiVSADYAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.Xingferat:BAAANQAECgQIBAAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAFFAMICAABALAVAA==.',
Ya='Yahargul:BAABNQAECn8gAAIbAAYK3g5HOQBYAQAbAAYK3g5HOQBYAQAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCgYIGgAAAA==.Zaradin:BAAANQAECgQIBAABNQAECgUIDgAMAAAAAA==.',
Ze='Zeik:BAABNQAECn8pAAILAAgKQyCZCwDeAgALAAgKQyCZCwDeAgAAAA==.Zellspell:BAAANQADCggICAABNQAFFAQICwAEAI4ZAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Àl']='Àlcàrà:BAAANQAECgQIBgAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgUICwAAAA==.',
['Ÿa']='Ÿamar:BAAANQAECgMIAwAAAA==.',
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
