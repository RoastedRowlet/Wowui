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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Rogue-Assassination','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Warrior-Protection','Warrior-Arms','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Mage-Arcane','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Rogue-Outlaw','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Enhancement','DeathKnight-Unholy','Monk-Mistweaver','Priest-Shadow','Monk-Brewmaster','Warrior-Fury','DemonHunter-Vengeance','Priest-Discipline','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-11-10',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAACNQAFFH8JAAIBAAQK1hNsEwDcAAABAAQK1hNsEwDcAAA1AAQKf0MAAgEACgpHIKwfAEUDAAEACgpHIKwfAEUDAAAA.',
Am='Amádeus:BAAANQAECgEIAQABNQAECgoKJgACAM8eAA==.',
An='Andezard:BAABNQAECn8qAAIDAAkK/xG5fACmAQADAAkK/xG5fACmAQAAAA==.Angelys:BAAANQADCgYJCQAAAA==.',
Ap='Aphrobitey:BAAANQAECgQIBgABNQAECgkJMQAEAJQOAA==.',
As='Ashynn:BAAANQAECgIIAgAAAA==.Astrit:BAAANQADCggIEAAAAA==.',
At='Athenaowl:BAAANQAECgUICQAAAA==.',
Ay='Ayanoriko:BAACNQAFFH8IAAIFAAUKHg8eBgDXAAAFAAUKHg8eBgDXAAA1AAQKfzwAAgUACgq3IwwJAEgDAAUACgq3IwwJAEgDAAAA.Ayasumi:BAAANQAECggICQAAAA==.',
Az='Azonia:BAAANQADCgYJEQAAAA==.',
Ba='Babaganoosh:BAAANQAECgIIAgAAAA==.Babynick:BAABNQAECn8aAAMGAAkK7g1WGAC0AQADAAgKvw1/bgDJAQAGAAkKNwtWGAC0AQAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYJEgAAAA==.',
Be='Beans:BAACNQAFFH8KAAQHAAMKXh9yCgBdAAAIAAMK6hwCHwD9AAAHAAEKmSRyCgBdAAAJAAEKARZzGwBPAAA1AAQKf00ABAgACgraJE8FAEQDAAgACgqiJE8FAEQDAAcABwrzIrgEADQCAAkABwr1GlsSAOIBAAE1AAUUBwgVAAoAfB4A.',
Bi='Bigsharder:BAAANQAECgMIBgABNQAFFAgIHQALAMwlAA==.Bigstones:BAACNQAFFH8HAAIMAAQK0wEFLgBYAAAMAAQK0wEFLgBYAAA1AAQKfzQAAgwACgqjDRCeANEBAAwACgqjDRCeANEBAAAA.',
Bl='Blacksavior:BAABNQAECn8jAAMNAAoKpBdKFABiAgANAAoKpBdKFABiAgABAAEKKAzzjwEwAAAAAA==.Blindbone:BAAANQADCggICAABNQAECgoKMgAMAKMaAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Blucifer:BAAANQADCgUICAAAAA==.Bluehydra:BAAANQAECgYIBQAAAA==.Bluepocalyps:BAAANQADCggIHAAAAA==.',
Bo='Bobbydigital:BAABNQAECn82AAIKAAoKcxIHIgDbAQAKAAoKcxIHIgDbAQAAAA==.Bolas:BAABNQAECn8WAAQOAAkKkgzdGgCVAAAPAAYKrQlxLgCqAAAOAAQKtgXdGgCVAAAQAAIKpgG4TQA4AAAAAA==.Bopchop:BAAANQAECgcICQABNQAECggIEwARAAAAAA==.Bowookie:BAAANQAECggICAAAAA==.',
Br='Bracynn:BAAANQAECgYIDAAAAA==.',
Bu='Buddapalm:BAAANQAECgEIAQAAAA==.',
Ca='Caimark:BAAANQADCggIEAAAAA==.Carí:BAAANQADCgcIBwAAAA==.',
Ce='Cealia:BAABNQAECn9CAAISAAoKdROJVAAFAgASAAoKdROJVAAFAgAAAA==.Cephalo:BAAANQADCggIEwAAAA==.',
Ch='Chakuneeai:BAAANQAECgUICQAAAA==.Chancleta:BAAANQAECgUIBAAAAA==.Christae:BAABNQAECn8cAAITAAcKrhnzTQDrAQATAAcKrhnzTQDrAQAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAABNQAECn8mAAICAAoKzx5KHgDyAgACAAoKzx5KHgDyAgAAAA==.',
Co='Cocytus:BAAANQABCgIIAgABNQAECgoKUAAIADIiAA==.Compromised:BAABNQAECn9AAAMUAAoK/B8ODgC3AgAUAAoK/B8ODgC3AgAVAAYKqxDoOQB2AQAAAA==.Connalious:BAAANQAECgEIAQAAAA==.',
Cr='Crwth:BAABNQAECn8WAAIBAAUKUAHjdwFkAAABAAUKUAHjdwFkAAAAAA==.',
Cu='Curendae:BAABNQAECn8sAAIDAAgKbRYrewCqAQADAAgKbRYrewCqAQAAAA==.Curst:BAAANQADCgQIBAAAAA==.Cuzom:BAAANQADCgQICgAAAA==.',
Da='Dabaldzombie:BAAANQABCgIIAgABNQAFFAQIDgAUACMSAA==.Danika:BAAANQAECgEIAQABNQAECgoKLwAWALghAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQAECgUIDgAAAA==.Daxzazi:BAAANQAECgcIDgAAAA==.',
De='Decillian:BAAANQAECgcIEwAAAA==.Dern:BAABNQAECn8eAAICAAoKBhZvKQBuAgACAAoKBhZvKQBuAgAAAA==.Desolit:BAABNQAECn8qAAIVAAoKAR5EDgBkAgAVAAoKAR5EDgBkAgAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAACNQAFFH8KAAIXAAYKVxFIAAA9AQAXAAYKVxFIAAA9AQA1AAQKfywAAxcACgqIGoQBAGwCABcACgqIGoQBAGwCABgAAgreD3FGAIQAAAAA.',
Do='Docvader:BAAANQAECgUIBgAAAA==.',
Dr='Drunkenhealz:BAABNQAECn8XAAITAAcKhQ4SqwAVAQATAAcKhQ4SqwAVAQAAAA==.Drunks:BAAANQAECgIJAgAAAA==.Drvargas:BAAANQAECgQIBAAAAA==.',
Du='Duldar:BAAANQAECgEIAQAAAA==.',
Ec='Eccehomito:BAAANQAECgQIBAAAAA==.',
El='Elmo:BAABNQAECn8lAAISAAgKEw/xlABoAQASAAgKEw/xlABoAQAAAA==.',
Em='Emryssa:BAAANQADCgUIBgAAAA==.',
Er='Erosis:BAACNQAFFH8IAAISAAUK5RrKHwDvAAASAAUK5RrKHwDvAAA1AAQKfzoAAxIACgoMJnILAKgDABIACgoMJnILAKgDABkAAQoCEE1LAC8AAAAA.Eryx:BAAANQAECgQIBAAAAA==.',
Es='Esidh:BAAANQAECgcIBAABNQAECgoKHwAaACkKAA==.Esidk:BAABNQAECn8fAAIaAAoKKQqtQwB0AQAaAAoKKQqtQwB0AQAAAA==.Esimage:BAAANQAECgMIAwABNQAECgoKHwAaACkKAA==.',
Ex='Exboyfriend:BAAANQAECggIDAAAAA==.Exgirlfriend:BAAANQADCggIDAABNQAECgQIBAARAAAAAA==.',
Ez='Ezaratren:BAAANQAECgUIBQABNQAECgoKGwATALkVAA==.Ezrin:BAAANQAECgQIBwAAAA==.',
Fe='Fear:BAABNQAECn8yAAMIAAoKECC9EQDZAgAIAAoKECC9EQDZAgAJAAEKTBr0cAA+AAAAAA==.Felysria:BAAANQADCgYIBgAAAA==.',
Fr='Frequency:BAEANQAECgUIBwABNQAECgUICwARAAAAAA==.',
Ga='Gakopozy:BAAANQAECgIIAwAAAA==.',
Gl='Glex:BAAANQAECgEIAQAAAA==.',
Gr='Grauggy:BAAANQAECgYIBgAAAA==.Grimlokke:BAAANQAECgEIAQABNQAECgoKGwATALkVAA==.Grïmyst:BAAANQAECggICAABNQAECgoKGwATALkVAA==.',
Gu='Gurten:BAAANQADCgMIAwABNQAECgYIGgAXABIMAA==.',
['Gé']='Géne:BAAANQAECgUIBgABNQAECgoKJgACAM8eAA==.',
Ha='Harbard:BAAANQAECgQICAAAAA==.Havrin:BAABNQAECn9SAAQbAAoKxBglEABeAgAbAAkKiBklEABeAgAcAAgKwAy+LABsAQAdAAQK8g+tKQCfAAAAAA==.',
He='Headhûnter:BAABNQAECn8YAAIeAAgKngWmHgAdAQAeAAgKngWmHgAdAQAAAA==.Headshots:BAAANQADCgQIBAABNQAFFAQICQABANYTAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hevenly:BAAANQADCgYIBgAAAA==.Hew:BAAANQAECgQIBQABNQAFFAYICgAXAFcRAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMJBQAAAA==.Hoogaplop:BAACNQAFFH8VAAQKAAcKfB77DwBVAQAKAAQKwB77DwBVAQAfAAQKwyBODwAWAQAaAAMKzBtTDADpAAA1AAQKf0UABAoACQq8JgsJAHEDAAoACAqpJgsJAHEDAB8ACApVI44aAO0CABoABgoRJP4sADgCAAAA.',
Hu='Huamulan:BAABNQAECn8pAAIBAAoKxwQJCgEOAQABAAoKxwQJCgEOAQAAAA==.',
Ib='Ibchilling:BAABNQAECn8lAAISAAoKExXixgD3AQASAAoKExXixgD3AQAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAABNQAECn9DAAMgAAoKRSEgBABoAwAgAAoKRSEgBABoAwAWAAEKAABdcwAmAAABNQAECgUIBwARAAAAAA==.Iccarus:BAABNQAECn8pAAMCAAkK/x9FDgBPAwACAAkK/x9FDgBPAwAEAAEKAACCMgE2AAABNQAECgUIBwARAAAAAA==.',
Ig='Ignis:BAAANQAECgUIBwAAAA==.',
Is='Iseldra:BAAANQAECgIIAQAAAA==.',
It='Itslifestyle:BAAANQADCggJDAAAAA==.',
Ja='Jackbfistn:BAABNQAECn8dAAIWAAoKrRXXEwAUAgAWAAoKrRXXEwAUAgABNQAECgoKMgAMAKMaAA==.Jaskim:BAABNQAECn8uAAIaAAkKfwbZWwAQAQAaAAkKfwbZWwAQAQAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgkJLgAaAH8GAA==.',
Jo='Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgUICAAAAA==.',
Ka='Kaffee:BAAANQAECggICQAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAACNQAFFH8GAAITAAYKQRlnCQD8AQATAAYKQRlnCQD8AQA1AAQKfzsAAxMACgq/JLcIAH4DABMACgq/JLcIAH4DACEABgovGEAoACsBAAAA.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAABNQAECn8hAAISAAkKEhnphwBvAgASAAkKEhnphwBvAgAAAA==.Katbeans:BAABNQAECn9BAAMiAAoKByEYAwCzAgAiAAkKoiIYAwCzAgAWAAQKUBXvQgCMAAAAAA==.Katclaw:BAAANQAECgcIBgAAAA==.Kathrynne:BAABNQAECn8fAAIDAAkKHwh5kwByAQADAAkKHwh5kwByAQAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Katpuffs:BAAANQADCgEIAQAAAA==.Katscratch:BAAANQADCgIIAgABNQAECgoKRwAcAHQeAA==.Kaykoh:BAABNQAECn8kAAMfAAoK1CKnBwCHAwAfAAoK1CKnBwCHAwAKAAIKoB9HqQB+AAAAAA==.',
Ke='Kelicemoon:BAABNQAECn85AAMIAAoKCQyxVQC/AQAIAAoKCQyxVQC/AQAJAAMKXAGvawBJAAAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQJBAAAAA==.Khatara:BAAANQADCgMIAwABNQAECgUIDgARAAAAAA==.',
Ki='Kiara:BAAANQAECgIIAQAAAA==.',
Kl='Kloner:BAAANQAECgEIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgcIFQAAAA==.',
['Kû']='Kûrr:BAAANQAECgMIBQABNQAECgoKJgACAM8eAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgYICAAAAA==.Laxeron:BAABNQAECn8kAAIjAAgKHiIDCAAWAgAjAAgKHiIDCAAWAgAAAA==.',
Le='Leotherassy:BAAANQAECgUIBQAAAA==.',
Lo='Lodehavoc:BAAANQADCgcIJQAAAA==.Longboneman:BAAANQAECgUIDAABNQAECgoKMgAMAKMaAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAABNQAECn9LAAIBAAoKzx/TKQAgAwABAAoKzx/TKQAgAwAAAA==.Lynthirae:BAABNQAECn83AAIFAAoK+xZ/CwAJAgAFAAoK+xZ/CwAJAgAAAA==.',
Ma='Madpearl:BAABNQAECn8xAAIEAAkKlA5qTgCHAQAEAAkKlA5qTgCHAQAAAA==.Mal:BAAANQADCgEIAQABNQAECgkJGgAkABYWAA==.',
Mc='Mcbodhran:BAABNQAECn8hAAIBAAgKQgc91gAYAQABAAgKQgc91gAYAQAAAA==.Mcfeast:BAABNQAECn8hAAIhAAgKnBgvHABjAgAhAAgKnBgvHABjAgAAAA==.',
Me='Medra:BAABNQAECn8jAAMMAAgKfQZwqQATAQAMAAgKfQZwqQATAQALAAIKAwM0QQA6AAAAAA==.Melidoria:BAAANQAECgUICQABNQAECgoKTgAPAEQWAA==.Meowdi:BAAANQADCgcIIgAAAA==.',
Mi='Milou:BAABNQAECn8XAAMZAAgKYA/TEgB7AQASAAgKLw2U4ADHAQAZAAcKxw3TEgB7AQABNQAECgoKGwATALkVAA==.Minibone:BAABNQAECn8yAAIMAAoKoxpWMgBoAgAMAAoKoxpWMgBoAgAAAA==.Mixr:BAAANQADCgEIAQAAAA==.Mizery:BAAANQAECgUIBQAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Momobelfas:BAAANQAECgIIAQAAAA==.Moonwolf:BAAANQAECgcIEAAAAA==.',
Mu='Mummrak:BAAANQAECgcIDgAAAA==.',
My='Mysticwood:BAABNQAECn8vAAIEAAoKPB5BIQAFAwAEAAoKPB5BIQAFAwABNQAECgoKMgAMAKMaAA==.',
Na='Nadjá:BAABNQAECn8pAAIUAAoK1BRYHgAFAgAUAAoK1BRYHgAFAgAAAA==.Nanija:BAAANQADCggIKAAAAA==.Narushi:BAAANQAECgUIBQAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ne='Nezrin:BAABNQAECn8dAAMCAAoKEBKZXQD2AQACAAoKEBKZXQD2AQAEAAMKuwfkswCNAAAAAA==.',
Ni='Nightcat:BAABNQAECn9HAAIcAAoKdB6GBwBUAwAcAAoKdB6GBwBUAwAAAA==.Nitebäne:BAAANQAECgMIAQAAAA==.Nitestorm:BAABNQAECn8bAAIEAAoKJxoKSwBKAgAEAAoKJxoKSwBKAgAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAABNQAECn8WAAIDAAkKmhnAbwDGAQADAAkKmhnAbwDGAQAAAA==.',
Og='Ogwarshock:BAACNQAFFH8GAAMJAAMK9hmsBQCVAAAJAAIK4xysBQCVAAAIAAEKHRT1MwBLAAA1AAQKfzMABAkACgqtI4YNACACAAkABQoYJoYNACACAAgABwraHKOCAN8BAAcAAQp8H5skAEsAAAAA.',
Ol='Oliiver:BAABNQAECn9KAAIDAAoKXyAeIgCpAgADAAoKXyAeIgCpAgAAAA==.Olrun:BAAANQADCgEIAQAAAA==.',
Om='Omni:BAABNQAECn8bAAMTAAoKuRVaYQD9AQATAAoKuRVaYQD9AQAlAAEKfAYCLgApAAAAAA==.',
Or='Orbeez:BAAANQAECgIIAwAAAA==.Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Pallyofdoom:BAAANQAECgYIBAAAAA==.Panaceus:BAABNQAECn8/AAIQAAoKBR+oBwDJAgAQAAoKBR+oBwDJAgAAAA==.Patron:BAAANQADCgUIBQAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgYIEAARAAAAAA==.',
Ph='Phrequency:BAEANQAECgUICwAAAA==.',
Pl='Plazmaglaive:BAABNQAECn8eAAMVAAoK5xFqGADdAQAVAAkK5xFqGADdAQAUAAIKKAU9iQBTAAAAAA==.',
Po='Poalo:BAAANQADCggICAAAAA==.Poisonóus:BAABNQAECn8WAAIKAAgKDxoMRwDdAQAKAAgKDxoMRwDdAQAAAA==.Polywóg:BAAANQAECgIIAgAAAA==.Polyxo:BAABNQAECn8fAAIBAAgKnwsmsQBYAQABAAgKnwsmsQBYAQAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Pricker:BAAANQAECgUIBQABNQAECgoKMgAMAKMaAA==.Prépared:BAACNQAFFH8OAAIUAAQKIxJGEgDQAAAUAAQKIxJGEgDQAAA1AAQKfyUAAyQACQoHG5kOAEYBABQACAqHGiczABICACQABwoqFpkOAEYBAAAA.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgUICgAAAA==.',
Qu='Quixotic:BAAANQADCgQIBwAAAA==.',
Ra='Radkeem:BAABNQAECn8tAAIKAAoKVh/ADgCnAgAKAAoKVh/ADgCnAgAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Rakeem:BAAANQAECgUIBQABNQAECgoKLQAKAFYfAA==.Ravenstone:BAAANQADCgcIDAAAAA==.Raya:BAABNQAECn8aAAMgAAUK5x+wFQCOAQAgAAUK5x+wFQCOAQAWAAIKzxYBVwCOAAABNQAECgYIDQARAAAAAA==.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAABNQAECn80AAMmAAoKcxQCRABVAgAmAAoKcxQCRABVAgABAAQKKgpGPAHAAAAAAA==.',
Ro='Roejawb:BAABNQAECn8aAAIEAAcKoAYRsQAxAQAEAAcKoAYRsQAxAQAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQAECgUIBwAAAA==.',
Ry='Ryder:BAAANQAECgUIBQABNQADCgEIAQARAAAAAA==.',
Sa='Sableanne:BAAANQAECgQIBQAAAA==.Sacon:BAAANQADCgYIDQABNQAECgkJGgAkABYWAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAABNQAECn82AAMmAAoKSRvAMABMAgAmAAoKSRvAMABMAgANAAIKlRJrVwCCAAAAAA==.Salorll:BAAANQAECgYIDgAAAA==.Savia:BAAANQAECgQIBAAAAA==.',
Sc='Schmoogus:BAAANQADCgcJBQAAAA==.Schmoop:BAABNQAECn8mAAMhAAkKXCGtCQBFAwAhAAkKXCGtCQBFAwATAAUKShV3kgBfAQABNQAFFAcIFQAKAHweAA==.',
Se='Sellari:BAAANQAECggICAAAAA==.Senza:BAABNQAECn8ZAAIBAAcKwgZy+wDbAAABAAcKwgZy+wDbAAAAAA==.Senzyri:BAABNQAECn9BAAMDAAoK5w/4TgAbAgADAAoK5w/4TgAbAgAGAAIKiQUqUABZAAAAAA==.',
Sh='Shadyscales:BAACNQAFFH8IAAIXAAMKaQwEAgDjAAAXAAMKaQwEAgDjAAA1AAQKfy8AAhcACQprF3kGAGcCABcACQprF3kGAGcCAAAA.Shenro:BAABNQAECn8mAAIBAAoKQAuFngB7AQABAAoKQAuFngB7AQAAAA==.Shierà:BAAANQADCgcIBwABNQAECgYICwARAAAAAA==.',
Si='Simic:BAABNQAECn8WAAIfAAgKcwYSQAD/AAAfAAgKcwYSQAD/AAAAAA==.Sinnori:BAAANQABCggICwAAAA==.',
Sm='Smiddy:BAABNQAECn8dAAMKAAoKoBLROQAfAgAKAAoKoBLROQAfAgAaAAQKUhUJcwDUAAAAAA==.',
So='Souldrains:BAAANQADCggIIwAAAA==.Soyjak:BAABNQAECn8rAAMTAAoKohJHTADyAQATAAoKohJHTADyAQAhAAUKdgU1RgB/AAAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.Spinner:BAAANQADCgMIAwAAAA==.Spudpal:BAAANQADCggICAABNQAFFAYIBgATAEEZAA==.',
St='Stonymahoney:BAAANQAECgcIDAAAAA==.Strongarmkin:BAABNQAECn8fAAIMAAgK4xGzZgC3AQAMAAgK4xGzZgC3AQAAAA==.',
Su='Suraisu:BAABNQAECn9HAAMjAAoKFCOvAQAiAwAjAAoKFCOvAQAiAwAMAAIK8A10MAFzAAAAAA==.',
Sv='Sveela:BAABNQAECn9GAAIbAAoK6SRaAgCoAwAbAAoK6SRaAgCoAwAAAA==.Sveelaa:BAABNQAECn8yAAIDAAkKpCE2DwBpAwADAAkKpCE2DwBpAwABNQAECgoKRgAbAOkkAA==.Sveella:BAAANQAECgYIEAABNQAECgoKRgAbAOkkAA==.',
Sy='Syda:BAAANQAECgUIBwABNQAECggICQARAAAAAA==.Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAABNQAECn86AAMTAAoKUB1UMwCbAgATAAoKUB1UMwCbAgAhAAEKAADgdgAAAAAAAA==.',
Te='Temlock:BAABNQAECn8yAAIIAAoKWxQePAATAgAIAAoKWxQePAATAgAAAA==.Temtank:BAAANQAECgYICQABNQAECgoKMgAIAFsUAA==.',
Th='Thechiefster:BAAANQAECgQIBgAAAA==.Theidor:BAAANQADCgEIAQAAAA==.',
To='Toes:BAABNQAECn8ZAAMYAAkKphoHMwAbAgAYAAgKkBcHMwAbAgAFAAcKzxnVGwA/AQAAAA==.',
Tr='Traiya:BAAANQADCgEIAQAAAA==.Tralyn:BAAANQABCgQIBAAAAA==.Trukarak:BAABNQAECn8pAAIBAAgKqA7jsABYAQABAAgKqA7jsABYAQAAAA==.Trusturheals:BAAANQAECgcIEQAAAA==.',
['Tê']='Têss:BAAANQAECgQIBAAAAA==.',
Um='Umarg:BAAANQADCgMIAwAAAA==.',
Ur='Uraha:BAAANQAECgQIBQAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
['Và']='Vàlor:BAABNQAECn8lAAMKAAoKxQhkNwBZAQAKAAoKxQhkNwBZAQAfAAEKgAJEAQEWAAAAAA==.',
Wa='Wagons:BAAANQAECgcJBgAAAA==.Warfangg:BAAANQADCgMIAwAAAA==.',
Wi='Wildama:BAABNQAECn8pAAIcAAgKWRGqJQCnAQAcAAgKWRGqJQCnAQAAAA==.Windle:BAAANQADCggIGgAAAA==.Windseer:BAAANQADCgYICwABNQAFFAQICQABANYTAA==.',
Wu='Wumbo:BAAANQAECgUICAAAAA==.',
Xa='Xarríøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Xh='Xhadowz:BAABNQAECn8VAAInAAoKEwc/YQBKAQAnAAoKEwc/YQBKAQAAAA==.',
Xi='Xiao:BAABNQAECn9JAAMgAAoKrxTbDABHAgAgAAoKrxTbDABHAgAWAAcKSQh3SQDYAAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.Xingferat:BAAANQAECgQIBAAAAA==.',
['Xâ']='Xârriøn:BAAANQAECgQIBAABNQAFFAQIDQABAF0SAA==.',
Ya='Yahargul:BAABNQAECn8tAAIhAAcKWg7UOQBYAQAhAAcKWg7UOQBYAQAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCggIHQAAAA==.Zaradin:BAAANQAECgQIBAABNQAECgUIDgARAAAAAA==.Zariest:BAAANQADCgIIAgABNQAECgUIDgARAAAAAA==.',
Ze='Zeik:BAABNQAECn9LAAINAAoK7yG+BgDZAgANAAoK7yG+BgDZAgAAAA==.Zellspell:BAAANQADCggICQABNQAFFAUIEwAEAGcdAA==.Zerase:BAAANQADCgEIAQAAAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
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
