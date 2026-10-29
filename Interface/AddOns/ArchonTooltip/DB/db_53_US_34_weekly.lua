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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Arms','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Rogue-Outlaw','Rogue-Subtlety','Priest-Holy','Mage-Frost','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Druid-Restoration','DeathKnight-Unholy','Monk-Mistweaver','Priest-Shadow','Monk-Brewmaster','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','Paladin-Holy','Hunter-Marksmanship',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-10-27',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAACNQAFFH8FAAIBAAIKvxTLFQCTAAABAAIKvxTLFQCTAAA1AAQKfz4AAgEACgpHIKwfAEUDAAEACgpHIKwfAEUDAAAA.',
Am='Amádeus:BAAANQAECgEIAQABNQAECgoKJQACAM8eAA==.',
An='Andezard:BAABNQAECn8eAAIDAAcKnhJzlgDbAQADAAcKnhJzlgDbAQAAAA==.Angelys:BAAANQADCgYJCQAAAA==.',
Ap='Aphrobitey:BAAANQAECgMIBAABNQAECgkJJAAEAH8MAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggJEAAAAA==.',
At='Athenaowl:BAAANQAECgUICQAAAA==.',
Ay='Ayanoriko:BAACNQAFFH8HAAIFAAQKHg+xAwDmAAAFAAQKHg+xAwDmAAA1AAQKfzQAAgUACgqrIgwJAEgDAAUACgqrIgwJAEgDAAAA.Ayasumi:BAAANQAECgEIAQAAAA==.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQAECgEIAQAAAA==.Babynick:BAAANQAECggIDwAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFH8KAAQGAAMKXh/CAgBuAAAHAAMK6hwCHwD9AAAGAAEKmSTCAgBuAAAIAAEKARZzGwBPAAA1AAQKf0IABAcACgo0IVEEACYDAAcACgr9IFEEACYDAAgABwr1GlsSAOIBAAYAAQqHI+oSAGsAAAE1AAUUBwgVAAkAfB4A.',
Bi='Bigsharder:BAAANQAECgMIBgABNQAFFAgIJQAKAMwaAA==.Bigstones:BAACNQAFFH8GAAIKAAMK0wHdIABfAAAKAAMK0wHdIABfAAA1AAQKfywAAgoACgpBDRCeANEBAAoACgpBDRCeANEBAAAA.',
Bl='Blacksavior:BAABNQAECn8iAAILAAoKpBdKFABiAgALAAoKpBdKFABiAgAAAA==.Blindbone:BAAANQADCggICAABNQAECgoKLgAEADweAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgUICAAAAA==.Bluehydra:BAAANQADCggICAAAAA==.Bluepocalyps:BAAANQADCgcIGwAAAA==.',
Bo='Bobbydigital:BAABNQAECn8oAAIJAAgKixDvMAAoAQAJAAgKixDvMAAoAQAAAA==.Bolas:BAABNQAECn8VAAQMAAgKJQ7dGgCVAAANAAUK2wtxLgCqAAAMAAQKtgXdGgCVAAAOAAIKpgG4TQA4AAAAAA==.Bopchop:BAAANQAECgcIBwABNQAECggIDwAPAAAAAA==.Bowookie:BAAANQAECggICAAAAA==.',
Br='Bracynn:BAAANQAECgYIDAAAAA==.',
Bu='Buddapalm:BAAANQAECgEIAQAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.',
Ce='Cealia:BAABNQAECn83AAIQAAoKNxDgQwDoAQAQAAoKNxDgQwDoAQAAAA==.Cephalo:BAAANQADCggIEwAAAA==.',
Ch='Chakuneeai:BAAANQAECgUICQAAAA==.Chancleta:BAAANQAECgQIBAAAAA==.Christae:BAAANQAECgYIEwAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAABNQAECn8lAAICAAoKzx5KHgDyAgACAAoKzx5KHgDyAgAAAA==.',
Co='Compromised:BAABNQAECn84AAMRAAoK7h7oCQCzAgARAAoK7h7oCQCzAgASAAYKqxDoOQB2AQAAAA==.Connalious:BAAANQAECgEIAQAAAA==.',
Cr='Crwth:BAABNQAECn8VAAIBAAUKUAHjdwFkAAABAAUKUAHjdwFkAAAAAA==.',
Cu='Curendae:BAABNQAECn8hAAIDAAcK7ha7bABfAQADAAcK7ha7bABfAQAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Dabaldzombie:BAAANQABCgIIAgABNQAFFAQIDgARACMSAA==.Danika:BAAANQAECgEIAQABNQAECgoKLwATALghAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUIDgAAAA==.Daxzazi:BAAANQAECgUICAAAAA==.',
De='Decillian:BAAANQAECgcIEwAAAA==.Delicious:BAEANQAECggIDwABNQAFFAYICwAKADYSAA==.Dern:BAAANQAFFAEIAQAAAA==.Desolit:BAABNQAECn8aAAISAAkKKRm6IQA9AgASAAkKKRm6IQA9AgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAACNQAFFH8HAAIUAAMKbxJkAADzAAAUAAMKbxJkAADzAAA1AAQKfyAAAxQACgoLGDEGAHMCABQACgoLGDEGAHMCABUAAgreD3FGAIQAAAAA.',
Do='Docvader:BAAANQAECgUIBgAAAA==.',
Dr='Drunkenhealz:BAABNQAECn8XAAIWAAcKhQ5mgADZAAAWAAcKhQ5mgADZAAAAAA==.Drunks:BAAANQAECgIJAgAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAABNQAECn8dAAIQAAcKmhC3hAA5AQAQAAcKmhC3hAA5AQAAAA==.',
Em='Emryssa:BAAANQADCgQIBAAAAA==.',
Er='Erosis:BAACNQAFFH8HAAIQAAQK5Ro4EwD+AAAQAAQK5Ro4EwD+AAA1AAQKfzAAAxAACgqoJHILAKgDABAACgqoJHILAKgDABcAAQoCEE1LAC8AAAAA.Eryx:BAAANQAECgQIBAAAAA==.',
Es='Esidh:BAAANQAECgcIBAABNQAECgoKHQAYADIJAA==.Esidk:BAABNQAECn8dAAIYAAoKMgkULwBrAQAYAAoKMgkULwBrAQAAAA==.Esimage:BAAANQAECgMIAwABNQAECgoKHQAYADIJAA==.',
Ex='Exboyfriend:BAAANQAECggIBAAAAA==.Exgirlfriend:BAAANQADCggIDAABNQAECgQIBAAPAAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECggIFwAXAGAPAA==.Ezrin:BAAANQAECgQIBwAAAA==.',
Fe='Fear:BAABNQAECn8iAAMHAAoKmB5FJAAnAgAHAAoKmB5FJAAnAgAIAAEKTBr0cAA+AAAAAA==.Felysria:BAAANQADCgYIBgAAAA==.',
Fr='Frequency:BAEANQAECgUIBwABNQAECgUICwAPAAAAAA==.',
Ga='Gakopozy:BAAANQAECgIIAgAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grauggy:BAAANQAECgYIBgAAAA==.Grimlokke:BAAANQAECgEIAQABNQAECggIFwAXAGAPAA==.',
['Gé']='Géne:BAAANQAECgUIBgABNQAECgoKJQACAM8eAA==.',
Ha='Harbard:BAAANQAECgQICAAAAA==.Havrin:BAABNQAECn9DAAQZAAkKExklEABeAgAZAAgKBRolEABeAgAaAAQK8g8PGgCxAAAbAAIKJQUbUQBKAAAAAA==.',
He='Headhûnter:BAAANQAECgYIDgAAAA==.Headshots:BAAANQADCgQIBAABNQAFFAIIBQABAL8UAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hew:BAAANQAECgQIBQABNQAFFAMIBwAUAG8SAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFH8VAAQJAAcKfB77DwBVAQAJAAQKwB77DwBVAQAcAAQKwyBODwAWAQAYAAMKzButBwDyAAA1AAQKf0UABAkACQq8JpAFAAMDAAkACAqpJpAFAAMDABwACApVI44aAO0CABgABgoRJP4sADgCAAAA.',
Hu='Huamulan:BAABNQAECn8jAAIBAAgKZAQJCgEOAQABAAgKZAQJCgEOAQAAAA==.',
Ib='Ibchilling:BAABNQAECn8fAAIQAAkKihLixgD3AQAQAAkKihLixgD3AQAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAABNQAECn88AAMdAAoKRSEgBABoAwAdAAoKRSEgBABoAwATAAEKAABdcwAmAAABNQAECgUIBwAPAAAAAA==.Iccarus:BAABNQAECn8pAAMCAAkK/x9FDgBPAwACAAkK/x9FDgBPAwAEAAEKAACCMgE2AAABNQAECgUIBwAPAAAAAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQADCgUICQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAABNQAECn8cAAITAAoKBxQmDgALAgATAAoKBxQmDgALAgABNQAECgoKLgAEADweAA==.Jaskim:BAABNQAECn8nAAIYAAkKPwarRgD8AAAYAAkKPwarRgD8AAAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgkJJwAYAD8GAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgEIAwAAAA==.',
Ka='Kaffee:BAAANQAECgEIAQABNQAECgMIAwAPAAAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAACNQAFFH8GAAIWAAYKQRljBAAPAgAWAAYKQRljBAAPAgA1AAQKfzIAAxYACgqNJEgGAIEDABYACgqNJEgGAIEDAB4ABQpRFHQqALcAAAAA.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAABNQAECn8gAAIQAAgKZxvphwBvAgAQAAgKZxvphwBvAgAAAA==.Katbeans:BAABNQAECn8zAAMfAAkKTSGaAwAyAgAfAAgKSSKaAwAyAgATAAMKKBUHWgB+AAAAAA==.Kathrynne:BAAANQAECgYIDgAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Katpuffs:BAAANQADCgEIAQAAAA==.Katscratch:BAAANQADCgIIAgABNQAECgkJMgAbAHMcAA==.Kaykoh:BAABNQAECn8jAAMcAAoK1CKnBwCHAwAcAAoK1CKnBwCHAwAJAAIKoB9ZbgBXAAAAAA==.',
Ke='Kelicemoon:BAABNQAECn8sAAMHAAoKbwvrPAC1AQAHAAoKbwvrPAC1AQAIAAMKXAGvawBJAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIAwABNQAECgUIDgAPAAAAAA==.',
Ki='Kiara:BAAANQAECgIIAQAAAA==.',
Kl='Kloner:BAAANQADCgIIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgcIFQAAAA==.',
['Kû']='Kûrr:BAAANQAECgMIBQABNQAECgoKJQACAM8eAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgYICAAAAA==.Laxeron:BAABNQAECn8dAAIgAAcKDiO5BwCnAQAgAAcKDiO5BwCnAQAAAA==.',
Le='Leotherassy:BAAANQAECgMIAwAAAA==.',
Lo='Lodehavoc:BAAANQADCgcIJQAAAA==.Longboneman:BAAANQAECgUICQABNQAECgoKLgAEADweAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAABNQAECn8/AAIBAAkKmB/TKQAgAwABAAkKmB/TKQAgAwAAAA==.Lynthirae:BAABNQAECn8xAAIFAAgKTRhvDAC3AQAFAAgKTRhvDAC3AQAAAA==.',
Ma='Madpearl:BAABNQAECn8kAAIEAAkKfwxRQgBLAQAEAAkKfwxRQgBLAQAAAA==.Mal:BAAANQADCgEIAQABNQAECgcIEQAPAAAAAA==.',
Mc='Mcbodhran:BAABNQAECn8ZAAIBAAgKNQXUDQEIAQABAAgKNQXUDQEIAQAAAA==.Mcfeast:BAABNQAECn8hAAIeAAgKnBgvHABjAgAeAAgKnBgvHABjAgAAAA==.',
Me='Medra:BAABNQAECn8cAAMKAAcKfwX5nwDMAAAKAAcKfwX5nwDMAAAhAAIKAwM0QQA6AAAAAA==.Melidoria:BAAANQAECgUIBQABNQAECgoKNQANAAQUAA==.Meowdi:BAAANQADCgcIIgAAAA==.',
Mi='Milou:BAABNQAECn8XAAMXAAgKYA/TEgB7AQAQAAgKLw2U4ADHAQAXAAcKxw3TEgB7AQAAAA==.Minibone:BAABNQAECn8lAAIKAAoKjBfRWACBAgAKAAoKjBfRWACBAgABNQAECgoKLgAEADweAA==.Mixr:BAAANQADCgEIAQAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Momobelfas:BAAANQADCgEIAQAAAA==.Moonwolf:BAAANQAECgcICwAAAA==.',
Mu='Mummrak:BAAANQAECgcICwAAAA==.',
My='Mysticwood:BAABNQAECn8uAAIEAAoKPB5BIQAFAwAEAAoKPB5BIQAFAwAAAA==.',
Na='Nadjá:BAABNQAECn8aAAIRAAkKLg89IwB7AQARAAkKLg89IwB7AQAAAA==.Nanija:BAAANQADCgcIJwAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAAANQAECgcIEwAAAA==.',
Ni='Nightcat:BAABNQAECn8yAAIbAAkKcxyVBwDfAgAbAAkKcxyVBwDfAgAAAA==.Nitestorm:BAABNQAECn8bAAIEAAoKJxoKSwBKAgAEAAoKJxoKSwBKAgAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAABNQAECn8WAAIDAAkKmhlPQQDeAQADAAkKmhlPQQDeAQAAAA==.',
Og='Ogwarshock:BAACNQAFFH8GAAMIAAMK9hmpAwCgAAAIAAIK4xypAwCgAAAHAAEKHRR+JwBLAAA1AAQKfy4ABAgACgqnI4YNACACAAgABQoYJoYNACACAAcABwrPHPVRAG0BAAYAAQp8H1YVAFoAAAAA.',
Ol='Oliiver:BAABNQAECn87AAIDAAoKXyBdEwC2AgADAAoKXyBdEwC2AgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAAANQAECggIEwABNQAECggIFwAXAGAPAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Panaceus:BAABNQAECn82AAIOAAoK+B7KCgD3AgAOAAoK+B7KCgD3AgAAAA==.Patron:BAAANQADCgUIBQAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgYICwAPAAAAAA==.',
Ph='Phrequency:BAEANQAECgUICwAAAA==.',
Pl='Plazmaglaive:BAABNQAECn8WAAMSAAoKYg+KEQDSAQASAAkKYg+KEQDSAQARAAIKKAU9iQBTAAAAAA==.',
Po='Poalo:BAAANQADCggICAAAAA==.Poisonóus:BAABNQAECn8WAAIJAAgKDxoMRwDdAQAJAAgKDxoMRwDdAQAAAA==.Polywóg:BAAANQADCgUICQAAAA==.Polyxo:BAABNQAECn8bAAIBAAcKMgzNigA8AQABAAcKMgzNigA8AQAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Pricker:BAAANQAECgUIBQABNQAECgoKLgAEADweAA==.Prépared:BAACNQAFFH8OAAIRAAQKIxJGEgDQAAARAAQKIxJGEgDQAAA1AAQKfx4AAxEACQqHGiczABICABEACAqHGiczABICACIAAQoAAJE0ACoAAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radkeem:BAABNQAECn8fAAIJAAoKiB0wEABCAgAJAAoKiB0wEABCAgAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECgoKHwAJAIgdAA==.Ravenstone:BAAANQADCgcIDAAAAA==.Raya:BAAANQAECgQIDgABNQAECgYICgAPAAAAAA==.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAABNQAECn8rAAMjAAoKAhOtLgDsAQAjAAoKAhOtLgDsAQABAAQKKgpGPAHAAAAAAA==.',
Ro='Roejawb:BAABNQAECn8aAAIEAAcKoAYRsQAxAQAEAAcKoAYRsQAxAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgUIBwAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQAPAAAAAA==.',
Sa='Sableanne:BAAANQAECgEIAQAAAA==.Sacon:BAAANQADCgYIDQABNQAECgcIEQAPAAAAAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECn8oAAMjAAoKWBqSRQBPAgAjAAoKWBqSRQBPAgALAAIKlRJrVwCCAAAAAA==.Salorll:BAAANQAECgUICAAAAA==.Savia:BAAANQAECgQIBAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECn8mAAMeAAkKXCGtCQBFAwAeAAkKXCGtCQBFAwAWAAUKShV3kgBfAQABNQAFFAcIFQAJAHweAA==.',
Se='Senza:BAAANQAECgYIDgAAAA==.Senzyri:BAABNQAECn8zAAMDAAoKig50SADFAQADAAoKig50SADFAQAkAAIKiQWuPwBZAAAAAA==.',
Sh='Shadyscales:BAACNQAFFH8IAAIUAAMKaQwEAgDjAAAUAAMKaQwEAgDjAAA1AAQKfy8AAhQACQprF3kGAGcCABQACQprF3kGAGcCAAAA.Shenro:BAABNQAECn8fAAIBAAgKpgtfnwAWAQABAAgKpgtfnwAWAQAAAA==.Shierà:BAAANQADCgcIBwABNQAECgYICwAPAAAAAA==.',
Si='Simic:BAAANQAECgYICgAAAA==.Sinnori:BAAANQABCggICwAAAA==.',
Sm='Smiddy:BAABNQAECn8dAAMJAAoKoBLROQAfAgAJAAoKoBLROQAfAgAYAAQKUhUJcwDUAAAAAA==.',
So='Souldrains:BAAANQADCggIFwAAAA==.Soyjak:BAABNQAECn8oAAMWAAkKwxLLOgDLAQAWAAkKwxLLOgDLAQAeAAUKdgWHMwCBAAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.Spinner:BAAANQADCgMIAwAAAA==.Spudpal:BAAANQADCggICAABNQAFFAYIBgAWAEEZAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAABNQAECn8WAAIKAAcKvA7TaQBJAQAKAAcKvA7TaQBJAQAAAA==.',
Su='Suraisu:BAABNQAECn80AAMgAAkKKSKoAwAWAwAgAAkKKSKoAwAWAwAKAAIK8A10MAFzAAAAAA==.',
Sv='Sveela:BAABNQAECn8yAAIZAAoK6SFaAgCoAwAZAAoK6SFaAgCoAwAAAA==.Sveelaa:BAABNQAECn8sAAIDAAkKpCE2DwBpAwADAAkKpCE2DwBpAwABNQAECgoKMgAZAOkhAA==.Sveella:BAAANQAECgcIEAABNQAECgoKMgAZAOkhAA==.',
Sy='Syda:BAAANQAECgMIAwAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECn8yAAMWAAoKUB1UMwCbAgAWAAoKUB1UMwCbAgAeAAEKAACIWgAAAAAAAA==.',
Te='Temlock:BAABNQAECn8hAAIHAAkKvBGqPwCrAQAHAAkKvBGqPwCrAQAAAA==.Temtank:BAAANQAECgYICQABNQAECgkJIQAHALwRAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.',
To='Toes:BAAANQAECgUIDwAAAA==.',
Tr='Traiya:BAAANQADCgEIAQAAAA==.Tralyn:BAAANQABCgQIBAAAAA==.Trukarak:BAABNQAECn8eAAIBAAcKNg9BnwAWAQABAAcKNg9BnwAWAQAAAA==.Trusturheals:BAAANQAECgUICQAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Um='Umarg:BAAANQADCgMIAwAAAA==.',
Ur='Uraha:BAAANQAECgIIAQAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
['Và']='Vàlor:BAABNQAECn8aAAMJAAgKZAYfOgD6AAAJAAgKZAYfOgD6AAAcAAEKgAJEAQEWAAAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAABNQAECn8gAAIbAAcKUhIJHACFAQAbAAcKUhIJHACFAQAAAA==.Windle:BAAANQADCggIEgAAAA==.Windseer:BAAANQADCgYICwABNQAFFAIIBQABAL8UAA==.',
Xa='Xarríøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Xh='Xhadowz:BAAANQAECgcIDAAAAA==.',
Xi='Xiao:BAABNQAECn86AAMdAAoKhRKxCQAcAgAdAAoKhRKxCQAcAgATAAYKugh3SQDYAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.Xingferat:BAAANQAECgQIBAAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Ya='Yahargul:BAABNQAECn8tAAIeAAcKWg6dIAADAQAeAAcKWg6dIAADAQAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCgcIHAAAAA==.Zaradin:BAAANQAECgQIBAABNQAECgUIDgAPAAAAAA==.Zariest:BAAANQABCgIIAgABNQAECgUIDgAPAAAAAA==.',
Ze='Zeik:BAABNQAECn88AAILAAoKvSBJBADcAgALAAoKvSBJBADcAgAAAA==.Zellspell:BAAANQADCggICQABNQAFFAUIEwAEAGcdAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Àl']='Àlcàrà:BAAANQAECgYICwAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgUICwAAAA==.',
['Ÿa']='Ÿamar:BAAANQAECgUIBAAAAA==.',
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
