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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Druid-Feral','Mage-Frost','Mage-Arcane','Shaman-Elemental','Hunter-BeastMastery','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost','Priest-Shadow','Paladin-Protection','Warrior-Fury','Mage-Fire','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAUIFQABAP8RAA==.',
Ad='Admaris:BAACNQAFFH8JAAMCAAIKMhqcCgCbAAACAAIKMhqcCgCbAAADAAIKbRFkAwCaAAA1AAQKfzQAAwIACgp1IPwMAP8CAAIACgp1IPwMAP8CAAMABwqQIdIJAKMCAAAA.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFH8VAAMEAAgK/w9RAwDrAAAFAAUKwwuiJwBLAQAEAAMKOxRRAwDrAAA1AAQKfy8AAwUACgqSJDhLAOsCAAUACgqTIzhLAOsCAAQAAwrsI7gNAC4BAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Almight:BAAANQADCgUIBQAAAA==.Alnasham:BAACNQAFFH8TAAIGAAcKcxlwAgCsAQAGAAcKcxlwAgCsAQA1AAQKfzEAAgYACgoDIoUUAE4DAAYACgoDIoUUAE4DAAAA.Alnava:BAAANQAECgcIDwAAAA==.Alvoka:BAABNQAECn8VAAIFAAcKLRbv0QDiAQAFAAcKLRbv0QDiAQAAAA==.',
Am='Amarillos:BAABNQAECn8VAAIHAAkKSBQqYwBPAgAHAAkKSBQqYwBPAgAAAA==.Amarillys:BAABNQAECn8tAAIIAAoK4CDoBQCIAwAIAAoK4CDoBQCIAwAAAA==.Ammutseba:BAABNQAECn8oAAMJAAoK0hkPEQA7AgAJAAoKlxkPEQA7AgAKAAMK2hZFIgCwAAAAAA==.',
An='Anfall:BAACNQAFFH8QAAILAAUKJhYMAgDzAAALAAUKJhYMAgDzAAA1AAQKfzMAAgsACgqiIUsIAPUCAAsACgqiIUsIAPUCAAAA.Angermeier:BAABNQAECn82AAIMAAoKERWSLQAlAgAMAAoKERWSLQAlAgAAAA==.Angers:BAAANQAECgIIAgABNQAECgoKNgAMABEVAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggICgAAAA==.Anthos:BAAANQAECggIDQAAAA==.Antikreist:BAAANQADCgUIBQAAAA==.',
Ap='Aphotic:BAAANQAECgIIAQAAAA==.',
Ar='Arcady:BAAANQADCgYIBgAAAA==.Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgoKHwABAEsbAA==.Arthaniis:BAABNQAECn8YAAIGAAcKKCESSwBKAgAGAAcKKCESSwBKAgAAAA==.',
As='Asystoli:BAABNQAECn8dAAMFAAoK1RUYWACkAQAFAAkKxhYYWACkAQAEAAIKQw8UKwA9AAAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgMIDwAAAA==.',
Au='Audideath:BAAANQAECgQICQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFH8cAAIJAAcKLRyqAwBFAgAJAAcKLRyqAwBFAgA1AAQKfyMAAgkACgpCJfQFAJYDAAkACgpCJfQFAJYDAAAA.',
Ax='Ax:BAECNQAFFH8RAAMBAAcKdRasBwCeAQABAAYKdRasBwCeAQANAAEKAADZOQAfAAA1AAQKfywAAgEACgqJI5MMAFQCAAEACgqJI5MMAFQCAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgQICQAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECggIDQAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAYIEQAOAO8OAA==.',
Bd='Bdk:BAABNQAECn8UAAINAAkKuR2rGQDgAgANAAkKuR2rGQDgAgAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQAECgMIAwAAAA==.Beers:BAAANQAECggIBwAAAA==.Beledros:BAABNQAECn8cAAIPAAkKVBP4FQBWAgAPAAkKVBP4FQBWAgAAAA==.Beni:BAABNQAECn9UAAMQAAoKQiMDBABvAwAQAAoKQiMDBABvAwADAAUK+BTEHAA7AQAAAA==.Benson:BAABNQAECn8hAAIRAAkKoxwsCACuAgARAAkKoxwsCACuAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFH8gAAQSAAYK6iKNAgBqAgASAAYK6iKNAgBqAgATAAIKygE5EwB6AAAUAAEK/BkXCABiAAA1AAQKfyMABBIACQotJiYzALwCABIABwo1JiYzALwCABMABwq3GxUUAM8BABQAAQoAAFYpAEcAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brewtherguy:BAABNQAECn8iAAIRAAkKAB1oBwDGAgARAAkKAB1oBwDGAgAAAA==.Brother:BAAANQADCgIIAgAAAA==.Bruceshepard:BAAANQADCgQICQABNQAECgUICQAVAAAAAA==.Brutebuffalo:BAABNQAECn8lAAMWAAkKqh2uIwDYAgAWAAkKqh2uIwDYAgAGAAUKQBH/rQA3AQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECgkJJQAWAKodAA==.Brutetestify:BAAANQADCggICAABNQAECgkJJQAWAKodAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAABNQAECn8ZAAIIAAkKNhOgaQDhAQAIAAkKNhOgaQDhAQAAAA==.',
['Bâ']='Bâra:BAABNQAECn8eAAIBAAoKahqhJQCoAgABAAoKahqhJQCoAgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.Castro:BAAANQAECgIIAgAAAA==.',
Ce='Cedren:BAACNQAFFH8LAAIJAAUKDQ6gDgAfAQAJAAUKDQ6gDgAfAQA1AAQKfy8AAwkACgqCGzEjAIICAAkACgqFGjEjAIICABcACAotE7srAOQBAAAA.Ceewhya:BAAANQAECgIIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQAECgEIAwAAAA==.Chama:BAABNQAECn8aAAIXAAkKpxI0JAAmAgAXAAkKpxI0JAAmAgAAAA==.Cheapheal:BAABNQAECn9AAAMQAAoKFSDzBABSAwAQAAoKFSDzBABSAwAYAAEKAAAqfwAAAAAAAA==.Cheapsnipe:BAAANQAECggICgABNQAECgoKQAAQABUgAA==.Cheburashka:BAACNQAFFH8YAAIGAAcKxiKrBABIAgAGAAcKxiKrBABIAgA1AAQKfyEAAgYACgpbIakoAN8CAAYACgpbIakoAN8CAAAA.Chimerabob:BAAANQAECgMIBgAAAA==.Chopsuey:BAAANQAECggIAwAAAA==.Chunkymonkey:BAACNQAFFH8XAAIZAAcK0xa7BADwAQAZAAcK0xa7BADwAQA1AAQKfzkAAhkACgraIc8LABkDABkACgraIc8LABkDAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cl='Clappncheeks:BAABNQAECn8YAAIHAAoK3xg2KgA4AgAHAAoK3xg2KgA4AgAAAA==.Claudefrollo:BAABNQAECn8fAAIYAAkK2wyuJwBJAQAYAAkK2wyuJwBJAQAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECn8zAAIUAAoKtASmBgBWAQAUAAoKtASmBgBWAQAAAA==.Crimsonaxel:BAABNQAECn8pAAIGAAkK1BrVIgDoAQAGAAkK1BrVIgDoAQAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAVAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECn8vAAIaAAkKKR/OFACfAgAaAAkKKR/OFACfAgAAAA==.Dam:BAAANQADCgUIBQABNQAECgkJIAANABgXAA==.Dangerruss:BAAANQAECgUICQAAAA==.Darkspartan:BAAANQAECgUIBQAAAA==.Dashytash:BAABNQAECn8xAAIKAAoKuhzlAwAxAgAKAAoKuhzlAwAxAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.',
De='Deadcowmeat:BAAANQAECggICAAAAA==.Deathschosen:BAAANQADCgQIBAAAAA==.Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECn8uAAMTAAoKQh/MDAArAgASAAkKQh6tWwBEAgATAAcKfhzMDAArAgAAAA==.Denagorn:BAABNQAECn89AAIbAAoKKCQeEQCEAwAbAAoKKCQeEQCEAwABNQAFFAcIKwABAM4gAA==.Denaki:BAAANQADCggICgABNQAFFAcIKwABAM4gAA==.Denhunt:BAABNQAECn8dAAMHAAoKyx8HIgAPAwAHAAoKvh8HIgAPAwAcAAQKLRm4JwDFAAABNQAFFAcIKwABAM4gAA==.Dentsama:BAAANQADCgEIAQAAAA==.Deplete:BAAANQADCgIJAgABNQAECgoKNAAYALsaAA==.Deutzfr:BAABNQAECn8YAAIKAAkKfxwZBwCfAgAKAAkKfxwZBwCfAgAAAA==.Develop:BAAANQAECgMIBAAAAA==.Devos:BAABNQAECn8YAAMGAAcKgBMrcgDKAQAGAAcKgBMrcgDKAQAWAAQKRQ6X1gC6AAABNQAFFAUICQAGAIcEAA==.',
Di='Dizzleman:BAAANQAECggICgAAAA==.',
Do='Dominant:BAABNQAECn8nAAMFAAoKoB4LWQDOAgAFAAoKoB4LWQDOAgAEAAEKAAA5SgAxAAAAAA==.',
Dp='Dpssos:BAAANQAECggIDgAAAA==.',
Dr='Draco:BAAANQADCgcIBwAAAA==.Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAABNQAECn81AAIXAAoKzCAqCABQAwAXAAoKzCAqCABQAwAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgYICAAAAA==.Drygth:BAAANQADCgMIBgABNQAECgoKMQAdABEiAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFH8WAAINAAYKZh/8BABcAQANAAYKZh/8BABcAQA1AAQKfzgAAg0ACgp4JSACAFMDAA0ACgp4JSACAFMDAAAA.',
Du='Dushimaya:BAABNQAECn82AAIaAAoKtSOOBwCOAwAaAAoKtSOOBwCOAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgoKNQAXAMwgAA==.',
Ei='Eisador:BAABNQAECn8VAAIHAAcKWAtIqAC1AQAHAAcKWAtIqAC1AQAAAA==.',
El='Elsen:BAAANQAECgUIDQAAAA==.Elsha:BAABNQAECn8hAAIRAAkKtxtdCACmAgARAAkKtxtdCACmAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgUICgAAAA==.',
Ev='Evelira:BAABNQAFFH8TAAIIAAcKyBu+BwARAgAIAAcKyBu+BwARAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQADCgYIBgABNQAECgoKOgAeAEcSAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFH8FAAIaAAMKYAJkGwC+AAAaAAMKYAJkGwC+AAA1AAQKfyIAAhoACQr5Ff5GAEoCABoACQr5Ff5GAEoCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFH8XAAMHAAYK9BaNEABUAQAHAAQKjRmNEABUAQAcAAUKDQ8gDwBMAQA1AAQKfygAAwcACgp1HuxDAJ8CAAcACgp1HuxDAJ8CABwABgq+Ero/AFUBAAAA.Feythe:BAACNQAFFH8rAAINAAoK2g/2AABAAgANAAoK2g/2AABAAgA1AAQKfxgAAg0ACgreFxQ5ACICAA0ACgreFxQ5ACICAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECn8nAAIIAAcKLiNgHAB8AgAIAAcKLiNgHAB8AgAAAA==.Fleebly:BAABNQAECn8iAAIXAAoKiBnXGQCLAgAXAAoKiBnXGQCLAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECn8qAAIbAAoKjAwRXACkAQAbAAoKjAwRXACkAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECgoKSwAWADscAA==.',
Gi='Gilgamesh:BAAANQAECggIDQAAAA==.',
Go='Gorobob:BAAANQAECgIIBQAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAABNQAECn8aAAICAAkK4AcpQgAYAQACAAkK4AcpQgAYAQAAAA==.Grimreaper:BAABNQAECn82AAIfAAoKUBmSBQCPAgAfAAoKUBmSBQCPAgAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAABNQAECn8xAAMdAAoKESKbBQAtAwAdAAoKCyKbBQAtAwAOAAgKYxuJKgBBAgAAAA==.',
Ha='Haarp:BAAANQAECgYIDwAAAA==.Hakü:BAAANQAECgcIBwAAAA==.Hammered:BAABNQAECn8WAAIbAAgK2yN7KQBaAgAbAAgK2yN7KQBaAgAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAACNQAFFH8FAAIYAAIKWw3nIQCEAAAYAAIKWw3nIQCEAAA1AAQKfyQAAhgACQrRIZcZAPsCABgACQrRIZcZAPsCAAAA.Hemophilia:BAABNQAECn8tAAIBAAgKwBK3JQBKAQABAAgKwBK3JQBKAQAAAA==.Heydk:BAABNQAECn8YAAMgAAkKlRuZWgA/AQAgAAUKRhqZWgA/AQABAAYKHBtBfgAjAQAAAA==.Heydruid:BAAANQAECgcIDQABNQAECgkJGAAgAJUbAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAABNQAECn8eAAMhAAgKOQuuLwCmAQAhAAgKOQuuLwCmAQAIAAUK4AIwygDDAAABNQAECgoKLAAiAAsRAA==.Hottsauce:BAABNQAECn8cAAILAAkKQBwwDQCbAgALAAkKQBwwDQCbAgAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgIIBQAAAA==.Hushhides:BAABNQAECn8eAAMOAAkKMRLXCwDCAQAdAAkK8g2CGAAYAgAOAAgK0xDXCwDCAQAAAA==.Hushrage:BAAANQAECggICwABNQAECgkJHgAOADESAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAABNQAECn8YAAIDAAoK6iNvAQAkAwADAAoK6iNvAQAkAwABNQAECgoKMgAjAEAmAA==.Iblisshaytan:BAABNQAECn9BAAIJAAoKSh0gGwDBAgAJAAoKSh0gGwDBAgABNQAFFAQICAAdAHAGAA==.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAACNQAFFH8JAAIiAAUKQxazAwDdAAAiAAUKQxazAwDdAAA1AAQKfyEAAiIACQpgIqQFAKYCACIACQpgIqQFAKYCAAAA.',
Io='Ionissa:BAABNQAECn8rAAIHAAoKwxz8LwDdAgAHAAoKwxz8LwDdAgAAAA==.',
Ir='Ironbreaker:BAAANQAECgYICwAAAA==.',
Is='Ischia:BAACNQAFFH8JAAMIAAQK5wgCGwATAQAIAAQK5wgCGwATAQAhAAEKbAEPGwA0AAA1AAQKfz4AAwgACQr8GvU2AIwCAAgACQr8GvU2AIwCACEAAgrUE55pAFsAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFH8eAAIHAAcK2h5iAQCCAgAHAAcK2h5iAQCCAgA1AAQKfzQAAwcACgrIJOUTAE8DAAcACgrIJOUTAE8DABwAAQpkFhCGADgAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAACNQAFFH8TAAIZAAYKhBzZAQCsAQAZAAYKhBzZAQCsAQA1AAQKfzkAAhkACgreI0oGAGwDABkACgreI0oGAGwDAAAA.Jedikepjr:BAACNQAFFH8GAAIbAAMKZQmRGwDLAAAbAAMKZQmRGwDLAAA1AAQKfyMAAhsACgpdI2cRAO0CABsACgpdI2cRAO0CAAE1AAUUBggTABkAhBwA.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECn80AAQEAAkK5h/dBQCtAgAEAAkK2B/dBQCtAgAkAAUK/hkSBAB/AQAFAAUKkhXAHAFcAQAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgQIBAAAAA==.Joyful:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECn8gAAIYAAgKqh7oIgC4AgAYAAgKqh7oIgC4AgAAAA==.',
Ju='Jubei:BAABNQAECn8kAAIjAAgKVQ7uDQDUAQAjAAgKVQ7uDQDUAQAAAA==.',
Ka='Kagayaki:BAAANQAECgcICgAAAA==.Kalmya:BAABNQAECn8nAAMCAAgKpQ0YMACaAQACAAgKpQ0YMACaAQADAAEKAAAhRgAuAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgoKHwABAEsbAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgkJHQAIAPcbAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECn8tAAIWAAoKMSLiHQD1AgAWAAoKMSLiHQD1AgAAAA==.',
Ko='Korris:BAABNQAECn8tAAMHAAoKyiAaJABUAgAHAAoKyiAaJABUAgAcAAEK1wLwnAAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECn8pAAIJAAoKoB2ZHAC1AgAJAAoKoB2ZHAC1AgAAAA==.',
Kt='Ktang:BAAANQAFFAEIAQAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAACNQAFFH8FAAIQAAIKxwlnBQBtAAAQAAIKxwlnBQBtAAA1AAQKfzUAAhAACgpSFz8OAMoBABAACgpSFz8OAMoBAAAA.Lazyfrost:BAABNQAECn8qAAIFAAoKmA+dmwBJAgAFAAoKmA+dmwBJAgAAAA==.',
Le='Lethò:BAABNQAECn8vAAMaAAoKFyO0CACDAwAaAAoKFyO0CACDAwAbAAcKRxnkdQBnAQAAAA==.Lethô:BAAANQAECgYIDwAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAACNQAFFH8RAAMOAAYK7w5JBQDfAQAOAAYKIw1JBQDfAQAdAAYKTgiPCQAEAQA1AAQKfyQAAw4ACgoSIbwUANUCAA4ACArtHrwUANUCAB0ACgpJGpQaAEgCAAAA.Lilzarthe:BAAANQAECgQIDAAAAA==.',
Lo='Loerasdh:BAABNQAECn8eAAIJAAgK3CVICgBeAwAJAAgK3CVICgBeAwAAAA==.Loko:BAACNQAFFH8SAAIYAAYKTBVhCQDpAQAYAAYKTBVhCQDpAQA1AAQKfzYAAhgACgrmI14TACwDABgACgrmI14TACwDAAAA.Looio:BAAANQADCgIIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQADCggICAAAAA==.Luxxus:BAABNQAECn8dAAIIAAkK9xtcKwC7AgAIAAkK9xtcKwC7AgAAAA==.',
Ly='Lyesx:BAABNQAECn8kAAMHAAkKeiFWFwA9AwAHAAkKeiFWFwA9AwAcAAMKpxSTVwDHAAABNQAFFAYIEQAOAO8OAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAABNQAECn8oAAIIAAoKJyHZDgD+AgAIAAoKJyHZDgD+AgAAAA==.Malícíous:BAABNQAECn8wAAISAAkK/RL6QgCeAQASAAkK/RL6QgCeAQAAAA==.Mantakore:BAACNQAFFH8JAAIPAAQKZwQRCgDPAAAPAAQKZwQRCgDPAAA1AAQKfzAAAg8ACgqeFeEVAFcCAA8ACgqeFeEVAFcCAAAA.Marcdruid:BAAANQAECgUICQAAAA==.Maubles:BAAANQADCggICAABNQAFFAUIEwAiAMwNAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Menopaws:BAABNQAECn9DAAIQAAoKPCawAAB+AwAQAAoKPCawAAB+AwAAAA==.Merdoon:BAAANQADCgEIAQAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECn8eAAMWAAkKtiIODQBYAwAWAAkKtiIODQBYAwAGAAMKiBDZ7QC7AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFH8QAAIdAAUKAiNaAwAGAgAdAAUKAiNaAwAGAgA1AAQKfzoAAh0ACgoCJv0AAMsDAB0ACgoCJv0AAMsDAAAA.Milenko:BAABNQAECn83AAIJAAkKviBVDwBXAgAJAAkKviBVDwBXAgAAAA==.Milly:BAABNQAECn8WAAIbAAgKFhhgZACPAQAbAAgKFhhgZACPAQABNQAECgkJNwAJAL4gAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFH8YAAIMAAcKYhPgBQCBAQAMAAcKYhPgBQCBAQA1AAQKfzsAAgwACgqIHXM5AN8CAAwACgqIHXM5AN8CAAAA.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQABNQAECggIFgAbANsjAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgUIBgAAAA==.Morox:BAAANQAECggIEQABNQAFFAgIFQAEAP8PAA==.Mothman:BAAANQAECgUICgAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECn8tAAISAAgKoga6egACAQASAAgKoga6egACAQAAAA==.',
Mt='Mthafknfreez:BAABNQAECn8eAAIEAAoKwBVbBwB7AgAEAAoKwBVbBwB7AgABNQAFFAQICAAdAHAGAA==.',
Mu='Muffìns:BAAANQAECgUIBgAAAA==.Musashi:BAABNQAECn8jAAIIAAgKKBosQQBmAgAIAAgKKBosQQBmAgAAAA==.',
My='Mynuturchin:BAABNQAECn8WAAMNAAcK2BZeQwDuAQANAAcK2BZeQwDuAQAgAAEKJApUswAsAAAAAA==.',
Na='Nagy:BAAANQAECgMIAwAAAA==.',
Ni='Night:BAABNQAECn8rAAIFAAkKlRLhtwAUAgAFAAkKlRLhtwAUAgAAAA==.Nightsecho:BAAANQAECgIIAQAAAA==.Nightshris:BAAANQAECgUIBwAAAA==.',
Nn='Nnyx:BAAANQABCgIIAgAAAA==.',
No='Notmehssos:BAAANQAECggIDAAAAA==.Notthechosen:BAAANQAFFAEIAQAAAA==.',
Ny='Nymeriã:BAAANQAECgUICAAAAA==.Nyssaradora:BAAANQADCgIIAgAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAVAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAVAAAAAA==.Oknelim:BAAANQADCggICAABNQAECgkJNwAJAL4gAA==.',
Ol='Olympicjeid:BAABNQAECn8dAAMcAAgK5ROcLgDXAQAcAAgK5ROcLgDXAQAHAAEKCQY7VwE7AAABNQAFFAYIEwAZAIQcAA==.',
Op='Opz:BAABNQAECn8zAAMhAAoKmhf7GQB9AgAhAAoKmhf7GQB9AgAlAAYKmxhCBQA2AQAAAA==.',
Or='Orghujon:BAAANQABCgYICAAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQIDQAAAA==.Parts:BAAANQABCgEIAQABNQAECgoKJwAFAKAeAA==.',
Pe='Pedro:BAABNQAECn8VAAIbAAcKJQrruADoAAAbAAcKJQrruADoAAAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgYICQABNQAECggIFgAbANsjAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAACNQAFFH8ZAAIKAAcKPhZsAABrAQAKAAcKPhZsAABrAQA1AAQKfx4AAgoACgpwGo0HAIwCAAoACgpwGo0HAIwCAAAA.',
Po='Polskashaman:BAABNQAECn8iAAILAAgK7hHNFwDrAQALAAgK7hHNFwDrAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgYICAAVAAAAAA==.',
Pr='Prea:BAABNQAECn8YAAMWAAoK9BiDUQAgAgAWAAkKQBmDUQAgAgAGAAEKAAAQQgEtAAAAAA==.Premiumferal:BAABNQAECn8bAAMOAAkKECGiHQCTAgAOAAkKECGiHQCTAgAdAAUKxRj4MAA2AQAAAA==.Primecarry:BAACNQAFFH8WAAIaAAcKbxplBgAIAgAaAAcKbxplBgAIAgA1AAQKfyYAAhoACgqUIc8JAHoDABoACgqUIc8JAHoDAAAA.Prine:BAABNQAECn8jAAIMAAoK6xy+KwANAwAMAAoK6xy+KwANAwABNQAFFAcIFgAaAG8aAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgIIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECn89AAIMAAoKCyWpCQCnAwAMAAoKCyWpCQCnAwAAAA==.Rainyday:BAABNQAECn8UAAIWAAYK9ApktwD+AAAWAAYK9ApktwD+AAAAAA==.Raiva:BAABNQAECn8ZAAIXAAoKBw/kFQCTAQAXAAoKBw/kFQCTAQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAVAAAAAA==.Randomkiller:BAAANQADCgMIAwAAAA==.Rassputen:BAABNQAECn8uAAINAAoKuxS/RwDaAQANAAoKuxS/RwDaAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYICgAAAA==.Renais:BAAANQAECgQIBwAAAA==.Rex:BAABNQAECn8gAAINAAkKGBfyMABNAgANAAkKGBfyMABNAgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQABCgcIEwAAAA==.',
Rj='Rjtheamazin:BAAANQAECgEIAQAAAA==.',
Ro='Roguen:BAACNQAFFH8IAAIdAAQKcAaeCwACAQAdAAQKcAaeCwACAQA1AAQKf0AAAx0ACgoZGB8NAKMCAB0ACgoZGB8NAKMCAA4AAwqGCNKCAKkAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECn83AAIGAAoKMwuXMACXAQAGAAoKMwuXMACXAQAAAA==.',
['Rù']='Rùckús:BAABNQAECn8pAAIBAAgKQR/eLgB1AgABAAgKQR/eLgB1AgABNQAFFAEIAQAVAAAAAA==.',
Sa='Sacredmentos:BAABNQAECn8sAAMiAAoKCxFZJgCsAQAiAAoKCxFZJgCsAQAbAAYKagqLrAD+AAAAAA==.Salaen:BAAANQAECggIAQAAAA==.Sammybeans:BAAANQAFFAIIAwAAAA==.Sapito:BAAANQADCgYICgAAAA==.Saulotsalubr:BAAANQADCgQIBAAAAA==.',
Sc='Scarecrow:BAAANQAECgEIAQABNQAECgkJNwAJAL4gAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.Sevyns:BAAANQAECgIIAgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQAECgEIAQAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAACNQAFFH8GAAIHAAIKDhvPEwCnAAAHAAIKDhvPEwCnAAA1AAQKfyUAAgcACgozHrw1AMoCAAcACgozHrw1AMoCAAAA.Shatteredsky:BAABNQAECn8hAAMWAAkKER2AKwC1AgAWAAkKER2AKwC1AgAGAAEKqgOgRQErAAAAAA==.Shazik:BAABNQAECn9LAAIWAAoKOxypDgDiAgAWAAoKOxypDgDiAgAAAA==.Shazzik:BAAANQAECgYICgABNQAECgoKSwAWADscAA==.Sheroko:BAAANQAECgMIBQAAAA==.Sheñanigans:BAAANQAFFAEIAQAAAA==.Shilbalam:BAAANQAECgUIBQAAAA==.Shirohane:BAAANQAECgEIAQAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAABNQAECn8XAAMNAAkKaRy8KgBwAgANAAkKaRy8KgBwAgABAAEKuQiLcgArAAABNQAECgoKGQAXAAcPAA==.Sirjames:BAAANQAECgEIAQAAAA==.',
Sk='Skelix:BAACNQAFFH8oAAIWAAkKTx99AAADAwAWAAkKTx99AAADAwA1AAQKfy8AAxYACQpLJmMFAJwDABYACQpLJmMFAJwDAAYAAwpVF6baAN8AAAAA.Skunkpaw:BAAANQADCgUICwAAAA==.Skysong:BAACNQAFFH8VAAQeAAcKQB3EAABKAQAeAAYKTh/EAABKAQAmAAEKBxVKCABSAAAPAAEKeAUJGQA+AAA1AAQKfyUAAx4ACgpJIYYJANkCAB4ACgpJIYYJANkCAA8AAwp/BaZBAJQAAAAA.',
Sl='Slashedeye:BAABNQAECn9BAAIkAAkKFRSWAgASAgAkAAkKFRSWAgASAgAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowfox:BAAANQADCgIIAgAAAA==.Snowynn:BAABNQAECn8gAAMQAAkKfhaFFAAdAgAQAAkKfhaFFAAdAgADAAMKxggGMgCDAAAAAA==.Snubby:BAABNQAECn8cAAMSAAkKtCJFOwCiAgASAAcKmyFFOwCiAgATAAIKcyVYOgDYAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICQAAAA==.Spathi:BAAANQAFFAIIAwAAAA==.Spicymeatbal:BAAANQABCggIEQAAAA==.',
St='Stepz:BAAANQABCggIDAAAAA==.Strathz:BAABNQAECn8iAAMSAAkKfRw0NQC1AgASAAkKMxk0NQC1AgATAAQKahyvKAA0AQAAAA==.Stregobor:BAAANQAECgQIBAABNQAECgoKJwAFAKAeAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgMIAQAAAA==.Sunstrider:BAAANQADCgMIBgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAcIFwAZANMWAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAASAOoiAA==.Sylätis:BAAANQAECgMIAwABNQAFFAYIIAASAOoiAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAVAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMIDQABNQAFFAcIEwAIAMgbAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFH8cAAIPAAcKABccBAA8AgAPAAcKABccBAA8AgA1AAQKf0EAAg8ACgr9IyUBAMYDAA8ACgr9IyUBAMYDAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQAECgIIAQAAAA==.Texicola:BAABNQAECn8+AAIEAAoKCB/RAgAvAwAEAAoKCB/RAgAvAwAAAA==.',
Th='Thabdeady:BAAANQAECgUICQABNQAECgoKOgAeAEcSAA==.Thabk:BAABNQAECn86AAQeAAoKRxJ5BQD7AQAeAAoKIBJ5BQD7AQAmAAgKnwt9DgBfAQAPAAYKCQs9LQA7AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAABNQAECn8eAAMPAAgKPQj/JwB3AQAPAAgKPQj/JwB3AQAmAAYKagoBDwCMAAAAAA==.Thunderjeed:BAAANQAECgYICQABNQAFFAYIEwAZAIQcAA==.Thurmond:BAABNQAECn8fAAMBAAoKSxtnOwA0AgABAAoKpxZnOwA0AgANAAYKBBn9WQCLAQAAAA==.Thurmoons:BAAANQAECgYICgABNQAECgoKHwABAEsbAA==.Thurmund:BAAANQADCgYIBgABNQAECgoKHwABAEsbAA==.',
Ti='Tiamat:BAAANQADCggICAAAAA==.Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQAECgQIDgAAAA==.Toastz:BAABNQAECn87AAIHAAoKGR9uCwCCAwAHAAoKGR9uCwCCAwAAAA==.Toebeanz:BAAANQAECgQIDAAAAA==.Tokken:BAACNQAFFH8ZAAIMAAcKKBMcBwBPAgAMAAcKKBMcBwBPAgA1AAQKfzYAAgwACgpPHWc9ANMCAAwACgpPHWc9ANMCAAAA.',
Tr='Treebeast:BAABNQAECn8WAAMGAAkKER+5LQDGAgAGAAkKER+5LQDGAgAWAAEKnQE3KAElAAAAAA==.Troile:BAAANQAECgUIBgAAAA==.Trojen:BAACNQAFFH8IAAIbAAQKVg72GQDYAAAbAAQKVg72GQDYAAA1AAQKfyAAAxsACQp2GpaDACECABsACApyGpaDACECABoACAoYC3J8AKQBAAAA.Trolladin:BAAANQADCgYICgABNQADCggIJQAVAAAAAA==.',
Tw='Twig:BAABNQAECn8jAAMYAAkKkxcyLAB5AgAYAAkKkxcyLAB5AgACAAQKLA8INgDGAAAAAA==.',
Ty='Tyras:BAABNQAECn8WAAMZAAUKMxGGRQDvAAAZAAUKzQ2GRQDvAAARAAQKlg+BFACDAAAAAA==.',
Tz='Tzarina:BAAANQABCgYIBgAAAA==.',
['Tâ']='Tâz:BAABNQAECn8wAAMWAAoKix/KKgC4AgAWAAoKix/KKgC4AgAGAAEKAAD65AAAAAAAAA==.',
Ul='Ulanda:BAABNQAECn9EAAMDAAoKLxZpCADHAQAQAAkKNhQzEQBNAgADAAgKohNpCADHAQAAAA==.',
Um='Umasi:BAACNQAFFH8fAAIiAAcK8iVOAAABAwAiAAcK8iVOAAABAwA1AAQKfzQAAiIACgqdJrEBAL8DACIACgqdJrEBAL8DAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.Unus:BAAANQAECgEIAQABNQAECgoKJwAFAKAeAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAVAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Vainquish:BAAANQADCgEIAQAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAABNQAECn8UAAIFAAgKzAyB4ADIAQAFAAgKzAyB4ADIAQAAAA==.Vengened:BAABNQAECn8pAAIMAAkKtBbcVwCEAgAMAAkKtBbcVwCEAgABNQAFFAEIAQAVAAAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECn8yAAIjAAoKQCYiAACEAwAjAAoKQCYiAACEAwAAAA==.',
Vy='Vyisesham:BAABNQAECn8wAAMGAAkKxBpNQAB0AgAGAAgKiBlNQAB0AgAWAAgKehZVTgBcAQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAVAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECn8hAAMnAAoKrROWFAAyAgAnAAoKrROWFAAyAgAZAAEKHQM/dgAiAAAAAA==.Wez:BAAANQAECgcICwAAAA==.',
Wh='Whiskee:BAACNQAFFH8GAAIDAAIKfRW4AQChAAADAAIKfRW4AQChAAA1AAQKfycAAwMACgqaIgMFADUDAAMACQqQIQMFADUDABAABwrzIHARAEoCAAAA.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAABNQAECn8VAAIFAAoK9RshZQC0AgAFAAoK9RshZQC0AgAAAA==.Wyndibear:BAAANQABCgEIAQAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgUIBgAVAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQAECgMIBQABNQAECgoKJwAFAKAeAA==.Xenophontes:BAABNQAECn8ZAAMEAAoKuByjGgAeAQAFAAkKGhrKtQAYAgAEAAUKFR2jGgAeAQABNQAFFAcIEwAIAMgbAA==.Xeris:BAAANQADCgEIAQAAAA==.',
Xi='Xihuang:BAABNQAECn80AAIYAAoKKRdLEwAYAgAYAAoKKRdLEwAYAgABNQAFFAQICAAdAHAGAA==.Xiia:BAAANQAECgQIBAAAAA==.',
Xo='Xouu:BAAANQAFFAQIBAABNQAFFAgIBgAWADoRAA==.',
Xx='Xxuu:BAAANQAFFAgIAgABNQAFFAgIBgAWADoRAA==.Xxuusham:BAACNQAFFH8GAAIWAAYKOhFoBwDkAQAWAAYKOhFoBwDkAQA1AAQKf0cAAhYACgrTJSICAMYDABYACgrTJSICAMYDAAAA.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAWADoRAA==.Xxuutwo:BAAANQAECggIAQABNQAFFAgIBgAWADoRAA==.',
Ya='Yaoguai:BAABNQAECn80AAMYAAoKuxqXEgAhAgAYAAoKuxqXEgAhAgAQAAEKHwm6YAAzAAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAABNQAECn8WAAQUAAgKhwu/GgCuAAASAAcKzgjE4wABAQAUAAUKDA2/GgCuAAATAAEKFgQthAAmAAABNQAECgkJIQARALcbAA==.',
Za='Zakkha:BAAANQADCgMIAwABNQADCggIDQAVAAAAAA==.Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAAANQAECgcIDQAAAA==.',
Ze='Zephon:BAABNQAECn8aAAIHAAgK3g3zlQDcAQAHAAgK3g3zlQDcAQAAAA==.',
Zo='Zotiel:BAAANQAFFAQIBAABNQAFFAcIKwABAM4gAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAVAAAAAA==.',
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
