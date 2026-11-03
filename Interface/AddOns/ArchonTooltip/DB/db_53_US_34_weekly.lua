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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Arms','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Mage-Arcane','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Rogue-Outlaw','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Enhancement','DeathKnight-Unholy','Monk-Mistweaver','Priest-Shadow','Monk-Brewmaster','Warrior-Fury','DemonHunter-Vengeance','Warrior-Protection','Priest-Discipline','Paladin-Holy',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAACNQAFFH8JAAIBAAQK1hMrEADfAAABAAQK1hMrEADfAAA1AAQKf0MAAgEACgpHIKwfAEUDAAEACgpHIKwfAEUDAAAA.',
Am='Amádeus:BAAANQAECgEIAgABNQAECgoKJgACAM8eAA==.',
An='Andezard:BAABNQAECn8nAAIDAAkKlQ/AeACCAQADAAkKlQ/AeACCAQAAAA==.Angelys:BAAANQADCgYJCQAAAA==.',
Ap='Aphrobitey:BAAANQAECgQIBgABNQAECgkJKwAEALEMAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggIEAAAAA==.',
At='Athenaowl:BAAANQAECgUICgAAAA==.',
Ay='Ayanoriko:BAACNQAFFH8IAAIFAAUKHg/oBADbAAAFAAUKHg/oBADbAAA1AAQKfzgAAgUACgqmIwwJAEgDAAUACgqmIwwJAEgDAAAA.Ayasumi:BAAANQAECggICQAAAA==.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQAECgEIAQAAAA==.Babynick:BAABNQAECn8aAAMGAAkK7g2iFQCxAQADAAgKvw0aYADAAQAGAAkKNwuiFQCxAQAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFH8KAAQHAAMKXh/GBgBfAAAIAAMK6hwCHwD9AAAHAAEKmSTGBgBfAAAJAAEKARZzGwBPAAA1AAQKf0wABAgACgqdJHsEAEEDAAgACgpmJHsEAEEDAAcABwrzImoDAEUCAAkABwr1GlsSAOIBAAE1AAUUBwgVAAoAfB4A.',
Bi='Bigsharder:BAAANQAECgMIBgABNQAFFAkJLAALAJodAA==.Bigstones:BAACNQAFFH8HAAILAAQK0wEhKABbAAALAAQK0wEhKABbAAA1AAQKfzAAAgsACgqjDRCeANEBAAsACgqjDRCeANEBAAAA.',
Bl='Blacksavior:BAABNQAECn8iAAIMAAoKpBdKFABiAgAMAAoKpBdKFABiAgAAAA==.Blindbone:BAAANQADCggICAABNQAECgoKLwALAKMaAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgUICAAAAA==.Bluehydra:BAAANQAECgYIBgAAAA==.Bluepocalyps:BAAANQADCggIHAAAAA==.',
Bo='Bobbydigital:BAABNQAECn8vAAIKAAgKGhFwOQA0AQAKAAgKGhFwOQA0AQAAAA==.Bolas:BAABNQAECn8WAAQNAAkKkgzdGgCVAAAOAAYKrQlxLgCqAAANAAQKtgXdGgCVAAAPAAIKpgG4TQA4AAAAAA==.Bopchop:BAAANQAECgcICwABNQAECggIEgAQAAAAAA==.Bowookie:BAAANQAECggICAAAAA==.',
Br='Bracynn:BAAANQAECgYIDAAAAA==.',
Bu='Buddapalm:BAAANQAECgEIAQAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.Carí:BAAANQADCgcIBwAAAA==.',
Ce='Cealia:BAABNQAECn89AAIRAAoK4hDFVwDjAQARAAoK4hDFVwDjAQAAAA==.Cephalo:BAAANQADCggIEwAAAA==.',
Ch='Chakuneeai:BAAANQAECgUICQAAAA==.Chancleta:BAAANQAECgQIBAAAAA==.Christae:BAABNQAECn8cAAISAAcKrhnGQQD6AQASAAcKrhnGQQD6AQAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAABNQAECn8mAAICAAoKzx5KHgDyAgACAAoKzx5KHgDyAgAAAA==.',
Co='Compromised:BAABNQAECn8/AAMTAAoK/B/RCwDBAgATAAoK/B/RCwDBAgAUAAYKqxDoOQB2AQAAAA==.Connalious:BAAANQAECgEIAQAAAA==.',
Cr='Crwth:BAABNQAECn8WAAIBAAUKUAHjdwFkAAABAAUKUAHjdwFkAAAAAA==.',
Cu='Curendae:BAABNQAECn8pAAIDAAgKgBUFcACYAQADAAgKgBUFcACYAQAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Dabaldzombie:BAAANQABCgIIAgABNQAFFAQIDgATACMSAA==.Danika:BAAANQAECgEIAQABNQAECgoKLwAVALghAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUIDgAAAA==.Daxzazi:BAAANQAECgcIDwAAAA==.',
De='Decillian:BAAANQAECgcIEwAAAA==.Dern:BAABNQAECn8eAAICAAoKBhbiIgB7AgACAAoKBhbiIgB7AgAAAA==.Desolit:BAABNQAECn8iAAIUAAoK+hw6EQAZAgAUAAoK+hw6EQAZAgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAACNQAFFH8JAAIWAAUKbxJ4AADlAAAWAAUKbxJ4AADlAAA1AAQKfygAAxYACgotGmoBAFwCABYACgotGmoBAFwCABcAAgreD3FGAIQAAAAA.',
Do='Docvader:BAAANQAECgUICQAAAA==.',
Dr='Drunkenhealz:BAABNQAECn8XAAISAAcKhQ4SqwAVAQASAAcKhQ4SqwAVAQAAAA==.Drunks:BAAANQAECgIJAgAAAA==.Drvargas:BAAANQAECgEIAwAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAABNQAECn8lAAIRAAgKEw9RhgBtAQARAAgKEw9RhgBtAQAAAA==.',
Em='Emryssa:BAAANQADCgQIBAAAAA==.',
Er='Erosis:BAACNQAFFH8IAAIRAAUK5RpCGgD2AAARAAUK5RpCGgD2AAA1AAQKfzUAAxEACgr4JXILAKgDABEACgr4JXILAKgDABgAAQoCEE1LAC8AAAAA.Eryx:BAAANQAECgQIBQAAAA==.',
Es='Esidh:BAAANQAECgcIBAABNQAECgoKHwAZACkKAA==.Esidk:BAABNQAECn8fAAIZAAoKKQrgOgB1AQAZAAoKKQrgOgB1AQAAAA==.Esimage:BAAANQAECgMIAwABNQAECgoKHwAZACkKAA==.',
Ex='Exboyfriend:BAAANQAECggICAAAAA==.Exgirlfriend:BAAANQADCggIDAABNQAECgQIBAAQAAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECgoKGwASALkVAA==.Ezrin:BAAANQAECgQIBwAAAA==.',
Fe='Fear:BAABNQAECn8pAAMIAAoKiR+9EADOAgAIAAoKiR+9EADOAgAJAAEKTBr0cAA+AAAAAA==.Felysria:BAAANQADCgYIBgAAAA==.',
Fr='Frequency:BAEANQAECgUIBwABNQAECgUIDAAQAAAAAA==.Frizzer:BAAANQAECgEIAgAAAA==.',
Ga='Gakopozy:BAAANQAECgIIAwAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grauggy:BAAANQAECgYIBwAAAA==.Grimlokke:BAAANQAECgEIAQABNQAECgoKGwASALkVAA==.',
['Gé']='Géne:BAAANQAECgUIBwABNQAECgoKJgACAM8eAA==.',
Ha='Harbard:BAAANQAECgQICAAAAA==.Havrin:BAABNQAECn9KAAQaAAoKxBglEABeAgAaAAkKiBklEABeAgAbAAYK0grZNwD4AAAcAAQK8g/WIwCgAAAAAA==.',
He='Headhûnter:BAABNQAECn8XAAIdAAgK9gRIHgD7AAAdAAgK9gRIHgD7AAAAAA==.Headshots:BAAANQADCgQIBAABNQAFFAQICQABANYTAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hevenly:BAAANQADCgYIBgAAAA==.Hew:BAAANQAECgQIBQABNQAFFAUICQAWAG8SAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFH8VAAQKAAcKfB77DwBVAQAKAAQKwB77DwBVAQAeAAQKwyBODwAWAQAZAAMKzBslCgDuAAA1AAQKf0UABAoACQq8JgsJAHEDAAoACAqpJgsJAHEDAB4ACApVI44aAO0CABkABgoRJP4sADgCAAAA.',
Hu='Huamulan:BAABNQAECn8lAAIBAAgKZAQJCgEOAQABAAgKZAQJCgEOAQAAAA==.',
Ib='Ibchilling:BAABNQAECn8lAAIRAAoKExX+iABnAQARAAoKExX+iABnAQAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAABNQAECn9DAAMfAAoKRSEgBABoAwAfAAoKRSEgBABoAwAVAAEKAABdcwAmAAABNQAECgUIBwAQAAAAAA==.Iccarus:BAABNQAECn8pAAMCAAkK/x9FDgBPAwACAAkK/x9FDgBPAwAEAAEKAACCMgE2AAABNQAECgUIBwAQAAAAAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQAECgIIAQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAABNQAECn8cAAIVAAoKBxQFEwD/AQAVAAoKBxQFEwD/AQABNQAECgoKLwALAKMaAA==.Jaskim:BAABNQAECn8uAAIZAAkKfwbfUQAQAQAZAAkKfwbfUQAQAQAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgkJLgAZAH8GAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgYICQAAAA==.',
Ka='Kaffee:BAAANQAECggIDAAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAACNQAFFH8GAAISAAYKQRn7BgAJAgASAAYKQRn7BgAJAgA1AAQKfzsAAxIACgq/JLcIAH4DABIACgq/JLcIAH4DACAABgovGHMjAC0BAAAA.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAABNQAECn8hAAIRAAkKEhnphwBvAgARAAkKEhnphwBvAgAAAA==.Katbeans:BAABNQAECn89AAMhAAoKSyDuAgCnAgAhAAkKzCHuAgCnAgAVAAQKUBVLPQCOAAAAAA==.Katclaw:BAAANQAECgcIBwAAAA==.Kathrynne:BAABNQAECn8XAAIDAAgKNQhsmgA5AQADAAgKNQhsmgA5AQAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Katpuffs:BAAANQADCgEIAQAAAA==.Katscratch:BAAANQADCgIIAgABNQAECgoKQwAbAHIeAA==.Kaykoh:BAABNQAECn8kAAMeAAoK1CKnBwCHAwAeAAoK1CKnBwCHAwAKAAIKoB9HqQB+AAAAAA==.',
Ke='Kelicemoon:BAABNQAECn81AAMIAAoK5wtzTAC4AQAIAAoK5wtzTAC4AQAJAAMKXAGvawBJAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIAwABNQAECgUIDgAQAAAAAA==.',
Ki='Kiara:BAAANQAECgIIAQAAAA==.',
Kl='Kloner:BAAANQAECgEIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgcIFQAAAA==.',
['Kû']='Kûrr:BAAANQAECgMICAABNQAECgoKJgACAM8eAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgYICAAAAA==.Laxeron:BAABNQAECn8jAAIiAAcKDiM2CQDGAQAiAAcKDiM2CQDGAQAAAA==.',
Le='Leotherassy:BAAANQAECgQIBAAAAA==.',
Lo='Lodehavoc:BAAANQADCgcIJQAAAA==.Longboneman:BAAANQAECgUICQABNQAECgoKLwALAKMaAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAABNQAECn9DAAIBAAoKgx/TKQAgAwABAAoKgx/TKQAgAwAAAA==.Lynthirae:BAABNQAECn81AAIFAAoK2RY6CgALAgAFAAoK2RY6CgALAgAAAA==.',
Ma='Madpearl:BAABNQAECn8rAAIEAAkKsQzqTwBfAQAEAAkKsQzqTwBfAQAAAA==.Mal:BAAANQADCgEIAQABNQAECggIGQAjAGQZAA==.',
Mc='Mcbodhran:BAABNQAECn8bAAIBAAgKSAXUDQEIAQABAAgKSAXUDQEIAQAAAA==.Mcfeast:BAABNQAECn8hAAIgAAgKnBgvHABjAgAgAAgKnBgvHABjAgAAAA==.',
Me='Medra:BAABNQAECn8iAAMLAAcKKQZwsADhAAALAAcKKQZwsADhAAAkAAIKAwM0QQA6AAAAAA==.Melidoria:BAAANQAECgUICQABNQAECgoKRgAOAPwVAA==.Meowdi:BAAANQADCgcIIgAAAA==.',
Mi='Milou:BAABNQAECn8XAAMYAAgKYA/TEgB7AQARAAgKLw2U4ADHAQAYAAcKxw3TEgB7AQABNQAECgoKGwASALkVAA==.Minibone:BAABNQAECn8vAAILAAoKoxqPKwBsAgALAAoKoxqPKwBsAgAAAA==.Mixr:BAAANQADCgEIAQAAAA==.Mizery:BAAANQADCggICAAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Momobelfas:BAAANQAECgIIAgAAAA==.Moonwolf:BAAANQAECgcIEAAAAA==.',
Mu='Mummrak:BAAANQAECgcIDgAAAA==.',
My='Mysticwood:BAABNQAECn8uAAIEAAoKPB5BIQAFAwAEAAoKPB5BIQAFAwABNQAECgoKLwALAKMaAA==.',
Na='Nadjá:BAABNQAECn8gAAITAAkKqRBdKwB3AQATAAkKqRBdKwB3AQAAAA==.Nanija:BAAANQADCggIKAAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAABNQAECn8YAAMCAAkKgBKZXQD2AQACAAkKgBKZXQD2AQAEAAEKjAUu6gAtAAAAAA==.',
Ni='Nightcat:BAABNQAECn9DAAIbAAoKch7vBQBZAwAbAAoKch7vBQBZAwAAAA==.Nitestorm:BAABNQAECn8bAAIEAAoKJxoKSwBKAgAEAAoKJxoKSwBKAgAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Noala:BAAANQAECgEIAQAAAA==.Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAABNQAECn8WAAIDAAkKmhk7YADAAQADAAkKmhk7YADAAQAAAA==.',
Og='Ogwarshock:BAACNQAFFH8GAAMJAAMK9hnZBACWAAAJAAIK4xzZBACWAAAIAAEKHRT4LgBLAAA1AAQKfy4ABAkACgqnI4YNACACAAkABQoYJoYNACACAAgABwrPHKOCAN8BAAcAAQp8H1AfAE8AAAAA.',
Ol='Oliiver:BAABNQAECn9FAAIDAAoKXyDYGwCvAgADAAoKXyDYGwCvAgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAABNQAECn8bAAMSAAoKuRVaYQD9AQASAAoKuRVaYQD9AQAlAAEKfAYCLgApAAAAAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Pallyofdoom:BAAANQAECgYIBwAAAA==.Panaceus:BAABNQAECn8/AAIPAAoKBR+SBgDMAgAPAAoKBR+SBgDMAgAAAA==.Patron:BAAANQADCgUIBQAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgcIDQAQAAAAAA==.',
Ph='Phrequency:BAEANQAECgUIDAAAAA==.',
Pl='Plazmaglaive:BAABNQAECn8aAAMUAAoK9w86FwDKAQAUAAkK9w86FwDKAQATAAIKKAU9iQBTAAAAAA==.',
Po='Poalo:BAAANQAECgEIAQAAAA==.Poisonóus:BAABNQAECn8WAAIKAAgKDxoMRwDdAQAKAAgKDxoMRwDdAQAAAA==.Polywóg:BAAANQADCgUICQAAAA==.Polyxo:BAABNQAECn8dAAIBAAcKMgyytQAmAQABAAcKMgyytQAmAQAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Pricker:BAAANQAECgUIBQABNQAECgoKLwALAKMaAA==.Prépared:BAACNQAFFH8OAAITAAQKIxJGEgDQAAATAAQKIxJGEgDQAAA1AAQKfyQAAyMACQoHG74MAEkBABMACAqHGiczABICACMABwoqFr4MAEkBAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radkeem:BAABNQAECn8pAAIKAAoKVh+bDACxAgAKAAoKVh+bDACxAgAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECgoKKQAKAFYfAA==.Ravenstone:BAAANQADCgcIDAAAAA==.Raya:BAAANQAECgMIEwABNQAECgYIDQAQAAAAAA==.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAABNQAECn80AAMmAAoKcxQqMwAeAgAmAAoKcxQqMwAeAgABAAQKKgpGPAHAAAAAAA==.',
Ro='Roejawb:BAABNQAECn8aAAIEAAcKoAYRsQAxAQAEAAcKoAYRsQAxAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgUIBwAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQAQAAAAAA==.',
Sa='Sableanne:BAAANQAECgEIBQAAAA==.Sacon:BAAANQADCgYIDQABNQAECggIGQAjAGQZAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECn8yAAMmAAoKnhomLQA/AgAmAAoKnhomLQA/AgAMAAIKlRJrVwCCAAAAAA==.Salorll:BAAANQAECgYIDgAAAA==.Savia:BAAANQAECgQIBAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECn8mAAMgAAkKXCGtCQBFAwAgAAkKXCGtCQBFAwASAAUKShV3kgBfAQABNQAFFAcIFQAKAHweAA==.',
Se='Sellari:BAAANQAECggICAAAAA==.Senza:BAABNQAECn8ZAAIBAAcKwgYS4QDeAAABAAcKwgYS4QDeAAAAAA==.Senzyri:BAABNQAECn89AAMDAAoKcA/IRwAFAgADAAoKcA/IRwAFAgAGAAIKiQW0SQBZAAAAAA==.',
Sh='Shadyscales:BAACNQAFFH8IAAIWAAMKaQwEAgDjAAAWAAMKaQwEAgDjAAA1AAQKfy8AAhYACQprF3kGAGcCABYACQprF3kGAGcCAAAA.Shenro:BAABNQAECn8hAAIBAAkKTQuFqgA5AQABAAkKTQuFqgA5AQAAAA==.Shierà:BAAANQADCgcIBwABNQAECgYICwAQAAAAAA==.',
Si='Simic:BAAANQAECgcIEwAAAA==.Sinnori:BAAANQABCggICwAAAA==.',
Sm='Smiddy:BAABNQAECn8dAAMKAAoKoBLROQAfAgAKAAoKoBLROQAfAgAZAAQKUhUJcwDUAAAAAA==.',
So='Souldrains:BAAANQADCggIHQAAAA==.Soyjak:BAABNQAECn8qAAMSAAkKehMqUADAAQASAAkKehMqUADAAQAgAAUKdgVdPwB/AAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.Spinner:BAAANQADCgMIAwAAAA==.Spudpal:BAAANQADCggICAABNQAFFAYIBgASAEEZAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAABNQAECn8dAAILAAgKMw9LZgCUAQALAAgKMw9LZgCUAQAAAA==.',
Su='Suraisu:BAABNQAECn89AAMiAAoKGCLCAgDUAgAiAAoKGCLCAgDUAgALAAIK8A10MAFzAAAAAA==.',
Sv='Sveela:BAABNQAECn88AAIaAAoKEyRaAgCoAwAaAAoKEyRaAgCoAwAAAA==.Sveelaa:BAABNQAECn8yAAIDAAkKpCE2DwBpAwADAAkKpCE2DwBpAwABNQAECgoKPAAaABMkAA==.Sveella:BAAANQAECgYIEQABNQAECgoKPAAaABMkAA==.',
Sy='Syda:BAAANQAECgUIBwABNQAECggIDAAQAAAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECn82AAMSAAoKUB1UMwCbAgASAAoKUB1UMwCbAgAgAAEKAAB6bAAAAAAAAA==.',
Te='Temlock:BAABNQAECn8qAAIIAAoKfBI7PQDtAQAIAAoKfBI7PQDtAQAAAA==.Temtank:BAAANQAECgYICQABNQAECgoKKgAIAHwSAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.Theidor:BAAANQADCgEIAQAAAA==.',
To='Toes:BAABNQAECn8ZAAMXAAkKphpsKwAaAgAXAAgKkBdsKwAaAgAFAAcKzxlJGQBEAQAAAA==.',
Tr='Traiya:BAAANQADCgEIAQAAAA==.Tralyn:BAAANQABCgQIBAAAAA==.Trukarak:BAABNQAECn8kAAIBAAcKNg8ivAAbAQABAAcKNg8ivAAbAQAAAA==.Trusturheals:BAAANQAECgcIEQAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Um='Umarg:BAAANQADCgMIAwAAAA==.',
Ur='Uraha:BAAANQAECgQIBAAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
Ve='Veliann:BAAANQAECgEIAQAAAA==.',
Vy='Vyktr:BAAANQAECgEIAwAAAA==.',
['Và']='Vàlor:BAABNQAECn8iAAMKAAkKJAgOPAAoAQAKAAkKJAgOPAAoAQAeAAEKgAJEAQEWAAAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAABNQAECn8mAAIbAAcKBRO3JACBAQAbAAcKBRO3JACBAQAAAA==.Windle:BAAANQADCggIGgAAAA==.Windseer:BAAANQADCgYICwABNQAFFAQICQABANYTAA==.',
Wu='Wumbo:BAAANQAECgUIBQAAAA==.',
Xa='Xarríøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Xh='Xhadowz:BAAANQAECgcIEAAAAA==.',
Xi='Xiao:BAABNQAECn9EAAMfAAoK3BJJDQAQAgAfAAoK3BJJDQAQAgAVAAcKSQh3SQDYAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.Xingferat:BAAANQAECgUIBQAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Ya='Yahargul:BAABNQAECn8tAAIgAAcKWg5xKQD9AAAgAAcKWg5xKQD9AAAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCggIHQAAAA==.Zaradin:BAAANQAECgQIBAABNQAECgUIDgAQAAAAAA==.Zariest:BAAANQADCgIIAgABNQAECgUIDgAQAAAAAA==.',
Ze='Zeik:BAABNQAECn9GAAIMAAoKvSBjBgDMAgAMAAoKvSBjBgDMAgAAAA==.Zellspell:BAAANQAECgEIAQABNQAFFAUIEwAEAGcdAA==.Zerase:BAAANQADCgEIAQAAAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Àl']='Àlcàrà:BAAANQAECgYICwAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgUICwAAAA==.',
['Ÿa']='Ÿamar:BAAANQAECgUICAAAAA==.',
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
