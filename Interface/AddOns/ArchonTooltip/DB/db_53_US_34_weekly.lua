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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Protection','Warrior-Arms','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Mage-Frost','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Priest-Holy','Monk-Brewmaster','Evoker-Devastation','Druid-Restoration','Hunter-BeastMastery','Evoker-Preservation','DemonHunter-Vengeance','Paladin-Holy','Priest-Shadow','Rogue-Outlaw','Warrior-Fury',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAABNQAECoEpAAIBAAgK7h/+OgDBAgABAAgK7h/+OgDBAgAAAA==.',
An='Andezard:BAAANQAECgYIDwAAAA==.Angelys:BAAANQADCgYJCQAAAA==.',
Ap='Aphrobitey:BAAANQAECgMIBAABNQAECgYIDwACAAAAAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggJEAAAAA==.',
At='Athenaowl:BAAANQADCggIEQAAAA==.',
Ay='Ayanoriko:BAABNQAECoEkAAIDAAkKkCKOBgBVAwADAAkKkCKOBgBVAwAAAA==.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQADCgIIAwAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFIEIAAMEAAMKTh7oFgAKAQAEAAMK6hzoFgAKAQAFAAEKARaJFwBSAAA1AAQKgSoAAwQACQoaI5wnAM4CAAQACAomI5wnAM4CAAUABwqTGvYQAOgBAAE1AAUUBQgMAAYAyx8A.',
Bi='Bigsharder:BAAANQAECgMIAwABNQAFFAYIFwAHAJkdAA==.Bigstones:BAABNQAECoEeAAIIAAkKCQsciQDfAQAIAAkKCQsciQDfAQAAAA==.',
Bl='Blacksavior:BAABNQAECoEdAAIJAAgKfxkwFQAxAgAJAAgKfxkwFQAxAgAAAA==.Blindbone:BAAANQADCggICAABNQAECgkJIgAKANgcAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgQIBAAAAA==.Bluepocalyps:BAAANQADCgYIFAAAAA==.',
Bo='Bobbydigital:BAAANQAECgYIEAAAAA==.Bolas:BAAANQAECgUICwAAAA==.',
Br='Bracynn:BAAANQAECgQIBwAAAA==.',
Bu='Bunnah:BAAANQABCgIIAgAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.',
Ce='Cealia:BAABNQAECoEfAAILAAcK3g+d1QC2AQALAAcK3g+d1QC2AQAAAA==.Cephalo:BAAANQADCggJEwAAAA==.',
Ch='Chancleta:BAAANQAECgQIBAAAAA==.Christae:BAAANQAECgQICgAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAABNQAECoEaAAIMAAkKMRlMKwCSAgAMAAkKMRlMKwCSAgAAAA==.',
Co='Compromised:BAABNQAECoEhAAMNAAkKSBoGGwCeAgANAAkKlhgGGwCeAgAOAAYKehTHMgCHAQAAAA==.',
Cr='Crwth:BAAANQAECgQIDAAAAA==.',
Cu='Curendae:BAAANQAECgQIDAAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Danika:BAAANQAECgEIAQABNQAECgkJJgAPAPkhAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUICgAAAA==.Daxzazi:BAAANQAECgQIBwAAAA==.',
De='Decillian:BAAANQAECgYIEgAAAA==.Delicious:BAEANQAECggIDgABNQAFFAQICQAIAFYWAA==.Dern:BAAANQAECgQIDAAAAA==.Desolit:BAABNQAECoEVAAIOAAcKKh1PHABWAgAOAAcKKh1PHABWAgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAAANQAFFAEIAgAAAA==.',
Dr='Drunkenhealz:BAAANQAECgUIEwAAAA==.Drunks:BAAANQAECgIJAgAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAAANQAECgUICQAAAA==.',
Er='Erosis:BAABNQAECoEkAAMLAAkKlSTcCgCnAwALAAkKlSTcCgCnAwAQAAEKAhB4QwAvAAAAAA==.',
Es='Esidk:BAAANQAECggIDgAAAA==.Esimage:BAAANQAECgMIAwABNQAECggIDgACAAAAAA==.',
Ex='Exgirlfriend:BAAANQADCggIDAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECggIFwAQADMQAA==.Ezrin:BAAANQAECgQIBgAAAA==.',
Fe='Fear:BAABNQAECoEYAAMEAAkKkBzZRABnAgAEAAgK2RzZRABnAgAFAAEKTBqyagBAAAAAAA==.',
Fr='Frequency:BAEANQAECgQIBgABNQAECgUICwACAAAAAA==.Frizzer:BAAANQADCggIDQAAAA==.',
Ga='Gakopozy:BAAANQADCggIFwAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grimlokke:BAAANQAECgEIAQABNQAECggIFwAQADMQAA==.',
['Gé']='Géne:BAAANQABCgYIBgABNQAECgkJGgAMADEZAA==.',
Ha='Harbard:BAAANQAECgQJCAAAAA==.Havrin:BAABNQAECoE6AAMRAAgKgBpBDABmAgARAAgKgBpBDABmAgASAAEKhw5vNQA4AAAAAA==.',
He='Headhûnter:BAAANQADCgMIAgAAAA==.Headshots:BAAANQADCgQIBAABNQAECggIKQABAO4fAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hew:BAAANQAECgQIBQABNQAFFAEIAgACAAAAAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFIEMAAQGAAUKyx8FDQBTAQAGAAQKvx8FDQBTAQATAAMKXiCZDAAWAQAUAAEKhhsQFgBPAAA1AAQKgTUABAYACQqiJsUHAHEDAAYACAp3JsUHAHEDABMACAomI0YWAPECABQABgrOI18jAEgCAAAA.',
Hu='Huamulan:BAABNQAECoEZAAIBAAcKvgKYAwHhAAABAAcKvgKYAwHhAAAAAA==.',
Ib='Ibchilling:BAABNQAECoEcAAILAAgKRhAirQAGAgALAAgKRhAirQAGAgAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAABNQAECoExAAMVAAkKJCCEBABJAwAVAAkKJCCEBABJAwAPAAEK3wa7ZQAmAAABNQAECgUIBwACAAAAAA==.Iccarus:BAABNQAECoEiAAMMAAkKmx+PDABIAwAMAAkKmx+PDABIAwAKAAEKQhQFEQE4AAABNQAECgUIBwACAAAAAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQADCgUICQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAAANQAECgYICQABNQAECgkJIgAKANgcAA==.Jaskim:BAABNQAECoEaAAIUAAcKfgZLTwArAQAUAAcKfgZLTwArAQAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgcIGgAUAH4GAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgEIAwAAAA==.',
Ka='Kaffee:BAAANQADCgUIBQAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAABNQAECoEbAAIWAAcKUiTsIQDKAgAWAAcKUiTsIQDKAgAAAA==.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAABNQAECoEeAAILAAgKXhyPcQCFAgALAAgKXhyPcQCFAgAAAA==.Katbeans:BAABNQAECoEdAAMXAAcKPiLXBgC5AgAXAAcKPiLXBgC5AgAPAAEKoQhUYQAtAAAAAA==.Kathrynne:BAAANQAECgUJDAAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Kaykoh:BAAANQAECggIEAAAAA==.',
Ke='Kelicemoon:BAABNQAECoEgAAMEAAgKqwpHgQC2AQAEAAgKqwpHgQC2AQAFAAMKXAEFZgBKAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIAwABNQAECgUICgACAAAAAA==.',
Ki='Kiara:BAAANQAECgEIAQAAAA==.',
Kl='Kloner:BAAANQADCgIIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgUIEwAAAA==.',
['Kû']='Kûrr:BAAANQABCgIIAgABNQAECgkJGgAMADEZAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgYICAAAAA==.Laxeron:BAAANQAECgQICgAAAA==.',
Le='Leotherassy:BAAANQADCgYIBwAAAA==.',
Lo='Lodehavoc:BAAANQADCgYIHQAAAA==.Longboneman:BAAANQAECgQIBgABNQAECgkJIgAKANgcAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAABNQAECoEnAAIBAAgKih3gQgCnAgABAAgKih3gQgCnAgAAAA==.Lynthirae:BAABNQAECoEiAAIDAAgKJxbEJAA1AgADAAgKJxbEJAA1AgAAAA==.',
Ma='Madpearl:BAAANQAECgYIDwAAAA==.',
Mc='Mcbodhran:BAAANQAECgUICgAAAA==.Mcfeast:BAAANQAECgYIEQAAAA==.',
Me='Medra:BAAANQAECgQICgAAAA==.Melidoria:BAAANQADCgYIBgABNQAECgcIGwAYAEsVAA==.Meowdi:BAAANQADCgYIHwAAAA==.',
Mi='Milou:BAABNQAECoEXAAMQAAgKMxCEDwCFAQALAAgKBw0ZxgDVAQAQAAcKpA6EDwCFAQAAAA==.Minibone:BAABNQAECoEXAAIIAAgKwRD8gAD1AQAIAAgKwRD8gAD1AQABNQAECgkJIgAKANgcAA==.Mixr:BAAANQADCgEIAQAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Monana:BAAANQADCgYIHQAAAA==.',
My='Mysticwood:BAABNQAECoEiAAIKAAkK2ByuHgD4AgAKAAkK2ByuHgD4AgAAAA==.',
Na='Nadjá:BAAANQAECgUIBQAAAA==.Nanija:BAAANQADCgYIHwAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAAANQAECgYIDAAAAA==.',
Ni='Nightcat:BAABNQAECoEbAAIZAAcKLRxzGQBIAgAZAAcKLRxzGQBIAgAAAA==.Nitestorm:BAABNQAECoEXAAIKAAcKPh91PABbAgAKAAcKPh91PABbAgAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAAANQABCggIHAAAAA==.',
Og='Ogwarshock:BAABNQAECoEeAAMFAAkK7SJ+DQAVAgAFAAUKYSV+DQAVAgAEAAUKDRymkQCLAQAAAA==.',
Ol='Oliiver:BAABNQAECoEgAAIaAAgKAx6AMAC5AgAaAAgKAx6AMAC5AgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAAANQAECgcIBwABNQAECggIFwAQADMQAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Panaceus:BAABNQAECoEkAAIbAAgKgh1FDgCxAgAbAAgKgh1FDgCxAgAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgQIBQACAAAAAA==.',
Ph='Phrequency:BAEANQAECgUICwAAAA==.',
Pl='Plazmaglaive:BAAANQAECgEIAQAAAA==.',
Po='Poisonóus:BAABNQAECoEWAAIGAAgK4RibPADvAQAGAAgK4RibPADvAQAAAA==.Polywóg:BAAANQADCgUIBQAAAA==.Polyxo:BAAANQAECgQICgAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Prépared:BAACNQAFFIEIAAINAAMKwxGEDgDcAAANAAMKwxGEDgDcAAA1AAQKgR4AAw0ACQqkGZQqACICAA0ACAo8G5QqACICABwAAQrrDCQtACoAAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radicchio:BAAANQADCgYIGAAAAA==.Radkeem:BAAANQAECgcIEQAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECgcIEQACAAAAAA==.Raya:BAAANQAECgEIBAABNQAECgQIBQACAAAAAA==.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAABNQAECoEcAAMdAAkKXxDPRAA0AgAdAAkKXxDPRAA0AgABAAQKKgrwFAHFAAAAAA==.',
Ro='Roejawb:BAABNQAECoEaAAIKAAcK6QXamgAyAQAKAAcK6QXamgAyAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgMIBAAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQACAAAAAA==.',
Sa='Sableanne:BAAANQADCgYICgAAAA==.Sacon:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECoEeAAMdAAgKARibPgBMAgAdAAgKARibPgBMAgAJAAEKFhKJYQA2AAAAAA==.Salorll:BAAANQAECgMIAwAAAA==.Savia:BAAANQADCgQIBAABNQADCggIDAACAAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECoEmAAMeAAkKEiJBBwBVAwAeAAkKEiJBBwBVAwAWAAUKShUpfgBkAQABNQAFFAUIDAAGAMsfAA==.',
Se='Senza:BAAANQAECgQICAAAAA==.Senzyri:BAABNQAECoEfAAIaAAgKZwrRegDqAQAaAAgKZwrRegDqAQAAAA==.',
Sh='Shadyscales:BAACNQAFFIEFAAIfAAMKrgXVAQDOAAAfAAMKrgXVAQDOAAA1AAQKgSwAAh8ACQonFQMGAGUCAB8ACQonFQMGAGUCAAAA.Shenro:BAABNQAECoEXAAIBAAcKdgwkuQByAQABAAcKdgwkuQByAQAAAA==.Shierà:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Si='Simic:BAAANQADCgcIEwAAAA==.Sinnori:BAAANQABCggICwAAAA==.',
Sm='Smiddy:BAAANQAECgYIEQAAAA==.',
So='Souldrains:BAAANQADCgQIBAAAAA==.Soyjak:BAABNQAECoEaAAMWAAcK3RAUbwCYAQAWAAcK3RAUbwCYAQAeAAEKwgOTfgAeAAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAAANQAECgUICgAAAA==.',
Su='Suraisu:BAABNQAECoEhAAMgAAgKfiDRAwDpAgAgAAgKfiDRAwDpAgAIAAIK8A00EwF5AAAAAA==.',
Sv='Sveela:BAABNQAECoEpAAIRAAkKTiTSAQCsAwARAAkKTiTSAQCsAwAAAA==.Sveelaa:BAABNQAECoEmAAIaAAkKayGKCwBwAwAaAAkKayGKCwBwAwABNQAECgkJKQARAE4kAA==.Sveella:BAAANQAECgYIDAABNQAECgkJKQARAE4kAA==.',
Sy='Syda:BAAANQADCgYIBgAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECoEjAAIWAAgKwhnUNgBrAgAWAAgKwhnUNgBrAgAAAA==.',
Te='Temlock:BAAANQAECgYIDwAAAA==.Temtank:BAAANQAECgQIBwABNQAECgYIDwACAAAAAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.',
To='Toes:BAAANQAECgIIAwAAAA==.',
Tr='Trukarak:BAAANQAECgQICgAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
Ve='Veepwakeup:BAAANQAECggIBAABNQAFFAgIBAACAAAAAA==.',
['Và']='Vàlor:BAAANQAECgYICQAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAAANQAECgUIDAAAAA==.Wildtail:BAAANQADCgcIDAAAAA==.Windle:BAAANQADCggICgAAAA==.Windseer:BAAANQADCgYICwABNQAECggIKQABAO4fAA==.',
Xa='Xarríøn:BAAANQADCgUIBQABNQAECgkJKAABAKYgAA==.',
Xh='Xhadowz:BAAANQAECgYICwAAAA==.',
Xi='Xiao:BAABNQAECoEgAAMVAAgK1wpDHwBrAQAVAAgK1wpDHwBrAQAPAAUK/AfpPwDfAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAECgkJKAABAKYgAA==.',
Ya='Yahargul:BAABNQAECoEaAAIeAAYKKg6XNABXAQAeAAYKKg6XNABXAQAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCgYIGgAAAA==.Zaradin:BAAANQAECgMIBAABNQAECgUICgACAAAAAA==.',
Ze='Zeik:BAABNQAECoEiAAIJAAgK0h7iDACqAgAJAAgK0h7iDACqAgAAAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Àl']='Àlcàrà:BAAANQAECgIIAgAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgUICwAAAA==.',
['Ÿa']='Ÿamar:BAAANQAECgIIAgAAAA==.',
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
